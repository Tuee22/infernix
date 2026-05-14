module Infernix.Service
  ( runService,
  )
where

import Data.Maybe (fromMaybe)
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.Runtime.Pulsar (runProductionDaemon)
import Infernix.Types (DaemonRole (ClusterDaemon, HostDaemon), DemoConfig (..), RuntimeMode (AppleSilicon), runtimeModeId)
import System.Environment (lookupEnv)

runService :: Maybe RuntimeMode -> IO ()
runService maybeRuntimeMode = do
  paths <- discoverPaths
  ensureRepoLayout paths
  maybeDemoConfigOverride <- lookupEnv "INFERNIX_DEMO_CONFIG_PATH"
  maybeDaemonRoleOverride <- lookupEnv "INFERNIX_DAEMON_ROLE"
  let selectedDemoConfigPath = fromMaybe (generatedDemoConfigPath paths) maybeDemoConfigOverride
  demoConfig <- decodeDemoConfigFile selectedDemoConfigPath
  runtimeMode <- resolveServiceRuntimeMode maybeRuntimeMode demoConfig
  daemonRole <- resolveServiceDaemonRole maybeDaemonRoleOverride demoConfig
  ensureServiceRuntimeSupported paths runtimeMode daemonRole
  whenAppleRuntimeReady paths runtimeMode daemonRole
  runProductionDaemon paths runtimeMode

resolveServiceRuntimeMode :: Maybe RuntimeMode -> DemoConfig -> IO RuntimeMode
resolveServiceRuntimeMode maybeRuntimeMode demoConfig =
  case maybeRuntimeMode of
    Just runtimeMode
      | runtimeMode == configRuntimeMode demoConfig -> pure runtimeMode
      | otherwise ->
          ioError
            ( userError
                ( "service runtime override "
                    <> show (runtimeModeId runtimeMode)
                    <> " does not match demo config runtime "
                    <> show (runtimeModeId (configRuntimeMode demoConfig))
                )
            )
    Nothing -> pure (configRuntimeMode demoConfig)

resolveServiceDaemonRole :: Maybe String -> DemoConfig -> IO DaemonRole
resolveServiceDaemonRole maybeDaemonRoleOverride demoConfig =
  case maybeDaemonRoleOverride of
    Nothing -> pure (activeDaemonRole demoConfig)
    Just "cluster" -> pure ClusterDaemon
    Just "host" -> pure HostDaemon
    Just rawValue ->
      ioError (userError ("Unsupported daemon role override for service: " <> rawValue))

ensureServiceRuntimeSupported :: Paths -> RuntimeMode -> DaemonRole -> IO ()
ensureServiceRuntimeSupported paths runtimeMode daemonRole =
  case (controlPlaneContext paths, runtimeMode, daemonRole) of
    ("outer-container", AppleSilicon, ClusterDaemon) -> pure ()
    _ -> ensureSupportedRuntimeModeForExecutionContext paths runtimeMode

whenAppleRuntimeReady :: Paths -> RuntimeMode -> DaemonRole -> IO ()
whenAppleRuntimeReady paths runtimeMode daemonRole =
  case (runtimeMode, daemonRole) of
    (AppleSilicon, HostDaemon) -> ensureAppleSiliconRuntimeReady paths
    _ -> pure ()
