{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Cluster
  ( AbsentConfigRecovery (..),
    RecordedNamespaceRelation (..),
    classifyAbsentConfigRecovery,
    clusterWorkloadArchitectureForHostArchitecture,
    clusterDown,
    clusterDownHarness,
    clusterStatus,
    clusterUp,
    clusterUpHarness,
    cleanupHarnessRuntimeState,
    ClusterMutationLocked,
    ClusterTeardownAuthority,
    clusterTeardownAuthorityRegionWitness,
    withClusterLifecycleLock,
    requireBoundedCommandActivitiesQuiescent,
    beginHarnessConfigTransaction,
    completeHarnessConfigTransaction,
    reconcileInterruptedHarnessState,
    reconcileInterruptedHarnessStateAt,
    withRuntimeConfigWriteAccess,
    withRuntimeConfigWriteAccessAt,
    RetainedReplayPlan (..),
    retainedReplayPlan,
    retainedReplayPending,
    preWorkloadRecoveryIntentMatches,
    KindKubeconfigRecoveryPlan (..),
    kindKubeconfigRecoveryPlan,
    SnapshotRecoveryAction (..),
    snapshotRecoveryPlan,
    WorkerPauseState (..),
    classifyWorkerPauseObservation,
    snapshotClaimNodeBindingsForPausedWorkers,
    withHarnessClusterSlot,
    withHarnessClusterSlotAt,
    seizeHarnessClusterSlotAt,
    releaseHarnessClusterSlotAt,
    reclaimHarnessClusterSlot,
    reclaimHarnessClusterSlotAt,
    authorizeClusterOwnership,
    ClusterCheckoutIdentity (..),
    clusterCheckoutIdentityFromHostRoot,
    ClusterSlotIdentity (..),
    ClusterSlotAdmission (..),
    ClusterOwnershipRefusalReason (..),
    authorizeHarnessReservationAccess,
    authorizeRuntimeConfigWriteAccess,
    withDelegatedHarnessChildGroup,
    uncordonResultsProveReady,
    withPersistedClusterMutation,
    ClusterOwnershipRefusal (..),
    HelmDeployPhase (..),
    kindControlPlaneNodeName,
    linuxGpuNvkindConfigMapBug,
    linuxGpuSupportedOnHost,
    loadClusterState,
    pulsarBootstrapLogIndicatesDirtyState,
    renderHelmValues,
    renderKindConfig,
    renderFleetMachineContracts,
    clusterFleetEngineDeployments,
    finalPhaseDeployments,
    fleetSlotLabelKey,
    perEngineDeploymentNames,
    runPlaywrightPrepareEngine,
    runKubectlCompat,
    writeGeneratedKindConfig,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, SomeException, bracket, displayException, mask, throwIO, try)
import Control.Monad (forM_, unless, void, when)
import Data.Aeson (FromJSON (parseJSON), Value (..), eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (isAlphaNum, isSpace)
import Data.Either (isRight)
import Data.IORef (atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, mapMaybe, maybeToList)
import Data.Text qualified as Text
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import Data.Vector qualified as Vector
import Infernix.Cluster.ClaimPermissions qualified as ClaimPermissions
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.Discover
import Infernix.Cluster.ImageFingerprint
import Infernix.Cluster.Invoke
  ( commandOutcomeToEither,
    invokeClusterCommand,
    renderBoundedCommandOutcome,
    tryClusterCommand,
  )
import Infernix.Cluster.LifecycleLock
  ( kernelFileLockIsHeld,
    withKernelFileLock,
    withLifecycleFileLock,
  )
import Infernix.Cluster.MutationRecovery
  ( InterruptedMutationRecoveryEffects (..),
    runInterruptedMutationRecovery,
  )
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.ClusterConfig
  ( KeycloakWiring (keycloakBaseUrl, keycloakClientId, keycloakJwksUrl),
    defaultClusterConfig,
    defaultKeycloakWiring,
    renderClusterConfig,
  )
import Infernix.Config (ControlPlaneContext (..), Paths (..), controlPlaneContextId)
import Infernix.Config qualified as Config
import Infernix.DemoConfig (renderGeneratedDemoConfigPayload, resolveInferenceMemoryBudget, restampMachineContractPin)
import Infernix.DemoConfig.Internal (decodeBootstrapDemoConfigFile, decodeDemoConfigFile)
import Infernix.DhallSchema.Enums (daemonRoleToDhall)
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.Error
  ( InfernixError (ClusterStateDecodeFailure),
    bracketPreservingPrimary,
    finallyPreservingPrimary,
    onExceptionPreservingPrimary,
    runCleanupsPreservingFailures,
  )
import Infernix.Evidence.Lease (Acquire (..), Lease, leasePayload, withLease)
import Infernix.Evidence.Readiness qualified as Readiness
import Infernix.HostConfig qualified as HostConfig
import Infernix.MachineContract (SystemContractDigest, digestSystemContractFile, systemContractDigestText)
import Infernix.Models
import Infernix.ProcessIdentity
  ( ProcessBirthIdentity (..),
    ProcessNamespaceIdentity,
    observeCurrentProcessNamespaceIdentity,
    parseProcessNamespaceIdentity,
    readProcessBirthIdentity,
    registerCurrentProcessIdentity,
    renderProcessNamespaceIdentity,
  )
import Infernix.Routes (routeHelmValues)
import Infernix.Runtime.Pulsar (WarmModelCacheOutcome (..), waitForEagerModelCacheReady)
import Infernix.Storage
import Infernix.Types
import Infernix.Workflow (platformCommandsAvailable)
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    method,
    newManager,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
    urlEncodedBody,
  )
import Network.HTTP.Types.Header (Header)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import Network.Socket qualified as Socket
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, getTemporaryDirectory, listDirectory, removeFile, removePathForcibly, renameDirectory, renameFile)
import System.FilePath (addTrailingPathSeparator, dropTrailingPathSeparator, normalise, takeDirectory, takeFileName, (</>))
import System.IO (hClose, hIsClosed, hPutStr, openBinaryTempFile)
import System.IO.Error (isDoesNotExistError)
import System.Info qualified
import System.Posix.Process (createProcessGroupFor, getProcessGroupID, getProcessID)
import System.Posix.Signals (nullSignal, signalProcessGroup)
import Text.Read (readMaybe)

clusterStatePath :: Paths -> FilePath
clusterStatePath paths = runtimeRoot paths </> "cluster-state.state"

clusterLifecycleLockPath :: Paths -> FilePath
clusterLifecycleLockPath paths =
  runtimeRoot paths </> "locks" </> "cluster-lifecycle.lock"

harnessReservationPath :: Paths -> FilePath
harnessReservationPath paths =
  runtimeRoot paths </> "locks" </> "harness-cluster-slot.reserved"

harnessLifetimeLockPath :: Paths -> FilePath
harnessLifetimeLockPath paths =
  runtimeRoot paths </> "locks" </> "harness-cluster-slot.held"

data ClusterMutationLocked = ClusterMutationLocked

data HarnessConfigTransaction
  = HarnessConfigUntouched
  | HarnessConfigRestorePending
  | HarnessConfigRemovePending
  | HarnessConfigRestored
  deriving (Eq, Show)

data HarnessReservation = HarnessReservation
  { harnessReservationOwnerPid :: Integer,
    harnessReservationProcessGroup :: Integer,
    harnessReservationOwnerBirthIdentity :: Maybe ProcessBirthIdentity,
    harnessReservationOwnerPidNamespace :: Maybe ProcessNamespaceIdentity,
    harnessReservationConfigTransaction :: HarnessConfigTransaction,
    -- | The process group of the one toolchain child the reservation owner is
    -- currently running, when that child was placed in a group of its own.
    --
    -- Phase 1 Sprint 1.21 gives every bounded toolchain child a fresh process
    -- group so exceptional cleanup can signal an owned group without signalling
    -- the harness itself. That made process-group equality stop meaning \"this
    -- is the harness's own work\": the cluster-owned suites run *inside* such a
    -- child, and their @internal materialize-substrate@ writes and cluster
    -- mutations were refused by the reservation their own parent minted.
    -- Registering the child's group keeps both properties — the child stays
    -- separately killable, and it is still recognisably the harness.
    --
    -- This is authority delegated for one child's lifetime, not a second owner:
    -- only the owner registers it, it is cleared when that child is reaped, and
    -- every authorization still requires the owner itself to be verified alive,
    -- so a registration that outlives a crashed harness authorizes nothing.
    harnessReservationAuthorizedChildGroup :: Maybe Integer
  }
  deriving (Eq, Show)

data ClusterReservationAccess
  = OperatorReservationAccess
  | HarnessReservationAccess HarnessReservation
  deriving (Eq)

data HarnessReservationOwnerStatus
  = HarnessReservationOwnerVerifiedAlive
  | HarnessReservationOwnerDefinitelyDead
  | HarnessReservationOwnerUnverifiable
  deriving (Eq, Show)

data RecordedNamespaceRelation
  = RecordedNamespaceMatches
  | RecordedNamespaceIsForeign
  | RecordedNamespaceCannotBeCompared
  deriving (Eq, Show)

data HarnessReservationOwnerInspection = HarnessReservationOwnerInspection
  { inspectedOwnerStatus :: HarnessReservationOwnerStatus,
    inspectedCurrentPidNamespace :: Maybe ProcessNamespaceIdentity,
    inspectedNamespaceRelation :: RecordedNamespaceRelation,
    inspectedLifetimeLockHeld :: Bool
  }

-- | Serialize every cluster mutation across CLI processes and threads. The
-- non-blocking exclusive file lock makes independent acquisitions contend
-- within and across processes, and the kernel releases it after normal exit
-- or process death.
withClusterLifecycleLock ::
  Paths ->
  (forall s. Lease s ClusterMutationLocked -> IO a) ->
  IO a
withClusterLifecycleLock paths action = do
  let lockPath = clusterLifecycleLockPath paths
  createDirectoryIfMissing True (takeDirectory lockPath)
  withLifecycleFileLock lockPath $
    withLease
      Acquire
        { acquireEstablish = pure ClusterMutationLocked,
          acquireRelease = \_ -> pure ()
        }
      action

-- | Require that the bounded-command kernel has no live activity for one
-- owner process group without exposing the command construction or execution
-- capabilities themselves.
requireBoundedCommandActivitiesQuiescent :: Paths -> Integer -> IO ()
requireBoundedCommandActivitiesQuiescent paths ownerProcessGroup =
  Subprocess.withBoundedCommandActivitiesQuiescent
    paths
    ownerProcessGroup
    (const (pure ()))

nodeMountedKindRoot :: FilePath
nodeMountedKindRoot = "/var/infernix-data"

data ClusterUpInputs = ClusterUpInputs
  { clusterUpControlPlane :: ControlPlaneContext,
    clusterUpRequestedEdgePort :: Int,
    clusterUpRequestedRegistryPort :: Int,
    clusterUpRequestedPulsarHttpPort :: Int,
    clusterUpDemoUiEnabled :: Bool,
    clusterUpDemoConfigPath :: FilePath,
    clusterUpKubeconfigPath :: FilePath,
    clusterUpPublishedCatalogPath :: FilePath,
    clusterUpConfigMapManifestPath :: FilePath,
    clusterUpMountedCatalogPath :: FilePath,
    clusterUpEngineMemberIds :: [Text.Text],
    clusterUpFleetMachineContracts :: [(Int, String)],
    clusterUpPayload :: Lazy.ByteString
  }

-- | Phase 7 Sprint 7.7: the supported three-role daemon split retired
-- the fused @infernix-service@ Deployment. The supported finalisation
-- waits on the new @infernix-coordinator@ + @infernix-engine@ rollouts
-- (see 'finalPhaseDeployments'), so this gate is now @False@ across
-- every substrate. Kept as a one-shot constant so a future re-introduction
-- of a single-role fused deployment can flip it back without rewriting
-- every reference.
clusterServiceEnabled :: RuntimeMode -> Bool
clusterServiceEnabled _runtimeMode = False

helmRepositories :: [Command.HelmRepository]
helmRepositories =
  [ Command.PerconaRepo,
    Command.PulsarRepo,
    Command.BitnamiRepo,
    Command.NvidiaPluginRepo
  ]

-- | Phase 3 Sprint 3.11 (2026-05-29): the bitnami minio sub-chart is
-- retired in favor of the hand-authored MinIO StatefulSet under
-- `chart/templates/minio/`, so the Helm dependency closure no longer
-- includes `chart/charts/minio-17.0.21.tgz`.
helmDependencyArchives :: [FilePath]
helmDependencyArchives =
  [ "chart/charts/pg-operator-2.9.0.tgz",
    "chart/charts/pg-db-2.9.0.tgz",
    "chart/charts/pulsar-4.5.0.tgz",
    "chart/charts/gateway-helm-v1.7.2.tgz"
  ]

envoyGatewayDependencyArchive :: FilePath
envoyGatewayDependencyArchive = "chart/charts/gateway-helm-v1.7.2.tgz"

helmDependencyArchivesDirectory :: Paths -> FilePath
helmDependencyArchivesDirectory paths = repoRoot paths </> "chart/charts"

-- | Phase 7 Sprint 7.7 / 7.24: the supported daemon-split wait list.
-- Production-shaped @demo_ui = false@ topologies still bring up the
-- coordinator because it owns request fan-in, model-to-pool routing,
-- result writeback, and model bootstrap. Only the browser demo and
-- Keycloak remain demo-gated. The retired @infernix-service@
-- Deployment is no longer part of the chart.
finalPhaseDeployments :: ClusterState -> [String]
finalPhaseDeployments state =
  baseDeployments
    <> [deployment | clusterStateHasDemoUi state, deployment <- demoDeployments]
  where
    baseDeployments =
      ["deployment/infernix-coordinator"]
        <> engineDeployments
        <> map (("deployment/infernix-engine-" <>) . Text.unpack) (perEngineDeploymentNames (clusterRuntimeMode state))
        <> [deployment | clusterServiceEnabled (clusterRuntimeMode state), deployment <- ["deployment/infernix-service"]]
    -- Phase 8 Sprint 8.12: the fleet lane replaces the single shared engine
    -- workload with one Deployment per machine, so the rollout wait list has to
    -- name the machines the Kind topology was created for. A single-machine
    -- deployment is unchanged.
    engineDeployments =
      case clusterFleetEngineDeployments state of
        [] -> ["deployment/infernix-engine"]
        fleetDeployments -> fleetDeployments
    demoDeployments =
      [ "deployment/infernix-demo",
        "deployment/infernix-keycloak"
      ]

-- | Phase 8 Sprint 8.12 — the machines this cluster deploys an engine for.
--
-- Empty means the deployed single-node topology: one shared @infernix-engine@
-- Deployment. It is empty for every one-machine contract and for every Apple
-- deployment, because Apple engine members are host daemons rather than pods —
-- a fleet there is two Macs, which the cluster does not deploy and must not
-- pretend to.
clusterFleetMachines :: ClusterState -> [(Int, Text.Text)]
clusterFleetMachines state =
  case clusterRuntimeMode state of
    AppleSilicon -> []
    _
      | engineMachineCountValue (engineMachineCountFromMemberIds memberIds) <= 1 -> []
      | otherwise -> zip [1 ..] memberIds
  where
    memberIds = clusterEngineMemberIds state

-- | The Deployment names a fleet's machines are deployed under.
--
-- The name is keyed on the machine's slot rather than on its member id: a
-- Deployment name has to leave room for the ReplicaSet and pod suffixes
-- Kubernetes appends, and a member id is operator-facing text of unbounded
-- length. The identity itself travels in the machine contract and in
-- @--engine-name@, where its length costs nothing.
clusterFleetEngineDeployments :: ClusterState -> [String]
clusterFleetEngineDeployments state =
  [ "deployment/" <> fleetEngineWorkloadName slot
  | (slot, _memberIdValue) <- clusterFleetMachines state
  ]

fleetEngineWorkloadName :: Int -> String
fleetEngineWorkloadName slot = "infernix-engine-m" <> show slot

finalPhaseStatefulSets :: [String]
finalPhaseStatefulSets =
  [ "statefulset/infernix-infernix-pulsar-bookie",
    "statefulset/infernix-infernix-pulsar-broker",
    "statefulset/infernix-infernix-pulsar-proxy",
    "statefulset/infernix-infernix-pulsar-recovery",
    "statefulset/infernix-infernix-pulsar-toolset",
    "statefulset/infernix-infernix-pulsar-zookeeper",
    "statefulset/infernix-minio"
  ]

-- | Phase 3 Sprint 3.17: the in-cluster registry is one Deployment.
--
-- What this list used to hold is the clearest measure of the change: five
-- Deployments (core, jobservice, nginx, portal, registry) plus two StatefulSets
-- (redis, trivy), each of which had to roll out before the platform could be
-- called up.
registryFinalPhaseDeployments :: [String]
registryFinalPhaseDeployments =
  ["deployment/infernix-registry"]

registryFinalPhaseStatefulSets :: [String]
registryFinalPhaseStatefulSets =
  ["statefulset/infernix-minio"]

nvidiaDevicePluginVersion :: String
nvidiaDevicePluginVersion = "0.17.1"

kindNodeImage :: String
kindNodeImage = "kindest/node:v1.34.0"

registryBootstrapHelmTimeout :: Command.HelmDuration
registryBootstrapHelmTimeout = Command.HelmSeconds 90

data HelmDeployPhase
  = WarmupPhase
  | BootstrapPhase
  | RegistryFinalPhase
  | KeycloakStoragePhase
  | PulsarReadyPhase
  | FinalPhase

isAppleHostedLinuxCpuLocalTopology :: Paths -> ControlPlaneContext -> RuntimeMode -> Bool
isAppleHostedLinuxCpuLocalTopology paths controlPlane runtimeMode =
  controlPlane == OuterContainer
    && runtimeMode == LinuxCpu
    && HostConfig.normalizeHostArchitecture (hostArchitectureForPaths paths) == "arm64"

data OperatorManagedClaim = OperatorManagedClaim
  { operatorClaimNamespace :: String,
    operatorClaimCluster :: String,
    operatorClaimInstanceSet :: String,
    operatorClaimRole :: String,
    operatorClaimDataKind :: String,
    operatorClaimInstance :: String,
    operatorClaimRepository :: String,
    operatorClaimPvcName :: String,
    operatorClaimRequestedStorage :: String
  }

postgresOperatorDeployment :: String
postgresOperatorDeployment = "deployment/infernix-postgres-operator"

-- | Phase 3 Sprint 3.17: the platform's only Patroni PostgreSQL cluster.
--
-- The registry carries no database at all, so the cluster that used to back it
-- is gone and Keycloak's is the one that remains. The startup-readiness and
-- stuck-pod-restart machinery below is retained and re-pointed here rather than
-- deleted with the registry's database: it handles a real Patroni startup flake
-- and that flake is a property of the operator, not of what sits on top of it.
patroniPostgresClusterName :: String
patroniPostgresClusterName = "keycloak-postgresql"

-- | Phase 3 Sprint 3.16: one Patroni instance per platform service, so one data
-- claim rather than three.
patroniPostgresExpectedDataClaims :: Int
patroniPostgresExpectedDataClaims = 1

patroniPostgresStartupRepairGraceAttempts :: Int
patroniPostgresStartupRepairGraceAttempts = 18

-- | Phase 7 Sprint 7.1 / Phase 3 Sprint 3.17: @keycloak-postgresql@ is an
-- operator-managed Patroni cluster that lands in FinalPhase, and since the
-- registry stopped carrying a database it is the only one. Phase 3 Sprint 3.16
-- collapsed it to one instance, so it contributes 2 operator-managed PVCs
-- (1 data + 1 pgbackrest repo), and the FinalPhase reconcile waits for that
-- total before declaring the PV side ready.
--
-- Nothing operator-managed lands earlier now: the warmup phase brings up the
-- Percona operator itself and no cluster for it to reconcile.
keycloakPostgresExpectedOperatorClaims :: Int
keycloakPostgresExpectedOperatorClaims = 2

finalPhaseExpectedOperatorClaims :: Int
finalPhaseExpectedOperatorClaims = keycloakPostgresExpectedOperatorClaims

keycloakRealmName :: String
keycloakRealmName = "infernix"

keycloakSpaClientId :: String
keycloakSpaClientId = "infernix-spa"

keycloakLoginThemeName :: String
keycloakLoginThemeName = "infernix"

keycloakAdminSecretName :: String
keycloakAdminSecretName = "infernix-keycloak-admin"

data KeycloakAdminCredentials = KeycloakAdminCredentials
  { keycloakAdminUsername :: String,
    keycloakAdminPassword :: String
  }

newtype KeycloakAdminToken = KeycloakAdminToken
  { keycloakAdminAccessToken :: Text.Text
  }

instance FromJSON KeycloakAdminToken where
  parseJSON = withObject "KeycloakAdminToken" $ \value ->
    KeycloakAdminToken <$> value .: "access_token"

-- | Phase 3 Sprint 3.16: one instance per platform service, so one zookeeper
-- pod. The retired ordinals 1 and 2 named an ensemble that no longer exists;
-- scanning for them found nothing and read as a clean scan.
pulsarBootstrapRepairLogTargets :: [String]
pulsarBootstrapRepairLogTargets =
  [ "infernix-infernix-pulsar-zookeeper-0",
    "infernix-infernix-pulsar-broker-0",
    "infernix-infernix-pulsar-bookie-0",
    "infernix-infernix-pulsar-recovery-0"
  ]

-- | Phase 3 Sprint 3.16: the retired markers were ensemble-shaped —
-- unresolvable bookie ordinals 1 and 2, and a @QuorumCoverage(e:2,w:2,a:2)@
-- that a one-bookie managed ledger cannot produce. They are deleted with the
-- topology that produced them rather than left as conditions nothing can meet.
pulsarBootstrapDirtySingleLogMarkers :: [String]
pulsarBootstrapDirtySingleLogMarkers =
  [ "Unable to load database on disk",
    "InvalidCookieException",
    "NoNode for /ledgers/cookies"
  ]

clusterStateHasDemoUi :: ClusterState -> Bool
clusterStateHasDemoUi state =
  any ((`elem` ["/", "/api"]) . path) (routes state)

persistClusterState :: Paths -> ClusterState -> IO ()
persistClusterState paths state = do
  let publicationPath = Config.publicationStatePath paths
  createDirectoryIfMissing True (takeDirectory publicationPath)
  writeClusterStateFile (clusterStatePath paths) state
  writeFile publicationPath (renderPublicationState (Config.controlPlaneContext paths) state)

-- | Sprint 2.14: record an in-progress lifecycle phase on the typed
-- 'clusterLifecycle' machine. The free-form @action@ string is parsed into a
-- closed 'LifecycleTransition' (a typo fails loud rather than persisting an
-- unresumable phase), and the resulting in-progress position preserves whether
-- the Kind cluster is already present: a bring-up phase before the API is
-- reachable is 'ClusterProvisioning', afterward 'ClusterActivating', and a
-- teardown phase is 'ClusterTearingDown'.
setLifecycleProgress :: Paths -> ClusterState -> String -> String -> String -> Bool -> IO ClusterState
setLifecycleProgress paths state action phase detail emitMarker = do
  now <- getCurrentTime
  transition <- requireLifecycleTransition action
  let phaseValue =
        LifecyclePhase
          { lifecyclePhaseTransition = transition,
            lifecyclePhaseName = phase,
            lifecyclePhaseDetail = detail,
            lifecyclePhaseHeartbeatAt = now
          }
      lifecycle = case transition of
        LifecycleBringUp
          | clusterPresent state -> ClusterActivating phaseValue
          | otherwise -> ClusterProvisioning phaseValue
        LifecycleTearDown -> ClusterTearingDown phaseValue
        LifecycleMutate -> ClusterMutating phaseValue
      updatedState =
        state
          { clusterLifecycle = lifecycle,
            updatedAt = now
          }
  persistClusterState paths updatedState
  when emitMarker $
    putStrLn (action <> " phase: " <> phase <> " - " <> detail)
  pure updatedState

-- | Sprint 2.14: parse a lifecycle action string into the closed
-- 'LifecycleTransition', failing loud on an unknown action rather than
-- persisting an unresumable phase.
requireLifecycleTransition :: String -> IO LifecycleTransition
requireLifecycleTransition action = case parseLifecycleTransition action of
  Just parsedTransition -> pure parsedTransition
  Nothing ->
    ioError
      ( userError
          ("setLifecycleProgress: unknown lifecycle transition action `" <> action <> "`")
      )

startLifecyclePhase :: Paths -> ClusterState -> String -> String -> String -> IO ClusterState
startLifecyclePhase paths state action phase detail =
  setLifecycleProgress paths state action phase detail True

touchLifecycleProgress :: Paths -> ClusterState -> IO ()
touchLifecycleProgress paths state =
  case lifecyclePhaseOf state of
    Nothing -> pure ()
    Just phase -> do
      _ <-
        setLifecycleProgress
          paths
          state
          (lifecycleTransitionAction (lifecyclePhaseTransition phase))
          (lifecyclePhaseName phase)
          (lifecyclePhaseDetail phase)
          False
      pure ()

-- | Sprint 2.14: settle the lifecycle machine onto a terminal (non-in-progress)
-- position — 'ClusterReady' when bring-up completes, 'ClusterAbsent' when
-- teardown completes. This replaces the previous @clearLifecycleProgress@, which
-- cleared the ambient @lifecycleProgress@ and separately mutated the
-- @clusterPresent@ boolean; the terminal position is now a single typed value.
settleLifecycle :: Paths -> ClusterState -> ClusterLifecycle -> IO ClusterState
settleLifecycle paths state lifecycle = do
  now <- getCurrentTime
  let updatedState =
        state
          { clusterLifecycle = lifecycle,
            updatedAt = now
          }
  persistClusterState paths updatedState
  pure updatedState

-- | Sprint 6.43 — bracket a test chaos mutation (node drain, deployment
-- over-scale, cordon) with a persisted first-class 'ClusterMutating' position.
-- The caller's state is only an optimistic token: while holding the lifecycle
-- lock, this rereads the persisted state, complete Kind inventory, and owner
-- reservation, and accepts only an exact live 'ClusterReady' match. The freshly
-- validated state is passed to the body and is the sole basis for the dirty and
-- restored records. An exception or failed postcondition leaves the dirty
-- marker in place so the next @cluster up@ reconciles it
-- ('reconcileInterruptedClusterMutation') rather than publishing a false
-- steady-state.
withPersistedClusterMutation ::
  Paths ->
  ClusterState ->
  String ->
  String ->
  (ClusterState -> IO a) ->
  IO a
withPersistedClusterMutation paths expectedState phaseName detail body =
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    recordedState <- loadClusterState paths
    freshState <-
      case recordedState of
        Nothing ->
          refuseMutation
            "no persisted cluster state exists"
        Just currentState
          | currentState /= expectedState ->
              refuseMutation
                "the caller state is stale; reload the persisted cluster state before retrying"
          | clusterLifecycle currentState /= ClusterReady ->
              refuseMutation
                ( "the persisted lifecycle must be ClusterReady, but is "
                    <> show (clusterLifecycle currentState)
                )
          | otherwise -> pure currentState
    let runtimeMode = clusterRuntimeMode freshState
        owner = clusterOwner freshState
    reservationAccess <- requireReservationAccess paths owner
    presentRuntimeModes <- presentClusterRuntimeModes paths
    unless (presentRuntimeModes == [runtimeMode]) $
      refuseMutation
        ( "the live cluster inventory must contain exactly "
            <> Text.unpack (runtimeModeId runtimeMode)
            <> ", but contains "
            <> show (map runtimeModeId presentRuntimeModes)
        )
    withClusterOwnerSingleton owner $ \ownerSingleton ->
      void
        ( requireClusterOwnership
            lifecycleLock
            paths
            runtimeMode
            "begin a persisted cluster mutation"
            ownerSingleton
            reservationAccess
            presentRuntimeModes
            recordedState
        )
    now <- getCurrentTime
    let phaseValue =
          LifecyclePhase
            { lifecyclePhaseTransition = LifecycleMutate,
              lifecyclePhaseName = phaseName,
              lifecyclePhaseDetail = detail,
              lifecyclePhaseHeartbeatAt = now
            }
        mutatingState =
          freshState
            { clusterLifecycle = ClusterMutating phaseValue,
              updatedAt = now
            }
    persistClusterState paths mutatingState
    result <- body freshState
    currentReservationAccess <- requireReservationAccess paths owner
    unless (currentReservationAccess == reservationAccess) $
      refuseMutation
        "the owner reservation identity changed while the mutation body ran"
    currentRuntimeModes <- presentClusterRuntimeModes paths
    unless (currentRuntimeModes == [runtimeMode]) $
      refuseMutation
        ( "the live cluster inventory changed while the mutation body ran; expected "
            <> Text.unpack (runtimeModeId runtimeMode)
            <> ", but found "
            <> show (map runtimeModeId currentRuntimeModes)
        )
    stateAfterBody <- loadClusterState paths
    unless (stateAfterBody == Just mutatingState) $
      refuseMutation
        "the persisted mutation marker changed while the mutation body ran"
    withClusterOwnerSingleton owner $ \ownerSingleton ->
      void
        ( requireClusterOwnership
            lifecycleLock
            paths
            runtimeMode
            "complete a persisted cluster mutation"
            ownerSingleton
            currentReservationAccess
            currentRuntimeModes
            stateAfterBody
        )
    restoreTime <- getCurrentTime
    persistClusterState
      paths
      ( freshState
          { clusterLifecycle = ClusterReady,
            updatedAt = restoreTime
          }
      )
    pure result
  where
    -- Explicitly generalized: @GADTs@ (needed for the owner singleton) turns on
    -- @MonoLocalBinds@, which would otherwise pin this refusal to one result
    -- type.
    refuseMutation :: String -> IO refusalResult
    refuseMutation reason =
      ioError
        ( userError
            ( "refusing persisted cluster mutation "
                <> show phaseName
                <> ": "
                <> reason
            )
        )

-- | Bring up the operator-owned cluster. The owner choice is not caller
-- constructible; harness bring-up has a separate reservation-gated entry.
clusterUp :: Maybe RuntimeMode -> IO ()
clusterUp = clusterUpForOwner SOperatorOwned

clusterUpHarness :: Maybe RuntimeMode -> IO ()
clusterUpHarness = clusterUpForOwner SHarnessOwned

clusterUpForOwner :: SClusterOwner owner -> Maybe RuntimeMode -> IO ()
clusterUpForOwner ownerSingleton maybeRuntimeMode = do
  paths <- discoverClusterCommandPaths
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    runtimeMode <- resolveClusterRuntimeMode paths maybeRuntimeMode
    let owner = clusterOwnerValue ownerSingleton
    reservationAccess <- requireReservationAccess paths owner
    Config.ensureSupportedRuntimeModeForExecutionContext paths runtimeMode
    when (runtimeMode == AppleSilicon) (ensureAppleSiliconRuntimeReady paths)
    commandsAvailable <- platformCommandsAvailable
    unless commandsAvailable $
      ioError
        ( userError
            "cluster up requires Docker, Helm, Kind, and kubectl on the supported path; simulation is no longer available."
        )
    recordedState <- loadClusterState paths
    presentRuntimeModes <- presentClusterRuntimeModes paths
    teardownAuthority <-
      requireClusterOwnership
        lifecycleLock
        paths
        runtimeMode
        ("bring up a " <> clusterOwnerLabel owner <> "-owned cluster")
        ownerSingleton
        reservationAccess
        presentRuntimeModes
        recordedState
    -- Sprint 6.45 — a live cluster that predates the on-resource identity is
    -- adopted here, under the same held lease that authorized it, so the very
    -- next authorization is a positive identity match rather than another
    -- adoption.
    adoptClusterSlotIfUnidentified teardownAuthority paths runtimeMode
    clusterUpWithPulsarBootstrapRepair lifecycleLock teardownAuthority ownerSingleton paths runtimeMode

clusterUpWithPulsarBootstrapRepair ::
  Lease s ClusterMutationLocked ->
  ClusterTeardownAuthority owner s ->
  SClusterOwner owner ->
  Paths ->
  RuntimeMode ->
  IO ()
clusterUpWithPulsarBootstrapRepair lifecycleLock teardownAuthority ownerSingleton paths runtimeMode = go 0
  where
    maxRepairAttempts = 3 :: Int
    go repairAttempts = do
      reconcileInterruptedClusterTeardown paths runtimeMode
      -- Sprint 2.15: reconcile a persisted 'ClusterMutating' left by a SIGKILLed
      -- @infernix test all@ before proceeding. The recovery driver uncordons
      -- drained nodes before entering the ordinary bring-up continuation, whose
      -- chart re-apply scales deployments back to their declared replica count.
      reconcileInterruptedClusterMutation paths runtimeMode $ do
        repairAttempts' <-
          if repairAttempts >= maxRepairAttempts
            then pure repairAttempts
            else do
              repaired <- repairInterruptedDirtyPulsarBootstrapState
              pure (if repaired then repairAttempts + 1 else repairAttempts)
        result <- try (clusterUpWithPlatform lifecycleLock teardownAuthority ownerSingleton paths runtimeMode)
        case result of
          Right _ -> pure ()
          Left err -> do
            maybeRepairReason <-
              if repairAttempts' < maxRepairAttempts
                then detectDirtyPulsarBootstrapState paths runtimeMode
                else pure Nothing
            case maybeRepairReason of
              Nothing -> ioError err
              Just repairReason -> do
                putStrLn ("cluster up detected inconsistent retained Pulsar state: " <> repairReason)
                clusterDownResolved
                  lifecycleLock
                  teardownAuthority
                  paths
                  runtimeMode
                  (`resetPulsarClaimDirectories` paths)
                putStrLn "retrying cluster up after resetting retained Pulsar claim roots"
                go (repairAttempts' + 1)
    repairInterruptedDirtyPulsarBootstrapState = do
      maybeState <- loadClusterState paths
      case matchingClusterState runtimeMode maybeState >>= lifecyclePhaseOf of
        Just phase
          | lifecyclePhaseTransition phase == LifecycleBringUp -> do
              maybeRepairReason <- detectDirtyPulsarBootstrapState paths runtimeMode
              case maybeRepairReason of
                Nothing -> pure False
                Just repairReason -> do
                  putStrLn ("cluster up detected interrupted inconsistent retained Pulsar state: " <> repairReason)
                  clusterDownResolved
                    lifecycleLock
                    teardownAuthority
                    paths
                    runtimeMode
                    (`resetPulsarClaimDirectories` paths)
                  putStrLn "retrying cluster up after resetting retained Pulsar claim roots"
                  pure True
        _ -> pure False

reconcileInterruptedClusterTeardown :: Paths -> RuntimeMode -> IO ()
reconcileInterruptedClusterTeardown paths runtimeMode = do
  maybeState <- loadClusterState paths
  case matchingClusterState runtimeMode maybeState of
    Just state ->
      case clusterLifecycle state of
        ClusterTearingDown phase -> do
          clusterExists <- kindClusterExists paths runtimeMode
          if clusterExists
            then do
              workerNodes <- kindWorkerNodeNames paths runtimeMode
              when (null workerNodes) $
                ioError
                  ( userError
                      "interrupted cluster teardown recovery found a live Kind cluster without workers"
                  )
              putStrLn
                ( "cluster up reconciling interrupted teardown phase "
                    <> lifecyclePhaseName phase
                    <> ": proving every Kind worker is unpaused"
                )
              unpauseSnapshotWorkers paths runtimeMode workerNodes
            else do
              _ <- settleLifecycle paths state ClusterAbsent
              pure ()
        _ -> pure ()
    Nothing -> pure ()

-- | Sprint 2.15 — reconcile a persisted 'ClusterMutating' position (left by a
-- SIGKILLed @infernix test all@ mid node-drain / over-scale) on the next
-- @cluster up@: uncordon any cordoned nodes (which the chart re-apply cannot do)
-- before entering the ordinary desired-state reconciliation. Deployment
-- replicas are reconciled by the chart re-apply that follows in the same
-- bring-up, and only successful bring-up completion publishes 'ClusterReady'.
-- A partial or unobservable uncordon aborts bring-up and preserves the mutation
-- evidence.
reconcileInterruptedClusterMutation :: Paths -> RuntimeMode -> IO a -> IO a
reconcileInterruptedClusterMutation paths runtimeMode =
  runInterruptedMutationRecovery
    InterruptedMutationRecoveryEffects
      { observeMutationRecoveryState =
          matchingClusterState runtimeMode <$> loadClusterState paths,
        mutationRecoveryRequired =
          clusterLifecycleMutating . clusterLifecycle,
        mutationRecoveryClusterExists =
          const (kindClusterExists paths runtimeMode),
        prepareLiveMutationRecovery = \state -> do
          putStrLn
            ( "cluster up reconciling interrupted cluster mutation: "
                <> maybe "unknown-phase" lifecyclePhaseName (lifecyclePhaseOf state)
            )
          -- Outer-container lanes (linux-cpu/linux-gpu) must join the Kind
          -- Docker network before kubectl can reach the API; without this the
          -- uncordon silently no-ops against an unreachable API on the exact
          -- lane node-drains run on.
          ensureOuterContainerKindNetworkAccess paths runtimeMode,
        uncordonMutationNodes = uncordonAllNodes,
        announceLiveMutationRecovered =
          const
            ( putStrLn
                "cluster up uncordoned every node; continuing through chart reconciliation before publishing steady-state"
            ),
        settleAbsentMutation = \state -> do
          putStrLn "cluster up clearing stale ClusterMutating marker for an absent cluster"
          _ <- settleLifecycle paths state ClusterAbsent
          pure ()
      }

clusterLifecycleMutating :: ClusterLifecycle -> Bool
clusterLifecycleMutating lifecycle = case lifecycle of
  ClusterMutating _ -> True
  ClusterAbsent -> False
  ClusterProvisioning _ -> False
  ClusterActivating _ -> False
  ClusterReady -> False
  ClusterTearingDown _ -> False

-- | The detached retained-state replay transaction. The unique intent phase is
-- persisted before Kind creation and remains current until host state has been
-- copied into every pre-workload worker. That durable fact distinguishes a
-- restartable first bring-up from an idempotent bring-up over live writers.
data RetainedReplayPlan
  = StartRetainedReplay
  | ResumeRetainedReplay
  | RetainedReplayNotRequired
  | RefuseAmbiguousRetainedReplay
  deriving (Eq, Show)

data KindKubeconfigRecoveryPlan
  = RecreatePreWorkloadKind
  | LeaveUnreadableKindUntouched
  deriving (Eq, Show)

retainedReplayPhaseName :: String
retainedReplayPhaseName = "replay-retained-state-into-kind"

retainedReplayPending :: ClusterState -> Bool
retainedReplayPending state =
  case clusterLifecycle state of
    ClusterProvisioning phase -> validReplayPhase phase
    ClusterActivating phase -> validReplayPhase phase
    _ -> False
  where
    validReplayPhase phase =
      lifecyclePhaseTransition phase == LifecycleBringUp
        && lifecyclePhaseName phase == retainedReplayPhaseName

preWorkloadRecoveryIntentMatches :: ClusterLifecycle -> ClusterState -> Bool
preWorkloadRecoveryIntentMatches expectedLifecycle state =
  retainedReplayPending state
    && clusterLifecycle state == expectedLifecycle

retainedReplayPlan ::
  Bool ->
  Bool ->
  ClusterOwner ->
  RuntimeMode ->
  Maybe ClusterState ->
  RetainedReplayPlan
retainedReplayPlan usesHostBindMounts clusterActuallyPresent requestedOwner runtimeMode maybeState
  | usesHostBindMounts = RetainedReplayNotRequired
  | not clusterActuallyPresent = StartRetainedReplay
  | otherwise =
      case maybeState of
        Just state
          | clusterOwner state /= requestedOwner ->
              RefuseAmbiguousRetainedReplay
          | clusterRuntimeMode state /= runtimeMode ->
              RefuseAmbiguousRetainedReplay
          | retainedReplayPending state ->
              ResumeRetainedReplay
          | reservedReplayPhasePresent state ->
              RefuseAmbiguousRetainedReplay
          | legacyProvisioningStatePresent state ->
              RefuseAmbiguousRetainedReplay
          | clusterLifecycle state == ClusterAbsent ->
              RefuseAmbiguousRetainedReplay
          | otherwise ->
              RetainedReplayNotRequired
        Nothing -> RefuseAmbiguousRetainedReplay
  where
    reservedReplayPhasePresent state =
      maybe
        False
        ((== retainedReplayPhaseName) . lifecyclePhaseName)
        (lifecyclePhaseOf state)
    legacyProvisioningStatePresent state =
      case clusterLifecycle state of
        ClusterProvisioning _ -> True
        _ -> False

retainedReplayRequired :: RetainedReplayPlan -> Bool
retainedReplayRequired replayPlan =
  case replayPlan of
    StartRetainedReplay -> True
    ResumeRetainedReplay -> True
    RetainedReplayNotRequired -> False
    RefuseAmbiguousRetainedReplay -> False

kindKubeconfigRecoveryPlan :: RetainedReplayPlan -> KindKubeconfigRecoveryPlan
kindKubeconfigRecoveryPlan replayPlan
  | retainedReplayRequired replayPlan = RecreatePreWorkloadKind
  | otherwise = LeaveUnreadableKindUntouched

retainedReplayLifecyclePhaseName :: RetainedReplayPlan -> String -> String
retainedReplayLifecyclePhaseName replayPlan ordinaryPhaseName
  | retainedReplayRequired replayPlan = retainedReplayPhaseName
  | otherwise = ordinaryPhaseName

requireUsableRetainedReplayPlan :: RetainedReplayPlan -> IO ()
requireUsableRetainedReplayPlan replayPlan =
  case replayPlan of
    RefuseAmbiguousRetainedReplay ->
      ioError
        ( userError
            ( "cluster up refused an ambiguous retained-state replay: a non-bind Kind cluster is "
                <> "present without the current replay-intent evidence; inspect the recorded "
                <> "lifecycle and retained snapshot before retrying"
            )
        )
    StartRetainedReplay -> pure ()
    ResumeRetainedReplay -> pure ()
    RetainedReplayNotRequired -> pure ()

-- | Sprint 2.15 — uncordon every node so a node cordoned by an interrupted
-- drain can schedule pods again. Returns whether the cluster API was reachable
-- (the node list was obtained): 'False' means the uncordon could not be
-- confirmed and the caller must not treat the mutation as reconciled. Every
-- discovered node must acknowledge the uncordon before bring-up proceeds to
-- chart reconciliation; this function never clears the dirty marker itself.
uncordonAllNodes :: ClusterState -> IO Bool
uncordonAllNodes state = do
  nodesResult <-
    tryDiscoveredClusterCommand $ \_ ->
      Command.kubectlGetNodeNames (clusterKubeTarget state)
  case nodesResult of
    Left _ -> pure False
    Right output -> do
      uncordonResults <-
        mapM
          ( \nodeName -> do
              uncordonResult <-
                tryDiscoveredClusterCommand $ \_ ->
                  Command.kubectlUncordon
                    (clusterKubeTarget state)
                    (Command.NodeName nodeName)
              case uncordonResult of
                Right _ -> pure ()
                Left err ->
                  putStrLn ("cluster up uncordon " <> nodeName <> " failed: " <> takeWhile (/= '\n') err)
              pure uncordonResult
          )
          (nodeNamesFromOutput output)
      pure (uncordonResultsProveReady uncordonResults)

uncordonResultsProveReady :: [Either String String] -> Bool
uncordonResultsProveReady results =
  not (null results) && all isRight results

nodeNamesFromOutput :: String -> [String]
nodeNamesFromOutput output =
  [ fromMaybe trimmed (List.stripPrefix "node/" trimmed)
  | rawLine <- lines output,
    let trimmed = filter (not . isSpace) rawLine,
    not (null trimmed)
  ]

clusterUpWithPlatform ::
  Lease s ClusterMutationLocked ->
  ClusterTeardownAuthority owner s ->
  SClusterOwner owner ->
  Paths ->
  RuntimeMode ->
  IO ()
clusterUpWithPlatform lifecycleLock teardownAuthority ownerSingleton paths runtimeMode = do
  recordedStateBeforeBringUp <- loadClusterState paths
  clusterAlreadyPresent <- kindClusterExists paths runtimeMode
  usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
  let owner = clusterOwnerValue ownerSingleton
      replayPlan =
        retainedReplayPlan
          usesHostBindMounts
          clusterAlreadyPresent
          owner
          runtimeMode
          recordedStateBeforeBringUp
  requireUsableRetainedReplayPlan replayPlan
  inputs <- prepareClusterUpInputs paths runtimeMode
  claimDiscoveryTime <- getCurrentTime
  let provisionalState0 =
        clusterUpState
          owner
          inputs
          runtimeMode
          clusterAlreadyPresent
          (clusterUpRequestedEdgePort inputs)
          (clusterUpRequestedRegistryPort inputs)
          (routeInventory (clusterUpDemoUiEnabled inputs))
          (platformClaimsForRuntime runtimeMode)
          claimDiscoveryTime
  provisionalState <-
    startLifecyclePhase
      paths
      provisionalState0
      "cluster-up"
      (retainedReplayLifecyclePhaseName replayPlan "discover-persistent-claims")
      "rendering Helm inputs and discovering durable claim roots"
  claimDiscoveryValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) provisionalState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) FinalPhase
  claimDiscoveryRenderedChartPath <- renderHelmChart paths runtimeMode [claimDiscoveryValuesPath]
  discoveredClaims <- discoverPersistentClaims paths claimDiscoveryRenderedChartPath
  discoveredRoutes <- discoverChartRoutesFile claimDiscoveryRenderedChartPath
  unless clusterAlreadyPresent $ do
    withWriterQuiesced lifecycleLock paths runtimeMode $ \quiesced -> do
      -- A killed non-bind teardown can leave the last committed snapshot under
      -- @.previous@, or a fully staged initial snapshot under @.incoming@.
      -- Recover that transaction inside the freshly rechecked absence lease,
      -- before scrub or claim preparation can create an empty current root.
      reconcileInterruptedRetainedSnapshot paths runtimeMode
      scrubRetainedStateUnderLease quiesced paths
  mapM_ (ensureClaimDirectoryReady paths runtimeMode) discoveredClaims
  clusterPrepareState <-
    startLifecyclePhase
      paths
      provisionalState
      "cluster-up"
      (retainedReplayLifecyclePhaseName replayPlan "prepare-kind-cluster")
      "creating or reusing the Kind cluster and preparing retained runtime data"
  (edgePortValue, registryPortValue, pulsarHttpPortValue, kubeconfigContents, clusterCreated) <-
    ensureKindCluster
      lifecycleLock
      teardownAuthority
      paths
      runtimeMode
      clusterAlreadyPresent
      replayPlan
      (clusterUpRequestedEdgePort inputs)
      (clusterUpRequestedRegistryPort inputs)
      (clusterUpRequestedPulsarHttpPort inputs)
  writeRegistryHostsConfig paths runtimeMode registryPortValue
  primeKindNodeRegistryHosts paths runtimeMode registryPortValue
  replayState <-
    if retainedReplayRequired replayPlan
      then
        startLifecyclePhase
          paths
          clusterPrepareState {clusterLifecycle = ClusterReady}
          "cluster-up"
          retainedReplayPhaseName
          "replaying the committed retained snapshot into the pre-workload Kind workers"
      else pure clusterPrepareState
  when (retainedReplayRequired replayPlan) $
    prepareKindNodeRuntimePaths paths replayState runtimeMode
  unless usesHostBindMounts $
    prepareKindNodeClaimDirectories paths replayState runtimeMode discoveredClaims
  writeFile (edgePortPath paths) (show edgePortValue)
  writeFile (registryPortPath paths) (show registryPortValue)
  writeFile (pulsarHttpPortPath paths) (show pulsarHttpPortValue)
  publishGeneratedKubeconfig paths (Text.pack kubeconfigContents)
  activeStateTime <- getCurrentTime
  let activeState0 =
        clusterUpState
          owner
          inputs
          runtimeMode
          True
          edgePortValue
          registryPortValue
          discoveredRoutes
          discoveredClaims
          activeStateTime
  activeState <-
    startLifecyclePhase
      paths
      activeState0
      "cluster-up"
      "wait-for-kubernetes-api"
      "waiting for the repo-local Kind kubeconfig and Kubernetes API to become reachable"
  ensureOuterContainerKindNetworkAccess paths runtimeMode
  waitForKubernetesApi paths runtimeMode
  configureRuntimeModeCluster paths runtimeMode
  now <- getCurrentTime
  let seedState = activeState {claims = platformClaimsForRuntime runtimeMode, updatedAt = now}
  warmupValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) WarmupPhase
  bootstrapValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) BootstrapPhase
  registryFinalValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) RegistryFinalPhase
  keycloakStorageValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) KeycloakStoragePhase
  pulsarReadyValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) PulsarReadyPhase
  finalValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) (clusterUpFleetMachineContracts inputs) FinalPhase
  renderedChartPath <- renderHelmChart paths runtimeMode [finalValuesPath]
  when clusterCreated $
    putStrLn "cluster-up phase: preload-bootstrap-images - skipped broad pre-registry support-image preload; registry-first publication owns remaining images"
  preloadHostCachedWarmupImagesOnKindWorker paths seedState runtimeMode
  applyBootstrapState paths runtimeMode (clusterUpDemoUiEnabled inputs) discoveredClaims
  let initialState = seedState {claims = discoveredClaims}
  initialStateWithDependencies <-
    startLifecyclePhase
      paths
      initialState
      "cluster-up"
      "ensure-helm-dependencies"
      "reusing or hydrating the top-level Helm dependency archive cache"
  ensureHelmDependencies paths
  storageReconcileState <-
    startLifecyclePhase
      paths
      initialStateWithDependencies
      "cluster-up"
      "reconcile-storage-and-warmup"
      "installing Gateway prerequisites, reconciling persistent volumes, and applying the warmup chart"
  ensureEnvoyGatewayCrdsInstalled paths storageReconcileState
  reconcilePersistentVolumes storageReconcileState
  deployChart paths storageReconcileState [warmupValuesPath] False
  state0 <- reconcileOperatorManagedPersistentVolumes paths storageReconcileState
  persistClusterState paths state0
  registryBootstrapState <-
    startLifecyclePhase
      paths
      state0
      "cluster-up"
      "bootstrap-registry"
      "deploying the in-cluster registry and waiting for it to become ready"
  bootstrapRegistry paths registryBootstrapState [bootstrapValuesPath]
  buildState <-
    startLifecyclePhase
      paths
      registryBootstrapState
      "cluster-up"
      "build-cluster-images"
      ("docker build " <> clusterWorkloadImageRef runtimeMode)
  buildClusterImages paths buildState runtimeMode
  imageOverridesPath <- publishClusterImages paths buildState renderedChartPath runtimeMode
  registryFinalState <-
    startLifecyclePhase
      paths
      buildState
      "cluster-up"
      "deploy-registry-final-phase"
      "deploying registry-backed platform workloads and waiting for registry plus Gateway rollouts"
  preloadRegistryBackedImagesOnKindWorker paths registryFinalState runtimeMode imageOverridesPath
  deployChart paths registryFinalState [registryFinalValuesPath, imageOverridesPath] True
  waitForRegistryFinalPhaseRollouts registryFinalState
  waitForGatewayApiCrds registryFinalState
  finalStorageStateWithOperatorClaims <-
    if clusterStateHasDemoUi registryFinalState
      then do
        finalStorageState <-
          startLifecyclePhase
            paths
            registryFinalState
            "cluster-up"
            "prepare-keycloak-storage"
            "applying the Keycloak PostgreSQL CR and binding operator-managed storage"
        deployChartSkippingHooks paths finalStorageState [keycloakStorageValuesPath, imageOverridesPath] False
        reconcileFinalPhaseOperatorManagedPersistentVolumes paths finalStorageState
      else pure registryFinalState
  finalRuntimePrereqState <-
    if isAppleHostedLinuxCpuLocalTopology paths (clusterUpControlPlane inputs) runtimeMode
      then do
        pulsarReadyState <-
          startLifecyclePhase
            paths
            finalStorageStateWithOperatorClaims
            "cluster-up"
            "prepare-pulsar-runtime"
            "starting Pulsar before the final app workloads on the Apple-hosted linux-cpu lane"
        deployChartSkippingHooks paths pulsarReadyState [pulsarReadyValuesPath, imageOverridesPath] False
        waitForPulsarReadyPhaseRollouts paths pulsarReadyState
        pure pulsarReadyState
      else pure finalStorageStateWithOperatorClaims
  finalDeployState <-
    startLifecyclePhase
      paths
      finalRuntimePrereqState
      "cluster-up"
      "deploy-final-phase"
      "deploying the final chart and waiting for routed workloads to become ready"
  -- Warmup already provisions MinIO buckets. Final deploys skip hooks so
  -- routed workloads are validated by the explicit rollout probes below
  -- instead of being coupled to dependency chart hooks.
  deployChartSkippingHooks paths finalDeployState [finalValuesPath, imageOverridesPath] False
  waitForFinalPhaseRollouts paths finalDeployState
  postKeycloakRealmState <-
    if clusterStateHasDemoUi finalDeployState
      then do
        keycloakRealmState <-
          startLifecyclePhase
            paths
            finalDeployState
            "cluster-up"
            "reconcile-keycloak-realm"
            "reconciling the demo Keycloak realm and browser redirect URIs"
        reconcileKeycloakRealmConfiguration paths keycloakRealmState
        pure keycloakRealmState
      else pure finalDeployState
  routedPublicationState <-
    startLifecyclePhase
      paths
      postKeycloakRealmState
      "cluster-up"
      "wait-for-routed-publication"
      "probing the routed publication surface on the chosen edge before declaring success"
  waitForRoutedPublicationSurface paths routedPublicationState
  warmModelCacheState <-
    startLifecyclePhase
      paths
      routedPublicationState
      "cluster-up"
      "warm-model-cache"
      "eagerly staging the configured model set into infernix-models before declaring success"
  warmModelCache paths runtimeMode inputs
  refreshedState <- refreshPersistentClaims warmModelCacheState
  _ <- settleLifecycle paths refreshedState ClusterReady
  putStrLn "cluster up complete"
  putStrLn ("controlPlaneContext: " <> controlPlaneContextId (clusterUpControlPlane inputs))
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("edgePort: " <> show edgePortValue)
  putStrLn ("registryPort: " <> show registryPortValue)
  putStrLn ("generatedDemoConfigPath: " <> clusterUpDemoConfigPath inputs)
  putStrLn ("publishedDemoConfigPath: " <> clusterUpPublishedCatalogPath inputs)
  putStrLn ("mountedDemoConfigPath: " <> clusterUpMountedCatalogPath inputs)

-- | Phase 8 Sprint 8.5: warm-model-cache barrier. Blocks @cluster up@
-- completion until the coordinator's eager sweep has staged every configured
-- model's @.ready@ sentinel into @infernix-models@, using a progress-based
-- deadline. Best-effort: a stall past the deadline is a warning, not a hard
-- failure, because the coordinator continues staging in the background and the
-- lazy per-inference fallback still covers first inference. Polls MinIO at the
-- host-reachable node-port endpoint for the active control-plane context.
warmModelCache :: Paths -> RuntimeMode -> ClusterUpInputs -> IO ()
warmModelCache paths runtimeMode inputs
  | not (clusterUpDemoUiEnabled inputs) =
      putStrLn "warm-model-cache: demo_ui disabled; skipping"
  | otherwise = do
      demoConfig <- decodeDemoConfigFile (clusterUpPublishedCatalogPath inputs)
      let configuredModelIds = map modelId (models demoConfig)
      if null configuredModelIds
        then putStrLn "warm-model-cache: no models configured (empty-models config); skipping"
        else do
          -- Reach the in-cluster MinIO node port (30011) the same way the Pulsar
          -- proxy probe does: on the Linux launcher (outer-container) the node
          -- ports are reachable at the kind control-plane node's IPv4, not the
          -- container name; on the Apple host they map to 127.0.0.1.
          minioHostResult <- resolveWarmModelCacheMinioHost paths runtimeMode inputs
          runWarmModelCacheBarrier configuredModelIds minioHostResult

resolveWarmModelCacheMinioHost :: Paths -> RuntimeMode -> ClusterUpInputs -> IO (Either String String)
resolveWarmModelCacheMinioHost paths runtimeMode inputs =
  case clusterUpControlPlane inputs of
    HostNative -> pure (Right "127.0.0.1")
    OuterContainer -> kindControlPlaneIpv4 paths runtimeMode

runWarmModelCacheBarrier :: [Text.Text] -> Either String String -> IO ()
runWarmModelCacheBarrier _ (Left err) =
  putStrLn
    ( "warm-model-cache: WARNING could not resolve the MinIO host endpoint ("
        <> err
        <> "); skipping the barrier — the coordinator's eager sweep and the lazy fallback still stage models"
    )
runWarmModelCacheBarrier configuredModelIds (Right minioHost) = do
  let minioBaseEndpoint = "http://" <> minioHost <> ":30011"
  putStrLn
    ( "warm-model-cache: waiting for "
        <> show (length configuredModelIds)
        <> " configured model(s) to stage into infernix-models via "
        <> minioBaseEndpoint
    )
  -- Sprint 8.7 (managed-state-transition doctrine): the warm-model-cache barrier
  -- returns typed readiness evidence. The "all staged" declaration is gated on
  -- the 'WarmModelCacheAllStaged' witness minted only when every sentinel was
  -- observed; a pending outcome carries the still-unstaged ids for a non-blocking
  -- warning.
  outcome <-
    waitForEagerModelCacheReady
      minioBaseEndpoint
      configuredModelIds
      (\message -> putStrLn ("warm-model-cache: " <> message))
  case outcome of
    WarmModelCacheAllStaged _ready ->
      putStrLn ("warm-model-cache: all " <> show (length configuredModelIds) <> " configured models staged")
    WarmModelCacheStillPending pending ->
      putStrLn
        ( "warm-model-cache: WARNING "
            <> show (length pending)
            <> " model(s) not yet staged after the progress-based deadline: "
            <> List.intercalate ", " (map Text.unpack pending)
            <> "; the coordinator continues staging in the background and the lazy per-inference fallback covers first inference"
        )

prepareClusterUpInputs :: Paths -> RuntimeMode -> IO ClusterUpInputs
prepareClusterUpInputs paths runtimeMode = do
  requestedPort <- chooseEdgePort paths
  requestedRegistryPort <- chooseRegistryPort paths
  requestedPulsarHttpPort <- choosePulsarHttpPort paths
  generatedConfigPath <- requireGeneratedDemoConfigFile paths runtimeMode
  generatedConfig <- decodeBootstrapDemoConfigFile generatedConfigPath
  inferenceMemoryBudgetValue <- resolveInferenceMemoryBudget paths runtimeMode
  let demoUiEnabledValue = demoUiEnabled generatedConfig
      publishedCatalogPath = Config.publishedConfigMapCatalogPath paths
      configMapManifestPath = Config.publishedConfigMapManifestPath paths
      publicationPath = Config.publicationStatePath paths
      mountedCatalogPath = Config.watchedDemoConfigPath
      -- Phase 8 Sprint 8.12: publication regenerates the payload rather than
      -- copying the operator's bytes, so it has to carry the operator's fleet
      -- dimension across that regeneration. Read from the declared member ids,
      -- which is the only place the generated contract records it.
      publishedMachineCount =
        engineMachineCountFromMemberIds (map engineMemberId (engineMembers generatedConfig))
      payload =
        Lazy.fromStrict
          ( renderGeneratedDemoConfigPayload
              paths
              runtimeMode
              publishedMachineCount
              demoUiEnabledValue
              inferenceMemoryBudgetValue
          )
  createDirectoryIfMissing True (buildRoot paths)
  createDirectoryIfMissing True (takeDirectory publishedCatalogPath)
  createDirectoryIfMissing True (takeDirectory configMapManifestPath)
  createDirectoryIfMissing True (takeDirectory publicationPath)
  Lazy.writeFile publishedCatalogPath payload
  writeFile configMapManifestPath (renderConfigMapManifest payload)
  -- Phase 8 Sprint 8.12: a fleet's pods cannot share the image-baked machine
  -- contract — it is byte identical in every image, so it collides across
  -- machines instead of discriminating them (Sprint 6.45's finding, applied to
  -- the manifest rather than to the repo root). Each machine gets its own
  -- generated contract naming exactly one member identity, pinned to the
  -- contract this publication just wrote.
  publishedDigest <- digestSystemContractFile publishedCatalogPath
  fleetMachineContracts <-
    renderFleetMachineContracts
      paths
      publishedDigest
      (fleetMemberIdsForPublication runtimeMode (map engineMemberId (engineMembers generatedConfig)))
  pure
    ClusterUpInputs
      { clusterUpControlPlane = Config.controlPlaneContext paths,
        clusterUpRequestedEdgePort = requestedPort,
        clusterUpRequestedRegistryPort = requestedRegistryPort,
        clusterUpRequestedPulsarHttpPort = requestedPulsarHttpPort,
        clusterUpDemoUiEnabled = demoUiEnabledValue,
        clusterUpDemoConfigPath = generatedConfigPath,
        clusterUpKubeconfigPath = Config.generatedKubeconfigPath paths,
        clusterUpPublishedCatalogPath = publishedCatalogPath,
        clusterUpConfigMapManifestPath = configMapManifestPath,
        clusterUpMountedCatalogPath = mountedCatalogPath,
        clusterUpEngineMemberIds = map engineMemberId (engineMembers generatedConfig),
        clusterUpFleetMachineContracts = fleetMachineContracts,
        clusterUpPayload = payload
      }

-- | Phase 8 Sprint 8.12 — the members a publication has to write a machine
-- contract for.
--
-- Only a fleet needs them. A one-machine deployment's pod reads the manifest
-- baked into its image, which describes that one machine correctly precisely
-- because there is one pod to bake it into; and an Apple deployment's engine is
-- a host daemon reading the operator's own repo-root manifest.
fleetMemberIdsForPublication :: RuntimeMode -> [Text.Text] -> [Text.Text]
fleetMemberIdsForPublication runtimeMode memberIds =
  case runtimeMode of
    AppleSilicon -> []
    _
      | engineMachineCountValue (engineMachineCountFromMemberIds memberIds) <= 1 -> []
      | otherwise -> memberIds

-- | Render one machine contract per fleet member, keyed by machine slot.
--
-- The base is this process's own host manifest, which in the launcher is the
-- image manifest the pods run with, so the filesystem and tool facts are
-- already the ones a pod holds. Only the machine block is replaced, and it is
-- replaced with a contract naming exactly one member — the shape
-- [daemon_topology.md](documents/architecture/daemon_topology.md) specifies for
-- a fleet, and the reason the pods can no longer collide on identity by
-- construction rather than by convention.
renderFleetMachineContracts ::
  Paths -> SystemContractDigest -> [Text.Text] -> IO [(Int, String)]
renderFleetMachineContracts _paths _publishedDigest [] = pure []
renderFleetMachineContracts paths publishedDigest memberIds =
  case Config.pathsHostConfig paths of
    Nothing ->
      ioError
        ( userError
            ( "a fleet publication needs this machine's host manifest to derive the"
                <> " per-machine contracts from, and none was discovered at "
                <> Config.hostConfigPath paths
                <> "; run `infernix init` first"
            )
        )
    Just hostConfig ->
      pure
        [ (slot, machineContractText hostConfig memberIdValue)
        | (slot, memberIdValue) <- zip [1 ..] memberIds
        ]
  where
    machineContractText hostConfig memberIdValue =
      LazyChar8.unpack
        ( HostConfig.encodeHostConfig
            hostConfig
              { HostConfig.hostMachine =
                  HostConfig.DeclaredMachine
                    HostConfig.MachineNode
                      { HostConfig.machineRole = daemonRoleToDhall Engine,
                        HostConfig.machineMembers = [memberIdValue],
                        HostConfig.machineModelCacheQuotaBytes =
                          fromInteger defaultModelCacheQuotaBytes,
                        HostConfig.machineSystemContractDigest =
                          systemContractDigestText publishedDigest
                      }
              }
        )

clusterUpState :: ClusterOwner -> ClusterUpInputs -> RuntimeMode -> Bool -> Int -> Int -> [RouteInfo] -> [PersistentClaim] -> UTCTime -> ClusterState
clusterUpState owner inputs runtimeMode clusterPresentValue edgePortValue registryPortValue routesValue claimsValue updatedAtValue =
  ClusterState
    { clusterLifecycle = if clusterPresentValue then ClusterReady else ClusterAbsent,
      clusterOwner = owner,
      edgePort = edgePortValue,
      registryPort = registryPortValue,
      routes = routesValue,
      storageClass = "infernix-manual",
      claims = claimsValue,
      clusterRuntimeMode = runtimeMode,
      clusterEngineMemberIds = clusterUpEngineMemberIds inputs,
      kubeconfigPath = clusterUpKubeconfigPath inputs,
      generatedDemoConfigPath = clusterUpDemoConfigPath inputs,
      publishedDemoConfigPath = clusterUpPublishedCatalogPath inputs,
      publishedConfigMapManifestPath = clusterUpConfigMapManifestPath inputs,
      mountedDemoConfigPath = clusterUpMountedCatalogPath inputs,
      updatedAt = updatedAtValue
    }

requireGeneratedDemoConfigFile :: Paths -> RuntimeMode -> IO FilePath
requireGeneratedDemoConfigFile paths expectedRuntimeMode = do
  let filePath = Config.generatedDemoConfigPath paths
  fileExists <- doesFileExist filePath
  unless fileExists $
    ioError
      ( userError
          ( "runtime config missing at "
              <> filePath
              <> "; run `infernix init` (or `infernix test init` for a test run) to create it"
          )
      )
  demoConfig <- decodeBootstrapDemoConfigFile filePath
  unless (configRuntimeMode demoConfig == expectedRuntimeMode) $
    ioError
      ( userError
          ( unlines
              [ "Generated substrate file runtime mismatch: " <> filePath,
                "expected: " <> Text.unpack (runtimeModeId expectedRuntimeMode),
                "actual: " <> Text.unpack (runtimeModeId (configRuntimeMode demoConfig)),
                "Restage the file for the active substrate before running cluster operations."
              ]
          )
      )
  pure filePath

resolveCommandRuntimeMode :: Paths -> Maybe RuntimeMode -> Maybe ClusterState -> IO RuntimeMode
resolveCommandRuntimeMode _ (Just runtimeMode) _ = pure runtimeMode
resolveCommandRuntimeMode paths Nothing maybeState = do
  let substratePath = Config.generatedDemoConfigPath paths
  substrateExists <- doesFileExist substratePath
  if substrateExists
    then configRuntimeMode <$> decodeBootstrapDemoConfigFile substratePath
    else maybe (Config.targetRuntimeModeForExecutionContext paths) (pure . clusterRuntimeMode) maybeState

resolveClusterRuntimeMode :: Paths -> Maybe RuntimeMode -> IO RuntimeMode
resolveClusterRuntimeMode _ (Just runtimeMode) = pure runtimeMode
resolveClusterRuntimeMode paths Nothing = Config.targetRuntimeModeForExecutionContext paths

discoverClusterCommandPaths :: IO Paths
discoverClusterCommandPaths = do
  paths <- Config.discoverPaths
  Config.ensureRepoLayout paths
  Config.requireHostManifest paths
  pure paths

matchingClusterState :: RuntimeMode -> Maybe ClusterState -> Maybe ClusterState
matchingClusterState runtimeMode maybeState =
  case maybeState of
    Just state
      | clusterRuntimeMode state == runtimeMode -> Just state
    _ -> Nothing

-- | Sprint 6.45 — the identity of the checkout that created a cluster, as it
-- is recorded /on the cluster itself/.
--
-- The value is the checkout's host-side repository root: the one identity that
-- is both per-checkout and machine-unique in /both/ supported execution
-- contexts. On an Apple host it is the operator's real repo path. Inside a
-- Linux launcher container it is the bind-mount source the host Docker daemon
-- resolved for @\/workspace@, /not/ the container-internal path — every
-- launcher container is baked with @hostRepoRoot = \/workspace@, so any
-- identity derived from an in-container path collides across checkouts instead
-- of discriminating them.
newtype ClusterCheckoutIdentity = ClusterCheckoutIdentity
  { unClusterCheckoutIdentity :: FilePath
  }
  deriving (Eq, Show)

-- | Normalise a host-side repository root into a comparable identity. Exposed
-- so a test can build two distinct checkout identities without a Docker
-- daemon.
clusterCheckoutIdentityFromHostRoot :: FilePath -> ClusterCheckoutIdentity
clusterCheckoutIdentityFromHostRoot =
  ClusterCheckoutIdentity . dropTrailingPathSeparator . normalise

-- | What the live protected resource says about who created it.
--
-- 'ClusterSlotUnidentified' covers a cluster created before the identity
-- existed /and/ one whose control-plane node cannot be read at all. Both are
-- treated identically on purpose: neither can prove the slot belongs to the
-- caller.
data ClusterSlotIdentity
  = ClusterSlotUnidentified
  | ClusterSlotIdentifiedAs !ClusterCheckoutIdentity
  deriving (Eq, Show)

-- | The positive outcome of an ownership authorization, which also says what
-- the caller still owes the resource.
data ClusterSlotAdmission
  = -- | No Infernix cluster is live; the slot is available to the first
    -- creator, which stamps its identity as part of creating it.
    ClusterSlotAbsent
  | -- | A live cluster carries this checkout's identity.
    ClusterSlotOwned
  | -- | A live cluster carries no identity and the operator is entitled to
    -- adopt it. The caller must stamp before mutating, so the next
    -- authorization is a positive match rather than another adoption.
    ClusterSlotAdoptable
  deriving (Eq, Show)

-- | Why an ownership authorization was refused.
data ClusterOwnershipRefusalReason
  = -- | The live inventory and the persisted ownership record disagree with
    -- the request: wrong runtime, wrong owner, missing record, or more than
    -- one live Infernix cluster.
    OwnerRecordMismatch
  | -- | The live cluster was created by a different checkout. This is the
    -- cross-checkout defect Sprint 6.45 exists to close: the lifecycle lock,
    -- the harness reservation, and the persisted state are all repo-local,
    -- while the Kind cluster they claim to protect is machine-global.
    ForeignCheckoutSlot !ClusterCheckoutIdentity
  | -- | The live cluster carries no identity and the requesting owner is not
    -- entitled to adopt it.
    UnidentifiedClusterSlot
  deriving (Eq, Show)

-- | Why an operation was refused: an actually-present cluster is not recorded
-- as belonging to the requested owner. A missing owner means the live Kind
-- cluster has no matching persisted state, which also fails closed.
data ClusterOwnershipRefusal = ClusterOwnershipRefusal
  { ownershipRequestedOwner :: ClusterOwner,
    ownershipRecordedOwner :: Maybe ClusterOwner,
    ownershipRequestedRuntimeMode :: RuntimeMode,
    ownershipPresentRuntimeModes :: [RuntimeMode],
    ownershipRefusalReason :: ClusterOwnershipRefusalReason
  }
  deriving (Eq, Show)

-- | Authorize an owner against the complete Kind inventory for this data root,
-- the single persisted ownership record, and — since Sprint 6.45 — the
-- identity carried by the live cluster itself. An absent inventory is
-- available to the first creator. Exactly one live cluster is authorized only
-- when its runtime, its owner, /and/ its recorded checkout all match; two
-- supported runtimes being live is an invariant breach that always fails
-- closed.
--
-- The identity comparison is what makes the guard cover the resource it
-- protects. Without it, a second checkout holding a leftover @HarnessOwned@
-- state file authorizes against the operator's live cluster using its own
-- state, and deletes it.
--
-- An unidentified live cluster predates the identity, so it cannot be matched.
-- The two owners are deliberately not symmetric there:
--
--   * @OperatorOwned@ may /adopt/ it. The operator is acting at their own
--     terminal on their own host, and refusing would strand a running cluster
--     behind a manual @kind delete@.
--
--   * @HarnessOwned@ may not. The harness is the destructive actor in the
--     defect above — an unattended @infernix test all@ that tears down
--     whatever it finds — so it is required to prove the slot is its own, and
--     an unidentified slot is exactly the proof it lacks.
authorizeClusterOwnership ::
  ClusterOwner ->
  RuntimeMode ->
  [RuntimeMode] ->
  Maybe ClusterState ->
  ClusterCheckoutIdentity ->
  ClusterSlotIdentity ->
  Either ClusterOwnershipRefusal ClusterSlotAdmission
authorizeClusterOwnership requestedOwner requestedRuntimeMode presentRuntimeModes maybeState localIdentity slotIdentity =
  case presentRuntimeModes of
    [] -> Right ClusterSlotAbsent
    [presentRuntimeMode]
      | presentRuntimeMode == requestedRuntimeMode ->
          case (requestedOwner, slotIdentity) of
            -- An explicit operator command is the recovery authority for a
            -- pre-identity cluster. This arm must precede the persisted-owner
            -- comparison: an interrupted harness can leave a real cluster and
            -- a HarnessOwned state record before the identity stamp, and
            -- requiring OperatorOwned first would make the documented
            -- adoption/removal path unreachable.
            (OperatorOwned, ClusterSlotUnidentified) -> Right ClusterSlotAdoptable
            _ ->
              case maybeState of
                Just state
                  | clusterRuntimeMode state == presentRuntimeMode,
                    clusterOwner state == requestedOwner ->
                      admitIdentifiedSlot
                _ -> Left (refusal OwnerRecordMismatch)
      | otherwise -> Left (refusal OwnerRecordMismatch)
    _ -> Left (refusal OwnerRecordMismatch)
  where
    admitIdentifiedSlot =
      case slotIdentity of
        ClusterSlotIdentifiedAs recordedIdentity
          | recordedIdentity == localIdentity -> Right ClusterSlotOwned
          | otherwise -> Left (refusal (ForeignCheckoutSlot recordedIdentity))
        ClusterSlotUnidentified ->
          case requestedOwner of
            OperatorOwned -> Right ClusterSlotAdoptable
            HarnessOwned -> Left (refusal UnidentifiedClusterSlot)
    refusal reason =
      ClusterOwnershipRefusal
        { ownershipRequestedOwner = requestedOwner,
          ownershipRecordedOwner = clusterOwner <$> maybeState,
          ownershipRequestedRuntimeMode = requestedRuntimeMode,
          ownershipPresentRuntimeModes = presentRuntimeModes,
          ownershipRefusalReason = reason
        }

-- | Render the refusal reason as the operator-facing tail of the diagnostic,
-- naming the remedy where one exists.
clusterOwnershipRefusalDetail :: ClusterOwnershipRefusal -> String
clusterOwnershipRefusalDetail refusal =
  case ownershipRefusalReason refusal of
    OwnerRecordMismatch -> ""
    ForeignCheckoutSlot recordedIdentity ->
      "; the live cluster was created by the checkout at "
        <> unClusterCheckoutIdentity recordedIdentity
        <> ", not by this one. Tear it down from that checkout, or remove it with "
        <> "'kind delete cluster'"
    UnidentifiedClusterSlot ->
      "; the live cluster carries no checkout identity, so the harness cannot "
        <> "prove it created it. Run 'infernix cluster down' as the operator to "
        <> "remove it, or 'infernix cluster up' to adopt it into this checkout"

-- | Where a cluster's creating-checkout identity lives inside its
-- control-plane node.
--
-- A directory rather than a bare file because the closed command catalog's
-- read-back primitive is @docker cp \<node>:\<dir>\/. \<local>@; writing the
-- marker into its own directory keeps that copy to a single small file. The
-- path is inside the node's own filesystem, not a bind mount, so it is
-- created by the Docker daemon that owns the cluster and is readable by any
-- process that can reach that daemon — which is exactly the sharing boundary
-- the guard has to cover.
clusterSlotIdentityDirectory :: FilePath
clusterSlotIdentityDirectory = "/etc/infernix"

clusterSlotIdentityFileName :: FilePath
clusterSlotIdentityFileName = "cluster-checkout-identity"

-- | This checkout's identity.
--
-- Fails closed rather than falling back. 'resolveHostRepoRoot' answers
-- @\/workspace@ when the launcher container's bind-mount lookup fails, which
-- is the correct conservative answer for /rendering a path/ but the worst
-- possible answer for an /identity/: every launcher container would claim the
-- same one, so two checkouts would silently authorize against each other's
-- clusters — the defect this exists to close.
localClusterCheckoutIdentity :: Paths -> IO ClusterCheckoutIdentity
localClusterCheckoutIdentity paths
  | not (isBakedLinuxOuterContainerManifest paths) =
      pure (clusterCheckoutIdentityFromHostRoot (repoRoot paths))
  | otherwise = do
      launcherContainer <- currentLauncherContainerName
      mountResult <-
        tryClusterCommand
          paths
          ( Command.dockerInspectContainerField
              (Command.ContainerName launcherContainer)
              (Command.MountSourceAt (repoRoot paths </> ".data"))
          )
      case trim <$> mountResult of
        Right hostDataRoot
          | not (null hostDataRoot) ->
              pure (clusterCheckoutIdentityFromHostRoot (takeDirectory hostDataRoot))
        _ ->
          ioError
            ( userError
                ( "cannot determine this checkout's host-side identity: the launcher container "
                    <> launcherContainer
                    <> " has no host bind-mount source for "
                    <> (repoRoot paths </> ".data")
                    <> ". Every launcher container is baked with the same in-container repo root, "
                    <> "so proceeding would let this checkout authorize cluster teardown against "
                    <> "another checkout's cluster."
                )
            )

-- | A private scratch directory for the identity read-back. Kept off the
-- repo-visible bind mounts for the same reason 'withKindScratchKubeconfig'
-- is, and keyed by pid so two Infernix processes on one host cannot read into
-- each other's copy.
withClusterIdentityScratchDirectory :: Paths -> RuntimeMode -> (FilePath -> IO a) -> IO a
withClusterIdentityScratchDirectory paths runtimeMode action = do
  scratchRoot <- getTemporaryDirectory
  readerPid <- getProcessID
  let scratchDirectory =
        scratchRoot
          </> ( "infernix-cluster-identity-"
                  <> kindClusterName paths runtimeMode
                  <> "-"
                  <> show (fromIntegral readerPid :: Int)
              )
  removePathForcibly scratchDirectory
  createDirectoryIfMissing True scratchDirectory
  finallyPreservingPrimary
    (action scratchDirectory)
    (removePathForcibly scratchDirectory)

-- | Read the checkout identity off the live cluster.
--
-- Any failure — no such cluster, control-plane container removed, marker never
-- written — is 'ClusterSlotUnidentified'. That is deliberate: the read proves
-- ownership, so an unreadable resource proves nothing and the caller's
-- fail-closed arm applies.
readClusterSlotIdentity :: Paths -> RuntimeMode -> IO ClusterSlotIdentity
readClusterSlotIdentity paths runtimeMode =
  withClusterIdentityScratchDirectory paths runtimeMode $ \scratchDirectory -> do
    copyResult <-
      tryClusterCommand
        paths
        ( Command.dockerCopyFromNode
            (Command.NodeName (kindControlPlaneNodeName paths runtimeMode))
            clusterSlotIdentityDirectory
            scratchDirectory
        )
    case copyResult of
      Left _ -> pure ClusterSlotUnidentified
      Right _ -> do
        let markerPath = scratchDirectory </> clusterSlotIdentityFileName
        markerExists <- doesFileExist markerPath
        if not markerExists
          then pure ClusterSlotUnidentified
          else do
            recorded <- trim <$> readFile markerPath
            pure
              ( if null recorded
                  then ClusterSlotUnidentified
                  else ClusterSlotIdentifiedAs (clusterCheckoutIdentityFromHostRoot recorded)
              )

-- | Read the identity of whichever single Infernix cluster is live. More than
-- one live runtime is already an invariant breach that
-- 'authorizeClusterOwnership' refuses on the inventory alone, so there is no
-- identity to attribute.
observeClusterSlotIdentity :: Paths -> [RuntimeMode] -> IO ClusterSlotIdentity
observeClusterSlotIdentity paths presentRuntimeModes =
  case presentRuntimeModes of
    [presentRuntimeMode] -> readClusterSlotIdentity paths presentRuntimeMode
    _ -> pure ClusterSlotUnidentified

-- | Stamp this checkout's identity onto the live cluster. Idempotent, and
-- called both immediately after creation and when an operator adopts a cluster
-- that predates the identity.
stampClusterSlotIdentity :: Paths -> RuntimeMode -> IO ()
stampClusterSlotIdentity paths runtimeMode = do
  identity <- localClusterCheckoutIdentity paths
  let controlPlaneNode = Command.NodeName (kindControlPlaneNodeName paths runtimeMode)
  runClusterCommand
    paths
    (Command.dockerMakeDirectory controlPlaneNode clusterSlotIdentityDirectory)
  runClusterCommand
    paths
    ( Command.dockerWriteFile
        controlPlaneNode
        (clusterSlotIdentityDirectory </> clusterSlotIdentityFileName)
        (Command.filePayload (unClusterCheckoutIdentity identity <> "\n"))
    )

-- | Adopt a live cluster that carries no identity, when the authority says
-- this owner is entitled to. A no-op for every other admission, so callers can
-- apply it unconditionally on the bring-up path.
--
-- Adoption /upgrades/ the evidence on a cluster that already passed the
-- ownership check, so a failed stamp is reported and not fatal. Aborting here
-- would put a damaged control-plane node — the one case that can fail — ahead
-- of the bring-up path's own recovery, which is what repairs it. Leaving the
-- slot unidentified keeps the harness fenced, which is the property that
-- matters.
adoptClusterSlotIfUnidentified ::
  ClusterTeardownAuthority owner s ->
  Paths ->
  RuntimeMode ->
  IO ()
adoptClusterSlotIfUnidentified authority paths runtimeMode =
  case teardownAuthorityAdmission authority of
    ClusterSlotAdoptable -> do
      stampResult <- try (stampClusterSlotIdentity paths runtimeMode)
      case stampResult of
        Right () -> pure ()
        Left stampError ->
          putStrLn
            ( "warning: could not record this checkout's identity on the existing "
                <> kindClusterName paths runtimeMode
                <> " cluster ("
                <> displayException (stampError :: SomeException)
                <> "); it stays unidentified, so 'infernix test all' will refuse it"
            )
    ClusterSlotOwned -> pure ()
    ClusterSlotAbsent -> pure ()

clusterOwnerLabel :: ClusterOwner -> String
clusterOwnerLabel OperatorOwned = "operator"
clusterOwnerLabel HarnessOwned = "harness"

-- | Sprint 6.45 — the runtime witness that selects a 'ClusterOwner' type index.
-- 'ClusterOwner' is an ordinary value type promoted with @DataKinds@; this
-- singleton is the only bridge between the promoted index and the owner value
-- the runtime checks still compare.
data SClusterOwner (owner :: ClusterOwner) where
  SOperatorOwned :: SClusterOwner 'OperatorOwned
  SHarnessOwned :: SClusterOwner 'HarnessOwned

-- | Project the ordinary owner value out of its singleton, so every existing
-- value-level comparison keeps operating on the same data it always did.
clusterOwnerValue :: SClusterOwner owner -> ClusterOwner
clusterOwnerValue ownerSingleton =
  case ownerSingleton of
    SOperatorOwned -> OperatorOwned
    SHarnessOwned -> HarnessOwned

-- | Recover a type-level owner index from an owner value that was read at
-- runtime (a persisted state document, say). The index is therefore always
-- derived from the bytes actually read; nothing here decides who owns a live
-- cluster.
withClusterOwnerSingleton ::
  ClusterOwner ->
  (forall owner. SClusterOwner owner -> IO a) ->
  IO a
withClusterOwnerSingleton owner use =
  case owner of
    OperatorOwned -> use SOperatorOwned
    HarnessOwned -> use SHarnessOwned

-- | The authority required by the raw teardown. Its constructor is private and
-- the value records both the checked owner and runtime. The only mint is
-- 'requireClusterOwnership', which evaluates the global inventory under the
-- lifecycle lock.
--
-- Sprint 6.45 — the @owner@ parameter is the promoted 'ClusterOwner' the
-- authority was minted for, and the @s@ parameter is the lifecycle-lock region.
-- Both roles are nominal, so an authority minted for one owner cannot be
-- /substituted/ where the other owner is required: the harness's teardown call
-- graph cannot be handed an operator authority, and vice versa. That is the
-- whole of what the index buys. It decides nothing about the live cluster —
-- which owner a present cluster actually has is discovered at runtime by
-- 'authorizeClusterOwnership', under the held lease, by rereading the persisted
-- record and the Kind inventory. A teardown of a genuinely 'OperatorOwned'
-- cluster is refused there, by a checked 'ioError', not by the typechecker.
data ClusterTeardownAuthority (owner :: ClusterOwner) s = ClusterTeardownAuthority
  { teardownAuthorityOwner :: SClusterOwner owner,
    teardownAuthorityRuntimeMode :: RuntimeMode,
    teardownAuthorityReservationAccess :: ClusterReservationAccess,
    -- | Sprint 6.45 — what the live cluster's own checkout identity said at
    -- mint time. 'ClusterSlotAdoptable' is the only value that leaves the
    -- caller something to do: stamp this checkout's identity onto the cluster
    -- before mutating it.
    teardownAuthorityAdmission :: ClusterSlotAdmission
  }

type role ClusterTeardownAuthority nominal nominal

data PreWorkloadKindRecovery (owner :: ClusterOwner) s
  = PreWorkloadKindRecovery
      (ClusterTeardownAuthority owner s)
      RuntimeMode
      ClusterLifecycle

type role PreWorkloadKindRecovery nominal nominal

data KindDeleteAuthorization (owner :: ClusterOwner) s
  = AuthorizedClusterTeardown (ClusterTeardownAuthority owner s)
  | AuthorizedPreWorkloadRecovery (PreWorkloadKindRecovery owner s)

type role KindDeleteAuthorization nominal nominal

-- | The owner value carried by an authority. Every runtime comparison uses
-- this projection, so promoting the index changed no check.
teardownAuthorityOwnerValue :: ClusterTeardownAuthority owner s -> ClusterOwner
teardownAuthorityOwnerValue = clusterOwnerValue . teardownAuthorityOwner

-- | Compile-time witness used by the capability fixtures. It mints no
-- authority and performs no transition; its only purpose is to make the
-- lifecycle-region equality required by every authority consumer observable
-- to an external typecheck.
clusterTeardownAuthorityRegionWitness ::
  Lease s ClusterMutationLocked ->
  ClusterTeardownAuthority owner s ->
  ()
clusterTeardownAuthorityRegionWitness lifecycleLock authority =
  case leasePayload lifecycleLock of
    ClusterMutationLocked ->
      case authority of
        ClusterTeardownAuthority {} -> ()

requireClusterOwnership ::
  Lease s ClusterMutationLocked ->
  Paths ->
  RuntimeMode ->
  String ->
  SClusterOwner owner ->
  ClusterReservationAccess ->
  [RuntimeMode] ->
  Maybe ClusterState ->
  IO (ClusterTeardownAuthority owner s)
requireClusterOwnership lifecycleLock paths runtimeMode action requestedOwnerSingleton reservationAccess presentRuntimeModes maybeState = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  -- Sprint 6.45 — the identity is read from the live resource under the held
  -- lease, alongside the inventory and the persisted record, so every mint
  -- decides on evidence gathered inside the same critical section.
  localIdentity <- localClusterCheckoutIdentity paths
  slotIdentity <- observeClusterSlotIdentity paths presentRuntimeModes
  case ( reservationAccessOwner reservationAccess == requestedOwner,
         authorizeClusterOwnership
           requestedOwner
           runtimeMode
           presentRuntimeModes
           maybeState
           localIdentity
           slotIdentity
       ) of
    (True, Right admission) ->
      pure
        ( ClusterTeardownAuthority
            requestedOwnerSingleton
            runtimeMode
            reservationAccess
            admission
        )
    (False, _) ->
      ioError
        ( userError
            "cluster ownership authorization received reservation evidence for another owner"
        )
    (_, Left refusal) ->
      ioError
        ( userError
            ( "refusing to "
                <> action
                <> ": requested runtime="
                <> Text.unpack (runtimeModeId runtimeMode)
                <> ", present Infernix runtimes="
                <> renderRuntimeModes (ownershipPresentRuntimeModes refusal)
                <> ", recorded owner="
                <> maybe "unknown" clusterOwnerLabel (ownershipRecordedOwner refusal)
                <> ", not owner="
                <> clusterOwnerLabel (ownershipRequestedOwner refusal)
                <> " at "
                <> dataRoot paths
                <> clusterOwnershipRefusalDetail refusal
            )
        )
  where
    requestedOwner = clusterOwnerValue requestedOwnerSingleton
    renderRuntimeModes runtimeModes =
      case runtimeModes of
        [] -> "none"
        _ -> List.intercalate "," (map (Text.unpack . runtimeModeId) runtimeModes)

reservationAccessOwner :: ClusterReservationAccess -> ClusterOwner
reservationAccessOwner reservationAccess =
  case reservationAccess of
    OperatorReservationAccess -> OperatorOwned
    HarnessReservationAccess _ -> HarnessOwned

revalidateClusterTeardownAuthority ::
  Lease s ClusterMutationLocked ->
  String ->
  ClusterTeardownAuthority owner s ->
  Paths ->
  RuntimeMode ->
  IO (Maybe ClusterState, [RuntimeMode])
revalidateClusterTeardownAuthority lifecycleLock action authority paths runtimeMode = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  unless (teardownAuthorityRuntimeMode authority == runtimeMode) $
    ioError
      ( userError
          "cluster teardown authority/runtime mismatch"
      )
  recordedState <- loadClusterState paths
  presentRuntimeModes <- presentClusterRuntimeModes paths
  currentReservationAccess <-
    requireReservationAccess paths (teardownAuthorityOwnerValue authority)
  unless
    (currentReservationAccess == teardownAuthorityReservationAccess authority)
    ( ioError
        ( userError
            "cluster teardown authority reservation identity changed after authorization"
        )
    )
  _ <-
    requireClusterOwnership
      lifecycleLock
      paths
      runtimeMode
      action
      (teardownAuthorityOwner authority)
      currentReservationAccess
      presentRuntimeModes
      recordedState
  pure (recordedState, presentRuntimeModes)

presentClusterRuntimeModes :: Paths -> IO [RuntimeMode]
presentClusterRuntimeModes paths = do
  existingClusters <-
    lines
      <$> captureClusterCommand
        paths
        Command.kindListClusters
  pure
    [ runtimeMode
    | runtimeMode <- allRuntimeModes,
      kindClusterName paths runtimeMode `elem` existingClusters
    ]

requireReservationAccess :: Paths -> ClusterOwner -> IO ClusterReservationAccess
requireReservationAccess paths requestedOwner = do
  maybeReservation <- readHarnessReservation paths
  currentProcessGroup <- fromIntegral <$> getProcessGroupID
  case (requestedOwner, maybeReservation) of
    (OperatorOwned, Nothing) ->
      pure OperatorReservationAccess
    (_, maybePresentReservation) -> do
      ownerStatus <-
        maybe
          (pure HarnessReservationOwnerDefinitelyDead)
          (fmap inspectedOwnerStatus . inspectHarnessReservationOwner paths)
          maybePresentReservation
      let maybeReservationProcessGroup =
            harnessReservationProcessGroup <$> maybePresentReservation
          maybeAuthorizedChildGroup =
            maybePresentReservation >>= harnessReservationAuthorizedChildGroup
      case authorizeHarnessReservationAccess
        requestedOwner
        currentProcessGroup
        (ownerStatus == HarnessReservationOwnerVerifiedAlive)
        maybeReservationProcessGroup
        maybeAuthorizedChildGroup of
        Left refusal ->
          ioError
            ( userError
                ( refusal
                    <> " at "
                    <> harnessReservationPath paths
                )
            )
        Right () ->
          case maybePresentReservation of
            Just reservation -> pure (HarnessReservationAccess reservation)
            Nothing ->
              ioError
                ( userError
                    "harness reservation authorization produced no evidence"
                )

-- | Whether a caller's process group is the live harness itself or the one
-- toolchain child it has delegated authority to.
--
-- Both arms require the owner to be verified alive, so a reservation left by a
-- dead harness authorizes nobody through either group.
harnessReservationGroupAuthorized ::
  Integer ->
  Bool ->
  Integer ->
  Maybe Integer ->
  Bool
harnessReservationGroupAuthorized
  currentProcessGroup
  ownerAlive
  reservationProcessGroup
  maybeAuthorizedChildGroup =
    ownerAlive
      && ( currentProcessGroup == reservationProcessGroup
             || maybeAuthorizedChildGroup == Just currentProcessGroup
         )

authorizeHarnessReservationAccess ::
  ClusterOwner ->
  Integer ->
  Bool ->
  Maybe Integer ->
  Maybe Integer ->
  Either String ()
authorizeHarnessReservationAccess
  requestedOwner
  currentProcessGroup
  ownerAlive
  maybeReservationProcessGroup
  maybeAuthorizedChildGroup =
    case (requestedOwner, maybeReservationProcessGroup) of
      (OperatorOwned, Nothing) -> Right ()
      (OperatorOwned, Just _) ->
        Left "refusing operator cluster mutation: the test harness owns the cluster slot"
      (HarnessOwned, Nothing) ->
        Left "refusing harness cluster mutation without a live cluster-slot reservation"
      (HarnessOwned, Just reservationProcessGroup)
        | harnessReservationGroupAuthorized
            currentProcessGroup
            ownerAlive
            reservationProcessGroup
            maybeAuthorizedChildGroup ->
            Right ()
        | otherwise ->
            Left "refusing harness cluster mutation outside the live reservation process group"

authorizeRuntimeConfigWriteAccess ::
  Integer ->
  Bool ->
  Maybe Integer ->
  Maybe Integer ->
  Either String ()
authorizeRuntimeConfigWriteAccess
  currentProcessGroup
  ownerAlive
  maybeReservationProcessGroup
  maybeAuthorizedChildGroup =
    case maybeReservationProcessGroup of
      Nothing -> Right ()
      Just reservationProcessGroup
        | harnessReservationGroupAuthorized
            currentProcessGroup
            ownerAlive
            reservationProcessGroup
            maybeAuthorizedChildGroup ->
            Right ()
        | otherwise ->
            Left "refusing runtime-config write outside the live harness reservation process group"

withRuntimeConfigWriteAccess :: IO a -> IO a
withRuntimeConfigWriteAccess action = do
  paths <- Config.discoverPaths
  withRuntimeConfigWriteAccessAt paths action

withRuntimeConfigWriteAccessAt :: Paths -> IO a -> IO a
withRuntimeConfigWriteAccessAt paths action = do
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \_ -> do
    maybeReservation <- readHarnessReservation paths
    ownerStatus <-
      maybe
        (pure HarnessReservationOwnerDefinitelyDead)
        (fmap inspectedOwnerStatus . inspectHarnessReservationOwner paths)
        maybeReservation
    currentProcessGroup <- fromIntegral <$> getProcessGroupID
    case authorizeRuntimeConfigWriteAccess
      currentProcessGroup
      (ownerStatus == HarnessReservationOwnerVerifiedAlive)
      (harnessReservationProcessGroup <$> maybeReservation)
      (maybeReservation >>= harnessReservationAuthorizedChildGroup) of
      Right () -> action
      Left refusal ->
        ioError
          ( userError
              ( refusal
                  <> " at "
                  <> harnessReservationPath paths
              )
          )

readHarnessReservation :: Paths -> IO (Maybe HarnessReservation)
readHarnessReservation paths = do
  let reservationPath = harnessReservationPath paths
  reservationPresent <- doesFileExist reservationPath
  if reservationPresent
    then do
      reservationContents <- readFile reservationPath
      case parseHarnessReservation reservationContents of
        Just reservation -> pure (Just reservation)
        Nothing ->
          ioError
            ( userError
                ( "the harness cluster-slot reservation is unreadable at "
                    <> reservationPath
                    <> "; inspect it before retrying"
                )
            )
    else pure Nothing

parseHarnessReservation :: String -> Maybe HarnessReservation
parseHarnessReservation reservationContents = do
  version <- uniqueField "version"
  "harness" <- uniqueField "owner"
  ownerPid <- uniqueField "pid" >>= readMaybe
  processGroup <- uniqueField "process-group" >>= readMaybe
  ownerBirthIdentity <-
    case version of
      -- Version 1 remains readable so a dead pre-upgrade reservation can be
      -- recovered. Its reusable PID/PGID is never accepted as live authority.
      "1" -> pure Nothing
      "2" -> do
        bootIdentity <- uniqueField "boot-identity"
        processStartTime <- uniqueField "process-start-time" >>= readMaybe
        if validBootIdentity bootIdentity
          && processStartTime > 0
          then
            pure
              ( Just
                  ProcessBirthIdentity
                    { processBirthBootIdentity = bootIdentity,
                      processBirthStartTime = processStartTime
                    }
              )
          else Nothing
      _ -> Nothing
  ownerPidNamespace <-
    case version of
      "1" -> pure Nothing
      "2" ->
        optionalUniqueField "owner-pid-namespace"
          >>= traverse parseProcessNamespaceIdentity
      _ -> Nothing
  configTransaction <- uniqueField "config-transaction" >>= parseConfigTransaction
  authorizedChildGroup <-
    uniqueField "authorized-child-group" >>= parseAuthorizedChildGroup
  if validProcessIdentifier ownerPid
    && processGroup == ownerPid
    && all validProcessIdentifier authorizedChildGroup
    && authorizedChildGroup /= Just processGroup
    then
      pure
        HarnessReservation
          { harnessReservationOwnerPid = ownerPid,
            harnessReservationProcessGroup = processGroup,
            harnessReservationOwnerBirthIdentity = ownerBirthIdentity,
            harnessReservationOwnerPidNamespace = ownerPidNamespace,
            harnessReservationConfigTransaction = configTransaction,
            harnessReservationAuthorizedChildGroup = authorizedChildGroup
          }
    else Nothing
  where
    -- A delegated group is spelled explicitly in both directions. An absent
    -- field is a malformed reservation rather than \"no child\", because the
    -- writer always renders one and a reservation missing a field it should
    -- carry is exactly the state this parser exists to refuse.
    parseAuthorizedChildGroup value =
      case value of
        "none" -> Just Nothing
        _ -> Just <$> readMaybe value
    uniqueField fieldName =
      case [ fieldValue
           | lineValue <- lines reservationContents,
             Just fieldValue <- [List.stripPrefix (fieldName <> "=") lineValue]
           ] of
        [fieldValue] -> Just fieldValue
        _ -> Nothing
    optionalUniqueField fieldName =
      case [ fieldValue
           | lineValue <- lines reservationContents,
             Just fieldValue <- [List.stripPrefix (fieldName <> "=") lineValue]
           ] of
        [] -> Just Nothing
        [fieldValue] -> Just (Just fieldValue)
        _ -> Nothing
    parseConfigTransaction value =
      case value of
        "untouched" -> Just HarnessConfigUntouched
        "restore-pending" -> Just HarnessConfigRestorePending
        "remove-pending" -> Just HarnessConfigRemovePending
        "restored" -> Just HarnessConfigRestored
        _ -> Nothing

validProcessIdentifier :: Integer -> Bool
validProcessIdentifier processId =
  processId > 0 && processId <= 2147483647

validBootIdentity :: String -> Bool
validBootIdentity value =
  not (null value)
    && all
      (\character -> isAlphaNum character || character `elem` ("-_" :: String))
      value

renderHarnessReservation :: HarnessReservation -> String
renderHarnessReservation reservation =
  case harnessReservationOwnerBirthIdentity reservation of
    Nothing ->
      unlines
        ( "version=1"
            : commonFields
        )
    Just birthIdentity ->
      unlines
        ( [ "version=2",
            "boot-identity=" <> processBirthBootIdentity birthIdentity,
            "process-start-time=" <> show (processBirthStartTime birthIdentity)
          ]
            <> maybe
              []
              ( \namespaceIdentity ->
                  [ "owner-pid-namespace="
                      <> renderProcessNamespaceIdentity namespaceIdentity
                  ]
              )
              (harnessReservationOwnerPidNamespace reservation)
            <> commonFields
        )
  where
    commonFields =
      [ "owner=harness",
        "pid=" <> show (harnessReservationOwnerPid reservation),
        "process-group=" <> show (harnessReservationProcessGroup reservation),
        "authorized-child-group="
          <> maybe
            "none"
            show
            (harnessReservationAuthorizedChildGroup reservation),
        "config-transaction="
          <> renderConfigTransaction (harnessReservationConfigTransaction reservation)
      ]
    renderConfigTransaction transaction =
      case transaction of
        HarnessConfigUntouched -> "untouched"
        HarnessConfigRestorePending -> "restore-pending"
        HarnessConfigRemovePending -> "remove-pending"
        HarnessConfigRestored -> "restored"

writeHarnessReservation :: Paths -> HarnessReservation -> IO ()
writeHarnessReservation paths reservation = mask $ \restore -> do
  let reservationPath = harnessReservationPath paths
      reservationDirectory = takeDirectory reservationPath
  createDirectoryIfMissing True reservationDirectory
  temporary <-
    openBinaryTempFile reservationDirectory "harness-cluster-slot.tmp"
  onExceptionPreservingPrimary
    ( restore $ do
        let (temporaryPath, handle) = temporary
        hPutStr handle (renderHarnessReservation reservation)
        hClose handle
        renameFile temporaryPath reservationPath
    )
    (cleanupTemporaryReservation temporary)
  where
    cleanupTemporaryReservation (temporaryPath, handle) =
      runCleanupsPreservingFailures
        [ do
            closed <- hIsClosed handle
            unless closed (hClose handle),
          do
            exists <- doesFileExist temporaryPath
            when exists (removeFile temporaryPath)
        ]

inspectHarnessReservationOwner ::
  Paths ->
  HarnessReservation ->
  IO HarnessReservationOwnerInspection
inspectHarnessReservationOwner paths reservation = do
  currentPidNamespace <- observeCurrentProcessNamespaceIdentity
  lifetimeLockHeld <- kernelFileLockIsHeld (harnessLifetimeLockPath paths)
  let namespaceRelation =
        classifyRecordedNamespace
          (harnessReservationOwnerPidNamespace reservation)
          currentPidNamespace
  ownerStatus <-
    case namespaceRelation of
      RecordedNamespaceMatches ->
        inspectOwnerWithinRecordedNamespace reservation
      RecordedNamespaceIsForeign
        | lifetimeLockHeld ->
            pure HarnessReservationOwnerUnverifiable
        | otherwise ->
            pure HarnessReservationOwnerDefinitelyDead
      RecordedNamespaceCannotBeCompared ->
        pure HarnessReservationOwnerUnverifiable
  pure
    HarnessReservationOwnerInspection
      { inspectedOwnerStatus = ownerStatus,
        inspectedCurrentPidNamespace = currentPidNamespace,
        inspectedNamespaceRelation = namespaceRelation,
        inspectedLifetimeLockHeld = lifetimeLockHeld
      }

classifyRecordedNamespace ::
  Maybe ProcessNamespaceIdentity ->
  Maybe ProcessNamespaceIdentity ->
  RecordedNamespaceRelation
classifyRecordedNamespace recordedNamespace currentNamespace =
  case (recordedNamespace, currentNamespace) of
    (Nothing, Nothing) -> RecordedNamespaceMatches
    (Just recorded, Just current)
      | recorded == current -> RecordedNamespaceMatches
      | otherwise -> RecordedNamespaceIsForeign
    _ -> RecordedNamespaceCannotBeCompared

-- Kept as the exact namespace-local rule: only an absent process group proves
-- death, while a reused leader identity leaves the old group's descendants
-- unverifiable.
inspectOwnerWithinRecordedNamespace ::
  HarnessReservation ->
  IO HarnessReservationOwnerStatus
inspectOwnerWithinRecordedNamespace reservation = do
  groupProbe <-
    try
      ( signalProcessGroup
          nullSignal
          (fromIntegral (harnessReservationProcessGroup reservation))
      ) ::
      IO (Either IOException ())
  case groupProbe of
    Left failure
      | isDoesNotExistError failure ->
          pure HarnessReservationOwnerDefinitelyDead
      | otherwise ->
          pure HarnessReservationOwnerUnverifiable
    Right () ->
      case harnessReservationOwnerBirthIdentity reservation of
        -- A version-1 reservation can fence the slot while its PGID exists,
        -- but its reusable numeric identity can never authorize a caller.
        Nothing -> pure HarnessReservationOwnerUnverifiable
        Just expectedBirthIdentity -> do
          observedBirthIdentity <-
            readProcessBirthIdentity
              (harnessReservationOwnerPid reservation)
          -- A mismatched or missing leader identity denies authority, but the
          -- still-populated PGID may contain descendants of the old owner.
          -- Only ESRCH from the group probe is evidence that recovery is safe.
          case observedBirthIdentity of
            Just identity
              | identity == expectedBirthIdentity ->
                  pure HarnessReservationOwnerVerifiedAlive
              | otherwise ->
                  pure HarnessReservationOwnerUnverifiable
            Nothing -> pure HarnessReservationOwnerUnverifiable

beginHarnessConfigTransaction :: Paths -> Bool -> IO a -> IO a
beginHarnessConfigTransaction paths hadExistingRuntimeConfig action =
  withClusterLifecycleLock paths $ \_ -> do
    access <- requireReservationAccess paths HarnessOwned
    reservation <- harnessReservationFromAccess access
    case harnessReservationConfigTransaction reservation of
      HarnessConfigUntouched -> do
        writeHarnessReservation
          paths
          reservation
            { harnessReservationConfigTransaction =
                if hadExistingRuntimeConfig
                  then HarnessConfigRestorePending
                  else HarnessConfigRemovePending
            }
        action
      transaction ->
        ioError
          ( userError
              ( "refusing to begin a second harness config transaction while the reservation is "
                  <> show transaction
              )
          )

completeHarnessConfigTransaction :: Paths -> IO a -> IO a
completeHarnessConfigTransaction paths action =
  withClusterLifecycleLock paths $ \_ -> do
    access <- requireReservationAccess paths HarnessOwned
    reservation <- harnessReservationFromAccess access
    case harnessReservationConfigTransaction reservation of
      HarnessConfigRestorePending -> complete reservation
      HarnessConfigRemovePending -> complete reservation
      transaction ->
        ioError
          ( userError
              ( "refusing to complete a harness config transaction from state "
                  <> show transaction
              )
          )
  where
    complete reservation = do
      result <- action
      writeHarnessReservation
        paths
        reservation {harnessReservationConfigTransaction = HarnessConfigRestored}
      pure result

harnessReservationFromAccess :: ClusterReservationAccess -> IO HarnessReservation
harnessReservationFromAccess reservationAccess =
  case reservationAccess of
    HarnessReservationAccess reservation -> pure reservation
    OperatorReservationAccess ->
      ioError
        ( userError
            "harness reservation evidence was required but operator evidence was provided"
        )

reconcileInterruptedHarnessState :: IO ()
reconcileInterruptedHarnessState = do
  paths <- Config.discoverPaths
  reconcileInterruptedHarnessStateAt paths

reconcileInterruptedHarnessStateAt :: Paths -> IO ()
reconcileInterruptedHarnessStateAt paths = do
  Config.ensureRepoLayout paths
  maybeReservation <- readHarnessReservation paths
  case maybeReservation of
    Nothing -> refuseUnreservedHarnessBackup paths
    Just reservation -> do
      ownerInspection <- inspectHarnessReservationOwner paths reservation
      case inspectedOwnerStatus ownerInspection of
        HarnessReservationOwnerVerifiedAlive -> pure ()
        HarnessReservationOwnerUnverifiable ->
          refuseUnverifiableHarnessReservation paths reservation ownerInspection
        HarnessReservationOwnerDefinitelyDead ->
          withClusterLifecycleLock paths $ \_ -> do
            currentReservation <- readHarnessReservation paths
            case currentReservation of
              Nothing -> refuseUnreservedHarnessBackup paths
              Just lockedReservation -> do
                lockedOwnerInspection <-
                  inspectHarnessReservationOwner paths lockedReservation
                case inspectedOwnerStatus lockedOwnerInspection of
                  HarnessReservationOwnerVerifiedAlive -> pure ()
                  HarnessReservationOwnerUnverifiable ->
                    refuseUnverifiableHarnessReservation
                      paths
                      lockedReservation
                      lockedOwnerInspection
                  HarnessReservationOwnerDefinitelyDead ->
                    withKernelFileLock
                      "harness cluster-slot recovery"
                      (harnessLifetimeLockPath paths)
                      ( do
                          -- Live-inventory discovery is itself a bounded
                          -- command. Observe it while the lifecycle and dead
                          -- owner's lifetime locks are held, before entering
                          -- the exclusive activity-quiescence region whose
                          -- callback cannot recursively start a shared-lock
                          -- helper.
                          presentRuntimeModes <- presentClusterRuntimeModes paths
                          recordedState <- loadClusterState paths
                          Subprocess.withBoundedCommandActivitiesQuiescent
                            paths
                            (harnessReservationProcessGroup lockedReservation)
                            ( \activitiesQuiescent -> do
                                restoredReservation <-
                                  recoverHarnessConfigTransaction
                                    activitiesQuiescent
                                    paths
                                    lockedReservation
                                if deadReservationCanBeRemoved restoredReservation presentRuntimeModes recordedState
                                  then
                                    removeHarnessReservation
                                      activitiesQuiescent
                                      paths
                                      lockedReservation
                                  else writeHarnessReservation paths restoredReservation
                            )
                      )

deadReservationCanBeRemoved ::
  HarnessReservation ->
  [RuntimeMode] ->
  Maybe ClusterState ->
  Bool
deadReservationCanBeRemoved reservation presentRuntimeModes maybeState =
  null presentRuntimeModes
    || ( harnessReservationConfigTransaction reservation == HarnessConfigUntouched
           && operatorOwnsOnlyPresentRuntime presentRuntimeModes maybeState
       )

operatorOwnsOnlyPresentRuntime :: [RuntimeMode] -> Maybe ClusterState -> Bool
operatorOwnsOnlyPresentRuntime presentRuntimeModes maybeState =
  case (presentRuntimeModes, maybeState) of
    ([presentRuntimeMode], Just state) ->
      clusterOwner state == OperatorOwned
        && clusterRuntimeMode state == presentRuntimeMode
    _ -> False

refuseUnreservedHarnessBackup :: Paths -> IO ()
refuseUnreservedHarnessBackup paths = do
  let backupConfig = Config.runtimeConfigPath paths <> ".harness-backup"
  backupPresent <- doesFileExist backupConfig
  when backupPresent $
    ioError
      ( userError
          ( "refusing identity-free harness config recovery: "
              <> backupConfig
              <> " exists without a harness reservation; preserve both files and resolve the orphaned backup explicitly"
          )
      )

recoverHarnessConfigTransaction ::
  Subprocess.BoundedCommandActivitiesQuiescent s ->
  Paths ->
  HarnessReservation ->
  IO HarnessReservation
recoverHarnessConfigTransaction activitiesQuiescent paths reservation = do
  requireBoundedCommandQuiescenceEvidence
    activitiesQuiescent
    reservation
  let runtimeConfig = Config.runtimeConfigPath paths
      backupConfig = runtimeConfig <> ".harness-backup"
      markRestored =
        reservation {harnessReservationConfigTransaction = HarnessConfigRestored}
  runtimePresent <- doesFileExist runtimeConfig
  backupPresent <- doesFileExist backupConfig
  case harnessReservationConfigTransaction reservation of
    HarnessConfigUntouched -> pure reservation
    HarnessConfigRestored -> pure reservation
    HarnessConfigRestorePending ->
      case (runtimePresent, backupPresent) of
        (_, True) -> do
          when runtimePresent (removeFile runtimeConfig)
          renameFile backupConfig runtimeConfig
          -- Phase 8 Sprint 8.11: recovery restores the operator's system
          -- contract, so it re-points this machine's pin at it too.
          restampMachineContractPin paths
          pure markRestored
        (True, False) ->
          pure markRestored
        (False, False) -> do
          -- Phase 6 Sprint 6.52: a restore-pending transaction with neither
          -- file present means one of two very different things, and the
          -- recorded owner namespace is what separates them.
          --
          -- The reservation is durable (`.data/` is host-mounted) while the
          -- config it describes is not: on the container lane `/workspace` is
          -- the image's own filesystem, so a killed launcher leaves a record
          -- whose subject no longer exists anywhere this process can see. The
          -- supported dead-owner reclamation path then asks this function to
          -- reconcile a transaction over a filesystem that is gone, and the
          -- retired arm refused unconditionally — which made the slot
          -- unreclaimable by the very path that exists to reclaim it.
          --
          -- A foreign namespace proves the subject is not ours: there is
          -- nothing here to restore and nothing here to clobber, so the
          -- transaction is terminal and the slot may be reclaimed. A matching
          -- namespace with both files absent is the opposite case — the
          -- operator's own config was moved to a backup that then vanished,
          -- which is real loss, and continuing would hide it. That one still
          -- fails closed, as does a namespace that cannot be compared at all,
          -- because absence of proof that the subject is foreign is not proof
          -- that it is ours.
          currentNamespace <- observeCurrentProcessNamespaceIdentity
          case classifyAbsentConfigRecovery
            ( classifyRecordedNamespace
                (harnessReservationOwnerPidNamespace reservation)
                currentNamespace
            ) of
            AbsentConfigReclaimable -> pure markRestored
            AbsentConfigUnrecoverable reason -> ioError (userError reason)
    HarnessConfigRemovePending ->
      if backupPresent
        then
          ioError
            ( userError
                "cannot recover interrupted harness config takeover: an unexpected backup exists for an originally absent config"
            )
        else do
          when runtimePresent (removeFile runtimeConfig)
          pure markRestored

-- | Phase 6 Sprint 6.52 — what a restore-pending transaction means when
-- neither the operator config nor its backup is present.
data AbsentConfigRecovery
  = AbsentConfigReclaimable
  | AbsentConfigUnrecoverable String
  deriving (Eq, Show)

-- | The decision, as a pure function of the recorded owner namespace.
--
-- Only a namespace proven foreign licenses reclamation. A matching namespace
-- means the operator's own config was moved to a backup that then vanished —
-- real loss, which must stay loud — and an incomparable namespace is not
-- evidence of anything, so it fails closed too.
classifyAbsentConfigRecovery :: RecordedNamespaceRelation -> AbsentConfigRecovery
classifyAbsentConfigRecovery relation =
  case relation of
    RecordedNamespaceIsForeign -> AbsentConfigReclaimable
    RecordedNamespaceMatches ->
      AbsentConfigUnrecoverable
        "cannot recover interrupted harness config takeover: both the operator config and its backup are absent"
    RecordedNamespaceCannotBeCompared ->
      AbsentConfigUnrecoverable
        "cannot recover interrupted harness config takeover: both the operator config and its backup are absent, and the recorded owner namespace cannot be compared with this one"

ensureHarnessReservationAvailable :: Paths -> IO ()
ensureHarnessReservationAvailable paths = do
  maybeReservation <- readHarnessReservation paths
  case maybeReservation of
    Nothing -> pure ()
    Just reservation -> do
      ownerInspection <- inspectHarnessReservationOwner paths reservation
      case inspectedOwnerStatus ownerInspection of
        HarnessReservationOwnerVerifiedAlive ->
          ioError
            ( userError
                ( "test harness cluster-slot seizure refused: another live harness process group owns "
                    <> harnessReservationPath paths
                )
            )
        HarnessReservationOwnerUnverifiable ->
          refuseUnverifiableHarnessReservation paths reservation ownerInspection
        HarnessReservationOwnerDefinitelyDead ->
          withKernelFileLock
            "harness cluster-slot recovery"
            (harnessLifetimeLockPath paths)
            ( Subprocess.withBoundedCommandActivitiesQuiescent
                paths
                (harnessReservationProcessGroup reservation)
                ( \activitiesQuiescent -> do
                    recoveredReservation <-
                      recoverHarnessConfigTransaction
                        activitiesQuiescent
                        paths
                        reservation
                    unless
                      ( harnessReservationConfigTransaction recoveredReservation
                          `elem` [HarnessConfigUntouched, HarnessConfigRestored]
                      )
                      ( ioError
                          ( userError
                              "test harness cluster-slot seizure refused: the interrupted config transaction could not be reconciled"
                          )
                      )
                    removeHarnessReservation
                      activitiesQuiescent
                      paths
                      reservation
                )
            )

requireBoundedCommandQuiescenceEvidence ::
  Subprocess.BoundedCommandActivitiesQuiescent s ->
  HarnessReservation ->
  IO ()
requireBoundedCommandQuiescenceEvidence activitiesQuiescent reservation =
  unless
    ( Subprocess.boundedCommandActivitiesOwnerProcessGroup activitiesQuiescent
        == harnessReservationProcessGroup reservation
    )
    ( ioError
        ( userError
            "bounded-command quiescence evidence belongs to another harness reservation process group"
        )
    )

removeHarnessReservation ::
  Subprocess.BoundedCommandActivitiesQuiescent s ->
  Paths ->
  HarnessReservation ->
  IO ()
removeHarnessReservation activitiesQuiescent paths reservation = do
  requireBoundedCommandQuiescenceEvidence
    activitiesQuiescent
    reservation
  removeFileIfExists (harnessReservationPath paths)

refuseUnverifiableHarnessReservation ::
  Paths ->
  HarnessReservation ->
  HarnessReservationOwnerInspection ->
  IO a
refuseUnverifiableHarnessReservation paths reservation inspection =
  ioError
    ( userError
        ( "refusing cluster-slot mutation because the reservation owner identity cannot be verified at "
            <> renderHarnessReservationInspection paths reservation inspection
            <> "; run `infernix cluster reclaim-slot --force-owner-pid "
            <> show (harnessReservationOwnerPid reservation)
            <> "` after verifying that recorded owner is gone"
        )
    )

renderHarnessReservationInspection ::
  Paths ->
  HarnessReservation ->
  HarnessReservationOwnerInspection ->
  String
renderHarnessReservationInspection paths reservation inspection =
  harnessReservationPath paths
    <> "; recorded-pid="
    <> show (harnessReservationOwnerPid reservation)
    <> "; recorded-process-group="
    <> show (harnessReservationProcessGroup reservation)
    <> "; recorded-birth-identity="
    <> show (harnessReservationOwnerBirthIdentity reservation)
    <> "; recorded-pid-namespace="
    <> renderOptionalNamespace
      (harnessReservationOwnerPidNamespace reservation)
    <> "; current-pid-namespace="
    <> renderOptionalNamespace
      (inspectedCurrentPidNamespace inspection)
    <> "; namespace-relation="
    <> show (inspectedNamespaceRelation inspection)
    <> "; lifetime-lock-held="
    <> show (inspectedLifetimeLockHeld inspection)
    <> "; owner-status="
    <> show (inspectedOwnerStatus inspection)
  where
    renderOptionalNamespace =
      maybe "unavailable-or-unrecorded" renderProcessNamespaceIdentity

createHarnessReservation :: Paths -> IO ClusterReservationAccess
createHarnessReservation paths = do
  ownerPid <- getProcessID
  existingProcessGroup <- getProcessGroupID
  when (existingProcessGroup /= fromIntegral ownerPid) $ do
    _ <- createProcessGroupFor ownerPid
    pure ()
  ownerProcessGroup <- getProcessGroupID
  unless (ownerProcessGroup == fromIntegral ownerPid) $
    ioError
      ( userError
          "test harness cluster-slot seizure refused: the reservation owner did not become its process-group leader"
      )
  ownerBirthIdentity <- registerCurrentProcessIdentity
  ownerPidNamespace <- observeCurrentProcessNamespaceIdentity
  let reservation =
        HarnessReservation
          { harnessReservationOwnerPid = fromIntegral ownerPid,
            harnessReservationProcessGroup = fromIntegral ownerProcessGroup,
            harnessReservationOwnerBirthIdentity = Just ownerBirthIdentity,
            harnessReservationOwnerPidNamespace = ownerPidNamespace,
            harnessReservationConfigTransaction = HarnessConfigUntouched,
            harnessReservationAuthorizedChildGroup = Nothing
          }
  writeHarnessReservation paths reservation
  pure (HarnessReservationAccess reservation)

-- | Delegate reservation authority to one freshly spawned toolchain child for
-- the duration of that child, then withdraw it.
--
-- The owner is the only writer here, and the delegation is a single slot rather
-- than a set: the harness runs its cluster-owned suites one at a time, and a set
-- would make \"which child is live\" a question the reservation cannot answer
-- after a crash. Withdrawal restores exactly 'Nothing' rather than reasserting a
-- remembered value, so a nested delegation cannot leave a dead group authorized.
--
-- A caller that holds no reservation (an operator running the same suite) is a
-- no-op rather than an error: the delegation exists only to widen an authority
-- that is already held.
withDelegatedHarnessChildGroup :: Paths -> Integer -> IO a -> IO a
withDelegatedHarnessChildGroup paths childProcessGroup action =
  bracketPreservingPrimary
    (updateDelegation (Just childProcessGroup))
    (const (updateDelegation Nothing))
    (const action)
  where
    updateDelegation delegation =
      withClusterLifecycleLock paths $ \_ -> do
        maybeReservation <- readHarnessReservation paths
        currentProcessGroup <- fromIntegral <$> getProcessGroupID
        case maybeReservation of
          Just reservation
            | harnessReservationProcessGroup reservation == currentProcessGroup,
              delegation /= Just currentProcessGroup ->
                writeHarnessReservation
                  paths
                  reservation
                    { harnessReservationAuthorizedChildGroup = delegation
                    }
          _ -> pure ()

-- | The operator's @infernix cluster down@ command. It refuses a live
-- 'HarnessOwned' cluster (and a live cluster with unknown ownership).
clusterDown :: Maybe RuntimeMode -> IO ()
clusterDown = clusterDownForOwner "tear down the operator cluster" SOperatorOwned

-- | Harness-only teardown. It refuses a live 'OperatorOwned' cluster, including
-- when an operator wins the slot between harness seizure and a cleanup
-- @finally@.
clusterDownHarness :: Maybe RuntimeMode -> IO ()
clusterDownHarness = clusterDownForOwner "tear down the harness cluster" SHarnessOwned

-- | Enclose the complete harness lifecycle in the cross-namespace lifetime
-- lock. Interrupted-state recovery happens before acquisition; after the lock
-- is held, reservation publication and cleanup remain the only supported
-- production path and the kernel drops the liveness token on process death.
withHarnessClusterSlot :: Maybe RuntimeMode -> IO a -> IO a
withHarnessClusterSlot maybeRuntimeMode action = do
  paths <- discoverClusterCommandPaths
  withHarnessClusterSlotAt paths maybeRuntimeMode action

withHarnessClusterSlotAt :: Paths -> Maybe RuntimeMode -> IO a -> IO a
withHarnessClusterSlotAt paths maybeRuntimeMode action = do
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \_ ->
    ensureHarnessReservationAvailable paths
  withKernelFileLock
    "harness cluster-slot lifetime"
    (harnessLifetimeLockPath paths)
    ( bracketPreservingPrimary
        (seizeHarnessClusterSlotAt paths maybeRuntimeMode)
        (const (releaseHarnessClusterSlotAt paths maybeRuntimeMode))
        (const action)
    )

-- | Unit-test seam for the transition inside 'withHarnessClusterSlotAt'.
-- Production callers cannot retain the lifetime lock across a returned raw
-- seizure and therefore use the enclosing bracket above.
seizeHarnessClusterSlotAt :: Paths -> Maybe RuntimeMode -> IO ()
seizeHarnessClusterSlotAt paths maybeRuntimeMode = do
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    ensureHarnessReservationAvailable paths
    preauthorizeHarnessClusterSlot paths maybeRuntimeMode
    reservationAccess <- createHarnessReservation paths
    clusterDownForOwnerUnderLock
      lifecycleLock
      paths
      "seize the cluster slot for the harness"
      SHarnessOwned
      reservationAccess
      maybeRuntimeMode

preauthorizeHarnessClusterSlot :: Paths -> Maybe RuntimeMode -> IO ()
preauthorizeHarnessClusterSlot paths maybeRuntimeMode = do
  recordedState <- loadClusterState paths
  requestedRuntimeMode <- resolveCommandRuntimeMode paths maybeRuntimeMode recordedState
  presentRuntimeModes <- presentClusterRuntimeModes paths
  let runtimeMode =
        teardownRuntimeMode
          HarnessOwned
          requestedRuntimeMode
          presentRuntimeModes
          recordedState
  localIdentity <- localClusterCheckoutIdentity paths
  slotIdentity <- observeClusterSlotIdentity paths presentRuntimeModes
  case authorizeClusterOwnership
    HarnessOwned
    runtimeMode
    presentRuntimeModes
    recordedState
    localIdentity
    slotIdentity of
    Right _ -> pure ()
    Left refusal ->
      ioError
        ( userError
            ( "test harness cluster-slot seizure refused before reservation publication: "
                <> "the live cluster inventory is not HarnessOwned for runtime "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> clusterOwnershipRefusalDetail refusal
            )
        )

-- | Finish a harness reservation. Teardown must succeed before the reservation
-- is removed; otherwise operator mutations remain fenced from a possibly live
-- harness writer.
releaseHarnessClusterSlotAt :: Paths -> Maybe RuntimeMode -> IO ()
releaseHarnessClusterSlotAt paths maybeRuntimeMode = do
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    reservationAccess <- requireReservationAccess paths HarnessOwned
    reservation <- harnessReservationFromAccess reservationAccess
    releasingPid <- fromIntegral <$> getProcessID
    unless (releasingPid == harnessReservationOwnerPid reservation) $
      ioError
        ( userError
            "only the harness process that seized the cluster slot may release it"
        )
    unless
      ( harnessReservationConfigTransaction reservation
          `elem` [HarnessConfigUntouched, HarnessConfigRestored]
      )
      ( ioError
          ( userError
              "refusing to release the harness cluster slot while its config transaction is incomplete"
          )
      )
    clusterDownForOwnerUnderLock
      lifecycleLock
      paths
      "release the cluster slot held by the harness"
      SHarnessOwned
      reservationAccess
      maybeRuntimeMode
    Subprocess.withBoundedCommandActivitiesQuiescent
      paths
      (harnessReservationProcessGroup reservation)
      ( \activitiesQuiescent ->
          removeHarnessReservation
            activitiesQuiescent
            paths
            reservation
      )

-- | Recover an interrupted harness reservation without running the ordinary
-- pre-dispatch reconciliation that would make this command unreachable for an
-- unverifiable legacy record. A forced PID is an operator-asserted premise
-- transcribed from the record; it never bypasses the lifetime lock, bounded
-- command quiescence proof, or config-transaction recovery.
reclaimHarnessClusterSlot :: Maybe Integer -> IO ()
reclaimHarnessClusterSlot maybeForcedOwnerPid = do
  paths <- Config.discoverPaths
  reclaimHarnessClusterSlotAt paths maybeForcedOwnerPid

reclaimHarnessClusterSlotAt :: Paths -> Maybe Integer -> IO ()
reclaimHarnessClusterSlotAt paths maybeForcedOwnerPid = do
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \_ -> do
    maybeReservation <- readHarnessReservation paths
    case maybeReservation of
      Nothing ->
        putStrLn "harness cluster-slot reservation is already absent"
      Just reservation -> do
        inspection <- inspectHarnessReservationOwner paths reservation
        putStrLn (renderHarnessReservationInspection paths reservation inspection)
        case inspectedOwnerStatus inspection of
          HarnessReservationOwnerVerifiedAlive ->
            ioError
              ( userError
                  "refusing to reclaim the harness cluster slot from its verified-live owner"
              )
          HarnessReservationOwnerDefinitelyDead ->
            retireHarnessReservation paths reservation
          HarnessReservationOwnerUnverifiable ->
            case maybeForcedOwnerPid of
              Just forcedOwnerPid
                | forcedOwnerPid == harnessReservationOwnerPid reservation ->
                    retireHarnessReservation paths reservation
                | otherwise ->
                    ioError
                      ( userError
                          ( "refusing to reclaim the harness cluster slot: --force-owner-pid "
                              <> show forcedOwnerPid
                              <> " does not match recorded owner pid "
                              <> show (harnessReservationOwnerPid reservation)
                          )
                      )
              Nothing ->
                refuseUnverifiableHarnessReservation paths reservation inspection

retireHarnessReservation :: Paths -> HarnessReservation -> IO ()
retireHarnessReservation paths reservation =
  withKernelFileLock
    "harness cluster-slot recovery"
    (harnessLifetimeLockPath paths)
    ( Subprocess.withBoundedCommandActivitiesQuiescent
        paths
        (harnessReservationProcessGroup reservation)
        ( \activitiesQuiescent -> do
            recoveredReservation <-
              recoverHarnessConfigTransaction
                activitiesQuiescent
                paths
                reservation
            unless
              ( harnessReservationConfigTransaction recoveredReservation
                  `elem` [HarnessConfigUntouched, HarnessConfigRestored]
              )
              ( ioError
                  ( userError
                      "harness cluster-slot reclaim refused: the config transaction did not reach a terminal state"
                  )
              )
            removeHarnessReservation activitiesQuiescent paths reservation
            putStrLn "harness cluster-slot reservation reclaimed"
        )
    )

-- | The raw ownership-gated teardown. Forces its 'ClusterTeardownAuthority' (a
-- data-constructor match is strict to WHNF), so an @undefined@-forged authority
-- is a loud crash rather than a silent unmanaged teardown. The authority is
-- minted only after the same locked presence/owner check.
clusterDownForOwner :: String -> SClusterOwner owner -> Maybe RuntimeMode -> IO ()
clusterDownForOwner action requestedOwnerSingleton maybeRuntimeMode = do
  paths <- discoverClusterCommandPaths
  Config.ensureRepoLayout paths
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    reservationAccess <-
      requireReservationAccess paths (clusterOwnerValue requestedOwnerSingleton)
    clusterDownForOwnerUnderLock
      lifecycleLock
      paths
      action
      requestedOwnerSingleton
      reservationAccess
      maybeRuntimeMode

clusterDownForOwnerUnderLock ::
  Lease lock ClusterMutationLocked ->
  Paths ->
  String ->
  SClusterOwner owner ->
  ClusterReservationAccess ->
  Maybe RuntimeMode ->
  IO ()
clusterDownForOwnerUnderLock lifecycleLock paths action requestedOwnerSingleton reservationAccess maybeRuntimeMode = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  recordedState <- loadClusterState paths
  requestedRuntimeMode <- resolveCommandRuntimeMode paths maybeRuntimeMode recordedState
  presentRuntimeModes <- presentClusterRuntimeModes paths
  let requestedOwner = clusterOwnerValue requestedOwnerSingleton
      runtimeMode =
        teardownRuntimeMode
          requestedOwner
          requestedRuntimeMode
          presentRuntimeModes
          recordedState
  teardownAuthority <-
    requireClusterOwnership
      lifecycleLock
      paths
      runtimeMode
      action
      requestedOwnerSingleton
      reservationAccess
      presentRuntimeModes
      recordedState
  clusterDownResolved
    lifecycleLock
    teardownAuthority
    paths
    runtimeMode
    (\_ -> pure ())

-- Harness cleanup follows an already-recorded HarnessOwned cluster even when a
-- stale generated config selects another runtime. Operator teardown never
-- retargets implicitly.
teardownRuntimeMode ::
  ClusterOwner ->
  RuntimeMode ->
  [RuntimeMode] ->
  Maybe ClusterState ->
  RuntimeMode
teardownRuntimeMode requestedOwner requestedRuntimeMode presentRuntimeModes maybeState =
  case (requestedOwner, presentRuntimeModes, maybeState) of
    (HarnessOwned, [presentRuntimeMode], Just state)
      | clusterOwner state == HarnessOwned,
        clusterRuntimeMode state == presentRuntimeMode ->
          presentRuntimeMode
    _ -> requestedRuntimeMode

-- | Execute teardown while the caller holds the cross-process lifecycle lock.
-- The rank-2 callback can perform additional retained-state repair only inside
-- the same 'WriterQuiesced' region used by the standard rebuildable scrub.
clusterDownResolved ::
  Lease s ClusterMutationLocked ->
  ClusterTeardownAuthority owner s ->
  Paths ->
  RuntimeMode ->
  (forall writerRegion. Lease writerRegion WriterQuiesced -> IO ()) ->
  IO ()
clusterDownResolved lifecycleLock authority paths runtimeMode onQuiesced = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  unless (teardownAuthorityRuntimeMode authority == runtimeMode) $
    ioError
      ( userError
          "cluster teardown authority/runtime mismatch"
      )
  (recordedState, presentRuntimeModes) <-
    revalidateClusterTeardownAuthority
      lifecycleLock
      "perform the authorized cluster teardown"
      authority
      paths
      runtimeMode
  let maybeState = matchingClusterState runtimeMode recordedState
      clusterExists = runtimeMode `elem` presentRuntimeModes
  when clusterExists $ do
    usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
    if usesHostBindMounts
      then deleteRecordedCluster maybeState
      else do
        frozenMaybeState <-
          case maybeState of
            Just state ->
              Just
                <$> startLifecyclePhase
                  paths
                  state
                  "cluster-down"
                  "freeze-retained-state"
                  "pausing every retained-state worker before snapshot staging"
            Nothing -> pure Nothing
        withFrozenRetainedSnapshotSource
          lifecycleLock
          paths
          runtimeMode
          frozenMaybeState
          ( \frozenSource -> do
              withDetachedRetainedCopyTarget lifecycleLock paths runtimeMode $ \detachedTarget ->
                case frozenMaybeState of
                  Just state -> do
                    replayState <-
                      startLifecyclePhase
                        paths
                        state
                        "cluster-down"
                        "replay-retained-state"
                        "staging a writer-frozen retained Kind snapshot before cluster deletion"
                    syncKindNodeRuntimePathsToHost frozenSource detachedTarget paths (Just replayState)
                  Nothing ->
                    syncKindNodeRuntimePathsToHost frozenSource detachedTarget paths Nothing
              -- The frozen-source lease remains live through deletion. Its
              -- release then tolerates the now-absent worker containers.
              deleteRecordedCluster maybeState
          )
  withWriterQuiesced lifecycleLock paths runtimeMode $ \quiesced -> do
    scrubRetainedStateUnderLease quiesced paths
    onQuiesced quiesced
  case maybeState of
    Nothing -> putStrLn "cluster already absent"
    Just state
      | clusterRuntimeMode state /= runtimeMode -> putStrLn "cluster down complete"
      | otherwise -> do
          _ <- settleLifecycle paths state ClusterAbsent
          putStrLn "cluster down complete"
  where
    deleteRecordedCluster stateValue =
      case stateValue of
        Just state -> do
          deleteState <-
            startLifecyclePhase
              paths
              state
              "cluster-down"
              "delete-kind-cluster"
              "deleting the Kind cluster after retained runtime data handling is complete"
          deleteKindCluster
            lifecycleLock
            (AuthorizedClusterTeardown authority)
            paths
            (clusterRuntimeMode deleteState)
        Nothing ->
          deleteKindCluster
            lifecycleLock
            (AuthorizedClusterTeardown authority)
            paths
            runtimeMode

clusterStatus :: Maybe RuntimeMode -> IO ()
clusterStatus maybeRuntimeMode = do
  paths <- Config.discoverPaths
  recordedState <- loadClusterState paths
  runtimeMode <- resolveCommandRuntimeMode paths maybeRuntimeMode recordedState
  let maybeState = matchingClusterState runtimeMode recordedState
  case maybeState of
    Nothing -> do
      putStrLn "cluster not yet reconciled"
      putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn "lifecycleStatus: idle"
      putStrLn "lifecyclePhase: not-yet-reconciled"
      putStrLn ("buildRoot: " <> buildRoot paths)
      putStrLn ("dataRoot: " <> dataRoot paths)
      putStrLn ("expectedDemoConfigPath: " <> Config.generatedDemoConfigPath paths)
      putStrLn ("expectedMountedDemoConfigPath: " <> Config.watchedDemoConfigPath)
    Just state -> do
      ensureOuterContainerKindNetworkAccess paths (clusterRuntimeMode state)
      actualPresent <- kindClusterExists paths (clusterRuntimeMode state)
      now <- getCurrentTime
      cacheEntries <- countLeafEntries (modelCacheRoot paths)
      resultCount <- countLeafEntries (resultsRoot paths)
      nodeCount <-
        kubectlLineCountIfReachable
          state
          Command.kubectlGetNodeRows
      podCount <-
        kubectlLineCountIfReachable
          state
          (`Command.kubectlListPods` Command.AllPodsNoHeaders)
      putStrLn ("clusterPresent: " <> show actualPresent)
      putStrLn ("clusterOwner: " <> clusterOwnerLabel (clusterOwner state))
      putStrLn ("controlPlaneContext: " <> controlPlaneContextId (Config.controlPlaneContext paths))
      putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId (clusterRuntimeMode state)))
      putStrLn ("edgePort: " <> show (edgePort state))
      putStrLn ("storageClass: " <> Text.unpack (storageClass state))
      putStrLn ("buildRoot: " <> buildRoot paths)
      putStrLn ("dataRoot: " <> dataRoot paths)
      putStrLn ("kubeconfigPath: " <> kubeconfigPath state)
      putStrLn ("generatedDemoConfigPath: " <> generatedDemoConfigPath state)
      putStrLn ("publishedDemoConfigPath: " <> publishedDemoConfigPath state)
      putStrLn ("publishedConfigMapManifestPath: " <> publishedConfigMapManifestPath state)
      putStrLn ("mountedDemoConfigPath: " <> mountedDemoConfigPath state)
      putStrLn ("publicationStatePath: " <> Config.publicationStatePath paths)
      putStrLn ("modelCacheRoot: " <> modelCacheRoot paths)
      putStrLn ("storageHealth: " <> show (length (claims state)) <> " chart-owned claim roots prepared")
      mapM_ putStrLn (lifecycleStatusLines now actualPresent state)
      publicationSummaryLines <- publicationStateSummaryLines (Config.publicationStatePath paths)
      putStrLn ("kubernetesNodeCount: " <> show nodeCount)
      putStrLn ("kubernetesPodCount: " <> show podCount)
      putStrLn ("runtimeResultCount: " <> show resultCount)
      putStrLn ("modelCacheEntryCount: " <> show cacheEntries)
      mapM_ putStrLn publicationSummaryLines
      mapM_
        (\route -> putStrLn ("route: " <> Text.unpack (path route) <> " -> " <> Text.unpack (purpose route)))
        (routes state)

lifecycleStatusLines :: UTCTime -> Bool -> ClusterState -> [String]
lifecycleStatusLines now actualPresent state =
  case lifecyclePhaseOf state of
    Nothing ->
      [ "lifecycleStatus: idle",
        "lifecyclePhase: " <> idleLifecyclePhase actualPresent
      ]
    Just phase ->
      let heartbeatAgeSeconds :: Integer
          heartbeatAgeSeconds =
            max 0 (round (diffUTCTime now (lifecyclePhaseHeartbeatAt phase)))
       in [ "lifecycleStatus: in-progress",
            "lifecycleAction: " <> lifecycleTransitionAction (lifecyclePhaseTransition phase),
            "lifecyclePhase: " <> lifecyclePhaseName phase,
            "lifecycleDetail: " <> lifecyclePhaseDetail phase,
            "lifecycleHeartbeatAt: " <> show (lifecyclePhaseHeartbeatAt phase),
            "lifecycleHeartbeatAgeSeconds: " <> show heartbeatAgeSeconds
          ]

idleLifecyclePhase :: Bool -> String
idleLifecyclePhase actualPresent =
  if actualPresent
    then "steady-state"
    else "cluster-absent"

-- | Sprint 2.14 (managed-state-transition doctrine): recorded state reads fail
-- closed. An absent state file is 'Nothing', but empty, malformed, or
-- unknown-version content is a loud 'ClusterStateDecodeFailure' rather than a
-- silent 'Nothing' — the previous behavior masked a corrupt or residual file as
-- "no cluster", which skipped retained-state replay during teardown and risked
-- losing durable data.
loadClusterState :: Paths -> IO (Maybe ClusterState)
loadClusterState paths = do
  let statePath = clusterStatePath paths
  result <- readClusterStateFile statePath
  case result of
    Right maybeState -> pure (fmap (normalizeClusterStatePaths paths) maybeState)
    Left detail -> throwIO (ClusterStateDecodeFailure statePath (take 300 detail))

runKubectlCompat :: [String] -> IO ()
runKubectlCompat args = do
  paths <- discoverClusterCommandPaths
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    reservationAccess <- requireReservationAccess paths OperatorOwned
    recordedState <- loadClusterState paths
    runtimeMode <- resolveCommandRuntimeMode paths Nothing recordedState
    let maybeState = matchingClusterState runtimeMode recordedState
    presentRuntimeModes <- presentClusterRuntimeModes paths
    _ <-
      requireClusterOwnership
        lifecycleLock
        paths
        runtimeMode
        "run operator kubectl read-only diagnostics"
        SOperatorOwned
        reservationAccess
        presentRuntimeModes
        recordedState
    let clusterExists = runtimeMode `elem` presentRuntimeModes
    case (clusterExists, maybeState) of
      (False, Nothing) ->
        putStrLn "No cluster state is available. Run `infernix cluster up` first."
      (False, Just _) -> putStrLn "Cluster is currently absent."
      (True, Just state) -> do
        ensureOuterContainerKindNetworkAccess paths (clusterRuntimeMode state)
        ensureClusterKubeconfigPresent paths state
        operatorCommand <-
          either
            (ioError . userError)
            pure
            ( Command.operatorKubectlCommand
                (Command.KubeTarget (kubeconfigPath state))
                args
            )
        putStr =<< captureOperatorKubectlCommand paths operatorCommand
      (True, Nothing) ->
        ioError
          ( userError
              "operator kubectl ownership authorization succeeded without matching cluster state"
          )

normalizeClusterStatePaths :: Paths -> ClusterState -> ClusterState
normalizeClusterStatePaths paths state =
  state
    { kubeconfigPath = Config.generatedKubeconfigPath paths
    }

-- | Closed test-harness mutation used by routed Playwright coverage. The model
-- id is resolved through the generated catalog before any deployment name is
-- constructed; callers cannot supply a Kubernetes resource or replica count.
runPlaywrightPrepareEngine :: Text.Text -> IO ()
runPlaywrightPrepareEngine requestedModelId =
  withHarnessPlaywrightCluster $ \paths state -> do
    let scale workload replicas =
          runClusterCommand
            paths
            ( Command.kubectlScaleDeployment
                (clusterKubeTarget state)
                (Command.Namespace "platform")
                (Command.WorkloadRef workload)
                replicas
            )
    demoConfig <- decodeDemoConfigFile (generatedDemoConfigPath state)
    case configRuntimeMode demoConfig of
      AppleSilicon -> pure ()
      LinuxCpu ->
        -- Phase 8 Sprint 8.12: a fleet deploys one Deployment per machine and
        -- no shared `infernix-engine`, so the browser preparation scales every
        -- machine rather than a single workload that would not exist.
        case clusterFleetEngineDeployments state of
          [] -> scale "deployment/infernix-engine" 1
          fleetDeployments -> forM_ fleetDeployments (`scale` 1)
      LinuxGpu -> do
        model <-
          maybe
            (ioError . userError $ "Playwright model is absent from the generated catalog: " <> Text.unpack requestedModelId)
            pure
            (List.find ((== requestedModelId) . modelId) (models demoConfig))
        binding <-
          maybe
            (ioError . userError $ "Playwright model has no selected engine binding: " <> Text.unpack requestedModelId)
            pure
            (engineBindingForSelectedEngine LinuxGpu (selectedEngine model))
        let maybeActiveEngine =
              if engineBindingPythonNative binding
                then engineNameForSelectedEngine LinuxGpu (selectedEngine model)
                else Nothing
        scale "deployment/infernix-engine" (maybe 1 (const 0) maybeActiveEngine)
        forM_ (perEngineDeploymentNames LinuxGpu) $ \engineName ->
          scale
            ("deployment/infernix-engine-" <> Text.unpack engineName)
            (if Just engineName == maybeActiveEngine then 1 else 0)

withHarnessPlaywrightCluster :: (Paths -> ClusterState -> IO a) -> IO a
withHarnessPlaywrightCluster action = do
  paths <- discoverClusterCommandPaths
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    reservationAccess <- requireReservationAccess paths HarnessOwned
    recordedState <- loadClusterState paths
    runtimeMode <- resolveCommandRuntimeMode paths Nothing recordedState
    presentRuntimeModes <- presentClusterRuntimeModes paths
    _ <-
      requireClusterOwnership
        lifecycleLock
        paths
        runtimeMode
        "run closed Playwright harness mutation"
        SHarnessOwned
        reservationAccess
        presentRuntimeModes
        recordedState
    state <-
      maybe
        (ioError (userError "Playwright harness mutation requires matching persisted cluster state"))
        pure
        (matchingClusterState runtimeMode recordedState)
    ensureOuterContainerKindNetworkAccess paths runtimeMode
    ensureClusterKubeconfigPresent paths state
    action paths state

ensureClusterKubeconfigPresent :: Paths -> ClusterState -> IO ()
ensureClusterKubeconfigPresent paths state = do
  let kubeconfigFile = kubeconfigPath state
  kubeconfigExists <- doesFileExist kubeconfigFile
  unless kubeconfigExists $
    publishGeneratedKubeconfig paths . Text.pack =<< waitForKindKubeconfigOrFail paths (clusterRuntimeMode state)

publicationStateSummaryLines :: FilePath -> IO [String]
publicationStateSummaryLines publicationPath = do
  publicationExists <- doesFileExist publicationPath
  if not publicationExists
    then pure []
    else do
      contents <- readFile publicationPath
      pure
        ( map ("publicationInferenceDispatchMode: " <>) (maybeToList (publicationInferenceDispatchMode contents))
            <> map ("publicationApiUpstreamMode: " <>) (maybeToList (publicationApiUpstreamMode contents))
            <> publicationUpstreamLines contents
        )

publicationInferenceDispatchMode :: String -> Maybe String
publicationInferenceDispatchMode contents =
  firstJsonStringField
    "\"inferenceDispatchMode\":"
    "inferenceDispatchMode"
    (lines contents)

publicationApiUpstreamMode :: String -> Maybe String
publicationApiUpstreamMode contents =
  firstJsonStringField
    "\"apiUpstream\": {"
    "mode"
    (lines contents)

publicationUpstreamLines :: String -> [String]
publicationUpstreamLines contents =
  foldr collect [] (lines contents)
  where
    collect lineValue acc =
      case publicationUpstreamLine lineValue of
        Just renderedLine -> renderedLine : acc
        Nothing -> acc

publicationUpstreamLine :: String -> Maybe String
publicationUpstreamLine lineValue = do
  upstreamId <- jsonStringField "id" lineValue
  healthStatusValue <- jsonStringField "healthStatus" lineValue
  targetSurfaceValue <- jsonStringField "targetSurface" lineValue
  durableBackendStateValue <- jsonStringField "durableBackendState" lineValue
  pure
    ( "publicationUpstream: "
        <> upstreamId
        <> " -> "
        <> healthStatusValue
        <> " via "
        <> targetSurfaceValue
        <> " ("
        <> durableBackendStateValue
        <> ")"
    )

firstJsonStringField :: String -> String -> [String] -> Maybe String
firstJsonStringField marker fieldName =
  go
  where
    go [] = Nothing
    go (lineValue : remaining)
      | marker `List.isInfixOf` lineValue = jsonStringField fieldName lineValue
      | otherwise = go remaining

jsonStringField :: String -> String -> Maybe String
jsonStringField fieldName lineValue =
  case dropWhile (not . List.isPrefixOf marker) (List.tails lineValue) of
    matched : _ -> readQuotedValue (drop (length marker) matched)
    [] -> Nothing
  where
    marker = "\"" <> fieldName <> "\": "

readQuotedValue :: String -> Maybe String
readQuotedValue value =
  case value of
    '"' : rest -> Just (takeWhile (/= '"') rest)
    _ -> Nothing

chooseEdgePort :: Paths -> IO Int
chooseEdgePort paths = chooseDynamicPort 9090 =<< readEdgePortMaybe paths

-- | Phase 3 follow-on (2026-05-29): pick a free host-side TCP port for
-- the registry's Kind hostPort mapping, mirroring 'chooseEdgePort'. The
-- in-cluster Kubernetes NodePort number stays @30002@ — only the
-- Kind hostPort observed by the operator host is dynamic, so the
-- chart's registry Service still resolves to @<node>:30002@ for
-- in-cluster reachability while the host probe and the containerd
-- registry-hosts namespace honor whatever port is actually free on
-- the operator's machine.
chooseRegistryPort :: Paths -> IO Int
chooseRegistryPort paths = chooseDynamicPort 30002 =<< readRegistryPortMaybe paths

-- | Phase 7 follow-on: pick a free host-side TCP port for the Pulsar proxy
-- HTTP NodePort's Kind hostPort mapping, mirroring 'chooseEdgePort' and
-- 'chooseRegistryPort'. The in-cluster Kubernetes NodePort number stays
-- @30080@; only the Kind hostPort observed by the operator host shifts when
-- another process (for example a VSCode auto-forwarded port) already holds
-- the @30080@ baseline. The Apple host-native service daemon reads the
-- selected port back from 'pulsarHttpPortPath' to reach the in-cluster
-- Pulsar proxy directly, bypassing the JWT-gated edge route.
choosePulsarHttpPort :: Paths -> IO Int
choosePulsarHttpPort paths = chooseDynamicPort pulsarProxyHttpNodePort =<< readPulsarHttpPortMaybe paths

pulsarProxyHttpNodePort :: Int
pulsarProxyHttpNodePort = 30080

chooseDynamicPort :: Int -> Maybe Int -> IO Int
chooseDynamicPort baseline maybeStoredPort =
  case maybeStoredPort of
    Just storedPort
      | storedPort >= baseline -> do
          storedPortFree <- portIsFree storedPort
          if storedPortFree
            then pure storedPort
            else firstAvailablePort (storedPort + 1)
    _ -> firstAvailablePort baseline

firstAvailablePort :: Int -> IO Int
firstAvailablePort = go
  where
    go candidatePort = do
      candidateFree <- portIsFree candidatePort
      if candidateFree
        then pure candidatePort
        else go (candidatePort + 1)

portIsFree :: Int -> IO Bool
portIsFree candidatePort = do
  bindResult <-
    try $
      Socket.withSocketsDo $
        bracket
          (Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol)
          Socket.close
          ( \socketHandle -> do
              Socket.setSocketOption socketHandle Socket.ReuseAddr 1
              Socket.bind
                socketHandle
                (Socket.SockAddrInet (fromIntegral candidatePort) (Socket.tupleToHostAddress (127, 0, 0, 1)))
          ) ::
      IO (Either IOException ())
  pure (either (const False) (const True) bindResult)

kindRuntimeRoot :: Paths -> RuntimeMode -> FilePath
kindRuntimeRoot paths runtimeMode =
  kindRoot paths </> Text.unpack (runtimeModeId runtimeMode)

claimDirectory :: Paths -> RuntimeMode -> PersistentClaim -> FilePath
claimDirectory paths runtimeMode =
  claimDirectoryUnder (kindRuntimeRoot paths runtimeMode)

claimDirectoryUnder :: FilePath -> PersistentClaim -> FilePath
claimDirectoryUnder retainedRoot persistentClaim =
  retainedRoot
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

ensureClaimDirectoryReady :: Paths -> RuntimeMode -> PersistentClaim -> IO ()
ensureClaimDirectoryReady paths runtimeMode persistentClaim = do
  let directoryPath = claimDirectory paths runtimeMode persistentClaim
  createDirectoryIfMissing True directoryPath
  -- Repo-local claim mirrors stay broadly writable so Apple can sync them into Linux Kind nodes
  -- even though the macOS host filesystem cannot model those node-local container owners.
  chmodClaimDirectory paths directoryPath
  case claimOwner persistentClaim of
    Nothing -> pure ()
    Just owner
      | hostClaimOwnershipAlignmentSupported paths -> do
          -- Phase 2 Sprint 2.13 follow-on (2026-05-31): chown alignment is a
          -- best-effort source-ownership tag across host/launcher/node
          -- filesystem boundaries. The actual Kind worker pod copies its own
          -- ownership during `prepareKindNodeRuntimePaths`, so a failure here
          -- is non-fatal as long as the directory is broadly writable (it is,
          -- per the `chmod a+rwX` above). Treat the chown as advisory: log
          -- the failure and continue so the lifecycle keeps moving.
          chownResult <-
            tryClusterCommand
              paths
              (Command.hostSetClaimOwner (Command.Owner owner) directoryPath)
          case chownResult of
            Right _ -> pure ()
            Left err ->
              putStrLn
                ( "warning: chown advisory failed for "
                    <> directoryPath
                    <> " (filesystem does not honor host-side ownership for "
                    <> owner
                    <> "); continuing with broadly writable permissions instead. ("
                    <> stripChownFailureNoise err
                    <> ")"
                )
      | otherwise -> pure ()

chmodClaimDirectory :: Paths -> FilePath -> IO ()
chmodClaimDirectory paths directoryPath = do
  repairResult <-
    ClaimPermissions.repairClaimPermissions
      5
      (createDirectoryIfMissing True directoryPath)
      (threadDelay 250000)
      ( tryClusterCommand
          paths
          (Command.hostMakeClaimWritable directoryPath)
      )
  case repairResult of
    Right () -> pure ()
    Left err ->
      ioError
        ( userError
            ( "command failed: chmod -R a+rwX "
                <> directoryPath
                <> "\n"
                <> err
            )
        )

stripChownFailureNoise :: String -> String
stripChownFailureNoise = takeWhile (/= '\n')

hostClaimOwnershipAlignmentSupported :: Paths -> Bool
hostClaimOwnershipAlignmentSupported paths =
  Config.controlPlaneContext paths == OuterContainer

claimOwner :: PersistentClaim -> Maybe String
claimOwner claimSpec
  | workload claimSpec == "minio" && claim claimSpec == "data" = Just "1001:1001"
  | "keycloak-postgresql" `List.isPrefixOf` Text.unpack (workload claimSpec) = Just "26:26"
  | otherwise = Nothing

ensureKindCluster ::
  Lease s ClusterMutationLocked ->
  ClusterTeardownAuthority owner s ->
  Paths ->
  RuntimeMode ->
  Bool ->
  RetainedReplayPlan ->
  Int ->
  Int ->
  Int ->
  IO (Int, Int, Int, String, Bool)
ensureKindCluster lifecycleLock teardownAuthority paths runtimeMode expectedClusterPresence replayPlan requestedPort requestedRegistryPort requestedPulsarHttpPort = do
  clusterExists <- kindClusterExists paths runtimeMode
  unless (clusterExists == expectedClusterPresence) $
    ioError
      ( userError
          ( "cluster presence changed while cluster up held the lifecycle lock for "
              <> kindClusterName paths runtimeMode
              <> "; refusing to act on stale replay evidence"
          )
      )
  (selectedPort, selectedRegistryPort, selectedPulsarHttpPort, clusterCreated) <-
    if clusterExists
      then do
        maybeExistingPort <- currentKindEdgePort paths runtimeMode
        maybeExistingRegistryPort <- currentKindRegistryPort paths runtimeMode
        maybeExistingPulsarHttpPort <- currentKindPulsarHttpPort paths runtimeMode
        pure
          ( fromMaybe requestedPort maybeExistingPort,
            fromMaybe requestedRegistryPort maybeExistingRegistryPort,
            fromMaybe requestedPulsarHttpPort maybeExistingPulsarHttpPort,
            False
          )
      else do
        (createdPort, createdRegistryPort, createdPulsarHttpPort) <- createKindCluster paths runtimeMode requestedPort requestedRegistryPort requestedPulsarHttpPort
        pure (createdPort, createdRegistryPort, createdPulsarHttpPort, True)
  kubeconfigResult <- waitForKindKubeconfig paths runtimeMode
  case kubeconfigResult of
    Right kubeconfigContents ->
      pure (selectedPort, selectedRegistryPort, selectedPulsarHttpPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) kubeconfigContents, clusterCreated)
    Left firstError ->
      case kindKubeconfigRecoveryPlan replayPlan of
        RecreatePreWorkloadKind -> do
          recoveryEvidence <-
            requirePreWorkloadKindRecovery
              lifecycleLock
              teardownAuthority
              paths
              runtimeMode
              replayPlan
          (recreatedPort, recreatedRegistryPort, recreatedPulsarHttpPort) <-
            recreatePreWorkloadKindCluster
              lifecycleLock
              recoveryEvidence
              paths
              selectedPort
              selectedRegistryPort
              selectedPulsarHttpPort
          recreatedKubeconfigResult <- waitForKindKubeconfig paths runtimeMode
          case recreatedKubeconfigResult of
            Right kubeconfigContents ->
              pure
                ( recreatedPort,
                  recreatedRegistryPort,
                  recreatedPulsarHttpPort,
                  normalizeKubeconfigServer
                    (Config.controlPlaneContext paths)
                    kubeconfigContents,
                  True
                )
            Left secondError ->
              ioError
                ( userError
                    ( "Kind kubeconfig remained unreadable after proof-gated pre-workload recreation for "
                        <> kindClusterName paths runtimeMode
                        <> "; retained replay remains pending for a later retry:\n"
                        <> secondError
                        <> "\ninitial kubeconfig failure:\n"
                        <> firstError
                    )
                )
        LeaveUnreadableKindUntouched ->
          ioError
            ( userError
                ( "Kind kubeconfig did not become readable for "
                    <> kindClusterName paths runtimeMode
                    <> "; the cluster is left untouched because no exact pre-workload replay intent authorizes deletion:\n"
                    <> firstError
                )
            )

requirePreWorkloadKindRecovery ::
  Lease s ClusterMutationLocked ->
  ClusterTeardownAuthority owner s ->
  Paths ->
  RuntimeMode ->
  RetainedReplayPlan ->
  IO (PreWorkloadKindRecovery owner s)
requirePreWorkloadKindRecovery lifecycleLock teardownAuthority paths runtimeMode replayPlan = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  unless (kindKubeconfigRecoveryPlan replayPlan == RecreatePreWorkloadKind) $
    ioError
      ( userError
          "pre-workload Kind recovery requires a retained-replay plan that authorizes recreation"
      )
  (recordedState, _) <-
    revalidateClusterTeardownAuthority
      lifecycleLock
      "recover an unreadable pre-workload Kind cluster"
      teardownAuthority
      paths
      runtimeMode
  case matchingClusterState runtimeMode recordedState of
    Just state
      | retainedReplayPending state ->
          pure
            ( PreWorkloadKindRecovery
                teardownAuthority
                runtimeMode
                (clusterLifecycle state)
            )
    _ ->
      ioError
        ( userError
            "pre-workload Kind recovery refused because the exact retained-replay lifecycle intent is no longer pending"
        )

recreatePreWorkloadKindCluster ::
  Lease s ClusterMutationLocked ->
  PreWorkloadKindRecovery owner s ->
  Paths ->
  Int ->
  Int ->
  Int ->
  IO (Int, Int, Int)
recreatePreWorkloadKindCluster lifecycleLock recoveryEvidence paths edgePortValue registryPortValue pulsarHttpPortValue = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  case recoveryEvidence of
    PreWorkloadKindRecovery _ runtimeMode _ -> do
      deleteKindCluster
        lifecycleLock
        (AuthorizedPreWorkloadRecovery recoveryEvidence)
        paths
        runtimeMode
      createKindCluster paths runtimeMode edgePortValue registryPortValue pulsarHttpPortValue

-- | Create the Kind cluster and immediately record which checkout created it.
--
-- Sprint 6.45 — the stamp is part of creation rather than a later bring-up
-- step because the window between the two is the only interval in which a
-- foreign checkout could observe the cluster as unidentified.
createKindCluster :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO (Int, Int, Int)
createKindCluster paths runtimeMode edgePortValue registryPortValue pulsarHttpPortValue = do
  publishedPorts <-
    createKindClusterNodes paths runtimeMode edgePortValue registryPortValue pulsarHttpPortValue
  stampClusterSlotIdentity paths runtimeMode
  pure publishedPorts

createKindClusterNodes :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO (Int, Int, Int)
createKindClusterNodes paths runtimeMode = case runtimeMode of
  LinuxGpu -> createLinuxGpuCluster paths
  _ -> go
  where
    go candidatePort registryPortCandidate pulsarHttpPortCandidate = do
      machineCount <- resolveClusterEngineMachineCount paths runtimeMode
      configPath <- writeGeneratedKindConfig paths runtimeMode machineCount candidatePort registryPortCandidate pulsarHttpPortCandidate
      result <- withKindScratchKubeconfig paths runtimeMode $ \scratchKubeconfig ->
        tryClusterCommand
          paths
          ( Command.kindCreate
              (Command.ClusterName (kindClusterName paths runtimeMode))
              configPath
              (Command.kindScratchKubeconfig scratchKubeconfig)
          )
      case result of
        Right _ -> pure (candidatePort, registryPortCandidate, pulsarHttpPortCandidate)
        Left err
          | kindHostPortConflict err ->
              go (candidatePort + 1) (registryPortCandidate + 1) (pulsarHttpPortCandidate + 1)
          | otherwise ->
              ioError
                (userError ("kind create cluster failed for " <> kindClusterName paths runtimeMode <> ":\n" <> err))

createLinuxGpuCluster :: Paths -> Int -> Int -> Int -> IO (Int, Int, Int)
createLinuxGpuCluster paths = go
  where
    go candidatePort registryPortCandidate pulsarHttpPortCandidate = do
      ensureLinuxGpuHostPrerequisites paths
      machineCount <- resolveClusterEngineMachineCount paths LinuxGpu
      configPath <- writeGeneratedKindConfig paths LinuxGpu machineCount candidatePort registryPortCandidate pulsarHttpPortCandidate
      result <- withKindScratchKubeconfig paths LinuxGpu $ \scratchKubeconfig ->
        tryClusterCommand
          paths
          ( Command.nvkindCreate
              (Command.ClusterName (kindClusterName paths LinuxGpu))
              configPath
              (Command.kindScratchKubeconfig scratchKubeconfig)
          )
      case result of
        Right _ -> pure (candidatePort, registryPortCandidate, pulsarHttpPortCandidate)
        Left err
          | kindHostPortConflict err ->
              go (candidatePort + 1) (registryPortCandidate + 1) (pulsarHttpPortCandidate + 1)
          | linuxGpuNvkindConfigMapBug err -> do
              clusterCreated <- kindClusterExists paths LinuxGpu
              if clusterCreated
                then do
                  putStrLn
                    ( "nvkind hit its known configmap persistence bug (nvkind reported: "
                        <> firstNonEmptyLine err
                        <> "); kind cluster was created — continuing with repo-owned linux-gpu node setup"
                    )
                  bootstrapResult <- try (completeLinuxGpuNodeBootstrap paths) :: IO (Either SomeException ())
                  case bootstrapResult of
                    Right () -> pure (candidatePort, registryPortCandidate, pulsarHttpPortCandidate)
                    Left bootstrapErr ->
                      ioError
                        ( userError
                            ( "repo-owned linux-gpu node bootstrap failed after working around the nvkind configmap persistence bug for "
                                <> kindClusterName paths LinuxGpu
                                <> ":\n"
                                <> displayException bootstrapErr
                            )
                        )
                else
                  ioError
                    ( userError
                        ( "nvkind cluster create hit its known configmap persistence bug but the kind cluster was not created for "
                            <> kindClusterName paths LinuxGpu
                            <> "; treat as fatal. nvkind reported:\n"
                            <> err
                        )
                    )
          | otherwise ->
              ioError
                (userError ("nvkind cluster create failed for " <> kindClusterName paths LinuxGpu <> ":\n" <> err))

kindHostPortConflict :: String -> Bool
kindHostPortConflict err =
  any (`List.isInfixOf` err) ["address already in use", "port is already allocated"]

linuxGpuNvkindConfigMapBug :: String -> Bool
linuxGpuNvkindConfigMapBug err =
  "%!w(<nil>)" `List.isInfixOf` err
    && ( "adding config to cluster" `List.isInfixOf` err
           || "writing configmap" `List.isInfixOf` err
       )

-- | First non-blank line of a captured error, trimmed, for single-line
-- diagnostics (e.g. the nvkind configmap-bug recovery log). Falls back to
-- the trimmed whole string when every line is blank.
firstNonEmptyLine :: String -> String
firstNonEmptyLine err =
  case dropWhile (all isSpace) (lines err) of
    (line : _) -> trim line
    [] -> trim err

completeLinuxGpuNodeBootstrap :: Paths -> IO ()
completeLinuxGpuNodeBootstrap paths = do
  nodeNames <- kindNodeNames paths LinuxGpu
  let workerNodeNames = filter (/= kindControlPlaneNodeName paths LinuxGpu) nodeNames
  mapM_ bootstrapWorkerNode workerNodeNames
  where
    bootstrapWorkerNode nodeName =
      runClusterCommand
        paths
        (Command.dockerBootstrapGpuNode (Command.NodeName nodeName))

data LinuxGpuProbeResults = LinuxGpuProbeResults
  { hostGpuResult :: Either String String,
    dockerRuntimeResult :: Either String String,
    dockerVolumeMountResult :: Either String String
  }

ensureLinuxGpuHostPrerequisites :: Paths -> IO ()
ensureLinuxGpuHostPrerequisites paths = do
  probeResults <- linuxGpuProbeResults paths
  unless (linuxGpuPreflightSatisfied (Config.controlPlaneContext paths) probeResults) $ do
    let failureReport = linuxGpuHostFailureReport (Config.controlPlaneContext paths) probeResults
    ioError (userError failureReport)

linuxGpuSupportedOnHost :: IO Bool
linuxGpuSupportedOnHost = do
  paths <- Config.discoverPaths
  linuxGpuPreflightSatisfied (Config.controlPlaneContext paths) <$> linuxGpuProbeResults paths

linuxGpuProbeResults :: Paths -> IO LinuxGpuProbeResults
linuxGpuProbeResults paths = do
  hostGpuResult <-
    tryClusterCommand
      paths
      Command.hostNvidiaSmiProbe
  dockerRuntimeResult <-
    tryClusterCommand
      paths
      (Command.dockerGpuProbe Command.RuntimeGpuProbe)
  defaultRuntimeVolumeMountResult <-
    tryClusterCommand
      paths
      (Command.dockerGpuProbe Command.DefaultRuntimeDeviceMountProbe)
  gpuVolumeMountResult <-
    tryClusterCommand
      paths
      (Command.dockerGpuProbe Command.GpuRuntimeDeviceMountProbe)
  let dockerVolumeMountResult =
        firstSuccessfulCommand
          defaultRuntimeVolumeMountResult
          gpuVolumeMountResult
  pure
    LinuxGpuProbeResults
      { hostGpuResult = hostGpuResult,
        dockerRuntimeResult = dockerRuntimeResult,
        dockerVolumeMountResult = dockerVolumeMountResult
      }

linuxGpuPreflightSatisfied :: ControlPlaneContext -> LinuxGpuProbeResults -> Bool
linuxGpuPreflightSatisfied controlPlane probeResults =
  commandSucceeded (dockerRuntimeResult probeResults)
    && commandSucceeded (dockerVolumeMountResult probeResults)
    && (controlPlane == OuterContainer || commandSucceeded (hostGpuResult probeResults))

commandSucceeded :: Either String String -> Bool
commandSucceeded result = case result of
  Right _ -> True
  Left _ -> False

firstSuccessfulCommand :: Either String String -> Either String String -> Either String String
firstSuccessfulCommand firstResult secondResult =
  case firstResult of
    Right _ -> firstResult
    Left firstErr ->
      case secondResult of
        Right secondOutput ->
          Right ("accepted docker --gpus all + worker-device mount preflight: " <> secondOutput)
        Left secondErr ->
          Left
            ( unlines
                [ "default runtime worker-device mount probe failed:",
                  firstErr,
                  "",
                  "docker --gpus all plus worker-device mount probe failed:",
                  secondErr
                ]
            )

linuxGpuHostFailureReport :: ControlPlaneContext -> LinuxGpuProbeResults -> String
linuxGpuHostFailureReport controlPlane probeResults =
  unlines
    ( [ "linux-gpu requires a real NVIDIA host plus a Docker engine configured for GPU and the NVIDIA volume-mount worker-device contract that nvkind uses for Kind workers.",
        "",
        "Active control-plane context: " <> controlPlaneContextId controlPlane
      ]
        <> requiredPreflightLines
        <> [ "",
             "If Docker is not configured yet, follow the NVIDIA toolkit setup sequence:",
             "  sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled",
             "  sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place",
             "  sudo systemctl restart docker",
             "",
             "Observed failures:",
             "launcher-local nvidia-smi:",
             renderCommandOutcome (hostGpuResult probeResults),
             "docker --gpus all:",
             renderCommandOutcome (dockerRuntimeResult probeResults),
             "docker worker-device mount preflight:",
             renderCommandOutcome (dockerVolumeMountResult probeResults)
           ]
    )
  where
    requiredPreflightLines
      | controlPlane == OuterContainer =
          [ "",
            "Required preflight commands for the outer-container launcher:",
            "  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  or docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "",
            "The supported NVIDIA host still needs a working `nvidia-smi -L`, but the launcher container may not ship that binary locally."
          ]
      | otherwise =
          [ "",
            "Required preflight commands:",
            "  nvidia-smi -L",
            "  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  or docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L"
          ]
    renderCommandOutcome result = case result of
      Right output -> output
      Left err -> err

waitForKindKubeconfig :: Paths -> RuntimeMode -> IO (Either String String)
waitForKindKubeconfig paths runtimeMode = do
  let addressing
        | Config.controlPlaneContext paths == OuterContainer = Command.InternalAddress
        | otherwise = Command.ExternalAddress
      commandArgs =
        ["get", "kubeconfig", "--name", kindClusterName paths runtimeMode]
          <> ["--internal" | addressing == Command.InternalAddress]
  retryCommandOutput
    30
    1000000
    ("kind " <> unwords commandArgs)
    ( tryClusterCommand
        paths
        ( Command.kindGetKubeconfig
            (Command.ClusterName (kindClusterName paths runtimeMode))
            addressing
        )
    )

waitForKindKubeconfigOrFail :: Paths -> RuntimeMode -> IO String
waitForKindKubeconfigOrFail paths runtimeMode = do
  result <- waitForKindKubeconfig paths runtimeMode
  case result of
    Right kubeconfigContents -> pure kubeconfigContents
    Left err ->
      ioError
        ( userError
            ( "kind get kubeconfig never became ready for "
                <> kindClusterName paths runtimeMode
                <> ":\n"
                <> err
            )
        )

publishGeneratedKubeconfig :: Paths -> Text.Text -> IO ()
publishGeneratedKubeconfig paths kubeconfigContents = do
  removeGeneratedKubeconfigLockFile paths
  writeTextFile (Config.generatedKubeconfigPath paths) kubeconfigContents
  removeGeneratedKubeconfigLockFile paths

generatedKubeconfigLockPath :: Paths -> FilePath
generatedKubeconfigLockPath paths = Config.generatedKubeconfigPath paths <> ".lock"

removeGeneratedKubeconfigLockFile :: Paths -> IO ()
removeGeneratedKubeconfigLockFile = removeFileIfExists . generatedKubeconfigLockPath

removeKubeconfigArtifacts :: FilePath -> IO ()
removeKubeconfigArtifacts kubeconfigFile =
  runCleanupsPreservingFailures
    [ removeFileIfExists kubeconfigFile,
      removeFileIfExists (kubeconfigFile <> ".lock")
    ]

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists filePath = do
  fileExists <- doesFileExist filePath
  when fileExists (removeFile filePath)

withKindScratchKubeconfig :: Paths -> RuntimeMode -> (FilePath -> IO a) -> IO a
withKindScratchKubeconfig paths runtimeMode action = do
  scratchRoot <- getTemporaryDirectory
  let scratchKubeconfig = scratchRoot </> ("infernix-kind-" <> kindClusterName paths runtimeMode <> ".kubeconfig")
  -- Kind and nvkind take file locks while creating or deleting clusters. Keep those transient
  -- locks off repo-visible bind mounts, then publish the durable repo-local kubeconfig ourselves.
  removeGeneratedKubeconfigLockFile paths
  removeKubeconfigArtifacts scratchKubeconfig
  finallyPreservingPrimary
    (action scratchKubeconfig)
    (removeKubeconfigArtifacts scratchKubeconfig)

waitForKubernetesApi :: Paths -> RuntimeMode -> IO ()
waitForKubernetesApi paths runtimeMode = do
  let kubeconfigFile = Config.generatedKubeconfigPath paths
      commandLabel = "kubectl --kubeconfig " <> kubeconfigFile <> " wait --for=condition=Ready node --all"
  result <-
    retryCommandOutputWithDeadline
      (Readiness.pollLimitedDeadline 500000 132 132 24)
      commandLabel
      ( tryClusterCommand
          paths
          ( Command.kubectlWaitAllNodesReady
              (Command.KubeTarget kubeconfigFile)
              5
          )
      )
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        ( userError
            ( "Kubernetes never reported ready nodes for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> ":\n"
                <> err
            )
        )

configureRuntimeModeCluster :: Paths -> RuntimeMode -> IO ()
configureRuntimeModeCluster paths runtimeMode =
  case runtimeMode of
    LinuxGpu -> configureLinuxGpuCluster paths runtimeMode
    _ -> pure ()

configureLinuxGpuCluster :: Paths -> RuntimeMode -> IO ()
configureLinuxGpuCluster paths _runtimeMode = do
  putStrLn "configuring linux-gpu runtime support"
  ensureLinuxGpuRuntimeClass paths
  ensureLinuxGpuNodeUserspace paths
  installLinuxGpuDevicePlugin paths
  waitForLinuxGpuResources paths

ensureLinuxGpuNodeUserspace :: Paths -> IO ()
ensureLinuxGpuNodeUserspace paths = do
  nodeNames <- kindNodeNames paths LinuxGpu
  let workerNodeNames = filter (/= kindControlPlaneNodeName paths LinuxGpu) nodeNames
  mapM_ ensureWorkerUserspace workerNodeNames
  where
    ensureWorkerUserspace nodeName = do
      userspaceReady <- linuxGpuNodeUserspaceReady nodeName
      unless userspaceReady $ do
        putStrLn ("syncing linux-gpu NVIDIA userspace into " <> nodeName)
        syncLinuxGpuNodeUserspace paths nodeName
        userspaceReadyAfterSync <- linuxGpuNodeUserspaceReady nodeName
        unless userspaceReadyAfterSync $
          ioError
            ( userError
                ( "linux-gpu worker never exposed usable NVIDIA userspace after repo-owned sync: "
                    <> nodeName
                )
            )

linuxGpuNodeUserspaceReady :: String -> IO Bool
linuxGpuNodeUserspaceReady nodeName =
  commandSucceeded
    <$> tryDiscoveredClusterCommand
      ( \_ ->
          Command.dockerProbeGpuUserspace (Command.NodeName nodeName)
      )

syncLinuxGpuNodeUserspace :: Paths -> String -> IO ()
syncLinuxGpuNodeUserspace paths nodeName =
  runClusterCommand
    paths
    (Command.dockerSyncGpuUserspace (Command.NodeName nodeName))

ensureLinuxGpuRuntimeClass :: Paths -> IO ()
ensureLinuxGpuRuntimeClass paths =
  runClusterCommand
    paths
    (Command.kubectlApplyNvidiaRuntimeClass (generatedKubeTarget paths))

installLinuxGpuDevicePlugin :: Paths -> IO ()
installLinuxGpuDevicePlugin paths = do
  ensureHelmRepositoryDefinitions paths
  runClusterCommand
    paths
    ( Command.helmUpgradeNvidiaPlugin
        (generatedKubeTarget paths)
        nvidiaDevicePluginVersion
    )

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel under the exact legacy 30-attempt × 1 s budget. Readiness is
-- now the kernel's positive outcome from a real allocatable-resource observation
-- rather than a bare-recursion fall-through.
waitForLinuxGpuResources :: Paths -> IO ()
waitForLinuxGpuResources paths = do
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 30 1000000) probe
  Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
  where
    probe = do
      allocatableValues <- linuxGpuAllocatableValues paths
      if any isPositiveGpuCount allocatableValues
        then pure (Right ())
        else pure (Left (Readiness.Progress 0 1 "no node reported allocatable nvidia.com/gpu"))
    onTimedOut _ =
      ioError (userError "linux-gpu nodes never reported allocatable nvidia.com/gpu resources")
    isPositiveGpuCount value =
      case readMaybe value of
        Just parsedCount -> parsedCount > (0 :: Int)
        Nothing -> False

linuxGpuAllocatableValues :: Paths -> IO [String]
linuxGpuAllocatableValues paths =
  filter (not . null) . map trim . lines
    <$> captureClusterCommand
      paths
      (Command.kubectlGetGpuAllocatable (generatedKubeTarget paths))

applyBootstrapState :: Paths -> RuntimeMode -> Bool -> [PersistentClaim] -> IO ()
applyBootstrapState paths runtimeMode demoUiEnabledValue claimInventory = do
  now <- getCurrentTime
  let state =
        ClusterState
          { clusterLifecycle = ClusterReady,
            -- Transient state used only to apply namespace/storage; never
            -- persisted as the authoritative owner record.
            clusterOwner = OperatorOwned,
            edgePort = 0,
            registryPort = 0,
            routes = routeInventory demoUiEnabledValue,
            storageClass = "infernix-manual",
            claims = claimInventory,
            clusterRuntimeMode = runtimeMode,
            -- Namespace and storage-class application is fleet independent, so
            -- this transient state names no machines rather than restating a
            -- list nothing here reads.
            clusterEngineMemberIds = [],
            kubeconfigPath = Config.generatedKubeconfigPath paths,
            generatedDemoConfigPath = Config.generatedDemoConfigPath paths,
            publishedDemoConfigPath = Config.publishedConfigMapCatalogPath paths,
            publishedConfigMapManifestPath = Config.publishedConfigMapManifestPath paths,
            mountedDemoConfigPath = Config.watchedDemoConfigPath,
            updatedAt = now
          }
  applyNamespace state "platform"
  resetStorageClasses paths state
  applyStorageClass state

applyNamespace :: ClusterState -> String -> IO ()
applyNamespace state namespaceName =
  runDiscoveredClusterCommand
    ( \_ ->
        Command.kubectlApplyNamespace
          (clusterKubeTarget state)
          (Command.Namespace namespaceName)
    )

resetStorageClasses :: Paths -> ClusterState -> IO ()
resetStorageClasses paths state = do
  existingClasses <-
    lines
      <$> kubectlOutput
        state
        Command.kubectlListStorageClasses
  mapM_
    ( runClusterCommand paths
        . Command.kubectlDeleteStorageClass (clusterKubeTarget state)
        . Command.ResourceName
    )
    existingClasses

applyStorageClass :: ClusterState -> IO ()
applyStorageClass state =
  runDiscoveredClusterCommand
    ( \_ ->
        Command.kubectlApplyInfernixStorageClass
          (clusterKubeTarget state)
    )

buildClusterImages :: Paths -> ClusterState -> RuntimeMode -> IO ()
buildClusterImages paths state runtimeMode = do
  targetArchitecture <- resolveClusterWorkloadArchitecture paths runtimeMode
  let workloadRuntimeMode = clusterWorkloadRuntimeMode runtimeMode
      runtimeModeName = Text.unpack (runtimeModeId workloadRuntimeMode)
      imageRef = clusterWorkloadImageRef runtimeMode
      goImage = "golang:1.24"
      baseImage =
        case workloadRuntimeMode of
          LinuxGpu -> "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
          _ -> "ubuntu:24.04"
      engineBaseImage = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
      buildInputs =
        ClusterImageBuildInputs
          { clusterImageBuildRuntimeMode = workloadRuntimeMode,
            clusterImageBuildGoImage = goImage,
            clusterImageBuildBaseImage = baseImage,
            clusterImageBuildTargetArchitecture = targetArchitecture,
            clusterImageBuildDemoUi = True
          }
  sourceFingerprint <- clusterImageSourceFingerprint paths buildInputs
  imageReusable <- clusterWorkloadImageReusableForBuild paths imageRef runtimeModeName targetArchitecture sourceFingerprint
  if imageReusable
    then putStrLn ("reusing cluster image for " <> runtimeModeName <> ": " <> imageRef)
    else do
      putStrLn ("building cluster images for " <> runtimeModeName)
      ensureDockerBuildBaseImage paths state goImage
      ensureDockerBuildBaseImage paths state baseImage
      runClusterCommand
        paths
        ( Command.dockerBuildControlPlane
            Command.ControlPlaneBuildSpec
              { Command.controlPlaneTargetImage = Command.ImageRef imageRef,
                Command.controlPlaneSourceFingerprint = sourceFingerprint,
                Command.controlPlaneRuntimeMode = runtimeModeName,
                Command.controlPlaneGoImage = Command.ImageRef goImage,
                Command.controlPlaneBaseImage = Command.ImageRef baseImage
              }
        )
  buildPerEngineImages
    imageRef
    baseImage
    engineBaseImage
    runtimeModeName
    targetArchitecture
    sourceFingerprint
  where
    buildPerEngineImages
      controlPlaneImageRef
      controlPlaneBaseImage
      engineBaseImage
      runtimeModeName
      targetArchitecture
      sourceFingerprint =
        case runtimeMode of
          LinuxGpu ->
            forM_ (perEngineDeploymentNames runtimeMode) $ \engineName -> do
              let engineImageRef = Text.unpack (perEngineImageName runtimeMode engineName)
              engineImageReusable <-
                dockerImageReusableWithSourceFingerprint
                  engineImageRef
                  runtimeModeName
                  targetArchitecture
                  sourceFingerprint
              if engineImageReusable
                then putStrLn ("reusing per-engine image for " <> Text.unpack engineName <> ": " <> engineImageRef)
                else do
                  ensureDockerBuildBaseImage paths state controlPlaneBaseImage
                  ensureDockerBuildBaseImage paths state engineBaseImage
                  runClusterCommand
                    paths
                    ( Command.dockerBuildEngine
                        Command.EngineBuildSpec
                          { Command.engineTargetImage = Command.ImageRef engineImageRef,
                            Command.engineSourceFingerprint = sourceFingerprint,
                            Command.engineRuntimeMode = runtimeModeName,
                            Command.engineKind = Command.EngineName (Text.unpack engineName),
                            Command.engineControlPlaneImage = Command.ImageRef controlPlaneImageRef,
                            Command.engineBaseImage = Command.ImageRef engineBaseImage
                          }
                    )
          _ -> pure ()

clusterWorkloadImageReusableForBuild :: Paths -> String -> String -> String -> String -> IO Bool
clusterWorkloadImageReusableForBuild paths imageRef runtimeModeName targetArchitecture sourceFingerprint =
  case Config.controlPlaneContext paths of
    OuterContainer -> dockerImageReusableForRegistryPush imageRef
    HostNative ->
      dockerImageReusableForHostBuild imageRef runtimeModeName targetArchitecture sourceFingerprint

dockerImageReusableForHostBuild :: String -> String -> String -> String -> IO Bool
dockerImageReusableForHostBuild =
  dockerImageReusableWithSourceFingerprint

dockerImageReusableWithSourceFingerprint :: String -> String -> String -> String -> IO Bool
dockerImageReusableWithSourceFingerprint imageRef runtimeModeName targetArchitecture sourceFingerprint = do
  pushReusable <- dockerImageReusableForRegistryPush imageRef
  architectureMatches <- dockerImageInspectFieldEquals imageRef Command.ImageArchitecture targetArchitecture
  fingerprintVersionMatches <-
    dockerImageInspectFieldEquals
      imageRef
      Command.ClusterFingerprintVersion
      clusterImageFingerprintVersion
  runtimeModeMatches <-
    dockerImageInspectFieldEquals imageRef Command.ClusterRuntimeMode runtimeModeName
  fingerprintMatches <-
    dockerImageInspectFieldEquals imageRef Command.ClusterSourceFingerprint sourceFingerprint
  pure
    ( pushReusable
        && architectureMatches
        && fingerprintVersionMatches
        && runtimeModeMatches
        && fingerprintMatches
    )

-- Docker 29 + BuildKit may leave local repo-owned images as OCI indexes
-- with provenance attestations. Registry publication is still Docker-push
-- based for repo-owned images, and those indexed local images have produced
-- intermittent "blob ... not found" failures against the MinIO-backed
-- registry. Images rebuilt with --provenance=false inspect as plain image
-- manifests; older Docker releases may omit Descriptor and are accepted after
-- the normal inspect succeeds.
dockerImageReusableForRegistryPush :: String -> IO Bool
dockerImageReusableForRegistryPush imageRef = do
  inspectResult <-
    tryDiscoveredClusterCommand $ \_ ->
      Command.dockerInspectImageField
        (Command.ImageRef imageRef)
        Command.DescriptorMediaType
  case inspectResult of
    Left _ -> pure False
    Right descriptor
      | "image.index" `List.isInfixOf` descriptor -> pure False
      | "manifest.list" `List.isInfixOf` descriptor -> pure False
      | otherwise -> pure True

dockerImageInspectFieldEquals ::
  String ->
  Command.ImageInspectField ->
  String ->
  IO Bool
dockerImageInspectFieldEquals imageRef inspectField expectedValue = do
  inspectResult <-
    tryDiscoveredClusterCommand $ \_ ->
      Command.dockerInspectImageField
        (Command.ImageRef imageRef)
        inspectField
  pure $
    case inspectResult of
      Left _ -> False
      Right rawValue ->
        let actualValue = trim rawValue
         in actualValue == expectedValue

ensureDockerBuildBaseImage :: Paths -> ClusterState -> String -> IO ()
ensureDockerBuildBaseImage paths state imageRef = do
  imagePresent <- dockerImagePresent imageRef
  unless imagePresent $
    case dockerHubMirrorRef imageRef of
      Nothing -> pure ()
      Just mirrorRef -> do
        _ <-
          startLifecyclePhase
            paths
            state
            "cluster-up"
            "build-cluster-images"
            ("pulling Docker build base image " <> imageRef <> " via " <> mirrorRef)
        runClusterCommand
          paths
          (Command.dockerPullImage Command.DefaultPlatform (Command.ImageRef mirrorRef))
        runClusterCommand
          paths
          (Command.dockerTagImage (Command.ImageRef mirrorRef) (Command.ImageRef imageRef))
        requireDockerImagePresent imageRef ("mirror pull completed for " <> mirrorRef <> ", but " <> imageRef <> " is still not inspectable locally after tagging")

requireDockerImagePresent :: String -> String -> IO ()
requireDockerImagePresent imageRef message = do
  imagePresent <- dockerImagePresent imageRef
  unless imagePresent (ioError (userError message))

dockerHubMirrorRef :: String -> Maybe String
dockerHubMirrorRef imageRef =
  ("mirror.gcr.io/" <>) <$> normalizedDockerHubPath imageRef
  where
    normalizedDockerHubPath rawImage =
      case stripRegistryPrefix rawImage of
        Just pathValue -> Just (ensureLibraryPrefix pathValue)
        Nothing ->
          if usesImplicitDockerHub rawImage
            then Just (ensureLibraryPrefix rawImage)
            else Nothing

    stripRegistryPrefix rawImage =
      case break (== '/') rawImage of
        ("docker.io", '/' : pathValue) -> Just pathValue
        _ -> Nothing

    usesImplicitDockerHub rawImage =
      case break (== '/') rawImage of
        (_, []) -> True
        (registryOrNamespace, _ : _) -> not (hasExplicitRegistryComponent registryOrNamespace)

    hasExplicitRegistryComponent component =
      '.' `elem` component || ':' `elem` component || component == "localhost"

    ensureLibraryPrefix pathValue =
      case break (== '/') pathValue of
        (_, []) -> "library/" <> pathValue
        _ -> pathValue

publishClusterImages :: Paths -> ClusterState -> FilePath -> RuntimeMode -> IO FilePath
publishClusterImages paths state renderedChartPath runtimeMode = do
  targetArchitecture <- resolveClusterWorkloadArchitecture paths runtimeMode
  let outputPath =
        buildRoot paths
          </> ("registry-image-overrides-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
      hostRegistryAddress = "localhost:" <> show (registryPort state)
  PublishImages.publishChartImagesFile
    PublishImages.defaultRegistryPublishOptions
      { PublishImages.registryHost = hostRegistryAddress,
        PublishImages.registryClientHost = hostRegistryAddress,
        PublishImages.registryApiHost = registryApiHost paths runtimeMode (registryPort state),
        PublishImages.registryTargetArchitecture = targetArchitecture
      }
    ( \detail -> do
        -- Sprint 3.15: record the publish sub-phase for progress. The former
        -- ProcessMonitor heartbeat is retired here; liveness is now the
        -- bounded 'Subprocess.Timeout' on each publish command, not a
        -- heartbeat that could mask a hung pull.
        _ <- startLifecyclePhase paths state "cluster-up" "publish-registry-images" detail
        pure ()
    )
    renderedChartPath
    outputPath
  pure outputPath

preloadHostCachedWarmupImagesOnKindWorker :: Paths -> ClusterState -> RuntimeMode -> IO ()
preloadHostCachedWarmupImagesOnKindWorker paths state runtimeMode = do
  workerContainers <- kindWorkerNodeNames paths runtimeMode
  forM_ workerContainers $ \workerContainer ->
    mapM_ (preloadHostCachedWarmupImage paths state workerContainer) hostCachedWarmupImageRefs

-- | Phase 3 Sprint 3.11 (2026-05-29): the warmup-preload list tracks
-- the multi-arch upstream image inventory after the `bitnamilegacy/*`
-- retirement. The MinIO server image is `minio/minio` (multi-arch); the
-- volume-permissions init container uses `busybox` (multi-arch); the
-- separate `minio-object-browser` Deployment was removed when
-- `console.enabled` flipped to `false` in `chart/values.yaml`.
hostCachedWarmupImageRefs :: [String]
hostCachedWarmupImageRefs =
  [ "docker.io/apachepulsar/pulsar-all:4.0.9",
    "docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z",
    "docker.io/minio/mc:RELEASE.2025-08-13T08-35-41Z",
    "docker.io/busybox:1.36",
    "docker.io/envoyproxy/gateway:v1.7.2",
    "docker.io/percona/percona-distribution-postgresql:18.3-1",
    "docker.io/percona/percona-pgbackrest:2.58.0-1",
    "docker.io/percona/percona-pgbouncer:1.25.1-1",
    "docker.io/percona/percona-postgresql-operator:2.9.0",
    "quay.io/keycloak/keycloak:26.0.7"
  ]

preloadHostCachedWarmupImage :: Paths -> ClusterState -> String -> String -> IO ()
preloadHostCachedWarmupImage paths state workerContainer imageRef = do
  imagePresent <- ensureHostWarmupImageCached paths state imageRef
  when imagePresent $ do
    preloadState <-
      startLifecyclePhase
        paths
        state
        "cluster-up"
        "preload-bootstrap-images"
        ("preloading host-cached warmup image " <> imageRef <> " on " <> workerContainer)
    result <-
      ( try
          (streamImportImageOnNode paths preloadState workerContainer imageRef) ::
          IO (Either IOException ())
      )
    case result of
      Right _ -> pure ()
      Left err -> do
        putStrLn
          ( "warmup image preload skipped after failure for "
              <> imageRef
              <> ": "
              <> displayException err
          )

ensureHostWarmupImageCached :: Paths -> ClusterState -> String -> IO Bool
ensureHostWarmupImageCached paths state imageRef = do
  imagePresent <- dockerImagePresent imageRef
  if imagePresent
    then pure True
    else hydrateMissingHostWarmupImage paths state imageRef

hydrateMissingHostWarmupImage :: Paths -> ClusterState -> String -> IO Bool
hydrateMissingHostWarmupImage paths state imageRef =
  case dockerHubMirrorRef imageRef of
    Nothing -> pure False
    Just mirrorRef -> do
      _ <-
        startLifecyclePhase
          paths
          state
          "cluster-up"
          "preload-bootstrap-images"
          ("hydrating warmup image " <> imageRef <> " via " <> mirrorRef)
      -- Phase 3 Sprint 3.11 (2026-05-29): the @--platform@ pin is
      -- derived from the active substrate so Apple Silicon hydrates
      -- arm64 base images natively. The hardcoded @linux/amd64@ this
      -- replaced was the Docker 29.x mirror fallback added when only
      -- amd64 substrates were supported.
      targetArchitecture <- resolveClusterWorkloadArchitecture paths (clusterRuntimeMode state)
      hydrateResult <-
        ( try
            ( do
                runClusterCommand
                  paths
                  ( Command.dockerPullImage
                      (Command.LinuxPlatform (Command.Architecture targetArchitecture))
                      (Command.ImageRef mirrorRef)
                  )
                runClusterCommand
                  paths
                  ( Command.dockerTagImage
                      (Command.ImageRef mirrorRef)
                      (Command.ImageRef imageRef)
                  )
                requireDockerImagePresent imageRef ("mirror pull completed for " <> mirrorRef <> ", but " <> imageRef <> " is still not inspectable locally after tagging")
            ) ::
            IO (Either IOException ())
        )
      case hydrateResult of
        Right _ -> pure True
        Left err -> do
          putStrLn
            ( "warmup image mirror hydration skipped after failure for "
                <> imageRef
                <> " via "
                <> mirrorRef
                <> ": "
                <> displayException err
            )
          pure False

preloadRegistryBackedImagesOnKindWorker :: Paths -> ClusterState -> RuntimeMode -> FilePath -> IO ()
preloadRegistryBackedImagesOnKindWorker paths state runtimeMode imageOverridesPath = do
  imageRefs <- registryOverlayImageRefs paths imageOverridesPath
  workerContainers <- kindWorkerNodeNames paths runtimeMode
  let uniqueImageRefs = List.nub (filter shouldPreloadOnWorker (map trim imageRefs))
  unless (null uniqueImageRefs) $ do
    putStrLn "preloading registry-backed final images on the Kind workers"
    forM_ workerContainers $ \workerContainer ->
      mapM_
        ( \imageRef -> do
            imageState <-
              startLifecyclePhase
                paths
                state
                "cluster-up"
                "preload-registry-images"
                ("preloading registry-backed image " <> imageRef <> " on " <> workerContainer)
            preloadRegistryImageOnNode paths imageState workerContainer imageRef
        )
        uniqueImageRefs
  where
    shouldPreloadOnWorker imageRef = not (null imageRef)

registryOverlayImageRefs :: Paths -> FilePath -> IO [String]
registryOverlayImageRefs _paths imageOverridesPath =
  filter (not . null) <$> discoverRegistryOverlayImageRefsFile imageOverridesPath

preloadRegistryImageOnNode :: Paths -> ClusterState -> String -> String -> IO ()
preloadRegistryImageOnNode paths state nodeContainer imageRef = do
  result <-
    tryClusterCommand
      paths
      ( Command.dockerCrictlPull
          (Command.NodeName nodeContainer)
          (Command.ImageRef imageRef)
      )
  case result of
    Right _ -> pure ()
    Left pullFailure -> do
      putStrLn
        ( "Anonymous registry-backed crictl preload failed for "
            <> imageRef
            <> " on "
            <> nodeContainer
            <> "; falling back to the host's protected Docker login and stream import"
        )
      fallbackState <-
        startLifecyclePhase
          paths
          state
          "cluster-up"
          "preload-registry-images"
          ("stream-importing registry-backed image " <> imageRef <> " on " <> nodeContainer)
      fallbackResult <-
        (try (streamImportImageOnNode paths fallbackState nodeContainer imageRef) :: IO (Either IOException ()))
      case fallbackResult of
        Right _ -> pure ()
        Left fallbackErr ->
          ioError
            ( userError
                ( "Kind worker could not preload registry-backed image "
                    <> imageRef
                    <> ":\ncrictl pull failure:\n"
                    <> pullFailure
                    <> "\nstream-import fallback failure:\n"
                    <> displayException fallbackErr
                )
            )

streamImportImageOnNode :: Paths -> ClusterState -> String -> String -> IO ()
streamImportImageOnNode paths _state nodeContainer imageRef =
  runClusterCommand
    paths
    ( Command.dockerStreamImportImage
        (Command.NodeName nodeContainer)
        (Command.ImageRef imageRef)
    )

dockerImagePresent :: String -> IO Bool
dockerImagePresent imageRef =
  commandSucceeded
    <$> tryDiscoveredClusterCommand
      ( \_ ->
          Command.dockerInspectImage (Command.ImageRef imageRef)
      )

-- | Phase 3 Sprint 3.17: the registry's @\/v2\/@ API answered.
--
-- This is a /liveness/ probe and nothing more. @registry:2@ serves @\/v2\/@
-- straight out of its own process without reading a byte from S3, so a 200 here
-- says the registry is up and says nothing at all about whether any blob is
-- retrievable. It may gate whether to keep waiting; it may never stand in for
-- publication evidence. That remains the @BlobServable@ witness minted by a real
-- bounded registry-only @skopeo copy@ in "Infernix.Cluster.PublishImages".
waitForRegistryEndpointResult :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO (Either String String)
waitForRegistryEndpointResult paths runtimeMode registryPortValue attempts delayMicros = do
  let registryApiUrl = "http://" <> registryApiHost paths runtimeMode registryPortValue <> "/v2/"
      probeCommand = do
        response <-
          tryClusterCommand
            paths
            (Command.curlRegistryApi (Command.Url registryApiUrl))
        pure $
          response >>= \payload ->
            case parseCurlBodyAndStatus payload of
              Just (_, statusCode)
                | statusCode `elem` ["200", "401", "403"] -> Right "ready"
              Just (_, statusCode) ->
                Left ("unexpected registry status " <> statusCode)
              Nothing ->
                Left "failed to parse registry probe output"
  if attempts <= 1
    then retryCommandOutput attempts delayMicros "wait for the in-cluster registry" probeCommand
    else
      let delaySeconds = max 1 ((delayMicros + 999999) `div` 1000000)
          totalSeconds = attempts * (30 + delaySeconds)
       in retryCommandOutputWithDeadline
            ( Readiness.pollLimitedDeadline
                delayMicros
                totalSeconds
                totalSeconds
                attempts
            )
            "wait for the in-cluster registry"
            probeCommand

-- | Phase 3 Sprint 3.17: bring the in-cluster registry up.
--
-- This replaces a three-attempt retry loop that existed for one reason: the
-- component this supersedes ran a first-boot schema migration against its own
-- PostgreSQL database, that migration could leave the schema marked dirty, and
-- a dirty schema wedged every later attempt until the migration job was deleted
-- and the schema was dropped and recreated. Detecting that state, repairing it,
-- and retrying around it was the bulk of this module's registry code.
--
-- @registry:2@ runs no migration because it has no database, so the failure
-- mode is gone rather than handled: deploy the bootstrap values, wait for the
-- endpoint, and fail with what the wait observed.
bootstrapRegistry :: Paths -> ClusterState -> [FilePath] -> IO ()
bootstrapRegistry paths state valuesPaths = do
  deployResult <- tryDeployChartWithTimeout paths state valuesPaths False registryBootstrapHelmTimeout
  case deployResult of
    Right _ -> awaitBootstrapRegistryReady
    Left err ->
      ioError
        (userError ("the registry bootstrap Helm reconcile failed:\n" <> err))
  where
    awaitBootstrapRegistryReady = do
      outcome <- Readiness.awaitReadiness registryReadinessDeadline probeRegistry
      Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
    probeRegistry = do
      registryResult <-
        waitForRegistryEndpointResult paths (clusterRuntimeMode state) (registryPort state) 1 0
      pure $ case registryResult of
        Right _ -> Right ()
        Left err -> Left (Readiness.Progress 0 1 (Text.pack err))
    onTimedOut progress =
      ioError
        ( userError
            ( "the in-cluster registry never became ready during bootstrap:\n"
                <> Text.unpack (Readiness.progressDetail progress)
            )
        )

-- | Sprint 3.14: the required deadline for the registry readiness wait,
-- preserving the previous 24-attempt × 5s (~120s) budget as an explicit,
-- data-carried bound instead of a bare recursion counter.
registryReadinessDeadline :: Readiness.Deadline
registryReadinessDeadline =
  Readiness.Deadline
    { Readiness.deadlinePollMicros = 5000000,
      Readiness.deadlineStallSeconds = 120,
      Readiness.deadlineCeilingSeconds = 120
    }

-- | Phase 3 Sprint 3.17: wait for the one remaining Patroni cluster to be
-- serving.
--
-- Retained from the retired registry database's readiness path and re-pointed
-- at @keycloak-postgresql@. What is /not/ retained is the schema-migration
-- repair that used to run alongside it: that was specific to the schema the
-- registry component owned, and no such schema exists now.
waitForPatroniDatabaseReady :: ClusterState -> IO ()
waitForPatroniDatabaseReady state = do
  waitForWorkloadRollout state 900 postgresOperatorDeployment
  waitForPatroniPostgresPodsReady state
  waitForWorkloadRollout state 900 ("deployment/" <> patroniPostgresClusterName <> "-pgbouncer")
  primaryPodName <- waitForPatroniPostgresPrimaryPod state
  runDiscoveredClusterCommand
    ( \_ ->
        Command.kubectlWaitPodReady
          (clusterKubeTarget state)
          (Command.Namespace "platform")
          (Command.PodName primaryPodName)
          60
    )

waitForPatroniPostgresPodsReady :: ClusterState -> IO ()
waitForPatroniPostgresPodsReady state = do
  restartIssuedRef <- newIORef False
  attemptRef <- newIORef (0 :: Int)
  lastErrorRef <- newIORef ""
  let totalAttempts = 72 :: Int
      probe = do
        attemptsElapsed <- readIORef attemptRef
        modifyIORef' attemptRef (+ 1)
        startupPods <- patroniPostgresStartupPods state
        let dataPodCount =
              length
                [ ()
                | startupPod <- startupPods,
                  "keycloak-postgresql-instance" `List.isPrefixOf` patroniPostgresStartupPodName startupPod
                ]
            repoHostCount =
              length
                [ ()
                | startupPod <- startupPods,
                  "keycloak-postgresql-repo-host-" `List.isPrefixOf` patroniPostgresStartupPodName startupPod
                ]
            allStartupPodsPresent =
              dataPodCount >= patroniPostgresExpectedDataClaims
                && repoHostCount >= 1
            currentError
              | dataPodCount < patroniPostgresExpectedDataClaims =
                  "expected "
                    <> show patroniPostgresExpectedDataClaims
                    <> " Patroni PostgreSQL data pods but found "
                    <> show dataPodCount
              | repoHostCount < 1 = "expected Patroni PostgreSQL pgBackRest repo host pod but found none"
              | all patroniPostgresStartupPodReady startupPods = ""
              | otherwise =
                  "Patroni PostgreSQL startup pods are not ready: "
                    <> List.intercalate
                      ", "
                      [ patroniPostgresStartupPodName startupPod
                          <> " ["
                          <> patroniPostgresStartupPodStatus startupPod
                          <> "]"
                      | startupPod <- startupPods,
                        not (patroniPostgresStartupPodReady startupPod)
                      ]
        case currentError of
          "" -> pure (Right ())
          _ -> do
            -- Match the original's "no repair on the final attempt": it checks its
            -- @remainingAttempts <= 1@ give-up guard BEFORE the repair branch, so the
            -- last poll (which will Expire) must not issue the destructive startup
            -- restart right as the wait gives up.
            when (attemptsElapsed < totalAttempts - 1) $ do
              restartIssued <- readIORef restartIssuedRef
              restarted <-
                if restartIssued
                  then pure False
                  else
                    restartPatroniPostgresStartupPodsIfStuck
                      state
                      allStartupPodsPresent
                      attemptsElapsed
                      startupPods
              when restarted (writeIORef restartIssuedRef True)
            retained <-
              atomicModifyIORef'
                lastErrorRef
                (\previous -> let kept = if null currentError then previous else currentError in (kept, kept))
            pure (Left (Readiness.Progress 0 1 (Text.pack retained)))
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline totalAttempts 5000000) probe
  Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
  where
    onTimedOut progress =
      ioError
        ( userError
            ( "Patroni PostgreSQL pods never became ready:\n"
                <> Text.unpack (Readiness.progressDetail progress)
            )
        )

data PatroniPostgresStartupPod = PatroniPostgresStartupPod
  { patroniPostgresStartupPodName :: String,
    patroniPostgresStartupPodReady :: Bool,
    patroniPostgresStartupPodStatus :: String
  }

patroniPostgresStartupPods :: ClusterState -> IO [PatroniPostgresStartupPod]
patroniPostgresStartupPods state =
  mapMaybe parseStartupPodLine . lines
    <$> kubectlOutput
      state
      (`Command.kubectlListPods` Command.PatroniPostgresStartupPods)
  where
    parseStartupPodLine lineValue =
      case words lineValue of
        podNameValue : readyValue : statusValue : _
          | isPatroniPostgresStartupPodName podNameValue ->
              Just
                PatroniPostgresStartupPod
                  { patroniPostgresStartupPodName = podNameValue,
                    patroniPostgresStartupPodReady = readyColumnSatisfied readyValue,
                    patroniPostgresStartupPodStatus = statusValue
                  }
        _ -> Nothing

    isPatroniPostgresStartupPodName podNameValue =
      "keycloak-postgresql-instance" `List.isPrefixOf` podNameValue
        || "keycloak-postgresql-repo-host-" `List.isPrefixOf` podNameValue

    readyColumnSatisfied readyValue =
      case break (== '/') readyValue of
        (readyCountText, '/' : totalCountText) ->
          case (readMaybe readyCountText :: Maybe Int, readMaybe totalCountText :: Maybe Int) of
            (Just readyCount, Just totalCount) -> totalCount > 0 && readyCount == totalCount
            _ -> False
        _ -> False

restartPatroniPostgresStartupPodsIfStuck :: ClusterState -> Bool -> Int -> [PatroniPostgresStartupPod] -> IO Bool
restartPatroniPostgresStartupPodsIfStuck state _allStartupPodsPresent attemptsElapsed startupPods =
  case NonEmpty.nonEmpty (map Command.PodName unreadyPodNames) of
    Just podNames
      | shouldRestart -> do
          runDiscoveredClusterCommand
            ( \_ ->
                Command.kubectlDeletePods
                  (clusterKubeTarget state)
                  (Command.Namespace "platform")
                  podNames
            )
          pure True
    _ -> pure False
  where
    unreadyPodNames =
      [ patroniPostgresStartupPodName startupPod
      | startupPod <- startupPods,
        not (patroniPostgresStartupPodReady startupPod)
      ]
    shouldRestart =
      not (null unreadyPodNames)
        && ( any podLooksStuck startupPods
               || attemptsElapsed >= patroniPostgresStartupRepairGraceAttempts
           )
    podLooksStuck startupPod =
      not (patroniPostgresStartupPodReady startupPod)
        && ( "CrashLoopBackOff" `List.isInfixOf` patroniPostgresStartupPodStatus startupPod
               || patroniPostgresStartupPodStatus startupPod == "Error"
               || patroniPostgresStartupPodStatus startupPod == "Init:Error"
           )

-- | Sprint 6.41: migrated onto the shared 'Readiness' kernel under the legacy
-- 72-attempt × 5 s budget. The resolved primary pod name is the kernel's readiness
-- evidence, minted only from a real non-empty pod observation.
waitForPatroniPostgresPrimaryPod :: ClusterState -> IO String
waitForPatroniPostgresPrimaryPod state = do
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 72 5000000) probe
  Readiness.foldReadiness pure onTimedOut onTimedOut outcome
  where
    probe = do
      podName <- patroniPostgresPrimaryPodNameMaybe state
      if null podName
        then pure (Left (Readiness.Progress 0 1 "Patroni PostgreSQL primary pod not yet present"))
        else pure (Right podName)
    onTimedOut _ =
      ioError (userError "Patroni PostgreSQL primary pod never appeared")

patroniPostgresPrimaryPodNameMaybe :: ClusterState -> IO String
patroniPostgresPrimaryPodNameMaybe state = do
  podNames <-
    filter (not . null) . map trim . lines
      <$> kubectlOutput
        state
        (`Command.kubectlListPods` Command.PatroniPostgresPrimary)
  pure (firstOrEmpty podNames)

firstOrEmpty :: [String] -> String
firstOrEmpty values =
  case values of
    firstValue : _ -> firstValue
    [] -> ""

deployChart :: Paths -> ClusterState -> [FilePath] -> Bool -> IO ()
deployChart paths state valuesPaths waitForRollout = do
  result <- tryDeployChart paths state valuesPaths waitForRollout
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("command failed: helm upgrade --install infernix chart\n" <> err))

deployChartSkippingHooks :: Paths -> ClusterState -> [FilePath] -> Bool -> IO ()
deployChartSkippingHooks paths state valuesPaths waitForRollout = do
  result <- tryDeployChartWithHooks paths state valuesPaths waitForRollout False
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("command failed: helm upgrade --install infernix chart --no-hooks\n" <> err))

tryDeployChart :: Paths -> ClusterState -> [FilePath] -> Bool -> IO (Either String String)
tryDeployChart paths state valuesPaths waitForRollout =
  tryDeployChartWithHooks paths state valuesPaths waitForRollout True

tryDeployChartWithHooks :: Paths -> ClusterState -> [FilePath] -> Bool -> Bool -> IO (Either String String)
tryDeployChartWithHooks paths state valuesPaths waitForRollout =
  tryDeployChartWithTimeoutAndHooks paths state valuesPaths waitForRollout (Command.HelmMinutes 30)

tryDeployChartWithTimeout :: Paths -> ClusterState -> [FilePath] -> Bool -> Command.HelmDuration -> IO (Either String String)
tryDeployChartWithTimeout paths state valuesPaths waitForRollout timeoutValue =
  tryDeployChartWithTimeoutAndHooks paths state valuesPaths waitForRollout timeoutValue True

tryDeployChartWithTimeoutAndHooks :: Paths -> ClusterState -> [FilePath] -> Bool -> Command.HelmDuration -> Bool -> IO (Either String String)
tryDeployChartWithTimeoutAndHooks paths state valuesPaths waitForRollout timeoutValue runHooks = do
  ensureHelmDependencies paths
  tryClusterCommand
    paths
    ( Command.helmUpgradeInfernix
        Command.HelmUpgradeSpec
          { Command.helmUpgradeTarget = clusterKubeTarget state,
            Command.helmUpgradeValues = valuesPaths,
            Command.helmUpgradeWait = waitForRollout,
            Command.helmUpgradeHooks = runHooks,
            Command.helmUpgradeTimeout = timeoutValue
          }
    )

waitForRegistryFinalPhaseRollouts :: ClusterState -> IO ()
waitForRegistryFinalPhaseRollouts state = do
  putStrLn "waiting for final registry rollouts"
  mapM_ (waitForWorkloadRollout state 1200) registryFinalPhaseStatefulSets
  mapM_ (waitForWorkloadRollout state 900) registryFinalPhaseDeployments

waitForGatewayApiCrds :: ClusterState -> IO ()
waitForGatewayApiCrds state =
  mapM_
    (waitForGatewayApiCrd state)
    [ "gatewayclasses.gateway.networking.k8s.io",
      "gateways.gateway.networking.k8s.io",
      "httproutes.gateway.networking.k8s.io",
      "referencegrants.gateway.networking.k8s.io"
    ]

waitForGatewayApiCrd :: ClusterState -> String -> IO ()
waitForGatewayApiCrd state crdName = do
  result <-
    retryCommandOutput
      60
      1000000
      ("wait for Gateway API CRD " <> crdName)
      ( tryDiscoveredClusterCommand
          ( \_ ->
              Command.kubectlGetCrd
                (clusterKubeTarget state)
                (Command.ResourceName crdName)
          )
      )
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("Gateway API CRD never became ready: " <> crdName <> "\n" <> err))

waitForFinalPhaseRollouts :: Paths -> ClusterState -> IO ()
waitForFinalPhaseRollouts paths state = do
  putStrLn "waiting for final platform rollouts"
  mapM_ (waitForFinalPhaseStatefulSetRollout paths state 1200) finalPhaseStatefulSets
  mapM_ (waitForWorkloadRollout state 900) (finalPhaseDeployments state)
  -- Phase 3 Sprint 3.17: the only Patroni cluster left belongs to Keycloak,
  -- which is demo-gated, so a production `demo_ui = false` deploy has no
  -- database to wait for.
  when (clusterStateHasDemoUi state) (waitForPatroniDatabaseReady state)

waitForPulsarReadyPhaseRollouts :: Paths -> ClusterState -> IO ()
waitForPulsarReadyPhaseRollouts paths state = do
  putStrLn "waiting for staged Pulsar rollouts"
  mapM_ (waitForFinalPhaseStatefulSetRollout paths state 1200) pulsarReadyPhaseStatefulSets
  when (clusterStateHasDemoUi state) $
    waitForWorkloadRollout state 900 "deployment/infernix-keycloak"

pulsarReadyPhaseStatefulSets :: [String]
pulsarReadyPhaseStatefulSets =
  [ "statefulset/infernix-infernix-pulsar-bookie",
    "statefulset/infernix-infernix-pulsar-broker",
    "statefulset/infernix-infernix-pulsar-proxy",
    "statefulset/infernix-infernix-pulsar-recovery",
    "statefulset/infernix-infernix-pulsar-toolset",
    "statefulset/infernix-infernix-pulsar-zookeeper"
  ]

waitForFinalPhaseStatefulSetRollout :: Paths -> ClusterState -> Int -> String -> IO ()
waitForFinalPhaseStatefulSetRollout paths state timeoutSeconds workload
  | "statefulset/infernix-infernix-pulsar-" `List.isPrefixOf` workload =
      waitForPulsarStatefulSetRollout paths state timeoutSeconds workload
  | otherwise = waitForWorkloadRollout state timeoutSeconds workload

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel under the legacy 30-attempt × 2 s budget. The retained last
-- non-empty reconcile error is carried in an 'IORef' the probe threads and
-- projected into the timeout diagnostic; readiness is the kernel's positive
-- outcome from a real successful reconcile.
reconcileKeycloakRealmConfiguration :: Paths -> ClusterState -> IO ()
reconcileKeycloakRealmConfiguration paths state =
  when (clusterStateHasDemoUi state) $ do
    putStrLn "reconciling Keycloak demo realm"
    manager <- newManager defaultManagerSettings
    lastErrorRef <- newIORef ""
    let probe = do
          result <-
            ( try
                (reconcileKeycloakRealmConfigurationOnce paths state manager) ::
                IO (Either SomeException ())
            )
          case result of
            Right _ -> pure (Right ())
            Left err -> do
              let message = displayException err
              retained <-
                atomicModifyIORef'
                  lastErrorRef
                  (\previous -> let kept = if null message then previous else message in (kept, kept))
              pure (Left (Readiness.Progress 0 1 (Text.pack retained)))
    outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 30 2000000) probe
    Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
  where
    onTimedOut progress =
      ioError
        ( userError
            ( "Keycloak realm reconcile failed:\n"
                <> Text.unpack (Readiness.progressDetail progress)
            )
        )

-- | Sprint 9.10 (managed-state-transition doctrine): hold the Keycloak admin
-- bearer only inside a region lease. 'withValidAdminToken' re-derives the token
-- at entry and confines it to the continuation's scope (the rank-2 region tag
-- keeps the 'KeycloakAdminToken' out of the result), so the raw credential is
-- never returned, stashed, or held past the admin operation's window. Each admin
-- reconcile re-derives a fresh bearer.
withValidAdminToken ::
  Manager ->
  String ->
  KeycloakAdminCredentials ->
  (forall s. Lease s KeycloakAdminToken -> IO r) ->
  IO r
withValidAdminToken manager edgeBaseUrl credentials =
  withLease
    Acquire
      { acquireEstablish = requestKeycloakAdminToken manager edgeBaseUrl credentials,
        acquireRelease = \_ -> pure ()
      }

reconcileKeycloakRealmConfigurationOnce :: Paths -> ClusterState -> Manager -> IO ()
reconcileKeycloakRealmConfigurationOnce paths state manager = do
  credentials <- readKeycloakAdminCredentials state
  withValidAdminToken manager (clusterEdgeBaseUrl paths state) credentials $ \tokenLease -> do
    let token = leasePayload tokenLease
    putKeycloakJson
      manager
      token
      (keycloakAdminRealmUrl paths state)
      keycloakRealmReconcilePayload
    clientValue <- fetchKeycloakSpaClient paths state manager token
    clientIdValue <- requireKeycloakClientInternalId clientValue
    clientPayload <-
      case keycloakSpaClientReconcilePayload paths state clientValue of
        Right value -> pure value
        Left err -> ioError (userError err)
    putKeycloakJson
      manager
      token
      (keycloakAdminRealmUrl paths state <> "/clients/" <> urlEncodedString clientIdValue)
      clientPayload

readKeycloakAdminCredentials :: ClusterState -> IO KeycloakAdminCredentials
readKeycloakAdminCredentials state = do
  encodedUsername <-
    kubectlOutput
      state
      ( \target ->
          Command.kubectlGetSecretField
            target
            (Command.Namespace "platform")
            (Command.SecretName keycloakAdminSecretName)
            Command.UsernameField
      )
  encodedPassword <-
    kubectlOutput
      state
      ( \target ->
          Command.kubectlGetSecretField
            target
            (Command.Namespace "platform")
            (Command.SecretName keycloakAdminSecretName)
            Command.PasswordField
      )
  KeycloakAdminCredentials
    <$> decodeKubernetesSecretField keycloakAdminSecretName "username" encodedUsername
    <*> decodeKubernetesSecretField keycloakAdminSecretName "password" encodedPassword

decodeKubernetesSecretField :: String -> String -> String -> IO String
decodeKubernetesSecretField secretName fieldName encodedValue =
  case Base64.decode (ByteString8.pack (trim encodedValue)) of
    Left err ->
      ioError
        ( userError
            ( "failed to decode "
                <> secretName
                <> "."
                <> fieldName
                <> ": "
                <> err
            )
        )
    Right decodedValue -> pure (ByteString8.unpack decodedValue)

requestKeycloakAdminToken :: Manager -> String -> KeycloakAdminCredentials -> IO KeycloakAdminToken
requestKeycloakAdminToken manager edgeBaseUrl credentials = do
  baseRequest <- parseRequest (edgeBaseUrl <> "/auth/realms/master/protocol/openid-connect/token")
  let formBody =
        [ ("grant_type", "password"),
          ("client_id", "admin-cli"),
          ("username", ByteString8.pack (keycloakAdminUsername credentials)),
          ("password", ByteString8.pack (keycloakAdminPassword credentials))
        ]
      tokenRequest =
        urlEncodedBody formBody (baseRequest {method = "POST"})
  response <- httpLbs tokenRequest manager
  let code = statusCode (responseStatus response)
  if code == 200
    then decodeKeycloakAdminTokenResponse (responseBody response)
    else
      ioError
        ( userError
            ( "Keycloak admin token request failed with status "
                <> show code
                <> ":\n"
                <> lazyBodyToString (responseBody response)
            )
        )

decodeKeycloakAdminTokenResponse :: Lazy.ByteString -> IO KeycloakAdminToken
decodeKeycloakAdminTokenResponse responsePayload =
  case eitherDecode responsePayload of
    Right token -> pure token
    Left decodeError ->
      ioError
        ( userError
            ( "failed to decode Keycloak admin token response:\n"
                <> decodeError
            )
        )

fetchKeycloakSpaClient :: Paths -> ClusterState -> Manager -> KeycloakAdminToken -> IO Value
fetchKeycloakSpaClient paths state manager token = do
  clientsValue <-
    getKeycloakJson
      manager
      token
      ( keycloakAdminRealmUrl paths state
          <> "/clients?clientId="
          <> urlEncodedString keycloakSpaClientId
      )
  clientValues <-
    case requireJsonArrayPath [] clientsValue of
      Right values -> pure values
      Left err -> ioError (userError ("invalid Keycloak clients response: " <> err))
  case List.find isSpaClient clientValues of
    Just clientValue -> pure clientValue
    Nothing ->
      ioError
        ( userError
            ( "Keycloak client "
                <> keycloakSpaClientId
                <> " was not present in realm "
                <> keycloakRealmName
            )
        )
  where
    isSpaClient clientValue =
      lookupJsonStringPath ["clientId"] clientValue == Just keycloakSpaClientId

requireKeycloakClientInternalId :: Value -> IO String
requireKeycloakClientInternalId clientValue =
  case lookupJsonStringPath ["id"] clientValue of
    Just clientIdValue -> pure clientIdValue
    Nothing ->
      ioError
        ( userError
            ( "Keycloak client "
                <> keycloakSpaClientId
                <> " did not include an internal id"
            )
        )

getKeycloakJson :: Manager -> KeycloakAdminToken -> String -> IO Value
getKeycloakJson manager token url = do
  request <- parseRequest url
  response <-
    httpLbs
      request
        { requestHeaders =
            keycloakAuthorizationHeader token : requestHeaders request
        }
      manager
  let code = statusCode (responseStatus response)
  if code >= 200 && code < 300
    then decodeKeycloakJsonResponse url (responseBody response)
    else
      ioError
        ( userError
            ( "Keycloak GET "
                <> url
                <> " failed with status "
                <> show code
                <> ":\n"
                <> lazyBodyToString (responseBody response)
            )
        )

decodeKeycloakJsonResponse :: String -> Lazy.ByteString -> IO Value
decodeKeycloakJsonResponse url responsePayload =
  case eitherDecode responsePayload of
    Right value -> pure value
    Left decodeError ->
      ioError
        ( userError
            ( "failed to decode Keycloak JSON response from "
                <> url
                <> ":\n"
                <> decodeError
            )
        )

putKeycloakJson :: Manager -> KeycloakAdminToken -> String -> Value -> IO ()
putKeycloakJson manager token url payload = do
  request <- parseRequest url
  response <-
    httpLbs
      request
        { method = "PUT",
          requestHeaders =
            [ keycloakAuthorizationHeader token,
              ("Content-Type", "application/json")
            ],
          requestBody = RequestBodyLBS (encode payload)
        }
      manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204]) $
    ioError
      ( userError
          ( "Keycloak PUT "
              <> url
              <> " failed with status "
              <> show code
              <> ":\n"
              <> lazyBodyToString (responseBody response)
          )
      )

keycloakAuthorizationHeader :: KeycloakAdminToken -> Header
keycloakAuthorizationHeader token =
  ( "Authorization",
    ByteString8.pack ("Bearer " <> Text.unpack (keycloakAdminAccessToken token))
  )

keycloakRealmReconcilePayload :: Value
keycloakRealmReconcilePayload =
  object
    [ "realm" .= keycloakRealmName,
      "loginTheme" .= keycloakLoginThemeName,
      "registrationAllowed" .= True,
      "registrationEmailAsUsername" .= False,
      "verifyEmail" .= False,
      "loginWithEmailAllowed" .= False,
      "duplicateEmailsAllowed" .= True,
      "resetPasswordAllowed" .= False,
      "editUsernameAllowed" .= False,
      "passwordPolicy" .= ("length(8)" :: String)
    ]

keycloakSpaClientReconcilePayload :: Paths -> ClusterState -> Value -> Either String Value
keycloakSpaClientReconcilePayload paths state (Object objectValue) =
  Right
    ( Object
        ( foldr
            (\(fieldName, fieldValue) -> KeyMap.insert (Key.fromText fieldName) fieldValue)
            objectValue
            [ ("redirectUris", keycloakStringArray (keycloakSpaRedirectUris paths state)),
              ("webOrigins", keycloakStringArray (keycloakSpaWebOrigins paths state)),
              ("publicClient", Bool True),
              ("standardFlowEnabled", Bool True),
              ("directAccessGrantsEnabled", Bool False),
              ("serviceAccountsEnabled", Bool False),
              ("implicitFlowEnabled", Bool False),
              ("protocol", String "openid-connect"),
              ("attributes", Object reconciledAttributes)
            ]
        )
    )
  where
    currentAttributes =
      case KeyMap.lookup (Key.fromText "attributes") objectValue of
        Just (Object attributesValue) -> attributesValue
        _ -> KeyMap.empty
    reconciledAttributes =
      foldr
        (\(fieldName, fieldValue) -> KeyMap.insert (Key.fromText fieldName) fieldValue)
        currentAttributes
        [ ("pkce.code.challenge.method", String "S256"),
          ("post.logout.redirect.uris", String "+")
        ]
keycloakSpaClientReconcilePayload _paths _state _ =
  Left "Keycloak SPA client representation was not a JSON object"

keycloakSpaRedirectUris :: Paths -> ClusterState -> [String]
keycloakSpaRedirectUris paths state =
  List.nub
    [ "/*",
      "http://127.0.0.1:" <> show (edgePort state) <> "/*",
      "http://localhost:" <> show (edgePort state) <> "/*",
      "http://infernix-linux-cpu-control-plane:30090/*",
      "http://infernix-linux-gpu-control-plane:30090/*",
      "http://infernix-apple-silicon-control-plane:30090/*",
      clusterEdgeBaseUrl paths state <> "/*"
    ]

keycloakSpaWebOrigins :: Paths -> ClusterState -> [String]
keycloakSpaWebOrigins paths state =
  List.nub
    [ "+",
      "http://127.0.0.1:" <> show (edgePort state),
      "http://localhost:" <> show (edgePort state),
      "http://infernix-linux-cpu-control-plane:30090",
      "http://infernix-linux-gpu-control-plane:30090",
      "http://infernix-apple-silicon-control-plane:30090",
      clusterEdgeBaseUrl paths state
    ]

keycloakStringArray :: [String] -> Value
keycloakStringArray values =
  Array (Vector.fromList (map (String . Text.pack) values))

keycloakAdminRealmUrl :: Paths -> ClusterState -> String
keycloakAdminRealmUrl paths state =
  clusterEdgeBaseUrl paths state <> "/auth/admin/realms/" <> keycloakRealmName

urlEncodedString :: String -> String
urlEncodedString =
  ByteString8.unpack . urlEncode True . ByteString8.pack

lazyBodyToString :: Lazy.ByteString -> String
lazyBodyToString = LazyChar8.unpack

detectDirtyPulsarBootstrapState :: Paths -> RuntimeMode -> IO (Maybe String)
detectDirtyPulsarBootstrapState paths runtimeMode = do
  maybeState <- loadClusterState paths
  clusterExists <- kindClusterExists paths runtimeMode
  case matchingClusterState runtimeMode maybeState of
    Just state
      | clusterPresent state && clusterExists ->
          inspectPods state pulsarBootstrapRepairLogTargets
    _ -> pure Nothing
  where
    inspectPods _ [] = pure Nothing
    inspectPods state (podName : remainingPods) = do
      dirtyPod <- pulsarBootstrapLogShowsDirtyState state podName
      if dirtyPod
        then
          pure
            ( Just
                ( podName
                    <> " reported incompatible retained Pulsar metadata"
                )
            )
        else inspectPods state remainingPods

pulsarBootstrapLogShowsDirtyState :: ClusterState -> String -> IO Bool
pulsarBootstrapLogShowsDirtyState state podName = do
  previousLogsDirty <- podLogsContainDirtyMarker state podName True
  if previousLogsDirty
    then pure True
    else podLogsContainDirtyMarker state podName False

podLogsContainDirtyMarker :: ClusterState -> String -> Bool -> IO Bool
podLogsContainDirtyMarker state podName usePreviousLogs = do
  result <-
    tryDiscoveredClusterCommand
      ( \_ ->
          Command.kubectlPodLogs
            (clusterKubeTarget state)
            (Command.Namespace "platform")
            (Command.PodName podName)
            usePreviousLogs
      )
  pure (either (const False) pulsarBootstrapLogIndicatesDirtyState result)

pulsarBootstrapLogIndicatesDirtyState :: String -> Bool
pulsarBootstrapLogIndicatesDirtyState output =
  any contains pulsarBootstrapDirtySingleLogMarkers
    || zookeeperEpochRegression
    || zookeeperZxidRegression
    || cookieMetadataMismatch
  where
    contains marker = marker `List.isInfixOf` output
    zookeeperEpochRegression =
      contains "The current epoch"
        && contains "older than the last zxid"
    zookeeperZxidRegression =
      contains "Got zxid"
        && contains "older than the last zxid"
    cookieMetadataMismatch =
      contains "is not matching with"
        && (contains "Cookie" || contains "instanceId" || contains "bookieId")

resetPulsarClaimDirectories :: Lease s WriterQuiesced -> Paths -> IO ()
resetPulsarClaimDirectories quiesced paths =
  case leasePayload quiesced of
    WriterQuiesced runtimeMode -> do
      maybeState <- loadClusterState paths
      case matchingClusterState runtimeMode maybeState of
        Nothing -> pure ()
        Just state -> do
          let pulsarClaims = filter isPulsarPersistentClaim (claims state)
          unless (null pulsarClaims) $
            putStrLn "resetting retained Pulsar claim roots"
          mapM_ (resetClaimDirectory state) pulsarClaims
  where
    isPulsarPersistentClaim persistentClaim =
      "pulsar-" `List.isPrefixOf` Text.unpack (workload persistentClaim)
    resetClaimDirectory state persistentClaim = do
      let directoryPath = claimDirectory paths (clusterRuntimeMode state) persistentClaim
      directoryPresent <- doesDirectoryExist directoryPath
      when directoryPresent (removePathForcibly directoryPath)

waitForRoutedPublicationSurface :: Paths -> ClusterState -> IO ()
waitForRoutedPublicationSurface paths state = do
  when (clusterStateHasDemoUi state) $ do
    let publicationUrl = clusterEdgeBaseUrl paths state <> "/api/publication"
        expectedRuntimeMode = clusterRuntimeMode state
    result <-
      retryCommandOutput
        120
        1000000
        ("wait for routed publication surface " <> publicationUrl)
        (probePublicationRoute publicationUrl expectedRuntimeMode)
    case result of
      Right _ -> pure ()
      Left err ->
        ioError
          ( userError
              ( "routed publication surface never became ready for "
                  <> Text.unpack (runtimeModeId expectedRuntimeMode)
                  <> ":\n"
                  <> err
              )
          )
  waitForDirectPulsarProxySurface paths state

waitForDirectPulsarProxySurface :: Paths -> ClusterState -> IO ()
waitForDirectPulsarProxySurface paths state = do
  result <-
    retryCommandOutputWithDeadline
      (Readiness.pollLimitedDeadline 1000000 5400 5400 300)
      "wait for direct Pulsar proxy surface"
      (probeDirectPulsarProxySurface paths state)
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        ( userError
            ( "direct Pulsar proxy surface never became ready for "
                <> Text.unpack (runtimeModeId (clusterRuntimeMode state))
                <> ":\n"
                <> err
            )
        )

probeDirectPulsarProxySurface :: Paths -> ClusterState -> IO (Either String String)
probeDirectPulsarProxySurface paths state = do
  endpointResult <- directPulsarProxyEndpoint paths state
  case endpointResult of
    Left err -> pure (Left err)
    Right (hostName, portNumber) -> do
      let clustersUrl = "http://" <> hostName <> ":" <> show portNumber <> "/admin/v2/clusters"
      requireConsecutiveDirectPulsarProxySuccesses paths clustersUrl 3

requireConsecutiveDirectPulsarProxySuccesses :: Paths -> String -> Int -> IO (Either String String)
requireConsecutiveDirectPulsarProxySuccesses paths clustersUrl requiredSuccesses = go 1
  where
    go sampleNumber = do
      result <- probeDirectPulsarProxyClustersUrl paths clustersUrl
      case result of
        Left err ->
          pure $
            Left
              ( "direct Pulsar proxy stability check failed on sample "
                  <> show sampleNumber
                  <> "/"
                  <> show requiredSuccesses
                  <> ": "
                  <> err
              )
        Right _
          | sampleNumber >= requiredSuccesses -> pure (Right "ready")
          | otherwise -> do
              threadDelay 1000000
              go (sampleNumber + 1)

probeDirectPulsarProxyClustersUrl :: Paths -> String -> IO (Either String String)
probeDirectPulsarProxyClustersUrl paths clustersUrl = do
  response <-
    tryClusterCommand
      paths
      (Command.curlPulsarClusters (Command.Url clustersUrl))
  pure $
    response >>= \payload ->
      case eitherDecode (LazyChar8.pack payload) of
        Right (Array _) -> Right "ready"
        Right _ -> Left ("unexpected Pulsar clusters payload from " <> clustersUrl)
        Left err -> Left ("invalid Pulsar clusters payload from " <> clustersUrl <> ": " <> err)

directPulsarProxyEndpoint :: Paths -> ClusterState -> IO (Either String (String, Int))
directPulsarProxyEndpoint paths state
  | Config.controlPlaneContext paths == OuterContainer = do
      ipv4Result <- kindControlPlaneIpv4 paths (clusterRuntimeMode state)
      pure $
        case ipv4Result of
          Right ipv4 -> Right (ipv4, pulsarProxyHttpNodePort)
          Left err -> Left err
  | otherwise = do
      pulsarHttpPort <- fromMaybe pulsarProxyHttpNodePort <$> readPulsarHttpPortMaybe paths
      pure (Right ("127.0.0.1", pulsarHttpPort))

kindControlPlaneIpv4 :: Paths -> RuntimeMode -> IO (Either String String)
kindControlPlaneIpv4 paths runtimeMode = do
  result <-
    tryClusterCommand
      paths
      ( Command.dockerInspectContainerField
          (Command.ContainerName (kindControlPlaneNodeName paths runtimeMode))
          Command.KindNetworkIpv4
      )
  pure $
    result >>= \rawOutput ->
      let ipv4 = Text.unpack (Text.strip (Text.pack rawOutput))
       in if null ipv4
            then Left ("Kind control-plane IPv4 was empty for " <> kindControlPlaneNodeName paths runtimeMode)
            else Right ipv4

waitForWorkloadRollout :: ClusterState -> Int -> String -> IO ()
waitForWorkloadRollout state timeoutSeconds workload =
  runDiscoveredClusterCommand
    ( \_ ->
        Command.kubectlRolloutStatus
          (clusterKubeTarget state)
          (Command.Namespace "platform")
          (Command.WorkloadRef workload)
          timeoutSeconds
    )

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel. Here the poll's wait is the blocking
-- @kubectl rollout status --timeout@ subcommand itself, so the kernel is driven
-- as a bounded poll-counter — a 1 µs inter-poll delay with a stall/ceiling of
-- @timeoutSeconds `div` probeSeconds@ polls — rather than a poll-and-sleep. The
-- terminal dirty-retained-state condition throws from inside the probe (an
-- exception the kernel propagates), and the retained last non-empty rollout error
-- is projected into the timeout diagnostic. Each poll still touches the lifecycle
-- progress heartbeat.
waitForPulsarStatefulSetRollout :: Paths -> ClusterState -> Int -> String -> IO ()
waitForPulsarStatefulSetRollout paths state timeoutSeconds workload = do
  lastErrorRef <- newIORef ""
  let probe = do
        touchLifecycleProgress paths state
        result <-
          tryClusterCommand
            paths
            ( Command.kubectlRolloutStatus
                (clusterKubeTarget state)
                (Command.Namespace "platform")
                (Command.WorkloadRef workload)
                probeSeconds
            )
        case result of
          Right _ -> pure (Right ())
          Left err -> do
            maybeRepairReason <- detectDirtyPulsarBootstrapState paths (clusterRuntimeMode state)
            case maybeRepairReason of
              Just repairReason ->
                ioError
                  ( userError
                      ( "Pulsar retained state is inconsistent while waiting for "
                          <> workload
                          <> ": "
                          <> repairReason
                      )
                  )
              Nothing -> do
                retained <-
                  atomicModifyIORef'
                    lastErrorRef
                    (\previous -> let kept = if null err then previous else err in (kept, kept))
                pure (Left (Readiness.Progress 0 1 (Text.pack retained)))
  outcome <-
    Readiness.awaitReadiness
      ( Readiness.pollLimitedDeadline
          1
          timeoutSeconds
          timeoutSeconds
          maxPolls
      )
      probe
  Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
  where
    probeSeconds = 30
    maxPolls = max 1 ((timeoutSeconds + probeSeconds - 1) `div` probeSeconds)
    onTimedOut progress =
      ioError
        ( userError
            ( "Pulsar rollout did not become ready for "
                <> workload
                <> ":\n"
                <> Text.unpack (Readiness.progressDetail progress)
            )
        )

ensureHelmDependencies :: Paths -> IO ()
ensureHelmDependencies paths = do
  createDirectoryIfMissing True (helmDependencyArchivesDirectory paths)
  mapM_ (ensureHelmDependencyArchivePresent paths) helmDependencyArchives

ensureHelmDependencyArchivePresent :: Paths -> FilePath -> IO ()
ensureHelmDependencyArchivePresent paths archiveRelativePath = do
  let archivePath = repoRoot paths </> archiveRelativePath
  archivePresent <- doesFileExist archivePath
  unless archivePresent $ do
    let archiveName = takeFileName archiveRelativePath
        fetchDirectory = helmDependencyArchivesDirectory paths </> (".fetch-" <> archiveName)
        fetchedArchivePath = fetchDirectory </> archiveName
    fetchDirectoryPresent <- doesDirectoryExist fetchDirectory
    when fetchDirectoryPresent (removePathForcibly fetchDirectory)
    createDirectoryIfMissing True fetchDirectory
    fetchHelmDependencyArchive paths archiveRelativePath fetchDirectory
    fetchedArchivePresent <- doesFileExist fetchedArchivePath
    unless fetchedArchivePresent $
      ioError
        ( userError
            ( "Helm dependency fetch did not produce the expected archive:\n"
                <> fetchedArchivePath
            )
        )
    renameFile fetchedArchivePath archivePath
    removePathForcibly fetchDirectory

fetchHelmDependencyArchive :: Paths -> FilePath -> FilePath -> IO ()
fetchHelmDependencyArchive paths archiveRelativePath destinationDirectory =
  case archiveRelativePath of
    "chart/charts/pg-operator-2.9.0.tgz" ->
      fetchDependency Command.PostgresOperatorChart
    "chart/charts/pg-db-2.9.0.tgz" ->
      fetchDependency Command.PostgresDatabaseChart
    "chart/charts/pulsar-4.5.0.tgz" ->
      fetchDependency Command.PulsarChart
    "chart/charts/gateway-helm-v1.7.2.tgz" ->
      fetchDependency Command.EnvoyGatewayChart
    _ ->
      ioError
        ( userError
            ( "Unsupported Helm dependency archive path:\n"
                <> archiveRelativePath
            )
        )
  where
    fetchDependency dependency =
      runClusterCommand
        paths
        (Command.helmPullDependency dependency destinationDirectory)

ensureEnvoyGatewayCrdsInstalled :: Paths -> ClusterState -> IO ()
ensureEnvoyGatewayCrdsInstalled paths state = do
  crdPaths <-
    filter ("gateway-helm/crds/" `List.isPrefixOf`) . lines
      <$> captureClusterCommand
        paths
        (Command.tarListArchive envoyGatewayDependencyArchive)
  when (null crdPaths) $
    ioError
      ( userError
          ( "Envoy Gateway dependency archive did not contain any CRDs:\n"
              <> repoRoot paths
              </> envoyGatewayDependencyArchive
          )
      )
  crdDocuments <-
    mapM
      ( captureClusterCommand paths
          . Command.tarExtractEntry envoyGatewayDependencyArchive
          . Command.ArchiveEntry
      )
      crdPaths
  -- Helm does not install CRDs that live under dependency charts, so apply the bundle explicitly.
  crdBundle <-
    case Command.mkCrdBundle (List.intercalate "\n---\n" crdDocuments) of
      Left err -> ioError (userError err)
      Right bundle -> pure bundle
  runClusterCommand
    paths
    ( Command.kubectlApplyCrdBundle
        (clusterKubeTarget state)
        crdBundle
    )

ensureHelmRepositoryDefinitions :: Paths -> IO ()
ensureHelmRepositoryDefinitions paths =
  mapM_
    (runClusterCommand paths . Command.helmRepoAdd)
    helmRepositories

-- | Phase 3 Sprint 3.17: bring the Percona operator up during warmup.
--
-- There is nothing for it to reconcile at this point any more. The Patroni
-- cluster that used to back the image registry landed here, and the registry no
-- longer has one; the only remaining cluster is Keycloak's, whose CR is applied
-- later in 'reconcileFinalPhaseOperatorManagedPersistentVolumes'. The operator
-- is still started here so it is already running when that CR lands.
reconcileOperatorManagedPersistentVolumes :: Paths -> ClusterState -> IO ClusterState
reconcileOperatorManagedPersistentVolumes _paths state = do
  waitForWorkloadRollout state 900 postgresOperatorDeployment
  pure state

-- | Phase 7 Sprint 7.1: second pass over operator-managed PVCs after the
-- FinalPhase chart deploy applies the @keycloak-postgresql@ PerconaPGCluster
-- CR. Phase 3 Sprint 3.16 collapsed that cluster to one instance, so the
-- Percona operator creates 2 additional PVCs (1 data + 1
-- pgbackrest repo) on the supported @infernix-manual@ storage class; we
-- create the matching PVs and wait for them to bind so the Keycloak
-- Deployment is not blocked behind a Pending database. Unlike the warmup
-- reconcile, this is the first and only pass that binds operator-managed
-- storage, because the warmup reconcile has no Patroni cluster to bind.
reconcileFinalPhaseOperatorManagedPersistentVolumes :: Paths -> ClusterState -> IO ClusterState
reconcileFinalPhaseOperatorManagedPersistentVolumes paths state = do
  operatorClaims <- waitForOperatorManagedPersistentClaims state finalPhaseExpectedOperatorClaims
  mapM_ (ensureClaimDirectoryReady paths (clusterRuntimeMode state)) operatorClaims
  usesHostBindMounts <- kindUsesHostBindMounts paths (clusterRuntimeMode state)
  unless usesHostBindMounts $
    prepareKindNodeClaimDirectories paths state (clusterRuntimeMode state) operatorClaims
  let updatedState = state {claims = mergePersistentClaims (claims state) operatorClaims}
  reconcilePersistentVolumes updatedState
  waitForPersistentClaimsBound updatedState operatorClaims
  pure updatedState

refreshPersistentClaims :: ClusterState -> IO ClusterState
refreshPersistentClaims state = do
  operatorClaims <- discoverOperatorManagedPersistentClaims state
  pure (state {claims = mergePersistentClaims (claims state) operatorClaims})

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel under the legacy 72-attempt × 5 s budget. The discovered
-- claim list is the kernel's readiness evidence, minted only when at least
-- @expectedCount@ operator-managed claims are actually observed; the last
-- observed count rides in the kernel 'Progress' and is projected into the timeout
-- diagnostic.
waitForOperatorManagedPersistentClaims :: ClusterState -> Int -> IO [PersistentClaim]
waitForOperatorManagedPersistentClaims state expectedCount = do
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 72 5000000) probe
  Readiness.foldReadiness pure onTimedOut onTimedOut outcome
  where
    probe = do
      currentClaims <- discoverOperatorManagedPersistentClaims state
      if length currentClaims >= expectedCount
        then pure (Right currentClaims)
        else
          pure
            ( Left
                ( Readiness.Progress
                    (length currentClaims)
                    expectedCount
                    "operator-managed PostgreSQL claims not yet present"
                )
            )
    onTimedOut progress =
      ioError
        ( userError
            ( "operator-managed PostgreSQL claims never appeared; expected at least "
                <> show expectedCount
                <> " but found "
                <> show (Readiness.progressObserved progress)
                <> " after retries"
            )
        )

discoverOperatorManagedPersistentClaims :: ClusterState -> IO [PersistentClaim]
discoverOperatorManagedPersistentClaims state = do
  pvcPayload <-
    kubectlOutput
      state
      Command.kubectlListPostgresPvcs
  claims <-
    case decodeOperatorManagedClaims pvcPayload of
      Left err -> ioError (userError err)
      Right value -> pure value
  pure (normalizeOperatorManagedClaims claims)

normalizeOperatorManagedClaims :: [OperatorManagedClaim] -> [PersistentClaim]
normalizeOperatorManagedClaims rawClaims =
  concatMap normalizeGroup groupedClaims
  where
    sortedClaims = List.sortOn (\claimValue -> (operatorClaimGroupingKey claimValue, operatorClaimPvcName claimValue)) rawClaims
    groupedClaims = List.groupBy sameGroupingKey sortedClaims
    sameGroupingKey left right = operatorClaimGroupingKey left == operatorClaimGroupingKey right
    normalizeGroup = zipWith operatorClaimToPersistentClaim [0 ..]

operatorClaimGroupingKey :: OperatorManagedClaim -> (String, String, String, String)
operatorClaimGroupingKey claimValue =
  ( operatorClaimNamespace claimValue,
    operatorClaimCluster claimValue,
    operatorManagedWorkloadName claimValue,
    operatorManagedClaimName claimValue
  )

operatorManagedWorkloadName :: OperatorManagedClaim -> String
operatorManagedWorkloadName claimValue =
  case operatorClaimRepository claimValue of
    repositoryValue
      | not (null repositoryValue) ->
          operatorClaimCluster claimValue <> "-pgbackrest"
    _ ->
      operatorClaimCluster claimValue
        <> "-"
        <> groupSuffix
  where
    groupSuffix
      | not (null (operatorClaimInstanceSet claimValue)) = operatorClaimInstanceSet claimValue
      | not (null (operatorClaimDataKind claimValue)) = operatorClaimDataKind claimValue
      | otherwise = operatorClaimRole claimValue

operatorManagedClaimName :: OperatorManagedClaim -> String
operatorManagedClaimName claimValue
  | not (null (operatorClaimRepository claimValue)) = operatorClaimRepository claimValue
  | operatorClaimRole claimValue `elem` ["pgdata", "pgwal"] = operatorClaimRole claimValue
  | not (null (operatorClaimDataKind claimValue)) = operatorClaimDataKind claimValue
  | otherwise = operatorClaimRole claimValue

operatorClaimToPersistentClaim :: Int -> OperatorManagedClaim -> PersistentClaim
operatorClaimToPersistentClaim ordinalValue claimValue =
  PersistentClaim
    { namespace = Text.pack (operatorClaimNamespace claimValue),
      release = "infernix",
      workload = Text.pack (operatorManagedWorkloadName claimValue),
      ordinal = ordinalValue,
      claim = Text.pack (operatorManagedClaimName claimValue),
      pvcName = Text.pack (operatorClaimPvcName claimValue),
      requestedStorage = Text.pack (operatorClaimRequestedStorage claimValue)
    }

decodeOperatorManagedClaims :: String -> Either String [OperatorManagedClaim]
decodeOperatorManagedClaims payload =
  case eitherDecode (LazyChar8.pack payload) of
    Left err -> Left ("failed to decode operator-managed PVC payload: " <> err)
    Right rootValue -> parseOperatorManagedClaims rootValue

parseOperatorManagedClaims :: Value -> Either String [OperatorManagedClaim]
parseOperatorManagedClaims rootValue = do
  items <- requireJsonArrayPath ["items"] rootValue
  maybeClaims <- mapM parseOperatorManagedClaimValue items
  pure
    ( List.sortOn
        (\claimValue -> (operatorClaimGroupingKey claimValue, operatorClaimPvcName claimValue))
        (catMaybes maybeClaims)
    )

parseOperatorManagedClaimValue :: Value -> Either String (Maybe OperatorManagedClaim)
parseOperatorManagedClaimValue itemValue = do
  let maybeClusterValue =
        lookupJsonTextPath ["metadata", "labels", "postgres-operator.crunchydata.com/cluster"] itemValue
  case maybeClusterValue of
    Nothing -> pure Nothing
    Just clusterValue ->
      operatorManagedClaimFromValue itemValue clusterValue

operatorManagedClaimFromValue :: Value -> Text.Text -> Either String (Maybe OperatorManagedClaim)
operatorManagedClaimFromValue itemValue clusterValue
  | null roleValue =
      Right Nothing
  | storageClassValue /= Just "infernix-manual" =
      Left ("operator-managed PostgreSQL PVC uses unsupported storageClassName " <> show storageClassValue)
  | otherwise =
      Right
        ( Just
            OperatorManagedClaim
              { operatorClaimNamespace =
                  lookupStringOr "default" ["metadata", "namespace"],
                operatorClaimCluster = Text.unpack clusterValue,
                operatorClaimInstanceSet =
                  lookupStringOr "" ["metadata", "labels", "postgres-operator.crunchydata.com/instance-set"],
                operatorClaimRole = roleValue,
                operatorClaimDataKind =
                  lookupStringOr (if null repositoryValue then "" else "pgbackrest") ["metadata", "labels", "postgres-operator.crunchydata.com/data"],
                operatorClaimInstance =
                  lookupStringOr "" ["metadata", "labels", "postgres-operator.crunchydata.com/instance"],
                operatorClaimRepository = repositoryValue,
                operatorClaimPvcName =
                  lookupStringOr "" ["metadata", "name"],
                operatorClaimRequestedStorage =
                  lookupStringOr "5Gi" ["spec", "resources", "requests", "storage"]
              }
        )
  where
    repositoryValue =
      lookupStringOr "" ["metadata", "labels", "postgres-operator.crunchydata.com/pgbackrest-repo"]
    roleValue =
      lookupStringOr (if null repositoryValue then "" else "pgbackrest") ["metadata", "labels", "postgres-operator.crunchydata.com/role"]
    storageClassValue =
      lookupJsonStringPath ["spec", "storageClassName"] itemValue
    lookupStringOr defaultValue pathSegments =
      fromMaybe defaultValue (lookupJsonStringPath pathSegments itemValue)

mergePersistentClaims :: [PersistentClaim] -> [PersistentClaim] -> [PersistentClaim]
mergePersistentClaims existingClaims newClaims =
  List.sortOn
    persistentVolumeClaimName
    (Map.elems (Map.fromList [(persistentVolumeClaimName persistentClaim, persistentClaim) | persistentClaim <- existingClaims <> newClaims]))

probePublicationRoute :: String -> RuntimeMode -> IO (Either String String)
probePublicationRoute publicationUrl expectedRuntimeMode = do
  response <-
    tryDiscoveredClusterCommand $ \_ ->
      Command.curlPublication (Command.Url publicationUrl)
  pure $
    response >>= \payload ->
      case eitherDecode (LazyChar8.pack payload) of
        Left err -> Left ("invalid publication payload: " <> err)
        Right publicationPayload ->
          if routedPublicationReady expectedRuntimeMode publicationPayload
            then Right "ready"
            else Left "publication route not ready"

routedPublicationReady :: RuntimeMode -> Value -> Bool
routedPublicationReady expectedRuntimeMode publicationPayload =
  lookupJsonStringPath ["daemonLocation"] publicationPayload
    == Just (Text.unpack (expectedDaemonLocationForRuntime expectedRuntimeMode))
    && lookupJsonStringPath ["inferenceDispatchMode"] publicationPayload
      == Just (Text.unpack (expectedInferenceDispatchModeForRuntime expectedRuntimeMode))
    && lookupJsonStringPath ["apiUpstream", "mode"] publicationPayload == Just "cluster-demo"
    && lookupJsonStringPath ["runtimeMode"] publicationPayload == Just (Text.unpack (runtimeModeId expectedRuntimeMode))

requireJsonArrayPath :: [Text.Text] -> Value -> Either String [Value]
requireJsonArrayPath pathSegments value =
  case lookupJsonValuePath pathSegments value of
    Just (Array values) -> Right (Vector.toList values)
    _ -> Left ("missing JSON array at " <> show (map Text.unpack pathSegments))

lookupJsonValuePath :: [Text.Text] -> Value -> Maybe Value
lookupJsonValuePath [] value = Just value
lookupJsonValuePath (segment : remainingSegments) (Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= lookupJsonValuePath remainingSegments
lookupJsonValuePath _ _ = Nothing

lookupJsonTextPath :: [Text.Text] -> Value -> Maybe Text.Text
lookupJsonTextPath pathSegments value =
  case lookupJsonValuePath pathSegments value of
    Just (String textValue) -> Just textValue
    _ -> Nothing

lookupJsonStringPath :: [Text.Text] -> Value -> Maybe String
lookupJsonStringPath pathSegments value =
  Text.unpack <$> lookupJsonTextPath pathSegments value

parseCurlBodyAndStatus :: String -> Maybe (String, String)
parseCurlBodyAndStatus payload =
  case reverse (lines payload) of
    statusCode : reversedBodyLines ->
      Just (unlines (reverse reversedBodyLines), trim statusCode)
    [] -> Nothing

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel under the legacy 72-attempt × 5 s budget per claim. The
-- Bound phase is the kernel's readiness evidence; the retained last non-empty
-- phase rides in an 'IORef' the probe threads and is projected into the timeout
-- diagnostic.
waitForPersistentClaimsBound :: ClusterState -> [PersistentClaim] -> IO ()
waitForPersistentClaimsBound state = mapM_ waitForPersistentClaimBound
  where
    waitForPersistentClaimBound persistentClaim = do
      lastPhaseRef <- newIORef ""
      let probe = do
            phaseValue <-
              trim
                <$> kubectlOutput
                  state
                  ( \target ->
                      Command.kubectlGetPvcPhase
                        target
                        (Command.Namespace claimNamespace)
                        (Command.PvcName pvcNameValue)
                  )
            if phaseValue == "Bound"
              then pure (Right ())
              else do
                retained <-
                  atomicModifyIORef'
                    lastPhaseRef
                    (\previous -> let kept = if null phaseValue then previous else phaseValue in (kept, kept))
                pure (Left (Readiness.Progress 0 1 (Text.pack retained)))
      outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 72 5000000) probe
      Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
      where
        claimNamespace = Text.unpack (namespace persistentClaim)
        pvcNameValue = persistentVolumeClaimName persistentClaim
        onTimedOut progress =
          ioError
            ( userError
                ( "persistent claim "
                    <> pvcNameValue
                    <> " never reached Bound phase; last phase was "
                    <> Text.unpack (Readiness.progressDetail progress)
                )
            )

reconcilePersistentVolumes :: ClusterState -> IO ()
reconcilePersistentVolumes state =
  mapM_ applyClaim (claims state)
  where
    applyClaim persistentClaim =
      runDiscoveredClusterCommand
        ( \_ ->
            Command.kubectlApplyPersistentVolume
              (clusterKubeTarget state)
              Command.PersistentVolumeSpec
                { Command.persistentVolumeName =
                    Command.ResourceName (persistentVolumeName persistentClaim),
                  Command.persistentVolumeStorage =
                    Text.unpack (requestedStorage persistentClaim),
                  Command.persistentVolumeClaimNamespace =
                    Command.Namespace (Text.unpack (namespace persistentClaim)),
                  Command.persistentVolumeClaimName =
                    Command.PvcName (persistentVolumeClaimName persistentClaim),
                  Command.persistentVolumeHostPath =
                    nodeMountedClaimPath persistentClaim
                }
        )

-- | Phase 8 Sprint 8.12: the Kind topology follows the system contract's fleet
-- rather than a constant, so the machine count is an argument. A fleet needs one
-- worker node per engine machine, because a machine is what the contract counts
-- and a node is what a machine is on this lane; anything else would put two
-- machines' engines on one box and reproduce exactly the double-admission the
-- fleet contract exists to prevent.
--
-- The count is passed in rather than read here: this function writes a file
-- from facts it is given, and the contract that carries the fleet is resolved
-- by the lifecycle step that has already validated it.
writeGeneratedKindConfig :: Paths -> RuntimeMode -> EngineMachineCount -> Int -> Int -> Int -> IO FilePath
writeGeneratedKindConfig paths runtimeMode machineCount edgePortValue registryPortValue pulsarHttpPortValue = do
  let outputPath =
        buildRoot paths
          </> "kind"
          </> ("cluster-" <> Text.unpack (runtimeModeId runtimeMode) <> ".generated.yaml")
  hostKindRoot <- resolveHostKindRoot paths runtimeMode
  usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
  writeRegistryHostsConfig paths runtimeMode registryPortValue
  hostRegistryHostsDirectory <- resolveHostRegistryHostsRoot paths runtimeMode
  writeTextFile outputPath (Text.pack (renderKindConfig paths runtimeMode machineCount edgePortValue registryPortValue pulsarHttpPortValue hostKindRoot hostRegistryHostsDirectory usesHostBindMounts))
  pure outputPath

-- | The fleet size the generated system contract declares.
--
-- Read from the contract rather than passed down from the caller because the
-- Kind topology is created before any cluster state exists, and the contract is
-- the only thing that has already been written at that point. It is required
-- to exist: @cluster up@ fails fast without it (Sprint 8.3), so an absent
-- contract is a named refusal here rather than a silent single-machine default.
resolveClusterEngineMachineCount :: Paths -> RuntimeMode -> IO EngineMachineCount
resolveClusterEngineMachineCount paths runtimeMode = do
  generatedConfigPath <- requireGeneratedDemoConfigFile paths runtimeMode
  generatedConfig <- decodeBootstrapDemoConfigFile generatedConfigPath
  pure (engineMachineCountFromMemberIds (map engineMemberId (engineMembers generatedConfig)))

-- | Phase 3 follow-on (2026-05-29): the containerd registry-hosts
-- namespace is keyed on @localhost:<host-port>@ — the same address
-- @docker push@ targets when publishing images — so the resolution
-- target points containerd at @<kind-node>:30002@ (the in-cluster
-- NodePort, which stays fixed).
writeRegistryHostsConfig :: Paths -> RuntimeMode -> Int -> IO ()
writeRegistryHostsConfig paths runtimeMode registryPortValue = do
  let namespaceName = "localhost:" <> show registryPortValue
      inClusterTarget = kindClusterName paths runtimeMode <> "-control-plane:30002"
  writeRegistryNamespace namespaceName inClusterTarget (localRegistryHostsRoot paths runtimeMode)
  where
    writeRegistryNamespace registryNamespace reachableRegistryHost registryRoot = do
      let registryDirectory = registryRoot </> registryNamespace
          hostsFile = registryDirectory </> "hosts.toml"
          hostsToml =
            unlines
              [ "server = \"http://" <> reachableRegistryHost <> "\"",
                "",
                "[host.\"http://" <> reachableRegistryHost <> "\"]",
                "  capabilities = [\"pull\", \"resolve\"]",
                "  skip_verify = true"
              ]
      createDirectoryIfMissing True registryDirectory
      writeFile hostsFile hostsToml

-- | Phase 2 Sprint 2.13: legacy host-kind-root env override
-- retired. The supported flow now derives @hostKindRoot@ from the
-- typed @HostConfig.hostFilesystem.kindRoot@ field that
-- 'Infernix.Config.discoverPaths' already threads through 'Paths', so
-- the host-side Kind root falls out of 'kindRuntimeRoot' directly.
resolveHostKindRoot :: Paths -> RuntimeMode -> IO FilePath
resolveHostKindRoot paths runtimeMode =
  resolveHostRepoPath paths (kindRuntimeRoot paths runtimeMode)

localRegistryHostsRoot :: Paths -> RuntimeMode -> FilePath
localRegistryHostsRoot paths runtimeMode =
  repoRoot paths
    </> ".build"
    </> "kind"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> "registry"

resolveHostRegistryHostsRoot :: Paths -> RuntimeMode -> IO FilePath
resolveHostRegistryHostsRoot paths runtimeMode =
  resolveHostRepoPath paths (localRegistryHostsRoot paths runtimeMode)

-- | Phase 2 Sprint 2.13: legacy host-repo-root env override
-- retired. On host-native Apple, the typed
-- @HostConfig.hostFilesystem.repoRoot@ already matches the host
-- filesystem so we return it directly. On the Linux outer-container
-- path, the manifest value is the launcher-internal @/workspace@
-- path; the actual host-side path lives only in the launcher
-- container's bind-mount metadata, which we discover by asking the
-- Docker daemon via the mounted Docker socket. Without this
-- translation, nested Kind workers receive the launcher's
-- @/workspace/...@ paths verbatim and Docker creates a separate
-- host-side directory tree at @/workspace/...@ that diverges from
-- the operator's real repo root.
resolveHostRepoRoot :: Paths -> IO FilePath
resolveHostRepoRoot paths
  | not (isBakedLinuxOuterContainerManifest paths) = pure (repoRoot paths)
  | otherwise = do
      launcherContainer <- currentLauncherContainerName
      mountResult <-
        tryClusterCommand
          paths
          ( Command.dockerInspectContainerField
              (Command.ContainerName launcherContainer)
              (Command.MountSourceAt (repoRoot paths </> ".data"))
          )
      case mountResult of
        Right rawSource ->
          let trimmedSource = trim rawSource
           in if null trimmedSource
                then pure (repoRoot paths)
                else pure (takeDirectory trimmedSource)
        Left _ -> pure (repoRoot paths)

-- | Detect whether 'paths' was discovered from the baked Linux outer-
-- container host manifest (the one shipped with the launcher image)
-- versus a unit-test fixture or operator-edited manifest. The
-- docker-inspect host-path translation only fires for the fully-baked
-- profile; tests + operator-overridden manifests are taken verbatim.
-- The check compares 'repoRoot', 'kindRoot', and 'dataRoot'
-- simultaneously: a unit test that synthesises a fixture overrides
-- @kindRoot@ + @dataRoot@ to point at the test sandbox, which falls
-- out of this check.
isBakedLinuxOuterContainerManifest :: Paths -> Bool
isBakedLinuxOuterContainerManifest paths =
  Config.controlPlaneContext paths == OuterContainer
    && repoRoot paths == "/workspace"
    && kindRoot paths == "/workspace/.data/runtime/kind"
    && dataRoot paths == "/workspace/.data"

resolveHostRepoPath :: Paths -> FilePath -> IO FilePath
resolveHostRepoPath paths containerPath = do
  hostRepoRoot <- resolveHostRepoRoot paths
  let normalizedRepoRoot = normalise (repoRoot paths)
      normalizedContainerPath = normalise containerPath
      repoRootPrefix = addTrailingPathSeparator normalizedRepoRoot
  pure (resolveHostRepoPathFromNormalized hostRepoRoot normalizedRepoRoot repoRootPrefix normalizedContainerPath)

resolveHostRepoPathFromNormalized :: FilePath -> FilePath -> FilePath -> FilePath -> FilePath
resolveHostRepoPathFromNormalized hostRepoRoot normalizedRepoRoot repoRootPrefix normalizedContainerPath
  | normalizedContainerPath == normalizedRepoRoot = hostRepoRoot
  | otherwise =
      case List.stripPrefix repoRootPrefix normalizedContainerPath of
        Just relativePath -> hostRepoRoot </> relativePath
        Nothing -> normalizedContainerPath

renderKindConfig :: Paths -> RuntimeMode -> EngineMachineCount -> Int -> Int -> Int -> FilePath -> FilePath -> Bool -> String
renderKindConfig paths runtimeMode machineCount edgePortValue registryPortValue pulsarHttpPortValue hostKindRoot registryHostsDirectory usesHostBindMounts =
  unlines (preamble <> containerdConfigPatchesBlock <> ["nodes:"] <> nodeBlock "control-plane" initLabels edgePortLines <> workerNodeBlocks)
  where
    preamble =
      [ "kind: Cluster",
        "apiVersion: kind.x-k8s.io/v1alpha4",
        "name: " <> kindClusterName paths runtimeMode,
        "networking:",
        "  apiServerAddress: \"127.0.0.1\""
      ]
    -- Phase 3 follow-on (2026-05-29): enable containerd's
    -- hosts.toml-driven registry resolution so each Kind node treats
    -- /etc/containerd/certs.d/<namespace>/hosts.toml as the authoritative
    -- mapping for that namespace. Without this, containerd ignores the
    -- registry-hosts files we mount via extraMounts and kubelet dials
    -- @localhost:<registryPort>@ literally inside the node, which has
    -- nothing listening and refuses the connection. Kind 0.31 does not
    -- emit @config_path@ by default; the patch matches what
    -- @writeRegistryHostsConfig@ already provisions under
    -- @\/etc\/containerd\/certs.d@.
    containerdConfigPatchesBlock =
      [ "containerdConfigPatches:",
        "  - |-",
        "    [plugins.\"io.containerd.grpc.v1.cri\".registry]",
        "      config_path = \"/etc/containerd/certs.d\""
      ]
    initLabels = controlPlaneRuntimeModeLabels runtimeMode
    workerLabels = runtimeModeLabels runtimeMode
    -- Every worker carries its fleet slot, including the single-worker
    -- topology: the label is what a fleet Deployment's `nodeSelector` names,
    -- and a topology that only grows the label when a fleet appears would make
    -- the two shapes differ in more than their size.
    workerNodeBlocks =
      concat
        [ nodeBlock "worker" (workerLabels <> "," <> fleetSlotLabelKey <> "=" <> show slot) []
        | slot <- [1 .. kindWorkerCount runtimeMode machineCount]
        ]
    edgePortLines =
      [ "    extraPortMappings:",
        "      - containerPort: 30090",
        "        hostPort: " <> show edgePortValue,
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30002",
        "        hostPort: " <> show registryPortValue,
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30011",
        "        hostPort: 30011",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: " <> show pulsarProxyHttpNodePort,
        "        hostPort: " <> show pulsarHttpPortValue,
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30650",
        "        hostPort: 30650",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP"
      ]
    nodeBlock role labels extraLines =
      [ "  - role: " <> role,
        "    image: " <> kindNodeImage
      ]
        <> extraLines
        <> extraMountLines role
        <> [ "    kubeadmConfigPatches:",
             "      - |",
             "        kind: " <> kubeConfiguration role,
             "        nodeRegistration:",
             "          kubeletExtraArgs:",
             "            node-labels: " <> show labels
           ]
    extraMountLines role
      | null nodeExtraMounts = []
      | otherwise = ["    extraMounts:"] <> nodeExtraMounts
      where
        nodeExtraMounts = linuxGpuMounts role <> hostBindMounts
    hostBindMounts
      | usesHostBindMounts =
          [ "      - hostPath: " <> hostKindRoot,
            "        containerPath: " <> nodeMountedKindRoot,
            "      - hostPath: " <> registryHostsDirectory,
            "        containerPath: /etc/containerd/certs.d"
          ]
      | otherwise = []
    linuxGpuMounts role = case (runtimeMode, role) of
      (LinuxGpu, "worker") ->
        [ "      - hostPath: /dev/null",
          "        containerPath: /var/run/nvidia-container-devices/all"
        ]
      _ -> []
    kubeConfiguration role
      | role == "control-plane" = "InitConfiguration"
      | otherwise = "JoinConfiguration"

-- | Phase 3 Sprint 3.16 follow-on: one worker per supported lane. The
-- retired @LinuxCpu -> 2@ existed to host a second engine replica under the
-- required pod anti-affinity, and both of those are deleted; a second worker
-- with nothing that must land on it is a node the topology does not use.
--
-- This is the same defect shape as the generated Helm overlay's replica
-- counts: the sprint edited the tracked @kind/cluster-linux-cpu.yaml@, but a
-- Kind cluster is created from 'renderKindConfig', so the tracked file is a
-- reference document and this function is what deploys.
kindWorkerCount :: RuntimeMode -> EngineMachineCount -> Int
kindWorkerCount runtimeMode machineCount =
  case runtimeMode of
    -- Apple engine members are host daemons, so an Apple fleet is a second Mac
    -- rather than a second node: the cluster's worker count is unaffected by it.
    AppleSilicon -> 1
    _ -> max 1 (engineMachineCountValue machineCount)

-- | Phase 2 Sprint 2.13: legacy host-repo-root env check
-- retired. The supported control-plane-context detector is the typed
-- @Paths.controlPlaneContext@ already derived from 'HostConfig'; no
-- env consultation is needed.
kindUsesHostBindMounts :: Paths -> RuntimeMode -> IO Bool
-- Linux outer-container runs can hand the host Docker daemon host-resolved paths, so Kind nodes
-- can mount retained state directly. Apple keeps explicit sync to avoid macOS uid/gid issues.
kindUsesHostBindMounts paths runtimeMode =
  case runtimeMode of
    AppleSilicon -> pure False
    _ -> pure (Config.controlPlaneContext paths == OuterContainer)

prepareKindNodeRuntimePaths :: Paths -> ClusterState -> RuntimeMode -> IO ()
prepareKindNodeRuntimePaths paths state runtimeMode = do
  let localKindRoot = kindRuntimeRoot paths runtimeMode
      controlPlaneNodeName = kindControlPlaneNodeName paths runtimeMode
  createDirectoryIfMissing True localKindRoot
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_
    ( primeNode
        localKindRoot
        controlPlaneNodeName
    )
    nodeNames
  where
    primeNode localKindRoot controlPlaneNodeName nodeName = do
      runClusterCommand
        paths
        (Command.dockerMakeDirectory (Command.NodeName nodeName) nodeMountedKindRoot)
      -- Stateful platform workloads schedule on worker nodes, so replay retained runtime data only
      -- there instead of copying large claim trees into the tainted control-plane node.
      unless (nodeName == controlPlaneNodeName) $ do
        copyState <-
          startLifecyclePhase
            paths
            state
            "cluster-up"
            retainedReplayPhaseName
            ("copying retained Kind runtime data into " <> nodeName)
        copyDirectoryContentsToContainer paths (Just copyState) localKindRoot nodeName nodeMountedKindRoot
        _ <-
          startLifecyclePhase
            paths
            copyState
            "cluster-up"
            retainedReplayPhaseName
            ("retained Kind runtime copy completed for " <> nodeName)
        pure ()

primeKindNodeRegistryHosts :: Paths -> RuntimeMode -> Int -> IO ()
primeKindNodeRegistryHosts paths runtimeMode registryPortValue = do
  let namespaceDirName = "localhost:" <> show registryPortValue
      registryDirectoryInNode = "/etc/containerd/certs.d/" <> namespaceDirName
      registryHostsPath = localRegistryHostsRoot paths runtimeMode </> namespaceDirName </> "hosts.toml"
  registryHostsContents <- readFile registryHostsPath
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_ (primeNode registryDirectoryInNode registryHostsContents) nodeNames
  where
    primeNode registryDirectoryInNode registryHostsContents nodeName = do
      runClusterCommand
        paths
        (Command.dockerMakeDirectory (Command.NodeName nodeName) registryDirectoryInNode)
      runClusterCommand
        paths
        ( Command.dockerWriteFile
            (Command.NodeName nodeName)
            (registryDirectoryInNode </> "hosts.toml")
            (Command.filePayload registryHostsContents)
        )

-- | Evidence that the repo-local retained root is a detached copy target, not
-- a bind mount currently written by a live Kind node. Apple/non-bind teardown
-- must carry this witness while it stages and atomically replaces the snapshot.
newtype DetachedRetainedCopyTarget = DetachedRetainedCopyTarget RuntimeMode

-- | Evidence that every Kind worker which can host a stateful workload is
-- paused and that the PVC-to-node binding map was unchanged across the pause
-- boundary. Teardown holds this lease through the final copy and Kind delete,
-- so no retained source can write between snapshot staging and writer removal.
data FrozenRetainedSnapshotSource = FrozenRetainedSnapshotSource
  { frozenSnapshotRuntimeMode :: RuntimeMode,
    frozenSnapshotWorkerNodes :: [String],
    frozenSnapshotClaimNodeBindings :: Map.Map String String
  }

data WorkerPauseState
  = WorkerAlreadyPaused
  | WorkerNeedsPause
  deriving (Eq, Show)

withFrozenRetainedSnapshotSource ::
  Lease lock ClusterMutationLocked ->
  Paths ->
  RuntimeMode ->
  Maybe ClusterState ->
  (forall s. Lease s FrozenRetainedSnapshotSource -> IO r) ->
  IO r
withFrozenRetainedSnapshotSource lifecycleLock paths runtimeMode maybeState action = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  workerNodes <- kindWorkerNodeNames paths runtimeMode
  when (null workerNodes) $
    ioError
      ( userError
          ( "retained snapshot source freeze refused: no Kind worker nodes exist for "
              <> Text.unpack (runtimeModeId runtimeMode)
          )
      )
  beforeBindings <- snapshotClaimNodeBindings maybeState
  bracketPreservingPrimary
    (pauseSnapshotWorkers paths runtimeMode workerNodes)
    (unpauseSnapshotWorkers paths runtimeMode)
    ( \pausedWorkers -> do
        afterBindings <- snapshotClaimNodeBindings maybeState
        unless (beforeBindings == afterBindings) $
          ioError
            ( userError
                "retained snapshot source freeze refused: claim/node bindings changed while the Kind workers were being paused"
            )
        completedBindings <-
          either
            (ioError . userError)
            pure
            ( snapshotClaimNodeBindingsForPausedWorkers
                maybeState
                pausedWorkers
                afterBindings
            )
        withLease
          Acquire
            { acquireEstablish =
                pure
                  FrozenRetainedSnapshotSource
                    { frozenSnapshotRuntimeMode = runtimeMode,
                      frozenSnapshotWorkerNodes = pausedWorkers,
                      frozenSnapshotClaimNodeBindings = completedBindings
                    },
              acquireRelease = \_ -> pure ()
            }
          action
    )
  where
    snapshotClaimNodeBindings stateValue =
      case stateValue of
        Just state
          | not (null (claims state)) -> discoverClaimNodeBindings state
        _ -> pure Map.empty

pauseSnapshotWorkers :: Paths -> RuntimeMode -> [String] -> IO [String]
pauseSnapshotWorkers paths runtimeMode workerNodes =
  mask $ \restore -> go restore [] workerNodes
  where
    go _ pausedWorkers [] = pure (reverse pausedWorkers)
    go restore pausedWorkers (workerNode : remainingWorkers) = do
      pauseObservation <-
        runPauseAttemptWithRollback
          restore
          pausedWorkers
          workerNode
          ( tryClusterCommand
              paths
              (Command.dockerContainerPaused (Command.ContainerName workerNode))
          )
      case classifyWorkerPauseObservation pauseObservation of
        Right WorkerAlreadyPaused ->
          go restore (workerNode : pausedWorkers) remainingWorkers
        Right WorkerNeedsPause -> do
          pauseResult <-
            runPauseAttemptWithRollback
              restore
              pausedWorkers
              workerNode
              ( tryClusterCommand
                  paths
                  (Command.dockerPauseContainer (Command.ContainerName workerNode))
              )
          case pauseResult of
            Right _ ->
              go restore (workerNode : pausedWorkers) remainingWorkers
            Left err -> failPause pausedWorkers workerNode err
        Left err -> do
          failPause pausedWorkers workerNode err
    rollbackPause pausedWorkers workerNode =
      -- An interrupted observation leaves the current state unknown, and an
      -- interrupted pause can have applied its side effect. Mask acquisition
      -- transitions and thaw the current plus prior candidates before allowing
      -- cancellation to escape the bracket acquisition.
      unpauseSnapshotWorkers
        paths
        runtimeMode
        (workerNode : pausedWorkers)
    runPauseAttemptWithRollback restore pausedWorkers workerNode attempt = do
      attemptResult <-
        try (restore attempt) ::
          IO (Either SomeException (Either String String))
      case attemptResult of
        Right result -> pure result
        Left primaryFailure ->
          finallyPreservingPrimary
            (throwIO primaryFailure)
            (rollbackPause pausedWorkers workerNode)
    failPause pausedWorkers workerNode err =
      -- A failed or timed-out Docker call can still have applied its side
      -- effect. Probe the current worker as well as every previously paused
      -- worker so acquisition rollback does not strand an ambiguous pause.
      finallyPreservingPrimary
        ( ioError
            ( userError
                ( "retained snapshot source freeze could not pause "
                    <> workerNode
                    <> ":\n"
                    <> err
                )
            )
        )
        (rollbackPause pausedWorkers workerNode)

classifyWorkerPauseObservation :: Either String String -> Either String WorkerPauseState
classifyWorkerPauseObservation observation =
  case trim <$> observation of
    Right "true" -> Right WorkerAlreadyPaused
    Right "false" -> Right WorkerNeedsPause
    Right unexpected ->
      Left ("invalid Docker paused-state observation: " <> unexpected)
    Left err -> Left err

unpauseSnapshotWorkers :: Paths -> RuntimeMode -> [String] -> IO ()
unpauseSnapshotWorkers paths runtimeMode workerNodes =
  runCleanupsPreservingFailures
    [ unpauseWorker workerNode
    | workerNode <- workerNodes
    ]
  where
    unpauseWorker workerNode = do
      thawResult <- thawSnapshotWorker paths workerNode
      case thawResult of
        Right () -> pure ()
        Left err -> do
          presentRuntimeModes <- presentClusterRuntimeModes paths
          when (runtimeMode `elem` presentRuntimeModes) $
            ioError
              ( userError
                  ( "retained snapshot worker thaw failed while the Kind cluster is still live: "
                      <> takeWhile (/= '\n') err
                  )
              )

thawSnapshotWorker :: Paths -> String -> IO (Either String ())
thawSnapshotWorker paths workerNode = do
  pausedResult <-
    tryClusterCommand
      paths
      (Command.dockerContainerPaused (Command.ContainerName workerNode))
  case classifyWorkerPauseObservation pausedResult of
    Right WorkerNeedsPause -> pure (Right ())
    Right WorkerAlreadyPaused ->
      void
        <$> tryClusterCommand
          paths
          (Command.dockerUnpauseContainer (Command.ContainerName workerNode))
    Left err -> pure (Left err)

snapshotClaimNodeBindingsForPausedWorkers ::
  Maybe ClusterState ->
  [String] ->
  Map.Map String String ->
  Either String (Map.Map String String)
snapshotClaimNodeBindingsForPausedWorkers maybeState workerNodes claimNodeBindings =
  case maybeState of
    Nothing -> Right claimNodeBindings
    Just state ->
      completeBindings
        claimNodeBindings
        (filter (not . isPatroniManagedClaim) (claims state))
  where
    completeBindings completed [] = Right completed
    completeBindings completed (persistentClaim : remainingClaims) =
      case Map.lookup claimName completed of
        Just workerNode
          | workerNode `elem` workerNodes ->
              completeBindings completed remainingClaims
        Just nonWorkerNode ->
          Left
            ( "retained snapshot source freeze refused: claim "
                <> claimName
                <> " is bound to non-worker node "
                <> nonWorkerNode
            )
        Nothing ->
          case workerNodes of
            [onlyWorker] ->
              completeBindings
                (Map.insert claimName onlyWorker completed)
                remainingClaims
            _ ->
              Left
                ( "retained snapshot source freeze found no owning node for claim "
                    <> claimName
                )
      where
        claimName = persistentVolumeClaimName persistentClaim

withDetachedRetainedCopyTarget ::
  Lease lock ClusterMutationLocked ->
  Paths ->
  RuntimeMode ->
  (forall s. Lease s DetachedRetainedCopyTarget -> IO r) ->
  IO r
withDetachedRetainedCopyTarget lifecycleLock paths runtimeMode =
  withLease
    Acquire
      { acquireEstablish = do
          case leasePayload lifecycleLock of
            ClusterMutationLocked -> pure ()
          usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
          if usesHostBindMounts
            then
              ioError
                ( userError
                    ( "retained snapshot staging refused: "
                        <> Text.unpack (runtimeModeId runtimeMode)
                        <> " uses live host bind mounts"
                    )
                )
            else pure (DetachedRetainedCopyTarget runtimeMode),
        acquireRelease = \_ -> pure ()
      }

-- | Sprint 2.14 (managed-state-transition doctrine) — evidence that the Kind
-- cluster (the live writer over the repo-local retained-state directories) has
-- been torn down, so a retained-state scrub cannot race a live workload. The
-- payload records which runtime mode was quiesced.
newtype WriterQuiesced = WriterQuiesced RuntimeMode

-- | Establish a 'WriterQuiesced' lease by proving the Kind cluster for
-- @runtimeMode@ is gone. If it is still live, acquisition fails loud rather than
-- letting the scrub run against a live writer — so a scrub against a live writer
-- is not a constructible term. On teardown the caller deletes the cluster, this
-- lease witnesses its absence, and 'scrubRetainedStateUnderLease' then removes
-- rebuildable retained directories. On bring-up the same lease proves that no
-- existing cluster is being reused before stale local state is removed.
withWriterQuiesced ::
  Lease lock ClusterMutationLocked ->
  Paths ->
  RuntimeMode ->
  (forall s. Lease s WriterQuiesced -> IO r) ->
  IO r
withWriterQuiesced lifecycleLock paths runtimeMode =
  withLease
    Acquire
      { acquireEstablish = do
          case leasePayload lifecycleLock of
            ClusterMutationLocked -> pure ()
          stillLive <- kindClusterExists paths runtimeMode
          if stillLive
            then
              ioError
                ( userError
                    ( "retained-state scrub refused: the Kind cluster for "
                        <> Text.unpack (runtimeModeId runtimeMode)
                        <> " is still live; the retained-state writer must be quiesced"
                        <> " (cluster deleted) before scrubbing"
                    )
                )
            else pure (WriterQuiesced runtimeMode),
        acquireRelease = \_ -> pure ()
      }

-- | Evidence that none of the supported Kind runtimes for this data root is
-- live. Runtime-root cleanup is shared across modes, so a mode-local absence
-- proof is insufficient.
data AllClusterWritersQuiesced = AllClusterWritersQuiesced

withAllClusterWritersQuiesced ::
  Lease lock ClusterMutationLocked ->
  Paths ->
  (forall s. Lease s AllClusterWritersQuiesced -> IO r) ->
  IO r
withAllClusterWritersQuiesced lifecycleLock paths =
  withLease
    Acquire
      { acquireEstablish = do
          case leasePayload lifecycleLock of
            ClusterMutationLocked -> pure ()
          presentRuntimeModes <- presentClusterRuntimeModes paths
          case presentRuntimeModes of
            [] -> pure AllClusterWritersQuiesced
            _ ->
              ioError
                ( userError
                    ( "test harness runtime cleanup refused: live Infernix Kind runtimes="
                        <> List.intercalate
                          ","
                          (map (Text.unpack . runtimeModeId) presentRuntimeModes)
                    )
                ),
        acquireRelease = \_ -> pure ()
      }

-- | Clear harness-owned runtime metadata only after proving globally that no
-- Kind writer is live. A dirty operator-owned transition is preserved even if
-- Kind has not become visible yet.
cleanupHarnessRuntimeState :: Paths -> RuntimeMode -> IO ()
cleanupHarnessRuntimeState paths runtimeMode =
  withClusterLifecycleLock paths $ \lifecycleLock -> do
    _ <- requireReservationAccess paths HarnessOwned
    maybeState <- loadClusterState paths
    case maybeState of
      Just state
        | clusterOwner state == OperatorOwned,
          clusterLifecycle state /= ClusterAbsent ->
            ioError
              ( userError
                  ( "test harness runtime cleanup refused: an operator-owned "
                      <> Text.unpack (runtimeModeId (clusterRuntimeMode state))
                      <> " cluster transition is recorded while cleaning "
                      <> Text.unpack (runtimeModeId runtimeMode)
                  )
              )
      _ -> pure ()
    withAllClusterWritersQuiesced lifecycleLock paths $ \quiesced ->
      removeHarnessRuntimeStateUnderLease quiesced paths

removeHarnessRuntimeStateUnderLease ::
  Lease s AllClusterWritersQuiesced ->
  Paths ->
  IO ()
removeHarnessRuntimeStateUnderLease quiesced paths =
  case leasePayload quiesced of
    AllClusterWritersQuiesced -> do
      createDirectoryIfMissing True (runtimeRoot paths)
      entries <- listDirectory (runtimeRoot paths)
      forM_ entries $ \entry ->
        unless
          (entry `elem` ["bounded-command-activity", "locks", "secrets"])
          (removePathForcibly (runtimeRoot paths </> entry))

-- | Sprint 2.14 — the retained-state teardown scrub. It requires a
-- 'WriterQuiesced' lease as evidence that no live cluster writer remains and
-- scrubs the directories for exactly the quiesced runtime mode. This is the
-- sole retained-state scrub entry: bring-up acquires the same absence witness
-- before cleaning a stale local root, while teardown acquires it after deleting
-- the cluster.
scrubRetainedStateUnderLease :: Lease s WriterQuiesced -> Paths -> IO ()
scrubRetainedStateUnderLease lease paths =
  case leasePayload lease of
    WriterQuiesced runtimeMode -> do
      scrubStalePatroniDirectories paths runtimeMode
      scrubRetainedRegistryStorage paths runtimeMode
  where
    -- Patroni claim trees and registry publication data are rebuildable. Keeping
    -- these raw deletions local to the lease-consuming function prevents an
    -- ungated scrub from becoming a constructible cluster transition.
    scrubStalePatroniDirectories pathsValue runtimeMode =
      mapM_ scrubDirectory patroniWorkloadDirectories
      where
        patroniWorkloadDirectories =
          [ "platform" </> "infernix" </> name
          | name <-
              [ "keycloak-postgresql-instance1",
                "keycloak-postgresql-pgbackrest",
                "keycloak-postgresql-instance1",
                "keycloak-postgresql-pgbackrest"
              ]
          ]
        scrubDirectory relativePath =
          removeDirectoryWhenPresent (kindRuntimeRoot pathsValue runtimeMode </> relativePath)

    scrubRetainedRegistryStorage pathsValue runtimeMode = do
      let minioRoot = kindRuntimeRoot pathsValue runtimeMode </> "platform" </> "infernix" </> "minio"
      minioPresent <- doesDirectoryExist minioRoot
      when minioPresent $ do
        ordinalNames <- listDirectory minioRoot
        forM_ ordinalNames $ \ordinalName -> do
          let dataRoot = minioRoot </> ordinalName </> "data"
          removeDirectoryWhenPresent (dataRoot </> "infernix-registry")
          removeDirectoryWhenPresent (dataRoot </> ".minio.sys" </> "buckets" </> "infernix-registry")
          removeDirectoryWhenPresent (dataRoot </> ".minio.sys" </> "multipart")
          removeDirectoryWhenPresent (dataRoot </> ".minio.sys" </> "tmp")

    removeDirectoryWhenPresent absolutePath = do
      directoryPresent <- doesDirectoryExist absolutePath
      when directoryPresent (removePathForcibly absolutePath)

prepareKindNodeClaimDirectories :: Paths -> ClusterState -> RuntimeMode -> [PersistentClaim] -> IO ()
prepareKindNodeClaimDirectories paths _state runtimeMode persistentClaims = do
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_ (prepareOnNode nodeNames) persistentClaims
  where
    prepareOnNode nodeNames persistentClaim =
      mapM_ (prepareOnSingleNode persistentClaim) nodeNames
    prepareOnSingleNode persistentClaim nodeName = do
      let directoryPath = nodeMountedClaimPath persistentClaim
      runClusterCommand
        paths
        (Command.dockerMakeDirectory (Command.NodeName nodeName) directoryPath)
      runClusterCommand
        paths
        (Command.dockerMakeDirectoryWritable (Command.NodeName nodeName) directoryPath)
      case claimOwner persistentClaim of
        Nothing -> pure ()
        Just owner ->
          runClusterCommand
            paths
            ( Command.dockerSetDirectoryOwner
                (Command.NodeName nodeName)
                (Command.Owner owner)
                directoryPath
            )

syncKindNodeRuntimePathsToHost ::
  Lease source FrozenRetainedSnapshotSource ->
  Lease s DetachedRetainedCopyTarget ->
  Paths ->
  Maybe ClusterState ->
  IO ()
syncKindNodeRuntimePathsToHost frozenSource detachedTarget paths maybeState =
  case (leasePayload frozenSource, leasePayload detachedTarget) of
    (FrozenRetainedSnapshotSource sourceRuntimeMode workerNodes claimNodeBindings, DetachedRetainedCopyTarget runtimeMode) -> do
      unless (sourceRuntimeMode == runtimeMode) $
        ioError (userError "retained snapshot source/target runtime mismatch")
      let localKindRoot = kindRuntimeRoot paths runtimeMode
          stagingRoot = localKindRoot <> ".incoming"
          previousRoot = localKindRoot <> ".previous"
      reconcileInterruptedRetainedSnapshot paths runtimeMode
      createDirectoryIfMissing True stagingRoot
      syncedClaims <-
        syncClaimDirectoriesWhenAvailable
          paths
          stagingRoot
          maybeState
          claimNodeBindings
      unless syncedClaims $ do
        mapM_
          ( \nodeName -> do
              case maybeState of
                Just state ->
                  void $
                    startLifecyclePhase
                      paths
                      state
                      "cluster-down"
                      "replay-retained-state"
                      ("staging retained Kind runtime data from " <> nodeName)
                Nothing -> pure ()
              copyDirectoryContentsFromContainer paths nodeName nodeMountedKindRoot stagingRoot
          )
          workerNodes
      writeFile
        (snapshotCompletionMarkerPath stagingRoot)
        "version=1\n"
      commitRetainedSnapshot localKindRoot stagingRoot previousRoot
      removeFileIfExists (snapshotCompletionMarkerPath localKindRoot)

snapshotCompletionMarkerName :: FilePath
snapshotCompletionMarkerName = ".infernix-snapshot-complete-v1"

snapshotCompletionMarkerPath :: FilePath -> FilePath
snapshotCompletionMarkerPath root = root </> snapshotCompletionMarkerName

reconcileInterruptedRetainedSnapshot :: Paths -> RuntimeMode -> IO ()
reconcileInterruptedRetainedSnapshot paths runtimeMode =
  reconcileInterruptedSnapshotSwap
    localKindRoot
    (localKindRoot <> ".incoming")
    (localKindRoot <> ".previous")
  where
    localKindRoot = kindRuntimeRoot paths runtimeMode

reconcileInterruptedSnapshotSwap :: FilePath -> FilePath -> FilePath -> IO ()
reconcileInterruptedSnapshotSwap currentRoot stagingRoot previousRoot = do
  currentExists <- doesDirectoryExist currentRoot
  stagingExists <- doesDirectoryExist stagingRoot
  previousExists <- doesDirectoryExist previousRoot
  stagingComplete <-
    doesFileExist (snapshotCompletionMarkerPath stagingRoot)
  mapM_
    executeRecoveryAction
    (snapshotRecoveryPlan currentExists stagingExists previousExists stagingComplete)
  removeFileIfExists (snapshotCompletionMarkerPath currentRoot)
  where
    executeRecoveryAction recoveryAction =
      case recoveryAction of
        RestorePreviousSnapshot -> renameDirectory previousRoot currentRoot
        PromoteIncomingSnapshot -> renameDirectory stagingRoot currentRoot
        DeletePreviousSnapshot -> removePathForcibly previousRoot
        DeleteIncomingSnapshot -> removePathForcibly stagingRoot

data SnapshotRecoveryAction
  = RestorePreviousSnapshot
  | PromoteIncomingSnapshot
  | DeletePreviousSnapshot
  | DeleteIncomingSnapshot
  deriving (Eq, Show)

snapshotRecoveryPlan :: Bool -> Bool -> Bool -> Bool -> [SnapshotRecoveryAction]
snapshotRecoveryPlan currentExists incomingExists previousExists incomingComplete =
  previousAction <> incomingAction
  where
    previousAction
      | previousExists && currentExists = [DeletePreviousSnapshot]
      | previousExists = [RestorePreviousSnapshot]
      | otherwise = []
    incomingAction
      | incomingExists,
        incomingComplete,
        not currentExists,
        not previousExists =
          [PromoteIncomingSnapshot]
      | incomingExists = [DeleteIncomingSnapshot]
      | otherwise = []

commitRetainedSnapshot :: FilePath -> FilePath -> FilePath -> IO ()
commitRetainedSnapshot currentRoot stagingRoot previousRoot =
  mask $ \restore -> do
    currentExists <- doesDirectoryExist currentRoot
    promotionResult <-
      try
        ( do
            when currentExists (renameDirectory currentRoot previousRoot)
            restore (renameDirectory stagingRoot currentRoot)
        ) ::
        IO (Either SomeException ())
    case promotionResult of
      Left promotionFailure ->
        finallyPreservingPrimary
          (throwIO promotionFailure)
          restorePreviousSnapshot
      Right () -> do
        previousExists <- doesDirectoryExist previousRoot
        when previousExists (removePathForcibly previousRoot)
  where
    restorePreviousSnapshot = do
      currentExists <- doesDirectoryExist currentRoot
      previousExists <- doesDirectoryExist previousRoot
      when (previousExists && not currentExists) $
        renameDirectory previousRoot currentRoot

syncClaimDirectoriesWhenAvailable ::
  Paths ->
  FilePath ->
  Maybe ClusterState ->
  Map.Map String String ->
  IO Bool
syncClaimDirectoriesWhenAvailable paths stagingRoot maybeState claimNodeBindings =
  case maybeState of
    Just state
      | not (null (claims state)) -> do
          syncClaimDirectoriesFromOwningNodes
            paths
            stagingRoot
            state
            claimNodeBindings
          pure True
    _ -> pure False

-- | Phase 2 Sprint 2.13 follow-on (2026-05-29): operator-managed
-- Patroni Postgres claims are not retained across cluster lifecycles.
-- The Percona Operator recreates the cluster from scratch on each
-- `cluster up`, and the upstream chart + this binary reconcile the
-- demo Keycloak realm config separately. Retaining the partial
-- `/pgdata/pg18` tree from a previous interrupted run causes the
-- @postgres-startup@ init container in the new pod to crash on
-- invalid bootstrap state (surfaced by the 2026-05-29 Apple cohort
-- `infernix test all` integration replay).
isPatroniManagedClaim :: PersistentClaim -> Bool
isPatroniManagedClaim persistentClaim =
  let workloadName = Text.unpack (workload persistentClaim)
   in "keycloak-postgresql-" `List.isPrefixOf` workloadName
        || "keycloak-postgresql-" `List.isPrefixOf` workloadName

syncClaimDirectoriesFromOwningNodes ::
  Paths ->
  FilePath ->
  ClusterState ->
  Map.Map String String ->
  IO ()
syncClaimDirectoriesFromOwningNodes paths stagingRoot state claimNodeBindings = do
  let retainedClaims = filter (not . isPatroniManagedClaim) (claims state)
  mapM_
    (\persistentClaim -> syncClaimDirectoryFromOwningNode paths stagingRoot state persistentClaim claimNodeBindings)
    retainedClaims

discoverClaimNodeBindings :: ClusterState -> IO (Map.Map String String)
discoverClaimNodeBindings state = do
  result <-
    tryDiscoveredClusterCommand
      ( \_ ->
          Command.kubectlGetClaimNodeBindings (clusterKubeTarget state)
      )
  case result of
    Left err ->
      ioError
        ( userError
            ( "retained snapshot staging could not discover claim/node bindings:\n"
                <> err
            )
        )
    Right output -> pure (parseClaimNodeBindings output)

parseClaimNodeBindings :: String -> Map.Map String String
parseClaimNodeBindings output =
  Map.fromList (mapMaybe parseClaimNodeBindingLine (lines output))

syncClaimDirectoryFromOwningNode ::
  Paths ->
  FilePath ->
  ClusterState ->
  PersistentClaim ->
  Map.Map String String ->
  IO ()
syncClaimDirectoryFromOwningNode paths stagingRoot state persistentClaim claimNodeBindings =
  case Map.lookup (persistentVolumeClaimName persistentClaim) claimNodeBindings of
    Nothing ->
      ioError
        ( userError
            ( "retained snapshot staging found no owning node for claim "
                <> persistentVolumeClaimName persistentClaim
            )
        )
    Just nodeName -> do
      let containerDirectory = nodeMountedClaimPath persistentClaim
          stagedDirectory = claimDirectoryUnder stagingRoot persistentClaim
      createDirectoryIfMissing True stagedDirectory
      void $
        startLifecyclePhase
          paths
          state
          "cluster-down"
          "replay-retained-state"
          ("staging claim " <> persistentVolumeClaimName persistentClaim <> " from " <> nodeName)
      copyDirectoryContentsFromContainer paths nodeName containerDirectory stagedDirectory

parseClaimNodeBindingLine :: String -> Maybe (String, String)
parseClaimNodeBindingLine lineValue =
  case splitTabs lineValue of
    [claimNameValue, nodeNameValue]
      | not (null claimNameValue) && not (null nodeNameValue) ->
          Just (claimNameValue, nodeNameValue)
    _ -> Nothing

kindNodeNames :: Paths -> RuntimeMode -> IO [String]
kindNodeNames paths runtimeMode =
  filter (not . null) . lines
    <$> captureClusterCommand
      paths
      (Command.kindListNodes (Command.ClusterName (kindClusterName paths runtimeMode)))

kindWorkerNodeNames :: Paths -> RuntimeMode -> IO [String]
kindWorkerNodeNames paths runtimeMode =
  filter (/= kindControlPlaneNodeName paths runtimeMode) <$> kindNodeNames paths runtimeMode

copyDirectoryContentsToContainer :: Paths -> Maybe ClusterState -> FilePath -> String -> FilePath -> IO ()
copyDirectoryContentsToContainer paths _maybeState localDirectory nodeName containerDirectory = do
  hasEntries <- directoryHasEntries localDirectory
  when hasEntries copyToNode
  where
    copyToNode =
      runClusterCommand
        paths
        ( Command.dockerCopyToNode
            localDirectory
            (Command.NodeName nodeName)
            containerDirectory
        )

copyDirectoryContentsFromContainer :: Paths -> String -> FilePath -> FilePath -> IO ()
copyDirectoryContentsFromContainer paths nodeName containerDirectory localDirectory = do
  createDirectoryIfMissing True localDirectory
  copyFromNode
  where
    copyFromNode =
      runClusterCommand
        paths
        ( Command.dockerCopyFromNode
            (Command.NodeName nodeName)
            containerDirectory
            localDirectory
        )

directoryHasEntries :: FilePath -> IO Bool
directoryHasEntries directory = do
  exists <- doesDirectoryExist directory
  if exists
    then not . null <$> listDirectory directory
    else pure False

-- | The node label a fleet machine's engine Deployment is pinned by.
--
-- Phase 3 Sprint 3.16 retired the engine pod anti-affinity because it expressed
-- a correctness rule as a scheduling preference the scheduler could leave
-- unsatisfied. This is the opposite shape and the distinction is the whole
-- reason a @nodeSelector@ is acceptable here: it does not express the
-- one-engine-per-machine rule at all — the broker-side member claim does — it
-- places a machine's declared identity on the node that is that machine. A slot
-- whose node is gone leaves its engine `Pending`, which is the honest rendering
-- of "that machine is down", not a silently unsatisfied invariant.
fleetSlotLabelKey :: String
fleetSlotLabelKey = "infernix.fleet/slot"

runtimeModeLabels :: RuntimeMode -> String
runtimeModeLabels runtimeMode = case runtimeMode of
  AppleSilicon -> "infernix.runtime/mode=apple-silicon"
  LinuxCpu -> "infernix.runtime/mode=linux-cpu"
  LinuxGpu -> "infernix.runtime/mode=linux-gpu,infernix.runtime/gpu=true"

controlPlaneRuntimeModeLabels :: RuntimeMode -> String
controlPlaneRuntimeModeLabels runtimeMode = case runtimeMode of
  LinuxGpu -> "infernix.runtime/mode=linux-gpu"
  _ -> runtimeModeLabels runtimeMode

kindClusterName :: Paths -> RuntimeMode -> String
kindClusterName paths runtimeMode =
  let baseName = "infernix-" <> Text.unpack (runtimeModeId runtimeMode)
   in if dataRoot paths == repoRoot paths </> ".data"
        then baseName
        else baseName <> "-" <> show (clusterNameHash (dataRoot paths))

kindControlPlaneNodeName :: Paths -> RuntimeMode -> String
kindControlPlaneNodeName paths runtimeMode = kindClusterName paths runtimeMode <> "-control-plane"

clusterNameHash :: FilePath -> Int
clusterNameHash =
  (`mod` 100000) . List.foldl' (\acc character -> (acc * 33) + fromEnum character) 5381

currentKindEdgePort :: Paths -> RuntimeMode -> IO (Maybe Int)
currentKindEdgePort paths runtimeMode = currentKindContainerPort paths runtimeMode "30090/tcp"

-- | Phase 3 follow-on (2026-05-29): the registry-facing Kind hostPort
-- mapping is now dynamic. When the cluster already exists, the
-- supported reconcile honors the port the existing Kind container is
-- actually publishing rather than re-using a stale persisted value,
-- so the binary's registry health probe + publication path target the
-- same address operators see from the host.
currentKindRegistryPort :: Paths -> RuntimeMode -> IO (Maybe Int)
currentKindRegistryPort paths runtimeMode = currentKindContainerPort paths runtimeMode "30002/tcp"

currentKindPulsarHttpPort :: Paths -> RuntimeMode -> IO (Maybe Int)
currentKindPulsarHttpPort paths runtimeMode = currentKindContainerPort paths runtimeMode "30080/tcp"

currentKindContainerPort :: Paths -> RuntimeMode -> String -> IO (Maybe Int)
currentKindContainerPort paths runtimeMode containerSpec = do
  result <-
    tryClusterCommand
      paths
      ( Command.dockerPortLookup
          (Command.ContainerName (kindClusterName paths runtimeMode <> "-control-plane"))
          (Command.ContainerPort containerSpec)
      )
  case result of
    Left _ -> pure Nothing
    Right output ->
      pure (parsePublishedPort output)
  where
    parsePublishedPort output =
      case lines output of
        firstLine : _ ->
          case reverse (takeWhile (/= ':') (reverse firstLine)) of
            [] -> Nothing
            portText -> readMaybe portText
        [] -> Nothing

writeHelmValuesFile ::
  Paths ->
  ControlPlaneContext ->
  ClusterState ->
  Lazy.ByteString ->
  [(Int, String)] ->
  HelmDeployPhase ->
  IO FilePath
writeHelmValuesFile paths controlPlane state demoConfigPayload fleetMachineContracts deployPhase = do
  let outputPath =
        buildRoot paths
          </> ("helm-values-" <> phaseSuffix deployPhase <> "-" <> Text.unpack (runtimeModeId (clusterRuntimeMode state)) <> ".yaml")
  writeFile outputPath (renderHelmValues paths controlPlane state demoConfigPayload fleetMachineContracts deployPhase)
  pure outputPath
  where
    phaseSuffix phaseValue = case phaseValue of
      WarmupPhase -> "warmup"
      BootstrapPhase -> "bootstrap"
      RegistryFinalPhase -> "registry-final"
      KeycloakStoragePhase -> "keycloak-storage"
      PulsarReadyPhase -> "pulsar-ready"
      FinalPhase -> "final"

renderHelmChart :: Paths -> RuntimeMode -> [FilePath] -> IO FilePath
renderHelmChart paths runtimeMode valuesPaths = do
  let outputPath =
        buildRoot paths
          </> ("helm-rendered-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
  ensureHelmDependencies paths
  renderedChart <-
    captureClusterCommand
      paths
      (Command.helmTemplateInfernix valuesPaths)
  writeFile outputPath renderedChart
  pure outputPath

discoverPersistentClaims :: Paths -> FilePath -> IO [PersistentClaim]
discoverPersistentClaims _paths =
  discoverChartClaimsFile

renderHelmValues ::
  Paths ->
  ControlPlaneContext ->
  ClusterState ->
  Lazy.ByteString ->
  [(Int, String)] ->
  HelmDeployPhase ->
  String
renderHelmValues paths controlPlane state demoConfigPayload fleetMachineContracts deployPhase =
  unlines
    ( [ "runtimeMode: " <> Text.unpack (runtimeModeId (clusterRuntimeMode state)),
        "controlPlaneContext: " <> show (controlPlaneContextId controlPlane),
        "gateway:",
        "  publishedPort: " <> show (edgePort state),
        "  publishedNodePort: 30090",
        "  listenerPort: 80",
        "demoConfig:",
        "  fileName: infernix.dhall",
        "  catalogPayload: |",
        indentBlock 4 (LazyChar8.unpack demoConfigPayload),
        "demo:",
        "  enabled: " <> yamlBool demoUiEnabledValue,
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  port: 8080",
        "  image:",
        "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
        "    tag: local",
        "    pullPolicy: IfNotPresent"
      ]
        <> demoResourceValueLines
        <> [ "publication:",
             "  payloadJson: |",
             indentBlock 4 (renderPublicationState controlPlane state),
             -- Phase 7 Sprint 7.7: the supported three-role daemon split
             -- replaces the legacy `service.*` Deployment. The split workloads
             -- depend on Pulsar (`coordinator` consumes inference-request
             -- topics, runs the bootstrap subscription, and registers schemas)
             -- so we hold their replica counts at zero until `FinalPhase`
             -- brings the upstream Pulsar chart up. `demo.replicaCount` was
             -- already phase-gated for the same reason.
             "coordinator:",
             "  enabled: true",
             "  replicaCount: " <> show (repoCoordinatorReplicaCount deployPhase),
             "  image:",
             "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
             "    tag: local",
             "    pullPolicy: IfNotPresent"
           ]
        <> coordinatorResourceValueLines
        <> [ "engine:",
             "  replicaCount: " <> show (repoEngineReplicaCount deployPhase),
             "  memberName: " <> show (Text.unpack sharedEngineMemberName),
             "  image:",
             "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
             "    tag: local",
             "    pullPolicy: IfNotPresent"
           ]
        <> engineResourceValueLines
        <> fleetEngineValueLines
        <> [ "  perEngine:",
             "    enabled: " <> yamlBool (not (null perEngineNames)),
             "    replicaCount: " <> show (repoPerEngineReplicaCount deployPhase),
             "    names:",
             renderYamlStringList 6 (map Text.unpack perEngineNames),
             "    images:"
           ]
        <> perEngineImageValueLines
        <> machineContractValueLines
        <> routeHelmValues demoUiEnabledValue
        <> unsupportedMonitoringOverrides
        <> clusterConfigValueLines
        <> clusterSecretsValueLines
        <> phaseChartOverrides deployPhase
        <> bootstrapRegistryOverrides deployPhase
        <> appleHostNativeLocalOverrides deployPhase
        <> appleHostedLinuxCpuLocalOverrides deployPhase
    )
  where
    demoUiEnabledValue = clusterStateHasDemoUi state
    -- Phase 8 Sprint 8.12: the fleet block. `engine.replicaCount` is already
    -- phase-gated to one engine process; when a fleet is deployed that single
    -- shared workload is replaced by one Deployment per machine, each pinned to
    -- its own node and each started with the member identity its own machine
    -- contract declares.
    fleetMachines = clusterFleetMachines state
    fleetEngineValueLines =
      [ "  fleet:",
        "    enabled: " <> yamlBool (not (null fleetMachines)),
        -- Phase-gated for the same reason the shared engine count is: an engine
        -- consumes Pulsar topics, so no engine — fleet or not — may be asked for
        -- before the phase that brings Pulsar up.
        "    replicaCount: " <> show (if null fleetMachines then 0 else repoWorkloadEngineReplicaCount deployPhase),
        "    slotLabel: " <> fleetSlotLabelKey,
        "    machines:"
      ]
        <> concat
          [ [ "      - slot: " <> show (show slot),
              "        name: " <> show (Text.unpack memberIdValue)
            ]
          | (slot, memberIdValue) <- fleetMachines
          ]
    machineContractValueLines =
      [ "machineContracts:",
        "  name: infernix-machine-contracts",
        "  bodies:"
      ]
        <> concat
          [ [ "    m" <> show slot <> ".dhall: |",
              indentBlock 6 contractBody
            ]
          | (slot, contractBody) <- fleetMachineContracts
          ]
    -- Phase 8 Sprint 8.4: the binary renders the `cluster.dhall`
    -- ConfigMap body and the `InfernixSecrets.dhall` manifest as strings;
    -- the chart templates only `nindent` these values. No `let`/schema
    -- Dhall lives inside a chart template. The keycloak wiring resolves to
    -- the routed edge base URL when the demo UI is enabled (matching the
    -- former `finalChartOverrides` clusterConfig.keycloak override).
    resolvedKeycloakWiring :: KeycloakWiring
    resolvedKeycloakWiring
      | demoUiEnabledValue =
          defaultKeycloakWiring
            { keycloakBaseUrl = Text.pack (clusterEdgeBaseUrl paths state <> "/auth"),
              keycloakClientId = Text.pack keycloakSpaClientId,
              keycloakJwksUrl =
                Text.pack
                  ( "http://infernix-keycloak.platform.svc.cluster.local:8080/auth/realms/"
                      <> keycloakRealmName
                      <> "/protocol/openid-connect/certs"
                  )
            }
      | otherwise = defaultKeycloakWiring
    clusterConfigBody =
      renderClusterConfig
        ( defaultClusterConfig
            (Text.pack (controlPlaneContextId controlPlane))
            resolvedKeycloakWiring
        )
    clusterConfigValueLines =
      [ "clusterConfig:",
        "  body: |",
        indentBlock 4 clusterConfigBody,
        -- The operator-routes SecurityPolicy template
        -- (`securitypolicy-operator-routes.yaml`) reads
        -- `clusterConfig.keycloak.{baseUrl,realmName,clientId,jwksUrl}` from the
        -- Helm values (NOT the rendered body) to build the JWT `issuer` and
        -- `remoteJWKS`. Emit the same resolved keycloak wiring here so the
        -- SecurityPolicy issuer matches the routed edge URL Keycloak stamps into
        -- token `iss` claims; without this the routed operator routes 401 every
        -- valid token (`realmName` keeps the chart default).
        "  keycloak:",
        "    baseUrl: " <> Text.unpack (keycloakBaseUrl resolvedKeycloakWiring),
        "    clientId: " <> Text.unpack (keycloakClientId resolvedKeycloakWiring),
        "    jwksUrl: " <> Text.unpack (keycloakJwksUrl resolvedKeycloakWiring)
      ]
    clusterSecretsValueLines =
      [ "clusterSecrets:",
        "  manifest: |",
        indentBlock 4 clusterSecretsManifestBody
      ]
    clusterSecretsManifestBody =
      unlines
        [ "let MinioCredentials = { credentialsPath : Text }",
          "let KeycloakAdminCredentials = { credentialsPath : Text }",
          "let KeycloakDbCredentials = { credentialsPath : Text }",
          "in  { minio = { credentialsPath = \"/etc/infernix/secrets/minio.json\" }",
          "    , keycloakAdmin = { credentialsPath = \"/etc/infernix/secrets/keycloak-admin.json\" }",
          "    , keycloakDb = { credentialsPath = \"/etc/infernix/secrets/keycloak-db.json\" }",
          "    }"
        ]
    appleHostNativeLocalTopology =
      controlPlane == HostNative && clusterRuntimeMode state == AppleSilicon
    appleHostedLinuxCpuLocalTopology =
      isAppleHostedLinuxCpuLocalTopology paths controlPlane (clusterRuntimeMode state)
    perEngineNames = perEngineDeploymentNames (clusterRuntimeMode state)
    sharedEngineMemberName =
      sharedEngineMemberId (clusterRuntimeMode state)
    perEngineImageValueLines =
      if null perEngineNames
        then ["      {}"]
        else concatMap perEngineImageLines perEngineNames
    perEngineImageLines engineName =
      [ "      " <> Text.unpack engineName <> ":",
        "        repository: " <> Text.unpack (perEngineImageRepository (clusterRuntimeMode state) engineName),
        "        tag: local",
        "        pullPolicy: IfNotPresent"
      ]
    localPulsarJvmGc :: String
    localPulsarJvmGc =
      "-XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -XX:+DisableExplicitGC -XX:+PerfDisableSharedMem"
    demoResourceValueLines
      | appleHostedLinuxCpuLocalTopology =
          [ "  resources:",
            "    requests:",
            "      cpu: 50m",
            "      memory: 96Mi",
            "    limits:",
            "      cpu: 500m",
            "      memory: 384Mi"
          ]
      | otherwise = []
    coordinatorResourceValueLines
      | appleHostedLinuxCpuLocalTopology =
          [ "  resources:",
            "    requests:",
            "      cpu: 50m",
            "      memory: 192Mi",
            "    limits:",
            "      cpu: 500m",
            "      memory: 768Mi"
          ]
      | otherwise = []
    engineResourceValueLines
      | appleHostedLinuxCpuLocalTopology =
          [ "  resources:",
            "    requests:",
            "      cpu: 250m",
            "      memory: 768Mi",
            "    limits:",
            "      cpu: \"2\"",
            "      memory: 5120Mi"
          ]
      | clusterRuntimeMode state == LinuxGpu =
          [ "  resources:",
            "    requests:",
            "      cpu: 500m",
            "      memory: 4Gi",
            "    limits:",
            "      cpu: \"2\"",
            "      memory: 16Gi"
          ]
      | otherwise = []

    -- Phase 3 Sprint 3.16 follow-on: one process per role per machine, and
    -- the generated overlay is where that rule has to be stated. Setting
    -- `chart/values.yaml` to 1 does not deploy 1 — every phase render
    -- supersedes the base values with this overlay, so a base default the
    -- overlay contradicts is dead text on exactly the lanes the sprint's
    -- cohort gate runs on. The retired values here (demo 2, coordinator 2,
    -- linux-cpu engine 2) were the replicated topology's, and the
    -- `linux-cpu` engine 2 additionally named a two-worker validation lane
    -- that Sprint 3.16 deleted.
    repoWorkloadReplicaCount :: HelmDeployPhase -> Int
    repoWorkloadReplicaCount phaseValue = case phaseValue of
      WarmupPhase -> 0
      BootstrapPhase -> 0
      RegistryFinalPhase -> 0
      KeycloakStoragePhase -> 0
      PulsarReadyPhase -> 0
      FinalPhase -> 1
    repoCoordinatorReplicaCount :: HelmDeployPhase -> Int
    repoCoordinatorReplicaCount phaseValue = case phaseValue of
      WarmupPhase -> 0
      BootstrapPhase -> 0
      RegistryFinalPhase -> 0
      KeycloakStoragePhase -> 0
      PulsarReadyPhase -> 0
      FinalPhase -> 1
    -- On Apple Silicon the engine role runs host-native (the same-binary
    -- host daemon launched from `./.build/infernix`); the cluster substrate
    -- must not deploy an in-cluster engine pod because it would compete with
    -- host engine members for the same Metal-backed work.
    -- Linux substrates keep the in-cluster engine deployment, at exactly one
    -- process per machine: two engine pods on one box hold two KV caches and
    -- two copies of every loaded weight, and each admits work independently
    -- against the machine's whole observed capacity. Scale the fleet by
    -- adding machines, never by raising this number.
    -- \| One engine process per machine, held at zero until Pulsar is up.
    -- Shared by the single shared engine workload and by each fleet machine's
    -- own Deployment, so the two cannot drift on when an engine may start.
    repoWorkloadEngineReplicaCount :: HelmDeployPhase -> Int
    repoWorkloadEngineReplicaCount phaseValue = case (phaseValue, clusterRuntimeMode state) of
      (WarmupPhase, _) -> 0
      (BootstrapPhase, _) -> 0
      (RegistryFinalPhase, _) -> 0
      (KeycloakStoragePhase, _) -> 0
      (PulsarReadyPhase, _) -> 0
      (FinalPhase, AppleSilicon) -> 0
      (FinalPhase, _) -> 1
    -- Phase 8 Sprint 8.12: a fleet renders one Deployment per machine and no
    -- shared engine workload, so the shared count is zero rather than a value
    -- naming a workload the overlay does not render.
    repoEngineReplicaCount :: HelmDeployPhase -> Int
    repoEngineReplicaCount phaseValue
      | null fleetMachines = repoWorkloadEngineReplicaCount phaseValue
      | otherwise = 0
    -- Phase 4 Sprint 4.17 follow-on (2026-06-11): the repo-owned
    -- linux-gpu lifecycle targets the documented single-worker,
    -- single-GPU Kind lane. The static chart still supports explicit
    -- per-engine replicas for operator-provided multi-GPU values, but the
    -- generated lifecycle values keep those deployments at zero replicas
    -- so the normal final-phase Helm wait does not require every framework
    -- image to hold the one GPU concurrently. Integration and Playwright
    -- validation scale one per-engine deployment at a time when proving the
    -- routed per-engine topics.
    repoPerEngineReplicaCount :: HelmDeployPhase -> Int
    repoPerEngineReplicaCount phaseValue = case (phaseValue, clusterRuntimeMode state) of
      (WarmupPhase, _) -> 0
      (BootstrapPhase, _) -> 0
      (RegistryFinalPhase, _) -> 0
      (KeycloakStoragePhase, _) -> 0
      (PulsarReadyPhase, _) -> 0
      (FinalPhase, LinuxGpu) -> 0
      (FinalPhase, _) -> 1
    renderYamlStringList indent values =
      case values of
        [] -> replicate indent ' ' <> "[]"
        _ -> unlines (map (\value -> replicate indent ' ' <> "- " <> value) values)
    yamlBool value
      | value = "true"
      | otherwise = "false"
    unsupportedMonitoringOverrides =
      [ "pulsar:",
        "  victoria-metrics-k8s-stack:",
        "    enabled: false"
      ]
    phaseChartOverrides phaseValue = case phaseValue of
      WarmupPhase -> preFinalChartOverrides False
      BootstrapPhase -> preFinalChartOverrides False
      RegistryFinalPhase -> preFinalChartOverrides True
      KeycloakStoragePhase -> preFinalChartOverridesWithKeycloakPg True demoUiEnabledValue
      PulsarReadyPhase -> pulsarReadyChartOverrides
      FinalPhase -> finalChartOverrides
    finalChartOverrides =
      [ "upstreamCharts:",
        "  keycloakpg:",
        "    enabled: " <> yamlBool demoUiEnabledValue,
        "keycloak:",
        "  enabled: " <> yamlBool demoUiEnabledValue
      ]
        <> [ "  externalBaseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth"
           | demoUiEnabledValue
           ]
    -- Phase 8 Sprint 8.4: the `clusterConfig.keycloak` override is now
    -- baked into the binary-rendered `clusterConfig.body` (see
    -- `resolvedKeycloakWiring`), so it is no longer emitted here.
    preFinalChartOverrides envoyGatewayEnabled =
      preFinalChartOverridesWithKeycloakPg envoyGatewayEnabled False
    pulsarReadyChartOverrides =
      [ "upstreamCharts:",
        "  postgresOperator:",
        "    enabled: true",
        "  keycloakpg:",
        "    enabled: " <> yamlBool demoUiEnabledValue,
        "  minio:",
        "    enabled: true",
        "  pulsar:",
        "    enabled: true",
        "  envoyGateway:",
        "    enabled: true",
        "repoGateway:",
        "  enabled: false",
        "keycloak:",
        "  externalBaseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth",
        "  enabled: " <> yamlBool demoUiEnabledValue,
        "minio:",
        "  console:",
        "    enabled: false"
      ]
    preFinalChartOverridesWithKeycloakPg envoyGatewayEnabled keycloakPgEnabled =
      [ "upstreamCharts:",
        "  postgresOperator:",
        "    enabled: true",
        -- Phase 7 Sprint 7.1: gate the Keycloak Patroni cluster the same way
        -- Pulsar is gated. The demo-only Keycloak and its Patroni backend only
        -- roll out in FinalPhase; otherwise the warmup helm-install can hang
        -- for 30m on the Keycloak Deployment's post-install readiness probe
        -- while waiting for its Patroni replicas.
        "  keycloakpg:",
        "    enabled: " <> yamlBool keycloakPgEnabled,
        "  minio:",
        "    enabled: true",
        "  pulsar:",
        "    enabled: false",
        "  envoyGateway:",
        "    enabled: " <> yamlBool envoyGatewayEnabled,
        "repoGateway:",
        "  enabled: false",
        "keycloak:",
        "  externalBaseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth",
        "  enabled: false",
        "minio:",
        "  console:",
        "    enabled: false"
      ]
    -- Phase 3 Sprint 3.17: hold the registry down during warmup and raise it
    -- in the bootstrap phase, so the warmup Helm pass reconciles storage
    -- without racing the registry against a MinIO bucket that does not exist
    -- yet.
    --
    -- This used to gate six components independently and toggle a schema
    -- migration hook in every phase. One Deployment with no migration replaces
    -- both.
    bootstrapRegistryOverrides phaseValue = case phaseValue of
      WarmupPhase ->
        [ "registry:",
          "  replicas: 0"
        ]
      _ ->
        [ "registry:",
          "  replicas: 1"
        ]
    -- Apple host-native validation runs the Linux control-plane workloads
    -- on the operator's already-selected Colima daemon.
    --
    -- Phase 3 Sprint 3.16 promoted this block's single-replica shape from
    -- exception to chart default, so every replica and quorum line it used to
    -- carry is gone: repeating the default here would be a second place to
    -- change. What remains is the one thing that is genuinely Apple-specific —
    -- disabling the upstream metrics stack. The external-database routing
    -- this block also carried went away with the registry's database.
    appleHostNativeLocalOverrides phaseValue
      | not appleHostNativeLocalTopology = []
      | not (appleHostNativeLocalPhase phaseValue) = []
      | otherwise =
          [ "pulsar:",
            "  victoria-metrics-k8s-stack:",
            "    enabled: false"
          ]
    appleHostNativeLocalPhase phaseValue =
      case phaseValue of
        BootstrapPhase -> True
        RegistryFinalPhase -> True
        KeycloakStoragePhase -> True
        PulsarReadyPhase -> True
        FinalPhase -> True
        _ -> False
    -- The Apple-hosted linux-cpu launcher runs on the operator's existing
    -- native arm64 Docker daemon. Kind advertises one allocatable memory pool
    -- per node, but all node containers share the same Colima VM memory, so the
    -- generated validation topology must keep aggregate requests/limits below
    -- that local envelope. Replica counts are deliberately absent here: Phase 3
    -- Sprint 3.16 made one process per role per machine the shape everywhere,
    -- and a default repeated inside an override is a second place to change.
    appleHostedLinuxCpuLocalOverrides phaseValue
      | not appleHostedLinuxCpuLocalTopology = []
      | not (appleHostedLinuxCpuLocalPhase phaseValue) = []
      | otherwise =
          [ "infernixMinio:",
            "  resources:",
            "    requests:",
            "      cpu: 50m",
            "      memory: 128Mi",
            "    limits:",
            "      memory: 4Gi",
            "registry:",
            "  resources:",
            "    requests:",
            "      cpu: 75m",
            "      memory: 192Mi",
            "    limits:",
            "      memory: 2Gi",
            "keycloak:",
            "  enabled: " <> yamlBool (keycloakEnabledForPhase phaseValue),
            "  externalBaseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth",
            "  javaOptsHeap: \"-XX:InitialRAMPercentage=10 -XX:MaxRAMPercentage=50\"",
            "  resources:",
            "    requests:",
            "      cpu: 100m",
            "      memory: 384Mi",
            "    limits:",
            "      memory: 768Mi",
            "keycloakpg:",
            "  proxy:",
            "    pgBouncer:",
            "      resources:",
            "        requests:",
            "          cpu: 25m",
            "          memory: 48Mi",
            "        limits:",
            "          cpu: 100m",
            "          memory: 96Mi",
            "  backups:",
            "    pgbackrest:",
            "      containers:",
            "        pgbackrest:",
            "          resources:",
            "            requests:",
            "              cpu: 25m",
            "              memory: 96Mi",
            "            limits:",
            "              cpu: 100m",
            "              memory: 192Mi",
            "        pgbackrestConfig:",
            "          resources:",
            "            requests:",
            "              cpu: 15m",
            "              memory: 32Mi",
            "            limits:",
            "              cpu: 50m",
            "              memory: 64Mi",
            "      jobs:",
            "        resources:",
            "          requests:",
            "            cpu: 25m",
            "            memory: 96Mi",
            "          limits:",
            "            cpu: 100m",
            "            memory: 192Mi",
            "      repoHost:",
            "        resources:",
            "          requests:",
            "            cpu: 25m",
            "            memory: 96Mi",
            "          limits:",
            "            cpu: 100m",
            "            memory: 192Mi",
            "pulsar:",
            "  victoria-metrics-k8s-stack:",
            "    enabled: false",
            "  zookeeper:",
            "    configData:",
            "      PULSAR_MEM: \"-Xms32m -Xmx96m\"",
            "      PULSAR_GC: " <> show localPulsarJvmGc,
            "    resources:",
            "      requests:",
            "        memory: 128Mi",
            "        cpu: 0.05",
            "      limits:",
            "        memory: 192Mi",
            "  bookkeeper:",
            "    metadata:",
            "      resources:",
            "        requests:",
            "          memory: 128Mi",
            "          cpu: 0.05",
            "        limits:",
            "          memory: 256Mi",
            "    configData:",
            "      PULSAR_MEM: \"-Xms64m -Xmx192m -XX:MaxDirectMemorySize=128m\"",
            "      PULSAR_GC: " <> show localPulsarJvmGc,
            "      dbStorage_writeCacheMaxSizeMb: \"16\"",
            "      dbStorage_readAheadCacheMaxSizeMb: \"16\"",
            "      dbStorage_rocksDB_writeBufferSizeMB: \"8\"",
            "      dbStorage_rocksDB_blockCacheSize: \"8388608\"",
            "    resources:",
            "      requests:",
            "        memory: 256Mi",
            "        cpu: 0.1",
            "      limits:",
            "        memory: 512Mi",
            "  pulsar_metadata:",
            "    resources:",
            "      requests:",
            "        memory: 128Mi",
            "        cpu: 0.05",
            "      limits:",
            "        memory: 256Mi",
            "  broker:",
            "    resources:",
            "      requests:",
            "        memory: 256Mi",
            "        cpu: 0.1",
            "      limits:",
            "        memory: 768Mi",
            "    configData:",
            "      PULSAR_MEM: \"-Xms128m -Xmx256m -XX:MaxDirectMemorySize=128m\"",
            "      PULSAR_GC: " <> show localPulsarJvmGc,
            "  proxy:",
            "    configData:",
            "      PULSAR_MEM: \"-Xms64m -Xmx128m -XX:MaxDirectMemorySize=64m\"",
            "      PULSAR_GC: " <> show localPulsarJvmGc,
            "      httpNumThreads: \"8\"",
            "      httpServerIdleTimeout: \"7200000\"",
            "      webSocketServiceEnabled: \"true\"",
            "    resources:",
            "      requests:",
            "        memory: 160Mi",
            "        cpu: 0.1",
            "      limits:",
            "        memory: 512Mi",
            "  autorecovery:",
            "    configData:",
            "      BOOKIE_MEM: \"-Xms64m -Xmx160m -XX:MaxDirectMemorySize=64m\"",
            "      PULSAR_GC: " <> show localPulsarJvmGc,
            "    resources:",
            "      requests:",
            "        memory: 192Mi",
            "        cpu: 0.025",
            "      limits:",
            "        memory: 384Mi",
            "  toolset:",
            "    resources:",
            "      requests:",
            "        memory: 128Mi",
            "        cpu: 0.05",
            "      limits:",
            "        memory: 256Mi"
          ]
    appleHostedLinuxCpuLocalPhase phaseValue =
      case phaseValue of
        RegistryFinalPhase -> True
        KeycloakStoragePhase -> True
        PulsarReadyPhase -> True
        FinalPhase -> True
        _ -> False
    keycloakEnabledForPhase phaseValue =
      case phaseValue of
        PulsarReadyPhase -> demoUiEnabledValue
        FinalPhase -> demoUiEnabledValue
        _ -> False

-- | Phase 3 follow-on (2026-05-29): the host-side variant honors the
-- dynamic registry port chosen by 'chooseRegistryPort' (passed in from
-- 'ClusterState.registryPort'). The outer-container variant stays on
-- the fixed in-cluster NodePort because in-cluster wiring is
-- independent of the operator's host port allocations.
registryApiHost :: Paths -> RuntimeMode -> Int -> String
registryApiHost paths runtimeMode registryPortValue
  | Config.controlPlaneContext paths == OuterContainer = kindControlPlaneNodeName paths runtimeMode <> ":30002"
  | otherwise = "127.0.0.1:" <> show registryPortValue

persistentVolumeClaimName :: PersistentClaim -> String
persistentVolumeClaimName persistentClaim =
  Text.unpack (pvcName persistentClaim)

persistentVolumeName :: PersistentClaim -> String
persistentVolumeName persistentClaim =
  Text.unpack (namespace persistentClaim)
    <> "-"
    <> Text.unpack (release persistentClaim)
    <> "-"
    <> Text.unpack (workload persistentClaim)
    <> "-"
    <> show (ordinal persistentClaim)
    <> "-"
    <> Text.unpack (claim persistentClaim)

nodeMountedClaimPath :: PersistentClaim -> String
nodeMountedClaimPath persistentClaim =
  nodeMountedKindRoot
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

kindClusterExists :: Paths -> RuntimeMode -> IO Bool
kindClusterExists paths runtimeMode = do
  existingClusters <-
    lines
      <$> captureClusterCommand
        paths
        Command.kindListClusters
  pure (kindClusterName paths runtimeMode `elem` existingClusters)

clusterEdgeBaseUrl :: Paths -> ClusterState -> String
clusterEdgeBaseUrl paths state =
  "http://"
    <> clusterEdgeHost paths state
    <> ":"
    <> show (clusterEdgePort paths state)

clusterEdgeHost :: Paths -> ClusterState -> String
clusterEdgeHost paths state
  | Config.controlPlaneContext paths == OuterContainer = kindControlPlaneNodeName paths (clusterRuntimeMode state)
  | otherwise = "127.0.0.1"

clusterEdgePort :: Paths -> ClusterState -> Int
clusterEdgePort paths state
  | Config.controlPlaneContext paths == OuterContainer = 30090
  | otherwise = edgePort state

-- | Capture kubectl output for helpers that only carry 'ClusterState'. The
-- semantic constructor argument fixes the operation before the command reaches
-- the subprocess kernel.
kubectlOutput ::
  ClusterState ->
  (Command.KubeTarget -> Command.ClusterCommand) ->
  IO String
kubectlOutput state buildCommand =
  captureDiscoveredClusterCommand $ \_ ->
    buildCommand (clusterKubeTarget state)

kubectlLineCountIfReachable ::
  ClusterState ->
  (Command.KubeTarget -> Command.ClusterCommand) ->
  IO Int
kubectlLineCountIfReachable state buildCommand = do
  result <-
    tryDiscoveredClusterCommand $ \_ ->
      buildCommand (clusterKubeTarget state)
  pure $
    case result of
      Right output -> countNonEmptyLines output
      Left _ -> 0

clusterKubeTarget :: ClusterState -> Command.KubeTarget
clusterKubeTarget state = Command.KubeTarget (kubeconfigPath state)

generatedKubeTarget :: Paths -> Command.KubeTarget
generatedKubeTarget paths = Command.KubeTarget (Config.generatedKubeconfigPath paths)

clusterWorkloadRuntimeMode :: RuntimeMode -> RuntimeMode
clusterWorkloadRuntimeMode runtimeMode =
  case runtimeMode of
    LinuxGpu -> LinuxGpu
    _ -> LinuxCpu

clusterWorkloadImageRepository :: RuntimeMode -> String
clusterWorkloadImageRepository runtimeMode =
  case clusterWorkloadRuntimeMode runtimeMode of
    LinuxGpu -> "infernix-linux-gpu"
    _ -> "infernix-linux-cpu"

clusterWorkloadImageRef :: RuntimeMode -> String
clusterWorkloadImageRef runtimeMode =
  clusterWorkloadImageRepository runtimeMode <> ":local"

perEngineDeploymentNames :: RuntimeMode -> [Text.Text]
perEngineDeploymentNames runtimeMode =
  case runtimeMode of
    LinuxGpu -> frameworkEngineNamesForMode runtimeMode
    _ -> []

-- | The engine member identity the shared @infernix-engine@ Deployment is.
--
-- Phase 8 Sprint 8.13: the shared engine workload runs the launcher image, so
-- it is exactly the member that has no per-engine Deployment of its own. On
-- @linux-gpu@ the launcher image carries the native payloads and none of the
-- framework virtual environments, so it is the @native@ member and the
-- framework members are the per-engine images; on @linux-cpu@ there are no
-- per-engine Deployments at all, so it is that lane's single member.
--
-- Deriving it by subtraction rather than writing a per-mode literal is
-- deliberate: the member list and the per-engine Deployment list already exist,
-- and a third hand-written copy of the same fact is the illegal-state shape
-- Sprint 8.10 deleted from the wire. A mode whose subtraction does not leave
-- exactly one member has no shared engine workload to name, and renders the
-- empty identity the chart treats as "no @--engine-name@".
sharedEngineMemberId :: RuntimeMode -> Text.Text
sharedEngineMemberId runtimeMode =
  case declaredSharedMembers of
    [onlyMember] -> onlyMember
    _ -> Text.empty
  where
    perEngineMembers = perEngineDeploymentNames runtimeMode
    declaredSharedMembers =
      [ memberIdValue
      | memberIdValue <- map engineMemberId (engineMembersForMode runtimeMode),
        memberIdValue `notElem` perEngineMembers
      ]

-- | Phase 3 Sprint 3.12: select the native container architecture for
-- cluster workloads. Apple remains arm64, linux-gpu remains amd64
-- because CUDA arm64 is not a supported substrate, and linux-cpu uses
-- the typed host architecture from `InfernixHost.dhall`.
resolveClusterWorkloadArchitecture :: Paths -> RuntimeMode -> IO String
resolveClusterWorkloadArchitecture paths runtimeMode =
  case clusterWorkloadArchitectureForHostArchitecture runtimeMode (hostArchitectureForPaths paths) of
    Right architecture -> pure architecture
    Left message -> ioError (userError message)

clusterWorkloadArchitectureForHostArchitecture :: RuntimeMode -> Text.Text -> Either String String
clusterWorkloadArchitectureForHostArchitecture runtimeMode hostArchitecture =
  case runtimeMode of
    AppleSilicon -> Right "arm64"
    LinuxGpu -> Right "amd64"
    LinuxCpu ->
      case Text.unpack (HostConfig.normalizeHostArchitecture hostArchitecture) of
        "amd64" -> Right "amd64"
        "arm64" -> Right "arm64"
        unsupported ->
          Left
            ( "Unsupported native host architecture for linux-cpu publication: "
                <> unsupported
                <> ". Supported linux-cpu hosts are native linux/amd64 and linux/arm64."
            )

hostArchitectureForPaths :: Paths -> Text.Text
hostArchitectureForPaths paths =
  case pathsHostConfig paths of
    Just hostConfig -> HostConfig.hostArchitecture hostConfig
    Nothing -> HostConfig.normalizeHostArchitecture (Text.pack System.Info.arch)

deleteKindCluster ::
  Lease s ClusterMutationLocked ->
  KindDeleteAuthorization owner s ->
  Paths ->
  RuntimeMode ->
  IO ()
deleteKindCluster lifecycleLock authorization paths runtimeMode = do
  case leasePayload lifecycleLock of
    ClusterMutationLocked -> pure ()
  outcome <-
    withKindScratchKubeconfig paths runtimeMode $ \scratchKubeconfig ->
      do
        revalidateKindDeleteAuthorization lifecycleLock authorization paths runtimeMode
        invokeClusterCommand
          paths
          ( Command.kindDelete
              (Command.ClusterName (kindClusterName paths runtimeMode))
              (Command.kindScratchKubeconfig scratchKubeconfig)
          )
  case outcome of
    Subprocess.CommandSucceeded _ -> pure ()
    Subprocess.CommandFailedFatal _ -> do
      clusterDeleted <- waitForKindClusterAbsence paths runtimeMode
      unless clusterDeleted (failDelete outcome)
    Subprocess.CommandFailedKernel _ -> failDelete outcome
    Subprocess.CommandTimedOut _ -> failDelete outcome
  where
    failDelete failedOutcome =
      ioError
        ( userError
            ( "command failed: kind delete cluster --name "
                <> kindClusterName paths runtimeMode
                <> "\n"
                <> renderBoundedCommandOutcome failedOutcome
            )
        )

revalidateKindDeleteAuthorization ::
  Lease s ClusterMutationLocked ->
  KindDeleteAuthorization owner s ->
  Paths ->
  RuntimeMode ->
  IO ()
revalidateKindDeleteAuthorization lifecycleLock authorization paths runtimeMode =
  case authorization of
    AuthorizedClusterTeardown teardownAuthority ->
      void
        ( revalidateClusterTeardownAuthority
            lifecycleLock
            "delete the authorized Kind cluster"
            teardownAuthority
            paths
            runtimeMode
        )
    AuthorizedPreWorkloadRecovery recoveryEvidence ->
      case recoveryEvidence of
        PreWorkloadKindRecovery teardownAuthority recoveryRuntimeMode expectedLifecycle -> do
          unless (recoveryRuntimeMode == runtimeMode) $
            ioError
              ( userError
                  "pre-workload Kind recovery evidence/runtime mismatch"
              )
          (recordedState, _) <-
            revalidateClusterTeardownAuthority
              lifecycleLock
              "delete an unreadable pre-workload Kind cluster"
              teardownAuthority
              paths
              runtimeMode
          case matchingClusterState runtimeMode recordedState of
            Just state
              | preWorkloadRecoveryIntentMatches expectedLifecycle state -> pure ()
            _ ->
              ioError
                ( userError
                    "pre-workload Kind recovery refused because the retained-replay lifecycle intent changed after authorization"
                )

-- | After a terminal delete failure, observe whether the intended absence was
-- nevertheless established before surfacing the command's original failure.
waitForKindClusterAbsence :: Paths -> RuntimeMode -> IO Bool
waitForKindClusterAbsence paths runtimeMode = do
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 30 1000000) probe
  pure (Readiness.foldReadiness (const True) (const False) (const False) outcome)
  where
    probe = do
      clusterStillExists <- kindClusterExists paths runtimeMode
      if clusterStillExists
        then pure (Left (Readiness.Progress 0 1 "kind cluster still present"))
        else pure (Right ())

-- | Run one command from the closed semantic command vocabulary. The
-- subprocess compiler resolves its exact tool dependencies and derives
-- process context and policy from the command plus typed environment.
runClusterCommand ::
  Paths ->
  Command.ClusterCommand ->
  IO ()
runClusterCommand paths command = do
  result <- tryClusterCommand paths command
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        ( userError
            ( "command failed: "
                <> renderClusterCommand command
                <> "\n"
                <> err
            )
        )

captureOperatorKubectlCommand ::
  Paths ->
  Command.OperatorKubectlCommand ->
  IO String
captureOperatorKubectlCommand paths command = do
  environment <- Subprocess.clusterSubprocessEnv paths
  boundedCommand <-
    either
      (ioError . userError)
      pure
      (Subprocess.compileOperatorKubectlCommand command environment)
  outcome <- Subprocess.runBoundedCommand boundedCommand
  case commandOutcomeToEither outcome of
    Left err -> ioError (userError err)
    Right stdoutOutput -> pure stdoutOutput

captureClusterCommand ::
  Paths ->
  Command.ClusterCommand ->
  IO String
captureClusterCommand paths command = do
  result <- tryClusterCommand paths command
  case result of
    Right stdoutOutput -> pure stdoutOutput
    Left err ->
      ioError
        ( userError
            ( "command failed: "
                <> renderClusterCommand command
                <> "\n"
                <> err
            )
        )

tryDiscoveredClusterCommand ::
  (Paths -> Command.ClusterCommand) ->
  IO (Either String String)
tryDiscoveredClusterCommand buildCommand = do
  paths <- Config.discoverPaths
  tryClusterCommand paths (buildCommand paths)

runDiscoveredClusterCommand ::
  (Paths -> Command.ClusterCommand) ->
  IO ()
runDiscoveredClusterCommand buildCommand = do
  paths <- Config.discoverPaths
  runClusterCommand paths (buildCommand paths)

captureDiscoveredClusterCommand ::
  (Paths -> Command.ClusterCommand) ->
  IO String
captureDiscoveredClusterCommand buildCommand = do
  paths <- Config.discoverPaths
  captureClusterCommand paths (buildCommand paths)

renderClusterCommand :: Command.ClusterCommand -> String
renderClusterCommand =
  show . Command.clusterCommandOperation

normalizeKubeconfigServer :: ControlPlaneContext -> String -> String
normalizeKubeconfigServer _controlPlane kubeconfigContents = kubeconfigContents

ensureOuterContainerKindNetworkAccess :: Paths -> RuntimeMode -> IO ()
ensureOuterContainerKindNetworkAccess paths _runtimeMode
  | Config.controlPlaneContext paths /= OuterContainer = pure ()
  | otherwise = do
      launcherContainer <- currentLauncherContainerName
      connectResult <-
        tryClusterCommand
          paths
          (Command.dockerConnectKindNetwork (Command.ContainerName launcherContainer))
      case connectResult of
        Right _ -> pure ()
        Left err
          | "already exists" `List.isInfixOf` err -> pure ()
          | "endpoint with name" `List.isInfixOf` err -> pure ()
          | otherwise ->
              ioError
                ( userError
                    ( "linux outer-container control plane could not join the private Kind network:\n"
                        <> err
                    )
                )

-- | Phase 2 Sprint 2.13: @HOSTNAME@ env read retired. The supported
-- launcher-id discovery now reads @/etc/hostname@ directly (Docker
-- writes the container id into this file on container start), falling
-- back to the @hostname@ binary only if the file cannot be read.
currentLauncherContainerName :: IO String
currentLauncherContainerName = do
  fileHostname <- readEtcHostnameMaybe
  case fileHostname of
    Just nameValue -> pure nameValue
    Nothing -> do
      hostnameOutput <-
        captureDiscoveredClusterCommand (const Command.hostHostname)
      let hostnameValue = trim hostnameOutput
      if null hostnameValue
        then ioError (userError "linux outer-container control plane could not determine its container id")
        else pure hostnameValue

-- | Phase 2 Sprint 2.13: read @/etc/hostname@ for the supported
-- in-container hostname discovery (Docker writes the container id
-- there at startup). Returns 'Nothing' on any read error so callers
-- can fall back to the @hostname@ binary.
readEtcHostnameMaybe :: IO (Maybe String)
readEtcHostnameMaybe = do
  result <- try (readFile "/etc/hostname") :: IO (Either IOException String)
  case result of
    Left _ -> pure Nothing
    Right contents ->
      let trimmed = trim contents
       in pure (if null trimmed then Nothing else Just trimmed)

indentBlock :: Int -> String -> String
indentBlock indentWidth contents =
  unlines (map (replicate indentWidth ' ' <>) (lines contents))

countLeafEntries :: FilePath -> IO Int
countLeafEntries root = do
  rootExists <- doesDirectoryExist root
  if not rootExists
    then pure 0
    else do
      children <- listDirectory root
      counts <- mapM countChild children
      pure (sum counts)
  where
    countChild childName = do
      let childPath = root </> childName
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then countLeafEntries childPath
        else pure 1

countNonEmptyLines :: String -> Int
countNonEmptyLines =
  length . filter (not . all isSpace) . lines

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

splitTabs :: String -> [String]
splitTabs [] = [""]
splitTabs value =
  case suffix of
    [] -> [prefix]
    _ : rest -> prefix : splitTabs rest
  where
    (prefix, suffix) = break (== '\t') value

-- | Sprint 6.41 (managed-state-transition doctrine): the shared retry primitive
-- behind the cluster readiness waits (kind kubeconfig, kubernetes API, registry
-- registry, Gateway CRDs, routed/direct Pulsar surfaces). It now polls through
-- the 'Infernix.Evidence.Readiness' kernel under a required 'Deadline' derived
-- from the legacy @attempts x delayMicros@ budget, so an unbounded wait is
-- unrepresentable. The single-attempt form stays a plain one-shot (no poll).
retryCommandOutput :: Int -> Int -> String -> IO (Either String String) -> IO (Either String String)
retryCommandOutput attempts delayMicros commandLabel action
  | attempts <= 1 =
      fmap (either (\err -> Left (commandLabel <> "\n" <> err)) Right) action
  | otherwise =
      retryCommandOutputWithDeadline
        (retryDeadline attempts delayMicros)
        commandLabel
        action

retryCommandOutputWithDeadline ::
  Readiness.Deadline ->
  String ->
  IO (Either String String) ->
  IO (Either String String)
retryCommandOutputWithDeadline deadline commandLabel action = do
  -- Retain the last non-empty error across polls (the legacy @chooseError@
  -- semantics), so the timeout message keeps the useful diagnostic even when
  -- the final failing poll produced empty output.
  lastErrorRef <- newIORef ""
  let step = do
        result <- action
        case result of
          Right stdoutOutput -> pure (Right stdoutOutput)
          Left err -> do
            retained <-
              atomicModifyIORef'
                lastErrorRef
                (\previous -> let kept = if null err then previous else err in (kept, kept))
            pure (Left (Readiness.Progress 0 1 (Text.pack retained)))
  outcome <- Readiness.awaitReadiness deadline step
  pure (Readiness.foldReadiness Right onTimedOut onTimedOut outcome)
  where
    onTimedOut progress =
      Left (commandLabel <> "\n" <> Text.unpack (Readiness.progressDetail progress))

-- | Encode a legacy @attempts x delayMicros@ retry budget as a 'Deadline'.
-- Sprint 6.41 folded this into the shared 'Readiness.budgetDeadline' bridge so
-- every migrated @go n@ readiness loop derives its bound the same way.
retryDeadline :: Int -> Int -> Readiness.Deadline
retryDeadline = Readiness.budgetDeadline
