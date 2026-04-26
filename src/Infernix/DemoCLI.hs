{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoCLI
  ( main,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.CLI (extractRuntimeMode)
import Infernix.Config (discoverPaths, ensureRepoLayout, generatedDemoConfigPath, publicationStatePath, resolveRuntimeMode)
import Infernix.Demo.Api (DemoApiOptions (..), runDemoApiServer)
import Infernix.Types (RuntimeMode, runtimeModeId)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)

main :: IO ()
main = do
  args <- getArgs
  case extractRuntimeMode args of
    Left message -> do
      putStrLn message
      exitFailure
    Right (maybeRuntimeMode, remainingArgs) ->
      dispatch maybeRuntimeMode remainingArgs

dispatch :: Maybe RuntimeMode -> [String] -> IO ()
dispatch _ ["--help"] = putStrLn helpText
dispatch _ [] = putStrLn helpText
dispatch maybeRuntimeMode ("serve" : serveArgs) =
  case parseServeArgs serveArgs of
    Left message -> do
      putStrLn message
      exitFailure
    Right (maybePort, maybeDhallPath) -> do
      paths <- discoverPaths
      ensureRepoLayout paths
      runtimeMode <- resolveRuntimeMode maybeRuntimeMode
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
dispatch _ _ = do
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
    [ "infernix-demo [--runtime-mode apple-silicon|linux-cpu|linux-cuda] serve [--dhall PATH] [--port PORT]",
      "",
      "Commands:",
      "  infernix-demo serve [--dhall PATH] [--port PORT]"
    ]
