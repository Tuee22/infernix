module Main (main) where

import Control.Exception (SomeException, bracket, displayException, try)
import Control.Monad (unless)
import Data.List (isInfixOf)
import Distribution.PackageDescription.PrettyPrint (showGenericPackageDescription)
import Distribution.Simple.PackageDescription (readGenericPackageDescription)
import Distribution.Utils.Path (makeSymbolicPath)
import Distribution.Verbosity (normal)
import GHC.RTS.Flags qualified as RTSFlags
import System.Directory
  ( createDirectory,
    doesFileExist,
    getCurrentDirectory,
    getTemporaryDirectory,
    removeFile,
    removePathForcibly,
  )
import System.FilePath (splitDirectories, takeDirectory, (</>))
import System.IO (hClose, openTempFile)

main :: IO ()
main = do
  assertDeFormattedManifestFails
  assertRuntimeHeapCap
  repositoryRoot <- discoverRepositoryRoot
  checkCabalManifest (repositoryRoot </> "infernix.cabal")
  checkCabalManifest
    (repositoryRoot </> "test" </> "cabal-format" </> "infernix-cabal-format.cabal")
  putStrLn "cabal-format-check: ok"

-- | The package is intentionally independent of @infernix@: that keeps its
-- exact Cabal 3.16 solver universe separate from Ormolu's Cabal-syntax 3.14
-- universe. Cabal runs tests from within the source tree, so walk upward to
-- the governed manifest instead of importing the production path decoder.
discoverRepositoryRoot :: IO FilePath
discoverRepositoryRoot = do
  workingDirectory <- getCurrentDirectory
  walkUp (length (splitDirectories workingDirectory) + 1) workingDirectory
  where
    walkUp remainingAncestors candidateRoot
      | remainingAncestors <= 0 =
          fail "cabal-format-check: exhausted the finite working-directory ancestor set"
      | otherwise = do
          manifestPresent <- doesFileExist (candidateRoot </> "infernix.cabal")
          if manifestPresent
            then pure candidateRoot
            else do
              let parentRoot = takeDirectory candidateRoot
              if parentRoot == candidateRoot
                then fail "cabal-format-check: repository root is not an ancestor of the test working directory"
                else walkUp (remainingAncestors - 1) parentRoot

-- | @cabal-install-3.16.1.0 format@ reads a generic package description and
-- writes this exact rendering. Compare it directly so the gate does not need a
-- temporary copy of the real manifest or a nested @cabal@ process.
checkCabalManifest :: FilePath -> IO ()
checkCabalManifest sourcePath = do
  sourceContents <- readFile sourcePath
  packageDescription <-
    readGenericPackageDescription normal Nothing (makeSymbolicPath sourcePath)
  let formattedContents = showGenericPackageDescription packageDescription
  unless
    (formattedContents == sourceContents)
    (fail ("cabal-format-check: " <> sourcePath <> " is not cabal-format clean"))

-- | Preserve the behavioral proof that a parseable but de-formatted manifest
-- is rejected by the in-process Cabal 3.16 renderer.
assertDeFormattedManifestFails :: IO ()
assertDeFormattedManifestFails =
  withFixtureDirectory $ \fixtureRoot -> do
    let deFormattedManifest = fixtureRoot </> "infernix-format-fixture.cabal"
    writeFile
      deFormattedManifest
      ( unlines
          [ "cabal-version: 3.0",
            "name: infernix-format-fixture",
            "version: 0.1.0.0",
            "build-type: Simple"
          ]
      )
    assertActionFailsWith
      "deliberately de-formatted Cabal manifest"
      "not cabal-format clean"
      (checkCabalManifest deFormattedManifest)

assertActionFailsWith :: String -> String -> IO () -> IO ()
assertActionFailsWith fixtureLabel expectedMessage action = do
  outcome <- try action
  case outcome :: Either SomeException () of
    Left failure ->
      unless
        (expectedMessage `isInfixOf` displayException failure)
        ( fail
            ( "cabal-format-check: "
                <> fixtureLabel
                <> " failed with the wrong diagnostic: "
                <> displayException failure
            )
        )
    Right () ->
      fail
        ( "cabal-format-check: "
            <> fixtureLabel
            <> " unexpectedly passed"
        )

withFixtureDirectory :: (FilePath -> IO result) -> IO result
withFixtureDirectory =
  bracket createFixtureDirectory removePathForcibly

createFixtureDirectory :: IO FilePath
createFixtureDirectory = do
  temporaryRoot <- getTemporaryDirectory
  (temporaryPath, handle) <-
    openTempFile temporaryRoot "infernix-cabal-format-"
  hClose handle
  removeFile temporaryPath
  createDirectory temporaryPath
  pure temporaryPath

assertRuntimeHeapCap :: IO ()
assertRuntimeHeapCap = do
  activeFlags <- RTSFlags.getRTSFlags
  let activeMaxHeapBlocks =
        toInteger (RTSFlags.maxHeapSize (RTSFlags.gcFlags activeFlags))
      expectedMaxHeapBlocks = 1024 * 1024 * 1024 `div` 4096
  unless
    (activeMaxHeapBlocks == expectedMaxHeapBlocks)
    ( fail
        ( "cabal-format-check: active RTS heap cap is not the baked 1024 MiB value: "
            <> show activeMaxHeapBlocks
        )
    )
