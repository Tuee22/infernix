{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Runtime.Enforcer.Internal
  ( parseFiniteMib,
    readCgroupMemoryLimitMib,
  )
where

import Control.Exception (IOException, try)
import Data.List (find)
import System.FilePath ((</>))

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

readCurrentCgroupPath :: IO (Maybe FilePath)
readCurrentCgroupPath = do
  readResult <- try (readFile "/proc/self/cgroup")
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
  readResult <- try (readFile path)
  case readResult of
    Left (_ :: IOException) -> firstFiniteLimit remaining
    Right contents ->
      case parseFiniteMib contents of
        Just limitMib -> pure (Just limitMib)
        Nothing -> firstFiniteLimit remaining
