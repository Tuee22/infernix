module Infernix.Runtime.Enforcer.Internal
  ( parseFiniteMib,
  )
where

parseFiniteMib :: String -> Maybe Int
parseFiniteMib rawValue =
  case reads (trim rawValue) of
    [(bytes, "")]
      | bytes > 0,
        bytes `mod` bytesPerMib == 0,
        let mib = bytes `div` bytesPerMib,
        mib > 0,
        mib <= toInteger (maxBound :: Int) ->
          Just (fromInteger mib)
    _ -> Nothing
  where
    trim = reverse . dropWhile (`elem` [' ', '\t', '\r', '\n']) . reverse . dropWhile (`elem` [' ', '\t', '\r', '\n'])
    bytesPerMib = 1048576 :: Integer
