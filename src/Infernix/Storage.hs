module Infernix.Storage
  ( edgePortPath,
    readStateFileMaybe,
    writeStateFile,
    writeTextFile,
  )
where

import Data.Text (Text)
import qualified Data.Text.IO as Text
import Infernix.Config (Paths (..))
import Text.Read (readMaybe)
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))

edgePortPath :: Paths -> FilePath
edgePortPath paths = runtimeRoot paths </> "edge-port.json"

writeStateFile :: Show a => FilePath -> a -> IO ()
writeStateFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  writeFile filePath (show value)

readStateFileMaybe :: Read a => FilePath -> IO (Maybe a)
readStateFileMaybe filePath = do
  contents <- readFile filePath
  pure (readMaybe contents)

writeTextFile :: FilePath -> Text -> IO ()
writeTextFile filePath contents = do
  createDirectoryIfMissing True (takeDirectory filePath)
  Text.writeFile filePath contents
