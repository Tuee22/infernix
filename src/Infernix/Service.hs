module Infernix.Service
  ( runService,
  )
where

import Infernix.Config
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.Runtime.Pulsar (runProductionDaemon)
import Infernix.Types (RuntimeMode (AppleSilicon))

runService :: Maybe RuntimeMode -> IO ()
runService maybeRuntimeMode = do
  paths <- discoverPaths
  ensureRepoLayout paths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  ensureSupportedRuntimeModeForExecutionContext paths runtimeMode
  whenAppleRuntimeReady paths runtimeMode
  runProductionDaemon paths runtimeMode

whenAppleRuntimeReady :: Paths -> RuntimeMode -> IO ()
whenAppleRuntimeReady paths runtimeMode =
  case runtimeMode of
    AppleSilicon -> ensureAppleSiliconRuntimeReady paths
    _ -> pure ()
