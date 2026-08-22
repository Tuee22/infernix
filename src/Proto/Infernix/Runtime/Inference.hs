{- This file was auto-generated from infernix/runtime/inference.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Infernix.Runtime.Inference (
        CatalogEntry(), CeilingAcknowledgement(), EngineBinding(),
        ErrorResponse(), GeneratedCatalog(), HostAndDeviceClaim(),
        HostResidentClaim(), InferenceError(), InferenceError'Error(..),
        _InferenceError'ModelMemoryLimitExceeded,
        _InferenceError'ModelRequirementUnderivable,
        InferenceMemoryBudget(), InferenceMemoryBudget'Claim(..),
        _InferenceMemoryBudget'HostResident,
        _InferenceMemoryBudget'HostAndDevice, InferenceRequest(),
        InferenceResult(), ModelExecutionShape(),
        ModelMemoryLimitExceeded(), ModelRequirementUnderivable(),
        RequestField(), ResultPayload(), ResultPayload'Output(..),
        _ResultPayload'InlineOutput, _ResultPayload'ObjectRef,
        _ResultPayload'InferenceError, WorkerRequest(), WorkerResponse()
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
     
         * 'Proto.Infernix.Runtime.Inference_Fields.matrixRowId' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.modelId' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.displayName' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.family' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.description' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.artifactType' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.referenceModel' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.downloadUrl' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.selectedEngine' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.requestShape' @:: Lens' CatalogEntry [RequestField]@
         * 'Proto.Infernix.Runtime.Inference_Fields.vec'requestShape' @:: Lens' CatalogEntry (Data.Vector.Vector RequestField)@
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeMode' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeLane' @:: Lens' CatalogEntry Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.requiresGpu' @:: Lens' CatalogEntry Prelude.Bool@
         * 'Proto.Infernix.Runtime.Inference_Fields.notes' @:: Lens' CatalogEntry Data.Text.Text@ -}
data CatalogEntry
  = CatalogEntry'_constructor {_CatalogEntry'matrixRowId :: !Data.Text.Text,
                               _CatalogEntry'modelId :: !Data.Text.Text,
                               _CatalogEntry'displayName :: !Data.Text.Text,
                               _CatalogEntry'family :: !Data.Text.Text,
                               _CatalogEntry'description :: !Data.Text.Text,
                               _CatalogEntry'artifactType :: !Data.Text.Text,
                               _CatalogEntry'referenceModel :: !Data.Text.Text,
                               _CatalogEntry'downloadUrl :: !Data.Text.Text,
                               _CatalogEntry'selectedEngine :: !Data.Text.Text,
                               _CatalogEntry'requestShape :: !(Data.Vector.Vector RequestField),
                               _CatalogEntry'runtimeMode :: !Data.Text.Text,
                               _CatalogEntry'runtimeLane :: !Data.Text.Text,
                               _CatalogEntry'requiresGpu :: !Prelude.Bool,
                               _CatalogEntry'notes :: !Data.Text.Text,
                               _CatalogEntry'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CatalogEntry where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CatalogEntry "matrixRowId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'matrixRowId
           (\ x__ y__ -> x__ {_CatalogEntry'matrixRowId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "modelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'modelId
           (\ x__ y__ -> x__ {_CatalogEntry'modelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "displayName" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'displayName
           (\ x__ y__ -> x__ {_CatalogEntry'displayName = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "family" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'family
           (\ x__ y__ -> x__ {_CatalogEntry'family = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "description" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'description
           (\ x__ y__ -> x__ {_CatalogEntry'description = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "artifactType" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'artifactType
           (\ x__ y__ -> x__ {_CatalogEntry'artifactType = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "referenceModel" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'referenceModel
           (\ x__ y__ -> x__ {_CatalogEntry'referenceModel = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "downloadUrl" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'downloadUrl
           (\ x__ y__ -> x__ {_CatalogEntry'downloadUrl = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "selectedEngine" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'selectedEngine
           (\ x__ y__ -> x__ {_CatalogEntry'selectedEngine = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "requestShape" [RequestField] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'requestShape
           (\ x__ y__ -> x__ {_CatalogEntry'requestShape = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CatalogEntry "vec'requestShape" (Data.Vector.Vector RequestField) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'requestShape
           (\ x__ y__ -> x__ {_CatalogEntry'requestShape = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'runtimeMode
           (\ x__ y__ -> x__ {_CatalogEntry'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "runtimeLane" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'runtimeLane
           (\ x__ y__ -> x__ {_CatalogEntry'runtimeLane = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "requiresGpu" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'requiresGpu
           (\ x__ y__ -> x__ {_CatalogEntry'requiresGpu = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CatalogEntry "notes" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CatalogEntry'notes (\ x__ y__ -> x__ {_CatalogEntry'notes = y__}))
        Prelude.id
instance Data.ProtoLens.Message CatalogEntry where
  messageName _ = Data.Text.pack "infernix.runtime.CatalogEntry"
  packedMessageDescriptor _
    = "\n\
      \\fCatalogEntry\DC2\"\n\
      \\rmatrix_row_id\CAN\SOH \SOH(\tR\vmatrixRowId\DC2\EM\n\
      \\bmodel_id\CAN\STX \SOH(\tR\amodelId\DC2!\n\
      \\fdisplay_name\CAN\ETX \SOH(\tR\vdisplayName\DC2\SYN\n\
      \\ACKfamily\CAN\EOT \SOH(\tR\ACKfamily\DC2 \n\
      \\vdescription\CAN\ENQ \SOH(\tR\vdescription\DC2#\n\
      \\rartifact_type\CAN\ACK \SOH(\tR\fartifactType\DC2'\n\
      \\SIreference_model\CAN\a \SOH(\tR\SOreferenceModel\DC2!\n\
      \\fdownload_url\CAN\b \SOH(\tR\vdownloadUrl\DC2'\n\
      \\SIselected_engine\CAN\t \SOH(\tR\SOselectedEngine\DC2C\n\
      \\rrequest_shape\CAN\n\
      \ \ETX(\v2\RS.infernix.runtime.RequestFieldR\frequestShape\DC2!\n\
      \\fruntime_mode\CAN\v \SOH(\tR\vruntimeMode\DC2!\n\
      \\fruntime_lane\CAN\f \SOH(\tR\vruntimeLane\DC2!\n\
      \\frequires_gpu\CAN\r \SOH(\bR\vrequiresGpu\DC2\DC4\n\
      \\ENQnotes\CAN\SO \SOH(\tR\ENQnotes"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        matrixRowId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "matrix_row_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"matrixRowId")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        modelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"modelId")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        displayName__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "display_name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"displayName")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        family__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "family"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"family")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        description__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "description"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"description")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        artifactType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "artifact_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"artifactType")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        referenceModel__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reference_model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"referenceModel")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        downloadUrl__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "download_url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"downloadUrl")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        selectedEngine__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "selected_engine"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"selectedEngine")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        requestShape__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_shape"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RequestField)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"requestShape")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        runtimeLane__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_lane"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeLane")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        requiresGpu__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "requires_gpu"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requiresGpu")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
        notes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "notes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"notes")) ::
              Data.ProtoLens.FieldDescriptor CatalogEntry
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, matrixRowId__field_descriptor),
           (Data.ProtoLens.Tag 2, modelId__field_descriptor),
           (Data.ProtoLens.Tag 3, displayName__field_descriptor),
           (Data.ProtoLens.Tag 4, family__field_descriptor),
           (Data.ProtoLens.Tag 5, description__field_descriptor),
           (Data.ProtoLens.Tag 6, artifactType__field_descriptor),
           (Data.ProtoLens.Tag 7, referenceModel__field_descriptor),
           (Data.ProtoLens.Tag 8, downloadUrl__field_descriptor),
           (Data.ProtoLens.Tag 9, selectedEngine__field_descriptor),
           (Data.ProtoLens.Tag 10, requestShape__field_descriptor),
           (Data.ProtoLens.Tag 11, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 12, runtimeLane__field_descriptor),
           (Data.ProtoLens.Tag 13, requiresGpu__field_descriptor),
           (Data.ProtoLens.Tag 14, notes__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CatalogEntry'_unknownFields
        (\ x__ y__ -> x__ {_CatalogEntry'_unknownFields = y__})
  defMessage
    = CatalogEntry'_constructor
        {_CatalogEntry'matrixRowId = Data.ProtoLens.fieldDefault,
         _CatalogEntry'modelId = Data.ProtoLens.fieldDefault,
         _CatalogEntry'displayName = Data.ProtoLens.fieldDefault,
         _CatalogEntry'family = Data.ProtoLens.fieldDefault,
         _CatalogEntry'description = Data.ProtoLens.fieldDefault,
         _CatalogEntry'artifactType = Data.ProtoLens.fieldDefault,
         _CatalogEntry'referenceModel = Data.ProtoLens.fieldDefault,
         _CatalogEntry'downloadUrl = Data.ProtoLens.fieldDefault,
         _CatalogEntry'selectedEngine = Data.ProtoLens.fieldDefault,
         _CatalogEntry'requestShape = Data.Vector.Generic.empty,
         _CatalogEntry'runtimeMode = Data.ProtoLens.fieldDefault,
         _CatalogEntry'runtimeLane = Data.ProtoLens.fieldDefault,
         _CatalogEntry'requiresGpu = Data.ProtoLens.fieldDefault,
         _CatalogEntry'notes = Data.ProtoLens.fieldDefault,
         _CatalogEntry'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CatalogEntry
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld RequestField
             -> Data.ProtoLens.Encoding.Bytes.Parser CatalogEntry
        loop x mutable'requestShape
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'requestShape <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                               (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                  mutable'requestShape)
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
                              (Data.ProtoLens.Field.field @"vec'requestShape")
                              frozen'requestShape x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "matrix_row_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"matrixRowId") y x)
                                  mutable'requestShape
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"modelId") y x)
                                  mutable'requestShape
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "display_name"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"displayName") y x)
                                  mutable'requestShape
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "family"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"family") y x)
                                  mutable'requestShape
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "description"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"description") y x)
                                  mutable'requestShape
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "artifact_type"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"artifactType") y x)
                                  mutable'requestShape
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reference_model"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"referenceModel") y x)
                                  mutable'requestShape
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "download_url"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"downloadUrl") y x)
                                  mutable'requestShape
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "selected_engine"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"selectedEngine") y x)
                                  mutable'requestShape
                        82
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "request_shape"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'requestShape y)
                                loop x v
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                                  mutable'requestShape
                        98
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_lane"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeLane") y x)
                                  mutable'requestShape
                        104
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "requires_gpu"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"requiresGpu") y x)
                                  mutable'requestShape
                        114
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "notes"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"notes") y x)
                                  mutable'requestShape
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'requestShape
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'requestShape <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'requestShape)
          "CatalogEntry"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"matrixRowId") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"displayName") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"family") _x
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
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"description") _x
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
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view (Data.ProtoLens.Field.field @"artifactType") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                     ((Prelude..)
                                        (\ bs
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                   (Prelude.fromIntegral
                                                      (Data.ByteString.length bs)))
                                                (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                        Data.Text.Encoding.encodeUtf8 _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"referenceModel") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                        ((Prelude..)
                                           (\ bs
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                      (Prelude.fromIntegral
                                                         (Data.ByteString.length bs)))
                                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                           Data.Text.Encoding.encodeUtf8 _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"downloadUrl") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                           ((Prelude..)
                                              (\ bs
                                                 -> (Data.Monoid.<>)
                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                         (Prelude.fromIntegral
                                                            (Data.ByteString.length bs)))
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
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((Prelude..)
                                                 (\ bs
                                                    -> (Data.Monoid.<>)
                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                            (Prelude.fromIntegral
                                                               (Data.ByteString.length bs)))
                                                         (Data.ProtoLens.Encoding.Bytes.putBytes
                                                            bs))
                                                 Data.Text.Encoding.encodeUtf8 _v))
                                     ((Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                           (\ _v
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                   ((Prelude..)
                                                      (\ bs
                                                         -> (Data.Monoid.<>)
                                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                 (Prelude.fromIntegral
                                                                    (Data.ByteString.length bs)))
                                                              (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                 bs))
                                                      Data.ProtoLens.encodeMessage _v))
                                           (Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"vec'requestShape") _x))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"runtimeMode") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                                    ((Prelude..)
                                                       (\ bs
                                                          -> (Data.Monoid.<>)
                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                  (Prelude.fromIntegral
                                                                     (Data.ByteString.length bs)))
                                                               (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                  bs))
                                                       Data.Text.Encoding.encodeUtf8 _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field @"runtimeLane")
                                                       _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                                       ((Prelude..)
                                                          (\ bs
                                                             -> (Data.Monoid.<>)
                                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                     (Prelude.fromIntegral
                                                                        (Data.ByteString.length
                                                                           bs)))
                                                                  (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                     bs))
                                                          Data.Text.Encoding.encodeUtf8 _v))
                                              ((Data.Monoid.<>)
                                                 (let
                                                    _v
                                                      = Lens.Family2.view
                                                          (Data.ProtoLens.Field.field
                                                             @"requiresGpu")
                                                          _x
                                                  in
                                                    if (Prelude.==)
                                                         _v Data.ProtoLens.fieldDefault then
                                                        Data.Monoid.mempty
                                                    else
                                                        (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             104)
                                                          ((Prelude..)
                                                             Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             (\ b -> if b then 1 else 0) _v))
                                                 ((Data.Monoid.<>)
                                                    (let
                                                       _v
                                                         = Lens.Family2.view
                                                             (Data.ProtoLens.Field.field @"notes")
                                                             _x
                                                     in
                                                       if (Prelude.==)
                                                            _v Data.ProtoLens.fieldDefault then
                                                           Data.Monoid.mempty
                                                       else
                                                           (Data.Monoid.<>)
                                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                114)
                                                             ((Prelude..)
                                                                (\ bs
                                                                   -> (Data.Monoid.<>)
                                                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                           (Prelude.fromIntegral
                                                                              (Data.ByteString.length
                                                                                 bs)))
                                                                        (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                           bs))
                                                                Data.Text.Encoding.encodeUtf8 _v))
                                                    (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                       (Lens.Family2.view
                                                          Data.ProtoLens.unknownFields
                                                          _x)))))))))))))))
instance Control.DeepSeq.NFData CatalogEntry where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CatalogEntry'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CatalogEntry'matrixRowId x__)
                (Control.DeepSeq.deepseq
                   (_CatalogEntry'modelId x__)
                   (Control.DeepSeq.deepseq
                      (_CatalogEntry'displayName x__)
                      (Control.DeepSeq.deepseq
                         (_CatalogEntry'family x__)
                         (Control.DeepSeq.deepseq
                            (_CatalogEntry'description x__)
                            (Control.DeepSeq.deepseq
                               (_CatalogEntry'artifactType x__)
                               (Control.DeepSeq.deepseq
                                  (_CatalogEntry'referenceModel x__)
                                  (Control.DeepSeq.deepseq
                                     (_CatalogEntry'downloadUrl x__)
                                     (Control.DeepSeq.deepseq
                                        (_CatalogEntry'selectedEngine x__)
                                        (Control.DeepSeq.deepseq
                                           (_CatalogEntry'requestShape x__)
                                           (Control.DeepSeq.deepseq
                                              (_CatalogEntry'runtimeMode x__)
                                              (Control.DeepSeq.deepseq
                                                 (_CatalogEntry'runtimeLane x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_CatalogEntry'requiresGpu x__)
                                                    (Control.DeepSeq.deepseq
                                                       (_CatalogEntry'notes x__) ()))))))))))))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.softBytes' @:: Lens' CeilingAcknowledgement Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.hardBytes' @:: Lens' CeilingAcknowledgement Data.Int.Int64@ -}
data CeilingAcknowledgement
  = CeilingAcknowledgement'_constructor {_CeilingAcknowledgement'softBytes :: !Data.Int.Int64,
                                         _CeilingAcknowledgement'hardBytes :: !Data.Int.Int64,
                                         _CeilingAcknowledgement'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CeilingAcknowledgement where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CeilingAcknowledgement "softBytes" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CeilingAcknowledgement'softBytes
           (\ x__ y__ -> x__ {_CeilingAcknowledgement'softBytes = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CeilingAcknowledgement "hardBytes" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CeilingAcknowledgement'hardBytes
           (\ x__ y__ -> x__ {_CeilingAcknowledgement'hardBytes = y__}))
        Prelude.id
instance Data.ProtoLens.Message CeilingAcknowledgement where
  messageName _
    = Data.Text.pack "infernix.runtime.CeilingAcknowledgement"
  packedMessageDescriptor _
    = "\n\
      \\SYNCeilingAcknowledgement\DC2\GS\n\
      \\n\
      \soft_bytes\CAN\SOH \SOH(\ETXR\tsoftBytes\DC2\GS\n\
      \\n\
      \hard_bytes\CAN\STX \SOH(\ETXR\thardBytes"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        softBytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "soft_bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"softBytes")) ::
              Data.ProtoLens.FieldDescriptor CeilingAcknowledgement
        hardBytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "hard_bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"hardBytes")) ::
              Data.ProtoLens.FieldDescriptor CeilingAcknowledgement
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, softBytes__field_descriptor),
           (Data.ProtoLens.Tag 2, hardBytes__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CeilingAcknowledgement'_unknownFields
        (\ x__ y__ -> x__ {_CeilingAcknowledgement'_unknownFields = y__})
  defMessage
    = CeilingAcknowledgement'_constructor
        {_CeilingAcknowledgement'softBytes = Data.ProtoLens.fieldDefault,
         _CeilingAcknowledgement'hardBytes = Data.ProtoLens.fieldDefault,
         _CeilingAcknowledgement'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CeilingAcknowledgement
          -> Data.ProtoLens.Encoding.Bytes.Parser CeilingAcknowledgement
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
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "soft_bytes"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"softBytes") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "hard_bytes"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"hardBytes") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CeilingAcknowledgement"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"softBytes") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"hardBytes") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData CeilingAcknowledgement where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CeilingAcknowledgement'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CeilingAcknowledgement'softBytes x__)
                (Control.DeepSeq.deepseq
                   (_CeilingAcknowledgement'hardBytes x__) ()))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.engine' @:: Lens' EngineBinding Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.adapterId' @:: Lens' EngineBinding Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.adapterType' @:: Lens' EngineBinding Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.adapterLocator' @:: Lens' EngineBinding Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.pythonNative' @:: Lens' EngineBinding Prelude.Bool@ -}
data EngineBinding
  = EngineBinding'_constructor {_EngineBinding'engine :: !Data.Text.Text,
                                _EngineBinding'adapterId :: !Data.Text.Text,
                                _EngineBinding'adapterType :: !Data.Text.Text,
                                _EngineBinding'adapterLocator :: !Data.Text.Text,
                                _EngineBinding'pythonNative :: !Prelude.Bool,
                                _EngineBinding'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show EngineBinding where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField EngineBinding "engine" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EngineBinding'engine
           (\ x__ y__ -> x__ {_EngineBinding'engine = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EngineBinding "adapterId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EngineBinding'adapterId
           (\ x__ y__ -> x__ {_EngineBinding'adapterId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EngineBinding "adapterType" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EngineBinding'adapterType
           (\ x__ y__ -> x__ {_EngineBinding'adapterType = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EngineBinding "adapterLocator" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EngineBinding'adapterLocator
           (\ x__ y__ -> x__ {_EngineBinding'adapterLocator = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EngineBinding "pythonNative" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EngineBinding'pythonNative
           (\ x__ y__ -> x__ {_EngineBinding'pythonNative = y__}))
        Prelude.id
instance Data.ProtoLens.Message EngineBinding where
  messageName _ = Data.Text.pack "infernix.runtime.EngineBinding"
  packedMessageDescriptor _
    = "\n\
      \\rEngineBinding\DC2\SYN\n\
      \\ACKengine\CAN\SOH \SOH(\tR\ACKengine\DC2\GS\n\
      \\n\
      \adapter_id\CAN\STX \SOH(\tR\tadapterId\DC2!\n\
      \\fadapter_type\CAN\ETX \SOH(\tR\vadapterType\DC2'\n\
      \\SIadapter_locator\CAN\EOT \SOH(\tR\SOadapterLocator\DC2#\n\
      \\rpython_native\CAN\ENQ \SOH(\bR\fpythonNative"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        engine__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "engine"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"engine")) ::
              Data.ProtoLens.FieldDescriptor EngineBinding
        adapterId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "adapter_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"adapterId")) ::
              Data.ProtoLens.FieldDescriptor EngineBinding
        adapterType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "adapter_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"adapterType")) ::
              Data.ProtoLens.FieldDescriptor EngineBinding
        adapterLocator__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "adapter_locator"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"adapterLocator")) ::
              Data.ProtoLens.FieldDescriptor EngineBinding
        pythonNative__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "python_native"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"pythonNative")) ::
              Data.ProtoLens.FieldDescriptor EngineBinding
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, engine__field_descriptor),
           (Data.ProtoLens.Tag 2, adapterId__field_descriptor),
           (Data.ProtoLens.Tag 3, adapterType__field_descriptor),
           (Data.ProtoLens.Tag 4, adapterLocator__field_descriptor),
           (Data.ProtoLens.Tag 5, pythonNative__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _EngineBinding'_unknownFields
        (\ x__ y__ -> x__ {_EngineBinding'_unknownFields = y__})
  defMessage
    = EngineBinding'_constructor
        {_EngineBinding'engine = Data.ProtoLens.fieldDefault,
         _EngineBinding'adapterId = Data.ProtoLens.fieldDefault,
         _EngineBinding'adapterType = Data.ProtoLens.fieldDefault,
         _EngineBinding'adapterLocator = Data.ProtoLens.fieldDefault,
         _EngineBinding'pythonNative = Data.ProtoLens.fieldDefault,
         _EngineBinding'_unknownFields = []}
  parseMessage
    = let
        loop ::
          EngineBinding -> Data.ProtoLens.Encoding.Bytes.Parser EngineBinding
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
                                       "engine"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"engine") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "adapter_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"adapterId") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "adapter_type"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"adapterType") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "adapter_locator"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"adapterLocator") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "python_native"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"pythonNative") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "EngineBinding"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"engine") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"adapterId") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"adapterType") _x
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
                               (Data.ProtoLens.Field.field @"adapterLocator") _x
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
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"pythonNative") _x
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
instance Control.DeepSeq.NFData EngineBinding where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_EngineBinding'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_EngineBinding'engine x__)
                (Control.DeepSeq.deepseq
                   (_EngineBinding'adapterId x__)
                   (Control.DeepSeq.deepseq
                      (_EngineBinding'adapterType x__)
                      (Control.DeepSeq.deepseq
                         (_EngineBinding'adapterLocator x__)
                         (Control.DeepSeq.deepseq (_EngineBinding'pythonNative x__) ())))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.errorCode' @:: Lens' ErrorResponse Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.message' @:: Lens' ErrorResponse Data.Text.Text@ -}
data ErrorResponse
  = ErrorResponse'_constructor {_ErrorResponse'errorCode :: !Data.Text.Text,
                                _ErrorResponse'message :: !Data.Text.Text,
                                _ErrorResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ErrorResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ErrorResponse "errorCode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ErrorResponse'errorCode
           (\ x__ y__ -> x__ {_ErrorResponse'errorCode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ErrorResponse "message" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ErrorResponse'message
           (\ x__ y__ -> x__ {_ErrorResponse'message = y__}))
        Prelude.id
instance Data.ProtoLens.Message ErrorResponse where
  messageName _ = Data.Text.pack "infernix.runtime.ErrorResponse"
  packedMessageDescriptor _
    = "\n\
      \\rErrorResponse\DC2\GS\n\
      \\n\
      \error_code\CAN\SOH \SOH(\tR\terrorCode\DC2\CAN\n\
      \\amessage\CAN\STX \SOH(\tR\amessage"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        errorCode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_code"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"errorCode")) ::
              Data.ProtoLens.FieldDescriptor ErrorResponse
        message__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "message"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"message")) ::
              Data.ProtoLens.FieldDescriptor ErrorResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, errorCode__field_descriptor),
           (Data.ProtoLens.Tag 2, message__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ErrorResponse'_unknownFields
        (\ x__ y__ -> x__ {_ErrorResponse'_unknownFields = y__})
  defMessage
    = ErrorResponse'_constructor
        {_ErrorResponse'errorCode = Data.ProtoLens.fieldDefault,
         _ErrorResponse'message = Data.ProtoLens.fieldDefault,
         _ErrorResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ErrorResponse -> Data.ProtoLens.Encoding.Bytes.Parser ErrorResponse
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
                                       "error_code"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"errorCode") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "message"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"message") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ErrorResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"errorCode") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"message") _x
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
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ErrorResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ErrorResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ErrorResponse'errorCode x__)
                (Control.DeepSeq.deepseq (_ErrorResponse'message x__) ()))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeMode' @:: Lens' GeneratedCatalog Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.edgePort' @:: Lens' GeneratedCatalog Data.Int.Int32@
         * 'Proto.Infernix.Runtime.Inference_Fields.configMapName' @:: Lens' GeneratedCatalog Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.generatedPath' @:: Lens' GeneratedCatalog Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.mountedPath' @:: Lens' GeneratedCatalog Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.models' @:: Lens' GeneratedCatalog [CatalogEntry]@
         * 'Proto.Infernix.Runtime.Inference_Fields.vec'models' @:: Lens' GeneratedCatalog (Data.Vector.Vector CatalogEntry)@
         * 'Proto.Infernix.Runtime.Inference_Fields.demoUi' @:: Lens' GeneratedCatalog Prelude.Bool@
         * 'Proto.Infernix.Runtime.Inference_Fields.requestTopics' @:: Lens' GeneratedCatalog [Data.Text.Text]@
         * 'Proto.Infernix.Runtime.Inference_Fields.vec'requestTopics' @:: Lens' GeneratedCatalog (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Infernix.Runtime.Inference_Fields.resultTopic' @:: Lens' GeneratedCatalog Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.engines' @:: Lens' GeneratedCatalog [EngineBinding]@
         * 'Proto.Infernix.Runtime.Inference_Fields.vec'engines' @:: Lens' GeneratedCatalog (Data.Vector.Vector EngineBinding)@ -}
data GeneratedCatalog
  = GeneratedCatalog'_constructor {_GeneratedCatalog'runtimeMode :: !Data.Text.Text,
                                   _GeneratedCatalog'edgePort :: !Data.Int.Int32,
                                   _GeneratedCatalog'configMapName :: !Data.Text.Text,
                                   _GeneratedCatalog'generatedPath :: !Data.Text.Text,
                                   _GeneratedCatalog'mountedPath :: !Data.Text.Text,
                                   _GeneratedCatalog'models :: !(Data.Vector.Vector CatalogEntry),
                                   _GeneratedCatalog'demoUi :: !Prelude.Bool,
                                   _GeneratedCatalog'requestTopics :: !(Data.Vector.Vector Data.Text.Text),
                                   _GeneratedCatalog'resultTopic :: !Data.Text.Text,
                                   _GeneratedCatalog'engines :: !(Data.Vector.Vector EngineBinding),
                                   _GeneratedCatalog'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GeneratedCatalog where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GeneratedCatalog "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'runtimeMode
           (\ x__ y__ -> x__ {_GeneratedCatalog'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "edgePort" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'edgePort
           (\ x__ y__ -> x__ {_GeneratedCatalog'edgePort = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "configMapName" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'configMapName
           (\ x__ y__ -> x__ {_GeneratedCatalog'configMapName = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "generatedPath" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'generatedPath
           (\ x__ y__ -> x__ {_GeneratedCatalog'generatedPath = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "mountedPath" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'mountedPath
           (\ x__ y__ -> x__ {_GeneratedCatalog'mountedPath = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "models" [CatalogEntry] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'models
           (\ x__ y__ -> x__ {_GeneratedCatalog'models = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GeneratedCatalog "vec'models" (Data.Vector.Vector CatalogEntry) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'models
           (\ x__ y__ -> x__ {_GeneratedCatalog'models = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "demoUi" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'demoUi
           (\ x__ y__ -> x__ {_GeneratedCatalog'demoUi = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "requestTopics" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'requestTopics
           (\ x__ y__ -> x__ {_GeneratedCatalog'requestTopics = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GeneratedCatalog "vec'requestTopics" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'requestTopics
           (\ x__ y__ -> x__ {_GeneratedCatalog'requestTopics = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "resultTopic" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'resultTopic
           (\ x__ y__ -> x__ {_GeneratedCatalog'resultTopic = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedCatalog "engines" [EngineBinding] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'engines
           (\ x__ y__ -> x__ {_GeneratedCatalog'engines = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GeneratedCatalog "vec'engines" (Data.Vector.Vector EngineBinding) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedCatalog'engines
           (\ x__ y__ -> x__ {_GeneratedCatalog'engines = y__}))
        Prelude.id
instance Data.ProtoLens.Message GeneratedCatalog where
  messageName _ = Data.Text.pack "infernix.runtime.GeneratedCatalog"
  packedMessageDescriptor _
    = "\n\
      \\DLEGeneratedCatalog\DC2!\n\
      \\fruntime_mode\CAN\SOH \SOH(\tR\vruntimeMode\DC2\ESC\n\
      \\tedge_port\CAN\STX \SOH(\ENQR\bedgePort\DC2&\n\
      \\SIconfig_map_name\CAN\ETX \SOH(\tR\rconfigMapName\DC2%\n\
      \\SOgenerated_path\CAN\EOT \SOH(\tR\rgeneratedPath\DC2!\n\
      \\fmounted_path\CAN\ENQ \SOH(\tR\vmountedPath\DC26\n\
      \\ACKmodels\CAN\ACK \ETX(\v2\RS.infernix.runtime.CatalogEntryR\ACKmodels\DC2\ETB\n\
      \\ademo_ui\CAN\a \SOH(\bR\ACKdemoUi\DC2%\n\
      \\SOrequest_topics\CAN\b \ETX(\tR\rrequestTopics\DC2!\n\
      \\fresult_topic\CAN\t \SOH(\tR\vresultTopic\DC29\n\
      \\aengines\CAN\n\
      \ \ETX(\v2\US.infernix.runtime.EngineBindingR\aengines"
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
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        edgePort__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "edge_port"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"edgePort")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        configMapName__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "config_map_name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"configMapName")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        generatedPath__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "generated_path"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"generatedPath")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        mountedPath__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "mounted_path"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"mountedPath")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        models__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "models"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CatalogEntry)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"models")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        demoUi__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "demo_ui"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"demoUi")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        requestTopics__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_topics"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"requestTopics")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        resultTopic__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "result_topic"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"resultTopic")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
        engines__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "engines"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor EngineBinding)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"engines")) ::
              Data.ProtoLens.FieldDescriptor GeneratedCatalog
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 2, edgePort__field_descriptor),
           (Data.ProtoLens.Tag 3, configMapName__field_descriptor),
           (Data.ProtoLens.Tag 4, generatedPath__field_descriptor),
           (Data.ProtoLens.Tag 5, mountedPath__field_descriptor),
           (Data.ProtoLens.Tag 6, models__field_descriptor),
           (Data.ProtoLens.Tag 7, demoUi__field_descriptor),
           (Data.ProtoLens.Tag 8, requestTopics__field_descriptor),
           (Data.ProtoLens.Tag 9, resultTopic__field_descriptor),
           (Data.ProtoLens.Tag 10, engines__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GeneratedCatalog'_unknownFields
        (\ x__ y__ -> x__ {_GeneratedCatalog'_unknownFields = y__})
  defMessage
    = GeneratedCatalog'_constructor
        {_GeneratedCatalog'runtimeMode = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'edgePort = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'configMapName = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'generatedPath = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'mountedPath = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'models = Data.Vector.Generic.empty,
         _GeneratedCatalog'demoUi = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'requestTopics = Data.Vector.Generic.empty,
         _GeneratedCatalog'resultTopic = Data.ProtoLens.fieldDefault,
         _GeneratedCatalog'engines = Data.Vector.Generic.empty,
         _GeneratedCatalog'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GeneratedCatalog
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld EngineBinding
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld CatalogEntry
                -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                   -> Data.ProtoLens.Encoding.Bytes.Parser GeneratedCatalog
        loop x mutable'engines mutable'models mutable'requestTopics
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'engines <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'engines)
                      frozen'models <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'models)
                      frozen'requestTopics <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                   mutable'requestTopics)
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
                              (Data.ProtoLens.Field.field @"vec'engines") frozen'engines
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'models") frozen'models
                                 (Lens.Family2.set
                                    (Data.ProtoLens.Field.field @"vec'requestTopics")
                                    frozen'requestTopics x))))
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
                                  mutable'engines mutable'models mutable'requestTopics
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "edge_port"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"edgePort") y x)
                                  mutable'engines mutable'models mutable'requestTopics
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "config_map_name"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"configMapName") y x)
                                  mutable'engines mutable'models mutable'requestTopics
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "generated_path"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"generatedPath") y x)
                                  mutable'engines mutable'models mutable'requestTopics
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "mounted_path"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"mountedPath") y x)
                                  mutable'engines mutable'models mutable'requestTopics
                        50
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "models"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'models y)
                                loop x mutable'engines v mutable'requestTopics
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "demo_ui"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"demoUi") y x)
                                  mutable'engines mutable'models mutable'requestTopics
                        66
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "request_topics"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'requestTopics y)
                                loop x mutable'engines mutable'models v
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "result_topic"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"resultTopic") y x)
                                  mutable'engines mutable'models mutable'requestTopics
                        82
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "engines"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'engines y)
                                loop x v mutable'models mutable'requestTopics
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'engines mutable'models mutable'requestTopics
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'engines <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              mutable'models <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              mutable'requestTopics <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'engines mutable'models
                mutable'requestTopics)
          "GeneratedCatalog"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"edgePort") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view
                            (Data.ProtoLens.Field.field @"configMapName") _x
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
                               (Data.ProtoLens.Field.field @"generatedPath") _x
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
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"mountedPath") _x
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
                         ((Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                               (\ _v
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                       ((Prelude..)
                                          (\ bs
                                             -> (Data.Monoid.<>)
                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                     (Prelude.fromIntegral
                                                        (Data.ByteString.length bs)))
                                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                          Data.ProtoLens.encodeMessage _v))
                               (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'models") _x))
                            ((Data.Monoid.<>)
                               (let
                                  _v = Lens.Family2.view (Data.ProtoLens.Field.field @"demoUi") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (\ b -> if b then 1 else 0) _v))
                               ((Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                     (\ _v
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                             ((Prelude..)
                                                (\ bs
                                                   -> (Data.Monoid.<>)
                                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                           (Prelude.fromIntegral
                                                              (Data.ByteString.length bs)))
                                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                                Data.Text.Encoding.encodeUtf8 _v))
                                     (Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"vec'requestTopics") _x))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"resultTopic") _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((Prelude..)
                                                 (\ bs
                                                    -> (Data.Monoid.<>)
                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                            (Prelude.fromIntegral
                                                               (Data.ByteString.length bs)))
                                                         (Data.ProtoLens.Encoding.Bytes.putBytes
                                                            bs))
                                                 Data.Text.Encoding.encodeUtf8 _v))
                                     ((Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                           (\ _v
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                   ((Prelude..)
                                                      (\ bs
                                                         -> (Data.Monoid.<>)
                                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                 (Prelude.fromIntegral
                                                                    (Data.ByteString.length bs)))
                                                              (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                 bs))
                                                      Data.ProtoLens.encodeMessage _v))
                                           (Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"vec'engines") _x))
                                        (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                           (Lens.Family2.view
                                              Data.ProtoLens.unknownFields _x)))))))))))
instance Control.DeepSeq.NFData GeneratedCatalog where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GeneratedCatalog'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GeneratedCatalog'runtimeMode x__)
                (Control.DeepSeq.deepseq
                   (_GeneratedCatalog'edgePort x__)
                   (Control.DeepSeq.deepseq
                      (_GeneratedCatalog'configMapName x__)
                      (Control.DeepSeq.deepseq
                         (_GeneratedCatalog'generatedPath x__)
                         (Control.DeepSeq.deepseq
                            (_GeneratedCatalog'mountedPath x__)
                            (Control.DeepSeq.deepseq
                               (_GeneratedCatalog'models x__)
                               (Control.DeepSeq.deepseq
                                  (_GeneratedCatalog'demoUi x__)
                                  (Control.DeepSeq.deepseq
                                     (_GeneratedCatalog'requestTopics x__)
                                     (Control.DeepSeq.deepseq
                                        (_GeneratedCatalog'resultTopic x__)
                                        (Control.DeepSeq.deepseq
                                           (_GeneratedCatalog'engines x__) ()))))))))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.hostMib' @:: Lens' HostAndDeviceClaim Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.deviceMib' @:: Lens' HostAndDeviceClaim Data.Int.Int64@ -}
data HostAndDeviceClaim
  = HostAndDeviceClaim'_constructor {_HostAndDeviceClaim'hostMib :: !Data.Int.Int64,
                                     _HostAndDeviceClaim'deviceMib :: !Data.Int.Int64,
                                     _HostAndDeviceClaim'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show HostAndDeviceClaim where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField HostAndDeviceClaim "hostMib" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HostAndDeviceClaim'hostMib
           (\ x__ y__ -> x__ {_HostAndDeviceClaim'hostMib = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField HostAndDeviceClaim "deviceMib" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HostAndDeviceClaim'deviceMib
           (\ x__ y__ -> x__ {_HostAndDeviceClaim'deviceMib = y__}))
        Prelude.id
instance Data.ProtoLens.Message HostAndDeviceClaim where
  messageName _
    = Data.Text.pack "infernix.runtime.HostAndDeviceClaim"
  packedMessageDescriptor _
    = "\n\
      \\DC2HostAndDeviceClaim\DC2\EM\n\
      \\bhost_mib\CAN\SOH \SOH(\ETXR\ahostMib\DC2\GS\n\
      \\n\
      \device_mib\CAN\STX \SOH(\ETXR\tdeviceMib"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        hostMib__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "host_mib"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"hostMib")) ::
              Data.ProtoLens.FieldDescriptor HostAndDeviceClaim
        deviceMib__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "device_mib"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"deviceMib")) ::
              Data.ProtoLens.FieldDescriptor HostAndDeviceClaim
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, hostMib__field_descriptor),
           (Data.ProtoLens.Tag 2, deviceMib__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _HostAndDeviceClaim'_unknownFields
        (\ x__ y__ -> x__ {_HostAndDeviceClaim'_unknownFields = y__})
  defMessage
    = HostAndDeviceClaim'_constructor
        {_HostAndDeviceClaim'hostMib = Data.ProtoLens.fieldDefault,
         _HostAndDeviceClaim'deviceMib = Data.ProtoLens.fieldDefault,
         _HostAndDeviceClaim'_unknownFields = []}
  parseMessage
    = let
        loop ::
          HostAndDeviceClaim
          -> Data.ProtoLens.Encoding.Bytes.Parser HostAndDeviceClaim
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
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "host_mib"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"hostMib") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "device_mib"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"deviceMib") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "HostAndDeviceClaim"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"hostMib") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"deviceMib") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData HostAndDeviceClaim where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_HostAndDeviceClaim'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_HostAndDeviceClaim'hostMib x__)
                (Control.DeepSeq.deepseq (_HostAndDeviceClaim'deviceMib x__) ()))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.hostMib' @:: Lens' HostResidentClaim Data.Int.Int64@ -}
data HostResidentClaim
  = HostResidentClaim'_constructor {_HostResidentClaim'hostMib :: !Data.Int.Int64,
                                    _HostResidentClaim'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show HostResidentClaim where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField HostResidentClaim "hostMib" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HostResidentClaim'hostMib
           (\ x__ y__ -> x__ {_HostResidentClaim'hostMib = y__}))
        Prelude.id
instance Data.ProtoLens.Message HostResidentClaim where
  messageName _ = Data.Text.pack "infernix.runtime.HostResidentClaim"
  packedMessageDescriptor _
    = "\n\
      \\DC1HostResidentClaim\DC2\EM\n\
      \\bhost_mib\CAN\SOH \SOH(\ETXR\ahostMib"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        hostMib__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "host_mib"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"hostMib")) ::
              Data.ProtoLens.FieldDescriptor HostResidentClaim
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, hostMib__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _HostResidentClaim'_unknownFields
        (\ x__ y__ -> x__ {_HostResidentClaim'_unknownFields = y__})
  defMessage
    = HostResidentClaim'_constructor
        {_HostResidentClaim'hostMib = Data.ProtoLens.fieldDefault,
         _HostResidentClaim'_unknownFields = []}
  parseMessage
    = let
        loop ::
          HostResidentClaim
          -> Data.ProtoLens.Encoding.Bytes.Parser HostResidentClaim
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
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "host_mib"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"hostMib") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "HostResidentClaim"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"hostMib") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData HostResidentClaim where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_HostResidentClaim'_unknownFields x__)
             (Control.DeepSeq.deepseq (_HostResidentClaim'hostMib x__) ())
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'error' @:: Lens' InferenceError (Prelude.Maybe InferenceError'Error)@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'modelMemoryLimitExceeded' @:: Lens' InferenceError (Prelude.Maybe ModelMemoryLimitExceeded)@
         * 'Proto.Infernix.Runtime.Inference_Fields.modelMemoryLimitExceeded' @:: Lens' InferenceError ModelMemoryLimitExceeded@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'modelRequirementUnderivable' @:: Lens' InferenceError (Prelude.Maybe ModelRequirementUnderivable)@
         * 'Proto.Infernix.Runtime.Inference_Fields.modelRequirementUnderivable' @:: Lens' InferenceError ModelRequirementUnderivable@ -}
data InferenceError
  = InferenceError'_constructor {_InferenceError'error :: !(Prelude.Maybe InferenceError'Error),
                                 _InferenceError'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InferenceError where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data InferenceError'Error
  = InferenceError'ModelMemoryLimitExceeded !ModelMemoryLimitExceeded |
    InferenceError'ModelRequirementUnderivable !ModelRequirementUnderivable
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField InferenceError "maybe'error" (Prelude.Maybe InferenceError'Error) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceError'error
           (\ x__ y__ -> x__ {_InferenceError'error = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceError "maybe'modelMemoryLimitExceeded" (Prelude.Maybe ModelMemoryLimitExceeded) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceError'error
           (\ x__ y__ -> x__ {_InferenceError'error = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InferenceError'ModelMemoryLimitExceeded x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__
              -> Prelude.fmap InferenceError'ModelMemoryLimitExceeded y__))
instance Data.ProtoLens.Field.HasField InferenceError "modelMemoryLimitExceeded" ModelMemoryLimitExceeded where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceError'error
           (\ x__ y__ -> x__ {_InferenceError'error = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InferenceError'ModelMemoryLimitExceeded x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__
                 -> Prelude.fmap InferenceError'ModelMemoryLimitExceeded y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField InferenceError "maybe'modelRequirementUnderivable" (Prelude.Maybe ModelRequirementUnderivable) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceError'error
           (\ x__ y__ -> x__ {_InferenceError'error = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InferenceError'ModelRequirementUnderivable x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__
              -> Prelude.fmap InferenceError'ModelRequirementUnderivable y__))
instance Data.ProtoLens.Field.HasField InferenceError "modelRequirementUnderivable" ModelRequirementUnderivable where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceError'error
           (\ x__ y__ -> x__ {_InferenceError'error = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InferenceError'ModelRequirementUnderivable x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__
                 -> Prelude.fmap InferenceError'ModelRequirementUnderivable y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message InferenceError where
  messageName _ = Data.Text.pack "infernix.runtime.InferenceError"
  packedMessageDescriptor _
    = "\n\
      \\SOInferenceError\DC2k\n\
      \\ESCmodel_memory_limit_exceeded\CAN\SOH \SOH(\v2*.infernix.runtime.ModelMemoryLimitExceededH\NULR\CANmodelMemoryLimitExceeded\DC2s\n\
      \\GSmodel_requirement_underivable\CAN\STX \SOH(\v2-.infernix.runtime.ModelRequirementUnderivableH\NULR\ESCmodelRequirementUnderivableB\a\n\
      \\ENQerror"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        modelMemoryLimitExceeded__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_memory_limit_exceeded"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ModelMemoryLimitExceeded)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'modelMemoryLimitExceeded")) ::
              Data.ProtoLens.FieldDescriptor InferenceError
        modelRequirementUnderivable__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_requirement_underivable"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ModelRequirementUnderivable)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field
                    @"maybe'modelRequirementUnderivable")) ::
              Data.ProtoLens.FieldDescriptor InferenceError
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, 
            modelMemoryLimitExceeded__field_descriptor),
           (Data.ProtoLens.Tag 2, 
            modelRequirementUnderivable__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InferenceError'_unknownFields
        (\ x__ y__ -> x__ {_InferenceError'_unknownFields = y__})
  defMessage
    = InferenceError'_constructor
        {_InferenceError'error = Prelude.Nothing,
         _InferenceError'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InferenceError
          -> Data.ProtoLens.Encoding.Bytes.Parser InferenceError
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
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "model_memory_limit_exceeded"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"modelMemoryLimitExceeded") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "model_requirement_underivable"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"modelRequirementUnderivable") y
                                     x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "InferenceError"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'error") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (InferenceError'ModelMemoryLimitExceeded v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (InferenceError'ModelRequirementUnderivable v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData InferenceError where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InferenceError'_unknownFields x__)
             (Control.DeepSeq.deepseq (_InferenceError'error x__) ())
instance Control.DeepSeq.NFData InferenceError'Error where
  rnf (InferenceError'ModelMemoryLimitExceeded x__)
    = Control.DeepSeq.rnf x__
  rnf (InferenceError'ModelRequirementUnderivable x__)
    = Control.DeepSeq.rnf x__
_InferenceError'ModelMemoryLimitExceeded ::
  Data.ProtoLens.Prism.Prism' InferenceError'Error ModelMemoryLimitExceeded
_InferenceError'ModelMemoryLimitExceeded
  = Data.ProtoLens.Prism.prism'
      InferenceError'ModelMemoryLimitExceeded
      (\ p__
         -> case p__ of
              (InferenceError'ModelMemoryLimitExceeded p__val)
                -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_InferenceError'ModelRequirementUnderivable ::
  Data.ProtoLens.Prism.Prism' InferenceError'Error ModelRequirementUnderivable
_InferenceError'ModelRequirementUnderivable
  = Data.ProtoLens.Prism.prism'
      InferenceError'ModelRequirementUnderivable
      (\ p__
         -> case p__ of
              (InferenceError'ModelRequirementUnderivable p__val)
                -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'claim' @:: Lens' InferenceMemoryBudget (Prelude.Maybe InferenceMemoryBudget'Claim)@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'hostResident' @:: Lens' InferenceMemoryBudget (Prelude.Maybe HostResidentClaim)@
         * 'Proto.Infernix.Runtime.Inference_Fields.hostResident' @:: Lens' InferenceMemoryBudget HostResidentClaim@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'hostAndDevice' @:: Lens' InferenceMemoryBudget (Prelude.Maybe HostAndDeviceClaim)@
         * 'Proto.Infernix.Runtime.Inference_Fields.hostAndDevice' @:: Lens' InferenceMemoryBudget HostAndDeviceClaim@ -}
data InferenceMemoryBudget
  = InferenceMemoryBudget'_constructor {_InferenceMemoryBudget'claim :: !(Prelude.Maybe InferenceMemoryBudget'Claim),
                                        _InferenceMemoryBudget'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InferenceMemoryBudget where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data InferenceMemoryBudget'Claim
  = InferenceMemoryBudget'HostResident !HostResidentClaim |
    InferenceMemoryBudget'HostAndDevice !HostAndDeviceClaim
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField InferenceMemoryBudget "maybe'claim" (Prelude.Maybe InferenceMemoryBudget'Claim) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceMemoryBudget'claim
           (\ x__ y__ -> x__ {_InferenceMemoryBudget'claim = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceMemoryBudget "maybe'hostResident" (Prelude.Maybe HostResidentClaim) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceMemoryBudget'claim
           (\ x__ y__ -> x__ {_InferenceMemoryBudget'claim = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InferenceMemoryBudget'HostResident x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap InferenceMemoryBudget'HostResident y__))
instance Data.ProtoLens.Field.HasField InferenceMemoryBudget "hostResident" HostResidentClaim where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceMemoryBudget'claim
           (\ x__ y__ -> x__ {_InferenceMemoryBudget'claim = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InferenceMemoryBudget'HostResident x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap InferenceMemoryBudget'HostResident y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField InferenceMemoryBudget "maybe'hostAndDevice" (Prelude.Maybe HostAndDeviceClaim) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceMemoryBudget'claim
           (\ x__ y__ -> x__ {_InferenceMemoryBudget'claim = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InferenceMemoryBudget'HostAndDevice x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap InferenceMemoryBudget'HostAndDevice y__))
instance Data.ProtoLens.Field.HasField InferenceMemoryBudget "hostAndDevice" HostAndDeviceClaim where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceMemoryBudget'claim
           (\ x__ y__ -> x__ {_InferenceMemoryBudget'claim = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InferenceMemoryBudget'HostAndDevice x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap InferenceMemoryBudget'HostAndDevice y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message InferenceMemoryBudget where
  messageName _
    = Data.Text.pack "infernix.runtime.InferenceMemoryBudget"
  packedMessageDescriptor _
    = "\n\
      \\NAKInferenceMemoryBudget\DC2J\n\
      \\rhost_resident\CAN\SOH \SOH(\v2#.infernix.runtime.HostResidentClaimH\NULR\fhostResident\DC2N\n\
      \\SIhost_and_device\CAN\STX \SOH(\v2$.infernix.runtime.HostAndDeviceClaimH\NULR\rhostAndDeviceB\a\n\
      \\ENQclaim"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        hostResident__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "host_resident"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor HostResidentClaim)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'hostResident")) ::
              Data.ProtoLens.FieldDescriptor InferenceMemoryBudget
        hostAndDevice__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "host_and_device"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor HostAndDeviceClaim)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'hostAndDevice")) ::
              Data.ProtoLens.FieldDescriptor InferenceMemoryBudget
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, hostResident__field_descriptor),
           (Data.ProtoLens.Tag 2, hostAndDevice__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InferenceMemoryBudget'_unknownFields
        (\ x__ y__ -> x__ {_InferenceMemoryBudget'_unknownFields = y__})
  defMessage
    = InferenceMemoryBudget'_constructor
        {_InferenceMemoryBudget'claim = Prelude.Nothing,
         _InferenceMemoryBudget'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InferenceMemoryBudget
          -> Data.ProtoLens.Encoding.Bytes.Parser InferenceMemoryBudget
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
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "host_resident"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"hostResident") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "host_and_device"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"hostAndDevice") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "InferenceMemoryBudget"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'claim") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (InferenceMemoryBudget'HostResident v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (InferenceMemoryBudget'HostAndDevice v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData InferenceMemoryBudget where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InferenceMemoryBudget'_unknownFields x__)
             (Control.DeepSeq.deepseq (_InferenceMemoryBudget'claim x__) ())
instance Control.DeepSeq.NFData InferenceMemoryBudget'Claim where
  rnf (InferenceMemoryBudget'HostResident x__)
    = Control.DeepSeq.rnf x__
  rnf (InferenceMemoryBudget'HostAndDevice x__)
    = Control.DeepSeq.rnf x__
_InferenceMemoryBudget'HostResident ::
  Data.ProtoLens.Prism.Prism' InferenceMemoryBudget'Claim HostResidentClaim
_InferenceMemoryBudget'HostResident
  = Data.ProtoLens.Prism.prism'
      InferenceMemoryBudget'HostResident
      (\ p__
         -> case p__ of
              (InferenceMemoryBudget'HostResident p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_InferenceMemoryBudget'HostAndDevice ::
  Data.ProtoLens.Prism.Prism' InferenceMemoryBudget'Claim HostAndDeviceClaim
_InferenceMemoryBudget'HostAndDevice
  = Data.ProtoLens.Prism.prism'
      InferenceMemoryBudget'HostAndDevice
      (\ p__
         -> case p__ of
              (InferenceMemoryBudget'HostAndDevice p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.requestId' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.requestModelId' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.inputText' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeMode' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.userId' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.contextId' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.userPromptMessageId' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.clientIdempotencyKey' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.conversationLogOffset' @:: Lens' InferenceRequest Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.prefixHash' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.causalRef' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.inputObjectRef' @:: Lens' InferenceRequest Data.Text.Text@ -}
data InferenceRequest
  = InferenceRequest'_constructor {_InferenceRequest'requestId :: !Data.Text.Text,
                                   _InferenceRequest'requestModelId :: !Data.Text.Text,
                                   _InferenceRequest'inputText :: !Data.Text.Text,
                                   _InferenceRequest'runtimeMode :: !Data.Text.Text,
                                   _InferenceRequest'userId :: !Data.Text.Text,
                                   _InferenceRequest'contextId :: !Data.Text.Text,
                                   _InferenceRequest'userPromptMessageId :: !Data.Text.Text,
                                   _InferenceRequest'clientIdempotencyKey :: !Data.Text.Text,
                                   _InferenceRequest'conversationLogOffset :: !Data.Int.Int64,
                                   _InferenceRequest'prefixHash :: !Data.Text.Text,
                                   _InferenceRequest'causalRef :: !Data.Text.Text,
                                   _InferenceRequest'inputObjectRef :: !Data.Text.Text,
                                   _InferenceRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InferenceRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField InferenceRequest "requestId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'requestId
           (\ x__ y__ -> x__ {_InferenceRequest'requestId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "requestModelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'requestModelId
           (\ x__ y__ -> x__ {_InferenceRequest'requestModelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "inputText" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'inputText
           (\ x__ y__ -> x__ {_InferenceRequest'inputText = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'runtimeMode
           (\ x__ y__ -> x__ {_InferenceRequest'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "userId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'userId
           (\ x__ y__ -> x__ {_InferenceRequest'userId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "contextId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'contextId
           (\ x__ y__ -> x__ {_InferenceRequest'contextId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "userPromptMessageId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'userPromptMessageId
           (\ x__ y__ -> x__ {_InferenceRequest'userPromptMessageId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "clientIdempotencyKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'clientIdempotencyKey
           (\ x__ y__ -> x__ {_InferenceRequest'clientIdempotencyKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "conversationLogOffset" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'conversationLogOffset
           (\ x__ y__ -> x__ {_InferenceRequest'conversationLogOffset = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "prefixHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'prefixHash
           (\ x__ y__ -> x__ {_InferenceRequest'prefixHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "causalRef" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'causalRef
           (\ x__ y__ -> x__ {_InferenceRequest'causalRef = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "inputObjectRef" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'inputObjectRef
           (\ x__ y__ -> x__ {_InferenceRequest'inputObjectRef = y__}))
        Prelude.id
instance Data.ProtoLens.Message InferenceRequest where
  messageName _ = Data.Text.pack "infernix.runtime.InferenceRequest"
  packedMessageDescriptor _
    = "\n\
      \\DLEInferenceRequest\DC2\GS\n\
      \\n\
      \request_id\CAN\SOH \SOH(\tR\trequestId\DC2(\n\
      \\DLErequest_model_id\CAN\STX \SOH(\tR\SOrequestModelId\DC2\GS\n\
      \\n\
      \input_text\CAN\ETX \SOH(\tR\tinputText\DC2!\n\
      \\fruntime_mode\CAN\EOT \SOH(\tR\vruntimeMode\DC2\ETB\n\
      \\auser_id\CAN\ENQ \SOH(\tR\ACKuserId\DC2\GS\n\
      \\n\
      \context_id\CAN\ACK \SOH(\tR\tcontextId\DC23\n\
      \\SYNuser_prompt_message_id\CAN\a \SOH(\tR\DC3userPromptMessageId\DC24\n\
      \\SYNclient_idempotency_key\CAN\b \SOH(\tR\DC4clientIdempotencyKey\DC26\n\
      \\ETBconversation_log_offset\CAN\t \SOH(\ETXR\NAKconversationLogOffset\DC2\US\n\
      \\vprefix_hash\CAN\n\
      \ \SOH(\tR\n\
      \prefixHash\DC2\GS\n\
      \\n\
      \causal_ref\CAN\v \SOH(\tR\tcausalRef\DC2(\n\
      \\DLEinput_object_ref\CAN\f \SOH(\tR\SOinputObjectRef"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        requestId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requestId")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        requestModelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requestModelId")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        inputText__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "input_text"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"inputText")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        userId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"userId")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        contextId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "context_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"contextId")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        userPromptMessageId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user_prompt_message_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"userPromptMessageId")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        clientIdempotencyKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "client_idempotency_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"clientIdempotencyKey")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        conversationLogOffset__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "conversation_log_offset"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"conversationLogOffset")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        prefixHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prefix_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"prefixHash")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        causalRef__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "causal_ref"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"causalRef")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        inputObjectRef__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "input_object_ref"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"inputObjectRef")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, requestId__field_descriptor),
           (Data.ProtoLens.Tag 2, requestModelId__field_descriptor),
           (Data.ProtoLens.Tag 3, inputText__field_descriptor),
           (Data.ProtoLens.Tag 4, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 5, userId__field_descriptor),
           (Data.ProtoLens.Tag 6, contextId__field_descriptor),
           (Data.ProtoLens.Tag 7, userPromptMessageId__field_descriptor),
           (Data.ProtoLens.Tag 8, clientIdempotencyKey__field_descriptor),
           (Data.ProtoLens.Tag 9, conversationLogOffset__field_descriptor),
           (Data.ProtoLens.Tag 10, prefixHash__field_descriptor),
           (Data.ProtoLens.Tag 11, causalRef__field_descriptor),
           (Data.ProtoLens.Tag 12, inputObjectRef__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InferenceRequest'_unknownFields
        (\ x__ y__ -> x__ {_InferenceRequest'_unknownFields = y__})
  defMessage
    = InferenceRequest'_constructor
        {_InferenceRequest'requestId = Data.ProtoLens.fieldDefault,
         _InferenceRequest'requestModelId = Data.ProtoLens.fieldDefault,
         _InferenceRequest'inputText = Data.ProtoLens.fieldDefault,
         _InferenceRequest'runtimeMode = Data.ProtoLens.fieldDefault,
         _InferenceRequest'userId = Data.ProtoLens.fieldDefault,
         _InferenceRequest'contextId = Data.ProtoLens.fieldDefault,
         _InferenceRequest'userPromptMessageId = Data.ProtoLens.fieldDefault,
         _InferenceRequest'clientIdempotencyKey = Data.ProtoLens.fieldDefault,
         _InferenceRequest'conversationLogOffset = Data.ProtoLens.fieldDefault,
         _InferenceRequest'prefixHash = Data.ProtoLens.fieldDefault,
         _InferenceRequest'causalRef = Data.ProtoLens.fieldDefault,
         _InferenceRequest'inputObjectRef = Data.ProtoLens.fieldDefault,
         _InferenceRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InferenceRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser InferenceRequest
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
                                       "request_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"requestId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "request_model_id"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"requestModelId") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "input_text"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"inputText") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"userId") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "context_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"contextId") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user_prompt_message_id"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"userPromptMessageId") y x)
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "client_idempotency_key"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"clientIdempotencyKey") y x)
                        72
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "conversation_log_offset"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"conversationLogOffset") y x)
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "prefix_hash"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"prefixHash") y x)
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "causal_ref"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"causalRef") y x)
                        98
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "input_object_ref"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"inputObjectRef") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "InferenceRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"requestId") _x
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
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"requestModelId") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"inputText") _x
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
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"runtimeMode") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"userId") _x
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
                         ((Data.Monoid.<>)
                            (let
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"contextId") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                     ((Prelude..)
                                        (\ bs
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                   (Prelude.fromIntegral
                                                      (Data.ByteString.length bs)))
                                                (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                        Data.Text.Encoding.encodeUtf8 _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"userPromptMessageId") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                        ((Prelude..)
                                           (\ bs
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                      (Prelude.fromIntegral
                                                         (Data.ByteString.length bs)))
                                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                           Data.Text.Encoding.encodeUtf8 _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"clientIdempotencyKey") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                           ((Prelude..)
                                              (\ bs
                                                 -> (Data.Monoid.<>)
                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                         (Prelude.fromIntegral
                                                            (Data.ByteString.length bs)))
                                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                              Data.Text.Encoding.encodeUtf8 _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"conversationLogOffset")
                                              _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 72)
                                              ((Prelude..)
                                                 Data.ProtoLens.Encoding.Bytes.putVarInt
                                                 Prelude.fromIntegral _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"prefixHash") _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                 ((Prelude..)
                                                    (\ bs
                                                       -> (Data.Monoid.<>)
                                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                               (Prelude.fromIntegral
                                                                  (Data.ByteString.length bs)))
                                                            (Data.ProtoLens.Encoding.Bytes.putBytes
                                                               bs))
                                                    Data.Text.Encoding.encodeUtf8 _v))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"causalRef") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                                    ((Prelude..)
                                                       (\ bs
                                                          -> (Data.Monoid.<>)
                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                  (Prelude.fromIntegral
                                                                     (Data.ByteString.length bs)))
                                                               (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                  bs))
                                                       Data.Text.Encoding.encodeUtf8 _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field
                                                          @"inputObjectRef")
                                                       _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                                       ((Prelude..)
                                                          (\ bs
                                                             -> (Data.Monoid.<>)
                                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                     (Prelude.fromIntegral
                                                                        (Data.ByteString.length
                                                                           bs)))
                                                                  (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                     bs))
                                                          Data.Text.Encoding.encodeUtf8 _v))
                                              (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                 (Lens.Family2.view
                                                    Data.ProtoLens.unknownFields _x)))))))))))))
instance Control.DeepSeq.NFData InferenceRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InferenceRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_InferenceRequest'requestId x__)
                (Control.DeepSeq.deepseq
                   (_InferenceRequest'requestModelId x__)
                   (Control.DeepSeq.deepseq
                      (_InferenceRequest'inputText x__)
                      (Control.DeepSeq.deepseq
                         (_InferenceRequest'runtimeMode x__)
                         (Control.DeepSeq.deepseq
                            (_InferenceRequest'userId x__)
                            (Control.DeepSeq.deepseq
                               (_InferenceRequest'contextId x__)
                               (Control.DeepSeq.deepseq
                                  (_InferenceRequest'userPromptMessageId x__)
                                  (Control.DeepSeq.deepseq
                                     (_InferenceRequest'clientIdempotencyKey x__)
                                     (Control.DeepSeq.deepseq
                                        (_InferenceRequest'conversationLogOffset x__)
                                        (Control.DeepSeq.deepseq
                                           (_InferenceRequest'prefixHash x__)
                                           (Control.DeepSeq.deepseq
                                              (_InferenceRequest'causalRef x__)
                                              (Control.DeepSeq.deepseq
                                                 (_InferenceRequest'inputObjectRef x__)
                                                 ()))))))))))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.requestId' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.resultModelId' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.matrixRowId' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeMode' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.selectedEngine' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.status' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.payload' @:: Lens' InferenceResult ResultPayload@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'payload' @:: Lens' InferenceResult (Prelude.Maybe ResultPayload)@
         * 'Proto.Infernix.Runtime.Inference_Fields.createdAt' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.causalRef' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.userId' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.contextId' @:: Lens' InferenceResult Data.Text.Text@ -}
data InferenceResult
  = InferenceResult'_constructor {_InferenceResult'requestId :: !Data.Text.Text,
                                  _InferenceResult'resultModelId :: !Data.Text.Text,
                                  _InferenceResult'matrixRowId :: !Data.Text.Text,
                                  _InferenceResult'runtimeMode :: !Data.Text.Text,
                                  _InferenceResult'selectedEngine :: !Data.Text.Text,
                                  _InferenceResult'status :: !Data.Text.Text,
                                  _InferenceResult'payload :: !(Prelude.Maybe ResultPayload),
                                  _InferenceResult'createdAt :: !Data.Text.Text,
                                  _InferenceResult'causalRef :: !Data.Text.Text,
                                  _InferenceResult'userId :: !Data.Text.Text,
                                  _InferenceResult'contextId :: !Data.Text.Text,
                                  _InferenceResult'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InferenceResult where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField InferenceResult "requestId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'requestId
           (\ x__ y__ -> x__ {_InferenceResult'requestId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "resultModelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'resultModelId
           (\ x__ y__ -> x__ {_InferenceResult'resultModelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "matrixRowId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'matrixRowId
           (\ x__ y__ -> x__ {_InferenceResult'matrixRowId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'runtimeMode
           (\ x__ y__ -> x__ {_InferenceResult'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "selectedEngine" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'selectedEngine
           (\ x__ y__ -> x__ {_InferenceResult'selectedEngine = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "status" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'status
           (\ x__ y__ -> x__ {_InferenceResult'status = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "payload" ResultPayload where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'payload
           (\ x__ y__ -> x__ {_InferenceResult'payload = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField InferenceResult "maybe'payload" (Prelude.Maybe ResultPayload) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'payload
           (\ x__ y__ -> x__ {_InferenceResult'payload = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "createdAt" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'createdAt
           (\ x__ y__ -> x__ {_InferenceResult'createdAt = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "causalRef" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'causalRef
           (\ x__ y__ -> x__ {_InferenceResult'causalRef = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "userId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'userId
           (\ x__ y__ -> x__ {_InferenceResult'userId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "contextId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'contextId
           (\ x__ y__ -> x__ {_InferenceResult'contextId = y__}))
        Prelude.id
instance Data.ProtoLens.Message InferenceResult where
  messageName _ = Data.Text.pack "infernix.runtime.InferenceResult"
  packedMessageDescriptor _
    = "\n\
      \\SIInferenceResult\DC2\GS\n\
      \\n\
      \request_id\CAN\SOH \SOH(\tR\trequestId\DC2&\n\
      \\SIresult_model_id\CAN\STX \SOH(\tR\rresultModelId\DC2\"\n\
      \\rmatrix_row_id\CAN\ETX \SOH(\tR\vmatrixRowId\DC2!\n\
      \\fruntime_mode\CAN\EOT \SOH(\tR\vruntimeMode\DC2'\n\
      \\SIselected_engine\CAN\ENQ \SOH(\tR\SOselectedEngine\DC2\SYN\n\
      \\ACKstatus\CAN\ACK \SOH(\tR\ACKstatus\DC29\n\
      \\apayload\CAN\a \SOH(\v2\US.infernix.runtime.ResultPayloadR\apayload\DC2\GS\n\
      \\n\
      \created_at\CAN\b \SOH(\tR\tcreatedAt\DC2\GS\n\
      \\n\
      \causal_ref\CAN\t \SOH(\tR\tcausalRef\DC2\ETB\n\
      \\auser_id\CAN\n\
      \ \SOH(\tR\ACKuserId\DC2\GS\n\
      \\n\
      \context_id\CAN\v \SOH(\tR\tcontextId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        requestId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requestId")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        resultModelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "result_model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"resultModelId")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        matrixRowId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "matrix_row_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"matrixRowId")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        selectedEngine__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "selected_engine"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"selectedEngine")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        status__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "status"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"status")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        payload__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "payload"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ResultPayload)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'payload")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        createdAt__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "created_at"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"createdAt")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        causalRef__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "causal_ref"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"causalRef")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        userId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"userId")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        contextId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "context_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"contextId")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, requestId__field_descriptor),
           (Data.ProtoLens.Tag 2, resultModelId__field_descriptor),
           (Data.ProtoLens.Tag 3, matrixRowId__field_descriptor),
           (Data.ProtoLens.Tag 4, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 5, selectedEngine__field_descriptor),
           (Data.ProtoLens.Tag 6, status__field_descriptor),
           (Data.ProtoLens.Tag 7, payload__field_descriptor),
           (Data.ProtoLens.Tag 8, createdAt__field_descriptor),
           (Data.ProtoLens.Tag 9, causalRef__field_descriptor),
           (Data.ProtoLens.Tag 10, userId__field_descriptor),
           (Data.ProtoLens.Tag 11, contextId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InferenceResult'_unknownFields
        (\ x__ y__ -> x__ {_InferenceResult'_unknownFields = y__})
  defMessage
    = InferenceResult'_constructor
        {_InferenceResult'requestId = Data.ProtoLens.fieldDefault,
         _InferenceResult'resultModelId = Data.ProtoLens.fieldDefault,
         _InferenceResult'matrixRowId = Data.ProtoLens.fieldDefault,
         _InferenceResult'runtimeMode = Data.ProtoLens.fieldDefault,
         _InferenceResult'selectedEngine = Data.ProtoLens.fieldDefault,
         _InferenceResult'status = Data.ProtoLens.fieldDefault,
         _InferenceResult'payload = Prelude.Nothing,
         _InferenceResult'createdAt = Data.ProtoLens.fieldDefault,
         _InferenceResult'causalRef = Data.ProtoLens.fieldDefault,
         _InferenceResult'userId = Data.ProtoLens.fieldDefault,
         _InferenceResult'contextId = Data.ProtoLens.fieldDefault,
         _InferenceResult'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InferenceResult
          -> Data.ProtoLens.Encoding.Bytes.Parser InferenceResult
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
                                       "request_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"requestId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "result_model_id"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"resultModelId") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "matrix_row_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"matrixRowId") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "selected_engine"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"selectedEngine") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "status"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"status") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "payload"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"payload") y x)
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "created_at"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"createdAt") y x)
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "causal_ref"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"causalRef") y x)
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"userId") y x)
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "context_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"contextId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "InferenceResult"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"requestId") _x
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
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"resultModelId") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"matrixRowId") _x
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
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"runtimeMode") _x
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
                                  (Data.ProtoLens.Field.field @"selectedEngine") _x
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
                         ((Data.Monoid.<>)
                            (let
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"status") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                     ((Prelude..)
                                        (\ bs
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                   (Prelude.fromIntegral
                                                      (Data.ByteString.length bs)))
                                                (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                        Data.Text.Encoding.encodeUtf8 _v))
                            ((Data.Monoid.<>)
                               (case
                                    Lens.Family2.view
                                      (Data.ProtoLens.Field.field @"maybe'payload") _x
                                of
                                  Prelude.Nothing -> Data.Monoid.mempty
                                  (Prelude.Just _v)
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                         ((Prelude..)
                                            (\ bs
                                               -> (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                       (Prelude.fromIntegral
                                                          (Data.ByteString.length bs)))
                                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                            Data.ProtoLens.encodeMessage _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"createdAt") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                           ((Prelude..)
                                              (\ bs
                                                 -> (Data.Monoid.<>)
                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                         (Prelude.fromIntegral
                                                            (Data.ByteString.length bs)))
                                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                              Data.Text.Encoding.encodeUtf8 _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"causalRef") _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((Prelude..)
                                                 (\ bs
                                                    -> (Data.Monoid.<>)
                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                            (Prelude.fromIntegral
                                                               (Data.ByteString.length bs)))
                                                         (Data.ProtoLens.Encoding.Bytes.putBytes
                                                            bs))
                                                 Data.Text.Encoding.encodeUtf8 _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"userId") _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                 ((Prelude..)
                                                    (\ bs
                                                       -> (Data.Monoid.<>)
                                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                               (Prelude.fromIntegral
                                                                  (Data.ByteString.length bs)))
                                                            (Data.ProtoLens.Encoding.Bytes.putBytes
                                                               bs))
                                                    Data.Text.Encoding.encodeUtf8 _v))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"contextId") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                                    ((Prelude..)
                                                       (\ bs
                                                          -> (Data.Monoid.<>)
                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                  (Prelude.fromIntegral
                                                                     (Data.ByteString.length bs)))
                                                               (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                  bs))
                                                       Data.Text.Encoding.encodeUtf8 _v))
                                           (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                              (Lens.Family2.view
                                                 Data.ProtoLens.unknownFields _x))))))))))))
instance Control.DeepSeq.NFData InferenceResult where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InferenceResult'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_InferenceResult'requestId x__)
                (Control.DeepSeq.deepseq
                   (_InferenceResult'resultModelId x__)
                   (Control.DeepSeq.deepseq
                      (_InferenceResult'matrixRowId x__)
                      (Control.DeepSeq.deepseq
                         (_InferenceResult'runtimeMode x__)
                         (Control.DeepSeq.deepseq
                            (_InferenceResult'selectedEngine x__)
                            (Control.DeepSeq.deepseq
                               (_InferenceResult'status x__)
                               (Control.DeepSeq.deepseq
                                  (_InferenceResult'payload x__)
                                  (Control.DeepSeq.deepseq
                                     (_InferenceResult'createdAt x__)
                                     (Control.DeepSeq.deepseq
                                        (_InferenceResult'causalRef x__)
                                        (Control.DeepSeq.deepseq
                                           (_InferenceResult'userId x__)
                                           (Control.DeepSeq.deepseq
                                              (_InferenceResult'contextId x__) ())))))))))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.contextLength' @:: Lens' ModelExecutionShape Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.batchSize' @:: Lens' ModelExecutionShape Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.generationBound' @:: Lens' ModelExecutionShape Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.cacheElementWidth' @:: Lens' ModelExecutionShape Data.Int.Int64@
         * 'Proto.Infernix.Runtime.Inference_Fields.streamWeightsToDevice' @:: Lens' ModelExecutionShape Prelude.Bool@ -}
data ModelExecutionShape
  = ModelExecutionShape'_constructor {_ModelExecutionShape'contextLength :: !Data.Int.Int64,
                                      _ModelExecutionShape'batchSize :: !Data.Int.Int64,
                                      _ModelExecutionShape'generationBound :: !Data.Int.Int64,
                                      _ModelExecutionShape'cacheElementWidth :: !Data.Int.Int64,
                                      _ModelExecutionShape'streamWeightsToDevice :: !Prelude.Bool,
                                      _ModelExecutionShape'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ModelExecutionShape where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ModelExecutionShape "contextLength" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelExecutionShape'contextLength
           (\ x__ y__ -> x__ {_ModelExecutionShape'contextLength = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelExecutionShape "batchSize" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelExecutionShape'batchSize
           (\ x__ y__ -> x__ {_ModelExecutionShape'batchSize = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelExecutionShape "generationBound" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelExecutionShape'generationBound
           (\ x__ y__ -> x__ {_ModelExecutionShape'generationBound = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelExecutionShape "cacheElementWidth" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelExecutionShape'cacheElementWidth
           (\ x__ y__ -> x__ {_ModelExecutionShape'cacheElementWidth = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelExecutionShape "streamWeightsToDevice" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelExecutionShape'streamWeightsToDevice
           (\ x__ y__
              -> x__ {_ModelExecutionShape'streamWeightsToDevice = y__}))
        Prelude.id
instance Data.ProtoLens.Message ModelExecutionShape where
  messageName _
    = Data.Text.pack "infernix.runtime.ModelExecutionShape"
  packedMessageDescriptor _
    = "\n\
      \\DC3ModelExecutionShape\DC2%\n\
      \\SOcontext_length\CAN\SOH \SOH(\ETXR\rcontextLength\DC2\GS\n\
      \\n\
      \batch_size\CAN\STX \SOH(\ETXR\tbatchSize\DC2)\n\
      \\DLEgeneration_bound\CAN\ETX \SOH(\ETXR\SIgenerationBound\DC2.\n\
      \\DC3cache_element_width\CAN\EOT \SOH(\ETXR\DC1cacheElementWidth\DC27\n\
      \\CANstream_weights_to_device\CAN\ENQ \SOH(\bR\NAKstreamWeightsToDevice"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        contextLength__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "context_length"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"contextLength")) ::
              Data.ProtoLens.FieldDescriptor ModelExecutionShape
        batchSize__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "batch_size"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"batchSize")) ::
              Data.ProtoLens.FieldDescriptor ModelExecutionShape
        generationBound__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "generation_bound"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"generationBound")) ::
              Data.ProtoLens.FieldDescriptor ModelExecutionShape
        cacheElementWidth__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_element_width"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cacheElementWidth")) ::
              Data.ProtoLens.FieldDescriptor ModelExecutionShape
        streamWeightsToDevice__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stream_weights_to_device"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"streamWeightsToDevice")) ::
              Data.ProtoLens.FieldDescriptor ModelExecutionShape
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, contextLength__field_descriptor),
           (Data.ProtoLens.Tag 2, batchSize__field_descriptor),
           (Data.ProtoLens.Tag 3, generationBound__field_descriptor),
           (Data.ProtoLens.Tag 4, cacheElementWidth__field_descriptor),
           (Data.ProtoLens.Tag 5, streamWeightsToDevice__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ModelExecutionShape'_unknownFields
        (\ x__ y__ -> x__ {_ModelExecutionShape'_unknownFields = y__})
  defMessage
    = ModelExecutionShape'_constructor
        {_ModelExecutionShape'contextLength = Data.ProtoLens.fieldDefault,
         _ModelExecutionShape'batchSize = Data.ProtoLens.fieldDefault,
         _ModelExecutionShape'generationBound = Data.ProtoLens.fieldDefault,
         _ModelExecutionShape'cacheElementWidth = Data.ProtoLens.fieldDefault,
         _ModelExecutionShape'streamWeightsToDevice = Data.ProtoLens.fieldDefault,
         _ModelExecutionShape'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ModelExecutionShape
          -> Data.ProtoLens.Encoding.Bytes.Parser ModelExecutionShape
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
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "context_length"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"contextLength") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "batch_size"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"batchSize") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "generation_bound"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"generationBound") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "cache_element_width"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"cacheElementWidth") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "stream_weights_to_device"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"streamWeightsToDevice") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ModelExecutionShape"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"contextLength") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"batchSize") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view
                            (Data.ProtoLens.Field.field @"generationBound") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"cacheElementWidth") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"streamWeightsToDevice") _x
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
instance Control.DeepSeq.NFData ModelExecutionShape where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ModelExecutionShape'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ModelExecutionShape'contextLength x__)
                (Control.DeepSeq.deepseq
                   (_ModelExecutionShape'batchSize x__)
                   (Control.DeepSeq.deepseq
                      (_ModelExecutionShape'generationBound x__)
                      (Control.DeepSeq.deepseq
                         (_ModelExecutionShape'cacheElementWidth x__)
                         (Control.DeepSeq.deepseq
                            (_ModelExecutionShape'streamWeightsToDevice x__) ())))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.modelId' @:: Lens' ModelMemoryLimitExceeded Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.requiredMib' @:: Lens' ModelMemoryLimitExceeded Data.Int.Int32@
         * 'Proto.Infernix.Runtime.Inference_Fields.availableMib' @:: Lens' ModelMemoryLimitExceeded Data.Int.Int32@
         * 'Proto.Infernix.Runtime.Inference_Fields.resource' @:: Lens' ModelMemoryLimitExceeded Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.source' @:: Lens' ModelMemoryLimitExceeded Data.Text.Text@ -}
data ModelMemoryLimitExceeded
  = ModelMemoryLimitExceeded'_constructor {_ModelMemoryLimitExceeded'modelId :: !Data.Text.Text,
                                           _ModelMemoryLimitExceeded'requiredMib :: !Data.Int.Int32,
                                           _ModelMemoryLimitExceeded'availableMib :: !Data.Int.Int32,
                                           _ModelMemoryLimitExceeded'resource :: !Data.Text.Text,
                                           _ModelMemoryLimitExceeded'source :: !Data.Text.Text,
                                           _ModelMemoryLimitExceeded'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ModelMemoryLimitExceeded where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ModelMemoryLimitExceeded "modelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMemoryLimitExceeded'modelId
           (\ x__ y__ -> x__ {_ModelMemoryLimitExceeded'modelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMemoryLimitExceeded "requiredMib" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMemoryLimitExceeded'requiredMib
           (\ x__ y__ -> x__ {_ModelMemoryLimitExceeded'requiredMib = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMemoryLimitExceeded "availableMib" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMemoryLimitExceeded'availableMib
           (\ x__ y__ -> x__ {_ModelMemoryLimitExceeded'availableMib = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMemoryLimitExceeded "resource" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMemoryLimitExceeded'resource
           (\ x__ y__ -> x__ {_ModelMemoryLimitExceeded'resource = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelMemoryLimitExceeded "source" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelMemoryLimitExceeded'source
           (\ x__ y__ -> x__ {_ModelMemoryLimitExceeded'source = y__}))
        Prelude.id
instance Data.ProtoLens.Message ModelMemoryLimitExceeded where
  messageName _
    = Data.Text.pack "infernix.runtime.ModelMemoryLimitExceeded"
  packedMessageDescriptor _
    = "\n\
      \\CANModelMemoryLimitExceeded\DC2\EM\n\
      \\bmodel_id\CAN\SOH \SOH(\tR\amodelId\DC2!\n\
      \\frequired_mib\CAN\STX \SOH(\ENQR\vrequiredMib\DC2#\n\
      \\ravailable_mib\CAN\ETX \SOH(\ENQR\favailableMib\DC2\SUB\n\
      \\bresource\CAN\EOT \SOH(\tR\bresource\DC2\SYN\n\
      \\ACKsource\CAN\ENQ \SOH(\tR\ACKsource"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        modelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"modelId")) ::
              Data.ProtoLens.FieldDescriptor ModelMemoryLimitExceeded
        requiredMib__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "required_mib"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requiredMib")) ::
              Data.ProtoLens.FieldDescriptor ModelMemoryLimitExceeded
        availableMib__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "available_mib"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"availableMib")) ::
              Data.ProtoLens.FieldDescriptor ModelMemoryLimitExceeded
        resource__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "resource"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"resource")) ::
              Data.ProtoLens.FieldDescriptor ModelMemoryLimitExceeded
        source__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "source"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"source")) ::
              Data.ProtoLens.FieldDescriptor ModelMemoryLimitExceeded
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, modelId__field_descriptor),
           (Data.ProtoLens.Tag 2, requiredMib__field_descriptor),
           (Data.ProtoLens.Tag 3, availableMib__field_descriptor),
           (Data.ProtoLens.Tag 4, resource__field_descriptor),
           (Data.ProtoLens.Tag 5, source__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ModelMemoryLimitExceeded'_unknownFields
        (\ x__ y__ -> x__ {_ModelMemoryLimitExceeded'_unknownFields = y__})
  defMessage
    = ModelMemoryLimitExceeded'_constructor
        {_ModelMemoryLimitExceeded'modelId = Data.ProtoLens.fieldDefault,
         _ModelMemoryLimitExceeded'requiredMib = Data.ProtoLens.fieldDefault,
         _ModelMemoryLimitExceeded'availableMib = Data.ProtoLens.fieldDefault,
         _ModelMemoryLimitExceeded'resource = Data.ProtoLens.fieldDefault,
         _ModelMemoryLimitExceeded'source = Data.ProtoLens.fieldDefault,
         _ModelMemoryLimitExceeded'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ModelMemoryLimitExceeded
          -> Data.ProtoLens.Encoding.Bytes.Parser ModelMemoryLimitExceeded
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
                                       "model_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"modelId") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "required_mib"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"requiredMib") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "available_mib"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"availableMib") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "resource"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"resource") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "source"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"source") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ModelMemoryLimitExceeded"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"modelId") _x
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
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"requiredMib") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"availableMib") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"resource") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"source") _x
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
instance Control.DeepSeq.NFData ModelMemoryLimitExceeded where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ModelMemoryLimitExceeded'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ModelMemoryLimitExceeded'modelId x__)
                (Control.DeepSeq.deepseq
                   (_ModelMemoryLimitExceeded'requiredMib x__)
                   (Control.DeepSeq.deepseq
                      (_ModelMemoryLimitExceeded'availableMib x__)
                      (Control.DeepSeq.deepseq
                         (_ModelMemoryLimitExceeded'resource x__)
                         (Control.DeepSeq.deepseq
                            (_ModelMemoryLimitExceeded'source x__) ())))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.modelId' @:: Lens' ModelRequirementUnderivable Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.artifactType' @:: Lens' ModelRequirementUnderivable Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.reason' @:: Lens' ModelRequirementUnderivable Data.Text.Text@ -}
data ModelRequirementUnderivable
  = ModelRequirementUnderivable'_constructor {_ModelRequirementUnderivable'modelId :: !Data.Text.Text,
                                              _ModelRequirementUnderivable'artifactType :: !Data.Text.Text,
                                              _ModelRequirementUnderivable'reason :: !Data.Text.Text,
                                              _ModelRequirementUnderivable'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ModelRequirementUnderivable where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ModelRequirementUnderivable "modelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelRequirementUnderivable'modelId
           (\ x__ y__ -> x__ {_ModelRequirementUnderivable'modelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelRequirementUnderivable "artifactType" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelRequirementUnderivable'artifactType
           (\ x__ y__
              -> x__ {_ModelRequirementUnderivable'artifactType = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ModelRequirementUnderivable "reason" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ModelRequirementUnderivable'reason
           (\ x__ y__ -> x__ {_ModelRequirementUnderivable'reason = y__}))
        Prelude.id
instance Data.ProtoLens.Message ModelRequirementUnderivable where
  messageName _
    = Data.Text.pack "infernix.runtime.ModelRequirementUnderivable"
  packedMessageDescriptor _
    = "\n\
      \\ESCModelRequirementUnderivable\DC2\EM\n\
      \\bmodel_id\CAN\SOH \SOH(\tR\amodelId\DC2#\n\
      \\rartifact_type\CAN\STX \SOH(\tR\fartifactType\DC2\SYN\n\
      \\ACKreason\CAN\ETX \SOH(\tR\ACKreason"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        modelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"modelId")) ::
              Data.ProtoLens.FieldDescriptor ModelRequirementUnderivable
        artifactType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "artifact_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"artifactType")) ::
              Data.ProtoLens.FieldDescriptor ModelRequirementUnderivable
        reason__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reason"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"reason")) ::
              Data.ProtoLens.FieldDescriptor ModelRequirementUnderivable
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, modelId__field_descriptor),
           (Data.ProtoLens.Tag 2, artifactType__field_descriptor),
           (Data.ProtoLens.Tag 3, reason__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ModelRequirementUnderivable'_unknownFields
        (\ x__ y__
           -> x__ {_ModelRequirementUnderivable'_unknownFields = y__})
  defMessage
    = ModelRequirementUnderivable'_constructor
        {_ModelRequirementUnderivable'modelId = Data.ProtoLens.fieldDefault,
         _ModelRequirementUnderivable'artifactType = Data.ProtoLens.fieldDefault,
         _ModelRequirementUnderivable'reason = Data.ProtoLens.fieldDefault,
         _ModelRequirementUnderivable'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ModelRequirementUnderivable
          -> Data.ProtoLens.Encoding.Bytes.Parser ModelRequirementUnderivable
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
                                       "model_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"modelId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "artifact_type"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"artifactType") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reason"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"reason") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ModelRequirementUnderivable"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"modelId") _x
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
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"artifactType") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"reason") _x
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
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData ModelRequirementUnderivable where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ModelRequirementUnderivable'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ModelRequirementUnderivable'modelId x__)
                (Control.DeepSeq.deepseq
                   (_ModelRequirementUnderivable'artifactType x__)
                   (Control.DeepSeq.deepseq
                      (_ModelRequirementUnderivable'reason x__) ())))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.name' @:: Lens' RequestField Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.label' @:: Lens' RequestField Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.fieldType' @:: Lens' RequestField Data.Text.Text@ -}
data RequestField
  = RequestField'_constructor {_RequestField'name :: !Data.Text.Text,
                               _RequestField'label :: !Data.Text.Text,
                               _RequestField'fieldType :: !Data.Text.Text,
                               _RequestField'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RequestField where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RequestField "name" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestField'name (\ x__ y__ -> x__ {_RequestField'name = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestField "label" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestField'label (\ x__ y__ -> x__ {_RequestField'label = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestField "fieldType" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestField'fieldType
           (\ x__ y__ -> x__ {_RequestField'fieldType = y__}))
        Prelude.id
instance Data.ProtoLens.Message RequestField where
  messageName _ = Data.Text.pack "infernix.runtime.RequestField"
  packedMessageDescriptor _
    = "\n\
      \\fRequestField\DC2\DC2\n\
      \\EOTname\CAN\SOH \SOH(\tR\EOTname\DC2\DC4\n\
      \\ENQlabel\CAN\STX \SOH(\tR\ENQlabel\DC2\GS\n\
      \\n\
      \field_type\CAN\ETX \SOH(\tR\tfieldType"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        name__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"name")) ::
              Data.ProtoLens.FieldDescriptor RequestField
        label__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "label"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"label")) ::
              Data.ProtoLens.FieldDescriptor RequestField
        fieldType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "field_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"fieldType")) ::
              Data.ProtoLens.FieldDescriptor RequestField
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, name__field_descriptor),
           (Data.ProtoLens.Tag 2, label__field_descriptor),
           (Data.ProtoLens.Tag 3, fieldType__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RequestField'_unknownFields
        (\ x__ y__ -> x__ {_RequestField'_unknownFields = y__})
  defMessage
    = RequestField'_constructor
        {_RequestField'name = Data.ProtoLens.fieldDefault,
         _RequestField'label = Data.ProtoLens.fieldDefault,
         _RequestField'fieldType = Data.ProtoLens.fieldDefault,
         _RequestField'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RequestField -> Data.ProtoLens.Encoding.Bytes.Parser RequestField
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
                                       "name"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"name") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "label"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"label") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "field_type"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"fieldType") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "RequestField"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"name") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"label") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"fieldType") _x
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
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData RequestField where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RequestField'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RequestField'name x__)
                (Control.DeepSeq.deepseq
                   (_RequestField'label x__)
                   (Control.DeepSeq.deepseq (_RequestField'fieldType x__) ())))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'output' @:: Lens' ResultPayload (Prelude.Maybe ResultPayload'Output)@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'inlineOutput' @:: Lens' ResultPayload (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Infernix.Runtime.Inference_Fields.inlineOutput' @:: Lens' ResultPayload Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'objectRef' @:: Lens' ResultPayload (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Infernix.Runtime.Inference_Fields.objectRef' @:: Lens' ResultPayload Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'inferenceError' @:: Lens' ResultPayload (Prelude.Maybe InferenceError)@
         * 'Proto.Infernix.Runtime.Inference_Fields.inferenceError' @:: Lens' ResultPayload InferenceError@ -}
data ResultPayload
  = ResultPayload'_constructor {_ResultPayload'output :: !(Prelude.Maybe ResultPayload'Output),
                                _ResultPayload'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ResultPayload where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data ResultPayload'Output
  = ResultPayload'InlineOutput !Data.Text.Text |
    ResultPayload'ObjectRef !Data.Text.Text |
    ResultPayload'InferenceError !InferenceError
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField ResultPayload "maybe'output" (Prelude.Maybe ResultPayload'Output) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ResultPayload "maybe'inlineOutput" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (ResultPayload'InlineOutput x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap ResultPayload'InlineOutput y__))
instance Data.ProtoLens.Field.HasField ResultPayload "inlineOutput" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (ResultPayload'InlineOutput x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap ResultPayload'InlineOutput y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Field.HasField ResultPayload "maybe'objectRef" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (ResultPayload'ObjectRef x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap ResultPayload'ObjectRef y__))
instance Data.ProtoLens.Field.HasField ResultPayload "objectRef" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (ResultPayload'ObjectRef x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap ResultPayload'ObjectRef y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Field.HasField ResultPayload "maybe'inferenceError" (Prelude.Maybe InferenceError) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (ResultPayload'InferenceError x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap ResultPayload'InferenceError y__))
instance Data.ProtoLens.Field.HasField ResultPayload "inferenceError" InferenceError where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResultPayload'output
           (\ x__ y__ -> x__ {_ResultPayload'output = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (ResultPayload'InferenceError x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap ResultPayload'InferenceError y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message ResultPayload where
  messageName _ = Data.Text.pack "infernix.runtime.ResultPayload"
  packedMessageDescriptor _
    = "\n\
      \\rResultPayload\DC2%\n\
      \\rinline_output\CAN\SOH \SOH(\tH\NULR\finlineOutput\DC2\US\n\
      \\n\
      \object_ref\CAN\STX \SOH(\tH\NULR\tobjectRef\DC2K\n\
      \\SIinference_error\CAN\ETX \SOH(\v2 .infernix.runtime.InferenceErrorH\NULR\SOinferenceErrorB\b\n\
      \\ACKoutput"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        inlineOutput__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "inline_output"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'inlineOutput")) ::
              Data.ProtoLens.FieldDescriptor ResultPayload
        objectRef__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "object_ref"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'objectRef")) ::
              Data.ProtoLens.FieldDescriptor ResultPayload
        inferenceError__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "inference_error"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor InferenceError)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'inferenceError")) ::
              Data.ProtoLens.FieldDescriptor ResultPayload
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, inlineOutput__field_descriptor),
           (Data.ProtoLens.Tag 2, objectRef__field_descriptor),
           (Data.ProtoLens.Tag 3, inferenceError__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ResultPayload'_unknownFields
        (\ x__ y__ -> x__ {_ResultPayload'_unknownFields = y__})
  defMessage
    = ResultPayload'_constructor
        {_ResultPayload'output = Prelude.Nothing,
         _ResultPayload'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ResultPayload -> Data.ProtoLens.Encoding.Bytes.Parser ResultPayload
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
                                       "inline_output"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"inlineOutput") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "object_ref"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"objectRef") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "inference_error"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"inferenceError") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ResultPayload"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'output") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (ResultPayload'InlineOutput v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.Text.Encoding.encodeUtf8 v)
                (Prelude.Just (ResultPayload'ObjectRef v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.Text.Encoding.encodeUtf8 v)
                (Prelude.Just (ResultPayload'InferenceError v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData ResultPayload where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ResultPayload'_unknownFields x__)
             (Control.DeepSeq.deepseq (_ResultPayload'output x__) ())
instance Control.DeepSeq.NFData ResultPayload'Output where
  rnf (ResultPayload'InlineOutput x__) = Control.DeepSeq.rnf x__
  rnf (ResultPayload'ObjectRef x__) = Control.DeepSeq.rnf x__
  rnf (ResultPayload'InferenceError x__) = Control.DeepSeq.rnf x__
_ResultPayload'InlineOutput ::
  Data.ProtoLens.Prism.Prism' ResultPayload'Output Data.Text.Text
_ResultPayload'InlineOutput
  = Data.ProtoLens.Prism.prism'
      ResultPayload'InlineOutput
      (\ p__
         -> case p__ of
              (ResultPayload'InlineOutput p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_ResultPayload'ObjectRef ::
  Data.ProtoLens.Prism.Prism' ResultPayload'Output Data.Text.Text
_ResultPayload'ObjectRef
  = Data.ProtoLens.Prism.prism'
      ResultPayload'ObjectRef
      (\ p__
         -> case p__ of
              (ResultPayload'ObjectRef p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_ResultPayload'InferenceError ::
  Data.ProtoLens.Prism.Prism' ResultPayload'Output InferenceError
_ResultPayload'InferenceError
  = Data.ProtoLens.Prism.prism'
      ResultPayload'InferenceError
      (\ p__
         -> case p__ of
              (ResultPayload'InferenceError p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.requestModelId' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.inputText' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeMode' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.selectedEngine' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.adapterId' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.engineInstallRoot' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.displayName' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.family' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.artifactType' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.runtimeLane' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.inputObjectRef' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.modelCacheRoot' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.modelCacheQuotaBytes' @:: Lens' WorkerRequest Data.Word.Word64@
         * 'Proto.Infernix.Runtime.Inference_Fields.minioEndpoint' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.minioModelsBucket' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.minioDemoArtifactsBucket' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.minioRegion' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.minioAccessKey' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.minioSecretKey' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.generatedOutputObjectPrefix' @:: Lens' WorkerRequest Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.memoryBudget' @:: Lens' WorkerRequest InferenceMemoryBudget@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'memoryBudget' @:: Lens' WorkerRequest (Prelude.Maybe InferenceMemoryBudget)@
         * 'Proto.Infernix.Runtime.Inference_Fields.executionShape' @:: Lens' WorkerRequest ModelExecutionShape@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'executionShape' @:: Lens' WorkerRequest (Prelude.Maybe ModelExecutionShape)@ -}
data WorkerRequest
  = WorkerRequest'_constructor {_WorkerRequest'requestModelId :: !Data.Text.Text,
                                _WorkerRequest'inputText :: !Data.Text.Text,
                                _WorkerRequest'runtimeMode :: !Data.Text.Text,
                                _WorkerRequest'selectedEngine :: !Data.Text.Text,
                                _WorkerRequest'adapterId :: !Data.Text.Text,
                                _WorkerRequest'engineInstallRoot :: !Data.Text.Text,
                                _WorkerRequest'displayName :: !Data.Text.Text,
                                _WorkerRequest'family :: !Data.Text.Text,
                                _WorkerRequest'artifactType :: !Data.Text.Text,
                                _WorkerRequest'runtimeLane :: !Data.Text.Text,
                                _WorkerRequest'inputObjectRef :: !Data.Text.Text,
                                _WorkerRequest'modelCacheRoot :: !Data.Text.Text,
                                _WorkerRequest'modelCacheQuotaBytes :: !Data.Word.Word64,
                                _WorkerRequest'minioEndpoint :: !Data.Text.Text,
                                _WorkerRequest'minioModelsBucket :: !Data.Text.Text,
                                _WorkerRequest'minioDemoArtifactsBucket :: !Data.Text.Text,
                                _WorkerRequest'minioRegion :: !Data.Text.Text,
                                _WorkerRequest'minioAccessKey :: !Data.Text.Text,
                                _WorkerRequest'minioSecretKey :: !Data.Text.Text,
                                _WorkerRequest'generatedOutputObjectPrefix :: !Data.Text.Text,
                                _WorkerRequest'memoryBudget :: !(Prelude.Maybe InferenceMemoryBudget),
                                _WorkerRequest'executionShape :: !(Prelude.Maybe ModelExecutionShape),
                                _WorkerRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show WorkerRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField WorkerRequest "requestModelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'requestModelId
           (\ x__ y__ -> x__ {_WorkerRequest'requestModelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "inputText" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'inputText
           (\ x__ y__ -> x__ {_WorkerRequest'inputText = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "runtimeMode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'runtimeMode
           (\ x__ y__ -> x__ {_WorkerRequest'runtimeMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "selectedEngine" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'selectedEngine
           (\ x__ y__ -> x__ {_WorkerRequest'selectedEngine = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "adapterId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'adapterId
           (\ x__ y__ -> x__ {_WorkerRequest'adapterId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "engineInstallRoot" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'engineInstallRoot
           (\ x__ y__ -> x__ {_WorkerRequest'engineInstallRoot = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "displayName" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'displayName
           (\ x__ y__ -> x__ {_WorkerRequest'displayName = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "family" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'family
           (\ x__ y__ -> x__ {_WorkerRequest'family = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "artifactType" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'artifactType
           (\ x__ y__ -> x__ {_WorkerRequest'artifactType = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "runtimeLane" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'runtimeLane
           (\ x__ y__ -> x__ {_WorkerRequest'runtimeLane = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "inputObjectRef" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'inputObjectRef
           (\ x__ y__ -> x__ {_WorkerRequest'inputObjectRef = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "modelCacheRoot" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'modelCacheRoot
           (\ x__ y__ -> x__ {_WorkerRequest'modelCacheRoot = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "modelCacheQuotaBytes" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'modelCacheQuotaBytes
           (\ x__ y__ -> x__ {_WorkerRequest'modelCacheQuotaBytes = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "minioEndpoint" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'minioEndpoint
           (\ x__ y__ -> x__ {_WorkerRequest'minioEndpoint = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "minioModelsBucket" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'minioModelsBucket
           (\ x__ y__ -> x__ {_WorkerRequest'minioModelsBucket = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "minioDemoArtifactsBucket" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'minioDemoArtifactsBucket
           (\ x__ y__ -> x__ {_WorkerRequest'minioDemoArtifactsBucket = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "minioRegion" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'minioRegion
           (\ x__ y__ -> x__ {_WorkerRequest'minioRegion = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "minioAccessKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'minioAccessKey
           (\ x__ y__ -> x__ {_WorkerRequest'minioAccessKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "minioSecretKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'minioSecretKey
           (\ x__ y__ -> x__ {_WorkerRequest'minioSecretKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "generatedOutputObjectPrefix" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'generatedOutputObjectPrefix
           (\ x__ y__
              -> x__ {_WorkerRequest'generatedOutputObjectPrefix = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "memoryBudget" InferenceMemoryBudget where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'memoryBudget
           (\ x__ y__ -> x__ {_WorkerRequest'memoryBudget = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField WorkerRequest "maybe'memoryBudget" (Prelude.Maybe InferenceMemoryBudget) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'memoryBudget
           (\ x__ y__ -> x__ {_WorkerRequest'memoryBudget = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerRequest "executionShape" ModelExecutionShape where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'executionShape
           (\ x__ y__ -> x__ {_WorkerRequest'executionShape = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField WorkerRequest "maybe'executionShape" (Prelude.Maybe ModelExecutionShape) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerRequest'executionShape
           (\ x__ y__ -> x__ {_WorkerRequest'executionShape = y__}))
        Prelude.id
instance Data.ProtoLens.Message WorkerRequest where
  messageName _ = Data.Text.pack "infernix.runtime.WorkerRequest"
  packedMessageDescriptor _
    = "\n\
      \\rWorkerRequest\DC2(\n\
      \\DLErequest_model_id\CAN\SOH \SOH(\tR\SOrequestModelId\DC2\GS\n\
      \\n\
      \input_text\CAN\STX \SOH(\tR\tinputText\DC2!\n\
      \\fruntime_mode\CAN\ETX \SOH(\tR\vruntimeMode\DC2'\n\
      \\SIselected_engine\CAN\EOT \SOH(\tR\SOselectedEngine\DC2\GS\n\
      \\n\
      \adapter_id\CAN\ENQ \SOH(\tR\tadapterId\DC2.\n\
      \\DC3engine_install_root\CAN\ACK \SOH(\tR\DC1engineInstallRoot\DC2!\n\
      \\fdisplay_name\CAN\a \SOH(\tR\vdisplayName\DC2\SYN\n\
      \\ACKfamily\CAN\b \SOH(\tR\ACKfamily\DC2#\n\
      \\rartifact_type\CAN\t \SOH(\tR\fartifactType\DC2!\n\
      \\fruntime_lane\CAN\n\
      \ \SOH(\tR\vruntimeLane\DC2(\n\
      \\DLEinput_object_ref\CAN\v \SOH(\tR\SOinputObjectRef\DC2(\n\
      \\DLEmodel_cache_root\CAN\f \SOH(\tR\SOmodelCacheRoot\DC25\n\
      \\ETBmodel_cache_quota_bytes\CAN\r \SOH(\EOTR\DC4modelCacheQuotaBytes\DC2%\n\
      \\SOminio_endpoint\CAN\SO \SOH(\tR\rminioEndpoint\DC2.\n\
      \\DC3minio_models_bucket\CAN\SI \SOH(\tR\DC1minioModelsBucket\DC2=\n\
      \\ESCminio_demo_artifacts_bucket\CAN\DLE \SOH(\tR\CANminioDemoArtifactsBucket\DC2!\n\
      \\fminio_region\CAN\DC1 \SOH(\tR\vminioRegion\DC2(\n\
      \\DLEminio_access_key\CAN\DC2 \SOH(\tR\SOminioAccessKey\DC2(\n\
      \\DLEminio_secret_key\CAN\DC3 \SOH(\tR\SOminioSecretKey\DC2C\n\
      \\RSgenerated_output_object_prefix\CAN\DC4 \SOH(\tR\ESCgeneratedOutputObjectPrefix\DC2L\n\
      \\rmemory_budget\CAN\NAK \SOH(\v2'.infernix.runtime.InferenceMemoryBudgetR\fmemoryBudget\DC2N\n\
      \\SIexecution_shape\CAN\SYN \SOH(\v2%.infernix.runtime.ModelExecutionShapeR\SOexecutionShape"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        requestModelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requestModelId")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        inputText__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "input_text"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"inputText")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        runtimeMode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeMode")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        selectedEngine__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "selected_engine"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"selectedEngine")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        adapterId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "adapter_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"adapterId")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        engineInstallRoot__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "engine_install_root"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"engineInstallRoot")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        displayName__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "display_name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"displayName")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        family__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "family"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"family")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        artifactType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "artifact_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"artifactType")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        runtimeLane__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "runtime_lane"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"runtimeLane")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        inputObjectRef__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "input_object_ref"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"inputObjectRef")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        modelCacheRoot__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_cache_root"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"modelCacheRoot")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        modelCacheQuotaBytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_cache_quota_bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"modelCacheQuotaBytes")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        minioEndpoint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "minio_endpoint"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"minioEndpoint")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        minioModelsBucket__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "minio_models_bucket"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"minioModelsBucket")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        minioDemoArtifactsBucket__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "minio_demo_artifacts_bucket"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"minioDemoArtifactsBucket")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        minioRegion__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "minio_region"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"minioRegion")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        minioAccessKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "minio_access_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"minioAccessKey")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        minioSecretKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "minio_secret_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"minioSecretKey")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        generatedOutputObjectPrefix__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "generated_output_object_prefix"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"generatedOutputObjectPrefix")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        memoryBudget__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "memory_budget"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor InferenceMemoryBudget)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'memoryBudget")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
        executionShape__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "execution_shape"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ModelExecutionShape)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'executionShape")) ::
              Data.ProtoLens.FieldDescriptor WorkerRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, requestModelId__field_descriptor),
           (Data.ProtoLens.Tag 2, inputText__field_descriptor),
           (Data.ProtoLens.Tag 3, runtimeMode__field_descriptor),
           (Data.ProtoLens.Tag 4, selectedEngine__field_descriptor),
           (Data.ProtoLens.Tag 5, adapterId__field_descriptor),
           (Data.ProtoLens.Tag 6, engineInstallRoot__field_descriptor),
           (Data.ProtoLens.Tag 7, displayName__field_descriptor),
           (Data.ProtoLens.Tag 8, family__field_descriptor),
           (Data.ProtoLens.Tag 9, artifactType__field_descriptor),
           (Data.ProtoLens.Tag 10, runtimeLane__field_descriptor),
           (Data.ProtoLens.Tag 11, inputObjectRef__field_descriptor),
           (Data.ProtoLens.Tag 12, modelCacheRoot__field_descriptor),
           (Data.ProtoLens.Tag 13, modelCacheQuotaBytes__field_descriptor),
           (Data.ProtoLens.Tag 14, minioEndpoint__field_descriptor),
           (Data.ProtoLens.Tag 15, minioModelsBucket__field_descriptor),
           (Data.ProtoLens.Tag 16, 
            minioDemoArtifactsBucket__field_descriptor),
           (Data.ProtoLens.Tag 17, minioRegion__field_descriptor),
           (Data.ProtoLens.Tag 18, minioAccessKey__field_descriptor),
           (Data.ProtoLens.Tag 19, minioSecretKey__field_descriptor),
           (Data.ProtoLens.Tag 20, 
            generatedOutputObjectPrefix__field_descriptor),
           (Data.ProtoLens.Tag 21, memoryBudget__field_descriptor),
           (Data.ProtoLens.Tag 22, executionShape__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _WorkerRequest'_unknownFields
        (\ x__ y__ -> x__ {_WorkerRequest'_unknownFields = y__})
  defMessage
    = WorkerRequest'_constructor
        {_WorkerRequest'requestModelId = Data.ProtoLens.fieldDefault,
         _WorkerRequest'inputText = Data.ProtoLens.fieldDefault,
         _WorkerRequest'runtimeMode = Data.ProtoLens.fieldDefault,
         _WorkerRequest'selectedEngine = Data.ProtoLens.fieldDefault,
         _WorkerRequest'adapterId = Data.ProtoLens.fieldDefault,
         _WorkerRequest'engineInstallRoot = Data.ProtoLens.fieldDefault,
         _WorkerRequest'displayName = Data.ProtoLens.fieldDefault,
         _WorkerRequest'family = Data.ProtoLens.fieldDefault,
         _WorkerRequest'artifactType = Data.ProtoLens.fieldDefault,
         _WorkerRequest'runtimeLane = Data.ProtoLens.fieldDefault,
         _WorkerRequest'inputObjectRef = Data.ProtoLens.fieldDefault,
         _WorkerRequest'modelCacheRoot = Data.ProtoLens.fieldDefault,
         _WorkerRequest'modelCacheQuotaBytes = Data.ProtoLens.fieldDefault,
         _WorkerRequest'minioEndpoint = Data.ProtoLens.fieldDefault,
         _WorkerRequest'minioModelsBucket = Data.ProtoLens.fieldDefault,
         _WorkerRequest'minioDemoArtifactsBucket = Data.ProtoLens.fieldDefault,
         _WorkerRequest'minioRegion = Data.ProtoLens.fieldDefault,
         _WorkerRequest'minioAccessKey = Data.ProtoLens.fieldDefault,
         _WorkerRequest'minioSecretKey = Data.ProtoLens.fieldDefault,
         _WorkerRequest'generatedOutputObjectPrefix = Data.ProtoLens.fieldDefault,
         _WorkerRequest'memoryBudget = Prelude.Nothing,
         _WorkerRequest'executionShape = Prelude.Nothing,
         _WorkerRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          WorkerRequest -> Data.ProtoLens.Encoding.Bytes.Parser WorkerRequest
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
                                       "request_model_id"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"requestModelId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "input_text"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"inputText") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeMode") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "selected_engine"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"selectedEngine") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "adapter_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"adapterId") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "engine_install_root"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"engineInstallRoot") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "display_name"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"displayName") y x)
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "family"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"family") y x)
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "artifact_type"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"artifactType") y x)
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "runtime_lane"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runtimeLane") y x)
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "input_object_ref"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"inputObjectRef") y x)
                        98
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model_cache_root"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"modelCacheRoot") y x)
                        104
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt
                                       "model_cache_quota_bytes"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"modelCacheQuotaBytes") y x)
                        114
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "minio_endpoint"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"minioEndpoint") y x)
                        122
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "minio_models_bucket"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"minioModelsBucket") y x)
                        130
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "minio_demo_artifacts_bucket"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"minioDemoArtifactsBucket") y x)
                        138
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "minio_region"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"minioRegion") y x)
                        146
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "minio_access_key"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"minioAccessKey") y x)
                        154
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "minio_secret_key"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"minioSecretKey") y x)
                        162
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "generated_output_object_prefix"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"generatedOutputObjectPrefix") y
                                     x)
                        170
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "memory_budget"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"memoryBudget") y x)
                        178
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "execution_shape"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"executionShape") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "WorkerRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"requestModelId") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"inputText") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"runtimeMode") _x
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
                               (Data.ProtoLens.Field.field @"selectedEngine") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"adapterId") _x
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
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"engineInstallRoot") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                     ((Prelude..)
                                        (\ bs
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                   (Prelude.fromIntegral
                                                      (Data.ByteString.length bs)))
                                                (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                        Data.Text.Encoding.encodeUtf8 _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"displayName") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                        ((Prelude..)
                                           (\ bs
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                      (Prelude.fromIntegral
                                                         (Data.ByteString.length bs)))
                                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                           Data.Text.Encoding.encodeUtf8 _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view (Data.ProtoLens.Field.field @"family") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                           ((Prelude..)
                                              (\ bs
                                                 -> (Data.Monoid.<>)
                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                         (Prelude.fromIntegral
                                                            (Data.ByteString.length bs)))
                                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                              Data.Text.Encoding.encodeUtf8 _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"artifactType") _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((Prelude..)
                                                 (\ bs
                                                    -> (Data.Monoid.<>)
                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                            (Prelude.fromIntegral
                                                               (Data.ByteString.length bs)))
                                                         (Data.ProtoLens.Encoding.Bytes.putBytes
                                                            bs))
                                                 Data.Text.Encoding.encodeUtf8 _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"runtimeLane") _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                 ((Prelude..)
                                                    (\ bs
                                                       -> (Data.Monoid.<>)
                                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                               (Prelude.fromIntegral
                                                                  (Data.ByteString.length bs)))
                                                            (Data.ProtoLens.Encoding.Bytes.putBytes
                                                               bs))
                                                    Data.Text.Encoding.encodeUtf8 _v))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"inputObjectRef")
                                                    _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                                    ((Prelude..)
                                                       (\ bs
                                                          -> (Data.Monoid.<>)
                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                  (Prelude.fromIntegral
                                                                     (Data.ByteString.length bs)))
                                                               (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                  bs))
                                                       Data.Text.Encoding.encodeUtf8 _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field
                                                          @"modelCacheRoot")
                                                       _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                                       ((Prelude..)
                                                          (\ bs
                                                             -> (Data.Monoid.<>)
                                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                     (Prelude.fromIntegral
                                                                        (Data.ByteString.length
                                                                           bs)))
                                                                  (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                     bs))
                                                          Data.Text.Encoding.encodeUtf8 _v))
                                              ((Data.Monoid.<>)
                                                 (let
                                                    _v
                                                      = Lens.Family2.view
                                                          (Data.ProtoLens.Field.field
                                                             @"modelCacheQuotaBytes")
                                                          _x
                                                  in
                                                    if (Prelude.==)
                                                         _v Data.ProtoLens.fieldDefault then
                                                        Data.Monoid.mempty
                                                    else
                                                        (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             104)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             _v))
                                                 ((Data.Monoid.<>)
                                                    (let
                                                       _v
                                                         = Lens.Family2.view
                                                             (Data.ProtoLens.Field.field
                                                                @"minioEndpoint")
                                                             _x
                                                     in
                                                       if (Prelude.==)
                                                            _v Data.ProtoLens.fieldDefault then
                                                           Data.Monoid.mempty
                                                       else
                                                           (Data.Monoid.<>)
                                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                114)
                                                             ((Prelude..)
                                                                (\ bs
                                                                   -> (Data.Monoid.<>)
                                                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                           (Prelude.fromIntegral
                                                                              (Data.ByteString.length
                                                                                 bs)))
                                                                        (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                           bs))
                                                                Data.Text.Encoding.encodeUtf8 _v))
                                                    ((Data.Monoid.<>)
                                                       (let
                                                          _v
                                                            = Lens.Family2.view
                                                                (Data.ProtoLens.Field.field
                                                                   @"minioModelsBucket")
                                                                _x
                                                        in
                                                          if (Prelude.==)
                                                               _v Data.ProtoLens.fieldDefault then
                                                              Data.Monoid.mempty
                                                          else
                                                              (Data.Monoid.<>)
                                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                   122)
                                                                ((Prelude..)
                                                                   (\ bs
                                                                      -> (Data.Monoid.<>)
                                                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                              (Prelude.fromIntegral
                                                                                 (Data.ByteString.length
                                                                                    bs)))
                                                                           (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                              bs))
                                                                   Data.Text.Encoding.encodeUtf8
                                                                   _v))
                                                       ((Data.Monoid.<>)
                                                          (let
                                                             _v
                                                               = Lens.Family2.view
                                                                   (Data.ProtoLens.Field.field
                                                                      @"minioDemoArtifactsBucket")
                                                                   _x
                                                           in
                                                             if (Prelude.==)
                                                                  _v
                                                                  Data.ProtoLens.fieldDefault then
                                                                 Data.Monoid.mempty
                                                             else
                                                                 (Data.Monoid.<>)
                                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                      130)
                                                                   ((Prelude..)
                                                                      (\ bs
                                                                         -> (Data.Monoid.<>)
                                                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                 (Prelude.fromIntegral
                                                                                    (Data.ByteString.length
                                                                                       bs)))
                                                                              (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                 bs))
                                                                      Data.Text.Encoding.encodeUtf8
                                                                      _v))
                                                          ((Data.Monoid.<>)
                                                             (let
                                                                _v
                                                                  = Lens.Family2.view
                                                                      (Data.ProtoLens.Field.field
                                                                         @"minioRegion")
                                                                      _x
                                                              in
                                                                if (Prelude.==)
                                                                     _v
                                                                     Data.ProtoLens.fieldDefault then
                                                                    Data.Monoid.mempty
                                                                else
                                                                    (Data.Monoid.<>)
                                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                         138)
                                                                      ((Prelude..)
                                                                         (\ bs
                                                                            -> (Data.Monoid.<>)
                                                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                    (Prelude.fromIntegral
                                                                                       (Data.ByteString.length
                                                                                          bs)))
                                                                                 (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                    bs))
                                                                         Data.Text.Encoding.encodeUtf8
                                                                         _v))
                                                             ((Data.Monoid.<>)
                                                                (let
                                                                   _v
                                                                     = Lens.Family2.view
                                                                         (Data.ProtoLens.Field.field
                                                                            @"minioAccessKey")
                                                                         _x
                                                                 in
                                                                   if (Prelude.==)
                                                                        _v
                                                                        Data.ProtoLens.fieldDefault then
                                                                       Data.Monoid.mempty
                                                                   else
                                                                       (Data.Monoid.<>)
                                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                            146)
                                                                         ((Prelude..)
                                                                            (\ bs
                                                                               -> (Data.Monoid.<>)
                                                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                       (Prelude.fromIntegral
                                                                                          (Data.ByteString.length
                                                                                             bs)))
                                                                                    (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                       bs))
                                                                            Data.Text.Encoding.encodeUtf8
                                                                            _v))
                                                                ((Data.Monoid.<>)
                                                                   (let
                                                                      _v
                                                                        = Lens.Family2.view
                                                                            (Data.ProtoLens.Field.field
                                                                               @"minioSecretKey")
                                                                            _x
                                                                    in
                                                                      if (Prelude.==)
                                                                           _v
                                                                           Data.ProtoLens.fieldDefault then
                                                                          Data.Monoid.mempty
                                                                      else
                                                                          (Data.Monoid.<>)
                                                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                               154)
                                                                            ((Prelude..)
                                                                               (\ bs
                                                                                  -> (Data.Monoid.<>)
                                                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                          (Prelude.fromIntegral
                                                                                             (Data.ByteString.length
                                                                                                bs)))
                                                                                       (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                          bs))
                                                                               Data.Text.Encoding.encodeUtf8
                                                                               _v))
                                                                   ((Data.Monoid.<>)
                                                                      (let
                                                                         _v
                                                                           = Lens.Family2.view
                                                                               (Data.ProtoLens.Field.field
                                                                                  @"generatedOutputObjectPrefix")
                                                                               _x
                                                                       in
                                                                         if (Prelude.==)
                                                                              _v
                                                                              Data.ProtoLens.fieldDefault then
                                                                             Data.Monoid.mempty
                                                                         else
                                                                             (Data.Monoid.<>)
                                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                  162)
                                                                               ((Prelude..)
                                                                                  (\ bs
                                                                                     -> (Data.Monoid.<>)
                                                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                             (Prelude.fromIntegral
                                                                                                (Data.ByteString.length
                                                                                                   bs)))
                                                                                          (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                             bs))
                                                                                  Data.Text.Encoding.encodeUtf8
                                                                                  _v))
                                                                      ((Data.Monoid.<>)
                                                                         (case
                                                                              Lens.Family2.view
                                                                                (Data.ProtoLens.Field.field
                                                                                   @"maybe'memoryBudget")
                                                                                _x
                                                                          of
                                                                            Prelude.Nothing
                                                                              -> Data.Monoid.mempty
                                                                            (Prelude.Just _v)
                                                                              -> (Data.Monoid.<>)
                                                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                      170)
                                                                                   ((Prelude..)
                                                                                      (\ bs
                                                                                         -> (Data.Monoid.<>)
                                                                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                                 (Prelude.fromIntegral
                                                                                                    (Data.ByteString.length
                                                                                                       bs)))
                                                                                              (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                                 bs))
                                                                                      Data.ProtoLens.encodeMessage
                                                                                      _v))
                                                                         ((Data.Monoid.<>)
                                                                            (case
                                                                                 Lens.Family2.view
                                                                                   (Data.ProtoLens.Field.field
                                                                                      @"maybe'executionShape")
                                                                                   _x
                                                                             of
                                                                               Prelude.Nothing
                                                                                 -> Data.Monoid.mempty
                                                                               (Prelude.Just _v)
                                                                                 -> (Data.Monoid.<>)
                                                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                         178)
                                                                                      ((Prelude..)
                                                                                         (\ bs
                                                                                            -> (Data.Monoid.<>)
                                                                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                                    (Prelude.fromIntegral
                                                                                                       (Data.ByteString.length
                                                                                                          bs)))
                                                                                                 (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                                    bs))
                                                                                         Data.ProtoLens.encodeMessage
                                                                                         _v))
                                                                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                                               (Lens.Family2.view
                                                                                  Data.ProtoLens.unknownFields
                                                                                  _x)))))))))))))))))))))))
instance Control.DeepSeq.NFData WorkerRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_WorkerRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_WorkerRequest'requestModelId x__)
                (Control.DeepSeq.deepseq
                   (_WorkerRequest'inputText x__)
                   (Control.DeepSeq.deepseq
                      (_WorkerRequest'runtimeMode x__)
                      (Control.DeepSeq.deepseq
                         (_WorkerRequest'selectedEngine x__)
                         (Control.DeepSeq.deepseq
                            (_WorkerRequest'adapterId x__)
                            (Control.DeepSeq.deepseq
                               (_WorkerRequest'engineInstallRoot x__)
                               (Control.DeepSeq.deepseq
                                  (_WorkerRequest'displayName x__)
                                  (Control.DeepSeq.deepseq
                                     (_WorkerRequest'family x__)
                                     (Control.DeepSeq.deepseq
                                        (_WorkerRequest'artifactType x__)
                                        (Control.DeepSeq.deepseq
                                           (_WorkerRequest'runtimeLane x__)
                                           (Control.DeepSeq.deepseq
                                              (_WorkerRequest'inputObjectRef x__)
                                              (Control.DeepSeq.deepseq
                                                 (_WorkerRequest'modelCacheRoot x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_WorkerRequest'modelCacheQuotaBytes x__)
                                                    (Control.DeepSeq.deepseq
                                                       (_WorkerRequest'minioEndpoint x__)
                                                       (Control.DeepSeq.deepseq
                                                          (_WorkerRequest'minioModelsBucket x__)
                                                          (Control.DeepSeq.deepseq
                                                             (_WorkerRequest'minioDemoArtifactsBucket
                                                                x__)
                                                             (Control.DeepSeq.deepseq
                                                                (_WorkerRequest'minioRegion x__)
                                                                (Control.DeepSeq.deepseq
                                                                   (_WorkerRequest'minioAccessKey
                                                                      x__)
                                                                   (Control.DeepSeq.deepseq
                                                                      (_WorkerRequest'minioSecretKey
                                                                         x__)
                                                                      (Control.DeepSeq.deepseq
                                                                         (_WorkerRequest'generatedOutputObjectPrefix
                                                                            x__)
                                                                         (Control.DeepSeq.deepseq
                                                                            (_WorkerRequest'memoryBudget
                                                                               x__)
                                                                            (Control.DeepSeq.deepseq
                                                                               (_WorkerRequest'executionShape
                                                                                  x__)
                                                                               ()))))))))))))))))))))))
{- | Fields :
     
         * 'Proto.Infernix.Runtime.Inference_Fields.outputText' @:: Lens' WorkerResponse Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.errorCode' @:: Lens' WorkerResponse Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.errorMessage' @:: Lens' WorkerResponse Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.objectRef' @:: Lens' WorkerResponse Data.Text.Text@
         * 'Proto.Infernix.Runtime.Inference_Fields.ceilingAcknowledgement' @:: Lens' WorkerResponse CeilingAcknowledgement@
         * 'Proto.Infernix.Runtime.Inference_Fields.maybe'ceilingAcknowledgement' @:: Lens' WorkerResponse (Prelude.Maybe CeilingAcknowledgement)@ -}
data WorkerResponse
  = WorkerResponse'_constructor {_WorkerResponse'outputText :: !Data.Text.Text,
                                 _WorkerResponse'errorCode :: !Data.Text.Text,
                                 _WorkerResponse'errorMessage :: !Data.Text.Text,
                                 _WorkerResponse'objectRef :: !Data.Text.Text,
                                 _WorkerResponse'ceilingAcknowledgement :: !(Prelude.Maybe CeilingAcknowledgement),
                                 _WorkerResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show WorkerResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField WorkerResponse "outputText" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerResponse'outputText
           (\ x__ y__ -> x__ {_WorkerResponse'outputText = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerResponse "errorCode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerResponse'errorCode
           (\ x__ y__ -> x__ {_WorkerResponse'errorCode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerResponse "errorMessage" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerResponse'errorMessage
           (\ x__ y__ -> x__ {_WorkerResponse'errorMessage = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerResponse "objectRef" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerResponse'objectRef
           (\ x__ y__ -> x__ {_WorkerResponse'objectRef = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WorkerResponse "ceilingAcknowledgement" CeilingAcknowledgement where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerResponse'ceilingAcknowledgement
           (\ x__ y__ -> x__ {_WorkerResponse'ceilingAcknowledgement = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField WorkerResponse "maybe'ceilingAcknowledgement" (Prelude.Maybe CeilingAcknowledgement) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WorkerResponse'ceilingAcknowledgement
           (\ x__ y__ -> x__ {_WorkerResponse'ceilingAcknowledgement = y__}))
        Prelude.id
instance Data.ProtoLens.Message WorkerResponse where
  messageName _ = Data.Text.pack "infernix.runtime.WorkerResponse"
  packedMessageDescriptor _
    = "\n\
      \\SOWorkerResponse\DC2\US\n\
      \\voutput_text\CAN\SOH \SOH(\tR\n\
      \outputText\DC2\GS\n\
      \\n\
      \error_code\CAN\STX \SOH(\tR\terrorCode\DC2#\n\
      \\rerror_message\CAN\ETX \SOH(\tR\ferrorMessage\DC2\GS\n\
      \\n\
      \object_ref\CAN\EOT \SOH(\tR\tobjectRef\DC2a\n\
      \\ETBceiling_acknowledgement\CAN\ENQ \SOH(\v2(.infernix.runtime.CeilingAcknowledgementR\SYNceilingAcknowledgement"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        outputText__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "output_text"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"outputText")) ::
              Data.ProtoLens.FieldDescriptor WorkerResponse
        errorCode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_code"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"errorCode")) ::
              Data.ProtoLens.FieldDescriptor WorkerResponse
        errorMessage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_message"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"errorMessage")) ::
              Data.ProtoLens.FieldDescriptor WorkerResponse
        objectRef__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "object_ref"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"objectRef")) ::
              Data.ProtoLens.FieldDescriptor WorkerResponse
        ceilingAcknowledgement__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "ceiling_acknowledgement"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CeilingAcknowledgement)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'ceilingAcknowledgement")) ::
              Data.ProtoLens.FieldDescriptor WorkerResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, outputText__field_descriptor),
           (Data.ProtoLens.Tag 2, errorCode__field_descriptor),
           (Data.ProtoLens.Tag 3, errorMessage__field_descriptor),
           (Data.ProtoLens.Tag 4, objectRef__field_descriptor),
           (Data.ProtoLens.Tag 5, ceilingAcknowledgement__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _WorkerResponse'_unknownFields
        (\ x__ y__ -> x__ {_WorkerResponse'_unknownFields = y__})
  defMessage
    = WorkerResponse'_constructor
        {_WorkerResponse'outputText = Data.ProtoLens.fieldDefault,
         _WorkerResponse'errorCode = Data.ProtoLens.fieldDefault,
         _WorkerResponse'errorMessage = Data.ProtoLens.fieldDefault,
         _WorkerResponse'objectRef = Data.ProtoLens.fieldDefault,
         _WorkerResponse'ceilingAcknowledgement = Prelude.Nothing,
         _WorkerResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          WorkerResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser WorkerResponse
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
                                       "output_text"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"outputText") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "error_code"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"errorCode") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "error_message"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"errorMessage") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "object_ref"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"objectRef") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "ceiling_acknowledgement"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"ceilingAcknowledgement") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "WorkerResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"outputText") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"errorCode") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"errorMessage") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"objectRef") _x
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
                         (case
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'ceilingAcknowledgement") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                   ((Prelude..)
                                      (\ bs
                                         -> (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                 (Prelude.fromIntegral (Data.ByteString.length bs)))
                                              (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                      Data.ProtoLens.encodeMessage _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData WorkerResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_WorkerResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_WorkerResponse'outputText x__)
                (Control.DeepSeq.deepseq
                   (_WorkerResponse'errorCode x__)
                   (Control.DeepSeq.deepseq
                      (_WorkerResponse'errorMessage x__)
                      (Control.DeepSeq.deepseq
                         (_WorkerResponse'objectRef x__)
                         (Control.DeepSeq.deepseq
                            (_WorkerResponse'ceilingAcknowledgement x__) ())))))
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \ infernix/runtime/inference.proto\DC2\DLEinfernix.runtime\"W\n\
    \\fRequestField\DC2\DC2\n\
    \\EOTname\CAN\SOH \SOH(\tR\EOTname\DC2\DC4\n\
    \\ENQlabel\CAN\STX \SOH(\tR\ENQlabel\DC2\GS\n\
    \\n\
    \field_type\CAN\ETX \SOH(\tR\tfieldType\"\136\EOT\n\
    \\fCatalogEntry\DC2\"\n\
    \\rmatrix_row_id\CAN\SOH \SOH(\tR\vmatrixRowId\DC2\EM\n\
    \\bmodel_id\CAN\STX \SOH(\tR\amodelId\DC2!\n\
    \\fdisplay_name\CAN\ETX \SOH(\tR\vdisplayName\DC2\SYN\n\
    \\ACKfamily\CAN\EOT \SOH(\tR\ACKfamily\DC2 \n\
    \\vdescription\CAN\ENQ \SOH(\tR\vdescription\DC2#\n\
    \\rartifact_type\CAN\ACK \SOH(\tR\fartifactType\DC2'\n\
    \\SIreference_model\CAN\a \SOH(\tR\SOreferenceModel\DC2!\n\
    \\fdownload_url\CAN\b \SOH(\tR\vdownloadUrl\DC2'\n\
    \\SIselected_engine\CAN\t \SOH(\tR\SOselectedEngine\DC2C\n\
    \\rrequest_shape\CAN\n\
    \ \ETX(\v2\RS.infernix.runtime.RequestFieldR\frequestShape\DC2!\n\
    \\fruntime_mode\CAN\v \SOH(\tR\vruntimeMode\DC2!\n\
    \\fruntime_lane\CAN\f \SOH(\tR\vruntimeLane\DC2!\n\
    \\frequires_gpu\CAN\r \SOH(\bR\vrequiresGpu\DC2\DC4\n\
    \\ENQnotes\CAN\SO \SOH(\tR\ENQnotes\"\183\SOH\n\
    \\rEngineBinding\DC2\SYN\n\
    \\ACKengine\CAN\SOH \SOH(\tR\ACKengine\DC2\GS\n\
    \\n\
    \adapter_id\CAN\STX \SOH(\tR\tadapterId\DC2!\n\
    \\fadapter_type\CAN\ETX \SOH(\tR\vadapterType\DC2'\n\
    \\SIadapter_locator\CAN\EOT \SOH(\tR\SOadapterLocator\DC2#\n\
    \\rpython_native\CAN\ENQ \SOH(\bR\fpythonNative\"\154\ETX\n\
    \\DLEGeneratedCatalog\DC2!\n\
    \\fruntime_mode\CAN\SOH \SOH(\tR\vruntimeMode\DC2\ESC\n\
    \\tedge_port\CAN\STX \SOH(\ENQR\bedgePort\DC2&\n\
    \\SIconfig_map_name\CAN\ETX \SOH(\tR\rconfigMapName\DC2%\n\
    \\SOgenerated_path\CAN\EOT \SOH(\tR\rgeneratedPath\DC2!\n\
    \\fmounted_path\CAN\ENQ \SOH(\tR\vmountedPath\DC26\n\
    \\ACKmodels\CAN\ACK \ETX(\v2\RS.infernix.runtime.CatalogEntryR\ACKmodels\DC2\ETB\n\
    \\ademo_ui\CAN\a \SOH(\bR\ACKdemoUi\DC2%\n\
    \\SOrequest_topics\CAN\b \ETX(\tR\rrequestTopics\DC2!\n\
    \\fresult_topic\CAN\t \SOH(\tR\vresultTopic\DC29\n\
    \\aengines\CAN\n\
    \ \ETX(\v2\US.infernix.runtime.EngineBindingR\aengines\"\226\ETX\n\
    \\DLEInferenceRequest\DC2\GS\n\
    \\n\
    \request_id\CAN\SOH \SOH(\tR\trequestId\DC2(\n\
    \\DLErequest_model_id\CAN\STX \SOH(\tR\SOrequestModelId\DC2\GS\n\
    \\n\
    \input_text\CAN\ETX \SOH(\tR\tinputText\DC2!\n\
    \\fruntime_mode\CAN\EOT \SOH(\tR\vruntimeMode\DC2\ETB\n\
    \\auser_id\CAN\ENQ \SOH(\tR\ACKuserId\DC2\GS\n\
    \\n\
    \context_id\CAN\ACK \SOH(\tR\tcontextId\DC23\n\
    \\SYNuser_prompt_message_id\CAN\a \SOH(\tR\DC3userPromptMessageId\DC24\n\
    \\SYNclient_idempotency_key\CAN\b \SOH(\tR\DC4clientIdempotencyKey\DC26\n\
    \\ETBconversation_log_offset\CAN\t \SOH(\ETXR\NAKconversationLogOffset\DC2\US\n\
    \\vprefix_hash\CAN\n\
    \ \SOH(\tR\n\
    \prefixHash\DC2\GS\n\
    \\n\
    \causal_ref\CAN\v \SOH(\tR\tcausalRef\DC2(\n\
    \\DLEinput_object_ref\CAN\f \SOH(\tR\SOinputObjectRef\"\241\a\n\
    \\rWorkerRequest\DC2(\n\
    \\DLErequest_model_id\CAN\SOH \SOH(\tR\SOrequestModelId\DC2\GS\n\
    \\n\
    \input_text\CAN\STX \SOH(\tR\tinputText\DC2!\n\
    \\fruntime_mode\CAN\ETX \SOH(\tR\vruntimeMode\DC2'\n\
    \\SIselected_engine\CAN\EOT \SOH(\tR\SOselectedEngine\DC2\GS\n\
    \\n\
    \adapter_id\CAN\ENQ \SOH(\tR\tadapterId\DC2.\n\
    \\DC3engine_install_root\CAN\ACK \SOH(\tR\DC1engineInstallRoot\DC2!\n\
    \\fdisplay_name\CAN\a \SOH(\tR\vdisplayName\DC2\SYN\n\
    \\ACKfamily\CAN\b \SOH(\tR\ACKfamily\DC2#\n\
    \\rartifact_type\CAN\t \SOH(\tR\fartifactType\DC2!\n\
    \\fruntime_lane\CAN\n\
    \ \SOH(\tR\vruntimeLane\DC2(\n\
    \\DLEinput_object_ref\CAN\v \SOH(\tR\SOinputObjectRef\DC2(\n\
    \\DLEmodel_cache_root\CAN\f \SOH(\tR\SOmodelCacheRoot\DC25\n\
    \\ETBmodel_cache_quota_bytes\CAN\r \SOH(\EOTR\DC4modelCacheQuotaBytes\DC2%\n\
    \\SOminio_endpoint\CAN\SO \SOH(\tR\rminioEndpoint\DC2.\n\
    \\DC3minio_models_bucket\CAN\SI \SOH(\tR\DC1minioModelsBucket\DC2=\n\
    \\ESCminio_demo_artifacts_bucket\CAN\DLE \SOH(\tR\CANminioDemoArtifactsBucket\DC2!\n\
    \\fminio_region\CAN\DC1 \SOH(\tR\vminioRegion\DC2(\n\
    \\DLEminio_access_key\CAN\DC2 \SOH(\tR\SOminioAccessKey\DC2(\n\
    \\DLEminio_secret_key\CAN\DC3 \SOH(\tR\SOminioSecretKey\DC2C\n\
    \\RSgenerated_output_object_prefix\CAN\DC4 \SOH(\tR\ESCgeneratedOutputObjectPrefix\DC2L\n\
    \\rmemory_budget\CAN\NAK \SOH(\v2'.infernix.runtime.InferenceMemoryBudgetR\fmemoryBudget\DC2N\n\
    \\SIexecution_shape\CAN\SYN \SOH(\v2%.infernix.runtime.ModelExecutionShapeR\SOexecutionShape\"\188\SOH\n\
    \\NAKInferenceMemoryBudget\DC2J\n\
    \\rhost_resident\CAN\SOH \SOH(\v2#.infernix.runtime.HostResidentClaimH\NULR\fhostResident\DC2N\n\
    \\SIhost_and_device\CAN\STX \SOH(\v2$.infernix.runtime.HostAndDeviceClaimH\NULR\rhostAndDeviceB\a\n\
    \\ENQclaim\".\n\
    \\DC1HostResidentClaim\DC2\EM\n\
    \\bhost_mib\CAN\SOH \SOH(\ETXR\ahostMib\"N\n\
    \\DC2HostAndDeviceClaim\DC2\EM\n\
    \\bhost_mib\CAN\SOH \SOH(\ETXR\ahostMib\DC2\GS\n\
    \\n\
    \device_mib\CAN\STX \SOH(\ETXR\tdeviceMib\"\239\SOH\n\
    \\DC3ModelExecutionShape\DC2%\n\
    \\SOcontext_length\CAN\SOH \SOH(\ETXR\rcontextLength\DC2\GS\n\
    \\n\
    \batch_size\CAN\STX \SOH(\ETXR\tbatchSize\DC2)\n\
    \\DLEgeneration_bound\CAN\ETX \SOH(\ETXR\SIgenerationBound\DC2.\n\
    \\DC3cache_element_width\CAN\EOT \SOH(\ETXR\DC1cacheElementWidth\DC27\n\
    \\CANstream_weights_to_device\CAN\ENQ \SOH(\bR\NAKstreamWeightsToDevice\"\247\SOH\n\
    \\SOWorkerResponse\DC2\US\n\
    \\voutput_text\CAN\SOH \SOH(\tR\n\
    \outputText\DC2\GS\n\
    \\n\
    \error_code\CAN\STX \SOH(\tR\terrorCode\DC2#\n\
    \\rerror_message\CAN\ETX \SOH(\tR\ferrorMessage\DC2\GS\n\
    \\n\
    \object_ref\CAN\EOT \SOH(\tR\tobjectRef\DC2a\n\
    \\ETBceiling_acknowledgement\CAN\ENQ \SOH(\v2(.infernix.runtime.CeilingAcknowledgementR\SYNceilingAcknowledgement\"V\n\
    \\SYNCeilingAcknowledgement\DC2\GS\n\
    \\n\
    \soft_bytes\CAN\SOH \SOH(\ETXR\tsoftBytes\DC2\GS\n\
    \\n\
    \hard_bytes\CAN\STX \SOH(\ETXR\thardBytes\"\174\SOH\n\
    \\rResultPayload\DC2%\n\
    \\rinline_output\CAN\SOH \SOH(\tH\NULR\finlineOutput\DC2\US\n\
    \\n\
    \object_ref\CAN\STX \SOH(\tH\NULR\tobjectRef\DC2K\n\
    \\SIinference_error\CAN\ETX \SOH(\v2 .infernix.runtime.InferenceErrorH\NULR\SOinferenceErrorB\b\n\
    \\ACKoutput\"\251\SOH\n\
    \\SOInferenceError\DC2k\n\
    \\ESCmodel_memory_limit_exceeded\CAN\SOH \SOH(\v2*.infernix.runtime.ModelMemoryLimitExceededH\NULR\CANmodelMemoryLimitExceeded\DC2s\n\
    \\GSmodel_requirement_underivable\CAN\STX \SOH(\v2-.infernix.runtime.ModelRequirementUnderivableH\NULR\ESCmodelRequirementUnderivableB\a\n\
    \\ENQerror\"u\n\
    \\ESCModelRequirementUnderivable\DC2\EM\n\
    \\bmodel_id\CAN\SOH \SOH(\tR\amodelId\DC2#\n\
    \\rartifact_type\CAN\STX \SOH(\tR\fartifactType\DC2\SYN\n\
    \\ACKreason\CAN\ETX \SOH(\tR\ACKreason\"\177\SOH\n\
    \\CANModelMemoryLimitExceeded\DC2\EM\n\
    \\bmodel_id\CAN\SOH \SOH(\tR\amodelId\DC2!\n\
    \\frequired_mib\CAN\STX \SOH(\ENQR\vrequiredMib\DC2#\n\
    \\ravailable_mib\CAN\ETX \SOH(\ENQR\favailableMib\DC2\SUB\n\
    \\bresource\CAN\EOT \SOH(\tR\bresource\DC2\SYN\n\
    \\ACKsource\CAN\ENQ \SOH(\tR\ACKsource\"\145\ETX\n\
    \\SIInferenceResult\DC2\GS\n\
    \\n\
    \request_id\CAN\SOH \SOH(\tR\trequestId\DC2&\n\
    \\SIresult_model_id\CAN\STX \SOH(\tR\rresultModelId\DC2\"\n\
    \\rmatrix_row_id\CAN\ETX \SOH(\tR\vmatrixRowId\DC2!\n\
    \\fruntime_mode\CAN\EOT \SOH(\tR\vruntimeMode\DC2'\n\
    \\SIselected_engine\CAN\ENQ \SOH(\tR\SOselectedEngine\DC2\SYN\n\
    \\ACKstatus\CAN\ACK \SOH(\tR\ACKstatus\DC29\n\
    \\apayload\CAN\a \SOH(\v2\US.infernix.runtime.ResultPayloadR\apayload\DC2\GS\n\
    \\n\
    \created_at\CAN\b \SOH(\tR\tcreatedAt\DC2\GS\n\
    \\n\
    \causal_ref\CAN\t \SOH(\tR\tcausalRef\DC2\ETB\n\
    \\auser_id\CAN\n\
    \ \SOH(\tR\ACKuserId\DC2\GS\n\
    \\n\
    \context_id\CAN\v \SOH(\tR\tcontextId\"H\n\
    \\rErrorResponse\DC2\GS\n\
    \\n\
    \error_code\CAN\SOH \SOH(\tR\terrorCode\DC2\CAN\n\
    \\amessage\CAN\STX \SOH(\tR\amessageJ\171]\n\
    \\a\DC2\ENQ\NUL\NUL\253\SOH\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\EM\n\
    \\n\
    \\n\
    \\STX\EOT\NUL\DC2\EOT\EOT\NUL\b\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\EOT\b\DC4\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\ENQ\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\ENQ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\ENQ\t\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\ENQ\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\ACK\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\ACK\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\ACK\t\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\ACK\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\a\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\a\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\a\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\a\SYN\ETB\n\
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\n\
    \\NUL\EM\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\n\
    \\b\DC4\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\v\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\v\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\v\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\v\EM\SUB\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX\f\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX\f\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX\f\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX\f\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETX\r\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ENQ\DC2\ETX\r\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETX\r\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETX\r\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ETX\DC2\ETX\SO\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ENQ\DC2\ETX\SO\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\SOH\DC2\ETX\SO\t\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ETX\DC2\ETX\SO\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\EOT\DC2\ETX\SI\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ENQ\DC2\ETX\SI\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\SOH\DC2\ETX\SI\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ETX\DC2\ETX\SI\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ENQ\DC2\ETX\DLE\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ENQ\ENQ\DC2\ETX\DLE\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ENQ\SOH\DC2\ETX\DLE\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ENQ\ETX\DC2\ETX\DLE\EM\SUB\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ACK\DC2\ETX\DC1\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ACK\ENQ\DC2\ETX\DC1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ACK\SOH\DC2\ETX\DC1\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ACK\ETX\DC2\ETX\DC1\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\a\DC2\ETX\DC2\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\a\ENQ\DC2\ETX\DC2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\a\SOH\DC2\ETX\DC2\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\a\ETX\DC2\ETX\DC2\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\b\DC2\ETX\DC3\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\b\ENQ\DC2\ETX\DC3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\b\SOH\DC2\ETX\DC3\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\b\ETX\DC2\ETX\DC3\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\t\DC2\ETX\DC4\STX+\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\EOT\DC2\ETX\DC4\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\ACK\DC2\ETX\DC4\v\ETB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\SOH\DC2\ETX\DC4\CAN%\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\ETX\DC2\ETX\DC4(*\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\n\
    \\DC2\ETX\NAK\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\n\
    \\ENQ\DC2\ETX\NAK\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\n\
    \\SOH\DC2\ETX\NAK\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\n\
    \\ETX\DC2\ETX\NAK\CAN\SUB\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\v\DC2\ETX\SYN\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\v\ENQ\DC2\ETX\SYN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\v\SOH\DC2\ETX\SYN\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\v\ETX\DC2\ETX\SYN\CAN\SUB\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\f\DC2\ETX\ETB\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\f\ENQ\DC2\ETX\ETB\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\f\SOH\DC2\ETX\ETB\a\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\f\ETX\DC2\ETX\ETB\SYN\CAN\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\r\DC2\ETX\CAN\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\r\ENQ\DC2\ETX\CAN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\r\SOH\DC2\ETX\CAN\t\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\r\ETX\DC2\ETX\CAN\DC1\DC3\n\
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT\ESC\NUL!\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\ESC\b\NAK\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\FS\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\FS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\FS\t\SI\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\FS\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\GS\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\GS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\GS\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\GS\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\RS\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\RS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\RS\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\RS\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ETX\DC2\ETX\US\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\ETX\US\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\ETX\US\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\EOT\DC2\ETX \STX\EM\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\ETX \STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\ETX \a\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\ETX \ETB\CAN\n\
    \\n\
    \\n\
    \\STX\EOT\ETX\DC2\EOT#\NUL.\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX#\b\CAN\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX$\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX$\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX$\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX$\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX%\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX%\STX\a\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX%\b\DC1\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX%\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX&\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX&\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX&\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX&\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX'\STX\FS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX'\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX'\t\ETB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX'\SUB\ESC\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX(\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX(\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX(\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX(\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ENQ\DC2\ETX)\STX#\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\EOT\DC2\ETX)\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ACK\DC2\ETX)\v\ETB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\SOH\DC2\ETX)\CAN\RS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ETX\DC2\ETX)!\"\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ACK\DC2\ETX*\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\ENQ\DC2\ETX*\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\SOH\DC2\ETX*\a\SO\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\ETX\DC2\ETX*\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\a\DC2\ETX+\STX%\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\EOT\DC2\ETX+\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\ENQ\DC2\ETX+\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\SOH\DC2\ETX+\DC2 \n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\ETX\DC2\ETX+#$\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\b\DC2\ETX,\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\b\ENQ\DC2\ETX,\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\b\SOH\DC2\ETX,\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\b\ETX\DC2\ETX,\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\t\DC2\ETX-\STX&\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\t\EOT\DC2\ETX-\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\t\ACK\DC2\ETX-\v\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\t\SOH\DC2\ETX-\EM \n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\t\ETX\DC2\ETX-#%\n\
    \\n\
    \\n\
    \\STX\EOT\EOT\DC2\EOT0\NULI\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX0\b\CAN\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX1\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX1\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX1\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX2\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX2\t\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX2\FS\GS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\STX\DC2\ETX3\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ENQ\DC2\ETX3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\ETX3\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\ETX3\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ETX\DC2\ETX4\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ENQ\DC2\ETX4\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\SOH\DC2\ETX4\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ETX\DC2\ETX4\CAN\EM\n\
    \\129\EOT\n\
    \\EOT\EOT\EOT\STX\EOT\DC2\ETX<\STX\NAK\SUB\243\ETX Phase 7 Sprint 7.8: typed envelope fields for the durable-context\n\
    \ dispatcher. user_id + context_id address the engine's result writeback\n\
    \ and per-user MinIO scoping. user_prompt_message_id is the conversation-\n\
    \ log MessageId that both producer-side dedup (on inference.request.<mode>)\n\
    \ and causal reference (carried through on inference.result.<mode>) use.\n\
    \ conversation_log_offset + prefix_hash let the engine verify KV cache\n\
    \ consistency before reuse; on hash mismatch it rebuilds from the log.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\ENQ\DC2\ETX<\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\SOH\DC2\ETX<\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\ETX\DC2\ETX<\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ENQ\DC2\ETX=\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ENQ\ENQ\DC2\ETX=\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ENQ\SOH\DC2\ETX=\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ENQ\ETX\DC2\ETX=\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ACK\DC2\ETX>\STX$\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ACK\ENQ\DC2\ETX>\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ACK\SOH\DC2\ETX>\t\US\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ACK\ETX\DC2\ETX>\"#\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\a\DC2\ETX?\STX$\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\a\ENQ\DC2\ETX?\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\a\SOH\DC2\ETX?\t\US\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\a\ETX\DC2\ETX?\"#\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\b\DC2\ETX@\STX$\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\b\ENQ\DC2\ETX@\STX\a\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\b\SOH\DC2\ETX@\b\US\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\b\ETX\DC2\ETX@\"#\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\t\DC2\ETXA\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\t\ENQ\DC2\ETXA\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\t\SOH\DC2\ETXA\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\t\ETX\DC2\ETXA\ETB\EM\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\n\
    \\DC2\ETXB\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\n\
    \\ENQ\DC2\ETXB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\n\
    \\SOH\DC2\ETXB\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\n\
    \\ETX\DC2\ETXB\SYN\CAN\n\
    \\196\STX\n\
    \\EOT\EOT\EOT\STX\v\DC2\ETXH\STX\US\SUB\182\STX Phase 4 Sprint 4.15: non-text input for the audio and image input\n\
    \ families (speech, source separation, audio-to-MIDI, music\n\
    \ transcription, OMR). Carries an infernix-demo-objects object\n\
    \ reference (bucket/key) the engine adapter reads instead of\n\
    \ input_text; text families leave it empty and use input_text.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\v\ENQ\DC2\ETXH\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\v\SOH\DC2\ETXH\t\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\v\ETX\DC2\ETXH\FS\RS\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOTK\NULv\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETXK\b\NAK\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETXL\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\ETXL\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETXL\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETXL\FS\GS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETXM\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ENQ\DC2\ETXM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETXM\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETXM\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETXN\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ENQ\DC2\ETXN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETXN\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETXN\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\ETXO\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ENQ\DC2\ETXO\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\ETXO\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\ETXO\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\EOT\DC2\ETXP\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ENQ\DC2\ETXP\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\SOH\DC2\ETXP\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ETX\DC2\ETXP\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ENQ\DC2\ETXQ\STX!\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ENQ\ENQ\DC2\ETXQ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ENQ\SOH\DC2\ETXQ\t\FS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ENQ\ETX\DC2\ETXQ\US \n\
    \\221\STX\n\
    \\EOT\EOT\ENQ\STX\ACK\DC2\ETXW\STX\SUB\SUB\207\STX Phase 7 Sprint 7.7: model metadata used to be loaded by adapters\n\
    \ from synthetic JSON files staged under ./.data/object-store/; the\n\
    \ supported target reads it straight off the wire from the daemon's\n\
    \ already-loaded substrate .dhall catalog and pulls actual weights\n\
    \ from MinIO infernix-models via adapters/model_cache.get_model_path.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ACK\ENQ\DC2\ETXW\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ACK\SOH\DC2\ETXW\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ACK\ETX\DC2\ETXW\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\a\DC2\ETXX\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\ENQ\DC2\ETXX\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\SOH\DC2\ETXX\t\SI\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\ETX\DC2\ETXX\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\b\DC2\ETXY\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\b\ENQ\DC2\ETXY\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\b\SOH\DC2\ETXY\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\b\ETX\DC2\ETXY\EM\SUB\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\t\DC2\ETXZ\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\t\ENQ\DC2\ETXZ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\t\SOH\DC2\ETXZ\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\t\ETX\DC2\ETXZ\CAN\SUB\n\
    \\179\SOH\n\
    \\EOT\EOT\ENQ\STX\n\
    \\DC2\ETX^\STX\US\SUB\165\SOH Phase 4 Sprint 4.15: non-text input object reference handed to the\n\
    \ adapter for the audio and image input families. Empty for text\n\
    \ families, which use input_text.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\n\
    \\ENQ\DC2\ETX^\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\n\
    \\SOH\DC2\ETX^\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\n\
    \\ETX\DC2\ETX^\FS\RS\n\
    \\230\STX\n\
    \\EOT\EOT\ENQ\STX\v\DC2\ETXd\STX\US\SUB\216\STX Phase 7 Sprint 7.7 / Phase 4 real-engine follow-on: typed cache\n\
    \ and MinIO wiring decoded by the Haskell engine daemon from the\n\
    \ mounted ClusterConfig + SecretsConfig and passed over the private\n\
    \ worker stdin boundary. Python adapters call adapters.model_cache.configure()\n\
    \ from these fields before get_model_path() or object upload/download.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\v\ENQ\DC2\ETXd\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\v\SOH\DC2\ETXd\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\v\ETX\DC2\ETXd\FS\RS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\f\DC2\ETXe\STX&\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\f\ENQ\DC2\ETXe\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\f\SOH\DC2\ETXe\t \n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\f\ETX\DC2\ETXe#%\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\r\DC2\ETXf\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\r\ENQ\DC2\ETXf\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\r\SOH\DC2\ETXf\t\ETB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\r\ETX\DC2\ETXf\SUB\FS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SO\DC2\ETXg\STX\"\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SO\ENQ\DC2\ETXg\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SO\SOH\DC2\ETXg\t\FS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SO\ETX\DC2\ETXg\US!\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SI\DC2\ETXh\STX*\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SI\ENQ\DC2\ETXh\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SI\SOH\DC2\ETXh\t$\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SI\ETX\DC2\ETXh')\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\DLE\DC2\ETXi\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DLE\ENQ\DC2\ETXi\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DLE\SOH\DC2\ETXi\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DLE\ETX\DC2\ETXi\CAN\SUB\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\DC1\DC2\ETXj\STX\US\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC1\ENQ\DC2\ETXj\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC1\SOH\DC2\ETXj\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC1\ETX\DC2\ETXj\FS\RS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\DC2\DC2\ETXk\STX\US\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC2\ENQ\DC2\ETXk\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC2\SOH\DC2\ETXk\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC2\ETX\DC2\ETXk\FS\RS\n\
    \\228\SOH\n\
    \\EOT\EOT\ENQ\STX\DC3\DC2\ETXo\STX-\SUB\214\SOH Phase 7 Sprint 7.28: Haskell-derived object-key prefix for generated\n\
    \ artifact uploads. Artifact adapters and native-runner upload paths must\n\
    \ write under this prefix and fail closed when it is absent or invalid.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC3\ENQ\DC2\ETXo\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC3\SOH\DC2\ETXo\t'\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC3\ETX\DC2\ETXo*,\n\
    \\255\SOH\n\
    \\EOT\EOT\ENQ\STX\DC4\DC2\ETXt\STX+\SUB\241\SOH Phase 4 Sprint 4.42: the admitted quantities and the execution shape the\n\
    \ compiler admitted this model against, carried on the message the engine\n\
    \ already reads. An adapter receives its memory-shaping parameters rather\n\
    \ than choosing them.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC4\ACK\DC2\ETXt\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC4\SOH\DC2\ETXt\CAN%\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\DC4\ETX\DC2\ETXt(*\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NAK\DC2\ETXu\STX+\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NAK\ACK\DC2\ETXu\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NAK\SOH\DC2\ETXu\SYN%\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NAK\ETX\DC2\ETXu(*\n\
    \\166\STX\n\
    \\STX\EOT\ACK\DC2\ENQ}\NUL\130\SOH\SOH\SUB\152\STX Phase 4 Sprint 4.42: exactly one device route is populated, never both.\n\
    \\n\
    \ A discriminated alternative makes the choice the sender already made visible\n\
    \ to the receiver. Two independent optional fields would let a caller populate\n\
    \ both and let a decoder guess which one meant it.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX}\b\GS\n\
    \\r\n\
    \\EOT\EOT\ACK\b\NUL\DC2\ENQ~\STX\129\SOH\ETX\n\
    \\f\n\
    \\ENQ\EOT\ACK\b\NUL\SOH\DC2\ETX~\b\r\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETX\DEL\EOT(\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\ETX\DEL\EOT\NAK\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETX\DEL\SYN#\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETX\DEL&'\n\
    \\f\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\EOT\128\SOH\EOT+\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\EOT\128\SOH\EOT\SYN\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\EOT\128\SOH\ETB&\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\EOT\128\SOH)*\n\
    \\f\n\
    \\STX\EOT\a\DC2\ACK\132\SOH\NUL\134\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\a\SOH\DC2\EOT\132\SOH\b\EM\n\
    \\f\n\
    \\EOT\EOT\a\STX\NUL\DC2\EOT\133\SOH\STX\NAK\n\
    \\r\n\
    \\ENQ\EOT\a\STX\NUL\ENQ\DC2\EOT\133\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\EOT\133\SOH\b\DLE\n\
    \\r\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\EOT\133\SOH\DC3\DC4\n\
    \\f\n\
    \\STX\EOT\b\DC2\ACK\136\SOH\NUL\139\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\b\SOH\DC2\EOT\136\SOH\b\SUB\n\
    \\f\n\
    \\EOT\EOT\b\STX\NUL\DC2\EOT\137\SOH\STX\NAK\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\ENQ\DC2\EOT\137\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\SOH\DC2\EOT\137\SOH\b\DLE\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\ETX\DC2\EOT\137\SOH\DC3\DC4\n\
    \\f\n\
    \\EOT\EOT\b\STX\SOH\DC2\EOT\138\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\EOT\b\STX\SOH\ENQ\DC2\EOT\138\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\b\STX\SOH\SOH\DC2\EOT\138\SOH\b\DC2\n\
    \\r\n\
    \\ENQ\EOT\b\STX\SOH\ETX\DC2\EOT\138\SOH\NAK\SYN\n\
    \\204\SOH\n\
    \\STX\EOT\t\DC2\ACK\144\SOH\NUL\150\SOH\SOH\SUB\189\SOH The shape the cache term was computed from, carried to the engine so it runs\n\
    \ the execution the model was admitted against rather than a number that was\n\
    \ never compared against a machine.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\t\SOH\DC2\EOT\144\SOH\b\ESC\n\
    \\f\n\
    \\EOT\EOT\t\STX\NUL\DC2\EOT\145\SOH\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\t\STX\NUL\ENQ\DC2\EOT\145\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\t\STX\NUL\SOH\DC2\EOT\145\SOH\b\SYN\n\
    \\r\n\
    \\ENQ\EOT\t\STX\NUL\ETX\DC2\EOT\145\SOH\EM\SUB\n\
    \\f\n\
    \\EOT\EOT\t\STX\SOH\DC2\EOT\146\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\EOT\t\STX\SOH\ENQ\DC2\EOT\146\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\t\STX\SOH\SOH\DC2\EOT\146\SOH\b\DC2\n\
    \\r\n\
    \\ENQ\EOT\t\STX\SOH\ETX\DC2\EOT\146\SOH\NAK\SYN\n\
    \\f\n\
    \\EOT\EOT\t\STX\STX\DC2\EOT\147\SOH\STX\GS\n\
    \\r\n\
    \\ENQ\EOT\t\STX\STX\ENQ\DC2\EOT\147\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\t\STX\STX\SOH\DC2\EOT\147\SOH\b\CAN\n\
    \\r\n\
    \\ENQ\EOT\t\STX\STX\ETX\DC2\EOT\147\SOH\ESC\FS\n\
    \\f\n\
    \\EOT\EOT\t\STX\ETX\DC2\EOT\148\SOH\STX \n\
    \\r\n\
    \\ENQ\EOT\t\STX\ETX\ENQ\DC2\EOT\148\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\t\STX\ETX\SOH\DC2\EOT\148\SOH\b\ESC\n\
    \\r\n\
    \\ENQ\EOT\t\STX\ETX\ETX\DC2\EOT\148\SOH\RS\US\n\
    \\f\n\
    \\EOT\EOT\t\STX\EOT\DC2\EOT\149\SOH\STX$\n\
    \\r\n\
    \\ENQ\EOT\t\STX\EOT\ENQ\DC2\EOT\149\SOH\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT\t\STX\EOT\SOH\DC2\EOT\149\SOH\a\US\n\
    \\r\n\
    \\ENQ\EOT\t\STX\EOT\ETX\DC2\EOT\149\SOH\"#\n\
    \\f\n\
    \\STX\EOT\n\
    \\DC2\ACK\152\SOH\NUL\173\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\n\
    \\SOH\DC2\EOT\152\SOH\b\SYN\n\
    \\f\n\
    \\EOT\EOT\n\
    \\STX\NUL\DC2\EOT\153\SOH\STX\EM\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\NUL\ENQ\DC2\EOT\153\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\NUL\SOH\DC2\EOT\153\SOH\t\DC4\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\NUL\ETX\DC2\EOT\153\SOH\ETB\CAN\n\
    \\f\n\
    \\EOT\EOT\n\
    \\STX\SOH\DC2\EOT\154\SOH\STX\CAN\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\SOH\ENQ\DC2\EOT\154\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\SOH\SOH\DC2\EOT\154\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\SOH\ETX\DC2\EOT\154\SOH\SYN\ETB\n\
    \\f\n\
    \\EOT\EOT\n\
    \\STX\STX\DC2\EOT\155\SOH\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\STX\ENQ\DC2\EOT\155\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\STX\SOH\DC2\EOT\155\SOH\t\SYN\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\STX\ETX\DC2\EOT\155\SOH\EM\SUB\n\
    \\224\STX\n\
    \\EOT\EOT\n\
    \\STX\ETX\DC2\EOT\162\SOH\STX\CAN\SUB\209\STX Phase 4 Sprint 4.15: artifact families (source separation,\n\
    \ audio-to-MIDI, music transcription, image, video, audio generation,\n\
    \ OMR) write their generated bytes to the infernix-demo-objects MinIO\n\
    \ bucket and return the object reference (bucket/key) here. Text\n\
    \ families (LLM, speech transcription) leave it empty and use\n\
    \ output_text.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\ETX\ENQ\DC2\EOT\162\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\ETX\SOH\DC2\EOT\162\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\ETX\ETX\DC2\EOT\162\SOH\SYN\ETB\n\
    \\154\EOT\n\
    \\EOT\EOT\n\
    \\STX\EOT\DC2\EOT\172\SOH\STX5\SUB\139\EOT Phase 4 Sprint 4.42: the conformance acknowledgement.\n\
    \\n\
    \ A limit that was set and a limit the running image fits under are different\n\
    \ claims, and only the second is evidence that this execution is bounded. The\n\
    \ acknowledgement rides this response rather than becoming a handshake: an\n\
    \ adapter that announced its installed limit and waited for permission would\n\
    \ turn a process with exactly one failure mode into one with a protocol state\n\
    \ machine, a second deadline, and a partial-exchange state neither side can\n\
    \ classify.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\EOT\ACK\DC2\EOT\172\SOH\STX\CAN\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\EOT\SOH\DC2\EOT\172\SOH\EM0\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\EOT\ETX\DC2\EOT\172\SOH34\n\
    \\241\ETX\n\
    \\STX\EOT\v\DC2\ACK\183\SOH\NUL\186\SOH\SOH\SUB\226\ETX Phase 4 Sprint 4.42: the two values the engine read back from inside the\n\
    \ process the limit binds, and deliberately nothing else.\n\
    \\n\
    \ The resource is not carried. The only consumer is the worker, which already\n\
    \ holds it in the `InstalledCeiling` it installed, so a field here would be a\n\
    \ second copy of a fact one side derives \226\128\148 and the adapter cannot produce it\n\
    \ without duplicating the lane's resource naming in Python, which is the\n\
    \ two-enumerations defect Sprint 4.38 deleted.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\v\SOH\DC2\EOT\183\SOH\b\RS\n\
    \\f\n\
    \\EOT\EOT\v\STX\NUL\DC2\EOT\184\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\EOT\v\STX\NUL\ENQ\DC2\EOT\184\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\v\STX\NUL\SOH\DC2\EOT\184\SOH\b\DC2\n\
    \\r\n\
    \\ENQ\EOT\v\STX\NUL\ETX\DC2\EOT\184\SOH\NAK\SYN\n\
    \\f\n\
    \\EOT\EOT\v\STX\SOH\DC2\EOT\185\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\EOT\v\STX\SOH\ENQ\DC2\EOT\185\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\v\STX\SOH\SOH\DC2\EOT\185\SOH\b\DC2\n\
    \\r\n\
    \\ENQ\EOT\v\STX\SOH\ETX\DC2\EOT\185\SOH\NAK\SYN\n\
    \\f\n\
    \\STX\EOT\f\DC2\ACK\188\SOH\NUL\194\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\f\SOH\DC2\EOT\188\SOH\b\NAK\n\
    \\SO\n\
    \\EOT\EOT\f\b\NUL\DC2\ACK\189\SOH\STX\193\SOH\ETX\n\
    \\r\n\
    \\ENQ\EOT\f\b\NUL\SOH\DC2\EOT\189\SOH\b\SO\n\
    \\f\n\
    \\EOT\EOT\f\STX\NUL\DC2\EOT\190\SOH\EOT\GS\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\ENQ\DC2\EOT\190\SOH\EOT\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\SOH\DC2\EOT\190\SOH\v\CAN\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\ETX\DC2\EOT\190\SOH\ESC\FS\n\
    \\f\n\
    \\EOT\EOT\f\STX\SOH\DC2\EOT\191\SOH\EOT\SUB\n\
    \\r\n\
    \\ENQ\EOT\f\STX\SOH\ENQ\DC2\EOT\191\SOH\EOT\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\f\STX\SOH\SOH\DC2\EOT\191\SOH\v\NAK\n\
    \\r\n\
    \\ENQ\EOT\f\STX\SOH\ETX\DC2\EOT\191\SOH\CAN\EM\n\
    \\f\n\
    \\EOT\EOT\f\STX\STX\DC2\EOT\192\SOH\EOT'\n\
    \\r\n\
    \\ENQ\EOT\f\STX\STX\ACK\DC2\EOT\192\SOH\EOT\DC2\n\
    \\r\n\
    \\ENQ\EOT\f\STX\STX\SOH\DC2\EOT\192\SOH\DC3\"\n\
    \\r\n\
    \\ENQ\EOT\f\STX\STX\ETX\DC2\EOT\192\SOH%&\n\
    \\f\n\
    \\STX\EOT\r\DC2\ACK\196\SOH\NUL\205\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\r\SOH\DC2\EOT\196\SOH\b\SYN\n\
    \\SO\n\
    \\EOT\EOT\r\b\NUL\DC2\ACK\197\SOH\STX\204\SOH\ETX\n\
    \\r\n\
    \\ENQ\EOT\r\b\NUL\SOH\DC2\EOT\197\SOH\b\r\n\
    \\f\n\
    \\EOT\EOT\r\STX\NUL\DC2\EOT\198\SOH\EOT=\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\ACK\DC2\EOT\198\SOH\EOT\FS\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\SOH\DC2\EOT\198\SOH\GS8\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\ETX\DC2\EOT\198\SOH;<\n\
    \\151\STX\n\
    \\EOT\EOT\r\STX\SOH\DC2\EOT\203\SOH\EOTB\SUB\136\STX Phase 4 Sprint 4.39: a model whose memory requirement could not be\n\
    \ derived from its own artifact is a distinct terminal outcome from one\n\
    \ whose requirement exceeded a limit. It carries no quantity, because the\n\
    \ quantity is exactly what could not be established.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\ACK\DC2\EOT\203\SOH\EOT\US\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\SOH\DC2\EOT\203\SOH =\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\ETX\DC2\EOT\203\SOH@A\n\
    \\f\n\
    \\STX\EOT\SO\DC2\ACK\207\SOH\NUL\211\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\SO\SOH\DC2\EOT\207\SOH\b#\n\
    \\f\n\
    \\EOT\EOT\SO\STX\NUL\DC2\EOT\208\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\NUL\ENQ\DC2\EOT\208\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\NUL\SOH\DC2\EOT\208\SOH\t\DC1\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\NUL\ETX\DC2\EOT\208\SOH\DC4\NAK\n\
    \\f\n\
    \\EOT\EOT\SO\STX\SOH\DC2\EOT\209\SOH\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\SOH\ENQ\DC2\EOT\209\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\SOH\SOH\DC2\EOT\209\SOH\t\SYN\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\SOH\ETX\DC2\EOT\209\SOH\EM\SUB\n\
    \\f\n\
    \\EOT\EOT\SO\STX\STX\DC2\EOT\210\SOH\STX\DC4\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\STX\ENQ\DC2\EOT\210\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\STX\SOH\DC2\EOT\210\SOH\t\SI\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\STX\ETX\DC2\EOT\210\SOH\DC2\DC3\n\
    \\f\n\
    \\STX\EOT\SI\DC2\ACK\213\SOH\NUL\219\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\SI\SOH\DC2\EOT\213\SOH\b \n\
    \\f\n\
    \\EOT\EOT\SI\STX\NUL\DC2\EOT\214\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\NUL\ENQ\DC2\EOT\214\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\NUL\SOH\DC2\EOT\214\SOH\t\DC1\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\NUL\ETX\DC2\EOT\214\SOH\DC4\NAK\n\
    \\f\n\
    \\EOT\EOT\SI\STX\SOH\DC2\EOT\215\SOH\STX\EM\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\SOH\ENQ\DC2\EOT\215\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\SOH\SOH\DC2\EOT\215\SOH\b\DC4\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\SOH\ETX\DC2\EOT\215\SOH\ETB\CAN\n\
    \\f\n\
    \\EOT\EOT\SI\STX\STX\DC2\EOT\216\SOH\STX\SUB\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\STX\ENQ\DC2\EOT\216\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\STX\SOH\DC2\EOT\216\SOH\b\NAK\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\STX\ETX\DC2\EOT\216\SOH\CAN\EM\n\
    \\f\n\
    \\EOT\EOT\SI\STX\ETX\DC2\EOT\217\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\ETX\ENQ\DC2\EOT\217\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\ETX\SOH\DC2\EOT\217\SOH\t\DC1\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\ETX\ETX\DC2\EOT\217\SOH\DC4\NAK\n\
    \\f\n\
    \\EOT\EOT\SI\STX\EOT\DC2\EOT\218\SOH\STX\DC4\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\EOT\ENQ\DC2\EOT\218\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\EOT\SOH\DC2\EOT\218\SOH\t\SI\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\EOT\ETX\DC2\EOT\218\SOH\DC2\DC3\n\
    \\f\n\
    \\STX\EOT\DLE\DC2\ACK\221\SOH\NUL\248\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\DLE\SOH\DC2\EOT\221\SOH\b\ETB\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\NUL\DC2\EOT\222\SOH\STX\CAN\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\NUL\ENQ\DC2\EOT\222\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\NUL\SOH\DC2\EOT\222\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\NUL\ETX\DC2\EOT\222\SOH\SYN\ETB\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\SOH\DC2\EOT\223\SOH\STX\GS\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\SOH\ENQ\DC2\EOT\223\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\SOH\SOH\DC2\EOT\223\SOH\t\CAN\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\SOH\ETX\DC2\EOT\223\SOH\ESC\FS\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\STX\DC2\EOT\224\SOH\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\STX\ENQ\DC2\EOT\224\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\STX\SOH\DC2\EOT\224\SOH\t\SYN\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\STX\ETX\DC2\EOT\224\SOH\EM\SUB\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\ETX\DC2\EOT\225\SOH\STX\SUB\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ETX\ENQ\DC2\EOT\225\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ETX\SOH\DC2\EOT\225\SOH\t\NAK\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ETX\ETX\DC2\EOT\225\SOH\CAN\EM\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\EOT\DC2\EOT\226\SOH\STX\GS\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\EOT\ENQ\DC2\EOT\226\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\EOT\SOH\DC2\EOT\226\SOH\t\CAN\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\EOT\ETX\DC2\EOT\226\SOH\ESC\FS\n\
    \\246\SOH\n\
    \\EOT\EOT\DLE\STX\ENQ\DC2\EOT\231\SOH\STX\DC4\SUB\231\SOH Supported status values: \"Completed\", \"Failed\", \"Cancelled\" (Phase 7\n\
    \ Sprint 7.8 adds Cancelled). Engine emits Cancelled when the bridge\n\
    \ observes a ConversationCancelEvent in the conversation log before the\n\
    \ inference completes.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ENQ\ENQ\DC2\EOT\231\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ENQ\SOH\DC2\EOT\231\SOH\t\SI\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ENQ\ETX\DC2\EOT\231\SOH\DC2\DC3\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\ACK\DC2\EOT\232\SOH\STX\FS\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ACK\ACK\DC2\EOT\232\SOH\STX\SI\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ACK\SOH\DC2\EOT\232\SOH\DLE\ETB\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ACK\ETX\DC2\EOT\232\SOH\SUB\ESC\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\a\DC2\EOT\233\SOH\STX\CAN\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\a\ENQ\DC2\EOT\233\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\a\SOH\DC2\EOT\233\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\a\ETX\DC2\EOT\233\SOH\SYN\ETB\n\
    \\186\STX\n\
    \\EOT\EOT\DLE\STX\b\DC2\EOT\239\SOH\STX\CAN\SUB\171\STX Phase 7 Sprint 7.8: causal reference back to the user prompt message id\n\
    \ that this result resolves. Used by the result-bridge to write a\n\
    \ ConversationInferenceResultEvent back to the per-context conversation\n\
    \ topic; producer-side dedup on the inference.result.<mode> topic is keyed\n\
    \ by this value.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\b\ENQ\DC2\EOT\239\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\b\SOH\DC2\EOT\239\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\b\ETX\DC2\EOT\239\SOH\SYN\ETB\n\
    \\252\STX\n\
    \\EOT\EOT\DLE\STX\t\DC2\EOT\246\SOH\STX\SYN\SUB\237\STX Phase 7 Sprint 7.8: per-context routing for the result-bridge. The\n\
    \ bridge consumes inference.result.<mode> with a Failover subscription\n\
    \ and writes a ConversationInferenceResultEvent to the per-context\n\
    \ conversation topic; user_id + context_id are the fields the bridge\n\
    \ uses to compute the destination topic name without consulting a\n\
    \ separate request-id cache.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\t\ENQ\DC2\EOT\246\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\t\SOH\DC2\EOT\246\SOH\t\DLE\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\t\ETX\DC2\EOT\246\SOH\DC3\NAK\n\
    \\f\n\
    \\EOT\EOT\DLE\STX\n\
    \\DC2\EOT\247\SOH\STX\EM\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\n\
    \\ENQ\DC2\EOT\247\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\n\
    \\SOH\DC2\EOT\247\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\n\
    \\ETX\DC2\EOT\247\SOH\SYN\CAN\n\
    \\f\n\
    \\STX\EOT\DC1\DC2\ACK\250\SOH\NUL\253\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\DC1\SOH\DC2\EOT\250\SOH\b\NAK\n\
    \\f\n\
    \\EOT\EOT\DC1\STX\NUL\DC2\EOT\251\SOH\STX\CAN\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\ENQ\DC2\EOT\251\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\SOH\DC2\EOT\251\SOH\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\ETX\DC2\EOT\251\SOH\SYN\ETB\n\
    \\f\n\
    \\EOT\EOT\DC1\STX\SOH\DC2\EOT\252\SOH\STX\NAK\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\ENQ\DC2\EOT\252\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\SOH\DC2\EOT\252\SOH\t\DLE\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\ETX\DC2\EOT\252\SOH\DC3\DC4b\ACKproto3"