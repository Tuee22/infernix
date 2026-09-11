{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 7 Sprint 7.32 — cancelling the execution, not only the conversation.
--
-- A cancel used to be a conversation event and nothing more. The projection
-- resolved the prompt, the browser stopped waiting, and the engine kept running
-- to completion with its weights loaded and its device arena held — so the work
-- the user cancelled still cost everything it was going to cost, and its result
-- arrived afterwards for a prompt the conversation had already closed.
--
-- Two things have to be true for a cancellation to mean what it says. The
-- running computation has to stop, with its process tree reaped and its
-- resources released; and the execution authority has to stay held until that
-- cleanup is established, because the dispatcher may queue and dispatch the
-- cancelled prompt's successor the moment the projection resolves. Receiving a
-- cancellation is not permission for the next execution to start — the previous
-- one finishing is.
--
-- The registry here owns both. An execution registers itself for the duration
-- of its own run; a cancellation delivers an asynchronous interrupt to exactly
-- that execution and then waits for it to report terminal, which it does from
-- the same bracket that terminates and reaps its engine child. A cancellation
-- for an execution that is not running is reported as such rather than being
-- silently dropped, because the queued and running cases resolve differently
-- and the caller has to tell them apart.
module Infernix.Runtime.Cancellation
  ( CancellationOutcome (..),
    CancellationRegistry,
    ExecutionIdentity (..),
    cancellationOutcomeLabel,
    newCancellationRegistry,
    registeredExecutionCount,
    requestCancellation,
    withCancellableExecution,
  )
where

import Control.Concurrent (ThreadId, forkIO, myThreadId, throwTo)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar)
import Control.Exception (AsyncException (ThreadKilled))
import Data.Aeson (FromJSON, ToJSON)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import GHC.Generics (Generic)
import Infernix.Error (finallyPreservingPrimary)
import System.Timeout (timeout)

-- | Which execution a cancellation names. The user-prompt message id is the
-- request's stable durable identity, and it is what a cancel event carries, so
-- the two cannot drift apart.
data ExecutionIdentity = ExecutionIdentity
  { executionTenant :: Text,
    executionContext :: Text,
    executionPromptMessageId :: Text
  }
  deriving (Eq, Generic, Ord, Show)

instance ToJSON ExecutionIdentity

instance FromJSON ExecutionIdentity

-- | One registered execution: the thread running it and the signal it posts
-- when its own cleanup is complete.
data RegisteredExecution = RegisteredExecution
  { registeredThread :: ThreadId,
    registeredTerminal :: MVar ()
  }

newtype CancellationRegistry = CancellationRegistry (IORef (Map ExecutionIdentity RegisteredExecution))

-- | What a cancellation request established.
data CancellationOutcome
  = -- | The named execution was running, was interrupted, and reported its
    -- cleanup terminal before this returned.
    CancelledRunningExecution
  | -- | Nothing by that identity is executing here. The prompt may be queued,
    -- already finished, or owned by another machine; this machine has no
    -- computation to stop and says so.
    NoRunningExecution
  | -- | The execution was interrupted but did not report terminal cleanup
    -- within the bound. Authority is not claimed released on this path.
    CancellationCleanupUnconfirmed
  deriving (Eq, Show)

cancellationOutcomeLabel :: CancellationOutcome -> Text
cancellationOutcomeLabel outcome =
  case outcome of
    CancelledRunningExecution -> "cancelled"
    NoRunningExecution -> "not-running"
    CancellationCleanupUnconfirmed -> "cleanup-unconfirmed"

newCancellationRegistry :: IO CancellationRegistry
newCancellationRegistry = CancellationRegistry <$> newIORef Map.empty

registeredExecutionCount :: CancellationRegistry -> IO Int
registeredExecutionCount (CancellationRegistry registryRef) =
  Map.size <$> readIORef registryRef

-- | Run one execution under its durable identity.
--
-- The terminal signal is posted from the release, so it is posted after the
-- action's own cleanup — which for an engine execution is the bracket that
-- terminates and reaps the engine's process group. A canceller waiting on that
-- signal is therefore waiting for the resources to be gone, not merely for the
-- interrupt to have been delivered.
withCancellableExecution :: CancellationRegistry -> ExecutionIdentity -> IO a -> IO a
withCancellableExecution (CancellationRegistry registryRef) identity action = do
  threadId <- myThreadId
  terminal <- newEmptyMVar
  let registration = RegisteredExecution threadId terminal
  atomicModifyIORef' registryRef (\registry -> (Map.insert identity registration registry, ()))
  action
    `finallyPreservingPrimary` ( do
                                   atomicModifyIORef' registryRef (\registry -> (Map.delete identity registry, ()))
                                   putMVar terminal ()
                               )

-- | Interrupt the named execution and wait for its cleanup to be terminal.
requestCancellation :: CancellationRegistry -> ExecutionIdentity -> IO CancellationOutcome
requestCancellation (CancellationRegistry registryRef) identity = do
  registry <- readIORef registryRef
  case Map.lookup identity registry of
    Nothing -> pure NoRunningExecution
    Just registration -> do
      -- Delivering the interrupt from a separate thread keeps a target that
      -- masks exceptions from blocking the canceller indefinitely; the bounded
      -- wait below is what decides the outcome either way.
      _ <- forkIO (throwTo (registeredThread registration) ThreadKilled)
      settled <-
        timeout
          cancellationCleanupBoundMicroseconds
          (readMVar (registeredTerminal registration))
      pure (cleanupOutcome settled)

-- | A confirmed cleanup is a cancellation; an unconfirmed one says so rather
-- than being reported as a stop nobody observed.
cleanupOutcome :: Maybe () -> CancellationOutcome
cleanupOutcome settled =
  case settled of
    Just () -> CancelledRunningExecution
    Nothing -> CancellationCleanupUnconfirmed

-- | How long a canceller waits for the interrupted execution's own cleanup.
-- Generous relative to reaping a process group, short enough that an
-- unconfirmed cleanup is reported rather than waited on forever.
cancellationCleanupBoundMicroseconds :: Int
cancellationCleanupBoundMicroseconds = 60 * 1000000
