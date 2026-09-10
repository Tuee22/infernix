{-# LANGUAGE OverloadedStrings #-}

module Infernix.Routes
  ( routeHelmValues,
    routeInventory,
    validateDeployedRoutes,
    routePublicationUpstreams,
    renderChartRouteRegistryCommentSection,
    renderClusterBootstrapRouteChecksSection,
    renderEdgeRoutingInventorySection,
    renderRegistryRouteSummarySection,
    renderMinioRouteSummarySection,
    renderPulsarRouteSummarySection,
    renderReadmeRouteSummarySection,
    renderWebPortalRoutesSection,
  )
where

import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types qualified as Aeson
import Data.List (intercalate, sort)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Types

data RouteSpec = RouteSpec
  { routeName :: Text,
    routePathPrefix :: Text,
    routePurpose :: Text,
    routeServiceName :: Text,
    routeServicePort :: Int,
    routeRewritePrefix :: Maybe Text,
    routeDemoOnly :: Bool,
    routePublicationId :: Maybe Text,
    routePublicationTargetSurface :: Maybe Text,
    routePublicationDurableState :: Maybe Text
  }

routeInventory :: Bool -> [RouteInfo]
routeInventory demoEnabled =
  [ RouteInfo (routePathPrefix routeSpec) (routePurpose routeSpec)
  | routeSpec <- publishedRoutes demoEnabled
  ]

-- | Compare live Gateway API observations with the binary-owned route registry.
-- Defaults inserted by the API server are accepted only when they preserve the
-- exact parent, match, rewrite, and backend contract. Readiness must describe
-- the current object generation, not a superseded route specification.
validateDeployedRoutes :: Bool -> Aeson.Value -> Either String ()
validateDeployedRoutes demoEnabled payload = do
  observed <- Aeson.parseEither (Aeson.withObject "HTTPRouteList" (\objectValue -> objectValue Aeson..: "items" >>= mapM parseDeployedRoute)) payload
  let expected =
        [ (routeName spec, routePathPrefix spec, routeServiceName spec, routeServicePort spec, routeRewritePrefix spec)
        | spec <- publishedRoutes demoEnabled
        ]
  unless (sort observed == sort expected) $
    Left ("deployed HTTPRoute inventory differs from the route registry; expected " <> show (sort expected) <> "; observed " <> show (sort observed))

type DeployedRoute = (Text, Text, Text, Int, Maybe Text)

parseDeployedRoute :: Aeson.Value -> Aeson.Parser DeployedRoute
parseDeployedRoute = Aeson.withObject "HTTPRoute" $ \objectValue -> do
  metadata <- objectValue Aeson..: "metadata"
  routeNameValue <- metadata Aeson..: "name"
  namespaceValue <- metadata Aeson..: "namespace"
  unless (namespaceValue == ("platform" :: Text)) (fail "HTTPRoute belongs to another namespace")
  generation <- metadata Aeson..: "generation"
  unless (generation > (0 :: Integer)) (fail "HTTPRoute generation is invalid")
  deletion <- metadata Aeson..:? "deletionTimestamp"
  unless (deletion == (Nothing :: Maybe Text)) (fail "HTTPRoute is being deleted")
  spec <- objectValue Aeson..: "spec"
  hostnames <- spec Aeson..:? "hostnames" Aeson..!= []
  unless (null (hostnames :: [Text])) (fail "HTTPRoute unexpectedly restricts hostnames")
  parent <- spec Aeson..: "parentRefs" >>= oneRouteValue "spec.parentRefs"
  parseRouteParent parent
  rule <- spec Aeson..: "rules" >>= oneRouteValue "spec.rules"
  matchValue <- rule Aeson..: "matches" >>= oneRouteValue "rule.matches"
  unless (KeyMap.keys matchValue == ["path"]) (fail "HTTPRoute has an unexpected match condition")
  matchedPath <- matchValue Aeson..: "path"
  matchType <- matchedPath Aeson..: "type"
  unless (matchType == ("PathPrefix" :: Text)) (fail "HTTPRoute does not use a prefix match")
  prefixValue <- matchedPath Aeson..: "value"
  backend <- rule Aeson..: "backendRefs" >>= oneRouteValue "rule.backendRefs"
  backendName <- backend Aeson..: "name"
  backendPort <- backend Aeson..: "port"
  backendNamespace <- backend Aeson..:? "namespace" Aeson..!= "platform"
  backendGroup <- backend Aeson..:? "group" Aeson..!= ""
  backendKind <- backend Aeson..:? "kind" Aeson..!= "Service"
  backendWeight <- backend Aeson..:? "weight" Aeson..!= (1 :: Int)
  backendFilters <- backend Aeson..:? "filters" Aeson..!= []
  unless
    ( backendNamespace == ("platform" :: Text)
        && backendGroup == ("" :: Text)
        && backendKind == ("Service" :: Text)
        && backendWeight == 1
        && null (backendFilters :: [Aeson.Value])
    )
    (fail "HTTPRoute backend has unexpected namespace, kind, weight, or filters")
  filters <- rule Aeson..:? "filters" Aeson..!= []
  rewriteValue <- parseRouteRewrite filters
  statusValue <- objectValue Aeson..: "status"
  parentStatus <- statusValue Aeson..: "parents" >>= oneRouteValue "status.parents"
  parentStatus Aeson..: "parentRef" >>= parseRouteParent
  controller <- parentStatus Aeson..: "controllerName"
  unless (controller == ("gateway.envoyproxy.io/gatewayclass-controller" :: Text)) (fail "HTTPRoute is not reconciled by the Envoy Gateway controller")
  conditions <- parentStatus Aeson..: "conditions"
  mapM_ (requireRouteCondition generation conditions) ["Accepted", "ResolvedRefs"]
  pure (routeNameValue, prefixValue, backendName, backendPort, rewriteValue)

oneRouteValue :: String -> [value] -> Aeson.Parser value
oneRouteValue _ [value] = pure value
oneRouteValue label _ = fail ("HTTPRoute requires exactly one " <> label)

parseRouteParent :: Aeson.Object -> Aeson.Parser ()
parseRouteParent parent = do
  parentName <- parent Aeson..: "name"
  parentSection <- parent Aeson..: "sectionName"
  parentNamespace <- parent Aeson..:? "namespace" Aeson..!= "platform"
  parentGroup <- parent Aeson..:? "group" Aeson..!= "gateway.networking.k8s.io"
  parentKind <- parent Aeson..:? "kind" Aeson..!= "Gateway"
  parentPort <- parent Aeson..:? "port"
  unless
    ( parentName == ("infernix-edge" :: Text)
        && parentSection == ("http" :: Text)
        && parentNamespace == ("platform" :: Text)
        && parentGroup == ("gateway.networking.k8s.io" :: Text)
        && parentKind == ("Gateway" :: Text)
        && parentPort == (Nothing :: Maybe Int)
    )
    (fail "HTTPRoute parent differs from the local infernix-edge HTTP listener")

parseRouteRewrite :: [Aeson.Object] -> Aeson.Parser (Maybe Text)
parseRouteRewrite [] = pure Nothing
parseRouteRewrite [filterValue] = do
  filterType <- filterValue Aeson..: "type"
  unless (filterType == ("URLRewrite" :: Text)) (fail "HTTPRoute has an unexpected rule filter")
  rewrite <- filterValue Aeson..: "urlRewrite"
  unless (KeyMap.keys rewrite == ["path"]) (fail "HTTPRoute rewrite changes more than the path")
  rewritePath <- rewrite Aeson..: "path"
  rewriteType <- rewritePath Aeson..: "type"
  unless (rewriteType == ("ReplacePrefixMatch" :: Text)) (fail "HTTPRoute has an unexpected rewrite type")
  Just <$> rewritePath Aeson..: "replacePrefixMatch"
parseRouteRewrite _ = fail "HTTPRoute has multiple rule filters"

requireRouteCondition :: Integer -> [Aeson.Object] -> Text -> Aeson.Parser ()
requireRouteCondition generation conditions wanted = do
  typedConditions <- mapM (\condition -> (,) <$> condition Aeson..: "type" <*> pure condition) conditions
  condition <- oneRouteValue ("condition " <> Text.unpack wanted) [value | (kind, value) <- typedConditions, kind == wanted]
  statusValue <- condition Aeson..: "status"
  observedGeneration <- condition Aeson..: "observedGeneration"
  unless (statusValue == ("True" :: Text) && observedGeneration == generation) $
    fail ("HTTPRoute " <> Text.unpack wanted <> " is not true for its current generation")

routePublicationUpstreams :: Bool -> ApiUpstream -> Text -> [PublicationUpstream]
routePublicationUpstreams demoEnabled apiUpstream inferenceDispatchMode =
  [ PublicationUpstream
      { publicationUpstreamId = upstreamId,
        publicationUpstreamRoutePrefix = routePathPrefix routeSpec,
        publicationUpstreamTargetSurface = publicationTargetSurface routeSpec apiUpstream inferenceDispatchMode,
        publicationUpstreamHealthStatus = "published",
        publicationUpstreamDurableBackendState = durableState
      }
  | routeSpec <- publicationRoutes demoEnabled,
    Just upstreamId <- [routePublicationId routeSpec],
    Just durableState <- [routePublicationDurableState routeSpec]
  ]

routeHelmValues :: Bool -> [String]
routeHelmValues demoEnabled =
  "routes:" : concatMap renderRouteValueLines (publishedRoutes demoEnabled)

renderReadmeRouteSummarySection :: String
renderReadmeRouteSummarySection =
  unlines
    [ "- always-published routed prefixes: " <> renderRoutePrefixList (alwaysPublishedRoutes routeSpecs),
      "- demo-only routed prefixes (present when `.dhall` `demo_ui = True`): " <> renderRoutePrefixList (demoOnlyRoutes routeSpecs),
      "- registry-owned rewrites: " <> renderRewriteList (rewrittenRoutes routeSpecs)
    ]

renderEdgeRoutingInventorySection :: String
renderEdgeRoutingInventorySection =
  unlines
    ( [ "| Public prefix | Visibility | Purpose | Backend | Rewrite |",
        "|---------------|------------|---------|---------|---------|"
      ]
        <> map renderEdgeRoutingRow routeSpecs
    )

renderWebPortalRoutesSection :: String
renderWebPortalRoutesSection =
  unlines
    ( [ "Demo-only prefixes:",
        "",
        "| Routed prefix | Purpose | Notes |",
        "|---------------|---------|-------|"
      ]
        <> map renderWebPortalRow (demoOnlyRoutes routeSpecs)
        <> [ "",
             "Always-published operator prefixes:",
             "",
             "| Routed prefix | Purpose | Notes |",
             "|---------------|---------|-------|"
           ]
        <> map renderWebPortalRow (alwaysPublishedRoutes routeSpecs)
    )

-- | Phase 3 Sprint 3.17: the in-cluster image repository is the single-binary
-- @registry:2@ distribution registry, which serves the OCI @\/v2@ API and
-- nothing else. It ships no portal, so the operator surface is one API prefix
-- rather than a browser console.
renderRegistryRouteSummarySection :: String
renderRegistryRouteSummarySection =
  renderToolRouteSummarySection (filter (\routeSpec -> routePathPrefix routeSpec == "/registry") routeSpecs)

-- | Phase 3 Sprint 3.13 removed the external @/minio/s3@ gateway route. MinIO
-- is no longer browser-reachable; the @infernix-demo@ webapp @/api/objects@
-- proxy is the only external file-storage surface, so this section states the
-- de-exposed posture rather than enumerating a removed route.
renderMinioRouteSummarySection :: String
renderMinioRouteSummarySection =
  "- MinIO has no external gateway route; the browser reaches objects only through the `infernix-demo` webapp `/api/objects` proxy.\n"

renderPulsarRouteSummarySection :: String
renderPulsarRouteSummarySection =
  renderToolRouteSummarySection (filter (\routeSpec -> routePathPrefix routeSpec `elem` ["/pulsar/admin", "/pulsar/ws"]) routeSpecs)

renderClusterBootstrapRouteChecksSection :: String
renderClusterBootstrapRouteChecksSection =
  unlines
    [ "- `curl http://127.0.0.1:<port>/registry/` checks the `/registry -> /v2` rewrite into the in-cluster registry Service.",
      "- `curl http://127.0.0.1:<port>/registry/_catalog` lists the published repositories through the same rewrite.",
      "- `curl http://127.0.0.1:<port>/pulsar/admin/admin/v2/clusters` checks the `/pulsar/admin -> /` rewrite into Pulsar's `/admin/v2` surface.",
      "- `curl http://127.0.0.1:<port>/pulsar/ws/v2/producer/infernix/demo/demo` checks the `/pulsar/ws -> /ws` rewrite and returns `405 Method Not Allowed` on the real cluster path."
    ]

renderChartRouteRegistryCommentSection :: String
renderChartRouteRegistryCommentSection =
  unlines
    ( "# Route registry summary generated from `src/Infernix/Routes.hs`."
        : map renderChartRouteComment routeSpecs
    )

publishedRoutes :: Bool -> [RouteSpec]
publishedRoutes demoEnabled =
  filter (\routeSpec -> demoEnabled || not (routeDemoOnly routeSpec)) routeSpecs

publicationRoutes :: Bool -> [RouteSpec]
publicationRoutes demoEnabled =
  filter hasPublicationMetadata (publishedRoutes demoEnabled)
  where
    hasPublicationMetadata routeSpec =
      case routePublicationId routeSpec of
        Just _ -> True
        Nothing -> False

publicationTargetSurface :: RouteSpec -> ApiUpstream -> Text -> Text
publicationTargetSurface routeSpec _apiUpstream inferenceDispatchMode =
  case (routePublicationId routeSpec, routePublicationTargetSurface routeSpec) of
    (Just "demo", _) -> "cluster-resident demo surface via " <> inferenceDispatchMode
    (_, Just targetSurface) -> targetSurface
    _ -> ""

renderRouteValueLines :: RouteSpec -> [String]
renderRouteValueLines routeSpec =
  [ "  - name: " <> Text.unpack (routeName routeSpec),
    "    purpose: " <> showText (routePurpose routeSpec),
    "    pathPrefix: " <> showText (routePathPrefix routeSpec),
    "    serviceName: " <> Text.unpack (routeServiceName routeSpec),
    "    servicePort: " <> show (routeServicePort routeSpec),
    "    demoOnly: " <> yamlBool (routeDemoOnly routeSpec),
    "    rewritePrefix: " <> maybe "\"\"" showText (routeRewritePrefix routeSpec)
  ]

routeSpecs :: [RouteSpec]
routeSpecs =
  [ RouteSpec
      "infernix-demo-root"
      "/"
      "Demo SPA"
      "infernix-demo"
      80
      Nothing
      True
      (Just "demo")
      Nothing
      (Just "generated web bundle and Haskell demo daemon"),
    RouteSpec
      "infernix-demo-api"
      "/api"
      "Demo API"
      "infernix-demo"
      80
      Nothing
      True
      Nothing
      Nothing
      Nothing,
    RouteSpec
      "infernix-registry-api"
      "/registry"
      "Image registry API"
      "infernix-registry"
      5000
      (Just "/v2")
      False
      (Just "registry")
      (Just "HTTPRoute -> in-cluster registry Service")
      (Just "envoy-gateway-routed registry deployment"),
    RouteSpec
      "infernix-pulsar-admin"
      "/pulsar/admin"
      "Pulsar admin surface"
      "infernix-infernix-pulsar-proxy"
      80
      (Just "/")
      False
      Nothing
      Nothing
      Nothing,
    RouteSpec
      "infernix-pulsar-ws"
      "/pulsar/ws"
      "Pulsar websocket surface"
      "infernix-infernix-pulsar-proxy"
      80
      (Just "/ws")
      False
      (Just "pulsar")
      (Just "HTTPRoute -> Pulsar Service")
      (Just "envoy-gateway-routed pulsar deployment"),
    RouteSpec
      "infernix-keycloak-auth"
      "/auth"
      "Keycloak SSO"
      "infernix-keycloak"
      8080
      Nothing
      True
      (Just "keycloak")
      (Just "HTTPRoute -> Keycloak Service")
      (Just "envoy-gateway-routed keycloak deployment"),
    RouteSpec
      "infernix-demo-ws"
      "/ws"
      "Demo durable-context WebSocket"
      "infernix-demo"
      80
      Nothing
      True
      Nothing
      Nothing
      Nothing,
    RouteSpec
      "infernix-demo-objects-api"
      "/api/objects"
      "Demo webapp object-proxy (upload/download/list/delete)"
      "infernix-demo"
      80
      Nothing
      True
      Nothing
      Nothing
      Nothing
  ]

yamlBool :: Bool -> String
yamlBool value
  | value = "true"
  | otherwise = "false"

showText :: Text -> String
showText = show . Text.unpack

alwaysPublishedRoutes :: [RouteSpec] -> [RouteSpec]
alwaysPublishedRoutes = filter (not . routeDemoOnly)

demoOnlyRoutes :: [RouteSpec] -> [RouteSpec]
demoOnlyRoutes = filter routeDemoOnly

rewrittenRoutes :: [RouteSpec] -> [RouteSpec]
rewrittenRoutes = filter (isJust . routeRewritePrefix)

renderRoutePrefixList :: [RouteSpec] -> String
renderRoutePrefixList routeValues =
  intercalate ", " (map (code . routePathPrefix) routeValues)

renderRewriteList :: [RouteSpec] -> String
renderRewriteList routeValues =
  intercalate "; " (map renderRewriteSummary routeValues)

renderEdgeRoutingRow :: RouteSpec -> String
renderEdgeRoutingRow routeSpec =
  "| "
    <> code (routePathPrefix routeSpec)
    <> " | "
    <> routeVisibilityLabel routeSpec
    <> " | "
    <> Text.unpack (routePurpose routeSpec)
    <> " | "
    <> backendRef routeSpec
    <> " | "
    <> rewriteBehavior routeSpec
    <> " |"

renderWebPortalRow :: RouteSpec -> String
renderWebPortalRow routeSpec =
  "| "
    <> code (routePathPrefix routeSpec)
    <> " | "
    <> Text.unpack (routePurpose routeSpec)
    <> " | "
    <> webPortalNotes routeSpec
    <> " |"

renderToolRouteSummarySection :: [RouteSpec] -> String
renderToolRouteSummarySection routeValues =
  unlines (map renderToolRouteLine routeValues)

renderToolRouteLine :: RouteSpec -> String
renderToolRouteLine routeSpec =
  "- "
    <> code (routePathPrefix routeSpec)
    <> " -> "
    <> backendRef routeSpec
    <> "; "
    <> rewriteSentence routeSpec

renderChartRouteComment :: RouteSpec -> String
renderChartRouteComment routeSpec =
  "# - "
    <> code (routePathPrefix routeSpec)
    <> " -> "
    <> backendRef routeSpec
    <> " ("
    <> routeVisibilityLabel routeSpec
    <> "; "
    <> rewriteBehavior routeSpec
    <> ")"

routeVisibilityLabel :: RouteSpec -> String
routeVisibilityLabel routeSpec
  | routeDemoOnly routeSpec = "demo-only"
  | otherwise = "always published"

backendRef :: RouteSpec -> String
backendRef routeSpec =
  code (routeServiceName routeSpec <> ":" <> Text.pack (show (routeServicePort routeSpec)))

rewriteBehavior :: RouteSpec -> String
rewriteBehavior routeSpec =
  maybe "no rewrite" (const (renderRewriteSummary routeSpec)) (routeRewritePrefix routeSpec)

renderRewriteSummary :: RouteSpec -> String
renderRewriteSummary routeSpec =
  case routeRewritePrefix routeSpec of
    Just rewritePrefix -> code (routePathPrefix routeSpec) <> " -> " <> code rewritePrefix
    Nothing -> "no rewrite"

rewriteSentence :: RouteSpec -> String
rewriteSentence routeSpec =
  case routeRewritePrefix routeSpec of
    Just rewritePrefix -> "rewrites to upstream " <> code rewritePrefix
    Nothing -> "forwards without a rewrite"

webPortalNotes :: RouteSpec -> String
webPortalNotes routeSpec =
  case routePathPrefix routeSpec of
    "/" -> "PureScript demo SPA served by `infernix-demo`."
    "/api" -> "Covers `/api/publication`, `/api/cache`, `/api/models`, and `/api/demo-config`."
    "/registry" -> "Rewrites to upstream `/v2` before forwarding to `infernix-registry:5000`."
    "/pulsar/admin" -> "Rewrites to upstream `/` before forwarding to `infernix-infernix-pulsar-proxy:80`."
    "/pulsar/ws" -> "Rewrites to upstream `/ws` before forwarding to `infernix-infernix-pulsar-proxy:80`."
    _ -> "Registry-defined route."

code :: Text -> String
code value = "`" <> Text.unpack value <> "`"
