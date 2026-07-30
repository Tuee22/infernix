{-# LANGUAGE OverloadedStrings #-}

-- | Descriptor-derived ELF loader-closure evidence for image-owned Linux
-- targets.
--
-- The closure-root digests an image target already carries cover only the
-- payload roots the catalog names. They therefore say nothing about the system
-- loader named by @PT_INTERP@, the resolution metadata in @\/etc\/ld.so.cache@,
-- or the recursively loaded system libraries an ELF, Python, or JVM target
-- binds through @DT_NEEDED@ — every one of which lives outside those roots. A
-- generation keyed on the payload roots alone cannot distinguish two images
-- whose @\/lib@ contents differ, so this module produces the missing evidence.
--
-- Every observation is taken through a retained descriptor: an object is
-- opened @O_NOFOLLOW@, its identity is checked before and after the read, and
-- the bytes that are parsed are exactly the bytes that were digested. A
-- pathname is never re-resolved between observation and use.
--
-- The resolver reproduces the loader's own search order for a @DT_NEEDED@ name
-- that contains no slash:
--
-- 1. the inherited @DT_RPATH@ stack, consulted only for an object that
--    declares no @DT_RUNPATH@ of its own;
-- 2. the requesting object's own @DT_RUNPATH@, which is not inherited;
-- 3. @\/etc\/ld.so.cache@;
-- 4. the architecture's default directories.
--
-- @LD_LIBRARY_PATH@ is deliberately absent. Reading it would be an ambient
-- environment read, which the configuration doctrine forbids, and a generation
-- whose identity depended on it would not be reproducible.
module Infernix.Engines.Artifact.Loader
  ( observeNativeArtifactLoaderEvidence,
    ElfImageInspection (..),
    ElfClass (..),
    ElfEndian (..),
    parseElfImageInspection,
    elfImageMagicPresent,
    LdSoCacheEntry (..),
    parseLdSoCache,
    expandElfSearchPath,
    ElfExpansionContext (..),
    elfDefaultSearchDirectories,
    elfPlatformToken,
    elfLibToken,
    maximumLoaderObjects,
    maximumLoaderEdges,
    maximumLoaderDepth,
    maximumLoaderObjectBytes,
    maximumLoaderMetadataBytes,
    maximumLoaderSearchDirectories,
    maximumLoaderCacheBytes,
    maximumLoaderCacheEntries,
    maximumLoaderScanEntries,
    maximumLoaderScanDepth,
  )
where

import Control.Exception (IOException, mask, try)
import Control.Monad (foldM, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (shiftL, (.&.), (.|.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TextEncoding
import Data.Word (Word16, Word32, Word64, Word8)
import Infernix.Engines.Artifact.Target
  ( NativeArtifactLoaderEvidence (..),
    NativeArtifactLoaderFileEvidence (..),
    NativeArtifactLoaderObjectEvidence (..),
    NativeArtifactLoaderResolutionEvidence (..),
  )
import Infernix.Error (finallyPreservingPrimary)
import System.Directory (canonicalizePath)
import System.FilePath
  ( isAbsolute,
    normalise,
    splitDirectories,
    takeDirectory,
    (</>),
  )
import System.IO.Error (isDoesNotExistError, isEOFError)
import System.Posix.Directory
  ( DirStream,
    closeDirStream,
    openDirStream,
    readDirStream,
  )
import System.Posix.Files
  ( FileStatus,
    deviceID,
    fileID,
    fileMode,
    fileSize,
    getFdStatus,
    getSymbolicLinkStatus,
    isDirectory,
    isRegularFile,
    isSymbolicLink,
    modificationTimeHiRes,
    statusChangeTimeHiRes,
  )
import System.Posix.IO
  ( OpenFileFlags (cloexec, nofollow),
    OpenMode (ReadOnly),
    closeFd,
    defaultFileFlags,
    openFd,
  )
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Types (Fd)

-- Bounds -------------------------------------------------------------------

-- | The most ELF objects one loader closure may bind. A Python or JRE closure
-- root carries a few thousand extension modules and shared objects, so the
-- bound is set above the largest configured root rather than at the smallest
-- observed one.
maximumLoaderObjects :: Int
maximumLoaderObjects = 8192

-- | The most @DT_NEEDED@ edges one loader closure may resolve.
maximumLoaderEdges :: Int
maximumLoaderEdges = 32768

-- | The deepest @DT_NEEDED@ chain one loader closure may follow.
maximumLoaderDepth :: Int
maximumLoaderDepth = 64

-- | The largest single ELF object this observer will read into memory.
maximumLoaderObjectBytes :: Integer
maximumLoaderObjectBytes = 2 * 1024 * 1024 * 1024

-- | The most dynamic-table string bytes one object may contribute.
maximumLoaderMetadataBytes :: Integer
maximumLoaderMetadataBytes = 4 * 1024 * 1024

-- | The most search directories one resolution may consult.
maximumLoaderSearchDirectories :: Int
maximumLoaderSearchDirectories = 256

-- | The largest @\/etc\/ld.so.cache@ this observer will read.
maximumLoaderCacheBytes :: Integer
maximumLoaderCacheBytes = 64 * 1024 * 1024

-- | The most entries a parsed @\/etc\/ld.so.cache@ may declare.
maximumLoaderCacheEntries :: Int
maximumLoaderCacheEntries = 65536

-- | The most directory entries the closure-root ELF scan may visit.
maximumLoaderScanEntries :: Int
maximumLoaderScanEntries = 500000

-- | The deepest directory nesting the closure-root ELF scan may visit.
maximumLoaderScanDepth :: Int
maximumLoaderScanDepth = 64

-- Pure ELF inspection ------------------------------------------------------

data ElfClass
  = Elf32
  | Elf64
  deriving (Eq, Show)

data ElfEndian
  = ElfLittleEndian
  | ElfBigEndian
  deriving (Eq, Show)

-- | Everything the loader consults in one ELF object, and nothing else. The
-- dynamic strings are returned exactly as the object declares them, before any
-- token expansion, so a fixture can pin the parse and the expansion separately.
data ElfImageInspection = ElfImageInspection
  { elfInspectionClass :: !ElfClass,
    elfInspectionEndian :: !ElfEndian,
    elfInspectionMachine :: !Int,
    elfInspectionInterpreter :: !(Maybe FilePath),
    elfInspectionSoname :: !(Maybe FilePath),
    elfInspectionNeeded :: ![FilePath],
    elfInspectionRPath :: ![FilePath],
    elfInspectionRunPath :: ![FilePath],
    elfInspectionMetadataBytes :: !Integer
  }
  deriving (Eq, Show)

elfMagic :: ByteString.ByteString
elfMagic = ByteString.pack [0x7f, 0x45, 0x4c, 0x46]

-- | Whether a file's leading bytes identify it as an ELF object. Unlike the
-- Mach-O universal magic this cannot collide with a Java class file, but the
-- class and data bytes are still required to be the two values the format
-- defines so an arbitrary file beginning with the magic is not admitted.
elfImageMagicPresent :: ByteString.ByteString -> Bool
elfImageMagicPresent leading =
  ByteString.take 4 leading == elfMagic
    && ByteString.length leading >= 6
    && ByteString.index leading 4 `elem` [1, 2]
    && ByteString.index leading 5 `elem` [1, 2]

parseElfImageInspection ::
  ByteString.ByteString ->
  Either String ElfImageInspection
parseElfImageInspection contents = do
  unlessEither
    (ByteString.take 4 contents == elfMagic)
    "ELF object does not carry the ELF magic"
  classByte <- readOctet contents 4
  dataByte <- readOctet contents 5
  elfClass <- elfClassFromByte classByte
  endian <- elfEndianFromByte dataByte
  let reader = elfReader elfClass endian
  machine <- fromIntegral <$> elfReaderHalf reader contents 18
  segments <- readElfProgramHeaders reader contents
  interpreter <- readElfInterpreter reader contents segments
  dynamic <- readElfDynamicEntries reader contents segments
  strings <- readElfDynamicStringTable reader contents segments dynamic
  attributes <- foldM (collectElfDynamicAttribute strings) emptyElfAttributes dynamic
  unlessEither
    (elfAttributeMetadataBytes attributes <= maximumLoaderMetadataBytes)
    "ELF dynamic metadata exceeds its fixed bound"
  pure
    ElfImageInspection
      { elfInspectionClass = elfClass,
        elfInspectionEndian = endian,
        elfInspectionMachine = machine,
        elfInspectionInterpreter = interpreter,
        elfInspectionSoname = elfAttributeSoname attributes,
        elfInspectionNeeded = reverse (elfAttributeNeeded attributes),
        elfInspectionRPath =
          concatMap splitElfSearchList (reverse (elfAttributeRPath attributes)),
        elfInspectionRunPath =
          concatMap splitElfSearchList (reverse (elfAttributeRunPath attributes)),
        elfInspectionMetadataBytes = elfAttributeMetadataBytes attributes
      }

elfClassFromByte :: Word8 -> Either String ElfClass
elfClassFromByte classByte =
  case classByte of
    1 -> Right Elf32
    2 -> Right Elf64
    _ -> Left "ELF object declares an unsupported class"

elfEndianFromByte :: Word8 -> Either String ElfEndian
elfEndianFromByte dataByte =
  case dataByte of
    1 -> Right ElfLittleEndian
    2 -> Right ElfBigEndian
    _ -> Left "ELF object declares an unsupported data encoding"

-- | The width- and endianness-specific accessors one parse needs. Bundling
-- them removes the width branch from every field read.
data ElfReader = ElfReader
  { elfReaderIs64 :: !Bool,
    elfReaderHalf :: !(ByteString.ByteString -> Int -> Either String Word16),
    elfReaderWord :: !(ByteString.ByteString -> Int -> Either String Word32),
    elfReaderAddress :: !(ByteString.ByteString -> Int -> Either String Word64)
  }

elfReader :: ElfClass -> ElfEndian -> ElfReader
elfReader elfClass endian =
  ElfReader
    { elfReaderIs64 = is64,
      elfReaderHalf = readHalf,
      elfReaderWord = readWord,
      elfReaderAddress = readAddress
    }
  where
    is64 = elfClass == Elf64
    little = endian == ElfLittleEndian
    readHalf bytes offset = fromIntegral <$> readInteger bytes offset 2 little
    readWord bytes offset = fromIntegral <$> readInteger bytes offset 4 little
    readAddress bytes offset =
      fromIntegral <$> readInteger bytes offset (if is64 then 8 else 4) little

-- | One @PT_LOAD@, @PT_DYNAMIC@, or @PT_INTERP@ program header.
data ElfSegment = ElfSegment
  { elfSegmentType :: !Word32,
    elfSegmentOffset :: !Word64,
    elfSegmentVirtualAddress :: !Word64,
    elfSegmentFileSize :: !Word64
  }
  deriving (Eq, Show)

elfProgramTypeLoad :: Word32
elfProgramTypeLoad = 1

elfProgramTypeDynamic :: Word32
elfProgramTypeDynamic = 2

elfProgramTypeInterpreter :: Word32
elfProgramTypeInterpreter = 3

-- | The most program headers one object may declare. The ELF specification
-- allows the count to escape into a section header, which no shared object or
-- executable this lane binds uses; such an object is rejected rather than
-- partially parsed.
maximumElfProgramHeaders :: Word16
maximumElfProgramHeaders = 1024

readElfProgramHeaders ::
  ElfReader ->
  ByteString.ByteString ->
  Either String [ElfSegment]
readElfProgramHeaders reader contents = do
  let is64 = elfReaderIs64 reader
      offsetField = if is64 then 32 else 28
      entrySizeField = if is64 then 54 else 42
      countField = if is64 then 56 else 44
  tableOffset <- elfReaderAddress reader contents offsetField
  entrySize <- elfReaderHalf reader contents entrySizeField
  entryCount <- elfReaderHalf reader contents countField
  unlessEither
    (entryCount <= maximumElfProgramHeaders)
    "ELF program header table exceeds its fixed bound"
  unlessEither
    (entrySize >= (if is64 then 56 else 32))
    "ELF program header entry size is invalid"
  let tableStart = fromIntegral tableOffset :: Integer
      tableBytes = fromIntegral entrySize * fromIntegral entryCount :: Integer
  unlessEither
    ( tableStart >= 0
        && tableStart + tableBytes
          <= fromIntegral (ByteString.length contents)
    )
    "ELF program header table is out of bounds"
  mapM
    (readElfProgramHeader reader contents (fromIntegral tableOffset) entrySize)
    [0 .. fromIntegral entryCount - 1]

readElfProgramHeader ::
  ElfReader ->
  ByteString.ByteString ->
  Int ->
  Word16 ->
  Int ->
  Either String ElfSegment
readElfProgramHeader reader contents tableOffset entrySize index = do
  let is64 = elfReaderIs64 reader
      base = tableOffset + index * fromIntegral entrySize
  segmentType <- elfReaderWord reader contents base
  fileOffset <-
    elfReaderAddress reader contents (base + (if is64 then 8 else 4))
  virtualAddress <-
    elfReaderAddress reader contents (base + (if is64 then 16 else 8))
  segmentFileSize <-
    elfReaderAddress reader contents (base + (if is64 then 32 else 16))
  pure
    ElfSegment
      { elfSegmentType = segmentType,
        elfSegmentOffset = fileOffset,
        elfSegmentVirtualAddress = virtualAddress,
        elfSegmentFileSize = segmentFileSize
      }

readElfInterpreter ::
  ElfReader ->
  ByteString.ByteString ->
  [ElfSegment] ->
  Either String (Maybe FilePath)
readElfInterpreter _reader contents segments =
  case filter ((== elfProgramTypeInterpreter) . elfSegmentType) segments of
    [] -> Right Nothing
    [segment] -> do
      slice <-
        boundedSlice
          contents
          (elfSegmentOffset segment)
          (elfSegmentFileSize segment)
      interpreter <- decodeElfString (ByteString.takeWhile (/= 0) slice)
      unlessEither
        (isAbsolute interpreter)
        "ELF PT_INTERP does not name an absolute loader"
      pure (Just interpreter)
    _ -> Left "ELF object declares more than one PT_INTERP segment"

-- | The most dynamic entries one object may declare.
maximumElfDynamicEntries :: Int
maximumElfDynamicEntries = 4096

readElfDynamicEntries ::
  ElfReader ->
  ByteString.ByteString ->
  [ElfSegment] ->
  Either String [(Word64, Word64)]
readElfDynamicEntries reader contents segments =
  case filter ((== elfProgramTypeDynamic) . elfSegmentType) segments of
    [] -> Right []
    [segment] -> do
      slice <-
        boundedSlice
          contents
          (elfSegmentOffset segment)
          (elfSegmentFileSize segment)
      let entryBytes = if elfReaderIs64 reader then 16 else 8
          available = ByteString.length slice `div` entryBytes
      unlessEither
        (available <= maximumElfDynamicEntries)
        "ELF dynamic table exceeds its fixed bound"
      readElfDynamicEntry reader slice entryBytes available 0 []
    _ -> Left "ELF object declares more than one PT_DYNAMIC segment"

readElfDynamicEntry ::
  ElfReader ->
  ByteString.ByteString ->
  Int ->
  Int ->
  Int ->
  [(Word64, Word64)] ->
  Either String [(Word64, Word64)]
readElfDynamicEntry reader slice entryBytes available index collected
  | index >= available = Right (reverse collected)
  | otherwise = do
      let base = index * entryBytes
      tag <- elfReaderAddress reader slice base
      value <- elfReaderAddress reader slice (base + entryBytes `div` 2)
      if tag == 0
        then Right (reverse collected)
        else
          readElfDynamicEntry
            reader
            slice
            entryBytes
            available
            (index + 1)
            ((tag, value) : collected)

elfDynamicNeeded :: Word64
elfDynamicNeeded = 1

elfDynamicStringTable :: Word64
elfDynamicStringTable = 5

elfDynamicStringTableSize :: Word64
elfDynamicStringTableSize = 10

elfDynamicSoname :: Word64
elfDynamicSoname = 14

elfDynamicRPath :: Word64
elfDynamicRPath = 15

elfDynamicRunPath :: Word64
elfDynamicRunPath = 29

-- | The dynamic string table located in the file. @DT_STRTAB@ is a virtual
-- address, so it is mapped back through the @PT_LOAD@ segments rather than
-- used as a file offset.
readElfDynamicStringTable ::
  ElfReader ->
  ByteString.ByteString ->
  [ElfSegment] ->
  [(Word64, Word64)] ->
  Either String ByteString.ByteString
readElfDynamicStringTable _reader contents segments dynamic =
  case (lookup elfDynamicStringTable dynamic, lookup elfDynamicStringTableSize dynamic) of
    (Nothing, _) -> Right ByteString.empty
    (Just _, Nothing) ->
      Left "ELF dynamic table declares DT_STRTAB without DT_STRSZ"
    (Just address, Just declaredSize) -> do
      unlessEither
        (fromIntegral declaredSize <= maximumLoaderMetadataBytes)
        "ELF dynamic string table exceeds its fixed bound"
      fileOffset <- elfVirtualAddressToOffset segments address
      boundedSlice contents fileOffset declaredSize

elfVirtualAddressToOffset ::
  [ElfSegment] ->
  Word64 ->
  Either String Word64
elfVirtualAddressToOffset segments address =
  case filter covers loadSegments of
    (segment : _) ->
      Right
        ( elfSegmentOffset segment
            + (address - elfSegmentVirtualAddress segment)
        )
    [] -> Left "ELF dynamic string table address is not mapped by any PT_LOAD"
  where
    loadSegments = filter ((== elfProgramTypeLoad) . elfSegmentType) segments
    covers segment =
      address >= elfSegmentVirtualAddress segment
        && address - elfSegmentVirtualAddress segment
          < elfSegmentFileSize segment

data ElfAttributes = ElfAttributes
  { elfAttributeSoname :: !(Maybe FilePath),
    elfAttributeNeeded :: ![FilePath],
    elfAttributeRPath :: ![FilePath],
    elfAttributeRunPath :: ![FilePath],
    elfAttributeMetadataBytes :: !Integer
  }

emptyElfAttributes :: ElfAttributes
emptyElfAttributes =
  ElfAttributes
    { elfAttributeSoname = Nothing,
      elfAttributeNeeded = [],
      elfAttributeRPath = [],
      elfAttributeRunPath = [],
      elfAttributeMetadataBytes = 0
    }

collectElfDynamicAttribute ::
  ByteString.ByteString ->
  ElfAttributes ->
  (Word64, Word64) ->
  Either String ElfAttributes
collectElfDynamicAttribute strings attributes (tag, value)
  | tag == elfDynamicNeeded = withString applyNeeded
  | tag == elfDynamicSoname = withString applySoname
  | tag == elfDynamicRPath = withString applyRPath
  | tag == elfDynamicRunPath = withString applyRunPath
  | otherwise = Right attributes
  where
    withString apply = do
      entry <- readElfStringTableEntry strings value
      pure
        (apply entry)
          { elfAttributeMetadataBytes =
              elfAttributeMetadataBytes attributes
                + fromIntegral (length entry)
          }
    applyNeeded entry =
      attributes {elfAttributeNeeded = entry : elfAttributeNeeded attributes}
    applySoname entry =
      attributes {elfAttributeSoname = Just entry}
    applyRPath entry =
      attributes {elfAttributeRPath = entry : elfAttributeRPath attributes}
    applyRunPath entry =
      attributes {elfAttributeRunPath = entry : elfAttributeRunPath attributes}

readElfStringTableEntry ::
  ByteString.ByteString ->
  Word64 ->
  Either String FilePath
readElfStringTableEntry strings offset = do
  unlessEither
    (offset < fromIntegral (ByteString.length strings))
    "ELF dynamic string offset is out of bounds"
  decodeElfString
    ( ByteString.takeWhile
        (/= 0)
        (ByteString.drop (fromIntegral offset) strings)
    )

decodeElfString :: ByteString.ByteString -> Either String FilePath
decodeElfString encoded = do
  unlessEither
    (not (ByteString.null encoded))
    "ELF dynamic string is empty"
  let decoded = ByteString8.unpack encoded
  unlessEither
    ('\0' `notElem` decoded)
    "ELF dynamic string contains NUL"
  Right decoded

-- | @DT_RPATH@ and @DT_RUNPATH@ hold a colon-separated list, which the loader
-- splits before expanding tokens. An empty element means the current working
-- directory to the loader; a closed generation has no such directory, so an
-- empty element is dropped rather than silently resolved against one.
splitElfSearchList :: FilePath -> [FilePath]
splitElfSearchList value =
  filter (not . null) (splitOnColon value)

splitOnColon :: String -> [String]
splitOnColon value =
  case break (== ':') value of
    (element, []) -> [element]
    (element, _ : rest) -> element : splitOnColon rest

-- Token expansion ----------------------------------------------------------

-- | What a dynamic token expands to for one object. @$ORIGIN@ is the directory
-- holding the object, so it is derived from the observed path rather than from
-- anything the object declares.
data ElfExpansionContext = ElfExpansionContext
  { elfExpansionOrigin :: !FilePath,
    elfExpansionLib :: !FilePath,
    elfExpansionPlatform :: !FilePath
  }
  deriving (Eq, Show)

-- | @$LIB@ for an object of the given class.
elfLibToken :: ElfClass -> FilePath
elfLibToken elfClass =
  case elfClass of
    Elf64 -> "lib64"
    Elf32 -> "lib"

-- | @$PLATFORM@ for the machine the object declares. Only the two machines
-- this lane supports are named; anything else fails closed rather than
-- expanding to a guess.
elfPlatformToken :: Int -> Either String FilePath
elfPlatformToken machine =
  case machine of
    62 -> Right "x86_64"
    183 -> Right "aarch64"
    _ -> Left "ELF object declares an unsupported machine"

-- | Expand the dynamic tokens in one search element and reject anything that
-- is not a normalized absolute path afterwards. A relative element would
-- resolve against the loader's working directory, which a sealed generation
-- does not fix, so it is refused rather than laundered.
expandElfSearchPath ::
  ElfExpansionContext ->
  FilePath ->
  Either String FilePath
expandElfSearchPath context element = do
  expanded <- expandElfTokens context element
  unlessEither
    (isAbsolute expanded)
    ("ELF search element is not absolute after expansion: " <> element)
  collapseElfPath element (normalise expanded)

-- | Collapse @.@ and @..@ lexically.
--
-- This agrees with kernel resolution because the only anchor that can
-- introduce an ascent is @$ORIGIN@, which is the directory of an object whose
-- canonical path was already observed — so no component of the prefix is a
-- symlink. An ascent past the filesystem root is refused rather than clamped.
collapseElfPath :: FilePath -> FilePath -> Either String FilePath
collapseElfPath element normalized =
  case foldl collapseComponent (Right []) (splitDirectories normalized) of
    Left failure -> Left failure
    Right collapsed -> Right ("/" <> List.intercalate "/" (reverse collapsed))
  where
    collapseComponent accumulated component =
      case (accumulated, component) of
        (Left failure, _) -> Left failure
        (Right stack, "/") -> Right stack
        (Right stack, ".") -> Right stack
        (Right [], "..") ->
          Left ("ELF search element ascends past the filesystem root: " <> element)
        (Right (_ : rest), "..") -> Right rest
        (Right stack, name) -> Right (name : stack)

expandElfTokens ::
  ElfExpansionContext ->
  String ->
  Either String String
expandElfTokens context = expandFrom
  where
    expandFrom [] = Right []
    expandFrom ('$' : rest) = expandToken rest
    expandFrom (character : rest) = (character :) <$> expandFrom rest
    expandToken rest =
      case matchElfToken rest of
        Just (token, remainder) -> do
          value <- tokenValue token
          (value <>) <$> expandFrom remainder
        Nothing -> Left "ELF search element names an unsupported dynamic token"
    tokenValue token =
      case token of
        "ORIGIN" -> Right (elfExpansionOrigin context)
        "LIB" -> Right (elfExpansionLib context)
        "PLATFORM" -> Right (elfExpansionPlatform context)
        _ -> Left "ELF search element names an unsupported dynamic token"

matchElfToken :: String -> Maybe (String, String)
matchElfToken ('{' : rest) =
  case break (== '}') rest of
    (token, '}' : remainder) -> Just (token, remainder)
    _ -> Nothing
matchElfToken rest =
  case List.find (`List.isPrefixOf` rest) elfBareTokens of
    Just token -> Just (token, drop (length token) rest)
    Nothing -> Nothing

elfBareTokens :: [String]
elfBareTokens = ["ORIGIN", "PLATFORM", "LIB"]

-- | The loader's default directories for one class. These are the fixed
-- fallbacks glibc consults after the cache; the multiarch directories are
-- included because the Debian-family base images this lane uses install every
-- system library under them.
elfDefaultSearchDirectories :: ElfClass -> FilePath -> [FilePath]
elfDefaultSearchDirectories elfClass platform =
  case elfClass of
    Elf64 ->
      [ "/lib/" <> platform <> "-linux-gnu",
        "/usr/lib/" <> platform <> "-linux-gnu",
        "/lib64",
        "/usr/lib64",
        "/lib",
        "/usr/lib"
      ]
    Elf32 ->
      [ "/lib",
        "/usr/lib"
      ]

-- ld.so.cache --------------------------------------------------------------

-- | One resolved entry of @\/etc\/ld.so.cache@, in the file's own order. The
-- index into this list is what a resolution records, so the evidence names the
-- exact entry the loader would have selected.
data LdSoCacheEntry = LdSoCacheEntry
  { ldSoCacheEntryKey :: !FilePath,
    ldSoCacheEntryValue :: !FilePath
  }
  deriving (Eq, Show)

oldCacheMagic :: ByteString.ByteString
oldCacheMagic = ByteString8.pack "ld.so-1.7.0\0"

newCacheMagic :: ByteString.ByteString
newCacheMagic = ByteString8.pack "glibc-ld.so.cache1.1"

-- | Parse @\/etc\/ld.so.cache@ in either the old or the new layout, including
-- the usual arrangement in which a new-format cache is appended after an
-- old-format one. String offsets in the new format are relative to the start of
-- the new-format header, which is why the embedded case cannot simply reuse the
-- file start.
parseLdSoCache ::
  ByteString.ByteString ->
  Either String [LdSoCacheEntry]
parseLdSoCache contents
  | newCacheMagic `ByteString.isPrefixOf` contents =
      parseNewLdSoCache contents 0
  | oldCacheMagic `ByteString.isPrefixOf` contents = do
      entryCount <- readInteger contents 12 4 True
      unlessEither
        (entryCount <= fromIntegral maximumLoaderCacheEntries)
        "ld.so.cache declares more entries than its fixed bound"
      let oldEntriesEnd = 16 + fromIntegral entryCount * 12
          aligned = alignToEight oldEntriesEnd
      if aligned + ByteString.length newCacheMagic <= ByteString.length contents
        && newCacheMagic
          `ByteString.isPrefixOf` ByteString.drop aligned contents
        then parseNewLdSoCache contents aligned
        else parseOldLdSoCache contents (fromIntegral entryCount) oldEntriesEnd
  | otherwise = Left "ld.so.cache does not carry a supported magic"

alignToEight :: Int -> Int
alignToEight value = (value + 7) .&. complementSeven
  where
    complementSeven = -8

parseOldLdSoCache ::
  ByteString.ByteString ->
  Int ->
  Int ->
  Either String [LdSoCacheEntry]
parseOldLdSoCache contents entryCount stringBase =
  mapM readOldEntry [0 .. entryCount - 1]
  where
    readOldEntry index = do
      let base = 16 + index * 12
      key <- readInteger contents (base + 4) 4 True
      value <- readInteger contents (base + 8) 4 True
      keyPath <- readCacheString contents (stringBase + fromIntegral key)
      valuePath <- readCacheString contents (stringBase + fromIntegral value)
      pure (LdSoCacheEntry keyPath valuePath)

parseNewLdSoCache ::
  ByteString.ByteString ->
  Int ->
  Either String [LdSoCacheEntry]
parseNewLdSoCache contents headerBase = do
  entryCount <- readInteger contents (headerBase + 20) 4 True
  unlessEither
    (entryCount <= fromIntegral maximumLoaderCacheEntries)
    "ld.so.cache declares more entries than its fixed bound"
  mapM readNewEntry [0 .. fromIntegral entryCount - 1]
  where
    readNewEntry index = do
      let base = headerBase + 48 + index * 24
      key <- readInteger contents (base + 4) 4 True
      value <- readInteger contents (base + 8) 4 True
      keyPath <- readCacheString contents (headerBase + fromIntegral key)
      valuePath <- readCacheString contents (headerBase + fromIntegral value)
      pure (LdSoCacheEntry keyPath valuePath)

readCacheString ::
  ByteString.ByteString ->
  Int ->
  Either String FilePath
readCacheString contents offset = do
  unlessEither
    (offset >= 0 && offset < ByteString.length contents)
    "ld.so.cache string offset is out of bounds"
  decodeElfString
    ( ByteString.takeWhile
        (/= 0)
        (ByteString.drop offset contents)
    )

-- Observation --------------------------------------------------------------

-- | One object already observed, keyed by its canonical path.
data ObservedObject = ObservedObject
  { observedObjectEvidence :: !NativeArtifactLoaderObjectEvidence,
    observedObjectInspection :: !ElfImageInspection
  }

data LoaderWalkState = LoaderWalkState
  { walkObjects :: !(Map FilePath ObservedObject),
    walkObjectOrder :: ![FilePath],
    walkResolutions :: ![NativeArtifactLoaderResolutionEvidence],
    walkEdges :: !Int,
    walkMaximumDepth :: !Int
  }

-- | One queued object, with the @DT_RPATH@ stack inherited from the objects
-- that loaded it. @DT_RUNPATH@ is not inherited, so it never appears here.
data LoaderQueueEntry = LoaderQueueEntry
  { queueEntryPath :: !FilePath,
    queueEntryInheritedRPath :: ![FilePath],
    queueEntryDepth :: !Int
  }

-- | Produce the complete loader closure for one image target.
--
-- The walk is seeded from the entry object, from every ELF object found by
-- scanning the closed image roots, and — once the entry object is inspected —
-- from its @PT_INTERP@ loader. Each @DT_NEEDED@ name is then resolved and the
-- resolved object queued, so the system libraries an image target binds outside
-- its payload roots are bound by exact identity rather than assumed.
observeNativeArtifactLoaderEvidence ::
  FilePath ->
  [FilePath] ->
  IO NativeArtifactLoaderEvidence
observeNativeArtifactLoaderEvidence entryObject closureRoots = do
  canonicalEntry <- canonicalizePath entryObject
  cacheEvidence <- observeLdSoCacheEvidence
  cacheEntries <- loadLdSoCacheEntries
  scanned <- concat <$> mapM scanClosureRootForElfObjects closureRoots
  let seeds =
        LoaderQueueEntry canonicalEntry [] 0
          : [LoaderQueueEntry path [] 0 | path <- scanned, path /= canonicalEntry]
  finalState <-
    walkLoaderClosure cacheEntries emptyWalkState seeds
  pure
    NativeArtifactLoaderEvidence
      { loaderEvidenceEntryObject = canonicalEntry,
        loaderEvidenceCache = cacheEvidence,
        loaderEvidenceObjects = walkObservedObjectEvidence finalState,
        loaderEvidenceResolutions = walkResolutions finalState,
        loaderEvidenceMaximumDepth = walkMaximumDepth finalState
      }

-- | The observed objects in first-observation order. The fingerprint sorts
-- them independently, so this order is a diagnostic convenience rather than
-- part of the identity.
walkObservedObjectEvidence ::
  LoaderWalkState ->
  [NativeArtifactLoaderObjectEvidence]
walkObservedObjectEvidence state =
  [ observedObjectEvidence observed
  | path <- reverse (walkObjectOrder state),
    Just observed <- [Map.lookup path (walkObjects state)]
  ]

emptyWalkState :: LoaderWalkState
emptyWalkState =
  LoaderWalkState
    { walkObjects = Map.empty,
      walkObjectOrder = [],
      walkResolutions = [],
      walkEdges = 0,
      walkMaximumDepth = 0
    }

ldSoCachePath :: FilePath
ldSoCachePath = "/etc/ld.so.cache"

-- | The cache's own exact identity, when the host has one. A host without a
-- cache resolves entirely through the default directories, which is a
-- legitimate configuration, so absence is recorded as absence rather than
-- failing the observation.
observeLdSoCacheEvidence :: IO (Maybe NativeArtifactLoaderFileEvidence)
observeLdSoCacheEvidence = do
  present <- pathStatus ldSoCachePath
  case present of
    Nothing -> pure Nothing
    Just _ -> Just <$> observeLoaderFileEvidence ldSoCachePath

loadLdSoCacheEntries :: IO [LdSoCacheEntry]
loadLdSoCacheEntries = do
  present <- pathStatus ldSoCachePath
  case present of
    Nothing -> pure []
    Just _ -> do
      contents <- readExactLoaderFileBytes ldSoCachePath maximumLoaderCacheBytes
      either (ioError . userError) pure (parseLdSoCache contents)

walkLoaderClosure ::
  [LdSoCacheEntry] ->
  LoaderWalkState ->
  [LoaderQueueEntry] ->
  IO LoaderWalkState
walkLoaderClosure _cacheEntries state [] = pure state
walkLoaderClosure cacheEntries state (entry : pending) = do
  when
    (queueEntryDepth entry > maximumLoaderDepth)
    (ioError (userError "ELF loader closure exceeds its fixed depth bound"))
  if Map.member (queueEntryPath entry) (walkObjects state)
    then walkLoaderClosure cacheEntries state pending
    else do
      observed <- observeLoaderObject (queueEntryPath entry)
      let widened =
            state
              { walkObjects =
                  Map.insert (queueEntryPath entry) observed (walkObjects state),
                walkObjectOrder =
                  queueEntryPath entry : walkObjectOrder state,
                walkMaximumDepth =
                  max (walkMaximumDepth state) (queueEntryDepth entry)
              }
      unless
        (Map.size (walkObjects widened) <= maximumLoaderObjects)
        (ioError (userError "ELF loader closure exceeds its fixed object bound"))
      (resolvedState, queued) <-
        resolveLoaderDependencies cacheEntries widened entry observed
      walkLoaderClosure cacheEntries resolvedState (pending <> queued)

resolveLoaderDependencies ::
  [LdSoCacheEntry] ->
  LoaderWalkState ->
  LoaderQueueEntry ->
  ObservedObject ->
  IO (LoaderWalkState, [LoaderQueueEntry])
resolveLoaderDependencies cacheEntries state entry observed = do
  let inspection = observedObjectInspection observed
      objectPath = queueEntryPath entry
      interpreterDependency =
        maybe [] pure (elfInspectionInterpreter inspection)
      dependencies = interpreterDependency <> elfInspectionNeeded inspection
  context <- loaderExpansionContext objectPath inspection
  ownRPath <-
    requireLoaderResolution
      (mapM (expandElfSearchPath context) (elfInspectionRPath inspection))
  ownRunPath <-
    requireLoaderResolution
      (mapM (expandElfSearchPath context) (elfInspectionRunPath inspection))
  platform <-
    requireLoaderResolution (elfPlatformToken (elfInspectionMachine inspection))
  let inheritedRPath = queueEntryInheritedRPath entry
      effectiveRPath =
        if null ownRunPath then inheritedRPath <> ownRPath else []
      declaredDirectories = List.nub (effectiveRPath <> ownRunPath)
      defaultDirectories =
        elfDefaultSearchDirectories (elfInspectionClass inspection) platform
      searchOrder = LoaderSearchOrder declaredDirectories defaultDirectories
      childInherited =
        if null ownRunPath then effectiveRPath else inheritedRPath
  unless
    ( length declaredDirectories + length defaultDirectories
        <= maximumLoaderSearchDirectories
    )
    (ioError (userError "ELF loader search stack exceeds its fixed bound"))
  foldM
    (resolveOneDependency cacheEntries objectPath searchOrder childInherited entry)
    (state, [])
    dependencies

-- | The two halves of the loader's search, kept apart because the cache sits
-- between them.
--
-- glibc searches the object's declared @DT_RPATH@\/@DT_RUNPATH@ directories
-- first, then @\/etc\/ld.so.cache@, and only then the architecture defaults.
-- Collapsing the two halves into one list and consulting the cache last would
-- resolve a library from @\/usr\/lib@ that the real loader would have taken
-- from the cache, which is a different object whenever the two disagree.
data LoaderSearchOrder = LoaderSearchOrder
  { loaderSearchDeclared :: ![FilePath],
    loaderSearchDefaults :: ![FilePath]
  }

-- | The complete ordered stack, for the record. The resolution itself uses the
-- two halves separately.
loaderSearchRecord :: LoaderSearchOrder -> [FilePath]
loaderSearchRecord searchOrder =
  loaderSearchDeclared searchOrder <> loaderSearchDefaults searchOrder

resolveOneDependency ::
  [LdSoCacheEntry] ->
  FilePath ->
  LoaderSearchOrder ->
  [FilePath] ->
  LoaderQueueEntry ->
  (LoaderWalkState, [LoaderQueueEntry]) ->
  FilePath ->
  IO (LoaderWalkState, [LoaderQueueEntry])
resolveOneDependency
  cacheEntries
  objectPath
  searchOrder
  childInherited
  entry
  (state, queued)
  needed = do
    resolution <-
      resolveLoaderNeeded cacheEntries searchOrder needed
    canonical <- canonicalizePath (resolvedNeededPath resolution)
    let record =
          NativeArtifactLoaderResolutionEvidence
            { loaderResolutionRequester = objectPath,
              loaderResolutionNeeded = needed,
              loaderResolutionSearchDirectories =
                loaderSearchRecord searchOrder,
              loaderResolutionUsedCache = resolvedNeededUsedCache resolution,
              loaderResolutionCacheEntryIndex =
                resolvedNeededCacheIndex resolution,
              loaderResolutionConfiguredPath = resolvedNeededPath resolution,
              loaderResolutionCanonicalPath = canonical
            }
        widened =
          state
            { walkResolutions = walkResolutions state <> [record],
              walkEdges = walkEdges state + 1
            }
    unless
      (walkEdges widened <= maximumLoaderEdges)
      (ioError (userError "ELF loader closure exceeds its fixed edge bound"))
    pure
      ( widened,
        queued
          <> [ LoaderQueueEntry
                 canonical
                 childInherited
                 (queueEntryDepth entry + 1)
             ]
      )

data ResolvedNeeded = ResolvedNeeded
  { resolvedNeededPath :: !FilePath,
    resolvedNeededUsedCache :: !Bool,
    resolvedNeededCacheIndex :: !(Maybe Int)
  }

-- | Resolve one @DT_NEEDED@ name in the loader's own order. A name carrying a
-- slash is a path and bypasses the search entirely, exactly as the loader
-- treats it; such a name must still be absolute, because a sealed generation
-- fixes no working directory to resolve a relative one against.
resolveLoaderNeeded ::
  [LdSoCacheEntry] ->
  LoaderSearchOrder ->
  FilePath ->
  IO ResolvedNeeded
resolveLoaderNeeded cacheEntries searchOrder needed
  | '/' `elem` needed = resolveLoaderNeededAsPath needed
  | otherwise = do
      declared <-
        firstExistingLoaderCandidate (loaderSearchDeclared searchOrder) needed
      case declared of
        Just path -> pure (ResolvedNeeded path False Nothing)
        Nothing -> resolveLoaderNeededAfterDeclared cacheEntries searchOrder needed

-- | The cache is consulted before the architecture defaults, which is the
-- order the loader uses. Searching the defaults first would resolve a library
-- from @\/usr\/lib@ that the loader would have taken from the cache.
resolveLoaderNeededAfterDeclared ::
  [LdSoCacheEntry] ->
  LoaderSearchOrder ->
  FilePath ->
  IO ResolvedNeeded
resolveLoaderNeededAfterDeclared cacheEntries searchOrder needed =
  case List.find (matchesNeeded . snd) (zip [0 ..] cacheEntries) of
    Just (index, cacheEntry) -> do
      present <- pathStatus (ldSoCacheEntryValue cacheEntry)
      case present of
        Just _ ->
          pure
            (ResolvedNeeded (ldSoCacheEntryValue cacheEntry) True (Just index))
        Nothing -> resolveLoaderNeededFromDefaults searchOrder needed
    Nothing -> resolveLoaderNeededFromDefaults searchOrder needed
  where
    matchesNeeded cacheEntry = ldSoCacheEntryKey cacheEntry == needed

resolveLoaderNeededFromDefaults ::
  LoaderSearchOrder ->
  FilePath ->
  IO ResolvedNeeded
resolveLoaderNeededFromDefaults searchOrder needed = do
  fallback <-
    firstExistingLoaderCandidate (loaderSearchDefaults searchOrder) needed
  case fallback of
    Just path -> pure (ResolvedNeeded path False Nothing)
    Nothing ->
      ioError
        (userError ("ELF DT_NEEDED is unresolvable: " <> needed))

resolveLoaderNeededAsPath :: FilePath -> IO ResolvedNeeded
resolveLoaderNeededAsPath needed = do
  unless
    (isAbsolute needed)
    ( ioError
        ( userError
            ("ELF DT_NEEDED names a relative path: " <> needed)
        )
    )
  present <- pathStatus needed
  case present of
    Nothing ->
      ioError
        (userError ("ELF DT_NEEDED path does not exist: " <> needed))
    Just _ -> pure (ResolvedNeeded needed False Nothing)

firstExistingLoaderCandidate ::
  [FilePath] ->
  FilePath ->
  IO (Maybe FilePath)
firstExistingLoaderCandidate [] _needed = pure Nothing
firstExistingLoaderCandidate (directory : rest) needed = do
  let candidate = directory </> needed
  present <- pathStatus candidate
  case present of
    Just status
      | not (isDirectory status) -> pure (Just candidate)
    _ -> firstExistingLoaderCandidate rest needed

loaderExpansionContext ::
  FilePath ->
  ElfImageInspection ->
  IO ElfExpansionContext
loaderExpansionContext objectPath inspection = do
  platform <-
    requireLoaderResolution (elfPlatformToken (elfInspectionMachine inspection))
  pure
    ElfExpansionContext
      { elfExpansionOrigin = takeDirectory objectPath,
        elfExpansionLib = elfLibToken (elfInspectionClass inspection),
        elfExpansionPlatform = platform
      }

requireLoaderResolution :: Either String value -> IO value
requireLoaderResolution = either (ioError . userError) pure

-- | Observe one ELF object through a retained descriptor and parse exactly the
-- bytes that were digested.
observeLoaderObject :: FilePath -> IO ObservedObject
observeLoaderObject configuredPath = do
  evidenceBase <- observeLoaderFileEvidence configuredPath
  contents <-
    readExactLoaderFileBytes
      (loaderFileCanonicalPath evidenceBase)
      maximumLoaderObjectBytes
  inspection <-
    requireLoaderResolution (parseElfImageInspection contents)
  pure
    ObservedObject
      { observedObjectEvidence =
          loaderObjectEvidenceFrom evidenceBase inspection,
        observedObjectInspection = inspection
      }

loaderObjectEvidenceFrom ::
  NativeArtifactLoaderFileEvidence ->
  ElfImageInspection ->
  NativeArtifactLoaderObjectEvidence
loaderObjectEvidenceFrom fileEvidence inspection =
  NativeArtifactLoaderObjectEvidence
    { loaderObjectConfiguredPath = loaderFileConfiguredPath fileEvidence,
      loaderObjectConfiguredDeviceId =
        loaderFileConfiguredDeviceId fileEvidence,
      loaderObjectConfiguredFileId = loaderFileConfiguredFileId fileEvidence,
      loaderObjectConfiguredMode = loaderFileConfiguredMode fileEvidence,
      loaderObjectConfiguredSize = loaderFileConfiguredSize fileEvidence,
      loaderObjectCanonicalPath = loaderFileCanonicalPath fileEvidence,
      loaderObjectCanonicalDeviceId = loaderFileCanonicalDeviceId fileEvidence,
      loaderObjectCanonicalFileId = loaderFileCanonicalFileId fileEvidence,
      loaderObjectCanonicalMode = loaderFileCanonicalMode fileEvidence,
      loaderObjectCanonicalSize = loaderFileCanonicalSize fileEvidence,
      loaderObjectDigest = loaderFileDigest fileEvidence,
      loaderObjectClassBits =
        case elfInspectionClass inspection of
          Elf64 -> 64
          Elf32 -> 32,
      loaderObjectEndian =
        case elfInspectionEndian inspection of
          ElfLittleEndian -> "little"
          ElfBigEndian -> "big",
      loaderObjectMachine = elfInspectionMachine inspection,
      loaderObjectInterpreter = elfInspectionInterpreter inspection,
      loaderObjectSoname = elfInspectionSoname inspection,
      loaderObjectNeeded = elfInspectionNeeded inspection,
      loaderObjectRPath = elfInspectionRPath inspection,
      loaderObjectRunPath = elfInspectionRunPath inspection
    }

-- | Exact configured and canonical identity plus content digest for one file.
observeLoaderFileEvidence ::
  FilePath ->
  IO NativeArtifactLoaderFileEvidence
observeLoaderFileEvidence configuredPath = do
  unless (isAbsolute configuredPath && '\0' `notElem` configuredPath) $
    ioError (userError ("loader file path is invalid: " <> configuredPath))
  configuredStatus <- getSymbolicLinkStatus configuredPath
  canonicalPath <- canonicalizePath configuredPath
  canonicalStatus <- getSymbolicLinkStatus canonicalPath
  unless
    ( isRegularFile canonicalStatus
        && not (isSymbolicLink canonicalStatus)
        && toInteger (fileSize canonicalStatus) <= maximumLoaderObjectBytes
    )
    ( ioError
        ( userError
            ("loader file is not a bounded regular file: " <> canonicalPath)
        )
    )
  digest <- digestLoaderFile canonicalPath canonicalStatus
  finalConfiguredStatus <- getSymbolicLinkStatus configuredPath
  finalCanonicalPath <- canonicalizePath configuredPath
  finalCanonicalStatus <- getSymbolicLinkStatus canonicalPath
  unless
    ( stableLoaderStatus configuredStatus finalConfiguredStatus
        && normalise canonicalPath == normalise finalCanonicalPath
        && stableLoaderStatus canonicalStatus finalCanonicalStatus
    )
    ( ioError
        ( userError
            ("loader file changed during observation: " <> configuredPath)
        )
    )
  pure
    NativeArtifactLoaderFileEvidence
      { loaderFileConfiguredPath = configuredPath,
        loaderFileConfiguredDeviceId = fromIntegral (deviceID configuredStatus),
        loaderFileConfiguredFileId = fromIntegral (fileID configuredStatus),
        loaderFileConfiguredMode = fromIntegral (fileMode configuredStatus),
        loaderFileConfiguredSize = fromIntegral (fileSize configuredStatus),
        loaderFileCanonicalPath = canonicalPath,
        loaderFileCanonicalDeviceId = fromIntegral (deviceID canonicalStatus),
        loaderFileCanonicalFileId = fromIntegral (fileID canonicalStatus),
        loaderFileCanonicalMode = fromIntegral (fileMode canonicalStatus),
        loaderFileCanonicalSize = fromIntegral (fileSize canonicalStatus),
        loaderFileDigest = digest
      }

digestLoaderFile :: FilePath -> FileStatus -> IO Text
digestLoaderFile path expectedStatus =
  withStableLoaderDescriptor path expectedStatus $ \descriptor openedStatus -> do
    let declared = toInteger (fileSize openedStatus)
    digestContext <- digestLoaderDescriptor descriptor SHA256.init declared
    pure
      ( "sha256:"
          <> TextEncoding.decodeUtf8 (Base16.encode (SHA256.finalize digestContext))
      )

digestLoaderDescriptor ::
  Fd ->
  SHA256.Ctx ->
  Integer ->
  IO SHA256.Ctx
digestLoaderDescriptor descriptor context remaining
  | remaining <= 0 = pure context
  | otherwise = do
      chunk <- readLoaderChunk descriptor (min remaining loaderChunkBytes)
      when (ByteString.null chunk) $
        ioError (userError "loader file ended before its declared size")
      digestLoaderDescriptor
        descriptor
        (SHA256.update context chunk)
        (remaining - toInteger (ByteString.length chunk))

loaderChunkBytes :: Integer
loaderChunkBytes = 1024 * 1024

-- | Read exactly the declared bytes of a file through a retained descriptor.
readExactLoaderFileBytes :: FilePath -> Integer -> IO ByteString.ByteString
readExactLoaderFileBytes path bound = do
  listedStatus <- getSymbolicLinkStatus path
  unless
    ( isRegularFile listedStatus
        && not (isSymbolicLink listedStatus)
        && toInteger (fileSize listedStatus) <= bound
        && toInteger (fileSize listedStatus) <= toInteger (maxBound :: Int)
    )
    ( ioError
        (userError ("loader file exceeds its fixed bound: " <> path))
    )
  withStableLoaderDescriptor path listedStatus $ \descriptor openedStatus ->
    readExactLoaderBytes descriptor (toInteger (fileSize openedStatus)) []

readExactLoaderBytes ::
  Fd ->
  Integer ->
  [ByteString.ByteString] ->
  IO ByteString.ByteString
readExactLoaderBytes descriptor remaining collected
  | remaining <= 0 = pure (ByteString.concat (reverse collected))
  | otherwise = do
      chunk <- readLoaderChunk descriptor (min remaining loaderChunkBytes)
      when (ByteString.null chunk) $
        ioError (userError "loader file ended before its declared size")
      readExactLoaderBytes
        descriptor
        (remaining - toInteger (ByteString.length chunk))
        (chunk : collected)

-- | @fdRead@ signals end-of-file by throwing rather than returning an empty
-- result, so an end-of-stream must be caught rather than tested for.
readLoaderChunk :: Fd -> Integer -> IO ByteString.ByteString
readLoaderChunk descriptor requested = do
  result <-
    try @IOException
      (PosixByteString.fdRead descriptor (fromIntegral requested))
  case result of
    Right chunk -> pure chunk
    Left failure
      | isEOFError failure -> pure ByteString.empty
      | otherwise -> ioError failure

withStableLoaderDescriptor ::
  FilePath ->
  FileStatus ->
  (Fd -> FileStatus -> IO result) ->
  IO result
withStableLoaderDescriptor path listedStatus action =
  mask $ \restore -> do
    descriptor <-
      openFd
        path
        ReadOnly
        defaultFileFlags {nofollow = True, cloexec = True}
    finallyPreservingPrimary
      ( restore $ do
          openedStatus <- getFdStatus descriptor
          unless (stableLoaderStatus listedStatus openedStatus) $
            ioError
              (userError ("loader file changed before its exact read: " <> path))
          result <- action descriptor openedStatus
          finalStatus <- getFdStatus descriptor
          unless (stableLoaderStatus openedStatus finalStatus) $
            ioError
              (userError ("loader file changed during its exact read: " <> path))
          pure result
      )
      (closeFd descriptor)

stableLoaderStatus :: FileStatus -> FileStatus -> Bool
stableLoaderStatus firstStatus secondStatus =
  deviceID firstStatus == deviceID secondStatus
    && fileID firstStatus == fileID secondStatus
    && fileMode firstStatus == fileMode secondStatus
    && fileSize firstStatus == fileSize secondStatus
    && modificationTimeHiRes firstStatus == modificationTimeHiRes secondStatus
    && statusChangeTimeHiRes firstStatus == statusChangeTimeHiRes secondStatus

pathStatus :: FilePath -> IO (Maybe FileStatus)
pathStatus path = do
  result <- try @IOException (getSymbolicLinkStatus path)
  case result of
    Right status -> pure (Just status)
    Left failure
      | isDoesNotExistError failure -> pure Nothing
      | otherwise -> ioError failure

-- | Every ELF object under one closed image root, in sorted order. A scanned
-- object is a load root in its own right: it is reached through some loader in
-- the same image, so it must carry evidence even when no dependency edge in
-- this closure names it.
scanClosureRootForElfObjects :: FilePath -> IO [FilePath]
scanClosureRootForElfObjects closureRoot = do
  status <- pathStatus closureRoot
  case status of
    Nothing -> pure []
    Just rootStatus
      | not (isDirectory rootStatus) -> pure []
      | otherwise -> do
          (found, _visited) <- scanElfDirectory closureRoot 0 ([], 0)
          pure (List.sort (List.nub found))

scanElfDirectory ::
  FilePath ->
  Int ->
  ([FilePath], Int) ->
  IO ([FilePath], Int)
scanElfDirectory directory depth accumulator = do
  when (depth > maximumLoaderScanDepth) $
    ioError (userError "ELF closure scan exceeds its fixed depth bound")
  entries <- listLoaderDirectory directory
  foldM (scanElfEntry directory depth) accumulator (List.sort entries)

scanElfEntry ::
  FilePath ->
  Int ->
  ([FilePath], Int) ->
  FilePath ->
  IO ([FilePath], Int)
scanElfEntry directory depth (found, visited) entry = do
  when (visited > maximumLoaderScanEntries) $
    ioError (userError "ELF closure scan exceeds its fixed entry bound")
  let path = directory </> entry
  status <- pathStatus path
  case status of
    Nothing -> pure (found, visited + 1)
    Just entryStatus
      | isSymbolicLink entryStatus -> pure (found, visited + 1)
      | isDirectory entryStatus ->
          scanElfDirectory path (depth + 1) (found, visited + 1)
      | isRegularFile entryStatus -> do
          candidate <- loaderElfCandidate path entryStatus
          pure (maybe found (: found) candidate, visited + 1)
      | otherwise -> pure (found, visited + 1)

loaderElfCandidate :: FilePath -> FileStatus -> IO (Maybe FilePath)
loaderElfCandidate path status
  | toInteger (fileSize status) < 6 = pure Nothing
  | toInteger (fileSize status) > maximumLoaderObjectBytes = pure Nothing
  | otherwise =
      withStableLoaderDescriptor path status $ \descriptor _openedStatus -> do
        leading <- readLoaderChunk descriptor 6
        pure
          ( if elfImageMagicPresent leading
              then Just path
              else Nothing
          )

listLoaderDirectory :: FilePath -> IO [FilePath]
listLoaderDirectory directory =
  mask $ \restore -> do
    stream <- openDirStream directory
    finallyPreservingPrimary
      (restore (drainLoaderDirectory stream []))
      (closeDirStream stream)

drainLoaderDirectory ::
  DirStream ->
  [FilePath] ->
  IO [FilePath]
drainLoaderDirectory stream collected = do
  entry <- readDirStream stream
  if null entry
    then pure (reverse collected)
    else
      if entry `elem` [".", ".."]
        then drainLoaderDirectory stream collected
        else drainLoaderDirectory stream (entry : collected)

-- Byte helpers -------------------------------------------------------------

readOctet :: ByteString.ByteString -> Int -> Either String Word8
readOctet bytes offset = do
  unlessEither
    (offset >= 0 && offset < ByteString.length bytes)
    "ELF read is out of bounds"
  Right (ByteString.index bytes offset)

readInteger ::
  ByteString.ByteString ->
  Int ->
  Int ->
  Bool ->
  Either String Word64
readInteger bytes offset width little = do
  unlessEither
    ( offset >= 0
        && width > 0
        && width <= 8
        && offset + width <= ByteString.length bytes
    )
    "ELF read is out of bounds"
  let octets =
        [ ByteString.index bytes (offset + index)
        | index <- [0 .. width - 1]
        ]
      ordered = if little then octets else reverse octets
  Right
    ( foldr
        (.|.)
        0
        [ fromIntegral octet `shiftL` shift
        | (octet, shift) <- zip ordered [0, 8 ..]
        ]
    )

boundedSlice ::
  ByteString.ByteString ->
  Word64 ->
  Word64 ->
  Either String ByteString.ByteString
boundedSlice contents offset size = do
  let available = fromIntegral (ByteString.length contents) :: Word64
  unlessEither
    ( size > 0
        && offset <= available
        && size <= available - offset
        && offset <= fromIntegral (maxBound :: Int)
        && size <= fromIntegral (maxBound :: Int)
    )
    "ELF slice is out of bounds"
  Right
    ( ByteString.take
        (fromIntegral size)
        (ByteString.drop (fromIntegral offset) contents)
    )

unlessEither :: Bool -> String -> Either String ()
unlessEither predicate failure
  | predicate = Right ()
  | otherwise = Left failure
