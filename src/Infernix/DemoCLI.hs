{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoCLI
  ( main,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.Config (discoverPaths, ensureRepoLayout, generatedDemoConfigPath, publicationStatePath, resolveRuntimeMode)
import Infernix.Demo.Api (DemoApiOptions (..), runDemoApiServer)
import Infernix.DemoConfig (ensureGeneratedDemoConfigFile)
import Infernix.Types (runtimeModeId)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)

main :: IO ()
main = do
  setLocaleEncoding utf8
  paths <- discoverPaths
  ensureRepoLayout paths
  runtimeMode <- resolveRuntimeMode Nothing
  _ <- ensureGeneratedDemoConfigFile paths runtimeMode
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
      runtimeMode <- resolveRuntimeMode Nothing
      let selectedDhallPath =
            fromMaybe (generatedDemoConfigPath paths runtimeMode) maybeDhallPath
      maybeBindHost <- lookupEnv "INFERNIX_BIND_HOST"
      maybePublicationPath <- lookupEnv "INFERNIX_PUBLICATION_STATE_PATH"
      putStrLn ("demoRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn ("demoConfigPath: " <> selectedDhallPath)
      runDemoApiServer
        DemoApiOptions
          { demoPaths = paths,
            demoRuntimeMode = runtimeMode,
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
