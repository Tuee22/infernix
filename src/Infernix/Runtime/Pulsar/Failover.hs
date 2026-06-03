{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.Pulsar.Failover
  ( failoverConsumerName,
  )
where

import Data.Text (Text)

-- | Build a consumer name for a Failover subscription member. The
-- subscription name remains the stable ownership key; the consumer
-- name is process-qualified so multiple coordinator replicas do not
-- present identical members to Pulsar during promotion.
failoverConsumerName :: Text -> Text -> Text
failoverConsumerName subscriptionName processLabel =
  subscriptionName <> "-consumer-" <> processLabel
