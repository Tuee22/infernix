{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.DemoConfig
  ( decodeBootstrapDemoConfigFile,
    decodeDemoConfigFile,
    materializeEmptyModelsDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    materializeHostSecrets,
    renderGeneratedDemoConfig,
    renderGeneratedDemoConfigPayload,
    renderModelListing,
    resolveInferenceMemoryBudget,
    stripDemoConfigBanner,
    validateDemoConfig,
    validateDemoConfigFile,
    writeProjectConfigFile,
  )
where

import Control.Exception (IOException, SomeException, bracketOnError, catch, try)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isSpace)
import Data.List (intercalate, nub)
import Data.Maybe (isNothing, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths)
import Infernix.Config qualified as Config
import Infernix.HostConfig (HostConfig)
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools qualified as HostTools
import Infernix.Models
  ( appleFallbackInferenceRamBudgetMib,
    catalogForMode,
    encodeDemoConfig,
    engineBindingsForMode,
    engineMemberRequestTopics,
    engineMembersForMode,
    enginePoolsForMode,
    linuxEngineInferenceRamBudgetMib,
    requestTopicsForMode,
    resultTopicForMode,
  )
import Infernix.Substrate (decodeSubstrateConfigFile, demoConfigGeneratedBannerLine)
import Infernix.Types
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
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
  case validateDemoConfigStrictModels demoConfig of
    Left message -> ioError (userError ("invalid demo config: " <> message))
    Right validDemoConfig -> pure validDemoConfig

-- | Decode the image-baked launcher config. It may intentionally carry an
-- empty model set so one-shot container commands do not trigger downloads; the
-- daemon-facing config path still uses 'decodeDemoConfigFile' and rejects that
-- shape.
decodeBootstrapDemoConfigFile :: FilePath -> IO DemoConfig
decodeBootstrapDemoConfigFile filePath = do
  demoConfig <- decodeSubstrateConfigFile filePath
  case validateDemoConfigAllowingEmptyModels demoConfig of
    Left message -> ioError (userError ("invalid demo config: " <> message))
    Right validDemoConfig -> pure validDemoConfig

validateDemoConfigFile :: FilePath -> IO ()
validateDemoConfigFile filePath = do
  _ <- decodeDemoConfigFile filePath
  pure ()

materializeGeneratedDemoConfigFile :: Paths -> RuntimeMode -> Bool -> IO FilePath
materializeGeneratedDemoConfigFile paths runtimeMode demoUiEnabledValue = do
  budget <- resolveInferenceMemoryBudget paths runtimeMode
  let filePath = Config.generatedDemoConfigPath paths
      payload = renderGeneratedDemoConfig paths runtimeMode demoUiEnabledValue budget
  writeProjectConfigFile filePath payload
  pure filePath

-- | Phase 8: the single atomic writer shared by `infernix init`,
-- `infernix test init`, and the substrate/host materializers. Writes the
-- payload to a temp file in the target directory and atomically renames it
-- into place, creating the parent directory as needed.
writeProjectConfigFile :: FilePath -> ByteString.ByteString -> IO ()
writeProjectConfigFile filePath payload = do
  let outputDirectory = takeDirectory filePath
  createDirectoryIfMissing True outputDirectory
  bracketOnError
    (openBinaryTempFile outputDirectory "infernix-config.dhall.tmp")
    ( \(temporaryPath, handle) -> do
        ignoreIo (hClose handle)
        ignoreIo (removeFile temporaryPath)
    )
    ( \(temporaryPath, handle) -> do
        ByteString.hPut handle payload
        hClose handle
        renameFile temporaryPath filePath
    )

-- | Phase 8: unconditional writer for the host manifest, invoked only by
-- `infernix init` and `internal materialize-substrate`. No auto-generate-
-- if-absent backstop remains anywhere; commands that need the manifest fail
-- fast naming `infernix init` when it is missing.
materializeHostManifestFile :: Paths -> IO FilePath
materializeHostManifestFile paths = do
  let filePath = Config.hostConfigPath paths
  operatorHome <- resolveOperatorHomeDirectory
  let hostConfig = case Config.controlPlaneContext paths of
        Config.OuterContainer ->
          HostConfig.defaultLinuxOuterContainerHostConfig (Text.pack "/root")
        _ ->
          HostConfig.defaultAppleHostNativeHostConfig
            (Text.pack (Config.repoRoot paths))
            (Text.pack operatorHome)
      payload = ByteStringChar8.pack (HostConfig.renderHostConfig hostConfig)
  writeProjectConfigFile filePath payload
  pure filePath

-- | Phase 8 Sprint 8.3: `infernix init` owns creation of the host worker
-- secret material under @./.data/runtime/secrets/@. This replaces the old
-- lazy `writeFileIfMissing` backstop in @Infernix.Runtime.Worker@; the host
-- worker now fails fast naming `infernix init` when the manifest is absent.
-- The manifest names credential *paths* (never values), and the placeholder
-- dev credential JSON files carry the default local MinIO/Keycloak logins.
-- Written unconditionally: a re-init is already gated by the runtime-config
-- `--force` check upstream, so we never clobber operator edits silently.
materializeHostSecrets :: Paths -> IO FilePath
materializeHostSecrets paths = do
  let secretsRoot = Config.runtimeRoot paths </> "secrets"
      manifestPath = secretsRoot </> "InfernixSecrets.dhall"
      minioPath = secretsRoot </> "minio.json"
      keycloakAdminPath = secretsRoot </> "keycloak-admin.json"
      keycloakDbPath = secretsRoot </> "keycloak-db.json"
  createDirectoryIfMissing True secretsRoot
  writeProjectConfigFile
    manifestPath
    (ByteStringChar8.pack (hostSecretsManifest minioPath keycloakAdminPath keycloakDbPath))
  writeProjectConfigFile minioPath "{ \"accessKey\": \"minioadmin\", \"secretKey\": \"minioadmin123\" }\n"
  writeProjectConfigFile keycloakAdminPath "{ \"username\": \"admin\", \"password\": \"operator-managed\" }\n"
  writeProjectConfigFile keycloakDbPath "{ \"username\": \"keycloak\", \"password\": \"operator-managed\" }\n"
  pure manifestPath

-- | Render the host secrets manifest. The manifest names the *paths* at
-- which credential JSON lives; the daemon reads each named file at startup.
hostSecretsManifest :: FilePath -> FilePath -> FilePath -> String
hostSecretsManifest minioPath keycloakAdminPath keycloakDbPath =
  unlines
    [ "let MinioCredentials = { credentialsPath : Text }",
      "let KeycloakAdminCredentials = { credentialsPath : Text }",
      "let KeycloakDbCredentials = { credentialsPath : Text }",
      "in  { minio = { credentialsPath = " <> show minioPath <> " }",
      "    , keycloakAdmin = { credentialsPath = " <> show keycloakAdminPath <> " }",
      "    , keycloakDb = { credentialsPath = " <> show keycloakDbPath <> " }",
      "    }"
    ]

ignoreIo :: IO () -> IO ()
ignoreIo action = action `catch` ignoreIOException

ignoreIOException :: IOException -> IO ()
ignoreIOException _ = pure ()

renderGeneratedDemoConfig :: Paths -> RuntimeMode -> Bool -> InferenceMemoryBudget -> ByteString.ByteString
renderGeneratedDemoConfig paths runtimeMode demoUiEnabledValue =
  renderGeneratedDemoConfigPayload paths runtimeMode demoUiEnabledValue (defaultDaemonRoleForMaterializedFile paths runtimeMode)

renderGeneratedDemoConfigPayload :: Paths -> RuntimeMode -> Bool -> DaemonRole -> InferenceMemoryBudget -> ByteString.ByteString
renderGeneratedDemoConfigPayload paths runtimeMode demoUiEnabledValue daemonRole =
  renderGeneratedDemoConfigPayloadWithModels paths runtimeMode demoUiEnabledValue daemonRole (catalogForMode runtimeMode)

-- | Phase 8 Sprint 8.5: render a substrate payload with an explicit model set.
-- @cluster up@ publication and @infernix init@ / the test harness use the full
-- demo catalog ('catalogForMode'); the image-baked config passes @[]@ so
-- @docker run --rm@ never stages weights and the ConfigMap-mounted config is the
-- source of truth at deploy.
renderGeneratedDemoConfigPayloadWithModels :: Paths -> RuntimeMode -> Bool -> DaemonRole -> [ModelDescriptor] -> InferenceMemoryBudget -> ByteString.ByteString
renderGeneratedDemoConfigPayloadWithModels paths runtimeMode demoUiEnabledValue daemonRole modelSet budget =
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
            webappDaemon = webappDaemonConfig runtimeMode,
            engineDaemons = engineDaemonConfigs runtimeMode,
            enginePools = enginePoolsForMode runtimeMode,
            engineMembers = engineMembersForMode runtimeMode,
            requestTopics = requestTopicsForMode runtimeMode,
            resultTopic = resultTopicForMode runtimeMode,
            modelsBucket = defaultModelsBucket,
            modelBootstrapTopic = defaultModelBootstrapTopic,
            engines = engineBindingsForMode runtimeMode,
            models = modelSet,
            inferenceMemoryBudget = budget
          }
    )

-- | Phase 8 Sprint 8.5: materialize the image-baked substrate config with an
-- empty model set. Used by the Dockerfile so a bare @docker run --rm@ image
-- carries no model catalog; the ConfigMap-mounted config supplies the real set
-- at deploy.
materializeEmptyModelsDemoConfigFile :: Paths -> RuntimeMode -> Bool -> IO FilePath
materializeEmptyModelsDemoConfigFile paths runtimeMode demoUiEnabledValue = do
  budget <- resolveInferenceMemoryBudget paths runtimeMode
  let filePath = Config.generatedDemoConfigPath paths
      payload =
        renderGeneratedDemoConfigPayloadWithModels
          paths
          runtimeMode
          demoUiEnabledValue
          (defaultDaemonRoleForMaterializedFile paths runtimeMode)
          []
          budget
  writeProjectConfigFile filePath payload
  pure filePath

defaultDaemonRoleForMaterializedFile :: Paths -> RuntimeMode -> DaemonRole
defaultDaemonRoleForMaterializedFile paths runtimeMode =
  case (Config.controlPlaneContext paths, runtimeMode) of
    (Config.HostNative, AppleSilicon) -> Engine
    _ -> Coordinator

-- | Phase 4 Sprint 4.27 — resolve the per-substrate inference-memory budget
-- at materialization time.
--
-- * @apple-silicon@: the on-host engine runs host-native outside the colima
--   VM, so the budget is host physical RAM (@sysctl -n hw.memsize@) minus the
--   colima VM pledge (@colima list --json@) minus a host reserve for the OS
--   and control-plane binary. Any discovery failure falls back to the
--   conservative 'appleFallbackInferenceRamBudgetMib' (biased low so a failure
--   rejects large models rather than risking an OS OOM-kill). A negative
--   computed value becomes an enforced @0 MiB@ budget, never an implicit
--   disabled guard.
-- * @linux-cpu@: admission uses the engine pod memory limit.
-- * @linux-gpu@: admission uses the configured GPU VRAM budget.
resolveInferenceMemoryBudget :: Paths -> RuntimeMode -> IO InferenceMemoryBudget
resolveInferenceMemoryBudget paths runtimeMode =
  case runtimeMode of
    AppleSilicon -> resolveAppleInferenceRamBudgetMib paths
    LinuxCpu ->
      pure
        EnforcedMemoryBudget
          { memoryBudgetResource = PodRam,
            memoryBudgetSource = "cluster-engine-pod-memory-limit",
            memoryBudgetAvailableMib = linuxEngineInferenceRamBudgetMib
          }
    LinuxGpu ->
      pure
        EnforcedMemoryBudget
          { memoryBudgetResource = GpuVram,
            memoryBudgetSource = "linux-gpu-vram-budget",
            memoryBudgetAvailableMib = linuxEngineInferenceRamBudgetMib
          }

-- | Host reserve (MiB) held back from the Apple inference budget for the OS,
-- the host-native control-plane binary, and the Node/Playwright surface that
-- runs during routed E2E.
appleHostReserveMib :: Int
appleHostReserveMib = 3072

resolveAppleInferenceRamBudgetMib :: Paths -> IO InferenceMemoryBudget
resolveAppleInferenceRamBudgetMib paths = do
  resolved <-
    try
      ( do
          hostConfig <- HostConfig.decodeHostConfigFile (Config.hostConfigPath paths)
          physicalMib <- appleHostPhysicalRamMib hostConfig
          colimaMib <- appleColimaPledgeMib
          pure (max 0 (physicalMib - colimaMib - appleHostReserveMib))
      )
  pure
    EnforcedMemoryBudget
      { memoryBudgetResource = UnifiedHostRam,
        memoryBudgetSource = "host-physical-minus-colima-reserve",
        memoryBudgetAvailableMib =
          case resolved :: Either SomeException Int of
            Right budgetMib -> budgetMib
            Left _ -> appleFallbackInferenceRamBudgetMib
      }

appleHostPhysicalRamMib :: HostConfig -> IO Int
appleHostPhysicalRamMib hostConfig = do
  output <- HostTools.readHostTool hostConfig HostTools.HostSysctl ["-n", "hw.memsize"] ""
  case readMaybeInt (filter (not . isSpace) output) of
    Just bytes -> pure (bytes `div` bytesPerMib)
    Nothing -> ioError (userError ("could not parse hw.memsize from sysctl output: " <> output))

-- | The colima VM's pledged memory (MiB). Reads @colima list --json@ (one JSON
-- object per line, via the bootstrap-adjacent fixed candidate path — colima is
-- read, never managed, and is not a manifest-owned tool) and takes the running
-- profile's @memory@ (bytes), preferring the @default@ profile. When colima is
-- unavailable or no profile is running (no colima VM), the pledge is zero and
-- the whole host RAM is available to inference — so colima discovery is
-- non-fatal and never forces the resolver onto its low fallback.
appleColimaPledgeMib :: IO Int
appleColimaPledgeMib = do
  result <- try (HostTools.readHostToolFallback HostTools.HostColima ["list", "--json"] "")
  case result :: Either SomeException (Maybe String) of
    Right (Just output) -> pure (colimaPledgeMibFromJsonLines output)
    _ -> pure 0

colimaPledgeMibFromJsonLines :: String -> Int
colimaPledgeMibFromJsonLines output =
  let profiles = mapMaybe decodeProfileLine (lines output)
      running = filter ((== "Running") . colimaStatus) profiles
      preferred = filter ((== "default") . colimaName) running
      chosen = listToMaybe (preferred <> running)
   in maybe 0 (\profile -> fromInteger (colimaMemory profile `div` toInteger bytesPerMib)) chosen
  where
    decodeProfileLine line =
      Aeson.decodeStrict (ByteStringChar8.pack line) :: Maybe ColimaProfile

data ColimaProfile = ColimaProfile
  { colimaName :: Text,
    colimaStatus :: Text,
    colimaMemory :: Integer
  }

instance Aeson.FromJSON ColimaProfile where
  parseJSON =
    Aeson.withObject "ColimaProfile" $ \value ->
      ColimaProfile
        <$> value Aeson..: "name"
        <*> value Aeson..: "status"
        <*> value Aeson..: "memory"

bytesPerMib :: Int
bytesPerMib = 1048576

readMaybeInt :: String -> Maybe Int
readMaybeInt text = case reads text of
  [(value, "")] -> Just value
  _ -> Nothing

coordinatorDaemonConfig :: RuntimeMode -> DaemonConfig
coordinatorDaemonConfig runtimeMode =
  DaemonConfig
    { daemonConfigRole = Coordinator,
      daemonConfigLocation = "cluster-pod",
      daemonConfigMemberId = Nothing,
      daemonConfigRequestTopics = requestTopicsForMode runtimeMode,
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigPulsarConnectionMode = ConfiguredTransport,
      daemonConfigConsumerSubscriptionType = Just ConsumerShared
    }

webappDaemonConfig :: RuntimeMode -> DaemonConfig
webappDaemonConfig runtimeMode =
  DaemonConfig
    { daemonConfigRole = Webapp,
      daemonConfigLocation = "cluster-pod",
      daemonConfigMemberId = Nothing,
      daemonConfigRequestTopics = requestTopicsForMode runtimeMode,
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigPulsarConnectionMode = ConfiguredTransport,
      daemonConfigConsumerSubscriptionType = Just ConsumerShared
    }

-- | Phase 7 Sprint 7.7: the engine role is deployed on every supported
-- substrate. On Apple silicon it runs as the on-host daemon (location
-- @control-plane-host@, Pulsar transport discovered through the
-- publication edge). On Linux substrates it runs as the in-cluster
-- @infernix-engine@ Deployment (location @cluster-pod@, Pulsar transport
-- from the mounted cluster config). In every case the engine consumes
-- the derived pool/model topics assigned to its stable member id.
engineDaemonConfigs :: RuntimeMode -> [DaemonConfig]
engineDaemonConfigs runtimeMode =
  map (engineDaemonConfigForMember runtimeMode pools) members
  where
    pools = enginePoolsForMode runtimeMode
    members = engineMembersForMode runtimeMode

engineDaemonConfigForMember :: RuntimeMode -> [EnginePool] -> EngineMember -> DaemonConfig
engineDaemonConfigForMember runtimeMode pools member =
  DaemonConfig
    { daemonConfigRole = Engine,
      daemonConfigLocation = engineMemberLocation member,
      daemonConfigMemberId = Just (engineMemberId member),
      daemonConfigRequestTopics = engineMemberRequestTopics runtimeMode pools member,
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigPulsarConnectionMode =
        if runtimeMode == AppleSilicon
          then PublicationEdgeAutoDiscovery
          else ConfiguredTransport,
      daemonConfigConsumerSubscriptionType = Just ConsumerShared
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

validateDemoConfigStrictModels :: DemoConfig -> Either String DemoConfig
validateDemoConfigStrictModels = validateDemoConfig False

validateDemoConfigAllowingEmptyModels :: DemoConfig -> Either String DemoConfig
validateDemoConfigAllowingEmptyModels = validateDemoConfig True

validateDemoConfig :: Bool -> DemoConfig -> Either String DemoConfig
validateDemoConfig allowEmptyModels demoConfig
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
  | null (models demoConfig) && not allowEmptyModels =
      Left "models must not be empty"
  | any invalidRequestShape (models demoConfig) =
      Left "every model must declare at least one request field"
  | invalidActiveDaemonRole =
      Left "active daemon role must match coordinator, webapp, or engine metadata"
  | daemonConfigRole (coordinatorDaemon demoConfig) /= Coordinator =
      Left "coordinator metadata must declare the coordinator role"
  | daemonConfigRole (webappDaemon demoConfig) /= Webapp =
      Left "webapp metadata must declare the webapp role"
  | invalidDaemonConfig (coordinatorDaemon demoConfig) =
      Left "coordinator metadata must declare role, location, request topics, and result topic"
  | invalidDaemonConfig (webappDaemon demoConfig) =
      Left "webapp metadata must declare role, location, request topics, and result topic"
  | null (enginePools demoConfig) =
      Left "enginePools must not be empty"
  | null (engineMembers demoConfig) =
      Left "engineMembers must not be empty"
  | duplicatePoolIds /= [] =
      Left ("duplicate engine pool ids detected: " <> intercalate ", " duplicatePoolIds)
  | duplicateMemberIds /= [] =
      Left ("duplicate engine member ids detected: " <> intercalate ", " duplicateMemberIds)
  | invalidPoolIds /= [] =
      Left ("invalid engine pool ids detected: " <> intercalate ", " invalidPoolIds)
  | invalidMemberIds /= [] =
      Left ("invalid engine member ids detected: " <> intercalate ", " invalidMemberIds)
  | emptyPoolModelIds /= [] =
      Left ("engine pools must declare at least one model id: " <> intercalate ", " emptyPoolModelIds)
  | emptyPoolMemberIds /= [] =
      Left ("engine pools must declare at least one member id: " <> intercalate ", " emptyPoolMemberIds)
  | emptyMemberPoolIds /= [] =
      Left ("engine members must declare at least one pool id: " <> intercalate ", " emptyMemberPoolIds)
  | wrongRuntimePoolIds /= [] =
      Left ("engine pools use the wrong runtimeMode: " <> intercalate ", " wrongRuntimePoolIds)
  | wrongRuntimeMemberIds /= [] =
      Left ("engine members use the wrong runtimeMode: " <> intercalate ", " wrongRuntimeMemberIds)
  | ambiguousPoolModelIds /= [] =
      Left ("engine pool model ownership is ambiguous: " <> intercalate ", " ambiguousPoolModelIds)
  | unknownPoolModelIds /= [] && not bootstrapEmptyModels =
      Left ("engine pools reference unknown model ids: " <> intercalate ", " unknownPoolModelIds)
  | unknownPoolMemberIds /= [] =
      Left ("engine pools reference unknown member ids: " <> intercalate ", " unknownPoolMemberIds)
  | unknownMemberPoolIds /= [] =
      Left ("engine members reference unknown pool ids: " <> intercalate ", " unknownMemberPoolIds)
  | poolMemberLinksMissingFromMembers /= [] =
      Left ("engine pool member links must be bidirectional: " <> intercalate ", " poolMemberLinksMissingFromMembers)
  | memberPoolLinksMissingFromPools /= [] =
      Left ("engine member pool links must be bidirectional: " <> intercalate ", " memberPoolLinksMissingFromPools)
  | failoverPoolIds /= [] =
      Left ("engine pools must not use Failover subscriptions: " <> intercalate ", " failoverPoolIds)
  | invalidInflightPoolIds /= [] =
      Left ("engine pools must set maxInflightPerMember greater than zero: " <> intercalate ", " invalidInflightPoolIds)
  | unroutableModelIds /= [] =
      Left ("models without eligible engine members: " <> intercalate ", " unroutableModelIds)
  | null (engineDaemons demoConfig) =
      Left "engine metadata must not be empty"
  | any invalidDaemonConfig (engineDaemons demoConfig) =
      Left "every engine metadata entry must declare role, location, request topics, and result topic"
  | engineDaemonsWithoutMembers /= [] =
      Left ("engine daemons reference unknown member ids: " <> intercalate ", " engineDaemonsWithoutMembers)
  | configRuntimeMode demoConfig == AppleSilicon && isNothing primaryEngineDaemon =
      Left "apple-silicon configs must include engine metadata"
  | configRuntimeMode demoConfig == AppleSilicon && maybe True (null . daemonConfigRequestTopics) primaryEngineDaemon =
      Left "apple-silicon engine metadata must consume assigned pool topics"
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
    bootstrapEmptyModels = allowEmptyModels && null (models demoConfig)
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
        && activeDaemonRole demoConfig
          /= daemonConfigRole (webappDaemon demoConfig)
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
    duplicatePoolIds = duplicates (map (Text.unpack . enginePoolId) (enginePools demoConfig))
    duplicateMemberIds = duplicates (map (Text.unpack . engineMemberId) (engineMembers demoConfig))
    knownModelIds = map modelId (models demoConfig)
    knownPoolIds = map enginePoolId (enginePools demoConfig)
    knownMemberIds = map engineMemberId (engineMembers demoConfig)
    invalidPoolIds =
      [ Text.unpack (enginePoolId pool)
      | pool <- enginePools demoConfig,
        invalidRoutingId (enginePoolId pool)
      ]
    invalidMemberIds =
      [ Text.unpack (engineMemberId member)
      | member <- engineMembers demoConfig,
        invalidRoutingId (engineMemberId member)
      ]
    emptyPoolModelIds =
      [ Text.unpack (enginePoolId pool)
      | pool <- enginePools demoConfig,
        null (enginePoolModelIds pool)
      ]
    emptyPoolMemberIds =
      [ Text.unpack (enginePoolId pool)
      | pool <- enginePools demoConfig,
        null (enginePoolMemberIds pool)
      ]
    emptyMemberPoolIds =
      [ Text.unpack (engineMemberId member)
      | member <- engineMembers demoConfig,
        null (engineMemberPoolIds member)
      ]
    wrongRuntimePoolIds =
      [ Text.unpack (enginePoolId pool)
      | pool <- enginePools demoConfig,
        enginePoolRuntimeMode pool /= configRuntimeMode demoConfig
      ]
    wrongRuntimeMemberIds =
      [ Text.unpack (engineMemberId member)
      | member <- engineMembers demoConfig,
        engineMemberRuntimeMode member /= configRuntimeMode demoConfig
      ]
    ambiguousPoolModelIds =
      duplicates
        [ Text.unpack modelIdValue
        | pool <- enginePools demoConfig,
          modelIdValue <- enginePoolModelIds pool
        ]
    unknownPoolModelIds =
      nub
        [ Text.unpack modelIdValue
        | pool <- enginePools demoConfig,
          modelIdValue <- enginePoolModelIds pool,
          modelIdValue `notElem` knownModelIds
        ]
    unknownPoolMemberIds =
      nub
        [ Text.unpack memberId
        | pool <- enginePools demoConfig,
          memberId <- enginePoolMemberIds pool,
          memberId `notElem` knownMemberIds
        ]
    unknownMemberPoolIds =
      nub
        [ Text.unpack poolId
        | member <- engineMembers demoConfig,
          poolId <- engineMemberPoolIds member,
          poolId `notElem` knownPoolIds
        ]
    poolMemberLinksMissingFromMembers =
      [ Text.unpack (enginePoolId pool) <> "/" <> Text.unpack memberId
      | pool <- enginePools demoConfig,
        memberId <- enginePoolMemberIds pool,
        memberId `elem` knownMemberIds,
        not (memberDeclaresPool memberId (enginePoolId pool))
      ]
    memberPoolLinksMissingFromPools =
      [ Text.unpack (engineMemberId member) <> "/" <> Text.unpack poolId
      | member <- engineMembers demoConfig,
        poolId <- engineMemberPoolIds member,
        poolId `elem` knownPoolIds,
        not (poolDeclaresMember poolId (engineMemberId member))
      ]
    failoverPoolIds =
      [ Text.unpack (enginePoolId pool)
      | pool <- enginePools demoConfig,
        enginePoolSubscriptionType pool == ConsumerFailover
      ]
    invalidInflightPoolIds =
      [ Text.unpack (enginePoolId pool)
      | pool <- enginePools demoConfig,
        enginePoolMaxInflightPerMember pool <= 0
      ]
    unroutableModelIds =
      [ Text.unpack modelIdValue
      | modelIdValue <- knownModelIds,
        not (modelHasEligibleMember modelIdValue)
      ]
    engineDaemonsWithoutMembers =
      nub
        [ Text.unpack memberId
        | daemonConfig <- engineDaemons demoConfig,
          Just memberId <- [daemonConfigMemberId daemonConfig],
          memberId `notElem` knownMemberIds
        ]
    modelHasEligibleMember modelIdValue =
      any (poolHasEligibleMember modelIdValue) (enginePools demoConfig)
    poolHasEligibleMember modelIdValue pool =
      modelIdValue `elem` enginePoolModelIds pool
        && any (memberParticipatesInPool pool) (engineMembers demoConfig)
    memberParticipatesInPool pool member =
      engineMemberId member `elem` enginePoolMemberIds pool
        && enginePoolId pool `elem` engineMemberPoolIds member
    memberDeclaresPool memberId poolId =
      any
        ( \member ->
            engineMemberId member == memberId
              && poolId `elem` engineMemberPoolIds member
        )
        (engineMembers demoConfig)
    poolDeclaresMember poolId memberId =
      any
        ( \pool ->
            enginePoolId pool == poolId
              && memberId `elem` enginePoolMemberIds pool
        )
        (enginePools demoConfig)
    invalidRoutingId value =
      Text.null stripped
        || "persistent://" `Text.isInfixOf` stripped
        || "/" `Text.isInfixOf` stripped
        || ":" `Text.isInfixOf` stripped
        || Text.any (== ' ') stripped
      where
        stripped = Text.strip value

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
