{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Service
  ( runService,
    serviceDemoConfigPath,
  )
where

import Control.Exception (IOException, bracketOnError, catch)
import Data.Text qualified as Text
import Infernix.ClusterConfig
  ( ClusterConfig (..),
    DemoBackendWiring (..),
    decodeClusterConfigFile,
    defaultClusterConfigMountPath,
  )
import Infernix.Config
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    compiledPlanRuntimeMode,
  )
import Infernix.HostConfig (MachineNode, machineNodeRole)
import Infernix.MachineContract
  ( requireDeclaredMachine,
    requireMachineContractPair,
    resolveMachineMemberId,
  )
import Infernix.Runtime.Daemon (runProductionDaemon)
import Infernix.Substrate (decodeCompiledRuntimePlanFile)
import Infernix.Types (DaemonRole (Coordinator, Engine, Webapp), RuntimeMode (AppleSilicon), runtimeModeId)
import Infernix.Webapp (runWebappRole)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory, (</>))
import System.IO (SeekMode (AbsoluteSeek), hPutStrLn, stderr)
import System.Posix.Files (touchFile)
import System.Posix.IO
  ( LockRequest (WriteLock),
    OpenFileFlags (creat),
    OpenMode (ReadWrite),
    closeFd,
    defaultFileFlags,
    fdWrite,
    getLock,
    openFd,
    setLock,
  )
import System.Posix.Process (getProcessID)

-- | Phase 4 Sprint 4.13: the supported daemon entrypoint. Both args
-- are now typed: 'maybeRuntimeMode' is the legacy host-side override
-- (unchanged), 'maybeDaemonRole' replaces the retired
-- @INFERNIX_DAEMON_ROLE@ env var. The chart-driven coordinator and
-- engine and webapp Deployments pass @--role coordinator@,
-- @--role engine@, and @--role webapp@ through @args@; host-native
-- flows omit the flag and fall back to this machine's contract. The optional
-- explicit config path supports targeted host-side validation without
-- rewriting the active generated substrate file.
--
-- Phase 8 Sprint 8.11: the machine contract is required here, and the generated
-- pair on disk is checked before any role is chosen. The pair check is local —
-- it proves this machine's manifest and this machine's system contract were
-- generated together — while the operational payload a daemon actually consumes
-- (which in a pod is the mounted publication) is covered by the contract digest
-- registered in the broker's topic properties.
runService :: Maybe RuntimeMode -> Maybe DaemonRole -> Maybe Text.Text -> Maybe FilePath -> IO ()
runService maybeRuntimeMode maybeDaemonRole maybeEngineName maybeDemoConfigPath = do
  paths <- discoverPaths
  ensureRepoLayout paths
  machineNode <- requireServiceMachineContract paths
  maybeClusterConfig <- tryLoadClusterConfig
  let selectedDemoConfigPath = serviceDemoConfigPath paths maybeClusterConfig maybeDemoConfigPath
  compiledPlanResult <- decodeCompiledRuntimePlanFile selectedDemoConfigPath
  compiledPlan <-
    case compiledPlanResult of
      Left errors ->
        ioError
          (userError ("generated substrate execution plan did not compile: " <> show errors))
      Right plan -> pure plan
  runtimeMode <- resolveServiceRuntimeMode maybeRuntimeMode compiledPlan
  let daemonRole = resolveServiceDaemonRole maybeDaemonRole machineNode
  ensureServiceRuntimeSupported paths runtimeMode daemonRole
  -- Identity is resolved before any preparation: a daemon that cannot say which
  -- member it is must refuse before it provisions a runtime or takes the engine
  -- lock, not after.
  resolvedEngineName <- resolveServiceEngineName daemonRole machineNode maybeEngineName
  whenAppleRuntimeReady paths runtimeMode daemonRole
  -- Phase 7 Sprint 7.23: Apple host engine singleton ownership is broker
  -- owned through the Pulsar batch-topic subscription. The local lock remains
  -- only as a non-Apple engine-role safety check while Kubernetes
  -- anti-affinity owns the Linux distributed placement rule.
  acquireEngineLockIfEngineRole paths runtimeMode daemonRole
  case daemonRole of
    Webapp -> runWebappRole paths runtimeMode maybeClusterConfig selectedDemoConfigPath
    _ -> runProductionDaemon paths runtimeMode maybeClusterConfig maybeDemoConfigPath daemonRole resolvedEngineName

-- | Phase 4 Sprint 4.13: best-effort load of the cluster manifest
-- mounted at the supported path. Cluster-resident pods have this
-- ConfigMap-mounted; host-native and unit-test paths do not, so the
-- absence is silently tolerated and downstream consumers fall back to
-- the substrate dhall + 'Paths' defaults.
tryLoadClusterConfig :: IO (Maybe ClusterConfig)
tryLoadClusterConfig = do
  let path = defaultClusterConfigMountPath
  exists <- doesFileExist path
  if exists
    then Just <$> decodeClusterConfigFile path
    else pure Nothing

serviceDemoConfigPath :: Paths -> Maybe ClusterConfig -> Maybe FilePath -> FilePath
serviceDemoConfigPath paths maybeClusterConfig maybeDemoConfigPath =
  case maybeDemoConfigPath of
    Just demoConfigPath -> demoConfigPath
    Nothing ->
      case maybeClusterConfig of
        Just clusterConfig ->
          let mountedPath = Text.unpack (demoConfigFilePath (clusterDemoBackend clusterConfig))
           in if null mountedPath then generatedDemoConfigPath paths else mountedPath
        Nothing -> generatedDemoConfigPath paths

resolveServiceRuntimeMode :: Maybe RuntimeMode -> CompiledRuntimePlan -> IO RuntimeMode
resolveServiceRuntimeMode maybeRuntimeMode compiledPlan =
  case maybeRuntimeMode of
    Just runtimeMode
      | runtimeMode == compiledPlanRuntimeMode compiledPlan -> pure runtimeMode
      | otherwise ->
          ioError
            ( userError
                ( "service runtime override "
                    <> show (runtimeModeId runtimeMode)
                    <> " does not match demo config runtime "
                    <> show (runtimeModeId (compiledPlanRuntimeMode compiledPlan))
                )
            )
    Nothing -> pure (compiledPlanRuntimeMode compiledPlan)

-- | Phase 4 Sprint 4.13: typed CLI override replaces the previous
-- @lookupEnv "INFERNIX_DAEMON_ROLE"@ + 'String' parsing path. The
-- parser is now in 'Infernix.CommandRegistry'; this function just
-- threads the parsed value.
--
-- Phase 8 Sprint 8.11: the fallback is this machine's contract rather than the
-- system contract. A role is a fact about the box a process runs on, not about
-- the platform every box shares — the split Deployments prove it, since three
-- roles run from one system contract and name themselves with @--role@.
resolveServiceDaemonRole :: Maybe DaemonRole -> MachineNode -> DaemonRole
resolveServiceDaemonRole maybeDaemonRoleOverride machineNode =
  case maybeDaemonRoleOverride of
    Nothing -> machineNodeRole machineNode
    Just daemonRole -> daemonRole

-- | Which declared member identity an engine process is.
--
-- Phase 8 Sprint 8.11: the machine contract is the source of engine identity,
-- so @--engine-name@ selects among the identities this machine declares rather
-- than among every member the platform compiles. The plan lookup downstream
-- still has to find that member in the pool graph, so a declared identity no
-- pool serves is a refusal too.
resolveServiceEngineName ::
  DaemonRole ->
  MachineNode ->
  Maybe Text.Text ->
  IO (Maybe Text.Text)
resolveServiceEngineName daemonRole machineNode requestedEngineName =
  case daemonRole of
    Engine ->
      case resolveMachineMemberId machineNode requestedEngineName of
        Right memberIdValue -> pure (Just memberIdValue)
        Left refusal -> ioError (userError refusal)
    Coordinator -> pure requestedEngineName
    Webapp -> pure requestedEngineName

-- | Require a declared machine contract, and require it to be paired with the
-- generated system contract sitting next to it.
requireServiceMachineContract :: Paths -> IO MachineNode
requireServiceMachineContract paths =
  case pathsHostConfig paths of
    Nothing ->
      ioError
        ( userError
            ( "host manifest missing at "
                <> hostConfigPath paths
                <> "; run `infernix init` to create ./infernix.dhall and ./infernix-host.dhall"
            )
        )
    Just hostConfig -> do
      requireMachineContractPair hostConfig (runtimeConfigPath paths)
      requireDeclaredMachine hostConfig

ensureServiceRuntimeSupported :: Paths -> RuntimeMode -> DaemonRole -> IO ()
ensureServiceRuntimeSupported paths runtimeMode daemonRole =
  case (controlPlaneContext paths, runtimeMode, daemonRole) of
    (OuterContainer, AppleSilicon, Coordinator) -> pure ()
    (OuterContainer, AppleSilicon, Webapp) -> pure ()
    _ -> ensureSupportedRuntimeModeForExecutionContext paths runtimeMode

whenAppleRuntimeReady :: Paths -> RuntimeMode -> DaemonRole -> IO ()
whenAppleRuntimeReady paths runtimeMode daemonRole =
  case (runtimeMode, daemonRole) of
    (AppleSilicon, Engine) -> ensureAppleSiliconRuntimeReady paths
    _ -> pure ()

-- | Path of the engine-role exclusive lock under the durable runtime root.
-- Each engine-role 'infernix service' process holds this lock for its
-- lifetime so a second engine cannot start on the same host while the
-- first is alive.
--
-- Phase 4 Sprint 4.34 removed the @apple-silicon@ waiver. It existed to let one
-- integration case run two host engine daemons on the same machine and assert
-- that they coexist on one @Shared@ subscription; that assertion is retired with
-- the waiver, because exactly one engine process per machine is a correctness
-- rule and not a scheduling preference — two processes hold two KV caches and
-- two copies of every loaded weight, and each admits work independently against
-- the whole machine's observed capacity.
--
-- What this lock does and does not do is worth stating: it is a host-local file
-- lock, so it excludes a second process on **this** machine and provably cannot
-- exclude one on another machine claiming the same member identity. The
-- cross-machine half is a broker-side member claim and is named as remaining
-- work in Phase 4 Sprint 4.34. Kubernetes placement is no longer part of this
-- contract at all: Phase 3 Sprint 3.16 deleted the engine pod anti-affinity,
-- which expressed the rule as a constraint the scheduler could leave
-- unsatisfied rather than as one that prevents a second process.
engineLockPath :: Paths -> FilePath
engineLockPath paths = runtimeRoot paths </> "engine.lock"

acquireEngineLockIfEngineRole :: Paths -> RuntimeMode -> DaemonRole -> IO ()
acquireEngineLockIfEngineRole paths _runtimeMode daemonRole =
  case daemonRole of
    Engine -> acquireEngineLock (engineLockPath paths)
    Coordinator -> pure ()
    Webapp -> pure ()

-- | Acquire an exclusive write lock on the supplied lock-file path. On
-- contention the helper reads the existing holder's PID (written into the
-- lock file at acquisition time below) and surfaces it through a fail-fast
-- diagnostic. The lock is released only when the file descriptor closes,
-- which happens automatically when the engine process exits — there is no
-- explicit @releaseEngineLock@ in the supported contract.
acquireEngineLock :: FilePath -> IO ()
acquireEngineLock lockPath = do
  createDirectoryIfMissing True (takeDirectory lockPath)
  -- Ensure the lock file exists so 'openFd' below succeeds with @creat = Nothing@-style
  -- semantics on subsequent runs. 'touchFile' is a no-op when the file already exists.
  touchFile lockPath `catch` (\(_ :: IOException) -> pure ())
  fd <-
    bracketOnError
      (openFd lockPath ReadWrite (defaultFileFlags {creat = Just 0o644}))
      closeFd
      pure
  maybeHolder <- getLock fd (WriteLock, AbsoluteSeek, 0, 0)
  case maybeHolder of
    Just (holderPid, _) -> do
      closeFd fd
      hPutStrLn stderr ("engine.lock held by PID " <> show holderPid)
      ioError
        ( userError
            ( "engine.lock at "
                <> lockPath
                <> " is held by PID "
                <> show holderPid
                <> "; refusing to start a second engine on this host"
            )
        )
    Nothing -> do
      setLock fd (WriteLock, AbsoluteSeek, 0, 0)
      -- Persist our own PID for the next contender's diagnostic.
      pid <- getProcessID
      _ <- fdWrite fd (show pid <> "\n")
      pure ()
