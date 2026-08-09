{- This file was auto-generated from infernix/manifest/runtime_manifest.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Infernix.Manifest.RuntimeManifest_Fields where
import qualified Data.ProtoLens.Runtime.Prelude as Prelude
import qualified Data.ProtoLens.Runtime.Data.Int as Data.Int
import qualified Data.ProtoLens.Runtime.Data.Monoid as Data.Monoid
import qualified Data.ProtoLens.Runtime.Data.Word as Data.Word
import qualified Data.ProtoLens.Runtime.Data.ProtoLens as Data.ProtoLens
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Bytes as Data.ProtoLens.Encoding.Bytes
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Growing as Data.ProtoLens.Encoding.Growing
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Parser.Unsafe as Data.ProtoLens.Encoding.Parser.Unsafe
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Wire as Data.ProtoLens.Encoding.Wire
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Field as Data.ProtoLens.Field
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Message.Enum as Data.ProtoLens.Message.Enum
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Service.Types as Data.ProtoLens.Service.Types
import qualified Data.ProtoLens.Runtime.Lens.Family2 as Lens.Family2
import qualified Data.ProtoLens.Runtime.Lens.Family2.Unchecked as Lens.Family2.Unchecked
import qualified Data.ProtoLens.Runtime.Data.Text as Data.Text
import qualified Data.ProtoLens.Runtime.Data.Map as Data.Map
import qualified Data.ProtoLens.Runtime.Data.ByteString as Data.ByteString
import qualified Data.ProtoLens.Runtime.Data.ByteString.Char8 as Data.ByteString.Char8
import qualified Data.ProtoLens.Runtime.Data.Text.Encoding as Data.Text.Encoding
import qualified Data.ProtoLens.Runtime.Data.Vector as Data.Vector
import qualified Data.ProtoLens.Runtime.Data.Vector.Generic as Data.Vector.Generic
import qualified Data.ProtoLens.Runtime.Data.Vector.Unboxed as Data.Vector.Unboxed
import qualified Data.ProtoLens.Runtime.Text.Read as Text.Read
cacheEntries ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cacheEntries" a) =>
  Lens.Family2.LensLike' f s a
cacheEntries = Data.ProtoLens.Field.field @"cacheEntries"
cacheKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cacheKey" a) =>
  Lens.Family2.LensLike' f s a
cacheKey = Data.ProtoLens.Field.field @"cacheKey"
cachePath ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cachePath" a) =>
  Lens.Family2.LensLike' f s a
cachePath = Data.ProtoLens.Field.field @"cachePath"
durableResultsPrefix ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "durableResultsPrefix" a) =>
  Lens.Family2.LensLike' f s a
durableResultsPrefix
  = Data.ProtoLens.Field.field @"durableResultsPrefix"
durableSourceUri ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "durableSourceUri" a) =>
  Lens.Family2.LensLike' f s a
durableSourceUri = Data.ProtoLens.Field.field @"durableSourceUri"
manifestId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "manifestId" a) =>
  Lens.Family2.LensLike' f s a
manifestId = Data.ProtoLens.Field.field @"manifestId"
materializations ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "materializations" a) =>
  Lens.Family2.LensLike' f s a
materializations = Data.ProtoLens.Field.field @"materializations"
materialized ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "materialized" a) =>
  Lens.Family2.LensLike' f s a
materialized = Data.ProtoLens.Field.field @"materialized"
materializedCachePath ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "materializedCachePath" a) =>
  Lens.Family2.LensLike' f s a
materializedCachePath
  = Data.ProtoLens.Field.field @"materializedCachePath"
modelId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "modelId" a) =>
  Lens.Family2.LensLike' f s a
modelId = Data.ProtoLens.Field.field @"modelId"
runtimeMode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "runtimeMode" a) =>
  Lens.Family2.LensLike' f s a
runtimeMode = Data.ProtoLens.Field.field @"runtimeMode"
selectedEngine ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "selectedEngine" a) =>
  Lens.Family2.LensLike' f s a
selectedEngine = Data.ProtoLens.Field.field @"selectedEngine"
vec'cacheEntries ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'cacheEntries" a) =>
  Lens.Family2.LensLike' f s a
vec'cacheEntries = Data.ProtoLens.Field.field @"vec'cacheEntries"
vec'materializations ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'materializations" a) =>
  Lens.Family2.LensLike' f s a
vec'materializations
  = Data.ProtoLens.Field.field @"vec'materializations"