{-# LANGUAGE OverloadedStrings #-}

module Infernix.Python
  ( ensurePoetryProjectReady,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
where

import Control.Monad (unless)
import Infernix.Config (Paths (..))
import Infernix.Types (RuntimeMode)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
  )
import System.Environment (getEnvironment)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.Process (CreateProcess (env), proc, readCreateProcessWithExitCode)

pythonProjectDirectory :: Paths -> RuntimeMode -> FilePath
pythonProjectDirectory paths _runtimeMode =
  repoRoot paths </> "python"

pythonAdaptersPresent :: FilePath -> IO Bool
pythonAdaptersPresent projectDirectory = do
  let adaptersRoot = projectDirectory </> "adapters"
  adaptersDirectoryPresent <- doesDirectoryExist adaptersRoot
  if not adaptersDirectoryPresent
    then pure False
    else not . null <$> listVisibleEntries adaptersRoot

ensurePoetryProjectReady :: Paths -> FilePath -> IO ()
ensurePoetryProjectReady paths projectDirectory = do
  projectPresent <- doesDirectoryExist projectDirectory
  if not projectPresent
    then ioError (userError ("python substrate project is missing: " <> projectDirectory))
    else do
      let projectVenv = projectDirectory </> ".venv"
      venvPresent <- doesDirectoryExist projectVenv
      unless venvPresent $
        runPoetryCommand
          projectDirectory
          ["install", "--directory", projectDirectory]
          ("failed to install poetry project " <> projectDirectory)
      ensureGeneratedPythonProto paths projectDirectory

ensureGeneratedPythonProto :: Paths -> FilePath -> IO ()
ensureGeneratedPythonProto paths projectDirectory = do
  let outputRoot = repoRoot paths </> "tools" </> "generated_proto"
      generatedFiles =
        [ outputRoot </> "infernix" </> "api" </> "inference_service_pb2.py",
          outputRoot </> "infernix" </> "manifest" </> "runtime_manifest_pb2.py",
          outputRoot </> "infernix" </> "runtime" </> "inference_pb2.py"
        ]
  allPresent <- allM doesFileExist generatedFiles
  unless allPresent $ do
    createDirectoryIfMissing True outputRoot
    runPoetryCommand
      projectDirectory
      ( [ "--directory",
          projectDirectory,
          "run",
          "python",
          "-m",
          "grpc_tools.protoc",
          "-I",
          repoRoot paths </> "proto",
          "--python_out",
          outputRoot
        ]
          <> map
            (\relativePath -> repoRoot paths </> "proto" </> relativePath)
            [ "infernix/api/inference_service.proto",
              "infernix/manifest/runtime_manifest.proto",
              "infernix/runtime/inference.proto"
            ]
      )
      "failed to generate Python protobuf stubs"
    mapM_
      ensureNamespaceInit
      [ outputRoot,
        outputRoot </> "infernix",
        outputRoot </> "infernix" </> "api",
        outputRoot </> "infernix" </> "manifest",
        outputRoot </> "infernix" </> "runtime"
      ]

ensureNamespaceInit :: FilePath -> IO ()
ensureNamespaceInit directoryPath = do
  let initPath = directoryPath </> "__init__.py"
  initPresent <- doesFileExist initPath
  unless initPresent (writeFile initPath "")

runPoetryCommand :: FilePath -> [String] -> String -> IO ()
runPoetryCommand projectDirectory args failurePrefix = do
  baseEnvironment <- getEnvironment
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      ( (proc "poetry" args)
          { env =
              Just
                ( ("POETRY_VIRTUALENVS_IN_PROJECT", "true")
                    : filter ((/= "POETRY_VIRTUALENVS_IN_PROJECT") . fst) baseEnvironment
                )
          }
      )
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( failurePrefix
                <> "\nproject: "
                <> projectDirectory
                <> "\n"
                <> stderrOutput
            )
        )

allM :: (a -> IO Bool) -> [a] -> IO Bool
allM predicate = go
  where
    go [] = pure True
    go (value : rest) = do
      matches <- predicate value
      if matches
        then go rest
        else pure False

listVisibleEntries :: FilePath -> IO [FilePath]
listVisibleEntries directoryPath = do
  entries <- listDirectory directoryPath
  pure [entry | entry <- entries, entry /= "." && entry /= ".."]
