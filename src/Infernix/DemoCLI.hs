{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoCLI
  ( main,
  )
where

import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.ClusterConfig (ClusterConfig, decodeClusterConfigFile, defaultClusterConfigMountPath)
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config (discoverPaths, ensureRepoLayout, generatedDemoConfigPath, publicationStatePath)
import Infernix.Demo.Api (DemoApiOptions (..), DemoBridgeMode (..), runDemoApiServer)
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Types (DemoConfig (configRuntimeMode), runtimeModeId)
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Exit (exitFailure)

main :: IO ()
main = do
  setLocaleEncoding utf8
  args <- getArgs
  dispatch args

dispatch :: [String] -> IO ()
dispatch ["--help"] = putStrLn helpText
dispatch [] = putStrLn helpText
dispatch ("serve" : serveArgs) =
  case parseServeArgs serveArgs of
    Left message -> do
      putStrLn message
      exitFailure
    Right (maybePort, maybeDhallPath) -> do
      paths <- discoverPaths
      ensureRepoLayout paths
      -- Phase 5 Sprint 5.9: bindHost / bridgeMode /
      -- publicationStatePath previously came from
      -- @INFERNIX_BIND_HOST@ / @INFERNIX_DEMO_BRIDGE_MODE@ /
      -- @INFERNIX_PUBLICATION_STATE_PATH@ env vars. They now flow
      -- through the typed @ClusterConfig.demoBackend.*@ fields read
      -- from the chart-mounted cluster ConfigMap; host-native flows
      -- without the manifest fall back to the supported defaults
      -- (127.0.0.1 + direct bridge + repo-local publication path).
      maybeClusterConfig <- tryLoadClusterConfig
      let demoBackend = Cluster.clusterDemoBackend <$> maybeClusterConfig
          configuredDhallPath =
            fmap (Text.unpack . Cluster.demoConfigFilePath) demoBackend
          selectedDhallPath =
            fromMaybe (generatedDemoConfigPath paths) (maybeDhallPath <|> (configuredDhallPath >>= nonEmpty))
      demoConfig <- decodeDemoConfigFile selectedDhallPath
      let runtimeMode = configRuntimeMode demoConfig
          bindHostValue =
            fromMaybe "127.0.0.1" (demoBackend >>= nonEmpty . Text.unpack . Cluster.demoBindHost)
          bridgeRaw =
            fmap (Text.unpack . Cluster.demoBridgeMode) demoBackend
          publicationPathValue =
            fromMaybe
              (publicationStatePath paths)
              (demoBackend >>= nonEmpty . Text.unpack . Cluster.demoPublicationStatePath)
      bridgeMode <- resolveDemoBridgeMode bridgeRaw
      let backendDefaultPort = maybe 8080 (fromIntegral . Cluster.demoPort) demoBackend
          resolvedPort :: Int
          resolvedPort = fromMaybe backendDefaultPort maybePort
      when (resolvedPort <= 0) (ioError (userError "demoBackend.port must be > 0"))
      putStrLn ("demoRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn ("demoConfigPath: " <> selectedDhallPath)
      putStrLn ("demoBridgeMode: " <> renderDemoBridgeMode bridgeMode)
      runDemoApiServer
        DemoApiOptions
          { demoPaths = paths,
            demoRuntimeMode = runtimeMode,
            demoBridgeMode = bridgeMode,
            demoBindHost = bindHostValue,
            demoPort = resolvedPort,
            demoConfigPath = selectedDhallPath,
            demoPublicationPath = publicationPathValue
          }
dispatch _ = do
  putStrLn helpText
  exitFailure

-- | Phase 5 Sprint 5.9: best-effort load of the cluster manifest
-- mounted by the chart at the supported path. The @infernix-demo@
-- daemon pod has this ConfigMap-mounted; host-native or first-run
-- developer flows do not, so absence is silently tolerated.
tryLoadClusterConfig :: IO (Maybe ClusterConfig)
tryLoadClusterConfig = do
  let path = defaultClusterConfigMountPath
  exists <- doesFileExist path
  if exists
    then Just <$> decodeClusterConfigFile path
    else pure Nothing

nonEmpty :: String -> Maybe String
nonEmpty value = if null value then Nothing else Just value

(<|>) :: Maybe a -> Maybe a -> Maybe a
Just value <|> _ = Just value
Nothing <|> alternative = alternative

infixl 3 <|>

parseServeArgs :: [String] -> Either String (Maybe Int, Maybe FilePath)
parseServeArgs = go Nothing Nothing
  where
    go maybePort maybeDhall [] = Right (maybePort, maybeDhall)
    go _ _ ["--port"] = Left "Missing value for --port"
    go _ maybeDhall ("--port" : rawPort : rest) =
      case reads rawPort of
        [(portValue, "")] -> go (Just portValue) maybeDhall rest
        _ -> Left ("Invalid port: " <> rawPort)
    go _ _ ["--dhall"] = Left "Missing value for --dhall"
    go maybePort _ ("--dhall" : dhallPath : rest) =
      go maybePort (Just dhallPath) rest
    go _ _ ("--help" : _) = Left helpText
    go _ _ (value : _) = Left ("Unsupported infernix-demo argument: " <> value)

helpText :: String
helpText =
  unlines
    [ "infernix-demo serve [--dhall PATH] [--port PORT]",
      "",
      "Commands:",
      "  infernix-demo serve [--dhall PATH] [--port PORT]"
    ]

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
