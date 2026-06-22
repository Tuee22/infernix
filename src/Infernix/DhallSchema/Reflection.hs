{-# LANGUAGE OverloadedStrings #-}

module Infernix.DhallSchema.Reflection
  ( renderDecoderExpected,
  )
where

import Data.Either.Validation (Validation (Failure, Success))
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall.Core qualified as DhallCore
import Dhall.Marshal.Decode qualified as DhallDecode

renderDecoderExpected :: DhallDecode.Decoder a -> Either String Text
renderDecoderExpected decoder =
  case DhallDecode.expected decoder of
    Failure _ ->
      Left "Dhall decoder did not expose a finite expected type expression"
    Success expectedExpression ->
      Right (normalizeTrailingNewline (DhallCore.pretty expectedExpression))

normalizeTrailingNewline :: Text -> Text
normalizeTrailingNewline value =
  Text.dropWhileEnd (== '\n') value <> "\n"
