module Infernix.Runtime.Pulsar
  ( runProductionDaemon,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Data.List (intercalate)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Types
import System.Environment (lookupEnv)

runProductionDaemon :: Paths -> RuntimeMode -> IO ()
runProductionDaemon paths runtimeMode = do
  maybeControlPlaneOverride <- lookupEnv "INFERNIX_CONTROL_PLANE_CONTEXT"
  maybeDaemonLocationOverride <- lookupEnv "INFERNIX_DAEMON_LOCATION"
  maybeCatalogSourceOverride <- lookupEnv "INFERNIX_CATALOG_SOURCE"
  maybeDemoConfigOverride <- lookupEnv "INFERNIX_DEMO_CONFIG_PATH"
  let controlPlane = fromMaybe (controlPlaneContext paths) maybeControlPlaneOverride
      daemonLocation =
        fromMaybe
          ( if controlPlane == "host-native"
              then "control-plane-host"
              else "cluster-pod"
          )
          maybeDaemonLocationOverride
      catalogSource =
        fromMaybe
          ( case maybeDemoConfigOverride of
              Just _ -> "env-config-override"
              Nothing -> "generated-build-root"
          )
          maybeCatalogSourceOverride
      selectedDemoConfigPath = fromMaybe (Infernix.Config.generatedDemoConfigPath paths runtimeMode) maybeDemoConfigOverride
  demoConfig <- decodeDemoConfigFile selectedDemoConfigPath
  putStrLn ("serviceControlPlaneContext: " <> controlPlane)
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> watchedDemoConfigPath runtimeMode)
  putStrLn ("serviceRequestTopics: " <> intercalate "," (map Text.unpack (requestTopics demoConfig)))
  putStrLn ("serviceResultTopic: " <> Text.unpack (resultTopic demoConfig))
  putStrLn ("serviceEngineBindingCount: " <> show (length (engines demoConfig)))
  putStrLn "serviceSubscriptionMode: placeholder-no-pulsar-consumer"
  putStrLn "serviceHttpListener: disabled"
  forever (threadDelay 60000000)
