module Infernix.Lint.Proto
  ( generatedHaskellProtoFiles,
    generatedHaskellProtoTreeViolations,
    protoSnapshotManifestViolations,
    runProtoLint,
  )
where

import Control.Monad (forM, forM_, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.List (intercalate, sort, (\\))
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory
  ( doesDirectoryExist,
    doesFileExist,
    listDirectory,
    pathIsSymbolicLink,
  )
import System.FilePath ((</>))

requiredProtoFiles :: [(FilePath, String, [String])]
requiredProtoFiles =
  [ ( "proto/infernix/runtime/inference.proto",
      "package infernix.runtime;",
      [ "message RequestField",
        "message CatalogEntry",
        "message EngineBinding",
        "message GeneratedCatalog",
        "message InferenceRequest",
        "message WorkerRequest",
        "message WorkerResponse",
        "message ResultPayload",
        "message InferenceResult",
        "message ErrorResponse"
      ]
    ),
    ( "proto/infernix/manifest/runtime_manifest.proto",
      "package infernix.manifest;",
      [ "message ModelMaterialization",
        "message RuntimeCacheEntry",
        "message RuntimeManifest"
      ]
    )
  ]

generatedHaskellProtoFiles :: [FilePath]
generatedHaskellProtoFiles =
  [ "src/Proto/Infernix/Manifest/RuntimeManifest.hs",
    "src/Proto/Infernix/Manifest/RuntimeManifest_Fields.hs",
    "src/Proto/Infernix/Runtime/Inference.hs",
    "src/Proto/Infernix/Runtime/Inference_Fields.hs"
  ]

protoSnapshotFiles :: [FilePath]
protoSnapshotFiles = map firstOfThree requiredProtoFiles <> generatedHaskellProtoFiles
  where
    firstOfThree (path, _, _) = path

protoSnapshotManifestPath :: FilePath
protoSnapshotManifestPath = "proto/haskell-bindings.sha256"

protoSnapshotManifestHeader :: [String]
protoSnapshotManifestHeader =
  [ "# infernix tracked Haskell protobuf binding snapshot v1",
    "# generator: proto-lens-protoc 0.9.0.1 with libprotoc 34.1",
    "# canonical inputs: proto/infernix/**/*.proto",
    "# style exclusion: only the four generated src/Proto modules inventoried below"
  ]

data ProtoSnapshotEntry = ProtoSnapshotEntry
  { protoSnapshotDigest :: String,
    protoSnapshotPath :: FilePath
  }

runProtoLint :: IO ()
runProtoLint = do
  paths <- discoverPaths
  forM_ requiredProtoFiles $ \(relativePath, packageLine, requiredSymbols) -> do
    let fullPath = repoRoot paths </> relativePath
    exists <- doesFileExist fullPath
    unless exists $
      ioError (userError ("missing required proto file: " <> relativePath))
    contents <- readFile fullPath
    unless ("syntax = \"proto3\";" `elem` lines contents) $
      ioError (userError (relativePath <> " must declare syntax = \"proto3\";"))
    unless (packageLine `elem` lines contents) $
      ioError (userError (relativePath <> " is missing package declaration " <> packageLine))
    forM_ requiredSymbols $ \requiredSymbol ->
      unless (elemSubstring requiredSymbol contents) $
        ioError (userError (relativePath <> " is missing required symbol: " <> requiredSymbol))
  generatedTreeFiles <- collectGeneratedHaskellProtoTree (repoRoot paths) "src/Proto"
  case generatedHaskellProtoTreeViolations generatedTreeFiles of
    [] -> pure ()
    violations ->
      ioError
        ( userError
            ( "generated Haskell protobuf source inventory drift:\n"
                <> intercalate "\n" violations
            )
        )
  fileContents <-
    forM protoSnapshotFiles $ \relativePath -> do
      let fullPath = repoRoot paths </> relativePath
      exists <- doesFileExist fullPath
      if exists
        then do
          contents <- ByteString.readFile fullPath
          pure (relativePath, contents)
        else pure (relativePath, ByteString.empty)
  let manifestPath = repoRoot paths </> protoSnapshotManifestPath
  manifestExists <- doesFileExist manifestPath
  manifestContents <-
    if manifestExists
      then ByteString.Char8.unpack <$> ByteString.readFile manifestPath
      else pure ""
  case protoSnapshotManifestViolations fileContents manifestContents of
    [] -> pure ()
    violations ->
      ioError
        ( userError
            ( "protobuf Haskell binding snapshot drift:\n"
                <> intercalate "\n" violations
                <> "\nregenerate all four Haskell modules from the canonical .proto inputs with the pinned Linux generation toolchain, then refresh "
                <> protoSnapshotManifestPath
            )
        )

-- | Require every regular file below @src/Proto@ to be one of the four
-- governed generator outputs, and require all four outputs to be present.
-- Production lint obtains this list by recursively walking the tree; keeping
-- the comparison pure makes the no-extra-files property easy to pin in tests.
generatedHaskellProtoTreeViolations :: [FilePath] -> [String]
generatedHaskellProtoTreeViolations actualFiles =
  [ "src/Proto is missing generated file: " <> relativePath
  | relativePath <- expectedFiles \\ actualFilesSorted
  ]
    <> [ "src/Proto contains an unexpected file: " <> relativePath
       | relativePath <- actualFilesSorted \\ expectedFiles
       ]
  where
    expectedFiles = sort generatedHaskellProtoFiles
    actualFilesSorted = sort actualFiles

collectGeneratedHaskellProtoTree :: FilePath -> FilePath -> IO [FilePath]
collectGeneratedHaskellProtoTree repositoryRoot relativePath = do
  let fullPath = repositoryRoot </> relativePath
  isSymbolicLink <- pathIsSymbolicLink fullPath
  when isSymbolicLink $
    ioError
      ( userError
          ( "generated Haskell protobuf source inventory drift:\n"
              <> relativePath
              <> ": symbolic links are forbidden under src/Proto"
          )
      )
  isDirectory <- doesDirectoryExist fullPath
  if isDirectory
    then do
      children <- sort <$> listDirectory fullPath
      concat <$> traverse (collectGeneratedHaskellProtoTree repositoryRoot . (relativePath </>)) children
    else do
      isFile <- doesFileExist fullPath
      if isFile
        then pure [relativePath]
        else
          ioError
            ( userError
                ( "generated Haskell protobuf source inventory drift:\n"
                    <> relativePath
                    <> ": expected a regular file or directory"
                )
            )

-- | Byte-exact drift proof for the checked-in proto-lens output. Ordinary
-- builds and this lint never execute @protoc@ or its Haskell plugin: the
-- canonical schemas and the four generated modules must instead match this
-- single, fixed-inventory SHA-256 snapshot together. The exact generated paths
-- are also the complete formatter/linter exclusion in 'Infernix.Lint.HaskellStyle'.
protoSnapshotManifestViolations ::
  [(FilePath, ByteString.ByteString)] ->
  String ->
  [String]
protoSnapshotManifestViolations fileContents manifestContents =
  case parseProtoSnapshotManifest manifestContents of
    Left parseFailure -> [protoSnapshotManifestPath <> ": " <> parseFailure]
    Right snapshotEntries ->
      concatMap (snapshotEntryViolations fileContents) snapshotEntries

parseProtoSnapshotManifest :: String -> Either String [ProtoSnapshotEntry]
parseProtoSnapshotManifest contents = do
  unlessEither
    (not (null contents) && last contents == '\n')
    "manifest must be non-empty and end with one newline"
  let manifestLines = lines contents
      (headerLines, entryLines) = splitAt (length protoSnapshotManifestHeader) manifestLines
  unlessEither
    (headerLines == protoSnapshotManifestHeader)
    "generator/canonical-input/style-exclusion header does not match the governed v1 format"
  entries <- traverse parseProtoSnapshotEntry entryLines
  unlessEither
    (map protoSnapshotPath entries == protoSnapshotFiles)
    ( "inventory must be exactly, in order: "
        <> intercalate ", " protoSnapshotFiles
    )
  pure entries

parseProtoSnapshotEntry :: String -> Either String ProtoSnapshotEntry
parseProtoSnapshotEntry lineValue = do
  let (digest, remainder) = splitAt 64 lineValue
  unlessEither
    (length digest == 64 && all isLowerHex digest)
    ("invalid lowercase SHA-256 entry: " <> lineValue)
  path <-
    case remainder of
      ' ' : ' ' : relativePath
        | not (null relativePath) -> Right relativePath
      _ -> Left ("invalid snapshot entry separator/path: " <> lineValue)
  pure
    ProtoSnapshotEntry
      { protoSnapshotDigest = digest,
        protoSnapshotPath = path
      }

snapshotEntryViolations ::
  [(FilePath, ByteString.ByteString)] ->
  ProtoSnapshotEntry ->
  [String]
snapshotEntryViolations fileContents entry =
  case lookup (protoSnapshotPath entry) fileContents of
    Nothing -> [protoSnapshotPath entry <> ": snapshot inventory content is missing"]
    Just contents
      | ByteString.null contents ->
          [protoSnapshotPath entry <> ": required snapshot file is missing or empty"]
      | actualDigest /= protoSnapshotDigest entry ->
          [ protoSnapshotPath entry
              <> ": SHA-256 mismatch (manifest "
              <> protoSnapshotDigest entry
              <> ", actual "
              <> actualDigest
              <> ")"
          ]
      | otherwise -> []
      where
        actualDigest =
          ByteString.Char8.unpack
            (Base16.encode (SHA256.hash contents))

unlessEither :: Bool -> String -> Either String ()
unlessEither condition failureMessage =
  if condition
    then Right ()
    else Left failureMessage

isLowerHex :: Char -> Bool
isLowerHex character =
  character `elem` ['0' .. '9'] || character `elem` ['a' .. 'f']

elemSubstring :: String -> String -> Bool
elemSubstring needle haystack =
  any (needle `prefixOf`) (tails haystack)

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (expected : expectedRest) (actual : actualRest) =
  expected == actual && prefixOf expectedRest actualRest

tails :: [a] -> [[a]]
tails [] = [[]]
tails value@(_ : rest) = value : tails rest
