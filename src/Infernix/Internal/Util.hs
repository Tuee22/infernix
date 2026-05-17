module Infernix.Internal.Util
  ( allM,
    findFirstM,
    firstJustM,
  )
where

allM :: (Monad m) => (a -> m Bool) -> [a] -> m Bool
allM predicate = go
  where
    go [] = pure True
    go (value : rest) = do
      matches <- predicate value
      if matches
        then go rest
        else pure False

findFirstM :: (Monad m) => (a -> m Bool) -> [a] -> m (Maybe a)
findFirstM _ [] = pure Nothing
findFirstM predicate (value : rest) = do
  matches <- predicate value
  if matches
    then pure (Just value)
    else findFirstM predicate rest

firstJustM :: (Monad m) => [m (Maybe a)] -> m (Maybe a)
firstJustM [] = pure Nothing
firstJustM (action : rest) = do
  result <- action
  case result of
    Just value -> pure (Just value)
    Nothing -> firstJustM rest
