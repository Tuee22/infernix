{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoCLI
  ( main,
  )
where

import Control.Exception (bracket_)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.CLI (extractRuntimeMode)
import Infernix.Config (discoverPaths, generatedDemoConfigPath, resolveRuntimeMode)
import Infernix.Service (runService)
import Infernix.Types (RuntimeMode, runtimeModeId)
import System.Environment (getArgs, lookupEnv, setEnv, unsetEnv)
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
      runtimeMode <- resolveRuntimeMode maybeRuntimeMode
      let selectedDhallPath =
            fromMaybe (generatedDemoConfigPath paths runtimeMode) maybeDhallPath
          runtimeModeValue = Text.unpack (runtimeModeId runtimeMode)
      withTemporaryEnv
        [ ("INFERNIX_DEMO_CONFIG_PATH", Just selectedDhallPath),
          ("INFERNIX_CATALOG_SOURCE", Just "env-config-override"),
          ("INFERNIX_RUNTIME_MODE", Just runtimeModeValue)
        ]
        (runService (Just runtimeMode) maybePort)
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

withTemporaryEnv :: [(String, Maybe String)] -> IO a -> IO a
withTemporaryEnv bindings action = do
  previousValues <- mapM (\(name, _) -> (,) name <$> lookupEnv name) bindings
  let applyBindings =
        mapM_
          ( \(name, maybeValue) ->
              case maybeValue of
                Just value -> setEnv name value
                Nothing -> unsetEnv name
          )
          bindings
      restoreBindings =
        mapM_
          ( \(name, maybeValue) ->
              case maybeValue of
                Just value -> setEnv name value
                Nothing -> unsetEnv name
          )
          previousValues
  bracket_ applyBindings restoreBindings action

helpText :: String
helpText =
  unlines
    [ "infernix-demo [--runtime-mode apple-silicon|linux-cpu|linux-cuda] serve [--dhall PATH] [--port PORT]",
      "",
      "Commands:",
      "  infernix-demo serve [--dhall PATH] [--port PORT]"
    ]
