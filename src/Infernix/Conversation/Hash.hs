{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.Conversation.Hash
  ( PrefixHash (..),
    emptyPrefixHash,
    extendPrefixHash,
    extendPrefixHashWithMessage,
    prefixHashChainOver,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as Lazy
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import GHC.Generics (Generic)
import Infernix.Web.Contracts (ConversationMessage)

-- | Merkle-style chain hash for a conversation log prefix. Equality means
-- provably-identical event sequence; mismatch means the projection must be
-- rebuilt from the log.
newtype PrefixHash = PrefixHash {unPrefixHash :: Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON)

-- | The hash of an empty prefix. Used as the seed for the chain.
emptyPrefixHash :: PrefixHash
emptyPrefixHash = PrefixHash (hashBytes "")

-- | Append a JSON-encoded message to a prefix and return the new prefix hash.
-- @newHash = SHA256(oldHash || sha256(message_bytes))@. Each layer is hashed
-- so chain mutation in either parent or message cascades to the result.
extendPrefixHash :: PrefixHash -> Lazy.ByteString -> PrefixHash
extendPrefixHash (PrefixHash parentHexText) messageBytes =
  let parentBytes = Text.encodeUtf8 parentHexText
      messageDigest = SHA256.hashlazy messageBytes
      combinedBytes = parentBytes <> messageDigest
   in PrefixHash (Text.decodeUtf8 (Base16.encode (SHA256.hash combinedBytes)))

-- | Hash a typed @ConversationMessage@ into the prefix chain by encoding it
-- as canonical JSON first. Aeson's @encode@ is deterministic for our wire types
-- because we use only @ToJSON@ instances derived through @taggedSumOptions@ and
-- records with fixed field order.
extendPrefixHashWithMessage :: PrefixHash -> ConversationMessage -> PrefixHash
extendPrefixHashWithMessage parent message =
  extendPrefixHash parent (Aeson.encode message)

-- | Fold a list of messages through the chain, returning each intermediate
-- hash. Useful for property tests and the engine's @prefixHash@ verification
-- step.
prefixHashChainOver :: [ConversationMessage] -> [PrefixHash]
prefixHashChainOver = scanl extendPrefixHashWithMessage emptyPrefixHash

hashBytes :: BS.ByteString -> Text
hashBytes = Text.decodeUtf8 . Base16.encode . SHA256.hash
