{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Service
  ( runService,
  )
where

import Control.Exception (IOException, bracketOnError, catch)
import Data.Text qualified as Text
import Infernix.ClusterConfig
  ( ClusterConfig,
    decodeClusterConfigFile,
    defaultClusterConfigMountPath,
  )
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.Runtime.Daemon (runProductionDaemon)
import Infernix.Types (DaemonRole (Coordinator, Engine), DemoConfig (..), RuntimeMode (AppleSilicon), runtimeModeId)
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
-- engine Deployments pass @--role coordinator@ and @--role engine@
-- through @args@; host-native flows omit the flag and fall back to
-- the active substrate dhall's @daemonRole@ field.
runService :: Maybe RuntimeMode -> Maybe DaemonRole -> Maybe Text.Text -> IO ()
runService maybeRuntimeMode maybeDaemonRole maybeEngineName = do
  paths <- discoverPaths
  ensureRepoLayout paths
  maybeClusterConfig <- tryLoadClusterConfig
  demoConfig <- decodeDemoConfigFile (generatedDemoConfigPath paths)
  runtimeMode <- resolveServiceRuntimeMode maybeRuntimeMode demoConfig
  let daemonRole = resolveServiceDaemonRole maybeDaemonRole demoConfig
  ensureServiceRuntimeSupported paths runtimeMode daemonRole
  whenAppleRuntimeReady paths runtimeMode daemonRole
  -- Phase 7 Sprint 7.23: Apple host engine singleton ownership is broker
  -- owned through the Pulsar batch-topic subscription. The local lock remains
  -- only as a non-Apple engine-role safety check while Kubernetes
  -- anti-affinity owns the Linux distributed placement rule.
  acquireEngineLockIfEngineRole paths runtimeMode daemonRole
  runProductionDaemon paths runtimeMode maybeClusterConfig daemonRole maybeEngineName

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

resolveServiceRuntimeMode :: Maybe RuntimeMode -> DemoConfig -> IO RuntimeMode
resolveServiceRuntimeMode maybeRuntimeMode demoConfig =
  case maybeRuntimeMode of
    Just runtimeMode
      | runtimeMode == configRuntimeMode demoConfig -> pure runtimeMode
      | otherwise ->
          ioError
            ( userError
                ( "service runtime override "
                    <> show (runtimeModeId runtimeMode)
                    <> " does not match demo config runtime "
                    <> show (runtimeModeId (configRuntimeMode demoConfig))
                )
            )
    Nothing -> pure (configRuntimeMode demoConfig)

-- | Phase 4 Sprint 4.13: typed CLI override replaces the previous
-- @lookupEnv "INFERNIX_DAEMON_ROLE"@ + 'String' parsing path. The
-- parser is now in 'Infernix.CommandRegistry'; this function just
-- threads the parsed value, falling back to the substrate dhall's
-- 'activeDaemonRole' when no override is supplied.
resolveServiceDaemonRole :: Maybe DaemonRole -> DemoConfig -> DaemonRole
resolveServiceDaemonRole maybeDaemonRoleOverride demoConfig =
  case maybeDaemonRoleOverride of
    Nothing -> activeDaemonRole demoConfig
    Just daemonRole -> daemonRole

ensureServiceRuntimeSupported :: Paths -> RuntimeMode -> DaemonRole -> IO ()
ensureServiceRuntimeSupported paths runtimeMode daemonRole =
  case (controlPlaneContext paths, runtimeMode, daemonRole) of
    (OuterContainer, AppleSilicon, Coordinator) -> pure ()
    _ -> ensureSupportedRuntimeModeForExecutionContext paths runtimeMode

whenAppleRuntimeReady :: Paths -> RuntimeMode -> DaemonRole -> IO ()
whenAppleRuntimeReady paths runtimeMode daemonRole =
  case (runtimeMode, daemonRole) of
    (AppleSilicon, Engine) -> ensureAppleSiliconRuntimeReady paths
    _ -> pure ()

-- | Path of the engine-role exclusive lock under the durable runtime root.
-- Each engine-role 'infernix service' process holds this lock for its
-- lifetime so a second engine cannot start on the same host while the
-- first is alive. Linux substrates additionally rely on Kubernetes
-- required pod anti-affinity at the chart layer; the lock keeps the
-- supported contract uniform across substrates.
engineLockPath :: Paths -> FilePath
engineLockPath paths = runtimeRoot paths </> "engine.lock"

acquireEngineLockIfEngineRole :: Paths -> RuntimeMode -> DaemonRole -> IO ()
acquireEngineLockIfEngineRole paths runtimeMode daemonRole =
  case (runtimeMode, daemonRole) of
    (AppleSilicon, Engine) -> pure ()
    (_, Engine) -> acquireEngineLock (engineLockPath paths)
    (_, Coordinator) -> pure ()

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
