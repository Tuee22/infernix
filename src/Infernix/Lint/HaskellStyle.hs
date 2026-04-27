module Infernix.Lint.HaskellStyle
  ( runHaskellStyleLint,
  )
where

import Control.Monad (when)
import Data.List (sort)
import Data.Maybe (fromMaybe)
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getTemporaryDirectory,
    listDirectory,
    removeFile,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)

runHaskellStyleLint :: IO ()
runHaskellStyleLint = do
  paths <- discoverPaths
  createDirectoryIfMissing True (buildRoot paths)
  installFormatterTools paths
  let toolsRoot = buildRoot paths </> "haskell-style-tools" </> "bin"
      ormoluPath = toolsRoot </> "ormolu"
      hlintPath = toolsRoot </> "hlint"
  ormoluPresent <- doesFileExist ormoluPath
  hlintPresent <- doesFileExist hlintPath
  when
    (not ormoluPresent || not hlintPresent)
    (ioError (userError "haskell-style-check: formatter bootstrap did not produce ormolu and hlint"))
  sources <- haskellSources (repoRoot paths)
  runCommand (repoRoot paths) ormoluPath (["--mode", "check"] <> sources)
  runCommand (repoRoot paths) hlintPath ["Setup.hs", "app", "src", "test"]
  checkCabalManifest paths
  putStrLn "haskell-style-check: ok"

installFormatterTools :: Paths -> IO ()
installFormatterTools paths = do
  let toolsRoot = buildRoot paths </> "haskell-style-tools" </> "bin"
      ormoluPath = toolsRoot </> "ormolu"
      hlintPath = toolsRoot </> "hlint"
  ormoluPresent <- doesFileExist ormoluPath
  hlintPresent <- doesFileExist hlintPath
  when (not ormoluPresent || not hlintPresent) $
    runCommand
      (repoRoot paths)
      "cabal"
      [ "--builddir=.build/cabal",
        "install",
        "--installdir=" <> toolsRoot,
        "--install-method=copy",
        "--overwrite-policy=always",
        "ormolu",
        "hlint"
      ]

checkCabalManifest :: Paths -> IO ()
checkCabalManifest paths = do
  let sourcePath = repoRoot paths </> "infernix.cabal"
  tempRoot <- getTemporaryDirectory
  (tempPath, tempHandle) <- openTempFile tempRoot "infernix.cabal"
  hClose tempHandle
  sourceContents <- readFile sourcePath
  writeFile tempPath sourceContents
  runCommand (repoRoot paths) "cabal" ["format", tempPath]
  formattedContents <- readFile tempPath
  removeFile tempPath
  if formattedContents == sourceContents
    then pure ()
    else ioError (userError "haskell-style-check: infernix.cabal is not cabal-format clean")

haskellSources :: FilePath -> IO [FilePath]
haskellSources repoRoot = do
  sourceFiles <- concat <$> mapM (collectHsFiles . (repoRoot </>)) ["app", "src", "test"]
  pure (sort ("Setup.hs" : map (makeRelative repoRoot) sourceFiles))

collectHsFiles :: FilePath -> IO [FilePath]
collectHsFiles directoryPath = do
  exists <- doesDirectoryExist directoryPath
  if not exists
    then pure []
    else do
      children <- listDirectory directoryPath
      concat <$> mapM (collectChild . (directoryPath </>)) children
  where
    collectChild childPath = do
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then collectHsFiles childPath
        else do
          isFile <- doesFileExist childPath
          if isFile && hasHsExtension childPath
            then pure [childPath]
            else pure []

hasHsExtension :: FilePath -> Bool
hasHsExtension pathValue =
  reverse (take 3 (reverse pathValue)) == ".hs"

makeRelative :: FilePath -> FilePath -> FilePath
makeRelative root fullPath =
  fromMaybe fullPath (stripPrefix (root <> "/") fullPath)

runCommand :: FilePath -> FilePath -> [String] -> IO ()
runCommand workingDirectory command args = do
  (exitCode, _, stderrOutput) <- readCreateProcessWithExitCode (proc command args) {cwd = Just workingDirectory} ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> stderrOutput))

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing
