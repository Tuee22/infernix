{-# LANGUAGE OverloadedStrings #-}

-- | Phase 1 Sprint 1.11 — runtime helpers that resolve every external
-- command through the absolute paths declared in
-- @dhall/InfernixHost.dhall@. The supported invariant
-- (`documents/architecture/configuration_doctrine.md` Section T) is
-- that no module ever calls @proc "<bare-name>"@ or relies on @\$PATH@
-- for resolution; every external invocation goes through 'runHostTool'
-- (or the lower-level 'hostToolPath' lookup) so the linter introduced
-- in Phase 6 Sprint 6.28 can mechanically reject regressions.
module Infernix.HostTools
  ( HostTool (..),
    hostToolName,
    hostToolPath,
    hostToolFallbackCandidates,
    hostToolFallbackPath,
    runHostTool,
    runHostToolWithCwd,
    readHostTool,
    readHostToolWithExitCode,
    hostToolProcess,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.HostConfig
  ( HostConfig (..),
    HostToolPaths (..),
  )
import System.Exit (ExitCode)
import System.Process
  ( CreateProcess (cwd),
    proc,
    readCreateProcessWithExitCode,
    readProcess,
    waitForProcess,
    withCreateProcess,
  )

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
  | HostOrmolu
  | HostHlint
  | HostNpm
  | HostNode
  | HostPython3
  | HostPoetry
  | HostProtoc
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
  deriving (Eq, Show)

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
  HostOrmolu -> "ormolu"
  HostHlint -> "hlint"
  HostNpm -> "npm"
  HostNode -> "node"
  HostPython3 -> "python3"
  HostPoetry -> "poetry"
  HostProtoc -> "protoc"
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
  HostOrmolu -> []
  HostHlint -> []
  HostNpm -> ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"]
  HostNode -> ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
  HostPython3 -> ["/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3", "/usr/bin/python3"]
  HostPoetry -> ["/opt/poetry/bin/poetry", "/usr/local/bin/poetry", "/usr/bin/poetry"]
  HostProtoc -> ["/opt/homebrew/bin/protoc", "/usr/local/bin/protoc", "/usr/bin/protoc"]
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

-- | Deterministic absolute fallback for pure call sites that cannot
-- check the filesystem before constructing a process description.
-- IO-capable call sites should still prefer 'hostToolFallbackCandidates'
-- plus an existence check.
hostToolFallbackPath :: HostTool -> Maybe FilePath
hostToolFallbackPath tool =
  case hostToolFallbackCandidates tool of
    [] -> Nothing
    candidate : _ -> Just candidate

pickToolPath :: HostTool -> HostToolPaths -> Text
pickToolPath tool paths = case tool of
  HostDocker -> hostDocker paths
  HostKubectl -> hostKubectl paths
  HostHelm -> hostHelm paths
  HostKind -> hostKind paths
  HostCabal -> hostCabal paths
  HostGhc -> hostGhc paths
  HostGhcup -> hostGhcup paths
  HostOrmolu -> hostOrmolu paths
  HostHlint -> hostHlint paths
  HostNpm -> hostNpm paths
  HostNode -> hostNode paths
  HostPython3 -> hostPython3 paths
  HostPoetry -> hostPoetry paths
  HostProtoc -> hostProtoc paths
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

-- | Run a tool with the supplied args, inheriting the parent's
-- handles. Returns when the process exits.
runHostTool :: HostConfig -> HostTool -> [String] -> IO ExitCode
runHostTool config tool args =
  withCreateProcess (hostToolProcess config tool args) $ \_ _ _ processHandle ->
    waitForProcess processHandle

-- | Run a tool with an explicit working directory.
runHostToolWithCwd :: HostConfig -> HostTool -> [String] -> FilePath -> IO ExitCode
runHostToolWithCwd config tool args workingDirectory =
  let cp = (hostToolProcess config tool args) {cwd = Just workingDirectory}
   in withCreateProcess cp $ \_ _ _ processHandle -> waitForProcess processHandle

-- | Run a tool and capture its stdout. Equivalent to the legacy
-- @readProcess "<bare-name>"@ pattern, with command resolution
-- routed through 'HostConfig'.
readHostTool :: HostConfig -> HostTool -> [String] -> String -> IO String
readHostTool config tool =
  readProcess (resolveOrFail config tool)

-- | Run a tool, capture its stdout, and return the exit code + stderr
-- alongside. Equivalent to @readProcessWithExitCode "<bare-name>"@.
readHostToolWithExitCode ::
  HostConfig ->
  HostTool ->
  [String] ->
  String ->
  IO (ExitCode, String, String)
readHostToolWithExitCode config tool args =
  readCreateProcessWithExitCode (hostToolProcess config tool args)
