{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoCLI
  ( main,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.Config (discoverPaths, ensureRepoLayout, generatedDemoConfigPath, publicationStatePath)
import Infernix.Demo.Api (DemoApiOptions (..), DemoBridgeMode (..), runDemoApiServer)
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Types (DemoConfig (configRuntimeMode), runtimeModeId)
import System.Environment (getArgs, lookupEnv)
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
      let selectedDhallPath =
            fromMaybe (generatedDemoConfigPath paths) maybeDhallPath
      ensureRepoLayout paths
      demoConfig <- decodeDemoConfigFile selectedDhallPath
      let runtimeMode = configRuntimeMode demoConfig
      maybeBindHost <- lookupEnv "INFERNIX_BIND_HOST"
      maybeBridgeMode <- lookupEnv "INFERNIX_DEMO_BRIDGE_MODE"
      maybePublicationPath <- lookupEnv "INFERNIX_PUBLICATION_STATE_PATH"
      bridgeMode <- resolveDemoBridgeMode maybeBridgeMode
      putStrLn ("demoRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn ("demoConfigPath: " <> selectedDhallPath)
      putStrLn ("demoBridgeMode: " <> renderDemoBridgeMode bridgeMode)
      runDemoApiServer
        DemoApiOptions
          { demoPaths = paths,
            demoRuntimeMode = runtimeMode,
            demoBridgeMode = bridgeMode,
            demoBindHost = fromMaybe "127.0.0.1" maybeBindHost,
            demoPort = fromMaybe 8080 maybePort,
            demoConfigPath = selectedDhallPath,
            demoPublicationPath = fromMaybe (publicationStatePath paths) maybePublicationPath
          }
dispatch _ = do
  putStrLn helpText
  exitFailure

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
    Just "pulsar-daemon" -> pure PulsarDaemonBridge
    Just rawValue ->
      ioError
        (userError ("Unsupported INFERNIX_DEMO_BRIDGE_MODE value: " <> rawValue))

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
