{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Phase 1 Sprint 1.21 — measure the host memory facts the bounded-build
-- ceiling is derived from.
--
-- The doctrine's first clause is that a ceiling is derived from /measured/
-- physical RAM, so this module observes rather than declares, and it fails
-- closed with a named reason rather than substituting a plausible number: a
-- guessed capacity produces a ceiling that looks measured and is not, which is
-- the exact failure mode 'Infernix.BuildMemory' exists to prevent.
--
-- Two figures are recorded because they differ where it matters. The physical
-- figure is what the machine has. The effective figure is what a build on this
-- lane actually gets: inside the Linux outer launcher container,
-- @\/proc\/meminfo@ still reports the whole machine while the container's own
-- cgroup maximum is the real bound, so the Linux path intersects the two and
-- the smaller wins. On Darwin, the supported container lanes consume a
-- co-resident Colima VM pledge from the same physical RAM, so the host-native
-- toolchain's effective figure subtracts the conservatively observed aggregate
-- active pledge. An unavailable or malformed Colima observation fails closed.
--
-- Canonical doctrine: documents\/architecture\/bounded_host_memory.md.
module Infernix.HostMemory
  ( observeHostMemoryFacts,
    buildMemoryPlanForHost,
    resolveLiveBuildMemoryPlan,
    parseMemTotalMib,
  )
where

import Control.Exception (SomeException, try)
import Data.Char (isDigit, isSpace)
import Infernix.BuildMemory
  ( BuildMemoryPlan,
    buildMemoryBudgetForPhysicalMib,
    deriveBuildMemoryPlan,
    resolveBuildConcurrency,
  )
import Infernix.DemoConfig.Colima qualified as Colima
import Infernix.HostConfig (HostConfig, HostMemoryFacts (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools qualified as HostTools
import Infernix.Runtime.Enforcer.Internal (readCgroupMemoryLimitMib)
import Numeric.Natural (Natural)
import System.Info (os)

-- | Observe this host's physical and effective memory, in MiB.
--
-- Linux reads @\/proc\/meminfo@ and intersects it with the cgroup v2 maximum in
-- force. Darwin reads @sysctl -n hw.memsize@ through the manifest-owned
-- absolute path, then subtracts the aggregate active Colima pledge observed by
-- the shared fixed-path producer in 'Infernix.DemoConfig.Colima'. The manifest
-- record is passed in rather than read back because the sole caller is the
-- manifest materializer itself and the file it is about to write does not
-- exist yet.
--
-- An unsupported platform, an unreadable probe, or a non-positive result is a
-- named 'Left'.
observeHostMemoryFacts :: HostConfig -> IO (Either String HostMemoryFacts)
observeHostMemoryFacts hostConfig =
  case os of
    "linux" -> observeLinuxHostMemoryFacts
    "darwin" -> observeDarwinHostMemoryFacts hostConfig
    other ->
      pure
        ( Left
            ( "host memory cannot be measured on the unsupported platform `"
                <> other
                <> "`; the supported lanes are Linux (/proc/meminfo intersected "
                <> "with the cgroup maximum) and Darwin (sysctl hw.memsize minus "
                <> "the active Colima pledge)"
            )
        )

-- | Derive this machine's build ceiling from the manifest's measured facts.
--
-- The effective figure is the one the account is a share of, because it is
-- what a build on this lane actually gets. An unmeasured manifest — the
-- 'Infernix.HostConfig.unmeasuredHostMemoryFacts' zero shape — is refused by
-- 'buildMemoryBudgetForPhysicalMib' by name, so a ceiling can never be derived
-- from a host nobody looked at.
buildMemoryPlanForHost :: HostConfig -> Either String BuildMemoryPlan
buildMemoryPlanForHost hostConfig = do
  budget <- buildMemoryBudgetForPhysicalMib effectiveMib
  concurrency <- resolveBuildConcurrency budget
  deriveBuildMemoryPlan budget concurrency
  where
    effectiveMib =
      fromIntegral
        (hostEffectiveMemoryMib (HostConfig.hostMemory hostConfig))

-- | Derive this machine's build ceiling from a live measurement.
--
-- The manifest's recorded facts are what @infernix init@ divides into the
-- generated @cabal.project.local@; this is the same derivation performed at the
-- point of use, and it measures the machine actually running the build rather
-- than the machine that last ran @init@. That distinction matters on the Linux
-- launcher lane, where the image bakes an unmeasured manifest and the container
-- it runs in has its own cgroup maximum.
resolveLiveBuildMemoryPlan :: HostConfig -> IO (Either String BuildMemoryPlan)
resolveLiveBuildMemoryPlan hostConfig = do
  observed <- observeHostMemoryFacts hostConfig
  pure $ do
    facts <- observed
    budget <-
      buildMemoryBudgetForPhysicalMib (fromIntegral (hostEffectiveMemoryMib facts))
    concurrency <- resolveBuildConcurrency budget
    deriveBuildMemoryPlan budget concurrency

observeLinuxHostMemoryFacts :: IO (Either String HostMemoryFacts)
observeLinuxHostMemoryFacts = do
  readResult <- try (readFile "/proc/meminfo")
  case readResult :: Either SomeException String of
    Left readError ->
      pure
        ( Left
            ( "could not read /proc/meminfo to measure physical host memory: "
                <> show readError
            )
        )
    Right contents ->
      case parseMemTotalMib contents of
        Nothing ->
          pure
            ( Left
                "could not parse a positive `MemTotal:` line from /proc/meminfo"
            )
        Just physicalMib -> do
          cgroupLimitMib <- readCgroupMemoryLimitMib
          pure
            ( Right
                HostMemoryFacts
                  { hostPhysicalMemoryMib = fromIntegral physicalMib,
                    hostEffectiveMemoryMib =
                      fromIntegral (maybe physicalMib (min physicalMib) cgroupLimitMib)
                  }
            )

observeDarwinHostMemoryFacts :: HostConfig -> IO (Either String HostMemoryFacts)
observeDarwinHostMemoryFacts hostConfig = do
  probed <-
    try
      (HostTools.readHostTool hostConfig HostTools.HostSysctl ["-n", "hw.memsize"] "")
  case probed :: Either SomeException String of
    Left probeError ->
      pure
        ( Left
            ( "could not read `sysctl -n hw.memsize` to measure physical host "
                <> "memory: "
                <> show probeError
            )
        )
    Right output ->
      case readPositiveInteger (filter (not . isSpace) output) of
        Nothing ->
          pure
            ( Left
                ( "could not parse a positive byte count from `sysctl -n "
                    <> "hw.memsize` output: "
                    <> output
                )
            )
        Just bytes ->
          let physicalMib = fromInteger (bytes `div` bytesPerMib) :: Natural
           in do
                observedPledge <- Colima.observeActiveColimaPledgeMib
                pure $ do
                  pledgedMib <- observedPledge
                  effectiveMib <-
                    Colima.effectiveHostMemoryMibAfterColimaPledge
                      physicalMib
                      pledgedMib
                  Right
                    HostMemoryFacts
                      { hostPhysicalMemoryMib = physicalMib,
                        hostEffectiveMemoryMib = effectiveMib
                      }

-- | The @MemTotal:@ line of a @\/proc\/meminfo@ payload, in MiB.
--
-- The kernel always reports @MemTotal@ in kB. A missing line, a non-@kB@ unit,
-- or a non-positive value is 'Nothing' rather than a defaulted figure.
parseMemTotalMib :: String -> Maybe Int
parseMemTotalMib contents =
  case [line | line <- lines contents, take 9 line == "MemTotal:"] of
    [] -> Nothing
    line : _ ->
      case words (drop 9 line) of
        [amount, "kB"] -> do
          kilobytes <- readPositiveInteger amount
          let mib = kilobytes `div` 1024
          if mib > 0 then Just (fromInteger mib) else Nothing
        _ -> Nothing

readPositiveInteger :: String -> Maybe Integer
readPositiveInteger rawValue
  | not (null rawValue),
    all isDigit rawValue,
    [(value, "")] <- reads rawValue,
    value > 0 =
      Just value
  | otherwise = Nothing

bytesPerMib :: Integer
bytesPerMib = 1048576
