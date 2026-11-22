{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Resolve cache controls through the compiled engine placement graph.
module Infernix.Runtime.CacheClient
  ( runRoutedCacheAction,
    runRoutedCacheOverview,
    routedCacheReports,
  )
where

import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.ClusterConfig (ClusterConfig)
import Infernix.Config (Paths)
import Infernix.ExecutionPlan qualified as ExecutionPlan
import Infernix.Runtime.Cache qualified as Cache
import Infernix.Runtime.Pulsar qualified as Pulsar
import Infernix.Substrate (decodeCompiledRuntimePlanFile)
import Infernix.Types
  ( CacheManifest (..),
    RuntimeMode,
    modelId,
    selectedEngine,
  )

-- | Compile the same runtime configuration the daemon uses and address the
-- engine owners from its placement graph. Failure to discover a transport is
-- an unobservable owner, never a local or empty-cache success.
runRoutedCacheAction ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  FilePath ->
  Cache.CacheAction ->
  Maybe Text ->
  IO (ExecutionPlan.CompiledRuntimePlan, [Cache.CacheOperationOutcome])
runRoutedCacheAction = runRoutedCacheActionWith False

-- | Dashboard observations have a short independent budget; slow or absent
-- owners remain unobservable instead of blocking the other overview fields.
runRoutedCacheOverview ::
  Paths -> RuntimeMode -> Maybe ClusterConfig -> FilePath -> IO (ExecutionPlan.CompiledRuntimePlan, [Cache.CacheOperationOutcome])
runRoutedCacheOverview paths runtimeMode maybeClusterConfig configPath =
  runRoutedCacheActionWith True paths runtimeMode maybeClusterConfig configPath Cache.ObserveCache Nothing

runRoutedCacheActionWith ::
  Bool -> Paths -> RuntimeMode -> Maybe ClusterConfig -> FilePath -> Cache.CacheAction -> Maybe Text -> IO (ExecutionPlan.CompiledRuntimePlan, [Cache.CacheOperationOutcome])
runRoutedCacheActionWith overview paths runtimeMode maybeClusterConfig configPath action maybeModel = do
  decoded <- decodeCompiledRuntimePlanFile configPath
  plan <-
    case decoded of
      Left errors -> ioError (userError ("cache control runtime plan did not compile: " <> show errors))
      Right value
        | ExecutionPlan.compiledPlanRuntimeMode value == runtimeMode -> pure value
        | otherwise -> ioError (userError "cache control runtime mode does not match its compiled plan")
  let selected =
        case maybeModel of
          Just modelName -> [modelName]
          Nothing -> map modelId (ExecutionPlan.compiledPlanConfiguredModels plan)
      unavailable reason =
        [ Cache.CacheOperationOutcome modelName (Cache.CacheUnobservable reason) False
        | modelName <- selected
        ]
  discovered <- try @SomeException (Pulsar.discoverPulsarTransport paths runtimeMode maybeClusterConfig)
  outcomes <-
    case discovered of
      Left err ->
        case fromException err :: Maybe SomeAsyncException of
          Just _ -> throwIO err
          Nothing -> pure (unavailable ("cache owner transport is unavailable: " <> Text.pack (show err)))
      Right Nothing -> pure (unavailable "cache owner transport is unavailable")
      Right (Just transport)
        | overview -> Pulsar.runRemoteCacheOverviewObservation transport plan selected
        | otherwise -> Pulsar.runRemoteCacheAction transport plan action selected
  pure (plan, outcomes)

-- | Pair configured catalog metadata with observations returned by the actual
-- engine owners. The metadata is a description, not proof of cache readiness.
routedCacheReports ::
  ExecutionPlan.CompiledRuntimePlan ->
  [Cache.CacheOperationOutcome] ->
  [Cache.CacheEntryReport]
routedCacheReports plan outcomes =
  [ Cache.CacheEntryReport
      ( CacheManifest
          { cacheRuntimeMode = ExecutionPlan.compiledPlanRuntimeMode plan,
            cacheModelId = modelId model,
            cacheSelectedEngine = selectedEngine model,
            cacheDurableSourceUri = "minio://" <> ExecutionPlan.compiledPlanModelsBucket plan <> "/" <> modelId model <> "/",
            cacheCacheKey = "default"
          }
      )
      ( maybe
          (Cache.CacheUnobservable "no cache owner observation was returned")
          Cache.cacheOutcomeState
          (find ((== modelId model) . Cache.cacheOutcomeModelId) outcomes)
      )
  | model <- ExecutionPlan.compiledPlanConfiguredModels plan
  ]
