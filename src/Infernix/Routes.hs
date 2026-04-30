{-# LANGUAGE OverloadedStrings #-}

module Infernix.Routes
  ( routeHelmValues,
    routeInventory,
    routePublicationUpstreams,
    renderChartRouteRegistryCommentSection,
    renderClusterBootstrapRouteChecksSection,
    renderEdgeRoutingInventorySection,
    renderHarborRouteSummarySection,
    renderMinioRouteSummarySection,
    renderPulsarRouteSummarySection,
    renderReadmeRouteSummarySection,
    renderWebPortalRoutesSection,
  )
where

import Data.List (intercalate)
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

routePublicationUpstreams :: Bool -> ApiUpstream -> [PublicationUpstream]
routePublicationUpstreams demoEnabled apiUpstream =
  [ PublicationUpstream
      { publicationUpstreamId = upstreamId,
        publicationUpstreamRoutePrefix = routePathPrefix routeSpec,
        publicationUpstreamTargetSurface = publicationTargetSurface routeSpec apiUpstream,
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

renderHarborRouteSummarySection :: String
renderHarborRouteSummarySection =
  renderToolRouteSummarySection (filter (\routeSpec -> routePathPrefix routeSpec `elem` ["/harbor/api", "/harbor"]) routeSpecs)

renderMinioRouteSummarySection :: String
renderMinioRouteSummarySection =
  renderToolRouteSummarySection (filter (\routeSpec -> routePathPrefix routeSpec `elem` ["/minio/console", "/minio/s3"]) routeSpecs)

renderPulsarRouteSummarySection :: String
renderPulsarRouteSummarySection =
  renderToolRouteSummarySection (filter (\routeSpec -> routePathPrefix routeSpec `elem` ["/pulsar/admin", "/pulsar/ws"]) routeSpecs)

renderClusterBootstrapRouteChecksSection :: String
renderClusterBootstrapRouteChecksSection =
  unlines
    [ "- `curl http://127.0.0.1:<port>/harbor` checks the Harbor portal route.",
      "- `curl http://127.0.0.1:<port>/harbor/api/v2.0/projects` checks the `/harbor/api -> /api` rewrite into the Harbor core service.",
      "- `curl http://127.0.0.1:<port>/minio/console/browser` checks the `/minio/console -> /` rewrite into the MinIO console service.",
      "- `curl http://127.0.0.1:<port>/minio/s3/models/demo.bin` checks the `/minio/s3 -> /` rewrite into the MinIO S3 service.",
      "- `curl http://127.0.0.1:<port>/pulsar/admin/admin/v2/clusters` checks the `/pulsar/admin -> /` rewrite into Pulsar's `/admin/v2` surface.",
      "- `curl http://127.0.0.1:<port>/pulsar/ws/v2/producer/public/default/demo` checks the `/pulsar/ws -> /ws` rewrite and returns `405 Method Not Allowed` on the real cluster path."
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

publicationTargetSurface :: RouteSpec -> ApiUpstream -> Text
publicationTargetSurface routeSpec apiUpstream =
  case (routePublicationId routeSpec, routePublicationTargetSurface routeSpec) of
    (Just "demo", _) ->
      case apiUpstreamMode apiUpstream of
        "host-demo-bridge" -> "host-native demo bridge"
        _ -> "cluster-resident demo surface"
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
      "Demo workbench"
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
      "infernix-demo-objects"
      "/objects"
      "Demo object store"
      "infernix-demo"
      80
      Nothing
      True
      Nothing
      Nothing
      Nothing,
    RouteSpec
      "infernix-harbor-api"
      "/harbor/api"
      "Harbor API"
      "infernix-harbor-core"
      80
      (Just "/api")
      False
      Nothing
      Nothing
      Nothing,
    RouteSpec
      "infernix-harbor-portal"
      "/harbor"
      "Harbor portal"
      "infernix-harbor-portal"
      80
      (Just "/")
      False
      (Just "harbor")
      (Just "HTTPRoute -> Harbor portal Service")
      (Just "envoy-gateway-routed harbor deployment"),
    RouteSpec
      "infernix-minio-console"
      "/minio/console"
      "MinIO console"
      "infernix-minio-console"
      9090
      (Just "/")
      False
      Nothing
      Nothing
      Nothing,
    RouteSpec
      "infernix-minio-s3"
      "/minio/s3"
      "MinIO S3 API"
      "infernix-minio"
      9000
      (Just "/")
      False
      (Just "minio")
      (Just "HTTPRoute -> MinIO Service")
      (Just "envoy-gateway-routed minio deployment"),
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
      (Just "envoy-gateway-routed pulsar deployment")
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
    "/" -> "PureScript manual inference workbench served by `infernix-demo`."
    "/api" -> "Covers `/api/publication`, `/api/cache`, `/api/models`, `/api/demo-config`, and `/api/inference`."
    "/objects" -> "Serves `GET /objects/:objectRef` for large outputs."
    "/harbor/api" -> "Rewrites to upstream `/api` before forwarding to `infernix-harbor-core:80`."
    "/harbor" -> "Rewrites to upstream `/` before forwarding to `infernix-harbor-portal:80`."
    "/minio/console" -> "Rewrites to upstream `/` before forwarding to `infernix-minio-console:9090`."
    "/minio/s3" -> "Rewrites to upstream `/` before forwarding to `infernix-minio:9000`."
    "/pulsar/admin" -> "Rewrites to upstream `/` before forwarding to `infernix-infernix-pulsar-proxy:80`."
    "/pulsar/ws" -> "Rewrites to upstream `/ws` before forwarding to `infernix-infernix-pulsar-proxy:80`."
    _ -> "Registry-defined route."

code :: Text -> String
code value = "`" <> Text.unpack value <> "`"
