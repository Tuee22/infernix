{-# LANGUAGE OverloadedStrings #-}

-- | Phase 8: explicit configuration creation. `infernix init` writes the
-- operator's runtime config (@./infernix.dhall@) plus the host manifest
-- (@./infernix-host.dhall@); `infernix test init` writes the thin test
-- config (@./infernix.test.dhall@) the test harness reads. Both share the
-- same defaults (the substrate materializer + host-manifest renderer), so
-- there is one source of truth for the generated shape. Nothing
-- auto-generates config: every other command fails fast when its config is
-- missing (see Phase 8 Sprint 8.3).
module Infernix.ProjectInit
  ( runProjectInit,
    runTestInit,
    resolveDeclaredEngineMachines,
  )
where

import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Infernix.Config
  ( Paths,
    discoverPathsWithHostManifest,
    ensureRepoLayout,
    runtimeConfigPath,
    targetRuntimeModeForExecutionContext,
    testConfigPath,
  )
import Infernix.DemoConfig
  ( materializeBuildMemoryCeilingFile,
    materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    materializeHostSecrets,
    renderGeneratedDemoConfigPayload,
    resolveInferenceMemoryBudget,
    writeProjectConfigFile,
  )
import Infernix.Models (engineMachineCountForMode)
import Infernix.Types (EngineMachineCount, RuntimeMode, singleEngineMachine)
import System.Directory (doesFileExist)

-- | @infernix init@. Writes @./infernix.dhall@ (runtime substrate for the
-- resolved mode) and @./infernix-host.dhall@ (host manifest). Fails fast if
-- the runtime config already exists unless @--force@; @--if-missing@ makes
-- an existing config a no-op.
runProjectInit :: Maybe RuntimeMode -> Maybe Bool -> Maybe Int -> Bool -> Bool -> IO ()
runProjectInit maybeRuntimeMode maybeDemoUi maybeEngineMachines force ifMissing = do
  -- This is deliberately independent of any existing host manifest. The
  -- command is the migration boundary that replaces that manifest, so a stale
  -- schema must not make @init --force@ unreachable.
  paths <- discoverPathsWithHostManifest Nothing
  ensureRepoLayout paths
  let runtimeConfig = runtimeConfigPath paths
  runtimeConfigExists <- doesFileExist runtimeConfig
  if runtimeConfigExists && ifMissing
    then putStrLn ("init: " <> runtimeConfig <> " already present; --if-missing is a no-op")
    else do
      when (runtimeConfigExists && not force) $
        ioError
          ( userError
              ( "project config already exists at "
                  <> runtimeConfig
                  <> "; pass --force to overwrite it"
              )
          )
      runtimeMode <- resolveInitRuntimeMode paths maybeRuntimeMode
      machineCount <- resolveDeclaredEngineMachines runtimeMode maybeEngineMachines
      let demoUiEnabled = fromMaybe True maybeDemoUi
      -- Write the host manifest first: the runtime config's apple-silicon
      -- inference RAM budget uses its manifest-owned sysctl path plus the same
      -- fixed-path Colima observation that measured effective build memory.
      writtenHost <- materializeHostManifestFile paths
      writtenSecrets <- materializeHostSecrets paths
      writtenRuntime <-
        materializeGeneratedDemoConfigFile paths runtimeMode machineCount demoUiEnabled
      -- Phase 1 Sprint 1.21 — the per-machine build ceiling is derived from the
      -- host manifest's measured memory facts, so it is written after it.
      writtenBuildCeiling <- materializeBuildMemoryCeilingFile paths
      putStrLn ("init: wrote " <> writtenRuntime)
      putStrLn ("init: wrote " <> writtenHost)
      putStrLn ("init: wrote " <> writtenSecrets)
      putStrLn ("init: wrote " <> writtenBuildCeiling)

-- | @infernix test init@. Writes @./infernix.test.dhall@ — the thin config
-- the test harness reads to generate the run's @./infernix.dhall@. Needs no
-- pre-existing runtime config.
runTestInit :: Maybe RuntimeMode -> Maybe Bool -> Maybe Int -> IO ()
runTestInit maybeRuntimeMode maybeDemoUi maybeEngineMachines = do
  -- Test initialization is the test-config migration boundary. Like
  -- @init --force@, it must remain reachable when an existing host manifest
  -- belongs to an older schema, so path discovery cannot decode that file.
  paths <- discoverPathsWithHostManifest Nothing
  ensureRepoLayout paths
  runtimeMode <- resolveInitRuntimeMode paths maybeRuntimeMode
  machineCount <- resolveDeclaredEngineMachines runtimeMode maybeEngineMachines
  inferenceMemoryBudgetValue <- resolveInferenceMemoryBudget paths runtimeMode
  let demoUiEnabled = fromMaybe True maybeDemoUi
      testConfig = testConfigPath paths
      payload =
        renderGeneratedDemoConfigPayload
          paths
          runtimeMode
          machineCount
          demoUiEnabled
          inferenceMemoryBudgetValue
  writeProjectConfigFile testConfig payload
  putStrLn ("test init: wrote " <> testConfig)

-- | Phase 8 Sprint 8.12 — resolve @--engine-machines@ against the mode.
--
-- Shared by @init@, @test init@, and the lane-facing
-- @internal materialize-substrate@, so one resolver decides what a fleet may be
-- and every generator entry point refuses the same shapes for the same reason.
--
-- Absent, the fleet is one machine, which is the deployed platform's topology
-- and keeps every generated contract byte identical to what it was before the
-- fleet dimension existed. Present, the count is checked against what the mode
-- can express, and an unsupported fleet is refused by name at the boundary that
-- would otherwise write it into a contract.
resolveDeclaredEngineMachines :: RuntimeMode -> Maybe Int -> IO EngineMachineCount
resolveDeclaredEngineMachines runtimeMode maybeEngineMachines =
  case maybeEngineMachines of
    Nothing -> pure singleEngineMachine
    Just requested ->
      case engineMachineCountForMode runtimeMode requested of
        Right count -> pure count
        Left refusal -> ioError (userError refusal)

-- | Resolve the runtime mode for an init: the explicit @--runtime-mode@
-- flag wins; otherwise fall back to the execution-context default (Apple
-- host-native → apple-silicon; Linux outer-container reads the baked
-- substrate, so container init should pass @--runtime-mode@).
resolveInitRuntimeMode :: Paths -> Maybe RuntimeMode -> IO RuntimeMode
resolveInitRuntimeMode paths =
  maybe (targetRuntimeModeForExecutionContext paths) pure
