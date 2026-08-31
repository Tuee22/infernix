module Main (main) where

import Control.Exception (SomeException, bracket, displayException, try)
import Control.Monad (unless, when)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Char (isSpace)
import Data.List (isInfixOf, isPrefixOf, sort)
import Data.Text.IO.Utf8 qualified as Text.Utf8
import GHC.RTS.Flags qualified as RTSFlags
import Infernix.BuildMemory
  ( ToolchainTestSuite (UnitSuite),
    allToolchainTestSuites,
    toolchainTestSuiteName,
  )
import Infernix.Config (Paths (..), discoverPathsWithHostManifest)
import Infernix.Lint.Docs
  ( governedSuiteFileTypeViolations,
    mirrorRuleDivergenceViolations,
    prohibitedStatusMarkerForTest,
    prohibitedStatusSectionForTest,
    retiredDoctrineViolationsForTest,
  )
import Infernix.Lint.HaskellStyle
  ( appleArtifactProvisioningViolations,
    appleClosureFixtureOwnershipViolations,
    appleMaterializationTransactionOwnershipViolations,
    artifactCapabilityBoundaryViolations,
    artifactWriterBoundaryViolations,
    boundedEngineOutputViolations,
    cappedEngineBoundaryViolations,
    isGeneratedHaskellProtoSource,
    linuxNativeMaterializationBoundaryViolations,
    nativeArtifactInvocationKernelOwnershipViolations,
    provisioningKernelOwnershipViolations,
    runHaskellStyleLintWith,
  )
import Infernix.Lint.Proto
  ( generatedHaskellProtoFiles,
    generatedHaskellProtoTreeViolations,
    protoSnapshotManifestViolations,
  )
import Language.Haskell.HLint qualified as HLint
import Ormolu qualified
import System.Directory
  ( createDirectory,
    getTemporaryDirectory,
    removeFile,
    removePathForcibly,
  )
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)

main :: IO ()
main = do
  assertRetiredDoctrineBoundary
  assertGovernedSuiteFileTypes
  assertMirrorRuleAgreement
  assertAppleArtifactProvisioningBoundary
  assertAppleClosureFixtureOwnership
  assertAppleMaterializationTransactionOwnership
  assertArtifactCapabilityBoundary
  assertArtifactWriterBoundary
  assertBoundedEngineOutput
  assertCappedEngineBoundary
  assertGeneratedProtoStyleExclusion
  assertProtoSnapshotDriftGate
  assertInProcessHaskellStyleBehavior
  assertComponentRtsClosure
  assertStyleRuntimeHeapCap
  assertLinuxNativeMaterializationBoundary
  assertNativeArtifactInvocationKernelOwnership
  assertProvisioningKernelOwnership
  runHaskellStyleLintWith checkOrmoluFormatting checkHLintHints

-- | The governed suite holds documentation only.
--
-- The negative half is the point: the exact path that sat in the suite
-- unreferenced must be rejected, because the coverage guard beside this one
-- lists @.md@ files and so could never see it.
assertGovernedSuiteFileTypes :: IO ()
assertGovernedSuiteFileTypes =
  unless
    ( not (null (governedSuiteFileTypeViolations ["documents/engineering/crash_harness.py"]))
        && not (null (governedSuiteFileTypeViolations ["documents/research/measure.sh"]))
        && null
          ( governedSuiteFileTypeViolations
              [ "documents/README.md",
                "documents/architecture/overview.md",
                "documents/engineering/testing.md"
              ]
          )
    )
    (ioError (userError "governed-suite file-type check does not reject a non-Markdown file under documents/"))

-- | The two entry-document mirrors agree.
--
-- The negative half uses the shape the divergence actually takes: one mirror
-- gains a rule, which reads as absent to whoever loads the other.
assertMirrorRuleAgreement :: IO ()
assertMirrorRuleAgreement =
  unless
    ( null (mirrorRuleDivergenceViolations mirrorFixture mirrorFixture)
        && not (null (mirrorRuleDivergenceViolations mirrorFixture divergentMirrorFixture))
        && not (null (mirrorRuleDivergenceViolations mirrorFixture alteredMirrorFixture))
    )
    (ioError (userError "mirror-rule check does not reject a rule present or altered in only one entry document"))
  where
    mirrorFixture =
      unlines
        [ "# AGENTS.md",
          "## Non-Negotiable Rules",
          "- never run `git add`",
          "- zero version-controlled `.dhall`",
          "## Scope"
        ]
    divergentMirrorFixture =
      unlines
        [ "# CLAUDE.md",
          "## Non-Negotiable Rules",
          "- never run `git add`",
          "- zero version-controlled `.dhall`",
          "- no repo-owned native implementation source",
          "## Scope"
        ]
    alteredMirrorFixture =
      unlines
        [ "# CLAUDE.md",
          "## Non-Negotiable Rules",
          "- never run `git add`",
          "- some version-controlled `.dhall` is permitted",
          "## Scope"
        ]

assertRetiredDoctrineBoundary :: IO ()
assertRetiredDoctrineBoundary = do
  unless
    ( prohibitedStatusMarkerForTest "README.md" "## Current Audit Note"
        && prohibitedStatusMarkerForTest "README.md" "### current status"
        && prohibitedStatusMarkerForTest "README.md" "  ### current audit"
        && prohibitedStatusMarkerForTest "README.md" "  ## Repository Status"
        && prohibitedStatusMarkerForTest "documents/development/python_policy.md" "Current state:"
        && not (prohibitedStatusMarkerForTest "README.md" "Current state:")
        && not (prohibitedStatusMarkerForTest "README.md" "## Runtime State")
        && not (prohibitedStatusMarkerForTest "README.md" "## Current State Machine")
        && not
          ( prohibitedStatusMarkerForTest
              "README.md"
              "The current state: pending until eligible engine"
          )
        && not
          ( prohibitedStatusSectionForTest
              "README.md"
              "```markdown\n## Current Status\n```"
          )
    )
    (fail "docs-lint fixture did not preserve the narrow status-heading boundary")
  mapM_
    assertRejected
    [ ( "README.md",
        "The local Kind cluster is the mandatory HA service topology.",
        "mandatory HA service topology"
      ),
      ( "documents/engineering/object_storage.md",
        "**Exactly-once semantics** come from the surviving coordinator replica.",
        "**Exactly-once semantics** come from"
      ),
      ( "documents/operations/cluster_bootstrap_runbook.md",
        "Run Patroni replica reinitialization after the leader changes.",
        "Patroni replica reinitialization"
      ),
      ( "documents/architecture/daemon_topology.md",
        "Pulsar `Failover` provides leader election for repository coordinator replicas.",
        "Pulsar `Failover` provides leader election"
      ),
      ( "documents/development/demo_app_test_plan.md",
        "The integration covers durable dispatcher, engine pod replacement, engine node drain.",
        "engine node drain"
      ),
      ( "documents/architecture/daemon_topology.md",
        "Phase\n4 owns the future SPA-style flow.",
        "Phase 4"
      )
    ]
  let accepted =
        concat
          [ retiredDoctrineViolationsForTest
              "documents/tools/pulsar.md"
              "Pulsar `Failover` provides broker-managed single-active subscription coordination; a pending request remains eligible for redelivery.",
            retiredDoctrineViolationsForTest
              "documents/architecture/daemon_topology.md"
              "Shared members on multiple machines leave an interrupted request pending for redelivery.",
            retiredDoctrineViolationsForTest
              "documents/architecture/managed_state_transitions.md"
              "Managed engine node drain reconciliation preserves the lifecycle lease.",
            retiredDoctrineViolationsForTest
              "documents/engineering/k8s_storage.md"
              "A single-instance chart expresses replica sizing as one replica per role and restarts the process after loss.",
            retiredDoctrineViolationsForTest
              "documents/tools/pulsar.md"
              "A broker-managed Failover handoff may select another consumer.",
            retiredDoctrineViolationsForTest
              "documents/architecture/pulsar_ml_workflow.md"
              "data Phase = Prepared | Published",
            retiredDoctrineViolationsForTest
              "documents/architecture/runtime_modes.md"
              "The domain value `Phase 1` is not schedule provenance.",
            retiredDoctrineViolationsForTest
              "documents/architecture/runtime_modes.md"
              "```text\nPhase 4 owns no schedule here.\n```"
          ]
  unless
    (null accepted)
    ( fail
        ( "docs-lint fixture rejected broker Failover/runtime-state doctrine: "
            <> show accepted
        )
    )
  where
    assertRejected (relativePath, fixture, expectedMatch) =
      unless
        ( any
            (expectedMatch `isInfixOf`)
            (retiredDoctrineViolationsForTest relativePath fixture)
        )
        ( fail
            ( "docs-lint fixture did not reject retired doctrine in "
                <> relativePath
                <> ": "
                <> expectedMatch
            )
        )

-- | Reproduce @ormolu --mode check@ in-process. The Cabal and @.ormolu@
-- refinement steps are part of the formatter's CLI semantics: using only
-- 'Ormolu.defaultConfig' would silently omit component extensions,
-- dependencies, fixities, and module re-exports.
checkOrmoluFormatting :: [FilePath] -> IO ()
checkOrmoluFormatting sourceFiles = do
  violations <- concat <$> mapM checkSource sourceFiles
  unless
    (null violations)
    (fail ("haskell-style-check: Ormolu formatting differs:\n" <> unlines violations))
  where
    checkSource sourceFile = do
      cabalSearchResult <- Ormolu.getCabalInfoForSourceFile sourceFile
      let cabalInfo = case cabalSearchResult of
            Ormolu.CabalNotFound -> Nothing
            Ormolu.CabalDidNotMention info -> Just info
            Ormolu.CabalFound info -> Just info
      (dotFixities, dotModuleReexports) <-
        Ormolu.getDotOrmoluForSourceFile sourceFile
      let rawConfig = Ormolu.defaultConfig
          config =
            Ormolu.refineConfig
              (Ormolu.detectSourceType sourceFile)
              cabalInfo
              (Just (Ormolu.cfgFixityOverrides rawConfig))
              (Just (Ormolu.cfgModuleReexports rawConfig))
              rawConfig
                { Ormolu.cfgFixityOverrides = dotFixities,
                  Ormolu.cfgModuleReexports = dotModuleReexports
                }
      original <- Text.Utf8.readFile sourceFile
      formatted <- Ormolu.ormolu config sourceFile original
      pure [sourceFile | formatted /= original]

-- | The executable shipped by HLint is this API call followed by a non-empty
-- result check, so the in-process form preserves its findings and diagnostics.
checkHLintHints :: [FilePath] -> IO ()
checkHLintHints sourceFiles = do
  ideas <- HLint.hlint sourceFiles
  failOnHLintIdeas ideas

failOnHLintIdeas :: [HLint.Idea] -> IO ()
failOnHLintIdeas ideas =
  unless
    (null ideas)
    ( fail
        ( "haskell-style-check: HLint reported findings:\n"
            <> unlines (map show ideas)
        )
    )

-- | Exercise both in-process callbacks against deliberately bad inputs. These
-- fixtures guard behavior, not merely the absence of the retired child process
-- strings.
assertInProcessHaskellStyleBehavior :: IO ()
assertInProcessHaskellStyleBehavior =
  withStyleFixtureDirectory $ \fixtureRoot -> do
    let unformattedSource = fixtureRoot </> "Unformatted.hs"
        hintedSource = fixtureRoot </> "Hinted.hs"
    writeFile
      unformattedSource
      "module Unformatted where\n\nfixtureValue=1\n"
    assertActionFailsWith
      "deliberately unformatted Haskell"
      "Ormolu formatting differs"
      (checkOrmoluFormatting [unformattedSource])

    writeFile
      hintedSource
      ( unlines
          [ "module Hinted where",
            "",
            "fixtureValue :: Eq value => value -> value -> Bool",
            "fixtureValue left right = not (left == right)"
          ]
      )
    ideas <- HLint.hlint ["--quiet", hintedSource]
    unless
      (length ideas == 1)
      (fail "haskell-style-check: the focused HLint fixture must produce exactly one idea")
    assertActionFailsWith
      "one HLint hint"
      "HLint reported findings"
      (failOnHLintIdeas ideas)

assertActionFailsWith :: String -> String -> IO () -> IO ()
assertActionFailsWith fixtureLabel expectedMessage action = do
  outcome <- try action
  case outcome :: Either SomeException () of
    Left failure ->
      unless
        (expectedMessage `isInfixOf` displayException failure)
        ( fail
            ( "haskell-style-check: "
                <> fixtureLabel
                <> " failed with the wrong diagnostic: "
                <> displayException failure
            )
        )
    Right () ->
      fail
        ( "haskell-style-check: "
            <> fixtureLabel
            <> " unexpectedly passed"
        )

withStyleFixtureDirectory :: (FilePath -> IO result) -> IO result
withStyleFixtureDirectory =
  bracket createStyleFixtureDirectory removePathForcibly

createStyleFixtureDirectory :: IO FilePath
createStyleFixtureDirectory = do
  temporaryRoot <- getTemporaryDirectory
  (temporaryPath, handle) <-
    openTempFile temporaryRoot "infernix-haskell-style-"
  hClose handle
  removeFile temporaryPath
  createDirectory temporaryPath
  pure temporaryPath

-- | Pin the per-component RTS contract in the Cabal source. The live style
-- assertion below independently proves that this component actually entered
-- with the baked heap cap.
assertComponentRtsClosure :: IO ()
assertComponentRtsClosure = do
  paths <- discoverPathsWithHostManifest Nothing
  cabalSource <- readFile (repoRoot paths </> "infernix.cabal")
  projectSource <- readFile (repoRoot paths </> "cabal.project")
  cabalFormatSource <-
    readFile
      ( repoRoot paths
          </> "test"
          </> "cabal-format"
          </> "infernix-cabal-format.cabal"
      )
  cabalFormatProjectSource <-
    readFile (repoRoot paths </> "test" </> "cabal-format" </> "cabal.project")
  let declaredSuiteNames = sort (topLevelTestSuiteNames cabalSource)
      closedSuiteNames = sort (map toolchainTestSuiteName allToolchainTestSuites)
  unless
    (declaredSuiteNames == closedSuiteNames)
    ( fail
        ( "haskell-style-check: Cabal test-suite inventory differs from the closed toolchain vocabulary: "
            <> show declaredSuiteNames
            <> " /= "
            <> show closedSuiteNames
        )
    )
  unless
    (topLevelTestSuiteNames cabalFormatSource == ["infernix-cabal-format"])
    (fail "haskell-style-check: the solver-isolated package must declare exactly the Cabal-format suite")
  unless
    ( "packages: test/cabal-format/infernix-cabal-format.cabal"
        `elem` lines cabalFormatProjectSource
        && length
          ( filter
              ("packages:" `isPrefixOf`)
              (lines cabalFormatProjectSource)
          )
          == 1
        && not ("infernix.cabal" `isInfixOf` cabalFormatProjectSource)
    )
    ( fail
        "haskell-style-check: the Cabal-format project must contain only its repository-root-relative solver-isolated package"
    )
  let cabalFormatComponent =
        componentBody cabalFormatSource "test-suite infernix-cabal-format"
  unless
    ( "Cabal ==3.16.1.0" `isInfixOf` cabalFormatComponent
        && not ("infernix" `isInfixOf` cabalFormatComponent)
    )
    (fail "haskell-style-check: the Cabal-format suite must pin Cabal 3.16 without depending on infernix")
  -- Sprint 1.30: the shipped image's reservation is sized for the host reserve
  -- its daemons run in, not for a toolchain control slot. It is address space
  -- rather than resident memory, and it is also the only thing bounding this
  -- image's heap growth, so a slot-sized value gave the host inference daemon a
  -- ceiling the ledger says it does not carry.
  assertComponentOption
    cabalSource
    "executable infernix"
    "-rtsopts=ignoreAll -with-rtsopts=-xr16384M"
  assertComponentOption
    cabalSource
    "test-suite infernix-unit"
    "-rtsopts -with-rtsopts=-M1024M"
  when
    ( "-rtsopts=ignoreAll"
        `isInfixOf` componentBody cabalSource "test-suite infernix-unit"
    )
    (fail "haskell-style-check: the unit component must retain its intentional -rtsopts surface")
  mapM_
    ( \suite ->
        assertComponentOption
          cabalSource
          ("test-suite " <> toolchainTestSuiteName suite)
          "-rtsopts=ignoreAll -with-rtsopts=-M1024M"
    )
    (filter (/= UnitSuite) allToolchainTestSuites)
  assertComponentOption
    cabalFormatSource
    "test-suite infernix-cabal-format"
    "-rtsopts=ignoreAll -with-rtsopts=-M1024M"
  unless
    ( all
        (`isInfixOf` cabalFormatProjectSource)
        [ "write-ghc-environment-files: never",
          "with-compiler: ghc-9.12.4",
          "jobs: 1",
          "ghc-options: +RTS -M4096M -xr12288M -RTS"
        ]
    )
    (fail "haskell-style-check: the Cabal-format project is missing its bounded fallback account")
  when
    ("-rtsopts" `isInfixOf` projectSource)
    (fail "haskell-style-check: cabal.project must not inject a global RTS-options surface")

topLevelTestSuiteNames :: String -> [String]
topLevelTestSuiteNames cabalSource =
  [ drop (length testSuitePrefix) sourceLine
  | sourceLine <- lines cabalSource,
    testSuitePrefix `isPrefixOf` sourceLine
  ]
  where
    testSuitePrefix = "test-suite "

assertComponentOption :: String -> String -> String -> IO ()
assertComponentOption cabalSource componentName requiredOption =
  unless
    (requiredOption `isInfixOf` componentBody cabalSource componentName)
    ( fail
        ( "haskell-style-check: "
            <> componentName
            <> " is missing the required RTS closure: "
            <> requiredOption
        )
    )

componentBody :: String -> String -> String
componentBody cabalSource componentName =
  case dropWhile (/= componentName) (lines cabalSource) of
    [] -> ""
    _ : bodyLines ->
      unlines (takeWhile isComponentLine bodyLines)
  where
    isComponentLine lineValue =
      case lineValue of
        [] -> True
        firstCharacter : _ -> isSpace firstCharacter

assertStyleRuntimeHeapCap :: IO ()
assertStyleRuntimeHeapCap = do
  activeFlags <- RTSFlags.getRTSFlags
  let activeMaxHeapBlocks =
        toInteger (RTSFlags.maxHeapSize (RTSFlags.gcFlags activeFlags))
      expectedMaxHeapBlocks = 1024 * 1024 * 1024 `div` 4096
  unless
    (activeMaxHeapBlocks == expectedMaxHeapBlocks)
    ( fail
        ( "haskell-style-check: active RTS heap cap is not the baked 1024 MiB value: "
            <> show activeMaxHeapBlocks
        )
    )

assertGeneratedProtoStyleExclusion :: IO ()
assertGeneratedProtoStyleExclusion = do
  let exactGeneratedSources =
        [ "src/Proto/Infernix/Manifest/RuntimeManifest.hs",
          "src/Proto/Infernix/Manifest/RuntimeManifest_Fields.hs",
          "src/Proto/Infernix/Runtime/Inference.hs",
          "src/Proto/Infernix/Runtime/Inference_Fields.hs"
        ]
  unless
    ( generatedHaskellProtoFiles == exactGeneratedSources
        && all isGeneratedHaskellProtoSource exactGeneratedSources
    )
    (fail "the Haskell style exclusion must inventory exactly the four generated proto-lens modules")
  when
    ( any
        isGeneratedHaskellProtoSource
        [ "src/Proto/Infernix/Runtime/Handwritten.hs",
          "test/Proto/Infernix/Runtime/Inference.hs",
          "src/Infernix/Runtime/Inference.hs"
        ]
    )
    (fail "the Haskell style exclusion widened beyond the four generated proto-lens modules")
  unless
    (null (generatedHaskellProtoTreeViolations exactGeneratedSources))
    (fail "the generated Haskell protobuf source tree must match its exact four-file inventory")
  when
    ( null
        ( generatedHaskellProtoTreeViolations
            ("src/Proto/Infernix/Runtime/Unexpected.hs" : exactGeneratedSources)
        )
    )
    (fail "the generated Haskell protobuf source tree gate must reject an unexpected file")

assertProtoSnapshotDriftGate :: IO ()
assertProtoSnapshotDriftGate = do
  paths <- discoverPathsWithHostManifest Nothing
  let snapshotFiles =
        [ "proto/infernix/runtime/inference.proto",
          "proto/infernix/manifest/runtime_manifest.proto"
        ]
          <> generatedHaskellProtoFiles
      manifestPath = repoRoot paths </> "proto/haskell-bindings.sha256"
  snapshotContents <-
    mapM
      ( \relativePath -> do
          contents <- ByteString.readFile (repoRoot paths </> relativePath)
          pure (relativePath, contents)
      )
      snapshotFiles
  manifestContents <- ByteString.Char8.unpack <$> ByteString.readFile manifestPath
  unless
    (null (protoSnapshotManifestViolations snapshotContents manifestContents))
    (fail "the checked-in Haskell protobuf snapshot must satisfy its byte-exact manifest")
  case snapshotContents of
    [] -> fail "the Haskell protobuf snapshot inventory must not be empty"
    (firstPath, firstContents) : remainingContents ->
      when
        ( null
            ( protoSnapshotManifestViolations
                ((firstPath, ByteString.cons 0 firstContents) : remainingContents)
                manifestContents
            )
        )
        (fail "the Haskell protobuf snapshot gate must reject one-byte source drift")

assertAppleClosureFixtureOwnership :: IO ()
assertAppleClosureFixtureOwnership = do
  let fixtureUse =
        [ (1, "AppleInternal.inspectMachOFixtureForTest bytes"),
          (2, "AppleInternal.resolveMachOPathsFixtureForTest root executable graph")
        ]
  when
    ( null
        ( appleClosureFixtureOwnershipViolations
            "src/Infernix/Runtime/Worker.hs"
            fixtureUse
        )
    )
    (fail "production code may not invoke the Apple Mach-O fixture interpreter")
  mapM_
    ( \owner ->
        unless
          ( null
              ( appleClosureFixtureOwnershipViolations
                  owner
                  fixtureUse
              )
          )
          (fail ("Apple closure ownership lint rejected " <> owner))
    )
    [ "src/Infernix/Engines/AppleSilicon/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  unless
    ( null
        ( appleClosureFixtureOwnershipViolations
            "test/apple-materializer/Spec.hs"
            fixtureUse
        )
    )
    (fail "Apple closure ownership lint must permit the dedicated test component")

assertAppleMaterializationTransactionOwnership :: IO ()
assertAppleMaterializationTransactionOwnership = do
  let rawTransactionAccess =
        [ (1, "import Infernix.Engines.AppleSilicon.MaterializationTransaction"),
          (2, "request = MaterializationRequest { completeCandidate = action }"),
          (3, "runMaterializationTransaction bracket request"),
          (4, "closedMaterializationRequest prepare recover cleanup write complete"),
          (5, "session = AppleMaterializationSession"),
          (6, "beginAppleMaterialization"),
          (7, "prepareMetalEngineCandidate writer grant deadlines installRoot tempRoot artifact session"),
          (8, "writeMetalEngineCandidatePayload writer paths tempRoot artifact session"),
          (9, "completeMetalEngineCandidate cacheWriter writer hook paths grant deadlines installRoot tempRoot artifact session"),
          (10, "cleanupMetalEngineCandidate writer grant deadlines tempRoot artifact session")
        ]
  when
    ( null
        ( appleMaterializationTransactionOwnershipViolations
            "src/Infernix/Runtime/Worker.hs"
            rawTransactionAccess
        )
    )
    (fail "production callers may not access the Apple transaction kernel")
  mapM_
    ( \owner ->
        unless
          ( null
              ( appleMaterializationTransactionOwnershipViolations
                  owner
                  rawTransactionAccess
              )
          )
          (fail ("Apple transaction ownership lint rejected " <> owner))
    )
    ["src/Infernix/Engines/AppleSilicon/Internal.hs"]
  unless
    ( null
        ( appleMaterializationTransactionOwnershipViolations
            "test/apple-materializer/Spec.hs"
            rawTransactionAccess
        )
    )
    (fail "Apple transaction ownership lint must stay scoped to production")
  unless
    ( null
        ( appleMaterializationTransactionOwnershipViolations
            "src/Infernix/Runtime/Worker.hs"
            [ (1, "-- MaterializationRequest"),
              (2, "description = \"runMaterializationTransaction\"")
            ]
        )
    )
    (fail "Apple transaction ownership lint must ignore comments and strings")

assertProvisioningKernelOwnership :: IO ()
assertProvisioningKernelOwnership = do
  let rawKernelUses =
        [ (1, "Subprocess.observeProvisioningMutationRoot root"),
          (2, "Subprocess.provisioningCreateDirectoryLeaf root parents leaf"),
          (3, "Subprocess.provisioningCreateSymbolicLinkLeaf root parents leaf target"),
          (4, "Subprocess.provisioningRemoveTreeLeaf root parents leaf"),
          (5, "Subprocess.provisioningRenameSiblingDirectory root parents source destination"),
          (6, "Subprocess.provisioningRenameSiblingRegularFile root parents source destination"),
          (7, "Subprocess.provisioningReplaceSiblingRegularFile root parents source destination"),
          (8, "Subprocess.runProvisioningFilesystemMutation environment timeout mutation"),
          (9, "Subprocess.compileProvisioningCommand command environment timeout"),
          (10, "Subprocess.compileProvisioningCommandWithExecutable command executable environment timeout"),
          (11, "Subprocess.compileProvisioningCommandWithExecutableInMutationRoot command root executable environment timeout"),
          (12, "Subprocess.resolveProvisioningCommandExecutable command environment")
        ]
      nonOwner = "src/Infernix/Runtime/Worker.hs"
      owners =
        [ "src/Infernix/Cluster/Subprocess.hs",
          "src/Infernix/Engines/Provisioning.hs"
        ]
      activationOwner = "src/Infernix/Engines/Artifact/Activation.hs"
  mapM_
    ( \rawUse ->
        when
          ( null
              ( provisioningKernelOwnershipViolations
                  nonOwner
                  [rawUse]
              )
          )
          (fail ("production caller may not use provisioning kernel token: " <> snd rawUse))
    )
    rawKernelUses
  mapM_
    ( \owner ->
        unless
          ( null
              ( provisioningKernelOwnershipViolations
                  owner
                  rawKernelUses
              )
          )
          (fail ("provisioning kernel ownership lint rejected " <> owner))
    )
    owners
  unless
    ( null
        ( provisioningKernelOwnershipViolations
            activationOwner
            rawKernelUses
        )
    )
    (fail "provisioning kernel ownership lint rejected the activation interpreter's generic operations")
  unless
    ( null
        ( provisioningKernelOwnershipViolations
            "test/integration/Spec.hs"
            rawKernelUses
        )
    )
    (fail "provisioning kernel ownership lint must stay scoped to production")
  unless
    ( null
        ( provisioningKernelOwnershipViolations
            nonOwner
            [ (1, "-- compileProvisioningCommand"),
              (2, "description = \"runProvisioningFilesystemMutation\"")
            ]
        )
    )
    (fail "provisioning kernel ownership lint must ignore comments and strings")

assertNativeArtifactInvocationKernelOwnership :: IO ()
assertNativeArtifactInvocationKernelOwnership = do
  let rawKernelUses =
        [ (1, "plan :: NativeArtifactInvocationPlan"),
          (2, "plan = Subprocess.nativeArtifactInvocationPlan model engine family adapter mode input object cache output inputFile"),
          (3, "Subprocess.runBoundedNativeArtifact executableModel artifact plan environment")
        ]
      nonOwner = "src/Infernix/Runtime/Worker.hs"
      owners =
        [ "src/Infernix/Cluster/Subprocess.hs",
          "src/Infernix/Runtime/CappedEngine/Internal.hs"
        ]
  mapM_
    ( \rawUse ->
        when
          ( null
              ( nativeArtifactInvocationKernelOwnershipViolations
                  nonOwner
                  [rawUse]
              )
          )
          (fail ("production caller may not use native-artifact invocation kernel token: " <> snd rawUse))
    )
    rawKernelUses
  mapM_
    ( \owner ->
        unless
          ( null
              ( nativeArtifactInvocationKernelOwnershipViolations
                  owner
                  rawKernelUses
              )
          )
          (fail ("native-artifact invocation ownership lint rejected " <> owner))
    )
    owners
  unless
    ( null
        ( nativeArtifactInvocationKernelOwnershipViolations
            "test/unit/Spec.hs"
            rawKernelUses
        )
    )
    (fail "native-artifact invocation ownership lint must stay scoped to production")
  unless
    ( null
        ( nativeArtifactInvocationKernelOwnershipViolations
            nonOwner
            [ (1, "-- runBoundedNativeArtifact"),
              (2, "description = \"NativeArtifactInvocationPlan\"")
            ]
        )
    )
    (fail "native-artifact invocation ownership lint must ignore comments and strings")

assertArtifactCapabilityBoundary :: IO ()
assertArtifactCapabilityBoundary = do
  let rawCapabilityImports =
        [ [(1, "import Infernix.Engines.Artifact.Capability")],
          [(1, "import qualified Infernix.Engines.Artifact.Capability as Capability")],
          [(1, "import Infernix.Engines.Artifact.Capability qualified as Capability")],
          [ (1, "import"),
            (2, "  qualified"),
            (3, "  Infernix.Engines.Artifact.Capability"),
            (4, "  as Capability")
          ]
        ]
      validationBoundaryUse =
        [(1, "Artifact.withFirstValidatedEngineArtifact identity expectation roots session")]
      workerFile = "src/Infernix/Runtime/Worker.hs"
      representationOwners =
        [ "src/Infernix/Engines/Artifact/Internal.hs",
          "src/Infernix/Runtime/CappedEngine/Internal.hs"
        ]
      boundaryOwners =
        "src/Infernix/Engines/Artifact.hs" : representationOwners
  mapM_
    ( \rawCapabilityImport ->
        when
          ( null
              ( artifactCapabilityBoundaryViolations
                  workerFile
                  rawCapabilityImport
              )
          )
          (fail "engine worker may not import the artifact capability representation")
    )
    rawCapabilityImports
  when
    ( null
        ( artifactCapabilityBoundaryViolations
            workerFile
            validationBoundaryUse
        )
    )
    (fail "engine worker may not enter the validated artifact boundary")
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactCapabilityBoundaryViolations
                  owner
                  (concat rawCapabilityImports)
              )
          )
          (fail ("artifact capability lint rejected its kernel owner " <> owner))
    )
    representationOwners
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactCapabilityBoundaryViolations
                  owner
                  validationBoundaryUse
              )
          )
          (fail ("artifact capability lint rejected its boundary owner " <> owner))
    )
    boundaryOwners
  when
    ( null
        ( artifactCapabilityBoundaryViolations
            "src/Infernix/Engines/Artifact.hs"
            (concat rawCapabilityImports)
        )
    )
    (fail "public artifact facade may not import the constructor-bearing representation")
  unless
    ( null
        ( artifactCapabilityBoundaryViolations
            "test/artifact-transaction/Spec.hs"
            (concat rawCapabilityImports <> validationBoundaryUse)
        )
    )
    (fail "artifact capability ownership lint must stay scoped to production sources")
  unless
    ( null
        ( artifactCapabilityBoundaryViolations
            workerFile
            [ (1, "-- import Infernix.Engines.Artifact.Capability"),
              (2, "description = \"withFirstValidatedEngineArtifact\"")
            ]
        )
    )
    (fail "artifact capability lint must ignore policy tokens in comments and string literals")

assertArtifactWriterBoundary :: IO ()
assertArtifactWriterBoundary = do
  let rawTransactionAccess =
        [ (1, "Artifact.reconcileEngineArtifactRoot installRoot"),
          (2, "Artifact.installEngineArtifactRootWithExpectedDigest installRoot candidateRoot digest"),
          (3, "Artifact.withEngineArtifactActivation authority installRoot candidateRoot digest continuation"),
          (4, "Artifact.finishEngineArtifactActivation CommitArtifactActivation activation"),
          (5, "Artifact.activateAppleEngineArtifactWithInstalledSmoke authority environment deadline adapter installRoot candidateRoot digest"),
          (6, "Artifact.activateLinuxEngineArtifactWithInstalledSmoke authority environment identity policy installRoot candidateRoot digest"),
          (7, "Artifact.activateAppleEngineArtifactWithInstalledPythonSourceIsolationSmoke authority environment deadline adapter spec installRoot candidateRoot digest")
        ]
      rawWriterLock =
        [(1, "withEngineMaterializationLock enginesRoot action")]
      rawArtifactInternalImport =
        [(1, "import Infernix.Engines.Artifact.Internal")]
      rawLockInternalImport =
        [(1, "import Infernix.Engines.MaterializationLock.Internal")]
      rawProjectLockInternalImport =
        [(1, "import Infernix.Python.MutationLock.Internal")]
      rawDownloadCacheLockInternalImport =
        [ (1, "import Infernix.Engines.DownloadCacheLock.Internal"),
          (2, "withDownloadCacheMutationLockInternal cacheRoot action")
        ]
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            rawTransactionAccess
        )
    )
    (fail "engine worker may not invoke raw artifact transactions")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Runtime/CappedEngine/Internal.hs"
            rawWriterLock
        )
    )
    (fail "capped-engine reader may not acquire the exclusive materialization lock")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Engines/LinuxNative.hs"
            (rawArtifactInternalImport <> rawLockInternalImport)
        )
    )
    (fail "Linux materialization may not import raw writer implementations")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Engines/AppleSilicon/Internal.hs"
            rawProjectLockInternalImport
        )
    )
    (fail "Apple materialization may not import the raw project-lock implementation")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Engines/AppleSilicon/Internal.hs"
            rawDownloadCacheLockInternalImport
        )
    )
    (fail "Apple materialization may not import the raw download-cache lock implementation")
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawTransactionAccess
              )
          )
          (fail ("artifact transaction lint rejected its writer owner " <> owner))
    )
    [ "src/Infernix/Engines/Artifact/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawWriterLock
              )
          )
          (fail ("materialization-lock lint rejected its writer owner " <> owner))
    )
    [ "src/Infernix/Engines/MaterializationLock/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawArtifactInternalImport
              )
          )
          (fail ("artifact internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/Artifact.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawLockInternalImport
              )
          )
          (fail ("materialization-lock internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/Artifact/Internal.hs",
      "src/Infernix/Engines/MaterializationLock.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawProjectLockInternalImport
              )
          )
          (fail ("project-lock internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/Provisioning.hs",
      "src/Infernix/Python.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawDownloadCacheLockInternalImport
              )
          )
          (fail ("download-cache lock internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/DownloadCacheLock/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  unless
    ( null
        ( artifactWriterBoundaryViolations
            "test/artifact-transaction/Spec.hs"
            (rawTransactionAccess <> rawWriterLock)
        )
    )
    (fail "artifact writer ownership lint must stay scoped to production sources")
  unless
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            [ (1, "-- installEngineArtifactRoot candidate"),
              (2, "description = \"withEngineMaterializationLock\""),
              (3, "-- import Infernix.Engines.Artifact.Internal"),
              (4, "description = \"import Infernix.Engines.MaterializationLock.Internal\""),
              (5, "-- import Infernix.Python.MutationLock.Internal"),
              (6, "description = \"withDownloadCacheMutationLockInternal\"")
            ]
        )
    )
    (fail "artifact writer lint must ignore policy tokens in comments and string literals")

assertCappedEngineBoundary :: IO ()
assertCappedEngineBoundary = do
  let workerFile = "src/Infernix/Runtime/Worker.hs"
      rawAuthority =
        [ (1, "DirectEngineCommand executable arguments workingDirectory environment"),
          (2, "runExecutableStdioEngine executable command payload")
        ]
      renderedEnvironment =
        [(1, "Subprocess.renderSubprocessEnv processEnvironment")]
      internalImport =
        [(1, "import Infernix.Runtime.CappedEngine.Internal")]
      outputCaptureImport =
        [(1, "import Infernix.Runtime.CappedEngine.OutputCapture")]
  mapM_
    ( \fixture ->
        when
          ( null
              ( cappedEngineBoundaryViolations
                  workerFile
                  fixture
              )
          )
          (fail "worker may not recover raw capped-engine process authority")
    )
    [rawAuthority, renderedEnvironment, internalImport, outputCaptureImport]
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "src/Infernix/Runtime/CappedEngine/Internal.hs"
            (rawAuthority <> renderedEnvironment <> outputCaptureImport)
        )
    )
    (fail "capped-engine ownership lint rejected its raw-process kernel")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "src/Infernix/Cluster/Subprocess.hs"
            renderedEnvironment
        )
    )
    (fail "environment-rendering lint rejected the bounded-command kernel")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "src/Infernix/Runtime/CappedEngine.hs"
            internalImport
        )
    )
    (fail "capped-engine facade may not import its hidden implementation")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "test/unit/Spec.hs"
            (rawAuthority <> renderedEnvironment <> internalImport <> outputCaptureImport)
        )
    )
    (fail "capped-engine ownership lint must stay scoped to production sources")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            workerFile
            [ (1, "-- runExecutableStdioEngine command"),
              (2, "description = \"renderSubprocessEnv DirectEngineCommand\"")
            ]
        )
    )
    (fail "capped-engine lint must ignore policy tokens in comments and string literals")

assertBoundedEngineOutput :: IO ()
assertBoundedEngineOutput = do
  let kernelFile = "src/Infernix/Runtime/CappedEngine/Internal.hs"
      unboundedReads =
        [ (1, "stdoutOutput <- hGetContents stdoutHandle"),
          (2, "stderrOutput <- ByteString.hGetContents stderrHandle"),
          (3, "stdoutOutput <- readAllText stdoutHandle")
        ]
  when
    (null (boundedEngineOutputViolations kernelFile unboundedReads))
    (fail "capped-engine output lint must reject lazy and unbounded handle reads")
  unless
    ( null
        ( boundedEngineOutputViolations
            kernelFile
            [(1, "chunk <- ByteString.hGetSome outputHandle fixedChunkBytes")]
        )
    )
    (fail "capped-engine output lint rejected fixed bounded chunk capture")
  unless
    ( null
        ( boundedEngineOutputViolations
            kernelFile
            [ (1, "-- hGetContents stdoutHandle"),
              (2, "description = \"readAllText\"")
            ]
        )
    )
    (fail "capped-engine output lint must ignore comments and string literals")
  unless
    ( null
        ( boundedEngineOutputViolations
            "test/capped-engine-observer/Spec.hs"
            unboundedReads
        )
    )
    (fail "capped-engine output lint must stay scoped to production sources")

assertLinuxNativeMaterializationBoundary :: IO ()
assertLinuxNativeMaterializationBoundary = do
  let rawPlanAccess =
        [ (1, "mapM_ materializeLinuxNativeEngineArtifactUnlocked linuxNativeEngineBuildPlan"),
          (2, "manifest <- manifestForLinuxNativeEngineArtifact root evidence artifact")
        ]
      owner = "src/Infernix/Engines/LinuxNative.hs"
  when
    ( null
        ( linuxNativeMaterializationBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            rawPlanAccess
        )
    )
    (fail "production callers may not inspect or invoke the raw Linux materialization plan")
  unless
    (null (linuxNativeMaterializationBoundaryViolations owner rawPlanAccess))
    (fail "Linux native materialization lint rejected its sole owner")
  unless
    ( null
        ( linuxNativeMaterializationBoundaryViolations
            "test/unit/Spec.hs"
            rawPlanAccess
        )
    )
    (fail "Linux native materialization lint must stay scoped to production sources")
  unless
    ( null
        ( linuxNativeMaterializationBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            [ (1, "-- linuxNativeEngineBuildPlan"),
              (2, "description = \"manifestForLinuxNativeEngineArtifact\"")
            ]
        )
    )
    (fail "Linux native materialization lint must ignore comments and string literals")

assertAppleArtifactProvisioningBoundary :: IO ()
assertAppleArtifactProvisioningBoundary = do
  let guardedFiles =
        [ "src/Infernix/Engines/AppleSilicon.hs",
          "src/Infernix/Engines/AppleSilicon/Internal.hs",
          "src/Infernix/Engines/Artifact.hs",
          "src/Infernix/Engines/Artifact/Internal.hs",
          "src/Infernix/Engines/Provisioning.hs",
          "src/Infernix/Engines/Provisioning/Internal.hs"
        ]
  mapM_
    ( \sourceFile -> do
        assertViolation
          sourceFile
          [(1, "import System.Process qualified as Process")]
          "System.Process imports are rejected"
        assertViolation
          sourceFile
          [(1, "result <- readCreateProcessWithExitCode specification input")]
          "raw process primitives are rejected"
    )
    guardedFiles
  assertViolation
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
    [(1, "ensurePoetryProjectReady paths")]
    "the legacy unbounded Poetry helper is rejected"
  assertViolation
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
    [(1, "ensurePoetryExecutable paths")]
    "the Poetry bootstrap helper is rejected"
  assertViolation
    "src/Infernix/Engines/Provisioning.hs"
    [(1, "liftProvisioningIO arbitraryAction")]
    "a generic provisioning IO lift is rejected"
  assertViolation
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
    [(1, "Subprocess.runBoundedCommand command")]
    "direct bounded-kernel use outside the provisioning facade is rejected"
  unless
    ( null
        ( appleArtifactProvisioningViolations
            "src/Infernix/Engines/Provisioning.hs"
            [(1, "Subprocess.runBoundedCommand command")]
        )
    )
    (fail "Apple artifact provisioning lint must permit its sole bounded-kernel owner")
  unless
    ( null
        ( appleArtifactProvisioningViolations
            "src/Infernix/Engines/AppleSilicon/Internal.hs"
            [ (1, "-- import System.Process"),
              (2, "description = \"readCreateProcessWithExitCode\"")
            ]
        )
    )
    (fail "Apple artifact provisioning lint must ignore policy tokens in comments and string literals")
  unless
    ( null
        ( appleArtifactProvisioningViolations
            "src/Infernix/Runtime/Daemon.hs"
            [(1, "import System.Process")]
        )
    )
    (fail "Apple artifact provisioning lint must stay scoped to the artifact boundary")

assertViolation :: FilePath -> [(Int, String)] -> String -> IO ()
assertViolation sourceFile numberedLines message =
  when
    (null (appleArtifactProvisioningViolations sourceFile numberedLines))
    (fail ("Apple artifact provisioning lint: " <> message <> " in " <> sourceFile))
