{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Closed command language for cluster lifecycle and image publication.
--
-- Production callers construct commands only through the semantic builders in
-- this module. Executable selection, CLI verbs, option ordering, templates, and
-- shell programs are owned by the renderer. The only raw-token surface is the
-- separately typed, read-only operator kubectl compatibility command.
module Infernix.Cluster.Command
  ( ClusterCommand,
    OperatorKubectlCommand,
    ClusterOperation (..),
    HostTool,
    RenderedCommandSpec,
    renderedCommandTool,
    renderedCommandRequiredTools,
    renderedCommandUsesRepositoryWorkingDirectory,
    renderedCommandEnvironment,
    renderedCommandArgv,
    renderedCommandStdin,
    renderedCommandLabel,
    clusterCommandOperation,
    validateClusterCommand,
    operatorKubectlOperation,
    renderClusterCommand,
    renderOperatorKubectlCommand,
    ClusterName (..),
    NodeName (..),
    ContainerName (..),
    Namespace (..),
    ResourceName (..),
    PodName (..),
    WorkloadRef (..),
    SecretName (..),
    PvcName (..),
    ImageRef (..),
    RegistryHost (..),
    Username (..),
    Password (..),
    Owner (..),
    ContainerPort (..),
    Url (..),
    ArchiveEntry (..),
    Architecture (..),
    EngineName (..),
    KubeTarget (..),
    KindScratchKubeconfig,
    kindScratchKubeconfig,
    InternalAddressing (..),
    Platform (..),
    GpuProbe (..),
    ImageInspectField (..),
    ContainerInspectField (..),
    PodQuery (..),
    SecretField (..),
    PostgresAction (..),
    HelmDuration (..),
    HelmUpgradeSpec (..),
    HelmDependency (..),
    HelmRepository (..),
    RegistryCredentials (..),
    RegistryAuthFile (..),
    ControlPlaneBuildSpec (..),
    EngineBuildSpec (..),
    PersistentVolumeSpec (..),
    CrdBundle,
    mkCrdBundle,
    FilePayload,
    filePayload,
    kindListClusters,
    kindCreate,
    kindGetKubeconfig,
    kindListNodes,
    kindDelete,
    nvkindCreate,
    kubectlGetNodeNames,
    kubectlGetNodeRows,
    kubectlUncordon,
    kubectlWaitAllNodesReady,
    kubectlApplyNvidiaRuntimeClass,
    kubectlGetGpuAllocatable,
    kubectlApplyNamespace,
    kubectlListStorageClasses,
    kubectlDeleteStorageClass,
    kubectlApplyInfernixStorageClass,
    kubectlDeleteHarborMigrationJob,
    kubectlListPods,
    kubectlScaleDeployment,
    kubectlWaitPodReady,
    kubectlDeletePods,
    kubectlReinitPostgresReplicas,
    kubectlRunPostgresAction,
    kubectlGetSecretField,
    kubectlGetCrd,
    kubectlPodLogs,
    kubectlRolloutStatus,
    kubectlListPostgresPvcs,
    kubectlGetPvcPhase,
    kubectlApplyPersistentVolume,
    kubectlGetClaimNodeBindings,
    kubectlApplyCrdBundle,
    helmUpgradeInfernix,
    helmUpgradeNvidiaPlugin,
    helmPullDependency,
    helmRepoAdd,
    helmTemplateInfernix,
    dockerBootstrapGpuNode,
    dockerGpuProbe,
    dockerProbeGpuUserspace,
    dockerSyncGpuUserspace,
    dockerBuildControlPlane,
    dockerBuildEngine,
    dockerInspectImage,
    dockerInspectImageField,
    dockerPullImage,
    dockerTagImage,
    dockerCrictlPull,
    dockerStreamImportImage,
    dockerCopyToNode,
    dockerCopyFromNode,
    dockerInspectContainerField,
    dockerContainerPaused,
    dockerPauseContainer,
    dockerUnpauseContainer,
    dockerMakeDirectory,
    dockerMakeDirectoryWritable,
    dockerSetDirectoryOwner,
    dockerWriteFile,
    dockerPortLookup,
    dockerConnectKindNetwork,
    hostNvidiaSmiProbe,
    hostMakeClaimWritable,
    hostSetClaimOwner,
    hostHostname,
    curlHarborHealth,
    curlPulsarClusters,
    curlPublication,
    tarListArchive,
    tarExtractEntry,
    publishInspectImage,
    publishInspectManifest,
    publishPullUpstream,
    publishVerifyRegistry,
    publishTag,
    publishPush,
    publishRemoveTag,
    publishInspectId,
    publishLogin,
    publishCopyDigest,
    operatorKubectlCommand,
  )
where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as Lazy
import Data.Char (isControl, isSpace)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Cluster.ImageFingerprint
  ( clusterImageFingerprintLabel,
    clusterImageFingerprintVersion,
    clusterImageFingerprintVersionLabel,
    clusterImageRuntimeModeLabel,
  )
import Infernix.HostTools (HostTool (..), hostToolName)
import System.FilePath (isAbsolute, normalise, pathSeparator, splitDirectories, (</>))

-- | Policy categories are selected by a semantic command, never by callers.
data ClusterOperation
  = KindReadOperation
  | KindCreateOperation
  | KindDeleteOperation
  | NvkindCreateOperation
  | KubectlReadOperation
  | KubectlApplyOperation
  | KubectlDeleteOperation
  | KubectlWaitOperation
  | KubectlExecOperation
  | OperatorKubectlOperation
  | HelmUpgradeOperation
  | HelmDependencyOperation
  | HelmRepositoryOperation
  | HelmRenderOperation
  | DockerExecOperation
  | DockerProbeOperation
  | DockerBuildOperation
  | DockerInspectOperation
  | DockerPullOperation
  | DockerTagOperation
  | DockerCopyOperation
  | DockerStreamImportOperation
  | DockerNetworkOperation
  | ContainerRuntimePullOperation
  | HostProbeOperation
  | HostMutationOperation
  | CurlProbeOperation
  | ArchiveReadOperation
  | GpuUserspaceSyncOperation
  | ImagePublicationLoginOperation
  | ImagePublicationInspectOperation
  | ImagePublicationPullOperation
  | ImagePublicationVerifyOperation
  | ImagePublicationTagOperation
  | ImagePublicationPushOperation
  | ImagePublicationRemoveOperation
  | ImagePublicationCopyOperation
  deriving (Eq, Show)

newtype ClusterName = ClusterName {unClusterName :: String}
  deriving (Eq, Show)

newtype NodeName = NodeName {unNodeName :: String}
  deriving (Eq, Show)

newtype ContainerName = ContainerName {unContainerName :: String}
  deriving (Eq, Show)

newtype Namespace = Namespace {unNamespace :: String}
  deriving (Eq, Show)

newtype ResourceName = ResourceName {unResourceName :: String}
  deriving (Eq, Show)

newtype PodName = PodName {unPodName :: String}
  deriving (Eq, Show)

newtype WorkloadRef = WorkloadRef {unWorkloadRef :: String}
  deriving (Eq, Show)

newtype SecretName = SecretName {unSecretName :: String}
  deriving (Eq, Show)

newtype PvcName = PvcName {unPvcName :: String}
  deriving (Eq, Show)

newtype ImageRef = ImageRef {unImageRef :: String}
  deriving (Eq, Show)

newtype RegistryHost = RegistryHost {unRegistryHost :: String}
  deriving (Eq, Show)

newtype Username = Username {unUsername :: String}
  deriving (Eq, Show)

newtype Password = Password {unPassword :: String}
  deriving (Eq)

newtype Owner = Owner {unOwner :: String}
  deriving (Eq, Show)

newtype ContainerPort = ContainerPort {unContainerPort :: String}
  deriving (Eq, Show)

newtype Url = Url {unUrl :: String}
  deriving (Eq, Show)

newtype ArchiveEntry = ArchiveEntry {unArchiveEntry :: FilePath}
  deriving (Eq, Show)

newtype Architecture = Architecture {unArchitecture :: String}
  deriving (Eq, Show)

newtype EngineName = EngineName {unEngineName :: String}
  deriving (Eq, Show)

newtype KubeTarget = KubeTarget {kubeconfigPath :: FilePath}
  deriving (Eq, Show)

newtype KindScratchKubeconfig = KindScratchKubeconfig FilePath
  deriving (Eq, Show)

kindScratchKubeconfig :: FilePath -> KindScratchKubeconfig
kindScratchKubeconfig = KindScratchKubeconfig

data InternalAddressing
  = ExternalAddress
  | InternalAddress
  deriving (Eq, Show)

data Platform
  = DefaultPlatform
  | LinuxPlatform !Architecture
  deriving (Eq, Show)

data GpuProbe
  = RuntimeGpuProbe
  | DefaultRuntimeDeviceMountProbe
  | GpuRuntimeDeviceMountProbe
  deriving (Eq, Show)

data ImageInspectField
  = DescriptorMediaType
  | ImageArchitecture
  | ClusterSourceFingerprint
  | ClusterFingerprintVersion
  | ClusterRuntimeMode
  deriving (Eq, Show)

data ContainerInspectField
  = KindNetworkIpv4
  | MountSourceAt !FilePath
  | ContainerPaused
  deriving (Eq, Show)

data PodQuery
  = AllPodsNoHeaders
  | HarborPostgresStartupPods
  | HarborPostgresPrimary
  | PlaywrightDemoPods
  deriving (Eq, Show)

data SecretField
  = UsernameField
  | PasswordField
  deriving (Eq, Show)

data PostgresAction
  = EnsureReplicationRole
  | DetectDirtyHarborMigration !Password
  | RepairDirtyHarborMigration !Password
  deriving (Eq)

data HelmDuration
  = HelmSeconds !Int
  | HelmMinutes !Int
  deriving (Eq, Show)

data HelmUpgradeSpec = HelmUpgradeSpec
  { helmUpgradeTarget :: !KubeTarget,
    helmUpgradeValues :: ![FilePath],
    helmUpgradeWait :: !Bool,
    helmUpgradeHooks :: !Bool,
    helmUpgradeTimeout :: !HelmDuration
  }
  deriving (Eq, Show)

data HelmDependency
  = HarborChart
  | PostgresOperatorChart
  | PostgresDatabaseChart
  | PulsarChart
  | EnvoyGatewayChart
  deriving (Eq, Show)

data HelmRepository
  = GoharborRepo
  | PerconaRepo
  | PulsarRepo
  | BitnamiRepo
  | NvidiaPluginRepo
  deriving (Eq, Show)

data RegistryCredentials = RegistryCredentials
  { registryUsername :: !Username,
    registryPassword :: !Password
  }
  deriving (Eq)

newtype RegistryAuthFile = RegistryAuthFile
  { registryAuthFilePath :: FilePath
  }
  deriving (Eq, Show)

data ControlPlaneBuildSpec = ControlPlaneBuildSpec
  { controlPlaneTargetImage :: !ImageRef,
    controlPlaneSourceFingerprint :: !String,
    controlPlaneRuntimeMode :: !String,
    controlPlaneGoImage :: !ImageRef,
    controlPlaneBaseImage :: !ImageRef
  }
  deriving (Eq, Show)

data EngineBuildSpec = EngineBuildSpec
  { engineTargetImage :: !ImageRef,
    engineSourceFingerprint :: !String,
    engineRuntimeMode :: !String,
    engineKind :: !EngineName,
    engineControlPlaneImage :: !ImageRef,
    engineBaseImage :: !ImageRef
  }
  deriving (Eq, Show)

data PersistentVolumeSpec = PersistentVolumeSpec
  { persistentVolumeName :: !ResourceName,
    persistentVolumeStorage :: !String,
    persistentVolumeClaimNamespace :: !Namespace,
    persistentVolumeClaimName :: !PvcName,
    persistentVolumeHostPath :: !FilePath
  }
  deriving (Eq, Show)

newtype CrdBundle = CrdBundle String
  deriving (Eq)

mkCrdBundle :: String -> Either String CrdBundle
mkCrdBundle payload
  | all isSpace payload = Left "CRD bundle must contain at least one non-whitespace character"
  | otherwise = Right (CrdBundle payload)

newtype FilePayload = FilePayload String
  deriving (Eq)

filePayload :: String -> FilePayload
filePayload = FilePayload

data ClusterCommand
  = KindListClusters
  | KindCreate !ClusterName !FilePath !KindScratchKubeconfig
  | KindGetKubeconfig !ClusterName !InternalAddressing
  | KindListNodes !ClusterName
  | KindDelete !ClusterName !KindScratchKubeconfig
  | NvkindCreate !ClusterName !FilePath !KindScratchKubeconfig
  | KubectlGetNodeNames !KubeTarget
  | KubectlGetNodeRows !KubeTarget
  | KubectlUncordon !KubeTarget !NodeName
  | KubectlWaitAllNodesReady !KubeTarget !Int
  | KubectlApplyNvidiaRuntimeClass !KubeTarget
  | KubectlGetGpuAllocatable !KubeTarget
  | KubectlApplyNamespace !KubeTarget !Namespace
  | KubectlListStorageClasses !KubeTarget
  | KubectlDeleteStorageClass !KubeTarget !ResourceName
  | KubectlApplyInfernixStorageClass !KubeTarget
  | KubectlDeleteHarborMigrationJob !KubeTarget
  | KubectlListPods !KubeTarget !PodQuery
  | KubectlScaleDeployment !KubeTarget !Namespace !WorkloadRef !Int
  | KubectlWaitPodReady !KubeTarget !Namespace !PodName !Int
  | KubectlDeletePods !KubeTarget !Namespace !(NonEmpty PodName)
  | KubectlReinitPostgresReplicas !KubeTarget !PodName !(NonEmpty PodName)
  | KubectlRunPostgresAction !KubeTarget !PodName !PostgresAction
  | KubectlGetSecretField !KubeTarget !Namespace !SecretName !SecretField
  | KubectlGetCrd !KubeTarget !ResourceName
  | KubectlPodLogs !KubeTarget !Namespace !PodName !Bool
  | KubectlRolloutStatus !KubeTarget !Namespace !WorkloadRef !Int
  | KubectlListPostgresPvcs !KubeTarget
  | KubectlGetPvcPhase !KubeTarget !Namespace !PvcName
  | KubectlApplyPersistentVolume !KubeTarget !PersistentVolumeSpec
  | KubectlGetClaimNodeBindings !KubeTarget
  | KubectlApplyCrdBundle !KubeTarget !CrdBundle
  | HelmUpgradeInfernix !HelmUpgradeSpec
  | HelmUpgradeNvidiaPlugin !KubeTarget !String
  | HelmPullDependency !HelmDependency !FilePath
  | HelmRepoAdd !HelmRepository
  | HelmTemplateInfernix ![FilePath]
  | DockerBootstrapGpuNode !NodeName
  | DockerGpuProbe !GpuProbe
  | DockerProbeGpuUserspace !NodeName
  | DockerSyncGpuUserspace !NodeName
  | DockerBuildControlPlane !ControlPlaneBuildSpec
  | DockerBuildEngine !EngineBuildSpec
  | DockerInspectImage !ImageRef
  | DockerInspectImageField !ImageRef !ImageInspectField
  | DockerPullImage !Platform !ImageRef
  | DockerTagImage !ImageRef !ImageRef
  | DockerCrictlPull !NodeName !ImageRef
  | DockerStreamImportImage !NodeName !ImageRef
  | DockerCopyToNode !FilePath !NodeName !FilePath
  | DockerCopyFromNode !NodeName !FilePath !FilePath
  | DockerInspectContainerField !ContainerName !ContainerInspectField
  | DockerPauseContainer !ContainerName
  | DockerUnpauseContainer !ContainerName
  | DockerMakeDirectory !NodeName !FilePath
  | DockerMakeDirectoryWritable !NodeName !FilePath
  | DockerSetDirectoryOwner !NodeName !Owner !FilePath
  | DockerWriteFile !NodeName !FilePath !FilePayload
  | DockerPortLookup !ContainerName !ContainerPort
  | DockerConnectKindNetwork !ContainerName
  | HostNvidiaSmiProbe
  | HostMakeClaimWritable !FilePath
  | HostSetClaimOwner !Owner !FilePath
  | HostHostnameCommand
  | CurlHarborHealth !Url
  | CurlPulsarClusters !Url
  | CurlPublication !Url
  | TarListArchive !FilePath
  | TarExtractEntry !FilePath !ArchiveEntry
  | PublishInspectImage !ImageRef
  | PublishInspectManifest !ImageRef
  | PublishPullUpstream !Platform !ImageRef
  | PublishVerifyRegistry !Architecture !RegistryAuthFile !ImageRef !FilePath
  | PublishTag !ImageRef !ImageRef
  | PublishPush !ImageRef
  | PublishRemoveTag !ImageRef
  | PublishInspectId !ImageRef
  | PublishLogin !RegistryHost !RegistryCredentials
  | PublishCopyDigest !Architecture !RegistryAuthFile !ImageRef !ImageRef

data OperatorKubectlCommand = OperatorKubectlCommand !KubeTarget ![String]

data RenderedCommandSpec = RenderedCommandSpec
  { renderedCommandTool :: !HostTool,
    renderedCommandRequiredTools :: ![HostTool],
    renderedCommandUsesRepositoryWorkingDirectory :: !Bool,
    renderedCommandEnvironment :: ![(String, String)],
    renderedCommandArgv :: ![String],
    renderedCommandStdin :: !String,
    renderedCommandLabel :: !String
  }
  deriving (Eq)

kindListClusters :: ClusterCommand
kindListClusters = KindListClusters

kindCreate :: ClusterName -> FilePath -> KindScratchKubeconfig -> ClusterCommand
kindCreate = KindCreate

kindGetKubeconfig :: ClusterName -> InternalAddressing -> ClusterCommand
kindGetKubeconfig = KindGetKubeconfig

kindListNodes :: ClusterName -> ClusterCommand
kindListNodes = KindListNodes

kindDelete :: ClusterName -> KindScratchKubeconfig -> ClusterCommand
kindDelete = KindDelete

nvkindCreate :: ClusterName -> FilePath -> KindScratchKubeconfig -> ClusterCommand
nvkindCreate = NvkindCreate

kubectlGetNodeNames :: KubeTarget -> ClusterCommand
kubectlGetNodeNames = KubectlGetNodeNames

kubectlGetNodeRows :: KubeTarget -> ClusterCommand
kubectlGetNodeRows = KubectlGetNodeRows

kubectlUncordon :: KubeTarget -> NodeName -> ClusterCommand
kubectlUncordon = KubectlUncordon

kubectlWaitAllNodesReady :: KubeTarget -> Int -> ClusterCommand
kubectlWaitAllNodesReady = KubectlWaitAllNodesReady

kubectlApplyNvidiaRuntimeClass :: KubeTarget -> ClusterCommand
kubectlApplyNvidiaRuntimeClass = KubectlApplyNvidiaRuntimeClass

kubectlGetGpuAllocatable :: KubeTarget -> ClusterCommand
kubectlGetGpuAllocatable = KubectlGetGpuAllocatable

kubectlApplyNamespace :: KubeTarget -> Namespace -> ClusterCommand
kubectlApplyNamespace = KubectlApplyNamespace

kubectlListStorageClasses :: KubeTarget -> ClusterCommand
kubectlListStorageClasses = KubectlListStorageClasses

kubectlDeleteStorageClass :: KubeTarget -> ResourceName -> ClusterCommand
kubectlDeleteStorageClass = KubectlDeleteStorageClass

kubectlApplyInfernixStorageClass :: KubeTarget -> ClusterCommand
kubectlApplyInfernixStorageClass = KubectlApplyInfernixStorageClass

kubectlDeleteHarborMigrationJob :: KubeTarget -> ClusterCommand
kubectlDeleteHarborMigrationJob = KubectlDeleteHarborMigrationJob

kubectlListPods :: KubeTarget -> PodQuery -> ClusterCommand
kubectlListPods = KubectlListPods

kubectlScaleDeployment :: KubeTarget -> Namespace -> WorkloadRef -> Int -> ClusterCommand
kubectlScaleDeployment = KubectlScaleDeployment

kubectlWaitPodReady :: KubeTarget -> Namespace -> PodName -> Int -> ClusterCommand
kubectlWaitPodReady = KubectlWaitPodReady

kubectlDeletePods :: KubeTarget -> Namespace -> NonEmpty PodName -> ClusterCommand
kubectlDeletePods = KubectlDeletePods

kubectlReinitPostgresReplicas ::
  KubeTarget ->
  PodName ->
  NonEmpty PodName ->
  ClusterCommand
kubectlReinitPostgresReplicas = KubectlReinitPostgresReplicas

kubectlRunPostgresAction :: KubeTarget -> PodName -> PostgresAction -> ClusterCommand
kubectlRunPostgresAction = KubectlRunPostgresAction

kubectlGetSecretField ::
  KubeTarget ->
  Namespace ->
  SecretName ->
  SecretField ->
  ClusterCommand
kubectlGetSecretField = KubectlGetSecretField

kubectlGetCrd :: KubeTarget -> ResourceName -> ClusterCommand
kubectlGetCrd = KubectlGetCrd

kubectlPodLogs :: KubeTarget -> Namespace -> PodName -> Bool -> ClusterCommand
kubectlPodLogs = KubectlPodLogs

kubectlRolloutStatus ::
  KubeTarget ->
  Namespace ->
  WorkloadRef ->
  Int ->
  ClusterCommand
kubectlRolloutStatus = KubectlRolloutStatus

kubectlListPostgresPvcs :: KubeTarget -> ClusterCommand
kubectlListPostgresPvcs = KubectlListPostgresPvcs

kubectlGetPvcPhase :: KubeTarget -> Namespace -> PvcName -> ClusterCommand
kubectlGetPvcPhase = KubectlGetPvcPhase

kubectlApplyPersistentVolume ::
  KubeTarget ->
  PersistentVolumeSpec ->
  ClusterCommand
kubectlApplyPersistentVolume = KubectlApplyPersistentVolume

kubectlGetClaimNodeBindings :: KubeTarget -> ClusterCommand
kubectlGetClaimNodeBindings = KubectlGetClaimNodeBindings

kubectlApplyCrdBundle :: KubeTarget -> CrdBundle -> ClusterCommand
kubectlApplyCrdBundle = KubectlApplyCrdBundle

helmUpgradeInfernix :: HelmUpgradeSpec -> ClusterCommand
helmUpgradeInfernix = HelmUpgradeInfernix

helmUpgradeNvidiaPlugin :: KubeTarget -> String -> ClusterCommand
helmUpgradeNvidiaPlugin = HelmUpgradeNvidiaPlugin

helmPullDependency :: HelmDependency -> FilePath -> ClusterCommand
helmPullDependency = HelmPullDependency

helmRepoAdd :: HelmRepository -> ClusterCommand
helmRepoAdd = HelmRepoAdd

helmTemplateInfernix :: [FilePath] -> ClusterCommand
helmTemplateInfernix = HelmTemplateInfernix

dockerBootstrapGpuNode :: NodeName -> ClusterCommand
dockerBootstrapGpuNode = DockerBootstrapGpuNode

dockerGpuProbe :: GpuProbe -> ClusterCommand
dockerGpuProbe = DockerGpuProbe

dockerProbeGpuUserspace :: NodeName -> ClusterCommand
dockerProbeGpuUserspace = DockerProbeGpuUserspace

dockerSyncGpuUserspace :: NodeName -> ClusterCommand
dockerSyncGpuUserspace = DockerSyncGpuUserspace

dockerBuildControlPlane :: ControlPlaneBuildSpec -> ClusterCommand
dockerBuildControlPlane = DockerBuildControlPlane

dockerBuildEngine :: EngineBuildSpec -> ClusterCommand
dockerBuildEngine = DockerBuildEngine

dockerInspectImage :: ImageRef -> ClusterCommand
dockerInspectImage = DockerInspectImage

dockerInspectImageField :: ImageRef -> ImageInspectField -> ClusterCommand
dockerInspectImageField = DockerInspectImageField

dockerPullImage :: Platform -> ImageRef -> ClusterCommand
dockerPullImage = DockerPullImage

dockerTagImage :: ImageRef -> ImageRef -> ClusterCommand
dockerTagImage = DockerTagImage

dockerCrictlPull ::
  NodeName ->
  ImageRef ->
  ClusterCommand
dockerCrictlPull = DockerCrictlPull

dockerStreamImportImage :: NodeName -> ImageRef -> ClusterCommand
dockerStreamImportImage = DockerStreamImportImage

dockerCopyToNode :: FilePath -> NodeName -> FilePath -> ClusterCommand
dockerCopyToNode = DockerCopyToNode

dockerCopyFromNode :: NodeName -> FilePath -> FilePath -> ClusterCommand
dockerCopyFromNode = DockerCopyFromNode

dockerInspectContainerField ::
  ContainerName ->
  ContainerInspectField ->
  ClusterCommand
dockerInspectContainerField = DockerInspectContainerField

dockerContainerPaused :: ContainerName -> ClusterCommand
dockerContainerPaused containerName =
  DockerInspectContainerField containerName ContainerPaused

dockerPauseContainer :: ContainerName -> ClusterCommand
dockerPauseContainer = DockerPauseContainer

dockerUnpauseContainer :: ContainerName -> ClusterCommand
dockerUnpauseContainer = DockerUnpauseContainer

dockerMakeDirectory :: NodeName -> FilePath -> ClusterCommand
dockerMakeDirectory = DockerMakeDirectory

dockerMakeDirectoryWritable :: NodeName -> FilePath -> ClusterCommand
dockerMakeDirectoryWritable = DockerMakeDirectoryWritable

dockerSetDirectoryOwner :: NodeName -> Owner -> FilePath -> ClusterCommand
dockerSetDirectoryOwner = DockerSetDirectoryOwner

dockerWriteFile :: NodeName -> FilePath -> FilePayload -> ClusterCommand
dockerWriteFile = DockerWriteFile

dockerPortLookup :: ContainerName -> ContainerPort -> ClusterCommand
dockerPortLookup = DockerPortLookup

dockerConnectKindNetwork :: ContainerName -> ClusterCommand
dockerConnectKindNetwork = DockerConnectKindNetwork

hostNvidiaSmiProbe :: ClusterCommand
hostNvidiaSmiProbe = HostNvidiaSmiProbe

hostMakeClaimWritable :: FilePath -> ClusterCommand
hostMakeClaimWritable = HostMakeClaimWritable

hostSetClaimOwner :: Owner -> FilePath -> ClusterCommand
hostSetClaimOwner = HostSetClaimOwner

hostHostname :: ClusterCommand
hostHostname = HostHostnameCommand

curlHarborHealth :: Url -> ClusterCommand
curlHarborHealth = CurlHarborHealth

curlPulsarClusters :: Url -> ClusterCommand
curlPulsarClusters = CurlPulsarClusters

curlPublication :: Url -> ClusterCommand
curlPublication = CurlPublication

tarListArchive :: FilePath -> ClusterCommand
tarListArchive = TarListArchive

tarExtractEntry :: FilePath -> ArchiveEntry -> ClusterCommand
tarExtractEntry = TarExtractEntry

publishInspectImage :: ImageRef -> ClusterCommand
publishInspectImage = PublishInspectImage

publishInspectManifest :: ImageRef -> ClusterCommand
publishInspectManifest = PublishInspectManifest

publishPullUpstream :: Platform -> ImageRef -> ClusterCommand
publishPullUpstream = PublishPullUpstream

publishVerifyRegistry ::
  Architecture ->
  RegistryAuthFile ->
  ImageRef ->
  FilePath ->
  ClusterCommand
publishVerifyRegistry = PublishVerifyRegistry

publishTag :: ImageRef -> ImageRef -> ClusterCommand
publishTag = PublishTag

publishPush :: ImageRef -> ClusterCommand
publishPush = PublishPush

publishRemoveTag :: ImageRef -> ClusterCommand
publishRemoveTag = PublishRemoveTag

publishInspectId :: ImageRef -> ClusterCommand
publishInspectId = PublishInspectId

publishLogin ::
  RegistryHost ->
  RegistryCredentials ->
  ClusterCommand
publishLogin = PublishLogin

publishCopyDigest ::
  Architecture ->
  RegistryAuthFile ->
  ImageRef ->
  ImageRef ->
  ClusterCommand
publishCopyDigest = PublishCopyDigest

-- | Validate the sole operator-supplied raw argument vector. The recorded
-- kubeconfig is always prepended by the renderer, and target-switching or
-- local-file-writing global flags are rejected in both split and
-- @--flag=value@ forms. Only an explicit observational command vocabulary can
-- inhabit 'OperatorKubectlCommand', so the read-policy compiler cannot be
-- reached with an unmanaged mutation.
operatorKubectlCommand ::
  KubeTarget ->
  [String] ->
  Either String OperatorKubectlCommand
operatorKubectlCommand target tokens
  | Left err <- validateKubeTarget target = Left err
  | null tokens = Left "kubectl compatibility command requires a subcommand"
  | any null tokens = Left "kubectl compatibility command contains an empty argument"
  | any (any isControl) tokens =
      Left "kubectl compatibility command contains a control character"
  | isConfigMutation tokens =
      Left "kubectl compatibility command cannot mutate its recorded target configuration"
  | Just _ <- List.find isForbiddenTargetToken tokens =
      Left "kubectl compatibility command cannot override its recorded target"
  | Just _ <- List.find isForbiddenLocalWriteToken tokens =
      Left "kubectl compatibility command cannot write local profile or cache data"
  | Left err <- validateOperatorKubectlReadOnly tokens = Left err
  | otherwise = Right (OperatorKubectlCommand target tokens)

validateOperatorKubectlReadOnly :: [String] -> Either String ()
validateOperatorKubectlReadOnly tokens = do
  (command, arguments) <- operatorKubectlCommandAndArguments tokens
  case command of
    "api-resources" -> Right ()
    "api-versions" -> Right ()
    "describe" -> Right ()
    "events" -> Right ()
    "explain" -> Right ()
    "get" -> Right ()
    "help" -> Right ()
    "logs" -> Right ()
    "options" -> Right ()
    "top" -> Right ()
    "version" -> Right ()
    "wait" -> Right ()
    "auth" ->
      requireOperatorKubectlSubcommand
        "auth"
        ["can-i", "whoami"]
        arguments
    "config" ->
      requireOperatorKubectlSubcommand
        "config"
        ["current-context", "get-contexts", "view"]
        arguments
    "rollout" ->
      requireOperatorKubectlSubcommand
        "rollout"
        ["history", "status"]
        arguments
    _ -> Left operatorKubectlReadOnlyError

operatorKubectlCommandAndArguments :: [String] -> Either String (String, [String])
operatorKubectlCommandAndArguments = go
  where
    go [] = Left "kubectl compatibility command requires a subcommand"
    go (token : remaining)
      | token `elem` ["-n", "--namespace"] =
          case remaining of
            [] -> Left ("kubectl compatibility option " <> token <> " requires a value")
            _namespaceValue : rest -> go rest
      | token `elem` ["-n=", "--namespace="] =
          Left ("kubectl compatibility option " <> token <> " requires a value")
      | isOperatorKubectlPrefixFlag token = go remaining
      | "-" `List.isPrefixOf` token =
          Left
            ( "kubectl compatibility command does not support prefix option "
                <> show token
            )
      | otherwise = Right (token, remaining)

isOperatorKubectlPrefixFlag :: String -> Bool
isOperatorKubectlPrefixFlag token =
  token `elem` ["-A", "--all-namespaces"]
    || any
      (`List.isPrefixOf` token)
      [ "-n=",
        "--namespace=",
        "-A=",
        "--all-namespaces="
      ]

requireOperatorKubectlSubcommand ::
  String ->
  [String] ->
  [String] ->
  Either String ()
requireOperatorKubectlSubcommand command supported arguments =
  case operatorKubectlCommandAndArguments arguments of
    Right (subcommand, _)
      | subcommand `elem` supported -> Right ()
    _ ->
      Left
        ( operatorKubectlReadOnlyError
            <> "; supported "
            <> command
            <> " subcommands are "
            <> List.intercalate ", " supported
        )

operatorKubectlReadOnlyError :: String
operatorKubectlReadOnlyError =
  "kubectl compatibility command is read-only; use `infernix cluster up` or `infernix cluster down` for managed mutations"

isForbiddenTargetToken :: String -> Bool
isForbiddenTargetToken token =
  isServerShorthand normalizedToken
    || any
      (\flag -> normalizedToken == flag || (flag <> "=") `List.isPrefixOf` normalizedToken)
      [ "--kubeconfig",
        "--kuberc",
        "--context",
        "--server",
        "--cluster",
        "--user",
        "--token",
        "--username",
        "--password",
        "--client-certificate",
        "--client-key",
        "--certificate-authority",
        "--insecure-skip-tls-verify",
        "--tls-server-name",
        "--as",
        "--as-group",
        "--as-user-extra",
        "--as-uid"
      ]
  where
    normalizedToken = normalizeOperatorKubectlFlagToken token
    isServerShorthand value =
      value == "-s"
        || "-s=" `List.isPrefixOf` value
        || ("-s" `List.isPrefixOf` value && not ("--" `List.isPrefixOf` value))

isForbiddenLocalWriteToken :: String -> Bool
isForbiddenLocalWriteToken token =
  any
    (\flag -> normalizedToken == flag || (flag <> "=") `List.isPrefixOf` normalizedToken)
    [ "--profile",
      "--profile-output",
      "--cache-dir"
    ]
  where
    normalizedToken = normalizeOperatorKubectlFlagToken token

normalizeOperatorKubectlFlagToken :: String -> String
normalizeOperatorKubectlFlagToken = map normalizeFlagCharacter
  where
    normalizeFlagCharacter character
      | character == '_' = '-'
      | otherwise = character

isConfigMutation :: [String] -> Bool
isConfigMutation tokens =
  case dropWhile (/= "config") tokens of
    [] -> False
    _config : configArguments ->
      -- Kubectl accepts persistent flags before @config@ and flags between
      -- @config@ and its subcommand. Conservatively scan the remaining
      -- arguments so neither position can hide a configuration mutation.
      any (`elem` configMutationSubcommands) configArguments

configMutationSubcommands :: [String]
configMutationSubcommands =
  [ "delete-cluster",
    "delete-context",
    "delete-user",
    "rename-context",
    "set",
    "set-cluster",
    "set-context",
    "set-credentials",
    "unset",
    "use-context"
  ]

clusterCommandOperation :: ClusterCommand -> ClusterOperation
clusterCommandOperation = \case
  KindListClusters -> KindReadOperation
  KindCreate {} -> KindCreateOperation
  KindGetKubeconfig {} -> KindReadOperation
  KindListNodes {} -> KindReadOperation
  KindDelete {} -> KindDeleteOperation
  NvkindCreate {} -> NvkindCreateOperation
  KubectlGetNodeNames {} -> KubectlReadOperation
  KubectlGetNodeRows {} -> KubectlReadOperation
  KubectlUncordon {} -> KubectlApplyOperation
  KubectlWaitAllNodesReady {} -> KubectlWaitOperation
  KubectlApplyNvidiaRuntimeClass {} -> KubectlApplyOperation
  KubectlGetGpuAllocatable {} -> KubectlReadOperation
  KubectlApplyNamespace {} -> KubectlApplyOperation
  KubectlListStorageClasses {} -> KubectlReadOperation
  KubectlDeleteStorageClass {} -> KubectlDeleteOperation
  KubectlApplyInfernixStorageClass {} -> KubectlApplyOperation
  KubectlDeleteHarborMigrationJob {} -> KubectlDeleteOperation
  KubectlListPods {} -> KubectlReadOperation
  KubectlScaleDeployment {} -> KubectlApplyOperation
  KubectlWaitPodReady {} -> KubectlWaitOperation
  KubectlDeletePods {} -> KubectlDeleteOperation
  KubectlReinitPostgresReplicas {} -> KubectlExecOperation
  KubectlRunPostgresAction {} -> KubectlExecOperation
  KubectlGetSecretField {} -> KubectlReadOperation
  KubectlGetCrd {} -> KubectlReadOperation
  KubectlPodLogs {} -> KubectlReadOperation
  KubectlRolloutStatus {} -> KubectlWaitOperation
  KubectlListPostgresPvcs {} -> KubectlReadOperation
  KubectlGetPvcPhase {} -> KubectlReadOperation
  KubectlApplyPersistentVolume {} -> KubectlApplyOperation
  KubectlGetClaimNodeBindings {} -> KubectlReadOperation
  KubectlApplyCrdBundle {} -> KubectlApplyOperation
  HelmUpgradeInfernix {} -> HelmUpgradeOperation
  HelmUpgradeNvidiaPlugin {} -> HelmUpgradeOperation
  HelmPullDependency {} -> HelmDependencyOperation
  HelmRepoAdd {} -> HelmRepositoryOperation
  HelmTemplateInfernix {} -> HelmRenderOperation
  DockerBootstrapGpuNode {} -> DockerExecOperation
  DockerGpuProbe {} -> DockerProbeOperation
  DockerProbeGpuUserspace {} -> DockerProbeOperation
  DockerSyncGpuUserspace {} -> GpuUserspaceSyncOperation
  DockerBuildControlPlane {} -> DockerBuildOperation
  DockerBuildEngine {} -> DockerBuildOperation
  DockerInspectImage {} -> DockerInspectOperation
  DockerInspectImageField {} -> DockerInspectOperation
  DockerPullImage {} -> DockerPullOperation
  DockerTagImage {} -> DockerTagOperation
  DockerCrictlPull {} -> ContainerRuntimePullOperation
  DockerStreamImportImage {} -> DockerStreamImportOperation
  DockerCopyToNode {} -> DockerCopyOperation
  DockerCopyFromNode {} -> DockerCopyOperation
  DockerInspectContainerField {} -> DockerInspectOperation
  DockerPauseContainer {} -> DockerExecOperation
  DockerUnpauseContainer {} -> DockerExecOperation
  DockerMakeDirectory {} -> DockerExecOperation
  DockerMakeDirectoryWritable {} -> DockerExecOperation
  DockerSetDirectoryOwner {} -> DockerExecOperation
  DockerWriteFile {} -> DockerExecOperation
  DockerPortLookup {} -> DockerProbeOperation
  DockerConnectKindNetwork {} -> DockerNetworkOperation
  HostNvidiaSmiProbe -> HostProbeOperation
  HostMakeClaimWritable {} -> HostMutationOperation
  HostSetClaimOwner {} -> HostMutationOperation
  HostHostnameCommand -> HostProbeOperation
  CurlHarborHealth {} -> CurlProbeOperation
  CurlPulsarClusters {} -> CurlProbeOperation
  CurlPublication {} -> CurlProbeOperation
  TarListArchive {} -> ArchiveReadOperation
  TarExtractEntry {} -> ArchiveReadOperation
  PublishInspectImage {} -> ImagePublicationInspectOperation
  PublishInspectManifest {} -> ImagePublicationInspectOperation
  PublishPullUpstream {} -> ImagePublicationPullOperation
  PublishVerifyRegistry {} -> ImagePublicationVerifyOperation
  PublishTag {} -> ImagePublicationTagOperation
  PublishPush {} -> ImagePublicationPushOperation
  PublishRemoveTag {} -> ImagePublicationRemoveOperation
  PublishInspectId {} -> ImagePublicationInspectOperation
  PublishLogin {} -> ImagePublicationLoginOperation
  PublishCopyDigest {} -> ImagePublicationCopyOperation

-- | Validate every caller-provided operand before a semantic command is
-- compiled. Renderers may concatenate validated values into fixed option
-- values, but no caller-provided value may become a new option, token, or
-- manifest document. Credential diagnostics deliberately name only the field.
validateClusterCommand :: ClusterCommand -> Either String ()
validateClusterCommand = \case
  KindListClusters -> Right ()
  KindCreate clusterName configPath scratchKubeconfig -> do
    validateClusterName clusterName
    validatePath "Kind config path" configPath
    validateKindScratchKubeconfig scratchKubeconfig
  KindGetKubeconfig clusterName _addressing ->
    validateClusterName clusterName
  KindListNodes clusterName ->
    validateClusterName clusterName
  KindDelete clusterName scratchKubeconfig -> do
    validateClusterName clusterName
    validateKindScratchKubeconfig scratchKubeconfig
  NvkindCreate clusterName configPath scratchKubeconfig -> do
    validateClusterName clusterName
    validatePath "nvkind config path" configPath
    validateKindScratchKubeconfig scratchKubeconfig
  KubectlGetNodeNames target ->
    validateKubeTarget target
  KubectlGetNodeRows target ->
    validateKubeTarget target
  KubectlUncordon target nodeName -> do
    validateKubeTarget target
    validateNodeName nodeName
  KubectlWaitAllNodesReady target timeoutSeconds -> do
    validateKubeTarget target
    validatePositive "kubectl node wait timeout" timeoutSeconds
  KubectlApplyNvidiaRuntimeClass target ->
    validateKubeTarget target
  KubectlGetGpuAllocatable target ->
    validateKubeTarget target
  KubectlApplyNamespace target namespaceName -> do
    validateKubeTarget target
    validateNamespace namespaceName
  KubectlListStorageClasses target ->
    validateKubeTarget target
  KubectlDeleteStorageClass target resourceName -> do
    validateKubeTarget target
    validateResourceName resourceName
  KubectlApplyInfernixStorageClass target ->
    validateKubeTarget target
  KubectlDeleteHarborMigrationJob target ->
    validateKubeTarget target
  KubectlListPods target _podQuery ->
    validateKubeTarget target
  KubectlScaleDeployment target namespaceName workload replicas -> do
    validateKubeTarget target
    validateNamespace namespaceName
    validateWorkloadRef workload
    require "kubectl deployment replicas must be non-negative" (replicas >= 0)
  KubectlWaitPodReady target namespaceName podName timeoutSeconds -> do
    validateKubeTarget target
    validateNamespace namespaceName
    validatePodName podName
    validatePositive "kubectl pod wait timeout" timeoutSeconds
  KubectlDeletePods target namespaceName podNames -> do
    validateKubeTarget target
    validateNamespace namespaceName
    mapM_ validatePodName (NonEmpty.toList podNames)
  KubectlReinitPostgresReplicas target primaryPod replicaPods -> do
    validateKubeTarget target
    validatePodName primaryPod
    mapM_ validatePodName (NonEmpty.toList replicaPods)
  KubectlRunPostgresAction target primaryPod action -> do
    validateKubeTarget target
    validatePodName primaryPod
    validatePostgresAction action
  KubectlGetSecretField target namespaceName secretName _secretField -> do
    validateKubeTarget target
    validateNamespace namespaceName
    validateSecretName secretName
  KubectlGetCrd target resourceName -> do
    validateKubeTarget target
    validateResourceName resourceName
  KubectlPodLogs target namespaceName podName _usePrevious -> do
    validateKubeTarget target
    validateNamespace namespaceName
    validatePodName podName
  KubectlRolloutStatus target namespaceName workload timeoutSeconds -> do
    validateKubeTarget target
    validateNamespace namespaceName
    validateWorkloadRef workload
    validatePositive "kubectl rollout timeout" timeoutSeconds
  KubectlListPostgresPvcs target ->
    validateKubeTarget target
  KubectlGetPvcPhase target namespaceName pvcName -> do
    validateKubeTarget target
    validateNamespace namespaceName
    validatePvcName pvcName
  KubectlApplyPersistentVolume target volumeSpec -> do
    validateKubeTarget target
    validatePersistentVolumeSpec volumeSpec
  KubectlGetClaimNodeBindings target ->
    validateKubeTarget target
  KubectlApplyCrdBundle target bundle -> do
    validateKubeTarget target
    validateCrdBundle bundle
  HelmUpgradeInfernix upgradeSpec ->
    validateHelmUpgradeSpec upgradeSpec
  HelmUpgradeNvidiaPlugin target pluginVersion -> do
    validateKubeTarget target
    validateAtom "NVIDIA plugin version" pluginVersion
  HelmPullDependency _dependency destinationDirectory ->
    validatePath "Helm dependency destination" destinationDirectory
  HelmRepoAdd _repository ->
    Right ()
  HelmTemplateInfernix valuesPaths ->
    mapM_ (validatePath "Helm values path") valuesPaths
  DockerBootstrapGpuNode nodeName ->
    validateNodeName nodeName
  DockerGpuProbe _probe ->
    Right ()
  DockerProbeGpuUserspace nodeName ->
    validateNodeName nodeName
  DockerSyncGpuUserspace nodeName ->
    validateNodeName nodeName
  DockerBuildControlPlane buildSpec ->
    validateControlPlaneBuildSpec buildSpec
  DockerBuildEngine buildSpec ->
    validateEngineBuildSpec buildSpec
  DockerInspectImage imageRef ->
    validateImageRef imageRef
  DockerInspectImageField imageRef _inspectField ->
    validateImageRef imageRef
  DockerPullImage platform imageRef -> do
    validatePlatform platform
    validateImageRef imageRef
  DockerTagImage sourceImage targetImage -> do
    validateImageRef sourceImage
    validateImageRef targetImage
  DockerCrictlPull nodeName imageRef -> do
    validateNodeName nodeName
    validateImageRef imageRef
  DockerStreamImportImage nodeName imageRef -> do
    validateNodeName nodeName
    validateImageRef imageRef
  DockerCopyToNode localDirectory nodeName containerDirectory -> do
    validatePath "Docker copy source path" localDirectory
    validateNodeName nodeName
    validatePath "Docker copy destination path" containerDirectory
  DockerCopyFromNode nodeName containerDirectory localDirectory -> do
    validateNodeName nodeName
    validatePath "Docker copy source path" containerDirectory
    validatePath "Docker copy destination path" localDirectory
  DockerInspectContainerField containerName inspectField -> do
    validateContainerName containerName
    validateContainerInspectField inspectField
  DockerPauseContainer containerName ->
    validateContainerName containerName
  DockerUnpauseContainer containerName ->
    validateContainerName containerName
  DockerMakeDirectory nodeName directoryPath -> do
    validateNodeName nodeName
    validatePath "Docker directory path" directoryPath
  DockerMakeDirectoryWritable nodeName directoryPath -> do
    validateNodeName nodeName
    validatePath "Docker directory path" directoryPath
  DockerSetDirectoryOwner nodeName owner directoryPath -> do
    validateNodeName nodeName
    validateOwner owner
    validatePath "Docker directory path" directoryPath
  DockerWriteFile nodeName destinationPath _payload -> do
    validateNodeName nodeName
    validatePath "Docker file destination" destinationPath
  DockerPortLookup containerName containerPort -> do
    validateContainerName containerName
    validateContainerPort containerPort
  DockerConnectKindNetwork containerName ->
    validateContainerName containerName
  HostNvidiaSmiProbe ->
    Right ()
  HostMakeClaimWritable directoryPath ->
    validatePath "claim directory path" directoryPath
  HostSetClaimOwner owner directoryPath -> do
    validateOwner owner
    validatePath "claim directory path" directoryPath
  HostHostnameCommand ->
    Right ()
  CurlHarborHealth url ->
    validateUrl url
  CurlPulsarClusters url ->
    validateUrl url
  CurlPublication url ->
    validateUrl url
  TarListArchive archivePath ->
    validateRepositoryPath "archive path" archivePath
  TarExtractEntry archivePath archiveEntry -> do
    validateRepositoryPath "archive path" archivePath
    validateArchiveEntry archiveEntry
  PublishInspectImage imageRef ->
    validateImageRef imageRef
  PublishInspectManifest imageRef ->
    validateImageRef imageRef
  PublishPullUpstream platform imageRef -> do
    validatePlatform platform
    validateImageRef imageRef
  PublishVerifyRegistry architecture authFile imageRef destinationDirectory -> do
    validateArchitecture architecture
    validatePath "registry authentication file" (registryAuthFilePath authFile)
    validateImageRef imageRef
    validatePath "registry verification directory" destinationDirectory
  PublishTag sourceImage targetImage -> do
    validateImageRef sourceImage
    validateImageRef targetImage
  PublishPush imageRef ->
    validateImageRef imageRef
  PublishRemoveTag imageRef ->
    validateImageRef imageRef
  PublishInspectId imageRef ->
    validateImageRef imageRef
  PublishLogin registryHost credentials -> do
    validateRegistryHost registryHost
    validateRegistryCredentials credentials
  PublishCopyDigest architecture authFile sourceImage targetImage -> do
    validateArchitecture architecture
    validatePath "registry authentication file" (registryAuthFilePath authFile)
    validateImageRef sourceImage
    validateImageRef targetImage

validateClusterName :: ClusterName -> Either String ()
validateClusterName = validateAtom "cluster name" . unClusterName

validateNodeName :: NodeName -> Either String ()
validateNodeName (NodeName nodeName) = do
  validateAtom "node name" nodeName
  require
    "node name must not contain ':'"
    (':' `notElem` nodeName)

validateContainerName :: ContainerName -> Either String ()
validateContainerName (ContainerName containerName) = do
  validateAtom "container name" containerName
  require
    "container name must not contain ':'"
    (':' `notElem` containerName)

validateNamespace :: Namespace -> Either String ()
validateNamespace = validateAtom "namespace" . unNamespace

validateResourceName :: ResourceName -> Either String ()
validateResourceName = validateAtom "resource name" . unResourceName

validatePodName :: PodName -> Either String ()
validatePodName = validateAtom "pod name" . unPodName

validateWorkloadRef :: WorkloadRef -> Either String ()
validateWorkloadRef = validateAtom "workload reference" . unWorkloadRef

validateSecretName :: SecretName -> Either String ()
validateSecretName = validateAtom "secret name" . unSecretName

validatePvcName :: PvcName -> Either String ()
validatePvcName = validateAtom "PVC name" . unPvcName

validateImageRef :: ImageRef -> Either String ()
validateImageRef = validateAtom "image reference" . unImageRef

validateRegistryHost :: RegistryHost -> Either String ()
validateRegistryHost = validateAtom "registry host" . unRegistryHost

validateUsername :: Username -> Either String ()
validateUsername (Username username) = do
  validateAtom "registry username" username
  require
    "registry username must not contain ':'"
    (':' `notElem` username)

validatePassword :: Password -> Either String ()
validatePassword (Password password) = do
  require "credential password must be non-empty" (not (null password))
  require
    "credential password must not contain control characters"
    (not (any isControl password))

validateOwner :: Owner -> Either String ()
validateOwner = validateAtom "filesystem owner" . unOwner

validateContainerPort :: ContainerPort -> Either String ()
validateContainerPort = validateAtom "container port" . unContainerPort

validateUrl :: Url -> Either String ()
validateUrl (Url url) = do
  validateAtom "URL" url
  require
    "URL must use http:// or https://"
    ("http://" `List.isPrefixOf` url || "https://" `List.isPrefixOf` url)

validateArchiveEntry :: ArchiveEntry -> Either String ()
validateArchiveEntry =
  validateRepositoryPath "archive entry" . unArchiveEntry

validateArchitecture :: Architecture -> Either String ()
validateArchitecture = validateAtom "architecture" . unArchitecture

validateEngineName :: EngineName -> Either String ()
validateEngineName = validateAtom "engine name" . unEngineName

validateKubeTarget :: KubeTarget -> Either String ()
validateKubeTarget = validatePath "kubeconfig path" . kubeconfigPath

validateKindScratchKubeconfig :: KindScratchKubeconfig -> Either String ()
validateKindScratchKubeconfig scratchKubeconfig = do
  let path = unKindScratchKubeconfig scratchKubeconfig
  validatePath "Kind scratch kubeconfig path" path
  require
    "Kind scratch kubeconfig path must not contain ':'"
    (':' `notElem` path)

validatePlatform :: Platform -> Either String ()
validatePlatform platform =
  case platform of
    DefaultPlatform -> Right ()
    LinuxPlatform architecture -> validateArchitecture architecture

validateContainerInspectField :: ContainerInspectField -> Either String ()
validateContainerInspectField inspectField =
  case inspectField of
    KindNetworkIpv4 -> Right ()
    MountSourceAt destinationPath ->
      validatePath "container mount destination" destinationPath
    ContainerPaused -> Right ()

validatePostgresAction :: PostgresAction -> Either String ()
validatePostgresAction action =
  case action of
    EnsureReplicationRole -> Right ()
    DetectDirtyHarborMigration password -> validatePassword password
    RepairDirtyHarborMigration password -> validatePassword password

validateHelmDuration :: HelmDuration -> Either String ()
validateHelmDuration duration =
  case duration of
    HelmSeconds seconds -> validatePositive "Helm timeout seconds" seconds
    HelmMinutes minutes -> validatePositive "Helm timeout minutes" minutes

validateHelmUpgradeSpec :: HelmUpgradeSpec -> Either String ()
validateHelmUpgradeSpec upgradeSpec = do
  validateKubeTarget (helmUpgradeTarget upgradeSpec)
  mapM_
    (validatePath "Helm values path")
    (helmUpgradeValues upgradeSpec)
  validateHelmDuration (helmUpgradeTimeout upgradeSpec)

validateRegistryCredentials :: RegistryCredentials -> Either String ()
validateRegistryCredentials credentials = do
  validateUsername (registryUsername credentials)
  validatePassword (registryPassword credentials)

validateControlPlaneBuildSpec :: ControlPlaneBuildSpec -> Either String ()
validateControlPlaneBuildSpec buildSpec = do
  validateImageRef (controlPlaneTargetImage buildSpec)
  validateAtom
    "control-plane source fingerprint"
    (controlPlaneSourceFingerprint buildSpec)
  validateAtom
    "control-plane runtime mode"
    (controlPlaneRuntimeMode buildSpec)
  validateImageRef (controlPlaneGoImage buildSpec)
  validateImageRef (controlPlaneBaseImage buildSpec)

validateEngineBuildSpec :: EngineBuildSpec -> Either String ()
validateEngineBuildSpec buildSpec = do
  validateImageRef (engineTargetImage buildSpec)
  validateAtom "engine source fingerprint" (engineSourceFingerprint buildSpec)
  validateAtom "engine runtime mode" (engineRuntimeMode buildSpec)
  validateEngineName (engineKind buildSpec)
  validateImageRef (engineControlPlaneImage buildSpec)
  validateImageRef (engineBaseImage buildSpec)

validatePersistentVolumeSpec :: PersistentVolumeSpec -> Either String ()
validatePersistentVolumeSpec volumeSpec = do
  validateResourceName (persistentVolumeName volumeSpec)
  validateAtom "persistent-volume storage" (persistentVolumeStorage volumeSpec)
  validateNamespace (persistentVolumeClaimNamespace volumeSpec)
  validatePvcName (persistentVolumeClaimName volumeSpec)
  validatePath
    "persistent-volume host path"
    (persistentVolumeHostPath volumeSpec)

validateCrdBundle :: CrdBundle -> Either String ()
validateCrdBundle (CrdBundle payload) =
  require
    "CRD bundle must contain at least one non-whitespace character"
    (not (all isSpace payload))

validateAtom :: String -> String -> Either String ()
validateAtom label value = do
  require (label <> " must be non-empty") (not (null value))
  require
    (label <> " must not contain control characters")
    (not (any isControl value))
  require
    (label <> " must not contain whitespace")
    (not (any isSpace value))
  require
    (label <> " must not begin with '-'")
    (not (isLeadingOption value))

validatePath :: String -> FilePath -> Either String ()
validatePath label path = do
  validatePathSyntax label path
  require (label <> " must be absolute") (isAbsolute path)
  require (label <> " must be normalized") (normalise path == path)
  require
    (label <> " must not name the filesystem root")
    (normalise path /= [pathSeparator])

validateRepositoryPath :: String -> FilePath -> Either String ()
validateRepositoryPath label path = do
  validatePathSyntax label path
  require (label <> " must be relative") (not (isAbsolute path))
  require (label <> " must be normalized") (normalise path == path)
  require (label <> " must not be '.'") (path /= ".")
  require
    (label <> " must not traverse parent directories")
    (".." `notElem` splitDirectories path)

validatePathSyntax :: String -> FilePath -> Either String ()
validatePathSyntax label path = do
  require (label <> " must be non-empty") (not (null path))
  require
    (label <> " must not be whitespace-only")
    (not (all isSpace path))
  require
    (label <> " must not contain control characters")
    (not (any isControl path))
  require
    (label <> " must not begin with '-'")
    (not (isLeadingOption path))

validatePositive :: String -> Int -> Either String ()
validatePositive label value =
  require (label <> " must be positive") (value > 0)

isLeadingOption :: String -> Bool
isLeadingOption ('-' : _) = True
isLeadingOption _ = False

require :: String -> Bool -> Either String ()
require message condition
  | condition = Right ()
  | otherwise = Left message

operatorKubectlOperation :: OperatorKubectlCommand -> ClusterOperation
operatorKubectlOperation _ = OperatorKubectlOperation

renderClusterCommand ::
  (HostTool -> FilePath) ->
  ClusterCommand ->
  RenderedCommandSpec
renderClusterCommand resolveTool = \case
  KindListClusters ->
    kindCommandSpec ["get", "clusters"] ""
  KindCreate clusterName configPath scratchKubeconfig ->
    withKindScratchKubeconfig scratchKubeconfig $
      kindCommandSpec
        ["create", "cluster", "--name", unClusterName clusterName, "--config", configPath]
        ""
  KindGetKubeconfig clusterName addressing ->
    kindCommandSpec
      ( ["get", "kubeconfig", "--name", unClusterName clusterName]
          <> case addressing of
            ExternalAddress -> []
            InternalAddress -> ["--internal"]
      )
      ""
  KindListNodes clusterName ->
    kindCommandSpec ["get", "nodes", "--name", unClusterName clusterName] ""
  KindDelete clusterName scratchKubeconfig ->
    withKindScratchKubeconfig scratchKubeconfig $
      kindCommandSpec ["delete", "cluster", "--name", unClusterName clusterName] ""
  NvkindCreate clusterName configPath scratchKubeconfig ->
    withNvkindEnvironment scratchKubeconfig $
      nvkindCommandSpec
        [ "cluster",
          "create",
          "--name",
          unClusterName clusterName,
          "--config-template",
          configPath,
          "--kubeconfig",
          unKindScratchKubeconfig scratchKubeconfig,
          "--wait",
          "5m"
        ]
        ""
  KubectlGetNodeNames target ->
    kubectlSpec target ["get", "nodes", "-o", "name"] ""
  KubectlGetNodeRows target ->
    kubectlSpec target ["get", "nodes", "--no-headers"] ""
  KubectlUncordon target nodeName ->
    kubectlSpec target ["uncordon", unNodeName nodeName] ""
  KubectlWaitAllNodesReady target timeoutSeconds ->
    kubectlSpec
      target
      [ "wait",
        "--for=condition=Ready",
        "node",
        "--all",
        "--timeout=" <> show timeoutSeconds <> "s"
      ]
      ""
  KubectlApplyNvidiaRuntimeClass target ->
    kubectlSpec target ["apply", "-f", "-"] nvidiaRuntimeClassManifest
  KubectlGetGpuAllocatable target ->
    kubectlSpec
      target
      [ "get",
        "nodes",
        "-l",
        "infernix.runtime/gpu=true",
        "-o",
        "jsonpath={range .items[*]}{.status.allocatable.nvidia\\.com/gpu}{\"\\n\"}{end}"
      ]
      ""
  KubectlApplyNamespace target namespaceName ->
    kubectlSpec
      target
      ["apply", "-f", "-"]
      (renderNamespaceManifest namespaceName)
  KubectlListStorageClasses target ->
    kubectlSpec target ["get", "storageclass", "-o", "name"] ""
  KubectlDeleteStorageClass target storageClassName ->
    kubectlSpec target ["delete", unResourceName storageClassName] ""
  KubectlApplyInfernixStorageClass target ->
    kubectlSpec target ["apply", "-f", "-"] infernixStorageClassManifest
  KubectlDeleteHarborMigrationJob target ->
    kubectlSpec
      target
      [ "-n",
        "platform",
        "delete",
        "job",
        "migration-job",
        "--ignore-not-found=true",
        "--wait=true"
      ]
      ""
  KubectlListPods target podQuery ->
    kubectlSpec target (podQueryArguments podQuery) ""
  KubectlScaleDeployment target namespaceName workload replicas ->
    kubectlSpec
      target
      [ "-n",
        unNamespace namespaceName,
        "scale",
        unWorkloadRef workload,
        "--replicas=" <> show replicas
      ]
      ""
  KubectlWaitPodReady target namespaceName podName timeoutSeconds ->
    kubectlSpec
      target
      [ "-n",
        unNamespace namespaceName,
        "wait",
        "--for=condition=Ready",
        "pod/" <> unPodName podName,
        "--timeout",
        show timeoutSeconds <> "s"
      ]
      ""
  KubectlDeletePods target namespaceName podNames ->
    kubectlSpec
      target
      ( ["-n", unNamespace namespaceName, "delete", "pod"]
          <> map unPodName (NonEmpty.toList podNames)
          <> ["--ignore-not-found=true", "--wait=false"]
      )
      ""
  KubectlReinitPostgresReplicas target primaryPod replicaPods ->
    kubectlSpec
      target
      ( [ "-n",
          "platform",
          "exec",
          unPodName primaryPod,
          "-c",
          "database",
          "--",
          "patronictl",
          "-k",
          "reinit",
          "harbor-postgresql-ha"
        ]
          <> map unPodName (NonEmpty.toList replicaPods)
          <> ["--force", "--wait", "--from-leader"]
      )
      ""
  KubectlRunPostgresAction target primaryPod action ->
    renderPostgresAction target primaryPod action
  KubectlGetSecretField target namespaceName secretName secretField ->
    kubectlSpec
      target
      [ "-n",
        unNamespace namespaceName,
        "get",
        "secret",
        unSecretName secretName,
        "-o",
        "jsonpath={.data." <> renderSecretField secretField <> "}"
      ]
      ""
  KubectlGetCrd target crdName ->
    kubectlSpec target ["get", "crd", unResourceName crdName] ""
  KubectlPodLogs target namespaceName podName usePrevious ->
    kubectlSpec
      target
      ( [ "--request-timeout=10s",
          "-n",
          unNamespace namespaceName,
          "logs",
          unPodName podName,
          "--tail=200"
        ]
          <> ["--previous" | usePrevious]
      )
      ""
  KubectlRolloutStatus target namespaceName workload timeoutSeconds ->
    kubectlSpec
      target
      [ "-n",
        unNamespace namespaceName,
        "rollout",
        "status",
        unWorkloadRef workload,
        "--timeout",
        show timeoutSeconds <> "s"
      ]
      ""
  KubectlListPostgresPvcs target ->
    kubectlSpec
      target
      [ "get",
        "pvc",
        "-A",
        "-l",
        "postgres-operator.crunchydata.com/cluster",
        "-o",
        "json"
      ]
      ""
  KubectlGetPvcPhase target namespaceName pvcName ->
    kubectlSpec
      target
      [ "-n",
        unNamespace namespaceName,
        "get",
        "pvc",
        unPvcName pvcName,
        "-o",
        "jsonpath={.status.phase}"
      ]
      ""
  KubectlApplyPersistentVolume target volumeSpec ->
    kubectlSpec target ["apply", "-f", "-"] (renderPersistentVolumeManifest volumeSpec)
  KubectlGetClaimNodeBindings target ->
    kubectlSpec
      target
      [ "get",
        "pods",
        "-A",
        "-o",
        claimNodeBindingsTemplate
      ]
      ""
  KubectlApplyCrdBundle target (CrdBundle payload) ->
    kubectlSpec
      target
      ["apply", "--server-side", "--force-conflicts", "-f", "-"]
      payload
  HelmUpgradeInfernix upgradeSpec ->
    fromRepositoryRoot $
      commandSpec HostHelm (renderHelmUpgrade upgradeSpec) ""
  HelmUpgradeNvidiaPlugin target pluginVersion ->
    commandSpec
      HostHelm
      [ "upgrade",
        "-i",
        "nvidia-device-plugin",
        "nvdp/nvidia-device-plugin",
        "--namespace",
        "nvidia",
        "--create-namespace",
        "--kubeconfig",
        kubeconfigPath target,
        "--version",
        pluginVersion,
        "--values",
        "-",
        "--wait",
        "--timeout",
        "10m"
      ]
      nvidiaDevicePluginValues
  HelmPullDependency dependency destinationDirectory ->
    commandSpec HostHelm (helmDependencyArguments dependency destinationDirectory) ""
  HelmRepoAdd repository ->
    let (repositoryName, repositoryUrl) = helmRepositoryDefinition repository
     in fromRepositoryRoot $
          commandSpec
            HostHelm
            ["repo", "add", "--force-update", repositoryName, repositoryUrl]
            ""
  HelmTemplateInfernix valuesPaths ->
    fromRepositoryRoot $
      commandSpec
        HostHelm
        ( ["template", "infernix", "chart", "--namespace", "platform"]
            <> concatMap (\valuesPath -> ["-f", valuesPath]) valuesPaths
        )
        ""
  DockerBootstrapGpuNode nodeName ->
    commandSpec
      HostDocker
      ["exec", unNodeName nodeName, "bash", "-c", gpuNodeBootstrapScript]
      ""
  DockerGpuProbe probe ->
    commandSpec HostDocker (dockerGpuProbeArguments probe) ""
  DockerProbeGpuUserspace nodeName ->
    commandSpec
      HostDocker
      [ "exec",
        unNodeName nodeName,
        "bash",
        "-lc",
        "nvidia-container-cli info >/dev/null 2>&1"
      ]
      ""
  DockerSyncGpuUserspace nodeName ->
    commandSpecWithRequiredTools
      HostBash
      [HostDocker]
      [ "-lc",
        gpuUserspaceSyncScript,
        "infernix-gpu-userspace-sync",
        resolveTool HostDocker,
        "nvidia/cuda:12.4.1-base-ubuntu22.04",
        unNodeName nodeName
      ]
      ""
  DockerBuildControlPlane buildSpec ->
    fromRepositoryRoot $
      commandSpec HostDocker (controlPlaneBuildArguments buildSpec) ""
  DockerBuildEngine buildSpec ->
    fromRepositoryRoot $
      commandSpec HostDocker (engineBuildArguments buildSpec) ""
  DockerInspectImage imageRef ->
    commandSpec HostDocker ["image", "inspect", unImageRef imageRef] ""
  DockerInspectImageField imageRef inspectField ->
    commandSpec
      HostDocker
      [ "image",
        "inspect",
        unImageRef imageRef,
        "--format",
        renderImageInspectField inspectField
      ]
      ""
  DockerPullImage platform imageRef ->
    commandSpec HostDocker (dockerPullArguments platform imageRef) ""
  DockerTagImage sourceImage targetImage ->
    commandSpec
      HostDocker
      ["tag", unImageRef sourceImage, unImageRef targetImage]
      ""
  DockerCrictlPull nodeName imageRef ->
    commandSpec
      HostDocker
      [ "exec",
        unNodeName nodeName,
        "crictl",
        "--runtime-endpoint",
        "unix:///run/containerd/containerd.sock",
        "pull",
        unImageRef imageRef
      ]
      ""
  DockerStreamImportImage nodeName imageRef ->
    commandSpecWithRequiredTools
      HostBash
      [HostDocker]
      [ "-lc",
        dockerStreamImportScript,
        "infernix-image-stream",
        resolveTool HostDocker,
        unImageRef imageRef,
        unNodeName nodeName
      ]
      ""
  DockerCopyToNode localDirectory nodeName containerDirectory ->
    commandSpec
      HostDocker
      ["cp", localDirectory </> ".", unNodeName nodeName <> ":" <> containerDirectory]
      ""
  DockerCopyFromNode nodeName containerDirectory localDirectory ->
    commandSpec
      HostDocker
      ["cp", (unNodeName nodeName <> ":" <> containerDirectory) </> ".", localDirectory]
      ""
  DockerInspectContainerField containerName inspectField ->
    commandSpec
      HostDocker
      [ "inspect",
        unContainerName containerName,
        "--format",
        renderContainerInspectField inspectField
      ]
      ""
  DockerPauseContainer containerName ->
    commandSpec HostDocker ["pause", unContainerName containerName] ""
  DockerUnpauseContainer containerName ->
    commandSpec HostDocker ["unpause", unContainerName containerName] ""
  DockerMakeDirectory nodeName directoryPath ->
    commandSpec
      HostDocker
      ["exec", unNodeName nodeName, "mkdir", "-p", directoryPath]
      ""
  DockerMakeDirectoryWritable nodeName directoryPath ->
    commandSpec
      HostDocker
      ["exec", unNodeName nodeName, "chmod", "-R", "a+rwX", directoryPath]
      ""
  DockerSetDirectoryOwner nodeName owner directoryPath ->
    commandSpec
      HostDocker
      ["exec", unNodeName nodeName, "chown", "-R", unOwner owner, directoryPath]
      ""
  DockerWriteFile nodeName destinationPath (FilePayload payload) ->
    commandSpec
      HostDocker
      ["exec", "-i", unNodeName nodeName, "cp", "/dev/stdin", destinationPath]
      payload
  DockerPortLookup containerName containerPort ->
    commandSpec
      HostDocker
      ["port", unContainerName containerName, unContainerPort containerPort]
      ""
  DockerConnectKindNetwork containerName ->
    commandSpec
      HostDocker
      ["network", "connect", "kind", unContainerName containerName]
      ""
  HostNvidiaSmiProbe ->
    commandSpec HostNvidiaSmi ["-L"] ""
  HostMakeClaimWritable directoryPath ->
    commandSpec HostChmod ["-R", "a+rwX", directoryPath] ""
  HostSetClaimOwner owner directoryPath ->
    commandSpec HostChown ["-R", unOwner owner, directoryPath] ""
  HostHostnameCommand ->
    commandSpec HostHostname [] ""
  CurlHarborHealth url ->
    commandSpec
      HostCurl
      ["-sS", "-m", "30", "-o", "-", "-w", "\n%{http_code}", unUrl url]
      ""
  CurlPulsarClusters url ->
    commandSpec
      HostCurl
      ["-fsS", "--connect-timeout", "2", "--max-time", "5", unUrl url]
      ""
  CurlPublication url ->
    commandSpec HostCurl ["-fsS", unUrl url] ""
  TarListArchive archivePath ->
    fromRepositoryRoot $
      commandSpec HostTar ["-tf", archivePath] ""
  TarExtractEntry archivePath archiveEntry ->
    fromRepositoryRoot $
      commandSpec HostTar ["-xOf", archivePath, unArchiveEntry archiveEntry] ""
  PublishInspectImage imageRef ->
    commandSpec HostDocker ["image", "inspect", unImageRef imageRef] ""
  PublishInspectManifest imageRef ->
    commandSpec HostDocker ["manifest", "inspect", unImageRef imageRef] ""
  PublishPullUpstream platform imageRef ->
    commandSpec HostDocker (dockerPullArguments platform imageRef) ""
  PublishVerifyRegistry architecture authFile imageRef destinationDirectory ->
    commandSpec
      HostSkopeo
      [ "--insecure-policy",
        "copy",
        "--src-tls-verify=false",
        "--override-os=linux",
        "--override-arch=" <> unArchitecture architecture,
        "--src-authfile=" <> registryAuthFilePath authFile,
        "docker://" <> unImageRef imageRef,
        "dir:" <> destinationDirectory
      ]
      ""
  PublishTag sourceImage targetImage ->
    commandSpec
      HostDocker
      ["tag", unImageRef sourceImage, unImageRef targetImage]
      ""
  PublishPush imageRef ->
    commandSpec HostDocker ["push", unImageRef imageRef] ""
  PublishRemoveTag imageRef ->
    commandSpec HostDocker ["image", "rm", "--no-prune", unImageRef imageRef] ""
  PublishInspectId imageRef ->
    commandSpec
      HostDocker
      ["inspect", unImageRef imageRef, "--format", "{{.Id}}"]
      ""
  PublishLogin registryHost credentials ->
    commandSpecRedacted
      HostDocker
      [ "login",
        unRegistryHost registryHost,
        "--username",
        unUsername (registryUsername credentials),
        "--password-stdin"
      ]
      (unPassword (registryPassword credentials) <> "\n")
      ( "docker login "
          <> unRegistryHost registryHost
          <> " --username "
          <> unUsername (registryUsername credentials)
          <> " --password-stdin"
      )
  PublishCopyDigest architecture authFile sourceImage targetImage ->
    commandSpec
      HostSkopeo
      [ "--insecure-policy",
        "copy",
        "--src-tls-verify=false",
        "--dest-tls-verify=false",
        "--override-os=linux",
        "--override-arch=" <> unArchitecture architecture,
        "--dest-authfile=" <> registryAuthFilePath authFile,
        "docker://" <> unImageRef sourceImage,
        "docker://" <> unImageRef targetImage
      ]
      ""

renderOperatorKubectlCommand ::
  (HostTool -> FilePath) ->
  OperatorKubectlCommand ->
  RenderedCommandSpec
renderOperatorKubectlCommand _resolveTool (OperatorKubectlCommand target tokens) =
  commandSpecRedacted
    HostKubectl
    (kubeTargetArguments target <> kubercDisabledArguments <> tokens)
    ""
    ("kubectl --kubeconfig " <> kubeconfigPath target <> " <operator command>")

commandSpec :: HostTool -> [String] -> String -> RenderedCommandSpec
commandSpec tool =
  commandSpecWithRequiredTools tool []

-- Kind delegates provider discovery and cluster lifecycle to Docker even for
-- read operations such as @get clusters@ and @get kubeconfig@.
kindCommandSpec :: [String] -> String -> RenderedCommandSpec
kindCommandSpec =
  commandSpecWithRequiredTools HostKind [HostDocker]

-- Nvkind's create path invokes Kind, Docker-backed Kind provider operations,
-- and kubectl readiness/apply probes.
nvkindCommandSpec :: [String] -> String -> RenderedCommandSpec
nvkindCommandSpec =
  commandSpecWithRequiredTools
    HostNvkind
    [HostKind, HostDocker, HostKubectl]

commandSpecWithRequiredTools ::
  HostTool ->
  [HostTool] ->
  [String] ->
  String ->
  RenderedCommandSpec
commandSpecWithRequiredTools tool requiredTools arguments input =
  commandSpecRedactedWithRequiredTools
    tool
    requiredTools
    arguments
    input
    (Text.unpack (hostToolName tool) <> " " <> unwords arguments)

commandSpecRedacted ::
  HostTool ->
  [String] ->
  String ->
  String ->
  RenderedCommandSpec
commandSpecRedacted tool =
  commandSpecRedactedWithRequiredTools tool []

commandSpecRedactedWithRequiredTools ::
  HostTool ->
  [HostTool] ->
  [String] ->
  String ->
  String ->
  RenderedCommandSpec
commandSpecRedactedWithRequiredTools tool requiredTools arguments input redactedLabel =
  RenderedCommandSpec
    { renderedCommandTool = tool,
      renderedCommandRequiredTools = tool : requiredTools,
      renderedCommandUsesRepositoryWorkingDirectory = False,
      renderedCommandEnvironment = [],
      renderedCommandArgv = arguments,
      renderedCommandStdin = input,
      renderedCommandLabel = redactedLabel
    }

fromRepositoryRoot :: RenderedCommandSpec -> RenderedCommandSpec
fromRepositoryRoot spec =
  spec {renderedCommandUsesRepositoryWorkingDirectory = True}

withKindScratchKubeconfig ::
  KindScratchKubeconfig ->
  RenderedCommandSpec ->
  RenderedCommandSpec
withKindScratchKubeconfig scratchKubeconfig spec =
  spec
    { renderedCommandEnvironment =
        [("KUBECONFIG", unKindScratchKubeconfig scratchKubeconfig)]
    }

withNvkindEnvironment ::
  KindScratchKubeconfig ->
  RenderedCommandSpec ->
  RenderedCommandSpec
withNvkindEnvironment scratchKubeconfig spec =
  spec
    { renderedCommandEnvironment =
        [ ("KUBECONFIG", unKindScratchKubeconfig scratchKubeconfig),
          ("KUBERC", "off")
        ]
    }

unKindScratchKubeconfig :: KindScratchKubeconfig -> FilePath
unKindScratchKubeconfig (KindScratchKubeconfig path) = path

kubectlSpec :: KubeTarget -> [String] -> String -> RenderedCommandSpec
kubectlSpec target arguments =
  commandSpec
    HostKubectl
    (kubeTargetArguments target <> kubercDisabledArguments <> arguments)

kubeTargetArguments :: KubeTarget -> [String]
kubeTargetArguments target = ["--kubeconfig", kubeconfigPath target]

kubercDisabledArguments :: [String]
kubercDisabledArguments = ["--kuberc=/dev/null"]

podQueryArguments :: PodQuery -> [String]
podQueryArguments podQuery =
  case podQuery of
    AllPodsNoHeaders -> ["get", "pods", "-A", "--no-headers"]
    HarborPostgresStartupPods ->
      ["-n", "platform", "get", "pods", "--no-headers"]
    HarborPostgresPrimary ->
      [ "-n",
        "platform",
        "get",
        "pods",
        "-l",
        "postgres-operator.crunchydata.com/cluster=harbor-postgresql,postgres-operator.crunchydata.com/role=primary",
        "--no-headers",
        "-o",
        "custom-columns=:metadata.name"
      ]
    PlaywrightDemoPods ->
      [ "-n",
        "platform",
        "get",
        "pods",
        "-l",
        "app.kubernetes.io/name=infernix-demo",
        "-o",
        "custom-columns=:metadata.name",
        "--no-headers"
      ]

renderSecretField :: SecretField -> String
renderSecretField secretField =
  case secretField of
    UsernameField -> "username"
    PasswordField -> "password"

renderPostgresAction ::
  KubeTarget ->
  PodName ->
  PostgresAction ->
  RenderedCommandSpec
renderPostgresAction target primaryPod action =
  case action of
    EnsureReplicationRole ->
      kubectlSpec
        target
        (postgresExecPrefix primaryPod <> ["sh", "-lc", replicationRoleRepairScript])
        ""
    DetectDirtyHarborMigration password ->
      postgresPasswordScriptSpec
        target
        primaryPod
        password
        detectDirtyHarborMigrationScript
        "detect dirty Harbor migration state"
    RepairDirtyHarborMigration password ->
      postgresPasswordScriptSpec
        target
        primaryPod
        password
        repairDirtyHarborMigrationScript
        "repair dirty Harbor migration state"

postgresPasswordScriptSpec ::
  KubeTarget ->
  PodName ->
  Password ->
  String ->
  String ->
  RenderedCommandSpec
postgresPasswordScriptSpec target primaryPod password script description =
  commandSpecRedacted
    HostKubectl
    ( kubeTargetArguments target
        <> kubercDisabledArguments
        <> [ "-n",
             "platform",
             "exec",
             "-i",
             unPodName primaryPod,
             "-c",
             "database",
             "--",
             "sh",
             "-lc",
             script
           ]
    )
    (unPassword password <> "\n")
    ( "kubectl --kubeconfig "
        <> kubeconfigPath target
        <> " -n platform exec "
        <> unPodName primaryPod
        <> " -c database -- sh -lc <"
        <> description
        <> "> <redacted>"
    )

postgresExecPrefix :: PodName -> [String]
postgresExecPrefix primaryPod =
  [ "-n",
    "platform",
    "exec",
    unPodName primaryPod,
    "-c",
    "database",
    "--"
  ]

renderHelmUpgrade :: HelmUpgradeSpec -> [String]
renderHelmUpgrade upgradeSpec =
  [ "upgrade",
    "--install",
    "infernix",
    "chart",
    "--namespace",
    "platform",
    "--create-namespace",
    "--kubeconfig",
    kubeconfigPath (helmUpgradeTarget upgradeSpec),
    "--timeout",
    renderHelmDuration (helmUpgradeTimeout upgradeSpec)
  ]
    <> ["--no-hooks" | not (helmUpgradeHooks upgradeSpec)]
    <> ["--wait" | helmUpgradeWait upgradeSpec]
    <> concatMap (\valuesPath -> ["-f", valuesPath]) (helmUpgradeValues upgradeSpec)

renderHelmDuration :: HelmDuration -> String
renderHelmDuration duration =
  case duration of
    HelmSeconds seconds -> show seconds <> "s"
    HelmMinutes minutes -> show minutes <> "m"

helmDependencyArguments :: HelmDependency -> FilePath -> [String]
helmDependencyArguments dependency destinationDirectory =
  case dependency of
    HarborChart ->
      repositoryChart "harbor" "1.18.3" "https://helm.goharbor.io"
    PostgresOperatorChart ->
      repositoryChart "pg-operator" "2.9.0" "https://percona.github.io/percona-helm-charts"
    PostgresDatabaseChart ->
      repositoryChart "pg-db" "2.9.0" "https://percona.github.io/percona-helm-charts"
    PulsarChart ->
      repositoryChart "pulsar" "4.5.0" "https://pulsar.apache.org/charts"
    EnvoyGatewayChart ->
      [ "pull",
        "oci://docker.io/envoyproxy/gateway-helm",
        "--version",
        "v1.7.2",
        "--destination",
        destinationDirectory
      ]
  where
    repositoryChart chartName chartVersion repositoryUrl =
      [ "pull",
        chartName,
        "--repo",
        repositoryUrl,
        "--version",
        chartVersion,
        "--destination",
        destinationDirectory
      ]

helmRepositoryDefinition :: HelmRepository -> (String, String)
helmRepositoryDefinition repository =
  case repository of
    GoharborRepo -> ("goharbor", "https://helm.goharbor.io")
    PerconaRepo -> ("percona", "https://percona.github.io/percona-helm-charts")
    PulsarRepo -> ("apachepulsar", "https://pulsar.apache.org/charts")
    BitnamiRepo -> ("bitnami", "https://charts.bitnami.com/bitnami")
    NvidiaPluginRepo -> ("nvdp", "https://nvidia.github.io/k8s-device-plugin")

dockerGpuProbeArguments :: GpuProbe -> [String]
dockerGpuProbeArguments gpuProbe =
  ["run", "--rm"]
    <> case gpuProbe of
      RuntimeGpuProbe ->
        ["--gpus", "all", cudaProbeImage, "nvidia-smi", "-L"]
      DefaultRuntimeDeviceMountProbe ->
        [ "-v",
          "/dev/null:/var/run/nvidia-container-devices/all",
          cudaProbeImage,
          "nvidia-smi",
          "-L"
        ]
      GpuRuntimeDeviceMountProbe ->
        [ "--gpus",
          "all",
          "-v",
          "/dev/null:/var/run/nvidia-container-devices/all",
          cudaProbeImage,
          "nvidia-smi",
          "-L"
        ]
  where
    cudaProbeImage = "nvidia/cuda:12.4.1-base-ubuntu22.04"

controlPlaneBuildArguments :: ControlPlaneBuildSpec -> [String]
controlPlaneBuildArguments buildSpec =
  [ "build",
    "-f",
    "docker/Dockerfile",
    "--provenance=false",
    "--label",
    clusterImageFingerprintLabel <> "=" <> controlPlaneSourceFingerprint buildSpec,
    "--label",
    clusterImageFingerprintVersionLabel <> "=" <> clusterImageFingerprintVersion,
    "--label",
    clusterImageRuntimeModeLabel <> "=" <> controlPlaneRuntimeMode buildSpec,
    "--build-arg",
    "GO_IMAGE=" <> unImageRef (controlPlaneGoImage buildSpec),
    "--build-arg",
    "BASE_IMAGE=" <> unImageRef (controlPlaneBaseImage buildSpec),
    "--build-arg",
    "RUNTIME_MODE=" <> controlPlaneRuntimeMode buildSpec,
    "-t",
    unImageRef (controlPlaneTargetImage buildSpec),
    "."
  ]

engineBuildArguments :: EngineBuildSpec -> [String]
engineBuildArguments buildSpec =
  [ "build",
    "-f",
    "docker/engine.Dockerfile",
    "--provenance=false",
    "--label",
    clusterImageFingerprintLabel <> "=" <> engineSourceFingerprint buildSpec,
    "--label",
    clusterImageFingerprintVersionLabel <> "=" <> clusterImageFingerprintVersion,
    "--label",
    clusterImageRuntimeModeLabel <> "=" <> engineRuntimeMode buildSpec,
    "--build-arg",
    "ENGINE=" <> unEngineName (engineKind buildSpec),
    "--build-arg",
    "CONTROL_PLANE_IMAGE=" <> unImageRef (engineControlPlaneImage buildSpec),
    "--build-arg",
    "BASE_IMAGE=" <> unImageRef (engineBaseImage buildSpec),
    "-t",
    unImageRef (engineTargetImage buildSpec),
    "."
  ]

renderImageInspectField :: ImageInspectField -> String
renderImageInspectField inspectField =
  case inspectField of
    DescriptorMediaType -> "{{.Descriptor.mediaType}}"
    ImageArchitecture -> "{{.Architecture}}"
    ClusterSourceFingerprint ->
      renderImageLabelTemplate clusterImageFingerprintLabel
    ClusterFingerprintVersion ->
      renderImageLabelTemplate clusterImageFingerprintVersionLabel
    ClusterRuntimeMode ->
      renderImageLabelTemplate clusterImageRuntimeModeLabel

renderImageLabelTemplate :: String -> String
renderImageLabelTemplate labelName =
  "{{ index .Config.Labels " <> show labelName <> " }}"

renderContainerInspectField :: ContainerInspectField -> String
renderContainerInspectField inspectField =
  case inspectField of
    KindNetworkIpv4 -> "{{.NetworkSettings.Networks.kind.IPAddress}}"
    MountSourceAt destinationPath ->
      "{{range .Mounts}}{{if eq .Destination "
        <> show destinationPath
        <> "}}{{.Source}}{{end}}{{end}}"
    ContainerPaused -> "{{.State.Paused}}"

dockerPullArguments :: Platform -> ImageRef -> [String]
dockerPullArguments platform imageRef =
  ["pull"]
    <> case platform of
      DefaultPlatform -> [unImageRef imageRef]
      LinuxPlatform architecture ->
        ["--platform", "linux/" <> unArchitecture architecture, unImageRef imageRef]

renderNamespaceManifest :: Namespace -> String
renderNamespaceManifest namespaceName =
  encodeManifest
    ( Aeson.object
        [ "apiVersion" Aeson..= ("v1" :: String),
          "kind" Aeson..= ("Namespace" :: String),
          "metadata"
            Aeson..= Aeson.object
              [ "name" Aeson..= unNamespace namespaceName
              ]
        ]
    )

renderPersistentVolumeManifest :: PersistentVolumeSpec -> String
renderPersistentVolumeManifest volumeSpec =
  encodeManifest
    ( Aeson.object
        [ "apiVersion" Aeson..= ("v1" :: String),
          "kind" Aeson..= ("PersistentVolume" :: String),
          "metadata"
            Aeson..= Aeson.object
              [ "name"
                  Aeson..= unResourceName
                    (persistentVolumeName volumeSpec)
              ],
          "spec"
            Aeson..= Aeson.object
              [ "capacity"
                  Aeson..= Aeson.object
                    [ "storage" Aeson..= persistentVolumeStorage volumeSpec
                    ],
                "accessModes" Aeson..= ["ReadWriteOnce" :: String],
                "persistentVolumeReclaimPolicy"
                  Aeson..= ("Retain" :: String),
                "storageClassName" Aeson..= ("infernix-manual" :: String),
                "volumeMode" Aeson..= ("Filesystem" :: String),
                "claimRef"
                  Aeson..= Aeson.object
                    [ "namespace"
                        Aeson..= unNamespace
                          (persistentVolumeClaimNamespace volumeSpec),
                      "name"
                        Aeson..= unPvcName
                          (persistentVolumeClaimName volumeSpec)
                    ],
                "hostPath"
                  Aeson..= Aeson.object
                    [ "path" Aeson..= persistentVolumeHostPath volumeSpec
                    ]
              ]
        ]
    )

encodeManifest :: Aeson.Value -> String
encodeManifest =
  Text.unpack . TextEncoding.decodeUtf8 . Lazy.toStrict . Aeson.encode

nvidiaRuntimeClassManifest :: String
nvidiaRuntimeClassManifest =
  unlines
    [ "apiVersion: node.k8s.io/v1",
      "kind: RuntimeClass",
      "metadata:",
      "  name: nvidia",
      "  annotations:",
      "    meta.helm.sh/release-name: infernix",
      "    meta.helm.sh/release-namespace: platform",
      "  labels:",
      "    app.kubernetes.io/managed-by: Helm",
      "handler: nvidia"
    ]

infernixStorageClassManifest :: String
infernixStorageClassManifest =
  unlines
    [ "apiVersion: storage.k8s.io/v1",
      "kind: StorageClass",
      "metadata:",
      "  name: infernix-manual",
      "provisioner: kubernetes.io/no-provisioner",
      "reclaimPolicy: Retain",
      "volumeBindingMode: WaitForFirstConsumer"
    ]

nvidiaDevicePluginValues :: String
nvidiaDevicePluginValues =
  unlines
    [ "fullnameOverride: nvidia-device-plugin-daemonset",
      "runtimeClassName: nvidia",
      "affinity:",
      "  nodeAffinity:",
      "    requiredDuringSchedulingIgnoredDuringExecution:",
      "      nodeSelectorTerms:",
      "        - matchExpressions:",
      "            - key: infernix.runtime/gpu",
      "              operator: In",
      "              values:",
      "                - \"true\""
    ]

claimNodeBindingsTemplate :: String
claimNodeBindingsTemplate =
  "go-template={{range .items}}{{ $node := .spec.nodeName }}"
    <> "{{range .spec.volumes}}{{if .persistentVolumeClaim}}"
    <> "{{printf \"%s\\t%s\\n\" .persistentVolumeClaim.claimName $node}}"
    <> "{{end}}{{end}}{{end}}"

gpuNodeBootstrapScript :: String
gpuNodeBootstrapScript =
  unlines
    [ "set -euo pipefail",
      "apt-get update",
      "apt-get install -y gpg curl",
      "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg",
      "curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list",
      "apt-get update",
      "apt-get install -y nvidia-container-toolkit",
      "nvidia-ctk runtime configure --runtime=containerd --config-source=command",
      "systemctl restart containerd",
      "umount -R /proc/driver/nvidia || true",
      "cp /proc/driver/nvidia/params /root/gpu-params",
      "sed -i 's/^ModifyDeviceFiles: 1$/ModifyDeviceFiles: 0/' /root/gpu-params",
      "mount --bind /root/gpu-params /proc/driver/nvidia/params"
    ]

gpuUserspaceSyncScript :: String
gpuUserspaceSyncScript =
  unlines
    [ "set -euo pipefail",
      "\"$1\" run --rm --gpus all \"$2\" bash -lc "
        <> "'tar -C / -cf - usr/lib/x86_64-linux-gnu/libnvidia* "
        <> "usr/lib/x86_64-linux-gnu/libcuda* usr/bin/nvidia* 2>/dev/null' "
        <> "| \"$1\" exec -i \"$3\" tar -C / -xf -",
      "\"$1\" exec \"$3\" bash -lc 'ldconfig'"
    ]

dockerStreamImportScript :: String
dockerStreamImportScript =
  "set -euo pipefail; \"$1\" image save \"$2\""
    <> " | \"$1\" exec -i \"$3\" ctr --namespace=k8s.io images import -"

replicationRoleRepairScript :: String
replicationRoleRepairScript =
  unlines
    [ "set -eu",
      "psql -d postgres -v ON_ERROR_STOP=1 <<'SQL'",
      "DO $$",
      "BEGIN",
      "  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '_crunchyrepl') THEN",
      "    CREATE ROLE _crunchyrepl WITH LOGIN REPLICATION;",
      "  ELSE",
      "    ALTER ROLE _crunchyrepl WITH LOGIN REPLICATION;",
      "  END IF;",
      "END",
      "$$;",
      "SQL"
    ]

detectDirtyHarborMigrationScript :: String
detectDirtyHarborMigrationScript =
  unlines
    (postgresPasswordPreamble <> harborMigrationDirtyCountScript <> dirtyResult)
  where
    dirtyResult =
      [ "if [ \"$dirty_count\" = \"0\" ]; then",
        "  echo clean",
        "else",
        "  echo dirty",
        "fi"
      ]

repairDirtyHarborMigrationScript :: String
repairDirtyHarborMigrationScript =
  unlines
    (postgresPasswordPreamble <> harborMigrationDirtyCountScript <> repair)
  where
    repair =
      [ "if [ \"$dirty_count\" != \"0\" ]; then",
        "  psql -h 127.0.0.1 -U harbor -d registry -v ON_ERROR_STOP=1 -c \"DROP SCHEMA IF EXISTS harbor CASCADE;\"",
        "  psql -h 127.0.0.1 -U harbor -d registry -v ON_ERROR_STOP=1 -c \"CREATE SCHEMA harbor AUTHORIZATION harbor;\"",
        "  psql -h 127.0.0.1 -U harbor -d registry -v ON_ERROR_STOP=1 -c \"GRANT ALL ON SCHEMA harbor TO harbor;\"",
        "fi"
      ]

postgresPasswordPreamble :: [String]
postgresPasswordPreamble =
  [ "set -eu",
    "IFS= read -r PGPASSWORD",
    "export PGPASSWORD"
  ]

harborMigrationDirtyCountScript :: [String]
harborMigrationDirtyCountScript =
  [ "migration_table_exists=$(psql -h 127.0.0.1 -U harbor -d registry -v ON_ERROR_STOP=1 -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'harbor' AND table_name = 'schema_migrations') THEN 'yes' ELSE 'no' END\")",
    "if [ \"$migration_table_exists\" = \"yes\" ]; then",
    "  dirty_count=$(psql -h 127.0.0.1 -U harbor -d registry -v ON_ERROR_STOP=1 -Atqc \"SELECT COUNT(*)::text FROM harbor.schema_migrations WHERE dirty = TRUE\")",
    "else",
    "  dirty_count=0",
    "fi"
  ]
