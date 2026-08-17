{-# LANGUAGE OverloadedStrings #-}

-- | Phase 1 Sprint 1.11 — runtime helpers that resolve every external
-- command through the absolute paths declared in
-- @dhall/InfernixHost.dhall@. The supported invariant
-- (`documents/architecture/configuration_doctrine.md` Section T) is
-- that no module ever calls @proc "<bare-name>"@ or relies on @\$PATH@
-- for resolution; every external invocation resolves through
-- 'hostToolPath' (or the fixed 'hostToolFallbackCandidates' list) so the
-- linter introduced in Phase 6 Sprint 6.28 can mechanically reject
-- regressions.
--
-- Phase 6 Sprint 6.44 follow-on narrowed this module to the two
-- /pre-manifest/ host probes it still owns. The generic runners
-- (@runHostTool@, @runHostToolWithCwd@, @readHostToolWithExitCode@) had
-- no callers left anywhere in the repository and were deleted rather
-- than carried: a caller-supplied executable plus caller-supplied argv is
-- exactly the shape the closed 'Infernix.Cluster.Command.ClusterCommand'
-- catalog exists to make unrepresentable. What remains — 'readHostTool'
-- and 'readHostToolFallback' — runs during @infernix init@, /before/ the
-- generated host manifest exists, so 'Infernix.Cluster.Subprocess.clusterSubprocessEnv'
-- (which fails closed without a manifest) cannot compile a closed command
-- there. Both therefore carry a required total deadline instead; see
-- 'hostProbeDeadlineMicros'.
--
-- Phase 1 Sprint 1.21 keeps 'readHostToolFallback' on one further surface that
-- is not pre-manifest but is the same /class/ of probe: the memory
-- observations the toolchain account is derived from and admitted against
-- ('Infernix.DemoConfig.Colima' and 'Infernix.HostClaimants'). Those are fixed
-- read-only system probes with fixed argument vectors, they are deliberately
-- not manifest-owned, and they must run at the point of use rather than at
-- @init@ time — an observation taken when the manifest was written cannot see
-- what is resident now.
module Infernix.HostTools
  ( HostTool (..),
    hostToolName,
    hostToolCommandNames,
    hostToolPath,
    hostToolFallbackCandidates,
    hostToolFallbackPath,
    readHostToolFallback,
    readHostTool,
    hostToolProcess,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.HostConfig
  ( HostConfig (..),
    HostToolPaths (..),
  )
import System.Directory (doesFileExist)
import System.Process
  ( CreateProcess,
    proc,
    readProcess,
  )
import System.Timeout (timeout)

-- | Closed enumeration of every external command the project ever
-- invokes. Adding a new constructor here is the supported way to
-- introduce a new external tool; the matching field in
-- 'HostToolPaths' must be added to @dhall/InfernixHost.dhall@ in the
-- same change.
data HostTool
  = HostDocker
  | HostKubectl
  | HostHelm
  | HostKind
  | HostCabal
  | HostGhc
  | HostGhcup
  | HostNpm
  | HostNode
  | HostPython3
  | HostPython311
  | HostLlamaCompletion
  | HostWhisperCli
  | HostPoetry
  | HostGit
  | HostTar
  | HostCurl
  | HostAptGet
  | HostBrew
  | HostSudo
  | HostSystemctl
  | HostMkdir
  | HostChmod
  | HostLn
  | HostInstall
  | HostId
  | HostGetent
  | HostCut
  | HostDirname
  | HostBash
  | HostCrictl
  | HostChown
  | HostNvidiaSmi
  | HostNvkind
  | HostSkopeo
  | HostHostname
  | HostSysctl
  | HostColima
  | HostPs
  | HostVmStat
  deriving (Bounded, Enum, Eq, Show)

-- | The supported short name for a tool, used in lint messages and
-- diagnostic output so a missing 'HostToolPaths' field surfaces a
-- readable error rather than an opaque empty-string failure.
hostToolName :: HostTool -> Text
hostToolName tool = case tool of
  HostDocker -> "docker"
  HostKubectl -> "kubectl"
  HostHelm -> "helm"
  HostKind -> "kind"
  HostCabal -> "cabal"
  HostGhc -> "ghc"
  HostGhcup -> "ghcup"
  HostNpm -> "npm"
  HostNode -> "node"
  HostPython3 -> "python3"
  HostPython311 -> "python3.11"
  HostLlamaCompletion -> "llama-completion"
  HostWhisperCli -> "whisper-cli"
  HostPoetry -> "poetry"
  HostGit -> "git"
  HostTar -> "tar"
  HostCurl -> "curl"
  HostAptGet -> "apt-get"
  HostBrew -> "brew"
  HostSudo -> "sudo"
  HostSystemctl -> "systemctl"
  HostMkdir -> "mkdir"
  HostChmod -> "chmod"
  HostLn -> "ln"
  HostInstall -> "install"
  HostId -> "id"
  HostGetent -> "getent"
  HostCut -> "cut"
  HostDirname -> "dirname"
  HostBash -> "bash"
  HostCrictl -> "crictl"
  HostChown -> "chown"
  HostNvidiaSmi -> "nvidia-smi"
  HostNvkind -> "nvkind"
  HostSkopeo -> "skopeo"
  HostHostname -> "hostname"
  HostSysctl -> "sysctl"
  HostColima -> "colima"
  HostPs -> "ps"
  HostVmStat -> "vm_stat"

-- | Every external command name, derived from the 'HostTool' enum. The
-- bare-name @proc@ lint in @Infernix.Lint.HaskellStyle@ reuses this so its
-- forbidden-command set cannot drift from the registered tool set: adding a
-- 'HostTool' constructor automatically extends the lint's coverage.
hostToolCommandNames :: [String]
hostToolCommandNames = map (Text.unpack . hostToolName) [minBound .. maxBound]

-- | Look up the absolute path for a tool. An empty path means the
-- active execution context does not provide the tool (e.g. @apt-get@
-- on Apple, @brew@ on Linux); the caller is expected to surface a
-- typed diagnostic in that case rather than fall back to @\$PATH@.
hostToolPath :: HostConfig -> HostTool -> Text
hostToolPath config tool = pickToolPath tool (hostToolPaths config)

-- | Narrow absolute fallback candidates for bootstrap-adjacent paths
-- that can run before a host manifest has been staged. Normal command
-- execution uses the manifest value; these candidates avoid consulting
-- the caller's PATH when the manifest is genuinely absent.
hostToolFallbackCandidates :: HostTool -> [FilePath]
hostToolFallbackCandidates tool = case tool of
  HostDocker -> ["/opt/homebrew/bin/docker", "/usr/bin/docker"]
  HostKubectl -> ["/opt/homebrew/bin/kubectl", "/usr/local/bin/kubectl", "/usr/bin/kubectl"]
  HostHelm -> ["/opt/homebrew/bin/helm", "/usr/local/bin/helm", "/usr/bin/helm"]
  HostKind -> ["/opt/homebrew/bin/kind", "/usr/local/bin/kind", "/usr/bin/kind"]
  HostCabal -> ["/root/.ghcup/bin/cabal", "/usr/local/bin/cabal", "/usr/bin/cabal"]
  HostGhc -> ["/root/.ghcup/bin/ghc", "/usr/local/bin/ghc", "/usr/bin/ghc"]
  HostGhcup -> ["/usr/local/bin/ghcup", "/usr/bin/ghcup"]
  HostNpm -> ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"]
  HostNode -> ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
  HostPython3 -> ["/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3", "/usr/bin/python3"]
  HostPython311 -> ["/opt/homebrew/bin/python3.11"]
  HostLlamaCompletion -> ["/opt/homebrew/bin/llama-completion"]
  HostWhisperCli -> ["/opt/homebrew/bin/whisper-cli"]
  HostPoetry -> ["/opt/homebrew/bin/poetry", "/opt/poetry/bin/poetry", "/usr/local/bin/poetry", "/usr/bin/poetry"]
  HostGit -> ["/opt/homebrew/bin/git", "/usr/bin/git"]
  HostTar -> ["/usr/bin/tar"]
  HostCurl -> ["/usr/bin/curl"]
  HostAptGet -> ["/usr/bin/apt-get"]
  HostBrew -> ["/opt/homebrew/bin/brew"]
  HostSudo -> ["/usr/bin/sudo"]
  HostSystemctl -> ["/usr/bin/systemctl"]
  HostMkdir -> ["/bin/mkdir", "/usr/bin/mkdir"]
  HostChmod -> ["/bin/chmod", "/usr/bin/chmod"]
  HostLn -> ["/bin/ln", "/usr/bin/ln"]
  HostInstall -> ["/usr/bin/install"]
  HostId -> ["/usr/bin/id"]
  HostGetent -> ["/usr/bin/getent"]
  HostCut -> ["/usr/bin/cut"]
  HostDirname -> ["/usr/bin/dirname"]
  HostBash -> ["/bin/bash", "/usr/bin/bash"]
  HostCrictl -> ["/usr/local/bin/crictl", "/usr/bin/crictl"]
  HostChown -> ["/usr/sbin/chown", "/usr/bin/chown"]
  HostNvidiaSmi -> ["/usr/bin/nvidia-smi"]
  HostNvkind -> ["/usr/local/bin/nvkind", "/usr/bin/nvkind"]
  HostSkopeo -> ["/opt/homebrew/bin/skopeo", "/usr/bin/skopeo"]
  HostHostname -> ["/bin/hostname", "/usr/bin/hostname"]
  HostSysctl -> ["/usr/sbin/sysctl", "/sbin/sysctl"]
  HostColima -> ["/opt/homebrew/bin/colima"]
  HostPs -> ["/bin/ps", "/usr/bin/ps"]
  HostVmStat -> ["/usr/bin/vm_stat"]

-- | Deterministic absolute fallback for pure call sites that cannot
-- check the filesystem before constructing a process description.
-- IO-capable call sites should still prefer 'hostToolFallbackCandidates'
-- plus an existence check.
hostToolFallbackPath :: HostTool -> Maybe FilePath
hostToolFallbackPath tool =
  case hostToolFallbackCandidates tool of
    [] -> Nothing
    candidate : _ -> Just candidate

-- | Phase 4 Sprint 4.26 — run a bootstrap-adjacent host-provisioning probe by
-- its first existing fixed candidate path (absolute, from
-- 'hostToolFallbackCandidates'), capturing stdout. Returns 'Nothing' when no
-- candidate exists on the host. Unlike 'readHostTool', this never consults the
-- manifest, so it fits tools that are intentionally not manifest-owned (e.g.
-- @colima@, read — never managed — by the shared build- and inference-memory
-- observer). The resolved path is always absolute, so it does not depend on
-- @\$PATH@.
readHostToolFallback :: HostTool -> [String] -> String -> IO (Maybe String)
readHostToolFallback tool args input = do
  maybePath <- firstExistingCandidate (hostToolFallbackCandidates tool)
  case maybePath of
    Nothing -> pure Nothing
    Just path ->
      Just
        <$> withHostProbeDeadline
          (Text.unpack (hostToolName tool))
          (readProcess path args input)
  where
    firstExistingCandidate [] = pure Nothing
    firstExistingCandidate (candidate : rest) = do
      present <- doesFileExist candidate
      if present then pure (Just candidate) else firstExistingCandidate rest

-- | The required total deadline shared by the two pre-manifest host
-- probes.
--
-- Both probes are strictly local reads — @sysctl -n hw.memsize@ reads a
-- kernel scalar and @colima list --json@ reads on-disk profile state —
-- and both complete in milliseconds on a healthy host. The number is
-- therefore not a performance budget; it is the bound that turns a
-- wedged probe (an unresponsive @colima@ daemon socket, a stuck
-- filesystem under the profile directory) into a named failure instead
-- of a hang that stalls @infernix init@ forever.
--
-- 120 s is chosen deliberately rather than invented: it is exactly the
-- @hostProbe@ deadline the generated host manifest gives every closed
-- 'Infernix.Cluster.Command.HostProbeOperation'. Keeping the
-- pre-manifest and post-manifest host-probe surfaces on the same bound
-- means an operator reading either one sees a single host-probe
-- deadline, and it leaves roughly four orders of magnitude of headroom
-- over the observed cost.
hostProbeDeadlineMicros :: Int
hostProbeDeadlineMicros = 120 * 1000 * 1000

-- | Impose 'hostProbeDeadlineMicros' on a pre-manifest host probe. The
-- capture primitive terminates its child when the deadline exception
-- unwinds it, so an expired probe leaves no orphan behind and surfaces
-- as an ordinary @IOError@ naming both the tool and the bound.
withHostProbeDeadline :: String -> IO a -> IO a
withHostProbeDeadline toolLabel action = do
  outcome <- timeout hostProbeDeadlineMicros action
  requireHostProbeOutcome toolLabel outcome

requireHostProbeOutcome :: String -> Maybe a -> IO a
requireHostProbeOutcome toolLabel outcome =
  case outcome of
    Just value -> pure value
    Nothing ->
      ioError
        ( userError
            ( "host probe `"
                <> toolLabel
                <> "` exceeded its required "
                <> show (hostProbeDeadlineMicros `div` 1000000)
                <> "s deadline"
            )
        )

pickToolPath :: HostTool -> HostToolPaths -> Text
pickToolPath tool paths = case tool of
  HostDocker -> hostDocker paths
  HostKubectl -> hostKubectl paths
  HostHelm -> hostHelm paths
  HostKind -> hostKind paths
  HostCabal -> hostCabal paths
  HostGhc -> hostGhc paths
  HostGhcup -> hostGhcup paths
  HostNpm -> hostNpm paths
  HostNode -> hostNode paths
  HostPython3 -> hostPython3 paths
  HostPython311 -> hostPython311 paths
  HostLlamaCompletion -> hostLlamaCompletion paths
  HostWhisperCli -> hostWhisperCli paths
  HostPoetry -> hostPoetry paths
  HostGit -> hostGit paths
  HostTar -> hostTar paths
  HostCurl -> hostCurl paths
  HostAptGet -> hostAptGet paths
  HostBrew -> hostBrew paths
  HostSudo -> hostSudo paths
  HostSystemctl -> hostSystemctl paths
  HostMkdir -> hostMkdir paths
  HostChmod -> hostChmod paths
  HostLn -> hostLn paths
  HostInstall -> hostInstall paths
  HostId -> hostId paths
  HostGetent -> hostGetent paths
  HostCut -> hostCut paths
  HostDirname -> hostDirname paths
  HostBash -> hostBash paths
  HostCrictl -> hostCrictl paths
  HostChown -> hostChown paths
  HostNvidiaSmi -> hostNvidiaSmi paths
  HostNvkind -> hostNvkind paths
  HostSkopeo -> hostSkopeo paths
  HostHostname -> hostHostname paths
  HostSysctl -> hostSysctl paths
  -- Colima is an Apple-only host-provisioning probe read (never managed) by the
  -- shared build- and inference-memory observer. It is deliberately NOT a
  -- manifest-owned tool (the Linux launcher manifest carries no colima field),
  -- so it has no 'HostToolPaths' entry and resolves through its fixed fallback
  -- candidate instead.
  HostColima -> ""
  -- The same shape, for the same reason: the Darwin half of the toolchain
  -- admission observation in 'Infernix.HostClaimants' reads @vm_stat@ for
  -- available memory and @ps@ for the foreign-claimant census. Both are
  -- read-only Darwin system probes, neither is managed by this repository, and
  -- the Linux lane reads @\/proc@ instead of either, so neither belongs in the
  -- manifest schema an operator materializes.
  HostPs -> ""
  HostVmStat -> ""

-- | Build a 'CreateProcess' for a tool invocation. The returned value
-- can be customized further by callers that need stdin/stdout/stderr
-- redirection before handing it to 'createProcess' or similar
-- machinery, while still keeping the command resolution under
-- 'HostConfig' control.
hostToolProcess :: HostConfig -> HostTool -> [String] -> CreateProcess
hostToolProcess config tool =
  proc (resolveOrFail config tool)

resolveOrFail :: HostConfig -> HostTool -> String
resolveOrFail config tool =
  let path = hostToolPath config tool
   in if Text.null path
        then
          error
            ( "Infernix.HostTools.resolveOrFail: tool "
                <> Text.unpack (hostToolName tool)
                <> " is unavailable in the active host execution context"
            )
        else Text.unpack path

-- | Run a manifest-resolved pre-manifest host probe and capture its
-- stdout under the required 'hostProbeDeadlineMicros' bound. The sole
-- caller is the Apple physical-RAM probe (@sysctl -n hw.memsize@), whose
-- argument vector is a fixed literal.
readHostTool :: HostConfig -> HostTool -> [String] -> String -> IO String
readHostTool config tool args input =
  withHostProbeDeadline
    (Text.unpack (hostToolName tool))
    (readProcess (resolveOrFail config tool) args input)
