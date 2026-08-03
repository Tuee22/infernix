{-# LANGUAGE ScopedTypeVariables #-}

-- | Phase 6 Sprint 6.44 — the shared bounded-command invocation shape.
--
-- Compiling a closed 'Command.ClusterCommand' against the typed subprocess
-- environment and running it through
-- 'Infernix.Cluster.Subprocess.runBoundedCommand' is a single pattern that used
-- to exist only inside @Infernix.Cluster@. Every other module that needed a
-- bounded external command therefore either reached for a raw spawn or grew a
-- private copy of this three-step sequence. Hoisting it here is what let the
-- runtime transport and model-bootstrap paths come off the raw-spawn exemption
-- list without duplicating the setup/compile/kernel error provenance that the
-- managed-state-transition doctrine requires each step to keep distinct.
--
-- Canonical doctrine:
-- @documents\/architecture\/managed_state_transitions.md@.
module Infernix.Cluster.Invoke
  ( invokeClusterCommand,
    tryClusterCommand,
    commandOutcomeToEither,
    renderBoundedCommandOutcome,
  )
where

import Control.Exception (IOException, displayException, try)
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths)

-- | Run one closed cluster command and classify its total outcome as either a
-- diagnostic or captured standard output.
tryClusterCommand ::
  Paths ->
  Command.ClusterCommand ->
  IO (Either String String)
tryClusterCommand paths command =
  commandOutcomeToEither <$> invokeClusterCommand paths command

-- | Keep setup, compilation, kernel, terminal-command, and timeout provenance
-- intact until a caller explicitly chooses how each state may transition.
invokeClusterCommand ::
  Paths ->
  Command.ClusterCommand ->
  IO Subprocess.CommandOutcome
invokeClusterCommand paths command = do
  environmentResult <-
    try (Subprocess.clusterSubprocessEnv paths) :: IO (Either IOException Subprocess.SubprocessEnv)
  case environmentResult of
    Left err ->
      pure
        ( Subprocess.CommandFailedKernel
            ("command environment setup failed: " <> displayException err)
        )
    Right environment ->
      case Subprocess.compileBoundedCommand command environment of
        Left err ->
          pure
            ( Subprocess.CommandFailedKernel
                ("command compilation failed: " <> err)
            )
        Right boundedCommand -> Subprocess.runBoundedCommand boundedCommand

commandOutcomeToEither :: Subprocess.CommandOutcome -> Either String String
commandOutcomeToEither outcome =
  case outcome of
    Subprocess.CommandSucceeded stdoutOutput -> Right stdoutOutput
    Subprocess.CommandFailedFatal message -> Left message
    Subprocess.CommandFailedKernel message -> Left message
    Subprocess.CommandTimedOut timeoutValue ->
      Left (renderBoundedCommandOutcome (Subprocess.CommandTimedOut timeoutValue))

renderBoundedCommandOutcome :: Subprocess.CommandOutcome -> String
renderBoundedCommandOutcome outcome =
  case outcome of
    Subprocess.CommandSucceeded stdoutOutput -> stdoutOutput
    Subprocess.CommandFailedFatal message -> message
    Subprocess.CommandFailedKernel message -> message
    Subprocess.CommandTimedOut (Subprocess.Timeout micros) ->
      "command timed out after " <> show (micros `div` 1000000) <> "s"
