{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster.ImageFingerprint
  ( ClusterImageBuildInputs (..),
    DockerIgnorePattern,
    clusterImageFingerprintLabel,
    clusterImageFingerprintVersion,
    clusterImageFingerprintVersionLabel,
    clusterImageRuntimeModeLabel,
    clusterImageSourceFingerprint,
    dockerIgnorePathIgnored,
    parseDockerIgnorePatterns,
    sourceSnapshot,
    retainSourceSnapshot,
  )
where

import Control.Exception (evaluate)
import Control.Monad (forM, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits ((.&.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (intercalate, isInfixOf, nub, sort, tails)
import Data.Maybe (catMaybes)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Config (Paths (..))
import Infernix.Types (RuntimeMode, runtimeModeId)
import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist, listDirectory)
import System.FilePath (takeDirectory, (</>))
import System.Posix.Files qualified as Posix

data ClusterImageBuildInputs = ClusterImageBuildInputs
  { clusterImageBuildRuntimeMode :: RuntimeMode,
    clusterImageBuildGoImage :: String,
    clusterImageBuildBaseImage :: String,
    clusterImageBuildTargetArchitecture :: String,
    clusterImageBuildDemoUi :: Bool
  }
  deriving (Eq, Show)

newtype DockerIgnorePattern = DockerIgnorePattern {dockerIgnorePatternSegments :: [String]}
  deriving (Eq, Show)

clusterImageFingerprintLabel :: String
clusterImageFingerprintLabel = "org.infernix.cluster-source-fingerprint"

clusterImageFingerprintVersionLabel :: String
clusterImageFingerprintVersionLabel = "org.infernix.cluster-source-fingerprint-version"

clusterImageRuntimeModeLabel :: String
clusterImageRuntimeModeLabel = "org.infernix.cluster-workload-runtime-mode"

clusterImageFingerprintVersion :: String
clusterImageFingerprintVersion = "cluster-image-v1"

clusterImageSourceFingerprint :: Paths -> ClusterImageBuildInputs -> IO String
clusterImageSourceFingerprint paths inputs = do
  patterns <- loadDockerIgnorePatterns (repoRoot paths)
  entries <- dockerContextEntries patterns (repoRoot paths)
  entryChunks <- concat <$> mapM (fingerprintEntryChunks (repoRoot paths)) entries
  let digestInput =
        LazyByteString.fromChunks
          (fingerprintHeader inputs (length entries) : entryChunks)
      digest = SHA256.hashlazy digestInput
  pure (ByteString8.unpack (Base16.encode digest))

-- | Each row binds a path, entry kind, permission bits and payload digest.
-- The caller compares independently observed trees; a tree hashing itself
-- cannot establish which checkout an operator requested.
sourceSnapshot :: FilePath -> IO [(FilePath, String, Int, String)]
sourceSnapshot root = do
  patterns <- loadDockerIgnorePatterns root
  contextEntries <- dockerContextEntries patterns root
  ignorePresent <- doesFileExist (root </> ".dockerignore")
  let entries = sort (nub (contextEntries <> [".dockerignore" | ignorePresent]))
  forM entries $ \relativePath -> do
    status <- Posix.getSymbolicLinkStatus (root </> relativePath)
    chunks <- fingerprintEntryChunks root relativePath
    let digest = ByteString8.unpack (Base16.encode (SHA256.hashlazy (LazyByteString.fromChunks chunks)))
    _ <- evaluate (length digest)
    pure
      ( relativePath,
        if Posix.isSymbolicLink status then "symlink" else "file",
        fromIntegral (Posix.fileMode status .&. 0o777),
        digest
      )

-- | Preserve the actual preimage, including relevant untracked inputs. A
-- second walk of both the source and retained copy detects changes during
-- capture. This is a sampled consistency check, not an atomic filesystem
-- snapshot or a defence against an executor rewriting its own validator.
retainSourceSnapshot :: FilePath -> FilePath -> IO [(FilePath, String, Int, String)]
retainSourceSnapshot root destination = do
  before <- sourceSnapshot root
  mapM_ retainEntry before
  after <- sourceSnapshot root
  retained <- sourceSnapshot destination
  unless (before == after && before == retained) $
    ioError (userError "validation source changed while retaining its preimage")
  pure before
  where
    retainEntry (relativePath, entryKind, mode, _) = do
      let source = root </> relativePath
          target = destination </> relativePath
      createDirectoryIfMissing True (takeDirectory target)
      if entryKind == "symlink"
        then Posix.readSymbolicLink source >>= (`Posix.createSymbolicLink` target)
        else do
          copyFile source target
          Posix.setFileMode target (fromIntegral mode)

loadDockerIgnorePatterns :: FilePath -> IO [DockerIgnorePattern]
loadDockerIgnorePatterns root = do
  overridePresent <- doesFileExist (root </> "docker" </> "Dockerfile.dockerignore")
  when overridePresent $
    ioError (userError "source inventory requires the governed root .dockerignore; a Dockerfile-specific override is unsupported")
  let ignorePath = root </> ".dockerignore"
  ignoreFilePresent <- doesFileExist ignorePath
  if ignoreFilePresent
    then do
      parsed <- parseDockerIgnorePatterns <$> readFile ignorePath
      case parsed of
        Right patterns -> pure patterns
        Left err -> ioError (userError err)
    else pure []

parseDockerIgnorePatterns :: String -> Either String [DockerIgnorePattern]
parseDockerIgnorePatterns contents =
  catMaybes <$> traverse parseDockerIgnoreLine (zip [1 :: Int ..] (lines contents))

parseDockerIgnoreLine :: (Int, String) -> Either String (Maybe DockerIgnorePattern)
parseDockerIgnoreLine (lineNumber, rawLine) =
  case trimDockerIgnoreLine rawLine of
    "" -> Right Nothing
    '#' : _ -> Right Nothing
    '!' : _ ->
      Left
        ( ".dockerignore negation patterns are not supported by the cluster image fingerprint parser; line "
            <> show lineNumber
            <> ": "
            <> trimDockerIgnoreLine rawLine
        )
    line ->
      parseDockerIgnorePattern line

parseDockerIgnorePattern :: String -> Either String (Maybe DockerIgnorePattern)
parseDockerIgnorePattern line =
  let normalized = dropTrailingSlashes (dropLeadingSlashes line)
      segments = splitPathSegments normalized
   in if null normalized || normalized == "."
        then Right Nothing
        else
          if any (`elem` ("[]\\" :: String)) normalized || any (`elem` [".", ".."]) segments || any (\segment -> "**" `isInfixOf` segment && segment /= "**") segments
            then Left ("unsupported .dockerignore pattern in source inventory: " <> normalized)
            else Right (Just (DockerIgnorePattern segments))

dockerContextEntries :: [DockerIgnorePattern] -> FilePath -> IO [FilePath]
dockerContextEntries patterns root = sort <$> walk ""
  where
    walk relativeDirectory = do
      let absoluteDirectory = absolutePath relativeDirectory
      names <- sort <$> listDirectory absoluteDirectory
      concat <$> forM names (walkEntry relativeDirectory)

    walkEntry relativeDirectory name = do
      let relativePath =
            if null relativeDirectory
              then name
              else relativeDirectory <> "/" <> name
          absoluteEntry = absolutePath relativePath
      if dockerIgnorePathIgnored patterns relativePath
        then pure []
        else do
          status <- Posix.getSymbolicLinkStatus absoluteEntry
          if Posix.isDirectory status
            then walk relativePath
            else
              if Posix.isRegularFile status || Posix.isSymbolicLink status
                then pure [relativePath]
                else pure []

    absolutePath relativePath =
      if null relativePath
        then root
        else root </> relativePath

fingerprintHeader :: ClusterImageBuildInputs -> Int -> ByteString.ByteString
fingerprintHeader inputs entryCount =
  encodeUtf8
    ( intercalate
        "\n"
        [ "version=" <> clusterImageFingerprintVersion,
          "runtimeMode=" <> Text.unpack (runtimeModeId (clusterImageBuildRuntimeMode inputs)),
          "goImage=" <> clusterImageBuildGoImage inputs,
          "baseImage=" <> clusterImageBuildBaseImage inputs,
          "targetArchitecture=" <> clusterImageBuildTargetArchitecture inputs,
          "demoUi=" <> boolText (clusterImageBuildDemoUi inputs),
          "entryCount=" <> show entryCount
        ]
        <> "\n\0"
    )

fingerprintEntryChunks :: FilePath -> FilePath -> IO [ByteString.ByteString]
fingerprintEntryChunks root relativePath = do
  let absoluteEntry = root </> relativePath
  status <- Posix.getSymbolicLinkStatus absoluteEntry
  let modeText = show (Posix.fileMode status .&. 0o777)
      entryPrefix entryType =
        [ "path\0",
          relativePath,
          "\0type\0",
          entryType,
          "\0mode\0",
          modeText,
          "\0payload\0"
        ]
      entrySuffix = "\0end-entry\0"
  if Posix.isSymbolicLink status
    then do
      target <- Posix.readSymbolicLink absoluteEntry
      pure [encodeUtf8 (concat (entryPrefix "symlink") <> target <> entrySuffix)]
    else do
      unless (Posix.isRegularFile status) $
        ioError (userError ("unsupported Docker context entry in fingerprint: " <> relativePath))
      contents <- ByteString.readFile absoluteEntry
      pure [encodeUtf8 (concat (entryPrefix "file")), contents, encodeUtf8 entrySuffix]

dockerIgnorePathIgnored :: [DockerIgnorePattern] -> FilePath -> Bool
dockerIgnorePathIgnored patterns relativePath =
  any (`dockerIgnorePatternMatches` splitPathSegments relativePath) patterns

dockerIgnorePatternMatches :: DockerIgnorePattern -> [String] -> Bool
dockerIgnorePatternMatches patternValue =
  -- Docker anchors ordinary patterns at the context root. Only an explicit
  -- \** spans arbitrary directory depth; matching any segment would hide
  -- inputs such as test/build/Spec.hs behind the root-only build exclusion.
  globSegmentsMatchPrefix (dockerIgnorePatternSegments patternValue)

globSegmentsMatchPrefix :: [String] -> [String] -> Bool
globSegmentsMatchPrefix [] _ = True
globSegmentsMatchPrefix ("**" : patternRest) pathSegments =
  globSegmentsMatchPrefix patternRest pathSegments
    || case pathSegments of
      [] -> False
      _ : pathRest -> globSegmentsMatchPrefix ("**" : patternRest) pathRest
globSegmentsMatchPrefix _ [] = False
globSegmentsMatchPrefix (patternSegment : patternRest) (pathSegment : pathRest) =
  globSegmentMatches patternSegment pathSegment
    && globSegmentsMatchPrefix patternRest pathRest

globSegmentMatches :: String -> String -> Bool
globSegmentMatches patternValue segmentValue =
  case patternValue of
    "" -> null segmentValue
    '*' : patternRest -> any (globSegmentMatches patternRest) (tails segmentValue)
    '?' : patternRest ->
      case segmentValue of
        _ : segmentRest -> globSegmentMatches patternRest segmentRest
        [] -> False
    patternChar : patternRest ->
      case segmentValue of
        segmentChar : segmentRest
          | patternChar == segmentChar -> globSegmentMatches patternRest segmentRest
        _ -> False

splitPathSegments :: FilePath -> [String]
splitPathSegments =
  filter (not . null) . splitOnSlash . map pathSeparatorToSlash

splitOnSlash :: String -> [String]
splitOnSlash input =
  case break (== '/') input of
    (segment, "") -> [segment]
    (segment, _ : rest) -> segment : splitOnSlash rest

pathSeparatorToSlash :: Char -> Char
pathSeparatorToSlash '\\' = '/'
pathSeparatorToSlash character = character

trimDockerIgnoreLine :: String -> String
trimDockerIgnoreLine = dropWhileEndAsciiSpace . dropWhileAsciiSpace . dropTrailingCarriageReturn

dropWhileAsciiSpace :: String -> String
dropWhileAsciiSpace = dropWhile (`elem` [' ', '\t'])

dropWhileEndAsciiSpace :: String -> String
dropWhileEndAsciiSpace = reverse . dropWhileAsciiSpace . reverse

dropTrailingCarriageReturn :: String -> String
dropTrailingCarriageReturn value =
  case reverse value of
    '\r' : rest -> reverse rest
    _ -> value

dropLeadingSlashes :: String -> String
dropLeadingSlashes = dropWhile (== '/')

dropTrailingSlashes :: String -> String
dropTrailingSlashes value =
  case reverse value of
    '/' : rest -> dropTrailingSlashes (reverse rest)
    _ -> value

boolText :: Bool -> String
boolText True = "true"
boolText False = "false"

encodeUtf8 :: String -> ByteString.ByteString
encodeUtf8 = TextEncoding.encodeUtf8 . Text.pack
