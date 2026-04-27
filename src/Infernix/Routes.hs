{-# LANGUAGE OverloadedStrings #-}

module Infernix.Routes
  ( routeHelmValues,
    routeInventory,
    routePublicationUpstreams,
  )
where

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
