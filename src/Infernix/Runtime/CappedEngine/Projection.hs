{-# LANGUAGE OverloadedStrings #-}

-- | Phase 4 Sprint 4.43 — the engine's own projection of what it needs.
--
-- The derivation in "Infernix.Models.Requirement" is correct about what it
-- models and silent about what it does not. It sums the checkpoint's tensor
-- table for the weight term and closes the key/value cache term from the
-- declared geometry and the execution shape. What it does not model is the
-- engine's own working set — @ggml@'s compute buffers, its graph scratch, and
-- backend allocation overhead — and that shortfall is not recoverable by making
-- the two modelled terms more precise, because it belongs to a third term the
-- artifact does not describe.
--
-- The engine knows it. This module is the closed specification for asking: the
-- caller supplies no command text, only the model payload the invocation already
-- resolved and the execution literals that same invocation renders. What comes
-- back is a quantity, or a refusal.
--
-- The projection is only ever used to /widen/ a ceiling — the installed value is
-- the greater of the derived and the projected quantity — so the derivation stays
-- authoritative wherever it is larger.
module Infernix.Runtime.CappedEngine.Projection
  ( EngineProjectionRequest,
    LlamaNativeExecution (..),
    engineProjectionRequest,
    llamaNativeExecutionArguments,
    projectionExecutableName,
    projectionArguments,
    parseEngineProjectionMib,
  )
where

import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

-- | The execution literals one native llama invocation runs under.
--
-- Both the engine invocation and its projection probe render from this one
-- value, so a projection can never describe a different execution than the one
-- that runs. That mattered enough to be a value rather than two matching
-- literals: a probe asked about a 2048-token context while the engine runs 512
-- reports a number about work the machine will not do, which is the same class
-- of defect as an authored constant that disagrees with the model it describes.
data LlamaNativeExecution = LlamaNativeExecution
  { llamaExecutionContextLength :: !Int,
    llamaExecutionGenerationBound :: !Int,
    llamaExecutionThreads :: !Int,
    llamaExecutionGpuLayers :: !Int
  }
  deriving (Eq, Show)

-- | The shared operands, in the order both renderers emit them.
llamaNativeExecutionArguments :: FilePath -> LlamaNativeExecution -> [String]
llamaNativeExecutionArguments payloadPath execution =
  [ "--model",
    payloadPath,
    "--n-predict",
    show (llamaExecutionGenerationBound execution),
    "--ctx-size",
    show (llamaExecutionContextLength execution),
    "--threads",
    show (llamaExecutionThreads execution),
    "--gpu-layers",
    show (llamaExecutionGpuLayers execution)
  ]

-- | A probe. Its constructor is hidden and 'engineProjectionRequest' is the only
-- mint, so no caller can name an executable or an argument vector of its own.
--
-- The executable is a /file name/ rather than a path: the launcher resolves it
-- as a sibling of the validated entry object, inside the same sealed immutable
-- closure root the artifact's own evidence already binds, so the probe cannot be
-- pointed anywhere the engine itself is not.
data EngineProjectionRequest = EngineProjectionRequest
  { projectionExecutableName :: FilePath,
    projectionArguments :: [String]
  }
  deriving (Eq, Show)

-- | The closed per-family projection catalog.
--
-- @Nothing@ is a positive statement rather than an omission: that engine family
-- ships no projection tool, so its ceiling is the artifact-derived quantity and
-- its provenance says exactly that. It is not the same outcome as a probe that
-- was asked and failed, which is a typed refusal at the call site.
--
-- llama.cpp ships @llama-fit-params@ in the same pinned payload as the
-- completion front-end, and @-fitp on@ makes it print its estimated required
-- memory and exit without loading the model.
engineProjectionRequest ::
  Text ->
  FilePath ->
  LlamaNativeExecution ->
  Maybe EngineProjectionRequest
engineProjectionRequest adapterId payloadPath execution =
  case adapterId of
    "llama-cpp-cli" ->
      Just
        EngineProjectionRequest
          { projectionExecutableName = "llama-fit-params",
            projectionArguments =
              llamaNativeExecutionArguments payloadPath execution
                <> ["-fitp", "on"]
          }
    _ -> Nothing

-- | Read the projection out of the probe's standard output.
--
-- @llama-fit-params@ writes one row per device, each a device name followed by
-- the model, context, and compute estimates in MiB. The host row is the one a
-- data-segment ceiling charges, so a device row is read and deliberately not
-- summed into it: a ceiling on host memory that included device buffers would
-- be wrong in the direction that hides a real bound.
--
-- Every failure is a refusal. An output with no rows, no host row, a row whose
-- quantities do not parse, or a non-positive total yields a reason rather than a
-- small number, because a projection that could not be read is exactly the
-- moment a fallback would be consulted and exactly the moment nothing has been
-- established.
parseEngineProjectionMib :: Text -> Either Text Int
parseEngineProjectionMib output
  | null rows =
      Left
        "the engine's projection probe produced no device row of the form <device> <model> <context> <compute>"
  | otherwise =
      case [total | (device, total) <- rows, device == hostProjectionRow] of
        [] ->
          Left
            ( "the engine's projection probe reported no "
                <> hostProjectionRow
                <> " row, only "
                <> Text.intercalate ", " (map fst rows)
            )
        total : _
          | total > 0 -> Right total
          | otherwise ->
              Left "the engine's projection probe reported a non-positive host quantity"
  where
    rows = [row | line <- Text.lines output, Just row <- [projectionRow line]]

-- | The device name llama.cpp gives the host backend.
hostProjectionRow :: Text
hostProjectionRow = "Host"

-- | One @\<device> \<model> \<context> \<compute>@ row, or nothing.
projectionRow :: Text -> Maybe (Text, Int)
projectionRow line =
  case Text.words (Text.strip line) of
    [device, modelMib, contextMib, computeMib]
      | not (Text.null device) ->
          (,) device . sum <$> traverse readMib [modelMib, contextMib, computeMib]
    _ -> Nothing
  where
    readMib value
      | not (Text.null value) && Text.all isDigit value =
          readMaybe (Text.unpack value)
      | otherwise = Nothing
