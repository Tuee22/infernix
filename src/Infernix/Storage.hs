{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Storage
  ( edgePortPath,
    formatTimestamp,
    harborPortPath,
    parseTimestamp,
    pulsarHttpPortPath,
    readCacheManifestProtoMaybe,
    readEdgePortMaybe,
    readHarborPortMaybe,
    readInferenceResultProtoMaybe,
    readPulsarHttpPortMaybe,
    readStateFileMaybe,
    writeCacheManifestProto,
    writeInferenceResultProto,
    writeStateFile,
    writeTextFile,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (throwIO)
import Data.ByteString qualified as ByteString
import Data.Maybe (fromMaybe)
import Data.ProtoLens (Message, decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Infernix.Config (Paths (..))
import Infernix.Error (InfernixError (ProtobufDecodeFailure))
import Infernix.Types
import Lens.Family2 (set, view)
import Proto.Infernix.Manifest.RuntimeManifest qualified as ProtoManifest
import Proto.Infernix.Manifest.RuntimeManifest_Fields qualified as ProtoManifestFields
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory, (</>))
import Text.Read (readMaybe)

edgePortPath :: Paths -> FilePath
edgePortPath paths = runtimeRoot paths </> "edge-port.json"

readEdgePortMaybe :: Paths -> IO (Maybe Int)
readEdgePortMaybe paths = readPortFileMaybe (edgePortPath paths)

-- | Phase 3 follow-on (2026-05-29): Harbor's host-side NodePort is
-- dynamically selected at @cluster up@ time using the same
-- bind-test / increment loop that the edge port uses, and persisted
-- here for downstream probes, the publication path, and the
-- containerd registry-hosts namespace mapping. The in-cluster
-- Kubernetes NodePort number stays fixed at @30002@; only the Kind
-- hostPort mapping observed by the operator host shifts when another
-- process (e.g. an unrelated VSCode debug worker) already holds the
-- baseline.
harborPortPath :: Paths -> FilePath
harborPortPath paths = runtimeRoot paths </> "harbor-port.json"

readHarborPortMaybe :: Paths -> IO (Maybe Int)
readHarborPortMaybe paths = readPortFileMaybe (harborPortPath paths)

-- | The Pulsar proxy HTTP NodePort's Kind hostPort mapping is selected
-- dynamically at @cluster up@ time from the @30080@ baseline using the same
-- bind-test / increment loop as the edge and Harbor ports, and persisted
-- here so the Apple host-native service daemon's loopback Pulsar transport
-- targets whatever host port is actually free on the operator's machine
-- (the in-cluster Kubernetes NodePort number stays @30080@; only the Kind
-- hostPort mapping shifts when another process such as a VSCode
-- auto-forwarded port already holds the baseline).
pulsarHttpPortPath :: Paths -> FilePath
pulsarHttpPortPath paths = runtimeRoot paths </> "pulsar-http-port.json"

readPulsarHttpPortMaybe :: Paths -> IO (Maybe Int)
readPulsarHttpPortMaybe paths = readPortFileMaybe (pulsarHttpPortPath paths)

readPortFileMaybe :: FilePath -> IO (Maybe Int)
readPortFileMaybe filePath = do
  fileExists <- doesFileExist filePath
  if fileExists
    then do
      contents <- readFile filePath
      pure (readMaybe contents)
    else pure Nothing

writeStateFile :: (Show a) => FilePath -> a -> IO ()
writeStateFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  writeFile filePath (show value)

readStateFileMaybe :: (Read a) => FilePath -> IO (Maybe a)
readStateFileMaybe filePath = do
  contents <- readFile filePath
  pure (readMaybe contents)

writeTextFile :: FilePath -> Text -> IO ()
writeTextFile filePath contents = do
  createDirectoryIfMissing True (takeDirectory filePath)
  Text.writeFile filePath contents

writeInferenceResultProto :: FilePath -> InferenceResult -> IO ()
writeInferenceResultProto filePath = writeProtoFile filePath . inferenceResultToProto

readInferenceResultProtoMaybe :: FilePath -> IO (Maybe InferenceResult)
readInferenceResultProtoMaybe filePath = do
  maybeProto <- readProtoFileMaybe filePath
  pure (inferenceResultFromProto =<< maybeProto)

writeCacheManifestProto :: FilePath -> FilePath -> CacheManifest -> IO ()
writeCacheManifestProto filePath materializedCachePath =
  writeProtoFile filePath . cacheManifestToProto materializedCachePath

readCacheManifestProtoMaybe :: FilePath -> IO (Maybe CacheManifest)
readCacheManifestProtoMaybe filePath = do
  maybeProto <- readProtoFileMaybe filePath
  pure (cacheManifestFromProto =<< maybeProto)

writeProtoFile :: (Message a) => FilePath -> a -> IO ()
writeProtoFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  ByteString.writeFile filePath (encodeMessage value)

readProtoFileMaybe :: (Message a) => FilePath -> IO (Maybe a)
readProtoFileMaybe filePath = do
  fileExists <- doesFileExist filePath
  if not fileExists
    then pure Nothing
    else do
      encoded <- ByteString.readFile filePath
      case decodeMessage encoded of
        Left err ->
          throwIO (ProtobufDecodeFailure filePath err)
        Right value -> pure (Just value)

inferenceResultToProto :: InferenceResult -> ProtoInference.InferenceResult
inferenceResultToProto resultValue =
  set (field @"requestId") (requestId resultValue) $
    set (field @"resultModelId") (resultModelId resultValue) $
      set (field @"matrixRowId") (resultMatrixRowId resultValue) $
        set (field @"runtimeMode") (runtimeModeId (resultRuntimeMode resultValue)) $
          set (field @"selectedEngine") (resultSelectedEngine resultValue) $
            set (field @"status") (status resultValue) $
              set (field @"payload") (resultPayloadToProto (payload resultValue)) $
                set (field @"createdAt") (formatTimestamp (createdAt resultValue)) $
                  set (field @"userId") (resultUserId resultValue) $
                    set (field @"contextId") (resultContextId resultValue) $
                      set (field @"causalRef") (resultCausalRef resultValue) defMessage

inferenceResultFromProto :: ProtoInference.InferenceResult -> Maybe InferenceResult
inferenceResultFromProto protoValue = do
  runtimeMode <- parseRuntimeMode (view ProtoInferenceFields.runtimeMode protoValue)
  createdAtValue <- parseTimestamp (view ProtoInferenceFields.createdAt protoValue)
  payloadValue <- resultPayloadFromProto (view ProtoInferenceFields.payload protoValue)
  pure
    InferenceResult
      { requestId = view ProtoInferenceFields.requestId protoValue,
        resultModelId = view ProtoInferenceFields.resultModelId protoValue,
        resultMatrixRowId = view ProtoInferenceFields.matrixRowId protoValue,
        resultRuntimeMode = runtimeMode,
        resultSelectedEngine = view ProtoInferenceFields.selectedEngine protoValue,
        status = view ProtoInferenceFields.status protoValue,
        payload = payloadValue,
        createdAt = createdAtValue,
        resultUserId = view ProtoInferenceFields.userId protoValue,
        resultContextId = view ProtoInferenceFields.contextId protoValue,
        resultCausalRef = view ProtoInferenceFields.causalRef protoValue
      }

resultPayloadToProto :: ResultPayload -> ProtoInference.ResultPayload
resultPayloadToProto payloadValue =
  case objectRef payloadValue of
    Just objectRefValue -> set (field @"objectRef") objectRefValue defMessage
    Nothing -> set (field @"inlineOutput") (fromMaybe "" (inlineOutput payloadValue)) defMessage

resultPayloadFromProto :: ProtoInference.ResultPayload -> Maybe ResultPayload
resultPayloadFromProto protoValue =
  case view ProtoInferenceFields.maybe'output protoValue of
    Just (ProtoInference.ResultPayload'InlineOutput inlineOutputValue) ->
      Just
        ResultPayload
          { inlineOutput = Just inlineOutputValue,
            objectRef = Nothing
          }
    Just (ProtoInference.ResultPayload'ObjectRef objectRefValue) ->
      Just
        ResultPayload
          { inlineOutput = Nothing,
            objectRef = Just objectRefValue
          }
    Nothing ->
      Just
        ResultPayload
          { inlineOutput = Just "",
            objectRef = Nothing
          }

cacheManifestToProto :: FilePath -> CacheManifest -> ProtoManifest.RuntimeManifest
cacheManifestToProto materializedCachePath manifest =
  set (field @"manifestId") manifestIdentifier $
    set (field @"runtimeMode") runtimeModeText $
      set (field @"materializations") [materialization] $
        set (field @"cacheEntries") [cacheEntry] $
          set (field @"durableResultsPrefix") durableResultsPrefix defMessage
  where
    runtimeModeText = runtimeModeId (cacheRuntimeMode manifest)
    manifestIdentifier = runtimeModeText <> ":" <> cacheModelId manifest <> ":" <> cacheCacheKey manifest
    -- Phase 7 Sprint 7.7 retires the on-disk object-store tree; durable
    -- results land in MinIO @infernix-demo-objects@ under the per-user
    -- prefix @users/<userId>/contexts/<contextId>/generated/@.
    durableResultsPrefix = "minio://infernix-demo-objects/users/"
    materialization =
      set (field @"runtimeMode") runtimeModeText $
        set (field @"modelId") (cacheModelId manifest) $
          set (field @"selectedEngine") (cacheSelectedEngine manifest) $
            set (field @"durableSourceUri") (cacheDurableSourceUri manifest) $
              set (field @"materializedCachePath") (Text.pack materializedCachePath) defMessage
    cacheEntry =
      set (field @"runtimeMode") runtimeModeText $
        set (field @"modelId") (cacheModelId manifest) $
          set (field @"cacheKey") (cacheCacheKey manifest) $
            set (field @"cachePath") (Text.pack materializedCachePath) $
              set (field @"materialized") True defMessage

cacheManifestFromProto :: ProtoManifest.RuntimeManifest -> Maybe CacheManifest
cacheManifestFromProto protoValue = do
  runtimeMode <-
    parseRuntimeMode
      (view ProtoManifestFields.runtimeMode protoValue)
  modelIdValue <- firstPresent modelIdFromMaterialization modelIdFromCacheEntry
  selectedEngineValue <- firstPresent selectedEngineFromMaterialization (Just "")
  durableSourceUriValue <- firstPresent durableSourceUriFromMaterialization (Just "")
  cacheKeyValue <- cacheKeyFromCacheEntry
  pure
    CacheManifest
      { cacheRuntimeMode = runtimeMode,
        cacheModelId = modelIdValue,
        cacheSelectedEngine = selectedEngineValue,
        cacheDurableSourceUri = durableSourceUriValue,
        cacheCacheKey = cacheKeyValue
      }
  where
    materializations = view ProtoManifestFields.materializations protoValue
    cacheEntries = view ProtoManifestFields.cacheEntries protoValue
    modelIdFromMaterialization =
      case materializations of
        firstMaterialization : _ -> Just (view ProtoManifestFields.modelId firstMaterialization)
        [] -> Nothing
    selectedEngineFromMaterialization =
      case materializations of
        firstMaterialization : _ -> Just (view ProtoManifestFields.selectedEngine firstMaterialization)
        [] -> Nothing
    durableSourceUriFromMaterialization =
      case materializations of
        firstMaterialization : _ -> Just (view ProtoManifestFields.durableSourceUri firstMaterialization)
        [] -> Nothing
    modelIdFromCacheEntry =
      case cacheEntries of
        firstCacheEntry : _ -> Just (view ProtoManifestFields.modelId firstCacheEntry)
        [] -> Nothing
    cacheKeyFromCacheEntry =
      case cacheEntries of
        firstCacheEntry : _ -> Just (view ProtoManifestFields.cacheKey firstCacheEntry)
        [] -> Nothing
    firstPresent firstChoice secondChoice =
      firstChoice <|> secondChoice

formatTimestamp :: UTCTime -> Text
formatTimestamp = Text.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ"

parseTimestamp :: Text -> Maybe UTCTime
parseTimestamp = parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" . Text.unpack
