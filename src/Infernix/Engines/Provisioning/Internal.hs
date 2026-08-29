{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.Provisioning.Internal
  ( AppleAdapterId (..),
    ApplePythonAdapterId (..),
    ApplePoetrySetupId (..),
    PoetryInstallGroup (..),
    ProvisioningPackageClosureRole (..),
    ProvisioningPackageClosureIdentity (..),
    ProvisioningRuntimeLibraryIdentity (..),
    ProvisioningExecutableIdentity (..),
    InstalledPythonSourceIsolationSpec (..),
    PositiveProvisioningTimeout,
    mkPositiveProvisioningTimeout,
    positiveProvisioningTimeoutMicros,
    linuxNativeSmokeTimeout,
    LinuxNativeSmokePolicy (..),
    ProvisioningCommand (..),
    ProvisioningOperation (..),
    appleAdapterForPython,
    appleAdapterSlug,
    applePythonAdapterSlug,
    applePoetryAdapterSlug,
    applePoetrySetupEntrypoint,
    poetryInstallGroupSlug,
    pinnedPipRequirement,
    pinnedPoetryBootstrapRequirements,
    pinnedPythonRequirements,
    fixedVenvPythonRelativePath,
    poetryBootstrapRequirementsRelativePath,
    installedSmokeExecutableRelativePath,
    installedSmokeArguments,
    nativeArtifactIdentity,
    linuxNativeArtifactSmokeArguments,
    installedPythonSourceIsolationSandboxExecutable,
    installedPythonSourceIsolationAuditInjectorExecutable,
    installedPythonDyldRuntimeEnvironment,
    installedPythonSourceIsolationProfile,
    installedPythonSourceIsolationProfileForCounts,
    installedPythonSourceIsolationArguments,
    installedPythonSourceIsolationArgumentsForPaths,
    installedPythonSourceIsolationMarker,
    installedPythonSourceIsolationReceiptDigestFor,
    audiverisVersion,
    audiverisDmgFileName,
    audiverisDmgUrl,
    provisioningCommandOperation,
    applePythonAdapterForApple,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Base16 qualified as Base16
import Data.List qualified as List
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Engines.Artifact.Identity qualified as Identity
import Infernix.Engines.Artifact.Recipe qualified as Recipe
import Infernix.Engines.Artifact.Target qualified as Target
import System.FilePath ((</>))

-- | Exact executable evidence minted by the provisioning region and consumed
-- only by the bounded-command anchor. Device and file identifiers establish
-- birth identity; the digest closes in-place content mutation. This module is
-- package-internal, so callers cannot manufacture executable authority.
data ProvisioningPackageClosureRole
  = ProvisioningPythonHomeClosure
  | ProvisioningPythonPathClosure
  | ProvisioningProjectSourceClosure
  | ProvisioningArtifactRootClosure
  deriving (Eq, Show)

data ProvisioningPackageClosureIdentity = ProvisioningPackageClosureIdentity
  { provisioningPackageClosureRole :: !ProvisioningPackageClosureRole,
    provisioningPackageClosureRoot :: !FilePath,
    provisioningPackageClosureDeviceId :: !Integer,
    provisioningPackageClosureFileId :: !Integer,
    provisioningPackageClosureMode :: !Integer,
    provisioningPackageClosureBytes :: !Integer,
    provisioningPackageClosureFiles :: !Integer,
    provisioningPackageClosureDigest :: !Text.Text
  }
  deriving (Eq, Show)

data ProvisioningRuntimeLibraryIdentity = ProvisioningRuntimeLibraryIdentity
  { provisioningRuntimeLibraryLeafName :: !FilePath,
    provisioningRuntimeLibraryConfiguredPath :: !FilePath,
    provisioningRuntimeLibraryCanonicalPath :: !FilePath,
    provisioningRuntimeLibraryDeviceId :: !Integer,
    provisioningRuntimeLibraryFileId :: !Integer,
    provisioningRuntimeLibraryMode :: !Integer,
    provisioningRuntimeLibrarySize :: !Integer,
    provisioningRuntimeLibraryDigest :: !Text.Text
  }
  deriving (Eq, Show)

data ProvisioningExecutableIdentity = ProvisioningExecutableIdentity
  { provisioningExecutableConfiguredPath :: !FilePath,
    provisioningExecutableCanonicalPath :: !FilePath,
    provisioningExecutableDeviceId :: !Integer,
    provisioningExecutableFileId :: !Integer,
    provisioningExecutableMode :: !Integer,
    provisioningExecutableSize :: !Integer,
    provisioningExecutableDigest :: !Text.Text,
    provisioningExecutablePackageClosures ::
      ![ProvisioningPackageClosureIdentity],
    provisioningExecutableRuntimeLibraries ::
      ![ProvisioningRuntimeLibraryIdentity]
  }
  deriving (Eq, Show)

-- | Exact external source-runtime identities denied only by the Darwin cohort
-- installed smoke. Paths never enter the SBPL program text: the fixed renderer
-- supplies them solely as @-D@ parameter values. The sandbox executable is an
-- exact platform-binary identity rather than a caller-selected wrapper.
data InstalledPythonSourceIsolationSpec = InstalledPythonSourceIsolationSpec
  { installedPythonSourceIsolationSandboxIdentity ::
      !ProvisioningExecutableIdentity,
    installedPythonSourceIsolationAuditInjectorIdentity ::
      !ProvisioningExecutableIdentity,
    installedPythonSourceIsolationDirectories ::
      ![ProvisioningPackageClosureIdentity],
    installedPythonSourceIsolationFiles ::
      ![ProvisioningRuntimeLibraryIdentity],
    installedPythonSourceIsolationWritableProbeIdentity ::
      !ProvisioningRuntimeLibraryIdentity,
    installedPythonSourceIsolationReceiptDigest :: !Text.Text
  }
  deriving (Eq, Show)

newtype PositiveProvisioningTimeout
  = PositiveProvisioningTimeout Int
  deriving (Eq, Show)

mkPositiveProvisioningTimeout ::
  Int ->
  Either String PositiveProvisioningTimeout
mkPositiveProvisioningTimeout microseconds
  | microseconds <= 0 =
      Left "provisioning deadline must be positive"
  | otherwise =
      Right (PositiveProvisioningTimeout microseconds)

positiveProvisioningTimeoutMicros ::
  PositiveProvisioningTimeout ->
  Int
positiveProvisioningTimeoutMicros
  (PositiveProvisioningTimeout microseconds) =
    microseconds

linuxNativeSmokeTimeout :: PositiveProvisioningTimeout
linuxNativeSmokeTimeout =
  PositiveProvisioningTimeout (30 * 1000 * 1000)

data LinuxNativeSmokePolicy
  = RequireImagePayload
  | AllowFixturePayloadAbsence
  deriving (Eq, Show)

-- | The complete Apple runner catalog admitted to provisioning. These
-- constructors remain package-internal so the supported facade can expose
-- named identities without exposing a command-construction surface.
data AppleAdapterId
  = LlamaCppCliAdapter
  | WhisperCppCliAdapter
  | CTranslate2Adapter
  | OnnxRuntimeAdapter
  | MlxAdapter
  | CoreMlAdapter
  | JvmAdapter
  deriving (Bounded, Enum, Eq, Show)

-- | The subset whose payload is hydrated into a per-artifact Python virtual
-- environment. Keeping this separate makes a pip operation for a non-Python
-- adapter unrepresentable.
data ApplePythonAdapterId
  = CTranslate2PythonAdapter
  | OnnxRuntimePythonAdapter
  | MlxPythonAdapter
  | CoreMlPythonAdapter
  deriving (Bounded, Enum, Eq, Show)

-- | The four Poetry-backed engine setup entrypoints admitted on Apple. The
-- entrypoint and adapter id are paired by construction.
data ApplePoetrySetupId
  = DiffusersPoetrySetup
  | PytorchPoetrySetup
  | TransformersPoetrySetup
  | VllmPoetrySetup
  deriving (Eq, Show)

data PoetryInstallGroup
  = PoetryDevGroup
  | PoetryCudaGroup
  | PoetryLinuxCpuGroup
  | PoetryAppleSiliconGroup
  deriving (Eq, Ord, Show)

poetryInstallGroupSlug :: PoetryInstallGroup -> String
poetryInstallGroupSlug group =
  case group of
    PoetryDevGroup -> "dev"
    PoetryCudaGroup -> "cuda"
    PoetryLinuxCpuGroup -> "linux-cpu"
    PoetryAppleSiliconGroup -> "apple-silicon"

appleAdapterForPython :: ApplePythonAdapterId -> AppleAdapterId
appleAdapterForPython adapter =
  case adapter of
    CTranslate2PythonAdapter -> CTranslate2Adapter
    OnnxRuntimePythonAdapter -> OnnxRuntimeAdapter
    MlxPythonAdapter -> MlxAdapter
    CoreMlPythonAdapter -> CoreMlAdapter

applePythonAdapterForApple :: AppleAdapterId -> Maybe ApplePythonAdapterId
applePythonAdapterForApple adapter =
  case adapter of
    CTranslate2Adapter -> Just CTranslate2PythonAdapter
    OnnxRuntimeAdapter -> Just OnnxRuntimePythonAdapter
    MlxAdapter -> Just MlxPythonAdapter
    CoreMlAdapter -> Just CoreMlPythonAdapter
    LlamaCppCliAdapter -> Nothing
    WhisperCppCliAdapter -> Nothing
    JvmAdapter -> Nothing

appleAdapterSlug :: AppleAdapterId -> String
appleAdapterSlug adapter =
  case adapter of
    LlamaCppCliAdapter -> "llama-cpp-cli"
    WhisperCppCliAdapter -> "whisper-cpp-cli"
    CTranslate2Adapter -> "ctranslate2-native"
    OnnxRuntimeAdapter -> "onnx-runtime-native"
    MlxAdapter -> "mlx-native"
    CoreMlAdapter -> "coreml-native"
    JvmAdapter -> "jvm-native"

applePythonAdapterSlug :: ApplePythonAdapterId -> String
applePythonAdapterSlug =
  appleAdapterSlug . appleAdapterForPython

applePoetryAdapterSlug :: ApplePoetrySetupId -> String
applePoetryAdapterSlug setup =
  case setup of
    DiffusersPoetrySetup -> "diffusers-python"
    PytorchPoetrySetup -> "pytorch-python"
    TransformersPoetrySetup -> "transformers-python"
    VllmPoetrySetup -> "vllm-python"

applePoetrySetupEntrypoint :: ApplePoetrySetupId -> String
applePoetrySetupEntrypoint setup =
  "setup-" <> applePoetryAdapterSlug setup

-- | Pip itself is part of the resolved provisioning input, rather than an
-- unconstrained upgrade to whatever release is current at execution time.
pinnedPipRequirement :: String
pinnedPipRequirement = Recipe.pinnedPipRequirement

pinnedPoetryBootstrapRequirements :: [String]
pinnedPoetryBootstrapRequirements =
  [ "anyio==4.14.2 --hash=sha256:9f505dda5ac9f0c8309b5e8bd445a8c2bf7246f3ce950121e45ea15bc41d1494",
    "backports.zstd==1.6.0 --hash=sha256:1d146926e997d2d3de8212bdcbf4985344a2622ca3bec458d8908000a84fd883",
    "build==1.5.0 --hash=sha256:13f3eecb844759ab66efec90ca17639bbf14dc06cb2fdf37a9010322d9c50a6f",
    "CacheControl==0.14.4 --hash=sha256:b7ac014ff72ee199b5f8af1de29d60239954f223e948196fa3d84adaffc71d2b",
    "certifi==2026.7.22 --hash=sha256:62f22742b58a1a33014a2b6b706588a8d7e2a88ae7bd1a6ebe8c992928483775",
    "cffi==2.1.0 --hash=sha256:78474632761faa0fb96f30b1c928c84ebcf68713cbb80d15bab09dfe61640fde",
    "charset-normalizer==3.4.9 --hash=sha256:45b0cc4e3556cd875e09102988d1ab8356c998b596c9fced84547c8138b487a0",
    "cleo==2.1.0 --hash=sha256:4a31bd4dd45695a64ee3c4758f583f134267c2bc518d8ae9a29cf237d009b07e",
    "crashtest==0.4.1 --hash=sha256:8d23eac5fa660409f57472e3851dab7ac18aba459a8d19cbbba86d3d5aecd2a5",
    "distlib==0.4.3 --hash=sha256:4b0ce306c966eb73bc3a7b6abad017c556dadd92c44701562cd528ac7fde4d5b",
    "dulwich==1.2.12 --hash=sha256:af7560e02c12aa7d6bdb8414bcde8c236a10d8f32db5c9e71e6cfdbe3e7d5795",
    "fastjsonschema==2.22.1 --hash=sha256:cf377ff5c9a6f4f3125fb35f75a2c5767bd824ffbcf62c209a93cd48d1453999",
    "filelock==3.32.0 --hash=sha256:d396bea984af47333ef05e50eae7eff88c84256de6112aea0ec48a233c064fe3",
    "findpython==0.8.0 --hash=sha256:4a61ee1618a8b55014f7d41f59345d322be93f6ce62395bdccccc651b3f7e28a",
    "h11==0.16.0 --hash=sha256:63cf8bbe7522de3bf65932fda1d9c2772064ffb3dae62d55932da54b31cb6c86",
    "httpcore==1.0.9 --hash=sha256:2d400746a40668fc9dec9810239072b40b4484b640a8c38fd654a024c7a1bf55",
    "httpx==0.28.1 --hash=sha256:d909fcccc110f8c7faf814ca82a9a4d816bc5a6dbfea25d6591d6985b8ba59ad",
    "idna==3.18 --hash=sha256:7f952cbe720b688055e3f87de14f5c3e5fdaa8bc3928985c4077ca689de849a2",
    "installer==1.0.1 --hash=sha256:011d045df8b954ced7dde3a7e42ae4418da40ecda7990f2d11d5ed7c146fd98b",
    "jaraco.classes==3.4.0 --hash=sha256:f662826b6bed8cace05e7ff873ce0f9283b5c924470fe664fff1c2f00f581790",
    "jaraco.context==6.1.2 --hash=sha256:bf8150b79a2d5d91ae48629d8b427a8f7ba0e1097dd6202a9059f29a36379535",
    "jaraco.functools==4.6.0 --hash=sha256:99e3dc0060c5cbe8fcd1cdb36258e2a65ca40f1566b2033b12abb1bb44dd3c30",
    "keyring==25.7.0 --hash=sha256:be4a0b195f149690c166e850609a477c532ddbfbaed96a404d4e43f8d5e2689f",
    "more-itertools==11.1.0 --hash=sha256:4b65538ae22f6fed0ce4874efd317463a7489796a0939fa66824dd542125a192",
    "msgpack==1.2.1 --hash=sha256:d3567748a5107cb40cdf66a275430c2f87c07777698f4bfd25c35f44d533258c",
    "packaging==26.2 --hash=sha256:5fc45236b9446107ff2415ce77c807cee2862cb6fac22b8a73826d0693b0980e",
    "pbs-installer==2026.7.18 --hash=sha256:fefa193fa55bfe1a09aedbb8fc24ba2fc05252985f3e90ffbf89175e9490aa9a",
    "pip==25.1.1 --hash=sha256:2913a38a2abf4ea6b64ab507bd9e967f3b53dc1ede74b01b0931e1ce548751af",
    "pkginfo==1.12.1.2 --hash=sha256:c783ac885519cab2c34927ccfa6bf64b5a704d7c69afaea583dd9b7afe969343",
    "platformdirs==4.11.0 --hash=sha256:360ccded2b7fce0af0ff80cc8f5942a1c5d99b0e856033acb030bfc634709e74",
    "poetry-core==2.4.0 --hash=sha256:4305848477da00272bebd3f615bbec87f64bd117cdb858ab660b626a06a9d96c",
    "poetry==2.4.1 --hash=sha256:a91f13279a3c9add0d12c5ca5c7cb173622930a5c8272fee68c751cb5c72f951",
    "pycparser==3.0 --hash=sha256:b727414169a36b7d524c1c3e31839a521725078d7b2ff038656844266160a992",
    "pyproject_hooks==1.2.0 --hash=sha256:9e5c6bfa8dcc30091c74b0cf803c81fdd29d94f01992a7707bc97babb1141913",
    "python-discovery==1.5.0 --hash=sha256:70c4fc61b4e7404e44f01d6fc44a715c4d685ca6cea83d295922f05891877c98",
    "RapidFuzz==3.14.5 --hash=sha256:1e910eebca9fd0eba245c0555e764597e8a0cccb673a92da2dc2397050725f48",
    "requests-toolbelt==1.0.0 --hash=sha256:cccfdd665f0a24fcf4726e690f65639d272bb0637b9b92dfd91a5568ccf6bd06",
    "requests==2.34.2 --hash=sha256:2a0d60c172f83ac6ab31e4554906c0f3b3588d37b5cb939b1c061f4907e278e0",
    "shellingham==1.5.4 --hash=sha256:7ecfff8f2fd72616f7481040475a65b2bf8af90a56c89140852d1120324e8686",
    "tomlkit==0.15.1 --hash=sha256:177a05aece5a8ca5266fd3c448abb47b8d352f09d477d3ca8332db4d89b24304",
    "trove-classifiers==2026.6.1.19 --hash=sha256:ab4c4ec93cc4a4e7815fa759906e05e6bb3f2fbd92ea0f897288c6a43efd15b3",
    "typing-extensions==4.16.0 --hash=sha256:481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8",
    "urllib3==2.7.0 --hash=sha256:9fb4c81ebbb1ce9531cce37674bbc6f1360472bc18ca9a553ede278ef7276897",
    "virtualenv==21.7.0 --hash=sha256:a8370c1c5530fbabf955e40b8fbbc68a431648b10f9433faa587db30a06e51dd",
    "xattr==1.3.0 --hash=sha256:fa23a25220e29d956cedf75746e3df6cc824cc1553326d6516479967c540e386"
  ]

-- | Direct provisioning requirements are exact. Transitive resolution is
-- recorded after installation by the typed provenance query.
pinnedPythonRequirements :: ApplePythonAdapterId -> [String]
pinnedPythonRequirements adapter =
  Recipe.pinnedPythonRequirements $
    case adapter of
      CTranslate2PythonAdapter ->
        Recipe.CTranslate2PythonRecipe
      OnnxRuntimePythonAdapter ->
        Recipe.OnnxRuntimePythonRecipe
      MlxPythonAdapter ->
        Recipe.MlxPythonRecipe
      CoreMlPythonAdapter ->
        Recipe.CoreMlPythonRecipe

installedSmokeExecutableRelativePath :: AppleAdapterId -> FilePath
installedSmokeExecutableRelativePath adapter =
  case adapter of
    LlamaCppCliAdapter -> "native/bin/llama-completion"
    WhisperCppCliAdapter -> "native/bin/whisper-cli"
    CTranslate2Adapter -> fixedVenvPythonRelativePath
    OnnxRuntimeAdapter -> fixedVenvPythonRelativePath
    MlxAdapter -> fixedVenvPythonRelativePath
    CoreMlAdapter -> fixedVenvPythonRelativePath
    JvmAdapter -> Target.audiverisAppleJvmRelativePath

installedSmokeArguments ::
  AppleAdapterId ->
  FilePath ->
  [String]
installedSmokeArguments adapter artifactRoot =
  case adapter of
    LlamaCppCliAdapter -> ["--version"]
    WhisperCppCliAdapter -> ["--version"]
    CTranslate2Adapter -> pythonArguments
    OnnxRuntimeAdapter -> pythonArguments
    MlxAdapter -> pythonArguments
    CoreMlAdapter -> pythonArguments
    -- `java -version` reports the JVM, on standard error, in three lines. The
    -- smoke's parser wants Audiveris's own seven-field banner, because that is
    -- the version the pinned checksum receipt binds. Reaching it means running
    -- the same classpath and main class the inference target runs, so the smoke
    -- proves the executed thing rather than the interpreter under it.
    JvmAdapter ->
      Target.audiverisAppleLeadingArguments artifactRoot <> ["-version"]
  where
    pythonArguments =
      [ "lib" </> "apple_native_runner.py",
        "--adapter-id",
        appleAdapterSlug adapter,
        "--engine-name",
        appleAdapterSlug adapter,
        "--expected-python-prefix",
        artifactRoot </> "venv",
        "--smoke"
      ]

installedPythonSourceIsolationSandboxExecutable :: FilePath
installedPythonSourceIsolationSandboxExecutable =
  "/usr/bin/sandbox-exec"

installedPythonSourceIsolationAuditInjectorExecutable :: FilePath
installedPythonSourceIsolationAuditInjectorExecutable =
  "/usr/bin/env"

-- | The exact dynamic-loader environment for the installed Python target.
-- The ordinary installed smoke and the source-isolation bridge both consume
-- this renderer, so the bridge cannot silently drift from the relocated
-- framework and library roots whose loader provenance is audited.
installedPythonDyldRuntimeEnvironment ::
  FilePath ->
  [(String, String)]
installedPythonDyldRuntimeEnvironment artifactRoot =
  [ ( "DYLD_FRAMEWORK_PATH",
      artifactRoot </> "python-frameworks"
    ),
    ( "DYLD_LIBRARY_PATH",
      List.intercalate
        ":"
        [ artifactRoot </> "native" </> "lib",
          artifactRoot </> "native" </> "libexec"
        ]
    ),
    ("DYLD_PRINT_LIBRARIES", "1")
  ]

installedPythonSourceIsolationProfile ::
  InstalledPythonSourceIsolationSpec ->
  String
installedPythonSourceIsolationProfile spec =
  installedPythonSourceIsolationProfileForCounts
    (length (installedPythonSourceIsolationDirectories spec))
    (length (installedPythonSourceIsolationFiles spec))

installedPythonSourceIsolationProfileForCounts ::
  Int ->
  Int ->
  String
installedPythonSourceIsolationProfileForCounts directoryCount fileCount =
  unlines
    ( ["(version 1)", "(allow default)"]
        <> concatMap directoryRules directoryParameters
        <> concatMap fileRules fileParameters
    )
  where
    directoryParameters =
      zipWith
        (\index _ -> sourceDirectoryParameter index)
        [(0 :: Int) ..]
        [1 .. directoryCount]
    fileParameters =
      zipWith
        (\index _ -> sourceFileParameter index)
        [(0 :: Int) ..]
        [1 .. fileCount]
    directoryRules parameter =
      [ "(deny file-read* (subpath (param \"" <> parameter <> "\")))",
        "(deny file-write* (subpath (param \"" <> parameter <> "\")))"
      ]
    fileRules parameter =
      [ "(deny file-read* (literal (param \"" <> parameter <> "\")))",
        "(deny file-write* (literal (param \"" <> parameter <> "\")))"
      ]

installedPythonSourceIsolationArguments ::
  AppleAdapterId ->
  FilePath ->
  InstalledPythonSourceIsolationSpec ->
  [String]
installedPythonSourceIsolationArguments adapter artifactRoot spec =
  installedPythonSourceIsolationArgumentsForPaths
    adapter
    artifactRoot
    ( map
        provisioningPackageClosureRoot
        (installedPythonSourceIsolationDirectories spec)
    )
    ( map
        provisioningRuntimeLibraryCanonicalPath
        (installedPythonSourceIsolationFiles spec)
    )
    ( provisioningRuntimeLibraryCanonicalPath
        (installedPythonSourceIsolationWritableProbeIdentity spec)
    )
    (installedPythonSourceIsolationReceiptDigest spec)

installedPythonSourceIsolationArgumentsForPaths ::
  AppleAdapterId ->
  FilePath ->
  [FilePath] ->
  [FilePath] ->
  FilePath ->
  Text.Text ->
  [String]
installedPythonSourceIsolationArgumentsForPaths
  adapter
  artifactRoot
  directoryPaths
  filePaths
  writableProbePath
  receiptDigest =
    [ "-p",
      installedPythonSourceIsolationProfileForCounts
        (length directoryPaths)
        (length filePaths)
    ]
      <> concatMap
        (\(parameter, path) -> ["-D", parameter <> "=" <> path])
        (directoryBindings <> fileBindings)
      <> [installedPythonSourceIsolationAuditInjectorExecutable]
      <> map
        (\(name, value) -> name <> "=" <> value)
        (installedPythonDyldRuntimeEnvironment artifactRoot)
      <> [artifactRoot </> installedSmokeExecutableRelativePath adapter]
      <> installedSmokeArguments adapter artifactRoot
      <> concatMap
        (\(_, path) -> ["--expected-unavailable-source-directory", path])
        directoryBindings
      <> concatMap
        (\(_, path) -> ["--expected-unavailable-source-file", path])
        fileBindings
      <> [ "--expected-unavailable-source-write-probe",
           writableProbePath
         ]
      <> [ "--source-isolation-receipt",
           Text.unpack receiptDigest
         ]
    where
      directoryBindings =
        zipWith
          ( \index path ->
              ( sourceDirectoryParameter index,
                path
              )
          )
          [(0 :: Int) ..]
          directoryPaths
      fileBindings =
        zipWith
          ( \index path ->
              ( sourceFileParameter index,
                path
              )
          )
          [(0 :: Int) ..]
          filePaths

installedPythonSourceIsolationMarker ::
  InstalledPythonSourceIsolationSpec ->
  String
installedPythonSourceIsolationMarker spec =
  "infernix-source-isolation-v1:"
    <> show sourceCount
    <> ":"
    <> Text.unpack (installedPythonSourceIsolationReceiptDigest spec)
  where
    sourceCount =
      length (installedPythonSourceIsolationDirectories spec)
        + length (installedPythonSourceIsolationFiles spec)

installedPythonSourceIsolationReceiptDigestFor ::
  [ProvisioningPackageClosureIdentity] ->
  [ProvisioningRuntimeLibraryIdentity] ->
  Text.Text
installedPythonSourceIsolationReceiptDigestFor directories files =
  "sha256:"
    <> TextEncoding.decodeUtf8
      ( Base16.encode
          ( SHA256.hash
              ( TextEncoding.encodeUtf8
                  (Text.intercalate "\0" receiptFields)
              )
          )
      )
  where
    receiptFields =
      [ "infernix-installed-python-source-isolation-v1",
        "directories=" <> Text.pack (show (length sortedDirectories)),
        "files=" <> Text.pack (show (length sortedFiles))
      ]
        <> concatMap directoryFields sortedDirectories
        <> concatMap fileFields sortedFiles
    sortedDirectories =
      List.sortOn provisioningPackageClosureRoot directories
    sortedFiles =
      List.sortOn provisioningRuntimeLibraryCanonicalPath files
    directoryFields identity =
      [ "directory-role=" <> packageClosureRoleText (provisioningPackageClosureRole identity),
        "directory-root=" <> Text.pack (provisioningPackageClosureRoot identity),
        "directory-device=" <> decimal (provisioningPackageClosureDeviceId identity),
        "directory-file=" <> decimal (provisioningPackageClosureFileId identity),
        "directory-mode=" <> decimal (provisioningPackageClosureMode identity),
        "directory-bytes=" <> decimal (provisioningPackageClosureBytes identity),
        "directory-files=" <> decimal (provisioningPackageClosureFiles identity),
        "directory-digest=" <> provisioningPackageClosureDigest identity
      ]
    fileFields identity =
      [ "file-leaf=" <> Text.pack (provisioningRuntimeLibraryLeafName identity),
        "file-configured=" <> Text.pack (provisioningRuntimeLibraryConfiguredPath identity),
        "file-canonical=" <> Text.pack (provisioningRuntimeLibraryCanonicalPath identity),
        "file-device=" <> decimal (provisioningRuntimeLibraryDeviceId identity),
        "file-id=" <> decimal (provisioningRuntimeLibraryFileId identity),
        "file-mode=" <> decimal (provisioningRuntimeLibraryMode identity),
        "file-size=" <> decimal (provisioningRuntimeLibrarySize identity),
        "file-digest=" <> provisioningRuntimeLibraryDigest identity
      ]
    packageClosureRoleText role =
      case role of
        ProvisioningPythonHomeClosure -> "python-home"
        ProvisioningPythonPathClosure -> "python-path"
        ProvisioningProjectSourceClosure -> "project-source"
        ProvisioningArtifactRootClosure -> "artifact-root"
    decimal = Text.pack . show

sourceDirectoryParameter :: Int -> String
sourceDirectoryParameter index =
  "INFERNIX_SOURCE_DIRECTORY_" <> show index

sourceFileParameter :: Int -> String
sourceFileParameter index =
  "INFERNIX_SOURCE_FILE_" <> show index

fixedVenvPythonRelativePath :: FilePath
fixedVenvPythonRelativePath =
  "venv" </> "bin" </> "infernix-python"

poetryBootstrapRequirementsRelativePath :: FilePath
poetryBootstrapRequirementsRelativePath =
  ".infernix-poetry-bootstrap-requirements.txt"

nativeArtifactIdentity ::
  AppleAdapterId ->
  Either String Identity.NativeArtifactIdentity
nativeArtifactIdentity adapter =
  case Identity.parseNativeArtifactIdentity
    (Text.pack (appleAdapterSlug adapter)) of
    Just identity -> Right identity
    Nothing ->
      Left
        ( "closed Apple adapter omitted from native artifact identity: "
            <> appleAdapterSlug adapter
        )

audiverisVersion :: String
audiverisVersion = Recipe.audiverisVersion

audiverisDmgFileName :: FilePath
audiverisDmgFileName = Recipe.audiverisDmgFileName

audiverisDmgUrl :: String
audiverisDmgUrl = Recipe.audiverisDmgUrl

-- | Closed semantic operations accepted by the bounded subprocess kernel.
-- Callers can supply only path operands; executable choices, argv structure,
-- stdin, package requirements, and labels are fixed by the kernel.
data ProvisioningCommand
  = InstallPoetryProject
      !FilePath
      ![PoetryInstallGroup]
  | -- | Create the in-project Poetry environment before the bounded install.
    -- Poetry chooses its target environment from the running interpreter when
    -- the project has none, and a sealed run points @PYTHONHOME@ at the sealed
    -- copy of Poetry's own environment, so a first install lands the engine's
    -- whole framework payload inside the ephemeral generation instead of the
    -- project. Creating the project environment first makes that choice the
    -- project's rather than the snapshot's. The interpreter is the configured
    -- host Python and the command is deliberately unsealed, because the
    -- environment it writes records the interpreter it was created from and an
    -- ephemeral path recorded there outlives the generation that held it.
    CreatePoetryProjectVenv
      !FilePath
  | GeneratePythonProto
      !FilePath
      !FilePath
  | InstallPoetryBootstrap
      !FilePath
  | ProbePythonVersion
      !ApplePythonAdapterId
      !FilePath
  | CreatePythonVenv
      !ApplePythonAdapterId
      !FilePath
  | UpgradePinnedPip
      !ApplePythonAdapterId
      !FilePath
  | InstallPinnedRequirements
      !ApplePythonAdapterId
      !FilePath
  | DownloadAudiverisDmg
      !FilePath
      !FilePath
  | MountAudiverisDmg
      !FilePath
      !FilePath
      !FilePath
  | DetachAudiverisDmg
      !FilePath
      !FilePath
  | ExtractAudiverisJavaCppNatives
      !FilePath
  | SmokeInstalledRunner
      !AppleAdapterId
      !FilePath
  | SmokeInstalledPythonRunnerSourceIsolated
      !AppleAdapterId
      !FilePath
      !InstalledPythonSourceIsolationSpec
  | -- | The architecture is part of the command because a @linux-native@
    -- target is an absolute image path that depends on it
    -- (@whisper-bin-ubuntu-x64@ versus @-arm64@). Carrying it here is what lets
    -- the renderer and the helper-side revalidation resolve the same closed
    -- catalog entry instead of agreeing by construction.
    SmokeLinuxNativeArtifact
      !Identity.NativeArtifactIdentity
      !Text.Text
      !FilePath
      !LinuxNativeSmokePolicy
  | QueryPythonVersion
      !ApplePythonAdapterId
      !FilePath
  | QueryPythonProvenance
      !ApplePythonAdapterId
      !FilePath
  deriving (Eq, Show)

-- | Operand-free command identity retained by the supervision kernel. It is
-- deliberately distinct from cluster operations and test-only fault hooks.
data ProvisioningOperation
  = PoetryProjectInstallOperation
  | PoetryProjectVenvCreateOperation
  | PythonProtoGenerationOperation
  | PoetryBootstrapInstallOperation
  | PythonVersionProbeOperation !ApplePythonAdapterId
  | PythonVenvCreateOperation !ApplePythonAdapterId
  | PipUpgradeOperation !ApplePythonAdapterId
  | RequirementsInstallOperation !ApplePythonAdapterId
  | AudiverisDownloadOperation
  | AudiverisMountOperation
  | AudiverisDetachOperation
  | AudiverisJavaCppExtractionOperation
  | InstalledRunnerSmokeOperation !AppleAdapterId
  | InstalledPythonSourceIsolationSmokeOperation !AppleAdapterId
  | LinuxNativeArtifactSmokeOperation !Identity.NativeArtifactIdentity !Text.Text
  | PythonVersionQueryOperation !ApplePythonAdapterId
  | PythonProvenanceQueryOperation !ApplePythonAdapterId
  deriving (Eq, Show)

provisioningCommandOperation :: ProvisioningCommand -> ProvisioningOperation
provisioningCommandOperation command =
  case command of
    InstallPoetryProject {} ->
      PoetryProjectInstallOperation
    CreatePoetryProjectVenv {} ->
      PoetryProjectVenvCreateOperation
    GeneratePythonProto {} ->
      PythonProtoGenerationOperation
    InstallPoetryBootstrap {} ->
      PoetryBootstrapInstallOperation
    ProbePythonVersion adapter _ ->
      PythonVersionProbeOperation adapter
    CreatePythonVenv adapter _ ->
      PythonVenvCreateOperation adapter
    UpgradePinnedPip adapter _ ->
      PipUpgradeOperation adapter
    InstallPinnedRequirements adapter _ ->
      RequirementsInstallOperation adapter
    DownloadAudiverisDmg {} ->
      AudiverisDownloadOperation
    MountAudiverisDmg {} ->
      AudiverisMountOperation
    DetachAudiverisDmg {} ->
      AudiverisDetachOperation
    ExtractAudiverisJavaCppNatives {} ->
      AudiverisJavaCppExtractionOperation
    SmokeInstalledRunner adapter _ ->
      InstalledRunnerSmokeOperation adapter
    SmokeInstalledPythonRunnerSourceIsolated adapter _ _ ->
      InstalledPythonSourceIsolationSmokeOperation adapter
    SmokeLinuxNativeArtifact identity architecture _ _ ->
      LinuxNativeArtifactSmokeOperation identity architecture
    QueryPythonVersion adapter _ ->
      PythonVersionQueryOperation adapter
    QueryPythonProvenance adapter _ ->
      PythonProvenanceQueryOperation adapter

-- | The arguments that follow a @linux-native@ target's own leading arguments.
--
-- These have to be real arguments of the image payload. The retired @bin\/*@
-- wrappers accepted a uniform @--smoke@ plus a payload-policy flag; the direct
-- targets do not, so each one gets the argument its own runner actually
-- understands, exactly as the Apple installed smoke already does. Only the
-- Python-runner targets reach @apple_native_runner.py@, so only they carry the
-- smoke and payload-policy flags.
linuxNativeArtifactSmokeArguments ::
  Identity.NativeArtifactIdentity ->
  LinuxNativeSmokePolicy ->
  [String]
linuxNativeArtifactSmokeArguments identity policy =
  case Text.unpack (Identity.nativeArtifactAdapterId identity) of
    "llama-cpp-cli" -> ["--version"]
    "whisper-cpp-cli" -> ["--version"]
    "jvm-native" -> ["-version"]
    _ ->
      [ "--smoke",
        case policy of
          RequireImagePayload -> "--require-native-payload"
          AllowFixturePayloadAbsence -> "--allow-missing-native-payload"
      ]
