{-# LANGUAGE OverloadedStrings #-}

module Infernix.Gateway
  ( harborGatewayTargetForPath,
    minioGatewayTargetForPath,
    pulsarGatewayTargetForPath,
    runGatewayProxy,
  )
where

import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.CaseInsensitive qualified as CI
import Data.Maybe (fromMaybe)
import Infernix.HttpProxy
  ( ProxyTarget (..),
    defaultServerPort,
    proxyRequest,
    requireEnvironment,
    runApplicationServer,
    stripPathPrefix,
  )
import Network.HTTP.Client (Manager)
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (methodGet, methodHead, status200, status404)
import Network.Wai (Application, Request (rawPathInfo, requestMethod), Response, responseLBS)
import System.Environment (lookupEnv)

runGatewayProxy :: String -> IO ()
runGatewayProxy gatewayKind = do
  bindHost <- fmap (fromMaybe "0.0.0.0") (lookupEnv "INFERNIX_BIND_HOST")
  portValue <- fmap (maybe defaultServerPort read) (lookupEnv "INFERNIX_PORT")
  manager <- newTlsManager
  application <- gatewayApplication manager gatewayKind
  runApplicationServer bindHost portValue application

gatewayApplication :: Manager -> String -> IO Application
gatewayApplication manager gatewayKind =
  case gatewayKind of
    "harbor" -> do
      backendUrl <- requireEnvironment "INFERNIX_HARBOR_BACKEND_URL"
      apiUrl <- requireEnvironment "INFERNIX_HARBOR_API_URL"
      authHeader <- harborAuthorizationHeader
      pure $ \request respond ->
        case harborGatewayTargetForPath backendUrl apiUrl authHeader (rawPathInfo request) of
          Just proxyTarget -> proxyRequest manager proxyTarget request respond
          Nothing -> respond (notFoundResponse "unsupported Harbor route")
    "minio" -> do
      s3Endpoint <- requireEnvironment "INFERNIX_MINIO_S3_ENDPOINT"
      consoleEndpoint <- requireEnvironment "INFERNIX_MINIO_CONSOLE_ENDPOINT"
      pure $ \request respond ->
        let pathValue = rawPathInfo request
         in if pathValue == "/minio/s3" && requestMethod request `elem` [methodGet, methodHead]
              then respond (jsonResponse (object ["path" .= ("/minio/s3" :: String), "status" .= ("ready" :: String), "surface" .= ("minio" :: String), "targetUrl" .= s3Endpoint]))
              else case minioGatewayTargetForPath consoleEndpoint s3Endpoint pathValue of
                Just proxyTarget -> proxyRequest manager proxyTarget request respond
                Nothing -> respond (notFoundResponse "unsupported MinIO route")
    "pulsar" -> do
      adminUrl <- requireEnvironment "INFERNIX_PULSAR_ADMIN_URL"
      httpBaseUrl <- requireEnvironment "INFERNIX_PULSAR_HTTP_BASE_URL"
      pure $ \request respond ->
        let pathValue = rawPathInfo request
         in if pathValue == "/pulsar/ws" && requestMethod request `elem` [methodGet, methodHead]
              then respond (jsonResponse (object ["path" .= ("/pulsar/ws" :: String), "status" .= ("ready" :: String), "surface" .= ("pulsar" :: String), "brokersHealth" .= ("ready" :: String)]))
              else case pulsarGatewayTargetForPath adminUrl httpBaseUrl pathValue of
                Just proxyTarget -> proxyRequest manager proxyTarget request respond
                Nothing -> respond (notFoundResponse "unsupported Pulsar route")
    _ -> ioError (userError ("unsupported gateway kind: " <> gatewayKind))

harborGatewayTargetForPath :: String -> String -> ByteString -> ByteString -> Maybe ProxyTarget
harborGatewayTargetForPath backendUrl apiUrl authHeader pathValue
  | pathValue == "/harbor/api" || "/harbor/api/" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget apiUrl (stripPathPrefix "/harbor" pathValue) [(CI.mk "Authorization", authHeader)])
  | "/harbor" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget backendUrl (stripPathPrefix "/harbor" pathValue) [])
  | otherwise = Nothing

minioGatewayTargetForPath :: String -> String -> ByteString -> Maybe ProxyTarget
minioGatewayTargetForPath consoleEndpoint s3Endpoint pathValue
  | "/minio/console" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget consoleEndpoint (stripPathPrefix "/minio/console" pathValue) [])
  | "/minio/s3/" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget s3Endpoint (stripPathPrefix "/minio/s3" pathValue) [])
  | otherwise = Nothing

pulsarGatewayTargetForPath :: String -> String -> ByteString -> Maybe ProxyTarget
pulsarGatewayTargetForPath adminUrl httpBaseUrl pathValue
  | "/pulsar/admin" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget adminUrl (stripPathPrefix "/pulsar/admin" pathValue) [])
  | "/pulsar/ws/" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget httpBaseUrl (stripPathPrefix "/pulsar/ws" pathValue) [])
  | otherwise = Nothing

harborAuthorizationHeader :: IO ByteString
harborAuthorizationHeader = do
  adminUser <- fmap (fromMaybe "admin") (lookupEnv "INFERNIX_HARBOR_ADMIN_USER")
  adminPassword <- fmap (fromMaybe "") (lookupEnv "INFERNIX_HARBOR_ADMIN_PASSWORD")
  let credentials = ByteString8.pack (adminUser <> ":" <> adminPassword)
  pure ("Basic " <> Base64.encode credentials)

jsonResponse :: Aeson.Value -> Response
jsonResponse payload =
  responseLBS
    status200
    [("Content-Type", "application/json; charset=utf-8")]
    (Aeson.encode payload)

notFoundResponse :: String -> Response
notFoundResponse message =
  responseLBS
    status404
    [("Content-Type", "text/plain; charset=utf-8")]
    (LazyChar8.pack message)
