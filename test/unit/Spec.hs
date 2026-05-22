{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (finally, try)
import Crypto.Hash.Algorithms qualified
import Crypto.PubKey.RSA qualified
import Crypto.PubKey.RSA.PKCS15 qualified
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Base64.URL qualified
import Data.ByteString.Lazy qualified as Lazy
import Data.List (find, isInfixOf, nub)
import Data.Map.Strict qualified as Map
import Data.Map.Strict qualified as MapStrict
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (getCurrentTime)
import Data.Time.Clock.POSIX qualified
import Infernix.Auth.Jwt qualified as Jwt
import Infernix.Bootstrap.Models qualified as BootstrapModels
import Infernix.Bridge.Result qualified as ResultBridge
import Infernix.CLI (writeGeneratedPursContracts)
import Infernix.Cluster (writeGeneratedKindConfig)
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages
  ( PublishedImage,
    contentAddressTagFromInspectPayload,
    dockerHubMirrorRef,
    normalizeRepositoryPath,
    prioritizePublishableImages,
    writeHarborOverridesFile,
  )
import Infernix.CommandRegistry
  ( Command (..),
    parseCommand,
    renderCliReferenceCommandsSection,
    renderCliSurfaceFamiliesSection,
  )
import Infernix.Config
import Infernix.Conversation.Event qualified as ConversationEvent
import Infernix.Conversation.Hash qualified as ConversationHash
import Infernix.Conversation.Idempotency qualified as ConversationIdempotency
import Infernix.Conversation.Reducer qualified as ConversationReducer
import Infernix.Conversation.Topic qualified as ConversationTopic
import Infernix.Demo.Auth qualified as DemoAuth
import Infernix.Demo.Bootstrap qualified as DemoBootstrap
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Dispatch.SingleFlight qualified as Dispatch
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.HostPrereqs (appleHostRequirementIds, colimaProfileSummary, decodeDefaultColimaProfileOutput)
import Infernix.Models
import Infernix.Objects.Layout qualified as ObjLayout
import Infernix.Objects.Presigned qualified as ObjPresigned
import Infernix.Routes
  ( renderChartRouteRegistryCommentSection,
    renderEdgeRoutingInventorySection,
    renderReadmeRouteSummarySection,
  )
import Infernix.Runtime
import Infernix.Runtime.Pulsar (runProductionDaemon)
import Infernix.Runtime.Worker (engineCommandOverrideEnvironmentName)
import Infernix.Topic.Drafts qualified as TopicDrafts
import Infernix.Topic.Metadata qualified as TopicMetadata
import Infernix.Types
import Infernix.Web.Contracts qualified as Contracts
import System.Directory
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO qualified
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Timeout (timeout)

main :: IO ()
main = do
  unitTestRoot <- testRootPath "unit"
  assert (length (catalogForMode AppleSilicon) == 15) "apple-silicon catalog count matches the matrix"
  assert (length (catalogForMode LinuxCpu) == 12) "linux-cpu catalog count matches the matrix"
  assert (length (catalogForMode LinuxGpu) == 16) "linux-gpu catalog count matches the matrix"
  assert
    (expectedDaemonLocationForRuntime AppleSilicon == "cluster-pod")
    "apple-silicon publication reports the cluster service daemon location"
  assert
    (expectedInferenceExecutorLocationForRuntime AppleSilicon == "control-plane-host")
    "apple-silicon publication reports the host-native inference executor location"
  assert
    (expectedDaemonLocationForRuntime LinuxCpu == "cluster-pod")
    "linux-cpu publication reports the cluster-resident service daemon location"
  assert
    (expectedDaemonLocationForRuntime LinuxGpu == "cluster-pod")
    "linux-gpu publication reports the cluster-resident service daemon location"
  assert
    (expectedInferenceDispatchModeForRuntime AppleSilicon == "pulsar-bridge-to-host-daemon")
    "apple-silicon publication reports the host-daemon dispatch mode"
  assert
    (expectedInferenceDispatchModeForRuntime LinuxCpu == "pulsar-bridge-to-cluster-daemon")
    "linux-cpu publication reports the cluster-daemon dispatch mode"
  assert
    (expectedInferenceDispatchModeForRuntime LinuxGpu == "pulsar-bridge-to-cluster-daemon")
    "linux-gpu publication reports the cluster-daemon dispatch mode"
  assert
    (length (platformClaimsForRuntime AppleSilicon) == 1)
    "apple-silicon retains the cluster service PVC claim"
  assert
    (length (platformClaimsForRuntime LinuxCpu) == 1 && length (platformClaimsForRuntime LinuxGpu) == 1)
    "linux runtime lanes retain the cluster service PVC claim"
  assert (isJust (findModel LinuxGpu "llm-qwen25-awq")) "linux-gpu includes the AWQ row"
  assert (isNothing (findModel AppleSilicon "llm-qwen25-awq")) "apple-silicon omits unsupported AWQ rows"
  assert
    (parseCommand ["cluster", "status"] == Right ClusterStatusCommand)
    "the structured command registry parses cluster commands without a runtime-mode prefix"
  assert
    (parseCommand ["internal", "discover", "images", "rendered-chart.yaml"] == Right (InternalDiscoverImagesCommand "rendered-chart.yaml"))
    "the structured command registry parses internal discovery commands from the same definition used by the docs"
  assert
    ( parseCommand ["internal", "materialize-substrate", "linux-cpu", "--demo-ui", "false"]
        == Right (InternalMaterializeSubstrateCommand LinuxCpu False)
    )
    "the structured command registry parses explicit substrate materialization commands"
  assert
    ("### `cluster`" `isInfixOf` renderCliReferenceCommandsSection)
    "the generated CLI reference includes the cluster family heading"
  assert
    ("- `test` - runs the aggregate validation entrypoints" `isInfixOf` renderCliSurfaceFamiliesSection)
    "the generated CLI surface overview includes the test family summary"
  assert
    ("--runtime-mode" `notElem` words renderCliReferenceCommandsSection)
    "the generated CLI reference no longer documents a runtime-mode override"
  assert
    ("`/harbor/api`" `isInfixOf` renderReadmeRouteSummarySection)
    "the README route summary includes the Harbor API prefix from the route registry"
  assert
    ("`/pulsar/ws`" `isInfixOf` renderEdgeRoutingInventorySection)
    "the edge-routing route table includes the Pulsar websocket prefix from the route registry"
  assert
    ("`/minio/s3` -> `infernix-minio:9000`" `isInfixOf` renderChartRouteRegistryCommentSection)
    "the chart route summary includes the MinIO S3 backend from the route registry"
  composeLauncherContents <- readFile "compose.yaml"
  assert
    ("${INFERNIX_COMPOSE_IMAGE:-infernix-linux-cpu:local}" `isInfixOf` composeLauncherContents)
    "compose defaults to the linux-cpu launcher image while allowing image selection"
  assert
    ("${INFERNIX_COMPOSE_SUBSTRATE:-linux-cpu}" `isInfixOf` composeLauncherContents)
    "compose build defaults to the linux-cpu substrate while allowing linux-gpu selection"
  assert
    ("${INFERNIX_COMPOSE_BASE_IMAGE:-ubuntu:24.04}" `isInfixOf` composeLauncherContents)
    "compose build keeps the default CPU base image while allowing the linux-gpu CUDA base image"
  assert
    (appleHostRequirementIds AppleSilicon ClusterUpCommand == ["docker", "colima", "kind", "kubectl", "helm", "node", "python", "poetry"])
    "apple host prerequisite planning includes the full cluster and adapter toolchain for apple-silicon cluster up"
  assert
    (appleHostRequirementIds LinuxCpu TestAllCommand == ["docker", "colima", "kind", "kubectl", "helm", "node"])
    "apple host prerequisite planning skips Poetry when the active runtime mode is linux-cpu"
  assert
    (null (appleHostRequirementIds AppleSilicon DocsCheckCommand))
    "apple host prerequisite planning does not install unrelated tools for docs-only commands"
  defaultColimaProfile <-
    expectRight
      "default Colima profile decode succeeds for newline-delimited multi-profile output"
      ( decodeDefaultColimaProfileOutput
          ( unlines
              [ "{\"name\":\"default\",\"status\":\"Running\",\"arch\":\"aarch64\",\"cpus\":8,\"memory\":25769803776,\"disk\":274877906944,\"runtime\":\"docker\"}",
                "{\"name\":\"bby-amd64\",\"status\":\"Stopped\",\"arch\":\"aarch64\",\"cpus\":4,\"memory\":17179869184,\"disk\":274877906944}"
              ]
          )
      )
  assert
    (colimaProfileSummary defaultColimaProfile == "8 CPU / 24 GiB memory")
    "newline-delimited Colima profile decode keeps the supported default profile details"
  legacyColimaProfile <-
    expectRight
      "legacy single-profile Colima JSON decode remains supported"
      ( decodeDefaultColimaProfileOutput
          "{\"status\":\"Running\",\"cpus\":8,\"memory\":17179869184}"
      )
  assert
    (colimaProfileSummary legacyColimaProfile == "8 CPU / 16 GiB memory")
    "single-profile Colima decode remains compatible with the older payload shape"
  assertUniqueModelIds AppleSilicon
  assertUniqueModelIds LinuxCpu
  assertUniqueModelIds LinuxGpu
  withTestRoot unitTestRoot $ do
    withOptionalEnv "INFERNIX_BUILD_ROOT" Nothing $ do
      paths <- discoverPaths
      ensureRepoLayout paths
      assert
        (controlPlaneContext paths == HostNative)
        "an unset build-root override keeps unit tests on the host-native control-plane context"
      assert
        (generatedKubeconfigPath paths == buildRoot paths </> "infernix.kubeconfig")
        "host-native kubeconfig stays under the build root"
      ensureSupportedRuntimeModeForExecutionContext paths AppleSilicon
      hostNativeLinuxCpuResult <- try (ensureSupportedRuntimeModeForExecutionContext paths LinuxCpu) :: IO (Either IOError ())
      assert
        (either (isInfixOf "Unsupported host-native runtime mode: linux-cpu" . show) (const False) hostNativeLinuxCpuResult)
        "host-native execution rejects the linux-cpu substrate"
      withOptionalEnv "INFERNIX_BUILD_ROOT" (Just "/opt/build/infernix") $ do
        outerPaths <- discoverPaths
        assert
          (controlPlaneContext outerPaths == OuterContainer)
          "setting a non-host build root selects the outer-container control-plane context"
        assert
          (generatedKubeconfigPath outerPaths == runtimeRoot outerPaths </> "infernix.kubeconfig")
          "outer-container kubeconfig persists under the durable runtime root"
        ensureSupportedRuntimeModeForExecutionContext outerPaths LinuxCpu
        outerContainerAppleResult <- try (ensureSupportedRuntimeModeForExecutionContext outerPaths AppleSilicon) :: IO (Either IOError ())
        assert
          (either (isInfixOf "Unsupported outer-container runtime mode: apple-silicon" . show) (const False) outerContainerAppleResult)
          "outer-container execution rejects the apple-silicon substrate"
      now <- getCurrentTime
      let legacyOnlyResult =
            InferenceResult
              { requestId = "legacy-only-request",
                resultModelId = "llm-qwen25-safetensors",
                resultMatrixRowId = "apple-qwen25-safetensors",
                resultRuntimeMode = AppleSilicon,
                resultSelectedEngine = "transformers-python",
                status = "completed",
                payload =
                  ResultPayload
                    { inlineOutput = Just "legacy output",
                      objectRef = Nothing
                    },
                createdAt = now
              }
          legacyResultPath = resultsRoot paths </> "legacy-only-request.state"
      createDirectoryIfMissing True (resultsRoot paths)
      writeFile legacyResultPath (show legacyOnlyResult)
      legacyOnlyReload <- loadInferenceResult paths "legacy-only-request"
      assert
        (isNothing legacyOnlyReload)
        "inference result loading ignores retired .state-only files"

      let legacyManifestDirectory = objectStoreRoot paths </> "manifests" </> "linux-cpu" </> "legacy-model"
          legacyCacheManifest =
            CacheManifest
              { cacheRuntimeMode = LinuxCpu,
                cacheModelId = "legacy-model",
                cacheSelectedEngine = "llama-cpp",
                cacheDurableSourceUri = "s3://infernix-runtime/artifacts/linux-cpu/legacy-model/bundle.json",
                cacheCacheKey = "default"
              }
      createDirectoryIfMissing True legacyManifestDirectory
      writeFile (legacyManifestDirectory </> "default.state") (show legacyCacheManifest)
      legacyCacheManifests <- listCacheManifests paths LinuxCpu
      assert
        (null legacyCacheManifests)
        "cache manifest loading ignores retired default.state files"

      let contractsOutputRoot = buildRoot paths </> "contracts-output"
          legacyContractsPath = contractsOutputRoot </> "Infernix" </> "Web" </> "Contracts.purs"
          generatedContractsPath = contractsOutputRoot </> "Generated" </> "Contracts.purs"
      createDirectoryIfMissing True (contractsOutputRoot </> "Infernix" </> "Web")
      writeFile legacyContractsPath "legacy generated contracts\n"
      writeGeneratedPursContracts AppleSilicon contractsOutputRoot
      generatedContractsExist <- doesFileExist generatedContractsPath
      legacyContractsContents <- readFile legacyContractsPath
      assert generatedContractsExist "PureScript contract generation writes the supported Generated path"
      assert
        (legacyContractsContents == "legacy generated contracts\n")
        "PureScript contract generation leaves the retired handwritten output path untouched"
      firstGeneratedContents <- System.IO.readFile' generatedContractsPath
      writeGeneratedPursContracts AppleSilicon contractsOutputRoot
      secondGeneratedContents <- System.IO.readFile' generatedContractsPath
      assert
        (firstGeneratedContents == secondGeneratedContents)
        "PureScript contract generation is byte-identical across repeated invocations"
      assert
        ("data ConversationEvent" `isInfixOf` firstGeneratedContents)
        "PureScript contract generation includes the Phase 7 ConversationEvent sum type"
      assert
        ("newtype UserId" `isInfixOf` firstGeneratedContents)
        "PureScript contract generation includes the Phase 7 UserId newtype"
      assert
        ("data WsClientMessage" `isInfixOf` firstGeneratedContents)
        "PureScript contract generation includes the Phase 7 WsClientMessage envelope"
      assert
        ("data WsServerMessage" `isInfixOf` firstGeneratedContents)
        "PureScript contract generation includes the Phase 7 WsServerMessage envelope"
      assert
        ("newtype ArtifactMimeType" `isInfixOf` firstGeneratedContents)
        "PureScript contract generation includes the Phase 7 ArtifactMimeType newtype"
      assertPhase7JsonRoundtrips
      assertConversationPrimitives
      assertCompactedMetadataPatterns
      assertSingleFlightDispatcher
      assertJwtValidation
      assertObjectsLayoutAndPresigning
      assertResultBridgeAndBatchTopics
      assertDemoAuthRealm
      assertBootstrapModels
      assertDemoBucketBootstrap

      let legacyRegistryNamespace = repoRoot paths </> ".build" </> "kind" </> "registry" </> "localhost:30001"
      createDirectoryIfMissing True legacyRegistryNamespace
      writeFile (legacyRegistryNamespace </> "hosts.toml") "legacy helper registry\n"
      _ <- writeGeneratedKindConfig paths LinuxCpu 30090
      legacyRegistryNamespaceExists <- doesDirectoryExist legacyRegistryNamespace
      legacyRegistryHostsContents <- readFile (legacyRegistryNamespace </> "hosts.toml")
      assert
        legacyRegistryNamespaceExists
        "kind registry-host generation leaves the retired helper-registry namespace untouched"
      assert
        (legacyRegistryHostsContents == "legacy helper registry\n")
        "kind registry-host generation does not rewrite the retired helper-registry namespace"
      withOptionalEnv "INFERNIX_BUILD_ROOT" (Just (unitTestRoot </> "outer-container" </> "build")) $
        withOptionalEnv "INFERNIX_HOST_REPO_ROOT" (Just "/host/infernix") $
          withOptionalEnv "INFERNIX_HOST_KIND_ROOT" Nothing $ do
            outerPaths <- discoverPaths
            ensureRepoLayout outerPaths
            generatedLinuxGpuKindConfigPath <- writeGeneratedKindConfig outerPaths LinuxGpu 30090
            generatedLinuxGpuKindConfig <- readFile generatedLinuxGpuKindConfigPath
            assert
              ("hostPath: /host/infernix/.build/test-unit/.data/kind/linux-gpu" `isInfixOf` generatedLinuxGpuKindConfig)
              "linux-gpu outer-container Kind config mounts host-resolved retained cluster data"
            assert
              ("containerPath: /var/infernix-data" `isInfixOf` generatedLinuxGpuKindConfig)
              "linux-gpu outer-container Kind config exposes retained data at the node PV root"
            assert
              ("hostPath: /host/infernix/.build/kind/registry" `isInfixOf` generatedLinuxGpuKindConfig)
              "linux-gpu outer-container Kind config mounts host-resolved registry hosts"
            assert
              ("containerPath: /var/run/nvidia-container-devices/all" `isInfixOf` generatedLinuxGpuKindConfig)
              "linux-gpu outer-container Kind config keeps the NVIDIA worker device mount"
      let demoConfig =
            DemoConfig
              { configRuntimeMode = LinuxCpu,
                configEdgePort = 0,
                configMapName = "infernix-demo-config",
                generatedPath = "./.build/infernix-substrate.dhall",
                mountedPath = "/opt/build/infernix-substrate.dhall",
                demoUiEnabled = True,
                activeDaemonRole = ClusterDaemon,
                clusterDaemon =
                  DaemonConfig
                    { daemonConfigRole = ClusterDaemon,
                      daemonConfigLocation = "cluster-pod",
                      daemonConfigRequestTopics = requestTopicsForMode LinuxCpu,
                      daemonConfigResultTopic = resultTopicForMode LinuxCpu,
                      daemonConfigHostBatchTopic = Nothing,
                      daemonConfigPulsarConnectionMode = ConfiguredTransport
                    },
                hostDaemon = Nothing,
                requestTopics = requestTopicsForMode LinuxCpu,
                resultTopic = resultTopicForMode LinuxCpu,
                engines = engineBindingsForMode LinuxCpu,
                models = catalogForMode LinuxCpu
              }
          demoConfigPath = buildRoot paths </> "demo-config-test.dhall"
      createDirectoryIfMissing True (buildRoot paths)
      Lazy.writeFile demoConfigPath (encodeDemoConfig demoConfig)
      demoConfigContents <- readFile demoConfigPath
      assert
        ("runtimeMode = \"linux-cpu\"" `isInfixOf` demoConfigContents)
        "generated substrate materialization writes Dhall record fields"
      assert
        (not ("\"runtimeMode\":" `isInfixOf` demoConfigContents))
        "generated substrate materialization no longer writes banner-prefixed JSON"
      decodedConfig <- decodeDemoConfigFile demoConfigPath
      assert (configRuntimeMode decodedConfig == LinuxCpu) "demo-config decode preserves runtime mode"
      assert (demoUiEnabled decodedConfig) "demo-config decode preserves the demo UI flag"
      assert (activeDaemonRole decodedConfig == ClusterDaemon) "demo-config decode preserves the active daemon role"
      assert (daemonConfigLocation (clusterDaemon decodedConfig) == "cluster-pod") "demo-config decode preserves cluster daemon metadata"
      assert (isNothing (hostDaemon decodedConfig)) "linux demo-config decode omits host daemon metadata"
      assert (requestTopics decodedConfig == requestTopicsForMode LinuxCpu) "demo-config decode preserves request topics"
      assert (resultTopic decodedConfig == resultTopicForMode LinuxCpu) "demo-config decode preserves the result topic"
      assert (engines decodedConfig == engineBindingsForMode LinuxCpu) "demo-config decode preserves engine bindings"
      assert (length (models decodedConfig) == length (catalogForMode LinuxCpu)) "demo-config decode preserves the model list"
      let appleHostConfig =
            DemoConfig
              { configRuntimeMode = AppleSilicon,
                configEdgePort = 0,
                configMapName = "infernix-demo-config",
                generatedPath = "./.build/infernix-substrate.dhall",
                mountedPath = "/opt/build/infernix-substrate.dhall",
                demoUiEnabled = True,
                activeDaemonRole = HostDaemon,
                clusterDaemon =
                  DaemonConfig
                    { daemonConfigRole = ClusterDaemon,
                      daemonConfigLocation = "cluster-pod",
                      daemonConfigRequestTopics = requestTopicsForMode AppleSilicon,
                      daemonConfigResultTopic = resultTopicForMode AppleSilicon,
                      daemonConfigHostBatchTopic = hostBatchTopicForMode AppleSilicon,
                      daemonConfigPulsarConnectionMode = ConfiguredTransport
                    },
                hostDaemon =
                  Just
                    DaemonConfig
                      { daemonConfigRole = HostDaemon,
                        daemonConfigLocation = "control-plane-host",
                        daemonConfigRequestTopics = maybe [] pure (hostBatchTopicForMode AppleSilicon),
                        daemonConfigResultTopic = resultTopicForMode AppleSilicon,
                        daemonConfigHostBatchTopic = hostBatchTopicForMode AppleSilicon,
                        daemonConfigPulsarConnectionMode = PublicationEdgeAutoDiscovery
                      },
                requestTopics = requestTopicsForMode AppleSilicon,
                resultTopic = resultTopicForMode AppleSilicon,
                engines = engineBindingsForMode AppleSilicon,
                models = catalogForMode AppleSilicon
              }
          appleConfigPath = buildRoot paths </> "apple-host-demo-config-test.dhall"
      Lazy.writeFile appleConfigPath (encodeDemoConfig appleHostConfig)
      decodedAppleConfig <- decodeDemoConfigFile appleConfigPath
      assert (activeDaemonRole decodedAppleConfig == HostDaemon) "apple host demo-config keeps host as the active local daemon role"
      assert (daemonConfigHostBatchTopic (clusterDaemon decodedAppleConfig) == hostBatchTopicForMode AppleSilicon) "apple cluster daemon metadata publishes the host batch topic"
      assert (fmap daemonConfigRequestTopics (hostDaemon decodedAppleConfig) == Just (maybe [] pure (hostBatchTopicForMode AppleSilicon))) "apple host daemon metadata consumes the host batch topic"
      let readinessMarkerPath = runtimeRoot paths </> "service" </> "subscription.ready"
      withOptionalEnv "INFERNIX_DEMO_CONFIG_PATH" (Just demoConfigPath) $
        withOptionalEnv "INFERNIX_PULSAR_WS_BASE_URL" (Just "ws://127.0.0.1:65530/ws/v2") $
          withOptionalEnv "INFERNIX_PULSAR_ADMIN_URL" (Just "http://127.0.0.1:65530/admin/v2") $ do
            _ <- timeout 2000000 (runProductionDaemon paths LinuxCpu)
            readinessMarkerPresent <- doesFileExist readinessMarkerPath
            assert
              (not readinessMarkerPresent)
              "real Pulsar startup keeps the readiness marker absent until schema registration succeeds"

      ensureAppleSiliconRuntimeReady paths

      let request =
            InferenceRequest
              { requestModelId = "llm-qwen25-safetensors",
                inputText = Text.replicate 96 "x"
              }
      inferenceResult <- executeInference paths AppleSilicon request
      case inferenceResult of
        Left err -> fail ("unexpected inference error: " <> show err)
        Right result -> do
          assert (resultModelId result == "llm-qwen25-safetensors") "inference result records the selected model id"
          assert (resultRuntimeMode result == AppleSilicon) "inference result records the runtime mode"
          assert (isJust (objectRef (payload result))) "long outputs are stored in the object store"
          let resultPath = resultsRoot paths </> Text.unpack (requestId result) <> ".pb"
          resultExists <- doesFileExist resultPath
          assert resultExists "inference execution writes a protobuf result file"
          reloadedResult <- loadInferenceResult paths (requestId result)
          assert
            (fmap requestId reloadedResult == Just (requestId result))
            "inference result reload reads the protobuf-backed result file"
          case objectRef (payload result) of
            Just objectRefValue -> do
              durableOutput <- readFile (objectStoreRoot paths </> Text.unpack objectRefValue)
              assert
                ("transformers-python|ready|llm-qwen25-safetensors|tok=1|" `isInfixOf` durableOutput)
                "python-native worker execution loads adapter bootstrap state and model metadata"
              assert
                (Text.unpack (inputText request) `isInfixOf` durableOutput)
                "python-native worker execution preserves the submitted prompt payload"
            Nothing -> fail "expected an object-store-backed output for the long inference result"
          let bootstrapManifestPath = dataRoot paths </> "engines" </> "transformers-python" </> "bootstrap.json"
          bootstrapExists <- doesFileExist bootstrapManifestPath
          assert bootstrapExists "apple-silicon setup creates per-adapter bootstrap manifests"
          bootstrapContents <- readFile bootstrapManifestPath
          assert ("transformers-python" `isInfixOf` bootstrapContents) "adapter bootstrap manifests record the adapter id"
          manifests <- listCacheManifests paths AppleSilicon
          let maybeManifest = find ((== "llm-qwen25-safetensors") . cacheModelId) manifests
          assert (isJust maybeManifest) "inference execution materializes a cache manifest"
          evictedCount <- evictCache paths AppleSilicon (Just "llm-qwen25-safetensors")
          assert (evictedCount == 1) "cache eviction removes the selected cache entry"
          rebuiltEntries <- rebuildCache paths AppleSilicon (Just "llm-qwen25-safetensors")
          assert (length rebuiltEntries == 1) "cache rebuild restores the selected cache entry"

      nativeInferenceResult <-
        executeInference
          paths
          AppleSilicon
          InferenceRequest
            { requestModelId = "speech-whisper-small",
              inputText = "native runner coverage"
            }
      case nativeInferenceResult of
        Left err -> fail ("unexpected native inference error: " <> show err)
        Right result -> do
          payloadText <- renderPayloadText paths (payload result)
          assert
            ("adapter=whisper-cpp-cli" `isInfixOf` payloadText)
            "native runner execution reports the adapter-specific runner id instead of a generic fallback payload"
          assert
            ("runner=whisper.cpp transcription lane" `isInfixOf` payloadText)
            "native runner execution reports the explicit runner lane description"

      let overrideModel = maybe (fail "expected the apple-silicon qwen row") pure (findModel AppleSilicon "llm-qwen25-safetensors")
      overrideModelDescriptor <- overrideModel
      let overrideBinding = engineBindingForSelectedEngine AppleSilicon (selectedEngine overrideModelDescriptor)
          overrideEnvName = engineCommandOverrideEnvironmentName overrideBinding
          overrideMarkerPath = buildRoot paths </> "worker-override-used.txt"
          overrideWrapperPath = buildRoot paths </> "python-worker-wrapper.sh"
      writeFile
        overrideWrapperPath
        ( unlines
            [ "#!/bin/sh",
              "printf override-used > " <> show overrideMarkerPath,
              "exec \"$@\""
            ]
        )
      wrapperPermissions <- getPermissions overrideWrapperPath
      setPermissions overrideWrapperPath wrapperPermissions {executable = True}
      assert
        (overrideEnvName == "INFERNIX_ENGINE_COMMAND_TRANSFORMERS_PYTHON")
        "python-native adapter overrides normalize adapter ids into environment variables"
      assert
        (engineBindingAdapterEntrypoint overrideBinding == "adapter-transformers-python")
        "engine bindings publish Poetry adapter entrypoints"
      assert
        (engineBindingSetupEntrypoint overrideBinding == "setup-transformers-python")
        "engine bindings publish Poetry setup entrypoints"
      assert
        (engineBindingProjectDirectory overrideBinding == "python")
        "engine bindings publish the shared Poetry project directory"
      withOptionalEnv overrideEnvName (Just (overrideWrapperPath <> " ")) $ do
        overrideResult <-
          executeInference
            paths
            AppleSilicon
            InferenceRequest
              { requestModelId = "llm-qwen25-safetensors",
                inputText = "  override payload  "
              }
        case overrideResult of
          Left err -> fail ("unexpected override inference error: " <> show err)
          Right result -> do
            payloadText <- renderPayloadText paths (payload result)
            assert
              ("override payload" `isInfixOf` payloadText)
              "adapter-specific command overrides still execute the selected worker path"
            markerExists <- doesFileExist overrideMarkerPath
            assert markerExists "adapter-specific command overrides invoke the configured worker wrapper"

    let invalidDemoConfigPath = unitTestRoot </> "invalid-demo-config.dhall"
    writeFile invalidDemoConfigPath "{\"runtimeMode\":\"apple-silicon\",\"models\":[]}\n"
    invalidConfigResult <- try (decodeDemoConfigFile invalidDemoConfigPath) :: IO (Either IOError DemoConfig)
    assert (either (const True) (const False) invalidConfigResult) "invalid demo configs are rejected"

    let renderedChartPath = unitTestRoot </> "rendered-chart.yaml"
    writeFile renderedChartPath sampleRenderedChart
    discoveredImages <- discoverChartImagesFile renderedChartPath
    assert
      ( discoveredImages
          == [ "docker.io/library/busybox:1.36",
               "docker.io/percona/percona-distribution-postgresql:18.3-1",
               "infernix-linux-cpu:local"
             ]
      )
      "rendered chart image discovery returns sorted unique image refs"
    discoveredClaims <- discoverChartClaimsFile renderedChartPath
    assert (length discoveredClaims == 3) "rendered chart claim discovery finds explicit and StatefulSet claims"
    assert
      ( map pvcName discoveredClaims
          == [ "data-infernix-minio-0",
               "data-infernix-minio-1",
               "infernix-service-0-data"
             ]
      )
      "rendered chart claim discovery preserves normalized PVC names"

    let harborOverlayPath = unitTestRoot </> "harbor-overlay.yaml"
        generatedHarborOverlayPath = unitTestRoot </> "generated-harbor-overrides.yaml"
    writeFile harborOverlayPath sampleHarborOverlay
    overlayImages <- discoverHarborOverlayImageRefsFile harborOverlayPath
    assert
      ( overlayImages
          == [ "harbor.local/library/infernix-linux-cpu:sha256-runtime",
               "harbor.local/library/bitnamilegacy/minio:sha256-minio",
               "harbor.local/library/bitnamilegacy/os-shell:sha256-shell",
               "harbor.local/library/bitnamilegacy/minio-object-browser:sha256-console",
               "harbor.local/library/bitnamilegacy/minio-client:sha256-client",
               "harbor.local/library/apachepulsar/pulsar-all:sha256-pulsar"
             ]
      )
      "Harbor overlay discovery returns the routed image refs"
    writeHarborOverridesFile samplePublishedImages generatedHarborOverlayPath
    generatedOverlayImages <- discoverHarborOverlayImageRefsFile generatedHarborOverlayPath
    assert
      ( generatedOverlayImages
          == [ "harbor.local/library/infernix-linux-cpu:sha256-runtime",
               "harbor.local/library/bitnamilegacy/minio:sha256-minio",
               "harbor.local/library/bitnamilegacy/os-shell:sha256-shell",
               "harbor.local/library/bitnamilegacy/minio-object-browser:sha256-console",
               "harbor.local/library/bitnamilegacy/minio-client:sha256-client",
               "harbor.local/library/apachepulsar/pulsar-all:sha256-pulsar"
             ]
      )
      "Harbor overlay emission produces the routed image override contract"
    assert
      (normalizeRepositoryPath "docker.io/library/busybox:1.36" == "library/busybox")
      "repository normalization removes tags and explicit registries"
    assert
      (normalizeRepositoryPath "localhost:30002/library/infernix-service@sha256:deadbeef" == "library/infernix-service")
      "repository normalization removes digests and loopback Harbor prefixes"
    assert
      (dockerHubMirrorRef "docker.io/percona/percona-pgbackrest:2.58.0-1" == Just "mirror.gcr.io/percona/percona-pgbackrest:2.58.0-1")
      "docker hub fallback maps explicit docker.io refs to mirror.gcr.io"
    assert
      (dockerHubMirrorRef "busybox:1.36" == Just "mirror.gcr.io/library/busybox:1.36")
      "docker hub fallback adds the implicit library namespace for single-segment refs"
    assert
      (isNothing (dockerHubMirrorRef "ghcr.io/example/image:1.0.0"))
      "docker hub fallback ignores non-Docker-Hub registries"
    assert
      ( prioritizePublishableImages
          [ "docker.io/percona/percona-postgresql-operator:2.9.0",
            "infernix-linux-cpu:local",
            "docker.io/apachepulsar/pulsar-all:4.0.9"
          ]
          == [ "infernix-linux-cpu:local",
               "docker.io/percona/percona-postgresql-operator:2.9.0",
               "docker.io/apachepulsar/pulsar-all:4.0.9"
             ]
      )
      "Harbor publication prioritizes repo-owned local images before remote chart dependencies"
    assert
      (contentAddressTagFromInspectPayload sampleDockerImageInspect == Right "sha256-deadbeef")
      "docker inspect parsing prefers repo digests for content-addressed tags"
    assert
      (contentAddressTagFromInspectPayload sampleDockerImageInspectWithoutRepoDigest == Right "sha256-fallback")
      "docker inspect parsing falls back to the image id when no repo digest is present"
  putStrLn "unit tests passed"

withTestRoot :: FilePath -> IO a -> IO a
withTestRoot root action = do
  catchIOError (removePathForcibly root) ignoreMissing
  createDirectoryIfMissing True root
  previousDataRoot <- lookupEnv "INFERNIX_DATA_ROOT"
  setEnv "INFERNIX_DATA_ROOT" (root </> ".data")
  withCurrentDirectory root action
    `finally` maybe (unsetEnv "INFERNIX_DATA_ROOT") (setEnv "INFERNIX_DATA_ROOT") previousDataRoot
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

withOptionalEnv :: String -> Maybe String -> IO a -> IO a
withOptionalEnv name maybeValue action = do
  previousValue <- lookupEnv name
  applyMaybeValue maybeValue
  action
    `finally` applyMaybeValue previousValue
  where
    applyMaybeValue (Just value) = setEnv name value
    applyMaybeValue Nothing = unsetEnv name

testRootPath :: FilePath -> IO FilePath
testRootPath suiteName = do
  paths <- discoverPaths
  pure (repoRoot paths </> ".build" </> ("test-" <> suiteName))

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message

assertJsonRoundtrip :: (Eq a, Show a, Aeson.ToJSON a, Aeson.FromJSON a) => String -> a -> IO ()
assertJsonRoundtrip label value =
  case Aeson.eitherDecode (Aeson.encode value) of
    Left err ->
      fail (label <> ": JSON decode failed: " <> err)
    Right decoded ->
      assert
        (decoded == value)
        (label <> ": encode/decode roundtrip diverged. Original=" <> show value <> " Decoded=" <> show decoded)

assertPhase7JsonRoundtrips :: IO ()
assertPhase7JsonRoundtrips = do
  let userId = Contracts.UserId "user-42"
      contextId = Contracts.ContextId "ctx-7"
      messageId = Contracts.MessageId "msg-1"
      idemKey = Contracts.ClientIdempotencyKey "idem-1"
      mimeType = Contracts.ArtifactMimeType "image/png"
      objectRef = Contracts.ObjectRef "infernix-demo-objects" "users/u/contexts/c/uploads/x.png"
      promptPayload =
        Contracts.UserPromptPayload
          { Contracts.promptText = "hello world",
            Contracts.promptClientIdempotencyKey = idemKey,
            Contracts.promptUserUploads = [objectRef]
          }
      inferenceResultPayload =
        Contracts.ConversationInferenceResultPayload
          { Contracts.inferenceResultUserPromptMessageId = messageId,
            Contracts.inferenceResultStatus = "Completed",
            Contracts.inferenceResultInlineOutput = Just "result text",
            Contracts.inferenceResultArtifacts = []
          }
      cancelPayload = Contracts.ConversationCancelPayload messageId
      uploadPayload =
        Contracts.ConversationUserUploadPayload
          { Contracts.uploadObjectRef = objectRef,
            Contracts.uploadMimeType = mimeType,
            Contracts.uploadDisplayName = "screenshot.png"
          }
      conversationMessage =
        Contracts.ConversationMessage
          { Contracts.conversationMessageId = messageId,
            Contracts.conversationMessageEvent = Contracts.ConversationUserPromptEvent promptPayload
          }
      conversationState =
        Contracts.ConversationState
          { Contracts.conversationStateContextId = contextId,
            Contracts.conversationStateMessages = [conversationMessage],
            Contracts.conversationStatePrefixHash = "deadbeef"
          }
      contextSummary =
        Contracts.ContextSummary
          { Contracts.contextSummaryId = contextId,
            Contracts.contextSummaryModelId = "qwen2.5-7b-instruct-q4",
            Contracts.contextSummaryTitle = "tasting notes",
            Contracts.contextSummarySoftDeleted = False
          }
      contextListState = Contracts.ContextListState [contextSummary]
      draftEntry = Contracts.DraftEntry contextId "half-written"
      draftMapState = Contracts.DraftMapState [draftEntry]
  assertJsonRoundtrip "UserId" userId
  assertJsonRoundtrip "ContextId" contextId
  assertJsonRoundtrip "MessageId" messageId
  assertJsonRoundtrip "ClientIdempotencyKey" idemKey
  assertJsonRoundtrip "ArtifactMimeType" mimeType
  assertJsonRoundtrip "ObjectRef" objectRef
  assertJsonRoundtrip "ArtifactKindUpload" Contracts.ArtifactKindUpload
  assertJsonRoundtrip "ArtifactKindGenerated" Contracts.ArtifactKindGenerated
  assertJsonRoundtrip "RenderInline" Contracts.RenderInline
  assertJsonRoundtrip "DownloadOnly" Contracts.DownloadOnly
  assertJsonRoundtrip "BoundedTextPreview" Contracts.BoundedTextPreview
  assertJsonRoundtrip "BrowserNativePdf" Contracts.BrowserNativePdf
  assertJsonRoundtrip "UserPromptPayload" promptPayload
  assertJsonRoundtrip "ConversationInferenceResultPayload" inferenceResultPayload
  assertJsonRoundtrip "ConversationCancelPayload" cancelPayload
  assertJsonRoundtrip "ConversationUserUploadPayload" uploadPayload
  assertJsonRoundtrip "ConversationEvent.UserPrompt" (Contracts.ConversationUserPromptEvent promptPayload)
  assertJsonRoundtrip "ConversationEvent.InferenceResult" (Contracts.ConversationInferenceResultEvent inferenceResultPayload)
  assertJsonRoundtrip "ConversationEvent.Cancel" (Contracts.ConversationCancelEvent cancelPayload)
  assertJsonRoundtrip "ConversationEvent.UserUpload" (Contracts.ConversationUserUploadEvent uploadPayload)
  assertJsonRoundtrip
    "ContextMetadataEvent.Created"
    ( Contracts.ContextCreated
        { Contracts.contextCreatedContextId = contextId,
          Contracts.contextCreatedModelId = "model",
          Contracts.contextCreatedTitle = "title"
        }
    )
  assertJsonRoundtrip
    "DraftEvent.Updated"
    (Contracts.DraftUpdated contextId "draft")
  assertJsonRoundtrip "ConversationMessage" conversationMessage
  assertJsonRoundtrip "ConversationState" conversationState
  assertJsonRoundtrip
    "ConversationStatePatch.Append"
    ( Contracts.ConversationStateAppendMessage
        { Contracts.appendMessage = conversationMessage,
          Contracts.appendNewPrefixHash = "cafef00d"
        }
    )
  assertJsonRoundtrip
    "ConversationStatePatch.Replace"
    (Contracts.ConversationStateReplaceSnapshot conversationState)
  assertJsonRoundtrip "ContextSummary" contextSummary
  assertJsonRoundtrip "ContextListState" contextListState
  assertJsonRoundtrip
    "ContextListPatch.Upsert"
    (Contracts.ContextListUpsert contextSummary)
  assertJsonRoundtrip
    "ContextListPatch.Replace"
    (Contracts.ContextListReplaceSnapshot contextListState)
  assertJsonRoundtrip "DraftEntry" draftEntry
  assertJsonRoundtrip "DraftMapState" draftMapState
  assertJsonRoundtrip
    "DraftMapPatch.Upsert"
    (Contracts.DraftMapUpsert draftEntry)
  assertJsonRoundtrip
    "DraftMapPatch.Remove"
    (Contracts.DraftMapRemove contextId)
  assertJsonRoundtrip
    "DraftMapPatch.Replace"
    (Contracts.DraftMapReplaceSnapshot draftMapState)
  assertJsonRoundtrip
    "WsClientMessage.Hello"
    (Contracts.ClientHello userId)
  assertJsonRoundtrip
    "WsClientMessage.SubmitPrompt"
    ( Contracts.ClientSubmitPrompt
        { Contracts.clientSubmitPromptContextId = contextId,
          Contracts.clientSubmitPromptPayload = promptPayload
        }
    )
  assertJsonRoundtrip
    "WsServerMessage.ConversationSnapshot"
    (Contracts.ServerConversationSnapshot conversationState)
  assertJsonRoundtrip
    "WsServerMessage.ConversationPatch"
    ( Contracts.ServerConversationPatch
        { Contracts.serverConversationPatchContextId = contextId,
          Contracts.serverConversationPatch =
            Contracts.ConversationStateAppendMessage
              { Contracts.appendMessage = conversationMessage,
                Contracts.appendNewPrefixHash = "deadc0de"
              }
        }
    )
  assertJsonRoundtrip
    "ArtifactUploadRequest"
    ( Contracts.ArtifactUploadRequest
        { Contracts.artifactUploadRequestContextId = contextId,
          Contracts.artifactUploadRequestMimeType = mimeType,
          Contracts.artifactUploadRequestDisplayName = "x.png"
        }
    )
  assertJsonRoundtrip
    "ArtifactUploadGrant"
    ( Contracts.ArtifactUploadGrant
        { Contracts.artifactUploadGrantObjectRef = objectRef,
          Contracts.artifactUploadGrantPresignedUrl = "https://minio/put",
          Contracts.artifactUploadGrantExpiresAtIso8601 = "2026-05-21T00:00:00Z"
        }
    )
  assertJsonRoundtrip
    "ArtifactDownloadGrant"
    ( Contracts.ArtifactDownloadGrant
        { Contracts.artifactDownloadGrantObjectRef = objectRef,
          Contracts.artifactDownloadGrantPresignedUrl = "https://minio/get",
          Contracts.artifactDownloadGrantMimeType = mimeType,
          Contracts.artifactDownloadGrantRenderDisposition = Contracts.RenderInline,
          Contracts.artifactDownloadGrantExpiresAtIso8601 = "2026-05-21T00:00:00Z"
        }
    )

assertConversationPrimitives :: IO ()
assertConversationPrimitives = do
  let userId = Contracts.UserId "u-1"
      contextId = Contracts.ContextId "c-1"
      anotherContextId = Contracts.ContextId "c-2"
      ns = ConversationTopic.defaultDemoTopicNamespace
      sysNs = ConversationTopic.systemTopicNamespace
      promptKey1 = Contracts.ClientIdempotencyKey "idem-1"
      promptKey2 = Contracts.ClientIdempotencyKey "idem-2"
      makePrompt key text =
        Contracts.UserPromptPayload
          { Contracts.promptText = text,
            Contracts.promptClientIdempotencyKey = key,
            Contracts.promptUserUploads = []
          }
      promptMessage messageIdText payload =
        Contracts.ConversationMessage
          { Contracts.conversationMessageId = Contracts.MessageId messageIdText,
            Contracts.conversationMessageEvent = Contracts.ConversationUserPromptEvent payload
          }
      resultMessage messageIdText forPromptMessageId =
        Contracts.ConversationMessage
          { Contracts.conversationMessageId = Contracts.MessageId messageIdText,
            Contracts.conversationMessageEvent =
              Contracts.ConversationInferenceResultEvent
                Contracts.ConversationInferenceResultPayload
                  { Contracts.inferenceResultUserPromptMessageId = Contracts.MessageId forPromptMessageId,
                    Contracts.inferenceResultStatus = "Completed",
                    Contracts.inferenceResultInlineOutput = Just "ok",
                    Contracts.inferenceResultArtifacts = []
                  }
          }
      cancelMessage messageIdText forPromptMessageId =
        Contracts.ConversationMessage
          { Contracts.conversationMessageId = Contracts.MessageId messageIdText,
            Contracts.conversationMessageEvent =
              Contracts.ConversationCancelEvent
                (Contracts.ConversationCancelPayload (Contracts.MessageId forPromptMessageId))
          }

  -- Topic naming determinism + shape
  assert
    (ConversationTopic.conversationTopicName ns userId contextId == "persistent://infernix/demo/demo.conversation.u-1.c-1")
    "conversation topic naming follows persistent://infernix/demo/demo.conversation.<userId>.<contextId>"
  assert
    (ConversationTopic.contextsMetadataTopicName ns userId == "persistent://infernix/demo/demo.user.u-1.contexts")
    "compacted contexts metadata topic follows the supported tenant/namespace layout"
  assert
    (ConversationTopic.draftsMetadataTopicName ns userId == "persistent://infernix/demo/demo.user.u-1.drafts")
    "compacted drafts metadata topic follows the supported tenant/namespace layout"
  assert
    (ConversationTopic.inferenceRequestTopicName ns "linux-cpu" == "persistent://infernix/demo/inference.request.linux-cpu")
    "inference request topic naming uses the supported demo namespace"
  assert
    (ConversationTopic.inferenceBatchTopicName ns "apple-silicon" == "persistent://infernix/demo/inference.batch.apple-silicon")
    "inference batch topic naming uses the supported demo namespace"
  assert
    (ConversationTopic.modelBootstrapRequestTopicName sysNs == "persistent://infernix/system/model.bootstrap.request")
    "model bootstrap request topic lives under the supported infernix/system namespace"
  assert
    (ConversationTopic.modelBootstrapReadyTopicName sysNs "qwen2.5-7b" == "persistent://infernix/system/model.bootstrap.ready.qwen2.5-7b")
    "model bootstrap ready topic names its modelId suffix"

  -- Topic naming is parameterizable per TopicNamespace
  let customNs = ConversationTopic.TopicNamespace "tenant" "demo"
  assert
    (ConversationTopic.conversationTopicName customNs userId contextId == "persistent://tenant/demo/demo.conversation.u-1.c-1")
    "conversation topic naming honors a custom TopicNamespace tenant"

  -- Hash chain monotonicity
  let prompt1 = promptMessage "m-1" (makePrompt promptKey1 "hi")
      prompt2 = promptMessage "m-2" (makePrompt promptKey2 "again")
      chain = ConversationHash.prefixHashChainOver [prompt1, prompt2]
  case chain of
    (firstHash : _) ->
      assert
        (firstHash == ConversationHash.emptyPrefixHash)
        "the prefixHash chain seed equals emptyPrefixHash"
    [] -> fail "prefixHash chain should be non-empty"
  assert
    (length chain == 3)
    "the prefixHash chain has one entry per prefix including the empty prefix"
  assert
    (length (nub chain) == 3)
    "each prefix in the chain has a distinct hash"
  -- Determinism: same input → same output
  let chain2 = ConversationHash.prefixHashChainOver [prompt1, prompt2]
  assert (chain == chain2) "prefixHash chain is deterministic across repeated invocations"
  -- Tamper resistance: changing any message changes every following hash
  let tampered = promptMessage "m-1" (makePrompt promptKey1 "hi tampered")
      chainTampered = ConversationHash.prefixHashChainOver [tampered, prompt2]
  case (chain, chainTampered) of
    (_ : c1 : c2 : _, _ : t1 : t2 : _) -> do
      assert (t1 /= c1) "tampering with the first message changes the resulting prefix hash"
      assert (t2 /= c2) "tampering with the first message propagates to every later prefix hash"
    _ -> fail "expected prefix hash chains to have at least three entries"

  -- Idempotency dedup at the reducer level
  let dupePrompts = [prompt1, prompt1]
      (finalReducerState, dupePatches) =
        ConversationReducer.foldEventsKeepingPatches contextId dupePrompts
  assert
    (length dupePatches == 1)
    "the reducer drops a duplicate user prompt that re-uses the same client idempotency key in the same context"
  assert
    (length (ConversationReducer.reducerMessages finalReducerState) == 1)
    "the reducer state contains exactly one message after a duplicate is dropped"

  -- Idempotency is scoped per (contextId, key): same key in another context is not a duplicate
  let dupeKey = ConversationIdempotency.IdempotencyKey contextId promptKey1
      anotherKey = ConversationIdempotency.IdempotencyKey anotherContextId promptKey1
      (firstAdmitted, set1) = ConversationIdempotency.rememberIdempotencyKey dupeKey ConversationIdempotency.emptyIdempotencySet
      (secondAdmitted, _) = ConversationIdempotency.rememberIdempotencyKey dupeKey set1
      (acrossContextAdmitted, _) = ConversationIdempotency.rememberIdempotencyKey anotherKey set1
  assert firstAdmitted "idempotency set admits a previously unseen (contextId, key)"
  assert (not secondAdmitted) "idempotency set rejects a (contextId, key) it has already seen"
  assert acrossContextAdmitted "idempotency set admits the same client key in a different context"

  -- Two-prompt-in-a-row ordering preserved
  let twoInARow = [prompt1, prompt2]
      (twoInARowState, _) = ConversationReducer.foldEventsKeepingPatches contextId twoInARow
      twoInARowOrder =
        map Contracts.conversationMessageId (toList (ConversationReducer.reducerMessages twoInARowState))
  assert
    (twoInARowOrder == [Contracts.MessageId "m-1", Contracts.MessageId "m-2"])
    "two distinct prompts in a row are retained in submission order"
  assert
    (ConversationReducer.nextDispatchablePrompt twoInARowState == Just (Contracts.MessageId "m-1"))
    "the single-flight rule dispatches the earliest unmatched prompt first"

  -- Cancellation marks a prompt as resolved
  let withCancel = [prompt1, cancelMessage "m-1-cancel" "m-1", prompt2]
      (cancelState, _) = ConversationReducer.foldEventsKeepingPatches contextId withCancel
  assert
    (ConversationReducer.nextDispatchablePrompt cancelState == Just (Contracts.MessageId "m-2"))
    "a cancellation event removes its target prompt from the single-flight queue"

  -- Inference result resolves a prompt
  let withResult = [prompt1, resultMessage "m-1-result" "m-1", prompt2]
      (resultState, _) = ConversationReducer.foldEventsKeepingPatches contextId withResult
  assert
    (ConversationReducer.nextDispatchablePrompt resultState == Just (Contracts.MessageId "m-2"))
    "an inference result event removes its target prompt from the single-flight queue"

  -- Patch-stream-vs-snapshot equivalence across multiple event sequences.
  -- This stands in for the property-based check until a QuickCheck-style
  -- generator is in the dep tree.
  let seedState =
        Contracts.ConversationState
          { Contracts.conversationStateContextId = contextId,
            Contracts.conversationStateMessages = [],
            Contracts.conversationStatePrefixHash = ConversationHash.unPrefixHash ConversationHash.emptyPrefixHash
          }
      sequences =
        [ ("empty log", []),
          ("single prompt", [prompt1]),
          ("prompt + result", [prompt1, resultMessage "m-1-result" "m-1"]),
          ("two prompts queued", [prompt1, prompt2]),
          ("prompt + cancel + prompt", [prompt1, cancelMessage "m-1-cancel" "m-1", prompt2]),
          ("prompt + result + prompt", [prompt1, resultMessage "m-1-result" "m-1", prompt2]),
          ("duplicate prompt dropped", [prompt1, prompt1, prompt2])
        ]
  mapM_
    ( \(label, events) -> do
        let (_, patches) = ConversationReducer.foldEventsKeepingPatches contextId events
            snapshot = ConversationReducer.snapshotReducer contextId events
            replayed = foldl ConversationReducer.applyPatchToState seedState patches
        assert
          (replayed == snapshot)
          ("patch stream replay converges to snapshot reducer projection: " <> label)
    )
    sequences

  -- Event helpers
  assert
    (ConversationEvent.eventClientIdempotencyKey (Contracts.ConversationUserPromptEvent (makePrompt promptKey1 "x")) == Just promptKey1)
    "eventClientIdempotencyKey returns the key for UserPrompt events"
  assert
    (ConversationEvent.isUserPrompt (Contracts.ConversationUserPromptEvent (makePrompt promptKey1 "x")))
    "isUserPrompt recognizes user-prompt events"
  assert
    ( ConversationEvent.eventUserPromptMessageId
        (Contracts.ConversationCancelEvent (Contracts.ConversationCancelPayload (Contracts.MessageId "m-x")))
        == Just (Contracts.MessageId "m-x")
    )
    "eventUserPromptMessageId returns the causal ref for Cancel events"
  where
    toList = foldr (:) []

assertCompactedMetadataPatterns :: IO ()
assertCompactedMetadataPatterns = do
  -- Generic compacted view: N events across M distinct keys yields M latest values
  let events =
        [ TopicMetadata.KeyedEvent "k1" ("v1-old" :: Text.Text),
          TopicMetadata.KeyedEvent "k2" "v2",
          TopicMetadata.KeyedEvent "k1" "v1-new",
          TopicMetadata.KeyedEvent "k3" "v3",
          TopicMetadata.KeyedEvent "k2" "v2-final"
        ]
      view = TopicMetadata.foldCompactedEvents events
  assert
    (TopicMetadata.compactedViewSize view == 3)
    "compacted view yields one entry per distinct key (5 events, 3 keys -> 3 entries)"
  assert
    (TopicMetadata.lookupCompactedView "k1" view == Just "v1-new")
    "compacted view returns the latest value per key (k1)"
  assert
    (TopicMetadata.lookupCompactedView "k2" view == Just "v2-final")
    "compacted view returns the latest value per key (k2)"
  assert
    (TopicMetadata.lookupCompactedView "k3" view == Just "v3")
    "compacted view returns the latest value per key (k3)"
  assert
    (TopicMetadata.compactedViewEntries view == [("k1", "v1-new"), ("k2", "v2-final"), ("k3", "v3")])
    "compacted view entries are returned in ascending key order"

  -- Drafts: keyed by ContextId, DraftCleared removes the entry
  let ctxA = Contracts.ContextId "ctx-a"
      ctxB = Contracts.ContextId "ctx-b"
      draftEvents =
        [ Contracts.DraftUpdated ctxA "half-written A",
          Contracts.DraftUpdated ctxB "half-written B",
          Contracts.DraftUpdated ctxA "revised A",
          Contracts.DraftCleared ctxB
        ]
      draftMap = TopicDrafts.foldDraftEvents draftEvents
  assert
    (MapStrict.size draftMap == 1)
    "draft compaction removes cleared entries (b cleared -> 1 remaining)"
  assert
    (MapStrict.lookup "ctx-a" draftMap == Just "revised A")
    "draft compaction yields the latest text per context id"
  assert
    (isNothing (MapStrict.lookup "ctx-b" draftMap))
    "draft compaction respects DraftCleared events"

  -- Round-trip through DraftMapState wire format
  let stateForm = TopicDrafts.draftMapFromState draftMap
      mapAgain = TopicDrafts.draftMapToState stateForm
  assert
    (mapAgain == draftMap)
    "DraftMapState <-> internal map roundtrip preserves the compacted projection"

assertSingleFlightDispatcher :: IO ()
assertSingleFlightDispatcher = do
  let userId = Contracts.UserId "user-1"
      contextId = Contracts.ContextId "ctx-flight"
      promptPayload text key =
        Contracts.UserPromptPayload
          { Contracts.promptText = text,
            Contracts.promptClientIdempotencyKey = Contracts.ClientIdempotencyKey key,
            Contracts.promptUserUploads = []
          }
      promptMsg mid text key =
        Contracts.ConversationMessage
          { Contracts.conversationMessageId = Contracts.MessageId mid,
            Contracts.conversationMessageEvent = Contracts.ConversationUserPromptEvent (promptPayload text key)
          }
      resultMsg mid forPrompt =
        Contracts.ConversationMessage
          { Contracts.conversationMessageId = Contracts.MessageId mid,
            Contracts.conversationMessageEvent =
              Contracts.ConversationInferenceResultEvent
                Contracts.ConversationInferenceResultPayload
                  { Contracts.inferenceResultUserPromptMessageId = Contracts.MessageId forPrompt,
                    Contracts.inferenceResultStatus = "Completed",
                    Contracts.inferenceResultInlineOutput = Just "done",
                    Contracts.inferenceResultArtifacts = []
                  }
          }

  -- Empty log: NoOp
  let emptyState = ConversationReducer.foldEvents contextId []
  assert
    (Dispatch.buildDispatchDecision userId emptyState == Dispatch.DispatchNoOp)
    "single-flight dispatcher emits NoOp on an empty log"

  -- Single prompt: dispatch with full envelope
  let oneState = ConversationReducer.foldEvents contextId [promptMsg "p-1" "first" "idem-1"]
      decision1 = Dispatch.buildDispatchDecision userId oneState
  case decision1 of
    Dispatch.DispatchNoOp -> fail "single-flight dispatcher should dispatch the first prompt"
    Dispatch.DispatchPrompt envelope -> do
      assert
        (Dispatch.inferenceUserId envelope == userId)
        "dispatched envelope carries the dispatcher's userId"
      assert
        (Dispatch.inferenceContextId envelope == contextId)
        "dispatched envelope carries the context id"
      assert
        (Dispatch.inferenceUserPromptMessageId envelope == Contracts.MessageId "p-1")
        "dispatched envelope carries the user prompt message id"
      assert
        (Dispatch.inferenceClientIdempotencyKey envelope == Contracts.ClientIdempotencyKey "idem-1")
        "dispatched envelope carries the client idempotency key"
      assert
        (Dispatch.inferencePromptText envelope == "first")
        "dispatched envelope carries the prompt text"
      assert
        (Dispatch.inferenceConversationLogOffset envelope == 0)
        "dispatched envelope carries the conversation log offset for the head prompt"
      assert
        (Dispatch.inferenceCausalRef envelope == "p-1")
        "dispatched envelope carries the causal ref tied to the user prompt message id"
      assert
        (Dispatch.producerDedupSequenceId envelope == "p-1")
        "producer-dedup sequence id is the user prompt message id"

  -- Two prompts in a row: dispatcher still picks the first (single-flight)
  let twoState = ConversationReducer.foldEvents contextId [promptMsg "p-1" "a" "idem-1", promptMsg "p-2" "b" "idem-2"]
      decision2 = Dispatch.buildDispatchDecision userId twoState
  case decision2 of
    Dispatch.DispatchPrompt envelope ->
      assert
        (Dispatch.inferenceUserPromptMessageId envelope == Contracts.MessageId "p-1")
        "single-flight dispatcher picks the earliest unmatched prompt when two are queued"
    _ -> fail "single-flight dispatcher should dispatch p-1 even when p-2 is queued"

  -- Once the first prompt has a result, dispatcher promotes the second
  let afterResultState =
        ConversationReducer.foldEvents
          contextId
          [promptMsg "p-1" "a" "idem-1", promptMsg "p-2" "b" "idem-2", resultMsg "r-1" "p-1"]
      decision3 = Dispatch.buildDispatchDecision userId afterResultState
  case decision3 of
    Dispatch.DispatchPrompt envelope ->
      assert
        (Dispatch.inferenceUserPromptMessageId envelope == Contracts.MessageId "p-2")
        "single-flight dispatcher promotes the second prompt once the first has a matching result"
    _ -> fail "single-flight dispatcher should dispatch p-2 after p-1's result lands"

  -- Subscription naming is per-context and stable
  assert
    (Dispatch.dispatcherSubscriptionName contextId == "dispatcher-ctx-flight")
    "named Failover subscription label is dispatcher-<contextId>"

assertJwtValidation :: IO ()
assertJwtValidation = do
  (publicKey, privateKey) <- Crypto.PubKey.RSA.generate 256 65537
  let kid = "test-kid-1"
      issuer = "https://infernix.local/auth/realms/infernix"
      audience = "infernix-demo"
      nowSeconds = 1_700_000_000 :: Integer
      config =
        Jwt.JwtValidationConfig
          { Jwt.jwtValidationIssuer = Jwt.JwtIssuer (Text.pack issuer),
            Jwt.jwtValidationAudience = Jwt.JwtAudience (Text.pack audience),
            Jwt.jwtValidationLeewaySeconds = 5
          }
      now = Data.Time.Clock.POSIX.posixSecondsToUTCTime (fromIntegral nowSeconds)
      jwk =
        Jwt.Jwk
          { Jwt.jwkKid = Text.pack kid,
            Jwt.jwkKty = "RSA",
            Jwt.jwkAlg = Just "RS256",
            Jwt.jwkUse = Just "sig",
            Jwt.jwkModulusN = base64UrlText (integerToBytes (Crypto.PubKey.RSA.public_n publicKey)),
            Jwt.jwkExponentE = base64UrlText (integerToBytes (Crypto.PubKey.RSA.public_e publicKey))
          }
      jwks = Jwt.Jwks [jwk]
      validClaims =
        Aeson.object
          [ "sub" Aeson..= ("user-test" :: String),
            "iss" Aeson..= issuer,
            "aud" Aeson..= audience,
            "exp" Aeson..= (nowSeconds + 60 :: Integer),
            "iat" Aeson..= (nowSeconds - 5 :: Integer)
          ]
      validToken = signJwt privateKey kid validClaims

  -- Positive path
  case Jwt.verifyAndParseJwt config now jwks validToken of
    Right claims -> do
      assert
        (Jwt.jwtClaimSubject claims == "user-test")
        "valid JWT decodes the sub claim"
      assert
        (Jwt.jwtClaimIssuer claims == Text.pack issuer)
        "valid JWT decodes the iss claim"
    Left err -> fail ("valid JWT was rejected: " <> show err)

  -- Tampered signature
  let tamperedToken = mangleLastChar validToken
  case Jwt.verifyAndParseJwt config now jwks tamperedToken of
    Left Jwt.JwtSignatureInvalid -> pure ()
    other -> fail ("tampered JWT was not rejected with JwtSignatureInvalid: " <> show other)

  -- Wrong issuer
  let wrongIssuerClaims =
        Aeson.object
          [ "sub" Aeson..= ("user-test" :: String),
            "iss" Aeson..= ("https://evil.example/auth" :: String),
            "aud" Aeson..= audience,
            "exp" Aeson..= (nowSeconds + 60 :: Integer)
          ]
      wrongIssuerToken = signJwt privateKey kid wrongIssuerClaims
  case Jwt.verifyAndParseJwt config now jwks wrongIssuerToken of
    Left Jwt.JwtIssuerMismatch {} -> pure ()
    other -> fail ("wrong-issuer JWT was not rejected: " <> show other)

  -- Wrong audience
  let wrongAudienceClaims =
        Aeson.object
          [ "sub" Aeson..= ("user-test" :: String),
            "iss" Aeson..= issuer,
            "aud" Aeson..= ("not-our-audience" :: String),
            "exp" Aeson..= (nowSeconds + 60 :: Integer)
          ]
      wrongAudienceToken = signJwt privateKey kid wrongAudienceClaims
  case Jwt.verifyAndParseJwt config now jwks wrongAudienceToken of
    Left Jwt.JwtAudienceMismatch {} -> pure ()
    other -> fail ("wrong-audience JWT was not rejected: " <> show other)

  -- Expired
  let expiredClaims =
        Aeson.object
          [ "sub" Aeson..= ("user-test" :: String),
            "iss" Aeson..= issuer,
            "aud" Aeson..= audience,
            "exp" Aeson..= (nowSeconds - 60 :: Integer)
          ]
      expiredToken = signJwt privateKey kid expiredClaims
  case Jwt.verifyAndParseJwt config now jwks expiredToken of
    Left Jwt.JwtExpired {} -> pure ()
    other -> fail ("expired JWT was not rejected: " <> show other)

  -- Unknown kid
  let mismatchedKidToken = signJwt privateKey "unknown-kid" validClaims
  case Jwt.verifyAndParseJwt config now jwks mismatchedKidToken of
    Left (Jwt.JwtUnknownKid _) -> pure ()
    other -> fail ("unknown-kid JWT was not rejected: " <> show other)

  -- Malformed structure
  case Jwt.verifyAndParseJwt config now jwks "not.a.jwt.with.too.many.dots" of
    Left Jwt.JwtMalformedStructure -> pure ()
    other -> fail ("malformed JWT was not rejected: " <> show other)

  -- JWKS parsing
  let jwksJson =
        Lazy.fromStrict $
          TextEncoding.encodeUtf8 $
            Text.pack
              "{\"keys\":[{\"kid\":\"k1\",\"kty\":\"RSA\",\"n\":\"AQ\",\"e\":\"AQAB\"}]}"
  case Jwt.parseJwks jwksJson of
    Right (Jwt.Jwks [k]) ->
      assert (Jwt.jwkKid k == "k1") "JWKS parser extracts the first key's kid"
    other -> fail ("JWKS parsing failed: " <> show other)

assertObjectsLayoutAndPresigning :: IO ()
assertObjectsLayoutAndPresigning = do
  let alice = Contracts.UserId "alice"
      bob = Contracts.UserId "bob"
      ctx = Contracts.ContextId "ctx-100"
      anotherCtx = Contracts.ContextId "ctx-200"

  -- Per-user prefix layout
  assert
    (ObjLayout.unUserPrefix (ObjLayout.userPrefix alice) == "users/alice/")
    "userPrefix follows users/<userId>/ layout"
  assert
    (ObjLayout.unContextPrefix (ObjLayout.contextPrefix alice ctx) == "users/alice/contexts/ctx-100/")
    "contextPrefix follows users/<userId>/contexts/<contextId>/ layout"

  -- Upload + generated object keys
  let upload = ObjLayout.uploadObjectKey alice ctx "screenshot.png"
      generated = ObjLayout.generatedObjectKey alice anotherCtx "result.wav"
  assert
    (Contracts.objectBucket upload == "infernix-demo-objects")
    "upload object key targets the infernix-demo-objects bucket"
  assert
    (Contracts.objectKey upload == "users/alice/contexts/ctx-100/uploads/screenshot.png")
    "upload object key includes the uploads subprefix"
  assert
    (Contracts.objectKey generated == "users/alice/contexts/ctx-200/generated/result.wav")
    "generated object key includes the generated subprefix"

  -- Model bucket + ready sentinel
  let modelBytes = ObjLayout.modelObjectKey "qwen2.5-7b" "tokenizer.json"
      modelReady = ObjLayout.modelReadySentinelKey "qwen2.5-7b"
  assert
    (Contracts.objectBucket modelBytes == "infernix-models")
    "model object keys target the infernix-models bucket"
  assert
    (Contracts.objectKey modelReady == "qwen2.5-7b/.ready")
    "model ready sentinel key is <modelId>/.ready"

  -- Per-user scope enforcement
  assert
    (ObjLayout.pathBelongsToUser alice "users/alice/contexts/ctx-100/uploads/x.png")
    "pathBelongsToUser admits alice's own prefix"
  assert
    (not (ObjLayout.pathBelongsToUser alice "users/bob/contexts/ctx-100/uploads/x.png"))
    "pathBelongsToUser rejects another user's prefix"
  assert
    (ObjLayout.pathBelongsToUser bob "users/bob/contexts/ctx-200/generated/y.wav")
    "pathBelongsToUser admits bob's own prefix"

  -- Presigned URL minting determinism
  let cfg =
        ObjPresigned.PresignedUrlConfig
          { ObjPresigned.presignedEndpoint = "infernix-minio:9000",
            ObjPresigned.presignedRegion = "us-east-1",
            ObjPresigned.presignedAccessKeyId = "AKIAIOSFODNN7EXAMPLE",
            ObjPresigned.presignedSecretAccessKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            ObjPresigned.presignedExpirySeconds = 900
          }
      fixedNow = Data.Time.Clock.POSIX.posixSecondsToUTCTime 1_700_000_000
      url1 = ObjPresigned.presignedPutUrl cfg fixedNow upload
      url2 = ObjPresigned.presignedPutUrl cfg fixedNow upload
  assert
    (url1 == url2)
    "presigned URL minting is deterministic given the same inputs"
  assert
    ("X-Amz-Signature=" `Text.isInfixOf` ObjPresigned.unPresignedUrl url1)
    "presigned URL carries the X-Amz-Signature query parameter"
  assert
    ("X-Amz-Algorithm=AWS4-HMAC-SHA256" `Text.isInfixOf` ObjPresigned.unPresignedUrl url1)
    "presigned URL declares the AWS4-HMAC-SHA256 algorithm"
  assert
    ("X-Amz-Expires=900" `Text.isInfixOf` ObjPresigned.unPresignedUrl url1)
    "presigned URL records the supplied expiry"

  -- Different method -> different signature
  let getUrl = ObjPresigned.presignedGetUrl cfg fixedNow upload
  assert
    (ObjPresigned.unPresignedUrl url1 /= ObjPresigned.unPresignedUrl getUrl)
    "presigned URL for PUT differs from presigned URL for GET on the same object"

  -- Different object -> different signature
  let otherObject = ObjLayout.uploadObjectKey alice ctx "different.png"
      otherUrl = ObjPresigned.presignedPutUrl cfg fixedNow otherObject
  assert
    (ObjPresigned.unPresignedUrl url1 /= ObjPresigned.unPresignedUrl otherUrl)
    "presigned URL differs when the underlying object key differs"

  -- ISO expiry
  let expiry = ObjPresigned.isoExpiryFor cfg fixedNow
  assert
    (expiry == "2023-11-14T22:28:20Z")
    "ISO expiry is now + expirySeconds in UTC"

assertDemoBucketBootstrap :: IO ()
assertDemoBucketBootstrap = do
  assert
    (DemoBootstrap.requiredDemoBuckets == ["infernix-models", "infernix-demo-objects"])
    "demo bucket bootstrap targets infernix-models + infernix-demo-objects"
  let fromEmpty = DemoBootstrap.planDemoBucketBootstrap []
  assert
    (DemoBootstrap.planMissingBuckets fromEmpty == ["infernix-models", "infernix-demo-objects"])
    "all required buckets are missing from an empty MinIO"
  let halfPresent = DemoBootstrap.planDemoBucketBootstrap ["infernix-models", "harbor-registry"]
  assert
    (DemoBootstrap.planMissingBuckets halfPresent == ["infernix-demo-objects"])
    "only the absent buckets land in the missing-list"
  let fullyPresent = DemoBootstrap.planDemoBucketBootstrap ["infernix-models", "infernix-demo-objects", "harbor-registry"]
  assert
    (null (DemoBootstrap.planMissingBuckets fullyPresent))
    "no work needed when every required bucket is already present"

assertBootstrapModels :: IO ()
assertBootstrapModels = do
  let req =
        BootstrapModels.ModelBootstrapRequest
          { BootstrapModels.bootstrapRequestModelId = "qwen2.5-7b",
            BootstrapModels.bootstrapRequestDownloadUrl = "https://huggingface.co/qwen2.5-7b",
            BootstrapModels.bootstrapRequestRequestedAtIso8601 = "2026-05-21T00:00:00Z"
          }
      ev =
        BootstrapModels.ModelBootstrapReadyEvent
          { BootstrapModels.readyEventModelId = "qwen2.5-7b",
            BootstrapModels.readyEventReadyAtIso8601 = "2026-05-21T00:01:00Z"
          }
  assert
    (BootstrapModels.bootstrapSubscriptionName == "bootstrap-models")
    "bootstrap-models subscription name is the supported label"
  assert
    (BootstrapModels.bootstrapRequestDedupKey req == "qwen2.5-7b")
    "bootstrap request dedup key is the modelId"
  assert
    (BootstrapModels.readyEventDedupKey ev == "qwen2.5-7b")
    "ready event dedup key is the modelId"
  assert
    (BootstrapModels.bootstrapReadyTopicFor "persistent://infernix/system" "qwen2.5-7b" == "persistent://infernix/system/model.bootstrap.ready.qwen2.5-7b")
    "ready topic name follows the supported infernix/system namespace pattern"
  assert
    (BootstrapModels.modelFileObjectKey "qwen2.5-7b" "tokenizer.json" == "qwen2.5-7b/tokenizer.json")
    "model file key follows <modelId>/<filename>"
  assert
    (BootstrapModels.readySentinelFilename == ".ready")
    "ready sentinel filename is .ready"
  assert
    (BootstrapModels.isReadySentinel "qwen2.5-7b/.ready")
    "isReadySentinel recognises the supported sentinel path"
  assert
    (not (BootstrapModels.isReadySentinel "qwen2.5-7b/tokenizer.json"))
    "isReadySentinel rejects ordinary model files"

assertDemoAuthRealm :: IO ()
assertDemoAuthRealm = do
  let cfg = DemoAuth.defaultInfernixRealmConfig
  assert
    (DemoAuth.realmIssuerUrl cfg == "http://localhost:9090/auth/realms/infernix")
    "default Keycloak realm issuer URL is base + /realms/<realm>"
  assert
    (DemoAuth.realmJwksUrl cfg == "http://localhost:9090/auth/realms/infernix/protocol/openid-connect/certs")
    "default Keycloak realm JWKS URL follows OpenID Connect convention"
  let validation = DemoAuth.realmValidationConfig cfg
  assert
    (Jwt.unJwtIssuer (Jwt.jwtValidationIssuer validation) == DemoAuth.realmIssuerUrl cfg)
    "JwtValidationConfig issuer matches the realm issuer URL"
  assert
    (Jwt.unJwtAudience (Jwt.jwtValidationAudience validation) == "infernix-demo")
    "JwtValidationConfig audience matches the realm client id"

assertResultBridgeAndBatchTopics :: IO ()
assertResultBridgeAndBatchTopics = do
  -- canonicalBatchTopicForMode now defined for every substrate
  assert
    (canonicalBatchTopicForMode AppleSilicon == "persistent://public/default/inference.batch.apple-silicon")
    "canonicalBatchTopicForMode emits the supported topic name for apple-silicon"
  assert
    (canonicalBatchTopicForMode LinuxCpu == "persistent://public/default/inference.batch.linux-cpu")
    "canonicalBatchTopicForMode emits the supported topic name for linux-cpu"
  assert
    (canonicalBatchTopicForMode LinuxGpu == "persistent://public/default/inference.batch.linux-gpu")
    "canonicalBatchTopicForMode emits the supported topic name for linux-gpu"

  -- Result-bridge subscription naming
  let bridgeConfig =
        ResultBridge.ResultBridgeConfig
          { ResultBridge.resultBridgeSubstrate = "linux-cpu",
            ResultBridge.resultBridgeResultTopic = "persistent://public/default/inference.result.linux-cpu",
            ResultBridge.resultBridgeConversationTopicNamespace = "infernix/demo"
          }
  assert
    (ResultBridge.bridgeSubscriptionName bridgeConfig == "result-bridge-linux-cpu")
    "result-bridge Failover subscription name is result-bridge-<substrate>"

  -- Dedup key derivation
  assert
    (ResultBridge.resultDedupKey (Contracts.MessageId "msg-42") == "inference-result:msg-42")
    "result-bridge dedup key encodes the userPromptMessageId"

  -- ConversationEvent construction
  let event =
        ResultBridge.inferenceResultEventFor
          (Contracts.MessageId "p-1")
          "Completed"
          (Just "done")
          []
  case event of
    Contracts.ConversationInferenceResultEvent payload -> do
      assert
        (Contracts.inferenceResultUserPromptMessageId payload == Contracts.MessageId "p-1")
        "result-bridge event carries the user prompt message id"
      assert
        (Contracts.inferenceResultStatus payload == "Completed")
        "result-bridge event carries the result status"
      assert
        (Contracts.inferenceResultInlineOutput payload == Just "done")
        "result-bridge event carries the inline output"
    _ -> fail "inferenceResultEventFor should produce a ConversationInferenceResultEvent"

mangleLastChar :: Text.Text -> Text.Text
mangleLastChar token =
  let lastDotIndex = Text.length token - Text.length (Text.takeWhileEnd (/= '.') token) - 1
      headerAndPayload = Text.take (lastDotIndex + 1) token
      signaturePart = Text.drop (lastDotIndex + 1) token
      mid = Text.length signaturePart `div` 2
      before = Text.take mid signaturePart
      midChar = Text.index signaturePart mid
      after = Text.drop (mid + 1) signaturePart
      replacement = if midChar == 'A' then 'B' else 'A'
   in headerAndPayload <> before <> Text.singleton replacement <> after

signJwt :: Crypto.PubKey.RSA.PrivateKey -> String -> Aeson.Value -> Text.Text
signJwt privateKey kid claimsValue =
  let headerJson = Aeson.encode (Aeson.object ["alg" Aeson..= ("RS256" :: String), "typ" Aeson..= ("JWT" :: String), "kid" Aeson..= kid])
      payloadJson = Aeson.encode claimsValue
      headerB64 = base64UrlText (Lazy.toStrict headerJson)
      payloadB64 = base64UrlText (Lazy.toStrict payloadJson)
      signingInput = TextEncoding.encodeUtf8 (headerB64 <> "." <> payloadB64)
      signatureResult =
        Crypto.PubKey.RSA.PKCS15.sign Nothing (Just Crypto.Hash.Algorithms.SHA256) privateKey signingInput
   in assembleSignedJwt headerB64 payloadB64 signatureResult

assembleSignedJwt :: Text.Text -> Text.Text -> Either Crypto.PubKey.RSA.Error BS.ByteString -> Text.Text
assembleSignedJwt _ _ (Left err) = error ("signJwt failed: " <> show err)
assembleSignedJwt headerB64 payloadB64 (Right signatureBytes) =
  headerB64 <> "." <> payloadB64 <> "." <> base64UrlText signatureBytes

base64UrlText :: BS.ByteString -> Text.Text
base64UrlText =
  Text.dropWhileEnd (== '=')
    . TextEncoding.decodeUtf8
    . Data.ByteString.Base64.URL.encode

integerToBytes :: Integer -> BS.ByteString
integerToBytes n
  | n == 0 = BS.singleton 0
  | otherwise = BS.pack (reverse (go n))
  where
    go 0 = []
    go x = fromIntegral (x `mod` 256) : go (x `div` 256)

expectRight :: String -> Either String a -> IO a
expectRight _ (Right value) = pure value
expectRight context (Left err) = fail (context <> ": " <> err)

assertUniqueModelIds :: RuntimeMode -> IO ()
assertUniqueModelIds mode = do
  let modelsForMode = catalogForMode mode
      identifiers = map modelId modelsForMode
      matrixRows = map matrixRowId modelsForMode
  assert (length identifiers == length (nub identifiers)) ("catalog model ids are unique for " <> show mode)
  assert (length matrixRows == length (nub matrixRows)) ("catalog matrix rows are unique for " <> show mode)

renderPayloadText :: Paths -> ResultPayload -> IO String
renderPayloadText paths payloadValue =
  case inlineOutput payloadValue of
    Just outputText -> pure (Text.unpack outputText)
    Nothing ->
      case objectRef payloadValue of
        Just objectRefValue -> readFile (objectStoreRoot paths </> Text.unpack objectRefValue)
        Nothing -> pure ""

sampleRenderedChart :: String
sampleRenderedChart =
  unlines
    [ "---",
      "apiVersion: apps/v1",
      "kind: Deployment",
      "metadata:",
      "  name: infernix-service",
      "spec:",
      "  template:",
      "    spec:",
      "      initContainers:",
      "        - name: prepare",
      "          image: docker.io/library/busybox:1.36",
      "      containers:",
      "        - name: service",
      "          image: infernix-linux-cpu:local",
      "---",
      "apiVersion: apps/v1",
      "kind: StatefulSet",
      "metadata:",
      "  name: infernix-minio",
      "  namespace: platform",
      "  labels:",
      "    release: infernix",
      "spec:",
      "  replicas: 2",
      "  volumeClaimTemplates:",
      "    - metadata:",
      "        name: data",
      "      spec:",
      "        storageClassName: infernix-manual",
      "        resources:",
      "          requests:",
      "            storage: 7Gi",
      "---",
      "apiVersion: v1",
      "kind: PersistentVolumeClaim",
      "metadata:",
      "  name: infernix-service-0-data",
      "  namespace: platform",
      "  labels:",
      "    infernix.io/release: infernix",
      "    infernix.io/workload: service",
      "    infernix.io/ordinal: \"0\"",
      "    infernix.io/claim: data",
      "spec:",
      "  storageClassName: infernix-manual",
      "  resources:",
      "    requests:",
      "      storage: 5Gi",
      "---",
      "apiVersion: pgv2.percona.com/v2",
      "kind: PerconaPGCluster",
      "metadata:",
      "  name: harbor-postgresql",
      "spec:",
      "  image: docker.io/percona/percona-distribution-postgresql:18.3-1",
      "  instances:",
      "    - name: instance1",
      "      dataVolumeClaimSpec:",
      "        storageClassName: infernix-manual"
    ]

sampleHarborOverlay :: String
sampleHarborOverlay =
  unlines
    [ "service:",
      "  image:",
      "    registry: harbor.local",
      "    repository: library/infernix-linux-cpu",
      "    tag: sha256-runtime",
      "demo:",
      "  image:",
      "    registry: harbor.local",
      "    repository: library/infernix-linux-cpu",
      "    tag: sha256-runtime",
      "minio:",
      "  image:",
      "    registry: harbor.local",
      "    repository: library/bitnamilegacy/minio",
      "    tag: sha256-minio",
      "  defaultInitContainers:",
      "    volumePermissions:",
      "      image:",
      "        registry: harbor.local",
      "        repository: library/bitnamilegacy/os-shell",
      "        tag: sha256-shell",
      "  console:",
      "    image:",
      "      registry: harbor.local",
      "      repository: library/bitnamilegacy/minio-object-browser",
      "      tag: sha256-console",
      "  clientImage:",
      "    registry: harbor.local",
      "    repository: library/bitnamilegacy/minio-client",
      "    tag: sha256-client",
      "pulsar:",
      "  defaultPulsarImageRepository: harbor.local/library/apachepulsar/pulsar-all",
      "  defaultPulsarImageTag: sha256-pulsar"
    ]

-- type PublishedImage = (String, String)
samplePublishedImages :: Map.Map String PublishedImage
samplePublishedImages =
  Map.fromList
    [ ("infernix-linux-cpu:local", ("harbor.local/library/infernix-linux-cpu", "sha256-runtime")),
      ("docker.io/bitnamilegacy/minio:2025.7.23-debian-12-r3", ("harbor.local/library/bitnamilegacy/minio", "sha256-minio")),
      ("docker.io/bitnamilegacy/os-shell:12-debian-12-r50", ("harbor.local/library/bitnamilegacy/os-shell", "sha256-shell")),
      ("docker.io/bitnamilegacy/minio-object-browser:2.0.2-debian-12-r3", ("harbor.local/library/bitnamilegacy/minio-object-browser", "sha256-console")),
      ("docker.io/bitnamilegacy/minio-client:2025.7.21-debian-12-r2", ("harbor.local/library/bitnamilegacy/minio-client", "sha256-client")),
      ("docker.io/apachepulsar/pulsar-all:4.0.9", ("harbor.local/library/apachepulsar/pulsar-all", "sha256-pulsar")),
      ("docker.io/percona/percona-postgresql-operator:2.9.0", ("harbor.local/library/percona/percona-postgresql-operator", "sha256-pg-operator")),
      ("docker.io/percona/percona-distribution-postgresql:18.3-1", ("harbor.local/library/percona/percona-distribution-postgresql", "sha256-pg-db")),
      ("docker.io/percona/percona-pgbouncer:1.25.1-1", ("harbor.local/library/percona/percona-pgbouncer", "sha256-pgbouncer")),
      ("docker.io/percona/percona-pgbackrest:2.58.0-1", ("harbor.local/library/percona/percona-pgbackrest", "sha256-pgbackrest"))
    ]

sampleDockerImageInspect :: String
sampleDockerImageInspect =
  unlines
    [ "[",
      "  {",
      "    \"RepoDigests\": [\"docker.io/library/busybox@sha256:deadbeef\"],",
      "    \"Id\": \"sha256:fallback\"",
      "  }",
      "]"
    ]

sampleDockerImageInspectWithoutRepoDigest :: String
sampleDockerImageInspectWithoutRepoDigest =
  unlines
    [ "[",
      "  {",
      "    \"RepoDigests\": [],",
      "    \"Id\": \"sha256:fallback\"",
      "  }",
      "]"
    ]
