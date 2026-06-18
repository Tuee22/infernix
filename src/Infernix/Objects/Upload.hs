{-# LANGUAGE OverloadedStrings #-}

module Infernix.Objects.Upload
  ( ObjectUploadConfig (..),
    putObjectWithPresignedUrl,
    objectExistsViaPresignedGet,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Infernix.Objects.Presigned qualified as Presigned
import Infernix.Web.Contracts qualified as Contracts
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    httpLbs,
    method,
    parseRequest,
    requestBody,
    responseStatus,
  )
import Network.HTTP.Types.Status (statusCode)

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
            requestBody = RequestBodyLBS (LazyByteString.fromStrict payload)
          }
  response <- httpLbs request manager
  let responseCode = statusCode (responseStatus response)
  if responseCode >= 200 && responseCode < 300
    then pure ()
    else fail ("MinIO artifact upload returned HTTP " <> show responseCode)

-- | Probe whether an object exists by issuing a presigned GET and treating an
-- HTTP 200 as present. Keeps the @Infernix.Objects.Presigned@ dependency inside
-- this object-access wrapper so engine runtime modules stay off the presign
-- boundary enforced by the Haskell-style gate.
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

presignedUrlConfig :: ObjectUploadConfig -> Presigned.PresignedUrlConfig
presignedUrlConfig uploadConfig =
  Presigned.PresignedUrlConfig
    { Presigned.presignedScheme = objectUploadScheme uploadConfig,
      Presigned.presignedEndpoint = objectUploadEndpoint uploadConfig,
      Presigned.presignedPathPrefix = objectUploadPathPrefix uploadConfig,
      Presigned.presignedRegion = objectUploadRegion uploadConfig,
      Presigned.presignedAccessKeyId = objectUploadAccessKeyId uploadConfig,
      Presigned.presignedSecretAccessKey = objectUploadSecretAccessKey uploadConfig,
      Presigned.presignedExpirySeconds = objectUploadExpirySeconds uploadConfig
    }
