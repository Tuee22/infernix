{-# LANGUAGE OverloadedStrings #-}

-- | Phase 4 Sprint 4.50 — what a validation run has to hold before it may call
-- one inference a real success.
--
-- The static guards this repository already carries (the Python adapter AST
-- check and the Haskell fabrication lint) bound what adapter *source* may say.
-- They are syntactic, and they are worth keeping, but they cannot decide the
-- proposition a passing suite actually claims: that a model ran and that the
-- bytes returned came from it. A transform that returns a plausible constant
-- passes every one of them.
--
-- So the claim is made here instead, from evidence a run collects rather than
-- from source it reads. Four facts are required of every asserted success, and
-- a fifth of every family whose output is a function of the prompt:
--
--   1. the result names the model the case asked for;
--   2. an engine invocation was observed, rather than a result appearing
--      without one;
--   3. the case's input was chosen and is non-degenerate, so a blank or
--      trivial prompt cannot make a trivial answer look responsive;
--   4. the output validated for its family — inline text containing a letter or digit, or
--      an artifact with a positive extent;
--   5. for a prompt-sensitive family, two independently chosen inputs produced
--      two different outputs.
--
-- Point 5 is the one a constant cannot survive, and it is why the acceptance
-- takes a case rather than a result: a single observation, however well shaped,
-- is consistent with an adapter that ignores its input entirely.
--
-- What this does not establish: that the output is *correct*, that the weights
-- were the intended ones, or that an adversary controlling the executor and the
-- evidence store together could not construct a passing case. Those are the
-- trust-boundary limits the testing doctrine states; this module bounds the
-- accidental substitutions, not a determined forgery.
module Infernix.Runtime.Realness
  ( InferenceExecutionObservation (..),
    RealInferenceCase (..),
    RealnessRefusal (..),
    acceptArtifactInference,
    acceptInputSensitiveInference,
    minimumNondegenerateInputCharacters,
    realnessRefusalText,
    sourceSeparationArchiveHasStems,
  )
where

import Data.Bits (complement, shiftR, xor, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (isAlphaNum, isSpace)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32)

-- | Inspect the uncompressed local entries produced by the source-separation
-- adapter, including matching directory entries and CRCs. It does not prove
-- the stems came from a model.
sourceSeparationArchiveHasStems :: ByteString -> Bool
sourceSeparationArchiveHasStems bytes =
  case walk 0 [] of
    Just entries -> length entries >= 2 && length (nub (map firstName entries)) == length entries
    Nothing -> False
  where
    firstName (name, _, _, _) = name
    walk offset entries
      | slice offset 4 == "PK\ETX\EOT" = do
          header <- section offset 30
          let flags = number (ByteString.take 2 (ByteString.drop 6 header))
              method = number (ByteString.take 2 (ByteString.drop 8 header))
              compressed = number (ByteString.take 4 (ByteString.drop 18 header))
              uncompressed = number (ByteString.take 4 (ByteString.drop 22 header))
              checksum = number (ByteString.take 4 (ByteString.drop 14 header))
              nameLength = number (ByteString.take 2 (ByteString.drop 26 header))
              extraLength = number (ByteString.take 2 (ByteString.drop 28 header))
              nameOffset = offset + 30
              dataOffset = nameOffset + nameLength + extraLength
          if flags /= 0 || method /= 0 || compressed /= uncompressed
            then Nothing
            else do
              name <- section nameOffset nameLength
              payload <- section dataOffset compressed
              if not (".wav" `ByteString.isSuffixOf` name) || not (wavHasSignal payload) || toInteger (crc32 payload) /= toInteger checksum
                then Nothing
                else walk (dataOffset + compressed) ((name, offset, compressed, checksum) : entries)
      | slice offset 4 == "PK\SOH\STX" = checkDirectory offset offset (reverse entries) entries
      | otherwise = Nothing
    checkDirectory start offset remaining entries =
      case remaining of
        [] -> do
          end <- section offset 22
          let field position width = number (ByteString.take width (ByteString.drop position end))
              commentLength = field 20 2
          if ByteString.take 4 end == "PK\ENQ\ACK"
            && field 4 2 == 0
            && field 6 2 == 0
            && field 8 2 == length entries
            && field 10 2 == length entries
            && field 12 4 == offset - start
            && field 16 4 == start
            && offset + 22 + commentLength == ByteString.length bytes
            then Just entries
            else Nothing
        (name, localOffset, size, checksum) : rest -> do
          header <- section offset 46
          let field position width = number (ByteString.take width (ByteString.drop position header))
              nameLength = field 28 2
              extraLength = field 30 2
              commentLength = field 32 2
              next = offset + 46 + nameLength + extraLength + commentLength
          centralName <- section (offset + 46) nameLength
          _ <- section offset (next - offset)
          if ByteString.take 4 header == "PK\SOH\STX"
            && field 8 2 == 0
            && field 10 2 == 0
            && field 16 4 == checksum
            && field 20 4 == size
            && field 24 4 == size
            && field 34 2 == 0
            && field 42 4 == localOffset
            && centralName == name
            then checkDirectory start next rest entries
            else Nothing
    slice offset width = ByteString.take width (ByteString.drop offset bytes)
    section offset width
      | offset >= 0 && width >= 0 && offset <= ByteString.length bytes - width = Just (slice offset width)
      | otherwise = Nothing
    number = ByteString.foldr' (\byte total -> fromIntegral byte + 256 * total) 0

crc32 :: ByteString -> Word32
crc32 = complement . ByteString.foldl' update (complement 0)
  where
    update value byte = rounds (8 :: Int) (value `xor` fromIntegral byte)
    rounds 0 value = value
    rounds count value = rounds (count - 1) (step value)
    step value = (value `shiftR` 1) `xor` if value .&. 1 == 1 then 0xedb88320 else 0

wavHasSignal :: ByteString -> Bool
wavHasSignal bytes =
  ByteString.take 4 bytes == "RIFF"
    && ByteString.take 4 (ByteString.drop 8 bytes) == "WAVE"
    && number (ByteString.take 4 (ByteString.drop 4 bytes)) == ByteString.length bytes - 8
    && walk 12 Nothing
  where
    number = ByteString.foldr' (\byte total -> fromIntegral byte + 256 * total) 0
    walk offset format
      | offset > ByteString.length bytes - 8 = False
      | otherwise =
          let chunk = ByteString.take 4 (ByteString.drop offset bytes)
              size = number (ByteString.take 4 (ByteString.drop (offset + 4) bytes))
              start = offset + 8
              field position width = number (ByteString.take width (ByteString.drop (start + position) bytes))
           in size <= ByteString.length bytes - start
                && if chunk == "fmt "
                  then
                    size >= 16
                      && field 0 2 == 1
                      && field 2 2 > 0
                      && field 4 4 > 0
                      && field 14 2 == 16
                      && field 12 2 == field 2 2 * 2
                      && walk (start + size + size `mod` 2) (Just (field 12 2))
                  else
                    if chunk == "data"
                      then validData format start size
                      else walk (start + size + size `mod` 2) format
    validData format start size =
      case format of
        Just block -> size >= block && size `mod` block == 0 && ByteString.any (/= 0) (ByteString.take size (ByteString.drop start bytes))
        Nothing -> False

-- | One observed execution: the input it was given, the identity and terminal
-- status the result carried, whether an engine invocation was actually
-- observed, and the output that came back.
data InferenceExecutionObservation = InferenceExecutionObservation
  { -- | The input this observation supplied. Chosen by the case, never derived
    -- from the answer.
    observationInput :: Text,
    -- | The model identity the result carried.
    observationResultModelId :: Text,
    -- | The result's terminal status.
    observationStatus :: Text,
    -- | Whether the run observed an engine invocation for this request. A
    -- result without one is a substituted result, whatever it contains.
    observationEngineExecuted :: Bool,
    -- | Inline output, for the families that carry one.
    observationInlineOutput :: Maybe Text,
    -- | The artifact's observed extent, for the families that carry one.
    observationArtifactBytes :: Maybe Integer
  }
  deriving (Eq, Show)

-- | The evidence for one model's asserted successful inference.
data RealInferenceCase = RealInferenceCase
  { realCaseModelId :: Text,
    realCaseObservations :: [InferenceExecutionObservation]
  }
  deriving (Eq, Show)

-- | Why a case is not evidence of a real inference. Each arm names the fact
-- that was missing, so a failing gate says which substitution it caught.
data RealnessRefusal
  = -- | The case supplied fewer observations than its acceptance requires.
    RealnessTooFewObservations Int Int
  | -- | Two observations reused one input, so a difference between their
    -- outputs would prove nothing.
    RealnessInputsNotIndependent Text
  | -- | An input was blank or too short to distinguish a responsive answer
    -- from a canned one.
    RealnessDegenerateInput Text
  | -- | A result did not reach the terminal completed status.
    RealnessNonTerminalOutcome Text
  | -- | A result named a different model than the case requested.
    RealnessModelIdentityMismatch Text Text
  | -- | No engine invocation was observed for a result.
    RealnessNoExecutionObserved Text
  | -- | The output did not validate for its family.
    RealnessEmptyOutput Text
  | -- | Every independently chosen input produced the same output.
    RealnessConstantOutput Text
  deriving (Eq, Show)

realnessRefusalText :: RealnessRefusal -> Text
realnessRefusalText refusal =
  case refusal of
    RealnessTooFewObservations required observed ->
      "the case supplies "
        <> Text.pack (show observed)
        <> " observations where this acceptance requires "
        <> Text.pack (show required)
    RealnessInputsNotIndependent modelIdValue ->
      "two observations for "
        <> modelIdValue
        <> " reused one input, so differing output would establish nothing"
    RealnessDegenerateInput modelIdValue ->
      "an input for "
        <> modelIdValue
        <> " is blank or shorter than "
        <> Text.pack (show minimumNondegenerateInputCharacters)
        <> " characters, which a canned answer would also satisfy"
    RealnessNonTerminalOutcome statusValue ->
      "the result status is "
        <> statusValue
        <> " rather than completed, so nothing about its output is a success"
    RealnessModelIdentityMismatch requested observed ->
      "the result names model "
        <> observed
        <> " while the case requested "
        <> requested
    RealnessNoExecutionObserved modelIdValue ->
      "no engine invocation was observed for "
        <> modelIdValue
        <> ", so the result did not come from one"
    RealnessEmptyOutput modelIdValue ->
      "the result for "
        <> modelIdValue
        <> " carries no validated output for its family"
    RealnessConstantOutput modelIdValue ->
      "every independently chosen input produced the same output for "
        <> modelIdValue
        <> ", which is what a constant-returning transform produces"

-- | The shortest input this acceptance treats as a real choice. Short enough
-- that ordinary fixtures clear it, long enough that a one-character prompt
-- cannot stand in for one.
minimumNondegenerateInputCharacters :: Int
minimumNondegenerateInputCharacters = 8

-- | Accept a prompt-sensitive family's success. Requires the four common facts
-- of every observation plus two independently chosen inputs whose outputs
-- differ.
acceptInputSensitiveInference :: RealInferenceCase -> Either RealnessRefusal ()
acceptInputSensitiveInference realCase = do
  requireObservationCount 2 realCase
  mapM_ (acceptOneObservation (realCaseModelId realCase)) observations
  requireIndependentInputs realCase
  requireDistinctOutputs realCase
  where
    observations = realCaseObservations realCase

-- | Accept an artifact family's success. The output is bytes rather than a
-- function of the prompt, so the input-sensitivity requirement does not apply;
-- the identity, execution, input, and validated-output facts still do.
acceptArtifactInference :: RealInferenceCase -> Either RealnessRefusal ()
acceptArtifactInference realCase = do
  requireObservationCount 1 realCase
  mapM_ (acceptOneObservation (realCaseModelId realCase)) (realCaseObservations realCase)

requireObservationCount :: Int -> RealInferenceCase -> Either RealnessRefusal ()
requireObservationCount required realCase
  | observed >= required = Right ()
  | otherwise = Left (RealnessTooFewObservations required observed)
  where
    observed = length (realCaseObservations realCase)

acceptOneObservation :: Text -> InferenceExecutionObservation -> Either RealnessRefusal ()
acceptOneObservation requestedModelId observation
  | observationStatus observation /= "completed" =
      Left (RealnessNonTerminalOutcome (observationStatus observation))
  | observationResultModelId observation /= requestedModelId =
      Left
        ( RealnessModelIdentityMismatch
            requestedModelId
            (observationResultModelId observation)
        )
  | not (observationEngineExecuted observation) =
      Left (RealnessNoExecutionObserved requestedModelId)
  | not (inputIsNondegenerate (observationInput observation)) =
      Left (RealnessDegenerateInput requestedModelId)
  | not (outputValidates observation) =
      Left (RealnessEmptyOutput requestedModelId)
  | otherwise = Right ()

inputIsNondegenerate :: Text -> Bool
inputIsNondegenerate inputValue =
  Text.length trimmed >= minimumNondegenerateInputCharacters
  where
    trimmed = Text.dropWhile isSpace (Text.dropWhileEnd isSpace inputValue)

outputValidates :: InferenceExecutionObservation -> Bool
outputValidates observation =
  inlineValidates || artifactValidates
  where
    inlineValidates =
      case observationInlineOutput observation of
        Just text -> Text.any isAlphaNum text
        Nothing -> False
    artifactValidates =
      case observationArtifactBytes observation of
        Just observedBytes -> observedBytes > 0
        Nothing -> False

requireIndependentInputs :: RealInferenceCase -> Either RealnessRefusal ()
requireIndependentInputs realCase
  | length (nub inputs) == length inputs = Right ()
  | otherwise = Left (RealnessInputsNotIndependent (realCaseModelId realCase))
  where
    inputs = map observationInput (realCaseObservations realCase)

requireDistinctOutputs :: RealInferenceCase -> Either RealnessRefusal ()
requireDistinctOutputs realCase
  | length (nub outputs) > 1 = Right ()
  | otherwise = Left (RealnessConstantOutput (realCaseModelId realCase))
  where
    outputs = map comparableOutput (realCaseObservations realCase)
    comparableOutput observation =
      ( observationInlineOutput observation,
        observationArtifactBytes observation
      )
