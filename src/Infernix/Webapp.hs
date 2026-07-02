{-# LANGUAGE OverloadedStrings #-}

module Infernix.Webapp
  ( runWebappRole,
  )
where

import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.ClusterConfig (ClusterConfig)
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config (Paths, publicationStatePath)
import Infernix.Demo.Api (DemoApiOptions (..), DemoBridgeMode (..), runDemoApiServer)
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Types (RuntimeMode, configRuntimeMode, runtimeModeId)

runWebappRole :: Paths -> RuntimeMode -> Maybe ClusterConfig -> FilePath -> IO ()
runWebappRole paths runtimeMode maybeClusterConfig selectedDhallPath = do
  demoConfig <- decodeDemoConfigFile selectedDhallPath
  when (configRuntimeMode demoConfig /= runtimeMode) $
    ioError
      ( userError
          ( "webapp runtime "
              <> Text.unpack (runtimeModeId runtimeMode)
              <> " does not match demo config runtime "
              <> Text.unpack (runtimeModeId (configRuntimeMode demoConfig))
          )
      )
  let demoBackend = Cluster.clusterDemoBackend <$> maybeClusterConfig
      bindHostValue =
        fromMaybe "127.0.0.1" (demoBackend >>= nonEmpty . Text.unpack . Cluster.demoBindHost)
      bridgeRaw =
        fmap (Text.unpack . Cluster.demoBridgeMode) demoBackend
      publicationPathValue =
        fromMaybe
          (publicationStatePath paths)
          (demoBackend >>= nonEmpty . Text.unpack . Cluster.demoPublicationStatePath)
      backendDefaultPort = maybe 8080 (fromIntegral . Cluster.demoPort) demoBackend
  bridgeMode <- resolveDemoBridgeMode bridgeRaw
  when (backendDefaultPort <= 0) (ioError (userError "demoBackend.port must be > 0"))
  putStrLn ("webappRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("webappConfigPath: " <> selectedDhallPath)
  putStrLn ("webappBridgeMode: " <> renderDemoBridgeMode bridgeMode)
  putStrLn ("webappHttpBind: " <> bindHostValue <> ":" <> show backendDefaultPort)
  runDemoApiServer
    DemoApiOptions
      { demoPaths = paths,
        demoRuntimeMode = runtimeMode,
        demoBridgeMode = bridgeMode,
        demoBindHost = bindHostValue,
        demoPort = backendDefaultPort,
        demoConfigPath = selectedDhallPath,
        demoPublicationPath = publicationPathValue
      }

nonEmpty :: String -> Maybe String
nonEmpty value = if null value then Nothing else Just value

resolveDemoBridgeMode :: Maybe String -> IO DemoBridgeMode
resolveDemoBridgeMode maybeRawValue =
  case fmap trimWhitespace maybeRawValue of
    Nothing -> pure DirectDemoInference
    Just "" -> pure DirectDemoInference
    Just "direct" -> pure DirectDemoInference
    Just "pulsar-daemon" -> pure PulsarDaemonBridge
    Just "pulsar" -> pure PulsarDaemonBridge
    Just rawValue ->
      ioError
        (userError ("Unsupported demoBackend.bridgeMode value: " <> rawValue))

renderDemoBridgeMode :: DemoBridgeMode -> String
renderDemoBridgeMode bridgeMode =
  case bridgeMode of
    DirectDemoInference -> "direct"
    PulsarDaemonBridge -> "pulsar-daemon"

trimWhitespace :: String -> String
trimWhitespace =
  reverse
    . dropWhile (`elem` [' ', '\n', '\r', '\t'])
    . reverse
    . dropWhile (`elem` [' ', '\n', '\r', '\t'])
