# HyperYESNO response-marker behavioural extraction

## Overview

`extract_response_markers_HyperYESNO.m` extracts the minimal behavioural information that can be obtained reliably from the event markers stored in the combined HyperYESNO EEG recordings.

The function processes:

```text
E:\EEG_data_HyperYESNO\DyadXX\DyadXX.set
```

for the requested dyads.

The analysis intentionally does **not** depend on `BlockStart` markers. Several recordings contain missing or additional `BlockStart` events, so using them to reconstruct all 32 trials would require assumptions and would discard substantial amounts of data.

Instead, the function uses only the four response markers:

```text
YES_AKnower
NO_AKnower
YES_BKnower
NO_BKnower
```

These markers directly describe the registered YES and NO responses made by the Knower during the task.

The function does not estimate the number of correctly guessed targets. Correct identification of the target word should be coded from the video recordings.

---

## Main rationale

The EEG event stream provides an objective record of:

- how many YES responses were registered;
- how many NO responses were registered;
- which participant was the Knower;
- the timing of each registered response.

These measures describe the observable response behaviour of the dyad without requiring the unreliable reconstruction of every trial.

The most defensible primary measures are therefore:

```text
NumResponses
NumYes
NumNo
YesProportion
```

calculated for the complete dyad and separately for A as Knower and B as Knower.

Timing measures are also retained, but they should be interpreted cautiously because recordings may include interruptions, missing markers, or incomplete sessions.

## Expected folder structure

```text
E:\EEG_data_HyperYESNO
│
├── Dyad01
│   └── Dyad01.set
│
├── Dyad02
│   └── Dyad02.set
│
├── ...
│
└── Dyad35
    └── Dyad35.set
```

---

## Response markers

| Marker | Registered response | Knower | Guesser |
|---|---|---|---|
| `YES_AKnower` | YES | A | B |
| `NO_AKnower` | NO | A | B |
| `YES_BKnower` | YES | B | A |
| `NO_BKnower` | NO | B | A |

The function also recognizes the original numeric Curry codes:

| Numeric code | Marker |
|---:|---|
| `100240` | `BlockStart` |
| `100241` | `YES_AKnower` |
| `100242` | `NO_AKnower` |
| `100244` | `YES_BKnower` |
| `100248` | `NO_BKnower` |

`BlockStart` is counted for quality-control purposes only. It is not used to define trials or calculate behavioural measures.

---

## Marker runs

The function creates a secondary descriptive unit called a **marker run**.

A marker run is a consecutive sequence of response markers belonging to the same Knower. A new run begins when:

```text
the Knower changes from A to B
or
the Knower changes from B to A
```

An optional maximum temporal gap can also be used to split a run.

For example:

```text
YES_AKnower
NO_AKnower
YES_AKnower
YES_BKnower
NO_BKnower
```

is divided into:

```text
Run 1: three A-Knower responses
Run 2: two B-Knower responses
```

### Important limitation

A marker run is not treated as a verified experimental trial.

Because the role alternated between trials, a change in Knower is compatible with a transition to the next trial. However, a trial with no recorded responses could cause two separate trials to be merged into one run.

Run-based measures are therefore secondary descriptive measures rather than direct trial measures.

They are retained because they provide a limited normalization of response counts without depending on the unreliable `BlockStart` sequence.

---

## Extracted response-level measures

The `responseTable` contains one row per valid YES or NO marker.

Important variables include:

```text
Dyad
DyadNumber
ResponseIndex
MarkerType
Response
Knower
Guesser
RunNumber
LatencySamples
TimeFromRecordingStartSec
IntervalFromPreviousResponseSec
SourceFile
```

### `Response`

The registered response:

```text
YES
NO
```

### `Knower` and `Guesser`

The participant roles derived directly from the marker label.

### `TimeFromRecordingStartSec`

The marker latency converted from samples to seconds.

### `IntervalFromPreviousResponseSec`

The interval between the current response and the preceding response marker in the recording.

The first response has a missing value because no preceding response exists.

---

## Run-level measures

The `runTable` contains one row per consecutive same-Knower marker run.

It includes:

```text
RunNumber
Knower
Guesser
StartTimeSec
EndTimeSec
RunSpanSec
NumYes
NumNo
NumResponses
YesProportion
MeanInterResponseIntervalSec
MedianInterResponseIntervalSec
ResponseRatePerMin
```

### `RunSpanSec`

The interval between the first and last response marker in the run.

This does not include the time from trial onset to the first response and should not be interpreted as complete trial duration.

### `NumResponses`

The total number of registered responses in the run.

### `YesProportion`

```text
NumYes / NumResponses
```

### Inter-response intervals

These describe the timing between consecutive registered responses within the same run.

---

## Dyad-level measures

The `dyadSummary` contains one row per dyad.

The principal variables are:

```text
NumResponses
NumYes
NumNo
YesProportion
```

Additional descriptive variables include:

```text
ResponseActiveSpanSec
ResponsesPerActiveMinute
MeanInterResponseIntervalSec
MedianInterResponseIntervalSec

NumMarkerRuns
MeanResponsesPerRun
MedianResponsesPerRun
MeanRunSpanSec
MedianRunSpanSec
```

### Primary interpretation

The response counts are the most direct behavioural measures available from the EEG markers.

A larger number of responses indicates that more YES/NO exchanges were registered during the recorded task. It does not directly indicate better or worse performance because more questions may reflect either sustained engagement or greater difficulty identifying the target.

### `ResponseActiveSpanSec`

The interval between the first and last valid response marker in the recording.

This is preferable to using the entire EEG recording duration, but it can still be affected by pauses, interruptions, incomplete sessions, or technical problems.

### `ResponsesPerActiveMinute`

The total number of responses divided by `ResponseActiveSpanSec`.

This value is descriptive and should not be treated as a pure response-speed measure when recordings contain interruptions.

---

## Role-specific measures

The `roleSummary` contains two rows per dyad:

```text
A as Knower / B as Guesser
B as Knower / A as Guesser
```

The summary variables are calculated separately for each Knower.

This allows the response behaviour to be compared depending on which participant was asking questions and which participant was providing YES/NO answers.

Role-specific rows are repeated observations from the same dyad and should not be treated as independent participants.

---

## Measures not estimated by this function

### Number of correctly guessed targets

The response markers do not establish whether the Guesser identified the exact target word.

A participant may receive several positive responses while approaching the target without identifying it correctly. Therefore, the final YES response, YES proportion, response count, and response timing are not used to infer successful guessing.

Target accuracy should be coded from the video recordings.

### Trial duration

The function does not calculate the time from `BlockStart` to the final response because the `BlockStart` sequence is inconsistent across several recordings.

### Number of completed trials

Marker runs are not counted as confirmed completed trials.

---

## Basic usage

```matlab
[responseTable, runTable, dyadSummary, roleSummary, qcTable] = ...
    extract_response_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35);
```

---

## Processing selected dyads

```matlab
[responseTable, runTable, dyadSummary, roleSummary, qcTable] = ...
    extract_response_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    [1 4 5 8 9 14 16 17 22 28 30]);
```

---

## Optional temporal splitting of marker runs

By default, a marker run is split only when the Knower changes:

```matlab
'MaxWithinRunGapSec', Inf
```

A maximum gap can be introduced if inspection of the data supports a defensible threshold.

For example, to start a new run when two responses from the same Knower are separated by more than 70 seconds:

```matlab
[responseTable, runTable, dyadSummary, roleSummary, qcTable] = ...
    extract_response_markers_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    'MaxWithinRunGapSec', 70);
```

The default is recommended until the response-interval distribution has been examined because an arbitrary threshold could incorrectly split or merge parts of the interaction.

---

## Optional arguments

| Option | Default | Description |
|---|---:|---|
| `OutputDir` | `rootDir` | Folder used to save the output files |
| `MaxWithinRunGapSec` | `Inf` | Optional gap used to split same-Knower runs |
| `WriteExcel` | `true` | Save the tables to an Excel workbook |
| `Verbose` | `true` | Print processing information |

---

## Quality control

The function reports:

```text
missing files
loading failures
invalid sampling rates
datasets without events
invalid event latencies
datasets without valid response markers
nonstandard BlockStart counts
```

A nonstandard number of `BlockStart` markers is reported for documentation but does not cause exclusion.

The function continues with the next dyad after a problem.

---

## Output files

The function saves:

```text
HyperYESNO_response_marker_behaviour.xlsx
HyperYESNO_response_marker_behaviour.mat
```

The Excel workbook contains:

```text
Responses
MarkerRuns
DyadSummary
RoleSummary
QC
```

---

## Table-construction approach

The function uses structure arrays and `struct2table`.

It does not use:

```text
cell2table
cell2mat
```

This simplifies variable typing and avoids the table-conversion error encountered in the earlier block-based function.

---

## Recommended analysis strategy

The most defensible main behavioural variables are:

```text
NumResponses
NumYes
NumNo
YesProportion
```

These can be analysed at the dyad level and separately by Knower.

The following variables are better treated as secondary or exploratory:

```text
ResponsesPerActiveMinute
NumMarkerRuns
MeanResponsesPerRun
MedianResponsesPerRun
MeanRunSpanSec
MedianRunSpanSec
```

Associations between these behavioural measures and interpersonal EEG measures should retain the dyad as the statistical unit.

The marker-derived measures describe registered response behaviour. They should not be described as accuracy, number of successful trials, or number of correctly guessed words.
