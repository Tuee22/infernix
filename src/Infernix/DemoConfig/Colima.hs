{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoConfig.Colima
  ( colimaPledgeMibFromJsonLines,
  )
where

import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.Char (isSpace)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Parse the JSON-lines form emitted by @colima list --json@. Profiles that
-- are not explicitly stopped are charged conservatively, and the aggregate is
-- rounded up once so sub-MiB pledges cannot disappear.
colimaPledgeMibFromJsonLines :: String -> Either String Int
colimaPledgeMibFromJsonLines output = do
  let profileLines = filter (not . all isSpace) (lines output)
  when
    (null profileLines)
    (Left "could not observe the running Colima memory pledge: no profiles were reported")
  profiles <- traverse decodeProfileLine profileLines
  let totalReservedBytes =
        sum
          [ colimaMemory profile
          | profile <- profiles,
            colimaStatus profile /= "Stopped"
          ]
      pledgedMib =
        (totalReservedBytes + toInteger bytesPerMib - 1)
          `div` toInteger bytesPerMib
  if pledgedMib > toInteger (maxBound :: Int)
    then Left "could not observe the running Colima memory pledge: value exceeds the supported integer range"
    else Right (fromInteger pledgedMib)
  where
    decodeProfileLine line =
      case Aeson.eitherDecodeStrict' (ByteStringChar8.pack line) of
        Left decodeError ->
          Left
            ( "could not observe the running Colima memory pledge: malformed profile: "
                <> decodeError
            )
        Right profile -> Right profile

data ColimaProfile = ColimaProfile
  { colimaStatus :: Text,
    colimaMemory :: Integer
  }

instance Aeson.FromJSON ColimaProfile where
  parseJSON = Aeson.withObject "ColimaProfile" $ \value -> do
    profileName <- value Aeson..: "name"
    status <- value Aeson..: "status"
    memoryBytes <- value Aeson..: "memory"
    if Text.null (Text.strip profileName)
      then fail "Colima profile name must not be blank"
      else
        if Text.null (Text.strip status)
          then fail "Colima profile status must not be blank"
          else
            if memoryBytes < 0
              then fail "Colima profile memory must not be negative"
              else pure (ColimaProfile status memoryBytes)

bytesPerMib :: Int
bytesPerMib = 1048576
