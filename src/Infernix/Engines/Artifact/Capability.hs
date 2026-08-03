{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RoleAnnotations #-}

-- | Constructor-bearing representation shared only by the exact artifact
-- validator and its runner. This module is Cabal-hidden.
--
-- The phase sequence is owned by the runner, not by its caller. A caller
-- supplies only an unprivileged 'ArtifactLauncher' over the closed, first-order
-- 'ArtifactLaunchRequest'; it never receives a 'ValidatedEngineArtifact', an
-- 'ArtifactRun' phase value, or any next-phase continuation it could drop,
-- reuse, skip, or retain past the shared materialization lock. An earlier draft
-- expressed this with a linear @%1@ transition, which an ordinary @IO@ consumer
-- cannot honour without an unsafe multiplicity cast, so the guarantee is now
-- carried by hidden constructors plus runner-owned sequencing instead.
module Infernix.Engines.Artifact.Capability
  ( ValidatedEngineArtifact (..),
    ArtifactPhase (..),
    ArtifactOutputStream (..),
    ArtifactProcessOutcome (..),
    ArtifactTerminalOutcome (..),
    ArtifactLaunchRequest,
    artifactLaunchInstallRoot,
    artifactLaunchEntrypoint,
    artifactLaunchLeadingArguments,
    ArtifactLauncher,
    artifactLauncher,
    ArtifactRun,
    ArtifactPreLaunchFixture,
    noArtifactPreLaunchFixture,
    overwriteFileBeforeLaunch,
    readyArtifactRun,
    reapArtifactRun,
    artifactRunOutcome,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Infernix.Engines.MaterializationLock
  ( ArtifactGenerationLease,
    withTryArtifactGenerationReadLock,
  )
import System.Exit (ExitCode)
import System.Posix.Files (FileStatus)

data ValidatedEngineArtifact s = ValidatedEngineArtifact
  { validatedArtifactInstallRoot :: !FilePath,
    validatedArtifactEntrypoint :: !FilePath,
    -- | The closed catalog's leading argument vector for this exact target,
    -- resolved by the validator from the same catalog entry it validated the
    -- entrypoint against. It is what makes the target speak the native-runner
    -- protocol at all — for an installed Python-runner target it is the runner
    -- script plus its required @--adapter-id@/@--engine-name@ pair, and for the
    -- Linux JVM target it is @-cp \/opt\/audiveris\/lib\/app\/* Audiveris@.
    validatedArtifactLeadingArguments :: ![String],
    validatedArtifactManifestFingerprint :: !Text,
    validatedArtifactGenerationLease :: !ArtifactGenerationLease,
    validatedArtifactRootStatus :: !FileStatus,
    validatedArtifactManifestStatus :: !FileStatus,
    validatedArtifactEntrypointStatus :: !FileStatus
  }

type role ValidatedEngineArtifact nominal

-- | The runner-owned phase index. There is deliberately no running phase a
-- caller can observe, and no phase value is ever handed out.
data ArtifactPhase
  = ArtifactReady
  | ArtifactReaped

data ArtifactOutputStream
  = ArtifactStandardOutput
  | ArtifactStandardError
  deriving (Eq, Show)

-- | First-order process classification carried out of the shared-lock runner.
-- It deliberately cannot contain a closure, 'IO' action, or validated artifact
-- capability.
data ArtifactProcessOutcome
  = ArtifactProcessExited !ExitCode
  | ArtifactProcessExceededCeiling !Int
  | ArtifactProcessEnforcementUnavailable !Text
  | ArtifactProcessOutputLimitExceeded !ArtifactOutputStream
  | ArtifactProcessOutputCaptureFailed !ArtifactOutputStream !Text
  deriving (Eq, Show)

-- | The fixed terminal result of every artifact run. Keeping the result closed
-- prevents a launcher from smuggling a capability out inside a nested function
-- or 'IO' action.
data ArtifactTerminalOutcome
  = ArtifactTerminalCompleted
  | ArtifactTerminalRejected
  | ArtifactTerminalProcess
      !ArtifactProcessOutcome
      !ExitCode
      !ByteString
      !ByteString
  deriving (Eq, Show)

-- | The complete, closed description the runner hands to an unprivileged
-- launcher. It names only the sealed root and the entrypoint inside it, both
-- already revalidated by the runner under the shared lock.
data ArtifactLaunchRequest = ArtifactLaunchRequest
  { artifactLaunchInstallRoot :: !FilePath,
    artifactLaunchEntrypoint :: !FilePath,
    -- | The closed catalog's leading arguments for this target. A launcher must
    -- render them before its own invocation arguments; without them the direct
    -- target does not speak the native-runner protocol the invocation uses.
    artifactLaunchLeadingArguments :: ![String]
  }
  deriving (Eq, Show)

-- | An unprivileged launcher. It is handed no artifact capability, no phase
-- value, and no lock authority, so it cannot retain anything that outlives the
-- runner's shared-lock region.
newtype ArtifactLauncher
  = ArtifactLauncher
      (ArtifactLaunchRequest -> IO ArtifactTerminalOutcome)

artifactLauncher ::
  (ArtifactLaunchRequest -> IO ArtifactTerminalOutcome) ->
  ArtifactLauncher
artifactLauncher = ArtifactLauncher

-- | Opaque one-shot authority for one exact artifact use. Both constructors
-- are hidden, so only 'readyArtifactRun' mints a ready run and only
-- 'reapArtifactRun' produces a reaped one.
data ArtifactRun s (phase :: ArtifactPhase) where
  ArtifactReadyRun ::
    ValidatedEngineArtifact s ->
    ArtifactRun s 'ArtifactReady
  ArtifactReapedRun ::
    ArtifactTerminalOutcome ->
    ArtifactRun s 'ArtifactReaped

type role ArtifactRun nominal nominal

-- | Mint the ready phase from a freshly validated artifact.
readyArtifactRun ::
  ValidatedEngineArtifact s ->
  ArtifactRun s 'ArtifactReady
readyArtifactRun = ArtifactReadyRun

-- | Fixed, first-order pre-launch fixtures. A fixture carries only data, never
-- an effect, a continuation, or an authority, so a test can pin the exact
-- use-boundary window between minting the ready run and the runner's own
-- revalidation without gaining the ability to inject arbitrary 'IO' while the
-- shared lock is held.
data ArtifactPreLaunchFixture
  = NoArtifactPreLaunchFixture
  | OverwriteFileBeforeLaunch !FilePath !ByteString
  deriving (Eq, Show)

noArtifactPreLaunchFixture :: ArtifactPreLaunchFixture
noArtifactPreLaunchFixture = NoArtifactPreLaunchFixture

overwriteFileBeforeLaunch ::
  FilePath ->
  ByteString ->
  ArtifactPreLaunchFixture
overwriteFileBeforeLaunch = OverwriteFileBeforeLaunch

runArtifactPreLaunchFixture :: ArtifactPreLaunchFixture -> IO ()
runArtifactPreLaunchFixture fixture =
  case fixture of
    NoArtifactPreLaunchFixture -> pure ()
    OverwriteFileBeforeLaunch path contents ->
      ByteString.writeFile path contents

-- | The single transition out of the ready phase, and the only place a launch
-- request is derived.
--
-- The transition takes the exact generation's shared read lease itself, from
-- the lease the validator derived from that generation's own manifest, and
-- holds it across the launcher's whole execution. Generation identity therefore
-- authorizes shared execution by construction: there is no mint site for the
-- lease-held evidence and no path from a ready run to a launch request that
-- does not go through this acquisition. A 'Nothing' result means the generation
-- is being mutated by a writer and no launch was attempted; the read lease is
-- refused rather than waited on, so a stopped materializer cannot turn request
-- resolution into an unbounded wait.
--
-- The launcher still cannot reach the ready run, repeat the transition, or skip
-- the revalidation.
reapArtifactRun ::
  (ValidatedEngineArtifact s -> IO Bool) ->
  ArtifactPreLaunchFixture ->
  ArtifactLauncher ->
  ArtifactRun s 'ArtifactReady ->
  IO (Maybe (ArtifactRun s 'ArtifactReaped))
reapArtifactRun
  revalidate
  preLaunchFixture
  (ArtifactLauncher launch)
  (ArtifactReadyRun validatedArtifact) =
    withTryArtifactGenerationReadLock
      (validatedArtifactGenerationLease validatedArtifact)
      ( do
          runArtifactPreLaunchFixture preLaunchFixture
          stillExact <- revalidate validatedArtifact
          if not stillExact
            then pure (ArtifactReapedRun ArtifactTerminalRejected)
            else
              ArtifactReapedRun
                <$> launch
                  ( ArtifactLaunchRequest
                      { artifactLaunchInstallRoot =
                          validatedArtifactInstallRoot validatedArtifact,
                        artifactLaunchEntrypoint =
                          validatedArtifactEntrypoint validatedArtifact,
                        artifactLaunchLeadingArguments =
                          validatedArtifactLeadingArguments validatedArtifact
                      }
                  )
      )

-- | Read the closed terminal result of a reaped run.
artifactRunOutcome ::
  ArtifactRun s 'ArtifactReaped ->
  ArtifactTerminalOutcome
artifactRunOutcome (ArtifactReapedRun terminalOutcome) = terminalOutcome
