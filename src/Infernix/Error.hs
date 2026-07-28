{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Error
  ( InfernixError (..),
    humanReadable,
    bracketPreservingPrimary,
    finallyPreservingPrimary,
    onExceptionPreservingPrimary,
    runCleanupsPreservingFailures,
  )
where

import Control.Exception
  ( Exception (fromException, toException),
    SomeAsyncException,
    SomeException,
    asyncExceptionFromException,
    asyncExceptionToException,
    displayException,
    mask,
    mask_,
    throwIO,
    try,
  )

data InfernixError
  = PoetryUnavailable
  | PythonProjectMissing FilePath
  | EdgePortNotPublished
  | ProcessFailure
      { processName :: String,
        processStderr :: String,
        processCwd :: Maybe FilePath
      }
  | ProtobufDecodeFailure FilePath String
  | ClusterStateDecodeFailure FilePath String
  | InvalidControlPlaneOverride String
  deriving (Eq)

instance Show InfernixError where
  show = humanReadable

instance Exception InfernixError

data PrimaryAndCleanupFailure
  = PrimaryAndCleanupFailure SomeException SomeException

instance Show PrimaryAndCleanupFailure where
  show (PrimaryAndCleanupFailure primaryFailure cleanupFailure) =
    renderPrimaryAndCleanupFailure primaryFailure cleanupFailure

instance Exception PrimaryAndCleanupFailure

data AsyncPrimaryAndCleanupFailure
  = AsyncPrimaryAndCleanupFailure SomeException SomeException

instance Show AsyncPrimaryAndCleanupFailure where
  show (AsyncPrimaryAndCleanupFailure primaryFailure cleanupFailure) =
    renderPrimaryAndCleanupFailure primaryFailure cleanupFailure

instance Exception AsyncPrimaryAndCleanupFailure where
  toException = asyncExceptionToException
  fromException = asyncExceptionFromException

-- | Acquire a resource under masking, then install diagnostic-preserving
-- cleanup before restoring the protected action's original masking state.
bracketPreservingPrimary :: IO resource -> (resource -> IO cleanup) -> (resource -> IO result) -> IO result
bracketPreservingPrimary acquire release action =
  mask $ \restore -> do
    resource <- acquire
    finallyPreservingPrimary
      (restore (action resource))
      (release resource)

-- | Run cleanup with the masking semantics of 'Control.Exception.finally',
-- while retaining both failures when the protected action and cleanup fail.
-- A cancellation on either side remains classified as an asynchronous
-- exception so callers cannot accidentally demote it to an ordinary failure.
finallyPreservingPrimary :: IO a -> IO b -> IO a
finallyPreservingPrimary action cleanup =
  mask $ \restore -> do
    actionResult <- tryAny (restore action)
    cleanupResult <- tryAny cleanup
    case (actionResult, cleanupResult) of
      (Right result, Right _) -> pure result
      (Left primaryFailure, Right _) -> throwIO primaryFailure
      (Right _, Left cleanupFailure) -> throwIO cleanupFailure
      (Left primaryFailure, Left cleanupFailure)
        | isAsyncFailure primaryFailure || isAsyncFailure cleanupFailure ->
            throwIO
              (AsyncPrimaryAndCleanupFailure primaryFailure cleanupFailure)
        | otherwise ->
            throwIO
              (PrimaryAndCleanupFailure primaryFailure cleanupFailure)

-- | Run cleanup only when the protected action fails, retaining both failures
-- without changing asynchronous-exception classification.
onExceptionPreservingPrimary :: IO a -> IO b -> IO a
onExceptionPreservingPrimary action cleanup =
  mask $ \restore -> do
    actionResult <- tryAny (restore action)
    case actionResult of
      Right result -> pure result
      Left primaryFailure ->
        finallyPreservingPrimary
          (throwIO primaryFailure)
          cleanup

-- | Run every cleanup from left to right, retaining every failure. Cleanup
-- remains masked while interruptible operations can still receive cancellation.
runCleanupsPreservingFailures :: [IO ()] -> IO ()
runCleanupsPreservingFailures cleanups =
  mask_ (foldr finallyPreservingPrimary (pure ()) cleanups)

tryAny :: IO a -> IO (Either SomeException a)
tryAny = try @SomeException

isAsyncFailure :: SomeException -> Bool
isAsyncFailure failure =
  case fromException failure :: Maybe SomeAsyncException of
    Just _ -> True
    Nothing -> False

renderPrimaryAndCleanupFailure :: SomeException -> SomeException -> String
renderPrimaryAndCleanupFailure primaryFailure cleanupFailure =
  "primary action failed:\n"
    <> displayException primaryFailure
    <> "\ncleanup also failed:\n"
    <> displayException cleanupFailure

humanReadable :: InfernixError -> String
humanReadable = \case
  PoetryUnavailable ->
    "poetry is not available on PATH. The supported non-Apple paths provide Poetry inside the shared Linux substrate images."
  PythonProjectMissing projectDirectory ->
    "python substrate project is missing: " <> projectDirectory
  EdgePortNotPublished ->
    "edge port was not published after cluster up"
  ProcessFailure name stderr cwd ->
    name
      <> maybe "" ("\nproject: " <>) cwd
      <> "\n"
      <> stderr
  ProtobufDecodeFailure filePath detail ->
    "failed to decode protobuf file " <> filePath <> ": " <> detail
  ClusterStateDecodeFailure filePath detail ->
    "recorded cluster state at "
      <> filePath
      <> " exists but could not be decoded; refusing to treat it as absent (which would skip retained-state replay during teardown and risk losing durable data). Inspect or remove the file, then retry. Detail: "
      <> detail
  InvalidControlPlaneOverride rawOverride ->
    "Unsupported INFERNIX_CONTROL_PLANE_CONTEXT override: "
      <> rawOverride
      <> ". Expected one of: host-native, outer-container."
