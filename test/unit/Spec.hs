{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Maybe (isJust)
import qualified Data.Text as Text
import Infernix.Config
import Infernix.Models
import Infernix.Runtime
import Infernix.Types
import System.Directory
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)

main :: IO ()
main = do
  assert (isJust (findModel "uppercase-text")) "seeded model lookup works"
  assert ("4010" `elem` words (renderTestConfig 4010)) "test config renders the chosen edge port"
  withTestRoot ".tmp/unit" $ do
    paths <- discoverPaths
    ensureRepoLayout paths
    result <-
      executeInference
        paths
        InferenceRequest
          { requestModelId = "echo-text",
            inputText = Text.replicate 81 "x"
          }
    case result of
      Left err -> fail ("unexpected error: " <> show err)
      Right inferenceResult -> do
        assert (isJust (objectRef (payload inferenceResult))) "large outputs use the object store"
        case objectRef (payload inferenceResult) of
          Nothing -> pure ()
          Just ref -> do
            exists <- doesFileExist (objectStoreRoot paths </> Text.unpack ref)
            assert exists "stored object reference points at a real file"
  putStrLn "unit tests passed"

withTestRoot :: FilePath -> IO a -> IO a
withTestRoot root action = do
  catchIOError (removePathForcibly root) ignoreMissing
  createDirectoryIfMissing True root
  withCurrentDirectory root action
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message
