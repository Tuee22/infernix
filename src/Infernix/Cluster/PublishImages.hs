{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster.PublishImages
  ( HarborPublishOptions (..),
    PublishedImage,
    buildHarborOverridesValue,
    contentAddressTagFromInspectPayload,
    contentAddressTagFromManifestPayload,
    dockerHubMirrorRef,
    ensureLocalImageAvailable,
    defaultHarborPublishOptions,
    normalizeRepositoryPath,
    prioritizePublishableImages,
    publishChartImagesFile,
    skopeoTargetRefForHarborApiHost,
    writeHarborOverridesFile,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless)
import Data.Aeson
  ( FromJSON (parseJSON),
    Value,
    eitherDecode,
    object,
    withObject,
    (.!=),
    (.:),
    (.:?),
    (.=),
  )
import Data.Aeson.Key qualified as Key
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (find, intercalate, isSuffixOf, nub, partition)
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Yaml qualified as Yaml
import Infernix.Cluster.Discover (discoverChartImagesFile)
import Infernix.ProcessMonitor qualified as ProcessMonitor
import Network.HTTP.Client
  ( Manager,
    Request,
    Response,
    httpLbs,
    newManager,
    parseRequest,
    requestHeaders,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import System.Exit (ExitCode (ExitSuccess))
import System.Process (proc, readCreateProcessWithExitCode)

data HarborPublishOptions = HarborPublishOptions
  { harborHost :: String,
    harborClientHost :: String,
    harborApiHost :: String,
    harborProject :: String,
    harborUser :: String,
    harborPassword :: String,
    harborDockerCommand :: FilePath,
    harborSkopeoCommand :: FilePath,
    -- | Phase 3 Sprint 3.11 (2026-05-29): the substrate-matched
    -- container architecture (@\"amd64\"@ or @\"arm64\"@) the
    -- publication path pins on every @docker pull --platform
    -- linux\/<arch>@ and @skopeo copy --override-arch=<arch>@.
    -- 'Cluster.publishClusterImages' overrides from the resolved
    -- host-aware architecture selector; the default below stays at
    -- @\"amd64\"@ for backward compat with callers that have not
    -- yet been updated.
    harborTargetArchitecture :: String
  }
  deriving (Eq, Show)

type PublishedImage = (String, String)

type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)

data PushAttemptResult
  = PushSucceeded
  | PushFailed String

defaultHarborPublishOptions :: HarborPublishOptions
defaultHarborPublishOptions =
  HarborPublishOptions
    { harborHost = "localhost:30002",
      harborClientHost = "localhost:30002",
      harborApiHost = "localhost:30002",
      harborProject = "library",
      harborUser = "admin",
      harborPassword = "Harbor12345",
      harborDockerCommand = "docker",
      harborSkopeoCommand = "skopeo",
      harborTargetArchitecture = "amd64"
    }

harborPrefixes :: [String]
harborPrefixes = ["goharbor/", "docker.io/goharbor/", "quay.io/goharbor/"]

requiredRenderedChartImageAlternatives :: [[String]]
requiredRenderedChartImageAlternatives =
  [ ["infernix-linux-cpu:local", "infernix-linux-gpu:local"]
  ]

alwaysPublishedImages :: [String]
alwaysPublishedImages = []

postgresOperatorImage :: String
postgresOperatorImage = "docker.io/percona/percona-postgresql-operator:2.9.0"

postgresDatabaseImage :: String
postgresDatabaseImage = "docker.io/percona/percona-distribution-postgresql:18.3-1"

postgresPgBouncerImage :: String
postgresPgBouncerImage = "docker.io/percona/percona-pgbouncer:1.25.1-1"

postgresPgBackRestImage :: String
postgresPgBackRestImage = "docker.io/percona/percona-pgbackrest:2.58.0-1"

registryReadyAttempts :: Int
registryReadyAttempts = 24

loginAttempts :: Int
loginAttempts = 6

pullVerifyAttempts :: Int
pullVerifyAttempts = 6

pushAttempts :: Int
pushAttempts = 8

pushRetryBaseDelayMicros :: Int
pushRetryBaseDelayMicros = 5000000

pushRetryMaxDelayMicros :: Int
pushRetryMaxDelayMicros = 30000000

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
publishChartImagesFile ::
  HarborPublishOptions ->
  CommandMonitorFactory ->
  FilePath ->
  FilePath ->
  IO ()
publishChartImagesFile options commandMonitorFactory renderedChartPath outputPath = do
  manager <- newManager tlsManagerSettings
  images <- discoverChartImagesFile renderedChartPath
  let chartPublishableImages = filter (not . isHarborImage) images
      publishableImages = prioritizePublishableImages (nub (alwaysPublishedImages <> chartPublishableImages))
  mapM_ (requireOnePresent chartPublishableImages) requiredRenderedChartImageAlternatives
  loginHarborWithRetries manager options
  publishedImages <- mapM (publishImage manager options commandMonitorFactory) publishableImages
  writeHarborOverridesFile (Map.fromList publishedImages) outputPath
  where
    requireOnePresent imageSet imageRefs
      | any (`elem` imageSet) imageRefs = pure ()
      | otherwise =
          failWith
            ( "none of the required repo-owned images were present in the rendered chart: "
                <> show imageRefs
            )

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
-- type PublishedImage = (String, String)
publishImage ::
  Manager ->
  HarborPublishOptions ->
  CommandMonitorFactory ->
  String ->
  IO (String, PublishedImage)
publishImage manager options commandMonitorFactory sourceImage = do
  (maybeSourceDigest, fallbackSourceImage) <- ensureLocalImageAvailable options commandMonitorFactory sourceImage
  targetTag <-
    case maybeSourceDigest of
      Just sourceDigest -> pure (replaceColon sourceDigest)
      Nothing -> contentAddressTag options sourceImage
  let repositoryPath = normalizeRepositoryPath sourceImage
      publishedRepository = harborHost options <> "/" <> harborProject options <> "/" <> repositoryPath
      clientRepository = harborClientHost options <> "/" <> harborProject options <> "/" <> repositoryPath
  publishIfNeeded manager options commandMonitorFactory maybeSourceDigest fallbackSourceImage sourceImage clientRepository repositoryPath targetTag
  pure (sourceImage, (publishedRepository, targetTag))

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
ensureLocalImageAvailable :: HarborPublishOptions -> CommandMonitorFactory -> String -> IO (Maybe String, String)
ensureLocalImageAvailable options commandMonitorFactory imageRef = do
  maybePresent <- tryRunCommand (harborDockerCommand options) ["image", "inspect", imageRef] ""
  manifestSourceImage <-
    case maybePresent of
      Right _ -> pure imageRef
      Left _ ->
        -- Phase 7 Sprint 7.7 follow-on (May 24, 2026): on
        -- Docker 29.x + the containerd snapshotter image store,
        -- @docker pull <multi-arch-tag>@ reports success but the
        -- post-pull @docker image inspect@ still fails because the
        -- snapshotter stores the manifest list rather than a
        -- single-platform image. The supported flow for multi-arch
        -- upstream images is to skip the post-pull inspect gate (the
        -- pull itself succeeded; the inspect-failure surface is the
        -- supported signal to switch to the digest-pinned path) and
        -- jump straight to the @pinLocalImageToTargetArchitecture@ helper, which
        -- runs @docker manifest inspect@ + @docker pull <image>\@<amd64-digest>@
        -- + @docker tag@ so the subsequent @docker push@ sees a
        -- single-platform local image. For non-multi-arch images we
        -- keep the strict requireLocalImagePresent gate because their
        -- pull-then-inspect cycle is the supported readiness signal.
        if isUpstreamMultiArchImage imageRef
          then pullUpstreamMultiArchImage options commandMonitorFactory imageRef
          else do
            pullImageWithFallback options commandMonitorFactory imageRef
            pure imageRef
  -- Phase 7 Sprint 7.7 follow-on: with Docker 29.x + the containerd
  -- snapshotter image store, @docker push@ of a multi-arch upstream
  -- image fails with "image with reference X was found but does not
  -- provide any platform" because the local tag points at the
  -- manifest list, not the platform-specific sub-image. Even
  -- @--platform linux/amd64@ on push reports "does not provide the
  -- specified platform" because the local list-entry isn't a
  -- standalone image tag. The supported workaround is to extract the
  -- linux/amd64 digest from the upstream manifest list, pull that
  -- specific digest, and re-tag it under the original tag name so the
  -- subsequent @docker push@ sees a single-platform local image.
  if isUpstreamMultiArchImage imageRef
    then do
      maybePinnedSource <- pinLocalImageToTargetArchitecture options commandMonitorFactory imageRef manifestSourceImage
      case maybePinnedSource of
        Just (amd64Digest, digestSourceImage) -> pure (Just amd64Digest, digestSourceImage)
        Nothing -> pure (Nothing, manifestSourceImage)
    else pure (Nothing, imageRef)

-- | Pull a multi-arch upstream image without requiring the post-pull
-- inspect to succeed. The supported invariant is that @docker pull@
-- itself returns success, either from the original reference or its
-- Docker Hub mirror. The returned reference is the manifest source that
-- downstream code ('pinLocalImageToTargetArchitecture' +
-- 'pushUpstreamMultiArchViaImagetools') should keep using so a Docker
-- Hub rate limit does not force a later registry roundtrip.
-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
pullUpstreamMultiArchImage :: HarborPublishOptions -> CommandMonitorFactory -> String -> IO String
pullUpstreamMultiArchImage options commandMonitorFactory imageRef = do
  pullMonitor <- commandMonitorFactory ("docker pull " <> imageRef)
  pullResult <- tryRunCommandMaybeMonitored (harborDockerCommand options) ["pull", imageRef] "" pullMonitor
  case pullResult of
    Right _ -> pure imageRef
    Left pullFailure ->
      case dockerHubMirrorRef imageRef of
        Nothing ->
          failWith ("docker pull failed for " <> imageRef <> "\n" <> pullFailure)
        Just mirrorRef -> do
          mirrorMonitor <- commandMonitorFactory ("docker pull " <> mirrorRef)
          mirrorPullResult <- tryRunCommandMaybeMonitored (harborDockerCommand options) ["pull", mirrorRef] "" mirrorMonitor
          case mirrorPullResult of
            Right _ -> pure mirrorRef
            Left mirrorFailure ->
              failWith
                ( "docker pull failed for "
                    <> imageRef
                    <> "\n"
                    <> pullFailure
                    <> "\nmirror fallback failed for "
                    <> mirrorRef
                    <> "\n"
                    <> mirrorFailure
                )

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
pullImageWithFallback :: HarborPublishOptions -> CommandMonitorFactory -> String -> IO ()
pullImageWithFallback options commandMonitorFactory imageRef = do
  initialMonitor <- commandMonitorFactory ("docker pull " <> imageRef)
  pullResult <- tryRunCommandMaybeMonitored (harborDockerCommand options) ["pull", imageRef] "" initialMonitor
  case pullResult of
    Right _ -> requireLocalImagePresent options imageRef ("docker pull completed for " <> imageRef <> ", but the image is still not inspectable locally")
    Left pullFailure ->
      case dockerHubMirrorRef imageRef of
        Nothing ->
          failWith ("docker pull failed for " <> imageRef <> "\n" <> pullFailure)
        Just mirrorRef -> do
          mirrorMonitor <- commandMonitorFactory ("docker pull " <> mirrorRef)
          mirrorPullResult <- tryRunCommandMaybeMonitored (harborDockerCommand options) ["pull", mirrorRef] "" mirrorMonitor
          case mirrorPullResult of
            Right _ -> do
              runCommand (harborDockerCommand options) ["tag", mirrorRef, imageRef] ""
              requireLocalImagePresent options imageRef ("mirror pull completed for " <> mirrorRef <> ", but " <> imageRef <> " is still not inspectable locally after tagging")
            Left mirrorFailure ->
              failWith
                ( "docker pull failed for "
                    <> imageRef
                    <> "\n"
                    <> pullFailure
                    <> "\nmirror fallback failed for "
                    <> mirrorRef
                    <> "\n"
                    <> mirrorFailure
                )

requireLocalImagePresent :: HarborPublishOptions -> String -> String -> IO ()
requireLocalImagePresent options imageRef message = do
  imagePresent <- tryRunCommand (harborDockerCommand options) ["image", "inspect", imageRef] ""
  case imagePresent of
    Right _ -> pure ()
    Left inspectFailure -> failWith (message <> "\n" <> inspectFailure)

dockerHubMirrorRef :: String -> Maybe String
dockerHubMirrorRef imageRef =
  ("mirror.gcr.io/" <>) <$> normalizedDockerHubPath imageRef
  where
    normalizedDockerHubPath rawImage =
      case stripRegistryPrefix rawImage of
        Just pathValue -> Just (ensureLibraryPrefix pathValue)
        Nothing ->
          if usesImplicitDockerHub rawImage
            then Just (ensureLibraryPrefix rawImage)
            else Nothing

    stripRegistryPrefix rawImage =
      case break (== '/') rawImage of
        ("docker.io", '/' : pathValue) -> Just pathValue
        _ -> Nothing

    usesImplicitDockerHub rawImage =
      case break (== '/') rawImage of
        (_, []) -> True
        (registryOrNamespace, _ : _) -> not (hasExplicitRegistryComponent registryOrNamespace)

    hasExplicitRegistryComponent component =
      '.' `elem` component || ':' `elem` component || component == "localhost"

    ensureLibraryPrefix pathValue =
      case break (== '/') pathValue of
        (_, []) -> "library/" <> pathValue
        _ -> pathValue

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
publishIfNeeded ::
  Manager ->
  HarborPublishOptions ->
  CommandMonitorFactory ->
  Maybe String ->
  String ->
  String ->
  String ->
  String ->
  String ->
  IO ()
publishIfNeeded manager options commandMonitorFactory maybeSourceDigest fallbackSourceImage sourceImage clientRepository repositoryPath targetTag = do
  let targetRef = clientRepository <> ":" <> targetTag
  tagPresent <- harborTagExists manager options repositoryPath targetTag
  if tagPresent
    then verifyRegistryPull manager options commandMonitorFactory targetRef
    else do
      pushImageWithRetries manager options commandMonitorFactory maybeSourceDigest fallbackSourceImage sourceImage targetRef
      verifyRegistryPull manager options commandMonitorFactory targetRef

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
pushImageWithRetries ::
  Manager ->
  HarborPublishOptions ->
  CommandMonitorFactory ->
  Maybe String ->
  String ->
  String ->
  String ->
  IO ()
pushImageWithRetries manager options commandMonitorFactory maybeSourceDigest fallbackSourceImage sourceImage targetRef = go pushAttempts ""
  where
    (targetRepository, _, targetTag) = breakRepositoryAndTag targetRef
    repositoryPath = normalizeRepositoryPath targetRepository

    go remainingAttempts lastFailure
      | remainingAttempts <= 0 =
          failWith ("docker push failed for " <> targetRef <> "\n" <> lastFailure)
      | otherwise = do
          waitForRegistry manager options
          attemptResult <- pushImageOnce
          case attemptResult of
            PushSucceeded -> pure ()
            PushFailed failureMessage ->
              retryPush remainingAttempts failureMessage

    pushImageOnce = do
      retagResult <- tryRunCommand (harborDockerCommand options) ["tag", sourceImage, targetRef] ""
      case retagResult of
        Left tagFailure
          | isUpstreamMultiArchImage sourceImage -> do
              imagetoolsResult <-
                pushUpstreamMultiArchViaImagetools
                  options
                  commandMonitorFactory
                  maybeSourceDigest
                  fallbackSourceImage
                  targetRef
              case imagetoolsResult of
                Right _ -> pure PushSucceeded
                Left imagetoolsFailure ->
                  recoverCompletedPush
                    ( "docker tag failed for "
                        <> sourceImage
                        <> " as "
                        <> targetRef
                        <> "\n"
                        <> tagFailure
                        <> "\nfallback multi-arch copy failed:\n"
                        <> imagetoolsFailure
                    )
        Left tagFailure ->
          pure
            ( PushFailed
                ("docker tag failed for " <> sourceImage <> " as " <> targetRef <> "\n" <> tagFailure)
            )
        Right _ -> do
          -- Phase 7 Sprint 7.7 follow-on (May 24, 2026): on Docker
          -- 29.x + containerd snapshotter, @docker push@ of a tag
          -- derived from an upstream multi-arch image (e.g.
          -- @envoyproxy/gateway:v1.7.2@) re-emits the manifest list
          -- even after a digest pin to @linux/amd64@. Harbor then
          -- rejects the push with @NotFound: content digest …: not
          -- found@ because the other platform manifests are not in
          -- the local store. The supported fallback is to copy the
          -- amd64 digest straight from the upstream registry into
          -- Harbor via @skopeo copy@, which bypasses the local
          -- docker store entirely and operates on the registry API. See
          -- 'pushUpstreamMultiArchViaImagetools' for the helper.
          monitor <- commandMonitorFactory ("docker push " <> targetRef)
          pushResult <- tryRunCommandMaybeMonitored (harborDockerCommand options) ["push", targetRef] "" monitor
          case pushResult of
            Right _ -> pure PushSucceeded
            Left failureMessage
              | isUpstreamMultiArchImage sourceImage -> do
                  imagetoolsResult <-
                    pushUpstreamMultiArchViaImagetools
                      options
                      commandMonitorFactory
                      maybeSourceDigest
                      fallbackSourceImage
                      targetRef
                  case imagetoolsResult of
                    Right _ -> pure PushSucceeded
                    Left imagetoolsFailure -> recoverCompletedPush (failureMessage <> "\nfallback multi-arch copy failed:\n" <> imagetoolsFailure)
              | otherwise -> recoverCompletedPush failureMessage

    recoverCompletedPush failureMessage = do
      tagPresent <- harborTagExists manager options repositoryPath targetTag
      registryPullable <- registryPullSucceeds options targetRef
      pure $
        if tagPresent || registryPullable
          then PushSucceeded
          else PushFailed failureMessage

    retryPush remainingAttempts failureMessage =
      if remainingAttempts > 1
        then do
          let attemptsUsed = pushAttempts - remainingAttempts + 1
          putStrLn
            ( "publish-chart-images: retrying docker push for "
                <> targetRef
                <> " after attempt "
                <> show attemptsUsed
                <> "/"
                <> show pushAttempts
                <> " failed"
            )
          ready <- registryReady manager (harborApiHost options)
          unless ready (waitForRegistry manager options)
          threadDelay (pushRetryDelayMicros attemptsUsed)
          go (remainingAttempts - 1) failureMessage
        else go 0 failureMessage

prioritizePublishableImages :: [String] -> [String]
prioritizePublishableImages imageRefs =
  let repoOwnedImages = concat requiredRenderedChartImageAlternatives
      isRepoOwned imageRef = imageRef `elem` repoOwnedImages || "infernix-engine-" `List.isPrefixOf` imageRef
      (localImages, otherImages) = partition isRepoOwned imageRefs
   in localImages <> otherImages

pushRetryDelayMicros :: Int -> Int
pushRetryDelayMicros attemptsUsed =
  min pushRetryMaxDelayMicros (attemptsUsed * pushRetryBaseDelayMicros)

registryPullSucceeds :: HarborPublishOptions -> String -> IO Bool
registryPullSucceeds options imageRef =
  either (const False) (const True) <$> tryRunCommand (harborDockerCommand options) ["pull", imageRef] ""

-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
verifyRegistryPull ::
  Manager ->
  HarborPublishOptions ->
  CommandMonitorFactory ->
  String ->
  IO ()
verifyRegistryPull manager options commandMonitorFactory targetRef = do
  waitForRegistry manager options
  go pullVerifyAttempts ""
  where
    go remainingAttempts lastFailure
      | remainingAttempts <= 0 =
          failWith ("docker pull verification failed for " <> targetRef <> "\n" <> lastFailure)
      | otherwise = do
          monitor <- commandMonitorFactory ("docker pull verify " <> targetRef)
          result <- tryRunCommandMaybeMonitored (harborDockerCommand options) ["pull", targetRef] "" monitor
          case result of
            Right _ -> pure ()
            Left failureMessage ->
              if remainingAttempts > 1
                then do
                  ready <- registryReady manager (harborApiHost options)
                  if ready
                    then threadDelay ((pullVerifyAttempts - remainingAttempts + 1) * 2000000)
                    else waitForRegistry manager options
                  go (remainingAttempts - 1) failureMessage
                else go 0 failureMessage

loginHarborWithRetries :: Manager -> HarborPublishOptions -> IO ()
loginHarborWithRetries manager options = do
  waitForRegistry manager options
  go loginAttempts ""
  where
    go remainingAttempts lastFailure
      | remainingAttempts <= 0 =
          failWith ("docker login failed for " <> harborClientHost options <> "\n" <> lastFailure)
      | otherwise = do
          result <-
            tryRunCommand
              (harborDockerCommand options)
              ["login", harborClientHost options, "--username", harborUser options, "--password-stdin"]
              (harborPassword options <> "\n")
          case result of
            Right _ -> pure ()
            Left failureMessage ->
              if remainingAttempts > 1
                then do
                  ready <- registryReady manager (harborApiHost options)
                  if ready
                    then threadDelay ((loginAttempts - remainingAttempts + 1) * 2000000)
                    else waitForRegistry manager options
                  go (remainingAttempts - 1) failureMessage
                else go 0 failureMessage

waitForRegistry :: Manager -> HarborPublishOptions -> IO ()
waitForRegistry manager options = go registryReadyAttempts
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          failWith ("Harbor registry at " <> harborApiHost options <> " never became ready for docker login")
      | otherwise = do
          ready <- registryReady manager (harborApiHost options)
          if ready
            then pure ()
            else do
              let attemptsUsed = registryReadyAttempts - remainingAttempts + 1
              threadDelay (min attemptsUsed 5 * 1000000)
              go (remainingAttempts - 1)

registryReady :: Manager -> String -> IO Bool
registryReady manager apiHost = do
  request <- parseRequest ("http://" <> apiHost <> "/v2/")
  responseResult <- try (httpLbs request manager) :: IO (Either SomeException (Response LazyChar8.ByteString))
  case responseResult of
    Left _ -> pure False
    Right response -> pure (statusCode (responseStatus response) `elem` [200, 401, 403])

harborTagExists :: Manager -> HarborPublishOptions -> String -> String -> IO Bool
harborTagExists manager options repositoryPath targetTag = do
  let requestUrl = harborRepositoryUrl (harborApiHost options) (harborProject options) repositoryPath
  request <- authenticatedHarborRequest options requestUrl
  responseResult <- try (httpLbs request manager) :: IO (Either SomeException (Response LazyChar8.ByteString))
  case responseResult of
    Left _ -> pure False
    Right response
      | statusCode (responseStatus response) == 404 -> pure False
      | statusCode (responseStatus response) < 200 || statusCode (responseStatus response) >= 300 -> pure False
      | otherwise ->
          case eitherDecode (responseBody response) of
            Right artifacts ->
              pure
                ( any
                    ( any (\tagValue -> harborTagName tagValue == targetTag)
                        . harborArtifactTags
                    )
                    (artifacts :: [HarborArtifact])
                )
            Left _ -> pure False

authenticatedHarborRequest :: HarborPublishOptions -> String -> IO Request
authenticatedHarborRequest options requestUrl = do
  request <- parseRequest requestUrl
  pure
    request
      { requestHeaders =
          ("Authorization", harborAuthorizationHeader options)
            : requestHeaders request
      }

harborAuthorizationHeader :: HarborPublishOptions -> ByteString8.ByteString
harborAuthorizationHeader options =
  "Basic "
    <> Base64.encode
      (ByteString8.pack (harborUser options <> ":" <> harborPassword options))

harborRepositoryUrl :: String -> String -> String -> String
harborRepositoryUrl apiHost project repositoryPath =
  "http://"
    <> apiHost
    <> "/api/v2.0/projects/"
    <> urlEncodeString project
    <> "/repositories/"
    <> urlEncodeString (urlEncodeString repositoryPath)
    <> "/artifacts?page_size=100&with_tag=true"

contentAddressTag :: HarborPublishOptions -> String -> IO String
contentAddressTag options imageRef = do
  inspectResult <- tryRunCommand (harborDockerCommand options) ["image", "inspect", imageRef] ""
  case inspectResult of
    Right payload ->
      case contentAddressTagFromInspectPayload payload of
        Right tagValue -> pure tagValue
        Left err -> failWith err
    Left inspectFailure
      | isUpstreamMultiArchImage imageRef -> do
          manifestResult <- tryRunCommand (harborDockerCommand options) ["manifest", "inspect", imageRef] ""
          case manifestResult of
            Right manifestPayload ->
              case contentAddressTagFromManifestPayload (harborTargetArchitecture options) manifestPayload of
                Right tagValue -> pure tagValue
                Left err -> failWith (err <> "\n" <> inspectFailure)
            Left manifestFailure ->
              failWith
                ( "command failed: "
                    <> harborDockerCommand options
                    <> " image inspect "
                    <> imageRef
                    <> "\n"
                    <> inspectFailure
                    <> "\nmanifest fallback failed:\n"
                    <> manifestFailure
                )
    Left inspectFailure ->
      failWith
        ( "command failed: "
            <> harborDockerCommand options
            <> " image inspect "
            <> imageRef
            <> "\n"
            <> inspectFailure
        )

contentAddressTagFromInspectPayload :: String -> Either String String
contentAddressTagFromInspectPayload payload = do
  records <- eitherDecode (LazyChar8.pack payload) :: Either String [DockerImageInspect]
  case records of
    firstRecord : _ ->
      case repoDigestTag firstRecord of
        Just digestTag -> Right digestTag
        Nothing ->
          case dockerImageId firstRecord of
            Just imageIdValue -> Right (replaceColon imageIdValue)
            Nothing -> Left "image inspect did not include an image id"
    [] -> Left "image inspect returned no payload"

repoDigestTag :: DockerImageInspect -> Maybe String
repoDigestTag inspection =
  find
    (not . null)
    [ replaceColon digestValue
    | repoDigestValue <- dockerRepoDigests inspection,
      Just (_, digestValue) <- [breakOn '@' repoDigestValue]
    ]

contentAddressTagFromManifestPayload :: String -> String -> Either String String
contentAddressTagFromManifestPayload targetArchitecture manifestPayload =
  case extractDigestForArchitecture targetArchitecture manifestPayload of
    Just digestValue -> Right (replaceColon digestValue)
    Nothing -> Left ("manifest inspect did not include a linux/" <> targetArchitecture <> " digest")

-- | Pull the substrate-matched sub-image (e.g. @linux/arm64@ on
-- Apple Silicon, @linux/amd64@ on Linux substrates) from a multi-arch
-- upstream and re-tag it under the original tag name so subsequent
-- @docker push@ works against a single-platform local image. See
-- 'ensureLocalImageAvailable' for the supported context.
--
-- Phase 7 Sprint 7.7 follow-on (May 24, 2026): on Docker 29.x + the
-- containerd snapshotter, the @docker tag <digest> <tag>@ step alone
-- is not sufficient because the named tag can still resolve to the
-- previously-pulled multi-arch manifest list under the same tag. The
-- supported workaround removes the local tag with @docker image rm@
-- before the pin so the subsequent @docker tag@ writes a fresh,
-- single-platform reference. The @rm@ is best-effort: an unknown-tag
-- failure is benign (the tag wasn't present yet).
--
-- Phase 3 Sprint 3.11 (2026-05-29): the platform pin is now derived
-- from @options.harborTargetArchitecture@ instead of hardcoded amd64,
-- so Apple Silicon substrates publish arm64 sub-images natively
-- without Rosetta emulation.
-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
pinLocalImageToTargetArchitecture :: HarborPublishOptions -> CommandMonitorFactory -> String -> String -> IO (Maybe (String, String))
pinLocalImageToTargetArchitecture options commandMonitorFactory imageRef preferredManifestSource =
  tryManifestSources manifestSources
  where
    targetArchitecture = harborTargetArchitecture options
    platformFlagValue = "linux/" <> targetArchitecture

    manifestSources =
      nub
        ( preferredManifestSource
            : case dockerHubMirrorRef imageRef of
              Just mirrorRef -> [mirrorRef]
              Nothing -> []
        )

    tryManifestSources [] = pure Nothing
    tryManifestSources (manifestSource : rest) = do
      inspectResult <- tryRunCommand (harborDockerCommand options) ["manifest", "inspect", manifestSource] ""
      case inspectResult of
        Left _ -> tryManifestSources rest
        Right manifestJson ->
          case extractDigestForArchitecture targetArchitecture manifestJson of
            Nothing -> tryManifestSources rest
            Just archDigest -> do
              let imageWithoutTag = takeBefore ':' manifestSource
                  imageByDigest = imageWithoutTag <> "@" <> archDigest
              digestMonitor <- commandMonitorFactory ("docker pull --platform " <> platformFlagValue <> " " <> imageByDigest)
              digestPullResult <-
                tryRunCommandMaybeMonitored
                  (harborDockerCommand options)
                  ["pull", "--platform", platformFlagValue, imageByDigest]
                  ""
                  digestMonitor
              case digestPullResult of
                Left _ -> tryManifestSources rest
                Right _ -> do
                  -- Best-effort untag so 'docker tag' writes a fresh
                  -- single-platform reference rather than overlaying the
                  -- multi-arch manifest list still attached to the tag.
                  -- The @rm@ may fail benignly (the tag wasn't present).
                  _ <- tryRunCommand (harborDockerCommand options) ["image", "rm", "--no-prune", imageRef] ""
                  -- @docker tag <image>\@<digest> <image>:<tag>@ fails
                  -- under the Docker 29.x containerd snapshotter
                  -- because the digest reference is not directly
                  -- tag-able even after @docker pull@ succeeds. The
                  -- supported workaround is to look up the image ID via
                  -- @docker inspect <image>\@<digest> --format '{{.Id}}'@
                  -- (which DOES work after the digest pull) and tag the
                  -- resolved ID under the original ref.
                  idResult <- tryRunCommand (harborDockerCommand options) ["inspect", imageByDigest, "--format", "{{.Id}}"] ""
                  case idResult of
                    Right rawId -> do
                      let imageId = trimNewlines rawId
                      tagResult <- tryRunCommand (harborDockerCommand options) ["tag", imageId, imageRef] ""
                      case tagResult of
                        Right _ -> pure ()
                        Left _ -> recoverOriginalTag options commandMonitorFactory imageRef manifestSource
                    Left _ -> recoverOriginalTag options commandMonitorFactory imageRef manifestSource
                  pure (Just (archDigest, manifestSource))

-- | Phase 3 Sprint 3.11 (2026-05-29): parse the JSON output of
-- @docker manifest inspect@ and return the digest of the entry whose
-- architecture matches the supplied @targetArchitecture@ (typically
-- @\"arm64\"@ on Apple Silicon or @\"amd64\"@ on Linux substrates).
-- Uses the Aeson FromJSON machinery to decode just the shape we need
-- without enumerating the full manifest-list schema.
extractDigestForArchitecture :: String -> String -> Maybe String
extractDigestForArchitecture targetArchitecture manifestJson =
  case eitherDecode (LazyChar8.pack manifestJson) :: Either String ManifestList of
    Left _ -> Nothing
    Right ml -> Text.unpack <$> findArchDigest (manifestListEntries ml)
  where
    targetArchText = Text.pack targetArchitecture
    findArchDigest [] = Nothing
    findArchDigest (entry : rest)
      | manifestEntryArchitecture entry == targetArchText
          && manifestEntryOs entry == "linux" =
          Just (manifestEntryDigest entry)
      | otherwise = findArchDigest rest

newtype ManifestList = ManifestList
  { manifestListEntries :: [ManifestEntry]
  }
  deriving (Eq, Show)

instance FromJSON ManifestList where
  parseJSON = withObject "ManifestList" $ \value ->
    ManifestList <$> value .: "manifests"

data ManifestEntry = ManifestEntry
  { manifestEntryDigest :: Text.Text,
    manifestEntryArchitecture :: Text.Text,
    manifestEntryOs :: Text.Text
  }
  deriving (Eq, Show)

instance FromJSON ManifestEntry where
  parseJSON = withObject "ManifestEntry" $ \value -> do
    digestField <- value .: "digest"
    platformField <- value .: "platform"
    architectureField <- platformField .: "architecture"
    osField <- platformField .: "os"
    pure
      ManifestEntry
        { manifestEntryDigest = digestField,
          manifestEntryArchitecture = architectureField,
          manifestEntryOs = osField
        }

-- | Push the @linux/amd64@ manifest of an upstream multi-arch image
-- straight into Harbor via @skopeo copy@. The copy path operates on
-- the registry API and accepts a digest-pinned source, so the Docker
-- 29.x + containerd snapshotter pitfalls that block @docker push@ for
-- multi-arch tags do not apply. The helper reuses an earlier manifest
-- digest when available; otherwise it extracts the @linux/amd64@
-- digest from the upstream manifest list, then copies
-- @docker://SRC\@DIGEST@ to @docker://DEST@.
-- Returns 'Left' with the captured stderr on any step that fails.
-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
pushUpstreamMultiArchViaImagetools ::
  HarborPublishOptions ->
  CommandMonitorFactory ->
  Maybe String ->
  String ->
  String ->
  IO (Either String ())
pushUpstreamMultiArchViaImagetools options commandMonitorFactory maybeKnownSourceDigest sourceImage targetRef =
  case maybeKnownSourceDigest of
    Just archDigest -> copyDigest archDigest
    Nothing -> do
      manifestResult <- tryRunCommand (harborDockerCommand options) ["manifest", "inspect", sourceImage] ""
      case manifestResult of
        Left manifestFailure ->
          pure (Left ("docker manifest inspect failed for " <> sourceImage <> "\n" <> manifestFailure))
        Right manifestJson ->
          case extractDigestForArchitecture targetArchitecture manifestJson of
            Nothing ->
              pure (Left ("no linux/" <> targetArchitecture <> " entry in upstream manifest for " <> sourceImage))
            Just archDigest -> copyDigest archDigest
  where
    targetArchitecture = harborTargetArchitecture options

    copyDigest archDigest = do
      let sourceRepository = takeBefore ':' sourceImage
          sourceByDigest = sourceRepository <> "@" <> archDigest
          -- Phase 7 Sprint 7.14 (May 25, 2026): retired the
          -- @docker buildx imagetools create@ fallback in favor
          -- of @skopeo copy@. The buildx imagetools path delegates
          -- to a buildkit container that runs on docker's default
          -- bridge network, so it cannot reach Harbor's NodePort
          -- 30002. @skopeo copy@ runs wherever the launcher command
          -- is executed, so it must dial the Harbor API host for the
          -- active control-plane context: @127.0.0.1:<port>@ for
          -- host-native execution and @<kind-control-plane>:30002@
          -- for the Linux outer-container lane. The rendered image
          -- refs and docker push target remain on 'harborHost' /
          -- 'harborClientHost'; only the skopeo transport target is
          -- rewritten.
          -- Phase 3 Sprint 3.11 (2026-05-29):
          -- @--override-os=linux@ + @--override-arch=<arch>@
          -- ensure the copy is the substrate-matched
          -- single-platform variant. On Apple Silicon this is
          -- @arm64@; on Linux substrates it stays @amd64@.
          skopeoTargetRef = skopeoTargetRefForHarborApiHost options targetRef
          skopeoSource = "docker://" <> sourceByDigest
          skopeoTarget = "docker://" <> skopeoTargetRef
          archOverrideArg = "--override-arch=" <> targetArchitecture
          destCredsArg = "--dest-creds=" <> harborUser options <> ":" <> harborPassword options
      -- Phase 3 Sprint 3.11 follow-on (2026-05-30): Homebrew's
      -- @skopeo@ on macOS does not ship a default
      -- @/etc/containers/policy.json@, so the binary's fallback
      -- aborts with "Error loading trust policy" unless we pass
      -- @--insecure-policy@. Linux distros + the launcher image's
      -- @skopeo@ ship the policy file by default; the flag is a
      -- no-op there because the policy in the file is already the
      -- supported @\"insecureAcceptAnything\"@ default. The supported
      -- contract uses HTTP against Harbor inside the cluster's
      -- private network, so insecure-policy + insecure-tls is the
      -- intended posture. @--dest-creds@ is also required because
      -- @skopeo@ reads its auth defaults from
      -- @~/.config/containers/auth.json@ (XDG-style) rather than
      -- @~/.docker/config.json@, so the @docker login@ credentials
      -- the binary already established do not transfer.
      skopeoMonitor <-
        commandMonitorFactory
          ( "skopeo --insecure-policy copy --src-tls-verify=false --dest-tls-verify=false "
              <> "--override-os=linux "
              <> archOverrideArg
              <> " --dest-creds=<redacted> "
              <> skopeoSource
              <> " "
              <> skopeoTarget
          )
      skopeoResult <-
        tryRunCommandMaybeMonitored
          (harborSkopeoCommand options)
          [ "--insecure-policy",
            "copy",
            "--src-tls-verify=false",
            "--dest-tls-verify=false",
            "--override-os=linux",
            archOverrideArg,
            destCredsArg,
            skopeoSource,
            skopeoTarget
          ]
          ""
          skopeoMonitor
      case skopeoResult of
        Right _ -> pure (Right ())
        Left skopeoFailure ->
          pure
            ( Left
                ( "skopeo copy failed for "
                    <> sourceByDigest
                    <> " -> "
                    <> targetRef
                    <> "\n"
                    <> skopeoFailure
                )
            )

-- | Heuristic: an image is considered upstream-multi-arch (and routed
-- through the digest-pinned @skopeo copy@ fallback instead of plain
-- @docker push@) when its reference does NOT start with the supported
-- locally-built prefix. Sprint 7.7's follow-on Docker-29 + containerd
-- snapshotter issue rejects pushes of multi-arch manifest lists, so
-- the supported workaround is to use a registry API copy path.
-- Locally-built repo images stay on the fast legacy @docker push@
-- path because they are single-platform by construction.
isUpstreamMultiArchImage :: String -> Bool
isUpstreamMultiArchImage imageRef =
  not (any (`hasPrefix` imageRef) localImagePrefixes)
  where
    localImagePrefixes = ["infernix-linux-cpu:", "infernix-linux-gpu:", "infernix-engine-"]
    hasPrefix prefixValue value = take (length prefixValue) value == prefixValue

parsePerEngineImageName :: String -> Maybe String
parsePerEngineImageName imageRef = do
  withoutPrefix <- List.stripPrefix "infernix-engine-" imageRef
  withoutModeSuffix <-
    stripSuffix "-linux-gpu:local" withoutPrefix
      <|> stripSuffix "-linux-cpu:local" withoutPrefix
  if null withoutModeSuffix
    then Nothing
    else Just withoutModeSuffix
  where
    stripSuffix suffix value =
      let suffixLength = length suffix
          valueLength = length value
       in if suffix `isSuffixOf` value
            then Just (take (valueLength - suffixLength) value)
            else Nothing

normalizeRepositoryPath :: String -> String
normalizeRepositoryPath rawImage =
  case splitOn '/' withoutTag of
    firstSegment : remainingSegments
      | isExplicitRegistry firstSegment -> joinWith "/" remainingSegments
    _ -> withoutTag
  where
    withoutDigest = takeBefore '@' rawImage
    withoutTag = fromMaybe withoutDigest (breakTagSuffix withoutDigest)

isHarborImage :: String -> Bool
isHarborImage imageRef = any (`isPrefixOfString` imageRef) harborPrefixes

-- type PublishedImage = (String, String)
writeHarborOverridesFile :: Map String PublishedImage -> FilePath -> IO ()
writeHarborOverridesFile publishedImages outputPath =
  case buildHarborOverridesValue publishedImages of
    Right overlayValue -> Yaml.encodeFile outputPath overlayValue
    Left err -> failWith err

-- type PublishedImage = (String, String)
buildHarborOverridesValue :: Map String PublishedImage -> Either String Value
buildHarborOverridesValue publishedImages = do
  runtimeImage <- requiredRuntimeImage publishedImages
  -- Phase 3 Sprint 3.11 (2026-05-29): the hand-authored MinIO
  -- StatefulSet under `chart/templates/minio/` consumes its image
  -- repository + tag from the `infernixMinio` block in
  -- `chart/values.yaml`. The Harbor overlay therefore overrides
  -- `infernixMinio.image` / `clientImage` / `initImage` to the
  -- Harbor-mirrored refs after publication, replacing the retired
  -- bitnami sub-chart's per-component overlay structure.
  minioImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/minio:RELEASE.2025-09-07T16-13-09Z" publishedImages)
  minioInitImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/busybox:1.36" publishedImages)
  minioClientImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/mc:RELEASE.2025-08-13T08-35-41Z" publishedImages)
  pulsarImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/pulsar-all:4.0.9" publishedImages)
  postgresOperatorPublished <- requireDiscoveredImage (Map.lookup postgresOperatorImage publishedImages)
  postgresDatabasePublished <- requireDiscoveredImage (Map.lookup postgresDatabaseImage publishedImages)
  postgresPgBouncerPublished <- requireDiscoveredImage (Map.lookup postgresPgBouncerImage publishedImages)
  postgresPgBackRestPublished <- requireDiscoveredImage (Map.lookup postgresPgBackRestImage publishedImages)
  let baseOverlay =
        object
          [ "service" .= workloadImageOverlay runtimeImage,
            "demo" .= workloadImageOverlay runtimeImage,
            -- Phase 7 Sprint 7.7: the supported three-role split routes
            -- coordinator + engine images through the same Harbor-mirrored
            -- runtime image. Without these overlays the new pods pull
            -- the bare `infernix-linux-{cpu,gpu}:local` ref which is not
            -- present on Kind worker nodes.
            "coordinator" .= workloadImageOverlay runtimeImage,
            "engine" .= engineImageOverlay runtimeImage,
            "infernixMinio"
              .= infernixMinioOverlay minioImage minioClientImage minioInitImage,
            "pulsar"
              .= pulsarImageOverlay pulsarImage,
            "postgresOperator"
              .= postgresOperatorOverlay postgresOperatorPublished,
            "harborpg"
              .= harborPostgresOverlay postgresDatabasePublished postgresPgBackRestPublished postgresPgBouncerPublished
          ]
  pure baseOverlay
  where
    workloadImageOverlay imageValue =
      object ["image" .= renderRepoOwnedImage imageValue]
    engineImageOverlay imageValue =
      object
        [ "image" .= renderRepoOwnedImage imageValue,
          "perEngine"
            .= object
              [ "images"
                  .= object
                    [ Key.fromString engineName .= renderRepoOwnedImage publishedImage
                    | (engineName, publishedImage) <- perEnginePublishedImages publishedImages
                    ]
              ]
        ]
    renderRepoOwnedImage (repository, tagValue) =
      object
        [ "repository" .= repository,
          "tag" .= tagValue,
          "pullPolicy" .= ("IfNotPresent" :: String)
        ]
    perEnginePublishedImages imagesMap =
      [ (engineName, publishedImage)
      | (sourceImage, publishedImage) <- Map.toList imagesMap,
        Just engineName <- [parsePerEngineImageName sourceImage]
      ]
    pulsarImageOverlay (repository, tagValue) =
      object
        [ "defaultPulsarImageRepository" .= repository,
          "defaultPulsarImageTag" .= tagValue,
          "defaultPullPolicy" .= ("IfNotPresent" :: String)
        ]
    postgresOperatorOverlay published =
      object
        [ "image" .= renderRepositoryAndTag published,
          "imagePullPolicy" .= ("IfNotPresent" :: String)
        ]
    harborPostgresOverlay databasePublished pgBackRestPublished pgBouncerPublished =
      object
        [ "image" .= renderRepositoryAndTag databasePublished,
          "imagePullPolicy" .= ("IfNotPresent" :: String),
          "backups" .= object ["pgbackrest" .= object ["image" .= renderRepositoryAndTag pgBackRestPublished]],
          "proxy" .= object ["pgBouncer" .= object ["image" .= renderRepositoryAndTag pgBouncerPublished]]
        ]
    -- Phase 3 Sprint 3.11 (2026-05-29): override the hand-authored
    -- MinIO chart values directly. The `chart/templates/minio/*`
    -- templates reference `infernixMinio.image.repository`,
    -- `infernixMinio.image.tag`, `infernixMinio.clientImage.*`, and
    -- `infernixMinio.initImage.*`; the overlay rewrites those to
    -- point at the Harbor-mirrored content-addressed tags.
    infernixMinioOverlay minioPublished minioClientPublished minioInitPublished =
      object
        [ "image" .= harborImageWithPullPolicy minioPublished,
          "clientImage" .= harborImageWithPullPolicy minioClientPublished,
          "initImage" .= harborImageWithPullPolicy minioInitPublished
        ]
    harborImageWithPullPolicy (repository, tagValue) =
      object
        [ "repository" .= repository,
          "tag" .= tagValue,
          "pullPolicy" .= ("IfNotPresent" :: String)
        ]

-- type PublishedImage = (String, String)
requiredRuntimeImage :: Map String PublishedImage -> Either String PublishedImage
requiredRuntimeImage publishedImages =
  maybe
    (Left "required runtime image infernix-linux-cpu:local or infernix-linux-gpu:local was not published")
    Right
    (Map.lookup "infernix-linux-gpu:local" publishedImages `orElse` Map.lookup "infernix-linux-cpu:local" publishedImages)

orElse :: Maybe a -> Maybe a -> Maybe a
orElse maybeLeft maybeRight =
  maybeLeft <|> maybeRight

-- type PublishedImage = (String, String)
findPublishedImageWithSuffix :: String -> Map String PublishedImage -> Maybe PublishedImage
findPublishedImageWithSuffix suffix =
  fmap snd . find (isSuffixOf suffix . fst) . Map.toList

requireDiscoveredImage :: Maybe a -> Either String a
requireDiscoveredImage =
  maybe
    (Left "did not discover every non-Harbor third-party image required for the final Harbor-backed rollout")
    Right

-- type PublishedImage = (String, String)
renderRepositoryAndTag :: PublishedImage -> String
renderRepositoryAndTag (repository, tagValue) = repository <> ":" <> tagValue

runCommand :: FilePath -> [String] -> String -> IO ()
runCommand command args inputPayload = do
  result <- tryRunCommand command args inputPayload
  case result of
    Right _ -> pure ()
    Left err -> failWith ("command failed: " <> command <> " " <> unwords args <> "\n" <> err)

tryRunCommand :: FilePath -> [String] -> String -> IO (Either String String)
tryRunCommand command args inputPayload = do
  processResult <- try (readCreateProcessWithExitCode (proc command args) inputPayload) :: IO (Either SomeException (ExitCode, String, String))
  case processResult of
    Left err -> pure (Left (show err))
    Right (exitCode, stdoutOutput, stderrOutput) ->
      case exitCode of
        ExitSuccess -> pure (Right stdoutOutput)
        _ -> pure (Left (stdoutOutput <> stderrOutput))

tryRunCommandMaybeMonitored :: FilePath -> [String] -> String -> Maybe ProcessMonitor.CommandMonitor -> IO (Either String String)
tryRunCommandMaybeMonitored command args inputPayload maybeMonitor
  | null inputPayload =
      ProcessMonitor.tryCommandMonitored Nothing [] command args maybeMonitor
  | otherwise =
      tryRunCommand command args inputPayload

urlEncodeString :: String -> String
urlEncodeString = ByteString8.unpack . urlEncode True . ByteString8.pack

failWith :: String -> IO a
failWith message = ioError (userError ("publish-chart-images: " <> message))

takeBefore :: Char -> String -> String
takeBefore delimiter = takeWhile (/= delimiter)

-- | Phase 7 Sprint 7.14 follow-on (May 25, 2026): rewrite a
-- @localhost@-prefixed host to @127.0.0.1@ so host-native @skopeo
-- dials Harbor's IPv4-only NodePort listener instead of the unbound
-- IPv6 loopback (glibc prefers IPv6 for @localhost@).
substituteLocalhostWithLoopbackV4 :: String -> String
substituteLocalhostWithLoopbackV4 imageRef =
  case List.stripPrefix "localhost:" imageRef of
    Just remainder -> "127.0.0.1:" <> remainder
    Nothing -> imageRef

-- | Return the transport ref used by @skopeo copy@. Docker push uses
-- 'harborClientHost' because the host Docker daemon owns the push, but
-- skopeo runs in the caller's network namespace. The registry host in
-- the destination ref is therefore replaced with 'harborApiHost'.
skopeoTargetRefForHarborApiHost :: HarborPublishOptions -> String -> String
skopeoTargetRefForHarborApiHost options =
  replaceImageRegistryHost (substituteLocalhostWithLoopbackV4 (harborApiHost options))

replaceImageRegistryHost :: String -> String -> String
replaceImageRegistryHost replacementHost imageRef =
  case break (== '/') imageRef of
    ("", _) -> imageRef
    (_, '/' : repositoryPath) -> replacementHost <> "/" <> repositoryPath
    _ -> imageRef

-- | Phase 7 Sprint 7.14 follow-on (May 25, 2026): trim trailing
-- newlines + whitespace from @docker inspect --format@ output. Docker
-- emits the captured field followed by a single newline; the tag
-- callers want the bare value.
trimNewlines :: String -> String
trimNewlines = reverse . dropWhile isTrailingWhitespace . reverse

isTrailingWhitespace :: Char -> Bool
isTrailingWhitespace character = character `elem` trailingWhitespaceCharacters

trailingWhitespaceCharacters :: String
trailingWhitespaceCharacters = " \n\r\t"

-- | Phase 7 Sprint 7.14 follow-on (May 25, 2026): recovery path used
-- when the digest-pinned image cannot be tagged under the original
-- ref. Re-pulls the original tag (which puts the multi-arch manifest
-- list back) so the downstream @pushUpstreamMultiArchViaImagetools@
-- fallback can do the work. Failure here is silent because the
-- caller already failed to pin and is doing best-effort recovery.
-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)
recoverOriginalTag :: HarborPublishOptions -> CommandMonitorFactory -> String -> String -> IO ()
recoverOriginalTag options commandMonitorFactory imageRef manifestSource = do
  let platformFlagValue = "linux/" <> harborTargetArchitecture options
  recoverMonitor <- commandMonitorFactory ("docker pull --platform " <> platformFlagValue <> " " <> manifestSource)
  _ <-
    tryRunCommandMaybeMonitored
      (harborDockerCommand options)
      ["pull", "--platform", platformFlagValue, manifestSource]
      ""
      recoverMonitor
  _ <-
    if manifestSource == imageRef
      then pure (Right "")
      else tryRunCommand (harborDockerCommand options) ["tag", manifestSource, imageRef] ""
  pure ()

breakTagSuffix :: String -> Maybe String
breakTagSuffix value =
  case breakRepositoryAndTag value of
    (repositoryPath, ":", tagValue)
      | '/' `notElem` tagValue -> Just repositoryPath
    _ -> Nothing

isExplicitRegistry :: String -> Bool
isExplicitRegistry segment =
  '.' `elem` segment || ':' `elem` segment || segment == "localhost"

splitOn :: Char -> String -> [String]
splitOn delimiter = go []
  where
    go acc [] = [reverse acc]
    go acc (current : rest)
      | current == delimiter = reverse acc : go [] rest
      | otherwise = go (current : acc) rest

joinWith :: String -> [String] -> String
joinWith = intercalate

breakRepositoryAndTag :: String -> (String, String, String)
breakRepositoryAndTag value =
  case remainder of
    ':' : reversedRepository -> (reverse reversedRepository, ":", reverse reversedTag)
    _ -> (value, "", "")
  where
    reversed = reverse value
    (reversedTag, remainder) = break (== ':') reversed

breakOn :: Char -> String -> Maybe (String, String)
breakOn delimiter value =
  case break (== delimiter) value of
    (prefix, _ : suffix) -> Just (prefix, suffix)
    _ -> Nothing

replaceColon :: String -> String
replaceColon = map (\char -> if char == ':' then '-' else char)

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing

isPrefixOfString :: String -> String -> Bool
isPrefixOfString prefix value =
  case stripPrefix prefix value of
    Just _ -> True
    Nothing -> False

data DockerImageInspect = DockerImageInspect
  { dockerRepoDigests :: [String],
    dockerImageId :: Maybe String
  }

instance FromJSON DockerImageInspect where
  parseJSON =
    withObject "DockerImageInspect" $ \value ->
      DockerImageInspect
        <$> value .:? "RepoDigests" .!= []
        <*> value .:? "Id"

newtype HarborArtifact = HarborArtifact
  { harborArtifactTags :: [HarborTag]
  }

instance FromJSON HarborArtifact where
  parseJSON =
    withObject "HarborArtifact" $ \value ->
      HarborArtifact
        <$> value .:? "tags" .!= []

newtype HarborTag = HarborTag
  { harborTagName :: String
  }

instance FromJSON HarborTag where
  parseJSON =
    withObject "HarborTag" $ \value ->
      HarborTag <$> value .: "name"
