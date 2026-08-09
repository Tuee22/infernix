{- This file was auto-generated from infernix/manifest/runtime_manifest.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Infernix.Manifest.RuntimeManifest (
        ModelMaterialization(), RuntimeCacheEntry(), RuntimeManifest()
    ) where
import qualified Data.ProtoLens.Runtime.Control.DeepSeq as Control.DeepSeq
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Prism as Data.ProtoLens.Prism
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
{- | Fields :
     
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.runtimeMode' @:: Lens' ModelMaterialization Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.modelId' @:: Lens' ModelMaterialization Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.selectedEngine' @:: Lens' ModelMaterialization Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.durableSourceUri' @:: Lens' ModelMaterialization Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.materializedCachePath' @:: Lens' ModelMaterialization Data.Text.Text@ -}
data ModelMaterialization
  = ModelMaterialization'_constructor {_ModelMaterialization'runtimeMode :: !Data.Text.Text,
                                       _ModelMaterialization'modelId :: !Data.Text.Text,
                                       _ModelMaterialization'selectedEngine :: !Data.Text.Text,
                                       _ModelMaterialization'durableSourceUri :: !Data.Text.Text,
                                       _ModelMaterialization'materializedCachePath :: !Data.Text.Text,
                                       _ModelMaterialization'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ModelMaterialization where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ModelMaterialization "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMaterialization'runtimeMode
           (\ x__ y__ -> x__ {_ModelMaterialization'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMaterialization "modelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMaterialization'modelId
           (\ x__ y__ -> x__ {_ModelMaterialization'modelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMaterialization "selectedEngine" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMaterialization'selectedEngine
           (\ x__ y__ -> x__ {_ModelMaterialization'selectedEngine = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMaterialization "durableSourceUri" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMaterialization'durableSourceUri
           (\ x__ y__ -> x__ {_ModelMaterialization'durableSourceUri = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMaterialization "materializedCachePath" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMaterialization'materializedCachePath
           (\ x__ y__
              -> x__ {_ModelMaterialization'materializedCachePath = y__}))
        Prelude.id
instance Data.ProtoLens.Message ModelMaterialization where
  messageName _
    = Data.Text.pack "infernix.manifest.ModelMaterialization"
  packedMessageDescriptor _
    = "\n\
      \\DC4ModelMaterialization\DC2!\n\
      \\fruntime_mode\CAN\SOH \SOH(\tR\vruntimeMode\DC2\EM\n\
      \\bmodel_id\CAN\STX \SOH(\tR\amodelId\DC2'\n\
      \\SIselected_engine\CAN\ETX \SOH(\tR\SOselectedEngine\DC2,\n\
      \\DC2durable_source_uri\CAN\EOT \SOH(\tR\DLEdurableSourceUri\DC26\n\
      \\ETBmaterialized_cache_path\CAN\ENQ \SOH(\tR\NAKmaterializedCachePath"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor ModelMaterialization
        modelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"modelId")) ::
              Data.ProtoLens.FieldDescriptor ModelMaterialization
        selectedEngine__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "selected_engine"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"selectedEngine")) ::
              Data.ProtoLens.FieldDescriptor ModelMaterialization
        durableSourceUri__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "durable_source_uri"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"durableSourceUri")) ::
              Data.ProtoLens.FieldDescriptor ModelMaterialization
        materializedCachePath__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "materialized_cache_path"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"materializedCachePath")) ::
              Data.ProtoLens.FieldDescriptor ModelMaterialization
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 2, modelId__field_descriptor),
           (Data.ProtoLens.Tag 3, selectedEngine__field_descriptor),
           (Data.ProtoLens.Tag 4, durableSourceUri__field_descriptor),
           (Data.ProtoLens.Tag 5, materializedCachePath__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ModelMaterialization'_unknownFields
        (\ x__ y__ -> x__ {_ModelMaterialization'_unknownFields = y__})
  defMessage
    = ModelMaterialization'_constructor
        {_ModelMaterialization'runtimeMode = Data.ProtoLens.fieldDefault,
         _ModelMaterialization'modelId = Data.ProtoLens.fieldDefault,
         _ModelMaterialization'selectedEngine = Data.ProtoLens.fieldDefault,
         _ModelMaterialization'durableSourceUri = Data.ProtoLens.fieldDefault,
         _ModelMaterialization'materializedCachePath = Data.ProtoLens.fieldDefault,
         _ModelMaterialization'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ModelMaterialization
          -> Data.ProtoLens.Encoding.Bytes.Parser ModelMaterialization
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"modelId") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "selected_engine"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"selectedEngine") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "durable_source_uri"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"durableSourceUri") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "materialized_cache_path"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"materializedCachePath") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ModelMaterialization"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"runtimeMode") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"modelId") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view
                            (Data.ProtoLens.Field.field @"selectedEngine") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"durableSourceUri") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"materializedCachePath") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData ModelMaterialization where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ModelMaterialization'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ModelMaterialization'runtimeMode x__)
                (Control.DeepSeq.deepseq
                   (_ModelMaterialization'modelId x__)
                   (Control.DeepSeq.deepseq
                      (_ModelMaterialization'selectedEngine x__)
                      (Control.DeepSeq.deepseq
                         (_ModelMaterialization'durableSourceUri x__)
                         (Control.DeepSeq.deepseq
                            (_ModelMaterialization'materializedCachePath x__) ())))))
{- | Fields :
     
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.runtimeMode' @:: Lens' RuntimeCacheEntry Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.modelId' @:: Lens' RuntimeCacheEntry Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.cacheKey' @:: Lens' RuntimeCacheEntry Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.cachePath' @:: Lens' RuntimeCacheEntry Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.materialized' @:: Lens' RuntimeCacheEntry Prelude.Bool@ -}
data RuntimeCacheEntry
  = RuntimeCacheEntry'_constructor {_RuntimeCacheEntry'runtimeMode :: !Data.Text.Text,
                                    _RuntimeCacheEntry'modelId :: !Data.Text.Text,
                                    _RuntimeCacheEntry'cacheKey :: !Data.Text.Text,
                                    _RuntimeCacheEntry'cachePath :: !Data.Text.Text,
                                    _RuntimeCacheEntry'materialized :: !Prelude.Bool,
                                    _RuntimeCacheEntry'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RuntimeCacheEntry where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RuntimeCacheEntry "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeCacheEntry'runtimeMode
           (\ x__ y__ -> x__ {_RuntimeCacheEntry'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeCacheEntry "modelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeCacheEntry'modelId
           (\ x__ y__ -> x__ {_RuntimeCacheEntry'modelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeCacheEntry "cacheKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeCacheEntry'cacheKey
           (\ x__ y__ -> x__ {_RuntimeCacheEntry'cacheKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeCacheEntry "cachePath" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeCacheEntry'cachePath
           (\ x__ y__ -> x__ {_RuntimeCacheEntry'cachePath = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeCacheEntry "materialized" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeCacheEntry'materialized
           (\ x__ y__ -> x__ {_RuntimeCacheEntry'materialized = y__}))
        Prelude.id
instance Data.ProtoLens.Message RuntimeCacheEntry where
  messageName _
    = Data.Text.pack "infernix.manifest.RuntimeCacheEntry"
  packedMessageDescriptor _
    = "\n\
      \\DC1RuntimeCacheEntry\DC2!\n\
      \\fruntime_mode\CAN\SOH \SOH(\tR\vruntimeMode\DC2\EM\n\
      \\bmodel_id\CAN\STX \SOH(\tR\amodelId\DC2\ESC\n\
      \\tcache_key\CAN\ETX \SOH(\tR\bcacheKey\DC2\GS\n\
      \\n\
      \cache_path\CAN\EOT \SOH(\tR\tcachePath\DC2\"\n\
      \\fmaterialized\CAN\ENQ \SOH(\bR\fmaterialized"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor RuntimeCacheEntry
        modelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"modelId")) ::
              Data.ProtoLens.FieldDescriptor RuntimeCacheEntry
        cacheKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cacheKey")) ::
              Data.ProtoLens.FieldDescriptor RuntimeCacheEntry
        cachePath__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_path"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cachePath")) ::
              Data.ProtoLens.FieldDescriptor RuntimeCacheEntry
        materialized__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "materialized"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"materialized")) ::
              Data.ProtoLens.FieldDescriptor RuntimeCacheEntry
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 2, modelId__field_descriptor),
           (Data.ProtoLens.Tag 3, cacheKey__field_descriptor),
           (Data.ProtoLens.Tag 4, cachePath__field_descriptor),
           (Data.ProtoLens.Tag 5, materialized__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RuntimeCacheEntry'_unknownFields
        (\ x__ y__ -> x__ {_RuntimeCacheEntry'_unknownFields = y__})
  defMessage
    = RuntimeCacheEntry'_constructor
        {_RuntimeCacheEntry'runtimeMode = Data.ProtoLens.fieldDefault,
         _RuntimeCacheEntry'modelId = Data.ProtoLens.fieldDefault,
         _RuntimeCacheEntry'cacheKey = Data.ProtoLens.fieldDefault,
         _RuntimeCacheEntry'cachePath = Data.ProtoLens.fieldDefault,
         _RuntimeCacheEntry'materialized = Data.ProtoLens.fieldDefault,
         _RuntimeCacheEntry'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RuntimeCacheEntry
          -> Data.ProtoLens.Encoding.Bytes.Parser RuntimeCacheEntry
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"modelId") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "cache_key"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"cacheKey") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "cache_path"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"cachePath") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "materialized"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"materialized") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "RuntimeCacheEntry"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"runtimeMode") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"modelId") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"cacheKey") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"cachePath") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"materialized") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                  ((Prelude..)
                                     Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (\ b -> if b then 1 else 0) _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData RuntimeCacheEntry where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RuntimeCacheEntry'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RuntimeCacheEntry'runtimeMode x__)
                (Control.DeepSeq.deepseq
                   (_RuntimeCacheEntry'modelId x__)
                   (Control.DeepSeq.deepseq
                      (_RuntimeCacheEntry'cacheKey x__)
                      (Control.DeepSeq.deepseq
                         (_RuntimeCacheEntry'cachePath x__)
                         (Control.DeepSeq.deepseq
                            (_RuntimeCacheEntry'materialized x__) ())))))
{- | Fields :
     
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.manifestId' @:: Lens' RuntimeManifest Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.runtimeMode' @:: Lens' RuntimeManifest Data.Text.Text@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.materializations' @:: Lens' RuntimeManifest [ModelMaterialization]@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.vec'materializations' @:: Lens' RuntimeManifest (Data.Vector.Vector ModelMaterialization)@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.cacheEntries' @:: Lens' RuntimeManifest [RuntimeCacheEntry]@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.vec'cacheEntries' @:: Lens' RuntimeManifest (Data.Vector.Vector RuntimeCacheEntry)@
         * 'Proto.Infernix.Manifest.RuntimeManifest_Fields.durableResultsPrefix' @:: Lens' RuntimeManifest Data.Text.Text@ -}
data RuntimeManifest
  = RuntimeManifest'_constructor {_RuntimeManifest'manifestId :: !Data.Text.Text,
                                  _RuntimeManifest'runtimeMode :: !Data.Text.Text,
                                  _RuntimeManifest'materializations :: !(Data.Vector.Vector ModelMaterialization),
                                  _RuntimeManifest'cacheEntries :: !(Data.Vector.Vector RuntimeCacheEntry),
                                  _RuntimeManifest'durableResultsPrefix :: !Data.Text.Text,
                                  _RuntimeManifest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RuntimeManifest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RuntimeManifest "manifestId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'manifestId
           (\ x__ y__ -> x__ {_RuntimeManifest'manifestId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeManifest "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'runtimeMode
           (\ x__ y__ -> x__ {_RuntimeManifest'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeManifest "materializations" [ModelMaterialization] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'materializations
           (\ x__ y__ -> x__ {_RuntimeManifest'materializations = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RuntimeManifest "vec'materializations" (Data.Vector.Vector ModelMaterialization) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'materializations
           (\ x__ y__ -> x__ {_RuntimeManifest'materializations = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeManifest "cacheEntries" [RuntimeCacheEntry] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'cacheEntries
           (\ x__ y__ -> x__ {_RuntimeManifest'cacheEntries = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RuntimeManifest "vec'cacheEntries" (Data.Vector.Vector RuntimeCacheEntry) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'cacheEntries
           (\ x__ y__ -> x__ {_RuntimeManifest'cacheEntries = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RuntimeManifest "durableResultsPrefix" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RuntimeManifest'durableResultsPrefix
           (\ x__ y__ -> x__ {_RuntimeManifest'durableResultsPrefix = y__}))
        Prelude.id
instance Data.ProtoLens.Message RuntimeManifest where
  messageName _ = Data.Text.pack "infernix.manifest.RuntimeManifest"
  packedMessageDescriptor _
    = "\n\
      \\SIRuntimeManifest\DC2\US\n\
      \\vmanifest_id\CAN\SOH \SOH(\tR\n\
      \manifestId\DC2!\n\
      \\fruntime_mode\CAN\STX \SOH(\tR\vruntimeMode\DC2S\n\
      \\DLEmaterializations\CAN\ETX \ETX(\v2'.infernix.manifest.ModelMaterializationR\DLEmaterializations\DC2I\n\
      \\rcache_entries\CAN\EOT \ETX(\v2$.infernix.manifest.RuntimeCacheEntryR\fcacheEntries\DC24\n\
      \\SYNdurable_results_prefix\CAN\ENQ \SOH(\tR\DC4durableResultsPrefix"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        manifestId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "manifest_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"manifestId")) ::
              Data.ProtoLens.FieldDescriptor RuntimeManifest
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor RuntimeManifest
        materializations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "materializations"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ModelMaterialization)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"materializations")) ::
              Data.ProtoLens.FieldDescriptor RuntimeManifest
        cacheEntries__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_entries"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RuntimeCacheEntry)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"cacheEntries")) ::
              Data.ProtoLens.FieldDescriptor RuntimeManifest
        durableResultsPrefix__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "durable_results_prefix"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"durableResultsPrefix")) ::
              Data.ProtoLens.FieldDescriptor RuntimeManifest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, manifestId__field_descriptor),
           (Data.ProtoLens.Tag 2, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 3, materializations__field_descriptor),
           (Data.ProtoLens.Tag 4, cacheEntries__field_descriptor),
           (Data.ProtoLens.Tag 5, durableResultsPrefix__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RuntimeManifest'_unknownFields
        (\ x__ y__ -> x__ {_RuntimeManifest'_unknownFields = y__})
  defMessage
    = RuntimeManifest'_constructor
        {_RuntimeManifest'manifestId = Data.ProtoLens.fieldDefault,
         _RuntimeManifest'runtimeMode = Data.ProtoLens.fieldDefault,
         _RuntimeManifest'materializations = Data.Vector.Generic.empty,
         _RuntimeManifest'cacheEntries = Data.Vector.Generic.empty,
         _RuntimeManifest'durableResultsPrefix = Data.ProtoLens.fieldDefault,
         _RuntimeManifest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RuntimeManifest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld RuntimeCacheEntry
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ModelMaterialization
                -> Data.ProtoLens.Encoding.Bytes.Parser RuntimeManifest
        loop x mutable'cacheEntries mutable'materializations
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'cacheEntries <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                               (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                  mutable'cacheEntries)
                      frozen'materializations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'materializations)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'cacheEntries")
                              frozen'cacheEntries
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'materializations")
                                 frozen'materializations x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "manifest_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"manifestId") y x)
                                  mutable'cacheEntries mutable'materializations
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                                  mutable'cacheEntries mutable'materializations
                        26
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "materializations"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'materializations y)
                                loop x mutable'cacheEntries v
                        34
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "cache_entries"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'cacheEntries y)
                                loop x v mutable'materializations
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "durable_results_prefix"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"durableResultsPrefix") y x)
                                  mutable'cacheEntries mutable'materializations
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'cacheEntries mutable'materializations
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'cacheEntries <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        Data.ProtoLens.Encoding.Growing.new
              mutable'materializations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'cacheEntries
                mutable'materializations)
          "RuntimeManifest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"manifestId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"runtimeMode") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                      (\ _v
                         -> (Data.Monoid.<>)
                              (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                              ((Prelude..)
                                 (\ bs
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                            (Prelude.fromIntegral (Data.ByteString.length bs)))
                                         (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                 Data.ProtoLens.encodeMessage _v))
                      (Lens.Family2.view
                         (Data.ProtoLens.Field.field @"vec'materializations") _x))
                   ((Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                         (\ _v
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                 ((Prelude..)
                                    (\ bs
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                               (Prelude.fromIntegral (Data.ByteString.length bs)))
                                            (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                    Data.ProtoLens.encodeMessage _v))
                         (Lens.Family2.view
                            (Data.ProtoLens.Field.field @"vec'cacheEntries") _x))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"durableResultsPrefix") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData RuntimeManifest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RuntimeManifest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RuntimeManifest'manifestId x__)
                (Control.DeepSeq.deepseq
                   (_RuntimeManifest'runtimeMode x__)
                   (Control.DeepSeq.deepseq
                      (_RuntimeManifest'materializations x__)
                      (Control.DeepSeq.deepseq
                         (_RuntimeManifest'cacheEntries x__)
                         (Control.DeepSeq.deepseq
                            (_RuntimeManifest'durableResultsPrefix x__) ())))))
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \(infernix/manifest/runtime_manifest.proto\DC2\DC1infernix.manifest\"\227\SOH\n\
    \\DC4ModelMaterialization\DC2!\n\
    \\fruntime_mode\CAN\SOH \SOH(\tR\vruntimeMode\DC2\EM\n\
    \\bmodel_id\CAN\STX \SOH(\tR\amodelId\DC2'\n\
    \\SIselected_engine\CAN\ETX \SOH(\tR\SOselectedEngine\DC2,\n\
    \\DC2durable_source_uri\CAN\EOT \SOH(\tR\DLEdurableSourceUri\DC26\n\
    \\ETBmaterialized_cache_path\CAN\ENQ \SOH(\tR\NAKmaterializedCachePath\"\177\SOH\n\
    \\DC1RuntimeCacheEntry\DC2!\n\
    \\fruntime_mode\CAN\SOH \SOH(\tR\vruntimeMode\DC2\EM\n\
    \\bmodel_id\CAN\STX \SOH(\tR\amodelId\DC2\ESC\n\
    \\tcache_key\CAN\ETX \SOH(\tR\bcacheKey\DC2\GS\n\
    \\n\
    \cache_path\CAN\EOT \SOH(\tR\tcachePath\DC2\"\n\
    \\fmaterialized\CAN\ENQ \SOH(\bR\fmaterialized\"\171\STX\n\
    \\SIRuntimeManifest\DC2\US\n\
    \\vmanifest_id\CAN\SOH \SOH(\tR\n\
    \manifestId\DC2!\n\
    \\fruntime_mode\CAN\STX \SOH(\tR\vruntimeMode\DC2S\n\
    \\DLEmaterializations\CAN\ETX \ETX(\v2'.infernix.manifest.ModelMaterializationR\DLEmaterializations\DC2I\n\
    \\rcache_entries\CAN\EOT \ETX(\v2$.infernix.manifest.RuntimeCacheEntryR\fcacheEntries\DC24\n\
    \\SYNdurable_results_prefix\CAN\ENQ \SOH(\tR\DC4durableResultsPrefixJ\185\a\n\
    \\ACK\DC2\EOT\NUL\NUL\SUB\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\SUB\n\
    \\n\
    \\n\
    \\STX\EOT\NUL\DC2\EOT\EOT\NUL\n\
    \\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\EOT\b\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\ENQ\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\ENQ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\ENQ\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\ENQ\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\ACK\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\ACK\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\ACK\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\ACK\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\a\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\a\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\a\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\a\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\b\STX \n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\b\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\b\t\ESC\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\b\RS\US\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX\t\STX%\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX\t\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX\t\t \n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX\t#$\n\
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\f\NUL\DC2\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\f\b\EM\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\r\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\r\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\r\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\r\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX\SO\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX\SO\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX\SO\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX\SO\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETX\SI\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ENQ\DC2\ETX\SI\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETX\SI\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETX\SI\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ETX\DC2\ETX\DLE\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ENQ\DC2\ETX\DLE\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\SOH\DC2\ETX\DLE\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ETX\DC2\ETX\DLE\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\EOT\DC2\ETX\DC1\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ENQ\DC2\ETX\DC1\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\SOH\DC2\ETX\DC1\a\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ETX\DC2\ETX\DC1\SYN\ETB\n\
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT\DC4\NUL\SUB\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\DC4\b\ETB\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\NAK\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\NAK\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\NAK\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\NAK\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\SYN\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\SYN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\SYN\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\SYN\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\ETB\STX5\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\EOT\DC2\ETX\ETB\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ACK\DC2\ETX\ETB\v\US\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\ETB 0\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\ETB34\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ETX\DC2\ETX\CAN\STX/\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\EOT\DC2\ETX\CAN\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ACK\DC2\ETX\CAN\v\FS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\ETX\CAN\GS*\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\ETX\CAN-.\n\
    \\v\n\
    \\EOT\EOT\STX\STX\EOT\DC2\ETX\EM\STX$\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\ETX\EM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\ETX\EM\t\US\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\ETX\EM\"#b\ACKproto3"