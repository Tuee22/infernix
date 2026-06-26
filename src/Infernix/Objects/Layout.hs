{-# LANGUAGE OverloadedStrings #-}

module Infernix.Objects.Layout
  ( ModelsBucket (..),
    defaultModelsBucket,
    EngineArtifactsBucket (..),
    defaultEngineArtifactsBucket,
    DemoObjectsBucket (..),
    defaultDemoObjectsBucket,
    UserPrefix (..),
    userPrefix,
    ContextPrefix (..),
    contextPrefix,
    uploadObjectKey,
    generatedObjectKey,
    modelObjectKey,
    modelReadySentinelKey,
    engineArtifactObjectKey,
    pathBelongsToUser,
    sanitizeFilename,
  )
where

import Data.Char (isAlphaNum)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Web.Contracts
  ( ContextId (..),
    ObjectRef (..),
    UserId (..),
  )

-- | The MinIO bucket holding platform model weights, tokenizers, and configs.
-- Always-on regardless of @demo_ui@. The supported layout is
-- @<modelId>/<filename>@ with a @<modelId>/.ready@ sentinel written last.
newtype ModelsBucket = ModelsBucket {unModelsBucket :: Text}
  deriving (Eq, Show)

defaultModelsBucket :: ModelsBucket
defaultModelsBucket = ModelsBucket "infernix-models"

-- | The MinIO bucket holding immutable engine software payloads. Model
-- weights and user-visible generated artifacts never live here.
newtype EngineArtifactsBucket = EngineArtifactsBucket {unEngineArtifactsBucket :: Text}
  deriving (Eq, Show)

defaultEngineArtifactsBucket :: EngineArtifactsBucket
defaultEngineArtifactsBucket = EngineArtifactsBucket "infernix-engine-artifacts"

-- | The demo-gated MinIO bucket holding user uploads and engine-generated
-- artifacts. The supported per-user prefix is
-- @users/<userId>/contexts/<contextId>/{uploads,generated}/@.
newtype DemoObjectsBucket = DemoObjectsBucket {unDemoObjectsBucket :: Text}
  deriving (Eq, Show)

defaultDemoObjectsBucket :: DemoObjectsBucket
defaultDemoObjectsBucket = DemoObjectsBucket "infernix-demo-objects"

-- | The per-user prefix in @infernix-demo-objects@. The presigned URL
-- minter derives object keys from the authenticated user's subject and
-- enforces this prefix at grant time.
newtype UserPrefix = UserPrefix {unUserPrefix :: Text}
  deriving (Eq, Show)

userPrefix :: UserId -> UserPrefix
userPrefix (UserId userId) = UserPrefix ("users/" <> userId <> "/")

-- | The per-context prefix beneath a user prefix. Adding a per-context layer
-- means soft-delete or rename can target the whole context tree without
-- touching unrelated artifacts.
newtype ContextPrefix = ContextPrefix {unContextPrefix :: Text}
  deriving (Eq, Show)

contextPrefix :: UserId -> ContextId -> ContextPrefix
contextPrefix uid (ContextId cid) =
  let UserPrefix base = userPrefix uid
   in ContextPrefix (base <> "contexts/" <> cid <> "/")

-- | Build an @ObjectRef@ for a user upload. @filename@ is the operator-
-- supplied display name; the demo backend is free to UUID-prefix it before
-- minting the presigned URL but the layout rule itself does not require that.
uploadObjectKey :: UserId -> ContextId -> Text -> ObjectRef
uploadObjectKey uid cid filename =
  let ContextPrefix base = contextPrefix uid cid
      DemoObjectsBucket bucket = defaultDemoObjectsBucket
   in ObjectRef
        { objectBucket = bucket,
          objectKey = base <> "uploads/" <> filename
        }

-- | Build an @ObjectRef@ for an engine-generated artifact (image, audio,
-- video, MIDI, or notation file).
generatedObjectKey :: UserId -> ContextId -> Text -> ObjectRef
generatedObjectKey uid cid filename =
  let ContextPrefix base = contextPrefix uid cid
      DemoObjectsBucket bucket = defaultDemoObjectsBucket
   in ObjectRef
        { objectBucket = bucket,
          objectKey = base <> "generated/" <> filename
        }

-- | Build an @ObjectRef@ for a model-weights file in the always-on
-- @infernix-models@ bucket. The supported layout is
-- @<modelId>/<filename>@.
modelObjectKey :: Text -> Text -> ObjectRef
modelObjectKey modelId filename =
  let ModelsBucket bucket = defaultModelsBucket
   in ObjectRef
        { objectBucket = bucket,
          objectKey = modelId <> "/" <> filename
        }

-- | The supported @.ready@ sentinel key for a model. Written last by the
-- coordinator's bootstrap subscription; engines wait for this object before
-- loading.
modelReadySentinelKey :: Text -> ObjectRef
modelReadySentinelKey modelId = modelObjectKey modelId ".ready"

-- | Build an @ObjectRef@ for an immutable engine software payload.
-- Digests may be supplied as @sha256:<hex>@ or just @<hex>@; the
-- content-addressed object key always uses @sha256/<hex>@.
engineArtifactObjectKey :: Text -> ObjectRef
engineArtifactObjectKey digest =
  let EngineArtifactsBucket bucket = defaultEngineArtifactsBucket
      digestSuffix = Text.dropWhile (== ':') (Text.dropWhile (/= ':') digest)
      digestHex
        | Text.isPrefixOf "sha256:" digest = digestSuffix
        | otherwise = digest
   in ObjectRef
        { objectBucket = bucket,
          objectKey = "sha256/" <> digestHex
        }

-- | Per-user scope enforcement helper. Returns 'True' iff the supplied
-- object key prefix is owned by the named user. The demo backend uses this
-- as the final guard before minting a presigned URL.
pathBelongsToUser :: UserId -> Text -> Bool
pathBelongsToUser uid key =
  let UserPrefix prefix = userPrefix uid
   in Text.isPrefixOf prefix key

-- | Neutralize a client-supplied artifact display name before it becomes part
-- of a server-derived object key. Phase 7 Sprint 7.25 makes the webapp the
-- single object mediator, so the only client-controlled component of an upload
-- key is the display name; this strips any directory components and path
-- traversal, keeps a conservative @[A-Za-z0-9._-]@ character set (other
-- characters collapse to @_@), forbids a leading dot, bounds the length, and
-- falls back to @file@ when nothing safe remains. The owning per-user prefix is
-- always derived from the verified @sub@, never from this value.
sanitizeFilename :: Text -> Text
sanitizeFilename raw =
  let lastSegment = last (Text.splitOn "/" (Text.replace "\\" "/" raw))
      mapped = Text.map keepOrUnderscore (Text.strip lastSegment)
      deDotted = Text.dropWhile (== '.') mapped
      bounded = Text.take 200 deDotted
   in if Text.null bounded then "file" else bounded
  where
    keepOrUnderscore c
      | isAlphaNum c = c
      | c `elem` ['.', '_', '-'] = c
      | otherwise = '_'
