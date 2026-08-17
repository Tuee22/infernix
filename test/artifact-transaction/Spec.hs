{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}

module Main (main) where

import Control.Concurrent
  ( MVar,
    forkFinally,
    newEmptyMVar,
    putMVar,
    takeMVar,
    throwTo,
  )
import Control.Exception
  ( AsyncException (ThreadKilled),
    IOException,
    SomeException,
    bracket,
    displayException,
    fromException,
    try,
  )
import Control.Monad (forM, unless, void, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.DescriptorSpace (establishBoundedDescriptorSpace)
import Infernix.Engines.Artifact
  ( ArtifactLauncher,
    ArtifactProcessOutcome (..),
    ArtifactResolution (..),
    ArtifactRuntimeExpectation,
    ArtifactSnapshotBoundary (..),
    ArtifactTerminalOutcome (..),
    EngineArtifactManifest (..),
    NativeArtifactIdentity,
    ResolvedArtifactProvenance (..),
    appleArtifactRuntimeExpectation,
    artifactLaunchLeadingArguments,
    artifactLauncher,
    currentArtifactRecipeFingerprint,
    decodeEngineArtifactManifest,
    digestEngineArtifactPayload,
    digestEngineArtifactPayloadWithObserver,
    engineArtifactManifestPath,
    engineArtifactPreviousRoot,
    engineArtifactTempRoot,
    linuxArtifactRuntimeExpectation,
    maximumArtifactSnapshotBytes,
    maximumArtifactSnapshotDepth,
    maximumArtifactSnapshotEntries,
    overwriteFileBeforeLaunch,
    parseNativeArtifactIdentity,
    renderArtifactSnapshotRecord,
    renderEngineArtifactManifest,
    validateArtifactSnapshotBounds,
    validateEngineArtifactRootAt,
    withFirstValidatedEngineArtifact,
    withFirstValidatedEngineArtifactUnderPreLaunchFixture,
  )
import Infernix.Engines.Artifact.Internal
  ( ArtifactActivationBoundary (..),
    ArtifactCleanupBoundary (..),
    artifactRootMutatorForTest,
    digestEngineArtifactImageClosureForTest,
    installEngineArtifactRoot,
    installEngineArtifactRootWithCleanupObserverForTest,
    installEngineArtifactRootWithExpectedDigest,
    installEngineArtifactRootWithObserverForTest,
    installEngineArtifactRootWithPendingActionForTest,
    reconcileEngineArtifactRoot,
  )
import Infernix.Engines.Artifact.Snapshot
  ( collectBoundedDirectoryEntries,
  )
import Infernix.Engines.Artifact.Target
  ( nativeArtifactTarget,
    nativeArtifactTargetFingerprint,
  )
import Infernix.Engines.MaterializationLock.Internal
  ( ArtifactGenerationLease,
    MaterializationAuthority,
    artifactGenerationLease,
    maximumArtifactGenerationLeaseDirectoryEntries,
    maximumArtifactGenerationLeaseSidecars,
    reconcileObsoleteArtifactGenerationLeases,
    reconcileObsoleteArtifactGenerationLeasesWithPauseForTest,
    withEngineMaterializationLock,
    withTryArtifactGenerationMutationLock,
    withTryArtifactGenerationReadLock,
  )
import System.Directory
  ( createDirectory,
    createDirectoryIfMissing,
    createFileLink,
    doesPathExist,
    getPermissions,
    getTemporaryDirectory,
    makeAbsolute,
    removeFile,
    removePathForcibly,
    renameDirectory,
    renameFile,
    setOwnerExecutable,
    setPermissions,
  )
import System.Exit (ExitCode (ExitSuccess), exitFailure)
import System.FileLock qualified as FileLock
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, openTempFile)
import System.IO.Unsafe (unsafeInterleaveIO)
import System.Posix.Files (createNamedPipe, setFileMode, setFileSize)
import System.Timeout (timeout)

main :: IO ()
main = do
  -- Test images spawn self-exec children through the same close_fds
  -- kernels the production binary uses, so they bound their descriptor
  -- space first. See "Infernix.DescriptorSpace".
  _ <- establishBoundedDescriptorSpace
  results <-
    forM testCases $ \(label, testCase) -> do
      result <- try @SomeException testCase
      case result of
        Right () -> do
          putStrLn ("PASS: " <> label)
          pure True
        Left failure -> do
          putStrLn
            ( "FAIL: "
                <> label
                <> "\n"
                <> displayException failure
            )
          pure False
  unless (and results) exitFailure
  putStrLn
    ( "artifact transaction tests passed: "
        <> show (length testCases)
        <> " cases"
    )

testCases :: [(String, IO ())]
testCases =
  [ ("payload record schema and field order are stable", payloadRecordGoldenTest),
    ("descriptor enumeration aborts before allocating beyond its budget", directoryEnumerationBudgetTest),
    ("payload digest is deterministic and covers content and mode", digestContentAndModeTest),
    ("payload digest covers safe link text and excludes the manifest", digestLinkAndManifestTest),
    ("descriptor snapshot rejects directory and symlink mutation", descriptorSnapshotMutationTest),
    ("descriptor snapshot rejects growth beyond a file's declared size", descriptorFileGrowthTest),
    ("descriptor snapshot bounds reject aggregate overflow", descriptorSnapshotBoundsTest),
    ("descriptor snapshot rejects sparse declared-size overflow before hashing", sparseDeclaredSizeOverflowTest),
    ("manifest symlinks and special payload files are rejected", manifestAndSpecialFileRejectionTest),
    ("absolute and nested escaping symlinks are rejected", escapingSymlinkRejectionTest),
    ("image closures admit only absolute symlinks contained by the exact root", imageClosureSymlinkPolicyTest),
    ("root, digest, and direct-target manifest mismatches are rejected", manifestMismatchTest),
    ("exact manifests bind canonical digest, key, mode, and Apple provenance", exactManifestContractTest),
    ("current closed recipe invalidates a prior artifact recipe", recipeFingerprintInvalidationTest),
    ("payload and manifest tampering reject runtime capability minting", artifactTamperTest),
    ("runtime capability binds adapter, entrypoint, substrate, and architecture", runtimeBindingTest),
    ("runtime resolution preserves fallback order and rejects corrupt priority roots", runtimeResolutionTest),
    ("runtime resolution reports materialization contention without waiting", runtimeBusyTest),
    ("generation sidecar reconciliation retains current and retries contention", generationSidecarReconciliationTest),
    ("generation sidecar reconciliation rejects inode replacement", generationSidecarReplacementTest),
    ("generation sidecar reconciliation rejects fixed-bound overflow", generationSidecarBoundTest),
    ("generation sidecar reconciliation bounds root enumeration", generationSidecarDirectoryBoundTest),
    ("full use-boundary validation detects nested payload tampering", nestedPayloadUseBoundaryTest),
    ("validated runtime callback excludes cooperative materialization", runtimeReadLockTest),
    ("runtime program holds and releases its read lock through reap and cancellation", runtimeProgramLockLifetimeTest),
    ("runtime launch holds the exact generation lease through reap", runtimeGenerationLeaseHeldTest),
    ("runtime launch refuses a generation no writer minted", runtimeUnmintedGenerationTest),
    ("runtime launch carries the closed catalog's leading arguments", runtimeLeadingArgumentsTest),
    ("fresh activation installs one exact root", freshActivationTest),
    ("smoke-bound activation rejects a valid candidate mutated after smoke", smokeBoundDigestTamperTest),
    ("replacement activation retires the previous exact root", replacementActivationTest),
    ("installed validation runs before rollback state is retired", installedValidationSuccessTest),
    ("pending activation synchronous failure restores the previous root", installedValidationFailureTest),
    ("pending activation cancellation restores the previous root", installedValidationCancellationTest),
    ("commit cleanup failure remains exactly reconcilable", activationCleanupFailureReconciliationTest),
    ("identical exact rerun discards only the candidate", idempotentExactRerunTest),
    ("legacy declarative roots remain distinct during reconciliation", legacyRootDistinctionTest),
    ("legacy candidates cannot downgrade an exact root", legacyCandidateDowngradeRejectionTest),
    ("candidate validation failure preserves a legacy migration root", legacyPreActivationFailureTest),
    ("exact activation migrates and retires a legacy root", legacyMigrationActivationTest),
    ("activation failure rolls back to the legacy migration root", legacyMigrationRollbackTest),
    ("fresh activation synchronous failure returns the candidate", synchronousFreshCandidateBoundaryTest),
    ("synchronous failure after moving the previous root rolls back", synchronousPreviousBoundaryTest),
    ("synchronous failure after moving the candidate rolls back", synchronousCandidateBoundaryTest),
    ("fresh activation asynchronous cancellation returns the candidate", asynchronousFreshCandidateBoundaryTest),
    ("asynchronous cancellation after moving the previous root rolls back", asynchronousPreviousBoundaryTest),
    ("asynchronous cancellation after moving the candidate rolls back", asynchronousCandidateBoundaryTest),
    ("crash reconciliation chooses only complete roots", crashReconciliationMatrixTest)
  ]

payloadRecordGoldenTest :: IO ()
payloadRecordGoldenTest =
  assertEqual
    "v2 record schema, field names, and order"
    ( ByteString.intercalate
        (ByteString8.pack "\0")
        ( map
            ByteString8.pack
            [ "infernix-engine-payload-record-v2",
              "type",
              "file",
              "path",
              "bin/runner",
              "mode",
              "493",
              "size",
              "12",
              "detail",
              "sha256:abc"
            ]
        )
        <> ByteString8.pack "\0"
    )
    (renderArtifactSnapshotRecord "file" "bin/runner" 493 12 "sha256:abc")

directoryEnumerationBudgetTest :: IO ()
directoryEnumerationBudgetTest = do
  exactReads <- newIORef ["zeta", ".", "alpha", "..", "middle", ""]
  exactEntries <-
    collectBoundedDirectoryEntries
      3
      (readSyntheticDirectoryEntry exactReads)
  assertEqual
    "the exact enumeration budget accepts and sorts every real entry"
    ["alpha", "middle", "zeta"]
    exactEntries

  overflowReads <- newIORef ["one", "two", "three", "overflow", "unread", ""]
  overflowResult <-
    try @IOException
      ( collectBoundedDirectoryEntries
          3
          (readSyntheticDirectoryEntry overflowReads)
      )
  case overflowResult of
    Left _ -> pure ()
    Right entries ->
      failTest
        ( "directory enumeration overflow was accepted: "
            <> show entries
        )
  remainingEntries <- readIORef overflowReads
  assertEqual
    "entry N+1 is rejected before it is retained and later names are not read"
    ["unread", ""]
    remainingEntries

readSyntheticDirectoryEntry :: IORef [FilePath] -> IO FilePath
readSyntheticDirectoryEntry entriesRef =
  atomicModifyIORef' entriesRef $ \case
    [] -> ([], error "synthetic directory stream read past its terminator")
    entry : remaining -> (remaining, entry)

digestContentAndModeTest :: IO ()
digestContentAndModeTest =
  withTestDirectory $ \workspace -> do
    let firstRoot = workspace </> "first"
        secondRoot = workspace </> "second"
        firstAlpha = firstRoot </> "nested" </> "alpha.txt"
        secondAlpha = secondRoot </> "nested" </> "alpha.txt"
    createDirectoryIfMissing True (firstRoot </> "nested")
    writeFile (firstRoot </> "zeta.txt") "zeta"
    writeFile firstAlpha "alpha"
    createDirectoryIfMissing True (secondRoot </> "nested")
    writeFile secondAlpha "alpha"
    writeFile (secondRoot </> "zeta.txt") "zeta"
    firstDigest <- digestEngineArtifactPayload firstRoot
    secondDigest <- digestEngineArtifactPayload secondRoot
    assertEqual
      "equal trees created in different orders have one digest"
      firstDigest
      secondDigest
    writeFile firstAlpha "changed"
    changedContentDigest <- digestEngineArtifactPayload firstRoot
    assertNotEqual
      "file content contributes to the digest"
      firstDigest
      changedContentDigest
    writeFile firstAlpha "alpha"
    originalPermissions <- getPermissions firstAlpha
    setPermissions firstAlpha (setOwnerExecutable True originalPermissions)
    changedModeDigest <- digestEngineArtifactPayload firstRoot
    assertNotEqual
      "file mode contributes to the digest"
      firstDigest
      changedModeDigest

digestLinkAndManifestTest :: IO ()
digestLinkAndManifestTest =
  withTestDirectory $ \workspace -> do
    let root = workspace </> "artifact"
        payloadRoot = root </> "payload"
        linkRoot = root </> "links"
        linkPath = linkRoot </> "current"
        manifestPath = engineArtifactManifestPath root
    createDirectoryIfMissing True payloadRoot
    createDirectory linkRoot
    writeFile (payloadRoot </> "first") "same"
    writeFile (payloadRoot </> "second") "same"
    createFileLink "../payload/first" linkPath
    firstLinkDigest <- digestEngineArtifactPayload root
    removeFile linkPath
    createFileLink "../payload/second" linkPath
    secondLinkDigest <- digestEngineArtifactPayload root
    assertNotEqual
      "safe relative symlink text contributes to the digest"
      firstLinkDigest
      secondLinkDigest
    writeFile manifestPath "first manifest body"
    firstManifestDigest <- digestEngineArtifactPayload root
    writeFile manifestPath "different manifest body"
    secondManifestDigest <- digestEngineArtifactPayload root
    assertEqual
      "manifest bytes are excluded from the payload digest"
      firstManifestDigest
      secondManifestDigest

descriptorSnapshotMutationTest :: IO ()
descriptorSnapshotMutationTest =
  withTestDirectory $ \workspace -> do
    let directoryRoot = workspace </> "directory-mutation"
        nestedRoot = directoryRoot </> "nested"
        previousNestedRoot = directoryRoot </> "nested.previous"
        symlinkRoot = workspace </> "symlink-mutation"
        symlinkPayloadRoot = symlinkRoot </> "payload"
        symlinkPath = symlinkRoot </> "current"
    createDirectoryIfMissing True nestedRoot
    writeFile (nestedRoot </> "payload") "original"
    -- The digest walks the generation twice and requires the two walks to
    -- agree, so every pause below is one-shot: a confirming walk that blocked
    -- on the recording walk's resume would deadlock rather than confirm.
    pauseDirectoryListing <- newIORef True
    directoryEntered <- newEmptyMVar
    directoryResume <- newEmptyMVar
    directoryResult <- newEmptyMVar
    _ <-
      forkFinally
        ( digestEngineArtifactPayloadWithObserver
            ( \case
                ArtifactSnapshotDirectoryListed "nested" -> do
                  shouldPause <-
                    atomicModifyIORef' pauseDirectoryListing (False,)
                  when shouldPause $
                    putMVar directoryEntered () >> takeMVar directoryResume
                _ -> pure ()
            )
            directoryRoot
        )
        (putMVar directoryResult)
    takeMVar directoryEntered
    renameDirectory nestedRoot previousNestedRoot
    createDirectory nestedRoot
    writeFile (nestedRoot </> "payload") "replacement"
    putMVar directoryResume ()
    assertSnapshotMutationRejected
      "replaced retained directory"
      =<< takeMVar directoryResult

    createDirectoryIfMissing True symlinkPayloadRoot
    writeFile (symlinkPayloadRoot </> "first") "first"
    writeFile (symlinkPayloadRoot </> "second") "second"
    createFileLink "payload/first" symlinkPath
    pauseSymlinkEntry <- newIORef True
    symlinkEntered <- newEmptyMVar
    symlinkResume <- newEmptyMVar
    symlinkResult <- newEmptyMVar
    _ <-
      forkFinally
        ( digestEngineArtifactPayloadWithObserver
            ( \case
                ArtifactSnapshotEntryOpened "current" -> do
                  shouldPause <- atomicModifyIORef' pauseSymlinkEntry (False,)
                  when shouldPause $
                    putMVar symlinkEntered () >> takeMVar symlinkResume
                _ -> pure ()
            )
            symlinkRoot
        )
        (putMVar symlinkResult)
    takeMVar symlinkEntered
    removeFile symlinkPath
    createFileLink "payload/second" symlinkPath
    putMVar symlinkResume ()
    assertSnapshotMutationRejected
      "replaced path-read symlink"
      =<< takeMVar symlinkResult

descriptorFileGrowthTest :: IO ()
descriptorFileGrowthTest =
  withTestDirectory $ \workspace -> do
    let root = workspace </> "growing-root"
        payloadPath = root </> "growing.bin"
    createDirectory root
    ByteString.writeFile
      payloadPath
      (ByteString.replicate (192 * 1024) 65)
    pauseFirstChunk <- newIORef True
    chunkEntered <- newEmptyMVar
    chunkResume <- newEmptyMVar
    digestResult <- newEmptyMVar
    _ <-
      forkFinally
        ( digestEngineArtifactPayloadWithObserver
            ( \case
                ArtifactSnapshotFileChunkRead "growing.bin" observedBytes
                  | observedBytes > 0 -> do
                      shouldPause <-
                        atomicModifyIORef'
                          pauseFirstChunk
                          (False,)
                      when shouldPause $
                        putMVar chunkEntered () >> takeMVar chunkResume
                _ -> pure ()
            )
            root
        )
        (putMVar digestResult)
    takeMVar chunkEntered
    ByteString.appendFile payloadPath (ByteString8.pack "grew-after-open")
    putMVar chunkResume ()
    assertSnapshotMutationRejected
      "regular file growth beyond its opened declared size"
      =<< takeMVar digestResult

descriptorSnapshotBoundsTest :: IO ()
descriptorSnapshotBoundsTest = do
  assertEqual
    "exact aggregate snapshot limits are accepted"
    (Right ())
    ( validateArtifactSnapshotBounds
        maximumArtifactSnapshotEntries
        maximumArtifactSnapshotBytes
        maximumArtifactSnapshotDepth
    )
  assertBoundsRejected
    "entry overflow"
    ( validateArtifactSnapshotBounds
        (maximumArtifactSnapshotEntries + 1)
        maximumArtifactSnapshotBytes
        maximumArtifactSnapshotDepth
    )
  assertBoundsRejected
    "byte overflow"
    ( validateArtifactSnapshotBounds
        maximumArtifactSnapshotEntries
        (maximumArtifactSnapshotBytes + 1)
        maximumArtifactSnapshotDepth
    )
  assertBoundsRejected
    "depth overflow"
    ( validateArtifactSnapshotBounds
        maximumArtifactSnapshotEntries
        maximumArtifactSnapshotBytes
        (maximumArtifactSnapshotDepth + 1)
    )

sparseDeclaredSizeOverflowTest :: IO ()
sparseDeclaredSizeOverflowTest =
  withTestDirectory $ \workspace -> do
    let root = workspace </> "sparse-root"
        sparsePath = root </> "sparse.bin"
    createDirectory root
    writeFile sparsePath ""
    setFileSize sparsePath (fromInteger (maximumArtifactSnapshotBytes + 1))
    assertIOException
      "a sparse file exceeding the aggregate byte bound is rejected before hashing"
      (digestEngineArtifactPayload root)

assertSnapshotMutationRejected ::
  String ->
  Either SomeException Text ->
  IO ()
assertSnapshotMutationRejected label result =
  case result of
    Left failure ->
      case fromException failure :: Maybe IOException of
        Just _ -> pure ()
        Nothing ->
          failTest (label <> " raised a non-IOException: " <> displayException failure)
    Right _ ->
      failTest (label <> " was accepted")

assertBoundsRejected :: String -> Either String () -> IO ()
assertBoundsRejected label result =
  case result of
    Left _ -> pure ()
    Right () -> failTest (label <> " was accepted")

manifestAndSpecialFileRejectionTest :: IO ()
manifestAndSpecialFileRejectionTest =
  withTestDirectory $ \workspace -> do
    let manifestLinkRoot = workspace </> "manifest-link"
        specialRoot = workspace </> "special"
    createDirectory manifestLinkRoot
    writeFile (manifestLinkRoot </> "manifest-target") "{}"
    createFileLink
      "manifest-target"
      (engineArtifactManifestPath manifestLinkRoot)
    assertIOException
      "a manifest symlink must not be excluded as trusted metadata"
      (digestEngineArtifactPayload manifestLinkRoot)
    createDirectory specialRoot
    createNamedPipe (specialRoot </> "payload.fifo") 0o600
    assertIOException
      "a FIFO is not an immutable artifact payload"
      (digestEngineArtifactPayload specialRoot)

escapingSymlinkRejectionTest :: IO ()
escapingSymlinkRejectionTest =
  withTestDirectory $ \workspace -> do
    let absoluteRoot = workspace </> "absolute"
        nestedRoot = workspace </> "nested"
    createDirectory absoluteRoot
    createFileLink
      "/tmp/infernix-artifact-transaction-outside"
      (absoluteRoot </> "outside")
    assertIOException
      "absolute symlinks are rejected"
      (digestEngineArtifactPayload absoluteRoot)
    createDirectoryIfMissing True (nestedRoot </> "level")
    createFileLink
      "../../outside"
      (nestedRoot </> "level" </> "outside")
    assertIOException
      "a second parent traversal from a nested link escapes the root"
      (digestEngineArtifactPayload nestedRoot)

imageClosureSymlinkPolicyTest :: IO ()
imageClosureSymlinkPolicyTest =
  withTestDirectory $ \workspace -> do
    let imageRoot = workspace </> "image-closure"
        outsideRoot = workspace </> "outside-closure"
    createDirectory imageRoot
    createDirectory outsideRoot
    writeFile (imageRoot </> "native-library") "inside"
    writeFile (outsideRoot </> "native-library") "outside"
    absoluteInside <- makeAbsolute (imageRoot </> "native-library")
    absoluteOutside <- makeAbsolute (outsideRoot </> "native-library")
    createFileLink absoluteInside (imageRoot </> "inside-link")
    assertIOException
      "an installed artifact rejects an absolute symlink even when it is self-contained"
      (digestEngineArtifactPayload imageRoot)
    void (digestEngineArtifactImageClosureForTest imageRoot)
    removeFile (imageRoot </> "inside-link")
    createFileLink absoluteOutside (imageRoot </> "outside-link")
    assertIOException
      "an image closure rejects an absolute symlink outside its exact root"
      (digestEngineArtifactImageClosureForTest imageRoot)

manifestMismatchTest :: IO ()
manifestMismatchTest =
  withTestDirectory $ \workspace -> do
    let expectedRoot = workspace </> "installed"
        actualRoot = workspace </> "candidate"
    validManifest <- writeExactArtifactRoot expectedRoot actualRoot "payload"
    writeManifest
      actualRoot
      validManifest
        { manifestLocalInstallRoot = expectedRoot <> "-other"
        }
    assertIOException
      "the manifest install root must name the exact final root"
      (validateEngineArtifactRootAt expectedRoot actualRoot)
    writeManifest
      actualRoot
      validManifest
        { manifestDigest = "sha256:not-the-payload-digest"
        }
    assertIOException
      "the manifest digest must match the actual payload tree"
      (validateEngineArtifactRootAt expectedRoot actualRoot)
    writeManifest
      actualRoot
      validManifest
        { manifestTargetContractFingerprint =
            "sha256:" <> Text.replicate 64 "0"
        }
    assertIOException
      "the manifest must bind the closed direct-target contract"
      (validateEngineArtifactRootAt expectedRoot actualRoot)
    writeManifest actualRoot validManifest
    removeFile (actualRoot </> "native" </> "bin" </> "llama-completion")
    assertIOException
      "the closed direct target must remain present"
      (validateEngineArtifactRootAt expectedRoot actualRoot)

exactManifestContractTest :: IO ()
exactManifestContractTest =
  withTestDirectory $ \workspace -> do
    let digestRoot = workspace </> "digest"
        keyRoot = workspace </> "key"
        modeRoot = workspace </> "mode"
        provenanceRoot = workspace </> "provenance"
    digestManifest <- writeExactArtifactRoot digestRoot digestRoot "digest"
    let uppercaseDigest =
          "sha256:" <> Text.replicate 64 "A"
    writeManifest
      digestRoot
      digestManifest
        { manifestDigest = uppercaseDigest,
          manifestMinioObjectKey =
            exactObjectKey
              "apple-silicon"
              "arm64"
              "llama-cpp-cli"
              uppercaseDigest
        }
    assertIOException
      "digest must use exactly 64 lowercase hexadecimal digits"
      (validateEngineArtifactRootAt digestRoot digestRoot)

    keyManifest <- writeExactArtifactRoot keyRoot keyRoot "key"
    writeManifest
      keyRoot
      keyManifest
        { manifestMinioObjectKey =
            exactObjectKey
              "apple-silicon"
              "arm64"
              "jvm-native"
              (manifestDigest keyManifest)
        }
    assertIOException
      "MinIO key must bind substrate, architecture, adapter, and digest"
      (validateEngineArtifactRootAt keyRoot keyRoot)

    _ <- writeExactArtifactRoot modeRoot modeRoot "mode"
    targetPermissions <-
      getPermissions (modeRoot </> "native" </> "bin" </> "llama-completion")
    setPermissions
      (modeRoot </> "native" </> "bin" </> "llama-completion")
      (setOwnerExecutable False targetPermissions)
    assertIOException
      "the direct target must remain executable"
      (validateEngineArtifactRootAt modeRoot modeRoot)

    provenanceManifest <-
      writeExactArtifactRoot provenanceRoot provenanceRoot "provenance"
    writeManifest
      provenanceRoot
      provenanceManifest
        { manifestResolvedProvenance = []
        }
    assertIOException
      "exact Apple artifact must carry resolved provenance"
      (validateEngineArtifactRootAt provenanceRoot provenanceRoot)

recipeFingerprintInvalidationTest :: IO ()
recipeFingerprintInvalidationTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        supersededFingerprint = "sha256:" <> Text.replicate 64 "0"
    manifest <- writeExactArtifactRoot installRoot installRoot "recipe"
    _ <- validateEngineArtifactRootAt installRoot installRoot
    assertNotEqual
      "the superseded recipe differs from the current catalog"
      supersededFingerprint
      (manifestRecipeFingerprint manifest)
    writeManifest
      installRoot
      manifest
        { manifestRecipeFingerprint = supersededFingerprint
        }
    assertIOException
      "a recipe revision bump invalidates an otherwise unchanged artifact"
      (validateEngineArtifactRootAt installRoot installRoot)

artifactTamperTest :: IO ()
artifactTamperTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let expectation = testRuntimeExpectation
        payloadRoot = workspace </> "payload"
        manifestRoot = workspace </> "manifest"
    _ <- writeExactArtifactRoot payloadRoot payloadRoot "original"
    writeFile (payloadRoot </> "payload.txt") "tampered"
    payloadResolution <-
      withFirstValidatedEngineArtifact
        identity
        expectation
        [payloadRoot]
        completedArtifactLauncher
    assertArtifactRejected
      "payload tamper"
      payloadRoot
      payloadResolution

    originalManifest <-
      writeExactArtifactRoot manifestRoot manifestRoot "manifest"
    let changedIdentity =
          case parseNativeArtifactIdentity "onnx-runtime-native" of
            Just parsedIdentity -> parsedIdentity
            Nothing ->
              error "closed native artifact catalog omitted onnx-runtime-native"
        changedManifest =
          originalManifest
            { manifestAdapterId = "onnx-runtime-native",
              manifestRecipeFingerprint =
                testRecipeFingerprintFor
                  changedIdentity
                  appleArtifactRuntimeExpectation,
              manifestTargetContractFingerprint =
                testTargetFingerprintFor
                  changedIdentity
                  "apple-silicon"
                  "arm64",
              manifestMinioObjectKey =
                exactObjectKey
                  "apple-silicon"
                  "arm64"
                  "onnx-runtime-native"
                  (manifestDigest originalManifest)
            }
    writeManifest manifestRoot changedManifest
    _ <- validateEngineArtifactRootAt manifestRoot manifestRoot
    manifestResolution <-
      withFirstValidatedEngineArtifact
        identity
        expectation
        [manifestRoot]
        completedArtifactLauncher
    assertArtifactRejected
      "manifest adapter tamper"
      manifestRoot
      manifestResolution

runtimeBindingTest :: IO ()
runtimeBindingTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let expectation = testRuntimeExpectation
        targetRoot = workspace </> "target"
        runtimeRoot = workspace </> "runtime"
    targetManifest <-
      writeExactArtifactRoot targetRoot targetRoot "target"
    writeManifest
      targetRoot
      targetManifest
        { manifestTargetContractFingerprint =
            "sha256:" <> Text.replicate 64 "0"
        }
    targetResolution <-
      withFirstValidatedEngineArtifact
        identity
        expectation
        [targetRoot]
        completedArtifactLauncher
    assertArtifactRejected
      "canonical direct-target contract mismatch"
      targetRoot
      targetResolution

    _ <- writeExactArtifactRoot runtimeRoot runtimeRoot "runtime"
    runtimeResolution <-
      withFirstValidatedEngineArtifact
        identity
        linuxArtifactRuntimeExpectation
        [runtimeRoot]
        completedArtifactLauncher
    assertArtifactRejected
      "runtime substrate mismatch"
      runtimeRoot
      runtimeResolution

runtimeResolutionTest :: IO ()
runtimeResolutionTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let expectation = testRuntimeExpectation
        missingRoot = workspace </> "missing"
        validRoot = workspace </> "valid"
        corruptRoot = workspace </> "corrupt"
    _ <- writeExactArtifactRoot validRoot validRoot "valid"
    fallbackResolution <-
      withFirstValidatedEngineArtifact
        identity
        expectation
        [missingRoot, validRoot]
        completedArtifactLauncher
    case fallbackResolution of
      ArtifactResolved ArtifactTerminalCompleted -> pure ()
      _ -> failTest "missing first root did not resolve the exact fallback root"

    createDirectory corruptRoot
    writeFile (corruptRoot </> "incomplete") "corrupt"
    corruptResolution <-
      withFirstValidatedEngineArtifact
        identity
        expectation
        [corruptRoot, validRoot]
        completedArtifactLauncher
    assertArtifactRejected
      "corrupt priority root"
      corruptRoot
      corruptResolution

runtimeBusyTest :: IO ()
runtimeBusyTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let installRoot = workspace </> "artifact"
    _ <- writeExactArtifactRoot installRoot installRoot "busy"
    resolution <-
      withEngineMaterializationLock workspace $ \_authority ->
        withFirstValidatedEngineArtifact
          identity
          testRuntimeExpectation
          [installRoot]
          completedArtifactLauncher
    case resolution of
      ArtifactBusy busyRoot ->
        assertEqual
          "busy root diagnostic"
          installRoot
          busyRoot
      _ ->
        failTest
          "runtime resolution did not return an immediate artifact-busy result"

generationSidecarReconciliationTest :: IO ()
generationSidecarReconciliationTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    currentLease <-
      testGenerationLease workspace identity '1'
    obsoleteLease <-
      testGenerationLease workspace identity '2'
    contendedLease <-
      testGenerationLease workspace identity '3'
    withEngineMaterializationLock workspace $ \authority -> do
      mapM_
        (createGenerationSidecar authority)
        [currentLease, obsoleteLease, contendedLease]
      contentionEntered <- newEmptyMVar
      contentionRelease <- newEmptyMVar
      contentionResult <- newEmptyMVar
      _ <-
        forkFinally
          ( withTryArtifactGenerationReadLock contendedLease $ do
              putMVar contentionEntered ()
              takeMVar contentionRelease
          )
          (putMVar contentionResult)
      takeMVar contentionEntered
      reconcileObsoleteArtifactGenerationLeases
        authority
        [currentLease]
      assertPathPresent
        "retained current generation sidecar"
        (testGenerationSidecarPath workspace '1')
      assertPathMissing
        "uncontended obsolete generation sidecar"
        (testGenerationSidecarPath workspace '2')
      assertPathPresent
        "contended obsolete generation sidecar"
        (testGenerationSidecarPath workspace '3')
      putMVar contentionRelease ()
      heldResult <-
        requireWithin
          "generation sidecar reader did not release"
          (takeMVar contentionResult)
      case heldResult of
        Right (Just ()) -> pure ()
        other ->
          failTest
            ( "generation sidecar reader returned an unexpected result: "
                <> show other
            )
      reconcileObsoleteArtifactGenerationLeases
        authority
        [currentLease]
      assertPathMissing
        "released obsolete generation sidecar"
        (testGenerationSidecarPath workspace '3')

generationSidecarReplacementTest :: IO ()
generationSidecarReplacementTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    obsoleteLease <-
      testGenerationLease workspace identity '4'
    withEngineMaterializationLock workspace $ \authority -> do
      createGenerationSidecar authority obsoleteLease
      observed <- newEmptyMVar
      resume <- newEmptyMVar
      reconciliationResult <- newEmptyMVar
      _ <-
        forkFinally
          ( reconcileObsoleteArtifactGenerationLeasesWithPauseForTest
              authority
              []
              observed
              resume
          )
          (putMVar reconciliationResult)
      takeMVar observed
      let sidecarPath =
            testGenerationSidecarPath workspace '4'
          originalPath =
            sidecarPath <> ".observed"
      renameFile sidecarPath originalPath
      writeFile sidecarPath ""
      setFileMode sidecarPath 0o600
      putMVar resume ()
      result <-
        requireWithin
          "generation sidecar replacement fixture did not finish"
          (takeMVar reconciliationResult)
      case result of
        Left failure
          | "changed after bounded observation"
              `List.isInfixOf` displayException failure ->
              pure ()
        Left failure ->
          failTest
            ( "generation sidecar replacement returned the wrong failure: "
                <> displayException failure
            )
        Right () ->
          failTest "generation sidecar replacement was accepted"
      assertPathPresent
        "replacement generation sidecar"
        sidecarPath

generationSidecarBoundTest :: IO ()
generationSidecarBoundTest =
  withTestDirectory $ \workspace -> do
    let sidecarCount =
          maximumArtifactGenerationLeaseSidecars + 1
    mapM_
      (writeGenerationSidecar workspace)
      [0 .. sidecarCount - 1]
    result <-
      try @IOException
        ( withEngineMaterializationLock workspace $ \authority ->
            reconcileObsoleteArtifactGenerationLeases authority []
        )
    case result of
      Left failure
        | "sidecar count exceeds its fixed bound"
            `List.isInfixOf` displayException failure ->
            pure ()
      Left failure ->
        failTest
          ( "generation sidecar bound returned the wrong failure: "
              <> displayException failure
          )
      Right () ->
        failTest "generation sidecar reconciliation accepted bound overflow"

generationSidecarDirectoryBoundTest :: IO ()
generationSidecarDirectoryBoundTest =
  withTestDirectory $ \workspace -> do
    mapM_
      ( \index ->
          writeFile
            (workspace </> "unrelated-entry-" <> show index)
            ""
      )
      [0 .. maximumArtifactGenerationLeaseDirectoryEntries]
    result <-
      try @IOException
        ( withEngineMaterializationLock workspace $ \authority ->
            reconcileObsoleteArtifactGenerationLeases authority []
        )
    case result of
      Left failure
        | "root exceeds its fixed directory-entry bound"
            `List.isInfixOf` displayException failure ->
            pure ()
      Left failure ->
        failTest
          ( "generation sidecar directory bound returned the wrong failure: "
              <> displayException failure
          )
      Right () ->
        failTest "generation sidecar reconciliation accepted unbounded root enumeration"

testGenerationLease ::
  FilePath ->
  NativeArtifactIdentity ->
  Char ->
  IO ArtifactGenerationLease
testGenerationLease workspace identity digit =
  either
    (failTest . ("derive test generation lease: " <>))
    pure
    ( artifactGenerationLease
        workspace
        identity
        fingerprint
        fingerprint
    )
  where
    fingerprint =
      "sha256:" <> Text.replicate 64 (Text.singleton digit)

createGenerationSidecar ::
  MaterializationAuthority w ->
  ArtifactGenerationLease ->
  IO ()
createGenerationSidecar authority lease = do
  created <-
    withTryArtifactGenerationMutationLock
      authority
      lease
      (const (pure ()))
  case created of
    Just () -> pure ()
    Nothing -> failTest "test generation sidecar was unexpectedly contended"

testGenerationSidecarPath :: FilePath -> Char -> FilePath
testGenerationSidecarPath workspace digit =
  workspace
    </> ( ".generation-lease-llama-cpp-cli-"
            <> replicate 64 digit
            <> ".lock"
        )

writeGenerationSidecar :: FilePath -> Int -> IO ()
writeGenerationSidecar workspace index = do
  let fingerprint =
        Text.unpack
          (Text.justifyRight 64 '0' (Text.pack (show index)))
      sidecarPath =
        workspace
          </> ( ".generation-lease-llama-cpp-cli-"
                  <> fingerprint
                  <> ".lock"
              )
  writeFile sidecarPath ""
  setFileMode sidecarPath 0o600

nestedPayloadUseBoundaryTest :: IO ()
nestedPayloadUseBoundaryTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let installRoot = workspace </> "artifact"
        nestedRoot = installRoot </> "lib"
        nestedPayload = nestedRoot </> "runtime.bin"
    manifest <- writeExactArtifactRoot installRoot installRoot "nested"
    createDirectory nestedRoot
    writeFile nestedPayload "original nested payload"
    _ <- refreshExactManifest installRoot manifest
    resolution <-
      withFirstValidatedEngineArtifactUnderPreLaunchFixture
        identity
        testRuntimeExpectation
        [installRoot]
        ( overwriteFileBeforeLaunch
            nestedPayload
            (ByteString8.pack "tampered nested payload")
        )
        ( artifactLauncher
            (const (pure ArtifactTerminalCompleted))
        )
    case resolution of
      ArtifactResolved ArtifactTerminalRejected -> pure ()
      _ ->
        failTest
          "runner-owned use-boundary revalidation accepted nested payload tampering"

-- | The generation lease is what makes generation identity authorize shared
-- execution. These two cases pin the halves of that separately, and both
-- discriminate against the pre-correction source, which stored the lease on the
-- validated capability and never consumed it: an exclusive lock on the sidecar
-- was freely available while an artifact ran, and a root whose generation no
-- writer had ever minted launched normally.
runtimeGenerationLeaseHeldTest :: IO ()
runtimeGenerationLeaseHeldTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let installRoot = workspace </> "artifact"
    manifest <- writeExactArtifactRoot installRoot installRoot "generation-leased"
    let sidecarPath = exactGenerationSidecarPath installRoot manifest

    launcherEntered <- newEmptyMVar
    launcherResume <- newEmptyMVar
    runResult <- newEmptyMVar
    _ <-
      forkFinally
        ( withFirstValidatedEngineArtifact
            identity
            testRuntimeExpectation
            [installRoot]
            ( artifactLauncher
                ( \_launchRequest -> do
                    putMVar launcherEntered ()
                    takeMVar launcherResume
                    pure ArtifactTerminalCompleted
                )
            )
        )
        (putMVar runResult)
    takeMVar launcherEntered
    heldDuringRun <- tryExclusiveGenerationSidecar sidecarPath
    when heldDuringRun $
      failTest
        "the exact generation lease was available exclusively while its artifact was running"
    putMVar launcherResume ()
    -- The bound is generous because this suite shares the host with the other
    -- lifecycle-driving suites; the assertion is about the lease, not latency.
    maybeCompleted <- timeout 20000000 (takeMVar runResult)
    completed <-
      maybe
        (failTest "leased artifact program did not finish")
        pure
        maybeCompleted
    case completed of
      Right (ArtifactResolved ArtifactTerminalCompleted) -> pure ()
      Right _ -> failTest "leased artifact program returned an unexpected result"
      Left failure ->
        failTest
          ( "leased artifact program failed unexpectedly: "
              <> displayException failure
          )
    releasedAfterRun <- tryExclusiveGenerationSidecar sidecarPath
    unless releasedAfterRun $
      failTest
        "the exact generation lease was not released after the artifact was reaped"

runtimeUnmintedGenerationTest :: IO ()
runtimeUnmintedGenerationTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let installRoot = workspace </> "artifact"
    manifest <- writeExactArtifactRoot installRoot installRoot "unminted"
    removeFile (exactGenerationSidecarPath installRoot manifest)
    launched <- newIORef False
    resolution <-
      withFirstValidatedEngineArtifact
        identity
        testRuntimeExpectation
        [installRoot]
        ( artifactLauncher
            ( const
                ( do
                    atomicModifyIORef' launched (const (True, ()))
                    pure ArtifactTerminalCompleted
                )
            )
        )
    case resolution of
      ArtifactRejected rejectedRoot _
        | rejectedRoot == installRoot -> pure ()
      _ ->
        failTest
          "runtime resolution admitted a generation whose lease sidecar no writer minted"
    reachedLauncher <- readIORef launched
    when reachedLauncher $
      failTest "an unminted generation reached the artifact launcher"

-- | Wrapper retirement removed the generated per-engine shell shim that
-- translated the native-runner protocol into each payload's real argument
-- vector, and rebuilt only the smoke's argument rendering. The runtime launch
-- must therefore carry the closed catalog's leading arguments itself — for an
-- installed Python-runner target, the runner script plus the runner's own
-- required @--adapter-id@/@--engine-name@ pair. Pre-correction the launch
-- request had no such field, so every Python-runner artifact was handed
-- protocol flags its runner cannot parse.
runtimeLeadingArgumentsTest :: IO ()
runtimeLeadingArgumentsTest =
  withTestDirectory $ \workspace -> do
    runnerIdentity <-
      maybe
        (failTest "closed native artifact catalog omitted onnx-runtime-native")
        pure
        (parseNativeArtifactIdentity "onnx-runtime-native")
    let installRoot = workspace </> "artifact"
    baseManifest <-
      writeExactArtifactRoot installRoot installRoot "leading-arguments"
    let runnerManifest =
          baseManifest
            { manifestAdapterId = "onnx-runtime-native",
              manifestRecipeFingerprint =
                testRecipeFingerprintFor
                  runnerIdentity
                  appleArtifactRuntimeExpectation,
              manifestTargetContractFingerprint =
                testTargetFingerprintFor
                  runnerIdentity
                  "apple-silicon"
                  "arm64",
              manifestMinioObjectKey =
                exactObjectKey
                  "apple-silicon"
                  "arm64"
                  "onnx-runtime-native"
                  (manifestDigest baseManifest)
            }
    writeManifest installRoot runnerManifest
    _ <- validateEngineArtifactRootAt installRoot installRoot
    mintExactGenerationSidecar runnerIdentity installRoot runnerManifest
    observedArguments <- newIORef []
    resolution <-
      withFirstValidatedEngineArtifact
        runnerIdentity
        testRuntimeExpectation
        [installRoot]
        ( artifactLauncher
            ( \launchRequest -> do
                atomicModifyIORef'
                  observedArguments
                  ( const
                      ( artifactLaunchLeadingArguments launchRequest,
                        ()
                      )
                  )
                pure ArtifactTerminalCompleted
            )
        )
    case resolution of
      ArtifactResolved ArtifactTerminalCompleted -> pure ()
      _ ->
        failTest
          "a Python-runner artifact did not resolve through the runtime launch"
    leadingArguments <- readIORef observedArguments
    unless
      ( leadingArguments
          == [ installRoot </> "lib" </> "apple_native_runner.py",
               "--adapter-id",
               "onnx-runtime-native",
               "--engine-name",
               "onnx-runtime-native",
               "--expected-python-prefix",
               installRoot </> "venv"
             ]
      )
      ( failTest
          ( "the launch request did not carry the closed catalog's leading arguments: "
              <> show leadingArguments
          )
      )

-- | The sidecar 'artifactGenerationLease' derives for an exact manifest. The
-- test computes it from the manifest rather than reading it back, so a change
-- to the naming scheme is a visible edit here.
exactGenerationSidecarPath :: FilePath -> EngineArtifactManifest -> FilePath
exactGenerationSidecarPath installRoot manifest =
  takeDirectory installRoot
    </> ( ".generation-lease-"
            <> Text.unpack (manifestAdapterId manifest)
            <> "-"
            <> Text.unpack
              (Text.drop 7 (manifestGenerationFingerprint manifest))
            <> ".lock"
        )

tryExclusiveGenerationSidecar :: FilePath -> IO Bool
tryExclusiveGenerationSidecar sidecarPath = do
  maybeLock <- FileLock.tryLockFile sidecarPath FileLock.Exclusive
  case maybeLock of
    Nothing -> pure False
    Just token -> do
      FileLock.unlockFile token
      pure True

runtimeReadLockTest :: IO ()
runtimeReadLockTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let installRoot = workspace </> "artifact"
    _ <- writeExactArtifactRoot installRoot installRoot "locked"
    resolution <-
      withFirstValidatedEngineArtifact
        identity
        testRuntimeExpectation
        [installRoot]
        ( artifactLauncher
            ( \_launchRequest -> do
                writerResult <-
                  try @IOException
                    (withEngineMaterializationLock workspace (\_authority -> pure ()))
                pure $
                  case writerResult of
                    Left _ -> ArtifactTerminalCompleted
                    Right () -> ArtifactTerminalRejected
            )
        )
    case resolution of
      ArtifactResolved ArtifactTerminalCompleted -> pure ()
      _ ->
        failTest
          "validated artifact callback did not exclude a cooperative writer"

runtimeProgramLockLifetimeTest :: IO ()
runtimeProgramLockLifetimeTest =
  withTestDirectory $ \workspace -> do
    identity <- testArtifactIdentity
    let installRoot = workspace </> "artifact"
        tryWriter =
          try @IOException
            (withEngineMaterializationLock workspace (\_authority -> pure ()))
    _ <- writeExactArtifactRoot installRoot installRoot "program-locked"

    actionEntered <- newEmptyMVar
    actionResume <- newEmptyMVar
    delayedWriterResult <- newEmptyMVar
    runtimeResult <- newEmptyMVar
    _ <-
      forkFinally
        ( withFirstValidatedEngineArtifact
            identity
            testRuntimeExpectation
            [installRoot]
            ( artifactLauncher
                ( \_launchRequest -> do
                    putMVar actionEntered ()
                    takeMVar actionResume
                    delayedBytes <-
                      unsafeInterleaveIO $ do
                        writerResult <- tryWriter
                        putMVar delayedWriterResult writerResult
                        pure "strict terminal payload"
                    pure
                      ( ArtifactTerminalProcess
                          (ArtifactProcessExited ExitSuccess)
                          ExitSuccess
                          (ByteString8.pack delayedBytes)
                          ByteString.empty
                      )
                )
            )
        )
        (putMVar runtimeResult)
    takeMVar actionEntered
    writerWhileRunning <- tryWriter
    assertWriterRejected
      "writer while the terminal program is running"
      writerWhileRunning
    putMVar actionResume ()
    forcedWriterResult <-
      requireMVar
        "strict terminal payload was not forced under the shared lock"
        delayedWriterResult
    assertWriterRejected
      "writer triggered while forcing the terminal result"
      forcedWriterResult
    completedResult <-
      requireMVar
        "terminal artifact program did not finish"
        runtimeResult
    case completedResult of
      Right
        ( ArtifactResolved
            ( ArtifactTerminalProcess
                (ArtifactProcessExited ExitSuccess)
                ExitSuccess
                stdoutOutput
                stderrOutput
              )
          )
          | stdoutOutput == ByteString8.pack "strict terminal payload",
            ByteString.null stderrOutput ->
              pure ()
      Right _ ->
        failTest "terminal artifact program returned an unexpected result"
      Left failure ->
        failTest
          ( "terminal artifact program failed unexpectedly: "
              <> displayException failure
          )
    assertWriterAccepted
      "writer after a normally reaped terminal program"
      =<< tryWriter

    cancellationEntered <- newEmptyMVar
    cancellationBlock <- newEmptyMVar :: IO (MVar ())
    cancellationResult <- newEmptyMVar
    cancellationThread <-
      forkFinally
        ( withFirstValidatedEngineArtifact
            identity
            testRuntimeExpectation
            [installRoot]
            ( artifactLauncher
                ( \_launchRequest -> do
                    putMVar cancellationEntered ()
                    () <- takeMVar cancellationBlock
                    pure ArtifactTerminalCompleted
                )
            )
        )
        (putMVar cancellationResult)
    takeMVar cancellationEntered
    assertWriterRejected
      "writer while a terminal program awaits cancellation"
      =<< tryWriter
    throwTo cancellationThread ThreadKilled
    cancelledResult <-
      requireMVar
        "cancelled artifact program did not unwind"
        cancellationResult
    case cancelledResult of
      Left failure ->
        assertEqual
          "artifact program cancellation classification"
          (Just ThreadKilled)
          (fromException failure :: Maybe AsyncException)
      Right _ ->
        failTest "cancelled artifact program unexpectedly completed"
    assertWriterAccepted
      "writer after asynchronous cancellation"
      =<< tryWriter
  where
    requireMVar label value = do
      maybeValue <- timeout 2000000 (takeMVar value)
      case maybeValue of
        Just observed -> pure observed
        Nothing -> failTest label

    assertWriterRejected label result =
      case result of
        Left _ -> pure ()
        Right () -> failTest (label <> " acquired the materialization lock")

    assertWriterAccepted label result =
      case result of
        Right () -> pure ()
        Left failure ->
          failTest
            (label <> " failed to acquire the materialization lock: " <> displayException failure)

freshActivationTest :: IO ()
freshActivationTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    _ <- writeExactArtifactRoot installRoot tempRoot "fresh"
    installArtifactRoot installRoot tempRoot
    assertExactPayload "fresh activation" installRoot "fresh"
    assertPathMissing "fresh activation candidate" tempRoot
    assertPathMissing
      "fresh activation rollback root"
      (engineArtifactPreviousRoot installRoot)

smokeBoundDigestTamperTest :: IO ()
smokeBoundDigestTamperTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    candidateManifest <-
      writeExactArtifactRoot installRoot tempRoot "smoked-payload"
    let smokeBoundDigest = manifestDigest candidateManifest
    writeFile (tempRoot </> "payload.txt") "payload-mutated-after-smoke"
    tamperedDigest <- digestEngineArtifactPayload tempRoot
    writeManifest
      tempRoot
      candidateManifest
        { manifestDigest = tamperedDigest,
          manifestMinioObjectKey =
            exactObjectKey
              (manifestSubstrate candidateManifest)
              (manifestArchitecture candidateManifest)
              (manifestAdapterId candidateManifest)
              tamperedDigest
        }
    assertIOException
      "activation authority remains bound to the payload observed by smoke"
      ( installArtifactRootWithExpectedDigest
          installRoot
          tempRoot
          smokeBoundDigest
      )
    assertPathMissing
      "post-smoke tamper does not install the altered candidate"
      installRoot
    assertPathPresent
      "post-smoke tamper leaves the candidate for owned cleanup"
      tempRoot
    assertPathMissing
      "post-smoke tamper creates no rollback residue"
      (engineArtifactPreviousRoot installRoot)

replacementActivationTest :: IO ()
replacementActivationTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    _ <- writeExactArtifactRoot installRoot tempRoot "replacement"
    installArtifactRoot installRoot tempRoot
    assertExactPayload "replacement activation" installRoot "replacement"
    assertPathMissing "replacement candidate" tempRoot
    assertPathMissing
      "replacement rollback root"
      (engineArtifactPreviousRoot installRoot)

idempotentExactRerunTest :: IO ()
idempotentExactRerunTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        observer boundary =
          failTest
            ( "identical exact rerun crossed an activation boundary: "
                <> show boundary
            )
    _ <- writeExactArtifactRoot installRoot installRoot "same"
    _ <- writeExactArtifactRoot installRoot tempRoot "same"
    installArtifactRootWithObserver installRoot tempRoot observer
    assertExactPayload
      "identical rerun preserves the existing exact root"
      installRoot
      "same"
    assertPathMissing "identical rerun candidate" tempRoot
    assertPathMissing
      "identical rerun rollback root"
      (engineArtifactPreviousRoot installRoot)

legacyRootDistinctionTest :: IO ()
legacyRootDistinctionTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        rollbackInstallRoot = workspace </> "rollback-artifact"
        rollbackPreviousRoot =
          engineArtifactPreviousRoot rollbackInstallRoot
        rollbackTempRoot = engineArtifactTempRoot rollbackInstallRoot
    writeLegacyArtifactRoot installRoot installRoot "legacy"
    _ <- writeExactArtifactRoot installRoot tempRoot "uncommitted"
    assertIOException
      "legacy root is not exact before reconciliation"
      (validateEngineArtifactRootAt installRoot installRoot)
    reconcileArtifactRoot installRoot
    assertLegacyPayload
      "legacy root remains an explicit migration root"
      installRoot
      "legacy"
    assertPathMissing "legacy reconciliation discards the candidate" tempRoot
    writeLegacyArtifactRoot
      rollbackInstallRoot
      rollbackPreviousRoot
      "legacy-rollback"
    _ <-
      writeExactArtifactRoot
        rollbackInstallRoot
        rollbackTempRoot
        "uncommitted"
    reconcileArtifactRoot rollbackInstallRoot
    assertLegacyPayload
      "reconciliation restores a legacy rollback root without promoting it to exact"
      rollbackInstallRoot
      "legacy-rollback"
    assertPathMissing
      "legacy rollback reconciliation consumes previous-root residue"
      rollbackPreviousRoot
    assertPathMissing
      "legacy rollback reconciliation discards the candidate"
      rollbackTempRoot

legacyCandidateDowngradeRejectionTest :: IO ()
legacyCandidateDowngradeRejectionTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "exact"
    writeLegacyArtifactRoot installRoot tempRoot "legacy-candidate"
    assertIOException
      "a legacy candidate may not replace an exact root"
      (installArtifactRoot installRoot tempRoot)
    assertExactPayload
      "downgrade rejection preserves the exact root"
      installRoot
      "exact"
    assertLegacyPayloadAt
      "downgrade rejection preserves the rejected candidate"
      installRoot
      tempRoot
      "legacy-candidate"
    assertPathMissing
      "downgrade rejection does not create rollback residue"
      (engineArtifactPreviousRoot installRoot)

legacyPreActivationFailureTest :: IO ()
legacyPreActivationFailureTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    writeLegacyArtifactRoot installRoot installRoot "legacy"
    _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
    writeFile (tempRoot </> "payload.txt") "tampered"
    assertIOException
      "candidate payload mismatch fails before activation"
      (installArtifactRoot installRoot tempRoot)
    assertLegacyPayload
      "pre-activation failure preserves the legacy root"
      installRoot
      "legacy"
    assertPathPresent
      "pre-activation failure preserves the failed candidate for cleanup"
      tempRoot
    assertPathMissing
      "pre-activation failure does not create rollback residue"
      (engineArtifactPreviousRoot installRoot)

legacyMigrationActivationTest :: IO ()
legacyMigrationActivationTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    writeLegacyArtifactRoot installRoot installRoot "legacy"
    _ <- writeExactArtifactRoot installRoot tempRoot "exact"
    installArtifactRoot installRoot tempRoot
    assertExactPayload
      "successful migration installs only the exact candidate"
      installRoot
      "exact"
    assertPathMissing "successful migration candidate" tempRoot
    assertPathMissing
      "successful migration retires the legacy rollback root"
      (engineArtifactPreviousRoot installRoot)

legacyMigrationRollbackTest :: IO ()
legacyMigrationRollbackTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        observer observedBoundary =
          when (observedBoundary == CandidateRootMoved) $
            ioError
              (userError "injected failure after exact candidate activation")
    writeLegacyArtifactRoot installRoot installRoot "legacy"
    _ <- writeExactArtifactRoot installRoot tempRoot "exact"
    assertIOException
      "failure after candidate activation triggers legacy rollback"
      (installArtifactRootWithObserver installRoot tempRoot observer)
    assertLegacyPayload
      "legacy migration rollback restores the predecessor"
      installRoot
      "legacy"
    assertExactPayloadAt
      "legacy migration rollback returns the exact candidate"
      installRoot
      tempRoot
      "exact"
    assertPathMissing
      "legacy migration rollback consumes previous-root residue"
      (engineArtifactPreviousRoot installRoot)

installedValidationSuccessTest :: IO ()
installedValidationSuccessTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        previousRoot = engineArtifactPreviousRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    candidateManifest <-
      writeExactArtifactRoot installRoot tempRoot "candidate"
    installArtifactRootWithInstalledValidation
      installRoot
      tempRoot
      (manifestDigest candidateManifest)
      ( \activatedRoot -> do
          assertEqual
            "installed validation receives the exact final root"
            installRoot
            activatedRoot
          assertExactPayload
            "installed validation observes the activated candidate"
            activatedRoot
            "candidate"
          previousPresent <- doesPathExist previousRoot
          unless previousPresent $
            failTest "installed validation ran after rollback state was retired"
      )
    assertExactPayload
      "successful installed validation commits the candidate"
      installRoot
      "candidate"
    assertPathMissing
      "successful installed validation retires rollback state"
      previousRoot

installedValidationFailureTest :: IO ()
installedValidationFailureTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        previousRoot = engineArtifactPreviousRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    candidateManifest <-
      writeExactArtifactRoot installRoot tempRoot "candidate"
    assertIOException
      "installed validation failure"
      ( installArtifactRootWithInstalledValidation
          installRoot
          tempRoot
          (manifestDigest candidateManifest)
          ( \activatedRoot -> do
              assertExactPayload
                "failed installed validation observes the candidate"
                activatedRoot
                "candidate"
              previousPresent <- doesPathExist previousRoot
              unless previousPresent $
                failTest "failed installed validation has no rollback root"
              ioError (userError "injected installed validation failure")
          )
      )
    assertRolledBackReplacement installRoot tempRoot

installedValidationCancellationTest :: IO ()
installedValidationCancellationTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    candidateManifest <-
      writeExactArtifactRoot installRoot tempRoot "candidate"
    enteredValidation <- newEmptyMVar
    blockValidation <- newEmptyMVar
    finished <- newEmptyMVar
    worker <-
      forkFinally
        ( installArtifactRootWithInstalledValidation
            installRoot
            tempRoot
            (manifestDigest candidateManifest)
            ( \activatedRoot -> do
                assertExactPayload
                  "cancelled installed validation observes the candidate"
                  activatedRoot
                  "candidate"
                putMVar enteredValidation ()
                takeMVar blockValidation
            )
        )
        (putMVar finished)
    requireWithin
      "installed validation did not start"
      (takeMVar enteredValidation)
    throwTo worker ThreadKilled
    result <-
      requireWithin
        "installed validation cancellation did not finish rollback"
        (takeMVar finished)
    case result of
      Right () ->
        failTest "cancelled installed validation unexpectedly succeeded"
      Left failure ->
        assertEqual
          "installed validation preserves cancellation classification"
          (Just ThreadKilled)
          (fromException failure :: Maybe AsyncException)
    assertRolledBackReplacement installRoot tempRoot

activationCleanupFailureReconciliationTest :: IO ()
activationCleanupFailureReconciliationTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        previousRoot = engineArtifactPreviousRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    candidateManifest <-
      writeExactArtifactRoot installRoot tempRoot "candidate"
    assertIOException
      "commit cleanup failure remains primary"
      ( withArtifactWriter installRoot $ \authority ->
          installEngineArtifactRootWithCleanupObserverForTest
            authority
            artifactRootMutatorForTest
            installRoot
            tempRoot
            (manifestDigest candidateManifest)
            ( \case
                BeforeOwnedArtifactRetirement retiredRoot
                  | retiredRoot == previousRoot ->
                      ioError
                        (userError "injected rollback-root retirement failure")
                _ -> pure ()
            )
      )
    assertExactPayload
      "a cleanup failure preserves the committed candidate"
      installRoot
      "candidate"
    assertExactPayloadAt
      "a cleanup failure preserves the complete rollback root"
      installRoot
      previousRoot
      "previous"
    assertPathMissing
      "a cleanup failure leaves no candidate-path ambiguity"
      tempRoot
    reconcileArtifactRoot installRoot
    assertExactPayload
      "reconciliation retains the committed candidate"
      installRoot
      "candidate"
    assertPathMissing
      "reconciliation retires the complete rollback root"
      previousRoot
    assertPathMissing
      "reconciliation leaves no candidate residue"
      tempRoot

synchronousFreshCandidateBoundaryTest :: IO ()
synchronousFreshCandidateBoundaryTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        observer observedBoundary =
          when (observedBoundary == CandidateRootMoved) $
            ioError
              ( userError
                  "injected synchronous failure during fresh activation"
              )
    _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
    assertIOException
      "synchronous failure during fresh activation"
      (installArtifactRootWithObserver installRoot tempRoot observer)
    assertRolledBackFreshActivation installRoot tempRoot

synchronousPreviousBoundaryTest :: IO ()
synchronousPreviousBoundaryTest =
  synchronousBoundaryRollbackTest PreviousRootMoved

synchronousCandidateBoundaryTest :: IO ()
synchronousCandidateBoundaryTest =
  synchronousBoundaryRollbackTest CandidateRootMoved

synchronousBoundaryRollbackTest ::
  ArtifactActivationBoundary ->
  IO ()
synchronousBoundaryRollbackTest targetBoundary =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
        observer observedBoundary =
          when (observedBoundary == targetBoundary) $
            ioError
              ( userError
                  ( "injected synchronous failure at "
                      <> show targetBoundary
                  )
              )
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
    assertIOException
      ("synchronous failure at " <> show targetBoundary)
      (installArtifactRootWithObserver installRoot tempRoot observer)
    assertRolledBackReplacement installRoot tempRoot

asynchronousPreviousBoundaryTest :: IO ()
asynchronousPreviousBoundaryTest =
  asynchronousBoundaryRollbackTest PreviousRootMoved

asynchronousCandidateBoundaryTest :: IO ()
asynchronousCandidateBoundaryTest =
  asynchronousBoundaryRollbackTest CandidateRootMoved

asynchronousFreshCandidateBoundaryTest :: IO ()
asynchronousFreshCandidateBoundaryTest =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
    reachedBoundary <- newEmptyMVar
    blockedObserver <- newEmptyMVar
    finished <- newEmptyMVar
    let observer observedBoundary =
          when (observedBoundary == CandidateRootMoved) $ do
            putMVar reachedBoundary ()
            takeMVar blockedObserver
    worker <-
      forkFinally
        (installArtifactRootWithObserver installRoot tempRoot observer)
        (putMVar finished)
    requireWithin
      "fresh activation did not reach CandidateRootMoved"
      (takeMVar reachedBoundary)
    throwTo worker ThreadKilled
    result <-
      requireWithin
        "fresh activation did not finish cancellation rollback"
        (takeMVar finished)
    assertThreadKilled CandidateRootMoved result
    assertRolledBackFreshActivation installRoot tempRoot

asynchronousBoundaryRollbackTest ::
  ArtifactActivationBoundary ->
  IO ()
asynchronousBoundaryRollbackTest targetBoundary =
  withTestDirectory $ \workspace -> do
    let installRoot = workspace </> "artifact"
        tempRoot = engineArtifactTempRoot installRoot
    _ <- writeExactArtifactRoot installRoot installRoot "previous"
    _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
    reachedBoundary <- newEmptyMVar
    blockedObserver <- newEmptyMVar
    finished <- newEmptyMVar
    let observer observedBoundary =
          when (observedBoundary == targetBoundary) $ do
            putMVar reachedBoundary ()
            takeMVar blockedObserver
    worker <-
      forkFinally
        (installArtifactRootWithObserver installRoot tempRoot observer)
        (putMVar finished)
    requireWithin
      ("worker did not reach " <> show targetBoundary)
      (takeMVar reachedBoundary)
    throwTo worker ThreadKilled
    result <-
      requireWithin
        ("worker did not finish rollback after " <> show targetBoundary)
        (takeMVar finished)
    assertThreadKilled targetBoundary result
    assertRolledBackReplacement installRoot tempRoot

crashReconciliationMatrixTest :: IO ()
crashReconciliationMatrixTest =
  withTestDirectory $ \workspace -> do
    reconcileFinalWins (workspace </> "final-wins")
    reconcilePreviousWins (workspace </> "previous-wins")
    reconcileCandidateWins (workspace </> "candidate-wins")
    reconcilePreviousReplacesInvalidFinal
      (workspace </> "previous-replaces-invalid")
    reconcileFinalCleansInvalidResidue
      (workspace </> "final-cleans-invalid")
    reconcileRemovesInvalidCandidate
      (workspace </> "invalid-candidate")
    reconcileRefusesInvalidPrevious
      (workspace </> "invalid-previous")
    reconcileRefusesInvalidFinal
      (workspace </> "invalid-final")

reconcileFinalWins :: FilePath -> IO ()
reconcileFinalWins installRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
      tempRoot = engineArtifactTempRoot installRoot
  _ <- writeExactArtifactRoot installRoot installRoot "final"
  _ <- writeExactArtifactRoot installRoot previousRoot "previous"
  _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
  reconcileArtifactRoot installRoot
  assertExactPayload "valid final wins reconciliation" installRoot "final"
  assertPathMissing "final-wins previous root" previousRoot
  assertPathMissing "final-wins candidate root" tempRoot

reconcilePreviousWins :: FilePath -> IO ()
reconcilePreviousWins installRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
      tempRoot = engineArtifactTempRoot installRoot
  _ <- writeExactArtifactRoot installRoot previousRoot "previous"
  _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
  reconcileArtifactRoot installRoot
  assertExactPayload
    "previous root wins over an uncommitted candidate"
    installRoot
    "previous"
  assertPathMissing "previous-wins rollback root" previousRoot
  assertPathMissing "previous-wins candidate root" tempRoot

reconcileCandidateWins :: FilePath -> IO ()
reconcileCandidateWins installRoot = do
  let tempRoot = engineArtifactTempRoot installRoot
  _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
  reconcileArtifactRoot installRoot
  assertExactPayload
    "candidate is promoted only without a final or previous root"
    installRoot
    "candidate"
  assertPathMissing "promoted candidate root" tempRoot

reconcilePreviousReplacesInvalidFinal :: FilePath -> IO ()
reconcilePreviousReplacesInvalidFinal installRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
      tempRoot = engineArtifactTempRoot installRoot
  writeInvalidRoot installRoot
  _ <- writeExactArtifactRoot installRoot previousRoot "previous"
  _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
  reconcileArtifactRoot installRoot
  assertExactPayload
    "valid previous replaces an invalid final"
    installRoot
    "previous"
  assertPathMissing "restored previous root" previousRoot
  assertPathMissing "discarded candidate after previous restore" tempRoot

reconcileFinalCleansInvalidResidue :: FilePath -> IO ()
reconcileFinalCleansInvalidResidue installRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
      tempRoot = engineArtifactTempRoot installRoot
  _ <- writeExactArtifactRoot installRoot installRoot "final"
  writeInvalidRoot previousRoot
  writeInvalidRoot tempRoot
  reconcileArtifactRoot installRoot
  assertExactPayload
    "valid final survives invalid crash residue"
    installRoot
    "final"
  assertPathMissing "invalid previous residue" previousRoot
  assertPathMissing "invalid candidate residue" tempRoot

reconcileRemovesInvalidCandidate :: FilePath -> IO ()
reconcileRemovesInvalidCandidate installRoot = do
  let tempRoot = engineArtifactTempRoot installRoot
  writeInvalidRoot tempRoot
  reconcileArtifactRoot installRoot
  assertPathMissing "invalid candidate without recovery evidence" tempRoot
  assertPathMissing "invalid candidate does not become final" installRoot

reconcileRefusesInvalidPrevious :: FilePath -> IO ()
reconcileRefusesInvalidPrevious installRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
      tempRoot = engineArtifactTempRoot installRoot
  writeInvalidRoot previousRoot
  _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
  assertIOException
    "invalid previous blocks candidate promotion"
    (reconcileArtifactRoot installRoot)
  assertPathMissing "invalid previous leaves final absent" installRoot
  assertPathPresent "invalid previous is preserved for diagnosis" previousRoot
  assertExactPayloadAt
    "candidate is preserved when previous recovery is ambiguous"
    installRoot
    tempRoot
    "candidate"

reconcileRefusesInvalidFinal :: FilePath -> IO ()
reconcileRefusesInvalidFinal installRoot = do
  let tempRoot = engineArtifactTempRoot installRoot
  writeInvalidRoot installRoot
  _ <- writeExactArtifactRoot installRoot tempRoot "candidate"
  assertIOException
    "invalid final without rollback proof blocks candidate promotion"
    (reconcileArtifactRoot installRoot)
  assertPathPresent "invalid final is preserved for diagnosis" installRoot
  assertExactPayloadAt
    "candidate is preserved when final recovery is ambiguous"
    installRoot
    tempRoot
    "candidate"

assertRolledBackReplacement :: FilePath -> FilePath -> IO ()
assertRolledBackReplacement installRoot tempRoot = do
  assertExactPayload "rollback restores the previous final" installRoot "previous"
  assertExactPayloadAt
    "rollback returns the complete candidate to its temporary root"
    installRoot
    tempRoot
    "candidate"
  assertPathMissing
    "rollback leaves no previous-root residue"
    (engineArtifactPreviousRoot installRoot)

assertRolledBackFreshActivation :: FilePath -> FilePath -> IO ()
assertRolledBackFreshActivation installRoot tempRoot = do
  assertPathMissing
    "failed fresh activation leaves no final root"
    installRoot
  assertExactPayloadAt
    "failed fresh activation returns the candidate to its temporary root"
    installRoot
    tempRoot
    "candidate"
  assertPathMissing
    "failed fresh activation leaves no previous root"
    (engineArtifactPreviousRoot installRoot)

assertThreadKilled ::
  ArtifactActivationBoundary ->
  Either SomeException () ->
  IO ()
assertThreadKilled targetBoundary result =
  case result of
    Right () ->
      failTest
        ( "cancellation at "
            <> show targetBoundary
            <> " unexpectedly succeeded"
        )
    Left failure ->
      assertEqual
        ("cancellation classification at " <> show targetBoundary)
        (Just ThreadKilled)
        (fromException failure :: Maybe AsyncException)

withArtifactWriter ::
  FilePath ->
  (forall w. MaterializationAuthority w -> IO result) ->
  IO result
withArtifactWriter installRoot =
  withEngineMaterializationLock (takeDirectory installRoot)

installArtifactRoot :: FilePath -> FilePath -> IO ()
installArtifactRoot installRoot tempRoot =
  withArtifactWriter installRoot $ \authority ->
    installEngineArtifactRoot
      authority
      artifactRootMutatorForTest
      installRoot
      tempRoot

installArtifactRootWithExpectedDigest ::
  FilePath ->
  FilePath ->
  Text ->
  IO ()
installArtifactRootWithExpectedDigest installRoot tempRoot expectedDigest =
  withArtifactWriter installRoot $ \authority ->
    installEngineArtifactRootWithExpectedDigest
      authority
      artifactRootMutatorForTest
      installRoot
      tempRoot
      expectedDigest

installArtifactRootWithInstalledValidation ::
  FilePath ->
  FilePath ->
  Text ->
  (FilePath -> IO ()) ->
  IO ()
installArtifactRootWithInstalledValidation
  installRoot
  tempRoot
  expectedDigest
  validateInstalled =
    withArtifactWriter installRoot $ \authority ->
      installEngineArtifactRootWithPendingActionForTest
        authority
        artifactRootMutatorForTest
        installRoot
        tempRoot
        expectedDigest
        (validateInstalled installRoot)

installArtifactRootWithObserver ::
  FilePath ->
  FilePath ->
  (ArtifactActivationBoundary -> IO ()) ->
  IO ()
installArtifactRootWithObserver installRoot tempRoot observer =
  withArtifactWriter installRoot $ \authority ->
    installEngineArtifactRootWithObserverForTest
      authority
      artifactRootMutatorForTest
      installRoot
      tempRoot
      observer

reconcileArtifactRoot :: FilePath -> IO ()
reconcileArtifactRoot installRoot =
  withArtifactWriter installRoot $ \authority ->
    reconcileEngineArtifactRoot
      authority
      artifactRootMutatorForTest
      installRoot

writeExactArtifactRoot ::
  FilePath ->
  FilePath ->
  String ->
  IO EngineArtifactManifest
writeExactArtifactRoot expectedInstallRoot actualRoot payload = do
  let binRoot = actualRoot </> "native" </> "bin"
      entrypointPath = binRoot </> "llama-completion"
  createDirectoryIfMissing True binRoot
  writeFile entrypointPath "#!/bin/sh\nexit 0\n"
  permissions <- getPermissions entrypointPath
  setPermissions entrypointPath (setOwnerExecutable True permissions)
  writeFile (actualRoot </> "payload.txt") payload
  writeTestAppleRuntimeLayout expectedInstallRoot actualRoot
  digest <- digestEngineArtifactPayload actualRoot
  let manifest = testManifest expectedInstallRoot digest
  writeManifest actualRoot manifest
  _ <- validateEngineArtifactRootAt expectedInstallRoot actualRoot
  identity <- testArtifactIdentity
  mintExactGenerationSidecar identity expectedInstallRoot manifest
  pure manifest

-- | Every exact artifact root production creates has its generation lease
-- sidecar minted by the activation transaction, and runtime resolution now
-- requires that sidecar before it will execute the generation. A fixture root
-- must therefore mint it the same way, or it models a generation no writer ever
-- produced.
mintExactGenerationSidecar ::
  NativeArtifactIdentity ->
  FilePath ->
  EngineArtifactManifest ->
  IO ()
mintExactGenerationSidecar identity expectedInstallRoot manifest = do
  lease <-
    either
      (failTest . ("test generation lease: " <>))
      pure
      ( artifactGenerationLease
          enginesRoot
          identity
          (manifestGenerationFingerprint manifest)
          (manifestDigest manifest)
      )
  withEngineMaterializationLock
    enginesRoot
    (`createGenerationSidecar` lease)
  where
    enginesRoot = takeDirectory expectedInstallRoot

writeLegacyArtifactRoot ::
  FilePath ->
  FilePath ->
  String ->
  IO ()
writeLegacyArtifactRoot expectedInstallRoot actualRoot payload = do
  let binRoot = actualRoot </> "native" </> "bin"
      entrypointPath = binRoot </> "llama-completion"
  createDirectoryIfMissing True binRoot
  writeFile entrypointPath "#!/bin/sh\nexit 0\n"
  permissions <- getPermissions entrypointPath
  setPermissions entrypointPath (setOwnerExecutable True permissions)
  writeFile (actualRoot </> "payload.txt") payload
  writeTestAppleRuntimeLayout expectedInstallRoot actualRoot
  let legacyManifest =
        (testManifest expectedInstallRoot "")
          { manifestResolvedProvenance = []
          }
      manifest =
        legacyManifest
          { manifestDigest = legacyDeclarativeTestDigest legacyManifest,
            manifestGenerationFingerprint = ""
          }
  writeManifest actualRoot manifest

writeTestAppleRuntimeLayout :: FilePath -> FilePath -> IO ()
writeTestAppleRuntimeLayout installRoot actualRoot = do
  let pythonHome = actualRoot </> "python-home"
      frameworkRoot =
        actualRoot </> "python-frameworks" </> "Python.framework"
      venvRoot = actualRoot </> "venv"
      pythonPath = venvRoot </> "bin" </> "infernix-python"
  createDirectoryIfMissing True pythonHome
  createDirectoryIfMissing True frameworkRoot
  createDirectoryIfMissing True (actualRoot </> "native" </> "lib")
  createDirectoryIfMissing True (actualRoot </> "native" </> "libexec")
  createDirectoryIfMissing True (venvRoot </> "bin")
  writeFile pythonPath "#!/bin/sh\nexit 0\n"
  pythonPermissions <- getPermissions pythonPath
  setPermissions pythonPath (setOwnerExecutable True pythonPermissions)
  writeFile
    (venvRoot </> "pyvenv.cfg")
    ( "home = "
        <> installRoot
        <> "/python-home\nbase-prefix = "
        <> installRoot
        <> "/python-home\nbase-exec-prefix = "
        <> installRoot
        <> "/python-home\n"
    )

legacyDeclarativeTestDigest :: EngineArtifactManifest -> Text
legacyDeclarativeTestDigest manifest =
  let digestInput =
        Text.intercalate
          "\n"
          [ manifestAdapterId manifest,
            manifestEngineName manifest,
            manifestArtifactKind manifest,
            manifestSourceRef manifest,
            manifestEngineVersion manifest,
            manifestRuntimeVersion manifest,
            manifestRecipeFingerprint manifest,
            manifestTargetContractFingerprint manifest,
            maybe
              "installed-target"
              (const "image-target")
              (manifestImageTargetEvidence manifest)
          ]
      digest =
        SHA256.hashlazy
          (LazyByteString.fromStrict (TextEncoding.encodeUtf8 digestInput))
   in "sha256:" <> TextEncoding.decodeUtf8 (Base16.encode digest)

testManifest :: FilePath -> Text -> EngineArtifactManifest
testManifest installRoot digest =
  EngineArtifactManifest
    { manifestAdapterId = "llama-cpp-cli",
      manifestEngineName = "Artifact Transaction Test",
      manifestSubstrate = "apple-silicon",
      manifestArchitecture = "arm64",
      manifestArtifactKind = "test-payload",
      manifestSourceRef = "infernix://test/artifact-transaction",
      manifestEngineVersion = "1",
      manifestPythonVersion = Nothing,
      manifestRuntimeVersion = "test-runtime-1",
      manifestResolvedProvenance =
        [ ResolvedArtifactProvenance
            { resolvedProvenanceName = "fixture",
              resolvedProvenanceVersion = "1",
              resolvedProvenanceSource = "infernix://test/fixture"
            }
        ],
      manifestRecipeFingerprint = testArtifactRecipeFingerprint,
      manifestDigest = digest,
      manifestGenerationFingerprint = digest,
      manifestMinioObjectKey =
        exactObjectKey
          "apple-silicon"
          "arm64"
          "llama-cpp-cli"
          digest,
      manifestLocalInstallRoot = installRoot,
      manifestTargetContractFingerprint =
        testTargetFingerprintFor
          testIdentity
          "apple-silicon"
          "arm64",
      manifestImageTargetEvidence = Nothing
    }
  where
    testIdentity =
      case parseNativeArtifactIdentity "llama-cpp-cli" of
        Just identity -> identity
        Nothing -> error "closed native artifact catalog omitted llama-cpp-cli"

exactObjectKey :: Text -> Text -> Text -> Text -> Text
exactObjectKey substrate architecture adapterId digest =
  Text.intercalate
    "/"
    [ "engine-artifacts",
      if substrate == "linux-native" then "linux" else substrate,
      architecture,
      adapterId,
      fromMaybeDigest digest <> ".tar.zst"
    ]
  where
    fromMaybeDigest value =
      fromMaybe value (Text.stripPrefix "sha256:" value)

refreshExactManifest ::
  FilePath ->
  EngineArtifactManifest ->
  IO EngineArtifactManifest
refreshExactManifest root manifest = do
  digest <- digestEngineArtifactPayload root
  let refreshedManifest =
        manifest
          { manifestDigest = digest,
            manifestGenerationFingerprint = digest,
            manifestMinioObjectKey =
              exactObjectKey
                (manifestSubstrate manifest)
                (manifestArchitecture manifest)
                (manifestAdapterId manifest)
                digest
          }
  writeManifest root refreshedManifest
  _ <- validateEngineArtifactRootAt root root
  -- A refreshed payload is a different generation, so it needs its own sidecar
  -- exactly as the first one did.
  identity <- testArtifactIdentity
  mintExactGenerationSidecar identity root refreshedManifest
  pure refreshedManifest

testArtifactIdentity :: IO NativeArtifactIdentity
testArtifactIdentity =
  maybe
    (failTest "closed native artifact catalog omitted llama-cpp-cli")
    pure
    (parseNativeArtifactIdentity "llama-cpp-cli")

testRuntimeExpectation :: ArtifactRuntimeExpectation
testRuntimeExpectation =
  appleArtifactRuntimeExpectation

testArtifactRecipeFingerprint :: Text
testArtifactRecipeFingerprint =
  testRecipeFingerprintFor
    testIdentity
    testRuntimeExpectation
  where
    testIdentity =
      case parseNativeArtifactIdentity "llama-cpp-cli" of
        Just identity -> identity
        Nothing -> error "closed native artifact catalog omitted llama-cpp-cli"

testRecipeFingerprintFor ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  Text
testRecipeFingerprintFor identity expectation =
  case currentArtifactRecipeFingerprint identity expectation of
    Right fingerprint -> fingerprint
    Left failure -> error failure

testTargetFingerprintFor ::
  NativeArtifactIdentity ->
  Text ->
  Text ->
  Text
testTargetFingerprintFor identity substrate architecture =
  case nativeArtifactTarget identity substrate architecture of
    Right target -> nativeArtifactTargetFingerprint target
    Left failure -> error failure

completedArtifactLauncher :: ArtifactLauncher
completedArtifactLauncher =
  artifactLauncher (const (pure ArtifactTerminalCompleted))

assertArtifactRejected ::
  String ->
  FilePath ->
  ArtifactResolution value ->
  IO ()
assertArtifactRejected label expectedRoot resolution =
  case resolution of
    ArtifactRejected rejectedRoot _failure ->
      assertEqual (label <> " root") expectedRoot rejectedRoot
    _ ->
      failTest (label <> ": expected ArtifactRejected")

writeManifest :: FilePath -> EngineArtifactManifest -> IO ()
writeManifest root manifest =
  LazyByteString.writeFile
    (engineArtifactManifestPath root)
    (renderEngineArtifactManifest manifest)

writeInvalidRoot :: FilePath -> IO ()
writeInvalidRoot root = do
  createDirectoryIfMissing True root
  writeFile (root </> "incomplete") "not a complete artifact"

assertExactPayload :: String -> FilePath -> String -> IO ()
assertExactPayload label root =
  assertExactPayloadAt label root root

assertLegacyPayload :: String -> FilePath -> String -> IO ()
assertLegacyPayload label root =
  assertLegacyPayloadAt label root root

assertLegacyPayloadAt ::
  String ->
  FilePath ->
  FilePath ->
  String ->
  IO ()
assertLegacyPayloadAt label expectedInstallRoot actualRoot expectedPayload = do
  assertIOException
    (label <> " exact-identity rejection")
    (validateEngineArtifactRootAt expectedInstallRoot actualRoot)
  manifestBytes <-
    LazyByteString.readFile (engineArtifactManifestPath actualRoot)
  manifest <-
    either
      (failTest . ((label <> " invalid manifest: ") <>))
      pure
      (decodeEngineArtifactManifest manifestBytes)
  assertEqual
    (label <> " has no resolved provenance")
    []
    (manifestResolvedProvenance manifest)
  assertEqual
    (label <> " retains its declarative digest")
    (legacyDeclarativeTestDigest manifest)
    (manifestDigest manifest)
  observedPayload <- readFile (actualRoot </> "payload.txt")
  assertEqual label expectedPayload observedPayload

assertExactPayloadAt ::
  String ->
  FilePath ->
  FilePath ->
  String ->
  IO ()
assertExactPayloadAt label expectedInstallRoot actualRoot expectedPayload = do
  _ <- validateEngineArtifactRootAt expectedInstallRoot actualRoot
  observedPayload <- readFile (actualRoot </> "payload.txt")
  assertEqual label expectedPayload observedPayload

assertIOException :: String -> IO value -> IO ()
assertIOException label action = do
  result <- try @IOException action
  case result of
    Left _ -> pure ()
    Right _ -> failTest (label <> ": expected IOException")

assertEqual ::
  (Eq value, Show value) =>
  String ->
  value ->
  value ->
  IO ()
assertEqual label expected actual =
  unless (actual == expected) $
    failTest
      ( label
          <> ": expected "
          <> show expected
          <> ", observed "
          <> show actual
      )

assertNotEqual ::
  (Eq value, Show value) =>
  String ->
  value ->
  value ->
  IO ()
assertNotEqual label first second =
  when (first == second) $
    failTest
      ( label
          <> ": both values were "
          <> show first
      )

assertPathMissing :: String -> FilePath -> IO ()
assertPathMissing label path = do
  present <- doesPathExist path
  when present $
    failTest (label <> ": path still exists: " <> path)

assertPathPresent :: String -> FilePath -> IO ()
assertPathPresent label path = do
  present <- doesPathExist path
  unless present $
    failTest (label <> ": path is absent: " <> path)

requireWithin :: String -> IO value -> IO value
requireWithin label action = do
  result <- timeout 10_000_000 action
  case result of
    Nothing -> failTest label
    Just value -> pure value

withTestDirectory :: (FilePath -> IO value) -> IO value
withTestDirectory =
  bracket createTestDirectory removePathForcibly

createTestDirectory :: IO FilePath
createTestDirectory = do
  temporaryRoot <- getTemporaryDirectory
  (temporaryPath, handle) <-
    openTempFile temporaryRoot "infernix-artifact-transaction-"
  hClose handle
  removeFile temporaryPath
  createDirectory temporaryPath
  pure temporaryPath

failTest :: String -> IO value
failTest = ioError . userError
