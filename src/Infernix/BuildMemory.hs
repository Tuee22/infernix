{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- |
-- Bounded host build memory for the toolchain account.
--
-- The bounded-host-memory doctrine partitions physical RAM into declared
-- accounts and records that the process which took this development host down
-- was in none of them: a host-side @cabal build@ from this checkout reached
-- 109.46 GiB
-- resident on a 124.94 GiB machine, wedged it for five and a half hours, and
-- was never selected by the kernel because it ran at @oom_score_adj@ 0 while
-- every cluster pod sat at 996-1000. It did not exceed its budget. It had no
-- account it could exceed.
--
-- This module is the declared account. Three properties are load-bearing, and
-- each is enforced by the shape of the types rather than by a convention.
--
-- __A ceiling is inseparable from its concurrency.__ The declared quantity is a
-- 'BuildMemoryBudget' for the whole account /together with/ the
-- 'BuildConcurrency' it will be multiplied by. 'deriveBuildMemoryPlan' is the
-- only mint of a 'BuildMemoryPlan', and 'planProcessAddressMib' /
-- 'planRtsHeapMib' are accessors on that type alone, so a per-process ceiling
-- cannot exist without the budget and the job count that produced it. This is
-- the shape that refuses the obvious wrong fix: a 48 GiB per-process heap cap
-- under @jobs: \$ncpus@ on a 32-core host permits 1536 GiB.
--
-- __The bound is lower-only and fails closed.__ 'establishBoundedBuildMemory'
-- follows 'Infernix.DescriptorSpace' exactly: it never raises a tighter
-- host-imposed limit, it writes both the soft /and/ the hard limit (lowering
-- only the soft one would leave a bound any child could raise back), and it
-- refuses by name when the limit cannot be observed as bounded afterwards.
-- 'requireBoundedBuildMemory' is the observation at the point of use, so a
-- process image that never established the bound is a loud, attributable
-- failure instead of an unbounded compile.
--
-- __The reservation comes first.__ Lowering @RLIMIT_AS@ below a reservation the
-- runtime has already taken succeeds and then kills the process on its next
-- allocation, so the establish-at-startup-and-inherit pattern
-- 'Infernix.DescriptorSpace' uses does not transfer on its own. Measured on the
-- development host with @ghc-9.12.4@, the runtime reserves __1073896924 kB__
-- (1024.65 GiB) of address space by default and __1203676 kB__ (1.15 GiB) under
-- an explicit @-xr1G@ reservation, at identical resident memory. The built
-- @infernix@ executable therefore declares
-- 'toolchainAddressSpaceReservationMib' through @-with-rtsopts@, and
-- 'toolchainReservationFitsEveryPlan' pins the invariant that the reservation
-- stays below the smallest per-process ceiling this module will ever mint.
--
-- The compiler runtime degrades gracefully rather than failing under the
-- inherited limit: it clamps its own reservation to what the limit allows and
-- compiles normally, and usable resident memory tracks the limit at roughly a
-- third of it, because the runtime reserves about three quarters of the limit
-- and its copying collector needs two semispaces. That ratio is
-- 'heapToAddressSpaceMultiplier', and it is why the plan carries an
-- address-space ceiling and a runtime heap cap rather than one number.
--
-- What this does /not/ bound is stated in the doctrine and is not restated
-- here: on a lane with no cgroup, @jobs × cap@ is arithmetic performed by this
-- repository, not a bound enforced by the kernel. Canonical doctrine:
-- documents\/architecture\/bounded_host_memory.md.
module Infernix.BuildMemory
  ( -- * Declared account
    BuildMemoryBudget,
    buildMemoryBudgetMib,
    mkBuildMemoryBudget,
    buildMemoryBudgetForPhysicalMib,
    BuildConcurrency,
    buildConcurrencyJobs,
    mkBuildConcurrency,
    resolveBuildConcurrency,

    -- * Derived plan
    BuildMemoryPlan,
    deriveBuildMemoryPlan,
    planBudgetMib,
    planJobs,
    planProcessAddressMib,
    planRtsHeapMib,

    -- * Installed bound
    BuildMemoryBound,
    buildMemoryBoundCeilingMib,
    enforcedAddressCeilingMib,
    renderBuildMemoryBound,
    establishBoundedBuildMemory,
    requireBoundedBuildMemory,

    -- * Toolchain spawn boundary
    ToolchainInvocation (..),
    ToolchainTestSuite (..),
    ToolchainSpawnAuthority,
    toolchainInvocationArguments,
    toolchainInvocationLabel,
    toolchainSpawnAuthorityPlan,
    withToolchainSpawnAuthority,
    withBoundedToolchainChild,
    applyToolchainChildVictimRank,

    -- * Resolved enforcement mechanism
    AddressSpaceEnforcement (..),
    BuildMemoryMechanism (..),
    ResolvedBuildMemoryMechanism (..),
    buildMemoryMechanismBoundsAggregate,
    renderBuildMemoryMechanism,
    renderResolvedBuildMemoryMechanism,
    resolveBuildMemoryMechanism,

    -- * Generated project ceiling
    renderCabalProjectLocal,

    -- * Calibrated constants
    committedBuildJobs,
    committedProcessAddressMib,
    committedRtsHeapMib,
    heapToAddressSpaceMultiplier,
    maximumBuildJobs,
    minimumProcessAddressMib,
    minimumProcessHeapMib,
    toolchainAddressSpaceReservationMib,
    toolchainReservationFitsEveryPlan,
    toolchainSharePercent,
  )
where

import Control.Exception (IOException, SomeException, bracket, try)
import Data.Char (isDigit)
import Data.List qualified as List
import Data.Maybe (listToMaybe)
import Infernix.Runtime.Enforcer.Internal (readCgroupMemoryLimitMib)
import System.FilePath ((</>))
import System.IO (readFile')
import System.Info (os)
import System.Posix.Resource
  ( Resource (ResourceTotalMemory),
    ResourceLimit (ResourceLimit, ResourceLimitInfinity, ResourceLimitUnknown),
    ResourceLimits (ResourceLimits, hardLimit, softLimit),
    getResourceLimit,
    setResourceLimit,
  )
import System.Posix.Types (ProcessID)
import Text.Read (readMaybe)

-- | The toolchain account's total claim on host memory, in MiB.
--
-- The constructor is unexported: a budget is either minted from a measured
-- physical-memory fact ('buildMemoryBudgetForPhysicalMib') or checked
-- explicitly ('mkBuildMemoryBudget'). There is no way to write one down.
newtype BuildMemoryBudget = BuildMemoryBudget Int
  deriving (Eq, Show)

-- | The account's total claim, in MiB.
buildMemoryBudgetMib :: BuildMemoryBudget -> Int
buildMemoryBudgetMib (BuildMemoryBudget budgetMib) = budgetMib

-- | The job count the budget is divided by.
--
-- The constructor is unexported for the same reason the budget's is: the whole
-- point of this module is that neither number is usable without the other.
newtype BuildConcurrency = BuildConcurrency Int
  deriving (Eq, Show)

-- | The job count.
buildConcurrencyJobs :: BuildConcurrency -> Int
buildConcurrencyJobs (BuildConcurrency jobs) = jobs

-- | A budget paired with the concurrency it is divided by, plus the two
-- per-process ceilings that division yields.
--
-- The constructor is unexported and 'deriveBuildMemoryPlan' is the only mint,
-- so 'planProcessAddressMib' and 'planRtsHeapMib' have no inhabitant that was
-- not divided by a job count.
data BuildMemoryPlan = BuildMemoryPlan
  { planBudget :: BuildMemoryBudget,
    planConcurrency :: BuildConcurrency,
    planProcessAddress :: Int,
    planRtsHeap :: Int
  }
  deriving (Eq, Show)

-- | The account budget this plan divides.
planBudgetMib :: BuildMemoryPlan -> Int
planBudgetMib = buildMemoryBudgetMib . planBudget

-- | The job count this plan divides by.
planJobs :: BuildMemoryPlan -> Int
planJobs = buildConcurrencyJobs . planConcurrency

-- | The per-process address-space ceiling (@RLIMIT_AS@), in MiB.
planProcessAddressMib :: BuildMemoryPlan -> Int
planProcessAddressMib = planProcessAddress

-- | The per-process runtime heap cap (@+RTS -M@), in MiB.
planRtsHeapMib :: BuildMemoryPlan -> Int
planRtsHeapMib = planRtsHeap

-- | Evidence that this process image's address space is bounded by a derived
-- per-process ceiling.
--
-- The constructor is unexported: the only ways to obtain the evidence are to
-- establish the bound or to observe that it already holds.
-- The index records which mechanism actually holds, so a bound established on a
-- lane with no address-space enforcement cannot be passed to an operation that
-- requires one. Each constructor fixes its own index and carries the mechanism
-- that produced it, so the claim and the evidence are a single fact.
data BuildMemoryBound (enforcement :: AddressSpaceEnforcement) where
  EnforcedAddressSpaceBound ::
    Int ->
    BuildMemoryMechanism 'AddressSpaceEnforced ->
    BuildMemoryBound 'AddressSpaceEnforced
  HeapCapOnlyBound ::
    Int ->
    BuildMemoryMechanism 'AddressSpaceUnavailable ->
    BuildMemoryBound 'AddressSpaceUnavailable

-- | The address-space ceiling the bound guarantees, in MiB.
--
-- Defined only for an enforced bound. This is the whole point of the index: on
-- a lane where @setrlimit@ cannot install a ceiling there is no such number to
-- return, and asking for one is a type error rather than a plausible integer.
enforcedAddressCeilingMib :: BuildMemoryBound 'AddressSpaceEnforced -> Int
enforcedAddressCeilingMib (EnforcedAddressSpaceBound limitMib _) = limitMib

-- | The per-process ceiling the bound was derived against, in MiB, on either
-- lane.
--
-- A derived number, not a guarantee — on an unenforced lane nothing in the
-- kernel holds it. Use 'enforcedAddressCeilingMib' when the guarantee is what
-- matters.
buildMemoryBoundCeilingMib :: BuildMemoryBound enforcement -> Int
buildMemoryBoundCeilingMib bound =
  case bound of
    EnforcedAddressSpaceBound limitMib _ -> limitMib
    HeapCapOnlyBound limitMib _ -> limitMib

-- | Describe the bound and, crucially, the mechanism actually behind it.
renderBuildMemoryBound :: BuildMemoryBound enforcement -> String
renderBuildMemoryBound bound =
  case bound of
    EnforcedAddressSpaceBound limitMib mechanism ->
      show limitMib
        <> " MiB enforced address-space ceiling via "
        <> renderBuildMemoryMechanism mechanism
    HeapCapOnlyBound limitMib mechanism ->
      show limitMib
        <> " MiB derived ceiling with no address-space enforcement; bounded by "
        <> renderBuildMemoryMechanism mechanism

-- | The toolchain account's share of measured host memory, as a percentage.
--
-- Half. The other half covers the Kind cluster this repository also runs on
-- the development host, the operator's desktop session, and the memory the
-- doctrine names as attributable to no process at all. It is a declared policy
-- number, not a measured one, and it is the only such number here.
toolchainSharePercent :: Int
toolchainSharePercent = 50

-- | The largest job count this module will mint.
--
-- Bounded rather than @\$ncpus@ on purpose: the job count is what the memory
-- budget affords, never what the processor count affords. A 32-core host that
-- schedules 32 compiles against a 62 GiB account would hand each one under
-- 2 GiB of heap, which 'minimumProcessHeapMib' refuses.
maximumBuildJobs :: Int
maximumBuildJobs = 8

-- | The smallest per-process runtime heap cap a plan may carry, in MiB.
--
-- This is the calibrated number, and the measurement rather than the value is
-- what has to be maintained. A complete clean @cabal build all --enable-tests@
-- of this checkout — 611 module compilations across six components that each
-- rebuild @src\/@, so the largest module is compiled six times — peaked at
-- __1328 MiB__ resident in the largest single compiler process and __1798 MiB__
-- summed across every concurrent compiler and @cabal@ process. 4096 MiB is
-- 3.1 times the single-process peak.
--
-- A ceiling set below what a legitimate build needs converts a working
-- development loop into a failing one, which is the calibration-honesty
-- obligation the doctrine names; that is why the floor is a measured multiple
-- and not the measurement itself.
minimumProcessHeapMib :: Int
minimumProcessHeapMib = 4096

-- | Address space a runtime needs per MiB of usable heap.
--
-- The runtime reserves about three quarters of an address-space limit and its
-- copying collector needs two semispaces, so usable resident memory tracks an
-- address-space limit at roughly a third of it. The plan therefore derives its
-- address-space ceiling from its heap cap rather than carrying two independent
-- numbers that can drift apart.
heapToAddressSpaceMultiplier :: Int
heapToAddressSpaceMultiplier = 3

-- | The smallest per-process address-space ceiling a plan can carry, in MiB.
minimumProcessAddressMib :: Int
minimumProcessAddressMib = minimumProcessHeapMib * heapToAddressSpaceMultiplier

-- | The address space the built @infernix@ executable reserves through
-- @-with-rtsopts=-xr@, in MiB.
--
-- 1 GiB. The reservation must stay below the smallest per-process ceiling this
-- module can mint, because a process cannot lower its own address-space limit
-- below a reservation it has already taken — it succeeds, and then dies on its
-- next allocation. 'toolchainReservationFitsEveryPlan' is that invariant, and
-- the unit suite asserts it rather than trusting the two numbers to stay in
-- agreement.
toolchainAddressSpaceReservationMib :: Int
toolchainAddressSpaceReservationMib = 1024

-- | Whether the executable's baked reservation fits under every ceiling
-- 'deriveBuildMemoryPlan' can produce.
toolchainReservationFitsEveryPlan :: Bool
toolchainReservationFitsEveryPlan =
  toolchainAddressSpaceReservationMib < minimumProcessAddressMib

-- | The job count committed to @cabal.project@ and to the compile-fixture
-- project for a fresh clone.
--
-- Those files have to carry a bound before any @infernix@ binary exists, so
-- they cannot be derived from a measured fact. The committed pair is the floor
-- itself: 4 jobs at a 4096 MiB heap cap is a 16 GiB worst case, which fits the
-- smallest host this repository is developed on and still leaves every job
-- 3.1 times the measured single-process peak.
-- 'renderCabalProjectLocal' supersedes it per machine.
committedBuildJobs :: Int
committedBuildJobs = 4

-- | The per-process runtime heap cap committed to @cabal.project@, in MiB.
committedRtsHeapMib :: Int
committedRtsHeapMib = minimumProcessHeapMib

-- | The per-process address-space ceiling committed to @cabal.project@, in MiB.
committedProcessAddressMib :: Int
committedProcessAddressMib = committedRtsHeapMib * heapToAddressSpaceMultiplier

-- | Check an explicit account budget, in MiB.
mkBuildMemoryBudget :: Int -> Either String BuildMemoryBudget
mkBuildMemoryBudget budgetMib
  | budgetMib < minimumProcessHeapMib =
      Left
        ( "a toolchain memory budget of "
            <> show budgetMib
            <> " MiB is below the "
            <> show minimumProcessHeapMib
            <> " MiB a single compiler process needs; a budget that cannot fund "
            <> "one job is not a budget"
        )
  | otherwise = Right (BuildMemoryBudget budgetMib)

-- | Mint the account budget from a measured host memory fact, in MiB.
--
-- The argument is the effective memory the host actually offers — physical
-- memory intersected with any cgroup limit in force — never a declared one.
buildMemoryBudgetForPhysicalMib :: Int -> Either String BuildMemoryBudget
buildMemoryBudgetForPhysicalMib effectiveMib
  | effectiveMib <= 0 =
      Left
        ( "measured host memory must be positive, not "
            <> show effectiveMib
            <> " MiB; a toolchain ceiling derived from an unmeasured host is a "
            <> "declared number wearing a measurement's clothes"
        )
  | otherwise =
      mkBuildMemoryBudget ((effectiveMib * toolchainSharePercent) `div` 100)

-- | Check an explicit job count.
mkBuildConcurrency :: Int -> Either String BuildConcurrency
mkBuildConcurrency jobs
  | jobs < 1 =
      Left ("a build job count must be at least 1, not " <> show jobs)
  | jobs > maximumBuildJobs =
      Left
        ( "a build job count of "
            <> show jobs
            <> " exceeds the "
            <> show maximumBuildJobs
            <> " this account will fund; the job count is what the memory "
            <> "budget affords, not what the processor count affords"
        )
  | otherwise = Right (BuildConcurrency jobs)

-- | The largest job count the budget funds at or above
-- 'minimumProcessHeapMib', capped by 'maximumBuildJobs'.
resolveBuildConcurrency :: BuildMemoryBudget -> Either String BuildConcurrency
resolveBuildConcurrency budget =
  mkBuildConcurrency
    (max 1 (min maximumBuildJobs (buildMemoryBudgetMib budget `div` minimumProcessHeapMib)))

-- | The single mint of a 'BuildMemoryPlan'.
--
-- Fails closed rather than rounding down to something unusable: a budget
-- divided by a job count that leaves each process below
-- 'minimumProcessAddressMib' is refused by name, with both operands in the
-- message, because the whole failure mode this module exists for is a ceiling
-- stated without the concurrency it is multiplied by.
deriveBuildMemoryPlan ::
  BuildMemoryBudget ->
  BuildConcurrency ->
  Either String BuildMemoryPlan
deriveBuildMemoryPlan budget concurrency
  | perProcessHeapMib < minimumProcessHeapMib =
      Left
        ( "a toolchain budget of "
            <> show (buildMemoryBudgetMib budget)
            <> " MiB divided by "
            <> show (buildConcurrencyJobs concurrency)
            <> " jobs leaves "
            <> show perProcessHeapMib
            <> " MiB per process, below the "
            <> show minimumProcessHeapMib
            <> " MiB floor; lower the job count or raise the budget"
        )
  | otherwise =
      Right
        BuildMemoryPlan
          { planBudget = budget,
            planConcurrency = concurrency,
            planProcessAddress = perProcessHeapMib * heapToAddressSpaceMultiplier,
            planRtsHeap = perProcessHeapMib
          }
  where
    perProcessHeapMib =
      buildMemoryBudgetMib budget `div` buildConcurrencyJobs concurrency

-- | Lower this process image's address-space limit to the plan's per-process
-- ceiling if it is not already at or below it.
--
-- Both the soft and the hard limit are written: lowering only the soft limit
-- would leave a bound any child could raise back, and lowering the hard limit
-- is unprivileged and one-way. The bound is inherited across @fork@ and
-- @exec@, so @cabal@, its setup helper, and the compiler itself each carry the
-- identical limit without doing anything themselves.
--
-- Fails closed: if the limit cannot be observed as bounded after the write, the
-- process image refuses to continue rather than proceeding to an unbounded
-- compile.
-- On a lane with no address-space enforcement there is nothing to install, so
-- this observes the mechanism that lane /does/ have — the committed runtime heap
-- cap — rather than minting evidence from the caller's own argument. A bound
-- that witnessed nothing would be worse than no bound at all: it would carry the
-- module's authority with none of its content.
establishBoundedBuildMemory ::
  FilePath ->
  BuildMemoryPlan ->
  IO
    ( Either
        (BuildMemoryBound 'AddressSpaceUnavailable)
        (BuildMemoryBound 'AddressSpaceEnforced)
    )
establishBoundedBuildMemory repoRootPath plan = do
  resolved <- resolveBuildMemoryMechanism
  case resolved of
    Left reason ->
      ioError
        ( userError
            ( "no host memory mechanism resolves on this lane, so a build "
                <> "memory bound cannot be established: "
                <> reason
            )
        )
    Right (UnenforcedLane mechanism) ->
      Left <$> observeHeapCapOnlyBound repoRootPath plan mechanism
    Right (EnforcedLane mechanism) ->
      Right <$> establishEnforcedAddressSpaceBound plan mechanism

establishEnforcedAddressSpaceBound ::
  BuildMemoryPlan ->
  BuildMemoryMechanism 'AddressSpaceEnforced ->
  IO (BuildMemoryBound 'AddressSpaceEnforced)
establishEnforcedAddressSpaceBound plan mechanism = do
  limits <- getResourceLimit ResourceTotalMemory
  case boundedAddressLimit ceilingMib (softLimit limits) of
    Just alreadyBounded ->
      pure (EnforcedAddressSpaceBound alreadyBounded mechanism)
    Nothing -> do
      target <- targetAddressLimit ceilingMib limits
      setResourceLimit
        ResourceTotalMemory
        ResourceLimits {softLimit = target, hardLimit = target}
      confirmed <- getResourceLimit ResourceTotalMemory
      case boundedAddressLimit ceilingMib (softLimit confirmed) of
        Just bounded -> pure (EnforcedAddressSpaceBound bounded mechanism)
        Nothing ->
          ioError
            ( userError
                ( "the address-space soft limit is still "
                    <> renderResourceLimit (softLimit confirmed)
                    <> " after lowering it to the derived per-process ceiling of "
                    <> show ceilingMib
                    <> " MiB ("
                    <> show (planBudgetMib plan)
                    <> " MiB budget / "
                    <> show (planJobs plan)
                    <> " jobs); a toolchain process started from this image "
                    <> "would compile unbounded"
                )
            )
  where
    ceilingMib = planProcessAddressMib plan

-- | Observe the bound immediately before a toolchain spawn.
--
-- The label names the spawning surface so an unbounded process image is
-- attributable from one line of output. On an address-space-enforcing lane this
-- is a @getrlimit(2)@ call; on an unenforced one it re-reads the committed
-- runtime heap cap, because that is the mechanism actually in force there.
requireBoundedBuildMemory ::
  FilePath ->
  String ->
  BuildMemoryPlan ->
  IO
    ( Either
        (BuildMemoryBound 'AddressSpaceUnavailable)
        (BuildMemoryBound 'AddressSpaceEnforced)
    )
requireBoundedBuildMemory repoRootPath label plan = do
  resolved <- resolveBuildMemoryMechanism
  case resolved of
    Left reason ->
      ioError
        ( userError
            ( label
                <> " refused to start a toolchain process on a lane that "
                <> "provides no memory bound: "
                <> reason
            )
        )
    Right (UnenforcedLane mechanism) ->
      Left <$> observeHeapCapOnlyBound repoRootPath plan mechanism
    Right (EnforcedLane mechanism) ->
      Right <$> requireEnforcedAddressSpaceBound label plan mechanism

requireEnforcedAddressSpaceBound ::
  String ->
  BuildMemoryPlan ->
  BuildMemoryMechanism 'AddressSpaceEnforced ->
  IO (BuildMemoryBound 'AddressSpaceEnforced)
requireEnforcedAddressSpaceBound label plan mechanism = do
  limits <- getResourceLimit ResourceTotalMemory
  case boundedAddressLimit ceilingMib (softLimit limits) of
    Just bounded -> pure (EnforcedAddressSpaceBound bounded mechanism)
    Nothing ->
      ioError
        ( userError
            ( label
                <> " refused to start a toolchain process with an unbounded "
                <> "address space: the limit is "
                <> renderResourceLimit (softLimit limits)
                <> ", above the derived per-process ceiling of "
                <> show ceilingMib
                <> " MiB. A compiler process in this checkout reached "
                <> "109.46 GiB resident on a 124.94 GiB host and was never "
                <> "selected by the kernel. Call establishBoundedBuildMemory "
                <> "before the first toolchain spawn in this process image."
            )
        )
  where
    ceilingMib = planProcessAddressMib plan

-- | Observe the bound on a lane that installs no address-space ceiling.
--
-- There is no @getrlimit@ answer to read here, so this reads the mechanism the
-- lane does have: the runtime heap cap committed to @cabal.project.local@, which
-- every toolchain child inherits through its own @+RTS -M@. Refusing when the
-- committed cap disagrees with the plan is the same act as the enforced lane's
-- post-write re-observation — it is what stops the returned value from being an
-- assertion about the caller's own argument.
observeHeapCapOnlyBound ::
  FilePath ->
  BuildMemoryPlan ->
  BuildMemoryMechanism 'AddressSpaceUnavailable ->
  IO (BuildMemoryBound 'AddressSpaceUnavailable)
observeHeapCapOnlyBound repoRootPath plan mechanism = do
  let projectPath = repoRootPath </> "cabal.project.local"
  -- Strict: a lazy read keeps the handle open until the string is forced, and
  -- the refusal paths below never force it. The next writer then fails with
  -- "resource busy" instead of the diagnostic this function exists to give.
  contents <-
    try (readFile' projectPath) :: IO (Either IOException String)
  case contents of
    Left readError ->
      ioError
        ( userError
            ( "this lane installs no address-space ceiling, so the runtime heap "
                <> "cap in "
                <> projectPath
                <> " is the whole bound -- and it could not be read: "
                <> show readError
                <> ". Run `infernix init` to generate it."
            )
        )
    Right projectText ->
      case committedRuntimeHeapCapMib projectText of
        Nothing ->
          ioError
            ( userError
                ( projectPath
                    <> " declares no `+RTS -M<n>M` runtime heap cap, so this "
                    <> "lane -- which installs no address-space ceiling -- has "
                    <> "no bound at all"
                )
            )
        Just committedMib
          | committedMib /= planRtsHeapMib plan ->
              ioError
                ( userError
                    ( projectPath
                        <> " commits a "
                        <> show committedMib
                        <> " MiB runtime heap cap but the derived plan is "
                        <> show (planRtsHeapMib plan)
                        <> " MiB ("
                        <> show (planBudgetMib plan)
                        <> " MiB budget / "
                        <> show (planJobs plan)
                        <> " jobs); regenerate it with `infernix init` rather "
                        <> "than compiling under a stale bound"
                    )
                )
          | otherwise ->
              pure (HeapCapOnlyBound (planProcessAddressMib plan) mechanism)

-- | The @-M\<n\>M@ runtime heap cap committed to a @cabal.project.local@ body.
--
-- Reads back what 'renderCabalProjectLocal' writes.
committedRuntimeHeapCapMib :: String -> Maybe Int
committedRuntimeHeapCapMib projectText =
  listToMaybe
    [ capMib
    | line <- lines projectText,
      token <- words line,
      Just rest <- [List.stripPrefix "-M" token],
      Just (digits, 'M') <- [List.unsnoc rest],
      not (null digits),
      all isDigit digits,
      Just capMib <- [readMaybe digits]
    ]

-- | The closed vocabulary of toolchain invocations.
--
-- This is the only way to name the compiler toolchain. A build started from a
-- caller-supplied argument list does not typecheck, which is the same shape the
-- cluster command language gives external commands: the operand set is closed,
-- so a new invocation is a new constructor with a review rather than a string
-- assembled at a call site.
data ToolchainInvocation
  = -- | @cabal build all@ — the largest memory consumer in the gate set.
    ToolchainBuildAll
  | -- | @cabal test \<suite\>@ for one of the repository's declared suites.
    ToolchainTest ToolchainTestSuite
  deriving (Eq, Show)

-- | The declared Cabal test suites a toolchain invocation may name.
data ToolchainTestSuite
  = HaskellStyleSuite
  | UnitSuite
  | IntegrationSuite
  deriving (Eq, Show)

-- | The exact argument vector for an invocation.
toolchainInvocationArguments :: ToolchainInvocation -> [String]
toolchainInvocationArguments invocation =
  case invocation of
    ToolchainBuildAll -> ["build", "all"]
    ToolchainTest suite -> ["test", toolchainTestSuiteName suite]

-- | A short label naming the invocation in a refusal.
toolchainInvocationLabel :: ToolchainInvocation -> String
toolchainInvocationLabel invocation =
  case invocation of
    ToolchainBuildAll -> "cabal build all"
    ToolchainTest suite -> "cabal test " <> toolchainTestSuiteName suite

toolchainTestSuiteName :: ToolchainTestSuite -> String
toolchainTestSuiteName suite =
  case suite of
    HaskellStyleSuite -> "infernix-haskell-style"
    UnitSuite -> "infernix-unit"
    IntegrationSuite -> "infernix-integration"

-- | Authority to start a toolchain process under a derived ceiling.
--
-- The constructor is unexported and the phantom region tag is universally
-- quantified by 'withToolchainSpawnAuthority', so an authority cannot escape the
-- region that established its ceiling and a plan minted for one region cannot be
-- substituted for another's.
--
-- The authority carries the mechanism its region resolved as well as the plan.
-- Resolving the lane and then discarding the answer is what made every gate
-- command fail on Darwin: the spawn wrapper below assumed an address-space
-- rlimit that this platform does not implement.
data ToolchainSpawnAuthority s
  = ToolchainSpawnAuthority BuildMemoryPlan ResolvedBuildMemoryMechanism

-- | The plan whose ceiling this authority carries.
toolchainSpawnAuthorityPlan :: ToolchainSpawnAuthority s -> BuildMemoryPlan
toolchainSpawnAuthorityPlan (ToolchainSpawnAuthority plan _) = plan

-- | Enter a region in which toolchain processes may be started under a derived
-- ceiling.
--
-- The mechanism is resolved rather than assumed: a lane on which none resolves
-- is a named refusal before any process starts. The resolved mechanism is then
-- /retained/ on the authority, because what bounds a toolchain child differs by
-- lane and the spawn wrapper has to act on that difference rather than on an
-- assumption.
withToolchainSpawnAuthority ::
  BuildMemoryPlan ->
  (forall s. ToolchainSpawnAuthority s -> IO result) ->
  IO result
withToolchainSpawnAuthority plan action = do
  mechanism <- resolveBuildMemoryMechanism
  case mechanism of
    Left reason ->
      ioError
        ( userError
            ( "no host memory mechanism resolves on this lane, so a toolchain "
                <> "process cannot be bounded: "
                <> reason
            )
        )
    Right resolved -> action (ToolchainSpawnAuthority plan resolved)

-- | Hold the derived per-process ceiling in force across a toolchain spawn.
--
-- The soft limit alone is lowered here, and the hard limit is deliberately left
-- untouched, because this authority is held by the long-lived operator CLI image
-- — the same process that later starts @kubectl@, @helm@, and a routed
-- end-to-end browser, none of which should inherit a build ceiling. Lowering the
-- hard limit is one-way, so it would bound those too.
--
-- What that costs is stated rather than hidden: a child could raise its own soft
-- limit back within the inherited hard limit. No toolchain does, and the
-- structural half of the guarantee is elsewhere — the closed vocabulary and this
-- authority are what make an unbounded toolchain spawn unrepresentable.
-- 'establishBoundedBuildMemory' remains the stronger form for a process image
-- dedicated to a build, where lowering the hard limit costs nothing.
--
-- The ceiling is held only on a lane that implements one. Darwin aliases
-- @RLIMIT_AS@ to the advisory @RLIMIT_RSS@ and rejects a finite soft limit
-- against the infinite hard limit it reports, so @setrlimit@ returns @EINVAL@
-- and this wrapper threw before the child was ever started — taking
-- @infernix test lint@, @test unit@, @test integration@ and @test all@ with it.
-- On that lane the bound is the runtime heap cap and the job count, both already
-- committed to @cabal.project.local@ and both inherited by the child without a
-- bracket. Acting on the resolved mechanism is what keeps this honest: the
-- alternative is asserting a ceiling the platform never installed.
withBoundedToolchainChild :: ToolchainSpawnAuthority s -> IO result -> IO result
withBoundedToolchainChild (ToolchainSpawnAuthority plan resolved) action =
  case resolved of
    EnforcedLane _ -> bracket acquire restore (const action)
    UnenforcedLane _ -> action
  where
    ceilingMib = planProcessAddressMib plan
    acquire = do
      limits <- getResourceLimit ResourceTotalMemory
      case boundedAddressLimit ceilingMib (softLimit limits) of
        Just _ -> pure limits
        Nothing -> do
          target <- targetAddressLimit ceilingMib limits
          setResourceLimit ResourceTotalMemory limits {softLimit = target}
          pure limits
    restore = setResourceLimit ResourceTotalMemory

-- | Raise the spawned child's out-of-memory victim rank.
--
-- Deliberately the weakest of the three legs, and the caveats are the point.
-- @oom_badness@ is per-process while the hazard is per-tree, so this changes
-- /who/ the kernel selects rather than /how much/ is allocated. It is applied to
-- the child after @createProcess@ returns its pid, so a child that exhausts the
-- host in its first milliseconds is still ranked as its parent was — the race is
-- real and is not closable through the public spawn API, which offers no hook
-- between fork and exec.
--
-- Platform-indexed so Darwin is an explicit no-op rather than a silent one: it
-- has no @oom_score_adj@ and no equivalent global out-of-memory killer.
applyToolchainChildVictimRank :: ToolchainSpawnAuthority s -> ProcessID -> IO ()
applyToolchainChildVictimRank _authority childPid =
  case os of
    "linux" -> do
      written <-
        try
          ( writeFile
              ("/proc/" <> show childPid <> "/oom_score_adj")
              (show toolchainChildVictimRank <> "\n")
          )
      case written :: Either SomeException () of
        Right () -> pure ()
        -- A rank that cannot be written is reported and not fatal: it is the
        -- weakest leg, and refusing the build because the kernel would pick a
        -- different victim would trade a real capability for a ranking.
        Left rankError ->
          ioError
            ( userError
                ( "could not raise the toolchain child's out-of-memory victim "
                    <> "rank: "
                    <> show rankError
                )
            )
    _ -> pure ()

-- | The @oom_score_adj@ a toolchain child runs at.
--
-- Cluster pods sit at 996-1000 and the container runtime sits strongly negative.
-- 800 puts a build above every ordinary process and below the pods, which is the
-- ranking the 2026-08-03 incident inverted: the compiler ran at 0 and the kernel
-- destroyed 111 pod processes without ever selecting it.
toolchainChildVictimRank :: Int
toolchainChildVictimRank = 800

-- | Whether the lane installs an address-space ceiling the kernel enforces.
--
-- The doctrine has always said the mechanism is resolved per lane and that
-- Darwin has no enforced address-space limit. This promotes that sentence into
-- the types, so a bound established on a lane without one cannot be handed to
-- an operation that requires one.
data AddressSpaceEnforcement
  = AddressSpaceEnforced
  | AddressSpaceUnavailable

-- | The strongest memory bound this lane actually provides, indexed by whether
-- it enforces an address-space ceiling.
--
-- The index and the constructor are one fact, not two: each constructor fixes
-- its own index, so no value can claim an enforcement its mechanism does not
-- have. Carrying a separate unindexed copy alongside the index would reintroduce
-- exactly the over-claim this type exists to forbid.
data BuildMemoryMechanism (enforcement :: AddressSpaceEnforcement) where
  -- | A finite cgroup v2 maximum is in force, so the /aggregate/ of the build
  -- tree is bounded by the kernel. Carries the observed limit in MiB. This is
  -- the outer-container lane's own limit and a Linux host-native lane running
  -- inside a limited slice or scope.
  CgroupAggregateMechanism :: Int -> BuildMemoryMechanism 'AddressSpaceEnforced
  -- | Linux host-native with no finite cgroup maximum. The per-process
  -- address-space rlimit and runtime heap cap hold; the aggregate is
  -- @jobs x cap@ arithmetic performed by this repository, not a kernel bound.
  LinuxProcessCeilingMechanism :: BuildMemoryMechanism 'AddressSpaceEnforced
  -- | Darwin. No cgroups, and @RLIMIT_AS@ is aliased to the advisory
  -- @RLIMIT_RSS@: the kernel reports it infinite and rejects every finite
  -- ceiling written against it, so there is no address-space bound to install
  -- at all. What bounds this lane is the runtime heap cap plus a bounded job
  -- count, and the aggregate is arithmetic.
  DarwinHeapCapMechanism :: BuildMemoryMechanism 'AddressSpaceUnavailable

-- | A resolved lane, with its enforcement decided.
--
-- 'resolveBuildMemoryMechanism' reads the platform at runtime, so the index
-- cannot be known statically; this sum is where that runtime fact is refined
-- into one of the two indexed types. Every consumer must handle both arms,
-- which is the point — the lane distinction stops being something a caller can
-- forget.
data ResolvedBuildMemoryMechanism
  = EnforcedLane (BuildMemoryMechanism 'AddressSpaceEnforced)
  | UnenforcedLane (BuildMemoryMechanism 'AddressSpaceUnavailable)

-- | Whether the mechanism bounds the /sum/ of a build tree, as opposed to each
-- process in it.
--
-- Only the cgroup one does. Every caller that reports a bound must distinguish
-- these, because @jobs x cap@ is arithmetic this repository performs and a
-- cgroup maximum is a bound the kernel enforces.
buildMemoryMechanismBoundsAggregate :: BuildMemoryMechanism enforcement -> Bool
buildMemoryMechanismBoundsAggregate mechanism =
  case mechanism of
    CgroupAggregateMechanism _ -> True
    LinuxProcessCeilingMechanism -> False
    DarwinHeapCapMechanism -> False

renderBuildMemoryMechanism :: BuildMemoryMechanism enforcement -> String
renderBuildMemoryMechanism mechanism =
  case mechanism of
    CgroupAggregateMechanism limitMib ->
      "cgroup v2 maximum of " <> show limitMib <> " MiB bounding the build tree's aggregate"
    LinuxProcessCeilingMechanism ->
      "per-process address-space rlimit and runtime heap cap; the aggregate is jobs x cap arithmetic"
    DarwinHeapCapMechanism ->
      "runtime heap cap and bounded concurrency; the aggregate is jobs x cap arithmetic"

-- | Render a resolved lane whichever arm it took.
renderResolvedBuildMemoryMechanism :: ResolvedBuildMemoryMechanism -> String
renderResolvedBuildMemoryMechanism resolved =
  case resolved of
    EnforcedLane mechanism -> renderBuildMemoryMechanism mechanism
    UnenforcedLane mechanism -> renderBuildMemoryMechanism mechanism

-- | Resolve the mechanism for this lane, never assume one.
resolveBuildMemoryMechanism :: IO (Either String ResolvedBuildMemoryMechanism)
resolveBuildMemoryMechanism =
  case os of
    "linux" ->
      Right
        . EnforcedLane
        . maybe LinuxProcessCeilingMechanism CgroupAggregateMechanism
        <$> readCgroupMemoryLimitMib
    "darwin" -> pure (Right (UnenforcedLane DarwinHeapCapMechanism))
    other ->
      pure
        ( Left
            ( "the platform `"
                <> other
                <> "` provides none of the supported bounds: a cgroup maximum, an "
                <> "address-space rlimit, or a runtime heap cap"
            )
        )

-- | Render the untracked per-machine @cabal.project.local@.
--
-- Both numbers appear in the banner because neither is meaningful alone; the
-- worst case the file actually bounds is spelled out rather than left to the
-- reader.
renderCabalProjectLocal :: BuildMemoryPlan -> String
renderCabalProjectLocal plan =
  unlines
    [ "-- Generated by `infernix init`. Untracked (.gitignore); regenerate rather",
      "-- than edit. Canonical doctrine:",
      "-- documents/architecture/bounded_host_memory.md",
      "--",
      "-- The toolchain account holds "
        <> show (planBudgetMib plan)
        <> " MiB of measured host memory,",
      "-- divided by "
        <> show (planJobs plan)
        <> " jobs into a "
        <> show (planRtsHeapMib plan)
        <> " MiB per-process runtime heap cap",
      "-- and a "
        <> show (planProcessAddressMib plan)
        <> " MiB per-process address-space reservation.",
      "--",
      "-- A per-process cap is not a host bound on its own. Both numbers are",
      "-- stated because the worst case is the product: "
        <> show (planJobs plan)
        <> " jobs x "
        <> show (planRtsHeapMib plan)
        <> " MiB",
      "-- = "
        <> show (planJobs plan * planRtsHeapMib plan)
        <> " MiB of runtime heap, inside the "
        <> show (planBudgetMib plan)
        <> " MiB account.",
      "",
      "jobs: " <> show (planJobs plan),
      "",
      "package *",
      "  ghc-options: +RTS -M"
        <> show (planRtsHeapMib plan)
        <> "M -xr"
        <> show (planProcessAddressMib plan)
        <> "M -RTS"
    ]

-- | The limit as a bounded MiB count, or 'Nothing' when it exceeds the ceiling
-- or cannot be represented.
boundedAddressLimit :: Int -> ResourceLimit -> Maybe Int
boundedAddressLimit ceilingMib limit =
  case limit of
    ResourceLimit value
      | value <= toInteger ceilingMib * bytesPerMib ->
          Just (fromInteger (value `div` bytesPerMib))
    _ -> Nothing

-- | The limit to write, given the hard limit that caps it.
--
-- An unknown hard limit is fail-closed rather than guessed, exactly as the
-- descriptor-space kernel does: writing a limit without knowing the ceiling it
-- must respect can only be wrong.
targetAddressLimit :: Int -> ResourceLimits -> IO ResourceLimit
targetAddressLimit ceilingMib limits =
  case hardLimit limits of
    ResourceLimitInfinity -> pure (ResourceLimit ceilingBytes)
    ResourceLimit value -> pure (ResourceLimit (min ceilingBytes value))
    ResourceLimitUnknown ->
      ioError
        ( userError
            ( "the address-space hard limit is not representable, so the "
                <> "per-process ceiling cannot be installed without risking a raise"
            )
        )
  where
    ceilingBytes = toInteger ceilingMib * bytesPerMib

bytesPerMib :: Integer
bytesPerMib = 1048576

renderResourceLimit :: ResourceLimit -> String
renderResourceLimit limit =
  case limit of
    ResourceLimit value -> show value <> " bytes"
    ResourceLimitInfinity -> "unlimited"
    ResourceLimitUnknown -> "unknown"
