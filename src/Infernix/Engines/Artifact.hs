{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

-- | Public engine-artifact validation and runtime-use facade.
--
-- Raw reconciliation and activation are intentionally absent. Engine writers
-- enter through the indexed provisioning interpreter, which alone imports the
-- Cabal-hidden transaction implementation.
module Infernix.Engines.Artifact
  ( ResolvedArtifactProvenance (..),
    EngineArtifactManifest (..),
    engineArtifactManifestPath,
    engineArtifactPreviousRoot,
    engineArtifactTempRoot,
    renderEngineArtifactManifest,
    decodeEngineArtifactManifest,
    ArtifactSnapshotBoundary (..),
    maximumArtifactSnapshotEntries,
    maximumArtifactSnapshotBytes,
    maximumArtifactSnapshotDepth,
    validateArtifactSnapshotBounds,
    renderArtifactSnapshotRecord,
    digestEngineArtifactPayload,
    digestEngineArtifactPayloadWithObserver,
    validateEngineArtifactRootAt,
    ArtifactResolution (..),
    NativeArtifactIdentity,
    parseNativeArtifactIdentity,
    ArtifactRuntimeExpectation,
    appleArtifactRuntimeExpectation,
    linuxArtifactRuntimeExpectation,
    currentArtifactRecipeFingerprint,
    engineArtifactGenerationFingerprint,
    ArtifactPhase (..),
    ArtifactOutputStream (..),
    ArtifactProcessOutcome (..),
    ArtifactTerminalOutcome (..),
    Session,
    Program,
    reapArtifact,
    withFirstValidatedEngineArtifact,
    revalidateValidatedEngineArtifact,
  )
where

import Infernix.Engines.Artifact.Internal
