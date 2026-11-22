{-# LANGUAGE OverloadedStrings #-}

-- | The only streaming reader for internal objects. The callback and response
-- body never escape this module; memory and staged file growth are bounded.
module Infernix.Objects.BoundedHttp (copyObjectToHandle, readObjectPrefix, readObjectSuffix, readObjectEdges) where

import Data.ByteString qualified as ByteString
import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Network.HTTP.Client
  ( BodyReader,
    Manager,
    Request,
    ResponseTimeout,
    brRead,
    checkResponse,
    decompress,
    method,
    requestHeaders,
    responseBody,
    responseHeaders,
    responseStatus,
    responseTimeout,
    withResponse,
  )
import Network.HTTP.Types.Header (HeaderName, hContentEncoding, hContentLength, hContentRange)
import Network.HTTP.Types.Status (statusCode)
import System.IO (Handle)
import Text.Read (readMaybe)

data ObjectRead
  = ReadPrefix Int
  | ReadSuffix Int
  | ReadTaggedPrefix Int
  | ReadTaggedSuffix Int ByteString.ByteString
  | CopyToHandle Handle Integer

data ObjectReadResult
  = PrefixRead ByteString.ByteString Integer
  | TaggedRead ByteString.ByteString Integer ByteString.ByteString
  | ObjectCopied Integer

readObjectPrefix :: Request -> Manager -> ResponseTimeout -> Int -> IO (Maybe (ByteString.ByteString, Integer))
readObjectPrefix request manager requestTimeout requestedBytes = do
  outcome <- readObject request manager requestTimeout (ReadPrefix requestedBytes)
  pure $ case outcome of
    Right (PrefixRead bytes total) -> Just (bytes, total)
    _ -> Nothing

-- | Read a bounded tail and prove the returned offsets and total extent. A
-- server that ignores the range is accepted only for a complete short object.
readObjectSuffix :: Request -> Manager -> ResponseTimeout -> Int -> IO (Maybe (ByteString.ByteString, Integer))
readObjectSuffix request manager requestTimeout requestedBytes = do
  outcome <- readObject request manager requestTimeout (ReadSuffix requestedBytes)
  pure $ case outcome of
    Right (PrefixRead bytes total) -> Just (bytes, total)
    _ -> Nothing

-- | Read both bounded edges from one strong object version. The suffix request
-- is conditional on the prefix response's unique strong ETag.
readObjectEdges :: Request -> Manager -> ResponseTimeout -> Int -> Int -> IO (Maybe (ByteString.ByteString, ByteString.ByteString, Integer))
readObjectEdges request manager timeout prefixLimit suffixLimit = do
  first <- readObject request manager timeout (ReadTaggedPrefix prefixLimit)
  case first of
    Right (TaggedRead prefix total tag) -> do
      second <- readObject request manager timeout (ReadTaggedSuffix suffixLimit tag)
      pure $ case second of
        Right (TaggedRead suffix suffixTotal suffixTag)
          | total == suffixTotal && tag == suffixTag -> Just (prefix, suffix, total)
        _ -> Nothing
    _ -> pure Nothing

-- | Copy one complete object to an already-owned staging handle. A positive,
-- unambiguous content length must fit the caller's disk bound and match the
-- bytes actually received. This function does not publish or close the handle.
copyObjectToHandle :: Request -> Manager -> ResponseTimeout -> Integer -> Handle -> IO (Either Text Integer)
copyObjectToHandle request manager requestTimeout limit handle = do
  outcome <- readObject request manager requestTimeout (CopyToHandle handle limit)
  pure $ case outcome of
    Right (ObjectCopied bytes) -> Right bytes
    Right (PrefixRead _ _) -> Left "unexpected prefix response for object copy"
    Right TaggedRead {} -> Left "unexpected tagged response for object copy"
    Left reason -> Left reason

readObject :: Request -> Manager -> ResponseTimeout -> ObjectRead -> IO (Either Text ObjectReadResult)
readObject initialRequest manager requestTimeout operation
  | objectReadLimit operation <= 0 = pure (Left "object read bound must be positive")
  | otherwise = do
      let rangeHeaders = case operation of
            ReadPrefix requestedBytes ->
              [("Range", ByteString.concat ["bytes=0-", Text.encodeUtf8 (Text.pack (show (requestedBytes - 1)))])]
            ReadSuffix requestedBytes ->
              [("Range", ByteString.concat ["bytes=-", Text.encodeUtf8 (Text.pack (show requestedBytes))])]
            ReadTaggedPrefix requestedBytes ->
              [("Range", ByteString.concat ["bytes=0-", Text.encodeUtf8 (Text.pack (show (requestedBytes - 1)))])]
            ReadTaggedSuffix requestedBytes tag ->
              [("Range", ByteString.concat ["bytes=-", Text.encodeUtf8 (Text.pack (show requestedBytes))]), ("If-Match", tag)]
            CopyToHandle _ _ -> []
          request =
            initialRequest
              { method = "GET",
                requestHeaders = rangeHeaders <> [("Accept-Encoding", "identity")] <> requestHeaders initialRequest,
                checkResponse = \_ _ -> pure (),
                decompress = const False,
                responseTimeout = requestTimeout
              }
      withResponse request manager $ \response -> do
        let responseCode = statusCode (responseStatus response)
            headers = responseHeaders response
        if not (identityEncoding headers)
          then pure (Left "object response uses a content encoding")
          else inspectObjectResponse operation responseCode headers (responseBody response)

objectReadLimit :: ObjectRead -> Integer
objectReadLimit operation = case operation of
  ReadPrefix requestedBytes -> toInteger requestedBytes
  ReadSuffix requestedBytes -> toInteger requestedBytes
  ReadTaggedPrefix requestedBytes -> toInteger requestedBytes
  ReadTaggedSuffix requestedBytes _ -> toInteger requestedBytes
  CopyToHandle _ limit -> limit

inspectObjectResponse :: ObjectRead -> Int -> [(HeaderName, ByteString.ByteString)] -> BodyReader -> IO (Either Text ObjectReadResult)
inspectObjectResponse operation responseCode headers reader = case operation of
  ReadTaggedPrefix requestedBytes -> tagged (ReadPrefix requestedBytes)
  ReadTaggedSuffix requestedBytes _ -> tagged (ReadSuffix requestedBytes)
  ReadPrefix requestedBytes ->
    if responseCode /= 200 && responseCode /= 206
      then pure (Left "object prefix request did not succeed")
      else do
        maybeBody <- readBoundedBody requestedBytes reader
        pure $ do
          body <- maybe (Left "object prefix exceeds its bound") Right maybeBody
          total <- maybe (Left "object prefix has invalid extent metadata") Right (objectTotalBytes responseCode headers requestedBytes (ByteString.length body))
          Right (PrefixRead body total)
  ReadSuffix requestedBytes ->
    if responseCode /= 200 && responseCode /= 206
      then pure (Left "object suffix request did not succeed")
      else do
        maybeBody <- readBoundedBody requestedBytes reader
        pure $ do
          body <- maybe (Left "object suffix exceeds its bound") Right maybeBody
          total <- maybe (Left "object suffix has invalid extent metadata") Right (objectSuffixTotalBytes responseCode headers requestedBytes (ByteString.length body))
          Right (PrefixRead body total)
  CopyToHandle handle limit ->
    case completeObjectLength responseCode headers limit of
      Left reason -> pure (Left reason)
      Right expected -> fmap (fmap ObjectCopied) (copyBoundedBody expected handle reader)
  where
    tagged inner = do
      result <- inspectObjectResponse inner responseCode headers reader
      pure $ do
        tag <- strongTag headers
        case result of
          Right (PrefixRead bytes total) -> Right (TaggedRead bytes total tag)
          Left reason -> Left reason
          _ -> Left "unexpected tagged object response"

strongTag :: [(HeaderName, ByteString.ByteString)] -> Either Text ByteString.ByteString
strongTag headers = case [value | (name, value) <- headers, name == "ETag"] of
  [tag]
    | ByteString.length tag >= 2,
      ByteString.head tag == 34,
      ByteString.last tag == 34,
      not (ByteString.elem 34 (ByteString.tail (ByteString.init tag))) ->
        Right tag
  _ -> Left "object response has no unique strong ETag"

-- Stop after the first chunk that exceeds the bound. Closing the response on
-- refusal prevents the rest of the object from being buffered.
readBoundedBody :: Int -> BodyReader -> IO (Maybe ByteString.ByteString)
readBoundedBody limit reader = go 0 []
  where
    go size chunks = do
      chunk <- brRead reader
      if ByteString.null chunk
        then pure (Just (ByteString.concat (reverse chunks)))
        else do
          let chunkSize = ByteString.length chunk
          if chunkSize > limit - size
            then pure Nothing
            else go (size + chunkSize) (chunk : chunks)

copyBoundedBody :: Integer -> Handle -> BodyReader -> IO (Either Text Integer)
copyBoundedBody expected handle reader = go 0
  where
    go size = do
      chunk <- brRead reader
      if ByteString.null chunk
        then
          pure
            ( if size == expected
                then Right size
                else Left "object body ended before its declared extent"
            )
        else do
          let nextSize = size + toInteger (ByteString.length chunk)
          if nextSize > expected
            then pure (Left "object body exceeded its declared extent")
            else do
              ByteString.hPut handle chunk
              go nextSize

completeObjectLength :: Int -> [(HeaderName, ByteString.ByteString)] -> Integer -> Either Text Integer
completeObjectLength responseCode headers limit
  | responseCode /= 200 = Left "object download did not return a complete response"
  | not (null [() | (name, _) <- headers, name == hContentRange]) = Left "complete object response carried range metadata"
  | otherwise =
      case [value | (name, value) <- headers, name == hContentLength] of
        [rawLength] -> do
          lengthText <- either (const (Left "object length is not UTF-8")) Right (Text.decodeUtf8' rawLength)
          bytes <- maybe (Left "object length is invalid") Right (naturalNumber lengthText)
          if bytes > 0 && bytes <= limit
            then Right bytes
            else Left "object length is empty or exceeds the cache bound"
        _ -> Left "object response has no unique content length"

identityEncoding :: [(HeaderName, ByteString.ByteString)] -> Bool
identityEncoding headers =
  case [value | (name, value) <- headers, name == hContentEncoding] of
    [] -> True
    ["identity"] -> True
    _ -> False

objectTotalBytes :: Int -> [(HeaderName, ByteString.ByteString)] -> Int -> Int -> Maybe Integer
objectTotalBytes responseCode headers requestedBytes bodyLength =
  case (responseCode, [value | (name, value) <- headers, name == hContentRange]) of
    (200, []) -> Just (toInteger bodyLength)
    (206, [rawRange]) -> do
      rangeText <- either (const Nothing) Just (Text.decodeUtf8' rawRange)
      extentText <- Text.stripPrefix "bytes 0-" rangeText
      case Text.splitOn "/" extentText of
        [endText, totalText] -> do
          end <- naturalNumber endText
          total <- naturalNumber totalText
          let observed = toInteger bodyLength
          if total > 0 && end + 1 == observed && observed == min (toInteger requestedBytes) total
            then Just total
            else Nothing
        _ -> Nothing
    _ -> Nothing

objectSuffixTotalBytes :: Int -> [(HeaderName, ByteString.ByteString)] -> Int -> Int -> Maybe Integer
objectSuffixTotalBytes responseCode headers requestedBytes bodyLength =
  case (responseCode, [value | (name, value) <- headers, name == hContentRange]) of
    (200, []) -> do
      total <- either (const Nothing) Just (completeObjectLength responseCode headers (toInteger requestedBytes))
      if total == toInteger bodyLength then Just total else Nothing
    (206, [rawRange]) -> do
      rangeText <- either (const Nothing) Just (Text.decodeUtf8' rawRange)
      extentText <- Text.stripPrefix "bytes " rangeText
      case Text.splitOn "/" extentText of
        [rangePart, totalText] -> do
          total <- naturalNumber totalText
          case Text.splitOn "-" rangePart of
            [startText, endText] -> do
              start <- naturalNumber startText
              end <- naturalNumber endText
              let expected = min (toInteger requestedBytes) total
              if total > 0 && start == total - expected && end == total - 1 && toInteger bodyLength == expected
                then Just total
                else Nothing
            _ -> Nothing
        _ -> Nothing
    _ -> Nothing

naturalNumber :: Text -> Maybe Integer
naturalNumber value
  | Text.null value || not (Text.all isDigit value) = Nothing
  | otherwise = readMaybe (Text.unpack value)
