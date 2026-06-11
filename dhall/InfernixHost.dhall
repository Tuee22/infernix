{- Infernix host manifest schema.

   Typed inventory of every external tool the project ever invokes
   (by absolute path), plus the filesystem conventions and host
   execution context the binary needs at startup.

   Phase 0 Sprint 0.9 declared the no-env-var + absolute-path doctrine
   (see documents/architecture/configuration_doctrine.md). Phase 1
   Sprint 1.11 materializes this schema and threads a `HostConfig`
   record through every Haskell entry point so no module needs to call
   `lookupEnv`, no module needs to resolve `proc "<bare-name>"` against
   `$PATH`, and bootstrap scripts can read tool paths from the same
   typed source after the binary exists.

   The schema is the single source of truth for "every command this
   project ever invokes." Any new external command added to the
   codebase must add a field here first.
-}

let ToolPaths =
      { docker : Text
      , kubectl : Text
      , helm : Text
      , kind : Text
      , cabal : Text
      , ghc : Text
      , ghcup : Text
      , ormolu : Text
      , hlint : Text
      , npm : Text
      , node : Text
      , python3 : Text
      , poetry : Text
      , protoc : Text
      , git : Text
      , tar : Text
      , curl : Text
      , aptGet : Text
      , brew : Text
      , sudo : Text
      , systemctl : Text
      , mkdir : Text
      , chmod : Text
      , ln : Text
      , install : Text
      , id : Text
      , getent : Text
      , cut : Text
      , dirname : Text
      , bash : Text
      , crictl : Text
      , chown : Text
      , nvidiaSmi : Text
      , nvkind : Text
      , skopeo : Text
      , hostname : Text
      , tart : Text
      }

let FilesystemConventions =
      { repoRoot : Text
      , buildRoot : Text
      , dataRoot : Text
      , runtimeRoot : Text
      , kubeconfigPath : Text
      , secretsRoot : Text
      , homeDirectory : Text
      , kindRoot : Text
      }

let HostExecutionContext =
      < AppleHostNative
      | LinuxOuterContainer
      >

in    { hostExecutionContext : HostExecutionContext
      , hostArchitecture : Text
      , toolPaths : ToolPaths
      , filesystem : FilesystemConventions
      , playwrightHost : Text
      , controlPlaneContext : Text
      }
