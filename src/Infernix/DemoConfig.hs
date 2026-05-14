{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoConfig
  ( decodeDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    renderGeneratedDemoConfigPayload,
    renderModelListing,
    stripDemoConfigBanner,
    validateDemoConfigFile,
  )
where

import Control.Exception (IOException, bracketOnError, catch)
import Data.Aeson (eitherDecodeStrict')
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (intercalate, nub)
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import Infernix.Config (Paths)
import Infernix.Config qualified as Config
import Infernix.Models (catalogForMode, encodeDemoConfig, engineBindingsForMode, hostBatchTopicForMode, requestTopicsForMode, resultTopicForMode)
import Infernix.Types
import Infernix.Workflow (demoConfigGeneratedBannerLine)
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory)
import System.IO (hClose, openBinaryTempFile)

demoConfigBannerBytes :: ByteString.ByteString
demoConfigBannerBytes = ByteStringChar8.pack demoConfigGeneratedBannerLine

stripDemoConfigBanner :: ByteString.ByteString -> ByteString.ByteString
stripDemoConfigBanner rawValue =
  case dropBlankPrefix (ByteStringChar8.lines rawValue) of
    firstLine : remainingLines
      | ByteStringChar8.strip firstLine == demoConfigBannerBytes ->
          ByteStringChar8.unlines remainingLines
    trimmedLines -> ByteStringChar8.unlines trimmedLines
  where
    dropBlankPrefix = dropWhile (ByteString.null . ByteStringChar8.strip)

decodeDemoConfigFile :: FilePath -> IO DemoConfig
decodeDemoConfigFile filePath = do
  rawValue <- ByteString.readFile filePath
  case eitherDecodeStrict' (stripDemoConfigBanner rawValue) of
    Left message -> ioError (userError ("invalid demo config: " <> message))
    Right demoConfig ->
      case validateDemoConfig demoConfig of
        Left message -> ioError (userError ("invalid demo config: " <> message))
        Right validDemoConfig -> pure validDemoConfig

validateDemoConfigFile :: FilePath -> IO ()
validateDemoConfigFile filePath = do
  _ <- decodeDemoConfigFile filePath
  pure ()

materializeGeneratedDemoConfigFile :: Paths -> RuntimeMode -> Bool -> IO FilePath
materializeGeneratedDemoConfigFile paths runtimeMode demoUiEnabledValue = do
  let filePath = Config.generatedDemoConfigPath paths
  let outputDirectory = takeDirectory filePath
      payload = renderGeneratedDemoConfig paths runtimeMode demoUiEnabledValue
  createDirectoryIfMissing True outputDirectory
  bracketOnError
    (openBinaryTempFile outputDirectory "infernix-substrate.dhall.tmp")
    ( \(temporaryPath, handle) -> do
        ignoreIo (hClose handle)
        ignoreIo (removeFile temporaryPath)
    )
    ( \(temporaryPath, handle) -> do
        ByteString.hPut handle payload
        hClose handle
        renameFile temporaryPath filePath
    )
  pure filePath

ignoreIo :: IO () -> IO ()
ignoreIo action = action `catch` ignoreIOException

ignoreIOException :: IOException -> IO ()
ignoreIOException _ = pure ()

renderGeneratedDemoConfig :: Paths -> RuntimeMode -> Bool -> ByteString.ByteString
renderGeneratedDemoConfig paths runtimeMode demoUiEnabledValue =
  renderGeneratedDemoConfigPayload paths runtimeMode demoUiEnabledValue (defaultDaemonRoleForMaterializedFile paths runtimeMode)

renderGeneratedDemoConfigPayload :: Paths -> RuntimeMode -> Bool -> DaemonRole -> ByteString.ByteString
renderGeneratedDemoConfigPayload paths runtimeMode demoUiEnabledValue daemonRole =
  LazyByteString.toStrict
    ( encodeDemoConfig
        DemoConfig
          { configRuntimeMode = runtimeMode,
            configEdgePort = 0,
            configMapName = "infernix-demo-config",
            generatedPath = Config.generatedDemoConfigPath paths,
            mountedPath = Config.watchedDemoConfigPath,
            demoUiEnabled = demoUiEnabledValue,
            activeDaemonRole = daemonRole,
            clusterDaemon = clusterDaemonConfig runtimeMode,
            hostDaemon = hostDaemonConfig runtimeMode,
            requestTopics = requestTopicsForMode runtimeMode,
            resultTopic = resultTopicForMode runtimeMode,
            engines = engineBindingsForMode runtimeMode,
            models = catalogForMode runtimeMode
          }
    )

defaultDaemonRoleForMaterializedFile :: Paths -> RuntimeMode -> DaemonRole
defaultDaemonRoleForMaterializedFile paths runtimeMode =
  case (Config.controlPlaneContext paths, runtimeMode) of
    ("host-native", AppleSilicon) -> HostDaemon
    _ -> ClusterDaemon

clusterDaemonConfig :: RuntimeMode -> DaemonConfig
clusterDaemonConfig runtimeMode =
  DaemonConfig
    { daemonConfigRole = ClusterDaemon,
      daemonConfigLocation = "cluster-pod",
      daemonConfigRequestTopics = requestTopicsForMode runtimeMode,
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigHostBatchTopic = hostBatchTopicForMode runtimeMode,
      daemonConfigPulsarConnectionMode = "configured-transport"
    }

hostDaemonConfig :: RuntimeMode -> Maybe DaemonConfig
hostDaemonConfig runtimeMode =
  case runtimeMode of
    AppleSilicon ->
      Just
        DaemonConfig
          { daemonConfigRole = HostDaemon,
            daemonConfigLocation = "control-plane-host",
            daemonConfigRequestTopics = maybe [] pure (hostBatchTopicForMode runtimeMode),
            daemonConfigResultTopic = resultTopicForMode runtimeMode,
            daemonConfigHostBatchTopic = hostBatchTopicForMode runtimeMode,
            daemonConfigPulsarConnectionMode = "publication-edge-auto-discovery"
          }
    _ -> Nothing

renderModelListing :: DemoConfig -> String
renderModelListing demoConfig =
  unlines
    ( ("runtimeMode\t" <> Text.unpack (runtimeModeId (configRuntimeMode demoConfig)))
        : map renderModelLine (models demoConfig)
    )
  where
    renderModelLine model =
      intercalate
        "\t"
        [ "model",
          Text.unpack (matrixRowId model),
          Text.unpack (modelId model),
          Text.unpack (selectedEngine model),
          Text.unpack (runtimeModeId (runtimeMode model)),
          if requiresGpu model then "true" else "false"
        ]

validateDemoConfig :: DemoConfig -> Either String DemoConfig
validateDemoConfig demoConfig
  | configEdgePort demoConfig < 0 || configEdgePort demoConfig > 65535 =
      Left "edgePort must be between 0 and 65535"
  | Text.null (Text.strip (configMapName demoConfig)) =
      Left "configMapName must not be blank"
  | null (requestTopics demoConfig) =
      Left "request_topics must not be empty"
  | any (Text.null . Text.strip) (requestTopics demoConfig) =
      Left "request_topics must not contain blank values"
  | Text.null (Text.strip (resultTopic demoConfig)) =
      Left "result_topic must not be blank"
  | null (engines demoConfig) =
      Left "engines must not be empty"
  | any invalidEngineBinding (engines demoConfig) =
      Left "every engine binding must declare non-blank engine, adapterId, adapterType, adapterLocator, adapterEntrypoint, setupEntrypoint, and projectDirectory values"
  | null (models demoConfig) =
      Left "models must not be empty"
  | any invalidRequestShape (models demoConfig) =
      Left "every model must declare at least one request field"
  | invalidActiveDaemonRole =
      Left "active daemon role must match either the cluster daemon or host daemon metadata"
  | invalidDaemonConfig (clusterDaemon demoConfig) =
      Left "cluster daemon metadata must declare role, location, request topics, and result topic"
  | maybe False invalidDaemonConfig (hostDaemon demoConfig) =
      Left "host daemon metadata must declare role, location, request topics, and result topic"
  | configRuntimeMode demoConfig == AppleSilicon && isNothing (hostDaemon demoConfig) =
      Left "apple-silicon configs must include host daemon metadata"
  | configRuntimeMode demoConfig == AppleSilicon && isNothing (daemonConfigHostBatchTopic (clusterDaemon demoConfig)) =
      Left "apple-silicon cluster daemon metadata must declare a host batch topic"
  | configRuntimeMode demoConfig == AppleSilicon && maybe True (null . daemonConfigRequestTopics) (hostDaemon demoConfig) =
      Left "apple-silicon host daemon metadata must consume the host batch topic"
  | any runtimeMismatch (models demoConfig) =
      Left "every model runtimeMode must match the demo config runtimeMode"
  | missingEngineBindings /= [] =
      Left ("missing engine bindings for selected engines: " <> intercalate ", " missingEngineBindings)
  | duplicateModelIds /= [] =
      Left ("duplicate model ids detected: " <> intercalate ", " duplicateModelIds)
  | duplicateMatrixRows /= [] =
      Left ("duplicate matrix row ids detected: " <> intercalate ", " duplicateMatrixRows)
  | duplicateEngineNames /= [] =
      Left ("duplicate engine bindings detected: " <> intercalate ", " duplicateEngineNames)
  | otherwise = Right demoConfig
  where
    invalidEngineBinding engineBinding =
      any
        (Text.null . Text.strip)
        [ engineBindingName engineBinding,
          engineBindingAdapterId engineBinding,
          engineBindingAdapterType engineBinding,
          engineBindingAdapterLocator engineBinding,
          engineBindingAdapterEntrypoint engineBinding,
          engineBindingSetupEntrypoint engineBinding,
          Text.pack (engineBindingProjectDirectory engineBinding)
        ]
    invalidRequestShape model =
      null (requestShape model)
        || any invalidField (requestShape model)
    invalidField requestField =
      any (Text.null . Text.strip) [name requestField, label requestField, fieldType requestField]
    invalidActiveDaemonRole =
      activeDaemonRole demoConfig
        /= daemonConfigRole (clusterDaemon demoConfig)
        && maybe True ((/= activeDaemonRole demoConfig) . daemonConfigRole) (hostDaemon demoConfig)
    invalidDaemonConfig daemonConfig =
      Text.null (Text.strip (daemonConfigLocation daemonConfig))
        || null (daemonConfigRequestTopics daemonConfig)
        || any (Text.null . Text.strip) (daemonConfigRequestTopics daemonConfig)
        || Text.null (Text.strip (daemonConfigResultTopic daemonConfig))
        || Text.null (Text.strip (daemonConfigPulsarConnectionMode daemonConfig))
    runtimeMismatch model = runtimeMode model /= configRuntimeMode demoConfig
    missingEngineBindings =
      [ Text.unpack engineName
      | engineName <- nub (map selectedEngine (models demoConfig)),
        engineName `notElem` map engineBindingName (engines demoConfig)
      ]
    duplicateModelIds = duplicates (map (Text.unpack . modelId) (models demoConfig))
    duplicateMatrixRows = duplicates (map (Text.unpack . matrixRowId) (models demoConfig))
    duplicateEngineNames = duplicates (map (Text.unpack . engineBindingName) (engines demoConfig))

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  nub [value | value <- values, occurrences value values > 1]

occurrences :: (Eq a) => a -> [a] -> Int
occurrences wantedValue = length . filter (== wantedValue)
