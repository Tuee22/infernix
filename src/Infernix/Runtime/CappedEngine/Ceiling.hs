{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 4 Sprint 4.41 — the ceiling an engine is launched under.
--
-- Detection observes a process that has already allocated; prevention refuses
-- the allocation. This module owns the second one on the lane that has a
-- mechanism for it, and it owns saying so honestly on the lane that does not.
--
-- The surface is deliberately narrow: there is no exported function taking an
-- executable, an argument vector, an environment, or a working directory, so
-- the surface a caller could misuse does not exist rather than being guarded.
-- What a caller supplies is an admitted quantity; what it receives is an opaque
-- installation whose strength is part of its value.
module Infernix.Runtime.CappedEngine.Ceiling
  ( CeilingStrength (..),
    CeilingRequirement (..),
    CeilingProvenance (..),
    EngineCeilingProjection (..),
    InstalledCeiling,
    ceilingEnforcementTool,
    installedCeilingArgumentPrefix,
    installedCeilingDerivedMib,
    installedCeilingMib,
    installedCeilingProvenance,
    installedCeilingResource,
    installedCeilingStrength,
    ceilingStrengthForLane,
    requireCeilingStrength,
    validateRuntimeCeilingReadiness,
    resolveEngineCeiling,
    projectionProbeCeiling,
    ceilingReadBackMatches,
  )
where

import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Types (Resource (HostRam, NvidiaVram, PodRam), RuntimeMode (AppleSilicon, LinuxCpu, LinuxGpu))

-- | What a lane's mechanism actually provides.
--
-- A lane declares the strength it has. An uncalibrated lane declares detection
-- only, and no kernel mechanism bounds device memory on any lane, so a contract
-- requiring prevention refuses readiness there rather than accepting the weaker
-- mechanism under the stronger word.
data CeilingStrength
  = -- | The residue is sampled after the engine allocates. This is what the
    -- Apple lane has by construction — Darwin has no cgroups, and its
    -- address-space limit is aliased to an advisory limit that rejects every
    -- finite ceiling, so there is nothing on that lane to install.
    CeilingDetectionOnly
  | -- | A kernel data-segment limit is installed before the engine's first
    -- instruction and cannot be raised back by the process it binds.
    CeilingInstalledDataSegment
  deriving (Eq, Show)

-- | The minimum strength a production lane contract accepts at readiness.
--
-- This is deliberately distinct from 'CeilingStrength': one is what the
-- contract requires and the other is what the calibrated mechanism provides.
-- Keeping both values means readiness compares two independently named facts
-- instead of treating the resolver's declaration as its own proof.
data CeilingRequirement
  = CeilingDetectionPermitted
  | CeilingPreventionRequired
  deriving (Eq, Show)

-- | Whether a real engine on a host lane has demonstrated a clean allocation
-- refusal under the installed mechanism.
--
-- Constructors stay private. Calibration is a cohort property of the pinned
-- lane implementation, not a caller-supplied runtime option: @linux-cpu@ has
-- the real llama.cpp observation, while @linux-gpu@ remains pending until its
-- own selected accelerator cohort runs. Apple and device resources never reach
-- this declaration because they have no installable mechanism.
data HostCeilingCalibration
  = HostCeilingCalibrationPending
  | HostCeilingCalibrationObserved
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.43 — what an engine projects it needs, or that its family
-- offers no projection at all.
--
-- The two arms are not the same statement and the type keeps them apart. An
-- engine that was asked and answered contributes a quantity; an engine family
-- whose upstream ships no projection tool contributes nothing, and the ceiling
-- it receives is the artifact-derived quantity with its provenance saying so. A
-- probe that was asked and /failed/ is neither: it never reaches this type,
-- because a failed projection is a typed refusal at the call site rather than an
-- absent quantity here.
data EngineCeilingProjection
  = NoEngineProjection
  | EngineProjectedMib !Int
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.43 — which quantities produced the installed value.
--
-- A ceiling derived from artifact-plus-projection is not the same value as one
-- derived from the artifact alone, so the per-lane strength table can state the
-- difference rather than implying a single provenance. The projected quantity is
-- retained beside the installed one because the margin between the two is the
-- evidence a later calibration reads; discarding it would leave the difference
-- recoverable only by re-running.
data CeilingProvenance
  = CeilingFromArtifact
  | CeilingFromArtifactAndProjection !Int
  deriving (Eq, Show)

-- | An installation. Its constructor is hidden; 'resolveEngineCeiling' is the
-- only mint, and the spawn kernel is the only consumer of its argument prefix.
data InstalledCeiling = InstalledCeiling
  { installedCeilingStrength :: CeilingStrength,
    installedCeilingResource :: Resource,
    -- | The quantity actually installed: the greater of the artifact-derived
    -- requirement and the engine's own projection.
    installedCeilingMib :: Int,
    -- | The artifact-derived requirement alone, retained beside the installed
    -- quantity so the two are never confused for one another.
    installedCeilingDerivedMib :: Int,
    installedCeilingProvenance :: CeilingProvenance,
    -- | The launch prefix, empty on a detection-only lane.
    installedCeilingArgumentPrefix :: [String]
  }
  deriving (Eq, Show)

-- | The enforcement tool, written as an absolute constant.
--
-- It is not a @toolPaths@ field. A manifest field is operator-editable by
-- design, and an enforcement path that the configuration of the thing being
-- bounded can repoint is not an enforcement path. This is the same argument that
-- pins the device observer's @\/usr\/bin\/nvidia-smi@ and the Apple footprint
-- observer's @\/usr\/bin\/top@ and @\/usr\/bin\/footprint@. The read-only-probe
-- carve-out that covers @ps@ and @vm_stat@ deliberately does not transfer:
-- @prlimit@ is not read-only, it installs kernel state and then becomes the
-- engine.
ceilingEnforcementTool :: FilePath
ceilingEnforcementTool = "/usr/bin/prlimit"

-- | Resolve the ceiling for one lane, one admitted quantity, and whatever the
-- engine itself projected.
--
-- The Apple arm is a /total/ function returning the detection-only value — not
-- an unimplemented case, not a silent fall-through to the Linux path, and not a
-- claim of prevention that the mechanism does not provide.
--
-- The device arm is detection-only for a different reason, and the two are kept
-- distinct: a host column reads detection because the calibration observation
-- has not been made yet, while the device column reads it because there is no
-- mechanism to calibrate. Collapsing them would let an absent mechanism be
-- mistaken for a pending measurement.
resolveEngineCeiling ::
  RuntimeMode ->
  Resource ->
  Int ->
  EngineCeilingProjection ->
  InstalledCeiling
resolveEngineCeiling runtimeModeValue resource derivedMib projection =
  case ceilingStrengthForLane runtimeModeValue resource of
    CeilingDetectionOnly -> detectionOnly
    CeilingInstalledDataSegment -> installedDataSegment
  where
    -- Phase 4 Sprint 4.43 — the greater of the two quantities, never a
    -- replacement of one by the other. The derivation stays authoritative
    -- wherever it is larger, so an engine that under-reports cannot widen its
    -- own bound below what its weights and cache provably need.
    (installedMib, provenance) =
      case projection of
        NoEngineProjection -> (derivedMib, CeilingFromArtifact)
        EngineProjectedMib projectedMib ->
          ( max derivedMib projectedMib,
            CeilingFromArtifactAndProjection projectedMib
          )
    detectionOnly =
      InstalledCeiling
        { installedCeilingStrength = CeilingDetectionOnly,
          installedCeilingResource = resource,
          installedCeilingMib = installedMib,
          installedCeilingDerivedMib = derivedMib,
          installedCeilingProvenance = provenance,
          installedCeilingArgumentPrefix = []
        }
    installedDataSegment =
      InstalledCeiling
        { installedCeilingStrength = CeilingInstalledDataSegment,
          installedCeilingResource = resource,
          installedCeilingMib = installedMib,
          installedCeilingDerivedMib = derivedMib,
          installedCeilingProvenance = provenance,
          installedCeilingArgumentPrefix = dataSegmentPrefix installedMib
        }

-- | The strength the selected lane has earned for one resource.
--
-- Linux CPU prevention is backed by a real pinned llama.cpp run that
-- initialized the backend and model under the data-segment ceiling and then
-- refused an over-budget compute-buffer allocation with an ordinary non-zero
-- exit. Linux GPU remains detection-only until the corresponding CUDA cohort
-- produces its own observation. Device memory and Apple unified memory have no
-- installable mechanism and therefore cannot be promoted by calibration.
ceilingStrengthForLane :: RuntimeMode -> Resource -> CeilingStrength
ceilingStrengthForLane runtimeModeValue resource =
  case (runtimeModeValue, resource) of
    (AppleSilicon, _) -> CeilingDetectionOnly
    (_, NvidiaVram) -> CeilingDetectionOnly
    (LinuxCpu, PodRam) -> strengthFromCalibration HostCeilingCalibrationObserved
    (LinuxGpu, PodRam) -> strengthFromCalibration HostCeilingCalibrationPending
    _ -> CeilingDetectionOnly
  where
    strengthFromCalibration calibration =
      case calibration of
        HostCeilingCalibrationPending -> CeilingDetectionOnly
        HostCeilingCalibrationObserved -> CeilingInstalledDataSegment

-- | Refuse a required prevention contract when the lane declares only
-- detection. Detection-permitted contracts accept either strength.
requireCeilingStrength :: CeilingRequirement -> CeilingStrength -> Either Text ()
requireCeilingStrength requirement provided =
  case (requirement, provided) of
    (CeilingDetectionPermitted, _) -> Right ()
    (CeilingPreventionRequired, CeilingInstalledDataSegment) -> Right ()
    (CeilingPreventionRequired, CeilingDetectionOnly) ->
      Left "the runtime contract requires prevention but this lane declares detection only"

-- | Production readiness check for every physical resource the runtime mode
-- can execute against.
--
-- The Linux CPU contract requires its calibrated host mechanism. The Apple
-- contract permits its honest detection-only host mechanism. Linux GPU stays
-- detection-permitted until Phase 6's CUDA calibration promotes that lane; its
-- device resource is permanently detection-only because no kernel mechanism
-- bounds device memory on any supported lane.
validateRuntimeCeilingReadiness :: RuntimeMode -> Either Text ()
validateRuntimeCeilingReadiness runtimeModeValue =
  traverse_ validateResource (runtimeResources runtimeModeValue)
  where
    validateResource resource =
      requireCeilingStrength
        (requiredStrength runtimeModeValue resource)
        (ceilingStrengthForLane runtimeModeValue resource)

    runtimeResources mode =
      case mode of
        AppleSilicon -> [HostRam]
        LinuxCpu -> [PodRam]
        LinuxGpu -> [PodRam, NvidiaVram]

    requiredStrength mode resource =
      case (mode, resource) of
        (LinuxCpu, PodRam) -> CeilingPreventionRequired
        _ -> CeilingDetectionPermitted

-- | @\/usr\/bin\/prlimit --data=\<soft>:\<hard> --@.
--
-- Both the soft and the hard limit are lowered, because lowering only the soft
-- limit produces a ceiling the bound process can raise back to its hard limit
-- whenever it likes, which is advice rather than enforcement. Lowering the hard
-- limit is one-way and inherited, which is why it happens in a process image
-- dedicated to a single execution rather than in the long-lived daemon: a daemon
-- that lowered its own would bind every later inference, every observer child,
-- and itself, permanently, from the first model that needed the smallest
-- ceiling.
--
-- @prlimit@ replaces itself with the engine rather than forking, so it leaves no
-- live process: the engine keeps its own process identity, its own group, and
-- its own exit status, and the sampling kernel's group walk and the worker's
-- exit classification are unchanged.
dataSegmentPrefix :: Int -> [String]
dataSegmentPrefix ceilingMib =
  [ ceilingEnforcementTool,
    "--data=" <> show ceilingBytes <> ":" <> show ceilingBytes,
    "--"
  ]
  where
    ceilingBytes = toInteger ceilingMib * 1024 * 1024

-- | Phase 4 Sprint 4.43 — the launch a projection probe runs under.
--
-- It installs nothing, and that is a decision rather than an omission. The probe
-- exists to correct a derived quantity that may be too tight for the execution
-- that runs; bounding the probe by that same quantity would turn a model that
-- would have run into a refusal, which is the defect the projection removes
-- arriving one layer earlier. Measured against the pinned llama.cpp payload, the
-- upstream projection tool needs roughly 48 MiB of private writable memory
-- whatever model it is asked about, and a device-streaming placement's derived
-- host term is the largest single tensor — 52 MiB for the row that produced this
-- sprint, and smaller for a smaller model.
--
-- What bounds the probe instead is what bounds every other process in the pod:
-- the lane's own outer envelope, a kernel limit this code neither installed nor
-- can raise. Its standard streams are bounded by the engine output capture, its
-- argument vector is a closed per-family specification, and its executable is a
-- sibling of the validated entry object inside the same sealed closure. The
-- derived quantity is carried on the value so a reader can see what the plan
-- would have installed; the strength says that nothing was.
projectionProbeCeiling :: Resource -> Int -> InstalledCeiling
projectionProbeCeiling resource derivedMib =
  InstalledCeiling
    { installedCeilingStrength = CeilingDetectionOnly,
      installedCeilingResource = resource,
      installedCeilingMib = derivedMib,
      installedCeilingDerivedMib = derivedMib,
      installedCeilingProvenance = CeilingFromArtifact,
      installedCeilingArgumentPrefix = []
    }

-- | Compare a read-back against the quantity the plan installed.
--
-- A limit that was set and a limit the running image fits under are different
-- claims, and only the second is evidence that this execution is bounded.
-- Nothing else in the pipeline can produce it, because nothing else is the
-- process the limit binds. A mismatch is a typed terminal failure and never a
-- retryable transient: a conformance failure laundered into a redelivery is an
-- unbounded launch repeated.
ceilingReadBackMatches :: InstalledCeiling -> Integer -> Integer -> Either Text ()
ceilingReadBackMatches installed reportedSoft reportedHard =
  case installedCeilingStrength installed of
    CeilingDetectionOnly -> Right ()
    CeilingInstalledDataSegment
      | reportedSoft == expectedBytes && reportedHard == expectedBytes -> Right ()
      | otherwise ->
          Left
            ( "the engine reported a data-segment limit of "
                <> Text.pack (show reportedSoft)
                <> ":"
                <> Text.pack (show reportedHard)
                <> " bytes against the "
                <> Text.pack (show expectedBytes)
                <> " bytes its plan installed"
            )
  where
    expectedBytes = toInteger (installedCeilingMib installed) * 1024 * 1024
