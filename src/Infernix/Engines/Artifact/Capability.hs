{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RoleAnnotations #-}

-- | Constructor-bearing representation shared only by the exact artifact
-- validator and its program interpreter. This module is Cabal-hidden.
module Infernix.Engines.Artifact.Capability
  ( ValidatedEngineArtifact (..),
    ArtifactPhase (..),
    ArtifactOutputStream (..),
    ArtifactProcessOutcome (..),
    ArtifactTerminalOutcome (..),
    Session (..),
    Program (..),
    reapArtifact,
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Infernix.Engines.MaterializationLock
  ( ArtifactGenerationLease,
  )
import System.Exit (ExitCode)
import System.Posix.Files (FileStatus)

data ValidatedEngineArtifact s = ValidatedEngineArtifact
  { validatedArtifactInstallRoot :: !FilePath,
    validatedArtifactEntrypoint :: !FilePath,
    validatedArtifactManifestFingerprint :: !Text,
    validatedArtifactGenerationLease :: !ArtifactGenerationLease,
    validatedArtifactRootStatus :: !FileStatus,
    validatedArtifactManifestStatus :: !FileStatus,
    validatedArtifactEntrypointStatus :: !FileStatus
  }

type role ValidatedEngineArtifact nominal

-- | The only public phase transition consumes a freshly validated artifact
-- and produces a terminal program. There is deliberately no running phase
-- value that can escape through unrestricted 'IO'.
data ArtifactPhase
  = ArtifactReady
  | ArtifactReaped

data ArtifactOutputStream
  = ArtifactStandardOutput
  | ArtifactStandardError
  deriving (Eq, Show)

-- | First-order process classification carried out of the shared-lock
-- interpreter. It deliberately cannot contain a closure, 'IO' action, or
-- validated artifact capability.
data ArtifactProcessOutcome
  = ArtifactProcessExited !ExitCode
  | ArtifactProcessExceededCeiling !Int
  | ArtifactProcessEnforcementUnavailable !Text
  | ArtifactProcessOutputLimitExceeded !ArtifactOutputStream
  | ArtifactProcessOutputCaptureFailed !ArtifactOutputStream !Text
  deriving (Eq, Show)

-- | The fixed terminal result of every artifact program. Keeping the result
-- closed prevents a callback from smuggling a capability out inside a nested
-- function or 'IO' action.
data ArtifactTerminalOutcome
  = ArtifactTerminalCompleted
  | ArtifactTerminalRejected
  | ArtifactTerminalProcess
      !ArtifactProcessOutcome
      !ExitCode
      !ByteString
      !ByteString
  deriving (Eq, Show)

-- | Opaque one-shot authority for one exact artifact use.
data Session s (phase :: ArtifactPhase) where
  ArtifactReadySession ::
    ValidatedEngineArtifact s ->
    Session s 'ArtifactReady

type role Session nominal nominal

-- | An inert terminal artifact program. 'Infernix.Engines.Artifact' is the
-- sole interpreter, so the enclosed launch-and-reap action cannot run after
-- the shared materialization lock has been released.
data Program s (phase :: ArtifactPhase) result where
  ArtifactReapedProgram ::
    IO ArtifactTerminalOutcome ->
    Program s 'ArtifactReaped ArtifactTerminalOutcome

type role Program nominal nominal nominal

-- | Spend the ready authority exactly once to describe launch through reap.
reapArtifact ::
  (ValidatedEngineArtifact s %1 -> IO ArtifactTerminalOutcome) ->
  Session s 'ArtifactReady %1 ->
  Program s 'ArtifactReaped ArtifactTerminalOutcome
reapArtifact transition (ArtifactReadySession validatedArtifact) =
  ArtifactReapedProgram (transition validatedArtifact)
