module Infernix.Lint.Chart
  ( runChartLint,
  )
where

import Control.Monad (forM_, unless, when)
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.Routes (renderChartRouteRegistryCommentSection)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

requiredFiles :: [FilePath]
requiredFiles =
  [ "chart/Chart.yaml",
    "chart/values.yaml",
    "chart/templates/configmap-demo-catalog.yaml",
    "chart/templates/configmap-publication-state.yaml",
    "chart/templates/deployment-coordinator.yaml",
    "chart/templates/deployment-demo.yaml",
    "chart/templates/deployment-engine.yaml",
    "chart/templates/envoyproxy.yaml",
    "chart/templates/gateway.yaml",
    "chart/templates/gatewayclass.yaml",
    "chart/templates/httproutes.yaml",
    "chart/templates/keycloak/configmap-theme.yaml",
    "chart/templates/runtimeclass-nvidia.yaml",
    "chart/templates/securitypolicy-operator-routes.yaml",
    "chart/templates/service-demo.yaml",
    -- Phase 3 Sprint 3.11 (2026-05-29): hand-authored MinIO
    -- templates replacing the retired bitnami sub-chart.
    "chart/templates/minio/service-headless.yaml",
    "chart/templates/minio/service.yaml",
    "chart/templates/minio/secret.yaml",
    "chart/templates/minio/statefulset.yaml",
    "chart/templates/minio/job-provisioning.yaml",
    "kind/cluster-apple-silicon.yaml",
    "kind/cluster-linux-cpu.yaml",
    "kind/cluster-linux-gpu.yaml"
  ]

requiredPhrases :: [(FilePath, [String])]
requiredPhrases =
  [ ( "chart/values.yaml",
      [ "runtimeMode:",
        "upstreamCharts:",
        "envoyGateway:",
        "harbor:",
        -- Phase 3 Sprint 3.11 (2026-05-29): the bitnami `minio:`
        -- sub-chart block was retired in favor of the hand-authored
        -- StatefulSet configured under `infernixMinio:`.
        "infernixMinio:",
        "pulsar:",
        "gateway:",
        "repoGateway:",
        "routes:",
        "operatorConsole:",
        "keycloak:",
        "theme:",
        "demo:",
        "enabled:",
        "catalogPayload:",
        "publication:",
        "engineAdapters:",
        "commandEnv:",
        "service:",
        "enabled:",
        "30002",
        "30011",
        "30650",
        "webSocketServiceEnabled: \"true\"",
        "storageClass: infernix-manual",
        "storageClassName: infernix-manual"
      ]
    ),
    -- Phase 7 Sprint 7.17: the demo Deployment's `INFERNIX_MINIO_ACCESS_KEY`
    -- / `INFERNIX_MINIO_SECRET_KEY` entries are retired; credentials now
    -- come from the `cluster-secrets` Secret mount at `/etc/infernix/secrets/`.
    -- Phase 6 Sprint 6.28 follow-on (May 26, 2026): the data-root
    -- override env entry retired too; `dataRoot` decodes from the
    -- mounted host manifest.
    ( "chart/templates/deployment-demo.yaml",
      [ ".Values.demo.enabled",
        "name: infernix-demo",
        "- infernix",
        "- webapp",
        "--config",
        ".Values.clusterConfig.name",
        "name: cluster-config",
        "mountPath: /opt/infernix/cluster.dhall",
        "name: cluster-secrets",
        "mountPath: /etc/infernix/secrets",
        "secretName: infernix-cluster-secrets",
        "emptyDir: {}"
      ]
    ),
    ( "chart/templates/envoyproxy.yaml",
      [ ".Values.repoGateway.enabled",
        "kind: EnvoyProxy",
        "name: infernix-edge",
        "type: NodePort",
        "externalTrafficPolicy: Cluster",
        ".Values.gateway.publishedNodePort"
      ]
    ),
    ( "chart/templates/gatewayclass.yaml",
      [ ".Values.repoGateway.enabled",
        "GatewayClass",
        "name: infernix-gateway",
        "gateway.envoyproxy.io/gatewayclass-controller"
      ]
    ),
    ( "chart/templates/gateway.yaml",
      [ ".Values.repoGateway.enabled",
        "kind: Gateway",
        "name: infernix-edge",
        "parametersRef:",
        "kind: EnvoyProxy",
        ".Values.gateway.listenerPort",
        "allowedRoutes:",
        "from: Same"
      ]
    ),
    -- Phase 7 Sprint 7.7: the supported split topology routes engine
    -- runtime-class + GPU resource shape through
    -- `chart/templates/deployment-engine.yaml`. The legacy
    -- `chart/templates/deployment-service.yaml` is retired together
    -- with the fused `service.*` Deployment.
    --
    -- Phase 4 Sprint 4.13: `INFERNIX_PULSAR_*` + `INFERNIX_DAEMON_*`
    -- env families retired; the daemon now reads them from
    -- `cluster.dhall` mounted from `ConfigMap/{{ .Values.clusterConfig.name }}`
    -- and `--role coordinator|engine` is the typed CLI arg that
    -- replaces `INFERNIX_DAEMON_ROLE`.
    ( "chart/templates/deployment-engine.yaml",
      [ ".Values.engine.enabled",
        "demoConfig.mountPath",
        ".Values.clusterConfig.name",
        "name: cluster-config",
        "mountPath: /opt/infernix/cluster.dhall",
        "name: cluster-secrets",
        "mountPath: /etc/infernix/secrets",
        "secretName: infernix-cluster-secrets",
        "- --role",
        "- engine",
        "runtimeClassName: nvidia",
        "infernix.runtime/gpu",
        "nvidia.com/gpu"
      ]
    ),
    ( "chart/templates/deployment-coordinator.yaml",
      [ ".Values.coordinator.enabled",
        ".Values.clusterConfig.name",
        "name: cluster-config",
        "mountPath: /opt/infernix/cluster.dhall",
        "name: cluster-secrets",
        "mountPath: /etc/infernix/secrets",
        "secretName: infernix-cluster-secrets",
        "- --role",
        "- coordinator"
      ]
    ),
    ( "chart/templates/secret-cluster-secrets.yaml",
      -- Phase 8 Sprint 8.4: the `InfernixSecrets.dhall` manifest body is
      -- rendered by the binary and passed through
      -- `.Values.clusterSecrets.manifest`; the template only `nindent`s it.
      [ "kind: Secret",
        "name: infernix-cluster-secrets",
        "InfernixSecrets.dhall:",
        ".Values.clusterSecrets.manifest",
        "minio.json:",
        "keycloak-admin.json:",
        "keycloak-db.json:",
        "{ \"accessKey\":"
      ]
    ),
    ( "chart/templates/configmap-cluster-config.yaml",
      -- Phase 8 Sprint 8.4: the `cluster.dhall` body is rendered by the
      -- binary and passed through `.Values.clusterConfig.body`; the template
      -- only `nindent`s it (no `let`/schema Dhall inside the template).
      [ ".Values.clusterConfig.name",
        "cluster.dhall:",
        ".Values.clusterConfig.body"
      ]
    ),
    ( "chart/templates/httproutes.yaml",
      [ ".Values.repoGateway.enabled",
        ".Values.routes",
        ".Values.demo.enabled",
        "kind: HTTPRoute",
        "infernix.io/purpose:",
        "value: {{ $route.pathPrefix }}",
        "name: {{ $route.serviceName }}",
        "replacePrefixMatch: {{ $route.rewritePrefix }}"
      ]
    ),
    ( "chart/templates/runtimeclass-nvidia.yaml",
      ["RuntimeClass", "name: nvidia", "handler: nvidia", ".Values.runtimeMode", "linux-gpu"]
    ),
    ("chart/templates/service-demo.yaml", [".Values.demo.enabled", "name: infernix-demo", "targetPort: {{ .Values.demo.port }}"]),
    ( "chart/templates/keycloak/configmap-theme.yaml",
      [ "name: infernix-keycloak-theme",
        "theme.properties:",
        "parent=keycloak.v2",
        "messages_en.properties:",
        "loginAccountTitle=Sign in to Infernix",
        "infernix.css:"
      ]
    ),
    ( "chart/templates/keycloak/deployment.yaml",
      [ "name: infernix-keycloak",
        "--import-realm",
        "--hostname-strict=true",
        "--http-relative-path=/auth",
        "name: login-theme",
        "mountPath: /opt/keycloak/themes/{{ .Values.keycloak.theme.name }}",
        "name: infernix-keycloak-theme"
      ]
    ),
    ( "chart/templates/securitypolicy-operator-routes.yaml",
      [ "kind: SecurityPolicy",
        "name: infernix-operator-routes-jwt",
        -- all four admin-gated operator routes must be targeted
        "name: infernix-harbor-portal",
        "name: infernix-harbor-api",
        "name: infernix-pulsar-admin",
        "name: infernix-pulsar-ws",
        "jwt:",
        "cookies:",
        ".Values.operatorConsole.jwtGating.cookieName",
        "remoteJWKS:",
        ".Values.clusterConfig.keycloak.jwksUrl",
        -- Phase 9: a valid JWT is necessary but not sufficient — the admin
        -- authorization rule (deny-by-default + admin realm role) must be present
        "authorization:",
        "defaultAction: Deny",
        ".Values.keycloak.realm.adminRealmRole"
      ]
    )
  ]

data GeneratedSectionRule = GeneratedSectionRule
  { generatedSectionPath :: FilePath,
    generatedSectionStartMarker :: String,
    generatedSectionEndMarker :: String,
    generatedSectionExpected :: String
  }

generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules =
  [ GeneratedSectionRule
      { generatedSectionPath = "chart/templates/httproutes.yaml",
        generatedSectionStartMarker = "{{/* infernix:route-registry:start */}}",
        generatedSectionEndMarker = "{{/* infernix:route-registry:end */}}",
        generatedSectionExpected = trimTrailingNewlines renderChartRouteRegistryCommentSection
      }
  ]

runChartLint :: IO ()
runChartLint = do
  paths <- discoverPaths
  forM_ requiredFiles $ \relativePath -> do
    exists <- doesFileExist (repoRoot paths </> relativePath)
    unless exists $
      ioError (userError ("missing required platform asset: " <> relativePath))
  forM_ requiredPhrases $ \(relativePath, phrases) -> do
    contents <- readFile (repoRoot paths </> relativePath)
    forM_ phrases $ \requiredPhrase ->
      unless (requiredPhrase `contains` contents) $
        ioError (userError (relativePath <> " is missing required phrase: " <> requiredPhrase))
  forM_ generatedSectionRules $ \rule -> do
    contents <- readFile (repoRoot paths </> generatedSectionPath rule)
    validateGeneratedSection rule contents
  forM_ envBlockRejectionPaths $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    forM_ (lines contents) $ \lineValue ->
      when
        (isEnvBlockStartLine lineValue)
        ( ioError
            ( userError
                ( relativePath
                    <> ": Phase 6 Sprint 6.28 chart lint gate rejects `env:`/`envFrom:` blocks "
                    <> "in infernix-owned deployment templates. The supported flow reads "
                    <> "runtime wiring from the mounted `cluster.dhall` ConfigMap and "
                    <> "credentials from the mounted `infernix-cluster-secrets` Secret. "
                    <> "Found `env:`/`envFrom:` at: "
                    <> lineValue
                )
            )
        )
  forM_ dhallBodyRejectionPaths $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    forM_ (lines contents) $ \lineValue ->
      when
        (isDhallBodyLine lineValue)
        ( ioError
            ( userError
                ( relativePath
                    <> ": Phase 8 Sprint 8.4 chart lint gate rejects `let`/schema Dhall "
                    <> "bodies inside chart templates. The `infernix` binary is the sole "
                    <> "generator of every `.dhall`; templates only `nindent` a "
                    <> "binary-produced string (e.g. `.Values.clusterConfig.body`, "
                    <> "`.Values.clusterSecrets.manifest`). Found a Dhall body line at: "
                    <> lineValue
                )
            )
        )
  forM_ kindLoopbackConfigPaths $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    checkKindLoopbackBindings relativePath contents

-- | Phase 6 Sprint 6.28 follow-on (May 26, 2026): the chart lint
-- gate rejects new @env:@ blocks in the three infernix-owned
-- daemon deployment templates. Runtime wiring must flow through
-- the mounted @cluster.dhall@ ConfigMap; credentials must flow
-- through the mounted @infernix-cluster-secrets@ Secret. Comments
-- mentioning @env:@ are fine — the check only looks at top-level
-- pod-spec @env:@ lines (whitespace + @env:@).
envBlockRejectionPaths :: [FilePath]
envBlockRejectionPaths =
  [ "chart/templates/deployment-coordinator.yaml",
    "chart/templates/deployment-engine.yaml",
    "chart/templates/deployment-demo.yaml"
  ]

-- | Phase 8 Sprint 8.4: the chart templates that previously carried an
-- inline `let …/in …` Dhall body (the cluster-config ConfigMap and the
-- cluster-secrets Secret manifest). Both now `nindent` a binary-produced
-- string; this gate keeps any `let`/schema Dhall from re-entering a chart
-- template.
dhallBodyRejectionPaths :: [FilePath]
dhallBodyRejectionPaths =
  [ "chart/templates/configmap-cluster-config.yaml",
    "chart/templates/secret-cluster-secrets.yaml"
  ]

-- | Phase 9 Sprint 9.4: the data-plane loopback invariant. Every host port
-- mapping in the committed Kind cluster configs — the MinIO S3 NodePort
-- (30011) and Pulsar proxy NodePorts (30080/30650) that the Apple host worker
-- reaches directly, and the admin-gated Envoy edge (30090) — must bind to
-- @127.0.0.1@ so the cluster data plane and the browser edge are reachable
-- only on loopback, never on a routable host interface. The generated
-- @renderKindConfig@ path is pinned by a unit assertion; this gate pins the
-- committed reference configs.
kindLoopbackConfigPaths :: [FilePath]
kindLoopbackConfigPaths =
  [ "kind/cluster-apple-silicon.yaml",
    "kind/cluster-linux-cpu.yaml",
    "kind/cluster-linux-gpu.yaml"
  ]

-- | Assert every @extraPortMappings@ entry in a Kind config binds to loopback.
-- A @- containerPort:@ line opens a mapping that must carry a
-- @listenAddress: "127.0.0.1"@ before the next mapping or end of file; any
-- @listenAddress:@ whose value is not @127.0.0.1@ is rejected outright.
checkKindLoopbackBindings :: FilePath -> String -> IO ()
checkKindLoopbackBindings relativePath = go False . lines
  where
    go pendingLoopback [] =
      when pendingLoopback (missingLoopback "end of file")
    go pendingLoopback (lineValue : rest) =
      let trimmed = dropWhile (`elem` (" \t" :: String)) lineValue
       in if "- containerPort:" `prefixOf` trimmed
            then do
              when pendingLoopback (missingLoopback lineValue)
              go True rest
            else
              if "listenAddress:" `prefixOf` trimmed
                then do
                  unless (isLoopbackListenAddress trimmed) (nonLoopback lineValue)
                  go False rest
                else go pendingLoopback rest
    missingLoopback context =
      ioError
        ( userError
            ( relativePath
                <> ": Phase 9 Sprint 9.4 requires every Kind extraPortMappings entry to bind to "
                <> "127.0.0.1 (the data-plane + admin-gated-edge loopback invariant). A "
                <> "containerPort mapping has no `listenAddress: \"127.0.0.1\"` before "
                <> context
            )
        )
    nonLoopback lineValue =
      ioError
        ( userError
            ( relativePath
                <> ": Phase 9 Sprint 9.4 rejects a non-loopback Kind host port binding. Every "
                <> "extraPortMappings entry must set `listenAddress: \"127.0.0.1\"`. Found: "
                <> lineValue
            )
        )

-- | Whether a trimmed @listenAddress:@ line binds to @127.0.0.1@, tolerating
-- quoting and surrounding whitespace.
isLoopbackListenAddress :: String -> Bool
isLoopbackListenAddress trimmed =
  let afterKey = drop (length ("listenAddress:" :: String)) trimmed
      value = filter (`notElem` ("\"' \t" :: String)) afterKey
   in value == "127.0.0.1"

-- | Whether a chart-template line is an inline Dhall `let` binding or a
-- schema-record type line. Comment lines (`#`, `{{/*`, and the leading `*`
-- of a Helm block comment) are skipped; the check targets real template
-- content lines. A `let ` binding starts a Dhall body; a bare
-- `{ field : Type` record type line is the other schema shape.
isDhallBodyLine :: String -> Bool
isDhallBodyLine lineValue =
  let trimmed = dropWhile (`elem` (" \t" :: String)) lineValue
   in not (isCommentLine trimmed)
        && ( "let " `prefixOf` trimmed
               || "in  {" `prefixOf` trimmed
               || "in {" `prefixOf` trimmed
           )

isCommentLine :: String -> Bool
isCommentLine ('#' : _) = True
isCommentLine ('*' : _) = True
isCommentLine ('{' : '{' : '/' : '*' : _) = True
isCommentLine _ = False

-- | Whether a single chart-template line starts an @env:@ or @envFrom:@ block.
-- Matches the canonical pod-spec position (leading whitespace, then the literal
-- @env:@ / @envFrom:@, optionally trailing whitespace). Comment lines starting
-- with @#@ are skipped. Only the three infernix-owned daemon templates
-- ('envBlockRejectionPaths') are scanned; the MinIO and Keycloak upstream
-- component templates carry their own @envFrom:@ surfaces and are intentionally
-- out of scope.
isEnvBlockStartLine :: String -> Bool
isEnvBlockStartLine lineValue =
  let leadingTrimmed = dropWhile (`elem` (" \t" :: String)) lineValue
   in isEnvBlockTrimmed leadingTrimmed

isEnvBlockTrimmed :: String -> Bool
isEnvBlockTrimmed ('#' : _) = False
isEnvBlockTrimmed trimmed =
  let normalized = dropTrailingWhitespace trimmed
   in normalized == "env:" || normalized == "envFrom:"

dropTrailingWhitespace :: String -> String
dropTrailingWhitespace = reverse . dropWhile (`elem` (" \t\r" :: String)) . reverse

contains :: String -> String -> Bool
contains needle haystack = any (needle `prefixOf`) (tails haystack)

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (expected : expectedRest) (actual : actualRest) =
  expected == actual && prefixOf expectedRest actualRest

tails :: [a] -> [[a]]
tails [] = [[]]
tails value@(_ : rest) = value : tails rest

validateGeneratedSection :: GeneratedSectionRule -> String -> IO ()
validateGeneratedSection rule contents =
  case extractGeneratedSection (generatedSectionStartMarker rule) (generatedSectionEndMarker rule) contents of
    Nothing ->
      ioError
        ( userError
            ( generatedSectionPath rule
                <> " is missing the generated section markers "
                <> generatedSectionStartMarker rule
                <> " and "
                <> generatedSectionEndMarker rule
            )
        )
    Just renderedSection ->
      unless
        (trimTrailingNewlines renderedSection == generatedSectionExpected rule)
        ( ioError
            ( userError
                ( generatedSectionPath rule
                    <> " has drifted from the Haskell route registry generated section"
                )
            )
        )

extractGeneratedSection :: String -> String -> String -> Maybe String
extractGeneratedSection startMarker endMarker contents = do
  let contentLines = lines contents
  startIndex <- findLineIndex startMarker contentLines
  endIndex <- findLineIndex endMarker contentLines
  if endIndex <= startIndex
    then Nothing
    else Just (unlines (take (endIndex - startIndex - 1) (drop (startIndex + 1) contentLines)))

findLineIndex :: String -> [String] -> Maybe Int
findLineIndex target = go 0
  where
    go _ [] = Nothing
    go index (lineValue : remaining)
      | lineValue == target = Just index
      | otherwise = go (index + 1) remaining

trimTrailingNewlines :: String -> String
trimTrailingNewlines =
  reverse . dropWhile (`elem` ['\n', '\r']) . reverse
