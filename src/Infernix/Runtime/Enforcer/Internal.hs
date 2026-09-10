{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Runtime.Enforcer.Internal
  ( CgroupObservationOperand (..),
    CgroupObservationFailure (..),
    renderCgroupObservationFailure,
    combineHostCgroupAvailabilityMib,
    withCgroupMemoryHeadroom,
    readCgroupMemoryAvailableMibWith,
    parseFiniteMib,
    readCgroupMemoryAvailableMib,
    readCgroupMemoryLimitMib,
  )
where

import Control.Exception (Exception (displayException), IOException, throwIO, try)
import Data.ByteString.Char8 qualified as ByteString
import Data.Char (isDigit)
import Data.List (find, stripPrefix)
import Data.Word (Word64)
import System.FilePath (isAbsolute, splitDirectories, (</>))
import System.IO (readFile')

parseFiniteMib :: String -> Maybe Int
parseFiniteMib rawValue =
  case reads (trim rawValue) of
    [(bytes, "")]
      | bytes > 0,
        bytes `mod` bytesPerMib == 0,
        let mib = bytes `div` bytesPerMib,
        mib > 0,
        mib <= toInteger (maxBound :: Int) ->
          Just (fromInteger mib)
    _ -> Nothing
  where
    trim = reverse . dropWhile (`elem` [' ', '\t', '\r', '\n']) . reverse . dropWhile (`elem` [' ', '\t', '\r', '\n'])
    bytesPerMib = 1048576 :: Integer

-- | The finite cgroup v2 memory maximum in force for this process, in MiB.
--
-- 'Nothing' means no finite limit was observable — an unlimited cgroup, a host
-- with no unified hierarchy, or an unreadable @\/proc@. Both callers treat that
-- as "no cgroup narrowing", never as "no memory": Sprint 1.21's host memory
-- facts intersect it with @\/proc\/meminfo@, and runtime-plan refinement pairs
-- it with a pod placement that already declared its own limit.
readCgroupMemoryLimitMib :: IO (Maybe Int)
readCgroupMemoryLimitMib = do
  maybeRelativePath <- readCurrentCgroupPath
  case maybeRelativePath of
    Nothing -> pure Nothing
    Just relativePath ->
      firstFiniteLimit
        ["/sys/fs/cgroup" </> relativePath </> "memory.max"]

-- | The operand whose observation must succeed before availability is known.
data CgroupObservationOperand = CgroupMembership | CgroupMaximum | CgroupUsage
  deriving (Eq, Show)

data CgroupObservationFailure
  = CgroupReadFailure CgroupObservationOperand FilePath String
  | CgroupInvalidObservation CgroupObservationOperand FilePath String
  | CgroupUsageExceedsMaximum FilePath Integer Integer
  | CgroupInsufficientHeadroom Int Int
  deriving (Eq, Show)

instance Exception CgroupObservationFailure where
  displayException = renderCgroupObservationFailure

renderCgroupObservationFailure :: CgroupObservationFailure -> String
renderCgroupObservationFailure failure =
  "could not observe available cgroup memory: " <> detail
  where
    detail = case failure of
      CgroupReadFailure operand path reason -> operandName operand <> " at " <> path <> " is unreadable: " <> reason
      CgroupInvalidObservation operand path reason -> operandName operand <> " at " <> path <> " is invalid: " <> reason
      CgroupUsageExceedsMaximum path usage maximumBytes -> "memory.current at " <> path <> " exceeds memory.max: usage=" <> show usage <> ", maximum=" <> show maximumBytes
      CgroupInsufficientHeadroom required available -> "memory.max minus memory.current provides " <> show available <> " MiB, below the required " <> show required <> " MiB engine admission requirement"
    operandName operand =
      case operand of
        CgroupMembership -> "/proc/self/cgroup"
        CgroupMaximum -> "memory.max"
        CgroupUsage -> "memory.current"

-- | Intersect an already decoded host observation with cgroup headroom.
-- Only a positively observed unlimited maximum leaves host availability alone.
combineHostCgroupAvailabilityMib :: Int -> Either CgroupObservationFailure (Maybe Int) -> Either CgroupObservationFailure Int
combineHostCgroupAvailabilityMib hostAvailable = fmap (maybe hostAvailable (min hostAvailable))

-- | Refuse before entering an engine's authority-producing action. The
-- observation is a snapshot, not a reservation against concurrent consumers.
-- The production engine kernel supplies the fixed observer; tests independently
-- control read outcomes and prove that the action is not entered on refusal.
withCgroupMemoryHeadroom :: Int -> IO (Either CgroupObservationFailure (Maybe Int)) -> IO a -> IO a
withCgroupMemoryHeadroom required observe action = do
  observed <- observe
  case observed of
    Left failure -> throwIO failure
    Right (Just available)
      | available < required -> throwIO (CgroupInsufficientHeadroom required available)
    Right _ -> action

-- | Observe usage before subtracting a finite maximum. Missing or invalid
-- operands are refusals; capacity is never substituted for availability.
readCgroupMemoryAvailableMib :: IO (Either CgroupObservationFailure (Maybe Int))
readCgroupMemoryAvailableMib =
  readCgroupMemoryAvailableMibWith ByteString.readFile "/proc/self/cgroup" "/sys/fs/cgroup"

-- | Package-private observation boundary for independent filesystem and read
-- failure controls. Production supplies only the fixed kernel paths above.
-- Strict bytes keep read errors inside the IOException handler.
readCgroupMemoryAvailableMibWith ::
  (FilePath -> IO ByteString.ByteString) ->
  FilePath ->
  FilePath ->
  IO (Either CgroupObservationFailure (Maybe Int))
readCgroupMemoryAvailableMibWith readBytes membershipPath hierarchyRoot =
  readOperand CgroupMembership membershipPath >>= either (pure . Left) observeMembership
  where
    readOperand operand path = do
      result <- try (readBytes path)
      pure $
        case result of
          Left (failure :: IOException) -> Left (CgroupReadFailure operand path (displayException failure))
          Right bytes -> Right (ByteString.unpack bytes)
    observeMembership contents =
      case [path | line <- lines contents, Just path <- [stripPrefix "0::" line]] of
        [path]
          | isAbsolute path && all (`notElem` [".", ".."]) (splitDirectories path) ->
              observeMaximum (hierarchyRoot </> dropWhile (== '/') path)
        _ -> pure (Left (CgroupInvalidObservation CgroupMembership membershipPath "expected one absolute unified-hierarchy path without traversal"))
    observeMaximum root = do
      let path = root </> "memory.max"
      result <- readOperand CgroupMaximum path
      case result of
        Left failure -> pure (Left failure)
        Right contents
          | trimCounter contents == "max" -> pure (Right Nothing)
          | otherwise ->
              either (pure . Left) (observeUsage root) (parseCounter CgroupMaximum path contents)
    observeUsage root maximumBytes = do
      let path = root </> "memory.current"
      result <- readOperand CgroupUsage path
      pure $ do
        contents <- result
        usageBytes <- parseCounter CgroupUsage path contents
        if usageBytes > maximumBytes
          then Left (CgroupUsageExceedsMaximum path usageBytes maximumBytes)
          else Right (Just (fromInteger ((maximumBytes - usageBytes) `div` 1048576)))

parseCounter :: CgroupObservationOperand -> FilePath -> String -> Either CgroupObservationFailure Integer
parseCounter operand path contents =
  case reads value of
    [(bytes, "")]
      | not (null value),
        all isDigit value,
        bytes <= toInteger (maxBound :: Word64),
        bytes `div` 1048576 <= toInteger (maxBound :: Int) ->
          Right bytes
    _ -> Left (CgroupInvalidObservation operand path "expected an unsigned decimal byte counter within the kernel and MiB domains")
  where
    value = trimCounter contents

trimCounter :: String -> String
trimCounter = reverse . dropWhile (`elem` [' ', '\t', '\r', '\n']) . reverse . dropWhile (`elem` [' ', '\t', '\r', '\n'])

readCurrentCgroupPath :: IO (Maybe FilePath)
readCurrentCgroupPath = do
  readResult <- try (readFile' "/proc/self/cgroup")
  pure $
    case readResult of
      Left (_ :: IOException) -> Nothing
      Right contents ->
        dropWhile (== '/')
          . drop (length ("0::" :: String))
          <$> find (startsWithUnifiedHierarchy . trimLine) (lines contents)
  where
    startsWithUnifiedHierarchy value = take 3 value == "0::"
    trimLine = reverse . dropWhile (`elem` ['\r', '\n']) . reverse

firstFiniteLimit :: [FilePath] -> IO (Maybe Int)
firstFiniteLimit [] = pure Nothing
firstFiniteLimit (path : remaining) = do
  readResult <- try (readFile' path)
  case readResult of
    Left (_ :: IOException) -> firstFiniteLimit remaining
    Right contents ->
      case parseFiniteMib contents of
        Just limitMib -> pure (Just limitMib)
        Nothing -> firstFiniteLimit remaining
