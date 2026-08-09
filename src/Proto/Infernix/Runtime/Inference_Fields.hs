{- This file was auto-generated from infernix/runtime/inference.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Infernix.Runtime.Inference_Fields where
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
adapterId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "adapterId" a) =>
  Lens.Family2.LensLike' f s a
adapterId = Data.ProtoLens.Field.field @"adapterId"
adapterLocator ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "adapterLocator" a) =>
  Lens.Family2.LensLike' f s a
adapterLocator = Data.ProtoLens.Field.field @"adapterLocator"
adapterType ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "adapterType" a) =>
  Lens.Family2.LensLike' f s a
adapterType = Data.ProtoLens.Field.field @"adapterType"
artifactType ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "artifactType" a) =>
  Lens.Family2.LensLike' f s a
artifactType = Data.ProtoLens.Field.field @"artifactType"
availableMib ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "availableMib" a) =>
  Lens.Family2.LensLike' f s a
availableMib = Data.ProtoLens.Field.field @"availableMib"
causalRef ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "causalRef" a) =>
  Lens.Family2.LensLike' f s a
causalRef = Data.ProtoLens.Field.field @"causalRef"
clientIdempotencyKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "clientIdempotencyKey" a) =>
  Lens.Family2.LensLike' f s a
clientIdempotencyKey
  = Data.ProtoLens.Field.field @"clientIdempotencyKey"
configMapName ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "configMapName" a) =>
  Lens.Family2.LensLike' f s a
configMapName = Data.ProtoLens.Field.field @"configMapName"
contextId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "contextId" a) =>
  Lens.Family2.LensLike' f s a
contextId = Data.ProtoLens.Field.field @"contextId"
conversationLogOffset ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "conversationLogOffset" a) =>
  Lens.Family2.LensLike' f s a
conversationLogOffset
  = Data.ProtoLens.Field.field @"conversationLogOffset"
createdAt ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "createdAt" a) =>
  Lens.Family2.LensLike' f s a
createdAt = Data.ProtoLens.Field.field @"createdAt"
demoUi ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "demoUi" a) =>
  Lens.Family2.LensLike' f s a
demoUi = Data.ProtoLens.Field.field @"demoUi"
description ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "description" a) =>
  Lens.Family2.LensLike' f s a
description = Data.ProtoLens.Field.field @"description"
displayName ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "displayName" a) =>
  Lens.Family2.LensLike' f s a
displayName = Data.ProtoLens.Field.field @"displayName"
downloadUrl ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "downloadUrl" a) =>
  Lens.Family2.LensLike' f s a
downloadUrl = Data.ProtoLens.Field.field @"downloadUrl"
edgePort ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "edgePort" a) =>
  Lens.Family2.LensLike' f s a
edgePort = Data.ProtoLens.Field.field @"edgePort"
engine ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "engine" a) =>
  Lens.Family2.LensLike' f s a
engine = Data.ProtoLens.Field.field @"engine"
engineInstallRoot ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "engineInstallRoot" a) =>
  Lens.Family2.LensLike' f s a
engineInstallRoot = Data.ProtoLens.Field.field @"engineInstallRoot"
engines ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "engines" a) =>
  Lens.Family2.LensLike' f s a
engines = Data.ProtoLens.Field.field @"engines"
errorCode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "errorCode" a) =>
  Lens.Family2.LensLike' f s a
errorCode = Data.ProtoLens.Field.field @"errorCode"
errorMessage ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "errorMessage" a) =>
  Lens.Family2.LensLike' f s a
errorMessage = Data.ProtoLens.Field.field @"errorMessage"
family ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "family" a) =>
  Lens.Family2.LensLike' f s a
family = Data.ProtoLens.Field.field @"family"
fieldType ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "fieldType" a) =>
  Lens.Family2.LensLike' f s a
fieldType = Data.ProtoLens.Field.field @"fieldType"
generatedOutputObjectPrefix ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "generatedOutputObjectPrefix" a) =>
  Lens.Family2.LensLike' f s a
generatedOutputObjectPrefix
  = Data.ProtoLens.Field.field @"generatedOutputObjectPrefix"
generatedPath ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "generatedPath" a) =>
  Lens.Family2.LensLike' f s a
generatedPath = Data.ProtoLens.Field.field @"generatedPath"
inferenceError ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "inferenceError" a) =>
  Lens.Family2.LensLike' f s a
inferenceError = Data.ProtoLens.Field.field @"inferenceError"
inlineOutput ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "inlineOutput" a) =>
  Lens.Family2.LensLike' f s a
inlineOutput = Data.ProtoLens.Field.field @"inlineOutput"
inputObjectRef ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "inputObjectRef" a) =>
  Lens.Family2.LensLike' f s a
inputObjectRef = Data.ProtoLens.Field.field @"inputObjectRef"
inputText ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "inputText" a) =>
  Lens.Family2.LensLike' f s a
inputText = Data.ProtoLens.Field.field @"inputText"
label ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "label" a) =>
  Lens.Family2.LensLike' f s a
label = Data.ProtoLens.Field.field @"label"
matrixRowId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "matrixRowId" a) =>
  Lens.Family2.LensLike' f s a
matrixRowId = Data.ProtoLens.Field.field @"matrixRowId"
maybe'error ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'error" a) =>
  Lens.Family2.LensLike' f s a
maybe'error = Data.ProtoLens.Field.field @"maybe'error"
maybe'inferenceError ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'inferenceError" a) =>
  Lens.Family2.LensLike' f s a
maybe'inferenceError
  = Data.ProtoLens.Field.field @"maybe'inferenceError"
maybe'inlineOutput ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'inlineOutput" a) =>
  Lens.Family2.LensLike' f s a
maybe'inlineOutput
  = Data.ProtoLens.Field.field @"maybe'inlineOutput"
maybe'modelMemoryLimitExceeded ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'modelMemoryLimitExceeded" a) =>
  Lens.Family2.LensLike' f s a
maybe'modelMemoryLimitExceeded
  = Data.ProtoLens.Field.field @"maybe'modelMemoryLimitExceeded"
maybe'objectRef ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'objectRef" a) =>
  Lens.Family2.LensLike' f s a
maybe'objectRef = Data.ProtoLens.Field.field @"maybe'objectRef"
maybe'output ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'output" a) =>
  Lens.Family2.LensLike' f s a
maybe'output = Data.ProtoLens.Field.field @"maybe'output"
maybe'payload ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'payload" a) =>
  Lens.Family2.LensLike' f s a
maybe'payload = Data.ProtoLens.Field.field @"maybe'payload"
message ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "message" a) =>
  Lens.Family2.LensLike' f s a
message = Data.ProtoLens.Field.field @"message"
minioAccessKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "minioAccessKey" a) =>
  Lens.Family2.LensLike' f s a
minioAccessKey = Data.ProtoLens.Field.field @"minioAccessKey"
minioDemoArtifactsBucket ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "minioDemoArtifactsBucket" a) =>
  Lens.Family2.LensLike' f s a
minioDemoArtifactsBucket
  = Data.ProtoLens.Field.field @"minioDemoArtifactsBucket"
minioEndpoint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "minioEndpoint" a) =>
  Lens.Family2.LensLike' f s a
minioEndpoint = Data.ProtoLens.Field.field @"minioEndpoint"
minioModelsBucket ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "minioModelsBucket" a) =>
  Lens.Family2.LensLike' f s a
minioModelsBucket = Data.ProtoLens.Field.field @"minioModelsBucket"
minioRegion ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "minioRegion" a) =>
  Lens.Family2.LensLike' f s a
minioRegion = Data.ProtoLens.Field.field @"minioRegion"
minioSecretKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "minioSecretKey" a) =>
  Lens.Family2.LensLike' f s a
minioSecretKey = Data.ProtoLens.Field.field @"minioSecretKey"
modelCacheQuotaBytes ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "modelCacheQuotaBytes" a) =>
  Lens.Family2.LensLike' f s a
modelCacheQuotaBytes
  = Data.ProtoLens.Field.field @"modelCacheQuotaBytes"
modelCacheRoot ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "modelCacheRoot" a) =>
  Lens.Family2.LensLike' f s a
modelCacheRoot = Data.ProtoLens.Field.field @"modelCacheRoot"
modelId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "modelId" a) =>
  Lens.Family2.LensLike' f s a
modelId = Data.ProtoLens.Field.field @"modelId"
modelMemoryLimitExceeded ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "modelMemoryLimitExceeded" a) =>
  Lens.Family2.LensLike' f s a
modelMemoryLimitExceeded
  = Data.ProtoLens.Field.field @"modelMemoryLimitExceeded"
models ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "models" a) =>
  Lens.Family2.LensLike' f s a
models = Data.ProtoLens.Field.field @"models"
mountedPath ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "mountedPath" a) =>
  Lens.Family2.LensLike' f s a
mountedPath = Data.ProtoLens.Field.field @"mountedPath"
name ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "name" a) =>
  Lens.Family2.LensLike' f s a
name = Data.ProtoLens.Field.field @"name"
notes ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "notes" a) =>
  Lens.Family2.LensLike' f s a
notes = Data.ProtoLens.Field.field @"notes"
objectRef ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "objectRef" a) =>
  Lens.Family2.LensLike' f s a
objectRef = Data.ProtoLens.Field.field @"objectRef"
outputText ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "outputText" a) =>
  Lens.Family2.LensLike' f s a
outputText = Data.ProtoLens.Field.field @"outputText"
payload ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "payload" a) =>
  Lens.Family2.LensLike' f s a
payload = Data.ProtoLens.Field.field @"payload"
prefixHash ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "prefixHash" a) =>
  Lens.Family2.LensLike' f s a
prefixHash = Data.ProtoLens.Field.field @"prefixHash"
pythonNative ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "pythonNative" a) =>
  Lens.Family2.LensLike' f s a
pythonNative = Data.ProtoLens.Field.field @"pythonNative"
referenceModel ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "referenceModel" a) =>
  Lens.Family2.LensLike' f s a
referenceModel = Data.ProtoLens.Field.field @"referenceModel"
requestId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "requestId" a) =>
  Lens.Family2.LensLike' f s a
requestId = Data.ProtoLens.Field.field @"requestId"
requestModelId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "requestModelId" a) =>
  Lens.Family2.LensLike' f s a
requestModelId = Data.ProtoLens.Field.field @"requestModelId"
requestShape ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "requestShape" a) =>
  Lens.Family2.LensLike' f s a
requestShape = Data.ProtoLens.Field.field @"requestShape"
requestTopics ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "requestTopics" a) =>
  Lens.Family2.LensLike' f s a
requestTopics = Data.ProtoLens.Field.field @"requestTopics"
requiredMib ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "requiredMib" a) =>
  Lens.Family2.LensLike' f s a
requiredMib = Data.ProtoLens.Field.field @"requiredMib"
requiresGpu ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "requiresGpu" a) =>
  Lens.Family2.LensLike' f s a
requiresGpu = Data.ProtoLens.Field.field @"requiresGpu"
resource ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "resource" a) =>
  Lens.Family2.LensLike' f s a
resource = Data.ProtoLens.Field.field @"resource"
resultModelId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "resultModelId" a) =>
  Lens.Family2.LensLike' f s a
resultModelId = Data.ProtoLens.Field.field @"resultModelId"
resultTopic ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "resultTopic" a) =>
  Lens.Family2.LensLike' f s a
resultTopic = Data.ProtoLens.Field.field @"resultTopic"
runtimeLane ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "runtimeLane" a) =>
  Lens.Family2.LensLike' f s a
runtimeLane = Data.ProtoLens.Field.field @"runtimeLane"
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
source ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "source" a) =>
  Lens.Family2.LensLike' f s a
source = Data.ProtoLens.Field.field @"source"
status ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "status" a) =>
  Lens.Family2.LensLike' f s a
status = Data.ProtoLens.Field.field @"status"
userId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "userId" a) =>
  Lens.Family2.LensLike' f s a
userId = Data.ProtoLens.Field.field @"userId"
userPromptMessageId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "userPromptMessageId" a) =>
  Lens.Family2.LensLike' f s a
userPromptMessageId
  = Data.ProtoLens.Field.field @"userPromptMessageId"
vec'engines ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'engines" a) =>
  Lens.Family2.LensLike' f s a
vec'engines = Data.ProtoLens.Field.field @"vec'engines"
vec'models ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'models" a) =>
  Lens.Family2.LensLike' f s a
vec'models = Data.ProtoLens.Field.field @"vec'models"
vec'requestShape ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'requestShape" a) =>
  Lens.Family2.LensLike' f s a
vec'requestShape = Data.ProtoLens.Field.field @"vec'requestShape"
vec'requestTopics ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'requestTopics" a) =>
  Lens.Family2.LensLike' f s a
vec'requestTopics = Data.ProtoLens.Field.field @"vec'requestTopics"