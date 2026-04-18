{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (finally)
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (isInfixOf, nub)
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
    assert (repoRoot paths /= cwd) "discoverPaths climbs from nested working directories back to the repo root"
    assert (buildRoot paths == expectedBuildRoot) "discoverPaths keeps build artifacts in the active build root"
    result <-
      executeInference
        paths
        AppleSilicon
        InferenceRequest
          { requestModelId = "llm-qwen25-safetensors",
            inputText = Text.replicate 81 "x"
          }
    case result of
      Left err -> fail ("unexpected error: " <> show err)
      Right inferenceResult -> do
        assert (isJust (objectRef (payload inferenceResult))) "large outputs use the object store"
        case objectRef (payload inferenceResult) of
          Nothing -> pure ()
          Just ref -> do
            exists <- doesFileExist (objectStoreRoot paths </> Text.unpack ref)
            assert exists "stored object reference points at a real file"
        resultProtoExists <-
          doesFileExist
            (resultsRoot paths </> Text.unpack (requestId inferenceResult) <> ".pb")
        legacyResultExists <-
          doesFileExist
            (resultsRoot paths </> Text.unpack (requestId inferenceResult) <> ".state")
        assert resultProtoExists "inference execution persists protobuf result files"
        assert (not legacyResultExists) "inference execution no longer writes legacy state result files"
        maybeLoadedResult <- loadInferenceResult paths (requestId inferenceResult)
        case maybeLoadedResult of
          Nothing -> fail "loadInferenceResult must decode the persisted protobuf result"
          Just loadedResult -> do
            assert (requestId loadedResult == requestId inferenceResult) "protobuf result reload preserves request ids"
            assert (resultModelId loadedResult == resultModelId inferenceResult) "protobuf result reload preserves model ids"
            assert (payload loadedResult == payload inferenceResult) "protobuf result reload preserves payload encoding"
        cacheExists <-
          doesFileExist
            (modelCacheRoot paths </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default" </> "materialized.txt")
        assert cacheExists "runtime cache is keyed by runtime mode and model id"
        manifestProtoExists <-
          doesFileExist
            (objectStoreRoot paths </> "manifests" </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default.pb")
        legacyManifestExists <-
          doesFileExist
            (objectStoreRoot paths </> "manifests" </> "apple-silicon" </> "llm-qwen25-safetensors" </> "default.state")
        assert manifestProtoExists "cache materialization persists protobuf manifests"
        assert (not legacyManifestExists) "cache materialization no longer writes legacy state manifests"
        manifests <- listCacheManifests paths AppleSilicon
        assert (any ((== "llm-qwen25-safetensors") . cacheModelId) manifests) "cache materialization writes a durable manifest"
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

assertUniqueModelIds :: RuntimeMode -> IO ()
assertUniqueModelIds mode = do
  let models = catalogForMode mode
      identifiers = map modelId models
      matrixRows = map matrixRowId models
  assert (length identifiers == length (nub identifiers)) ("catalog model ids are unique for " <> show mode)
  assert (length matrixRows == length (nub matrixRows)) ("catalog matrix rows are unique for " <> show mode)
