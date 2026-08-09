{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoConfig.Colima
  ( activeColimaPledgeMibFromObservation,
    colimaPledgeMibFromJsonLines,
    effectiveHostMemoryMibAfterColimaPledge,
    observeActiveColimaPledgeMib,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.Char (isSpace)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.HostTools qualified as HostTools
import Numeric.Natural (Natural)

-- | Observe the aggregate memory pledge of every Colima profile that is not
-- explicitly stopped.
--
-- This is the single producer shared by the Darwin build-memory measurement
-- and the Apple inference-memory partition. The executable is selected from
-- the closed absolute-path candidate list in 'Infernix.HostTools', and that
-- helper supplies the fixed 120-second host-probe deadline. An unavailable
-- executable, a failed probe, or an unparseable response is a named 'Left';
-- none is evidence that the active pledge is zero.
observeActiveColimaPledgeMib :: IO (Either String Int)
observeActiveColimaPledgeMib = do
  observed <-
    try
      (HostTools.readHostToolFallback HostTools.HostColima ["list", "--json"] "") ::
      IO (Either IOException (Maybe String))
  pure $
    case observed of
      Left observationError ->
        Left
          ( "could not observe the running Colima memory pledge: "
              <> displayException observationError
          )
      Right output -> activeColimaPledgeMibFromObservation output

-- | Classify the output of the fixed Colima probe.
--
-- Kept separate from the IO producer so the unavailable and malformed cases
-- are deterministic unit-test inputs rather than host-dependent tests.
activeColimaPledgeMibFromObservation :: Maybe String -> Either String Int
activeColimaPledgeMibFromObservation maybeOutput =
  case maybeOutput of
    Nothing ->
      Left
        "could not observe the running Colima memory pledge: colima executable unavailable"
    Just output -> colimaPledgeMibFromJsonLines output

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

-- | Subtract an observed active Colima pledge from physical Darwin memory.
--
-- The result is the memory actually available to the host-native toolchain,
-- not a second independently declared budget. A missing observation is
-- handled by 'observeActiveColimaPledgeMib'; this pure boundary additionally
-- rejects impossible/non-positive arithmetic so an overcommitted host cannot
-- write a plausible-looking @effectiveMemoryMib = 0@ manifest.
effectiveHostMemoryMibAfterColimaPledge :: Natural -> Int -> Either String Natural
effectiveHostMemoryMibAfterColimaPledge physicalMib pledgedMib
  | physicalMib == 0 =
      Left
        "could not derive effective Darwin host memory: measured physical memory is zero MiB"
  | pledgedMib < 0 =
      Left
        ( "could not derive effective Darwin host memory: active Colima pledge is negative ("
            <> show pledgedMib
            <> " MiB)"
        )
  | pledgedNatural >= physicalMib =
      Left
        ( "could not derive effective Darwin host memory: active Colima pledge of "
            <> show pledgedMib
            <> " MiB leaves no memory from "
            <> show physicalMib
            <> " MiB physical RAM"
        )
  | otherwise = Right (physicalMib - pledgedNatural)
  where
    pledgedNatural = fromIntegral pledgedMib

bytesPerMib :: Int
bytesPerMib = 1048576
