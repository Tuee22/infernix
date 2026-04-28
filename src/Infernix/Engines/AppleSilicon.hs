{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.AppleSilicon
  ( ensureAppleSiliconRuntimeReady,
  )
where

import Control.Monad (unless)
import Data.List (nubBy)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingsForMode)
import Infernix.Python (ensurePoetryProjectReady, pythonProjectDirectory)
import Infernix.Types (EngineBinding (..), RuntimeMode (AppleSilicon))
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)

data AppleSetupStep
  = EnsureEngineRoot FilePath
  | EnsurePoetryProject FilePath
  | RunPoetrySetupEntrypoint FilePath FilePath String

ensureAppleSiliconRuntimeReady :: Paths -> IO ()
ensureAppleSiliconRuntimeReady paths =
  mapM_ (runAppleSetupStep paths) (appleSetupPlan paths)

appleSetupPlan :: Paths -> [AppleSetupStep]
appleSetupPlan paths =
  [ EnsurePoetryProject projectDirectory
  ]
    <> map
      (EnsureEngineRoot . engineInstallRoot)
      uniqueBindings
    <> map
      (\binding -> RunPoetrySetupEntrypoint projectDirectory (engineInstallRoot binding) (Text.unpack (engineBindingSetupEntrypoint binding)))
      pythonBindings
  where
    projectDirectory = pythonProjectDirectory paths AppleSilicon
    uniqueBindings =
      nubBy
        (\left right -> engineBindingAdapterId left == engineBindingAdapterId right)
        (engineBindingsForMode AppleSilicon)
    pythonBindings = filter engineBindingPythonNative uniqueBindings
    engineInstallRoot binding =
      dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId binding)

runAppleSetupStep :: Paths -> AppleSetupStep -> IO ()
runAppleSetupStep paths step =
  case step of
    EnsureEngineRoot directoryPath ->
      createDirectoryIfMissing True directoryPath
    EnsurePoetryProject projectDirectory ->
      ensurePoetryProjectReady paths projectDirectory
    RunPoetrySetupEntrypoint projectDirectory engineInstallRoot entrypoint -> do
      let bootstrapManifestPath = engineInstallRoot </> "bootstrap.json"
      bootstrapReady <- doesFileExist bootstrapManifestPath
      unless bootstrapReady $ do
        baseEnvironment <- getEnvironment
        let processEnvironment =
              [ ("POETRY_VIRTUALENVS_IN_PROJECT", "true"),
                ("INFERNIX_REPO_ROOT", repoRoot paths),
                ("INFERNIX_ENGINE_INSTALL_ROOT", engineInstallRoot),
                ("INFERNIX_RUNTIME_MODE", "apple-silicon")
              ]
                <> filter
                  (\(name, _) -> name `notElem` ["POETRY_VIRTUALENVS_IN_PROJECT", "INFERNIX_REPO_ROOT", "INFERNIX_ENGINE_INSTALL_ROOT", "INFERNIX_RUNTIME_MODE"])
                  baseEnvironment
        (exitCode, _, stderrOutput) <-
          readCreateProcessWithExitCode
            ( (proc "poetry" ["--directory", projectDirectory, "run", entrypoint])
                { cwd = Just projectDirectory,
                  env = Just processEnvironment
                }
            )
            ""
        case exitCode of
          ExitSuccess -> pure ()
          _ ->
            ioError
              ( userError
                  ( "apple-silicon setup entrypoint failed: "
                      <> entrypoint
                      <> "\n"
                      <> stderrOutput
                  )
              )
