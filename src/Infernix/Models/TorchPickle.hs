{-# LANGUAGE OverloadedStrings #-}

-- Non-executing, bounded reader for the protocol-2 checkpoint metadata. This
-- module describes persistent tensor storages; it never imports or calls a
-- pickle GLOBAL or REDUCE target.
module Infernix.Models.TorchPickle (readTorchStorages) where

import Control.Monad (unless, when)
import Data.Bits (shiftL)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.Int (Int32)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Word (Word8)

data Value = Marker | Unknown | StringValue !Text | NumberValue !Integer | GlobalValue !Text !Text | TupleValue ![Value]
  deriving (Eq, Show)

data Scan = Scan
  { scanOffset :: !Int,
    scanStack :: ![Value],
    scanMemo :: !(Map Int Value),
    scanStorages :: !(Map Text Integer),
    scanSteps :: !Int
  }

-- The byte input is itself bounded by the ZIP metadata budget. Step, stack,
-- memo, string and storage limits prevent compact opcodes from expanding that
-- budget into an unbounded in-memory interpreter state. Each opcode pushes at
-- most one stack value, so the step limit also bounds stack depth.
readTorchStorages :: ByteString -> Either Text (Map Text Integer)
readTorchStorages bytes
  | BS.length bytes > 1048576 = Left "pickle metadata exceeds the bounded checkpoint metadata budget"
  | BS.take 2 bytes /= BS.pack [0x80, 2] = Left "checkpoint pickle is not protocol 2"
  | otherwise = loop (Scan 2 [] Map.empty Map.empty 0)
  where
    loop state = do
      when (scanSteps state >= 200000 || Map.size (scanMemo state) > 100000) $
        Left "checkpoint pickle exceeds interpreter bounds"
      (op, afterOp) <- byteAt bytes (scanOffset state)
      let next = state {scanOffset = afterOp, scanSteps = scanSteps state + 1}
      case op of
        0x2e -> do
          unless (afterOp == BS.length bytes && length (scanStack state) == 1 && not (Map.null (scanStorages state))) $
            Left "checkpoint pickle has a trailing payload or an incomplete stack"
          Right (scanStorages state)
        0x28 -> loop (push Marker next)
        0x7d -> loop (push Unknown next)
        0x5d -> loop (push Unknown next)
        0x29 -> loop (push (TupleValue []) next)
        0x4e -> loop (push Unknown next)
        0x88 -> loop (push Unknown next)
        0x89 -> loop (push Unknown next)
        0x4b -> scalar bytes next 1 >>= loop
        0x4d -> scalar bytes next 2 >>= loop
        0x4a -> do
          (raw, off) <- unsignedAt bytes afterOp 4
          let signed = toInteger (fromIntegral raw :: Int32)
          loop (push (NumberValue signed) next {scanOffset = off})
        0x47 -> do
          (_, off) <- bytesAt bytes afterOp 8
          loop (push Unknown next {scanOffset = off})
        0x58 -> do
          (size, off) <- unsignedAt bytes afterOp 4
          when (size > 1048576) (Left "pickle string exceeds its bound")
          (raw, end) <- bytesAt bytes off (fromInteger size)
          value <- either (const (Left "pickle string is not UTF-8")) Right (Text.decodeUtf8' raw)
          loop (push (StringValue value) next {scanOffset = end})
        0x63 -> do
          (moduleName, off) <- lineAt bytes afterOp
          (name, end) <- lineAt bytes off
          unless ((moduleName, name) `elem` allowedGlobals) (Left "unsupported checkpoint pickle global")
          loop (push (GlobalValue moduleName name) next {scanOffset = end})
        0x71 -> memoWrite bytes next 1 >>= loop
        0x72 -> memoWrite bytes next 4 >>= loop
        0x68 -> memoRead bytes next 1 >>= loop
        0x6a -> memoRead bytes next 4 >>= loop
        0x74 -> tupleFromMarker next >>= loop
        0x85 -> tupleN 1 next >>= loop
        0x86 -> tupleN 2 next >>= loop
        0x87 -> tupleN 3 next >>= loop
        0x51 -> persistentId next >>= loop
        0x52 -> reduce next >>= loop
        0x62 -> discardOne next >>= loop
        0x61 -> discardOne next >>= loop
        0x65 -> discardToMarker next >>= loop
        0x75 -> discardToMarker next >>= loop
        _ -> Left ("unsupported checkpoint pickle opcode " <> Text.pack (show op))

push :: Value -> Scan -> Scan
push value state = state {scanStack = value : scanStack state}

byteAt :: ByteString -> Int -> Either Text (Word8, Int)
byteAt input offset
  | offset < 0 || offset >= BS.length input = Left "truncated checkpoint pickle"
  | otherwise = Right (BS.index input offset, offset + 1)

bytesAt :: ByteString -> Int -> Int -> Either Text (ByteString, Int)
bytesAt input offset size
  | offset < 0 || size < 0 || offset > BS.length input - size = Left "truncated checkpoint pickle operand"
  | otherwise = Right (BS.take size (BS.drop offset input), offset + size)

unsignedAt :: ByteString -> Int -> Int -> Either Text (Integer, Int)
unsignedAt input offset width = do
  (raw, end) <- bytesAt input offset width
  pure (sum [toInteger value `shiftL` (8 * index) | (index, value) <- zip [0 ..] (BS.unpack raw)], end)

scalar :: ByteString -> Scan -> Int -> Either Text Scan
scalar input state width = do
  (value, end) <- unsignedAt input (scanOffset state) width
  pure (push (NumberValue value) state {scanOffset = end})

lineAt :: ByteString -> Int -> Either Text (Text, Int)
lineAt input offset = do
  let remaining = BS.drop offset input
      (line, terminator) = BS.break (== 10) remaining
  when (BS.null terminator || BS.length line > 256) (Left "invalid checkpoint pickle global")
  value <- either (const (Left "pickle global is not UTF-8")) Right (Text.decodeUtf8' line)
  pure (value, offset + BS.length line + 1)

memoWrite :: ByteString -> Scan -> Int -> Either Text Scan
memoWrite input state width = do
  (index, end) <- unsignedAt input (scanOffset state) width
  value <- memoStackTop (scanStack state)
  when (index > 100000) (Left "pickle memo index exceeds its bound")
  pure state {scanOffset = end, scanMemo = Map.insert (fromInteger index) value (scanMemo state)}

memoStackTop :: [Value] -> Either Text Value
memoStackTop stack = case stack of
  top : _ -> Right top
  _ -> Left "pickle memo write has an empty stack"

memoRead :: ByteString -> Scan -> Int -> Either Text Scan
memoRead input state width = do
  (index, end) <- unsignedAt input (scanOffset state) width
  when (index > 100000) (Left "pickle memo index exceeds its bound")
  value <- maybe (Left "pickle references an absent memo entry") Right (Map.lookup (fromInteger index) (scanMemo state))
  pure (push value state {scanOffset = end})

tupleFromMarker :: Scan -> Either Text Scan
tupleFromMarker state = do
  (items, remainder) <- splitMarker (scanStack state)
  pure state {scanStack = TupleValue (reverse items) : remainder}

tupleN :: Int -> Scan -> Either Text Scan
tupleN size state =
  let (items, rest) = splitAt size (scanStack state)
   in if length items == size && Marker `notElem` items
        then Right state {scanStack = TupleValue (reverse items) : rest}
        else Left "pickle tuple has an incomplete stack"

splitMarker :: [Value] -> Either Text ([Value], [Value])
splitMarker stack = case break (== Marker) stack of
  (items, Marker : rest) -> Right (items, rest)
  _ -> Left "pickle mark is absent"

discardToMarker :: Scan -> Either Text Scan
discardToMarker state = do
  (_, rest) <- splitMarker (scanStack state)
  case rest of
    [] -> Left "pickle container is absent"
    _ -> Right state {scanStack = rest}

discardOne :: Scan -> Either Text Scan
discardOne state = case scanStack state of
  _ : _ : rest -> Right state {scanStack = Unknown : rest}
  _ -> Left "pickle operation has an incomplete stack"

reduce :: Scan -> Either Text Scan
reduce state = case scanStack state of
  _args : GlobalValue moduleName name : rest
    | (moduleName, name) `elem` allowedReductions -> Right state {scanStack = Unknown : rest}
  _ -> Left "unsupported checkpoint pickle reduction"

persistentId :: Scan -> Either Text Scan
persistentId state = case scanStack state of
  TupleValue [StringValue "storage", GlobalValue "torch" storageType, StringValue key, StringValue _, NumberValue count] : rest -> do
    width <- maybe (Left "unsupported checkpoint storage type") Right (Map.lookup storageType storageWidths)
    unless (not (Text.null key) && Text.all isDigit key && count >= 0) $
      Left "invalid checkpoint storage identity"
    let size = count * width
    when (size > 18446744073709551615 || Map.size (scanStorages state) >= 65535) $
      Left "checkpoint storage exceeds its bound"
    case Map.lookup key (scanStorages state) of
      Just previous | previous /= size -> Left "conflicting checkpoint storage declaration"
      _ -> pure state {scanStack = Unknown : rest, scanStorages = Map.insert key size (scanStorages state)}
  _ -> Left "unsupported checkpoint pickle persistent identity"

allowedGlobals :: [(Text, Text)]
allowedGlobals = allowedReductions <> [("demucs.htdemucs", "HTDemucs")] <> [("torch", name) | name <- Map.keys storageWidths]

allowedReductions :: [(Text, Text)]
allowedReductions =
  [ ("fractions", "Fraction"),
    ("torch._utils", "_rebuild_tensor_v2"),
    ("collections", "OrderedDict"),
    ("numpy.core.multiarray", "scalar"),
    ("numpy", "dtype"),
    ("_codecs", "encode")
  ]

storageWidths :: Map Text Integer
storageWidths = Map.fromList [("HalfStorage", 2), ("FloatStorage", 4), ("DoubleStorage", 8), ("LongStorage", 8), ("IntStorage", 4), ("ShortStorage", 2), ("CharStorage", 1), ("ByteStorage", 1), ("BoolStorage", 1)]
