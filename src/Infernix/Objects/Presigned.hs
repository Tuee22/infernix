{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Objects.Presigned
  ( PresignedUrlConfig (..),
    PresignedRequest (..),
    PresignedBucketRequest (..),
    HttpMethod (..),
    PresignedUrl (..),
    presignedUrlForRequest,
    presignedUrlForRequestWithQuery,
    presignedBucketUrl,
    presignedBucketUrlWithQuery,
    presignedPutUrl,
    presignedGetUrl,
    presignedHeadUrl,
    isoExpiryFor,
  )
where

import Crypto.Hash (Digest, SHA256, hash)
import Crypto.MAC.HMAC (HMAC (..), hmac)
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (UTCTime, addUTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Infernix.Web.Contracts (ObjectRef (..))

-- | Endpoint + credentials needed to mint a presigned URL against MinIO.
-- The endpoint hostname doubles as the SigV4 @host@ header.
--
-- @presignedEndpoint@ is @host:port@ (no scheme), e.g.
-- @infernix-minio.platform.svc.cluster.local:9000@. @presignedScheme@ is
-- @http@ for the supported in-cluster MinIO deployment (the chart does
-- not provision TLS for the MinIO service) and @https@ for TLS-fronted
-- MinIO. @presignedPathPrefix@ is not part of the SigV4 canonical path;
-- it is only prepended to the public URL for Gateway prefixes that rewrite
-- away before the request reaches MinIO.
data PresignedUrlConfig = PresignedUrlConfig
  { presignedScheme :: Text,
    presignedEndpoint :: Text,
    presignedPathPrefix :: Text,
    presignedRegion :: Text,
    presignedAccessKeyId :: Text,
    presignedSecretAccessKey :: Text,
    presignedExpirySeconds :: Int
  }
  deriving (Eq, Show)

data HttpMethod = HttpGet | HttpPut | HttpHead | HttpDelete deriving (Eq, Show)

httpMethodText :: HttpMethod -> Text
httpMethodText HttpGet = "GET"
httpMethodText HttpPut = "PUT"
httpMethodText HttpHead = "HEAD"
httpMethodText HttpDelete = "DELETE"

-- | A presigned URL request scoped to a single @ObjectRef@.
data PresignedRequest = PresignedRequest
  { presignedRequestMethod :: HttpMethod,
    presignedRequestObject :: ObjectRef,
    presignedRequestNow :: UTCTime
  }
  deriving (Eq, Show)

-- | A presigned URL request scoped to a bucket-level S3 operation such as
-- CreateBucket. Bucket repair uses this at demo backend startup when the
-- chart-time MinIO provisioner was bypassed.
data PresignedBucketRequest = PresignedBucketRequest
  { presignedBucketRequestMethod :: HttpMethod,
    presignedBucketRequestBucket :: Text,
    presignedBucketRequestNow :: UTCTime
  }
  deriving (Eq, Show)

newtype PresignedUrl = PresignedUrl {unPresignedUrl :: Text}
  deriving (Eq, Show)

-- | Mint a presigned URL for the requested @ObjectRef@ + HTTP method using
-- the AWS SigV4 query-parameter signing scheme that MinIO honours. The
-- result is a fully-qualified URL the browser can PUT or GET against
-- without ever talking to the demo backend.
--
-- The signing is implemented from the SigV4 spec rather than via a
-- third-party SDK so the demo backend has no additional runtime dependency:
-- canonical request -> string to sign -> HMAC chain -> hex signature
-- appended as the @X-Amz-Signature@ query parameter.
presignedUrlForRequest :: PresignedUrlConfig -> PresignedRequest -> PresignedUrl
presignedUrlForRequest config request =
  presignedUrlForRequestWithQuery config request []

presignedUrlForRequestWithQuery :: PresignedUrlConfig -> PresignedRequest -> [(Text, Text)] -> PresignedUrl
presignedUrlForRequestWithQuery config request extraQuery =
  let method = httpMethodText (presignedRequestMethod request)
      object = presignedRequestObject request
      bucket = objectBucket object
      key = objectKey object
      canonicalPath = "/" <> bucket <> "/" <> key
   in presignedS3Url config method canonicalPath (presignedRequestNow request) extraQuery

presignedBucketUrl :: PresignedUrlConfig -> PresignedBucketRequest -> PresignedUrl
presignedBucketUrl config request =
  presignedBucketUrlWithQuery config request []

presignedBucketUrlWithQuery :: PresignedUrlConfig -> PresignedBucketRequest -> [(Text, Text)] -> PresignedUrl
presignedBucketUrlWithQuery config request =
  presignedS3Url
    config
    (httpMethodText (presignedBucketRequestMethod request))
    ("/" <> presignedBucketRequestBucket request)
    (presignedBucketRequestNow request)

presignedPutUrl :: PresignedUrlConfig -> UTCTime -> ObjectRef -> PresignedUrl
presignedPutUrl config now object =
  presignedUrlForRequest
    config
    PresignedRequest
      { presignedRequestMethod = HttpPut,
        presignedRequestObject = object,
        presignedRequestNow = now
      }

presignedGetUrl :: PresignedUrlConfig -> UTCTime -> ObjectRef -> PresignedUrl
presignedGetUrl config now object =
  presignedUrlForRequest
    config
    PresignedRequest
      { presignedRequestMethod = HttpGet,
        presignedRequestObject = object,
        presignedRequestNow = now
      }

presignedHeadUrl :: PresignedUrlConfig -> UTCTime -> ObjectRef -> PresignedUrl
presignedHeadUrl config now object =
  presignedUrlForRequest
    config
    PresignedRequest
      { presignedRequestMethod = HttpHead,
        presignedRequestObject = object,
        presignedRequestNow = now
      }

-- | The ISO 8601 expiry timestamp the demo backend echoes back to the
-- caller. Format matches @ArtifactUploadGrant / ArtifactDownloadGrant@'s
-- @artifactUploadGrantExpiresAtIso8601@ field.
isoExpiryFor :: PresignedUrlConfig -> UTCTime -> Text
isoExpiryFor config now =
  let expiry = fromIntegral (presignedExpirySeconds config) :: Double
      expiresAt = addUTCTime (realToFrac expiry) now
   in Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" expiresAt)

presignedS3Url :: PresignedUrlConfig -> Text -> Text -> UTCTime -> [(Text, Text)] -> PresignedUrl
presignedS3Url config method canonicalPath now extraQuery =
  let host = presignedEndpoint config
      region = presignedRegion config
      service = "s3" :: Text
      accessKeyId = presignedAccessKeyId config
      secretAccessKey = presignedSecretAccessKey config
      expiry = presignedExpirySeconds config
      amzDate = Text.pack (formatTime defaultTimeLocale "%Y%m%dT%H%M%SZ" now)
      dateStamp = Text.pack (formatTime defaultTimeLocale "%Y%m%d" now)
      credentialScope = dateStamp <> "/" <> region <> "/" <> service <> "/aws4_request"
      credential = accessKeyId <> "/" <> credentialScope
      signedHeaders = "host" :: Text
      queryParams =
        sort
          ( extraQuery
              <> [ ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
                   ("X-Amz-Credential", credential),
                   ("X-Amz-Date", amzDate),
                   ("X-Amz-Expires", Text.pack (show expiry)),
                   ("X-Amz-SignedHeaders", signedHeaders)
                 ]
          )
      canonicalQuery = Text.intercalate "&" [uriEncode k <> "=" <> uriEncode v | (k, v) <- queryParams]
      canonicalRequest =
        Text.intercalate
          "\n"
          [ method,
            canonicalPath,
            canonicalQuery,
            "host:" <> host,
            "",
            signedHeaders,
            "UNSIGNED-PAYLOAD"
          ]
      hashedCanonicalRequest = sha256Hex (TextEncoding.encodeUtf8 canonicalRequest)
      stringToSign =
        Text.intercalate
          "\n"
          [ "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            hashedCanonicalRequest
          ]
      signingKey = deriveSigningKey secretAccessKey dateStamp region service
      signature = hmacHex signingKey (TextEncoding.encodeUtf8 stringToSign)
      finalQuery = canonicalQuery <> "&X-Amz-Signature=" <> signature
      scheme = presignedScheme config
      publicPath = normalizePathPrefix (presignedPathPrefix config) <> canonicalPath
   in PresignedUrl (scheme <> "://" <> host <> publicPath <> "?" <> finalQuery)

deriveSigningKey :: Text -> Text -> Text -> Text -> ByteString
deriveSigningKey secret dateStamp region service =
  let kSecret = TextEncoding.encodeUtf8 ("AWS4" <> secret)
      kDate = hmacRaw kSecret (TextEncoding.encodeUtf8 dateStamp)
      kRegion = hmacRaw kDate (TextEncoding.encodeUtf8 region)
      kService = hmacRaw kRegion (TextEncoding.encodeUtf8 service)
      kSigning = hmacRaw kService "aws4_request"
   in kSigning

hmacRaw :: ByteString -> ByteString -> ByteString
hmacRaw secret payload =
  let digest :: HMAC SHA256
      digest = hmac secret payload
   in convert (hmacGetDigest digest)

hmacHex :: ByteString -> ByteString -> Text
hmacHex secret payload =
  let digest :: HMAC SHA256
      digest = hmac secret payload
   in TextEncoding.decodeUtf8 (convertToBase Base16 (hmacGetDigest digest))

sha256Hex :: ByteString -> Text
sha256Hex bytes =
  let digest :: Digest SHA256
      digest = hash bytes
   in TextEncoding.decodeUtf8 (convertToBase Base16 digest)

-- | URI-encode for AWS canonical query strings.
uriEncode :: Text -> Text
uriEncode = Text.concatMap encodeChar
  where
    encodeChar c
      | isUnreserved c = Text.singleton c
      | otherwise = Text.pack ('%' : hexByte (fromEnum c))
    isUnreserved c =
      isAsciiUpper c
        || isAsciiLower c
        || isDigit c
        || c == '-'
        || c == '_'
        || c == '.'
        || c == '~'
    hexByte n =
      let highNibble = n `div` 16
          lowNibble = n `mod` 16
       in [hexDigit highNibble, hexDigit lowNibble]
    hexDigit n
      | n < 10 = toEnum (fromEnum '0' + n)
      | otherwise = toEnum (fromEnum 'A' + n - 10)

normalizePathPrefix :: Text -> Text
normalizePathPrefix raw
  | Text.null stripped = ""
  | "/" `Text.isPrefixOf` stripped = Text.dropWhileEnd (== '/') stripped
  | otherwise = "/" <> Text.dropWhileEnd (== '/') stripped
  where
    stripped = Text.strip raw
