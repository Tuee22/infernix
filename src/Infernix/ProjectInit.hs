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
  )
where

import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Infernix.Config
  ( Paths,
    discoverPaths,
    ensureRepoLayout,
    runtimeConfigPath,
    targetRuntimeModeForExecutionContext,
    testConfigPath,
  )
import Infernix.DemoConfig
  ( materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    materializeHostSecrets,
    renderGeneratedDemoConfig,
    writeProjectConfigFile,
  )
import Infernix.Types (RuntimeMode)
import System.Directory (doesFileExist)

-- | @infernix init@. Writes @./infernix.dhall@ (runtime substrate for the
-- resolved mode) and @./infernix-host.dhall@ (host manifest). Fails fast if
-- the runtime config already exists unless @--force@; @--if-missing@ makes
-- an existing config a no-op.
runProjectInit :: Maybe RuntimeMode -> Maybe Bool -> Bool -> Bool -> IO ()
runProjectInit maybeRuntimeMode maybeDemoUi force ifMissing = do
  paths <- discoverPaths
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
      let demoUiEnabled = fromMaybe True maybeDemoUi
      writtenRuntime <- materializeGeneratedDemoConfigFile paths runtimeMode demoUiEnabled
      writtenHost <- materializeHostManifestFile paths
      writtenSecrets <- materializeHostSecrets paths
      putStrLn ("init: wrote " <> writtenRuntime)
      putStrLn ("init: wrote " <> writtenHost)
      putStrLn ("init: wrote " <> writtenSecrets)

-- | @infernix test init@. Writes @./infernix.test.dhall@ — the thin config
-- the test harness reads to generate the run's @./infernix.dhall@. Needs no
-- pre-existing runtime config.
runTestInit :: Maybe RuntimeMode -> Maybe Bool -> IO ()
runTestInit maybeRuntimeMode maybeDemoUi = do
  paths <- discoverPaths
  ensureRepoLayout paths
  runtimeMode <- resolveInitRuntimeMode paths maybeRuntimeMode
  let demoUiEnabled = fromMaybe True maybeDemoUi
      testConfig = testConfigPath paths
      payload = renderGeneratedDemoConfig paths runtimeMode demoUiEnabled
  writeProjectConfigFile testConfig payload
  putStrLn ("test init: wrote " <> testConfig)

-- | Resolve the runtime mode for an init: the explicit @--runtime-mode@
-- flag wins; otherwise fall back to the execution-context default (Apple
-- host-native → apple-silicon; Linux outer-container reads the baked
-- substrate, so container init should pass @--runtime-mode@).
resolveInitRuntimeMode :: Paths -> Maybe RuntimeMode -> IO RuntimeMode
resolveInitRuntimeMode paths =
  maybe (targetRuntimeModeForExecutionContext paths) pure
