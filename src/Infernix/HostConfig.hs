{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

-- | Phase 1 Sprint 1.11 — typed Haskell record for the
-- @dhall/InfernixHost.dhall@ manifest. The supported contract is
-- declared in Phase 0 Sprint 0.9
-- (`DEVELOPMENT_PLAN/development_plan_standards.md` Sections T+U); this
-- module is the in-process surface that lets every Haskell entry point
-- thread typed tool paths + filesystem conventions down its call tree
-- without ever consulting @lookupEnv@ or @\$PATH@.
module Infernix.HostConfig
  ( HostConfig (..),
    HostToolPaths (..),
    HostFilesystem (..),
    HostExecutionContext (..),
    DhallRetryPolicy (..),
    DhallBoundedRetry (..),
    DhallFailureClass (..),
    DhallCommandPolicy (..),
    DhallCommandPolicies (..),
    defaultDhallCommandPolicies,
    renderDhallCommandPolicies,
    decodeHostConfigFile,
    renderHostConfig,
    renderHostConfigSchema,
    encodeHostConfig,
    hostConfigGeneratedBanner,
    normalizeHostArchitecture,
    defaultLinuxOuterContainerHostConfig,
    defaultLinuxOuterContainerHostConfigForArchitecture,
    defaultAppleHostNativeHostConfig,
  )
where

import Control.Exception (SomeException, displayException, try)
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (toLower)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import GHC.Generics (Generic)
import Infernix.DhallSchema.Reflection (renderDecoderExpected)
import Numeric.Natural (Natural)
import System.Info qualified

-- | Where the supported binary is currently running. Mirrors the
-- @HostExecutionContext@ union in @dhall/InfernixHost.dhall@.
data HostExecutionContext
  = AppleHostNative
  | LinuxOuterContainer
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall HostExecutionContext

-- | Absolute paths for every external command the project ever
-- invokes. Adding a new command here is the supported way to
-- introduce a new external tool; bare-name @proc@ calls are rejected
-- by Phase 6 Sprint 6.28's lint gate.
data HostToolPaths = HostToolPaths
  { hostDocker :: Text,
    hostKubectl :: Text,
    hostHelm :: Text,
    hostKind :: Text,
    hostCabal :: Text,
    hostGhc :: Text,
    hostGhcup :: Text,
    hostOrmolu :: Text,
    hostHlint :: Text,
    hostNpm :: Text,
    hostNode :: Text,
    hostPython3 :: Text,
    hostPython311 :: Text,
    hostLlamaCli :: Text,
    hostWhisperCli :: Text,
    hostPoetry :: Text,
    hostProtoc :: Text,
    hostGit :: Text,
    hostTar :: Text,
    hostCurl :: Text,
    hostAptGet :: Text,
    hostBrew :: Text,
    hostSudo :: Text,
    hostSystemctl :: Text,
    hostMkdir :: Text,
    hostChmod :: Text,
    hostLn :: Text,
    hostInstall :: Text,
    hostId :: Text,
    hostGetent :: Text,
    hostCut :: Text,
    hostDirname :: Text,
    hostBash :: Text,
    hostCrictl :: Text,
    hostChown :: Text,
    hostNvidiaSmi :: Text,
    hostNvkind :: Text,
    hostSkopeo :: Text,
    hostHostname :: Text,
    hostSysctl :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall HostToolPaths where
  autoWith _ = Dhall.genericAutoWith hostInterpretOptions

-- | Filesystem conventions the supported flow assumes.
data HostFilesystem = HostFilesystem
  { hostRepoRoot :: Text,
    hostBuildRoot :: Text,
    hostDataRoot :: Text,
    hostRuntimeRoot :: Text,
    hostKubeconfigPath :: Text,
    hostSecretsRoot :: Text,
    hostHomeDirectory :: Text,
    hostKindRoot :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall HostFilesystem where
  autoWith _ = Dhall.genericAutoWith hostInterpretOptions

-- | Proper Dhall retry union for generated cluster-command policies. The
-- constructor names intentionally match the wire labels exactly.
data DhallRetryPolicy
  = Never
  | Bounded DhallBoundedRetry
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DhallRetryPolicy

data DhallBoundedRetry = DhallBoundedRetry
  { dhallAttempts :: Natural,
    dhallBackoffMicros :: Natural
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DhallBoundedRetry where
  autoWith _ = Dhall.genericAutoWith commandPolicyInterpretOptions

-- | Proper Dhall failure-class union. The raw generated representation remains
-- distinct from the subprocess kernel's refined policy type.
data DhallFailureClass
  = Fatal
  | TransientThenFatal
  | IdempotentAbsence
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DhallFailureClass

data DhallCommandPolicy = DhallCommandPolicy
  { dhallTimeoutMicros :: Natural,
    dhallRetry :: DhallRetryPolicy,
    dhallFailureClass :: DhallFailureClass
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DhallCommandPolicy where
  autoWith _ = Dhall.genericAutoWith commandPolicyInterpretOptions

-- | Exact generated policy table for every production operation category in
-- 'Infernix.Cluster.Subprocess.ClusterOperation'. Test-only kernel probes are
-- deliberately excluded from operator configuration.
data DhallCommandPolicies = DhallCommandPolicies
  { dhallKindRead :: DhallCommandPolicy,
    dhallKindCreate :: DhallCommandPolicy,
    dhallKindDelete :: DhallCommandPolicy,
    dhallNvkindCreate :: DhallCommandPolicy,
    dhallKubectlRead :: DhallCommandPolicy,
    dhallKubectlApply :: DhallCommandPolicy,
    dhallKubectlDelete :: DhallCommandPolicy,
    dhallKubectlWait :: DhallCommandPolicy,
    dhallKubectlExec :: DhallCommandPolicy,
    dhallHelmUpgrade :: DhallCommandPolicy,
    dhallHelmDependency :: DhallCommandPolicy,
    dhallHelmRepository :: DhallCommandPolicy,
    dhallHelmRender :: DhallCommandPolicy,
    dhallDockerExec :: DhallCommandPolicy,
    dhallDockerProbe :: DhallCommandPolicy,
    dhallDockerBuild :: DhallCommandPolicy,
    dhallDockerInspect :: DhallCommandPolicy,
    dhallDockerPull :: DhallCommandPolicy,
    dhallDockerTag :: DhallCommandPolicy,
    dhallDockerCopy :: DhallCommandPolicy,
    dhallDockerStreamImport :: DhallCommandPolicy,
    dhallDockerNetwork :: DhallCommandPolicy,
    dhallContainerRuntimePull :: DhallCommandPolicy,
    dhallHostProbe :: DhallCommandPolicy,
    dhallHostMutation :: DhallCommandPolicy,
    dhallCurlProbe :: DhallCommandPolicy,
    dhallArchiveRead :: DhallCommandPolicy,
    dhallGpuUserspaceSync :: DhallCommandPolicy,
    dhallImagePublicationLogin :: DhallCommandPolicy,
    dhallImagePublicationInspect :: DhallCommandPolicy,
    dhallImagePublicationPull :: DhallCommandPolicy,
    dhallImagePublicationVerify :: DhallCommandPolicy,
    dhallImagePublicationTag :: DhallCommandPolicy,
    dhallImagePublicationPush :: DhallCommandPolicy,
    dhallImagePublicationRemove :: DhallCommandPolicy,
    dhallImagePublicationCopy :: DhallCommandPolicy
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DhallCommandPolicies where
  autoWith _ = Dhall.genericAutoWith commandPolicyInterpretOptions

-- | Full host manifest the binary decodes at startup.
data HostConfig = HostConfig
  { hostExecutionContext :: HostExecutionContext,
    hostArchitecture :: Text,
    hostToolPaths :: HostToolPaths,
    hostFilesystem :: HostFilesystem,
    hostCommandPolicies :: DhallCommandPolicies,
    hostPlaywrightHost :: Text,
    hostControlPlaneContext :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall HostConfig where
  autoWith _ = Dhall.genericAutoWith hostInterpretOptions

-- | Dhall field-name normalization. The Haskell record selectors carry
-- the @host…@ prefix (so a record-pattern match on @HostConfig@ stays
-- readable in cross-module call sites) but the Dhall schema fields are
-- the bare camelCase names (@docker@, @kubectl@, @buildRoot@, etc).
hostInterpretOptions :: Dhall.InterpretOptions
hostInterpretOptions =
  Dhall.defaultInterpretOptions {Dhall.fieldModifier = hostFieldName}

commandPolicyInterpretOptions :: Dhall.InterpretOptions
commandPolicyInterpretOptions =
  Dhall.defaultInterpretOptions {Dhall.fieldModifier = commandPolicyFieldName}

commandPolicyFieldName :: Text -> Text
commandPolicyFieldName rawFieldName =
  maybe rawFieldName lowerInitial (Text.stripPrefix "dhall" rawFieldName)

hostFieldName :: Text -> Text
hostFieldName rawFieldName =
  case Text.stripPrefix "host" rawFieldName of
    Nothing -> rawFieldName
    Just "ExecutionContext" -> "hostExecutionContext"
    Just "Architecture" -> "hostArchitecture"
    Just "ToolPaths" -> "toolPaths"
    Just "Filesystem" -> "filesystem"
    Just "CommandPolicies" -> "commandPolicies"
    Just "PlaywrightHost" -> "playwrightHost"
    Just "ControlPlaneContext" -> "controlPlaneContext"
    Just "AptGet" -> "aptGet"
    Just "NvidiaSmi" -> "nvidiaSmi"
    Just suffix -> lowerInitial suffix

lowerInitial :: Text -> Text
lowerInitial value =
  case Text.uncons value of
    Nothing -> value
    Just (firstCharacter, rest) -> Text.cons (toLower firstCharacter) rest

defaultDhallCommandPolicies :: DhallCommandPolicies
defaultDhallCommandPolicies =
  DhallCommandPolicies
    { dhallKindRead = fatalMinutes 2,
      dhallKindCreate = fatalMinutes 30,
      dhallKindDelete = boundedIdempotentMinutes 10 3 2000000,
      dhallNvkindCreate = fatalMinutes 30,
      dhallKubectlRead = fatalMinutes 10,
      dhallKubectlApply = fatalMinutes 10,
      dhallKubectlDelete = idempotentMinutes 10,
      dhallKubectlWait = fatalMinutes 25,
      dhallKubectlExec = fatalMinutes 10,
      dhallHelmUpgrade = fatalMinutes 35,
      dhallHelmDependency = fatalMinutes 20,
      dhallHelmRepository = fatalMinutes 5,
      dhallHelmRender = fatalMinutes 10,
      dhallDockerExec = fatalMinutes 15,
      dhallDockerProbe = fatalMinutes 2,
      dhallDockerBuild = fatalMinutes 45,
      dhallDockerInspect = fatalMinutes 2,
      dhallDockerPull = fatalMinutes 20,
      dhallDockerTag = fatalMinutes 2,
      dhallDockerCopy = fatalMinutes 15,
      dhallDockerStreamImport = fatalMinutes 20,
      dhallDockerNetwork = idempotentMinutes 2,
      dhallContainerRuntimePull = fatalMinutes 15,
      dhallHostProbe = fatalMinutes 2,
      dhallHostMutation = fatalMinutes 15,
      dhallCurlProbe = fatalMinutes 2,
      dhallArchiveRead = fatalMinutes 10,
      dhallGpuUserspaceSync = fatalMinutes 20,
      dhallImagePublicationLogin = transientMinutes 2 6 6000000,
      dhallImagePublicationInspect = fatalMinutes 2,
      dhallImagePublicationPull = fatalMinutes 20,
      dhallImagePublicationVerify = transientMinutes 15 6 6000000,
      dhallImagePublicationTag = fatalMinutes 2,
      -- One kernel-owned 40-minute deadline encloses all 30 attempts and
      -- backoffs. This replaces the caller-side loop that previously reset a
      -- 40-minute command budget on every attempt.
      dhallImagePublicationPush = transientMinutes 40 30 50000000,
      dhallImagePublicationRemove = idempotentMinutes 2,
      dhallImagePublicationCopy = transientMinutes 40 30 50000000
    }
  where
    fatalMinutes count = commandPolicyMinutes count Never Fatal
    idempotentMinutes count =
      commandPolicyMinutes count Never IdempotentAbsence
    boundedIdempotentMinutes count attempts backoffMicros =
      commandPolicyMinutes
        count
        ( boundedRetry
            attempts
            backoffMicros
        )
        IdempotentAbsence
    transientMinutes count attempts backoffMicros =
      commandPolicyMinutes
        count
        (boundedRetry attempts backoffMicros)
        TransientThenFatal
    boundedRetry attempts backoffMicros =
      Bounded
        DhallBoundedRetry
          { dhallAttempts = attempts,
            dhallBackoffMicros = backoffMicros
          }

commandPolicyMinutes ::
  Natural ->
  DhallRetryPolicy ->
  DhallFailureClass ->
  DhallCommandPolicy
commandPolicyMinutes count retryPolicy failureClass =
  DhallCommandPolicy
    { dhallTimeoutMicros = count * 60 * 1000000,
      dhallRetry = retryPolicy,
      dhallFailureClass = failureClass
    }

hostConfigGeneratedBanner :: String
hostConfigGeneratedBanner =
  "{- Auto-generated by infernix host-manifest materialization -}\n"

-- | Decode a materialized @InfernixHost.dhall@ file. Errors carry the
-- supported failure context so cluster/test flows surface them early.
decodeHostConfigFile :: FilePath -> IO HostConfig
decodeHostConfigFile filePath = do
  decoded <- try (Dhall.inputFile Dhall.auto filePath :: IO HostConfig)
  case decoded of
    Left err ->
      ioError
        ( userError
            ( "invalid generated host manifest Dhall at "
                <> filePath
                <> ":\n"
                <> displayException (err :: SomeException)
            )
        )
    Right value -> pure value

-- | Serialize the typed record back to the Dhall source form.
encodeHostConfig :: HostConfig -> LazyChar8.ByteString
encodeHostConfig hostConfig =
  LazyChar8.pack (hostConfigGeneratedBanner <> renderHostConfig hostConfig)

renderHostConfig :: HostConfig -> String
renderHostConfig hostConfig =
  let HostConfig {..} = hostConfig
      HostToolPaths {..} = hostToolPaths
      HostFilesystem {..} = hostFilesystem
      ctxRender = case hostExecutionContext of
        AppleHostNative -> "< AppleHostNative | LinuxOuterContainer >.AppleHostNative"
        LinuxOuterContainer -> "< AppleHostNative | LinuxOuterContainer >.LinuxOuterContainer"
      renderText label value = "  , " <> label <> " = " <> showT value <> "\n"
      renderHeadText label value = "  { " <> label <> " = " <> showT value <> "\n"
      showT t = "\"" <> Text.unpack t <> "\""
   in unlines
        [ "{ hostExecutionContext = " <> ctxRender,
          ", hostArchitecture = " <> showT hostArchitecture,
          ", toolPaths =",
          renderHeadText "docker" hostDocker
            <> renderText "kubectl" hostKubectl
            <> renderText "helm" hostHelm
            <> renderText "kind" hostKind
            <> renderText "cabal" hostCabal
            <> renderText "ghc" hostGhc
            <> renderText "ghcup" hostGhcup
            <> renderText "ormolu" hostOrmolu
            <> renderText "hlint" hostHlint
            <> renderText "npm" hostNpm
            <> renderText "node" hostNode
            <> renderText "python3" hostPython3
            <> renderText "python311" hostPython311
            <> renderText "llamaCli" hostLlamaCli
            <> renderText "whisperCli" hostWhisperCli
            <> renderText "poetry" hostPoetry
            <> renderText "protoc" hostProtoc
            <> renderText "git" hostGit
            <> renderText "tar" hostTar
            <> renderText "curl" hostCurl
            <> renderText "aptGet" hostAptGet
            <> renderText "brew" hostBrew
            <> renderText "sudo" hostSudo
            <> renderText "systemctl" hostSystemctl
            <> renderText "mkdir" hostMkdir
            <> renderText "chmod" hostChmod
            <> renderText "ln" hostLn
            <> renderText "install" hostInstall
            <> renderText "id" hostId
            <> renderText "getent" hostGetent
            <> renderText "cut" hostCut
            <> renderText "dirname" hostDirname
            <> renderText "bash" hostBash
            <> renderText "crictl" hostCrictl
            <> renderText "chown" hostChown
            <> renderText "nvidiaSmi" hostNvidiaSmi
            <> renderText "nvkind" hostNvkind
            <> renderText "skopeo" hostSkopeo
            <> renderText "hostname" hostHostname
            <> renderText "sysctl" hostSysctl
            <> "  }",
          ", filesystem =",
          renderHeadText "repoRoot" hostRepoRoot
            <> renderText "buildRoot" hostBuildRoot
            <> renderText "dataRoot" hostDataRoot
            <> renderText "runtimeRoot" hostRuntimeRoot
            <> renderText "kubeconfigPath" hostKubeconfigPath
            <> renderText "secretsRoot" hostSecretsRoot
            <> renderText "homeDirectory" hostHomeDirectory
            <> renderText "kindRoot" hostKindRoot
            <> "  }",
          ", commandPolicies =",
          renderDhallCommandPolicies hostCommandPolicies,
          ", playwrightHost = " <> showT hostPlaywrightHost,
          ", controlPlaneContext = " <> showT hostControlPlaneContext,
          "}"
        ]

renderDhallCommandPolicies :: DhallCommandPolicies -> String
renderDhallCommandPolicies policies =
  let DhallCommandPolicies {..} = policies
      renderHead label policy =
        "  { " <> label <> " = " <> renderDhallCommandPolicy policy <> "\n"
      renderField label policy =
        "  , " <> label <> " = " <> renderDhallCommandPolicy policy <> "\n"
   in renderHead "kindRead" dhallKindRead
        <> renderField "kindCreate" dhallKindCreate
        <> renderField "kindDelete" dhallKindDelete
        <> renderField "nvkindCreate" dhallNvkindCreate
        <> renderField "kubectlRead" dhallKubectlRead
        <> renderField "kubectlApply" dhallKubectlApply
        <> renderField "kubectlDelete" dhallKubectlDelete
        <> renderField "kubectlWait" dhallKubectlWait
        <> renderField "kubectlExec" dhallKubectlExec
        <> renderField "helmUpgrade" dhallHelmUpgrade
        <> renderField "helmDependency" dhallHelmDependency
        <> renderField "helmRepository" dhallHelmRepository
        <> renderField "helmRender" dhallHelmRender
        <> renderField "dockerExec" dhallDockerExec
        <> renderField "dockerProbe" dhallDockerProbe
        <> renderField "dockerBuild" dhallDockerBuild
        <> renderField "dockerInspect" dhallDockerInspect
        <> renderField "dockerPull" dhallDockerPull
        <> renderField "dockerTag" dhallDockerTag
        <> renderField "dockerCopy" dhallDockerCopy
        <> renderField "dockerStreamImport" dhallDockerStreamImport
        <> renderField "dockerNetwork" dhallDockerNetwork
        <> renderField "containerRuntimePull" dhallContainerRuntimePull
        <> renderField "hostProbe" dhallHostProbe
        <> renderField "hostMutation" dhallHostMutation
        <> renderField "curlProbe" dhallCurlProbe
        <> renderField "archiveRead" dhallArchiveRead
        <> renderField "gpuUserspaceSync" dhallGpuUserspaceSync
        <> renderField "imagePublicationLogin" dhallImagePublicationLogin
        <> renderField "imagePublicationInspect" dhallImagePublicationInspect
        <> renderField "imagePublicationPull" dhallImagePublicationPull
        <> renderField "imagePublicationVerify" dhallImagePublicationVerify
        <> renderField "imagePublicationTag" dhallImagePublicationTag
        <> renderField "imagePublicationPush" dhallImagePublicationPush
        <> renderField "imagePublicationRemove" dhallImagePublicationRemove
        <> renderField "imagePublicationCopy" dhallImagePublicationCopy
        <> "  }"

renderDhallCommandPolicy :: DhallCommandPolicy -> String
renderDhallCommandPolicy policy =
  "{ timeoutMicros = "
    <> show (dhallTimeoutMicros policy)
    <> ", retry = "
    <> renderDhallRetryPolicy (dhallRetry policy)
    <> ", failureClass = "
    <> renderDhallFailureClass (dhallFailureClass policy)
    <> " }"

renderDhallRetryPolicy :: DhallRetryPolicy -> String
renderDhallRetryPolicy retryPolicy =
  case retryPolicy of
    Never -> retryType <> ".Never"
    Bounded boundedRetry ->
      retryType
        <> ".Bounded { attempts = "
        <> show (dhallAttempts boundedRetry)
        <> ", backoffMicros = "
        <> show (dhallBackoffMicros boundedRetry)
        <> " }"
  where
    retryType =
      "< Never | Bounded : { attempts : Natural, backoffMicros : Natural } >"

renderDhallFailureClass :: DhallFailureClass -> String
renderDhallFailureClass failureClass =
  let failureType =
        "< Fatal | TransientThenFatal | IdempotentAbsence >"
      constructorName =
        case failureClass of
          Fatal -> "Fatal"
          TransientThenFatal -> "TransientThenFatal"
          IdempotentAbsence -> "IdempotentAbsence"
   in failureType <> "." <> constructorName

renderHostConfigSchema :: Either String Text
renderHostConfigSchema =
  renderDecoderExpected (Dhall.auto @HostConfig)

-- | Supported defaults for the Linux outer-container launcher image.
-- The image bakes its toolchain at known prefixes; operators override
-- by editing @/opt/infernix/dhall/InfernixHost.dhall@ inside the
-- image build, not via env var.
defaultLinuxOuterContainerHostConfig :: Text -> HostConfig
defaultLinuxOuterContainerHostConfig homeDir =
  defaultLinuxOuterContainerHostConfigForArchitecture homeDir (Text.pack System.Info.arch)

defaultLinuxOuterContainerHostConfigForArchitecture :: Text -> Text -> HostConfig
defaultLinuxOuterContainerHostConfigForArchitecture homeDir architecture =
  HostConfig
    { hostExecutionContext = LinuxOuterContainer,
      hostArchitecture = normalizeHostArchitecture architecture,
      hostToolPaths =
        HostToolPaths
          { hostDocker = "/usr/bin/docker",
            hostKubectl = "/usr/local/bin/kubectl",
            hostHelm = "/usr/local/bin/helm",
            hostKind = "/usr/local/bin/kind",
            hostCabal = homeDir <> "/.ghcup/bin/cabal",
            hostGhc = homeDir <> "/.ghcup/bin/ghc",
            hostGhcup = "",
            hostOrmolu = "/workspace/.build/haskell-style-tools/bin/ormolu",
            hostHlint = "/workspace/.build/haskell-style-tools/bin/hlint",
            hostNpm = "/usr/bin/npm",
            hostNode = "/usr/bin/node",
            hostPython3 = "/usr/bin/python3",
            hostPython311 = "",
            hostLlamaCli = "",
            hostWhisperCli = "",
            hostPoetry = "/opt/poetry/bin/poetry",
            hostProtoc = "/usr/bin/protoc",
            hostGit = "/usr/bin/git",
            hostTar = "/usr/bin/tar",
            hostCurl = "/usr/bin/curl",
            hostAptGet = "/usr/bin/apt-get",
            hostBrew = "",
            hostSudo = "/usr/bin/sudo",
            hostSystemctl = "/usr/bin/systemctl",
            hostMkdir = "/usr/bin/mkdir",
            hostChmod = "/usr/bin/chmod",
            hostLn = "/usr/bin/ln",
            hostInstall = "/usr/bin/install",
            hostId = "/usr/bin/id",
            hostGetent = "/usr/bin/getent",
            hostCut = "/usr/bin/cut",
            hostDirname = "/usr/bin/dirname",
            hostBash = "/usr/bin/bash",
            hostCrictl = "/usr/local/bin/crictl",
            hostChown = "/usr/bin/chown",
            hostNvidiaSmi = "/usr/bin/nvidia-smi",
            hostNvkind = "/usr/local/bin/nvkind",
            hostSkopeo = "/usr/bin/skopeo",
            hostHostname = "/usr/bin/hostname",
            hostSysctl = "/sbin/sysctl"
          },
      hostFilesystem =
        HostFilesystem
          { hostRepoRoot = "/workspace",
            hostBuildRoot = "/workspace/.build/outer-container/build",
            hostDataRoot = "/workspace/.data",
            hostRuntimeRoot = "/workspace/.data/runtime",
            hostKubeconfigPath = "/workspace/.data/runtime/infernix.kubeconfig",
            hostSecretsRoot = "/workspace/.data/runtime/secrets",
            hostHomeDirectory = homeDir,
            hostKindRoot = "/workspace/.data/runtime/kind"
          },
      hostCommandPolicies = defaultDhallCommandPolicies,
      hostPlaywrightHost = "127.0.0.1",
      hostControlPlaneContext = "outer-container"
    }

-- | Supported defaults for the Apple host-native flow. Tool paths
-- reflect the Homebrew + ghcup convention the supported Apple operator
-- workflow uses; @infernix init@ materializes them into the repo-root
-- @./infernix-host.dhall@.
defaultAppleHostNativeHostConfig :: Text -> Text -> HostConfig
defaultAppleHostNativeHostConfig repoRoot homeDir =
  HostConfig
    { hostExecutionContext = AppleHostNative,
      hostArchitecture = "arm64",
      hostToolPaths =
        HostToolPaths
          { hostDocker = "/opt/homebrew/bin/docker",
            hostKubectl = "/opt/homebrew/bin/kubectl",
            hostHelm = "/opt/homebrew/bin/helm",
            hostKind = "/opt/homebrew/bin/kind",
            hostCabal = homeDir <> "/.ghcup/bin/cabal",
            hostGhc = homeDir <> "/.ghcup/bin/ghc",
            hostGhcup = homeDir <> "/.ghcup/bin/ghcup",
            hostOrmolu = repoRoot <> "/.build/haskell-style-tools/bin/ormolu",
            hostHlint = repoRoot <> "/.build/haskell-style-tools/bin/hlint",
            hostNpm = "/opt/homebrew/bin/npm",
            hostNode = "/opt/homebrew/bin/node",
            hostPython3 = "/opt/homebrew/bin/python3.12",
            hostPython311 = "/opt/homebrew/bin/python3.11",
            hostLlamaCli = "/opt/homebrew/bin/llama-cli",
            hostWhisperCli = "/opt/homebrew/bin/whisper-cli",
            hostPoetry =
              homeDir <> "/.local/share/pypoetry/venv/bin/poetry",
            hostProtoc = "/opt/homebrew/bin/protoc",
            hostGit = "/usr/bin/git",
            hostTar = "/usr/bin/tar",
            hostCurl = "/usr/bin/curl",
            hostAptGet = "",
            hostBrew = "/opt/homebrew/bin/brew",
            hostSudo = "/usr/bin/sudo",
            hostSystemctl = "",
            hostMkdir = "/bin/mkdir",
            hostChmod = "/bin/chmod",
            hostLn = "/bin/ln",
            hostInstall = "/usr/bin/install",
            hostId = "/usr/bin/id",
            hostGetent = "",
            hostCut = "/usr/bin/cut",
            hostDirname = "/usr/bin/dirname",
            hostBash = "/bin/bash",
            hostCrictl = "",
            hostChown = "/usr/sbin/chown",
            hostNvidiaSmi = "",
            hostNvkind = "",
            hostSkopeo = "/opt/homebrew/bin/skopeo",
            hostHostname = "/bin/hostname",
            hostSysctl = "/usr/sbin/sysctl"
          },
      hostFilesystem =
        HostFilesystem
          { hostRepoRoot = repoRoot,
            hostBuildRoot = repoRoot <> "/.build",
            hostDataRoot = repoRoot <> "/.data",
            hostRuntimeRoot = repoRoot <> "/.data/runtime",
            hostKubeconfigPath = repoRoot <> "/.build/infernix.kubeconfig",
            hostSecretsRoot = repoRoot <> "/.data/runtime/secrets",
            hostHomeDirectory = homeDir,
            hostKindRoot = repoRoot <> "/.data/runtime/kind"
          },
      hostCommandPolicies = defaultDhallCommandPolicies,
      hostPlaywrightHost = "host.docker.internal",
      hostControlPlaneContext = "host-native"
    }

normalizeHostArchitecture :: Text -> Text
normalizeHostArchitecture rawArchitecture =
  case Text.toLower (Text.strip rawArchitecture) of
    "x86_64" -> "amd64"
    "amd64" -> "amd64"
    "aarch64" -> "arm64"
    "arm64" -> "arm64"
    other -> other
