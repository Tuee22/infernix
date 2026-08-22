{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Phase 1 Sprint 1.21 — the two observations the governed toolchain account is
-- /admitted/ against, rather than merely divided from.
--
-- The bounded-host-memory ledger has one claimable pool and two alternative
-- occupants: the checked inference partition and this repository's Haskell
-- toolchain account. Arithmetic over installed capacity divides that pool; it
-- cannot see what is already resident in it, and an unseen claimant is exactly
-- what exhausts a host. Two observations close that gap, and both are taken at
-- the point of use:
--
-- * __available host memory__, which is what the machine has left rather than
--   what it contains; and
--
-- * __a census of foreign toolchain claimants__ — a compiler, driver, or
--   interactive toolchain image running outside this process's own tree, held
--   by another checkout, another CLI image, or a stage-0 bootstrap that shares
--   no token with this authority.
--
-- Both fail closed. An unavailable probe, a malformed response, or a census
-- that names a claimant is a refusal that reports what it found; none of them
-- is evidence that the host is free. A named claimant is /attributed, never
-- measured/: cross-user physical-footprint observation is unavailable to an
-- unprivileged process, so the coarse resident figure the process table
-- supplies is enough to name a claimant and not enough to account for one. It
-- is refused rather than killed, because a repository that destroyed processes
-- it did not start would be a worse failure than the one it prevents.
--
-- Canonical doctrine: documents\/architecture\/bounded_host_memory.md.
module Infernix.HostClaimants
  ( -- * Available host memory
    observeAvailableHostMemoryMib,
    parseDarwinVmStatAvailableMib,
    parseLinuxMemAvailableMib,

    -- * Foreign toolchain claimants
    ForeignToolchainClaimant (..),
    ProcessRow (..),
    censusForeignToolchainClaimants,
    foreignToolchainClaimants,
    isToolchainImageName,
    parseDarwinProcessTable,
    renderForeignToolchainClaimants,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.Char (isDigit, isSpace)
import Data.List (intercalate, isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.Set qualified as Set
import Infernix.HostTools qualified as HostTools
import Infernix.Runtime.Enforcer.Internal (readCgroupMemoryAvailableMib)
import System.Directory (listDirectory)
import System.FilePath (takeFileName, (</>))
import System.IO (readFile')
import System.Info (os)
import System.Posix.Process (getProcessID)
import Text.Read (readMaybe)

-- | One row of the host process table, reduced to the four facts a census
-- needs: who the process is, who its parent is, the coarse resident figure
-- that can be attributed to it, and the executable image it is running.
data ProcessRow = ProcessRow
  { processRowPid :: !Int,
    processRowParentPid :: !Int,
    processRowResidentKib :: !Integer,
    processRowImage :: !String
  }
  deriving (Eq, Show)

-- | A toolchain image running outside this process's own tree.
--
-- The resident figure is deliberately the coarse one: it names a claimant, and
-- it does not account for one.
data ForeignToolchainClaimant = ForeignToolchainClaimant
  { claimantPid :: !Int,
    claimantImage :: !String,
    claimantResidentKib :: !Integer
  }
  deriving (Eq, Show)

-- | Observe how much host memory is actually available, in MiB.
--
-- Both lanes measure the same quantity: memory a new claimant can have without
-- swapping. Linux takes the kernel's own @MemAvailable@ estimate, which counts
-- reclaimable page cache, and narrows it by the headroom of the cgroup in force
-- when one is. Darwin counts free, speculative, purgeable, and inactive pages,
-- which is the same estimate expressed in the counters @vm_stat@ publishes:
-- inactive pages there are clean or backed and the kernel hands them over on
-- demand. Active and wired pages are excluded on both lanes.
--
-- Excluding inactive pages on Darwin alone was not conservatism but a different
-- quantity, and the difference is not small: after any stage that touches the
-- filesystem the kernel holds most of the machine as inactive cache, so the
-- observation collapsed toward zero on a host with tens of GiB reclaimable and
-- refused every later stage of a multi-stage validation run.
--
-- The failure direction still matters — understating availability refuses a
-- build that would have fitted, overstating it admits one that will not — and
-- the census of foreign claimants is the other half of the admission.
--
-- An unsupported platform, an unavailable probe, or an unparseable response is
-- a named 'Left'; none is a zero-availability default and none is a pass.
observeAvailableHostMemoryMib :: IO (Either String Int)
observeAvailableHostMemoryMib =
  case os of
    "darwin" -> observeDarwinAvailableHostMemoryMib
    "linux" -> observeLinuxAvailableHostMemoryMib
    other ->
      pure
        ( Left
            ( "available host memory cannot be observed on the unsupported "
                <> "platform `"
                <> other
                <> "`; the supported lanes are Darwin (vm_stat) and Linux "
                <> "(/proc/meminfo intersected with the cgroup headroom)"
            )
        )

observeDarwinAvailableHostMemoryMib :: IO (Either String Int)
observeDarwinAvailableHostMemoryMib = do
  observed <-
    try
      (HostTools.readHostToolFallback HostTools.HostVmStat [] "") ::
      IO (Either IOException (Maybe String))
  pure $
    case observed of
      Left probeError ->
        Left
          ( "could not observe available host memory: "
              <> displayException probeError
          )
      Right Nothing ->
        Left
          "could not observe available host memory: vm_stat executable unavailable"
      Right (Just output) -> parseDarwinVmStatAvailableMib output

observeLinuxAvailableHostMemoryMib :: IO (Either String Int)
observeLinuxAvailableHostMemoryMib = do
  readResult <- try (readFile' "/proc/meminfo") :: IO (Either IOException String)
  case readResult of
    Left readError ->
      pure
        ( Left
            ( "could not read /proc/meminfo to observe available host memory: "
                <> displayException readError
            )
        )
    Right contents ->
      case parseLinuxMemAvailableMib contents of
        Left reason -> pure (Left reason)
        Right hostAvailableMib ->
          Right . maybe hostAvailableMib (min hostAvailableMib)
            <$> readCgroupMemoryAvailableMib

-- | Available MiB from a @vm_stat@ payload.
--
-- Kept pure so the malformed, truncated, and unexpected-unit cases are
-- deterministic unit-test inputs rather than host-dependent tests. The page
-- size is read from the header rather than assumed, because Apple Silicon
-- reports 16384-byte pages where the Intel lane reported 4096.
parseDarwinVmStatAvailableMib :: String -> Either String Int
parseDarwinVmStatAvailableMib output = do
  pageSizeBytes <- requirePageSize
  freePages <- requireCounter "Pages free"
  speculativePages <- requireCounter "Pages speculative"
  purgeablePages <- requireCounter "Pages purgeable"
  inactivePages <- requireCounter "Pages inactive"
  let availableBytes =
        ( freePages
            + speculativePages
            + purgeablePages
            + inactivePages
        )
          * pageSizeBytes
      availableMib = availableBytes `div` bytesPerMib
  if availableMib > toInteger (maxBound :: Int)
    then
      Left
        "could not observe available host memory: vm_stat reported a value beyond the supported integer range"
    else Right (fromInteger availableMib)
  where
    payloadLines = lines output

    requirePageSize =
      case [value | line <- payloadLines, Just value <- [pageSizeOfHeader line]] of
        value : _ -> Right value
        [] ->
          Left
            "could not observe available host memory: vm_stat emitted no `(page size of N bytes)` header"

    pageSizeOfHeader line = do
      afterMarker <- stripInfix "page size of " line
      let (digits, remainder) = span isDigit afterMarker
      if null digits || not (" bytes" `isPrefixOf` remainder)
        then Nothing
        else do
          value <- readMaybe digits
          if value > (0 :: Integer) then Just value else Nothing

    requireCounter label =
      case [ value
           | line <- payloadLines,
             Just rawValue <- [stripInfix (label <> ":") line],
             Just value <- [readCounter rawValue]
           ] of
        value : _ -> Right value
        [] ->
          Left
            ( "could not observe available host memory: vm_stat emitted no `"
                <> label
                <> ":` counter"
            )

    readCounter rawValue =
      case readMaybe (takeWhile isDigit (dropWhile isSpace rawValue)) of
        Just value | value >= (0 :: Integer) -> Just value
        _ -> Nothing

-- | Available MiB from a @\/proc\/meminfo@ payload.
--
-- The kernel always reports @MemAvailable@ in kB. A missing line, a non-@kB@
-- unit, or an unreadable value is a named 'Left' rather than a defaulted
-- figure, because the whole point of the observation is that it was taken.
parseLinuxMemAvailableMib :: String -> Either String Int
parseLinuxMemAvailableMib contents =
  case [line | line <- lines contents, "MemAvailable:" `isPrefixOf` line] of
    [] ->
      Left
        "could not observe available host memory: /proc/meminfo carries no `MemAvailable:` line"
    line : _ ->
      case words (drop (length ("MemAvailable:" :: String)) line) of
        [amount, "kB"]
          | Just kilobytes <- readMaybe amount,
            kilobytes >= (0 :: Integer) ->
              Right (fromInteger (kilobytes `div` 1024))
        _ ->
          Left
            "could not observe available host memory: /proc/meminfo carries an unreadable `MemAvailable:` value"

-- | Census the host for toolchain images this process's tree does not own.
--
-- Darwin reads the process table through the fixed absolute @ps@ candidate;
-- Linux reads @\/proc@ directly, so the launcher image needs no extra tool. A
-- process that vanishes mid-walk is skipped rather than failing the census —
-- it is no longer a claimant — while a table that cannot be read at all is a
-- named 'Left'.
censusForeignToolchainClaimants :: IO (Either String [ForeignToolchainClaimant])
censusForeignToolchainClaimants = do
  selfPid <- getProcessID
  observed <- observeProcessTable
  pure (foreignToolchainClaimants (fromIntegral selfPid) <$> observed)

observeProcessTable :: IO (Either String [ProcessRow])
observeProcessTable =
  case os of
    "darwin" -> observeDarwinProcessTable
    "linux" -> observeLinuxProcessTable
    other ->
      pure
        ( Left
            ( "the toolchain claimant census cannot read the process table on "
                <> "the unsupported platform `"
                <> other
                <> "`"
            )
        )

observeDarwinProcessTable :: IO (Either String [ProcessRow])
observeDarwinProcessTable = do
  observed <-
    try
      ( HostTools.readHostToolFallback
          HostTools.HostPs
          ["-A", "-o", "pid=,ppid=,rss=,comm="]
          ""
      ) ::
      IO (Either IOException (Maybe String))
  pure $
    case observed of
      Left probeError ->
        Left
          ( "the toolchain claimant census could not read the process table: "
              <> displayException probeError
          )
      Right Nothing ->
        Left
          "the toolchain claimant census could not read the process table: ps executable unavailable"
      Right (Just output) -> parseDarwinProcessTable output

-- | Parse the fixed @ps -A -o pid=,ppid=,rss=,comm=@ table.
--
-- The first three columns are integers and the remainder of the line is the
-- image, which routinely contains spaces because @comm@ prints an absolute
-- path. A line that does not carry three leading integers is a malformed
-- table rather than a skippable row: silently dropping rows would let a
-- claimant disappear from a census that then reports the host is clear.
parseDarwinProcessTable :: String -> Either String [ProcessRow]
parseDarwinProcessTable output =
  traverse parseRow (filter (not . all isSpace) (lines output))
  where
    parseRow line =
      case words line of
        rawPid : rawParent : rawResident : imageWords
          | Just pid <- readMaybe rawPid,
            Just parentPid <- readMaybe rawParent,
            Just residentKib <- readMaybe rawResident,
            not (null imageWords) ->
              Right
                ProcessRow
                  { processRowPid = pid,
                    processRowParentPid = parentPid,
                    processRowResidentKib = residentKib,
                    processRowImage = unwords imageWords
                  }
        _ ->
          Left
            ( "the toolchain claimant census read a malformed process-table row: "
                <> line
            )

observeLinuxProcessTable :: IO (Either String [ProcessRow])
observeLinuxProcessTable = do
  listed <- try (listDirectory "/proc") :: IO (Either IOException [FilePath])
  case listed of
    Left listError ->
      pure
        ( Left
            ( "the toolchain claimant census could not list /proc: "
                <> displayException listError
            )
        )
    Right entries -> do
      rows <-
        traverse
          readProcessStatus
          [entry | entry <- entries, all isDigit entry, not (null entry)]
      pure (Right (catMaybes rows))

readProcessStatus :: FilePath -> IO (Maybe ProcessRow)
readProcessStatus entry = do
  readResult <-
    -- Strict, because the census walks a directory listing that is stale the
    -- instant it is taken: a process that exits between the listing and this
    -- read raises from inside a lazy read's continuation, outside this `try`,
    -- and a claimant census that dies because a process exited is not a census.
    -- An entry that vanishes is an absent claimant, which is what `Nothing`
    -- already means here.
    try (readFile' ("/proc" </> entry </> "status")) ::
      IO (Either IOException String)
  pure $
    case readResult of
      Left _ -> Nothing
      Right contents -> do
        pid <- readMaybe entry
        image <- statusField "Name:" contents
        parentPid <- statusField "PPid:" contents >>= readMaybe
        let residentKib =
              fromMaybe
                0
                (statusField "VmRSS:" contents >>= readMaybe . takeWhile isDigit)
        Just
          ProcessRow
            { processRowPid = pid,
              processRowParentPid = parentPid,
              processRowResidentKib = residentKib,
              processRowImage = image
            }

statusField :: String -> String -> Maybe String
statusField label contents =
  case [ dropWhile isSpace (drop (length label) line)
       | line <- lines contents,
         label `isPrefixOf` line
       ] of
    value : _ | not (null value) -> Just (takeWhile (not . isSpace) value)
    _ -> Nothing

-- | Select the toolchain images that are not inside this process's own tree.
--
-- \"Own tree\" runs in both directions, and the ancestor half is load-bearing
-- rather than a nicety. A gate invoked as @infernix test unit@ runs inside a
-- @cabal@ this authority's own CLI started, so the observing process's parent
-- chain is full of toolchain images that are the very invocation being
-- admitted. Counting them as foreign would make the account refuse itself. A
-- sibling checkout's build is still foreign, because it is neither an ancestor
-- nor a descendant of this process.
--
-- Both walks climb the parent map and are bounded by the table size, so a
-- truncated or cyclic map terminates instead of hanging the gate that calls it.
foreignToolchainClaimants :: Int -> [ProcessRow] -> [ForeignToolchainClaimant]
foreignToolchainClaimants selfPid rows =
  [ ForeignToolchainClaimant
      { claimantPid = processRowPid row,
        claimantImage = processRowImage row,
        claimantResidentKib = processRowResidentKib row
      }
  | row <- rows,
    isToolchainImageName (takeFileName (processRowImage row)),
    not (withinOwnProcessTree (processRowPid row))
  ]
  where
    parents = Map.fromList [(processRowPid row, processRowParentPid row) | row <- rows]
    walkBudget = length rows + 1

    withinOwnProcessTree candidatePid =
      Set.member candidatePid selfAncestors
        || climbReachesSelf walkBudget candidatePid

    selfAncestors = collectAncestors walkBudget selfPid (Set.singleton selfPid)

    collectAncestors budget current seen
      | budget <= (0 :: Int) = seen
      | current <= 0 = seen
      | otherwise =
          case Map.lookup current parents of
            Nothing -> seen
            Just parent
              | parent == current -> seen
              | Set.member parent seen -> seen
              | otherwise ->
                  collectAncestors (budget - 1) parent (Set.insert parent seen)

    climbReachesSelf budget current
      | current == selfPid = True
      | budget <= (0 :: Int) = False
      | current <= 0 = False
      | otherwise =
          case Map.lookup current parents of
            Nothing -> False
            Just parent
              | parent == current -> False
              | otherwise -> climbReachesSelf (budget - 1) parent

-- | Whether an executable basename names a Haskell toolchain image.
--
-- Deliberately the compiler, driver, package, documentation, and interactive
-- images this repository's own account covers — never the native helpers
-- (@ld@, @clang@, @cc1@) that any unrelated build also runs, because a census
-- that named those would refuse on a host doing ordinary work and would teach
-- an operator to ignore it.
isToolchainImageName :: String -> Bool
isToolchainImageName image =
  image `elem` exactImages || versionedGhcImage
  where
    exactImages =
      [ "cabal",
        "ghc",
        "ghc-iserv",
        "ghc-iserv-dyn",
        "ghc-iserv-prof",
        "ghc-pkg",
        "ghci",
        "haddock",
        "hsc2hs",
        "runghc",
        "runhaskell"
      ]
    versionedGhcImage =
      case splitAt (length ("ghc-" :: String)) image of
        ("ghc-", suffix : _) -> isDigit suffix
        _ -> False

-- | Render a census refusal so it names every claimant it found.
renderForeignToolchainClaimants :: [ForeignToolchainClaimant] -> String
renderForeignToolchainClaimants claimants =
  intercalate ", " (map renderClaimant claimants)
  where
    renderClaimant claimant =
      "pid "
        <> show (claimantPid claimant)
        <> " `"
        <> claimantImage claimant
        <> "` ("
        <> show (claimantResidentKib claimant `div` 1024)
        <> " MiB resident, attributed not measured)"

stripInfix :: String -> String -> Maybe String
stripInfix needle haystack
  | null needle = Just haystack
  | otherwise = go haystack
  where
    go [] = Nothing
    go remainder@(_ : rest)
      | needle `isPrefixOf` remainder = Just (drop (length needle) remainder)
      | otherwise = go rest

bytesPerMib :: Integer
bytesPerMib = 1048576
