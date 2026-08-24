{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster.PublishImages
  ( RegistryPublishOptions (..),
    PublishedImage,
    buildRegistryOverridesValue,
    classifyRegistryApiStatus,
    contentAddressTagFromInspectPayload,
    contentAddressTagFromManifestPayload,
    dockerHubMirrorRef,
    ensureLocalImageAvailable,
    defaultRegistryPublishOptions,
    normalizeRepositoryPath,
    prioritizePublishableImages,
    publishChartImagesFile,
    skopeoTargetRefForRegistryApiHost,
    withRegistryAuthFile,
    writeRegistryOverridesFile,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, displayException, mask_, throwIO, try)
import Control.Monad (unless, when)
import Data.Aeson
  ( FromJSON (parseJSON),
    Value,
    eitherDecode,
    encode,
    object,
    withObject,
    (.!=),
    (.:),
    (.:?),
    (.=),
  )
import Data.Aeson.Key qualified as Key
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (find, intercalate, isSuffixOf, nub, partition)
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Yaml qualified as Yaml
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.Discover (discoverChartImagesFile)
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config qualified as Config
import Infernix.Error
  ( bracketPreservingPrimary,
    finallyPreservingPrimary,
  )
import Infernix.Evidence.Readiness qualified as Readiness
import Infernix.ProcessIdentity
  ( ProcessBirthIdentity (..),
    readProcessBirthIdentity,
  )
import Network.HTTP.Client
  ( Manager,
    Request,
    Response,
    ResponseTimeout,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
    responseTimeout,
    responseTimeoutMicro,
  )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import System.Directory (createDirectory, createDirectoryIfMissing, doesFileExist, listDirectory, removeFile, removePathForcibly)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, openBinaryTempFile)
import System.IO.Error (isAlreadyExistsError)
import System.Posix.Files (ownerModes, setFileMode)
import System.Posix.Process (getProcessID)
import Text.Read (readMaybe)

data RegistryPublishOptions = RegistryPublishOptions
  { registryHost :: String,
    registryClientHost :: String,
    registryApiHost :: String,
    -- | The repository path prefix every published image is written under
    -- (@localhost:30002\/\<namespace>\/\<repository>@). @registry:2@ creates a
    -- repository implicitly on first push, so this is a naming convention
    -- rather than a resource that has to be provisioned ahead of the push.
    registryNamespace :: String,
    -- | Phase 3 Sprint 3.11 (2026-05-29): the substrate-matched
    -- container architecture (@\"amd64\"@ or @\"arm64\"@) the
    -- publication path pins on every @docker pull --platform
    -- linux\/<arch>@ and @skopeo copy --override-arch=<arch>@.
    -- 'Cluster.publishClusterImages' overrides from the resolved
    -- host-aware architecture selector; the default below stays at
    -- @\"amd64\"@ for backward compat with callers that have not
    -- yet been updated.
    registryTargetArchitecture :: String
  }
  deriving (Eq)

instance Show RegistryPublishOptions where
  show options =
    "RegistryPublishOptions {registryHost = "
      <> show (registryHost options)
      <> ", registryClientHost = "
      <> show (registryClientHost options)
      <> ", registryApiHost = "
      <> show (registryApiHost options)
      <> ", registryNamespace = "
      <> show (registryNamespace options)
      <> ", registryTargetArchitecture = "
      <> show (registryTargetArchitecture options)
      <> "}"

type PublishedImage = (String, String)

-- | Sprint 3.15 (managed-state-transition doctrine): a publish-phase progress
-- hook. Given a human-readable command description it records the lifecycle
-- sub-phase. It no longer returns a heartbeat monitor: liveness is now the
-- required 'Subprocess.Timeout' carried by every command via the bounded
-- command kernel, not an unbounded 30 s "still running" heartbeat that could
-- mask a hung pull.
type PublishPhaseHook = String -> IO ()

-- | Sprint 3.15 (managed-state-transition doctrine): opaque evidence that a
-- specific image reference is actually /servable/ — that a bounded,
-- registry-only @skopeo copy@ from the in-cluster registry returned every
-- selected blob. This is strictly stronger than 'observeRegistryApi' (the
-- registry's @/v2/@ answered) and than @registryTagMetadataPresent@ (a tag row
-- exists in the registry's
-- retained-state-replayed Postgres). The constructor is hidden and
-- 'probeRegistryPull' is the sole minter, so "the tag metadata exists ⇒ the
-- blob is servable" is not a constructible term — this closes the
-- retained-state second-cluster-up race where the ~40 GB MinIO backing has not
-- finished rehydrating.
newtype BlobServable = BlobServable String

data PushAttemptResult
  = PushSucceeded
  | PushFailed String

defaultRegistryPublishOptions :: RegistryPublishOptions
defaultRegistryPublishOptions =
  RegistryPublishOptions
    { registryHost = "localhost:30002",
      registryClientHost = "localhost:30002",
      registryApiHost = "localhost:30002",
      registryNamespace = "library",
      registryTargetArchitecture = "amd64"
    }

-- | Image prefixes belonging to the in-cluster registry itself.
--
-- These are excluded from publication because publishing them would require
-- the registry to already be serving in order to stand the registry up. They
-- are the bounded bootstrap exception the image doctrine names: the registry
-- and its storage backend pull from upstream, and every later workload pulls
-- registry-backed refs.
registryComponentPrefixes :: [String]
registryComponentPrefixes =
  ["registry:", "library/registry:", "docker.io/library/registry:"]

requiredRenderedChartImageAlternatives :: [[String]]
requiredRenderedChartImageAlternatives =
  [ ["infernix-linux-cpu:local", "infernix-linux-gpu:local"]
  ]

alwaysPublishedImages :: [String]
alwaysPublishedImages =
  [ postgresOperatorImage,
    postgresDatabaseImage,
    postgresPgBouncerImage,
    postgresPgBackRestImage
  ]

postgresOperatorImage :: String
postgresOperatorImage = "docker.io/percona/percona-postgresql-operator:2.9.0"

postgresDatabaseImage :: String
postgresDatabaseImage = "docker.io/percona/percona-distribution-postgresql:18.3-1"

postgresPgBouncerImage :: String
postgresPgBouncerImage = "docker.io/percona/percona-pgbouncer:1.25.1-1"

postgresPgBackRestImage :: String
postgresPgBackRestImage = "docker.io/percona/percona-pgbackrest:2.58.0-1"

registryApiPollSeconds :: Int
registryApiPollSeconds = 5

registryApiPollMicros :: Int
registryApiPollMicros = registryApiPollSeconds * 1000000

registryApiReadinessSeconds :: Int
registryApiReadinessSeconds = 120

-- The legacy loop allowed roughly two minutes of local-registry startup.
-- Express that as one total readiness budget rather than an attempt counter.
registryApiReadinessDeadline :: Readiness.Deadline
registryApiReadinessDeadline =
  Readiness.Deadline
    { Readiness.deadlinePollMicros = registryApiPollMicros,
      Readiness.deadlineStallSeconds = registryApiReadinessSeconds,
      Readiness.deadlineCeilingSeconds = registryApiReadinessSeconds
    }

-- Each local registry request is independently bounded well inside the registry
-- readiness ceiling. This applies to both the /v2/ readiness probe and the
-- authenticated artifact metadata request.
registryHttpResponseTimeout :: ResponseTimeout
registryHttpResponseTimeout = responseTimeoutMicro 5000000

publishChartImagesFile ::
  RegistryPublishOptions ->
  PublishPhaseHook ->
  FilePath ->
  FilePath ->
  IO ()
publishChartImagesFile options startPublishPhase renderedChartPath outputPath = do
  manager <- newManager tlsManagerSettings
  images <- discoverChartImagesFile renderedChartPath
  let chartPublishableImages = filter (not . isRegistryComponentImage) images
      publishableImages = prioritizePublishableImages (nub (alwaysPublishedImages <> chartPublishableImages))
  mapM_ (requireOnePresent chartPublishableImages) requiredRenderedChartImageAlternatives
  waitForRegistry manager options
  publishedImages <- mapM (publishImage manager options startPublishPhase) publishableImages
  writeRegistryOverridesFile (Map.fromList publishedImages) outputPath
  where
    requireOnePresent imageSet imageRefs
      | any (`elem` imageSet) imageRefs = pure ()
      | otherwise =
          failWith
            ( "none of the required repo-owned images were present in the rendered chart: "
                <> show imageRefs
            )

-- type PublishedImage = (String, String)
publishImage ::
  Manager ->
  RegistryPublishOptions ->
  PublishPhaseHook ->
  String ->
  IO (String, PublishedImage)
publishImage manager options startPublishPhase sourceImage = do
  (maybeSourceDigest, fallbackSourceImage) <- ensureLocalImageAvailable options startPublishPhase sourceImage
  targetTag <-
    case maybeSourceDigest of
      Just sourceDigest -> pure (replaceColon sourceDigest)
      Nothing -> contentAddressTag options sourceImage
  let repositoryPath = normalizeRepositoryPath sourceImage
      publishedRepository = registryHost options <> "/" <> registryNamespace options <> "/" <> repositoryPath
      clientRepository = registryClientHost options <> "/" <> registryNamespace options <> "/" <> repositoryPath
  publishIfNeeded manager options startPublishPhase maybeSourceDigest fallbackSourceImage sourceImage clientRepository repositoryPath targetTag
  pure (sourceImage, (publishedRepository, targetTag))

ensureLocalImageAvailable :: RegistryPublishOptions -> PublishPhaseHook -> String -> IO (Maybe String, String)
ensureLocalImageAvailable options startPublishPhase imageRef = do
  maybePresent <-
    tryRunPublishCommand
      (Command.publishInspectImage (Command.ImageRef imageRef))
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
          then pullUpstreamMultiArchImage options startPublishPhase imageRef
          else do
            pullImageWithFallback options startPublishPhase imageRef
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
      maybePinnedSource <- pinLocalImageToTargetArchitecture options startPublishPhase imageRef manifestSourceImage
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
pullUpstreamMultiArchImage :: RegistryPublishOptions -> PublishPhaseHook -> String -> IO String
pullUpstreamMultiArchImage _options startPublishPhase imageRef = do
  startPublishPhase ("docker pull " <> imageRef)
  pullResult <-
    tryRunPublishCommand
      (Command.publishPullUpstream Command.DefaultPlatform (Command.ImageRef imageRef))
  case pullResult of
    Right _ -> pure imageRef
    Left pullFailure ->
      case dockerHubMirrorRef imageRef of
        Nothing ->
          failWith ("docker pull failed for " <> imageRef <> "\n" <> pullFailure)
        Just mirrorRef -> do
          startPublishPhase ("docker pull " <> mirrorRef)
          mirrorPullResult <-
            tryRunPublishCommand
              (Command.publishPullUpstream Command.DefaultPlatform (Command.ImageRef mirrorRef))
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

pullImageWithFallback :: RegistryPublishOptions -> PublishPhaseHook -> String -> IO ()
pullImageWithFallback options startPublishPhase imageRef = do
  startPublishPhase ("docker pull " <> imageRef)
  pullResult <-
    tryRunPublishCommand
      (Command.publishPullUpstream Command.DefaultPlatform (Command.ImageRef imageRef))
  case pullResult of
    Right _ -> requireLocalImagePresent options imageRef ("docker pull completed for " <> imageRef <> ", but the image is still not inspectable locally")
    Left pullFailure ->
      case dockerHubMirrorRef imageRef of
        Nothing ->
          failWith ("docker pull failed for " <> imageRef <> "\n" <> pullFailure)
        Just mirrorRef -> do
          startPublishPhase ("docker pull " <> mirrorRef)
          mirrorPullResult <-
            tryRunPublishCommand
              (Command.publishPullUpstream Command.DefaultPlatform (Command.ImageRef mirrorRef))
          case mirrorPullResult of
            Right _ -> do
              requirePublishCommand
                ("docker tag failed for " <> mirrorRef <> " as " <> imageRef)
                (Command.publishTag (Command.ImageRef mirrorRef) (Command.ImageRef imageRef))
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

requireLocalImagePresent :: RegistryPublishOptions -> String -> String -> IO ()
requireLocalImagePresent _options imageRef message = do
  imagePresent <-
    tryRunPublishCommand
      (Command.publishInspectImage (Command.ImageRef imageRef))
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

publishIfNeeded ::
  Manager ->
  RegistryPublishOptions ->
  PublishPhaseHook ->
  Maybe String ->
  String ->
  String ->
  String ->
  String ->
  String ->
  IO ()
publishIfNeeded manager options startPublishPhase maybeSourceDigest fallbackSourceImage sourceImage clientRepository repositoryPath targetTag = do
  let targetRef = clientRepository <> ":" <> targetTag
  -- Sprint 3.15: tag metadata presence (the registry's metadata store, part of the
  -- replayed retained state) may only shortcut the push via a real servability
  -- probe; it is not itself terminal. If the blob is not yet servable (e.g. the
  -- retained-state MinIO replay has not rehydrated it on a second cluster-up)
  -- the probe returns Nothing and we fall through to a real push. "Publish
  -- done" is reached only holding a 'BlobServable'.
  metadataPresent <- registryTagMetadataPresent manager options repositoryPath targetTag
  fastPath <-
    if metadataPresent
      then probeRegistryPull manager options startPublishPhase targetRef
      else pure Nothing
  case fastPath of
    Just _servable -> pure ()
    Nothing -> do
      pushImageWithinPolicyDeadline manager options startPublishPhase maybeSourceDigest fallbackSourceImage sourceImage targetRef
      _servable <- verifyRegistryPull manager options startPublishPhase targetRef
      pure ()

pushImageWithinPolicyDeadline ::
  Manager ->
  RegistryPublishOptions ->
  PublishPhaseHook ->
  Maybe String ->
  String ->
  String ->
  String ->
  IO ()
pushImageWithinPolicyDeadline manager options startPublishPhase maybeSourceDigest fallbackSourceImage sourceImage targetRef = do
  waitForRegistry manager options
  attemptResult <- pushImageOnce
  case attemptResult of
    PushSucceeded -> pure ()
    PushFailed failureMessage ->
      failWith ("docker push failed for " <> targetRef <> "\n" <> failureMessage)
  where
    (targetRepository, _, targetTag) = breakRepositoryAndTag targetRef
    repositoryPath = normalizeRepositoryPath targetRepository

    pushImageOnce = do
      retagResult <-
        tryRunPublishCommand
          (Command.publishTag (Command.ImageRef sourceImage) (Command.ImageRef targetRef))
      case retagResult of
        Left tagFailure
          | isUpstreamMultiArchImage sourceImage -> do
              imagetoolsResult <-
                pushUpstreamMultiArchViaImagetools
                  options
                  startPublishPhase
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
          -- even after a digest pin to @linux/amd64@. The registry then
          -- rejects the push with @NotFound: content digest …: not
          -- found@ because the other platform manifests are not in
          -- the local store. The supported fallback is to copy the
          -- amd64 digest straight from the upstream registry into
          -- the registry via @skopeo copy@, which bypasses the local
          -- docker store entirely and operates on the registry API. See
          -- 'pushUpstreamMultiArchViaImagetools' for the helper.
          startPublishPhase ("docker push " <> targetRef)
          pushResult <-
            tryRunPublishCommand
              (Command.publishPush (Command.ImageRef targetRef))
          case pushResult of
            Right _ -> pure PushSucceeded
            Left failureMessage
              | isUpstreamMultiArchImage sourceImage -> do
                  imagetoolsResult <-
                    pushUpstreamMultiArchViaImagetools
                      options
                      startPublishPhase
                      maybeSourceDigest
                      fallbackSourceImage
                      targetRef
                  case imagetoolsResult of
                    Right _ -> pure PushSucceeded
                    Left imagetoolsFailure -> recoverCompletedPush (failureMessage <> "\nfallback multi-arch copy failed:\n" <> imagetoolsFailure)
              | otherwise -> recoverCompletedPush failureMessage

    recoverCompletedPush failureMessage = do
      tagPresent <- registryTagMetadataPresent manager options repositoryPath targetTag
      pure $
        if tagPresent
          then PushSucceeded
          else PushFailed failureMessage

prioritizePublishableImages :: [String] -> [String]
prioritizePublishableImages imageRefs =
  let repoOwnedImages = concat requiredRenderedChartImageAlternatives
      isRepoOwned imageRef = imageRef `elem` repoOwnedImages || "infernix-engine-" `List.isPrefixOf` imageRef
      (localImages, otherImages) = partition isRepoOwned imageRefs
   in localImages <> otherImages

-- | Sprint 3.15: probe whether @targetRef@'s blob is servable from the local
-- in-cluster registry, minting 'BlobServable' evidence only after a bounded
-- registry-only pull copies the selected manifest, config, and every layer into
-- a fresh empty directory. The pull cannot reuse Docker's shared content store.
-- This is the sole minter of 'BlobServable'.
probeRegistryPull ::
  Manager ->
  RegistryPublishOptions ->
  PublishPhaseHook ->
  String ->
  IO (Maybe BlobServable)
probeRegistryPull manager options startPublishPhase targetRef = do
  waitForRegistry manager options
  startPublishPhase ("skopeo registry-only pull verify " <> targetRef)
  let registryRef = skopeoTargetRefForRegistryApiHost options targetRef
  result <-
    withRegistryAuthFile options $ \authFilePath -> do
      let verificationRoot = takeDirectory authFilePath </> "registry-pull-verification"
      bracketPreservingPrimary
        ( do
            createDirectory verificationRoot
            setFileMode verificationRoot ownerModes
            pure verificationRoot
        )
        removePathForcibly
        ( \emptyVerificationRoot ->
            tryRunPublishCommand
              ( Command.publishVerifyRegistry
                  (Command.Architecture (registryTargetArchitecture options))
                  (Command.RegistryAuthFile authFilePath)
                  (Command.ImageRef registryRef)
                  (emptyVerificationRoot </> "image")
              )
        )
  pure $
    case result of
      Right _ -> Just (BlobServable targetRef)
      Left _ -> Nothing

-- | Sprint 3.15: require servability evidence for @targetRef@ or abort the
-- publish. Reached only after a push, so a publish cannot be declared done
-- without a real bounded registry-only pull of every selected image blob
-- succeeding.
verifyRegistryPull ::
  Manager ->
  RegistryPublishOptions ->
  PublishPhaseHook ->
  String ->
  IO BlobServable
verifyRegistryPull manager options startPublishPhase targetRef = do
  outcome <- probeRegistryPull manager options startPublishPhase targetRef
  case outcome of
    Just servable -> pure servable
    Nothing ->
      failWith
        ( "registry-only pull verification failed for "
            <> targetRef
            <> ": the blob is not servable from the in-cluster registry"
        )

waitForRegistry :: Manager -> RegistryPublishOptions -> IO ()
waitForRegistry manager options = do
  outcome <-
    Readiness.awaitReadinessObservable
      registryApiReadinessDeadline
      (observeRegistryApi manager (registryApiHost options))
  Readiness.foldReadiness
    (const (pure ()))
    registryNotReady
    registryNotReady
    outcome
  where
    registryNotReady progress =
      failWith
        ( "the in-cluster registry at "
            <> registryApiHost options
            <> " never became ready to accept a publication: "
            <> Text.unpack (Readiness.progressDetail progress)
        )

-- | Sprint 3.15: the registry's @/v2/@ API answered (200/401/403). This is
-- strictly weaker than 'BlobServable' — it proves only that the registry
-- endpoint is up, not that any specific blob is servable — so it may gate
-- /whether to keep polling/, never "publish done".
observeRegistryApi :: Manager -> String -> IO (Readiness.PollOutcome ())
observeRegistryApi manager apiHost = do
  request <- parseRequest ("http://" <> apiHost <> "/v2/")
  responseResult <-
    try (httpLbs (boundedRegistryRequest request) manager) ::
      IO (Either SomeException (Response LazyChar8.ByteString))
  case responseResult of
    Left err ->
      pure
        ( Readiness.Unobservable
            (Text.pack ("registry transport failure: " <> displayException err))
        )
    Right response ->
      pure
        ( Readiness.Measured
            (classifyRegistryApiStatus (statusCode (responseStatus response)))
        )

classifyRegistryApiStatus :: Int -> Either Readiness.Progress ()
classifyRegistryApiStatus responseStatusCode
  | responseStatusCode `elem` [200, 401, 403] = Right ()
  | otherwise =
      Left
        Readiness.Progress
          { Readiness.progressObserved = 0,
            Readiness.progressExpected = 1,
            Readiness.progressDetail =
              Text.pack
                ( "the registry returned measured non-ready HTTP status "
                    <> show responseStatusCode
                )
          }

-- | Sprint 3.15: a tag /metadata/ row for @targetTag@ exists in the registry's
-- tag list. This is metadata presence only — NOT evidence the underlying blob
-- is servable — so it may shortcut the push (via a real 'probeRegistryPull'
-- servability check) but is never itself a terminal "published" state.
--
-- Sprint 3.17: read from the OCI distribution @\/v2\/\<name>\/tags\/list@
-- endpoint. The distinction the doctrine rests on is unchanged and, if
-- anything, sharper here: @registry:2@ answers this route out of its metadata
-- store without reading a single blob from S3, so a tag named in this list is
-- exactly the case a retained-state cluster with an unrehydrated object store
-- would get wrong.
registryTagMetadataPresent :: Manager -> RegistryPublishOptions -> String -> String -> IO Bool
registryTagMetadataPresent manager options repositoryPath targetTag = do
  let requestUrl = registryTagListUrl (registryApiHost options) (registryNamespace options) repositoryPath
  request <- boundedRegistryRequest <$> parseRequest requestUrl
  responseResult <-
    try (httpLbs (boundedRegistryRequest request) manager) ::
      IO (Either SomeException (Response LazyChar8.ByteString))
  case responseResult of
    Left _ -> pure False
    Right response
      | statusCode (responseStatus response) == 404 -> pure False
      | statusCode (responseStatus response) < 200 || statusCode (responseStatus response) >= 300 -> pure False
      | otherwise ->
          case eitherDecode (responseBody response) of
            Right tagList -> pure (targetTag `elem` registryTagListTags tagList)
            Left _ -> pure False

boundedRegistryRequest :: Request -> Request
boundedRegistryRequest request =
  request {responseTimeout = registryHttpResponseTimeout}

-- | The OCI distribution tag-list route for one published repository.
registryTagListUrl :: String -> String -> String -> String
registryTagListUrl apiHost namespace repositoryPath =
  "http://"
    <> apiHost
    <> "/v2/"
    <> urlEncodeString namespace
    <> "/"
    <> urlEncodeString repositoryPath
    <> "/tags/list"

contentAddressTag :: RegistryPublishOptions -> String -> IO String
contentAddressTag options imageRef = do
  inspectResult <-
    tryRunPublishCommand
      (Command.publishInspectImage (Command.ImageRef imageRef))
  case inspectResult of
    Right payload ->
      case contentAddressTagFromInspectPayload payload of
        Right tagValue -> pure tagValue
        Left err -> failWith err
    Left inspectFailure
      | isUpstreamMultiArchImage imageRef -> do
          manifestResult <-
            tryRunPublishCommand
              (Command.publishInspectManifest (Command.ImageRef imageRef))
          case manifestResult of
            Right manifestPayload ->
              case contentAddressTagFromManifestPayload (registryTargetArchitecture options) manifestPayload of
                Right tagValue -> pure tagValue
                Left err -> failWith (err <> "\n" <> inspectFailure)
            Left manifestFailure ->
              failWith
                ( "command failed: docker image inspect "
                    <> imageRef
                    <> "\n"
                    <> inspectFailure
                    <> "\nmanifest fallback failed:\n"
                    <> manifestFailure
                )
    Left inspectFailure ->
      failWith
        ( "command failed: docker image inspect "
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
-- from @options.registryTargetArchitecture@ instead of hardcoded amd64,
-- so Apple Silicon substrates publish arm64 sub-images natively
-- without Rosetta emulation.
pinLocalImageToTargetArchitecture :: RegistryPublishOptions -> PublishPhaseHook -> String -> String -> IO (Maybe (String, String))
pinLocalImageToTargetArchitecture options startPublishPhase imageRef preferredManifestSource =
  tryManifestSources manifestSources
  where
    targetArchitecture = registryTargetArchitecture options
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
      inspectResult <-
        tryRunPublishCommand
          (Command.publishInspectManifest (Command.ImageRef manifestSource))
      case inspectResult of
        Left _ -> tryManifestSources rest
        Right manifestJson ->
          case extractDigestForArchitecture targetArchitecture manifestJson of
            Nothing -> tryManifestSources rest
            Just archDigest -> do
              let imageWithoutTag = takeBefore ':' manifestSource
                  imageByDigest = imageWithoutTag <> "@" <> archDigest
              startPublishPhase ("docker pull --platform " <> platformFlagValue <> " " <> imageByDigest)
              digestPullResult <-
                tryRunPublishCommand
                  ( Command.publishPullUpstream
                      (Command.LinuxPlatform (Command.Architecture targetArchitecture))
                      (Command.ImageRef imageByDigest)
                  )
              case digestPullResult of
                Left _ -> tryManifestSources rest
                Right _ -> do
                  -- Best-effort untag so 'docker tag' writes a fresh
                  -- single-platform reference rather than overlaying the
                  -- multi-arch manifest list still attached to the tag.
                  -- The @rm@ may fail benignly (the tag wasn't present).
                  _ <-
                    tryRunPublishCommand
                      (Command.publishRemoveTag (Command.ImageRef imageRef))
                  -- @docker tag <image>\@<digest> <image>:<tag>@ fails
                  -- under the Docker 29.x containerd snapshotter
                  -- because the digest reference is not directly
                  -- tag-able even after @docker pull@ succeeds. The
                  -- supported workaround is to look up the image ID via
                  -- @docker inspect <image>\@<digest> --format '{{.Id}}'@
                  -- (which DOES work after the digest pull) and tag the
                  -- resolved ID under the original ref.
                  idResult <-
                    tryRunPublishCommand
                      (Command.publishInspectId (Command.ImageRef imageByDigest))
                  case idResult of
                    Right rawId -> do
                      let imageId = trimNewlines rawId
                      tagResult <-
                        tryRunPublishCommand
                          (Command.publishTag (Command.ImageRef imageId) (Command.ImageRef imageRef))
                      case tagResult of
                        Right _ -> pure ()
                        Left _ -> recoverOriginalTag options startPublishPhase imageRef manifestSource
                    Left _ -> recoverOriginalTag options startPublishPhase imageRef manifestSource
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
-- straight into the registry via @skopeo copy@. The copy path operates on
-- the registry API and accepts a digest-pinned source, so the Docker
-- 29.x + containerd snapshotter pitfalls that block @docker push@ for
-- multi-arch tags do not apply. The helper reuses an earlier manifest
-- digest when available; otherwise it extracts the @linux/amd64@
-- digest from the upstream manifest list, then copies
-- @docker://SRC\@DIGEST@ to @docker://DEST@.
-- Returns 'Left' with the captured stderr on any step that fails.
pushUpstreamMultiArchViaImagetools ::
  RegistryPublishOptions ->
  PublishPhaseHook ->
  Maybe String ->
  String ->
  String ->
  IO (Either String ())
pushUpstreamMultiArchViaImagetools options startPublishPhase maybeKnownSourceDigest sourceImage targetRef =
  case maybeKnownSourceDigest of
    Just archDigest -> copyDigest archDigest
    Nothing -> do
      manifestResult <-
        tryRunPublishCommand
          (Command.publishInspectManifest (Command.ImageRef sourceImage))
      case manifestResult of
        Left manifestFailure ->
          pure (Left ("docker manifest inspect failed for " <> sourceImage <> "\n" <> manifestFailure))
        Right manifestJson ->
          case extractDigestForArchitecture targetArchitecture manifestJson of
            Nothing ->
              pure (Left ("no linux/" <> targetArchitecture <> " entry in upstream manifest for " <> sourceImage))
            Just archDigest -> copyDigest archDigest
  where
    targetArchitecture = registryTargetArchitecture options

    copyDigest archDigest = do
      let sourceRepository = takeBefore ':' sourceImage
          sourceByDigest = sourceRepository <> "@" <> archDigest
          -- Phase 7 Sprint 7.14 (May 25, 2026): retired the
          -- @docker buildx imagetools create@ fallback in favor
          -- of @skopeo copy@. The buildx imagetools path delegates
          -- to a buildkit container that runs on docker's default
          -- bridge network, so it cannot reach the registry's NodePort
          -- 30002. @skopeo copy@ runs wherever the launcher command
          -- is executed, so it must dial the registry API host for the
          -- active control-plane context: @127.0.0.1:<port>@ for
          -- host-native execution and @<kind-control-plane>:30002@
          -- for the Linux outer-container lane. The rendered image
          -- refs and docker push target remain on 'registryHost' /
          -- 'registryClientHost'; only the skopeo transport target is
          -- rewritten.
          -- Phase 3 Sprint 3.11 (2026-05-29):
          -- @--override-os=linux@ + @--override-arch=<arch>@
          -- ensure the copy is the substrate-matched
          -- single-platform variant. On Apple Silicon this is
          -- @arm64@; on Linux substrates it stays @amd64@.
          skopeoTargetRef = skopeoTargetRefForRegistryApiHost options targetRef
          skopeoSource = "docker://" <> sourceByDigest
          skopeoTarget = "docker://" <> skopeoTargetRef
          archOverrideArg = "--override-arch=" <> targetArchitecture
      -- Phase 3 Sprint 3.11 follow-on (2026-05-30): Homebrew's
      -- @skopeo@ on macOS does not ship a default
      -- @/etc/containers/policy.json@, so the binary's fallback
      -- aborts with "Error loading trust policy" unless we pass
      -- @--insecure-policy@. Linux distros + the launcher image's
      -- @skopeo@ ship the policy file by default; the flag is a
      -- no-op there because the policy in the file is already the
      -- supported @\"insecureAcceptAnything\"@ default. The supported
      -- contract uses HTTP against the registry inside the cluster's
      -- private network, so insecure-policy + insecure-tls is the
      -- intended posture. A protected short-lived @--dest-authfile@ is also
      -- required because
      -- @skopeo@ reads its auth defaults from
      -- @~/.config/containers/auth.json@ (XDG-style) rather than
      -- @~/.docker/config.json@, so the @docker login@ credentials
      -- the binary already established do not transfer.
      startPublishPhase
        ( "skopeo --insecure-policy copy --src-tls-verify=false --dest-tls-verify=false "
            <> "--override-os=linux "
            <> archOverrideArg
            <> " --dest-authfile=<protected> "
            <> skopeoSource
            <> " "
            <> skopeoTarget
        )
      skopeoResult <-
        withRegistryAuthFile options $ \authFilePath ->
          tryRunPublishCommand
            ( Command.publishCopyDigest
                (Command.Architecture targetArchitecture)
                (Command.RegistryAuthFile authFilePath)
                (Command.ImageRef sourceByDigest)
                (Command.ImageRef skopeoTargetRef)
            )
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

isRegistryComponentImage :: String -> Bool
isRegistryComponentImage imageRef = any (`isPrefixOfString` imageRef) registryComponentPrefixes

-- type PublishedImage = (String, String)
writeRegistryOverridesFile :: Map String PublishedImage -> FilePath -> IO ()
writeRegistryOverridesFile publishedImages outputPath =
  case buildRegistryOverridesValue publishedImages of
    Right overlayValue -> Yaml.encodeFile outputPath overlayValue
    Left err -> failWith err

-- type PublishedImage = (String, String)
buildRegistryOverridesValue :: Map String PublishedImage -> Either String Value
buildRegistryOverridesValue publishedImages = do
  runtimeImage <- requiredRuntimeImage publishedImages
  -- Phase 3 Sprint 3.11 (2026-05-29): the hand-authored MinIO
  -- StatefulSet under `chart/templates/minio/` consumes its image
  -- repository + tag from the `infernixMinio` block in
  -- `chart/values.yaml`. The publication overlay therefore overrides
  -- `infernixMinio.image` / `clientImage` / `initImage` to the
  -- registry-mirrored refs after publication, replacing the retired
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
            -- coordinator + engine images through the same registry-mirrored
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
            -- Phase 3 Sprint 3.17: `keycloakpg` is the platform's only
            -- Patroni cluster now that the registry carries no database, so
            -- it is the overlay target for the published Percona images.
            "keycloakpg"
              .= postgresDatabaseOverlay postgresDatabasePublished postgresPgBackRestPublished postgresPgBouncerPublished
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
    postgresDatabaseOverlay databasePublished pgBackRestPublished pgBouncerPublished =
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
    -- point at the registry-mirrored content-addressed tags.
    infernixMinioOverlay minioPublished minioClientPublished minioInitPublished =
      object
        [ "image" .= publishedImageWithPullPolicy minioPublished,
          "clientImage" .= publishedImageWithPullPolicy minioClientPublished,
          "initImage" .= publishedImageWithPullPolicy minioInitPublished
        ]
    publishedImageWithPullPolicy (repository, tagValue) =
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
    (Left "did not discover every third-party image required for the final registry-backed rollout")
    Right

-- type PublishedImage = (String, String)
renderRepositoryAndTag :: PublishedImage -> String
renderRepositoryAndTag (repository, tagValue) = repository <> ":" <> tagValue

requirePublishCommand :: String -> Command.ClusterCommand -> IO ()
requirePublishCommand failureContext command = do
  result <- tryRunPublishCommand command
  case result of
    Right _ -> pure ()
    Left err -> failWith (failureContext <> "\n" <> err)

-- | Execute only an already-closed semantic publication command. The command
-- constructor selects its generated timeout, retry, and failure policy; this
-- module cannot attach a caller-chosen budget to an arbitrary executable.
tryRunPublishCommand :: Command.ClusterCommand -> IO (Either String String)
tryRunPublishCommand command = do
  environment <- registrySubprocessEnv
  boundedCommand <-
    either
      failWith
      pure
      ( Subprocess.compileBoundedCommand
          command
          environment
      )
  outcome <- Subprocess.runBoundedCommand boundedCommand
  pure (commandOutcomeToEither outcome)

-- | Collapse a total 'Subprocess.CommandOutcome' onto the publication
-- call-site result. Retry ownership remains inside 'runBoundedCommand', where
-- one generated timeout encloses every attempt and backoff.
commandOutcomeToEither :: Subprocess.CommandOutcome -> Either String String
commandOutcomeToEither outcome =
  case outcome of
    Subprocess.CommandSucceeded stdoutOutput -> Right stdoutOutput
    Subprocess.CommandFailedFatal message -> Left message
    Subprocess.CommandFailedKernel message -> Left message
    Subprocess.CommandTimedOut (Subprocess.Timeout micros) ->
      Left ("command timed out after " <> show (micros `div` 1000000) <> "s")

-- | The typed subprocess environment for host publish commands. Fails closed
-- when the host manifest is absent (the kernel builder requires it), so a
-- publish exec without @HOME@/@TMPDIR@ is unrepresentable.
registrySubprocessEnv :: IO Subprocess.SubprocessEnv
registrySubprocessEnv = do
  paths <- Config.discoverPaths
  Subprocess.clusterSubprocessEnv paths

urlEncodeString :: String -> String
urlEncodeString = ByteString8.unpack . urlEncode True . ByteString8.pack

failWith :: String -> IO a
failWith message = ioError (userError ("publish-chart-images: " <> message))

takeBefore :: Char -> String -> String
takeBefore delimiter = takeWhile (/= delimiter)

-- | Phase 7 Sprint 7.14 follow-on (May 25, 2026): rewrite a
-- @localhost@-prefixed host to @127.0.0.1@ so host-native @skopeo
-- dials the registry's IPv4-only NodePort listener instead of the unbound
-- IPv6 loopback (glibc prefers IPv6 for @localhost@).
substituteLocalhostWithLoopbackV4 :: String -> String
substituteLocalhostWithLoopbackV4 imageRef =
  case List.stripPrefix "localhost:" imageRef of
    Just remainder -> "127.0.0.1:" <> remainder
    Nothing -> imageRef

-- | Return the transport ref used by @skopeo copy@. Docker push uses
-- 'registryClientHost' because the host Docker daemon owns the push, but
-- skopeo runs in the caller's network namespace. The registry host in
-- the destination ref is therefore replaced with 'registryApiHost'.
skopeoTargetRefForRegistryApiHost :: RegistryPublishOptions -> String -> String
skopeoTargetRefForRegistryApiHost options =
  replaceImageRegistryHost (skopeoRegistryHost options)

-- Skopeo resolves credentials by the destination authority string, so the
-- auth-file key must use the same IPv4 loopback normalization as the ref.
skopeoRegistryHost :: RegistryPublishOptions -> String
skopeoRegistryHost =
  substituteLocalhostWithLoopbackV4 . registryApiHost

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
recoverOriginalTag :: RegistryPublishOptions -> PublishPhaseHook -> String -> String -> IO ()
recoverOriginalTag options startPublishPhase imageRef manifestSource = do
  let platformFlagValue = "linux/" <> registryTargetArchitecture options
  startPublishPhase ("docker pull --platform " <> platformFlagValue <> " " <> manifestSource)
  _ <-
    tryRunPublishCommand
      ( Command.publishPullUpstream
          (Command.LinuxPlatform (Command.Architecture (registryTargetArchitecture options)))
          (Command.ImageRef manifestSource)
      )
  _ <-
    if manifestSource == imageRef
      then pure (Right "")
      else
        tryRunPublishCommand
          (Command.publishTag (Command.ImageRef manifestSource) (Command.ImageRef imageRef))
  pure ()

-- | Supply skopeo with Docker-compatible authentication without placing a
-- credential in argv. 'openBinaryTempFile' creates the file mode 0600; the
-- bracket removes it on success, failure, and asynchronous cancellation.
withRegistryAuthFile ::
  RegistryPublishOptions ->
  (FilePath -> IO a) ->
  IO a
withRegistryAuthFile options action = do
  paths <- Config.discoverPaths
  processId <- fromIntegral <$> getProcessID
  processIdentity <-
    readProcessBirthIdentity processId
      >>= maybe
        ( ioError
            ( userError
                "publication refused: the kernel did not provide a process birth identity for the owned registry scratch root"
            )
        )
        pure
  let authRoot = Config.runtimeRoot paths </> "secrets" </> "skopeo-auth"
  createDirectoryIfMissing True authRoot
  setFileMode authRoot ownerModes
  reconcileStaleAuthDirectories authRoot
  bracketPreservingPrimary
    (createOwnedAuthDirectory authRoot processId processIdentity)
    removePathForcibly
    ( \processDirectory ->
        bracketPreservingPrimary
          (createAuthFile processDirectory)
          removeAuthFile
          action
    )
  where
    createAuthFile secretDirectory =
      bracketPreservingPrimary
        (openBinaryTempFile secretDirectory "skopeo-auth.json.")
        (hClose . snd)
        ( \(authFilePath, authHandle) -> do
            LazyChar8.hPutStr authHandle (registryAuthPayload options)
            pure authFilePath
        )
    removeAuthFile authFilePath = do
      exists <- doesFileExist authFilePath
      when exists (removeFile authFilePath)

createOwnedAuthDirectory ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  IO FilePath
createOwnedAuthDirectory authRoot processId processIdentity =
  mask_ (createCandidate 0)
  where
    createCandidate candidateIndex = do
      let candidate =
            authRoot
              </> renderOwnedAuthDirectory
                processId
                processIdentity
                candidateIndex
      createResult <- try (createDirectory candidate)
      case createResult of
        Right () -> do
          modeResult <-
            try (setFileMode candidate ownerModes) ::
              IO (Either SomeException ())
          case modeResult of
            Right () -> pure candidate
            Left modeFailure ->
              finallyPreservingPrimary
                (throwIO modeFailure)
                (removePathForcibly candidate)
        Left err
          | isAlreadyExistsError err -> createCandidate (candidateIndex + 1)
          | otherwise -> ioError err

renderOwnedAuthDirectory ::
  Integer ->
  ProcessBirthIdentity ->
  Int ->
  FilePath
renderOwnedAuthDirectory processId processIdentity candidateIndex =
  List.intercalate
    "."
    [ "process-v1",
      show processId,
      show (processBirthStartTime processIdentity),
      processBirthBootIdentity processIdentity,
      show candidateIndex
    ]

parseOwnedAuthDirectory ::
  FilePath ->
  Maybe (Integer, ProcessBirthIdentity)
parseOwnedAuthDirectory entry =
  case splitOnPeriod entry of
    ["process-v1", processIdText, startTimeText, bootIdentity, candidateIndexText] -> do
      processId <- readMaybe processIdText
      startTime <- readMaybe startTimeText
      candidateIndex <- readMaybe candidateIndexText
      if processId > 0 && startTime > 0 && candidateIndex >= (0 :: Int)
        then
          Just
            ( processId,
              ProcessBirthIdentity
                { processBirthBootIdentity = bootIdentity,
                  processBirthStartTime = startTime
                }
            )
        else Nothing
    _ -> Nothing

splitOnPeriod :: String -> [String]
splitOnPeriod value =
  case break (== '.') value of
    (component, []) -> [component]
    (component, _ : suffix) -> component : splitOnPeriod suffix

reconcileStaleAuthDirectories :: FilePath -> IO ()
reconcileStaleAuthDirectories authRoot = do
  entries <- listDirectory authRoot
  mapM_ reconcileEntry entries
  where
    reconcileEntry entry =
      case parseOwnedAuthDirectory entry of
        Nothing ->
          ioError
            ( userError
                ( "unexpected entry in the skopeo auth root: "
                    <> authRoot
                    </> entry
                )
            )
        Just (ownerProcessId, expectedIdentity) -> do
          observedIdentity <- readProcessBirthIdentity ownerProcessId
          unless
            (observedIdentity == Just expectedIdentity)
            (removePathForcibly (authRoot </> entry))

-- | Sprint 3.17: the in-cluster registry serves anonymously, so the file
-- skopeo is pointed at declares an entry for the registry host carrying no
-- credential at all.
--
-- The file has not become pointless with the credential gone — what it always
-- protected, and still protects, is the mode-0700 birth-identity-owned
-- directory it lives in. 'probeRegistryPull' builds its throwaway @dir:@ store
-- as a sibling of this file, so that directory holds real pulled image layers
-- and its ownership is the property that matters.
registryAuthPayload :: RegistryPublishOptions -> LazyChar8.ByteString
registryAuthPayload options =
  encode
    ( object
        [ "auths"
            .= object
              [ Key.fromString (skopeoRegistryHost options) .= object []
              ]
        ]
    )

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

-- | The OCI distribution @\/v2\/\<name>\/tags\/list@ response body.
newtype RegistryTagList = RegistryTagList
  { registryTagListTags :: [String]
  }

instance FromJSON RegistryTagList where
  parseJSON =
    withObject "RegistryTagList" $ \value ->
      RegistryTagList
        <$> value .:? "tags" .!= []
