{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Runtime.Enforcer.Internal
  ( parseFiniteMib,
    readCgroupMemoryAvailableMib,
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

-- | The headroom remaining inside the cgroup v2 memory maximum in force, in
-- MiB.
--
-- Phase 1 Sprint 1.21 admission needs what the slice has /left/, not what it
-- was granted: inside the Linux launcher container @\/proc\/meminfo@ still
-- reports the whole machine, so an available-memory observation that ignored
-- the cgroup would admit a toolchain account the container cannot fund.
--
-- Three outcomes, and the degradation is deliberate rather than hidden. With
-- both @memory.max@ and @memory.current@ readable the answer is their
-- difference. With a readable maximum and an unreadable current usage the
-- answer degrades to the maximum itself — an upper bound on the headroom, not
-- a measurement of it — because a slice that is bounded at all still bounds
-- more than the host figure does. With no finite maximum the answer is
-- 'Nothing', which every caller reads as "no cgroup narrowing" rather than as
-- "no memory".
readCgroupMemoryAvailableMib :: IO (Maybe Int)
readCgroupMemoryAvailableMib = do
  maybeRelativePath <- readCurrentCgroupPath
  case maybeRelativePath of
    Nothing -> pure Nothing
    Just relativePath -> do
      maybeLimitMib <-
        firstFiniteLimit ["/sys/fs/cgroup" </> relativePath </> "memory.max"]
      case maybeLimitMib of
        Nothing -> pure Nothing
        Just limitMib ->
          Just . cgroupHeadroomMib limitMib
            <$> readFlooredMib ("/sys/fs/cgroup" </> relativePath </> "memory.current")

-- | The headroom a readable maximum and an optional current usage describe.
cgroupHeadroomMib :: Int -> Maybe Int -> Int
cgroupHeadroomMib limitMib maybeCurrentMib =
  case maybeCurrentMib of
    Nothing -> limitMib
    Just currentMib -> max 0 (limitMib - currentMib)

-- | A byte counter floored to MiB.
--
-- Separate from 'parseFiniteMib' on purpose: that parser requires an exact MiB
-- multiple because a cgroup /maximum/ this repository trusts is always written
-- as one, while a current-usage counter is an arbitrary byte figure and
-- rejecting it for not dividing evenly would discard the observation.
readFlooredMib :: FilePath -> IO (Maybe Int)
readFlooredMib path = do
  readResult <- try (readFile path)
  pure $
    case readResult of
      Left (_ :: IOException) -> Nothing
      Right contents ->
        case reads (trim contents) of
          [(bytes, "")]
            | bytes >= (0 :: Integer),
              let mib = bytes `div` 1048576,
              mib <= toInteger (maxBound :: Int) ->
                Just (fromInteger mib)
          _ -> Nothing
  where
    trim =
      reverse
        . dropWhile (`elem` [' ', '\t', '\r', '\n'])
        . reverse
        . dropWhile (`elem` [' ', '\t', '\r', '\n'])

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
