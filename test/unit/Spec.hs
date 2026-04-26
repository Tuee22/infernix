{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (finally, try)
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.List (dropWhileEnd, find, nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as Text
import Infernix.CLI (extractRuntimeMode)
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages
  ( PublishedImage,
    contentAddressTagFromInspectPayload,
    normalizeRepositoryPath,
    writeHarborOverridesFile,
  )
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Edge (edgeTargetForPath)
import Infernix.Gateway
  ( harborGatewayTargetForPath,
    minioGatewayTargetForPath,
    pulsarGatewayTargetForPath,
  )
import Infernix.HttpProxy (ProxyTarget (..))
import Infernix.Models
import Infernix.Runtime
import Infernix.Runtime.Worker (engineCommandOverrideEnvironmentName)
import Infernix.Types
import System.Directory
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process (readProcess)

main :: IO ()
main = do
  unitTestRoot <- testRootPath "unit"
  assert (length (catalogForMode AppleSilicon) == 15) "apple-silicon catalog count matches the matrix"
  assert (length (catalogForMode LinuxCpu) == 12) "linux-cpu catalog count matches the matrix"
  assert (length (catalogForMode LinuxCuda) == 16) "linux-cuda catalog count matches the matrix"
  assert (isJust (findModel LinuxCuda "llm-qwen25-awq")) "linux-cuda includes the AWQ row"
  assert (isNothing (findModel AppleSilicon "llm-qwen25-awq")) "apple-silicon omits unsupported AWQ rows"
  assert
    (extractRuntimeMode ["--runtime-mode", "linux-cpu", "cluster", "status"] == Right (Just LinuxCpu, ["cluster", "status"]))
    "CLI parsing accepts --runtime-mode before the command family"
  assert
    (extractRuntimeMode ["cluster", "status", "--runtime-mode", "linux-cuda"] == Right (Just LinuxCuda, ["cluster", "status"]))
    "CLI parsing accepts --runtime-mode after the command family"
  assert (extractRuntimeMode ["--runtime-mode"] == Left "Missing value for --runtime-mode") "CLI parsing rejects a missing runtime mode value"
  assert (extractRuntimeMode ["--runtime-mode", "bogus"] == Left "Unsupported runtime mode: bogus") "CLI parsing rejects unsupported runtime modes"
  assertUniqueModelIds AppleSilicon
  assertUniqueModelIds LinuxCpu
  assertUniqueModelIds LinuxCuda
  withTestRoot unitTestRoot $ do
    paths <- discoverPaths
    ensureRepoLayout paths
    let demoConfig =
          DemoConfig
            { configRuntimeMode = LinuxCpu,
              configEdgePort = 9090,
              configMapName = "infernix-demo-config",
              generatedPath = "./.build/infernix-demo-linux-cpu.dhall",
              mountedPath = "/opt/build/infernix-demo-linux-cpu.dhall",
              demoUiEnabled = True,
              requestTopics = requestTopicsForMode LinuxCpu,
              resultTopic = resultTopicForMode LinuxCpu,
              engines = engineBindingsForMode LinuxCpu,
              models = catalogForMode LinuxCpu
            }
        demoConfigPath = buildRoot paths </> "demo-config-test.dhall"
    createDirectoryIfMissing True (buildRoot paths)
    Lazy.writeFile demoConfigPath (encodeDemoConfig demoConfig)
    decodedConfig <- decodeDemoConfigFile demoConfigPath
    assert (configRuntimeMode decodedConfig == LinuxCpu) "demo-config decode preserves runtime mode"
    assert (demoUiEnabled decodedConfig) "demo-config decode preserves the demo UI flag"
    assert (requestTopics decodedConfig == requestTopicsForMode LinuxCpu) "demo-config decode preserves request topics"
    assert (resultTopic decodedConfig == resultTopicForMode LinuxCpu) "demo-config decode preserves the result topic"
    assert (engines decodedConfig == engineBindingsForMode LinuxCpu) "demo-config decode preserves engine bindings"
    assert (length (models decodedConfig) == length (catalogForMode LinuxCpu)) "demo-config decode preserves the model list"

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
        case objectRef (payload result) of
          Just objectRefValue -> do
            durableOutput <- readFile (objectStoreRoot paths </> Text.unpack objectRefValue)
            assert
              (durableOutput == replicate 96 'x')
              "python-native worker execution uses the process-isolated typed adapter path by default"
          Nothing -> fail "expected an object-store-backed output for the long inference result"
        manifests <- listCacheManifests paths AppleSilicon
        let maybeManifest = find ((== "llm-qwen25-safetensors") . cacheModelId) manifests
        assert (isJust maybeManifest) "inference execution materializes a cache manifest"
        evictedCount <- evictCache paths AppleSilicon (Just "llm-qwen25-safetensors")
        assert (evictedCount == 1) "cache eviction removes the selected cache entry"
        rebuiltEntries <- rebuildCache paths AppleSilicon (Just "llm-qwen25-safetensors")
        assert (length rebuiltEntries == 1) "cache rebuild restores the selected cache entry"

    let overrideModel = maybe (fail "expected the apple-silicon qwen row") pure (findModel AppleSilicon "llm-qwen25-safetensors")
    overrideModelDescriptor <- overrideModel
    let overrideBinding = engineBindingForSelectedEngine (selectedEngine overrideModelDescriptor)
        overrideEnvName = engineCommandOverrideEnvironmentName overrideBinding
        overrideMarkerPath = buildRoot paths </> "worker-override-used.txt"
        overrideWrapperPath = buildRoot paths </> "python-worker-wrapper.sh"
    workerPython <- resolveWorkerPython paths
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
    withOptionalEnv overrideEnvName (Just (overrideWrapperPath <> " " <> workerPython)) $ do
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
          assert
            (inlineOutput (payload result) == Just "override payload")
            "adapter-specific command overrides still execute the selected worker path"
          markerExists <- doesFileExist overrideMarkerPath
          assert markerExists "adapter-specific command overrides invoke the configured worker wrapper"

    writeFile "invalid-demo-config.dhall" "{\"runtimeMode\":\"apple-silicon\",\"models\":[]}\n"
    invalidConfigResult <- try (decodeDemoConfigFile "invalid-demo-config.dhall") :: IO (Either IOError DemoConfig)
    assert (either (const True) (const False) invalidConfigResult) "invalid demo configs are rejected"

    writeFile "rendered-chart.yaml" sampleRenderedChart
    discoveredImages <- discoverChartImagesFile "rendered-chart.yaml"
    assert
      ( discoveredImages
          == [ "docker.io/library/busybox:1.36",
               "docker.io/percona/percona-distribution-postgresql:18.3-1",
               "infernix-service:local"
             ]
      )
      "rendered chart image discovery returns sorted unique image refs"
    discoveredClaims <- discoverChartClaimsFile "rendered-chart.yaml"
    assert (length discoveredClaims == 3) "rendered chart claim discovery finds explicit and StatefulSet claims"
    assert
      ( map pvcName discoveredClaims
          == [ "data-infernix-minio-0",
               "data-infernix-minio-1",
               "infernix-service-0-data"
             ]
      )
      "rendered chart claim discovery preserves normalized PVC names"

    writeFile "harbor-overlay.yaml" sampleHarborOverlay
    overlayImages <- discoverHarborOverlayImageRefsFile "harbor-overlay.yaml"
    assert
      ( overlayImages
          == [ "harbor.local/library/infernix-service:sha256-service",
               "harbor.local/library/infernix-web:sha256-web",
               "harbor.local/library/bitnamilegacy/minio:sha256-minio",
               "harbor.local/library/bitnamilegacy/os-shell:sha256-shell",
               "harbor.local/library/bitnamilegacy/minio-object-browser:sha256-console",
               "harbor.local/library/bitnamilegacy/minio-client:sha256-client",
               "harbor.local/library/apachepulsar/pulsar-all:sha256-pulsar"
             ]
      )
      "Harbor overlay discovery returns the routed image refs"
    writeHarborOverridesFile samplePublishedImages "generated-harbor-overrides.yaml"
    generatedOverlayImages <- discoverHarborOverlayImageRefsFile "generated-harbor-overrides.yaml"
    assert
      ( generatedOverlayImages
          == [ "harbor.local/library/infernix-service:sha256-service",
               "harbor.local/library/infernix-web:sha256-web",
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
      (contentAddressTagFromInspectPayload sampleDockerImageInspect == Right "sha256-deadbeef")
      "docker inspect parsing prefers repo digests for content-addressed tags"
    assert
      (contentAddressTagFromInspectPayload sampleDockerImageInspectWithoutRepoDigest == Right "sha256-fallback")
      "docker inspect parsing falls back to the image id when no repo digest is present"

    assertProxyTarget
      (edgeTargetForPath (Just "http://demo:18081") (Just "http://web:8080") "http://harbor:8080" "http://minio:9001" "http://pulsar:8080" "/api/models")
      "http://demo:18081"
      "/api/models"
      "edge proxy sends API paths to the demo upstream"
    assertProxyTarget
      (edgeTargetForPath (Just "http://demo:18081") (Just "http://web:8080") "http://harbor:8080" "http://minio:9001" "http://pulsar:8080" "/objects/result.pb")
      "http://demo:18081"
      "/objects/result.pb"
      "edge proxy sends object paths to the demo upstream"
    assertProxyTarget
      (edgeTargetForPath (Just "http://demo:18081") (Just "http://web:8080") "http://harbor:8080" "http://minio:9001" "http://pulsar:8080" "/harbor/api/v2.0/projects")
      "http://harbor:8080"
      "/harbor/api/v2.0/projects"
      "edge proxy sends Harbor paths to the Harbor gateway"
    assertProxyTarget
      (edgeTargetForPath (Just "http://demo:18081") (Just "http://web:8080") "http://harbor:8080" "http://minio:9001" "http://pulsar:8080" "/")
      "http://demo:18081"
      "/"
      "edge proxy sends the browser root to the demo upstream"
    assertProxyTarget
      (edgeTargetForPath Nothing (Just "http://web:8080") "http://harbor:8080" "http://minio:9001" "http://pulsar:8080" "/")
      "http://web:8080"
      "/"
      "edge proxy falls back to the web upstream when no demo upstream is configured"
    assert
      ( isNothing
          (edgeTargetForPath Nothing (Just "http://web:8080") "http://harbor:8080" "http://minio:9001" "http://pulsar:8080" "/api/models")
      )
      "edge proxy leaves demo API paths unpublished when no demo upstream is configured"

    assertProxyTarget
      (harborGatewayTargetForPath "http://harbor-ui:8080" "http://harbor-core:8080" "Basic dGVzdA==" "/harbor/api/v2.0/projects")
      "http://harbor-core:8080"
      "/api/v2.0/projects"
      "Harbor gateway strips the routed prefix before proxying"
    assertProxyHeader
      (harborGatewayTargetForPath "http://harbor-ui:8080" "http://harbor-core:8080" "Basic dGVzdA==" "/harbor/api/v2.0/projects")
      "Basic dGVzdA=="
      "Harbor gateway injects the configured basic-auth header for API traffic"
    assertProxyTarget
      (harborGatewayTargetForPath "http://harbor-ui:8080" "http://harbor-core:8080" "Basic dGVzdA==" "/harbor")
      "http://harbor-ui:8080"
      "/"
      "Harbor gateway normalizes the bare routed prefix to root"
    assertProxyTarget
      (minioGatewayTargetForPath "http://minio-console:9001" "http://minio-s3:9000" "/minio/console/browser")
      "http://minio-console:9001"
      "/browser"
      "MinIO gateway routes console requests to the console upstream"
    assertProxyTarget
      (minioGatewayTargetForPath "http://minio-console:9001" "http://minio-s3:9000" "/minio/s3/models")
      "http://minio-s3:9000"
      "/models"
      "MinIO gateway routes S3 requests to the S3 upstream"
    assertProxyTarget
      (pulsarGatewayTargetForPath "http://pulsar-admin:8080" "http://pulsar-http:8080" "/pulsar/admin/clusters")
      "http://pulsar-admin:8080"
      "/clusters"
      "Pulsar gateway routes admin requests to the admin upstream"
    assertProxyTarget
      (pulsarGatewayTargetForPath "http://pulsar-admin:8080" "http://pulsar-http:8080" "/pulsar/ws/v2/producer/public/default/topic")
      "http://pulsar-http:8080"
      "/v2/producer/public/default/topic"
      "Pulsar gateway routes HTTP websocket-surface requests to the broker HTTP upstream"
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

resolveWorkerPython :: Paths -> IO FilePath
resolveWorkerPython paths = do
  poetryEnvPath <- readProcess "poetry" ["--directory", repoRoot paths </> "python", "env", "info", "--path"] ""
  pure (trimTrailingWhitespace poetryEnvPath </> "bin" </> "python")

trimTrailingWhitespace :: String -> String
trimTrailingWhitespace =
  dropWhileEnd (`elem` [' ', '\n', '\r', '\t'])

testRootPath :: FilePath -> IO FilePath
testRootPath suiteName = do
  paths <- discoverPaths
  pure (repoRoot paths </> ".build" </> ("test-" <> suiteName))

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message

assertProxyTarget :: Maybe ProxyTarget -> String -> String -> String -> IO ()
assertProxyTarget maybeTarget expectedBaseUrl expectedPath message =
  case maybeTarget of
    Just target ->
      assert
        (proxyBaseUrl target == expectedBaseUrl && proxyPath target == ByteString8.pack expectedPath)
        message
    Nothing -> fail message

assertProxyHeader :: Maybe ProxyTarget -> String -> String -> IO ()
assertProxyHeader maybeTarget expectedHeaderValue message =
  case maybeTarget of
    Just target ->
      assert
        ( case proxyRequestHeaders target of
            [(_, headerValue)] -> headerValue == ByteString8.pack expectedHeaderValue
            _ -> False
        )
        message
    Nothing -> fail message

assertUniqueModelIds :: RuntimeMode -> IO ()
assertUniqueModelIds mode = do
  let modelsForMode = catalogForMode mode
      identifiers = map modelId modelsForMode
      matrixRows = map matrixRowId modelsForMode
  assert (length identifiers == length (nub identifiers)) ("catalog model ids are unique for " <> show mode)
  assert (length matrixRows == length (nub matrixRows)) ("catalog matrix rows are unique for " <> show mode)

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
      "          image: infernix-service:local",
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
      "    repository: library/infernix-service",
      "    tag: sha256-service",
      "web:",
      "  image:",
      "    registry: harbor.local",
      "    repository: library/infernix-web",
      "    tag: sha256-web",
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

samplePublishedImages :: Map.Map String PublishedImage
samplePublishedImages =
  Map.fromList
    [ ("infernix-service:local", ("harbor.local/library/infernix-service", "sha256-service")),
      ("infernix-web:local", ("harbor.local/library/infernix-web", "sha256-web")),
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
