{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster.ClaimPermissions
  ( claimOwner,
    repairClaimPermissions,
  )
where

import Data.List qualified as List
import Data.Text qualified as Text
import Infernix.Types (PersistentClaim (..))

-- The retained tree must remain owned by the actual workload user after
-- reconciliation, including when the pod is already running.
claimOwner :: PersistentClaim -> Maybe String
claimOwner claimSpec
  | workload claimSpec == "minio" && claim claimSpec == "data" = Just "65532:65532"
  | "keycloak-postgresql" `List.isPrefixOf` Text.unpack (workload claimSpec) = Just "26:26"
  | otherwise = Nothing

-- | Run a finite missing-path repair loop and require one final successful
-- permission observation after the last recreation. Callers supply the
-- recreation, delay, and bounded chmod effects; this module owns only the
-- workflow and is kept internal to the package.
repairClaimPermissions ::
  Int ->
  IO () ->
  IO () ->
  IO (Either String output) ->
  IO (Either String ())
repairClaimPermissions maximumAttempts recreate delayBeforeRetry attempt
  | maximumAttempts <= 0 =
      pure (Left "claim permission repair requires at least one bounded chmod attempt")
  | otherwise = go maximumAttempts ""
  where
    go remainingAttempts lastError = do
      recreate
      result <- attempt
      case result of
        Right _ -> pure (Right ())
        Left err
          | claimPathMissing err && remainingAttempts > 1 -> do
              delayBeforeRetry
              go (remainingAttempts - 1) err
          | claimPathMissing err -> do
              recreate
              proofResult <- attempt
              pure $
                case proofResult of
                  Right _ -> Right ()
                  Left proofError -> Left (chooseError proofError (chooseError err lastError))
          | otherwise -> pure (Left err)

    chooseError current previous
      | null current = previous
      | otherwise = current

claimPathMissing :: String -> Bool
claimPathMissing err =
  "No such file or directory" `List.isInfixOf` err
    || "fts_read failed" `List.isInfixOf` err
