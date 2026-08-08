{-# LANGUAGE OverloadedStrings #-}

-- | Closed direct-target catalog for native artifacts. The constructors are
-- hidden so callers cannot substitute an executable, argument prefix, or
-- image-owned runtime closure.
module Infernix.Engines.Artifact.Target
  ( NativeArtifactTarget,
    NativeArtifactTargetEvidence (..),
    NativeArtifactTargetExecutableEvidence (..),
    NativeArtifactTargetClosureEvidence (..),
    NativeArtifactLoaderFileEvidence (..),
    NativeArtifactLoaderObjectEvidence (..),
    NativeArtifactLoaderResolutionEvidence (..),
    NativeArtifactLoaderEvidence (..),
    nativeArtifactTarget,
    nativeArtifactTargetExecutable,
    nativeArtifactTargetLeadingArguments,
    nativeArtifactTargetImmutableClosureRoots,
    nativeArtifactTargetIsInstalled,
    nativeArtifactTargetArchitecture,
    nativeArtifactTargetFingerprint,
    nativeArtifactTargetEvidenceFingerprint,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import Data.ByteString.Base16 qualified as Base16
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    nativeArtifactAdapterId,
  )
import System.FilePath (takeDirectory, (</>))

data TargetPath
  = InstalledTarget !FilePath
  | ImageTarget !FilePath
  deriving (Eq, Show)

data TargetArgumentPrefix
  = NoTargetArgumentPrefix
  | InstalledPythonRunnerPrefix
  | ImagePythonRunnerPrefix
  deriving (Eq, Show)

data ClosureRoot
  = InstalledClosureRoot !FilePath
  | ImageClosureRoot !FilePath
  deriving (Eq, Show)

data NativeArtifactTarget = NativeArtifactTarget
  { targetAdapterId :: !Text,
    targetSubstrate :: !Text,
    targetArchitecture :: !Text,
    targetPath :: !TargetPath,
    targetArgumentPrefix :: !TargetArgumentPrefix,
    targetClosureRoots :: ![ClosureRoot]
  }
  deriving (Eq, Show)

data NativeArtifactTargetExecutableEvidence
  = NativeArtifactTargetExecutableEvidence
  { targetExecutableConfiguredPath :: !FilePath,
    targetExecutableConfiguredDeviceId :: !Integer,
    targetExecutableConfiguredFileId :: !Integer,
    targetExecutableConfiguredMode :: !Integer,
    targetExecutableConfiguredSize :: !Integer,
    targetExecutableCanonicalPath :: !FilePath,
    targetExecutableCanonicalDeviceId :: !Integer,
    targetExecutableCanonicalFileId :: !Integer,
    targetExecutableCanonicalMode :: !Integer,
    targetExecutableCanonicalSize :: !Integer,
    targetExecutableDigest :: !Text
  }
  deriving (Eq, Show)

data NativeArtifactTargetClosureEvidence
  = NativeArtifactTargetClosureEvidence
  { targetClosurePath :: !FilePath,
    targetClosureDeviceId :: !Integer,
    targetClosureFileId :: !Integer,
    targetClosureMode :: !Integer,
    targetClosureDigest :: !Text
  }
  deriving (Eq, Show)

data NativeArtifactTargetEvidence
  = NativeArtifactTargetEvidence
  { targetEvidenceContractFingerprint :: !Text,
    targetEvidenceExecutable :: !NativeArtifactTargetExecutableEvidence,
    targetEvidenceClosures :: ![NativeArtifactTargetClosureEvidence],
    targetEvidenceLoader :: !(Maybe NativeArtifactLoaderEvidence)
  }
  deriving (Eq, Show)

-- | Exact identity for loader metadata consulted while resolving an image
-- target. Linux currently records the glibc cache when it participates in a
-- resolution; configuration files are deliberately not consulted at runtime.
data NativeArtifactLoaderFileEvidence
  = NativeArtifactLoaderFileEvidence
  { loaderFileConfiguredPath :: !FilePath,
    loaderFileConfiguredDeviceId :: !Integer,
    loaderFileConfiguredFileId :: !Integer,
    loaderFileConfiguredMode :: !Integer,
    loaderFileConfiguredSize :: !Integer,
    loaderFileCanonicalPath :: !FilePath,
    loaderFileCanonicalDeviceId :: !Integer,
    loaderFileCanonicalFileId :: !Integer,
    loaderFileCanonicalMode :: !Integer,
    loaderFileCanonicalSize :: !Integer,
    loaderFileDigest :: !Text
  }
  deriving (Eq, Show)

-- | Descriptor-derived ELF metadata and exact configured/canonical file
-- identity. Every ELF object in the closed image roots, the PT_INTERP loader,
-- and every recursively resolved DT_NEEDED object has one record.
data NativeArtifactLoaderObjectEvidence
  = NativeArtifactLoaderObjectEvidence
  { loaderObjectConfiguredPath :: !FilePath,
    loaderObjectConfiguredDeviceId :: !Integer,
    loaderObjectConfiguredFileId :: !Integer,
    loaderObjectConfiguredMode :: !Integer,
    loaderObjectConfiguredSize :: !Integer,
    loaderObjectCanonicalPath :: !FilePath,
    loaderObjectCanonicalDeviceId :: !Integer,
    loaderObjectCanonicalFileId :: !Integer,
    loaderObjectCanonicalMode :: !Integer,
    loaderObjectCanonicalSize :: !Integer,
    loaderObjectDigest :: !Text,
    loaderObjectClassBits :: !Int,
    loaderObjectEndian :: !Text,
    loaderObjectMachine :: !Int,
    loaderObjectInterpreter :: !(Maybe FilePath),
    loaderObjectSoname :: !(Maybe FilePath),
    loaderObjectNeeded :: ![FilePath],
    loaderObjectRPath :: ![FilePath],
    loaderObjectRunPath :: ![FilePath]
  }
  deriving (Eq, Show)

-- | One exact loader edge. The ordered search directories are the actual
-- metadata used by the package-owned resolver. The resolved configured and
-- canonical paths must name an object in 'loaderEvidenceObjects'.
data NativeArtifactLoaderResolutionEvidence
  = NativeArtifactLoaderResolutionEvidence
  { loaderResolutionRequester :: !FilePath,
    loaderResolutionNeeded :: !FilePath,
    loaderResolutionSearchDirectories :: ![FilePath],
    loaderResolutionUsedCache :: !Bool,
    loaderResolutionCacheEntryIndex :: !(Maybe Int),
    loaderResolutionConfiguredPath :: !FilePath,
    loaderResolutionCanonicalPath :: !FilePath
  }
  deriving (Eq, Show)

data NativeArtifactLoaderEvidence
  = NativeArtifactLoaderEvidence
  { loaderEvidenceEntryObject :: !FilePath,
    loaderEvidenceCache :: !(Maybe NativeArtifactLoaderFileEvidence),
    loaderEvidenceObjects :: ![NativeArtifactLoaderObjectEvidence],
    loaderEvidenceResolutions :: ![NativeArtifactLoaderResolutionEvidence],
    loaderEvidenceMaximumDepth :: !Int
  }
  deriving (Eq, Show)

instance ToJSON NativeArtifactTargetExecutableEvidence where
  toJSON evidence =
    object
      [ "configuredPath" .= targetExecutableConfiguredPath evidence,
        "configuredDeviceId" .= targetExecutableConfiguredDeviceId evidence,
        "configuredFileId" .= targetExecutableConfiguredFileId evidence,
        "configuredMode" .= targetExecutableConfiguredMode evidence,
        "configuredSize" .= targetExecutableConfiguredSize evidence,
        "canonicalPath" .= targetExecutableCanonicalPath evidence,
        "canonicalDeviceId" .= targetExecutableCanonicalDeviceId evidence,
        "canonicalFileId" .= targetExecutableCanonicalFileId evidence,
        "canonicalMode" .= targetExecutableCanonicalMode evidence,
        "canonicalSize" .= targetExecutableCanonicalSize evidence,
        "digest" .= targetExecutableDigest evidence
      ]

instance FromJSON NativeArtifactTargetExecutableEvidence where
  parseJSON =
    withObject "NativeArtifactTargetExecutableEvidence" $ \value ->
      NativeArtifactTargetExecutableEvidence
        <$> value .: "configuredPath"
        <*> value .: "configuredDeviceId"
        <*> value .: "configuredFileId"
        <*> value .: "configuredMode"
        <*> value .: "configuredSize"
        <*> value .: "canonicalPath"
        <*> value .: "canonicalDeviceId"
        <*> value .: "canonicalFileId"
        <*> value .: "canonicalMode"
        <*> value .: "canonicalSize"
        <*> value .: "digest"

instance ToJSON NativeArtifactTargetClosureEvidence where
  toJSON evidence =
    object
      [ "path" .= targetClosurePath evidence,
        "deviceId" .= targetClosureDeviceId evidence,
        "fileId" .= targetClosureFileId evidence,
        "mode" .= targetClosureMode evidence,
        "digest" .= targetClosureDigest evidence
      ]

instance FromJSON NativeArtifactTargetClosureEvidence where
  parseJSON =
    withObject "NativeArtifactTargetClosureEvidence" $ \value ->
      NativeArtifactTargetClosureEvidence
        <$> value .: "path"
        <*> value .: "deviceId"
        <*> value .: "fileId"
        <*> value .: "mode"
        <*> value .: "digest"

instance ToJSON NativeArtifactTargetEvidence where
  toJSON evidence =
    object
      [ "contractFingerprint"
          .= targetEvidenceContractFingerprint evidence,
        "executable" .= targetEvidenceExecutable evidence,
        "closures" .= targetEvidenceClosures evidence,
        "loader" .= targetEvidenceLoader evidence
      ]

instance FromJSON NativeArtifactTargetEvidence where
  parseJSON =
    withObject "NativeArtifactTargetEvidence" $ \value ->
      NativeArtifactTargetEvidence
        <$> value .: "contractFingerprint"
        <*> value .: "executable"
        <*> value .: "closures"
        <*> value .: "loader"

instance ToJSON NativeArtifactLoaderFileEvidence where
  toJSON evidence =
    object
      [ "configuredPath" .= loaderFileConfiguredPath evidence,
        "configuredDeviceId" .= loaderFileConfiguredDeviceId evidence,
        "configuredFileId" .= loaderFileConfiguredFileId evidence,
        "configuredMode" .= loaderFileConfiguredMode evidence,
        "configuredSize" .= loaderFileConfiguredSize evidence,
        "canonicalPath" .= loaderFileCanonicalPath evidence,
        "canonicalDeviceId" .= loaderFileCanonicalDeviceId evidence,
        "canonicalFileId" .= loaderFileCanonicalFileId evidence,
        "canonicalMode" .= loaderFileCanonicalMode evidence,
        "canonicalSize" .= loaderFileCanonicalSize evidence,
        "digest" .= loaderFileDigest evidence
      ]

instance FromJSON NativeArtifactLoaderFileEvidence where
  parseJSON =
    withObject "NativeArtifactLoaderFileEvidence" $ \value ->
      NativeArtifactLoaderFileEvidence
        <$> value .: "configuredPath"
        <*> value .: "configuredDeviceId"
        <*> value .: "configuredFileId"
        <*> value .: "configuredMode"
        <*> value .: "configuredSize"
        <*> value .: "canonicalPath"
        <*> value .: "canonicalDeviceId"
        <*> value .: "canonicalFileId"
        <*> value .: "canonicalMode"
        <*> value .: "canonicalSize"
        <*> value .: "digest"

instance ToJSON NativeArtifactLoaderObjectEvidence where
  toJSON evidence =
    object
      [ "configuredPath" .= loaderObjectConfiguredPath evidence,
        "configuredDeviceId" .= loaderObjectConfiguredDeviceId evidence,
        "configuredFileId" .= loaderObjectConfiguredFileId evidence,
        "configuredMode" .= loaderObjectConfiguredMode evidence,
        "configuredSize" .= loaderObjectConfiguredSize evidence,
        "canonicalPath" .= loaderObjectCanonicalPath evidence,
        "canonicalDeviceId" .= loaderObjectCanonicalDeviceId evidence,
        "canonicalFileId" .= loaderObjectCanonicalFileId evidence,
        "canonicalMode" .= loaderObjectCanonicalMode evidence,
        "canonicalSize" .= loaderObjectCanonicalSize evidence,
        "digest" .= loaderObjectDigest evidence,
        "classBits" .= loaderObjectClassBits evidence,
        "endian" .= loaderObjectEndian evidence,
        "machine" .= loaderObjectMachine evidence,
        "interpreter" .= loaderObjectInterpreter evidence,
        "soname" .= loaderObjectSoname evidence,
        "needed" .= loaderObjectNeeded evidence,
        "rpath" .= loaderObjectRPath evidence,
        "runpath" .= loaderObjectRunPath evidence
      ]

instance FromJSON NativeArtifactLoaderObjectEvidence where
  parseJSON =
    withObject "NativeArtifactLoaderObjectEvidence" $ \value ->
      NativeArtifactLoaderObjectEvidence
        <$> value .: "configuredPath"
        <*> value .: "configuredDeviceId"
        <*> value .: "configuredFileId"
        <*> value .: "configuredMode"
        <*> value .: "configuredSize"
        <*> value .: "canonicalPath"
        <*> value .: "canonicalDeviceId"
        <*> value .: "canonicalFileId"
        <*> value .: "canonicalMode"
        <*> value .: "canonicalSize"
        <*> value .: "digest"
        <*> value .: "classBits"
        <*> value .: "endian"
        <*> value .: "machine"
        <*> value .: "interpreter"
        <*> value .: "soname"
        <*> value .: "needed"
        <*> value .: "rpath"
        <*> value .: "runpath"

instance ToJSON NativeArtifactLoaderResolutionEvidence where
  toJSON evidence =
    object
      [ "requester" .= loaderResolutionRequester evidence,
        "needed" .= loaderResolutionNeeded evidence,
        "searchDirectories" .= loaderResolutionSearchDirectories evidence,
        "usedCache" .= loaderResolutionUsedCache evidence,
        "cacheEntryIndex" .= loaderResolutionCacheEntryIndex evidence,
        "configuredPath" .= loaderResolutionConfiguredPath evidence,
        "canonicalPath" .= loaderResolutionCanonicalPath evidence
      ]

instance FromJSON NativeArtifactLoaderResolutionEvidence where
  parseJSON =
    withObject "NativeArtifactLoaderResolutionEvidence" $ \value ->
      NativeArtifactLoaderResolutionEvidence
        <$> value .: "requester"
        <*> value .: "needed"
        <*> value .: "searchDirectories"
        <*> value .: "usedCache"
        <*> value .: "cacheEntryIndex"
        <*> value .: "configuredPath"
        <*> value .: "canonicalPath"

instance ToJSON NativeArtifactLoaderEvidence where
  toJSON evidence =
    object
      [ "entryObject" .= loaderEvidenceEntryObject evidence,
        "cache" .= loaderEvidenceCache evidence,
        "objects" .= loaderEvidenceObjects evidence,
        "resolutions" .= loaderEvidenceResolutions evidence,
        "maximumDepth" .= loaderEvidenceMaximumDepth evidence
      ]

instance FromJSON NativeArtifactLoaderEvidence where
  parseJSON =
    withObject "NativeArtifactLoaderEvidence" $ \value ->
      NativeArtifactLoaderEvidence
        <$> value .: "entryObject"
        <*> value .: "cache"
        <*> value .: "objects"
        <*> value .: "resolutions"
        <*> value .: "maximumDepth"

nativeArtifactTarget ::
  NativeArtifactIdentity ->
  Text ->
  Text ->
  Either String NativeArtifactTarget
nativeArtifactTarget identity substrate architecture =
  case (substrate, architecture, nativeArtifactAdapterId identity) of
    ("apple-silicon", "arm64", "llama-cpp-cli") ->
      appleTarget identity (InstalledTarget "native/bin/llama-cli") NoTargetArgumentPrefix
    ("apple-silicon", "arm64", "whisper-cpp-cli") ->
      appleTarget identity (InstalledTarget "native/bin/whisper-cli") NoTargetArgumentPrefix
    ("apple-silicon", "arm64", adapterId)
      | adapterId
          `elem` [ "ctranslate2-native",
                   "onnx-runtime-native",
                   "mlx-native",
                   "coreml-native"
                 ] ->
          appleTarget
            identity
            (InstalledTarget "venv/bin/infernix-python")
            InstalledPythonRunnerPrefix
    ("apple-silicon", "arm64", "jvm-native") ->
      appleTarget
        identity
        (InstalledTarget "Audiveris.app/Contents/runtime/Contents/Home/bin/java")
        NoTargetArgumentPrefix
    ("linux-native", laneArchitecture, "llama-cpp-cli")
      | supportedLinuxArchitecture laneArchitecture ->
          linuxTarget
            identity
            laneArchitecture
            -- llama.cpp b9704 split the former single front-end: `llama-cli`
            -- is now the interactive chat UI and refuses `--no-conversation`
            -- at runtime ("please use llama-completion instead", printed to
            -- stdout) while continuing in chat mode anyway. Under the retired
            -- target a *successful* run published the chat banner, build
            -- string, slash-command list, echoed prompt, and timing footer as
            -- the model's answer — output that is not the model's, which the
            -- realness contract forbids. `llama-completion` is the one-shot
            -- completion front-end and ships in the same pinned payload.
            (ImageTarget "/opt/infernix/native-payloads/llama.cpp/llama-b9704/llama-completion")
            NoTargetArgumentPrefix
            [ImageClosureRoot "/opt/infernix/native-payloads/llama.cpp/llama-b9704"]
    ("linux-native", laneArchitecture, "whisper-cpp-cli")
      | supportedLinuxArchitecture laneArchitecture ->
          let payloadArchitecture =
                if laneArchitecture == "amd64" then "x64" else "arm64"
              closureRoot =
                "/opt/infernix/native-payloads/whisper.cpp/whisper-bin-ubuntu-"
                  <> Text.unpack payloadArchitecture
           in linuxTarget
                identity
                laneArchitecture
                (ImageTarget (closureRoot </> "whisper-cli"))
                NoTargetArgumentPrefix
                [ImageClosureRoot closureRoot]
    ("linux-native", laneArchitecture, adapterId)
      | supportedLinuxArchitecture laneArchitecture,
        adapterId `elem` ["ctranslate2-native", "onnx-runtime-native"] ->
          linuxTarget
            identity
            laneArchitecture
            (ImageTarget "/opt/infernix/native-python/bin/python")
            ImagePythonRunnerPrefix
            [ ImageClosureRoot "/opt/infernix/native-python",
              ImageClosureRoot "/workspace/python/native-runners"
            ]
    ("linux-native", laneArchitecture, "jvm-native")
      | supportedLinuxArchitecture laneArchitecture ->
          linuxTarget
            identity
            laneArchitecture
            (ImageTarget "/opt/infernix/audiveris-jre/bin/java")
            NoTargetArgumentPrefix
            [ ImageClosureRoot "/opt/infernix/audiveris-jre",
              ImageClosureRoot "/opt/audiveris/lib/app",
              ImageClosureRoot "/opt/infernix/audiveris-javacpp-cache"
            ]
    _ ->
      Left
        ( "closed native target catalog has no entry for "
            <> Text.unpack substrate
            <> "/"
            <> Text.unpack architecture
            <> "/"
            <> Text.unpack (nativeArtifactAdapterId identity)
        )
  where
    appleTarget artifactIdentity executable argumentPrefix =
      Right
        NativeArtifactTarget
          { targetAdapterId = nativeArtifactAdapterId artifactIdentity,
            targetSubstrate = "apple-silicon",
            targetArchitecture = "arm64",
            targetPath = executable,
            targetArgumentPrefix = argumentPrefix,
            targetClosureRoots = [InstalledClosureRoot "."]
          }
    linuxTarget artifactIdentity laneArchitecture executable argumentPrefix closures =
      Right
        NativeArtifactTarget
          { targetAdapterId = nativeArtifactAdapterId artifactIdentity,
            targetSubstrate = "linux-native",
            targetArchitecture = laneArchitecture,
            targetPath = executable,
            targetArgumentPrefix = argumentPrefix,
            targetClosureRoots = closures
          }

supportedLinuxArchitecture :: Text -> Bool
supportedLinuxArchitecture architecture =
  architecture `elem` ["amd64", "arm64"]

nativeArtifactTargetExecutable ::
  FilePath ->
  NativeArtifactTarget ->
  FilePath
nativeArtifactTargetExecutable installRoot target =
  case targetPath target of
    InstalledTarget relativePath -> installRoot </> relativePath
    ImageTarget absolutePath -> absolutePath

-- | The lane architecture this target was resolved for.
--
-- A @linux-native@ image path depends on it, so a caller that already holds a
-- resolved target can re-derive the identical catalog entry from the target
-- itself rather than threading a second architecture value that could disagree.
nativeArtifactTargetArchitecture :: NativeArtifactTarget -> Text
nativeArtifactTargetArchitecture = targetArchitecture

nativeArtifactTargetIsInstalled :: NativeArtifactTarget -> Bool
nativeArtifactTargetIsInstalled target =
  case targetPath target of
    InstalledTarget _ -> True
    ImageTarget _ -> False

nativeArtifactTargetLeadingArguments ::
  FilePath ->
  Text ->
  NativeArtifactTarget ->
  [String]
nativeArtifactTargetLeadingArguments installRoot engineName target =
  case targetArgumentPrefix target of
    NoTargetArgumentPrefix ->
      case (targetSubstrate target, targetAdapterId target) of
        ("apple-silicon", "jvm-native") ->
          [ "-Dorg.bytedeco.javacpp.cachedir=" <> (installRoot </> "javacpp-cache"),
            "-cp",
            installRoot </> "Audiveris.app" </> "Contents" </> "app" </> "*",
            "Audiveris"
          ]
        ("linux-native", "jvm-native") ->
          [ "-Dorg.bytedeco.javacpp.cachedir=/opt/infernix/audiveris-javacpp-cache",
            "-cp",
            "/opt/audiveris/lib/app/*",
            "Audiveris"
          ]
        _ -> []
    InstalledPythonRunnerPrefix ->
      pythonRunnerArguments
        (installRoot </> "lib/apple_native_runner.py")
    ImagePythonRunnerPrefix ->
      pythonRunnerArguments
        "/workspace/python/native-runners/apple_native_runner.py"
  where
    pythonRunnerArguments runnerPath =
      [ runnerPath,
        "--adapter-id",
        Text.unpack (targetAdapterId target),
        "--engine-name",
        Text.unpack engineName,
        "--expected-python-prefix",
        expectedPythonPrefix
      ]
    expectedPythonPrefix =
      case targetPath target of
        InstalledTarget _ -> installRoot </> "venv"
        ImageTarget executable -> takeDirectory (takeDirectory executable)

nativeArtifactTargetImmutableClosureRoots ::
  FilePath ->
  NativeArtifactTarget ->
  [FilePath]
nativeArtifactTargetImmutableClosureRoots installRoot target =
  map renderClosureRoot (targetClosureRoots target)
  where
    renderClosureRoot closureRoot =
      case closureRoot of
        InstalledClosureRoot relativePath ->
          installRoot </> relativePath
        ImageClosureRoot absolutePath ->
          absolutePath

nativeArtifactTargetFingerprint ::
  NativeArtifactTarget ->
  Text
nativeArtifactTargetFingerprint target =
  "sha256:"
    <> TextEncoding.decodeUtf8
      ( Base16.encode
          ( SHA256.hash
              ( TextEncoding.encodeUtf8
                  ( Text.intercalate
                      "\0"
                      [ "infernix-native-direct-target-v1",
                        targetAdapterId target,
                        targetSubstrate target,
                        targetArchitecture target,
                        renderTargetPath (targetPath target),
                        renderArgumentPrefix (targetArgumentPrefix target),
                        Text.intercalate
                          ","
                          (map renderClosure (targetClosureRoots target)),
                        ""
                      ]
                  )
              )
          )
      )

-- | Canonical content identity for the complete direct-target observation.
-- The NUL-delimited encoding is unambiguous because every observed path and
-- ELF string is rejected if it contains NUL. Lists are sorted by their stable
-- identity fields so observation traversal order cannot change a generation
-- fingerprint.
nativeArtifactTargetEvidenceFingerprint ::
  NativeArtifactTargetEvidence ->
  Text
nativeArtifactTargetEvidenceFingerprint evidence =
  "sha256:"
    <> TextEncoding.decodeUtf8
      ( Base16.encode
          ( SHA256.hash
              ( TextEncoding.encodeUtf8
                  (Text.intercalate "\0" canonicalFields)
              )
          )
      )
  where
    canonicalFields =
      [ "infernix-native-target-evidence-v2",
        targetEvidenceContractFingerprint evidence
      ]
        <> executableFields (targetEvidenceExecutable evidence)
        <> concatMap
          closureFields
          ( List.sortOn
              targetClosurePath
              (targetEvidenceClosures evidence)
          )
        <> maybe
          ["loader", "none"]
          loaderFields
          (targetEvidenceLoader evidence)
        <> [""]

executableFields ::
  NativeArtifactTargetExecutableEvidence ->
  [Text]
executableFields evidence =
  [ "executable",
    Text.pack (targetExecutableConfiguredPath evidence),
    decimal (targetExecutableConfiguredDeviceId evidence),
    decimal (targetExecutableConfiguredFileId evidence),
    decimal (targetExecutableConfiguredMode evidence),
    decimal (targetExecutableConfiguredSize evidence),
    Text.pack (targetExecutableCanonicalPath evidence),
    decimal (targetExecutableCanonicalDeviceId evidence),
    decimal (targetExecutableCanonicalFileId evidence),
    decimal (targetExecutableCanonicalMode evidence),
    decimal (targetExecutableCanonicalSize evidence),
    targetExecutableDigest evidence
  ]

closureFields ::
  NativeArtifactTargetClosureEvidence ->
  [Text]
closureFields evidence =
  [ "closure",
    Text.pack (targetClosurePath evidence),
    decimal (targetClosureDeviceId evidence),
    decimal (targetClosureFileId evidence),
    decimal (targetClosureMode evidence),
    targetClosureDigest evidence
  ]

loaderFields :: NativeArtifactLoaderEvidence -> [Text]
loaderFields evidence =
  [ "loader",
    Text.pack (loaderEvidenceEntryObject evidence),
    decimal (loaderEvidenceMaximumDepth evidence)
  ]
    <> maybe
      ["cache", "none"]
      loaderFileFields
      (loaderEvidenceCache evidence)
    <> concatMap
      loaderObjectFields
      ( List.sortOn
          loaderObjectCanonicalPath
          (loaderEvidenceObjects evidence)
      )
    <> concatMap
      loaderResolutionFields
      ( List.sortOn
          ( \resolution ->
              ( loaderResolutionRequester resolution,
                loaderResolutionNeeded resolution,
                loaderResolutionCanonicalPath resolution
              )
          )
          (loaderEvidenceResolutions evidence)
      )

loaderFileFields :: NativeArtifactLoaderFileEvidence -> [Text]
loaderFileFields evidence =
  [ "cache",
    Text.pack (loaderFileConfiguredPath evidence),
    decimal (loaderFileConfiguredDeviceId evidence),
    decimal (loaderFileConfiguredFileId evidence),
    decimal (loaderFileConfiguredMode evidence),
    decimal (loaderFileConfiguredSize evidence),
    Text.pack (loaderFileCanonicalPath evidence),
    decimal (loaderFileCanonicalDeviceId evidence),
    decimal (loaderFileCanonicalFileId evidence),
    decimal (loaderFileCanonicalMode evidence),
    decimal (loaderFileCanonicalSize evidence),
    loaderFileDigest evidence
  ]

loaderObjectFields :: NativeArtifactLoaderObjectEvidence -> [Text]
loaderObjectFields evidence =
  [ "object",
    Text.pack (loaderObjectConfiguredPath evidence),
    decimal (loaderObjectConfiguredDeviceId evidence),
    decimal (loaderObjectConfiguredFileId evidence),
    decimal (loaderObjectConfiguredMode evidence),
    decimal (loaderObjectConfiguredSize evidence),
    Text.pack (loaderObjectCanonicalPath evidence),
    decimal (loaderObjectCanonicalDeviceId evidence),
    decimal (loaderObjectCanonicalFileId evidence),
    decimal (loaderObjectCanonicalMode evidence),
    decimal (loaderObjectCanonicalSize evidence),
    loaderObjectDigest evidence,
    decimal (loaderObjectClassBits evidence),
    loaderObjectEndian evidence,
    decimal (loaderObjectMachine evidence),
    maybe "" Text.pack (loaderObjectInterpreter evidence),
    maybe "" Text.pack (loaderObjectSoname evidence)
  ]
    <> taggedPaths "needed" (loaderObjectNeeded evidence)
    <> taggedPaths "rpath" (loaderObjectRPath evidence)
    <> taggedPaths "runpath" (loaderObjectRunPath evidence)

loaderResolutionFields ::
  NativeArtifactLoaderResolutionEvidence ->
  [Text]
loaderResolutionFields evidence =
  [ "resolution",
    Text.pack (loaderResolutionRequester evidence),
    Text.pack (loaderResolutionNeeded evidence),
    if loaderResolutionUsedCache evidence then "cache" else "directory",
    maybe "" decimal (loaderResolutionCacheEntryIndex evidence),
    Text.pack (loaderResolutionConfiguredPath evidence),
    Text.pack (loaderResolutionCanonicalPath evidence)
  ]
    <> taggedPaths
      "search"
      (loaderResolutionSearchDirectories evidence)

taggedPaths :: Text -> [FilePath] -> [Text]
taggedPaths tag paths =
  [tag, decimal (length paths)] <> map Text.pack paths

decimal :: (Show value) => value -> Text
decimal = Text.pack . show

renderTargetPath :: TargetPath -> Text
renderTargetPath target =
  case target of
    InstalledTarget path -> "installed:" <> Text.pack path
    ImageTarget path -> "image:" <> Text.pack path

renderArgumentPrefix :: TargetArgumentPrefix -> Text
renderArgumentPrefix argumentPrefix =
  case argumentPrefix of
    NoTargetArgumentPrefix -> "none"
    InstalledPythonRunnerPrefix -> "installed-python-runner-v1"
    ImagePythonRunnerPrefix -> "image-python-runner-v1"

renderClosure :: ClosureRoot -> Text
renderClosure closureRoot =
  case closureRoot of
    InstalledClosureRoot path -> "installed:" <> Text.pack path
    ImageClosureRoot path -> "image:" <> Text.pack path
