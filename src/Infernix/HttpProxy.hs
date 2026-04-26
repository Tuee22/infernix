{-# LANGUAGE OverloadedStrings #-}

module Infernix.HttpProxy
  ( ProxyTarget (..),
    defaultServerPort,
    proxyRequest,
    requireEnvironment,
    runApplicationServer,
    runProxyServer,
    stripPathPrefix,
  )
where

import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.CaseInsensitive qualified as CI
import Data.List (foldl')
import Data.String (fromString)
import Network.HTTP.Client
  ( Manager,
    Request (method, redirectCount, requestBody, requestHeaders, responseTimeout),
    RequestBody (RequestBodyLBS),
    Response,
    httpLbs,
    parseRequest,
    responseBody,
    responseHeaders,
    responseStatus,
  )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (status502)
import Network.Wai
  ( Application,
    Request (rawPathInfo, rawQueryString, requestMethod),
    responseLBS,
    strictRequestBody,
  )
import Network.Wai qualified
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import System.Environment (lookupEnv)

data ProxyTarget = ProxyTarget
  { proxyBaseUrl :: String,
    proxyPath :: ByteString,
    proxyRequestHeaders :: [(CI.CI ByteString, ByteString)]
  }
  deriving (Eq, Show)

defaultServerPort :: Int
defaultServerPort = 8080

runProxyServer :: String -> Int -> (ByteString -> Maybe ProxyTarget) -> IO ()
runProxyServer bindHost port resolveTarget = do
  manager <- newTlsManager
  runApplicationServer bindHost port (proxyApplication manager resolveTarget)

runApplicationServer :: String -> Int -> Application -> IO ()
runApplicationServer bindHost port =
  runSettings settings
  where
    settings =
      setHost (fromString bindHost) $
        setPort port defaultSettings

proxyApplication :: Manager -> (ByteString -> Maybe ProxyTarget) -> Application
proxyApplication manager resolveTarget request respond =
  case resolveTarget (rawPathInfo request) of
    Nothing ->
      respond
        ( responseLBS
            status502
            [("Content-Type", "text/plain; charset=utf-8")]
            "proxy target was not configured for the requested path"
        )
    Just proxyTarget ->
      proxyRequest manager proxyTarget request respond

proxyRequest :: Manager -> ProxyTarget -> Network.Wai.Request -> (Network.Wai.Response -> IO responseReceived) -> IO responseReceived
proxyRequest manager proxyTarget request respond = do
  requestBodyValue <- strictRequestBody request
  result <- try (issueProxyRequest manager proxyTarget request requestBodyValue) :: IO (Either SomeException (Response Lazy.ByteString))
  case result of
    Left _ ->
      respond
        ( responseLBS
            status502
            [("Content-Type", "text/plain; charset=utf-8")]
            "upstream request failed"
        )
    Right upstreamResponse ->
      respond
        ( responseLBS
            (responseStatus upstreamResponse)
            (filterResponseHeaders (responseHeaders upstreamResponse))
            (responseBody upstreamResponse)
        )

issueProxyRequest :: Manager -> ProxyTarget -> Network.Wai.Request -> Lazy.ByteString -> IO (Response Lazy.ByteString)
issueProxyRequest manager proxyTarget request requestBodyValue = do
  baseRequest <- parseRequest (proxyRequestUrl proxyTarget (rawQueryString request))
  let forwardedHeaders =
        mergeRequestHeaders
          (filterRequestHeaders (Network.Wai.requestHeaders request))
          (proxyRequestHeaders proxyTarget)
  let proxiedRequest =
        baseRequest
          { method = requestMethod request,
            requestHeaders = forwardedHeaders,
            requestBody = RequestBodyLBS requestBodyValue,
            redirectCount = 0,
            responseTimeout = responseTimeout baseRequest
          }
  httpLbs proxiedRequest manager

proxyRequestUrl :: ProxyTarget -> ByteString -> String
proxyRequestUrl proxyTarget queryString =
  trimTrailingSlash (proxyBaseUrl proxyTarget)
    <> ByteString8.unpack (proxyPath proxyTarget)
    <> ByteString8.unpack queryString

trimTrailingSlash :: String -> String
trimTrailingSlash value =
  reverse (dropWhile (== '/') (reverse value))

filterRequestHeaders :: [(CI.CI ByteString, ByteString)] -> [(CI.CI ByteString, ByteString)]
filterRequestHeaders =
  filter (\(headerName, _) -> not (hopByHopHeader headerName) && CI.foldedCase headerName /= "host")

filterResponseHeaders :: [(CI.CI ByteString, ByteString)] -> [(CI.CI ByteString, ByteString)]
filterResponseHeaders =
  filter (\(headerName, _) -> not (hopByHopHeader headerName) && CI.foldedCase headerName /= "content-length")

mergeRequestHeaders :: [(CI.CI ByteString, ByteString)] -> [(CI.CI ByteString, ByteString)] -> [(CI.CI ByteString, ByteString)]
mergeRequestHeaders =
  foldl' upsertHeader
  where
    upsertHeader headers (headerName, headerValue) =
      (headerName, headerValue) : filter (\(existingName, _) -> existingName /= headerName) headers

hopByHopHeader :: CI.CI ByteString -> Bool
hopByHopHeader headerName =
  CI.foldedCase headerName
    `elem` [ "connection",
             "keep-alive",
             "proxy-authenticate",
             "proxy-authorization",
             "te",
             "trailers",
             "transfer-encoding",
             "upgrade"
           ]

stripPathPrefix :: ByteString -> ByteString -> ByteString
stripPathPrefix prefix pathValue =
  case ByteString.stripPrefix prefix pathValue of
    Just suffix
      | ByteString.null suffix -> "/"
      | ByteString.head suffix == 47 -> suffix
      | otherwise -> ByteString.cons 47 suffix
    Nothing -> pathValue

requireEnvironment :: String -> IO String
requireEnvironment variableName = do
  maybeValue <- lookupEnv variableName
  case maybeValue of
    Just value -> pure value
    Nothing -> ioError (userError ("missing required environment variable: " <> variableName))
