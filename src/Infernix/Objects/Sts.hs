{-# LANGUAGE OverloadedStrings #-}

-- | Phase 9 Sprint 9.7 — per-user MinIO STS defense-in-depth. The webapp
-- object-proxy already derives every object key server-side from the verified
-- Keycloak @sub@ and rejects a cross-user key with 'pathBelongsToUser'
-- (Phase 7). This module adds a second, independent boundary at the IAM layer:
-- before touching MinIO for a per-user operation, the webapp exchanges the
-- shared root credential for a short-lived credential scoped by an inline
-- session policy to the caller's @users\/<sub>\/@ prefix (MinIO STS
-- @AssumeRole@). If the server-side path check were ever bypassed, MinIO itself
-- would still deny access outside the caller's prefix — the shared root
-- credential stops being the sole isolation boundary.
--
-- The signing and response parsing are pure so they are validated by the
-- machine-independent unit gate; the HTTP exchange lives in the object-proxy
-- (`src/Infernix/Demo/Api.hs`). The live cross-user IAM-denial proof is the
-- Wave Q cohort residual. Canonical doctrine:
-- documents/architecture/access_control_doctrine.md and
-- documents/architecture/tenant_isolation_doctrine.md.
module Infernix.Objects.Sts
  ( StsConfig (..),
    ScopedCredentials (..),
    SignedStsRequest (..),
    userScopedPolicyDocument,
    encodedUserScopedPolicy,
    stsAssumeRoleForm,
    signedStsAssumeRoleRequest,
    parseAssumeRoleCredentials,
  )
where

import Crypto.Hash (Digest, SHA256, hash)
import Crypto.MAC.HMAC (HMAC (..), hmac)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as Lazy
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Infernix.Objects.Layout (UserPrefix (..), userPrefix)
import Infernix.Web.Contracts (UserId (..))

-- | The wiring the webapp needs to mint a per-user scoped credential. The
-- endpoint + region + root credential match the internal MinIO presigned
-- config the object-proxy already loads; @stsBucket@ is the demo-objects
-- bucket the session policy scopes.
data StsConfig = StsConfig
  { stsScheme :: Text,
    stsEndpoint :: Text,
    stsRegion :: Text,
    stsAccessKeyId :: Text,
    stsSecretAccessKey :: Text,
    stsDurationSeconds :: Int,
    stsBucket :: Text
  }
  deriving (Eq, Show)

-- | The short-lived credential MinIO STS returns from @AssumeRole@. The
-- session token is threaded into the presigned S3 request as
-- @X-Amz-Security-Token@.
data ScopedCredentials = ScopedCredentials
  { scopedAccessKeyId :: Text,
    scopedSecretAccessKey :: Text,
    scopedSessionToken :: Text,
    scopedExpiration :: Text
  }
  deriving (Eq, Show)

-- | A fully signed MinIO STS @AssumeRole@ request. The caller sends
-- 'signedStsBody' verbatim as the POST body with the three named headers.
data SignedStsRequest = SignedStsRequest
  { signedStsUrl :: Text,
    signedStsBody :: Text,
    signedStsAuthorization :: Text,
    signedStsAmzDate :: Text,
    signedStsContentType :: Text
  }
  deriving (Eq, Show)

-- | The inline session policy scoping the assumed credential to the caller's
-- @users\/<sub>\/@ prefix. Object read/write/delete is allowed only under that
-- prefix, and @ListBucket@ is constrained to it by an @s3:prefix@ condition.
userScopedPolicyDocument :: Text -> UserId -> Value
userScopedPolicyDocument bucket userId =
  let UserPrefix prefix = userPrefix userId
      objectArn = "arn:aws:s3:::" <> bucket <> "/" <> prefix <> "*"
      bucketArn = "arn:aws:s3:::" <> bucket
   in object
        [ "Version" .= ("2012-10-17" :: Text),
          "Statement"
            .= [ object
                   [ "Effect" .= ("Allow" :: Text),
                     "Action" .= (["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] :: [Text]),
                     "Resource" .= ([objectArn] :: [Text])
                   ],
                 object
                   [ "Effect" .= ("Allow" :: Text),
                     "Action" .= (["s3:ListBucket"] :: [Text]),
                     "Resource" .= ([bucketArn] :: [Text]),
                     "Condition"
                       .= object
                         [ "StringLike"
                             .= object ["s3:prefix" .= ([prefix <> "*"] :: [Text])]
                         ]
                   ]
               ]
        ]

-- | The scoped policy serialized to the compact JSON MinIO STS expects in the
-- @Policy@ form field.
encodedUserScopedPolicy :: Text -> UserId -> Text
encodedUserScopedPolicy bucket userId =
  TextEncoding.decodeUtf8 (Lazy.toStrict (encode (userScopedPolicyDocument bucket userId)))

-- | The @AssumeRole@ form parameters (in canonical body order).
stsAssumeRoleForm :: StsConfig -> UserId -> [(Text, Text)]
stsAssumeRoleForm config userId =
  [ ("Action", "AssumeRole"),
    ("Version", "2011-06-15"),
    ("DurationSeconds", Text.pack (show (stsDurationSeconds config))),
    ("Policy", encodedUserScopedPolicy (stsBucket config) userId)
  ]

-- | Header-based AWS SigV4 signing (service @sts@) of the @AssumeRole@ POST.
-- Signing is implemented directly from the SigV4 spec — canonical request ->
-- string to sign -> HMAC chain -> hex signature in an @Authorization@ header —
-- so the webapp keeps no extra SDK dependency, matching
-- 'Infernix.Objects.Presigned'.
signedStsAssumeRoleRequest :: StsConfig -> UserId -> UTCTime -> SignedStsRequest
signedStsAssumeRoleRequest config userId now =
  let host = stsEndpoint config
      region = stsRegion config
      service = "sts" :: Text
      contentType = "application/x-www-form-urlencoded" :: Text
      amzDate = Text.pack (formatTime defaultTimeLocale "%Y%m%dT%H%M%SZ" now)
      dateStamp = Text.pack (formatTime defaultTimeLocale "%Y%m%d" now)
      body = formUrlEncode (stsAssumeRoleForm config userId)
      bodyHash = sha256Hex (TextEncoding.encodeUtf8 body)
      signedHeaders = "content-type;host;x-amz-date" :: Text
      canonicalHeaders =
        "content-type:"
          <> contentType
          <> "\nhost:"
          <> host
          <> "\nx-amz-date:"
          <> amzDate
          <> "\n"
      canonicalRequest =
        Text.intercalate
          "\n"
          ["POST", "/", "", canonicalHeaders, signedHeaders, bodyHash]
      hashedCanonical = sha256Hex (TextEncoding.encodeUtf8 canonicalRequest)
      credentialScope = dateStamp <> "/" <> region <> "/" <> service <> "/aws4_request"
      stringToSign =
        Text.intercalate
          "\n"
          ["AWS4-HMAC-SHA256", amzDate, credentialScope, hashedCanonical]
      signingKey = deriveSigningKey (stsSecretAccessKey config) dateStamp region service
      signature = hmacHex signingKey (TextEncoding.encodeUtf8 stringToSign)
      credential = stsAccessKeyId config <> "/" <> credentialScope
      authorization =
        "AWS4-HMAC-SHA256 Credential="
          <> credential
          <> ", SignedHeaders="
          <> signedHeaders
          <> ", Signature="
          <> signature
   in SignedStsRequest
        { signedStsUrl = stsScheme config <> "://" <> host <> "/",
          signedStsBody = body,
          signedStsAuthorization = authorization,
          signedStsAmzDate = amzDate,
          signedStsContentType = contentType
        }

-- | Parse the @AssumeRole@ XML response into the scoped credential. Returns
-- 'Left' when any required @Credentials@ field is absent.
parseAssumeRoleCredentials :: Text -> Either String ScopedCredentials
parseAssumeRoleCredentials xmlBody =
  case (extractTag "AccessKeyId", extractTag "SecretAccessKey", extractTag "SessionToken") of
    (Just accessKeyId, Just secretKey, Just sessionToken) ->
      Right
        ScopedCredentials
          { scopedAccessKeyId = accessKeyId,
            scopedSecretAccessKey = secretKey,
            scopedSessionToken = sessionToken,
            scopedExpiration = fromMaybe "" (extractTag "Expiration")
          }
    _ ->
      Left
        ( "MinIO STS AssumeRole response is missing Credentials fields: "
            <> Text.unpack (Text.take 300 xmlBody)
        )
  where
    extractTag tagName =
      let openTag = "<" <> tagName <> ">"
          closeTag = "</" <> tagName <> ">"
          (_, afterOpen) = Text.breakOn openTag xmlBody
       in if Text.null afterOpen
            then Nothing
            else
              let inner = Text.drop (Text.length openTag) afterOpen
                  (value, afterClose) = Text.breakOn closeTag inner
               in if Text.null afterClose then Nothing else Just value

formUrlEncode :: [(Text, Text)] -> Text
formUrlEncode params =
  Text.intercalate "&" [uriEncode key <> "=" <> uriEncode value | (key, value) <- params]

deriveSigningKey :: Text -> Text -> Text -> Text -> ByteString
deriveSigningKey secret dateStamp region service =
  let kSecret = TextEncoding.encodeUtf8 ("AWS4" <> secret)
      kDate = hmacRaw kSecret (TextEncoding.encodeUtf8 dateStamp)
      kRegion = hmacRaw kDate (TextEncoding.encodeUtf8 region)
      kService = hmacRaw kRegion (TextEncoding.encodeUtf8 service)
   in hmacRaw kService "aws4_request"

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
