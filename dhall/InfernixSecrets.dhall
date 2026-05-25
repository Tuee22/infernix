{- Infernix secrets file-paths manifest.

   Typed record naming the file *paths* at which credential material
   lives, never the credential values themselves. The Haskell daemon
   reads the named JSON files via `readFile` after decoding this
   manifest at startup.

   Phase 0 Sprint 0.9 declared the no-env-var doctrine
   (see `documents/architecture/configuration_doctrine.md`). Phase 7
   Sprint 7.17 materializes this schema and threads a `SecretsConfig`
   record through the credential-bearing entry points so no module
   needs to consume `INFERNIX_MINIO_ACCESS_KEY` /
   `INFERNIX_MINIO_SECRET_KEY` / `INFERNIX_KEYCLOAK_*` env vars.

   On-cluster path: the files referenced by this schema come from a
   Kubernetes `Secret` mounted at `/etc/infernix/secrets/` (the chart
   template `chart/templates/secret-cluster-secrets.yaml` materializes
   the matching `Secret/infernix-cluster-secrets` resource).

   Host path: the files live under `./.data/runtime/secrets/`
   (gitignored, operator-edited). The directory is created by
   `infernix internal materialize-substrate` on first run with
   placeholder JSON files; operators edit the placeholder values
   before the daemon needs them.

   The credentials themselves never appear here. Only paths.
-}

let MinioCredentials =
      { credentialsPath : Text
      }

let KeycloakAdminCredentials =
      { credentialsPath : Text
      }

let KeycloakDbCredentials =
      { credentialsPath : Text
      }

in    { minio : MinioCredentials
      , keycloakAdmin : KeycloakAdminCredentials
      , keycloakDb : KeycloakDbCredentials
      }
