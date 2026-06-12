{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.DemoConfig
  ( decodeDemoConfigFile,
    ensureGeneratedDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    renderGeneratedDemoConfigPayload,
    renderModelListing,
    stripDemoConfigBanner,
    validateDemoConfigFile,
  )
where

import Control.Exception (IOException, SomeException, bracketOnError, catch, try)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (intercalate, nub)
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import Infernix.Config (Paths)
import Infernix.Config qualified as Config
import Infernix.HostConfig qualified as HostConfig
import Infernix.Models
  ( canonicalBatchTopicForMode,
    catalogForMode,
    encodeDemoConfig,
    engineBindingsForMode,
    frameworkEngineNamesForMode,
    hostBatchTopicForMode,
    perEngineBatchTopicForMode,
    requestTopicsForMode,
    resultTopicForMode,
  )
import Infernix.Substrate (decodeSubstrateConfigFile, demoConfigGeneratedBannerLine)
import Infernix.Types
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile, renameFile)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, openBinaryTempFile)
import System.Posix.User (getEffectiveUserID, getUserEntryForID, homeDirectory)

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
  demoConfig <- decodeSubstrateConfigFile filePath
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

-- | Phase 1 Sprint 1.11 — materialize the host manifest beside the
-- substrate file. The supported defaults come from
-- 'HostConfig.defaultAppleHostNativeHostConfig' (Apple) and
-- 'HostConfig.defaultLinuxOuterContainerHostConfig' (Linux launcher)
-- per the active execution context. Operators override individual
-- fields by hand-editing the materialized file; subsequent
-- @infernix internal materialize-substrate@ runs do not overwrite the
-- operator edits because we only materialize when the file is absent
-- (the @ensureGeneratedDemoConfigFile@ idempotency model is mirrored
-- here for the host manifest).
materializeHostManifestFile :: Paths -> IO FilePath
materializeHostManifestFile paths = do
  let buildRootPath = Config.buildRoot paths
      filePath = buildRootPath </> "infernix-host.dhall"
  createDirectoryIfMissing True buildRootPath
  alreadyMaterialized <- doesFileExist filePath
  if alreadyMaterialized
    then pure filePath
    else do
      operatorHome <- resolveOperatorHomeDirectory
      let hostConfig = case Config.controlPlaneContext paths of
            Config.OuterContainer ->
              HostConfig.defaultLinuxOuterContainerHostConfig (Text.pack "/root")
            _ ->
              HostConfig.defaultAppleHostNativeHostConfig
                (Text.pack (Config.repoRoot paths))
                (Text.pack operatorHome)
          payload = ByteStringChar8.pack (HostConfig.renderHostConfig hostConfig)
      bracketOnError
        (openBinaryTempFile buildRootPath "infernix-host.dhall.tmp")
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

ensureGeneratedDemoConfigFile :: Paths -> RuntimeMode -> Bool -> IO FilePath
ensureGeneratedDemoConfigFile paths runtimeMode defaultDemoUiEnabled = do
  let filePath = Config.generatedDemoConfigPath paths
  fileExists <- doesFileExist filePath
  if fileExists
    then do
      -- Phase 7 Sprint 7.7: re-materialise if the staged file fails to
      -- decode under the current schema. The supported flow
      -- materialises this file as part of cluster up; a stale
      -- pre-rename file (with @clusterDaemon@ / @hostDaemon@ keys)
      -- can't satisfy the renamed @coordinator@ / @engine@ schema, so
      -- the decoder rejects it and we regenerate from
      -- @renderGeneratedDemoConfigPayload@.
      decodeResult <- try (decodeDemoConfigFile filePath)
      case decodeResult of
        Left (_ :: SomeException) ->
          materializeGeneratedDemoConfigFile paths runtimeMode defaultDemoUiEnabled
        Right demoConfig ->
          if configRuntimeMode demoConfig == runtimeMode
            then pure filePath
            else materializeGeneratedDemoConfigFile paths runtimeMode defaultDemoUiEnabled
    else materializeGeneratedDemoConfigFile paths runtimeMode defaultDemoUiEnabled

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
            coordinatorDaemon = coordinatorDaemonConfig runtimeMode,
            engineDaemons = engineDaemonConfigs runtimeMode,
            requestTopics = requestTopicsForMode runtimeMode,
            resultTopic = resultTopicForMode runtimeMode,
            modelsBucket = defaultModelsBucket,
            modelBootstrapTopic = defaultModelBootstrapTopic,
            engines = engineBindingsForMode runtimeMode,
            models = catalogForMode runtimeMode
          }
    )

defaultDaemonRoleForMaterializedFile :: Paths -> RuntimeMode -> DaemonRole
defaultDaemonRoleForMaterializedFile paths runtimeMode =
  case (Config.controlPlaneContext paths, runtimeMode) of
    (Config.HostNative, AppleSilicon) -> Engine
    _ -> Coordinator

coordinatorDaemonConfig :: RuntimeMode -> DaemonConfig
coordinatorDaemonConfig runtimeMode =
  DaemonConfig
    { daemonConfigRole = Coordinator,
      daemonConfigLocation = "cluster-pod",
      daemonConfigRequestTopics = requestTopicsForMode runtimeMode,
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigHostBatchTopic = hostBatchTopicForMode runtimeMode,
      daemonConfigPulsarConnectionMode = ConfiguredTransport
    }

-- | Phase 7 Sprint 7.7: the engine role is deployed on every supported
-- substrate. On Apple silicon it runs as the on-host daemon (location
-- @control-plane-host@, Pulsar transport discovered through the
-- publication edge). On Linux substrates it runs as the in-cluster
-- @infernix-engine@ Deployment (location @cluster-pod@, Pulsar transport
-- configured directly via env vars). In every case the engine consumes
-- the inference-batch topic the coordinator hands off to.
engineDaemonConfigs :: RuntimeMode -> [DaemonConfig]
engineDaemonConfigs runtimeMode =
  -- Phase 7 Sprint 7.7: the engine consumes its substrate's
  -- @inference.batch.<mode>@ topic, executes the worker, and publishes
  -- the result to @inference.result.<mode>@. The host_batch_topic
  -- field stays @Nothing@ for the engine role so the consumer loop
  -- falls into the "execute inline" branch; setting it to the same
  -- topic the engine consumes from would create an infinite
  -- forward loop in @handleConsumerEnvelope@. The coordinator role
  -- is the only daemon that forwards from request -> batch.
  case runtimeMode of
    AppleSilicon ->
      [ hostEngineDaemon runtimeMode
      ]
    _ ->
      genericLinuxEngineDaemon runtimeMode : perFrameworkEngineDaemons runtimeMode

hostEngineDaemon :: RuntimeMode -> DaemonConfig
hostEngineDaemon runtimeMode =
  DaemonConfig
    { daemonConfigRole = Engine,
      daemonConfigLocation = "control-plane-host",
      daemonConfigRequestTopics = maybe [] pure (hostBatchTopicForMode runtimeMode),
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigHostBatchTopic = Nothing,
      daemonConfigPulsarConnectionMode = PublicationEdgeAutoDiscovery
    }

genericLinuxEngineDaemon :: RuntimeMode -> DaemonConfig
genericLinuxEngineDaemon runtimeMode =
  DaemonConfig
    { daemonConfigRole = Engine,
      daemonConfigLocation = "cluster-pod",
      daemonConfigRequestTopics = [canonicalBatchTopicForMode runtimeMode],
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigHostBatchTopic = Nothing,
      daemonConfigPulsarConnectionMode = ConfiguredTransport
    }

perFrameworkEngineDaemons :: RuntimeMode -> [DaemonConfig]
perFrameworkEngineDaemons runtimeMode =
  case runtimeMode of
    LinuxGpu ->
      map (perFrameworkEngineDaemon runtimeMode) (frameworkEngineNamesForMode runtimeMode)
    _ -> []

perFrameworkEngineDaemon :: RuntimeMode -> Text.Text -> DaemonConfig
perFrameworkEngineDaemon runtimeMode engineName =
  DaemonConfig
    { daemonConfigRole = Engine,
      daemonConfigLocation = "cluster-pod",
      daemonConfigRequestTopics = [perEngineBatchTopicForMode runtimeMode engineName],
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigHostBatchTopic = Nothing,
      daemonConfigPulsarConnectionMode = ConfiguredTransport
    }

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
      Left "active daemon role must match either the coordinator or engine metadata"
  | invalidDaemonConfig (coordinatorDaemon demoConfig) =
      Left "coordinator metadata must declare role, location, request topics, and result topic"
  | null (engineDaemons demoConfig) =
      Left "engine metadata must not be empty"
  | any invalidDaemonConfig (engineDaemons demoConfig) =
      Left "every engine metadata entry must declare role, location, request topics, and result topic"
  | configRuntimeMode demoConfig == AppleSilicon && isNothing primaryEngineDaemon =
      Left "apple-silicon configs must include engine metadata"
  | configRuntimeMode demoConfig == AppleSilicon && isNothing (daemonConfigHostBatchTopic (coordinatorDaemon demoConfig)) =
      Left "apple-silicon coordinator metadata must declare a host batch topic"
  | configRuntimeMode demoConfig == AppleSilicon && maybe True (null . daemonConfigRequestTopics) primaryEngineDaemon =
      Left "apple-silicon engine metadata must consume the host batch topic"
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
      any (Text.null . Text.strip) [name requestField, label requestField]
    invalidActiveDaemonRole =
      activeDaemonRole demoConfig
        /= daemonConfigRole (coordinatorDaemon demoConfig)
        && all ((/= activeDaemonRole demoConfig) . daemonConfigRole) (engineDaemons demoConfig)
    invalidDaemonConfig daemonConfig =
      Text.null (Text.strip (daemonConfigLocation daemonConfig))
        || null (daemonConfigRequestTopics daemonConfig)
        || any (Text.null . Text.strip) (daemonConfigRequestTopics daemonConfig)
        || Text.null (Text.strip (daemonConfigResultTopic daemonConfig))
    primaryEngineDaemon =
      case engineDaemons demoConfig of
        firstEngineDaemon : _ -> Just firstEngineDaemon
        [] -> Nothing
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

-- | Phase 7 Sprint 7.17 Apple cohort closure (2026-05-29): the
-- operator's home directory used to anchor Apple host manifest defaults
-- ('HostConfig.defaultAppleHostNativeHostConfig') is resolved through
-- the libc user database via 'System.Posix.User.getEffectiveUserID' +
-- 'getUserEntryForID'. This matches the configuration-doctrine rule
-- (Section U) that operator home discovery comes from the system user
-- database, not the @\$HOME@ env var.
resolveOperatorHomeDirectory :: IO FilePath
resolveOperatorHomeDirectory = do
  uid <- getEffectiveUserID
  entry <- getUserEntryForID uid
  pure (homeDirectory entry)
