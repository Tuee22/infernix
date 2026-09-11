{-# LANGUAGE OverloadedStrings #-}

-- | Phase 7 Sprint 7.31 — the conversation prefix an inference runs against,
-- and what has to be true of it before an engine sees it.
--
-- A dispatched request carries two facts about its history: the offset of the
-- prompt on the conversation topic, and the canonical projection hash at that
-- point. Neither was checked. The engine received the latest prompt text and
-- nothing else, so a multi-turn context executed as a sequence of unrelated
-- single-turn requests, and the hash was compared against a bookkeeping map
-- that no engine state corresponded to.
--
-- What the request states is therefore verified against the durable log before
-- the engine is reached. The retained events are read through exactly the named
-- offset, the projection is recomputed over that prefix, and the recomputed
-- hash must equal the one the request carries. A history that is short, that no
-- longer hashes to what the dispatcher saw, or whose named offset is not a
-- prompt at all, is a visible refusal — not a fallback to the current prompt,
-- which is the substitution this check exists to catch.
--
-- Tenant scoping is structural rather than checked here. The conversation topic
-- is derived from the authenticated user and the requested context, so the
-- events this module folds are the ones that identity selects; a request naming
-- a foreign context reads that context's own topic, whose projection does not
-- hash to the value the dispatcher published for this one, and the mismatch is
-- what surfaces. This module therefore records the identity it was given and
-- checks the proposition it can actually decide.
module Infernix.Conversation.Prefix
  ( ConversationTurn (..),
    PrefixVerificationFailure (..),
    VerifiedConversationPrefix,
    prefixVerificationFailureText,
    reconstructVerifiedPrefix,
    verifiedPrefixBytes,
    verifiedPrefixContext,
    verifiedPrefixHash,
    verifiedPrefixTurns,
  )
where

import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Conversation.Hash (PrefixHash (..))
import Infernix.Conversation.Reducer qualified as Reducer
import Infernix.Web.Contracts
  ( ContextId (..),
    ConversationEvent (..),
    ConversationInferenceResultPayload (..),
    ConversationMessage (..),
    UserPromptPayload (..),
  )

-- | One turn of the canonical projection, in the order the engine replays it.
data ConversationTurn = ConversationTurn
  { -- | @user@ or @assistant@, assigned from the durable event type rather
    -- than inferred from content.
    conversationTurnRole :: Text,
    conversationTurnText :: Text
  }
  deriving (Eq, Show)

-- | A prefix that has been read from durable history and agreed with the
-- offset and hash the request named. The constructor is not exported: the only
-- way to hold one is to have passed 'reconstructVerifiedPrefix'.
data VerifiedConversationPrefix = VerifiedConversationPrefix
  { verifiedPrefixTurns :: [ConversationTurn],
    verifiedPrefixHash :: PrefixHash,
    -- | The context whose topic these events were read from.
    verifiedPrefixContext :: ContextId,
    -- | The UTF-8 extent of the reconstructed turns. The reconstruction buffer
    -- is a real claim on the execution's budget, so the quantity is reported
    -- rather than left for the engine to discover.
    verifiedPrefixBytes :: Integer
  }
  deriving (Eq, Show)

-- | Why a request's stated history could not be established. Every arm refuses;
-- none of them falls back to the current prompt.
data PrefixVerificationFailure
  = -- | The retained history is shorter than the offset the request names, so
    -- the prompt it refers to is not there to read.
    PrefixOffsetOutOfRange Int Int
  | -- | The recomputed projection hash differs from the one the dispatcher
    -- published, so the history is not the history the request describes.
    PrefixHashMismatch Text Text
  | -- | The named offset does not carry a user prompt, so the request does not
    -- describe a dispatchable turn.
    PrefixOffsetNotAPrompt Int
  deriving (Eq, Show)

prefixVerificationFailureText :: PrefixVerificationFailure -> Text
prefixVerificationFailureText failure =
  case failure of
    PrefixOffsetOutOfRange requested available ->
      "the request names conversation offset "
        <> Text.pack (show requested)
        <> " but only "
        <> Text.pack (show available)
        <> " retained events are readable"
    PrefixHashMismatch expected observed ->
      "the reconstructed projection hashes to "
        <> observed
        <> " where the request states "
        <> expected
    PrefixOffsetNotAPrompt requested ->
      "conversation offset "
        <> Text.pack (show requested)
        <> " does not carry a user prompt"

-- | Reconstruct and verify the prefix a request names.
--
-- @retained@ is the context's ordered retained history as read from the
-- conversation topic that this context's identity selects. The prefix is
-- everything through @offset@ inclusive: the prompt being executed together
-- with every turn before it.
reconstructVerifiedPrefix ::
  ContextId ->
  Int ->
  PrefixHash ->
  [ConversationMessage] ->
  Either PrefixVerificationFailure VerifiedConversationPrefix
reconstructVerifiedPrefix contextIdValue offset statedHash retained
  | offset < 0 || offset >= length retained =
      Left (PrefixOffsetOutOfRange offset (length retained))
  | not (promptAt offset prefixMessages) = Left (PrefixOffsetNotAPrompt offset)
  | recomputed /= statedHash =
      Left (PrefixHashMismatch (unPrefixHash statedHash) (unPrefixHash recomputed))
  | otherwise =
      Right
        VerifiedConversationPrefix
          { verifiedPrefixTurns = turns,
            verifiedPrefixHash = recomputed,
            verifiedPrefixContext = contextIdValue,
            verifiedPrefixBytes = sum (map turnBytes turns)
          }
  where
    prefixMessages = take (offset + 1) retained
    recomputed = Reducer.reducerPrefixHash (Reducer.foldEvents contextIdValue prefixMessages)
    turns = concatMap conversationTurnsFor prefixMessages

promptAt :: Int -> [ConversationMessage] -> Bool
promptAt offset messages =
  case drop offset messages of
    message : _ -> isPromptEvent (conversationMessageEvent message)
    [] -> False

isPromptEvent :: ConversationEvent -> Bool
isPromptEvent event =
  case event of
    ConversationUserPromptEvent _ -> True
    _ -> False

-- | The turns an event contributes. Only prompts and completed results carry
-- text an engine replays; the other durable event types are conversation
-- bookkeeping and contribute nothing.
conversationTurnsFor :: ConversationMessage -> [ConversationTurn]
conversationTurnsFor message =
  case conversationMessageEvent message of
    ConversationUserPromptEvent payload -> [ConversationTurn "user" (promptText payload)]
    ConversationInferenceResultEvent payload ->
      case inferenceResultInlineOutput payload of
        Just outputText -> [ConversationTurn "assistant" outputText]
        Nothing -> []
    _ -> []

turnBytes :: ConversationTurn -> Integer
turnBytes turn =
  toInteger
    ( ByteString.length (TextEncoding.encodeUtf8 (conversationTurnRole turn))
        + ByteString.length (TextEncoding.encodeUtf8 (conversationTurnText turn))
    )
