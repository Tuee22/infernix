-- | Primary-preserving cleanup combinators used by the capped-engine process
-- region. Keeping this small boundary separate makes failure injection
-- possible without exposing process handles or raw commands.
module Infernix.Runtime.CappedEngine.Cleanup
  ( runCappedEngineCleanup,
    withCappedEngineCleanupBoundary,
  )
where

import Control.Monad (void)
import Infernix.Error
  ( bracketPreservingPrimary,
    runCleanupsPreservingFailures,
  )

withCappedEngineCleanupBoundary ::
  IO resource ->
  (resource -> IO cleanup) ->
  (resource -> IO result) ->
  IO result
withCappedEngineCleanupBoundary =
  bracketPreservingPrimary

runCappedEngineCleanup ::
  [IO ()] ->
  IO terminal ->
  IO ()
runCappedEngineCleanup cleanups reap =
  runCleanupsPreservingFailures (cleanups <> [void reap])
