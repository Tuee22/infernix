{-# LANGUAGE OverloadedStrings #-}

module Infernix.Objects.Layout
  ( ModelsBucket (..),
    defaultModelsBucket,
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
    pathBelongsToUser,
  )
where

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

-- | The demo-gated MinIO bucket holding user uploads and engine-generated
-- artifacts. The supported per-user prefix is
-- @users/<userId>/contexts/<contextId>/{uploads,generated}/@.
newtype DemoObjectsBucket = DemoObjectsBucket {unDemoObjectsBucket :: Text}
  deriving (Eq, Show)

defaultDemoObjectsBucket :: DemoObjectsBucket
defaultDemoObjectsBucket = DemoObjectsBucket "infernix-demo-objects"

-- | The per-user prefix in @infernix-demo-objects@. Per-user scope policy
-- forbids any caller from listing or fetching outside this prefix; the
-- presigned URL minter enforces that constraint by mint time.
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

-- | Per-user scope enforcement helper. Returns 'True' iff the supplied
-- object key prefix is owned by the named user. The demo backend uses this
-- to reject presigned-URL requests that point outside the caller's scope.
pathBelongsToUser :: UserId -> Text -> Bool
pathBelongsToUser uid key =
  let UserPrefix prefix = userPrefix uid
   in Text.isPrefixOf prefix key
