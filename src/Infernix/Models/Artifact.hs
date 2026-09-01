{-# LANGUAGE OverloadedStrings #-}

-- | Phase 4 Sprint 4.39 — read a model checkpoint's tensor table from a bounded
-- prefix of the artifact, without loading the checkpoint.
--
-- Nothing here estimates. A checkpoint header states, per tensor, the dtype, the
-- shape, and the byte range those elements occupy, and those are the bytes the
-- loader will map. The weight term of a model's memory requirement is therefore
-- the sum over that table, and the largest single entry is the staging bound a
-- streamed load has to hold at once — a different quantity from the total, which
-- is why both are reported.
--
-- Three formats are read: safetensors, GGUF, and whisper.cpp's legacy GGML
-- container. Safetensors and GGUF put a complete tensor table in a bounded
-- prefix. Legacy Whisper interleaves tensor records with tensor payloads, so
-- its fixed header can establish the family and execution geometry but not a
-- prefix-indexed tensor sum. For that host-resident format the actual object
-- extent is the conservative weight charge; it is still a fact of the
-- artifact, not a family constant or a fallback. A payload in any other family
-- yields no header, which is a refusal rather than an authored substitute.
module Infernix.Models.Artifact
  ( ArtifactHeader (..),
    ArtifactHeaderError (..),
    ArtifactTensor (..),
    artifactHeaderPrefixBudgetBytes,
    artifactHeaderErrorText,
    artifactHeaderStagedPrefixBytes,
    readArtifactHeader,
    readArtifactHeaderWithSize,
    readGgufHeaderBytes,
    readSafetensorsHeaderBytes,
  )
where

import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (FromJSON (parseJSON), Value (Object), withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.IO (IOMode (ReadMode), hFileSize, withBinaryFile)

-- | One entry of a checkpoint's tensor table.
data ArtifactTensor = ArtifactTensor
  { artifactTensorName :: Text,
    -- | The declared shape, most-significant dimension first.
    artifactTensorShape :: [Integer],
    -- | Bytes this tensor occupies in the payload, computed from its declared
    -- element count and its dtype's own width. For a block-quantized GGUF type
    -- this is the block count times the block size, which is the same statement
    -- for a dtype whose element width is fractional.
    artifactTensorBytes :: Integer,
    -- | The tensor's byte offset from the start of the payload region.
    artifactTensorOffset :: Integer
  }
  deriving (Eq, Show)

-- | A checkpoint's tensor table plus the exact prefix it was read from.
data ArtifactHeader = ArtifactHeader
  { artifactHeaderTensors :: [ArtifactTensor],
    -- | Total weight bytes: the sum over the table.
    artifactHeaderWeightBytes :: Integer,
    -- | The largest single entry — the staging bound a streamed load holds at
    -- once, which is not the total and is not derivable from it.
    artifactHeaderLargestTensorBytes :: Integer,
    -- | How many bytes of the artifact this derivation actually read.
    artifactHeaderPrefixBytes :: Integer,
    -- | The digest of exactly those bytes.
    --
    -- It covers the prefix and deliberately not the payload: digesting the whole
    -- artifact to avoid reading the whole artifact is circular. A requirement is
    -- therefore a statement about one exact header rather than about whatever
    -- currently sits at a path.
    artifactHeaderPrefixDigest :: Text,
    artifactHeaderFileBytes :: Integer
  }
  deriving (Eq, Show)

-- | Why a header yielded no tensor table. Every arm is a refusal; none of them
-- has a smaller-number fallback.
data ArtifactHeaderError
  = -- | The path could not be opened or read.
    ArtifactUnreadable Text
  | -- | No reader understands this payload's container.
    ArtifactFamilyUnsupported Text
  | -- | The header claims a length this derivation will not read.
    ArtifactHeaderBudgetExceeded Integer Integer
  | -- | The header did not parse as its container's own header.
    ArtifactHeaderMalformed Text
  | -- | Header length plus payload extent disagrees with the file size.
    ArtifactExtentMismatch Integer Integer
  | -- | A tensor's declared byte extent disagrees with its shape and dtype.
    ArtifactTensorExtentMismatch Text Integer Integer
  | -- | The tensor offsets do not tile the payload densely from zero.
    ArtifactTensorTilingBroken Text Integer Integer
  | -- | The prefix read hashes to a different digest than the one recorded.
    ArtifactPrefixDigestMismatch Text Text
  deriving (Eq, Show)

artifactHeaderErrorText :: ArtifactHeaderError -> Text
artifactHeaderErrorText headerError =
  case headerError of
    ArtifactUnreadable reason ->
      "the artifact could not be read: " <> reason
    ArtifactFamilyUnsupported family ->
      "no checkpoint-header reader is present for the " <> family <> " artifact family"
    ArtifactHeaderBudgetExceeded declared budget ->
      "the artifact header declares "
        <> Text.pack (show declared)
        <> " bytes, past the "
        <> Text.pack (show budget)
        <> "-byte prefix budget this derivation reads"
    ArtifactHeaderMalformed reason ->
      "the artifact header did not parse: " <> reason
    ArtifactExtentMismatch declared actual ->
      "the artifact header plus its payload extent is "
        <> Text.pack (show declared)
        <> " bytes against a file of "
        <> Text.pack (show actual)
    ArtifactTensorExtentMismatch tensorName declared computed ->
      "tensor "
        <> tensorName
        <> " declares "
        <> Text.pack (show declared)
        <> " bytes against "
        <> Text.pack (show computed)
        <> " for its own shape and dtype"
    ArtifactTensorTilingBroken tensorName expected actual ->
      "tensor "
        <> tensorName
        <> " starts at "
        <> Text.pack (show actual)
        <> " where the dense tiling reaches "
        <> Text.pack (show expected)
    ArtifactPrefixDigestMismatch expected actual ->
      "the header prefix hashes to " <> actual <> " against the recorded " <> expected

-- | The self-imposed prefix budget.
--
-- A header length the file /claims/ cannot be turned into an unbounded read of a
-- file this process was never going to load, so the budget is checked against
-- the declared length before a single payload byte is requested. Sixteen MiB is
-- far above any tensor table observed in this catalog — the largest measured is
-- 29.8 KiB — and far below every artifact it appears in.
artifactHeaderPrefixBudgetBytes :: Integer
artifactHeaderPrefixBudgetBytes = 16 * 1024 * 1024

-- | Read a checkpoint header, selecting the reader from the artifact's own
-- leading bytes rather than from a declared family string: a row's
-- @artifactType@ is display text an operator wrote, and the container is a fact
-- about the bytes.
readArtifactHeader :: FilePath -> IO (Either ArtifactHeaderError ArtifactHeader)
readArtifactHeader path = do
  sized <-
    try (withBinaryFile path ReadMode hFileSize) ::
      IO (Either IOException Integer)
  case sized of
    Left ioError' -> pure (Left (ArtifactUnreadable (Text.pack (show ioError'))))
    Right fileBytes -> readArtifactHeaderWithSize path fileBytes

-- | Read a checkpoint header from a file holding only the artifact's leading
-- bytes, with the artifact's own total size supplied separately.
--
-- This is the shape a machine needs when it derives a requirement from an object
-- the coordinator staged but this machine has not downloaded: a ranged read
-- fetches the tensor table, and the object's total size comes back with it. The
-- extent invariant still compares the header against the /artifact's/ size, not
-- against the size of the prefix that was fetched, so a truncated fetch is
-- refused rather than treated as a smaller artifact.
readArtifactHeaderWithSize ::
  FilePath ->
  Integer ->
  IO (Either ArtifactHeaderError ArtifactHeader)
readArtifactHeaderWithSize path fileBytes = do
  opened <-
    try (withBinaryFile path ReadMode (`ByteString.hGet` ggufMagicLength)) ::
      IO (Either IOException ByteString)
  case opened of
    Left ioError' -> pure (Left (ArtifactUnreadable (Text.pack (show ioError'))))
    Right leading
      | leading == ggufMagic -> readGgufHeaderBytes path fileBytes
      | leading == whisperGgmlMagic -> readWhisperGgmlHeaderBytes path fileBytes
      | otherwise -> readSafetensorsHeaderBytes path fileBytes

-- | How many leading bytes a machine fetches when it derives a requirement from
-- a staged object rather than from a local file. It is the GGUF standing window,
-- which is the larger of the two readers' needs and inside the prefix budget.
artifactHeaderStagedPrefixBytes :: Int
artifactHeaderStagedPrefixBytes = fromInteger ggufPrefixReadBytes

ggufMagic :: ByteString
ggufMagic = "GGUF"

ggufMagicLength :: Int
ggufMagicLength = ByteString.length ggufMagic

-- | whisper.cpp's pre-GGUF model magic is the little-endian encoding of
-- @0x67676d6c@. The bytes therefore spell @lmgg@ on disk. Selecting from the
-- bytes rather than the catalog label prevents an authored family string from
-- choosing a more permissive reader.
whisperGgmlMagic :: ByteString
whisperGgmlMagic = "lmgg"

-- | The legacy Whisper fixed header is the magic followed by eleven signed
-- little-endian 32-bit values: vocabulary size, five audio dimensions, four
-- text dimensions, mel count, and file type. Upstream reads these fields before
-- its filter, vocabulary, and interleaved tensor records.
whisperGgmlHeaderBytes :: Int
whisperGgmlHeaderBytes = 12 * 4

readWhisperGgmlHeaderBytes ::
  FilePath ->
  Integer ->
  IO (Either ArtifactHeaderError ArtifactHeader)
readWhisperGgmlHeaderBytes path fileBytes = do
  prefixRead <- readBoundedPrefix path whisperGgmlHeaderBytes
  pure (prefixRead >>= parseWhisperGgmlHeader fileBytes)

parseWhisperGgmlHeader :: Integer -> ByteString -> Either ArtifactHeaderError ArtifactHeader
parseWhisperGgmlHeader fileBytes prefix = do
  let fields =
        [ decodeLittleEndian (sliceAt prefix offset 4)
        | offset <- [4, 8 .. whisperGgmlHeaderBytes - 4]
        ]
      namedDimensions =
        zip
          [ "n_vocab",
            "n_audio_ctx",
            "n_audio_state",
            "n_audio_head",
            "n_audio_layer",
            "n_text_ctx",
            "n_text_state",
            "n_text_head",
            "n_text_layer",
            "n_mels"
          ]
          (take 10 fields)
  case fields of
    [ _,
      _,
      nAudioState,
      nAudioHead,
      _,
      _,
      nTextState,
      nTextHead,
      _,
      _,
      fileType
      ] -> do
        mapM_ requirePositiveInt32 namedDimensions
        requireHeadWidth "audio" nAudioState nAudioHead
        requireHeadWidth "text" nTextState nTextHead
        if fileType > maximumSignedInt32
          then Left (ArtifactHeaderMalformed "the Whisper GGML file type is negative")
          else
            if fileBytes <= toInteger whisperGgmlHeaderBytes
              then
                Left
                  ( ArtifactExtentMismatch
                      (toInteger whisperGgmlHeaderBytes + 1)
                      fileBytes
                  )
              else
                Right
                  ArtifactHeader
                    { artifactHeaderTensors = [],
                      -- Legacy GGML has no prefix-indexed tensor table: each
                      -- record is followed immediately by its payload. Charging
                      -- the complete observed object extent is conservative and
                      -- remains derived from the artifact's own bytes.
                      artifactHeaderWeightBytes = fileBytes,
                      artifactHeaderLargestTensorBytes = fileBytes,
                      artifactHeaderPrefixBytes = toInteger (ByteString.length prefix),
                      artifactHeaderPrefixDigest = prefixDigest prefix,
                      artifactHeaderFileBytes = fileBytes
                    }
    _ -> Left (ArtifactHeaderMalformed "the Whisper GGML fixed header is incomplete")
  where
    requirePositiveInt32 (fieldName, value)
      | value > 0 && value <= maximumSignedInt32 = Right ()
      | otherwise =
          Left
            ( ArtifactHeaderMalformed
                ( "the Whisper GGML "
                    <> fieldName
                    <> " field is not a positive signed 32-bit value"
                )
            )

    requireHeadWidth label stateWidth headCount
      | stateWidth `mod` headCount == 0 = Right ()
      | otherwise =
          Left
            ( ArtifactHeaderMalformed
                ( "the Whisper GGML "
                    <> label
                    <> " state width is not divisible by its head count"
                )
            )

maximumSignedInt32 :: Integer
maximumSignedInt32 = 2147483647

-- | Read a bounded prefix of a file, never requesting more than the budget.
readBoundedPrefix :: FilePath -> Int -> IO (Either ArtifactHeaderError ByteString)
readBoundedPrefix path requested
  | toInteger requested > artifactHeaderPrefixBudgetBytes =
      pure
        ( Left
            ( ArtifactHeaderBudgetExceeded
                (toInteger requested)
                artifactHeaderPrefixBudgetBytes
            )
        )
  | otherwise = do
      readResult <-
        try (withBinaryFile path ReadMode (`ByteString.hGet` requested)) ::
          IO (Either IOException ByteString)
      pure $
        case readResult of
          Left ioError' -> Left (ArtifactUnreadable (Text.pack (show ioError')))
          Right contents
            | ByteString.length contents < requested ->
                Left
                  ( ArtifactHeaderMalformed
                      ( "the artifact ended after "
                          <> Text.pack (show (ByteString.length contents))
                          <> " of a declared "
                          <> Text.pack (show requested)
                          <> " header bytes"
                      )
                  )
            | otherwise -> Right contents

prefixDigest :: ByteString -> Text
prefixDigest = TextEncoding.decodeUtf8 . Base16.encode . SHA256.hash

-- | Decode a little-endian unsigned integer of the given width.
decodeLittleEndian :: ByteString -> Integer
decodeLittleEndian bytes =
  foldl'
    (\acc (index, byte) -> acc .|. (toInteger byte `shiftL` (8 * index)))
    0
    (zip [0 :: Int ..] (ByteString.unpack bytes))

-- ---------------------------------------------------------------------------
-- safetensors
-- ---------------------------------------------------------------------------

safetensorsLengthPrefixBytes :: Int
safetensorsLengthPrefixBytes = 8

-- | Safetensors packs its payload with no inter-tensor padding, so its tiling is
-- exact contiguity.
safetensorsPayloadAlignment :: Integer
safetensorsPayloadAlignment = 1

-- | Read a safetensors header: eight little-endian bytes of header length
-- followed by exactly that many bytes of tensor table.
readSafetensorsHeaderBytes ::
  FilePath ->
  Integer ->
  IO (Either ArtifactHeaderError ArtifactHeader)
readSafetensorsHeaderBytes path fileBytes = do
  lengthPrefix <- readBoundedPrefix path safetensorsLengthPrefixBytes
  case lengthPrefix of
    Left readError -> pure (Left readError)
    Right lengthBytes -> do
      let declaredHeaderBytes = decodeLittleEndian lengthBytes
      if declaredHeaderBytes <= 0
        || declaredHeaderBytes + toInteger safetensorsLengthPrefixBytes > fileBytes
        then
          pure
            ( Left
                ( ArtifactExtentMismatch
                    (declaredHeaderBytes + toInteger safetensorsLengthPrefixBytes)
                    fileBytes
                )
            )
        else
          if declaredHeaderBytes + toInteger safetensorsLengthPrefixBytes
            > artifactHeaderPrefixBudgetBytes
            then
              pure
                ( Left
                    ( ArtifactHeaderBudgetExceeded
                        declaredHeaderBytes
                        artifactHeaderPrefixBudgetBytes
                    )
                )
            else do
              let prefixBytes =
                    safetensorsLengthPrefixBytes + fromInteger declaredHeaderBytes
              prefixRead <- readBoundedPrefix path prefixBytes
              pure $ do
                prefix <- prefixRead
                tensors <-
                  parseSafetensorsTable
                    (ByteString.drop safetensorsLengthPrefixBytes prefix)
                completeArtifactHeader
                  safetensorsPayloadAlignment
                  (toInteger safetensorsLengthPrefixBytes + declaredHeaderBytes)
                  fileBytes
                  prefix
                  tensors

-- | One row of the safetensors table, exactly as the header states it.
data SafetensorsEntry = SafetensorsEntry
  { safetensorsEntryDtype :: Text,
    safetensorsEntryShape :: [Integer],
    safetensorsEntryOffsets :: [Integer]
  }

instance FromJSON SafetensorsEntry where
  parseJSON =
    withObject "SafetensorsEntry" $ \fields ->
      SafetensorsEntry
        <$> fields .: "dtype"
        <*> fields .: "shape"
        <*> fields .: "data_offsets"

parseSafetensorsTable :: ByteString -> Either ArtifactHeaderError [ArtifactTensor]
parseSafetensorsTable tableBytes =
  case Aeson.decodeStrict tableBytes of
    Just (Object entries) ->
      traverse
        parseEntry
        [ (Key.toText name, value)
        | (name, value) <- KeyMap.toList entries,
          Key.toText name /= "__metadata__"
        ]
    _ ->
      Left (ArtifactHeaderMalformed "the safetensors tensor table is not a JSON object")
  where
    parseEntry (tensorName, value) =
      case Aeson.fromJSON value of
        Aeson.Error reason ->
          Left
            ( ArtifactHeaderMalformed
                ( "safetensors entry "
                    <> tensorName
                    <> " is malformed: "
                    <> Text.pack reason
                )
            )
        Aeson.Success entry -> buildTensor tensorName entry

    buildTensor tensorName entry = do
      elementWidth <- safetensorsElementWidth tensorName (safetensorsEntryDtype entry)
      shape <- requireNaturalShape tensorName (safetensorsEntryShape entry)
      (start, end) <- requireOffsets tensorName (safetensorsEntryOffsets entry)
      let declaredBytes = end - start
          computedBytes = product shape * toInteger elementWidth
      if declaredBytes /= computedBytes
        then Left (ArtifactTensorExtentMismatch tensorName declaredBytes computedBytes)
        else
          Right
            ArtifactTensor
              { artifactTensorName = tensorName,
                artifactTensorShape = shape,
                artifactTensorBytes = computedBytes,
                artifactTensorOffset = start
              }

    requireNaturalShape tensorName shape
      | all (>= 0) shape = Right shape
      | otherwise =
          Left
            ( ArtifactHeaderMalformed
                ("safetensors entry " <> tensorName <> " has a negative dimension")
            )

    requireOffsets tensorName offsets =
      case offsets of
        [start, end]
          | start >= 0, end >= start -> Right (start, end)
          | otherwise ->
              Left (ArtifactTensorExtentMismatch tensorName (end - start) 0)
        _ ->
          Left
            ( ArtifactHeaderMalformed
                ("safetensors entry " <> tensorName <> " has no two-element `data_offsets`")
            )

-- | Element widths for the safetensors dtypes this catalog's checkpoints use.
-- An unknown dtype is a refusal: a width guessed for a dtype nobody enumerated
-- is exactly the authored constant this derivation replaces.
safetensorsElementWidth :: Text -> Text -> Either ArtifactHeaderError Int
safetensorsElementWidth tensorName dtype =
  case dtype of
    "BOOL" -> Right 1
    "U8" -> Right 1
    "I8" -> Right 1
    "F8_E4M3" -> Right 1
    "F8_E5M2" -> Right 1
    "U16" -> Right 2
    "I16" -> Right 2
    "F16" -> Right 2
    "BF16" -> Right 2
    "U32" -> Right 4
    "I32" -> Right 4
    "F32" -> Right 4
    "U64" -> Right 8
    "I64" -> Right 8
    "F64" -> Right 8
    _ ->
      Left
        ( ArtifactHeaderMalformed
            ( "safetensors entry "
                <> tensorName
                <> " declares the unsupported dtype "
                <> dtype
            )
        )

-- ---------------------------------------------------------------------------
-- GGUF
-- ---------------------------------------------------------------------------

-- | Read a GGUF header: magic, version, tensor count, and metadata count,
-- followed by the metadata block and then the tensor-info block.
--
-- The metadata block is walked rather than parsed into values, because the only
-- thing this derivation needs from it is where it ends. Walking it still fails
-- closed on a malformed entry, which is the property that matters: a length this
-- file claims is never turned into a read past the budget.
readGgufHeaderBytes ::
  FilePath ->
  Integer ->
  IO (Either ArtifactHeaderError ArtifactHeader)
readGgufHeaderBytes path fileBytes = do
  prefixRead <- readBoundedPrefix path (fromInteger ggufPrefixReadBytes)
  case prefixRead of
    Left (ArtifactHeaderMalformed _) -> readShortGguf
    Left readError -> pure (Left readError)
    Right prefix -> pure (parseGgufPrefix fileBytes prefix)
  where
    -- An artifact smaller than the standing prefix read is read whole; the
    -- budget is a ceiling on what is requested, not a floor on what exists.
    readShortGguf = do
      shortRead <- readBoundedPrefix path (fromInteger (min fileBytes ggufPrefixReadBytes))
      pure (shortRead >>= parseGgufPrefix fileBytes)

-- | The standing GGUF prefix read.
--
-- GGUF states its tensor count up front but not its header length, so the read
-- is a fixed bounded window rather than a declared one. Two MiB covers a tensor
-- table of well over ten thousand entries and is inside the prefix budget.
ggufPrefixReadBytes :: Integer
ggufPrefixReadBytes = 2 * 1024 * 1024

parseGgufPrefix :: Integer -> ByteString -> Either ArtifactHeaderError ArtifactHeader
parseGgufPrefix fileBytes prefix = do
  requireGgufBytes 24 prefix
  let tensorCount = decodeLittleEndian (ByteString.take 8 (ByteString.drop 8 prefix))
      metadataCount = decodeLittleEndian (ByteString.take 8 (ByteString.drop 16 prefix))
  metadataEnd <- skipGgufMetadata prefix 24 metadataCount
  (tensors, tensorEnd) <- readGgufTensorInfos prefix metadataEnd tensorCount
  let alignment = ggufDefaultAlignment
      payloadStart = alignUp (toInteger tensorEnd) alignment
      consumedPrefix = min (toInteger (ByteString.length prefix)) payloadStart
  completeArtifactHeader
    alignment
    payloadStart
    fileBytes
    (ByteString.take (fromInteger consumedPrefix) prefix)
    tensors

-- | GGUF pads the tensor-info block up to this alignment before the payload.
-- The value is the format's own default; a file that declares another one in its
-- metadata is refused by the extent check rather than silently mis-summed.
ggufDefaultAlignment :: Integer
ggufDefaultAlignment = 32

alignUp :: Integer -> Integer -> Integer
alignUp value alignment
  | alignment <= 0 = value
  | otherwise = ((value + alignment - 1) `div` alignment) * alignment

requireGgufBytes :: Int -> ByteString -> Either ArtifactHeaderError ()
requireGgufBytes needed bytes
  | ByteString.length bytes >= needed = Right ()
  | otherwise =
      Left (ArtifactHeaderMalformed "the GGUF header ended inside its own fixed fields")

-- | Walk the metadata block, returning the offset just past it.
skipGgufMetadata :: ByteString -> Int -> Integer -> Either ArtifactHeaderError Int
skipGgufMetadata prefix start count
  | count < 0 = Left (ArtifactHeaderMalformed "the GGUF metadata count is negative")
  | otherwise = go start count
  where
    go offset remaining
      | remaining <= 0 = Right offset
      | otherwise = do
          keyEnd <- skipGgufString prefix offset
          typeEnd <- requireOffset (keyEnd + 4)
          let valueType = decodeLittleEndian (sliceAt prefix keyEnd 4)
          valueEnd <- skipGgufValue prefix typeEnd valueType
          go valueEnd (remaining - 1)

    requireOffset offset
      | offset <= ByteString.length prefix = Right offset
      | otherwise =
          Left
            ( ArtifactHeaderMalformed
                "the GGUF metadata block runs past the bounded prefix this derivation reads"
            )

skipGgufString :: ByteString -> Int -> Either ArtifactHeaderError Int
skipGgufString prefix offset
  | offset + 8 > ByteString.length prefix =
      Left (ArtifactHeaderMalformed "a GGUF string length runs past the bounded prefix")
  | otherwise =
      let declared = decodeLittleEndian (sliceAt prefix offset 8)
          end = offset + 8 + fromInteger declared
       in if declared < 0 || end > ByteString.length prefix
            then Left (ArtifactHeaderMalformed "a GGUF string runs past the bounded prefix")
            else Right end

skipGgufValue :: ByteString -> Int -> Integer -> Either ArtifactHeaderError Int
skipGgufValue prefix offset valueType =
  case valueType of
    0 -> fixed 1
    1 -> fixed 1
    2 -> fixed 2
    3 -> fixed 2
    4 -> fixed 4
    5 -> fixed 4
    6 -> fixed 4
    7 -> fixed 1
    8 -> skipGgufString prefix offset
    9 -> skipArray
    10 -> fixed 8
    11 -> fixed 8
    12 -> fixed 8
    _ ->
      Left
        ( ArtifactHeaderMalformed
            ("the GGUF metadata declares the unknown value type " <> Text.pack (show valueType))
        )
  where
    fixed width
      | offset + width <= ByteString.length prefix = Right (offset + width)
      | otherwise =
          Left (ArtifactHeaderMalformed "a GGUF scalar runs past the bounded prefix")

    skipArray
      | offset + 12 > ByteString.length prefix =
          Left (ArtifactHeaderMalformed "a GGUF array header runs past the bounded prefix")
      | otherwise =
          let elementType = decodeLittleEndian (sliceAt prefix offset 4)
              elementCount = decodeLittleEndian (sliceAt prefix (offset + 4) 8)
           in skipArrayElements (offset + 12) elementType elementCount

    skipArrayElements cursor elementType remaining
      | remaining <= 0 = Right cursor
      | otherwise = do
          next <- skipGgufValue prefix cursor elementType
          skipArrayElements next elementType (remaining - 1)

readGgufTensorInfos ::
  ByteString ->
  Int ->
  Integer ->
  Either ArtifactHeaderError ([ArtifactTensor], Int)
readGgufTensorInfos prefix start count
  | count < 0 = Left (ArtifactHeaderMalformed "the GGUF tensor count is negative")
  | otherwise = go start count []
  where
    go offset remaining acc
      | remaining <= 0 = Right (reverse acc, offset)
      | otherwise = do
          nameEnd <- skipGgufString prefix offset
          let nameBytes = sliceAt prefix (offset + 8) (nameEnd - offset - 8)
              tensorName = TextEncoding.decodeUtf8Lenient nameBytes
          dimensionCount <- requireScalar nameEnd 4
          let dimensionsStart = nameEnd + 4
              dimensionWords = fromInteger dimensionCount
          _ <- requireScalar dimensionsStart (8 * dimensionWords)
          let shape =
                [ decodeLittleEndian (sliceAt prefix (dimensionsStart + 8 * index) 8)
                | index <- [0 .. dimensionWords - 1]
                ]
              typeOffset = dimensionsStart + 8 * dimensionWords
          ggmlType <- requireScalar typeOffset 4
          tensorOffset <- requireScalar (typeOffset + 4) 8
          tensorBytes <- ggufTensorBytes tensorName ggmlType (product shape)
          go
            (typeOffset + 12)
            (remaining - 1)
            ( ArtifactTensor
                { artifactTensorName = tensorName,
                  artifactTensorShape = shape,
                  artifactTensorBytes = tensorBytes,
                  artifactTensorOffset = tensorOffset
                }
                : acc
            )

    requireScalar offset width
      | offset + width <= ByteString.length prefix =
          Right (decodeLittleEndian (sliceAt prefix offset width))
      | otherwise =
          Left
            ( ArtifactHeaderMalformed
                "the GGUF tensor-info block runs past the bounded prefix this derivation reads"
            )

-- | Bytes one GGUF tensor occupies: block count times block size.
--
-- A block-quantized type has no whole-byte element width, so \"element count
-- times element width\" is stated as the same arithmetic over the type's own
-- block. An element count that is not a whole number of blocks is a refusal.
ggufTensorBytes :: Text -> Integer -> Integer -> Either ArtifactHeaderError Integer
ggufTensorBytes tensorName ggmlType elements =
  case ggmlTypeLayout ggmlType of
    Nothing ->
      Left
        ( ArtifactHeaderMalformed
            ( "GGUF tensor "
                <> tensorName
                <> " declares the unknown ggml type "
                <> Text.pack (show ggmlType)
            )
        )
    Just (blockElements, blockBytes)
      | blockElements <= 0 ->
          Left (ArtifactHeaderMalformed ("GGUF tensor " <> tensorName <> " has an empty block"))
      | elements `mod` blockElements /= 0 ->
          Left
            ( ArtifactTensorExtentMismatch
                tensorName
                elements
                blockElements
            )
      | otherwise -> Right ((elements `div` blockElements) * blockBytes)

-- | @(block element count, block byte size)@ for every ggml type this reader
-- admits. An absent type is refused rather than approximated.
ggmlTypeLayout :: Integer -> Maybe (Integer, Integer)
ggmlTypeLayout ggmlType =
  case ggmlType of
    0 -> Just (1, 4)
    1 -> Just (1, 2)
    2 -> Just (32, 18)
    3 -> Just (32, 20)
    6 -> Just (32, 22)
    7 -> Just (32, 24)
    8 -> Just (32, 34)
    9 -> Just (32, 40)
    10 -> Just (256, 84)
    11 -> Just (256, 110)
    12 -> Just (256, 144)
    13 -> Just (256, 176)
    14 -> Just (256, 210)
    15 -> Just (256, 292)
    16 -> Just (256, 66)
    17 -> Just (256, 74)
    18 -> Just (256, 98)
    19 -> Just (256, 50)
    20 -> Just (32, 18)
    21 -> Just (256, 110)
    22 -> Just (256, 82)
    23 -> Just (256, 136)
    24 -> Just (1, 1)
    25 -> Just (1, 2)
    26 -> Just (1, 4)
    27 -> Just (1, 8)
    28 -> Just (1, 8)
    29 -> Just (256, 56)
    30 -> Just (1, 2)
    _ -> Nothing

sliceAt :: ByteString -> Int -> Int -> ByteString
sliceAt bytes offset width = ByteString.take width (ByteString.drop offset bytes)

-- ---------------------------------------------------------------------------
-- shared completion
-- ---------------------------------------------------------------------------

-- | Check the invariants every reader shares and assemble the header.
--
-- The offsets must tile the payload densely from zero with no gap and no
-- overlap, and the header extent plus the payload extent must equal the file
-- size. A table that describes a smaller file than it occupies — or the same
-- bytes twice — is refused rather than summed.
completeArtifactHeader ::
  Integer ->
  Integer ->
  Integer ->
  ByteString ->
  [ArtifactTensor] ->
  Either ArtifactHeaderError ArtifactHeader
completeArtifactHeader alignment payloadStart fileBytes prefix tensors = do
  payloadExtent <- checkDenseTiling alignment (sortOn artifactTensorOffset tensors)
  let declaredTotal = payloadStart + payloadExtent
  if declaredTotal /= fileBytes
    then Left (ArtifactExtentMismatch declaredTotal fileBytes)
    else
      Right
        ArtifactHeader
          { artifactHeaderTensors = tensors,
            artifactHeaderWeightBytes = sum (map artifactTensorBytes tensors),
            artifactHeaderLargestTensorBytes =
              maximum (0 : map artifactTensorBytes tensors),
            artifactHeaderPrefixBytes = toInteger (ByteString.length prefix),
            artifactHeaderPrefixDigest = prefixDigest prefix,
            artifactHeaderFileBytes = fileBytes
          }

-- | Walk the table in offset order and require each entry to begin exactly
-- where the previous one ended, once that end is rounded up to the container's
-- own alignment.
--
-- Safetensors packs its payload with no padding at all, so its alignment is one
-- and the check is exact contiguity. GGUF aligns every tensor, so the same check
-- runs against the aligned cursor rather than the raw one — an alignment-blind
-- version would reject every real GGUF file whose tensor sizes are not multiples
-- of its alignment, which is most of them.
checkDenseTiling :: Integer -> [ArtifactTensor] -> Either ArtifactHeaderError Integer
checkDenseTiling alignment = go 0
  where
    go cursor [] = Right cursor
    go cursor (tensor : rest)
      | artifactTensorOffset tensor /= cursor =
          Left
            ( ArtifactTensorTilingBroken
                (artifactTensorName tensor)
                cursor
                (artifactTensorOffset tensor)
            )
      | otherwise = go (alignUp (cursor + artifactTensorBytes tensor) alignment) rest
