{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.Auth.Jwt
  ( JwtIssuer (..),
    JwtAudience (..),
    JwtClaims (..),
    Jwk (..),
    Jwks (..),
    JwtValidationConfig (..),
    JwtError (..),
    parseJwks,
    decodeJwtUnverified,
    verifyAndParseJwt,
    selectJwkByKid,
  )
where

import Control.Monad (unless, when)
import Crypto.Hash.Algorithms (SHA256 (..))
import Crypto.PubKey.RSA (PublicKey (..))
import Crypto.PubKey.RSA.PKCS15 qualified as PKCS15
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as AesonTypes
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base64.URL qualified as Base64URL
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as Lazy
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time.Clock (UTCTime, addUTCTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import GHC.Generics (Generic)

-- | Issuer constraint: the JWT must carry an @iss@ claim equal to this value.
newtype JwtIssuer = JwtIssuer {unJwtIssuer :: Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord)

-- | Audience constraint: the JWT must carry an @aud@ claim that includes
-- this value. Keycloak typically emits the audience as a string; this
-- validator also accepts an array.
newtype JwtAudience = JwtAudience {unJwtAudience :: Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord)

-- | Parameters the validator needs. Issuer + audience are stable across the
-- platform's lifetime; the current time and a small leeway are supplied at
-- verification time so the parsing layer stays pure.
data JwtValidationConfig = JwtValidationConfig
  { jwtValidationIssuer :: JwtIssuer,
    jwtValidationAudience :: JwtAudience,
    jwtValidationLeewaySeconds :: Int
  }
  deriving (Eq, Show)

-- | Subset of registered claims the durable-context surface relies on. The
-- @sub@ is the @userId@ the demo uses for per-user MinIO scoping and per-user
-- Pulsar topic families.
data JwtClaims = JwtClaims
  { jwtClaimSubject :: Text,
    jwtClaimIssuer :: Text,
    jwtClaimAudience :: [Text],
    jwtClaimExpiresAtSeconds :: Integer,
    jwtClaimIssuedAtSeconds :: Maybe Integer,
    jwtClaimNotBeforeSeconds :: Maybe Integer
  }
  deriving (Eq, Show)

instance FromJSON JwtClaims where
  parseJSON = Aeson.withObject "JwtClaims" $ \o -> do
    sub <- o Aeson..: "sub"
    iss <- o Aeson..: "iss"
    aud <- parseAudienceField o
    expVal <- o Aeson..: "exp"
    iatVal <- o Aeson..:? "iat"
    nbfVal <- o Aeson..:? "nbf"
    pure
      JwtClaims
        { jwtClaimSubject = sub,
          jwtClaimIssuer = iss,
          jwtClaimAudience = aud,
          jwtClaimExpiresAtSeconds = expVal,
          jwtClaimIssuedAtSeconds = iatVal,
          jwtClaimNotBeforeSeconds = nbfVal
        }
    where
      parseAudienceField o = do
        rawValue <- o Aeson..: "aud"
        case rawValue of
          Aeson.String single -> pure [single]
          Aeson.Array values -> traverse parseSingle (foldr (:) [] values)
          _ -> fail "aud must be a string or array of strings"
      parseSingle = Aeson.withText "aud entry" pure

-- | One JSON Web Key entry. Only RSA keys are supported at this layer
-- because Keycloak issues RS256 tokens by default and that is the supported
-- contract.
data Jwk = Jwk
  { jwkKid :: Text,
    jwkKty :: Text,
    jwkAlg :: Maybe Text,
    jwkUse :: Maybe Text,
    jwkModulusN :: Text,
    jwkExponentE :: Text
  }
  deriving (Eq, Show)

instance FromJSON Jwk where
  parseJSON = Aeson.withObject "Jwk" $ \o -> do
    kid <- o Aeson..: "kid"
    kty <- o Aeson..: "kty"
    alg <- o Aeson..:? "alg"
    use <- o Aeson..:? "use"
    n <- o Aeson..: "n"
    e <- o Aeson..: "e"
    pure
      Jwk
        { jwkKid = kid,
          jwkKty = kty,
          jwkAlg = alg,
          jwkUse = use,
          jwkModulusN = n,
          jwkExponentE = e
        }

-- | Full JWKS document: the @keys@ array.
newtype Jwks = Jwks {unJwks :: [Jwk]}
  deriving (Eq, Show)

instance FromJSON Jwks where
  parseJSON = Aeson.withObject "Jwks" $ \o -> Jwks <$> o Aeson..: "keys"

-- | All the failure modes the validator can return. Each variant names the
-- specific check that failed so the caller can map it onto a typed WS close
-- code or HTTP error response.
data JwtError
  = JwtMalformedStructure
  | JwtUnsupportedAlgorithm Text
  | JwtMissingKid
  | JwtUnknownKid Text
  | JwtNonRsaJwk Text
  | JwtBase64DecodeFailed Text
  | JwtSignatureInvalid
  | JwtClaimParseFailed String
  | JwtIssuerMismatch {jwtIssuerExpected :: Text, jwtIssuerActual :: Text}
  | JwtAudienceMismatch {jwtAudienceExpected :: Text, jwtAudienceActual :: [Text]}
  | JwtExpired {jwtExpiredAt :: Integer, jwtNowAt :: Integer}
  | JwtNotYetValid {jwtNotBefore :: Integer, jwtNowAt :: Integer}
  deriving (Eq, Show)

-- | Parse a JWKS payload from a raw JSON ByteString. Fails with
-- 'JwtClaimParseFailed' on a malformed document.
parseJwks :: Lazy.ByteString -> Either JwtError Jwks
parseJwks bytes = case Aeson.eitherDecode bytes of
  Left err -> Left (JwtClaimParseFailed err)
  Right value -> Right value

-- | The unverified header + claims a JWT carries. Returned by
-- 'decodeJwtUnverified'; treat this as untrusted until 'verifyAndParseJwt'
-- accepts it.
data JwtHeader = JwtHeader
  { jwtHeaderAlg :: Text,
    jwtHeaderKid :: Maybe Text
  }
  deriving (Eq, Show)

instance FromJSON JwtHeader where
  parseJSON = Aeson.withObject "JwtHeader" $ \o -> do
    alg <- o Aeson..: "alg"
    kid <- o Aeson..:? "kid"
    pure JwtHeader {jwtHeaderAlg = alg, jwtHeaderKid = kid}

-- | Decode the JWT's three base64url segments without verifying the
-- signature. Returns the parsed header + claims plus the raw header and
-- payload bytes (needed for signature verification) and the signature bytes.
decodeJwtUnverified ::
  Text ->
  Either JwtError (JwtHeader, JwtClaims, ByteString, ByteString)
decodeJwtUnverified token = do
  (rawHeader, rawPayload, rawSignature) <- splitThreeSegments token
  headerBytes <- base64URLDecode rawHeader
  payloadBytes <- base64URLDecode rawPayload
  signatureBytes <- base64URLDecode rawSignature
  header <- decodeJsonOrFail headerBytes
  claims <- decodeJsonOrFail payloadBytes
  let signingInput = Text.encodeUtf8 (rawHeader <> "." <> rawPayload)
  Right (header, claims, signingInput, signatureBytes)

splitThreeSegments :: Text -> Either JwtError (Text, Text, Text)
splitThreeSegments token = case Text.splitOn "." token of
  [h, p, s] -> Right (h, p, s)
  _ -> Left JwtMalformedStructure

decodeJsonOrFail :: (FromJSON a) => ByteString -> Either JwtError a
decodeJsonOrFail bytes = case Aeson.eitherDecode (Lazy.fromStrict bytes) of
  Left err -> Left (JwtClaimParseFailed err)
  Right value -> Right value

base64URLDecode :: Text -> Either JwtError ByteString
base64URLDecode encoded =
  case Base64URL.decode (Text.encodeUtf8 (padBase64Url encoded)) of
    Left err -> Left (JwtBase64DecodeFailed (Text.pack err))
    Right bytes -> Right bytes

-- | Restore the @=@ padding base64url-without-padding strips.
padBase64Url :: Text -> Text
padBase64Url encoded =
  let remainder = Text.length encoded `mod` 4
   in paddingFor remainder encoded

paddingFor :: Int -> Text -> Text
paddingFor 0 encoded = encoded
paddingFor 2 encoded = encoded <> "=="
paddingFor 3 encoded = encoded <> "="
paddingFor _ encoded = encoded <> "==="

-- | Select the JWK with a matching @kid@. Returns 'JwtMissingKid' when the
-- JWT header has no @kid@; in that case Keycloak's JWKS rotation strategy
-- is incompatible with the supported validator.
selectJwkByKid :: JwtHeader -> Jwks -> Either JwtError Jwk
selectJwkByKid header (Jwks ks) =
  lookupKidInKeys (jwtHeaderKid header) ks

lookupKidInKeys :: Maybe Text -> [Jwk] -> Either JwtError Jwk
lookupKidInKeys Nothing _ = Left JwtMissingKid
lookupKidInKeys (Just kid) ks = case find (\k -> jwkKid k == kid) ks of
  Nothing -> Left (JwtUnknownKid kid)
  Just k -> Right k

-- | Verify the signature and validate the claims. Returns the typed
-- 'JwtClaims' on success or a typed error variant on any failure.
verifyAndParseJwt ::
  JwtValidationConfig ->
  UTCTime ->
  Jwks ->
  Text ->
  Either JwtError JwtClaims
verifyAndParseJwt config now jwks token = do
  (header, claims, signingInput, signature) <- decodeJwtUnverified token
  unless (jwtHeaderAlg header == "RS256") $
    Left (JwtUnsupportedAlgorithm (jwtHeaderAlg header))
  jwk <- selectJwkByKid header jwks
  publicKey <- jwkToRsaPublicKey jwk
  unless (PKCS15.verify (Just SHA256) publicKey signingInput signature) $
    Left JwtSignatureInvalid
  validateClaims config now claims
  Right claims

jwkToRsaPublicKey :: Jwk -> Either JwtError PublicKey
jwkToRsaPublicKey jwk = do
  unless (jwkKty jwk == "RSA") $
    Left (JwtNonRsaJwk (jwkKty jwk))
  modulusBytes <- base64URLDecode (jwkModulusN jwk)
  exponentBytes <- base64URLDecode (jwkExponentE jwk)
  let modulus = bytesToInteger modulusBytes
      publicExponent = bytesToInteger exponentBytes
      modulusSize = BS.length modulusBytes
  Right
    PublicKey
      { public_size = modulusSize,
        public_n = modulus,
        public_e = publicExponent
      }

bytesToInteger :: ByteString -> Integer
bytesToInteger = BS.foldl' (\accumulator byte -> accumulator * 256 + fromIntegral byte) 0

validateClaims :: JwtValidationConfig -> UTCTime -> JwtClaims -> Either JwtError ()
validateClaims config now claims = do
  let expectedIssuer = unJwtIssuer (jwtValidationIssuer config)
      expectedAudience = unJwtAudience (jwtValidationAudience config)
      leeway = fromIntegral (jwtValidationLeewaySeconds config)
      nowSeconds = floor (utcTimeToPOSIXSeconds now) :: Integer
      windowEarliest = floor (utcTimeToPOSIXSeconds (addUTCTime (negate leeway) now)) :: Integer
      windowLatest = floor (utcTimeToPOSIXSeconds (addUTCTime leeway now)) :: Integer
  when (jwtClaimIssuer claims /= expectedIssuer) $
    Left
      JwtIssuerMismatch
        { jwtIssuerExpected = expectedIssuer,
          jwtIssuerActual = jwtClaimIssuer claims
        }
  unless (expectedAudience `elem` jwtClaimAudience claims) $
    Left
      JwtAudienceMismatch
        { jwtAudienceExpected = expectedAudience,
          jwtAudienceActual = jwtClaimAudience claims
        }
  when (jwtClaimExpiresAtSeconds claims < windowEarliest) $
    Left
      JwtExpired
        { jwtExpiredAt = jwtClaimExpiresAtSeconds claims,
          jwtNowAt = nowSeconds
        }
  case jwtClaimNotBeforeSeconds claims of
    Just nbf
      | nbf > windowLatest ->
          Left JwtNotYetValid {jwtNotBefore = nbf, jwtNowAt = nowSeconds}
    _ -> Right ()

-- Suppress unused warnings for instance/import surface used by downstream callers.
_unusedShim :: ByteString -> ByteString
_unusedShim = BS8.dropWhile (== '\0')

_unusedShimAeson :: AesonTypes.Value -> AesonTypes.Value
_unusedShimAeson = id

_unusedJsonOut :: (ToJSON a) => a -> Aeson.Value
_unusedJsonOut = Aeson.toJSON
