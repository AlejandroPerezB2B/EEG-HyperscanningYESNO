# Behavioural marker extraction for HyperYESNO

## Overview

`extract_behavioural_markers_HyperYESNO.m` extracts trial-level behavioural measures from the event markers stored in the combined EEG recordings of the HyperYESNO experiment.

The function processes the files:

```text
E:\EEG_data_HyperYESNO\DyadXX\DyadXX.set
```

for `Dyad01` to `Dyad35`.

Each experimental trial begins with a `BlockStart` marker. The behavioural responses registered during that trial are represented by:

```text
YES_AKnower
NO_AKnower
YES_BKnower
NO_BKnower
```

The function uses the marker types and latencies to estimate trial duration, YES and NO counts, response timing, response rate, and the identity of the Knower and Guesser. It also appends the fixed target word, semantic category, hint, and expected role assignment corresponding to each trial in the experimental PowerPoint.

The output preserves the trial-level data and additionally creates summaries by dyad, conversational role, and target word.

---

## Dependencies

- MATLAB
- EEGLAB
- `pop_loadset`
- `eeg_checkset`

EEGLAB must be started, or its folders must be available on the MATLAB path, before running the function.

---

## Expected data structure

```text
E:\EEG_data_HyperYESNO
│
├── Dyad01
│   └── Dyad01.set
├── Dyad02
│   └── Dyad02.set
├── ...
└── Dyad35
    └── Dyad35.set
```

The input file is the combined EEGLAB recording containing the events from both participants.

---

## Experimental markers

### Trial marker

```text
BlockStart
```

`BlockStart` corresponds to the beginning of the 60-s trial.

### Response markers

```text
YES_AKnower
NO_AKnower
YES_BKnower
NO_BKnower
```

The first part of the marker indicates the Knower's verbal response. The second part indicates the participant occupying the Knower role:

```text
AKnower → participant A is Knower and participant B is Guesser
BKnower → participant B is Knower and participant A is Guesser
```

The function also recognizes the original numeric Curry codes:

```text
100240 → BlockStart
100241 → YES_AKnower
100242 → NO_AKnower
100244 → YES_BKnower
100248 → NO_BKnower
```

---

## Trial definition

For each `BlockStart`, the function identifies all YES and NO markers occurring before the subsequent `BlockStart`:

```text
BlockStart(i) ≤ response < BlockStart(i+1)
```

For the final trial, the end of the EEG recording is used as the upper boundary. A response occurring at exactly the same sample as the following `BlockStart` is assigned to the new trial.

---

## Behavioural measures

### Trial-use time

The main duration measure is:

```text
last response latency − BlockStart latency
```

converted to seconds using the EEG sampling rate:

```matlab
TrialUseTimeSec = ...
    (LastResponseLatency - BlockStartLatency) / EEG.srate;
```

This represents the time elapsed between trial onset and the final YES or NO response registered on the response pad.

### Response counts

For every trial, the function calculates:

```text
NumYes
NumNo
NumResponses
```

where:

```text
NumResponses = NumYes + NumNo
```

These values approximate the number of questions asked, assuming that the Knower registered every verbal response.

### Additional timing measures

The function also calculates:

```text
FirstResponseTimeSec
MeanInterResponseIntervalSec
MedianInterResponseIntervalSec
TransitionAfterLastResponseSec
BlockStartToNextBlockSec
```

`TransitionAfterLastResponseSec` is the time between the final response and the next `BlockStart`. It includes the time used to exchange the response pad, confirm readiness, and advance the presentation.

### Derived response measures

```text
YesProportion
ResponseRatePerMin
LastResponseType
LastResponseValence
```

---

## Fixed target schedule

The function includes the fixed sequence of 32 experimental targets. Participant B is expected to be Knower in the first analysed trial, and the roles alternate thereafter.

| Trial | Category | Target | Hint | Knower |
|---:|---|---|---|:---:|
| 1 | Animals | Dog |  | B |
| 2 | Animals | Horse |  | A |
| 3 | Animals | Elephant |  | B |
| 4 | Animals | Tiger |  | A |
| 5 | Professions | Doctor |  | B |
| 6 | Professions | Teacher |  | A |
| 7 | Professions | Chef/cooker |  | B |
| 8 | Professions | Police |  | A |
| 9 | Meals | Pizza |  | B |
| 10 | Meals | Burger |  | A |
| 11 | Meals | Ice Cream |  | B |
| 12 | Meals | Sushi |  | A |
| 13 | Objects | Laptop | Technology | B |
| 14 | Objects | Toothbrush | Cleaning | A |
| 15 | Objects | Bicycle | Transport | B |
| 16 | Objects | Backpack | Something you wear | A |
| 17 | Animals | Dolphin |  | B |
| 18 | Animals | Giraffe |  | A |
| 19 | Animals | Penguin |  | B |
| 20 | Animals | Snake |  | A |
| 21 | Professions | Lawyer |  | B |
| 22 | Professions | Pilot |  | A |
| 23 | Meals | Cake |  | B |
| 24 | Meals | Hot Dog |  | A |
| 25 | Objects | Ball | Sports | B |
| 26 | Objects | Chair | Furniture | A |
| 27 | Objects | Book | Education | B |
| 28 | Objects | Car | Transport | A |
| 29 | Animals | Monkey |  | B |
| 30 | Animals | Kangaroo |  | A |
| 31 | Animals | Eagle |  | B |
| 32 | Animals | Lion |  | A |

Additional object slides appearing after the experiment-ending slides are not included.

---

## Role-specific behavioural measures

The function retains two role configurations:

```text
A as Knower / B as Guesser
B as Knower / A as Guesser
```

These are summarized separately in `roleSummary`. This allows behavioural measures to be compared according to which participant was asking the questions and which participant was responding.

---

## Exploratory putative-completion measure

The EEG markers do not directly indicate whether the target word was correctly guessed. The function therefore creates an explicitly exploratory variable:

```text
PutativeOutcome
```

with four possible values:

```text
LikelyGuessedEarly
NearTimeLimit
EarlyEndUncertain
NoResponses
```

### `LikelyGuessedEarly`

The final response occurred before the near-time-limit threshold and was YES. This pattern is compatible with the Guesser correctly identifying the target before the time limit.

### `NearTimeLimit`

The final response occurred close to the nominal 60-s limit. With the default settings, responses at 55 s or later are classified as near the limit.

### `EarlyEndUncertain`

The trial ended before the near-time-limit threshold, but the final response was NO.

### `NoResponses`

No valid YES or NO markers were found in the trial.

`PutativeOutcome` must not be interpreted as verified task accuracy. The video recordings remain the appropriate source for determining whether a target was correctly guessed.

---

## Quality-control checks

A standard recording is expected to contain 32 `BlockStart` markers. By default, a recording with a different number is:

1. entered in the QC table;
2. skipped; and
3. followed by the next dyad.

The function also reports:

```text
missing files
loading failures
missing events
invalid event latencies
invalid sampling rates
mixed A-Knower and B-Knower markers within a trial
role-sequence mismatches
trials without responses
implausible trial durations
```

The batch continues after a problematic dyad.

---

## Basic usage

```matlab
[trialTable, dyadSummary, roleSummary, targetSummary, qcTable] = ...
    extract_behavioural_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35);
```

---

## Processing selected dyads

```matlab
[trialTable, dyadSummary, roleSummary, targetSummary, qcTable] = ...
    extract_behavioural_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    [1 2 3 10 20 35]);
```

---

## Changing the near-time-limit threshold

The default tolerance is 5 s, producing a 55-s threshold:

```text
60 − 5 = 55 s
```

To classify only responses at 57 s or later as near the time limit:

```matlab
[trialTable, dyadSummary, roleSummary, targetSummary, qcTable] = ...
    extract_behavioural_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    'NearTimeoutToleranceSec', 3);
```

---

## Processing irregular block counts

By default, recordings without exactly 32 `BlockStart` markers are skipped. To process the available blocks instead:

```matlab
[trialTable, dyadSummary, roleSummary, targetSummary, qcTable] = ...
    extract_behavioural_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    'SkipUnexpectedBlockCount', false);
```

When this option is disabled, the function processes only the number of trials for which both a `BlockStart` and target metadata are available.

---

## Optional arguments

| Option | Default | Description |
|---|---:|---|
| `OutputDir` | `rootDir` | Folder used to save the Excel and MAT outputs |
| `ExpectedBlocks` | `32` | Expected number of experimental trials |
| `TrialLimitSec` | `60` | Nominal maximum trial duration |
| `NearTimeoutToleranceSec` | `5` | Seconds before the limit used for the near-time-limit classification |
| `FirstKnower` | `'B'` | Participant expected to be Knower in the first trial |
| `SkipUnexpectedBlockCount` | `true` | Skip recordings with a nonstandard number of blocks |
| `WriteExcel` | `true` | Save the output tables to an Excel workbook |
| `Verbose` | `true` | Print processing information to the Command Window |

---

## Outputs

### `trialTable`

One row per valid trial. Important variables include:

```text
Dyad
DyadNumber
TrialNumber
Category
Target
Hint
ExpectedKnower
ExpectedGuesser
ObservedKnower
ObservedGuesser
RoleMatchesSchedule
FirstResponseTimeSec
TrialUseTimeSec
BlockStartToNextBlockSec
TransitionAfterLastResponseSec
NumYes
NumNo
NumResponses
YesProportion
ResponseRatePerMin
MeanInterResponseIntervalSec
MedianInterResponseIntervalSec
LastResponseType
LastResponseValence
SecondsBeforeNominalLimit
NearTimeLimit
PutativeEarlyCompletion
PutativeOutcome
QCFlag
SourceFile
```

### `dyadSummary`

One row per processed dyad, including trial duration, response counts, response timing, exploratory completion rates, and QC counts.

### `roleSummary`

One row per dyad and valid Knower/Guesser configuration.

### `targetSummary`

One row per target word summarized across processed dyads. This can be used to identify targets that required more time, elicited more questions, or more frequently approached the trial limit.

### `qcTable`

Contains recording- and marker-level quality-control information.

---

## Saved files

The function saves:

```text
HyperYESNO_behavioural_markers.xlsx
HyperYESNO_behavioural_markers.mat
```

The Excel workbook contains:

```text
TrialLevel
DyadSummary
RoleSummary
TargetSummary
QC
TargetSchedule
```

---

## Interpretation considerations

The behavioural measures are based on response-pad markers and assume that:

1. each `BlockStart` corresponds to the beginning of a trial;
2. the Knower registered every verbal YES or NO response;
3. the fixed target order was preserved across dyads;
4. the role sequence alternated according to the presentation; and
5. marker latencies remained aligned with the EEG data.

`NumResponses` should therefore be interpreted as the number of registered responses rather than a direct count of spoken questions.

`TrialUseTimeSec` measures the interval from trial onset to the final registered response. It does not include the time between the final response and advancement to the next trial.

The exploratory completion variables should be used cautiously and, where possible, validated against the video recordings.

---

## Recommended analysis strategy

The trial-level table should be retained as the primary behavioural dataset. Potential analyses include:

```text
trial duration across target words
number of responses across semantic categories
behavioural differences between A-as-Guesser and B-as-Guesser
change in duration or response rate across the experiment
association between behavioural measures and interbrain GCMI
association between behavioural measures and interaction ratings
```

The statistical unit for group-level analyses remains the dyad. Role-specific values should be treated as repeated observations nested within dyad rather than as independent participants.
