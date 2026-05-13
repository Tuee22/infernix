{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster.PublishImages
  ( HarborPublishOptions (..),
    PublishedImage,
    buildHarborOverridesValue,
    contentAddressTagFromInspectPayload,
    dockerHubMirrorRef,
    ensureLocalImageAvailable,
    defaultHarborPublishOptions,
    normalizeRepositoryPath,
    publishChartImagesFile,
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
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (find, intercalate, isSuffixOf, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
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
    harborPassword :: String
  }
  deriving (Eq, Show)

type PublishedImage = (String, String)

type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)

defaultHarborPublishOptions :: HarborPublishOptions
defaultHarborPublishOptions =
  HarborPublishOptions
    { harborHost = "localhost:30002",
      harborClientHost = "localhost:30002",
      harborApiHost = "localhost:30002",
      harborProject = "library",
      harborUser = "admin",
      harborPassword = "Harbor12345"
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

publishChartImagesFile :: HarborPublishOptions -> CommandMonitorFactory -> FilePath -> FilePath -> IO ()
publishChartImagesFile options commandMonitorFactory renderedChartPath outputPath = do
  manager <- newManager tlsManagerSettings
  images <- discoverChartImagesFile renderedChartPath
  let chartPublishableImages = filter (not . isHarborImage) images
      publishableImages = nub (alwaysPublishedImages <> chartPublishableImages)
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

publishImage :: Manager -> HarborPublishOptions -> CommandMonitorFactory -> String -> IO (String, PublishedImage)
publishImage manager options commandMonitorFactory sourceImage = do
  ensureLocalImageAvailable commandMonitorFactory sourceImage
  targetTag <- contentAddressTag sourceImage
  let repositoryPath = normalizeRepositoryPath sourceImage
      publishedRepository = harborHost options <> "/" <> harborProject options <> "/" <> repositoryPath
      clientRepository = harborClientHost options <> "/" <> harborProject options <> "/" <> repositoryPath
  publishIfNeeded manager options commandMonitorFactory sourceImage clientRepository repositoryPath targetTag
  pure (sourceImage, (publishedRepository, targetTag))

ensureLocalImageAvailable :: CommandMonitorFactory -> String -> IO ()
ensureLocalImageAvailable commandMonitorFactory imageRef = do
  maybePresent <- tryRunCommand "docker" ["image", "inspect", imageRef] ""
  case maybePresent of
    Right _ -> pure ()
    Left _ -> pullImageWithFallback commandMonitorFactory imageRef

pullImageWithFallback :: CommandMonitorFactory -> String -> IO ()
pullImageWithFallback commandMonitorFactory imageRef = do
  initialMonitor <- commandMonitorFactory ("docker pull " <> imageRef)
  pullResult <- tryRunCommandMaybeMonitored "docker" ["pull", imageRef] "" initialMonitor
  case pullResult of
    Right _ -> pure ()
    Left pullFailure ->
      case dockerHubMirrorRef imageRef of
        Nothing ->
          failWith ("docker pull failed for " <> imageRef <> "\n" <> pullFailure)
        Just mirrorRef -> do
          mirrorMonitor <- commandMonitorFactory ("docker pull " <> mirrorRef)
          mirrorPullResult <- tryRunCommandMaybeMonitored "docker" ["pull", mirrorRef] "" mirrorMonitor
          case mirrorPullResult of
            Right _ -> runCommand "docker" ["tag", mirrorRef, imageRef] ""
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

publishIfNeeded :: Manager -> HarborPublishOptions -> CommandMonitorFactory -> String -> String -> String -> String -> IO ()
publishIfNeeded manager options commandMonitorFactory sourceImage clientRepository repositoryPath targetTag = do
  let targetRef = clientRepository <> ":" <> targetTag
  runCommand "docker" ["tag", sourceImage, targetRef] ""
  tagPresent <- harborTagExists manager options repositoryPath targetTag
  if tagPresent
    then verifyRegistryPull manager options commandMonitorFactory targetRef
    else do
      pushImageWithRetries manager options commandMonitorFactory targetRef
      verifyRegistryPull manager options commandMonitorFactory targetRef

pushImageWithRetries :: Manager -> HarborPublishOptions -> CommandMonitorFactory -> String -> IO ()
pushImageWithRetries manager options commandMonitorFactory targetRef = go pushAttempts ""
  where
    (targetRepository, _, targetTag) = breakRepositoryAndTag targetRef
    repositoryPath = normalizeRepositoryPath targetRepository
    go remainingAttempts lastFailure
      | remainingAttempts <= 0 =
          failWith ("docker push failed for " <> targetRef <> "\n" <> lastFailure)
      | otherwise = do
          waitForRegistry manager options
          monitor <- commandMonitorFactory ("docker push " <> targetRef)
          result <- tryRunCommandMaybeMonitored "docker" ["push", targetRef] "" monitor
          case result of
            Right _ -> pure ()
            Left failureMessage -> do
              tagPresent <- harborTagExists manager options repositoryPath targetTag
              registryPullable <- registryPullSucceeds targetRef
              if tagPresent || registryPullable
                then pure ()
                else do
                  let attemptsUsed = pushAttempts - remainingAttempts + 1
                  if remainingAttempts > 1
                    then do
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

pushRetryDelayMicros :: Int -> Int
pushRetryDelayMicros attemptsUsed =
  min pushRetryMaxDelayMicros (attemptsUsed * pushRetryBaseDelayMicros)

registryPullSucceeds :: String -> IO Bool
registryPullSucceeds imageRef =
  either (const False) (const True) <$> tryRunCommand "docker" ["pull", imageRef] ""

verifyRegistryPull :: Manager -> HarborPublishOptions -> CommandMonitorFactory -> String -> IO ()
verifyRegistryPull manager options commandMonitorFactory targetRef = do
  waitForRegistry manager options
  go pullVerifyAttempts ""
  where
    go remainingAttempts lastFailure
      | remainingAttempts <= 0 =
          failWith ("docker pull verification failed for " <> targetRef <> "\n" <> lastFailure)
      | otherwise = do
          monitor <- commandMonitorFactory ("docker pull verify " <> targetRef)
          result <- tryRunCommandMaybeMonitored "docker" ["pull", targetRef] "" monitor
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
              "docker"
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

contentAddressTag :: String -> IO String
contentAddressTag imageRef = do
  payload <- captureCommand "docker" ["image", "inspect", imageRef] ""
  case contentAddressTagFromInspectPayload payload of
    Right tagValue -> pure tagValue
    Left err -> failWith err

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

normalizeRepositoryPath :: String -> String
normalizeRepositoryPath rawImage =
  let withoutDigest = takeBefore '@' rawImage
      withoutTag = fromMaybe withoutDigest (breakTagSuffix withoutDigest)
      pathSegments = splitOn '/' withoutTag
   in case pathSegments of
        firstSegment : remainingSegments
          | isExplicitRegistry firstSegment -> joinWith "/" remainingSegments
        _ -> withoutTag

isHarborImage :: String -> Bool
isHarborImage imageRef = any (`isPrefixOfString` imageRef) harborPrefixes

writeHarborOverridesFile :: Map String PublishedImage -> FilePath -> IO ()
writeHarborOverridesFile publishedImages outputPath =
  case buildHarborOverridesValue publishedImages of
    Right overlayValue -> Yaml.encodeFile outputPath overlayValue
    Left err -> failWith err

buildHarborOverridesValue :: Map String PublishedImage -> Either String Value
buildHarborOverridesValue publishedImages = do
  runtimeImage <- requiredRuntimeImage publishedImages
  minioImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/minio:2025.7.23-debian-12-r3" publishedImages)
  minioShellImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/os-shell:12-debian-12-r50" publishedImages)
  minioConsoleImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/minio-object-browser:2.0.2-debian-12-r3" publishedImages)
  pulsarImage <- requireDiscoveredImage (findPublishedImageWithSuffix "/pulsar-all:4.0.9" publishedImages)
  postgresOperatorPublished <- requireDiscoveredImage (Map.lookup postgresOperatorImage publishedImages)
  postgresDatabasePublished <- requireDiscoveredImage (Map.lookup postgresDatabaseImage publishedImages)
  postgresPgBouncerPublished <- requireDiscoveredImage (Map.lookup postgresPgBouncerImage publishedImages)
  postgresPgBackRestPublished <- requireDiscoveredImage (Map.lookup postgresPgBackRestImage publishedImages)
  let minioClientImage = findPublishedImageWithSuffix "/minio-client:2025.7.21-debian-12-r2" publishedImages
      baseOverlay =
        object
          [ "service"
              .= object
                [ "image" .= renderRepoOwnedImage runtimeImage
                ],
            "demo"
              .= object
                [ "image" .= renderRepoOwnedImage runtimeImage
                ],
            "minio"
              .= minioObject minioImage minioShellImage minioConsoleImage minioClientImage,
            "pulsar"
              .= object
                [ "defaultPulsarImageRepository" .= fst pulsarImage,
                  "defaultPulsarImageTag" .= snd pulsarImage,
                  "defaultPullPolicy" .= ("IfNotPresent" :: String)
                ],
            "postgresOperator"
              .= object
                [ "image" .= renderRepositoryAndTag postgresOperatorPublished,
                  "imagePullPolicy" .= ("IfNotPresent" :: String)
                ],
            "harborpg"
              .= object
                [ "image" .= renderRepositoryAndTag postgresDatabasePublished,
                  "imagePullPolicy" .= ("IfNotPresent" :: String),
                  "backups"
                    .= object
                      [ "pgbackrest"
                          .= object
                            [ "image" .= renderRepositoryAndTag postgresPgBackRestPublished
                            ]
                      ],
                  "proxy"
                    .= object
                      [ "pgBouncer"
                          .= object
                            [ "image" .= renderRepositoryAndTag postgresPgBouncerPublished
                            ]
                      ]
                ]
          ]
  pure baseOverlay
  where
    renderRepoOwnedImage (repository, tagValue) =
      object
        [ "repository" .= repository,
          "tag" .= tagValue,
          "pullPolicy" .= ("IfNotPresent" :: String)
        ]
    minioObject minioPublished minioShellPublished minioConsolePublished maybeMinioClientPublished =
      let baseObject =
            [ "image" .= splitRegistryRepository minioPublished,
              "defaultInitContainers"
                .= object
                  [ "volumePermissions"
                      .= object
                        [ "image" .= splitRegistryRepository minioShellPublished
                        ]
                  ],
              "console"
                .= object
                  [ "image" .= splitRegistryRepository minioConsolePublished
                  ]
            ]
       in object
            ( baseObject
                <> maybe
                  []
                  (\published -> ["clientImage" .= splitRegistryRepository published])
                  maybeMinioClientPublished
            )

requiredRuntimeImage :: Map String PublishedImage -> Either String PublishedImage
requiredRuntimeImage publishedImages =
  maybe
    (Left "required runtime image infernix-linux-cpu:local or infernix-linux-gpu:local was not published")
    Right
    (Map.lookup "infernix-linux-gpu:local" publishedImages `orElse` Map.lookup "infernix-linux-cpu:local" publishedImages)

orElse :: Maybe a -> Maybe a -> Maybe a
orElse maybeLeft maybeRight =
  maybeLeft <|> maybeRight

findPublishedImageWithSuffix :: String -> Map String PublishedImage -> Maybe PublishedImage
findPublishedImageWithSuffix suffix =
  fmap snd . find (isSuffixOf suffix . fst) . Map.toList

requireDiscoveredImage :: Maybe a -> Either String a
requireDiscoveredImage =
  maybe
    (Left "did not discover every non-Harbor third-party image required for the final Harbor-backed rollout")
    Right

splitRegistryRepository :: PublishedImage -> Value
splitRegistryRepository (repository, tagValue) =
  let (registryValue, repositoryRemainder) = breakOnFirst '/' repository
   in object
        [ "registry" .= registryValue,
          "repository" .= repositoryRemainder,
          "tag" .= tagValue
        ]

renderRepositoryAndTag :: PublishedImage -> String
renderRepositoryAndTag (repository, tagValue) = repository <> ":" <> tagValue

runCommand :: FilePath -> [String] -> String -> IO ()
runCommand command args inputPayload = do
  result <- tryRunCommand command args inputPayload
  case result of
    Right _ -> pure ()
    Left err -> failWith ("command failed: " <> command <> " " <> unwords args <> "\n" <> err)

captureCommand :: FilePath -> [String] -> String -> IO String
captureCommand command args inputPayload = do
  result <- tryRunCommand command args inputPayload
  case result of
    Right stdoutOutput -> pure stdoutOutput
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
  let reversed = reverse value
      (reversedTag, remainder) = break (== ':') reversed
   in case remainder of
        ':' : reversedRepository -> (reverse reversedRepository, ":", reverse reversedTag)
        _ -> (value, "", "")

breakOn :: Char -> String -> Maybe (String, String)
breakOn delimiter value =
  case break (== delimiter) value of
    (prefix, _ : suffix) -> Just (prefix, suffix)
    _ -> Nothing

breakOnFirst :: Char -> String -> (String, String)
breakOnFirst delimiter value =
  case break (== delimiter) value of
    (prefix, _ : suffix) -> (prefix, suffix)
    _ -> (value, "")

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
