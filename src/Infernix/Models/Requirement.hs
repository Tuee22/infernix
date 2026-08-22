{-# LANGUAGE OverloadedStrings #-}

-- | Phase 4 Sprint 4.39 — a model's memory requirement, computed from the
-- model's own bytes.
--
-- Two terms, neither of them authored. The weight term is the sum over the
-- checkpoint's tensor table, read from a bounded prefix by
-- "Infernix.Models.Artifact". The cache term is a closed function of the model's
-- declared geometry and the execution shape the engine will actually run under:
--
-- > 2 × layers × keyValueHeads × headWidth × contextLength × elementWidth
--
-- It is closed in both senses — total over its inputs, and taking no input that
-- is not already a term in the plan. Nothing multiplies the result by a safety
-- margin, because a margin is an authored number wearing a derived number's
-- clothes.
--
-- Where weights stream to a device the model-size term is absent from the host
-- formula entirely: the host holds one tensor at a time, so its requirement is
-- the largest single entry in the table, and the weights plus the cache are
-- charged to the device.
module Infernix.Models.Requirement
  ( DerivedModelRequirement (..),
    deriveModelRequirement,
    deriveModelRequirementFromHeader,
    deriveModelRequirementFromStagedPrefix,
    keyValueCacheBytes,
    modelRequirementBytesToMib,
  )
where

import Data.Char (isDigit)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Models.Artifact
  ( ArtifactHeader
      ( artifactHeaderLargestTensorBytes,
        artifactHeaderPrefixBytes,
        artifactHeaderPrefixDigest,
        artifactHeaderTensors,
        artifactHeaderWeightBytes
      ),
    ArtifactHeaderError,
    ArtifactTensor (artifactTensorName, artifactTensorShape),
    artifactHeaderErrorText,
    readArtifactHeader,
    readArtifactHeaderWithSize,
  )
import Infernix.Types
  ( ModelDescriptor (modelExecutionShape, modelGeometry, modelId),
    ModelExecutionShape
      ( executionCacheElementWidth,
        executionContextLength,
        executionLoadStrategy
      ),
    ModelGeometry
      ( geometryHeadWidth,
        geometryHiddenWidth,
        geometryKeyValueHeads,
        geometryLayers
      ),
    ModelLoadStrategy (LoadResidentHost, StreamWeightsToDevice),
    ModelResourceRequirement,
    mkHostAndDeviceRequirement,
    mkHostResidentRequirement,
  )
import Text.Read (readMaybe)

-- | A requirement together with the evidence it was derived from.
--
-- The digest covers the header prefix that was read and explicitly not the
-- payload, so this value is a statement about one exact header rather than about
-- whatever currently sits at a path.
data DerivedModelRequirement = DerivedModelRequirement
  { derivedRequirement :: ModelResourceRequirement,
    derivedWeightBytes :: Integer,
    derivedCacheBytes :: Integer,
    derivedLargestTensorBytes :: Integer,
    derivedPrefixBytes :: Integer,
    derivedPrefixDigest :: Text
  }
  deriving (Eq, Show)

-- | Read the staged artifact's header and derive this model's requirement.
deriveModelRequirement ::
  ModelDescriptor ->
  FilePath ->
  IO (Either Text DerivedModelRequirement)
deriveModelRequirement model artifactPath = do
  headerResult <- readArtifactHeader artifactPath
  pure (completeDerivation model headerResult)

completeDerivation ::
  ModelDescriptor ->
  Either ArtifactHeaderError ArtifactHeader ->
  Either Text DerivedModelRequirement
completeDerivation model headerResult =
  case headerResult of
    Left headerError ->
      Left
        ( "no memory requirement could be derived for "
            <> modelId model
            <> ": "
            <> artifactHeaderErrorText headerError
        )
    Right header -> deriveModelRequirementFromHeader model header

-- | Derive from a file holding only the artifact's leading bytes, with the
-- artifact's own total size supplied separately.
deriveModelRequirementFromStagedPrefix ::
  ModelDescriptor ->
  FilePath ->
  Integer ->
  IO (Either Text DerivedModelRequirement)
deriveModelRequirementFromStagedPrefix model prefixPath artifactBytes = do
  headerResult <- readArtifactHeaderWithSize prefixPath artifactBytes
  pure (completeDerivation model headerResult)

-- | The pure half: everything except reading the file.
deriveModelRequirementFromHeader ::
  ModelDescriptor ->
  ArtifactHeader ->
  Either Text DerivedModelRequirement
deriveModelRequirementFromHeader model header = do
  cacheBytes <- modelCacheBytes model header
  let weightBytes = artifactHeaderWeightBytes header
      largestBytes = artifactHeaderLargestTensorBytes header
      shape = modelExecutionShape model
  requirement <-
    case executionLoadStrategy shape of
      LoadResidentHost ->
        mintHostResident (modelRequirementBytesToMib (weightBytes + cacheBytes))
      StreamWeightsToDevice ->
        mintHostAndDevice
          (modelRequirementBytesToMib largestBytes)
          (modelRequirementBytesToMib (weightBytes + cacheBytes))
  pure
    DerivedModelRequirement
      { derivedRequirement = requirement,
        derivedWeightBytes = weightBytes,
        derivedCacheBytes = cacheBytes,
        derivedLargestTensorBytes = largestBytes,
        derivedPrefixBytes = artifactHeaderPrefixBytes header,
        derivedPrefixDigest = artifactHeaderPrefixDigest header
      }
  where
    mintHostResident hostMib =
      either (Left . mintFailure) Right (mkHostResidentRequirement hostMib)
    mintHostAndDevice hostMib deviceMib =
      either (Left . mintFailure) Right (mkHostAndDeviceRequirement hostMib deviceMib)
    mintFailure reason =
      "the derived requirement for "
        <> modelId model
        <> " is not admissible: "
        <> Text.pack reason

-- | Round a byte quantity up to whole MiB, so a requirement never understates
-- what the artifact states.
modelRequirementBytesToMib :: Integer -> Int
modelRequirementBytesToMib bytes
  | bytes <= 0 = 1
  | otherwise = fromInteger ((bytes + mibBytes - 1) `div` mibBytes)
  where
    mibBytes = 1024 * 1024

-- | The cache term, or zero for a model whose engine keeps no key/value cache.
--
-- A declared geometry is cross-checked against the header before it is used: the
-- layer count, the head counts, and the hidden width the cache term is computed
-- from must be facts the tensor table actually contains, or the derivation
-- yields no requirement rather than a small one.
modelCacheBytes :: ModelDescriptor -> ArtifactHeader -> Either Text Integer
modelCacheBytes model header =
  case modelGeometry model of
    Nothing -> Right 0
    Just geometry -> do
      checkGeometryAgainstHeader (modelId model) geometry header
      Right
        ( keyValueCacheBytes
            geometry
            (executionContextLength shape)
            (executionCacheElementWidth shape)
        )
  where
    shape = modelExecutionShape model

-- | @2 × layers × keyValueHeads × headWidth × contextLength × elementWidth@.
--
-- The leading two counts keys and values separately. Batch is deliberately not a
-- factor: one serialized inference is what this repository admits, and a factor
-- for work the machine will not do is a margin.
keyValueCacheBytes :: ModelGeometry -> Int -> Int -> Integer
keyValueCacheBytes geometry contextLength elementWidth =
  2
    * toInteger (geometryLayers geometry)
    * toInteger (geometryKeyValueHeads geometry)
    * toInteger (geometryHeadWidth geometry)
    * toInteger contextLength
    * toInteger elementWidth

-- | The sixth fail-closed invariant: a declared geometry that the header does
-- not corroborate is refused.
--
-- Three checks, each against a fact the table states rather than against another
-- declaration: the number of distinct per-layer indices in the tensor names, the
-- hidden width in the embedding tensor's shape, and the key-projection width in
-- a key-projection tensor's shape. A dimension is looked for anywhere in the
-- shape because the two formats disagree about dimension order, and a check that
-- assumed one order would pass on one format and fail on the other for reasons
-- that have nothing to do with the model.
checkGeometryAgainstHeader :: Text -> ModelGeometry -> ArtifactHeader -> Either Text ()
checkGeometryAgainstHeader modelIdValue geometry header = do
  requireEqual "layer count" (geometryLayers geometry) observedLayers
  requireDimension
    "hidden width"
    (geometryHiddenWidth geometry)
    (shapesOf isEmbeddingTensor)
  requireDimension
    "key-projection width"
    (geometryKeyValueHeads geometry * geometryHeadWidth geometry)
    (shapesOf isKeyProjectionTensor)
  where
    tensors = artifactHeaderTensors header

    observedLayers =
      length (nub [index | tensor <- tensors, Just index <- [layerIndexOf (artifactTensorName tensor)]])

    shapesOf predicate =
      [artifactTensorShape tensor | tensor <- tensors, predicate (artifactTensorName tensor)]

    requireEqual label declared observed
      | declared == observed = Right ()
      | otherwise =
          Left
            ( "the declared geometry for "
                <> modelIdValue
                <> " states a "
                <> label
                <> " of "
                <> Text.pack (show declared)
                <> " against "
                <> Text.pack (show observed)
                <> " in the artifact's own tensor table"
            )

    requireDimension label declared shapes
      | any (elem (toInteger declared)) shapes = Right ()
      | otherwise =
          Left
            ( "the declared geometry for "
                <> modelIdValue
                <> " states a "
                <> label
                <> " of "
                <> Text.pack (show declared)
                <> " that appears in no matching tensor's shape"
            )

-- | The per-layer index in a tensor name, under either format's convention:
-- @model.layers.<n>.…@ for safetensors and @blk.<n>.…@ for GGUF.
layerIndexOf :: Text -> Maybe Int
layerIndexOf tensorName =
  case numericSegments of
    index : _ -> readMaybe (Text.unpack index)
    [] -> Nothing
  where
    numericSegments =
      [ segment
      | segment <- Text.splitOn "." tensorName,
        not (Text.null segment),
        Text.all isDigit segment
      ]

isEmbeddingTensor :: Text -> Bool
isEmbeddingTensor tensorName =
  any
    (`Text.isInfixOf` tensorName)
    ["embed_tokens", "token_embd", "tok_embeddings", "wte"]

isKeyProjectionTensor :: Text -> Bool
isKeyProjectionTensor tensorName =
  any
    (`Text.isInfixOf` tensorName)
    ["k_proj.weight", "attn_k.weight", "wk.weight"]
