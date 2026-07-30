{-# LANGUAGE TypeApplications #-}

-- | Cabal-hidden interpreter that combines the artifact transaction with the
-- closed bounded-smoke language. Raw activation authority and raw process
-- specifications remain outside this module's export surface.
module Infernix.Engines.Artifact.Activation
  ( activateAppleEngineArtifactWithInstalledSmoke,
    activateLinuxEngineArtifactWithInstalledSmoke,
  )
where

import Control.Exception
  ( SomeException,
    mask,
    throwIO,
    try,
  )
import Control.Monad (unless)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    nativeArtifactAdapterId,
  )
import Infernix.Engines.Artifact.Internal qualified as Artifact
import Infernix.Engines.Artifact.Target (NativeArtifactTargetEvidence)
import Infernix.Engines.MaterializationLock.Internal
  ( ArtifactGenerationLease,
    MaterializationAuthority,
    artifactGenerationLease,
    artifactGenerationLeaseFields,
    reconcileObsoleteArtifactGenerationLeases,
    retireArtifactGenerationLease,
    withTryArtifactGenerationMutationLock,
  )
import Infernix.Engines.Provisioning.Internal qualified as Provisioning
import Infernix.Error (finallyPreservingPrimary)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (normalise, takeDirectory)

activateAppleEngineArtifactWithInstalledSmoke ::
  MaterializationAuthority w ->
  Artifact.ArtifactRootMutator w ->
  Subprocess.AbandonedActivitiesRecovered ->
  ArtifactGenerationLease ->
  Subprocess.SubprocessEnv ->
  Provisioning.PositiveProvisioningTimeout ->
  Provisioning.AppleAdapterId ->
  FilePath ->
  FilePath ->
  Text ->
  IO (Either String Subprocess.NativeArtifactCommandOutcome)
activateAppleEngineArtifactWithInstalledSmoke
  authority
  mutator
  recovered
  generationLease
  environment
  smokeTimeout
  adapter
  installRoot
  tempRoot
  expectedDigest = do
    identity <-
      either
        (ioError . userError)
        pure
        (Provisioning.nativeArtifactIdentity adapter)
    activateEngineArtifactWithInstalledSmoke
      authority
      mutator
      recovered
      generationLease
      identity
      installRoot
      tempRoot
      expectedDigest
      ( Subprocess.runClosedInstalledRunnerSmoke
          adapter
          generationLease
      )
      environment
      smokeTimeout

activateLinuxEngineArtifactWithInstalledSmoke ::
  MaterializationAuthority w ->
  Artifact.ArtifactRootMutator w ->
  Subprocess.AbandonedActivitiesRecovered ->
  ArtifactGenerationLease ->
  Subprocess.SubprocessEnv ->
  Provisioning.PositiveProvisioningTimeout ->
  NativeArtifactIdentity ->
  Provisioning.LinuxNativeSmokePolicy ->
  NativeArtifactTargetEvidence ->
  FilePath ->
  FilePath ->
  Text ->
  IO (Either String Subprocess.NativeArtifactCommandOutcome)
activateLinuxEngineArtifactWithInstalledSmoke
  authority
  mutator
  recovered
  generationLease
  environment
  smokeTimeout
  identity
  smokePolicy
  expectedTargetEvidence
  installRoot
  tempRoot
  expectedDigest =
    activateEngineArtifactWithInstalledSmoke
      authority
      mutator
      recovered
      generationLease
      identity
      installRoot
      tempRoot
      expectedDigest
      ( \retainedRoot activeEnvironment timeout ->
          Subprocess.runClosedLinuxNativeArtifactSmoke
            identity
            generationLease
            retainedRoot
            expectedTargetEvidence
            smokePolicy
            activeEnvironment
            timeout
      )
      environment
      smokeTimeout

activateEngineArtifactWithInstalledSmoke ::
  MaterializationAuthority w ->
  Artifact.ArtifactRootMutator w ->
  Subprocess.AbandonedActivitiesRecovered ->
  ArtifactGenerationLease ->
  NativeArtifactIdentity ->
  FilePath ->
  FilePath ->
  Text ->
  ( Subprocess.ProvisioningMutationRoot ->
    Subprocess.SubprocessEnv ->
    Subprocess.Timeout ->
    IO (Either String Subprocess.NativeArtifactCommandOutcome)
  ) ->
  Subprocess.SubprocessEnv ->
  Provisioning.PositiveProvisioningTimeout ->
  IO (Either String Subprocess.NativeArtifactCommandOutcome)
activateEngineArtifactWithInstalledSmoke
  authority
  mutator
  recovered
  generationLease
  identity
  installRoot
  tempRoot
  expectedDigest
  runSmoke
  environment
  smokeTimeout =
    mask $ \restore -> do
      recovered `seq` validateCurrentGenerationLease
      pendingResult <-
        withTryArtifactGenerationMutationLock
          authority
          generationLease
          ( \generationAuthority -> do
              candidateManifest <-
                Artifact.validateEngineArtifactRootAt installRoot tempRoot
              let (_, _, leaseFingerprint, leasePayloadDigest) =
                    artifactGenerationLeaseFields generationLease
              unless
                ( Artifact.manifestGenerationFingerprint candidateManifest
                    == leaseFingerprint
                    && Artifact.manifestDigest candidateManifest
                      == leasePayloadDigest
                )
                ( ioError
                    ( userError
                        "candidate manifest disagrees with its exact generation lease"
                    )
                )
              Artifact.beginEngineArtifactActivationUnderGeneration
                authority
                generationAuthority
                mutator
                installRoot
                tempRoot
                expectedDigest
          )
      case pendingResult of
        Nothing ->
          pure
            (Left "artifact generation is in use before final-path activation")
        Just pending -> do
          smokeResult <-
            try @SomeException
              ( restore $ do
                  retainedRoot <-
                    observeFinalArtifactRoot installRoot
                  runSmoke
                    retainedRoot
                    environment
                    (provisioningSubprocessTimeout smokeTimeout)
              )
          case smokeResult of
            Left failure ->
              finallyPreservingPrimary
                (throwIO failure)
                (rollbackPendingActivation authority generationLease pending)
            Right outcome
              | installedSmokeSucceeded outcome -> do
                  committedResult <-
                    withTryArtifactGenerationMutationLock
                      authority
                      generationLease
                      ( \generationAuthority -> do
                          revalidation <-
                            try @SomeException
                              ( revalidatePendingActivation
                                  identity
                                  expectedDigest
                                  installRoot
                                  pending
                              )
                          case revalidation of
                            Left failure ->
                              finallyPreservingPrimary
                                (throwIO failure)
                                ( Artifact.rollbackEngineArtifactActivationUnderGeneration
                                    generationAuthority
                                    pending
                                )
                            Right () ->
                              Artifact.commitEngineArtifactActivationUnderGeneration
                                generationAuthority
                                pending
                      )
                  case committedResult of
                    Nothing ->
                      pure
                        ( Left
                            "artifact generation became busy before final-path commit; recoverable sibling state was retained"
                        )
                    Just committed -> do
                      retired <-
                        retirePriorGeneration
                          authority
                          generationLease
                          identity
                          installRoot
                          committed
                      reconcileObsoleteArtifactGenerationLeases
                        authority
                        [generationLease]
                      pure (retired >> outcome)
              | otherwise -> do
                  rollbackResult <-
                    try @SomeException
                      (rollbackPendingActivation authority generationLease pending)
                  case rollbackResult of
                    Left failure -> throwIO failure
                    Right () ->
                      pure (rejectEmptySmokeOutput outcome)
    where
      validateCurrentGenerationLease =
        let (enginesRoot, leaseAdapter, _leaseFingerprint, leasePayloadDigest) =
              artifactGenerationLeaseFields generationLease
         in unless
              ( normalise enginesRoot == normalise (takeDirectory installRoot)
                  && leaseAdapter == nativeArtifactAdapterId identity
                  && leasePayloadDigest == expectedDigest
              )
              ( ioError
                  ( userError
                      "artifact activation generation lease disagrees with its exact root, adapter, or payload digest"
                  )
              )

observeFinalArtifactRoot ::
  FilePath ->
  IO Subprocess.ProvisioningMutationRoot
observeFinalArtifactRoot installRoot = do
  observed <-
    Subprocess.observeProvisioningMutationRoot installRoot
  case observed of
    Left failure ->
      ioError
        ( userError
            ( "observe retained final artifact root: "
                <> show failure
            )
        )
    Right retainedRoot -> pure retainedRoot

installedSmokeSucceeded ::
  Either String Subprocess.NativeArtifactCommandOutcome ->
  Bool
installedSmokeSucceeded outcome =
  case outcome of
    Right
      ( Subprocess.NativeArtifactCommandExited
          ExitSuccess
          output
          _
        ) ->
        not (ByteString.null output)
    _ -> False

rollbackPendingActivation ::
  MaterializationAuthority w ->
  ArtifactGenerationLease ->
  Artifact.PendingArtifactActivation w ->
  IO ()
rollbackPendingActivation authority generationLease pending = do
  rollbackResult <-
    withTryArtifactGenerationMutationLock
      authority
      generationLease
      (`Artifact.rollbackEngineArtifactActivationUnderGeneration` pending)
  case rollbackResult of
    Just () -> pure ()
    Nothing ->
      ioError
        ( userError
            "artifact generation remained busy during rollback; recoverable sibling state was retained"
        )

revalidatePendingActivation ::
  NativeArtifactIdentity ->
  Text ->
  FilePath ->
  Artifact.PendingArtifactActivation w ->
  IO ()
revalidatePendingActivation identity expectedDigest installRoot pending = do
  observedManifest <-
    Artifact.validateEngineArtifactRootAt installRoot installRoot
  observedDigest <-
    Artifact.digestEngineArtifactPayload installRoot
  let pendingManifest =
        Artifact.pendingArtifactActivationManifest pending
      expectedAdapter =
        nativeArtifactAdapterId identity
  unless
    ( observedManifest == pendingManifest
        && Artifact.manifestAdapterId observedManifest == expectedAdapter
        && Artifact.manifestDigest observedManifest == expectedDigest
        && observedDigest == expectedDigest
    )
    ( ioError
        ( userError
            "activated artifact changed before exclusive generation revalidation"
        )
    )

retirePriorGeneration ::
  MaterializationAuthority w ->
  ArtifactGenerationLease ->
  NativeArtifactIdentity ->
  FilePath ->
  Artifact.CommittedArtifactActivation w ->
  IO (Either String ())
retirePriorGeneration
  authority
  currentLease
  identity
  installRoot
  committed =
    case Artifact.committedArtifactActivationPriorManifest committed of
      Nothing -> pure (Right ())
      Just priorManifest
        | Artifact.manifestGenerationFingerprint priorManifest
            == Artifact.manifestGenerationFingerprint currentManifest ->
            pure (Right ())
        | otherwise -> do
            unless
              ( Artifact.manifestAdapterId priorManifest
                  == nativeArtifactAdapterId identity
                  && Artifact.manifestLocalInstallRoot priorManifest
                    == installRoot
              )
              ( ioError
                  ( userError
                      "prior artifact manifest disagrees with the closed activation identity"
                  )
              )
            priorLease <-
              either
                (ioError . userError . ("derive prior artifact generation lease: " <>))
                pure
                ( artifactGenerationLease
                    enginesRoot
                    identity
                    (Artifact.manifestGenerationFingerprint priorManifest)
                    (Artifact.manifestDigest priorManifest)
                )
            if priorLease == currentLease
              then
                ioError
                  ( userError
                      "obsolete artifact generation resolved to the current lease"
                  )
              else do
                retirement <-
                  withTryArtifactGenerationMutationLock
                    authority
                    priorLease
                    ( \priorAuthority ->
                        retireArtifactGenerationLease
                          authority
                          priorAuthority
                          priorLease
                    )
                pure (obsoleteSidecarRetirementOutcome retirement)
    where
      (enginesRoot, _, _, _) =
        artifactGenerationLeaseFields currentLease
      currentManifest =
        Artifact.committedArtifactActivationManifest committed

-- | A rolled-back activation still fails closed when its installed smoke
-- exited cleanly but produced no standard output.
rejectEmptySmokeOutput ::
  Either String Subprocess.NativeArtifactCommandOutcome ->
  Either String Subprocess.NativeArtifactCommandOutcome
rejectEmptySmokeOutput outcome =
  case outcome of
    Right
      ( Subprocess.NativeArtifactCommandExited
          ExitSuccess
          output
          _
        )
        | ByteString.null output ->
            Left "installed artifact smoke returned empty standard output"
    _ -> outcome

-- | A contended obsolete sidecar is retained, not silently discarded.
obsoleteSidecarRetirementOutcome :: Maybe () -> Either String ()
obsoleteSidecarRetirementOutcome retirement =
  case retirement of
    Just () -> Right ()
    Nothing ->
      Left
        "obsolete artifact generation sidecar remains contended and was retained"

provisioningSubprocessTimeout ::
  Provisioning.PositiveProvisioningTimeout ->
  Subprocess.Timeout
provisioningSubprocessTimeout timeout =
  Subprocess.Timeout
    (Provisioning.positiveProvisioningTimeoutMicros timeout)
