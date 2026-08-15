{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RoleAnnotations #-}

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
-- here: on a lane with no cgroup, the compiler subtotal plus the Cabal and
-- worker-associated control/helper subtotal is arithmetic performed by this
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
    planControlHeapMib,
    planProcessAddressMib,
    planRtsHeapMib,
    planCompilerHeapAccountMib,
    planControlAccountMib,
    planToolchainAccountMib,

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
    allToolchainTestSuites,
    toolchainTestSuiteName,
    DarwinAppleMaterializerTest (..),
    ToolchainSpawnAuthority,
    ToolchainHostAdmission,
    admissionAvailableMib,
    admitToolchainAccount,
    observeToolchainHostAdmission,
    toolchainSpawnAuthorityAdmission,
    toolchainInvocationArguments,
    toolchainInvocationLabel,
    requireToolchainInvocationProjectState,
    toolchainSpawnAuthorityPlan,
    withToolchainSpawnAuthority,
    withBoundedToolchainChild,
    applyToolchainChildVictimRank,

    -- * Darwin build-memory validation
    DarwinBuildMemoryValidationAuthority,
    darwinBuildMemoryValidationAuthorityAccountMib,
    DarwinBuildMemoryInvocation (..),
    DarwinBuildMemorySamples,
    DarwinBuildMemoryInvocationEvidence,
    DarwinInstalledCliIsolationEvidence,
    DarwinBuildMemoryEvidence,
    checkedToolchainAccountMib,
    requireDarwinBuildMemoryValidationAuthority,
    withDarwinBuildMemoryValidationChild,
    darwinBuildMemoryInvocationArguments,
    darwinBuildMemoryInvocationLabel,
    darwinBuildMemorySampleIntervalMicros,
    emptyDarwinBuildMemorySamples,
    recordDarwinBuildMemorySample,
    mkDarwinBuildMemoryInvocationEvidence,
    mkDarwinInstalledCliIsolationEvidence,
    mkDarwinBuildMemoryEvidence,
    renderDarwinBuildMemoryEvidence,

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
    toolchainControlHeapMib,
    minimumProcessAddressMib,
    minimumProcessHeapMib,
    toolchainAddressSpaceReservationMib,
    toolchainReservationFitsEveryPlan,
    toolchainSharePercent,
  )
where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (IOException, bracket, try)
import Control.Monad (filterM, unless, void)
import Data.Char (isDigit)
import Data.List qualified as List
import Data.Maybe (isNothing)
import Data.Word (Word64)
import Infernix.HostClaimants
  ( censusForeignToolchainClaimants,
    observeAvailableHostMemoryMib,
    renderForeignToolchainClaimants,
  )
import Infernix.Runtime.Enforcer.Internal (readCgroupMemoryLimitMib)
import System.Directory (doesPathExist)
import System.FilePath (isAbsolute, (</>))
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

-- | The compiler-worker count the budget is divided across.
--
-- The constructor is unexported for the same reason the budget's is: the whole
-- point of this module is that neither number is usable without the other.
newtype BuildConcurrency = BuildConcurrency Int
  deriving (Eq, Show)

-- | The compiler-worker count supplied to Cabal's @--jobs@.
buildConcurrencyJobs :: BuildConcurrency -> Int
buildConcurrencyJobs (BuildConcurrency jobs) = jobs

-- | A budget paired with compiler concurrency, the control-image heap cap,
-- and the two compiler-process ceilings that division yields.
--
-- The constructor is unexported and 'deriveBuildMemoryPlan' is the only mint,
-- so 'planProcessAddressMib' and 'planRtsHeapMib' have no inhabitant that was
-- not divided by a job count.
data BuildMemoryPlan = BuildMemoryPlan
  { planBudget :: BuildMemoryBudget,
    planConcurrency :: BuildConcurrency,
    planControlHeap :: Int,
    planProcessAddress :: Int,
    planRtsHeap :: Int
  }
  deriving (Eq, Show)

-- | The account budget this plan divides.
planBudgetMib :: BuildMemoryPlan -> Int
planBudgetMib = buildMemoryBudgetMib . planBudget

-- | The compiler-worker count supplied to Cabal's @--jobs@.
planJobs :: BuildMemoryPlan -> Int
planJobs = buildConcurrencyJobs . planConcurrency

-- | The heap cap for Cabal and Haskell control/helper images, in MiB.
planControlHeapMib :: BuildMemoryPlan -> Int
planControlHeapMib = planControlHeap

-- | The per-process address-space ceiling (@RLIMIT_AS@), in MiB.
planProcessAddressMib :: BuildMemoryPlan -> Int
planProcessAddressMib = planProcessAddress

-- | The per-process runtime heap cap (@+RTS -M@), in MiB.
planRtsHeapMib :: BuildMemoryPlan -> Int
planRtsHeapMib = planRtsHeap

-- | The compiler-worker heap subtotal, in MiB.
planCompilerHeapAccountMib :: BuildMemoryPlan -> Int
planCompilerHeapAccountMib plan = planJobs plan * planRtsHeapMib plan

-- | The conservative control/helper subtotal, in MiB.
--
-- One claimant is the live Cabal driver and one accompanies each compiler job
-- (Setup, linker, or another serialized helper in that worker slot).
planControlAccountMib :: BuildMemoryPlan -> Int
planControlAccountMib plan =
  (planJobs plan + 1) * planControlHeapMib plan

-- | The complete compiler-phase account, in MiB.
planToolchainAccountMib :: BuildMemoryPlan -> Int
planToolchainAccountMib plan =
  planCompilerHeapAccountMib plan + planControlAccountMib plan

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

-- | The fixed heap cap for Cabal and Haskell control/helper images, in MiB.
--
-- The clean-build calibration measured 1798 MiB across the complete concurrent
-- compiler/driver tree while its largest compiler alone held 1328 MiB. A 1024
-- MiB control slot is therefore more than twice the measured non-compiler
-- remainder. It is deliberately distinct from 'minimumProcessHeapMib': giving
-- every Cabal, test, Setup, and helper image a compiler-sized claim made the
-- account arithmetic false before a compiler could start.
toolchainControlHeapMib :: Int
toolchainControlHeapMib = 1024

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
-- they cannot be derived from a measured fact. The committed account is three
-- 4096 MiB compiler slots plus four 1024 MiB control/helper slots: exactly
-- 16384 MiB. It fits the smallest host this repository is developed on and
-- still leaves every compiler 3.1 times the measured single-process peak.
-- 'renderCabalProjectLocal' supersedes it per machine.
committedBuildJobs :: Int
committedBuildJobs = 3

-- | The per-process runtime heap cap committed to @cabal.project@, in MiB.
committedRtsHeapMib :: Int
committedRtsHeapMib = minimumProcessHeapMib

-- | The per-process address-space ceiling committed to @cabal.project@, in MiB.
committedProcessAddressMib :: Int
committedProcessAddressMib = committedRtsHeapMib * heapToAddressSpaceMultiplier

-- | Check an explicit account budget, in MiB.
mkBuildMemoryBudget :: Int -> Either String BuildMemoryBudget
mkBuildMemoryBudget budgetMib
  | budgetMib < minimumToolchainAccountMib =
      Left
        ( "a toolchain memory budget of "
            <> show budgetMib
            <> " MiB is below the "
            <> show minimumToolchainAccountMib
            <> " MiB needed for one compiler plus its helper and the live Cabal "
            <> "driver; a budget that cannot fund the complete claimant set is "
            <> "not a budget"
        )
  | otherwise = Right (BuildMemoryBudget budgetMib)

-- One compiler at the calibrated floor, one worker-associated helper, and the
-- live Cabal driver are the smallest complete toolchain claimant set.
minimumToolchainAccountMib :: Int
minimumToolchainAccountMib =
  minimumProcessHeapMib + 2 * toolchainControlHeapMib

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
  | budgetInteger > toInteger (maxBound :: Int) =
      Left "measured host memory produced a toolchain budget that overflowed Int"
  | otherwise = mkBuildMemoryBudget (fromInteger budgetInteger)
  where
    budgetInteger =
      toInteger effectiveMib * toInteger toolchainSharePercent `div` 100

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

-- | The largest compiler-worker count the complete account funds at or above
-- 'minimumProcessHeapMib', capped by 'maximumBuildJobs'. Each worker needs one
-- compiler slot and one control/helper slot; the live Cabal driver needs one
-- additional control slot.
resolveBuildConcurrency :: BuildMemoryBudget -> Either String BuildConcurrency
resolveBuildConcurrency budget =
  mkBuildConcurrency
    ( max
        1
        ( min
            maximumBuildJobs
            ( (buildMemoryBudgetMib budget - toolchainControlHeapMib)
                `div` (minimumProcessHeapMib + toolchainControlHeapMib)
            )
        )
    )

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
  | availableCompilerMib <= 0 || perProcessHeapMib < minimumProcessHeapMib =
      Left
        ( "a toolchain budget of "
            <> show (buildMemoryBudgetMib budget)
            <> " MiB, after reserving "
            <> show controlAccountMib
            <> " MiB for the live Cabal driver and worker-associated helpers, "
            <> "divided by "
            <> show (buildConcurrencyJobs concurrency)
            <> " jobs leaves "
            <> show perProcessHeapMib
            <> " MiB per process, below the "
            <> show minimumProcessHeapMib
            <> " MiB floor; lower the job count or raise the budget"
        )
  | processAddressMibInteger > toInteger (maxBound :: Int) =
      Left "the derived compiler address-space reservation overflowed Int"
  | otherwise =
      Right
        BuildMemoryPlan
          { planBudget = budget,
            planConcurrency = concurrency,
            planControlHeap = toolchainControlHeapMib,
            planProcessAddress = fromInteger processAddressMibInteger,
            planRtsHeap = perProcessHeapMib
          }
  where
    jobs = buildConcurrencyJobs concurrency
    controlAccountMib = (jobs + 1) * toolchainControlHeapMib
    availableCompilerMib = buildMemoryBudgetMib budget - controlAccountMib
    perProcessHeapMib =
      availableCompilerMib `div` jobs
    processAddressMibInteger =
      toInteger perProcessHeapMib * toInteger heapToAddressSpaceMultiplier

-- | Lower this process image's address-space limit to the plan's per-process
-- ceiling if it is not already at or below it.
--
-- Both the soft and the hard limit are written: lowering only the soft limit
-- would leave a bound any child could raise back, and lowering the hard limit
-- is unprivileged and one-way. The bound is inherited across @fork@ and
-- @exec@, so @cabal@, compiler images, and their worker-associated helpers each
-- carry the identical limit without doing anything themselves.
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
-- job count, runtime heap cap, and runtime reservation, because that complete
-- generated triple is the mechanism actually in force there.
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
-- lane does have: the job count, runtime heap cap, and runtime reservation
-- committed to @cabal.project.local@. Refusing when any member of that triple
-- disagrees with the plan is the same act as the enforced lane's post-write
-- re-observation — it is what stops the returned value from being an assertion
-- about the caller's own argument.
observeHeapCapOnlyBound ::
  FilePath ->
  BuildMemoryPlan ->
  BuildMemoryMechanism 'AddressSpaceUnavailable ->
  IO (BuildMemoryBound 'AddressSpaceUnavailable)
observeHeapCapOnlyBound repoRootPath plan mechanism = do
  _ <- requireCommittedToolchainSettings repoRootPath plan
  pure (HeapCapOnlyBound (planProcessAddressMib plan) mechanism)

-- | The three settings in the generated @cabal.project.local@ that make the
-- Darwin bound one fact: concurrency, per-process heap, and the compiler
-- runtime's address-space reservation. The constructor remains private so an
-- authority can carry only settings observed from the generated file.
data CommittedToolchainSettings = CommittedToolchainSettings
  { committedToolchainJobs :: !Int,
    committedToolchainHeapMib :: !Int,
    committedToolchainAddressReservationMib :: !Int
  }
  deriving (Eq, Show)

-- | Strictly observe the settings 'renderCabalProjectLocal' generates and
-- require the complete triple to agree with the live plan.
--
-- Requiring exactly one occurrence matters. Cabal can accept repeated fields,
-- and accepting the first matching @jobs:@ or RTS token would authenticate one
-- value while the toolchain consumes another. This file is binary-owned and
-- documented as regenerate-rather-than-edit, so an absent, duplicate, or
-- malformed setting is a named refusal rather than an invitation to guess
-- Cabal's precedence rules.
requireCommittedToolchainSettings ::
  FilePath ->
  BuildMemoryPlan ->
  IO CommittedToolchainSettings
requireCommittedToolchainSettings repoRootPath plan = do
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
            ( "the generated toolchain settings in "
                <> projectPath
                <> " could not be read: "
                <> show readError
                <> ". Run `infernix init` to generate them."
            )
        )
    Right projectText ->
      case committedToolchainSettings projectText of
        Nothing ->
          ioError
            ( userError
                ( projectPath
                    <> " must contain exactly one generated `jobs: <n>` row, "
                    <> "one `-M<n>M` runtime heap cap, and one `-xr<n>M` "
                    <> "runtime address-space reservation; regenerate it with "
                    <> "`infernix init`"
                )
            )
        Just committed
          | committedToolchainJobs committed /= planJobs plan
              || committedToolchainHeapMib committed /= planRtsHeapMib plan
              || committedToolchainAddressReservationMib committed
                /= planProcessAddressMib plan ->
              ioError
                ( userError
                    ( projectPath
                        <> " commits jobs/heap/address settings "
                        <> show
                          ( committedToolchainJobs committed,
                            committedToolchainHeapMib committed,
                            committedToolchainAddressReservationMib committed
                          )
                        <> " but the live derived plan requires "
                        <> show
                          ( planJobs plan,
                            planRtsHeapMib plan,
                            planProcessAddressMib plan
                          )
                        <> " ("
                        <> show (planBudgetMib plan)
                        <> " MiB account); regenerate it with `infernix init` "
                        <> "rather than compiling under stale concurrency or "
                        <> "runtime limits"
                    )
                )
          | otherwise -> pure committed

-- | Parse exactly the generated settings this module renders. The parser is
-- deliberately narrower than Cabal's complete project grammar: the file is
-- generated by Infernix, and every other shape is refused.
committedToolchainSettings :: String -> Maybe CommittedToolchainSettings
committedToolchainSettings projectText = do
  jobs <- exactlyOne (generatedJobCounts projectText)
  heapMib <- exactlyOne (generatedRuntimeMibValues "-M" projectText)
  addressMib <- exactlyOne (generatedRuntimeMibValues "-xr" projectText)
  pure
    CommittedToolchainSettings
      { committedToolchainJobs = jobs,
        committedToolchainHeapMib = heapMib,
        committedToolchainAddressReservationMib = addressMib
      }

generatedJobCounts :: String -> [Int]
generatedJobCounts projectText =
  [ jobs
  | line <- lines projectText,
    ["jobs:", rawJobs] <- [words line],
    not (null rawJobs),
    all isDigit rawJobs,
    Just jobs <- [readMaybe rawJobs]
  ]

generatedRuntimeMibValues :: String -> String -> [Int]
generatedRuntimeMibValues prefix projectText =
  [ valueMib
  | line <- lines projectText,
    token <- words line,
    Just rest <- [List.stripPrefix prefix token],
    Just (digits, 'M') <- [List.unsnoc rest],
    not (null digits),
    all isDigit digits,
    Just valueMib <- [readMaybe digits]
  ]

exactlyOne :: [value] -> Maybe value
exactlyOne values =
  case values of
    [value] -> Just value
    _ -> Nothing

-- | The closed vocabulary of toolchain invocations.
--
-- This is the only way to name the compiler toolchain. A build started from a
-- caller-supplied argument list does not typecheck, which is the same shape the
-- cluster command language gives external commands: the operand set is closed,
-- so a new invocation is a new constructor with a review rather than a string
-- assembled at a call site.
data ToolchainInvocation
  = -- | @cabal build all --enable-tests@ — the largest memory consumer in the gate set.
    ToolchainBuildAll
  | -- | @cabal test \<suite\>@ for one of the root package's declared suites.
    ToolchainTest ToolchainTestSuite
  | -- | The exact Cabal-format check in its solver-isolated package.
    ToolchainCabalFormat
  | -- | One fixed Darwin-only Apple materializer cohort mode.
    ToolchainDarwinAppleMaterializerTest DarwinAppleMaterializerTest
  deriving (Eq, Show)

-- | The root package's declared Cabal test suites a toolchain invocation may name.
data ToolchainTestSuite
  = HaskellStyleSuite
  | UnitSuite
  | CompileFailSuite
  | ArtifactTransactionSuite
  | AppleMaterializerSuite
  | CappedEngineObserverSuite
  | ExecutionPlanInternalSuite
  | IntegrationSuite
  deriving (Bounded, Enum, Eq, Show)

-- | The complete constructor-derived suite inventory. Adding a constructor
-- automatically extends the manifest-closure test rather than requiring a
-- second hand-maintained list.
allToolchainTestSuites :: [ToolchainTestSuite]
allToolchainTestSuites = [minBound .. maxBound]

-- | The two Darwin-only Apple materializer modes that are deliberately absent
-- from the default machine-independent suite. Their option strings are not
-- caller data: selecting a mode chooses one exact reviewed Cabal vector.
data DarwinAppleMaterializerTest
  = DarwinProductionAudiverisCancellation
  | DarwinInstalledPythonSourceIsolation
  deriving (Eq, Show)

-- | The exact argument vector for an invocation, including the memory plan
-- carried by its spawn authority.
--
-- Cabal reads @cabal.project.local@ after the parent has spawned it, so a
-- pre-spawn observation of that file cannot itself bind what the child later
-- consumes. Command-line configuration has the final precedence, and deriving
-- these arguments from the opaque authority closes that recheck-to-read gap:
-- neither a caller nor a concurrent file replacement can substitute an
-- unbounded job count or compiler runtime limit. The leading RTS segment caps
-- the Cabal driver image itself; the final Cabal options cap the compiler
-- images and retain their bounded address-space reservation.
toolchainInvocationArguments ::
  ToolchainSpawnAuthority s ->
  ToolchainInvocation ->
  [String]
toolchainInvocationArguments authority invocation =
  toolchainDriverRtsArguments authority
    <> invocationArguments
    <> toolchainAuthorityArguments authority
  where
    invocationArguments =
      case invocation of
        ToolchainBuildAll -> ["build", "all", "--enable-tests"]
        ToolchainTest suite -> ["test", toolchainTestSuiteName suite, "--enable-tests"]
        ToolchainCabalFormat ->
          [ "test",
            "--project-file=test/cabal-format/cabal.project",
            "--builddir=" <> toolchainCabalFormatBuildDirectory authority,
            "infernix-cabal-format:test:infernix-cabal-format",
            "--enable-tests"
          ]
        ToolchainDarwinAppleMaterializerTest darwinTest ->
          [ "test",
            toolchainTestSuiteName AppleMaterializerSuite,
            "--enable-tests",
            "--test-show-details=direct",
            "--test-options=" <> darwinAppleMaterializerTestOption darwinTest
          ]

-- Phase 1 Sprint 1.21 retired the build-only @GHCRTS@ environment cap this
-- boundary used to add to every toolchain child. It was carried as a control
-- cap for the Cabal driver and system Haskell build tools, and the reason it
-- is gone is that it does not bind the thing it was aimed at: an RTS image
-- linked without runtime options does not accept an inherited @GHCRTS@ at all,
-- it /refuses to start/ under one. A third-party package's own setup program
-- is exactly such an image, so the environment form converted a capped build
-- into a failed one while capping nothing. The caps that bind are the
-- invocation-borne ones below — the leading @+RTS@ segment for the driver
-- image and the final ordered Cabal option for the compiler images — and both
-- are derived from the opaque authority rather than from an operator surface.
--
-- Keep the driver cap before Cabal's program arguments. These tokens are
-- consumed by Cabal's own RTS and therefore cannot be mistaken for a Cabal
-- subcommand or forwarded to GHC.
toolchainDriverRtsArguments :: ToolchainSpawnAuthority s -> [String]
toolchainDriverRtsArguments authority =
  [ "+RTS",
    "-M" <> show (planControlHeapMib plan) <> "M",
    "-RTS"
  ]
  where
    plan = toolchainSpawnAuthorityPlan authority

-- Keep these as the final Cabal arguments. Cabal merges project files before
-- command-line configuration, so their position and authority-derived values
-- are what make a later @cabal.project.local@ replacement unable to widen the
-- production child.
toolchainAuthorityArguments :: ToolchainSpawnAuthority s -> [String]
toolchainAuthorityArguments authority =
  [ "--jobs=" <> show (planJobs plan),
    -- One plural option is load-bearing. The rejected repeated-singular form
    -- did not preserve the RTS grouping at configure time and handed -M/-xr to
    -- GHC as compiler flags. The plural form parses this one value into the
    -- exact ordered GHC argv.
    "--ghc-options=+RTS -M"
      <> show (planRtsHeapMib plan)
      <> "M -xr"
      <> show (planProcessAddressMib plan)
      <> "M -RTS"
  ]
  where
    plan = toolchainSpawnAuthorityPlan authority

-- | A short label naming the invocation in a refusal.
toolchainInvocationLabel ::
  ToolchainSpawnAuthority s ->
  ToolchainInvocation ->
  String
toolchainInvocationLabel authority invocation =
  case invocation of
    ToolchainBuildAll -> "cabal build all --enable-tests"
    ToolchainTest suite ->
      "cabal test " <> toolchainTestSuiteName suite <> " --enable-tests"
    ToolchainCabalFormat ->
      "cabal test --project-file=test/cabal-format/cabal.project "
        <> "--builddir="
        <> toolchainCabalFormatBuildDirectory authority
        <> " "
        <> "infernix-cabal-format:test:infernix-cabal-format --enable-tests"
    ToolchainDarwinAppleMaterializerTest darwinTest ->
      "cabal test "
        <> toolchainTestSuiteName AppleMaterializerSuite
        <> " --enable-tests"
        <> " --test-show-details=direct --test-options="
        <> darwinAppleMaterializerTestOption darwinTest

darwinAppleMaterializerTestOption :: DarwinAppleMaterializerTest -> String
darwinAppleMaterializerTestOption darwinTest =
  case darwinTest of
    DarwinProductionAudiverisCancellation ->
      "--darwin-production-audiveris-cancellation"
    DarwinInstalledPythonSourceIsolation ->
      "--darwin-installed-python-source-isolation"

toolchainTestSuiteName :: ToolchainTestSuite -> String
toolchainTestSuiteName suite =
  case suite of
    HaskellStyleSuite -> "infernix-haskell-style"
    UnitSuite -> "infernix-unit"
    CompileFailSuite -> "infernix-compile-fail"
    ArtifactTransactionSuite -> "infernix-artifact-transaction"
    AppleMaterializerSuite -> "infernix-apple-materializer"
    CappedEngineObserverSuite -> "infernix-capped-engine-observer"
    ExecutionPlanInternalSuite -> "infernix-execution-plan-internal"
    IntegrationSuite -> "infernix-integration"

toolchainCabalFormatBuildDirectory :: ToolchainSpawnAuthority s -> FilePath
toolchainCabalFormatBuildDirectory authority =
  toolchainSpawnAuthorityRepoRoot authority </> ".build" </> "cabal-format"

toolchainSpawnAuthorityRepoRoot :: ToolchainSpawnAuthority s -> FilePath
toolchainSpawnAuthorityRepoRoot
  (ToolchainSpawnAuthority repoRootPath _ _ _ _ _) = repoRootPath

-- | Refuse unreviewed sibling project overlays before a toolchain child starts.
--
-- The solver-isolated Cabal-format project is tracked source, while Cabal
-- automatically merges sibling @.local@ and @.freeze@ files. The supported
-- workflow freezes source for a validation run, so an absence check at the
-- masked pre-spawn boundary is the required fail-closed contract; this does not
-- claim a cross-process filesystem lease.
requireToolchainInvocationProjectState ::
  ToolchainSpawnAuthority s ->
  ToolchainInvocation ->
  IO ()
requireToolchainInvocationProjectState authority invocation =
  case invocation of
    ToolchainCabalFormat -> do
      unexpectedPaths <- filterM doesPathExist cabalFormatOverlayPaths
      unless (null unexpectedPaths) $
        ioError
          ( userError
              ( "refusing Cabal-format validation with unreviewed sibling project overlays: "
                  <> show unexpectedPaths
              )
          )
    _ -> pure ()
  where
    projectRoot =
      toolchainSpawnAuthorityRepoRoot authority
        </> "test"
        </> "cabal-format"
    cabalFormatOverlayPaths =
      [ projectRoot </> "cabal.project.local",
        projectRoot </> "cabal.project.freeze"
      ]

-- | Authority to start a toolchain process under a derived ceiling.
--
-- The constructor is unexported and the phantom region tag is universally
-- quantified by 'withToolchainSpawnAuthority', so an authority cannot escape the
-- region that established its ceiling and a plan minted for one region cannot be
-- substituted for another's.
--
-- The authority carries the mechanism its region resolved, the plan, and the
-- exact generated settings observed when the region was entered. Resolving the
-- lane and then discarding the answer is what made every gate command fail on
-- Darwin; minting authority without observing the file would be the symmetric
-- error, asserting the only bound that lane has without checking it exists.
-- Its private single-flight token serializes concurrent calls through the
-- package-owned child-lifecycle wrapper for /this authority/. It cannot stop a
-- caller from ignoring that wrapper and using @System.Process@ directly; the
-- closed repository-owned CLI caller plus the raw-spawn lint are the other half
-- of this boundary. This is deliberately not a machine-global lease:
-- independently minted authorities in separate CLI images remain an
-- unsupported concurrent-claimant case named in the doctrine.
newtype ToolchainSingleFlight
  = ToolchainSingleFlight (MVar ())

-- | Evidence that this host was observed able to fund the toolchain account,
-- and that no toolchain claimant outside this process's own tree was resident
-- when the observation was taken.
--
-- The constructor is unexported and 'admitToolchainAccount' is the only mint,
-- so an authority cannot be assembled from arithmetic over installed capacity
-- alone. That is the whole point of clause 4 of the doctrine: declared capacity
-- is what the machine contains, availability is what it has left, and the two
-- differ by whatever else is resident.
--
-- What it proves is bounded and is stated rather than implied. It is an
-- observation at an instant, not a lease: nothing stops a claimant from
-- starting immediately afterwards, which is why the child boundary re-takes it
-- rather than trusting the one taken at mint.
newtype ToolchainHostAdmission
  = ToolchainHostAdmission Int
  deriving (Eq, Show)

-- | The available host memory this admission was granted against, in MiB.
admissionAvailableMib :: ToolchainHostAdmission -> Int
admissionAvailableMib (ToolchainHostAdmission availableMib) = availableMib

type role ToolchainSpawnAuthority nominal

data ToolchainSpawnAuthority s
  = ToolchainSpawnAuthority
      FilePath
      BuildMemoryPlan
      ResolvedBuildMemoryMechanism
      CommittedToolchainSettings
      ToolchainSingleFlight
      ToolchainHostAdmission

-- | The plan whose ceiling this authority carries.
toolchainSpawnAuthorityPlan :: ToolchainSpawnAuthority s -> BuildMemoryPlan
toolchainSpawnAuthorityPlan (ToolchainSpawnAuthority _ plan _ _ _ _) = plan

-- | The admission observation this authority was minted against.
toolchainSpawnAuthorityAdmission ::
  ToolchainSpawnAuthority s ->
  ToolchainHostAdmission
toolchainSpawnAuthorityAdmission
  (ToolchainSpawnAuthority _ _ _ _ _ admission) = admission

-- | Decide admission from a plan and the two observations, purely.
--
-- Kept separate from 'observeToolchainHostAdmission' so both refusals are
-- deterministic test inputs rather than host-dependent ones: the account this
-- refuses is arithmetic, and the observations it refuses on are data.
admitToolchainAccount ::
  BuildMemoryPlan ->
  Int ->
  [String] ->
  Either String ToolchainHostAdmission
admitToolchainAccount plan availableMib namedClaimants
  | availableMib < planBudgetMib plan =
      Left
        ( "refusing to start the governed toolchain: the host has "
            <> show availableMib
            <> " MiB of available memory, below the "
            <> show (planBudgetMib plan)
            <> " MiB account this plan claims ("
            <> show (planJobs plan)
            <> " jobs x "
            <> show (planRtsHeapMib plan)
            <> " MiB compiler heap plus "
            <> show (planJobs plan + 1)
            <> " x "
            <> show (planControlHeapMib plan)
            <> " MiB control/helper claims)"
        )
  | not (null namedClaimants) =
      Left
        ( "refusing to start the governed toolchain beside a toolchain "
            <> "claimant this authority did not start: "
            <> List.intercalate ", " namedClaimants
            <> "; the claimant is named and left running rather than killed, "
            <> "so quiesce it and retry"
        )
  | otherwise = Right (ToolchainHostAdmission availableMib)

-- | Take both admission observations and decide on them.
--
-- Either observation failing is a refusal that reports what it found. An
-- unavailable probe is never read as "the host is free": a census that could
-- not run has found nothing precisely because it did not look.
observeToolchainHostAdmission ::
  BuildMemoryPlan ->
  IO (Either String ToolchainHostAdmission)
observeToolchainHostAdmission plan = do
  observedAvailability <- observeAvailableHostMemoryMib
  case observedAvailability of
    Left reason ->
      pure
        ( Left
            ( "refusing to start the governed toolchain without an admission "
                <> "observation: "
                <> reason
            )
        )
    Right availableMib -> do
      observedCensus <- censusForeignToolchainClaimants
      pure $
        case observedCensus of
          Left reason ->
            Left
              ( "refusing to start the governed toolchain without a "
                  <> "foreign-claimant census: "
                  <> reason
              )
          Right claimants ->
            admitToolchainAccount
              plan
              availableMib
              [renderForeignToolchainClaimants claimants | not (null claimants)]

requireToolchainHostAdmission ::
  BuildMemoryPlan ->
  IO ToolchainHostAdmission
requireToolchainHostAdmission plan = do
  admitted <- observeToolchainHostAdmission plan
  either (ioError . userError) pure admitted

-- | Enter a region in which toolchain processes may be started under a derived
-- ceiling.
--
-- The mechanism is resolved rather than assumed: a lane on which none resolves
-- is a named refusal before any process starts. The resolved mechanism is then
-- /retained/ on the authority, because what bounds a toolchain child differs by
-- lane and the spawn wrapper has to act on that difference rather than on an
-- assumption. Authority minting also consumes an exact observation of the
-- binary-owned @cabal.project.local@ settings; the spawn boundary re-observes
-- them so changing the file inside the region cannot reuse stale authority.
withToolchainSpawnAuthority ::
  FilePath ->
  BuildMemoryPlan ->
  (forall s. ToolchainSpawnAuthority s -> IO result) ->
  IO result
withToolchainSpawnAuthority repoRootPath plan action
  | not (isAbsolute repoRootPath) || '\0' `elem` repoRootPath =
      ioError
        ( userError
            "refusing to mint toolchain authority from a non-absolute or NUL-containing repository root"
        )
  | otherwise = do
      committed <- requireCommittedToolchainSettings repoRootPath plan
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
        Right resolved -> do
          admission <- requireToolchainHostAdmission plan
          singleFlight <- ToolchainSingleFlight <$> newMVar ()
          action
            ( ToolchainSpawnAuthority
                repoRootPath
                plan
                resolved
                committed
                singleFlight
                admission
            )

-- | Hold one authority's single-flight token and derived per-process ceiling
-- across a complete toolchain-child lifecycle.
--
-- The soft limit alone is lowered here, and the hard limit is deliberately left
-- untouched, because this authority is held by the long-lived operator CLI image
-- — the same process that later starts @kubectl@, @helm@, and a routed
-- end-to-end browser, none of which should inherit a build ceiling. Lowering the
-- hard limit is one-way, so it would bound those too.
--
-- What that costs is stated rather than hidden: a child could raise its own soft
-- limit back within the inherited hard limit. No toolchain does, and the
-- repository-owned boundary is the closed vocabulary, this authority, and the
-- lint that rejects a raw toolchain spawn beside the package-owned caller.
-- 'establishBoundedBuildMemory' remains the stronger form for a process image
-- dedicated to a build, where lowering the hard limit costs nothing.
--
-- The ceiling is held only on a lane that implements one. Darwin aliases
-- @RLIMIT_AS@ to the advisory @RLIMIT_RSS@ and rejects a finite soft limit
-- against the infinite hard limit it reports, so @setrlimit@ returns @EINVAL@
-- and this wrapper threw before the child was ever started — taking
-- @infernix test lint@, @test unit@, @test integration@ and @test all@ with it.
-- On that lane the bound is the runtime heap cap and the job count, with the
-- runtime reservation making that cap installable in each compiler image. All
-- three are committed to @cabal.project.local@, observed both when authority is
-- minted and here immediately before the spawn, and rendered from this same
-- authority into Cabal's command-line configuration. The explicit arguments
-- are load-bearing: Cabal opens the project file in the child after this
-- wrapper returns to its action, so the observation alone would leave a
-- recheck-to-child-read race. Acting on the resolved mechanism and binding the
-- child arguments are what keep this honest: the alternative is asserting a
-- ceiling the platform never installed or the child never consumed.
--
-- The caller's action owns spawn, victim-rank adjustment, sampling where
-- applicable, wait, and exceptional cleanup/reap. Returning a live child from
-- the action would release both the token and the inherited soft ceiling too
-- early; the only production callers keep that entire lifecycle inside.
withBoundedToolchainChild :: ToolchainSpawnAuthority s -> IO result -> IO result
withBoundedToolchainChild
  ( ToolchainSpawnAuthority
      repoRootPath
      plan
      resolved
      committedAtMint
      (ToolchainSingleFlight singleFlight)
      _admissionAtMint
    )
  childLifecycle =
    withMVar singleFlight $ \() -> do
      committedAtSpawn <- requireCommittedToolchainSettings repoRootPath plan
      unless (committedAtSpawn == committedAtMint) $
        ioError
          ( userError
              "generated toolchain settings changed after spawn authority was minted"
          )
      -- The admission taken at mint is an observation at an instant, not a
      -- lease. A claimant that started inside the region, or a host that has
      -- since filled up, must refuse the child rather than ride the earlier
      -- answer, so the observation is re-taken here immediately before the
      -- fork the caller's action performs.
      _admissionAtSpawn <- requireToolchainHostAdmission plan
      case resolved of
        EnforcedLane _ -> bracket acquire restore (const childLifecycle)
        UnenforcedLane _ -> childLifecycle
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
      -- An ordinary /proc write failure is not fatal: victim selection is the
      -- weakest leg, and refusing the build would trade a real capability for
      -- a ranking. Catch only IOException; asynchronous cancellation must
      -- escape into the caller's owned-group cleanup rather than be demoted.
      void
        ( try
            ( writeFile
                ("/proc/" <> show childPid <> "/oom_score_adj")
                (show toolchainChildVictimRank <> "\n")
            ) ::
            IO (Either IOException ())
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

-- | Darwin-only refinement of a toolchain authority for the opt-in measured
-- build validation. The constructor is hidden: the retained mechanism and the
-- complete account arithmetic must be checked together before a validation
-- child can be named.
type role DarwinBuildMemoryValidationAuthority nominal

data DarwinBuildMemoryValidationAuthority s
  = DarwinBuildMemoryValidationAuthority
      (ToolchainSpawnAuthority s)
      Int

-- | The two closed Cabal invocations exercised in one fresh scratch build
-- root. The install follows the build only after the build succeeds, so it can
-- reuse the same compiled graph while still proving the executable install
-- surface carries the identical authority-derived limits.
data DarwinBuildMemoryInvocation
  = DarwinBuildAllWithTests
  | DarwinInstallAllExecutables
  deriving (Eq, Show)

-- | Checked complete compiler-phase account, in MiB.
--
-- This accepts primitive integers so the overflow and over-budget refusal can
-- be pinned without fabricating a 'BuildMemoryPlan'. Production calls it only
-- through 'requireDarwinBuildMemoryValidationAuthority'.
checkedToolchainAccountMib :: Int -> Int -> Int -> Int -> Either String Int
checkedToolchainAccountMib jobs heapMib controlHeapMib budgetMib
  | jobs <= 0 = Left "Darwin build-memory validation requires a positive job count"
  | heapMib <= 0 = Left "Darwin build-memory validation requires a positive compiler heap cap"
  | controlHeapMib <= 0 = Left "Darwin build-memory validation requires a positive control/helper heap cap"
  | budgetMib <= 0 = Left "Darwin build-memory validation requires a positive account budget"
  | accountInteger > toInteger (maxBound :: Int) =
      Left "Darwin build-memory validation complete claimant arithmetic overflowed Int"
  | accountInteger > toInteger budgetMib =
      Left
        ( "Darwin build-memory validation refuses compiler plus control/helper claims of "
            <> show accountInteger
            <> " MiB above its "
            <> show budgetMib
            <> " MiB account budget"
        )
  | otherwise = Right (fromInteger accountInteger)
  where
    accountInteger =
      toInteger jobs * toInteger heapMib
        + (toInteger jobs + 1) * toInteger controlHeapMib

-- | Refine an existing exact-file spawn authority to the one supported Darwin
-- validation mechanism and check the complete account before any scratch root,
-- descriptor, observer, or child is created.
requireDarwinBuildMemoryValidationAuthority ::
  ToolchainSpawnAuthority s ->
  Either String (DarwinBuildMemoryValidationAuthority s)
requireDarwinBuildMemoryValidationAuthority authority
  | os /= "darwin" =
      Left "Darwin build-memory validation is available only on Darwin"
  | otherwise =
      case toolchainSpawnAuthorityMechanism authority of
        UnenforcedLane DarwinHeapCapMechanism -> do
          accountMib <-
            checkedToolchainAccountMib
              (planJobs plan)
              (planRtsHeapMib plan)
              (planControlHeapMib plan)
              (planBudgetMib plan)
          Right (DarwinBuildMemoryValidationAuthority authority accountMib)
        resolved ->
          Left
            ( "Darwin build-memory validation requires exactly the unenforced "
                <> "Darwin heap-cap mechanism, but resolved "
                <> renderResolvedBuildMemoryMechanism resolved
            )
  where
    plan = toolchainSpawnAuthorityPlan authority

toolchainSpawnAuthorityMechanism ::
  ToolchainSpawnAuthority s ->
  ResolvedBuildMemoryMechanism
toolchainSpawnAuthorityMechanism (ToolchainSpawnAuthority _ _ resolved _ _ _) = resolved

-- | Re-observe the exact generated settings at the validation spawn boundary
-- without exposing the underlying general toolchain authority.
withDarwinBuildMemoryValidationChild ::
  DarwinBuildMemoryValidationAuthority s ->
  IO result ->
  IO result
withDarwinBuildMemoryValidationChild
  (DarwinBuildMemoryValidationAuthority authority _) =
    withBoundedToolchainChild authority

-- | The checked complete claimant account this validation authority carries,
-- in MiB.
--
-- Exposed so the evidence constructor can refuse a sampled peak that reaches
-- it without reconstructing the arithmetic from the plan a second time.
darwinBuildMemoryValidationAuthorityAccountMib ::
  DarwinBuildMemoryValidationAuthority s ->
  Int
darwinBuildMemoryValidationAuthorityAccountMib
  (DarwinBuildMemoryValidationAuthority _ accountMib) = accountMib

-- | Render one validation invocation. The caller supplies only the internally
-- minted scratch root; the executable remains the manifest's closed HostCabal
-- selection in the CLI and every behavioral operand is fixed by this enum.
-- The authority-derived Cabal-driver RTS prefix begins both vectors, while
-- authority-derived concurrency and compiler RTS limits deliberately remain
-- the final Cabal arguments.
darwinBuildMemoryInvocationArguments ::
  DarwinBuildMemoryValidationAuthority s ->
  DarwinBuildMemoryInvocation ->
  FilePath ->
  Either String [String]
darwinBuildMemoryInvocationArguments
  (DarwinBuildMemoryValidationAuthority authority _)
  invocation
  scratchRoot
    | not (isAbsolute scratchRoot) || '\0' `elem` scratchRoot =
        Left "Darwin build-memory validation scratch root must be an absolute NUL-free path"
    | otherwise =
        Right
          ( toolchainDriverRtsArguments authority
              <> invocationArguments
              <> toolchainAuthorityArguments authority
          )
    where
      buildRoot = scratchRoot </> "dist-newstyle"
      installRoot = scratchRoot </> "bin"
      invocationArguments =
        case invocation of
          DarwinBuildAllWithTests ->
            [ "build",
              "all",
              "--enable-tests",
              "--builddir=" <> buildRoot
            ]
          DarwinInstallAllExecutables ->
            [ "install",
              "all:exes",
              "--installdir=" <> installRoot,
              "--install-method=copy",
              "--overwrite-policy=always",
              "--builddir=" <> buildRoot
            ]

darwinBuildMemoryInvocationLabel :: DarwinBuildMemoryInvocation -> String
darwinBuildMemoryInvocationLabel invocation =
  case invocation of
    DarwinBuildAllWithTests -> "cabal build all --enable-tests"
    DarwinInstallAllExecutables -> "cabal install all:exes"

-- | Fixed pause between complete aggregate physical-footprint samples. Each
-- sample itself has the observer kernel's independent bounded deadline.
darwinBuildMemorySampleIntervalMicros :: Int
darwinBuildMemorySampleIntervalMicros = 1000000

-- | Count and maximum for one invocation's observations. No samples are
-- summed: the metric is a sampled peak of an aggregate process-group physical
-- footprint, not a time integral and not a per-process maximum.
data DarwinBuildMemorySamples = DarwinBuildMemorySamples
  { darwinBuildMemorySampleCount :: !Word64,
    darwinBuildMemorySampledPeakBytes :: !Word64
  }
  deriving (Eq, Show)

emptyDarwinBuildMemorySamples :: DarwinBuildMemorySamples
emptyDarwinBuildMemorySamples = DarwinBuildMemorySamples 0 0

recordDarwinBuildMemorySample ::
  Word64 ->
  DarwinBuildMemorySamples ->
  Either String DarwinBuildMemorySamples
recordDarwinBuildMemorySample physicalFootprintBytes samples
  | darwinBuildMemorySampleCount samples == maxBound =
      Left "Darwin build-memory validation sample count overflowed Word64"
  | otherwise =
      Right
        DarwinBuildMemorySamples
          { darwinBuildMemorySampleCount = darwinBuildMemorySampleCount samples + 1,
            darwinBuildMemorySampledPeakBytes =
              max
                physicalFootprintBytes
                (darwinBuildMemorySampledPeakBytes samples)
          }

data DarwinBuildMemoryInvocationEvidence = DarwinBuildMemoryInvocationEvidence
  { darwinBuildMemoryEvidenceInvocation :: !DarwinBuildMemoryInvocation,
    darwinBuildMemoryEvidenceExitStatus :: !Int,
    darwinBuildMemoryEvidenceDurationMicros :: !Word64,
    darwinBuildMemoryEvidenceSampleCount :: !Word64,
    darwinBuildMemoryEvidenceSampledPeakBytes :: !Word64
  }
  deriving (Eq, Show)

-- | Evidence that the freshly installed runtime CLI ignored an adversarial
-- inherited @GHCRTS@ value. The constructor is hidden; only an ordinary zero
-- exit from the closed proof can enter the final report.
data DarwinInstalledCliIsolationEvidence
  = DarwinInstalledCliIsolationEvidence
  deriving (Eq, Show)

mkDarwinInstalledCliIsolationEvidence :: Int -> Either String DarwinInstalledCliIsolationEvidence
mkDarwinInstalledCliIsolationEvidence exitStatus
  | exitStatus == 0 = Right DarwinInstalledCliIsolationEvidence
  | otherwise =
      Left
        ( "the freshly installed runtime CLI processed the build-only GHCRTS environment (isolation proof exit "
            <> show exitStatus
            <> ")"
        )

-- | The build is the measurement-bearing invocation and must cross at least
-- one fixed-cadence footprint probe. The install deliberately reuses that build
-- root and can therefore reach ordinary terminal completion before the first
-- one-second probe. A zero-sample install is retained as explicit terminal
-- evidence (and rendered as such), never converted into a fabricated
-- footprint; the aggregate evidence constructor still requires a positive
-- sampled build.
mkDarwinBuildMemoryInvocationEvidence ::
  DarwinBuildMemoryInvocation ->
  Int ->
  Word64 ->
  DarwinBuildMemorySamples ->
  Either String DarwinBuildMemoryInvocationEvidence
mkDarwinBuildMemoryInvocationEvidence invocation exitStatus durationMicros samples
  | darwinBuildMemorySampleCount samples == 0
      && invocation == DarwinBuildAllWithTests =
      Left
        ( darwinBuildMemoryInvocationLabel invocation
            <> " completed without a sampled aggregate physical footprint"
        )
  | otherwise =
      Right
        DarwinBuildMemoryInvocationEvidence
          { darwinBuildMemoryEvidenceInvocation = invocation,
            darwinBuildMemoryEvidenceExitStatus = exitStatus,
            darwinBuildMemoryEvidenceDurationMicros = durationMicros,
            darwinBuildMemoryEvidenceSampleCount = darwinBuildMemorySampleCount samples,
            darwinBuildMemoryEvidenceSampledPeakBytes = darwinBuildMemorySampledPeakBytes samples
          }

data DarwinBuildMemoryEvidence = DarwinBuildMemoryEvidence
  { darwinBuildMemoryPhysicalMib :: !Integer,
    darwinBuildMemoryEffectiveMib :: !Integer,
    darwinBuildMemoryActiveColimaPledgeMib :: !Integer,
    darwinBuildMemoryBudgetMib :: !Int,
    darwinBuildMemoryJobs :: !Int,
    darwinBuildMemoryHeapMib :: !Int,
    darwinBuildMemoryControlHeapMib :: !Int,
    darwinBuildMemoryAddressReservationMib :: !Int,
    darwinBuildMemoryCompilerAccountMib :: !Int,
    darwinBuildMemoryControlAccountMib :: !Int,
    darwinBuildMemoryAccountMib :: !Int,
    darwinBuildMemoryInstalledCliIsolated :: !(Maybe DarwinInstalledCliIsolationEvidence),
    darwinBuildMemoryEvidenceIntervalMicros :: !Int,
    darwinBuildMemoryEvidenceTotalSamples :: !Word64,
    darwinBuildMemoryEvidencePeakBytes :: !Word64,
    darwinBuildMemoryEvidenceInvocations :: ![DarwinBuildMemoryInvocationEvidence]
  }
  deriving (Eq, Show)

mkDarwinBuildMemoryEvidence ::
  Integer ->
  Integer ->
  Integer ->
  DarwinBuildMemoryValidationAuthority s ->
  Int ->
  [DarwinBuildMemoryInvocationEvidence] ->
  Maybe DarwinInstalledCliIsolationEvidence ->
  Either String DarwinBuildMemoryEvidence
mkDarwinBuildMemoryEvidence
  physicalMib
  effectiveMib
  activeColimaPledgeMib
  (DarwinBuildMemoryValidationAuthority authority accountMib)
  intervalMicros
  invocationEvidence
  installedCliIsolation = do
    if physicalMib <= 0
      then Left "Darwin build-memory evidence requires positive physical memory"
      else Right ()
    if effectiveMib <= 0 || effectiveMib > physicalMib
      then Left "Darwin build-memory evidence requires positive effective memory no larger than physical memory"
      else Right ()
    if activeColimaPledgeMib < 0 || effectiveMib + activeColimaPledgeMib /= physicalMib
      then Left "Darwin build-memory evidence carries an inconsistent active Colima pledge"
      else Right ()
    if intervalMicros <= 0
      then Left "Darwin build-memory evidence requires a positive sampling interval"
      else Right ()
    if validInvocationSequence invocationEvidence
      then Right ()
      else Left "Darwin build-memory evidence carries an invalid invocation sequence"
    if installedCliIsolationMatches invocationEvidence installedCliIsolation
      then Right ()
      else Left "a successful Darwin install requires the closed installed-CLI GHCRTS isolation proof"
    totalSamples <- checkedTotalSamples invocationEvidence
    if totalSamples == 0
      then Left "Darwin build-memory evidence contains no physical-footprint samples"
      else Right ()
    let sampledPeakBytes =
          maximum (map darwinBuildMemoryEvidenceSampledPeakBytes invocationEvidence)
    if sampledPeakBytes == 0
      then Left "Darwin build-memory evidence requires a positive sampled aggregate physical footprint"
      else Right ()
    -- The multiple this evidence renders is a claim that the account bounded
    -- what the build actually took, so it is a checked quantity rather than a
    -- rendered one. A report whose sampled peak reaches or exceeds the account
    -- is not constructible: the command fails and names both figures instead
    -- of printing a ratio at or below 1.00x and exiting zero, which is exactly
    -- the shape that would let an over-account build be filed as proof the
    -- account held.
    if toInteger sampledPeakBytes >= toInteger accountMib * bytesPerMib
      then
        Left
          ( "Darwin build-memory evidence refuses a sampled aggregate physical "
              <> "footprint of "
              <> show sampledPeakBytes
              <> " bytes at or above its "
              <> show accountMib
              <> " MiB claimant account"
          )
      else Right ()
    let plan = toolchainSpawnAuthorityPlan authority
    Right
      DarwinBuildMemoryEvidence
        { darwinBuildMemoryPhysicalMib = physicalMib,
          darwinBuildMemoryEffectiveMib = effectiveMib,
          darwinBuildMemoryActiveColimaPledgeMib = activeColimaPledgeMib,
          darwinBuildMemoryBudgetMib = planBudgetMib plan,
          darwinBuildMemoryJobs = planJobs plan,
          darwinBuildMemoryHeapMib = planRtsHeapMib plan,
          darwinBuildMemoryControlHeapMib = planControlHeapMib plan,
          darwinBuildMemoryAddressReservationMib = planProcessAddressMib plan,
          darwinBuildMemoryCompilerAccountMib = planCompilerHeapAccountMib plan,
          darwinBuildMemoryControlAccountMib = planControlAccountMib plan,
          darwinBuildMemoryAccountMib = accountMib,
          darwinBuildMemoryInstalledCliIsolated = installedCliIsolation,
          darwinBuildMemoryEvidenceIntervalMicros = intervalMicros,
          darwinBuildMemoryEvidenceTotalSamples = totalSamples,
          darwinBuildMemoryEvidencePeakBytes = sampledPeakBytes,
          darwinBuildMemoryEvidenceInvocations = invocationEvidence
        }
    where
      validInvocationSequence evidence =
        map darwinBuildMemoryEvidenceInvocation evidence
          `elem` [ [DarwinBuildAllWithTests],
                   [DarwinBuildAllWithTests, DarwinInstallAllExecutables]
                 ]
      installedCliIsolationMatches evidence isolation =
        case reverse evidence of
          latest : _
            | darwinBuildMemoryEvidenceInvocation latest == DarwinInstallAllExecutables
                && darwinBuildMemoryEvidenceExitStatus latest == 0 ->
                case isolation of
                  Just _ -> True
                  Nothing -> False
          _ -> isNothing isolation
      checkedTotalSamples = foldl addSamples (Right 0)
      addSamples accumulated evidence = do
        current <- accumulated
        let next = darwinBuildMemoryEvidenceSampleCount evidence
        if maxBound - current < next
          then Left "Darwin build-memory evidence total sample count overflowed Word64"
          else Right (current + next)

-- | Stable, line-oriented report for operator evidence capture.
renderDarwinBuildMemoryEvidence :: DarwinBuildMemoryEvidence -> String
renderDarwinBuildMemoryEvidence evidence =
  unlines
    ( [ "darwinBuildMemoryEvidence: v1",
        "physicalMemoryMib: " <> show (darwinBuildMemoryPhysicalMib evidence),
        "effectiveMemoryMib: " <> show (darwinBuildMemoryEffectiveMib evidence),
        "activeColimaPledgeMib: " <> show (darwinBuildMemoryActiveColimaPledgeMib evidence),
        "planBudgetMib: " <> show (darwinBuildMemoryBudgetMib evidence),
        "planJobs: " <> show (darwinBuildMemoryJobs evidence),
        "planCompilerRtsHeapMib: " <> show (darwinBuildMemoryHeapMib evidence),
        "planControlHeapMib: " <> show (darwinBuildMemoryControlHeapMib evidence),
        "planProcessAddressReservationMib: " <> show (darwinBuildMemoryAddressReservationMib evidence),
        "planCompilerJobsTimesHeapMib: " <> show (darwinBuildMemoryCompilerAccountMib evidence),
        "planControlClaimCount: " <> show (darwinBuildMemoryJobs evidence + 1),
        "planControlAccountMib: " <> show (darwinBuildMemoryControlAccountMib evidence),
        "planAccountMib: " <> show (darwinBuildMemoryAccountMib evidence),
        "installedRuntimeCliInheritedGhcrts: "
          <> case darwinBuildMemoryInstalledCliIsolated evidence of
            Just _ -> "ignored (proved with adversarial invalid GHCRTS)"
            Nothing -> "not-run (build or install did not complete successfully)",
        "excludedHostReserveClaimants: operator CLI parent and fixed observer tools (outside the toolchain account and sampled Cabal process group)",
        "sampleMetric: sampled peak aggregate physical footprint",
        "sampleIntervalMicros: " <> show (darwinBuildMemoryEvidenceIntervalMicros evidence),
        "sampleCount: " <> show (darwinBuildMemoryEvidenceTotalSamples evidence),
        "sampledPeakAggregatePhysicalFootprintBytes: " <> show (darwinBuildMemoryEvidencePeakBytes evidence),
        "planAccountToSampledPeakMultiple: " <> renderAccountToSampledPeakMultiple evidence
      ]
        <> concatMap renderInvocation (zip [(1 :: Int) ..] (darwinBuildMemoryEvidenceInvocations evidence))
        <> [ "darwinCaveat: Darwin provides no enforced aggregate or address-space ceiling for this lane; fixed-interval samples can miss a transient peak and do not bound processes outside the measured Cabal process group."
           ]
    )
  where
    renderInvocation (index, invocationEvidence) =
      let prefix = "invocation." <> show index <> "."
       in [ prefix <> "name: " <> darwinBuildMemoryInvocationLabel (darwinBuildMemoryEvidenceInvocation invocationEvidence),
            prefix <> "exitStatus: " <> show (darwinBuildMemoryEvidenceExitStatus invocationEvidence),
            prefix <> "durationMicros: " <> show (darwinBuildMemoryEvidenceDurationMicros invocationEvidence),
            prefix <> "samplingOutcome: " <> renderInvocationSamplingOutcome invocationEvidence,
            prefix <> "sampleCount: " <> show (darwinBuildMemoryEvidenceSampleCount invocationEvidence),
            prefix <> "sampledPeakAggregatePhysicalFootprintBytes: " <> show (darwinBuildMemoryEvidenceSampledPeakBytes invocationEvidence)
          ]

    renderInvocationSamplingOutcome invocationEvidence
      | darwinBuildMemoryEvidenceSampleCount invocationEvidence == 0 =
          "terminal-before-first-fixed-cadence-probe"
      | otherwise = "sampled"

-- Integer hundredths keep the evidence deterministic and avoid both floating
-- formatting drift and fixed-width multiplication overflow. The smart
-- constructor has already proved the sampled peak is positive.
renderAccountToSampledPeakMultiple :: DarwinBuildMemoryEvidence -> String
renderAccountToSampledPeakMultiple evidence =
  show whole <> "." <> paddedHundredths <> "x"
  where
    accountBytes =
      toInteger (darwinBuildMemoryAccountMib evidence) * 1024 * 1024
    peakBytes = toInteger (darwinBuildMemoryEvidencePeakBytes evidence)
    fixedHundredths = accountBytes * 100 `div` peakBytes
    (whole, hundredths) = fixedHundredths `divMod` 100
    paddedHundredths
      | hundredths < 10 = "0" <> show hundredths
      | otherwise = show hundredths

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
      "per-process address-space rlimit and runtime heap caps; the aggregate is compiler plus control/helper claimant arithmetic"
    DarwinHeapCapMechanism ->
      "runtime heap caps and bounded concurrency; the aggregate is compiler plus control/helper claimant arithmetic"

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
-- Every claimant appears in the banner because no per-process cap is meaningful
-- alone; the complete compiler-phase account is spelled out rather than left
-- to the reader.
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
      "-- with "
        <> show (planJobs plan)
        <> " compiler jobs at a "
        <> show (planRtsHeapMib plan)
        <> " MiB runtime heap cap and a",
      "-- "
        <> show (planProcessAddressMib plan)
        <> " MiB compiler address-space reservation. Cabal and each",
      "-- worker-associated control/helper slot carry a separate "
        <> show (planControlHeapMib plan)
        <> " MiB heap cap.",
      "--",
      "-- A per-process cap is not a host bound on its own. The compiler subtotal is",
      "-- "
        <> show (planJobs plan)
        <> " jobs x "
        <> show (planRtsHeapMib plan)
        <> " MiB = "
        <> show (planCompilerHeapAccountMib plan)
        <> " MiB; the control/helper subtotal is",
      "-- "
        <> show (planJobs plan + 1)
        <> " claims x "
        <> show (planControlHeapMib plan)
        <> " MiB = "
        <> show (planControlAccountMib plan)
        <> " MiB.",
      "-- = "
        <> show (planToolchainAccountMib plan)
        <> " MiB total inside the "
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
