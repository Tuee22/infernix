{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Main (main) where

import Control.Concurrent
  ( MVar,
    ThreadId,
    forkFinally,
    newEmptyMVar,
    putMVar,
    takeMVar,
    throwTo,
  )
import Control.Exception
  ( AsyncException (ThreadKilled),
    SomeAsyncException,
    SomeException,
    bracket,
    displayException,
    fromException,
    onException,
    try,
  )
import Control.Monad (forM, forM_, unless, when)
import Data.Bits (shiftR)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.Either (isLeft)
import Data.List qualified as List
import Data.Text qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.Engines.AppleSilicon.Internal qualified as AppleInternal
import Infernix.Engines.Artifact qualified as Artifact
import Infernix.HostConfig qualified as HostConfig
import System.Directory
  ( createDirectory,
    createDirectoryIfMissing,
    doesFileExist,
    doesPathExist,
    getTemporaryDirectory,
    removeFile,
    removePathForcibly,
  )
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))
import System.Info (os)
import System.Posix.Process (getProcessID)
import System.Timeout qualified as Timeout

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    [] -> runMachineIndependentTests
    ["--darwin-production-audiveris-cancellation"] ->
      runDarwinProductionCancellationTest
    _ ->
      fail
        ( "unsupported apple-materializer test arguments: "
            <> show arguments
            <> "; use no arguments or exactly --darwin-production-audiveris-cancellation"
        )

runMachineIndependentTests :: IO ()
runMachineIndependentTests = do
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
    ( "Apple materializer tests passed: "
        <> show (length testCases)
        <> " cases"
    )

runDarwinProductionCancellationTest :: IO ()
runDarwinProductionCancellationTest = do
  productionAudiverisCancellationRecoveryTest
  putStrLn
    "PASS: actual Darwin Audiveris materializer cancellation recovers its exact mount and preserves the prior root"

testCases :: [(String, IO ())]
testCases =
  [ ("private indexed runner cleans every synthetic synchronous boundary failure", syntheticBoundaryFailureTest),
    ("private indexed runner cleans every synthetic asynchronous boundary cancellation", syntheticBoundaryCancellationTest),
    ("production materializer locks release and reacquire", productionLockReleaseTest),
    ("obsolete Apple bridge retirement is exact and fail-closed", obsoleteRootRetirementTest),
    ("exact Audiveris mount records recover or remain durable", exactMountRecordRecoveryTest),
    ("Apple runtime smoke parsing is exact for all seven targets", exactAppleRuntimeSmokeParsingTest),
    ("Mach-O fixture copies recursive inherited-rpath closure", recursiveMachOClosureTest),
    ("Mach-O fixture rejects missing, unresolved, and colliding closure input", rejectedMachOClosureTest),
    ("Mach-O production hard bounds reject every excess dimension", machOClosureBoundsTest)
  ]

syntheticBoundaryFailureTest :: IO ()
syntheticBoundaryFailureTest =
  withMaterializerFixture "boundary-failure" $ \paths fixtureRoot -> do
    priorMarker <- createPriorRootMarker paths
    forM_ AppleInternal.appleMaterializerFixtureBoundaries $ \boundary -> do
      result <-
        try @SomeException
          ( AppleInternal.appleMaterializerBoundaryFailureForTest
              paths
              boundary
          )
      assertLeft ("synthetic failure at " <> show boundary) result
      assertCandidateRetired paths boundary
      assertPriorRootMarker priorMarker fixtureRoot boundary

syntheticBoundaryCancellationTest :: IO ()
syntheticBoundaryCancellationTest =
  withMaterializerFixture "boundary-cancellation" $ \paths fixtureRoot -> do
    priorMarker <- createPriorRootMarker paths
    forM_ AppleInternal.appleMaterializerFixtureBoundaries $ \boundary -> do
      entered <- newEmptyMVar
      resume <- newEmptyMVar
      assertThreadCancellation
        ("synthetic boundary " <> show boundary)
        entered
        ( AppleInternal.appleMaterializerBoundaryCancellationForTest
            paths
            boundary
            entered
            resume
        )
      assertCandidateRetired paths boundary
      assertPriorRootMarker priorMarker fixtureRoot boundary

productionLockReleaseTest :: IO ()
productionLockReleaseTest =
  withMaterializerFixture "lock-release" $ \paths _ -> do
    first <- AppleInternal.appleMaterializerLockContentionForTest paths
    second <- AppleInternal.appleMaterializerLockContentionForTest paths
    assertEqual
      "all nested lock acquisitions contend"
      (True, True, True, True)
      first
    assertEqual
      "all locks reacquire after their first region exits"
      (True, True, True, True)
      second

obsoleteRootRetirementTest :: IO ()
obsoleteRootRetirementTest =
  withMaterializerFixture "obsolete-root" $ \paths _ -> do
    let obsoleteRoot =
          dataRoot paths
            </> "engines"
            </> "apple-metal-runtime-bridge"
        payload = obsoleteRoot </> "owned-payload"
    createDirectoryIfMissing True obsoleteRoot
    writeFile payload "obsolete\n"
    AppleInternal.retireLegacyAppleMetalRuntimeBridgeForTest paths
    retired <- not <$> doesPathExist obsoleteRoot
    assertEqual "owned obsolete bridge directory is retired" True retired
    createDirectoryIfMissing True (dataRoot paths </> "engines")
    writeFile obsoleteRoot "not an owned directory\n"
    refusal <-
      try @SomeException
        (AppleInternal.retireLegacyAppleMetalRuntimeBridgeForTest paths)
    assertLeft "non-directory obsolete bridge root is refused" refusal
    stillPresent <- doesFileExist obsoleteRoot
    assertEqual
      "unsafe obsolete bridge root remains after refusal"
      True
      stillPresent
    removeFile obsoleteRoot
    AppleInternal.retireLegacyAppleMetalRuntimeBridgeForTest paths
    reacquired <- AppleInternal.appleMaterializerLockContentionForTest paths
    assertEqual
      "retirement failure releases all materializer locks"
      (True, True, True, True)
      reacquired

exactMountRecordRecoveryTest :: IO ()
exactMountRecordRecoveryTest =
  withMaterializerFixture "mount-recovery" $ \paths _ -> do
    forM_
      [ AppleInternal.RecoverPreparedMountRecord,
        AppleInternal.RecoverAttachedAlreadyDetachedRecord
      ]
      $ \fixture -> do
        AppleInternal.recoverAudiverisMountRecordFixtureForTest
          paths
          fixture
        fixturePresent <-
          doesPathExist
            ( AppleInternal.audiverisMountRecoveryFixtureRootForTest
                paths
                fixture
            )
        assertEqual
          ("successful exact mount recovery removes " <> show fixture)
          False
          fixturePresent
    let changedFixture = AppleInternal.RejectChangedMountPlaceholder
        changedRoot =
          AppleInternal.audiverisMountRecoveryFixtureRootForTest
            paths
            changedFixture
        activityRecord =
          changedRoot </> ".audiveris-mount-activity.json"
    changedResult <-
      try @SomeException
        ( AppleInternal.recoverAudiverisMountRecordFixtureForTest
            paths
            changedFixture
        )
    assertLeft "changed exact placeholder is refused" changedResult
    candidatePresent <- doesPathExist changedRoot
    recordPresent <- doesFileExist activityRecord
    assertEqual
      "failed exact mount recovery preserves the candidate"
      True
      candidatePresent
    assertEqual
      "failed exact mount recovery preserves its durable record"
      True
      recordPresent
    reacquired <- AppleInternal.appleMaterializerLockContentionForTest paths
    assertEqual
      "failed mount recovery releases all materializer locks"
      (True, True, True, True)
      reacquired

productionAudiverisCancellationRecoveryTest :: IO ()
productionAudiverisCancellationRecoveryTest = do
  unless (os == "darwin") $
    fail
      "the opt-in full-production Audiveris cancellation test requires a Darwin host"
  paths <- discoverPaths
  case pathsHostConfig paths of
    Nothing ->
      fail
        ( "the opt-in full-production Audiveris cancellation test requires the generated host manifest at "
            <> (repoRoot paths </> "infernix-host.dhall")
        )
    Just _ -> pure ()
  let installRoot =
        AppleInternal.metalEngineInstallRoot paths "jvm-native"
      candidateRoot = Artifact.engineArtifactTempRoot installRoot
      activityPath =
        candidateRoot </> ".audiveris-mount-activity.json"
      mountRoot =
        candidateRoot </> "tmp" </> "audiveris-dmg"
  priorManifest <-
    Artifact.validateEngineArtifactRootAt installRoot installRoot
  unless
    ( Artifact.manifestAdapterId priorManifest == "jvm-native"
        && Artifact.manifestSubstrate priorManifest == "apple-silicon"
        && Artifact.manifestArchitecture priorManifest == "arm64"
        && Artifact.manifestLocalInstallRoot priorManifest == installRoot
    )
    ( fail
        ( "the opt-in cancellation test requires a current real jvm-native Apple artifact at "
            <> installRoot
        )
    )
  mapM_
    requirePathAbsentBeforeProductionCancellation
    [candidateRoot, activityPath, mountRoot]
  entered <- newEmptyMVar
  resume <- newEmptyMVar
  completed <- newEmptyMVar
  materializerThread <-
    forkFinally
      ( AppleInternal.materializeAudiverisProductionPausedForTest
          paths
          entered
          resume
      )
      (putMVar completed)
  checkpoint <-
    Timeout.timeout
      productionCheckpointTimeoutMicros
      (takeMVar entered)
  case checkpoint of
    Nothing -> do
      result <-
        cancelProductionMaterializer
          materializerThread
          completed
      fail
        ( "the actual Audiveris materializer did not reach its durable attached-mount checkpoint; terminal result: "
            <> renderThreadResult result
        )
    Just () -> do
      requireProductionMountCheckpoint candidateRoot activityPath mountRoot
        `onException` cancelProductionMaterializer materializerThread completed
      result <-
        cancelProductionMaterializer
          materializerThread
          completed
      requireAsynchronousCancellation
        "actual Darwin Audiveris post-mount checkpoint"
        result
  mapM_
    requirePathAbsentAfterProductionCancellation
    [candidateRoot, activityPath, mountRoot]
  currentManifest <-
    Artifact.validateEngineArtifactRootAt installRoot installRoot
  assertEqual
    "actual cancellation preserves the complete prior jvm-native artifact"
    priorManifest
    currentManifest
  reacquired <- AppleInternal.appleMaterializerLockContentionForTest paths
  assertEqual
    "all four Apple provisioning lifecycle locks reacquire immediately after actual cancellation"
    (True, True, True, True)
    reacquired

productionCheckpointTimeoutMicros :: Int
productionCheckpointTimeoutMicros = 1500000000

productionCleanupTimeoutMicros :: Int
productionCleanupTimeoutMicros = 300000000

requirePathAbsentBeforeProductionCancellation :: FilePath -> IO ()
requirePathAbsentBeforeProductionCancellation path = do
  present <- doesPathExist path
  when present $
    fail
      ( "the opt-in production cancellation test requires a clean candidate boundary; remove or recover "
          <> path
          <> " before retrying"
      )

requireProductionMountCheckpoint ::
  FilePath ->
  FilePath ->
  FilePath ->
  IO ()
requireProductionMountCheckpoint candidateRoot activityPath mountRoot = do
  candidatePresent <- doesPathExist candidateRoot
  activityPresent <- doesFileExist activityPath
  mountPresent <- doesPathExist mountRoot
  unless (candidatePresent && activityPresent && mountPresent) $
    fail
      ( "the production pause hook fired without its candidate, durable mount activity, and mounted path: "
          <> show
            ( candidatePresent,
              activityPresent,
              mountPresent
            )
      )

cancelProductionMaterializer ::
  ThreadId ->
  MVar (Either SomeException ()) ->
  IO (Either SomeException ())
cancelProductionMaterializer materializerThread completed = do
  throwTo materializerThread ThreadKilled
  result <-
    Timeout.timeout
      productionCleanupTimeoutMicros
      (takeMVar completed)
  case result of
    Nothing ->
      fail
        "the actual Audiveris materializer did not finish bounded exact-mount cleanup after cancellation"
    Just terminal -> pure terminal

requireAsynchronousCancellation ::
  String ->
  Either SomeException () ->
  IO ()
requireAsynchronousCancellation label result =
  case result of
    Left failure
      | Just (_ :: SomeAsyncException) <- fromException failure ->
          pure ()
      | otherwise ->
          fail
            ( label
                <> " produced a synchronous exception: "
                <> displayException failure
            )
    Right () ->
      fail (label <> " unexpectedly completed")

requirePathAbsentAfterProductionCancellation :: FilePath -> IO ()
requirePathAbsentAfterProductionCancellation path = do
  present <- doesPathExist path
  when present $
    fail
      ( "actual Audiveris cancellation left owned candidate or mount activity at "
          <> path
      )

renderThreadResult :: Either SomeException () -> String
renderThreadResult result =
  case result of
    Left failure -> displayException failure
    Right () -> "completed successfully before cancellation"

exactAppleRuntimeSmokeParsingTest :: IO ()
exactAppleRuntimeSmokeParsingTest = do
  forM_ validAppleRuntimeSmokeFixtures $
    \(adapterId, smokeOutput, expectedVersion) -> do
      observed <-
        requireRight
          ("parse exact runtime smoke for " <> Text.unpack adapterId)
          (parseAppleRuntimeSmoke adapterId smokeOutput)
      assertEqual
        ("normalized runtime version for " <> Text.unpack adapterId)
        expectedVersion
        observed
  forM_ invalidAppleRuntimeSmokeFixtures $
    \(label, adapterId, smokeOutput) ->
      assertEqual
        label
        True
        (isLeft (parseAppleRuntimeSmoke adapterId smokeOutput))

validAppleRuntimeSmokeFixtures ::
  [(Text.Text, ByteString.ByteString, Text.Text)]
validAppleRuntimeSmokeFixtures =
  [ ( "llama-cpp-cli",
      ByteStringChar8.pack
        ( "version: 9870 (2d973636e)\n"
            <> "built with AppleClang 21.0.0.21000099 for Darwin arm64\n"
        ),
      "llama.cpp-b9870-2d973636e"
    ),
    ( "whisper-cpp-cli",
      ByteStringChar8.pack "whisper.cpp version: 1.9.1\n",
      "1.9.1"
    ),
    ( "ctranslate2-native",
      canonicalPythonSmoke
        "ctranslate2-native"
        "\"ctranslate2\":\"4.6.0\",\"faster-whisper\":\"1.1.1\"",
      "ctranslate2=4.6.0,faster-whisper=1.1.1"
    ),
    ( "onnx-runtime-native",
      canonicalPythonSmoke
        "onnx-runtime-native"
        "\"onnxruntime\":\"1.21.0\"",
      "onnxruntime=1.21.0"
    ),
    ( "mlx-native",
      canonicalPythonSmoke
        "mlx-native"
        "\"mlx\":\"0.25.2\",\"mlx-lm\":\"0.24.1\"",
      "mlx=0.25.2,mlx-lm=0.24.1"
    ),
    ( "coreml-native",
      canonicalPythonSmoke
        "coreml-native"
        ( "\"apple-ml-stable-diffusion\":\"1.0.0\","
            <> "\"basic-pitch\":\"0.4.0\",\"coremltools\":\"8.3.0\""
        ),
      "apple-ml-stable-diffusion=1.0.0,basic-pitch=0.4.0,coremltools=8.3.0"
    ),
    ( "jvm-native",
      ByteStringChar8.pack
        ( "Audiveris\n"
            <> "- Version:      5.10.2\n"
            <> "- Commit:       8fbdc39\n"
            <> "- OS:           Mac OS X 15.5\n"
            <> "- Architecture: aarch64\n"
            <> "- Java VM:      OpenJDK 64-Bit Server VM 21.0.7\n"
            <> "- OCR Engine:   Tesseract OCR 5.5.1\n"
        ),
      "5.10.2"
    )
  ]

invalidAppleRuntimeSmokeFixtures ::
  [(String, Text.Text, ByteString.ByteString)]
invalidAppleRuntimeSmokeFixtures =
  [ ( "llama rejects an extra version line",
      "llama-cpp-cli",
      ByteStringChar8.pack
        ( "version: 9870 (2d973636e)\n"
            <> "built with AppleClang 21.0.0.21000099 for Darwin arm64\n"
            <> "version: 9871 (3e084747f)\n"
        )
    ),
    ( "llama rejects a zero build",
      "llama-cpp-cli",
      ByteStringChar8.pack
        ( "version: 0 (2d973636e)\n"
            <> "built with AppleClang 21.0.0.21000099 for Darwin arm64\n"
        )
    ),
    ( "llama rejects uppercase commit evidence",
      "llama-cpp-cli",
      ByteStringChar8.pack
        ( "version: 9870 (2D973636E)\n"
            <> "built with AppleClang 21.0.0.21000099 for Darwin arm64\n"
        )
    ),
    ( "whisper rejects ambiguous output",
      "whisper-cpp-cli",
      ByteStringChar8.pack
        "whisper.cpp version: 1.9.1\nwhisper.cpp version: 1.9.2\n"
    ),
    ( "Python smoke rejects a mismatched adapter",
      "onnx-runtime-native",
      canonicalPythonSmoke
        "mlx-native"
        "\"onnxruntime\":\"1.21.0\""
    ),
    ( "Python smoke rejects an extra package",
      "onnx-runtime-native",
      canonicalPythonSmoke
        "onnx-runtime-native"
        "\"fabricated\":\"1.0\",\"onnxruntime\":\"1.21.0\""
    ),
    ( "Python smoke rejects noncanonical JSON",
      "onnx-runtime-native",
      ByteStringChar8.pack
        ( "{\"schemaVersion\": 1, \"packages\": "
            <> "{\"onnxruntime\": \"1.21.0\"}, "
            <> "\"adapterId\": \"onnx-runtime-native\"}\n"
        )
    ),
    ( "Audiveris rejects a version outside the pinned receipt",
      "jvm-native",
      ByteStringChar8.pack
        ( "Audiveris\n"
            <> "- Version:      5.10.3\n"
            <> "- Commit:       8fbdc39\n"
            <> "- OS:           Mac OS X 15.5\n"
            <> "- Architecture: aarch64\n"
            <> "- Java VM:      OpenJDK 64-Bit Server VM 21.0.7\n"
            <> "- OCR Engine:   Tesseract OCR 5.5.1\n"
        )
    ),
    ( "Audiveris rejects an empty exact field",
      "jvm-native",
      ByteStringChar8.pack
        ( "Audiveris\n"
            <> "- Version:      5.10.2\n"
            <> "- Commit:       \n"
            <> "- OS:           Mac OS X 15.5\n"
            <> "- Architecture: aarch64\n"
            <> "- Java VM:      OpenJDK 64-Bit Server VM 21.0.7\n"
            <> "- OCR Engine:   Tesseract OCR 5.5.1\n"
        )
    ),
    ( "runtime smoke rejects NUL",
      "whisper-cpp-cli",
      ByteStringChar8.pack "whisper.cpp version: 1.9.1\NUL\n"
    ),
    ( "runtime smoke rejects invalid UTF-8",
      "whisper-cpp-cli",
      ByteString.pack [0xff]
    ),
    ( "runtime smoke rejects oversized evidence",
      "whisper-cpp-cli",
      ByteString.replicate (64 * 1024 + 1) 97
    )
  ]

canonicalPythonSmoke ::
  String ->
  String ->
  ByteString.ByteString
canonicalPythonSmoke adapterId packages =
  ByteStringChar8.pack
    ( "{\"adapterId\":\""
        <> adapterId
        <> "\",\"packages\":{"
        <> packages
        <> "},\"schemaVersion\":1}\n"
    )

parseAppleRuntimeSmoke ::
  Text.Text ->
  ByteString.ByteString ->
  Either String Text.Text
parseAppleRuntimeSmoke adapterId smokeOutput = do
  artifact <-
    maybe
      (Left ("closed Apple build plan omitted " <> Text.unpack adapterId))
      Right
      ( List.find
          ((== adapterId) . AppleInternal.metalEngineAdapterId)
          AppleInternal.metalEngineBuildPlan
      )
  AppleInternal.parseAppleRuntimeVersionForTest artifact smokeOutput

recursiveMachOClosureTest :: IO ()
recursiveMachOClosureTest = do
  let upstreamRoot = "/infernix-fixture/macho-recursive/upstream"
      candidateRoot = "/infernix-fixture/macho-recursive/candidate"
      executable = upstreamRoot </> "bin" </> "tool"
      libraryA = upstreamRoot </> "lib" </> "libA.dylib"
      libraryB = upstreamRoot </> "lib" </> "libB.dylib"
      firstChoice =
        upstreamRoot </> "first" </> "libChoice.dylib"
      secondChoice =
        upstreamRoot </> "second" </> "libChoice.dylib"
      loaderLibrary =
        upstreamRoot </> "bin" </> "libLoader.dylib"
      executableLibrary =
        upstreamRoot </> "bin" </> "libExec.dylib"
      frameworkSource =
        upstreamRoot
          </> "Frameworks"
          </> "Fancy.framework"
          </> "Versions"
          </> "A"
          </> "Fancy"
      rootImage =
        machOImage
          [ "@rpath/libA.dylib",
            "@rpath/libChoice.dylib",
            "@loader_path/libLoader.dylib",
            "@executable_path/libExec.dylib",
            frameworkSource,
            "/usr/lib/libSystem.B.dylib"
          ]
          [ "@loader_path/../first",
            "@loader_path/../second",
            "@loader_path/../lib"
          ]
      emptyImage = machOImage [] []
      graph =
        [ (executable, rootImage),
          (libraryA, machOImage ["@rpath/libB.dylib"] []),
          (libraryB, emptyImage),
          (firstChoice, emptyImage),
          (secondChoice, emptyImage),
          (loaderLibrary, emptyImage),
          (executableLibrary, emptyImage),
          (frameworkSource, emptyImage)
        ]
  plan <-
    requireRight
      "recursive Mach-O graph resolves"
      ( AppleInternal.resolveMachOPathsFixtureForTest
          candidateRoot
          executable
          graph
      )
  let copies = AppleInternal.machOFixturePlannedCopies plan
      expectedLibrary leaf =
        candidateRoot </> "native" </> "lib" </> leaf
  assertEqual
    "recursive inherited LC_RPATH includes the grandchild"
    (Just (expectedLibrary "libB.dylib"))
    (lookup libraryB copies)
  assertEqual
    "LC_RPATH search order selects the first existing path"
    (Just (expectedLibrary "libChoice.dylib"))
    (lookup firstChoice copies)
  assertEqual
    "LC_RPATH search order does not visit the second existing path"
    Nothing
    (lookup secondChoice copies)
  assertEqual
    "framework closure preserves its framework-relative destination"
    ( Just
        ( candidateRoot
            </> "native"
            </> "frameworks"
            </> "Fancy.framework"
            </> "Versions"
            </> "A"
            </> "Fancy"
        )
    )
    (lookup frameworkSource copies)
  assertEqual
    "system dependencies do not enter the copy plan"
    Nothing
    (lookup "/usr/lib/libSystem.B.dylib" copies)
  assertEqual
    "the recursive fixture records every visited image"
    7
    (AppleInternal.machOFixtureImageCount plan)
  assertEqual
    "the recursive fixture has no plugin root"
    0
    (AppleInternal.machOFixturePluginRootCount plan)

rejectedMachOClosureTest :: IO ()
rejectedMachOClosureTest = do
  let fixtureRoot = "/infernix-fixture/macho-rejected"
      candidateRoot = fixtureRoot </> "candidate"
      executable = fixtureRoot </> "bin" </> "tool"
      emptyImage = machOImage [] []
      resolve =
        AppleInternal.resolveMachOPathsFixtureForTest
          candidateRoot
          executable
  assertEqual
    "a graph without its exact executable is refused"
    True
    (isLeft (resolve []))
  assertEqual
    "an unresolved non-system dependency is refused"
    True
    ( isLeft
        ( resolve
            [ ( executable,
                machOImage [fixtureRoot </> "lib" </> "missing.dylib"] []
              )
            ]
        )
    )
  let firstCollision =
        fixtureRoot </> "first" </> "libCollision.dylib"
      secondCollision =
        fixtureRoot </> "second" </> "libCollision.dylib"
  assertEqual
    "different sources cannot share one owned destination"
    True
    ( isLeft
        ( resolve
            [ ( executable,
                machOImage [firstCollision, secondCollision] []
              ),
              (firstCollision, emptyImage),
              (secondCollision, emptyImage)
            ]
        )
    )
  forM_
    [ machOImage ["/usr/lib/../private/non-system.dylib"] [],
      machOImage [] ["../lib"],
      machOImage [] ["@rpath/other"],
      machOImage ["@loader_path/../outside.dylib"] []
    ]
    ( \invalidImage ->
        assertEqual
          "unsafe Mach-O path policy is refused"
          True
          (isLeft (resolve [(executable, invalidImage)]))
    )
  assertEqual
    "an oversized load-command declaration is refused"
    True
    ( isLeft
        ( AppleInternal.inspectMachOFixtureForTest
            (machOHeader 1 (4 * 1024 * 1024 + 1))
        )
    )

machOClosureBoundsTest :: IO ()
machOClosureBoundsTest = do
  let dependency = "/infernix-fixture/lib/libRuntime.dylib"
      rpath = "/infernix-fixture/lib"
      thin = machOImage [dependency] [rpath]
  assertEqual
    "a thin arm64 Mach-O fixture parses exact dependencies and rpaths"
    (Right ([dependency], [rpath]))
    (AppleInternal.inspectMachOFixtureForTest thin)
  assertEqual
    "a fat arm64 Mach-O fixture selects and parses its exact slice"
    (Right ([dependency], [rpath]))
    (AppleInternal.inspectMachOFixtureForTest (fatMachO thin))
  assertEqual
    "a non-Mach-O payload is refused"
    True
    (isLeft (AppleInternal.inspectMachOFixtureForTest "not-mach-o"))
  let fixtureRoot = "/infernix-fixture/macho-bounds"
      candidateRoot = fixtureRoot </> "candidate"
      executable = fixtureRoot </> "bin" </> "tool"
      primary = [fixtureRoot </> "lib" </> ("lib" <> show index <> ".dylib") | index <- [1 .. 256 :: Int]]
      secondary = [fixtureRoot </> "lib" </> ("lib" <> show index <> ".dylib") | index <- [257 .. 512 :: Int]]
      finalLibrary = fixtureRoot </> "lib" </> "lib513.dylib"
      oversizedGraph =
        ( executable,
          machOImage primary []
        )
          : (head primary, machOImage secondary [])
          : (primary !! 1, machOImage [finalLibrary] [])
          : [ (path, machOImage [] [])
            | path <- primary <> secondary <> [finalLibrary],
              path /= head primary,
              path /= primary !! 1
            ]
  assertEqual
    "more than 512 copied runtime images is refused"
    True
    ( isLeft
        ( AppleInternal.resolveMachOPathsFixtureForTest
            candidateRoot
            executable
            oversizedGraph
        )
    )
  let firstPlugin =
        "/opt/homebrew/Cellar/ggml/1.0/libexec/ggml-metal.dylib"
      secondPlugin =
        "/opt/homebrew/Cellar/ggml/2.0/libexec/ggml-cpu.dylib"
  assertEqual
    "more than one exact ggml plugin root is refused"
    True
    ( isLeft
        ( AppleInternal.resolveMachOPathsFixtureForTest
            candidateRoot
            executable
            [ (executable, machOImage [firstPlugin, secondPlugin] []),
              (firstPlugin, machOImage [] []),
              (secondPlugin, machOImage [] [])
            ]
        )
    )

withMaterializerFixture ::
  String ->
  (Paths -> FilePath -> IO result) ->
  IO result
withMaterializerFixture label action =
  bracket acquire removeFixture (uncurry action)
  where
    acquire = do
      temporaryRoot <- getTemporaryDirectory
      processId <- getProcessID
      nonce <- getMonotonicTimeNSec
      let fixtureRoot =
            temporaryRoot
              </> ( "infernix-apple-materializer-"
                      <> label
                      <> "-"
                      <> show processId
                      <> "-"
                      <> show nonce
                  )
          fixtureRepo = fixtureRoot </> "repo"
          fixtureData = fixtureRoot </> "data"
          hostConfig =
            HostConfig.defaultAppleHostNativeHostConfig
              (Text.pack fixtureRepo)
              (Text.pack fixtureRoot)
          paths =
            Paths
              { repoRoot = fixtureRepo,
                buildRoot = fixtureRepo </> ".build",
                dataRoot = fixtureData,
                runtimeRoot = fixtureData </> "runtime",
                kindRoot = fixtureData </> "kind",
                helmConfigRoot =
                  fixtureData </> "helm" </> "config",
                helmCacheRoot =
                  fixtureData </> "helm" </> "cache",
                helmDataRoot =
                  fixtureData </> "helm" </> "data",
                resultsRoot = fixtureData </> "results",
                modelCacheRoot = fixtureData </> "model-cache",
                pathsHostConfig = Just hostConfig
              }
      createDirectory fixtureRoot
      createDirectoryIfMissing True (fixtureRepo </> "python")
      createDirectory fixtureData
      pure (paths, fixtureRoot)
    removeFixture (paths, fixtureRoot) = do
      present <- doesPathExist fixtureRoot
      when present (removePathForcibly fixtureRoot)
      let candidate =
            AppleInternal.appleMaterializerFixtureCandidateRoot paths
      candidatePresent <- doesPathExist candidate
      when candidatePresent $
        fail
          ( "fixture cleanup left the synthetic candidate outside its root: "
              <> candidate
          )

createPriorRootMarker :: Paths -> IO FilePath
createPriorRootMarker paths = do
  let marker =
        dataRoot paths
          </> "engines"
          </> "prior-complete-root"
          </> "marker"
  createDirectoryIfMissing True (dataRoot paths </> "engines" </> "prior-complete-root")
  writeFile marker (repoRoot paths <> "\n")
  pure marker

assertCandidateRetired ::
  Paths ->
  AppleInternal.AppleMaterializerFixtureBoundary ->
  IO ()
assertCandidateRetired paths boundary = do
  candidatePresent <-
    doesPathExist
      (AppleInternal.appleMaterializerFixtureCandidateRoot paths)
  assertEqual
    ("candidate cleanup after " <> show boundary)
    False
    candidatePresent

assertPriorRootMarker ::
  FilePath ->
  FilePath ->
  AppleInternal.AppleMaterializerFixtureBoundary ->
  IO ()
assertPriorRootMarker marker fixtureRoot boundary = do
  markerContents <- readFile marker
  assertEqual
    ("prior root after " <> show boundary)
    ((fixtureRoot </> "repo") <> "\n")
    markerContents

machOImage :: [FilePath] -> [FilePath] -> ByteString.ByteString
machOImage dependencies rpaths =
  let commands =
        map machODylibCommand dependencies
          <> map machORpathCommand rpaths
   in ByteString.concat
        ( machOHeader
            (length commands)
            (sum (map ByteString.length commands))
            : commands
        )

machODylibCommand :: FilePath -> ByteString.ByteString
machODylibCommand =
  machOStringCommand 0x0000000c 24

machORpathCommand :: FilePath -> ByteString.ByteString
machORpathCommand =
  machOStringCommand 0x8000001c 12

machOStringCommand ::
  Int ->
  Int ->
  FilePath ->
  ByteString.ByteString
machOStringCommand command stringOffset value =
  ByteString.concat
    [ word32LE command,
      word32LE commandSize,
      word32LE stringOffset,
      ByteString.replicate (stringOffset - 12) 0,
      encoded,
      ByteString.replicate (commandSize - stringOffset - ByteString.length encoded) 0
    ]
  where
    encoded = ByteStringChar8.pack value <> ByteString.singleton 0
    commandSize = align8 (stringOffset + ByteString.length encoded)

machOHeader :: Int -> Int -> ByteString.ByteString
machOHeader commandCount commandBytes =
  ByteString.concat
    [ word32LE 0xfeedfacf,
      word32LE 0x0100000c,
      word32LE 0,
      word32LE 2,
      word32LE commandCount,
      word32LE commandBytes,
      word32LE 0,
      word32LE 0
    ]

fatMachO :: ByteString.ByteString -> ByteString.ByteString
fatMachO thin =
  ByteString.concat
    [ word32BE 0xcafebabe,
      word32BE 1,
      word32BE 0x0100000c,
      word32BE 0,
      word32BE sliceOffset,
      word32BE (ByteString.length thin),
      word32BE 0,
      thin
    ]
  where
    sliceOffset = 28

word32LE :: Int -> ByteString.ByteString
word32LE value =
  ByteString.pack
    [ octet 0,
      octet 8,
      octet 16,
      octet 24
    ]
  where
    octet shift = fromIntegral ((value `shiftR` shift) `mod` 256)

word32BE :: Int -> ByteString.ByteString
word32BE value =
  ByteString.pack
    [ octet 24,
      octet 16,
      octet 8,
      octet 0
    ]
  where
    octet shift = fromIntegral ((value `shiftR` shift) `mod` 256)

align8 :: Int -> Int
align8 value =
  ((value + 7) `div` 8) * 8

requireRight :: String -> Either String value -> IO value
requireRight label result =
  case result of
    Left failure -> fail (label <> ": " <> failure)
    Right value -> pure value

pause :: MVar () -> MVar () -> IO ()
pause entered resume = do
  putMVar entered ()
  takeMVar resume

assertThreadCancellation :: String -> MVar () -> IO () -> IO ()
assertThreadCancellation label entered action = do
  completed <- newEmptyMVar
  threadId <- forkFinally action (putMVar completed)
  takeMVar entered
  throwTo threadId ThreadKilled
  result <- takeMVar completed
  case result of
    Left failure
      | Just (_ :: SomeAsyncException) <- fromException failure ->
          pure ()
      | otherwise ->
          fail
            ( label
                <> " produced a synchronous exception: "
                <> displayException failure
            )
    Right () ->
      fail (label <> " unexpectedly completed")

assertLeft :: String -> Either failure result -> IO ()
assertLeft label result =
  case result of
    Left _ -> pure ()
    Right _ -> fail (label <> ": expected failure")

assertEqual ::
  (Eq value, Show value) =>
  String ->
  value ->
  value ->
  IO ()
assertEqual label expected actual =
  unless (actual == expected) $
    fail
      ( label
          <> ": expected "
          <> show expected
          <> ", observed "
          <> show actual
      )
