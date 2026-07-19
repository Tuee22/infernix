module Infernix.Lint.HaskellStyle
  ( runHaskellStyleLint,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (when)
import Data.Char (isAlphaNum)
import Data.List (find, intercalate, isInfixOf, sort)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools qualified as HostTools
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getTemporaryDirectory,
    listDirectory,
    removeFile,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)

runHaskellStyleLint :: IO ()
runHaskellStyleLint = do
  paths <- discoverPaths
  createDirectoryIfMissing True (buildRoot paths)
  installFormatterTools paths
  let toolsRoot = formatterToolsBinRoot paths
      ormoluPath = toolsRoot </> "ormolu"
      hlintPath = toolsRoot </> "hlint"
  ormoluPresent <- doesFileExist ormoluPath
  hlintPresent <- doesFileExist hlintPath
  when
    (not ormoluPresent || not hlintPresent)
    (ioError (userError "haskell-style-check: formatter bootstrap did not produce ormolu and hlint"))
  sources <- haskellSources (repoRoot paths)
  runCommand (repoRoot paths) ormoluPath (["--mode", "check"] <> sources)
  runCommand (repoRoot paths) hlintPath ["Setup.hs", "app", "src", "test"]
  checkReadabilityRules (repoRoot paths) sources
  checkCabalManifest paths
  putStrLn "haskell-style-check: ok"

installFormatterTools :: Paths -> IO ()
installFormatterTools paths = do
  let toolsRoot = formatterToolsBinRoot paths
      ormoluPath = toolsRoot </> "ormolu"
      hlintPath = toolsRoot </> "hlint"
  ormoluPresent <- doesFileExist ormoluPath
  hlintPresent <- doesFileExist hlintPath
  when (not ormoluPresent || not hlintPresent) $ do
    cabalPath <- requireStyleCabal paths
    installResult <- try (installFormatterToolsWithCommand paths cabalPath (formatterInstallArgs paths)) :: IO (Either IOException ())
    case installResult of
      Right () -> pure ()
      Left installErr ->
        ioError
          ( userError
              ( "haskell-style-check: formatter bootstrap failed\nerror:\n"
                  <> show installErr
              )
          )

installFormatterToolsWithCommand :: Paths -> FilePath -> [String] -> IO ()
installFormatterToolsWithCommand paths =
  runCommand (repoRoot paths)

formatterInstallArgs :: Paths -> [String]
formatterInstallArgs paths =
  [ "--builddir=" <> formatterToolsBuildRoot paths,
    "install",
    "--installdir=" <> formatterToolsBinRoot paths,
    "--install-method=copy",
    "--overwrite-policy=always",
    "ormolu",
    "hlint"
  ]

formatterToolsRoot :: Paths -> FilePath
formatterToolsRoot paths = buildRoot paths </> "haskell-style-tools"

formatterToolsBuildRoot :: Paths -> FilePath
formatterToolsBuildRoot paths = formatterToolsRoot paths </> "cabal"

formatterToolsBinRoot :: Paths -> FilePath
formatterToolsBinRoot paths = formatterToolsRoot paths </> "bin"

checkCabalManifest :: Paths -> IO ()
checkCabalManifest paths = do
  let sourcePath = repoRoot paths </> "infernix.cabal"
  tempRoot <- getTemporaryDirectory
  (tempPath, tempHandle) <- openTempFile tempRoot "infernix.cabal"
  hClose tempHandle
  sourceContents <- readFile sourcePath
  writeFile tempPath sourceContents
  cabalPath <- requireStyleCabal paths
  runCommand (repoRoot paths) cabalPath ["format", tempPath]
  formattedContents <- readFile tempPath
  removeFile tempPath
  if formattedContents == sourceContents
    then pure ()
    else ioError (userError "haskell-style-check: infernix.cabal is not cabal-format clean")

haskellSources :: FilePath -> IO [FilePath]
haskellSources repoRoot = do
  sourceFiles <- concat <$> mapM (collectHsFiles . (repoRoot </>)) ["app", "src", "test"]
  pure (sort ("Setup.hs" : map (makeRelative repoRoot) sourceFiles))

collectHsFiles :: FilePath -> IO [FilePath]
collectHsFiles directoryPath = do
  exists <- doesDirectoryExist directoryPath
  if not exists
    then pure []
    else do
      children <- listDirectory directoryPath
      concat <$> mapM (collectChild . (directoryPath </>)) children
  where
    collectChild childPath = do
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then collectHsFiles childPath
        else do
          isFile <- doesFileExist childPath
          if isFile && hasHsExtension childPath
            then pure [childPath]
            else pure []

hasHsExtension :: FilePath -> Bool
hasHsExtension pathValue =
  reverse (take 3 (reverse pathValue)) == ".hs"

checkReadabilityRules :: FilePath -> [FilePath] -> IO ()
checkReadabilityRules repoRoot sourceFiles = do
  violations <- concat <$> mapM (checkSourceReadability repoRoot) sourceFiles
  case violations of
    [] -> pure ()
    _ ->
      ioError
        ( userError
            ( "haskell-style-check: readability rules failed\n"
                <> intercalate "\n" violations
            )
        )

checkSourceReadability :: FilePath -> FilePath -> IO [String]
checkSourceReadability repoRoot sourceFile = do
  contents <- readFile (repoRoot </> sourceFile)
  let numberedLines = zip [1 :: Int ..] (lines contents)
  pure
    ( hangingCaseViolations sourceFile numberedLines
        <> aliasCommentViolations sourceFile numberedLines
        <> envFunctionViolations sourceFile numberedLines
        <> bareNameProcViolations sourceFile numberedLines
        <> ambientToolLookupViolations sourceFile numberedLines
        <> engineRuntimeBoundaryViolations sourceFile numberedLines
        <> sharedPhase7BoundaryViolations sourceFile numberedLines
        <> realnessFabricationViolations sourceFile numberedLines
        <> escapeTokenViolations sourceFile numberedLines
        <> capabilityGatingViolations sourceFile numberedLines
    )

-- | Sprint 6.39 (managed-state-transition doctrine) — capability-gating lint.
-- Reject raw destructive shell primitives (@rm -rf@ / @docker exec ... rm@) and
-- empty subprocess environments (@env = Just []@). Retained-state deletion must
-- go through the lease-gated teardown (Sprint 2.14), and every subprocess must
-- carry a typed 'Infernix.Cluster.Subprocess.SubprocessEnv' (which always
-- carries @HOME@/@TMPDIR@) rather than an empty environment. The
-- cluster-lifecycle module owns the grandfathered container-scoped scrub surface
-- and is exempt from the raw-@rm@ rule; every other module is guarded. Canonical
-- doctrine: documents/architecture/managed_state_transitions.md.
capabilityGatingViolations :: FilePath -> [(Int, String)] -> [String]
capabilityGatingViolations sourceFile numberedLines =
  rawDestructiveViolations sourceFile numberedLines
    <> emptySubprocessEnvViolations sourceFile numberedLines
    <> unboundedExecViolations sourceFile numberedLines
    <> unboundedHttpViolations sourceFile numberedLines

rawDestructiveViolations :: FilePath -> [(Int, String)] -> [String]
rawDestructiveViolations sourceFile numberedLines
  | sourceFile `elem` rawDestructiveExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": " <> reason
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        reason <- rawDestructiveReasons lineValue
      ]

rawDestructiveReasons :: String -> [String]
rawDestructiveReasons lineValue =
  [ "forbidden raw `rm -rf` scrub; route retained-state deletion through the lease-gated teardown (Sprint 2.14; see documents/architecture/managed_state_transitions.md)"
  | any (`isInfixOf` lineValue) ["rm -rf", "rm -fr"]
  ]
    <> [ "forbidden `docker exec ... rm` destructive primitive; route through the lease-gated teardown (see documents/architecture/managed_state_transitions.md)"
       | "docker exec" `isInfixOf` lineValue,
         " rm " `isInfixOf` lineValue
       ]

rawDestructiveExemptedFiles :: [FilePath]
rawDestructiveExemptedFiles =
  [ -- The cluster-lifecycle module owns the container-scoped retained-state
    -- scrub surface (the `docker exec ... rm -rf` Harbor-registry-storage
    -- cleanup) and the lease-gated teardown of Sprint 2.14.
    "src/Infernix/Cluster.hs",
    -- This lint module names the forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

emptySubprocessEnvViolations :: FilePath -> [(Int, String)] -> [String]
emptySubprocessEnvViolations sourceFile numberedLines
  | sourceFile `elem` emptySubprocessEnvExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden empty subprocess environment `env = Just []`; build a typed Infernix.Cluster.Subprocess.SubprocessEnv (which always carries HOME/TMPDIR) instead (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        "env = Just []" `isInfixOf` lineValue
      ]

emptySubprocessEnvExemptedFiles :: [FilePath]
emptySubprocessEnvExemptedFiles =
  [ -- This lint module names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Sprint 3.15 (managed-state-transition doctrine) — reject raw unbounded
-- process spawns outside the bounded-command kernel. Every cluster-lifecycle
-- subprocess must go through
-- 'Infernix.Cluster.Subprocess.runBoundedCommand', which carries a required
-- 'Infernix.Cluster.Subprocess.Timeout' and returns a total
-- 'Infernix.Cluster.Subprocess.CommandOutcome', so an unbounded exec — the
-- class that produced the ~23-minute Harbor @docker pull@ hang — is
-- unrepresentable. The exemption list is deliberately shrinking: 'ProcessMonitor.hs'
-- was retired onto the kernel by Sprint 6.41; 'Cluster.hs' still holds the general
-- cluster subprocess helpers whose raw-exec migration is deferred; the
-- engine/runtime/host-tool spawn surface (long-lived inference runners, host
-- prerequisite probes, Python tooling) is a different domain not owned by the
-- cluster kernel. The kernel module and this lint module (which names the
-- tokens as literals) are permanently exempt. Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
unboundedExecViolations :: FilePath -> [(Int, String)] -> [String]
unboundedExecViolations sourceFile numberedLines
  -- The bounded-command doctrine governs the production cluster surface, not the
  -- test harness (which orchestrates real clusters) or the cabal @Setup.hs@.
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedExecExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden raw unbounded process spawn `" <> needle <> "`; route it through Infernix.Cluster.Subprocess.runBoundedCommand (a required Timeout + total CommandOutcome) so an unbounded exec is unrepresentable (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenUnboundedExecTokens,
        containsToken needle lineValue
      ]

forbiddenUnboundedExecTokens :: [String]
forbiddenUnboundedExecTokens =
  [ "readCreateProcessWithExitCode",
    "readProcessWithExitCode",
    "readProcess",
    "createProcess",
    "waitForProcess",
    "spawnProcess",
    "callProcess",
    "callCommand"
  ]

-- | Sprint 4.29 (managed-state-transition doctrine) — reject raw streaming HTTP
-- reads of an upstream body outside the bounded model-download wrapper. The
-- model-weight download from an untrusted third-party origin must go through
-- 'Infernix.Runtime.Pulsar.downloadUpstreamModelToFile', which sends a
-- User-Agent, bounds the transfer, and classifies the status into a total
-- @DownloadOutcome@ (so a rate-limit is retried with a bounded backoff, not
-- hammered forever). @withResponse@ — the streaming-body reader that pattern
-- powers — is therefore forbidden elsewhere in production code; trusted
-- in-cluster MinIO/Harbor calls use @httpLbs@ and are unaffected. Canonical
-- doctrine: documents/architecture/managed_state_transitions.md.
unboundedHttpViolations :: FilePath -> [(Int, String)] -> [String]
unboundedHttpViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedHttpExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden raw streaming HTTP read `withResponse`; route an upstream download through Infernix.Runtime.Pulsar.downloadUpstreamModelToFile (User-Agent + bounded transfer + total DownloadOutcome) so a rate-limited fetch is retried with backoff, not hammered forever (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        containsToken "withResponse" lineValue
      ]

unboundedHttpExemptedFiles :: [FilePath]
unboundedHttpExemptedFiles =
  [ -- Owns the single bounded upstream-download wrapper
    -- ('downloadUpstreamModelToFile'), the sole legitimate 'withResponse'.
    "src/Infernix/Runtime/Pulsar.hs",
    -- Names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

unboundedExecExemptedFiles :: [FilePath]
unboundedExecExemptedFiles =
  [ -- Owns the bounded-command kernel (the one legitimate raw spawn surface).
    "src/Infernix/Cluster/Subprocess.hs",
    -- Names the forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs",
    -- Cluster lifecycle surface: the general cluster subprocess helpers'
    -- raw-exec migration is deferred (ProcessMonitor.hs was retired, Sprint 6.41).
    "src/Infernix/Cluster.hs",
    -- Engine / runtime / host-tool spawn surface: a different domain (long-lived
    -- inference runners, host prerequisite probes, Python tooling) not owned by
    -- the cluster bounded-command kernel.
    "src/Infernix/CLI.hs",
    "src/Infernix/Engines/AppleSilicon.hs",
    "src/Infernix/Engines/LinuxNative.hs",
    "src/Infernix/HostPrereqs.hs",
    "src/Infernix/HostTools.hs",
    "src/Infernix/Lint/Files.hs",
    "src/Infernix/Python.hs",
    "src/Infernix/Runtime/Pulsar.hs",
    "src/Infernix/Runtime/Worker.hs",
    "src/Infernix/Workflow.hs"
  ]

-- | Phase 0 Sprint 0.13 (managed-state-transition doctrine) — the escape-token
-- gate. Inside the evidence-kernel modules the type system is the enforcement:
-- opaque newtypes with hidden constructors, rank-2 region leases, and total
-- 'Infernix.Cluster.Subprocess.CommandOutcome' values. The only two escapes GHC
-- cannot close from inside those modules are @unsafeCoerce@ (forge an opaque
-- evidence value past its hidden constructor) and @unsafePerformIO@ (let a
-- probe fabricate evidence purely, the same masked-failure the realness
-- contract rejects). Both are forbidden in the evidence modules; the type
-- system closes everything else, so the gate is deliberately scoped to that
-- small audit surface. Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
escapeTokenViolations :: FilePath -> [(Int, String)] -> [String]
escapeTokenViolations sourceFile numberedLines
  | sourceFile `notElem` escapeTokenScopedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden escape token `" <> needle <> "` in an evidence module; the managed-state-transition doctrine closes evidence with the type system and these two escapes would forge it (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenEscapeTokens,
        containsToken needle lineValue
      ]

-- | The evidence-kernel modules whose guarantees rest on the type system. The
-- list grows as later sprints add evidence-minting modules (the lease-gated
-- scrub, the sentinel commit, the token leases), so their escape surface is
-- gated the moment they land.
escapeTokenScopedFiles :: [FilePath]
escapeTokenScopedFiles =
  [ "src/Infernix/Evidence/Readiness.hs",
    "src/Infernix/Evidence/Lease.hs",
    "src/Infernix/Cluster/Subprocess.hs",
    -- Sprint 3.15: mints the opaque 'BlobServable' evidence (hidden ctor);
    -- forbid the two escapes that could forge it.
    "src/Infernix/Cluster/PublishImages.hs"
  ]

forbiddenEscapeTokens :: [String]
forbiddenEscapeTokens =
  [ "unsafeCoerce",
    "unsafePerformIO"
  ]

-- | Phase 6 Sprint 6.28 (initial landing — May 25, 2026): reject new
-- occurrences of @lookupEnv@ / @getEnv@ / @getEnvironment@ /
-- @setEnv@ / @unsetEnv@ outside the explicit exemption list. The
-- exemption list names the modules whose env retirements are
-- deferred to specific later sprints (Phase 7 Sprint 7.17 for the
-- credential-bearing reads, the Apple validation pass for the
-- Apple-only code paths). As those sprints close, their rows leave
-- this list and the gate tightens automatically.
envFunctionViolations :: FilePath -> [(Int, String)] -> [String]
envFunctionViolations sourceFile numberedLines
  | sourceFile == "Setup.hs" = setupHsEnvFunctionViolations sourceFile numberedLines
  | sourceFile `elem` envFunctionExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden env-IO call `" <> needle <> "`; route through HostConfig or a typed Dhall manifest"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenEnvFunctions,
        containsToken needle lineValue
      ]

forbiddenEnvFunctions :: [String]
forbiddenEnvFunctions =
  [ "lookupEnv",
    "getEnv",
    "getEnvironment",
    "setEnv",
    "unsetEnv"
  ]

-- | Realness lint mechanism (Phase 0 Sprint 0.12 governance) — realness by
-- construction. The generated native-engine runner must emit only real engine
-- output (or exit non-zero); it may never fabricate a result. This lint module
-- lists the fabrication tokens as literals and is itself out of scope, so it
-- does not trip its own check. The per-runner scope ('realnessScopedFiles') is
-- extended by each accelerator phase as it de-stubs, and now covers both
-- generated-runner modules: Phase 4 Sprint 4.21 added Engines/LinuxNative.hs;
-- Phase 1 Sprint 1.15 adds Engines/AppleSilicon.hs.
-- Canonical doctrine: documents/architecture/realness_contract.md.
realnessFabricationViolations :: FilePath -> [(Int, String)] -> [String]
realnessFabricationViolations sourceFile numberedLines
  | sourceFile `notElem` realnessScopedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden fabrication token `" <> needle <> "`; native runners must emit real engine output or exit non-zero (see documents/architecture/realness_contract.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenNativeFabricationTokens,
        needle `isInfixOf` lineValue
      ]

realnessScopedFiles :: [FilePath]
realnessScopedFiles =
  [ "src/Infernix/Engines/LinuxNative.hs",
    "src/Infernix/Engines/AppleSilicon.hs"
  ]

forbiddenNativeFabricationTokens :: [String]
forbiddenNativeFabricationTokens =
  -- NB: `np.zeros` is intentionally NOT forbidden — it is a fundamental NumPy
  -- primitive that real engines use legitimately for scratch buffers (e.g. the
  -- basic-pitch note-creation peak matrix). The fabrication signal is the
  -- constant artifact (`b64decode` of a literal) and the masking helpers; the
  -- fake-input-to-model pattern is prohibited by the realness doctrine + review.
  [ "emit_fallback_result",
    "infernix_emit_validation_result",
    "native-validation",
    "b64decode",
    "native fallback"
  ]

envFunctionExemptedFiles :: [FilePath]
envFunctionExemptedFiles =
  [ -- This lint module defines the forbidden tokens as string
    -- literals; it must exempt itself or the check trips on its own
    -- token list.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

setupHsEnvFunctionViolations :: FilePath -> [(Int, String)] -> [String]
setupHsEnvFunctionViolations sourceFile numberedLines =
  [ sourceFile <> ":" <> show lineNumber <> ": Setup.hs may only mutate PATH for the proto-lens custom-setup shim"
  | (lineNumber, lineValue) <- numberedLines,
    not (isCommentLine lineValue),
    needle <- forbiddenEnvFunctions,
    containsToken needle lineValue,
    not (allowedSetupEnvLine lineValue)
  ]

allowedSetupEnvLine :: String -> Bool
allowedSetupEnvLine lineValue =
  "qualified System.Environment as Env" `isInfixOf` lineValue
    || "Env.setEnv \"PATH\"" `isInfixOf` lineValue

-- | Phase 6 Sprint 6.28 (initial landing — May 25, 2026): reject
-- bare-name @proc "<command>"@ invocations whose name matches a
-- known external tool. The supported flow routes every invocation
-- through `Infernix.HostTools.runHostTool` so the absolute path
-- comes from the typed `HostConfig.toolPaths.*` record.
bareNameProcViolations :: FilePath -> [(Int, String)] -> [String]
bareNameProcViolations sourceFile numberedLines
  | sourceFile `elem` bareNameProcExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden bare-name `proc " <> show toolName <> "`; route through HostTools.runHostTool"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        toolName <- forbiddenBareProcCommands,
        let needle = "proc \"" <> toolName <> "\"",
        needle `isInfixOf` lineValue
      ]

-- | Derived from the 'HostTools.HostTool' enum (via 'HostTools.hostToolCommandNames')
-- so the forbidden bare-name set cannot drift from the registered host-tool set:
-- adding a 'HostTool' constructor automatically extends this gate.
forbiddenBareProcCommands :: [String]
forbiddenBareProcCommands = HostTools.hostToolCommandNames

bareNameProcExemptedFiles :: [FilePath]
bareNameProcExemptedFiles =
  [ -- This lint module lists forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 6 Sprint 6.28 follow-on: reject ambient executable discovery
-- for registered host tools. Supported invocation paths either read
-- absolute paths from HostConfig.toolPaths or use fixed absolute
-- fallback candidates from Infernix.HostTools.
ambientToolLookupViolations :: FilePath -> [(Int, String)] -> [String]
ambientToolLookupViolations sourceFile numberedLines
  | sourceFile `elem` ambientToolLookupExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden ambient host-tool lookup `" <> needle <> "`; route through HostTools and HostConfig.toolPaths"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenAmbientToolLookups,
        containsToken needle lineValue
      ]

forbiddenAmbientToolLookups :: [String]
forbiddenAmbientToolLookups =
  [ "findExecutable",
    "findExecutables"
  ]

ambientToolLookupExemptedFiles :: [FilePath]
ambientToolLookupExemptedFiles =
  [ -- This lint module lists forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 7 Sprint 7.8: keep the engine runtime surface from
-- importing frontend, coordinator, auth, object-presign, or WebSocket
-- modules. `Runtime.Daemon` owns role orchestration and may wire both
-- coordinator and engine loops, so this gate is scoped to the concrete
-- engine runtime modules.
engineRuntimeBoundaryViolations :: FilePath -> [(Int, String)] -> [String]
engineRuntimeBoundaryViolations sourceFile numberedLines
  | sourceFile `notElem` engineRuntimeBoundaryFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": engine runtime module must not import `" <> forbiddenModule <> "`"
      | (lineNumber, lineValue) <- numberedLines,
        let trimmedLine = trimWhitespace lineValue,
        not (isCommentLine lineValue),
        "import " `isPrefixOfString` trimmedLine,
        forbiddenModule <- forbiddenEngineRuntimeImports,
        forbiddenModule `isInfixOf` trimmedLine
      ]

engineRuntimeBoundaryFiles :: [FilePath]
engineRuntimeBoundaryFiles =
  [ "src/Infernix/Runtime.hs",
    "src/Infernix/Runtime/Cache.hs",
    "src/Infernix/Runtime/KVCache.hs",
    "src/Infernix/Runtime/Worker.hs"
  ]

forbiddenEngineRuntimeImports :: [String]
forbiddenEngineRuntimeImports =
  [ "Infernix.Demo.",
    "Infernix.Auth.Jwt",
    "Infernix.Objects.Presigned",
    "Infernix.Dispatch.SingleFlight",
    "Infernix.Bridge.Result",
    "Infernix.Bootstrap.Models",
    "Network.WebSockets"
  ]

-- | Phase 7 shared-library modules must remain product/runtime agnostic.
-- Conversation primitives are allowed to depend on generated wire contracts,
-- but not on demo application modules. The pure dispatcher/result/bootstrap
-- helpers must also stay out of runtime orchestration, auth, object-presign,
-- and WebSocket concerns.
sharedPhase7BoundaryViolations :: FilePath -> [(Int, String)] -> [String]
sharedPhase7BoundaryViolations sourceFile numberedLines =
  case lookup sourceFile sharedPhase7BoundaryFiles of
    Nothing -> []
    Just forbiddenImports ->
      [ sourceFile <> ":" <> show lineNumber <> ": shared Phase 7 module must not import `" <> forbiddenModule <> "`"
      | (lineNumber, lineValue) <- numberedLines,
        let trimmedLine = trimWhitespace lineValue,
        not (isCommentLine lineValue),
        "import " `isPrefixOfString` trimmedLine,
        forbiddenModule <- forbiddenImports,
        forbiddenModule `isInfixOf` trimmedLine
      ]

sharedPhase7BoundaryFiles :: [(FilePath, [String])]
sharedPhase7BoundaryFiles =
  map conversationBoundaryFile conversationPrimitiveFiles
    <> [ ( "src/Infernix/Dispatch/SingleFlight.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Dispatch/ContextModelMap.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Bridge/Result.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Bootstrap/Models.hs",
           productAgnosticHelperForbiddenImports
         )
       ]

conversationBoundaryFile :: FilePath -> (FilePath, [String])
conversationBoundaryFile sourceFile =
  (sourceFile, conversationForbiddenImports)

conversationPrimitiveFiles :: [FilePath]
conversationPrimitiveFiles =
  [ "src/Infernix/Conversation/Event.hs",
    "src/Infernix/Conversation/Hash.hs",
    "src/Infernix/Conversation/Idempotency.hs",
    "src/Infernix/Conversation/Reducer.hs",
    "src/Infernix/Conversation/Topic.hs"
  ]

conversationForbiddenImports :: [String]
conversationForbiddenImports =
  [ "Infernix.Demo",
    "Infernix.Runtime",
    "Infernix.Auth.Jwt",
    "Infernix.Objects.Presigned",
    "Network.WebSockets"
  ]

productAgnosticHelperForbiddenImports :: [String]
productAgnosticHelperForbiddenImports =
  conversationForbiddenImports
    <> [ "Infernix.Dispatch.SingleFlight",
         "Infernix.Bridge.Result",
         "Infernix.Bootstrap.Models"
       ]

isPrefixOfString :: String -> String -> Bool
isPrefixOfString expected value =
  case stripPrefix expected value of
    Just _ -> True
    Nothing -> False

hangingCaseViolations :: FilePath -> [(Int, String)] -> [String]
hangingCaseViolations sourceFile numberedLines =
  [ sourceFile <> ":" <> show lineNumber <> ": avoid hanging `case`; move it into a named helper or make it the outer expression"
  | (lineNumber, lineValue) <- numberedLines,
    not (isCommentLine lineValue),
    lineHasHangingCase lineValue
  ]

lineHasHangingCase :: String -> Bool
lineHasHangingCase lineValue =
  any
    (`isInfixOf` paddedLine)
    hangingCaseNeedles
  where
    paddedLine = " " <> lineValue <> " "

hangingCaseNeedles :: [String]
hangingCaseNeedles =
  [ "(" <> " case",
    "->" <> " case",
    "then" <> " case",
    "else" <> " case",
    "<-" <> " case",
    " in" <> " case "
  ]

aliasCommentViolations :: FilePath -> [(Int, String)] -> [String]
aliasCommentViolations sourceFile numberedLines =
  concatMap signatureViolations (signatureBlocks numberedLines)
  where
    signatureViolations (lineNumber, signatureLines) =
      [ sourceFile <> ":" <> show lineNumber <> ": aliased type `" <> aliasName <> "` needs comment `" <> requiredComment <> "`"
      | (aliasName, requiredComment) <- aliasedTypeComments,
        containsToken aliasName (unlines signatureLines),
        not (hasRequiredAliasComment requiredComment lineNumber numberedLines)
      ]

aliasedTypeComments :: [(String, String)]
aliasedTypeComments =
  [ ("Application", "-- type Application = Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived"),
    ("HostPreference", "-- type HostPreference = String"),
    ("InferenceResponse", "-- type InferenceResponse = Either (Status, ErrorResponse) InferenceResult"),
    ("PublishedImage", "-- type PublishedImage = (String, String)")
  ]

signatureBlocks :: [(Int, String)] -> [(Int, [String])]
signatureBlocks [] = []
signatureBlocks ((lineNumber, lineValue) : remainingLines)
  | isSignatureStart lineValue =
      let (continuation, rest) = span isSignatureContinuation remainingLines
       in (lineNumber, lineValue : map snd continuation) : signatureBlocks rest
  | otherwise = signatureBlocks remainingLines

isSignatureStart :: String -> Bool
isSignatureStart lineValue =
  not (startsWithSpace lineValue)
    && not (isCommentLine lineValue)
    && "::" `isInfixOf` lineValue

isSignatureContinuation :: (Int, String) -> Bool
isSignatureContinuation (_, lineValue) =
  null (trimWhitespace lineValue) || startsWithSpace lineValue || isCommentLine lineValue

startsWithSpace :: String -> Bool
startsWithSpace (' ' : _) = True
startsWithSpace ('\t' : _) = True
startsWithSpace _ = False

hasRequiredAliasComment :: String -> Int -> [(Int, String)] -> Bool
hasRequiredAliasComment requiredComment lineNumber numberedLines =
  requiredComment `elem` precedingNonBlankLines
  where
    precedingNonBlankLines =
      take
        6
        [ trimWhitespace candidateLine
        | (candidateLineNumber, candidateLine) <- reverse numberedLines,
          candidateLineNumber < lineNumber,
          not (null (trimWhitespace candidateLine))
        ]

containsToken :: String -> String -> Bool
containsToken token value =
  token `elem` tokenize value

tokenize :: String -> [String]
tokenize =
  words . map tokenCharacter
  where
    tokenCharacter character
      | isAlphaNum character || character == '_' || character == '\'' = character
      | otherwise = ' '

isCommentLine :: String -> Bool
isCommentLine lineValue =
  case trimWhitespace lineValue of
    '-' : '-' : _ -> True
    _ -> False

trimWhitespace :: String -> String
trimWhitespace =
  reverse . dropWhile (`elem` [' ', '\t']) . reverse . dropWhile (`elem` [' ', '\t'])

makeRelative :: FilePath -> FilePath -> FilePath
makeRelative root fullPath =
  fromMaybe fullPath (stripPrefix (root <> "/") fullPath)

runCommand :: FilePath -> FilePath -> [String] -> IO ()
runCommand workingDirectory command args = do
  (exitCode, stdoutOutput, stderrOutput) <- readCreateProcessWithExitCode (proc command args) {cwd = Just workingDirectory} ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> stdoutOutput <> stderrOutput))

requireStyleCabal :: Paths -> IO FilePath
requireStyleCabal paths =
  case configuredCabalPath paths of
    Just cabalPath -> pure cabalPath
    Nothing -> do
      fallback <- findFirstExisting (HostTools.hostToolFallbackCandidates HostTools.HostCabal)
      case fallback of
        Just cabalPath -> pure cabalPath
        Nothing ->
          ioError
            ( userError
                "haskell-style-check: cabal is unavailable through HostConfig.toolPaths.cabal and fixed fallback candidates"
            )

configuredCabalPath :: Paths -> Maybe FilePath
configuredCabalPath paths = do
  hostConfig <- pathsHostConfig paths
  let configured = HostConfig.hostCabal (HostConfig.hostToolPaths hostConfig)
  if Text.null configured
    then Nothing
    else Just (Text.unpack configured)

findFirstExisting :: [FilePath] -> IO (Maybe FilePath)
findFirstExisting candidates = do
  existing <-
    mapM
      ( \candidate -> do
          exists <- doesFileExist candidate
          pure (candidate, exists)
      )
      candidates
  pure (fst <$> find snd existing)

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing
