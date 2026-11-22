{-# LANGUAGE OverloadedStrings #-}

-- | Closed wire messages for engine-owned cache observations and mutations.
-- No caller-supplied path or model descriptor crosses this boundary.
module Infernix.Runtime.CacheControl
  ( CacheControlRequest (..),
    CacheControlReply (..),
    cacheControlTargets,
    cacheControlReplyIsExpected,
    cacheControlOutcomes,
    boundedCacheObservation,
  )
where

import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), object, withObject, (.:), (.=))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Infernix.ExecutionPlan (CompiledRuntimePlan)
import Infernix.Runtime.Cache
  ( CacheAction (..),
    CacheEntryFacts (..),
    CacheEntryState (..),
    CacheOperationOutcome (..),
    cacheEligibleOwnerMembers,
    cacheOutcomeMatchesAction,
  )
import System.Timeout (timeout)

-- | Stop read-only owner work at the caller's deadline, releasing any lease
-- held by the observation before another request is handled.
boundedCacheObservation :: Int -> IO a -> IO (Maybe a)
boundedCacheObservation = timeout

data CacheControlRequest = CacheControlRequest
  { cacheRequestId :: Text,
    cacheRequestDeadline :: UTCTime,
    cacheRequestAction :: CacheAction,
    cacheRequestTargets :: Map Text [Text]
  }
  deriving (Eq, Show)

instance ToJSON CacheControlRequest where
  toJSON request =
    object
      [ "requestId" .= cacheRequestId request,
        "deadline" .= cacheRequestDeadline request,
        "action" .= cacheRequestAction request,
        "targets" .= cacheRequestTargets request
      ]

instance FromJSON CacheControlRequest where
  parseJSON = withObject "CacheControlRequest" $ \value ->
    CacheControlRequest
      <$> value .: "requestId"
      <*> value .: "deadline"
      <*> value .: "action"
      <*> value .: "targets"

data CacheControlReply = CacheControlReply
  { cacheReplyRequestId :: Text,
    cacheReplyMemberId :: Text,
    cacheReplyOutcome :: CacheOperationOutcome
  }
  deriving (Eq, Show)

instance ToJSON CacheControlReply where
  toJSON reply =
    object
      [ "requestId" .= cacheReplyRequestId reply,
        "memberId" .= cacheReplyMemberId reply,
        "outcome" .= cacheReplyOutcome reply
      ]

instance FromJSON CacheControlReply where
  parseJSON = withObject "CacheControlReply" $ \value ->
    CacheControlReply
      <$> value .: "requestId"
      <*> value .: "memberId"
      <*> value .: "outcome"

-- | Build one request target per actual eligible member and model. Unknown or
-- unroutable models are returned separately, so they cannot become successes.
cacheControlTargets :: CompiledRuntimePlan -> [Text] -> (Map Text [Text], [(Text, Text)])
cacheControlTargets plan = foldl' addModel (Map.empty, [])
  where
    addModel (targets, refused) modelName =
      case cacheEligibleOwnerMembers plan modelName of
        Left reason -> (targets, refused <> [(modelName, reason)])
        Right owners ->
          ( foldl' (\acc owner -> Map.insertWith (<>) owner [modelName] acc) targets owners,
            refused
          )

-- | Ignore unrelated, duplicate, or semantically inconsistent replies. The
-- caller also tracks the first reply for each expected owner/model pair.
cacheControlReplyIsExpected :: CacheControlRequest -> CacheControlReply -> Bool
cacheControlReplyIsExpected request reply =
  cacheReplyRequestId reply == cacheRequestId request
    && maybe False (cacheOutcomeModelId outcome `elem`) (Map.lookup (cacheReplyMemberId reply) (cacheRequestTargets request))
    && cacheOutcomeMatchesAction (cacheRequestAction request) outcome
  where
    outcome = cacheReplyOutcome reply

-- | Reduce only replies from every expected owner. Partial or absent ownership
-- observations are explicitly unobservable and never count as completed work.
cacheControlOutcomes ::
  CacheControlRequest ->
  [Text] ->
  [(Text, Text)] ->
  Map (Text, Text) CacheOperationOutcome ->
  [CacheOperationOutcome]
cacheControlOutcomes request modelNames refused replies = map outcomeFor modelNames
  where
    outcomeFor modelName =
      case lookup modelName refused of
        Just reason -> unobservable modelName reason
        Nothing ->
          let owners =
                [ owner
                | (owner, models) <- Map.toAscList (cacheRequestTargets request),
                  modelName `elem` models
                ]
              missing = [owner | owner <- owners, Map.notMember (owner, modelName) replies]
              observed = [outcome | owner <- owners, Just outcome <- [Map.lookup (owner, modelName) replies]]
           in if null owners
                then unobservable modelName "no eligible cache owner is available"
                else
                  if not (null missing)
                    then unobservable modelName ("cache owners did not respond: " <> Text.intercalate ", " missing)
                    else combine modelName observed

    combine modelName [single] = single {cacheOutcomeModelId = modelName}
    combine modelName observed =
      case cacheRequestAction request of
        ObserveCache ->
          case traverse readyFacts observed of
            Just facts -> CacheOperationOutcome modelName (CacheVerifiedReady (sumFacts facts)) False
            Nothing ->
              if all isMissing observed
                then CacheOperationOutcome modelName (CacheMissing "all eligible owners report a missing cache") False
                else unobservable modelName "eligible owners report different or unavailable cache states"
        EvictOwnedCache ->
          if all isMissing observed
            then CacheOperationOutcome modelName (CacheMissing "all eligible owners report a missing cache") (any cacheOutcomeChanged observed)
            else unobservable modelName "cache eviction did not complete on every eligible owner"
        RebuildOwnedCache ->
          case traverse readyFacts observed of
            Just facts -> CacheOperationOutcome modelName (CacheVerifiedReady (sumFacts facts)) True
            Nothing -> unobservable modelName "cache rebuild did not complete on every eligible owner"

    readyFacts outcome =
      case cacheOutcomeState outcome of
        CacheVerifiedReady facts -> Just facts
        _ -> Nothing
    isMissing outcome =
      case cacheOutcomeState outcome of
        CacheMissing _ -> True
        _ -> False
    sumFacts facts =
      CacheEntryFacts
        { cacheEntryFileCount = sum (map cacheEntryFileCount facts),
          cacheEntryBytes = sum (map cacheEntryBytes facts)
        }
    unobservable modelName reason = CacheOperationOutcome modelName (CacheUnobservable reason) False
