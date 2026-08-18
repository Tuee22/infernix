{-# LANGUAGE OverloadedStrings #-}

module Infernix.EngineRouting
  ( engineMemberClaimTopicForMode,
    engineMemberRequestTopics,
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

-- | Phase 8 Sprint 8.12 — the topic one engine member's identity is claimed on.
--
-- The claim needs a topic of its own rather than a subscription on a pool
-- topic, because a pool topic is consumed @Shared@ by every member of the pool:
-- an exclusive claim taken there would exclude the fleet rather than one
-- identity. This topic carries no messages at all. What it carries is one
-- exclusive subscription per member identity, and the broker's refusal to grant
-- a second one is the whole mechanism — the broker is the only place N machines
-- meet, so it is the only place a second machine adopting the first machine's
-- identity is observable.
engineMemberClaimTopicForMode :: RuntimeMode -> Text -> Text
engineMemberClaimTopicForMode runtimeMode memberIdValue =
  defaultPulsarTopicPrefix
    <> "fleet.member-claim."
    <> runtimeModeId runtimeMode
    <> "."
    <> topicSegment memberIdValue

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
