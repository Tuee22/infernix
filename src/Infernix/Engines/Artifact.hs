{-# LANGUAGE DataKinds #-}

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
    manifestFingerprint,
    validateArtifactGenerationPayloadLease,
    validateEngineArtifactHelperLease,
    ArtifactResolution (..),
    NativeArtifactIdentity,
    parseNativeArtifactIdentity,
    ArtifactRuntimeExpectation,
    appleArtifactRuntimeExpectation,
    linuxArtifactRuntimeExpectation,
    currentArtifactRecipeFingerprint,
    engineArtifactGenerationFingerprint,
    rederiveArtifactGenerationFingerprint,
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
    ArtifactPreLaunchFixture,
    noArtifactPreLaunchFixture,
    overwriteFileBeforeLaunch,
    withFirstValidatedEngineArtifact,
    withFirstValidatedEngineArtifactUnderPreLaunchFixture,
    revalidateValidatedEngineArtifact,
  )
where

import Infernix.Engines.Artifact.Internal
