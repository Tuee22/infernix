{-# LANGUAGE LambdaCase #-}

module Infernix.Error
  ( InfernixError (..),
    humanReadable,
  )
where

import Control.Exception (Exception)

data InfernixError
  = PoetryUnavailable
  | PythonProjectMissing FilePath
  | EdgePortNotPublished
  | ProcessFailure
      { processName :: String,
        processStderr :: String,
        processCwd :: Maybe FilePath
      }
  | ProtobufDecodeFailure FilePath String
  | ClusterStateDecodeFailure FilePath String
  | InvalidControlPlaneOverride String
  deriving (Eq)

instance Show InfernixError where
  show = humanReadable

instance Exception InfernixError

humanReadable :: InfernixError -> String
humanReadable = \case
  PoetryUnavailable ->
    "poetry is not available on PATH. The supported non-Apple paths provide Poetry inside the shared Linux substrate images."
  PythonProjectMissing projectDirectory ->
    "python substrate project is missing: " <> projectDirectory
  EdgePortNotPublished ->
    "edge port was not published after cluster up"
  ProcessFailure name stderr cwd ->
    name
      <> maybe "" ("\nproject: " <>) cwd
      <> "\n"
      <> stderr
  ProtobufDecodeFailure filePath detail ->
    "failed to decode protobuf file " <> filePath <> ": " <> detail
  ClusterStateDecodeFailure filePath detail ->
    "recorded cluster state at "
      <> filePath
      <> " exists but could not be decoded; refusing to treat it as absent (which would skip retained-state replay during teardown and risk losing durable data). Inspect or remove the file, then retry. Detail: "
      <> detail
  InvalidControlPlaneOverride rawOverride ->
    "Unsupported INFERNIX_CONTROL_PLANE_CONTEXT override: "
      <> rawOverride
      <> ". Expected one of: host-native, outer-container."
