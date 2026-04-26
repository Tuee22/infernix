{-# LANGUAGE OverloadedStrings #-}

module Infernix.Edge
  ( edgeTargetForPath,
    runEdgeProxy,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Maybe (fromMaybe)
import Infernix.HttpProxy
  ( ProxyTarget (..),
    defaultServerPort,
    requireEnvironment,
    runProxyServer,
  )
import System.Environment (lookupEnv)

runEdgeProxy :: IO ()
runEdgeProxy = do
  bindHost <- fmap (fromMaybe "0.0.0.0") (lookupEnv "INFERNIX_BIND_HOST")
  portValue <- fmap (maybe defaultServerPort read) (lookupEnv "INFERNIX_PORT")
  maybeDemoUpstream <- traverse normalizeHostPort =<< lookupEnv "INFERNIX_DEMO_UPSTREAM"
  maybeWebUpstream <- traverse normalizeHostPort =<< lookupEnv "INFERNIX_WEB_UPSTREAM"
  harborUpstream <- normalizeHostPort =<< requireEnvironment "INFERNIX_HARBOR_UPSTREAM"
  minioUpstream <- normalizeHostPort =<< requireEnvironment "INFERNIX_MINIO_UPSTREAM"
  pulsarUpstream <- normalizeHostPort =<< requireEnvironment "INFERNIX_PULSAR_UPSTREAM"
  runProxyServer bindHost portValue (edgeTargetForPath maybeDemoUpstream maybeWebUpstream harborUpstream minioUpstream pulsarUpstream)

edgeTargetForPath :: Maybe String -> Maybe String -> String -> String -> String -> ByteString -> Maybe ProxyTarget
edgeTargetForPath maybeDemoUpstream maybeWebUpstream harborUpstream minioUpstream pulsarUpstream pathValue
  | "/harbor" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget harborUpstream pathValue [])
  | "/minio/" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget minioUpstream pathValue [])
  | "/pulsar/" `ByteString.isPrefixOf` pathValue =
      Just (ProxyTarget pulsarUpstream pathValue [])
  | isDemoRoute pathValue =
      proxyTo maybeDemoUpstream pathValue
  | Just demoUpstream <- maybeDemoUpstream =
      Just (ProxyTarget demoUpstream pathValue [])
  | otherwise =
      proxyTo maybeWebUpstream pathValue

isDemoRoute :: ByteString -> Bool
isDemoRoute pathValue =
  pathValue == "/api"
    || "/api/" `ByteString.isPrefixOf` pathValue
    || pathValue == "/objects"
    || "/objects/" `ByteString.isPrefixOf` pathValue
    || pathValue == "/healthz"

proxyTo :: Maybe String -> ByteString -> Maybe ProxyTarget
proxyTo maybeUpstream pathValue =
  fmap (\upstream -> ProxyTarget upstream pathValue []) maybeUpstream

normalizeHostPort :: String -> IO String
normalizeHostPort value
  | "http://" `prefixOf` value = pure value
  | "https://" `prefixOf` value = pure value
  | otherwise = pure ("http://" <> value)

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (expected : expectedRest) (actual : actualRest) =
  expected == actual && prefixOf expectedRest actualRest
