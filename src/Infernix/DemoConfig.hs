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
  ( catalogForMode,
    encodeDemoConfig,
    engineBindingsForMode,
    engineMemberRequestTopics,
    engineMembersForMode,
    enginePoolsForMode,
    hostBatchTopicForMode,
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
            enginePools = enginePoolsForMode runtimeMode,
            engineMembers = engineMembersForMode runtimeMode,
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
      daemonConfigMemberId = Nothing,
      daemonConfigRequestTopics = requestTopicsForMode runtimeMode,
      daemonConfigResultTopic = resultTopicForMode runtimeMode,
      daemonConfigHostBatchTopic = hostBatchTopicForMode runtimeMode,
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
      daemonConfigHostBatchTopic = Nothing,
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
  | unknownPoolModelIds /= [] =
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
  | engineDaemonsWithoutMembers /= [] =
      Left ("engine daemons reference unknown member ids: " <> intercalate ", " engineDaemonsWithoutMembers)
  | configRuntimeMode demoConfig == AppleSilicon && isNothing primaryEngineDaemon =
      Left "apple-silicon configs must include engine metadata"
  | configRuntimeMode demoConfig == AppleSilicon && isNothing (daemonConfigHostBatchTopic (coordinatorDaemon demoConfig)) =
      Left "apple-silicon coordinator metadata must declare a legacy handoff topic fallback"
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
