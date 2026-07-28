module Infernix.Runtime.Enforcer.Properties
  ( runFiniteCgroupLimitParserProperties,
  )
where

import Infernix.Runtime.Enforcer.Internal (parseFiniteMib)

runFiniteCgroupLimitParserProperties :: IO ()
runFiniteCgroupLimitParserProperties = do
  let expectedMib = 1024
      expectedBytes = toInteger expectedMib * bytesPerMib
      overflowingBytes = (toInteger (maxBound :: Int) + 1) * bytesPerMib
  assertEqual
    "an exact positive MiB limit is accepted"
    (Just expectedMib)
    (parseFiniteMib (" \t" <> show expectedBytes <> "\r\n"))
  mapM_
    ( \(label, rawLimit) ->
        assertEqual label Nothing (parseFiniteMib rawLimit)
    )
    [ ("one byte below the exact limit is rejected", show (expectedBytes - 1)),
      ("one byte above the exact limit is rejected", show (expectedBytes + 1)),
      ("the cgroup unlimited sentinel is rejected", "max"),
      ("malformed cgroup content is rejected", "1024MiB"),
      ("a zero-byte limit is rejected", "0"),
      ("a negative limit is rejected", "-1048576"),
      ("a MiB value above the Int domain is rejected", show overflowingBytes)
    ]
  putStrLn "finite cgroup-limit parser properties passed"

bytesPerMib :: Integer
bytesPerMib = 1048576

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  if actual == expected
    then pure ()
    else
      fail
        (label <> ": expected " <> show expected <> ", got " <> show actual)
