{-# LANGUAGE OverloadedStrings #-}

module Infernix.EngineRouting
  ( engineMemberRequestTopics,
    engineMemberPinnedTopicForMode,
    enginePoolTopicForMode,
    requestTopicsForMode,
    resultTopicForMode,
  )
where

import Data.Char (isAlphaNum)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Types
  ( EngineMember (engineMemberId, engineMemberPoolIds),
    EnginePool (enginePoolId, enginePoolMemberIds, enginePoolModelIds),
    RuntimeMode,
    runtimeModeId,
  )

-- | Derived normal-pool topic. Operators declare pools and members, never raw
-- topic strings.
enginePoolTopicForMode :: RuntimeMode -> Text -> Text -> Text
enginePoolTopicForMode runtimeMode poolId modelIdValue =
  defaultPulsarTopicPrefix
    <> "inference.batch."
    <> runtimeModeId runtimeMode
    <> ".pool."
    <> topicSegment poolId
    <> ".model."
    <> topicSegment modelIdValue

engineMemberRequestTopics :: RuntimeMode -> [EnginePool] -> EngineMember -> [Text]
engineMemberRequestTopics runtimeMode pools member =
  [ enginePoolTopicForMode runtimeMode (enginePoolId pool) modelIdValue
  | pool <- pools,
    enginePoolId pool `elem` engineMemberPoolIds member,
    engineMemberId member `elem` enginePoolMemberIds pool,
    modelIdValue <- enginePoolModelIds pool
  ]

-- | Derived pinned-member topic for exact-member routes.
engineMemberPinnedTopicForMode :: RuntimeMode -> Text -> Text -> Text
engineMemberPinnedTopicForMode runtimeMode memberId modelIdValue =
  defaultPulsarTopicPrefix
    <> "inference.batch."
    <> runtimeModeId runtimeMode
    <> ".member."
    <> topicSegment memberId
    <> ".model."
    <> topicSegment modelIdValue

-- | The coordinator request topic and the shared result topic are functions of
-- the runtime mode alone.
--
-- Phase 8 Sprint 8.10: they live here, beside the pool and member topics, so the
-- generated wire can drop its copies. A generated field that must equal what the
-- binary already derives is a permanent illegal-state generator; deriving it is
-- the only shape with no disagreement to detect.
requestTopicsForMode :: RuntimeMode -> [Text]
requestTopicsForMode runtimeMode =
  [defaultPulsarTopicPrefix <> "inference.request." <> runtimeModeId runtimeMode]

resultTopicForMode :: RuntimeMode -> Text
resultTopicForMode runtimeMode =
  defaultPulsarTopicPrefix <> "inference.result." <> runtimeModeId runtimeMode

defaultPulsarTopicPrefix :: Text
defaultPulsarTopicPrefix = "persistent://infernix/demo/"

topicSegment :: Text -> Text
topicSegment =
  Text.map
    ( \character ->
        if isAlphaNum character || character `elem` ("._-" :: String)
          then character
          else '-'
    )
