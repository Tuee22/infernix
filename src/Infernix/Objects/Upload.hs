{-# LANGUAGE OverloadedStrings #-}

module Infernix.Objects.Upload
  ( ObjectUploadConfig (..),
    putObjectWithPresignedUrl,
    getObjectWithPresignedUrl,
    getObjectPrefixWithPresignedUrl,
    listObjectKeysWithPresignedUrl,
    objectExistsViaPresignedGet,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time (UTCTime)
import Infernix.Objects.Presigned qualified as Presigned
import Infernix.Web.Contracts qualified as Contracts
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    ResponseTimeout,
    httpLbs,
    method,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseHeaders,
    responseStatus,
    responseTimeout,
    responseTimeoutMicro,
  )
import Network.HTTP.Types.Status (statusCode)
import Text.Read (readMaybe)

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

-- | Probe whether an object exists by issuing a presigned GET and treating an
-- HTTP 200 as present. Keeps the @Infernix.Objects.Presigned@ dependency inside
-- this object-access wrapper so engine runtime modules stay off the presign
-- boundary enforced by the Haskell-style gate.
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

objectExistsViaPresignedGet :: ObjectUploadConfig -> Manager -> UTCTime -> Contracts.ObjectRef -> IO Bool
objectExistsViaPresignedGet uploadConfig manager now objectRef = do
  request <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  response <- httpLbs request manager
  pure (statusCode (responseStatus response) == 200)

-- | Phase 4 Sprint 4.39 — read a bounded leading prefix of a staged object, and
-- report the object's own total size alongside it.
--
-- This is how a machine derives a model's memory requirement from a checkpoint
-- it has not downloaded: the tensor table lives in the artifact's first few
-- kilobytes, and a ranged read fetches exactly those. Returns 'Nothing' when the
-- object is absent, so a model the coordinator has not staged yet is a missing
-- observation rather than a failed one.
getObjectPrefixWithPresignedUrl ::
  ObjectUploadConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  Int ->
  IO (Maybe (ByteString.ByteString, Integer))
getObjectPrefixWithPresignedUrl uploadConfig manager now objectRef requestedBytes = do
  initialRequest <-
    parseRequest
      ( Text.unpack
          ( Presigned.unPresignedUrl
              (Presigned.presignedGetUrl (presignedUrlConfig uploadConfig) now objectRef)
          )
      )
  let rangeHeader =
        ByteString.concat
          [ "bytes=0-",
            Text.encodeUtf8 (Text.pack (show (max 0 (requestedBytes - 1))))
          ]
      request =
        initialRequest
          { requestHeaders = ("Range", rangeHeader) : requestHeaders initialRequest,
            responseTimeout = objectRequestTimeout
          }
  response <- httpLbs request manager
  let responseCode = statusCode (responseStatus response)
      body = LazyByteString.toStrict (responseBody response)
  if responseCode < 200 || responseCode >= 300
    then pure Nothing
    else
      pure
        ( fmap
            (body,)
            (objectTotalBytes (responseHeaders response) (ByteString.length body))
        )

-- | The object's total size: from @Content-Range@ when the server honoured the
-- range, and otherwise the length of what it actually returned, because a server
-- that ignores the range answers with the whole object.
objectTotalBytes :: [(a, ByteString.ByteString)] -> Int -> Maybe Integer
objectTotalBytes headers bodyLength =
  case [value | (_, value) <- headers, "bytes " `ByteString.isPrefixOf` value] of
    value : _ ->
      case Text.splitOn "/" (Text.decodeUtf8Lenient value) of
        [_, totalText] -> readMaybe (Text.unpack (Text.filter isDigit totalText))
        _ -> Just (toInteger bodyLength)
    [] -> Just (toInteger bodyLength)

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
