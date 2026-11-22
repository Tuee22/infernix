{-# LANGUAGE OverloadedStrings #-}

-- | Package-internal cache locks shared by engine execution, mutations and the
-- Python adapter's LRU. The caller keeps the observed cache root for the whole
-- protected operation.
module Infernix.Runtime.ModelCacheLease
  ( modelCacheMutationLockPath,
    prepareCacheRootLockPath,
    prepareMutationLockPath,
    withModelCacheExecutionLease,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Cluster.LifecycleLock (withKernelFileLock, withKernelSharedFileLock)
import Infernix.Config (Paths (..))
import Infernix.Runtime.ModelCacheReplacement (cacheReplacementPending, recoverCacheReplacement)
import Infernix.Types (RuntimeMode, runtimeModeId)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

withModelCacheExecutionLease :: Paths -> RuntimeMode -> FilePath -> Text -> IO a -> IO a
withModelCacheExecutionLease paths runtimeMode cacheRoot modelIdValue action = do
  lockPath <- prepareMutationLockPath paths runtimeMode modelIdValue
  cacheLockPath <- prepareCacheRootLockPath cacheRoot modelIdValue
  let executeOrRecover = do
        result <-
          withKernelSharedFileLock "model cache execution" lockPath $
            withKernelSharedFileLock "model cache root execution" cacheLockPath $ do
              pending <- cacheReplacementPending cacheRoot modelIdValue
              if pending then pure Nothing else Just <$> action
        case result of
          Just value -> pure value
          Nothing -> do
            withKernelFileLock "model cache recovery" lockPath $
              withKernelFileLock "model cache root recovery" cacheLockPath $
                recoverCacheReplacement cacheRoot modelIdValue
            executeOrRecover
  executeOrRecover

-- This lock is inside the actual cache root so the adapter's LRU sees it even
-- when the engine and webapp have distinct runtime scratch directories.
prepareCacheRootLockPath :: FilePath -> Text -> IO FilePath
prepareCacheRootLockPath cacheRoot modelIdValue = do
  let lockDirectory = cacheRoot </> ".infernix-model-locks"
  createDirectoryIfMissing True lockDirectory
  pure (lockDirectory </> Text.unpack modelIdValue <> ".held")

modelCacheMutationLockPath :: Paths -> RuntimeMode -> Text -> FilePath
modelCacheMutationLockPath paths runtimeMode modelIdValue =
  runtimeRoot paths
    </> "locks"
    </> ( "model-cache-"
            <> Text.unpack (runtimeModeId runtimeMode)
            <> "-"
            <> Text.unpack modelIdValue
            <> ".held"
        )

prepareMutationLockPath :: Paths -> RuntimeMode -> Text -> IO FilePath
prepareMutationLockPath paths runtimeMode modelIdValue = do
  let lockPath = modelCacheMutationLockPath paths runtimeMode modelIdValue
  createDirectoryIfMissing True (runtimeRoot paths </> "locks")
  pure lockPath
