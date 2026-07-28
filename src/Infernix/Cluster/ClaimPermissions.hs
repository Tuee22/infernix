module Infernix.Cluster.ClaimPermissions
  ( repairClaimPermissions,
  )
where

import Data.List qualified as List

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
