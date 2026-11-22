{-# LANGUAGE OverloadedStrings #-}

module Infernix.Objects.Upload
  ( ObjectUploadConfig (..),
    ObjectHeadOutcome (..),
    putObjectWithPresignedUrl,
    getObjectWithPresignedUrl,
    getObjectPrefixWithPresignedUrl,
    getObjectSuffixWithPresignedUrl,
    getObjectEdgesWithPresignedUrl,
    copyObjectToHandleWithPresignedUrl,
    listObjectKeysWithPresignedUrl,
    objectExistsViaPresignedHead,
    observeObjectViaPresignedHead,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time (UTCTime)
import Infernix.Objects.BoundedHttp qualified as BoundedHttp
import Infernix.Objects.Presigned qualified as Presigned
import Infernix.Web.Contracts qualified as Contracts
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    ResponseTimeout,
    checkResponse,
    httpLbs,
    httpNoBody,
    method,
    parseRequest,
    requestBody,
    responseBody,
    responseStatus,
    responseTimeout,
    responseTimeoutMicro,
  )
import Network.HTTP.Types.Status (statusCode)
import System.IO (Handle)

data ObjectUploadConfig = ObjectUploadConfig
  { objectUploadScheme :: Text,
    objectUploadEndpoint :: Text,
    objectUploadPathPrefix :: Text,
    objectUploadRegion :: Text,
    objectUploadAccessKeyId :: Text,
    objectUploadSecretAccessKey :: Text,
    objectUploadExpirySeconds :: Int
  }
  deriving (Eq, Show)

putObjectWithPresignedUrl :: ObjectUploadConfig -> Manager -> UTCTime -> Contracts.ObjectRef -> ByteString.ByteString -> IO ()
putObjectWithPresignedUrl uploadConfig manager now objectRef payload = do
  initialRequest <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedPutUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  let request =
        initialRequest
          { method = "PUT",
            requestBody = RequestBodyLBS (LazyByteString.fromStrict payload),
            responseTimeout = objectRequestTimeout
          }
  response <- httpLbs (request {responseTimeout = objectRequestTimeout}) manager
  let responseCode = statusCode (responseStatus response)
  if responseCode >= 200 && responseCode < 300
    then pure ()
    else fail ("MinIO artifact upload returned HTTP " <> show responseCode)

getObjectWithPresignedUrl :: ObjectUploadConfig -> Manager -> UTCTime -> Contracts.ObjectRef -> IO ByteString.ByteString
getObjectWithPresignedUrl uploadConfig manager now objectRef = do
  request <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  response <- httpLbs (request {responseTimeout = objectRequestTimeout}) manager
  let responseCode = statusCode (responseStatus response)
  if responseCode >= 200 && responseCode < 300
    then pure (LazyByteString.toStrict (responseBody response))
    else fail ("MinIO artifact download returned HTTP " <> show responseCode)

-- | Phase 4 Sprint 4.43 — the object keys staged under one prefix.
--
-- A model is staged one of two ways: a single upstream file becomes one
-- @\<modelId>/payload@ object, and a multi-file repository is mirrored under the
-- upstream repository's own file names. A reader that assumes the first shape
-- finds nothing at all for the second, which is not the same statement as "this
-- artifact family has no reader" and must not be reported as one.
--
-- The listing is bounded in both directions a listing can run away: a page cap
-- and a page-count cap, so a bucket with an unexpected number of objects under
-- one model prefix is truncated rather than followed indefinitely.
listObjectKeysWithPresignedUrl ::
  ObjectUploadConfig ->
  Manager ->
  UTCTime ->
  Text ->
  Text ->
  IO (Either Text [Text])
listObjectKeysWithPresignedUrl config manager now bucket prefix =
  collect maximumObjectListingPages Nothing []
  where
    collect remainingPages continuation acc
      | remainingPages <= (0 :: Int) = pure (Right acc)
      | otherwise = do
          let signed =
                Presigned.presignedBucketUrlWithQuery
                  (presignedUrlConfig config)
                  Presigned.PresignedBucketRequest
                    { Presigned.presignedBucketRequestMethod = Presigned.HttpGet,
                      Presigned.presignedBucketRequestBucket = bucket,
                      Presigned.presignedBucketRequestNow = now
                    }
                  ( [ ("list-type", "2"),
                      ("prefix", prefix),
                      ("max-keys", Text.pack (show maximumObjectListingKeysPerPage))
                    ]
                      <> maybe [] (\token -> [("continuation-token", token)]) continuation
                  )
          requestValue <- parseRequest (Text.unpack (Presigned.unPresignedUrl signed))
          response <-
            httpLbs (requestValue {responseTimeout = objectRequestTimeout}) manager
          case statusCode (responseStatus response) of
            200 -> do
              let bodyText =
                    Text.decodeUtf8
                      (LazyByteString.toStrict (responseBody response))
                  keys = xmlTagValues "Key" bodyText
                  truncated = xmlTagValues "IsTruncated" bodyText == ["true"]
                  next = firstOf (xmlTagValues "NextContinuationToken" bodyText)
              case next of
                Just token
                  | truncated -> collect (remainingPages - 1) (Just token) (acc <> keys)
                _ -> pure (Right (acc <> keys))
            -- A listing that could not be performed is not a listing that found
            -- nothing, and reporting the second for the first is how an absent
            -- capability gets recorded as an absent object.
            code ->
              pure
                ( Left
                    ( "the model object listing returned HTTP "
                        <> Text.pack (show code)
                    )
                )

    firstOf values =
      case values of
        value : _ -> Just value
        [] -> Nothing

-- | Every value between one XML tag pair, without a parser dependency. MinIO's
-- listing response is a flat element list, and the two tags read here carry no
-- attributes and no nesting.
xmlTagValues :: Text -> Text -> [Text]
xmlTagValues tagName body =
  [ value
  | segment <- drop 1 (Text.splitOn ("<" <> tagName <> ">") body),
    value : _ <- [Text.splitOn ("</" <> tagName <> ">") segment]
  ]

maximumObjectListingKeysPerPage :: Int
maximumObjectListingKeysPerPage = 1000

maximumObjectListingPages :: Int
maximumObjectListingPages = 8

-- | Test existence without downloading the model object. S3 authorizes HEAD
-- using the same object-read permission as GET, but the method must be signed.
objectExistsViaPresignedHead :: ObjectUploadConfig -> Manager -> UTCTime -> Contracts.ObjectRef -> IO Bool
objectExistsViaPresignedHead uploadConfig manager now objectRef =
  (== ObjectHeadPresent) <$> observeObjectViaPresignedHead uploadConfig manager now objectRef

-- | Absence is distinct from an authorization or service failure. A caller
-- that uses absence to choose a legacy path must inspect this outcome.
data ObjectHeadOutcome = ObjectHeadPresent | ObjectHeadMissing | ObjectHeadUnavailable Int
  deriving (Eq, Show)

observeObjectViaPresignedHead :: ObjectUploadConfig -> Manager -> UTCTime -> Contracts.ObjectRef -> IO ObjectHeadOutcome
observeObjectViaPresignedHead uploadConfig manager now objectRef = do
  initialRequest <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedHeadUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  let request =
        initialRequest
          { method = "HEAD",
            checkResponse = \_ _ -> pure (),
            responseTimeout = objectRequestTimeout
          }
  response <- httpNoBody request manager
  pure $
    case statusCode (responseStatus response) of
      200 -> ObjectHeadPresent
      404 -> ObjectHeadMissing
      other -> ObjectHeadUnavailable other

-- | Retain at most the requested prefix, even if a server ignores Range or lies
-- about Content-Length. A partial response must describe exactly the bytes
-- returned and the object's total extent; an unproved extent is a refusal.
getObjectPrefixWithPresignedUrl ::
  ObjectUploadConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  Int ->
  IO (Maybe (ByteString.ByteString, Integer))
getObjectPrefixWithPresignedUrl uploadConfig manager now objectRef requestedBytes
  | requestedBytes <= 0 = pure Nothing
  | otherwise = do
      initialRequest <-
        parseRequest
          ( Text.unpack
              ( Presigned.unPresignedUrl
                  (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
              )
          )
      BoundedHttp.readObjectPrefix initialRequest manager objectRequestTimeout requestedBytes

-- | Read and verify a bounded tail without downloading the entire object.
getObjectSuffixWithPresignedUrl ::
  ObjectUploadConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  Int ->
  IO (Maybe (ByteString.ByteString, Integer))
getObjectSuffixWithPresignedUrl uploadConfig manager now objectRef requestedBytes
  | requestedBytes <= 0 = pure Nothing
  | otherwise = do
      initialRequest <-
        parseRequest
          ( Text.unpack
              ( Presigned.unPresignedUrl
                  (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
              )
          )
      BoundedHttp.readObjectSuffix initialRequest manager objectRequestTimeout requestedBytes

-- | Read both edges conditionally from the same strong object version.
getObjectEdgesWithPresignedUrl ::
  ObjectUploadConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  Int ->
  Int ->
  IO (Maybe (ByteString.ByteString, ByteString.ByteString, Integer))
getObjectEdgesWithPresignedUrl uploadConfig manager now objectRef prefixBytes suffixBytes = do
  initialRequest <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  BoundedHttp.readObjectEdges initialRequest manager objectRequestTimeout prefixBytes suffixBytes

-- | Stream a complete signed object into the caller's staging handle. The
-- bounded kernel verifies the response extent before reporting success.
copyObjectToHandleWithPresignedUrl ::
  ObjectUploadConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  Integer ->
  Handle ->
  IO (Either Text Integer)
copyObjectToHandleWithPresignedUrl uploadConfig manager now objectRef limit handle = do
  request <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  BoundedHttp.copyObjectToHandle request manager objectRequestTimeout limit handle

presignedUrlConfig :: ObjectUploadConfig -> Presigned.PresignedUrlConfig
presignedUrlConfig uploadConfig =
  Presigned.PresignedUrlConfig
    { Presigned.presignedScheme = objectUploadScheme uploadConfig,
      Presigned.presignedEndpoint = objectUploadEndpoint uploadConfig,
      Presigned.presignedPathPrefix = objectUploadPathPrefix uploadConfig,
      Presigned.presignedRegion = objectUploadRegion uploadConfig,
      Presigned.presignedAccessKeyId = objectUploadAccessKeyId uploadConfig,
      Presigned.presignedSecretAccessKey = objectUploadSecretAccessKey uploadConfig,
      Presigned.presignedExpirySeconds = objectUploadExpirySeconds uploadConfig,
      Presigned.presignedSessionToken = Nothing
    }

objectRequestTimeout :: ResponseTimeout
objectRequestTimeout =
  responseTimeoutMicro 120000000
