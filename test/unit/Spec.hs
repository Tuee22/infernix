{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (finally)
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (find, isInfixOf, nub)
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text qualified as Text
import Infernix.CLI (extractRuntimeMode)
import Infernix.Config
import Infernix.Models
import Infernix.Runtime
import Infernix.Types
import System.Directory
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process (readProcessWithExitCode)

main :: IO ()
main = do
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
  assert (all ((== AppleSilicon) . runtimeMode) (catalogForMode AppleSilicon)) "apple-silicon catalog entries carry the apple-silicon mode id"
  assert (all ((== LinuxCpu) . runtimeMode) (catalogForMode LinuxCpu)) "linux-cpu catalog entries carry the linux-cpu mode id"
  assert (all ((== LinuxCuda) . runtimeMode) (catalogForMode LinuxCuda)) "linux-cuda catalog entries carry the linux-cuda mode id"
  assert (not (any requiresGpu (catalogForMode AppleSilicon))) "apple-silicon catalog entries do not claim GPU-only scheduling"
  assert (not (any requiresGpu (catalogForMode LinuxCpu))) "linux-cpu catalog entries do not claim GPU-only scheduling"
  assert (any requiresGpu (catalogForMode LinuxCuda)) "linux-cuda catalog entries expose GPU-bound scheduling metadata"
  let demoConfig =
        DemoConfig
          { configRuntimeMode = LinuxCpu,
            configEdgePort = 9090,
            configMapName = "infernix-demo-config",
            generatedPath = "./.build/infernix-demo-linux-cpu.dhall",
            mountedPath = "/opt/build/infernix-demo-linux-cpu.dhall",
            models = catalogForMode LinuxCpu
          }
  assert
    (any ("\"runtimeMode\": \"linux-cpu\"" `isInfixOf`) (lines (LazyChar8.unpack (encodeDemoConfig demoConfig))))
    "demo config render includes the active runtime mode"
  withTestRoot ".tmp/unit" $ do
    cwd <- getCurrentDirectory
    paths <- discoverPaths
    ensureRepoLayout paths
    maybeBuildRootEnv <- lookupEnv "INFERNIX_BUILD_ROOT"
    let expectedBuildRoot = fromMaybe (repoRoot paths </> ".build") maybeBuildRootEnv
        request =
          InferenceRequest
            { requestModelId = "llm-qwen25-safetensors",
              inputText = Text.replicate 81 "x"
            }
        validateLoadedResult inferenceResult loadedResult = do
          assert (requestId loadedResult == requestId inferenceResult) "protobuf result reload preserves request ids"
          assert (resultModelId loadedResult == resultModelId inferenceResult) "protobuf result reload preserves model ids"
          assert (payload loadedResult == payload inferenceResult) "protobuf result reload preserves payload encoding"
        failUnexpected err = fail ("unexpected error: " <> show err)
        validateInferenceResult inferenceResult = do
          let maybeObjectRef = objectRef (payload inferenceResult)
              checkObjectRef ref = do
                exists <- doesFileExist (objectStoreRoot paths </> Text.unpack ref)
                assert exists "stored object reference points at a real file"
          assert (isJust maybeObjectRef) "large outputs use the object store"
          maybe (pure ()) checkObjectRef maybeObjectRef
          resultProtoExists <-
            doesFileExist
              (resultsRoot paths </> Text.unpack (requestId inferenceResult) <> ".pb")
          legacyResultExists <-
            doesFileExist
              (resultsRoot paths </> Text.unpack (requestId inferenceResult) <> ".state")
          assert resultProtoExists "inference execution persists protobuf result files"
          assert (not legacyResultExists) "inference execution no longer writes legacy state result files"
          maybeLoadedResult <- loadInferenceResult paths (requestId inferenceResult)
          maybe
            (fail "loadInferenceResult must decode the persisted protobuf result")
            (validateLoadedResult inferenceResult)
            maybeLoadedResult
          cacheExists <-
            doesFileExist
              (modelCacheRoot paths </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default" </> "materialized.txt")
          assert cacheExists "runtime cache is keyed by runtime mode and model id"
          let durableArtifactPath =
                objectStoreRoot paths </> "artifacts" </> "apple-silicon" </> "llm-qwen25-safetensors" </> "bundle.json"
          durableArtifactExists <- doesFileExist durableArtifactPath
          assert durableArtifactExists "inference execution materializes a durable artifact bundle for the selected model"
          durableArtifactContents <- readFile durableArtifactPath
          assert ("\"engineAdapterId\": \"pytorch-python\"" `isInfixOf` durableArtifactContents) "durable artifact bundles record the selected engine adapter id"
          assert ("\"artifactAcquisitionMode\": \"local-file-copy\"" `isInfixOf` durableArtifactContents) "host-side durable artifact bundles use explicit local source-artifact copies under fixture overrides"
          assert ("\"sourceArtifactFetchStatus\": \"materialized\"" `isInfixOf` durableArtifactContents) "host-side durable artifact bundles record materialized source-artifact state"
          assert ("\"sourceArtifactSelectionMode\": \"engine-specific-direct-artifact\"" `isInfixOf` durableArtifactContents) "durable artifact bundles record engine-specific source-artifact selection metadata"
          assert ("source-artifacts/apple-silicon/llm-qwen25-safetensors/source.json" `isInfixOf` durableArtifactContents) "host-side durable artifact bundles point at the durable source-artifact manifest"
          assert ("\"sourceArtifactResolvedUrl\": \"file://" `isInfixOf` durableArtifactContents) "durable artifact bundles record the resolved source artifact location"
          assert ("\"sourceArtifactAuthoritativeUri\": \"file://" `isInfixOf` durableArtifactContents) "durable artifact bundles record the authoritative runtime input location"
          assert ("\"sourceArtifactSelectedArtifacts\": [" `isInfixOf` durableArtifactContents) "durable artifact bundles record the selected engine-ready artifacts"
          cacheBundleExists <-
            doesFileExist
              (modelCacheRoot paths </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default" </> "artifact-bundle.json")
          assert cacheBundleExists "runtime cache materialization copies the durable artifact bundle into the derived cache root"
          sourceManifestExists <-
            doesFileExist
              (objectStoreRoot paths </> "source-artifacts" </> "apple-silicon" </> "llm-qwen25-safetensors" </> "source.json")
          assert sourceManifestExists "host-side materialization persists the durable source-artifact manifest"
          manifestProtoExists <-
            doesFileExist
              (objectStoreRoot paths </> "manifests" </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default.pb")
          legacyManifestExists <-
            doesFileExist
              (objectStoreRoot paths </> "manifests" </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default.state")
          assert manifestProtoExists "cache materialization persists protobuf manifests"
          assert (not legacyManifestExists) "cache materialization no longer writes legacy state manifests"
          manifests <- listCacheManifests paths AppleSilicon
          let maybeManifest = find ((== "llm-qwen25-safetensors") . cacheModelId) manifests
          assert (maybe False (("artifacts/apple-silicon/llm-qwen25-safetensors/bundle.json" `isInfixOf`) . Text.unpack . cacheDurableSourceUri) maybeManifest) "cache manifests point at the durable artifact bundle rather than the upstream download URL"
          evictedCount <- evictCache paths AppleSilicon (Just "llm-qwen25-safetensors")
          assert (evictedCount == 1) "cache eviction removes the requested derived cache entry"
          cachePresentAfterEvict <-
            doesFileExist
              (modelCacheRoot paths </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default" </> "materialized.txt")
          assert (not cachePresentAfterEvict) "cache eviction removes the materialized cache marker"
          rebuiltEntries <- rebuildCache paths AppleSilicon (Just "llm-qwen25-safetensors")
          assert (length rebuiltEntries == 1) "cache rebuild restores a manifest-backed cache entry"
          cachePresentAfterRebuild <-
            doesFileExist
              (modelCacheRoot paths </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default" </> "materialized.txt")
          assert cachePresentAfterRebuild "cache rebuild restores the materialized cache marker"
          cacheBundleExistsAfterRebuild <-
            doesFileExist
              (modelCacheRoot paths </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default" </> "artifact-bundle.json")
          assert cacheBundleExistsAfterRebuild "cache rebuild restores the durable artifact bundle into the derived cache root"
        validateJaxArtifactBundle = do
          let jaxRequest =
                InferenceRequest
                  { requestModelId = "music-mt3-jax",
                    inputText = "jax adapter coverage"
                  }
              jaxArtifactPath =
                objectStoreRoot paths </> "artifacts" </> "apple-silicon" </> "music-mt3-jax" </> "bundle.json"
          jaxResult <- executeInference paths AppleSilicon jaxRequest
          case jaxResult of
            Left err -> fail ("unexpected jax inference error: " <> show err)
            Right _ -> pure ()
          jaxArtifactContents <- readFile jaxArtifactPath
          assert ("\"engineAdapterId\": \"jax-python\"" `isInfixOf` jaxArtifactContents) "durable artifact bundles map jax-metal to the explicit jax adapter"
          assert ("\"artifactAcquisitionMode\": \"local-file-copy\"" `isInfixOf` jaxArtifactContents) "host-side durable artifact bundles reuse the explicit source-artifact materialization helper for jax coverage"
          assert ("\"sourceArtifactSelectionMode\": \"engine-specific-direct-artifact\"" `isInfixOf` jaxArtifactContents) "jax artifact bundles record the engine-specific source-artifact selection mode"
    assert (repoRoot paths /= cwd) "discoverPaths climbs from nested working directories back to the repo root"
    assert (buildRoot paths == expectedBuildRoot) "discoverPaths keeps build artifacts in the active build root"
    let qwenSourceFixture = cwd </> "source-fixture.txt"
        jaxSourceFixture = cwd </> "source-fixture-jax.txt"
    writeFile qwenSourceFixture "local source fixture\n"
    writeFile jaxSourceFixture "local jax source fixture\n"
    withSourceArtifactOverrides
      [ ("llm-qwen25-safetensors", "file://" <> qwenSourceFixture),
        ("music-mt3-jax", "file://" <> jaxSourceFixture)
      ]
      $ do
        result <- executeInference paths AppleSilicon request
        either failUnexpected validateInferenceResult result
        validateJaxArtifactBundle
    let runtimeBackendFixtureModeScript =
          unlines
            [ "import pathlib",
              "import sys",
              "sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / 'tools'))",
              "from runtime_backend import RuntimeBackend",
              "data_root = pathlib.Path(sys.argv[2])",
              "paths = {",
              "  'results_root': data_root / 'runtime' / 'results',",
              "  'object_store_root': data_root / 'object-store',",
              "  'model_cache_root': data_root / 'runtime' / 'model-cache',",
              "}",
              "for path in paths.values():",
              "  path.mkdir(parents=True, exist_ok=True)",
              "try:",
              "  RuntimeBackend(paths=paths, runtime_mode='linux-cpu', control_plane_context='host-native', daemon_location='control-plane-host', publication_state={'routes': []})",
              "except RuntimeError as exc:",
              "  print(str(exc))",
              "else:",
              "  raise SystemExit('runtime backend unexpectedly allowed filesystem mode without explicit fixture ownership')"
            ]
    (fixtureModeExitCode, fixtureModeStdout, fixtureModeStderr) <-
      readProcessWithExitCode
        "python3"
        ["-c", runtimeBackendFixtureModeScript, repoRoot paths, cwd </> ".data"]
        ""
    assert (fixtureModeExitCode == ExitSuccess) ("runtime backend explicit fixture-mode requirement is observable: " <> fixtureModeStderr)
    assert ("filesystem-fixture mode must be enabled explicitly" `isInfixOf` fixtureModeStdout) "runtime backend refuses implicit filesystem fallback"
    let runtimeBackendScript =
          unlines
            [ "import json",
              "import pathlib",
              "import sys",
              "sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / 'tools'))",
              "from runtime_backend import RuntimeBackend",
              "repo_root = pathlib.Path(sys.argv[1])",
              "data_root = pathlib.Path(sys.argv[2])",
              "paths = {",
              "  'results_root': data_root / 'runtime' / 'results',",
              "  'object_store_root': data_root / 'object-store',",
              "  'model_cache_root': data_root / 'runtime' / 'model-cache',",
              "}",
              "for path in paths.values():",
              "  path.mkdir(parents=True, exist_ok=True)",
              "backend = RuntimeBackend(paths=paths, runtime_mode='linux-cpu', control_plane_context='host-native', daemon_location='control-plane-host', publication_state={'routes': []}, allow_filesystem_fallback=True)",
              "entry = backend.materialize_cache({",
              "  'matrixRowId': 'fixture-row',",
              "  'modelId': 'fixture-model',",
              "  'displayName': 'Fixture Model',",
              "  'family': 'llm',",
              "  'artifactType': 'fixture',",
              "  'referenceModel': 'fixture',",
              "  'selectedEngine': 'llama.cpp',",
              "  'runtimeLane': 'kind-linux-cpu',",
              "  'downloadUrl': pathlib.Path('source-fixture.txt').resolve().as_uri(),",
              "})",
              "print(json.dumps(entry, sort_keys=True))",
              "backend.close()"
            ]
    (backendExitCode, backendStdout, backendStderr) <-
      readProcessWithExitCode
        "python3"
        ["-c", runtimeBackendScript, repoRoot paths, cwd </> ".data"]
        ""
    assert (backendExitCode == ExitSuccess) ("runtime backend local source materialization succeeds: " <> backendStderr)
    assert ("\"artifactAcquisitionMode\": \"local-file-copy\"" `isInfixOf` backendStdout) "runtime backend records local-file source acquisition in cache status"
    assert ("\"engineAdapterId\": \"llama-cpp-cli\"" `isInfixOf` backendStdout) "runtime backend cache status records engine-specific runner metadata"
    assert ("\"sourceArtifactFetchStatus\": \"materialized\"" `isInfixOf` backendStdout) "runtime backend cache status records materialized source-artifact state"
    assert ("\"sourceArtifactSelectionMode\": \"engine-specific-direct-artifact\"" `isInfixOf` backendStdout) "runtime backend cache status records engine-specific source-artifact selection"
    assert ("\"sourceArtifactSelectedArtifacts\": [" `isInfixOf` backendStdout) "runtime backend cache status exposes selected source artifacts for direct materialization"
    writeFile "remote-fixture.txt" "remote source fixture\n"
    let remoteRuntimeBackendScript =
          unlines
            [ "import functools",
              "import http.server",
              "import json",
              "import pathlib",
              "import sys",
              "import threading",
              "sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / 'tools'))",
              "from runtime_backend import RuntimeBackend",
              "repo_root = pathlib.Path(sys.argv[1])",
              "data_root = pathlib.Path(sys.argv[2])",
              "handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(pathlib.Path.cwd()))",
              "server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)",
              "thread = threading.Thread(target=server.serve_forever, daemon=True)",
              "thread.start()",
              "port = server.server_address[1]",
              "paths = {",
              "  'results_root': data_root / 'runtime' / 'results',",
              "  'object_store_root': data_root / 'object-store',",
              "  'model_cache_root': data_root / 'runtime' / 'model-cache',",
              "}",
              "for path in paths.values():",
              "  path.mkdir(parents=True, exist_ok=True)",
              "backend = RuntimeBackend(paths=paths, runtime_mode='linux-cpu', control_plane_context='host-native', daemon_location='control-plane-host', publication_state={'routes': []}, allow_filesystem_fallback=True)",
              "try:",
              "  entry = backend.materialize_cache({",
              "    'matrixRowId': 'remote-row',",
              "    'modelId': 'remote-model',",
              "    'displayName': 'Remote Model',",
              "    'family': 'llm',",
              "    'artifactType': 'fixture',",
              "    'referenceModel': 'remote',",
              "    'selectedEngine': 'llama.cpp',",
              "    'runtimeLane': 'kind-linux-cpu',",
              "    'downloadUrl': f'http://127.0.0.1:{port}/remote-fixture.txt',",
              "  })",
              "  print(json.dumps(entry, sort_keys=True))",
              "finally:",
              "  backend.close()",
              "  server.shutdown()",
              "  server.server_close()"
            ]
    (remoteExitCode, remoteStdout, remoteStderr) <-
      readProcessWithExitCode
        "python3"
        ["-c", remoteRuntimeBackendScript, repoRoot paths, cwd </> ".data"]
        ""
    assert (remoteExitCode == ExitSuccess) ("runtime backend remote source materialization succeeds: " <> remoteStderr)
    assert ("\"artifactAcquisitionMode\": \"direct-http-download\"" `isInfixOf` remoteStdout) "runtime backend records direct upstream HTTP acquisition in cache status"
    assert ("\"sourceArtifactFetchStatus\": \"materialized\"" `isInfixOf` remoteStdout) "runtime backend records materialized direct upstream source state"
    assert ("\"sourceArtifactSelectionMode\": \"engine-specific-direct-artifact\"" `isInfixOf` remoteStdout) "runtime backend records engine-specific direct-artifact selection for HTTP inputs"
    assert ("\"sourceArtifactSelectedArtifacts\": [" `isInfixOf` remoteStdout) "runtime backend cache status exposes selected source artifacts for direct HTTP materialization"
    let providerSelectionScript =
          unlines
            [ "import json",
              "import pathlib",
              "import sys",
              "sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / 'tools'))",
              "from runtime_backend import select_github_artifacts, select_huggingface_artifacts",
              "hf = select_huggingface_artifacts(",
              "  model={",
              "    'selectedEngine': 'llama.cpp',",
              "    'artifactType': 'GGUF',",
              "    'downloadUrl': 'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',",
              "  },",
              "  payload={",
              "    'modelId': 'TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',",
              "    'metadata': {'siblings': ['tinyllama.Q4_K_M.gguf', 'tokenizer.json', 'README.md']},",
              "  },",
              "  payload_uri='file:///tmp/hf-provider.json',",
              "  resolved_url='https://huggingface.co/api/models/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',",
              ")",
              "gh = select_github_artifacts(",
              "  model={",
              "    'selectedEngine': 'whisper.cpp',",
              "    'artifactType': 'whisper.cpp model set / GGML-style',",
              "    'downloadUrl': 'https://github.com/ggml-org/whisper.cpp/tree/master/models',",
              "  },",
              "  payload={",
              "    'repository': 'ggml-org/whisper.cpp',",
              "    'metadata': {'html_url': 'https://github.com/ggml-org/whisper.cpp', 'default_branch': 'master'},",
              "    'releases': [",
              "      {'assets': [",
              "        {'name': 'ggml-small.en.bin', 'browser_download_url': 'https://github.com/ggml-org/whisper.cpp/releases/download/v1/ggml-small.en.bin', 'content_type': 'application/octet-stream'},",
              "        {'name': 'vocab.json', 'browser_download_url': 'https://github.com/ggml-org/whisper.cpp/releases/download/v1/vocab.json', 'content_type': 'application/json'},",
              "      ]}",
              "    ],",
              "  },",
              "  payload_uri='file:///tmp/github-provider.json',",
              "  resolved_url='https://api.github.com/repos/ggml-org/whisper.cpp',",
              ")",
              "print(json.dumps({",
              "  'hfAuthoritativeUri': hf.authoritative_uri,",
              "  'hfAuthoritativeKind': hf.authoritative_kind,",
              "  'hfSelectedArtifacts': hf.selected_artifacts,",
              "  'ghAuthoritativeUri': gh.authoritative_uri,",
              "  'ghAuthoritativeKind': gh.authoritative_kind,",
              "  'ghSelectedArtifacts': gh.selected_artifacts,",
              "}, sort_keys=True))"
            ]
    (providerExitCode, providerStdout, providerStderr) <-
      readProcessWithExitCode
        "python3"
        ["-c", providerSelectionScript, repoRoot paths]
        ""
    assert (providerExitCode == ExitSuccess) ("provider-backed engine-ready artifact selection succeeds: " <> providerStderr)
    assert ("\"hfAuthoritativeUri\": \"https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama.Q4_K_M.gguf\"" `isInfixOf` providerStdout) "huggingface selection promotes the required engine-ready artifact to the authoritative URI"
    assert ("\"hfAuthoritativeKind\": \"gguf-weights\"" `isInfixOf` providerStdout) "huggingface selection records the authoritative artifact kind"
    assert ("\"ghAuthoritativeUri\": \"https://github.com/ggml-org/whisper.cpp/releases/download/v1/ggml-small.en.bin\"" `isInfixOf` providerStdout) "github selection promotes the required engine-ready artifact to the authoritative URI"
    assert ("\"ghSelectedArtifacts\": [" `isInfixOf` providerStdout) "github selection records the selected artifact inventory"
    writeFile "runner-source.json" (unlines ["{", "  \"selectionMode\": \"engine-specific-huggingface-selection\",", "  \"fetchStatus\": \"materialized\",", "  \"acquisitionMode\": \"huggingface-model-metadata\",", "  \"selectedArtifacts\": [", "    {", "      \"artifactId\": \"tinyllama.Q4_K_M.gguf\",", "      \"artifactKind\": \"gguf-weights\",", "      \"uri\": \"file:///tmp/unit-runner.gguf\",", "      \"required\": true", "    }", "  ]", "}"])
    writeFile "runner-bundle.json" (unlines ["{", "  \"artifactKind\": \"infernix-runtime-bundle\",", "  \"schemaVersion\": 1,", "  \"runtimeMode\": \"linux-cpu\",", "  \"matrixRowId\": \"runner-row\",", "  \"modelId\": \"runner-model\",", "  \"displayName\": \"Runner Model\",", "  \"family\": \"llm\",", "  \"artifactType\": \"GGUF\",", "  \"referenceModel\": \"TinyLlama\",", "  \"selectedEngine\": \"llama.cpp\",", "  \"runtimeLane\": \"kind-linux-cpu\",", "  \"sourceDownloadUrl\": \"https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF\",", "  \"workerProfile\": \"text-generation\",", "  \"engineAdapterId\": \"llama-cpp-cli\",", "  \"engineAdapterType\": \"external-command\",", "  \"engineAdapterLocator\": \"missing-llama-cli\",", "  \"artifactAcquisitionMode\": \"engine-ready-artifact-manifests\",", "  \"sourceArtifactManifestPath\": \"runner-source.json\",", "  \"sourceArtifactSelectionMode\": \"engine-specific-huggingface-selection\",", "  \"sourceArtifactAuthoritativeUri\": \"file:///tmp/unit-runner.gguf\",", "  \"sourceArtifactAuthoritativeKind\": \"gguf-weights\"", "}"])
    (runnerExitCode, runnerStdout, runnerStderr) <-
      readProcessWithExitCode
        "python3"
        [ repoRoot paths </> "tools" </> "final_engine_runner.py",
          "--artifact-bundle",
          "runner-bundle.json",
          "--input-text",
          "runner coverage",
          "--adapter-id",
          "llama-cpp-cli"
        ]
        ""
    assert (runnerExitCode == ExitSuccess) ("engine-specific worker runner reports authoritative artifact selection: " <> runnerStderr)
    assert ("authoritative=gguf-weights" `isInfixOf` runnerStdout) "engine-specific worker runner reports the authoritative artifact kind"
    assert ("artifacts=1:gguf-weights:file:///tmp/unit-runner.gguf" `isInfixOf` runnerStdout) "engine-specific worker runner reports the selected artifact inventory"
    assert ("selection=engine-specific-huggingface-selection" `isInfixOf` runnerStdout) "engine-specific worker runner reports the manifest selection mode"
    writeFile "invalid-demo-config.dhall" "{\"runtimeMode\":\"apple-silicon\",\"models\":[{\"modelId\":\"missing-fields\"}]}\n"
    (exitCode, _, stderrOutput) <-
      readProcessWithExitCode
        "python3"
        [ repoRoot paths </> "tools" </> "service_server.py",
          "--repo-root",
          repoRoot paths,
          "--port",
          "0",
          "--runtime-mode",
          "apple-silicon",
          "--control-plane-context",
          "host-native",
          "--daemon-location",
          "control-plane-host",
          "--catalog-source",
          "generated-build-root",
          "--demo-config",
          cwd </> "invalid-demo-config.dhall",
          "--mounted-demo-config",
          "/opt/build/infernix-demo-apple-silicon.dhall",
          "--publication-state",
          cwd </> "publication.json"
        ]
        ""
    assert (exitCode /= ExitSuccess) "service startup fails on invalid generated demo config metadata"
    assert ("invalid demo config" `isInfixOf` stderrOutput) "service startup reports invalid demo config failures clearly"
  putStrLn "unit tests passed"

withSourceArtifactOverrides :: [(String, String)] -> IO () -> IO ()
withSourceArtifactOverrides overrides action = do
  previousOverrides <- lookupEnv "INFERNIX_SOURCE_ARTIFACT_OVERRIDES"
  let renderedOverrides =
        "{"
          <> unwordsWith ", " [show modelId <> ": " <> show sourceUrl | (modelId, sourceUrl) <- overrides]
          <> "}"
  setEnv "INFERNIX_SOURCE_ARTIFACT_OVERRIDES" renderedOverrides
  action `finally` maybe (unsetEnv "INFERNIX_SOURCE_ARTIFACT_OVERRIDES") (setEnv "INFERNIX_SOURCE_ARTIFACT_OVERRIDES") previousOverrides

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

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message

unwordsWith :: String -> [String] -> String
unwordsWith _ [] = ""
unwordsWith separator values = foldr1 (\left right -> left <> separator <> right) values

assertUniqueModelIds :: RuntimeMode -> IO ()
assertUniqueModelIds mode = do
  let models = catalogForMode mode
      identifiers = map modelId models
      matrixRows = map matrixRowId models
  assert (length identifiers == length (nub identifiers)) ("catalog model ids are unique for " <> show mode)
  assert (length matrixRows == length (nub matrixRows)) ("catalog matrix rows are unique for " <> show mode)
