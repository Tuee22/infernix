-- | Phase 0 Sprint 0.24 — the mechanical half of
-- @DEVELOPMENT_PLAN/development_plan_standards.md@.
--
-- The standards declare enforcement scans for exactly one of their twenty-two
-- sections, and even those two were prose instructions to whoever ran the
-- "maintenance pass" rather than code. The result is the shape this repository
-- already refuses everywhere else: the section the corpus violates most
-- severely — Section D, declarative language — is precisely the section with no
-- scan, no threshold, and no owner. A rule that is only prose is a rule that
-- decays.
--
-- Every scan below is a proxy for a rule rather than the rule itself. Where a
-- proxy can only approximate its section, the diagnostic and the comment say
-- so instead of implying the check is complete. What this module does not
-- claim: that a clean report means the plan is well written, that a phase's
-- recorded status is true, or that a receipt describes a run that happened.
module Infernix.Lint.Plan
  ( runPlanLint,
    scanPlanViolations,
    backwardEdgeViolations,
    sprintBackwardEdgeViolations,
    dualAcceleratorGateViolations,
    statusVocabularyViolations,
    remainingWorkViolations,
    receiptMarkerViolations,
    ledgerDoubleListingViolations,
    phaseStatusTableViolations,
    forwardOwnershipViolations,
    parseSprintBlocks,
    SprintBlock
      ( SprintBlock,
        sprintSourceFile,
        sprintHeadingLineNumber,
        sprintIdentifier,
        sprintDeclaredStatus,
        sprintBodyLines
      ),
    declaredSprintStatuses,
    receiptMarkerLineCount,
    maximumReceiptMarkerLinesPerPhaseDocument,
  )
where

import Control.Monad (unless)
import Data.Char (isDigit, isSpace)
import Data.List
  ( intercalate,
    isInfixOf,
    isPrefixOf,
    isSuffixOf,
    nub,
    sort,
  )
import Data.Maybe (fromMaybe)
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory (listDirectory)
import System.FilePath ((</>))

-- | The plan directory every scan reads. Discovered rather than enumerated so
-- a new plan document cannot be added outside the scans' view.
planDirectory :: FilePath
planDirectory = "DEVELOPMENT_PLAN"

-- | The cleanup ledger Section D designates as the home for supersession
-- history, and Section I as the removal ledger.
legacyLedgerDocument :: FilePath
legacyLedgerDocument = "DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md"

-- | The one document allowed to spell the vocabulary the other scans reject:
-- the standards define the rules and therefore have to quote them.
standardsDocument :: FilePath
standardsDocument = "DEVELOPMENT_PLAN/development_plan_standards.md"

-- | Run every scan and fail with the collected diagnostics.
runPlanLint :: IO ()
runPlanLint = do
  paths <- discoverPaths
  documents <- readPlanDocuments (repoRoot paths)
  let failures = scanPlanViolations documents
  unless (null failures) (ioError (userError (unlines failures)))

-- | Read every Markdown document under the plan directory, paired with its
-- repository-relative path.
readPlanDocuments :: FilePath -> IO [(FilePath, String)]
readPlanDocuments root = do
  entries <- listDirectory (root </> planDirectory)
  let markdownEntries = sort (filter (isSuffixOf ".md") entries)
  mapM (readPlanDocument root) markdownEntries

readPlanDocument :: FilePath -> FilePath -> IO (FilePath, String)
readPlanDocument root entry = do
  let relativePath = planDirectory <> "/" <> entry
  contents <- readFile (root </> relativePath)
  pure (relativePath, contents)

-- | Every scan, in the order the standards present their sections.
scanPlanViolations :: [(FilePath, String)] -> [String]
scanPlanViolations documents =
  concat
    [ statusVocabularyViolations sprints,
      remainingWorkViolations sprints,
      backwardEdgeViolations phaseDocuments,
      sprintBackwardEdgeViolations sprints,
      dualAcceleratorGateViolations phaseDocuments,
      receiptMarkerViolations phaseDocuments,
      ledgerDoubleListingViolations documents,
      phaseStatusTableViolations documents,
      forwardOwnershipViolations phaseDocuments
    ]
  where
    phaseDocuments = filter (isPhasePlanDocument . fst) documents
    sprints = concatMap (uncurry parseSprintBlocks) phaseDocuments

-- | @DEVELOPMENT_PLAN\/phase-<n>-*.md@, the documents Sections C, D, G and Q
-- govern.
isPhasePlanDocument :: FilePath -> Bool
isPhasePlanDocument relativePath =
  isPrefixOf (planDirectory <> "/phase-") relativePath
    && isSuffixOf ".md" relativePath

-- | The owning phase number carried by a phase document's file name.
phaseNumberOfDocument :: FilePath -> Maybe Int
phaseNumberOfDocument relativePath =
  readNumber (takeWhile isDigit (drop prefixLength relativePath))
  where
    prefixLength = length (planDirectory <> "/phase-")

-- | One @## Sprint X.Y: Name [STATUS]@ block and the lines beneath it.
data SprintBlock = SprintBlock
  { sprintSourceFile :: !FilePath,
    sprintHeadingLineNumber :: !Int,
    -- | @(phase, sprint)@ when the heading carries a parseable identifier.
    sprintIdentifier :: !(Maybe (Int, Int)),
    -- | The text between the heading's final brackets.
    sprintDeclaredStatus :: !String,
    sprintBodyLines :: ![(Int, String)]
  }
  deriving (Eq, Show)

-- | Split a phase document into its sprint blocks.
parseSprintBlocks :: FilePath -> String -> [SprintBlock]
parseSprintBlocks relativePath contents =
  buildBlocks (zip [1 :: Int ..] (lines contents))
  where
    buildBlocks numberedLines =
      case dropWhile (not . isSprintHeading . snd) numberedLines of
        [] -> []
        ((headingNumber, headingValue) : rest) ->
          let body = takeWhile (not . isSprintHeading . snd) rest
              remainder = dropWhile (not . isSprintHeading . snd) rest
              block =
                SprintBlock
                  { sprintSourceFile = relativePath,
                    sprintHeadingLineNumber = headingNumber,
                    sprintIdentifier = parseSprintIdentifier headingValue,
                    sprintDeclaredStatus = parseBracketedStatus headingValue,
                    sprintBodyLines = body
                  }
           in block : buildBlocks remainder

isSprintHeading :: String -> Bool
isSprintHeading = isPrefixOf "## Sprint "

-- | @## Sprint 1.20: Name [Active]@ yields @Just (1, 20)@.
parseSprintIdentifier :: String -> Maybe (Int, Int)
parseSprintIdentifier headingValue =
  splitIdentifier (takeWhile (/= ':') (drop (length "## Sprint ") headingValue))
  where
    splitIdentifier text =
      let phaseText = takeWhile isDigit (dropWhile isSpace text)
          sprintText = takeWhile isDigit (drop 1 (dropWhile (/= '.') text))
       in pairNumbers (readNumber phaseText) (readNumber sprintText)
    pairNumbers (Just phase) (Just sprint) = Just (phase, sprint)
    pairNumbers _ _ = Nothing

-- | The text inside the heading's final bracket pair.
parseBracketedStatus :: String -> String
parseBracketedStatus headingValue =
  trim (takeWhile (/= ']') (drop 1 (dropWhile (/= '[') lastBracketed)))
  where
    lastBracketed = fromMaybe "" (breakOnLastBracket headingValue)

breakOnLastBracket :: String -> Maybe String
breakOnLastBracket value =
  lastOrNothing [drop index value | index <- [0 .. length value - 1], take 1 (drop index value) == "["]

lastOrNothing :: [a] -> Maybe a
lastOrNothing [] = Nothing
lastOrNothing values = Just (last values)

-- | Section C's four-value status vocabulary. Anything else — including the
-- @Active — Validation Only@ fifth value the corpus grew — is a violation,
-- because a status outside the table has no defined obligations.
declaredSprintStatuses :: [String]
declaredSprintStatuses = ["Active", "Blocked", "Done", "Planned"]

-- | Section C: a sprint's status must be one of the four declared values.
statusVocabularyViolations :: [SprintBlock] -> [String]
statusVocabularyViolations sprints =
  [ describeSprint sprint
      <> ": status `"
      <> sprintDeclaredStatus sprint
      <> "` is outside the Section C vocabulary ("
      <> intercalate ", " declaredSprintStatuses
      <> ")"
  | sprint <- sprints,
    sprintDeclaredStatus sprint `notElem` declaredSprintStatuses
  ]

-- | Section C: @Active@ requires remaining work, @Blocked@ requires a named
-- blocker, and @Done@ requires that no remaining work is left.
remainingWorkViolations :: [SprintBlock] -> [String]
remainingWorkViolations = concatMap sprintViolations
  where
    sprintViolations sprint
      | sprintDeclaredStatus sprint == "Done" = doneViolations sprint
      | sprintDeclaredStatus sprint == "Active" = activeViolations sprint
      | sprintDeclaredStatus sprint == "Blocked" = blockedViolations sprint
      | otherwise = []

    doneViolations sprint =
      [ describeSprint sprint
          <> ": `Done` carries "
          <> show (length (remainingWorkBody sprint))
          <> " lines of remaining work; Section C reserves `Done` for a sprint with none"
      | not (isDischargedRemainingWork (remainingWorkBody sprint))
      ]

    activeViolations sprint =
      [ describeSprint sprint
          <> ": `Active` has no remaining work recorded; Section C requires a `Remaining Work` section that says what is open"
      | isDischargedRemainingWork (remainingWorkBody sprint)
      ]

    blockedViolations sprint =
      [ describeSprint sprint
          <> ": `Blocked` names no blocker; Section C requires a `Blocked by` line"
      | not (any (isInfixOf "Blocked by" . snd) (sprintBodyLines sprint))
      ]

-- | The prose beneath a sprint's @### Remaining Work@ heading.
--
-- Blank lines and the horizontal rule that separates sprints carry no claim,
-- so they are dropped before the section is judged. Counting the rule would
-- report every correctly discharged sprint as carrying a line of open work,
-- which is the difference between a scan and a nuisance.
remainingWorkBody :: SprintBlock -> [String]
remainingWorkBody sprint =
  [ trimmed
  | (_, lineValue) <- sectionLines "### Remaining Work" (sprintBodyLines sprint),
    let trimmed = trim lineValue,
    not (null trimmed),
    not (isHorizontalRule trimmed)
  ]

-- | A Markdown thematic break, in any of the lengths the plan uses.
isHorizontalRule :: String -> Bool
isHorizontalRule value = length value >= 3 && all (== '-') value

-- | Whether a @Remaining Work@ body records that nothing is open. The corpus
-- writes this several ways, and treating only a bare @None@ as discharged
-- would manufacture violations out of a formatting choice.
isDischargedRemainingWork :: [String] -> Bool
isDischargedRemainingWork [] = True
isDischargedRemainingWork [single] = isDischargedRemainingWorkLine single
isDischargedRemainingWork _ = False

-- | Whether one line declares nothing open.
--
-- The corpus writes discharge as @None@ plus, often, a clause naming where the
-- closure was recorded; that is still a discharge. A clause naming a residual
-- is not: Section C is explicit that a sprint whose code-side work is complete
-- but whose cohort gate is pending stays @Active@ with that residual named, so
-- "None (code-side); the cohort rebuild is the residual" on a @Done@ sprint is
-- the violation rather than a wording variant of none.
isDischargedRemainingWorkLine :: String -> Bool
isDischargedRemainingWorkLine value =
  isPrefixOf "None" stripped && not (namesPendingResidual stripped)
  where
    stripped = trim (dropBulletMarker (trim value))

dropBulletMarker :: String -> String
dropBulletMarker value
  | "- " `isPrefixOf` value = drop 2 value
  | "**" `isPrefixOf` value = filter (/= '*') value
  | otherwise = value

namesPendingResidual :: String -> Bool
namesPendingResidual value =
  any (`isInfixOf` value) ["residual", "tracked with", "cohort gate", "remains open", "still pending"]

-- | Lines beneath a @###@ heading, up to the next heading of any depth.
sectionLines :: String -> [(Int, String)] -> [(Int, String)]
sectionLines heading numberedLines =
  takeWhile (not . isAnyHeading . snd) (drop 1 (dropWhile (not . isWantedHeading . snd) numberedLines))
  where
    isWantedHeading lineValue = trim lineValue == heading
    isAnyHeading = isPrefixOf "#"

-- | Section Q invariant 1: every dependency edge points at an
-- equal-or-lower-numbered phase and sprint.
--
-- The declared scan reads forward edges from the blocked party's own
-- @Blocked by@ line. That form cannot see a backward edge phrased from the
-- other side — "ordered before Sprint 6.43 can reach `Done`" states that a
-- lower-numbered sibling is blocked by this one — so the reverse phrasing is
-- scanned for as well and reported distinctly.
backwardEdgeViolations :: [(FilePath, String)] -> [String]
backwardEdgeViolations = concatMap documentViolations
  where
    documentViolations (relativePath, contents) =
      concatMap
        (lineViolations relativePath (phaseNumberOfDocument relativePath))
        (blockedByLines contents)

    -- A blocker statement wraps. The corpus writes the dependency on one line
    -- and its qualification on the next, so reading single lines misses
    -- exactly the reverse-direction phrasing this scan exists to catch. The
    -- statement runs to the following bold field marker.
    blockedByLines contents = collectStatements (zip [1 :: Int ..] (lines contents))

    collectStatements numberedLines =
      case dropWhile (not . isInfixOf "Blocked by" . snd) numberedLines of
        [] -> []
        ((lineNumber, lineValue) : rest) ->
          let continuation = takeWhile (isBlockerContinuation . snd) rest
              statement = unwords (lineValue : map snd continuation)
           in (lineNumber, statement) : collectStatements (drop (length continuation) rest)

    isBlockerContinuation lineValue =
      not (null (trim lineValue))
        && not ("**" `isPrefixOf` trim lineValue)
        && not ("#" `isPrefixOf` trim lineValue)
        && not ("|" `isPrefixOf` trim lineValue)
        && not ("-" `isPrefixOf` trim lineValue)

    lineViolations relativePath maybeOwningPhase (lineNumber, lineValue) =
      forwardViolations relativePath maybeOwningPhase lineNumber lineValue
        <> reverseViolations relativePath lineNumber lineValue

    forwardViolations relativePath maybeOwningPhase lineNumber lineValue =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": backward dependency edge — a phase-"
          <> show owningPhase
          <> " document is blocked by phase "
          <> show referenced
          <> "; Section Q requires every edge to reference an equal-or-lower-numbered phase"
      | owningPhase <- maybeToList maybeOwningPhase,
        referenced <- nub (referencedPhaseNumbers lineValue),
        referenced > owningPhase
      ]

    reverseViolations relativePath lineNumber lineValue =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": backward dependency edge stated from the dependee's side — this blocker line says a lower-numbered sprint cannot close until this one lands, which Section Q's forward-edge scan cannot see"
      | "before Sprint " `isInfixOf` lineValue
      ]

-- | Phase numbers named by a blocker line, from both @Phase <n>@ and the
-- @<n>.<m>@ sprint form.
referencedPhaseNumbers :: String -> [Int]
referencedPhaseNumbers lineValue =
  concatMap numbersAt (indices lineValue)
  where
    indices value = [0 .. length value - 1]
    numbersAt index =
      phaseWordNumber (drop index lineValue)
        <> sprintDottedNumber (drop index lineValue)

    phaseWordNumber suffix =
      [ number
      | "Phase " `isPrefixOf` suffix,
        number <- maybeToList (readNumber (takeWhile isDigit (drop (length "Phase ") suffix)))
      ]

    sprintDottedNumber suffix =
      [ number
      | "Sprint " `isPrefixOf` suffix,
        let dotted = drop (length "Sprint ") suffix,
        "." `isInfixOf` takeWhile (not . isSpace) dotted,
        number <- maybeToList (readNumber (takeWhile isDigit dotted))
      ]

-- | Section Q invariant 1 at sprint granularity.
--
-- The invariant is stated over phases /and sprints/, but comparing only the
-- owning document's phase number lets a within-phase backward edge through: a
-- phase-6 sprint blocked by a higher-numbered phase-6 sibling references phase
-- 6, which passes. That is not a hypothetical shape — it is how the plan
-- actually recorded the one backward edge it had.
--
-- The dependency is caught wherever it is stated. A blocker line is exact. A
-- @Remaining Work@ body saying a sprint cannot close before a higher-numbered
-- sibling is the same edge written somewhere the blocker scan does not look,
-- and it is reported with its own wording so the reader can see which form was
-- used.
sprintBackwardEdgeViolations :: [SprintBlock] -> [String]
sprintBackwardEdgeViolations = concatMap sprintViolations
  where
    sprintViolations sprint =
      concatMap (edgeViolations sprint) (maybeToList (sprintIdentifier sprint))

    edgeViolations sprint identifier =
      blockerViolations sprint identifier <> closureViolations sprint identifier

    blockerViolations sprint identifier =
      [ describeSprint sprint
          <> ": blocked by the higher-numbered Sprint "
          <> renderSprintIdentifier referenced
          <> "; Section Q requires every dependency edge to reference an equal-or-lower-numbered sprint"
      | (_, statement) <- blockerStatements (sprintBodyLines sprint),
        referenced <- nub (referencedSprintIdentifiers statement),
        referenced > identifier
      ]

    -- The closure phrase and the sprint it names must be on one line. Reading
    -- them from anywhere in the body pairs an unrelated historical mention
    -- with an unrelated closure sentence, which reported two phase documents
    -- that have no such dependency at all.
    closureViolations sprint identifier =
      [ describeSprint sprint
          <> ": closure depends on the higher-numbered Sprint "
          <> renderSprintIdentifier referenced
          <> "; the edge is recorded in `Remaining Work` rather than a blocker line, but Section Q's forward-only rule applies to the dependency, not to where it is written"
      | lineValue <- remainingWorkBody sprint,
        namesLaterClosure lineValue,
        referenced <- nub (referencedSprintIdentifiers lineValue),
        referenced > identifier
      ]

    namesLaterClosure value =
      any (`isInfixOf` value) ["cannot reach", "cannot close", "before it", "owns the"]

-- | Blocker statements inside one sprint body, joined across their wrap.
blockerStatements :: [(Int, String)] -> [(Int, String)]
blockerStatements numberedLines =
  case dropWhile (not . isInfixOf "Blocked by" . snd) numberedLines of
    [] -> []
    ((lineNumber, lineValue) : rest) ->
      let continuation = takeWhile (isStatementContinuation . snd) rest
          statement = unwords (lineValue : map snd continuation)
       in (lineNumber, statement) : blockerStatements (drop (length continuation) rest)

isStatementContinuation :: String -> Bool
isStatementContinuation lineValue =
  not (null (trim lineValue))
    && not ("**" `isPrefixOf` trim lineValue)
    && not ("#" `isPrefixOf` trim lineValue)
    && not ("|" `isPrefixOf` trim lineValue)
    && not ("-" `isPrefixOf` trim lineValue)

-- | Every @Sprint N.M@ identifier named in a statement.
referencedSprintIdentifiers :: String -> [(Int, Int)]
referencedSprintIdentifiers statement =
  concatMap identifierAt (suffixes statement)
  where
    identifierAt suffix =
      [ identifier
      | "Sprint " `isPrefixOf` suffix,
        let dotted = drop (length "Sprint ") suffix,
        identifier <- maybeToList (parseDottedIdentifier dotted)
      ]

parseDottedIdentifier :: String -> Maybe (Int, Int)
parseDottedIdentifier dotted =
  pairNumbers (readNumber phaseText) (readNumber sprintText)
  where
    phaseText = takeWhile isDigit dotted
    afterPhase = drop (length phaseText) dotted
    sprintText = takeWhile isDigit (drop 1 afterPhase)
    pairNumbers (Just phase) (Just sprint)
      | "." `isPrefixOf` afterPhase = Just (phase, sprint)
    pairNumbers _ _ = Nothing

renderSprintIdentifier :: (Int, Int) -> String
renderSprintIdentifier (phase, sprint) = show phase <> "." <> show sprint

-- | Section Q invariant 2: no single @### Validation@ gate spans both
-- accelerators.
--
-- The declared scan names @--apple-silicon@ \/ @apple-silicon.sh@ against
-- @linux-gpu.sh@. That token list is narrow enough that a gate written with
-- bare substrate identifiers would pass it, so the bare form is reported too —
-- separately, because per-lane attestation narration legitimately mentions
-- both and only a shared must-pass-together invocation is a violation.
dualAcceleratorGateViolations :: [(FilePath, String)] -> [String]
dualAcceleratorGateViolations = concatMap documentViolations
  where
    documentViolations (relativePath, contents) =
      concatMap (blockViolations relativePath) (validationBlocks contents)

    validationBlocks contents =
      validationSections (zip [1 :: Int ..] (lines contents))

    blockViolations relativePath (headingNumber, blockLines) =
      [ relativePath
          <> ":"
          <> show headingNumber
          <> ": validation gate names an apple-silicon invocation and a linux-gpu invocation together; Section Q requires one accelerator plus `linux-cpu`"
      | any (containsAnyToken appleInvocationTokens) blockLines,
        any (containsAnyToken linuxGpuInvocationTokens) blockLines
      ]

    containsAnyToken tokens lineValue = any (`isInfixOf` lineValue) tokens

appleInvocationTokens :: [String]
appleInvocationTokens = ["--apple-silicon", "apple-silicon.sh"]

linuxGpuInvocationTokens :: [String]
linuxGpuInvocationTokens = ["--linux-gpu", "linux-gpu.sh"]

-- | Each @### Validation@ heading paired with the lines beneath it.
validationSections :: [(Int, String)] -> [(Int, [String])]
validationSections numberedLines =
  case dropWhile (not . isValidationHeading . snd) numberedLines of
    [] -> []
    ((headingNumber, _) : rest) ->
      let body = map snd (takeWhile (not . isPrefixOf "#" . snd) rest)
          remainder = dropWhile (not . isPrefixOf "#" . snd) rest
       in (headingNumber, body) : validationSections remainder

isValidationHeading :: String -> Bool
isValidationHeading lineValue = trim lineValue == "### Validation"

-- | Section D: phase documents are declarative descriptions of a target, not
-- migration diaries.
--
-- Section D is the rule the corpus violates most severely and the one the
-- standards never gave a scan. A perfect check is not available — "is this
-- prose declarative" is not decidable — so this bans the run-log artefacts
-- that only a diary contains and reports the residual density. A process
-- identifier, a wall-clock time, or an inode number describes one execution on
-- one machine and can never be true of the target.
receiptMarkerViolations :: [(FilePath, String)] -> [String]
receiptMarkerViolations = concatMap documentViolations
  where
    documentViolations (relativePath, contents) =
      bannedMarkerViolations relativePath contents
        <> densityViolations relativePath contents

    bannedMarkerViolations relativePath contents =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": run-log artefact in a phase document ("
          <> markerName
          <> "); Section D keeps execution chronology out of the plan's declarative text"
      | (lineNumber, lineValue) <- zip [1 :: Int ..] (lines contents),
        (markerName, matches) <- bannedMarkers lineValue,
        matches
      ]

    densityViolations relativePath contents =
      [ relativePath
          <> ": "
          <> show markerLines
          <> " lines carry a validation-receipt marker, above the declared ceiling of "
          <> show maximumReceiptMarkerLinesPerPhaseDocument
          <> "; Section D places supersession history in "
          <> legacyLedgerDocument
      | let markerLines = receiptMarkerLineCount contents,
        markerLines > maximumReceiptMarkerLinesPerPhaseDocument
      ]

-- | The run-log artefacts a declarative phase document can never need.
bannedMarkers :: String -> [(String, Bool)]
bannedMarkers lineValue =
  [ ("process identifier", containsProcessIdentifier lineValue),
    ("wall-clock time", containsClockTime lineValue),
    ("inode number", containsInodeNumber lineValue)
  ]

-- | An inode /number/, not the word. Prose that reasons about inode allocation
-- is prescriptive and belongs in a phase document; a specific inode identifies
-- one object on one filesystem on one machine and does not.
containsInodeNumber :: String -> Bool
containsInodeNumber lineValue = any startsWithInodeNumber (suffixes lineValue)
  where
    startsWithInodeNumber suffix =
      isPrefixOf "inode " suffix
        && not (null (takeWhile isDigit (drop (length "inode ") suffix)))

containsProcessIdentifier :: String -> Bool
containsProcessIdentifier lineValue =
  any startsWithProcessIdentifier (suffixes lineValue)
  where
    startsWithProcessIdentifier suffix =
      any (`isPrefixOf` suffix) ["PID ", "pid ", "PGID ", "pgid "]
        && not (null (takeWhile isDigit (dropWhile (not . isDigit) (take 12 suffix))))

-- | @HH:MM:SS@ anywhere in the line.
containsClockTime :: String -> Bool
containsClockTime lineValue = any isClockTimeAt (suffixes lineValue)
  where
    isClockTimeAt suffix =
      case take 8 suffix of
        [h1, h2, c1, m1, m2, c2, s1, s2] ->
          all isDigit [h1, h2, m1, m2, s1, s2] && c1 == ':' && c2 == ':'
        _ -> False

suffixes :: String -> [String]
suffixes value = [drop index value | index <- [0 .. length value - 1]]

-- | How many lines carry a validation-receipt marker.
receiptMarkerLineCount :: String -> Int
receiptMarkerLineCount contents =
  length (filter isReceiptMarkerLine (lines contents))

isReceiptMarkerLine :: String -> Bool
isReceiptMarkerLine lineValue =
  containsClockTime lineValue
    || containsProcessIdentifier lineValue
    || containsIsoDate lineValue
    || any (`isInfixOf` lineValue) ["GREEN", "INVALIDATED", "sha256:"]

containsIsoDate :: String -> Bool
containsIsoDate lineValue = any isIsoDateAt (suffixes lineValue)
  where
    isIsoDateAt suffix =
      case take 10 suffix of
        [y1, y2, y3, y4, d1, m1, m2, d2, day1, day2] ->
          all isDigit [y1, y2, y3, y4, m1, m2, day1, day2] && d1 == '-' && d2 == '-'
        _ -> False

-- | The declared per-document ceiling for receipt-bearing lines.
--
-- A phase document legitimately cites a handful of dated attestations. It does
-- not legitimately contain hundreds; at that point the document has become the
-- ledger rather than referencing it. The ceiling is a judgement encoded as a
-- number so the cleanup can be measured instead of asserted.
maximumReceiptMarkerLinesPerPhaseDocument :: Int
maximumReceiptMarkerLinesPerPhaseDocument = 40

-- | Section I: an item is pending or complete, never both.
--
-- A row that sits in both tables is how a removal gets recorded as landed
-- while its Pending twin keeps claiming the work is open; the reader cannot
-- tell which is current. Self-declared discharge is caught too: a Pending row
-- whose own text says the surface was removed belongs in the Completed table
-- by Section I's move rule.
ledgerDoubleListingViolations :: [(FilePath, String)] -> [String]
ledgerDoubleListingViolations documents =
  concatMap ledgerViolations (filter ((== legacyLedgerDocument) . fst) documents)
  where
    ledgerViolations (relativePath, contents) =
      dischargedPendingViolations relativePath contents
        <> doubleListedViolations relativePath contents

    dischargedPendingViolations relativePath contents =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": pending removal row declares its own surface already removed; Section I moves a landed item to the Completed table"
      | (lineNumber, rowValue) <- pendingRows contents,
        "Removed " `isInfixOf` rowValue
      ]

    doubleListedViolations relativePath contents =
      [ relativePath
          <> ":"
          <> show pendingNumber
          <> ": pending removal row shares "
          <> show (length shared)
          <> " named symbols and its owning sprint with a Completed row; Section I forbids an item appearing in both tables"
      | (pendingNumber, pendingRow) <- pendingRows contents,
        (_, completedRow) <- completedRows contents,
        ledgerRowOwner pendingRow == ledgerRowOwner completedRow,
        not (null (ledgerRowOwner pendingRow)),
        let shared = sharedCodeTokens pendingRow completedRow,
        length shared >= minimumSharedLedgerSymbols
      ]

-- | How many distinct backticked symbols two ledger rows must share before
-- they are treated as the same item.
--
-- Symbol overlap alone is not evidence: a pending row describing a surface
-- that still exists and a completed row describing the migration that reduced
-- it legitimately name the same identifiers. The owning sprint is the
-- discriminator — one sprint recording the same item as both open and landed
-- is the Section I defect — so both must agree before a pair is reported.
minimumSharedLedgerSymbols :: Int
minimumSharedLedgerSymbols = 3

-- | The owning phase or sprint in a ledger row's final column.
ledgerRowOwner :: String -> String
ledgerRowOwner rowValue =
  case reverse (splitTableCells rowValue) of
    [] -> ""
    (lastCell : _) -> trim lastCell

splitTableCells :: String -> [String]
splitTableCells rowValue =
  filter (not . null . trim) (foldr accumulate [""] (trim rowValue))
  where
    accumulate character (current : rest)
      | character == '|' = "" : current : rest
      | otherwise = (character : current) : rest
    accumulate _ [] = [""]

pendingRows :: String -> [(Int, String)]
pendingRows = ledgerTableRows "## Pending Removal"

completedRows :: String -> [(Int, String)]
completedRows = ledgerTableRows "## Completed"

ledgerTableRows :: String -> String -> [(Int, String)]
ledgerTableRows heading contents =
  [ numbered
  | numbered@(_, lineValue) <- sectionLines heading (zip [1 :: Int ..] (lines contents)),
    "| " `isPrefixOf` lineValue,
    not ("| Location" `isPrefixOf` lineValue),
    not ("|---" `isPrefixOf` lineValue)
  ]

-- | Distinct backticked identifiers common to two ledger rows.
sharedCodeTokens :: String -> String -> [String]
sharedCodeTokens leftRow rightRow =
  [token | token <- nub (backtickedTokens leftRow), token `elem` backtickedTokens rightRow]

backtickedTokens :: String -> [String]
backtickedTokens = collect
  where
    collect remaining =
      case break (== '`') remaining of
        (_, []) -> []
        (_, _ : afterOpen) -> takeToken afterOpen

    takeToken afterOpen =
      case break (== '`') afterOpen of
        (_, []) -> []
        (token, _ : afterClose) -> keepToken token <> collect afterClose

    keepToken token
      | length token >= 6 = [token]
      | otherwise = []

-- | Section J: the plan carries one phase-status table, not five.
--
-- Duplicated status tables do not merely repeat; they diverge, and a reader
-- has no way to tell which copy is current.
-- | Section Q scan 8 — zero forward ownership.
--
-- Scan 1 reads @Blocked by@ statements, which is the form a dependency takes
-- when someone writes it down as one. The form it takes in practice is a
-- sentence: a deliverable another sprint @owns@, work @re-home@d forward, an
-- implementation @landed with@ a later sprint. None of those is a blocker line,
-- so scan 1 is structurally blind to them, and they are precisely how an earlier
-- phase ends up unable to close without a later one.
--
-- What this scan decides: the plan no longer /claims/ an earlier phase depends on
-- a later one. What it cannot decide: whether a re-home was correct, or whether
-- the earlier phase can now actually close. A closed sprint pointing forward to
-- what replaced it is Section G working and is not matched here, because the
-- ownership verbs below describe who owns an obligation rather than what
-- superseded a finished one.
forwardOwnershipViolations :: [(FilePath, String)] -> [String]
forwardOwnershipViolations = concatMap documentViolations
  where
    documentViolations (relativePath, contents) =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": forward ownership — a phase-"
          <> show owningPhase
          <> " document places an obligation with phase "
          <> show referenced
          <> " ("
          <> verb
          <> "); Section C requires every phase to be completable using only"
          <> " equal-or-lower-numbered phases, so this deliverable is re-homed rather than recorded"
      | owningPhase <- maybeToList (phaseNumberOfDocument relativePath),
        (lineNumber, lineValue) <- zip [1 :: Int ..] (lines contents),
        not (isSupersessionLine lineValue),
        verb <- ownershipVerbsIn lineValue,
        referenced <- nub (referencedPhaseNumbers lineValue),
        referenced > owningPhase
      ]

    ownershipVerbsIn lineValue =
      [verb | verb <- forwardOwnershipVerbs, verb `isInfixOf` lineValue]

    -- Section G's forward pointer from a closed sprint is the sanctioned form and
    -- is excluded by its own field marker rather than by guessing at prose.
    isSupersessionLine lineValue =
      any
        (`isInfixOf` lineValue)
        ["**Supersession note**", "**Current-API note**", "**Historical-scope note**"]

-- | The sentence forms that place an obligation with another sprint. Kept
-- narrow deliberately: a broader list would match ordinary cross-references,
-- and a scan that cries wolf is turned off.
forwardOwnershipVerbs :: [String]
forwardOwnershipVerbs =
  [ "owned by",
    "is owned by",
    "re-home",
    "landed with",
    "owns the"
  ]

phaseStatusTableViolations :: [(FilePath, String)] -> [String]
phaseStatusTableViolations documents =
  [ "phase-status table appears "
      <> show (length occurrences)
      <> " times across the plan ("
      <> intercalate ", " (map describeOccurrence occurrences)
      <> "); Section J keeps one canonical current-state table"
  | let occurrences = concatMap documentOccurrences documents,
    length occurrences > 1
  ]
  where
    documentOccurrences (relativePath, contents)
      | relativePath == standardsDocument = []
      | otherwise =
          [ (relativePath, lineNumber)
          | (lineNumber, lineValue) <- zip [1 :: Int ..] (lines contents),
            isPhaseStatusTableHeader lineValue
          ]
    describeOccurrence (relativePath, lineNumber) = relativePath <> ":" <> show lineNumber

-- | A status-table /header/ row, not any table row whose first cell happens to
-- start with the word @Phase@.
--
-- The looser prefix form reported three removal-ledger rows — @| Phase 3 Sprint
-- 3.10 … validation residual … | Closed … |@ — as duplicate status tables. A
-- ledger row naming the phase that owns a removal is exactly what Section I
-- requires, so the scan has to read the cell rather than the line: the header's
-- first column is the bare word @Phase@ and one of its columns names status.
isPhaseStatusTableHeader :: String -> Bool
isPhaseStatusTableHeader lineValue =
  case splitTableCells lineValue of
    [] -> False
    (firstCell : remainingCells) ->
      trim firstCell == "Phase" && any (isInfixOf "status") remainingCells

describeSprint :: SprintBlock -> String
describeSprint sprint =
  sprintSourceFile sprint
    <> ":"
    <> show (sprintHeadingLineNumber sprint)

readNumber :: String -> Maybe Int
readNumber text
  | null text = Nothing
  | not (all isDigit text) = Nothing
  | length text > 9 = Nothing
  | otherwise = Just (read text)

maybeToList :: Maybe a -> [a]
maybeToList Nothing = []
maybeToList (Just value) = [value]

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse
