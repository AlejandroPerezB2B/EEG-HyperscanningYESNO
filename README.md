# EEG-Hyperscanning-YESNO

## Methods

### Task and Procedure

Participants completed a dyadic yes/no guessing task/game similar to the Hedbanz board game. They were seated side by side at a shared workstation, each facing the screen of a laptop. A response pad was placed at the centre of the table, between the laptops. In each round, one participant (“Knower”) viewed a target word on the screen; the partner (“Guesser”) could not see the word and attempted to identify it by asking yes/no questions. Participants were instructed to ask relevant, information-seeking questions (e.g., “Does it meow?”; “Is it a pet?”) and to avoid elimination strategies based on unrelated or negated queries (e.g., “Is it not a bird?”). A printed sheet with suggested questions per category (template) was available as an optional aid. The Knower answered aloud and simultaneously registered each response on the response pad using role-specific keys for each participant. Button presses were sent as triggers to the EEG acquisition system. At the end of the round, the response pad was passed to the partner as roles switched. The beginning of each turn was detected using a photodiode attached to one of the screens and also served as a trigger for the EEG.  

Stimuli were 32 target words drawn from four superordinate categories (complete list in Supplementary Materials 1): Animals, Professions, Meals, and Objects. The "Guesser" received information about the category corresponding to the turn. Example items included dog, horse, lion (Animals); doctor, teacher, pilot (Professions); pizza, sushi, cake (Meals) and laptop, toothbrush, chair (Objects). In the case of the broader Object category, an additional hint was provided (e.g., "transport" for Object "car"). The presentation order of the target words was identical for all dyads. Each round lasted 60 seconds maximum. However, if a round concluded before (i.e., a correct guess), participants can advance immediately to the subsequent trial. Both partners shared control of the presentation to proceed and could advance the trial when ready (self-paced). Before the main task, participants completed two practice trials to familiarise themselves with the procedure and response pad. Sessions were also video-recorded with the laptops' front cameras. Participants were asked to keep their gaze on the screen and remain within the camera frame during the entire experiment.

## Step1_preprocessing_HyperYESNO.m

Script to import, trigger extraction, trim, split, and save\
Minimal MATLAB script to load Curry EEG, decode triggers, trim, split by participants (A/B), and save EEGLAB sets per dyad.
### Dependencies
- MATLAB + EEGLAB 2025.0.0
- **loadcurry 3.3.2** plugin
- `standard-10-5-cap385.elp` (EEGLAB resource)

### Workflow
- Load Curry files via `loadcurry` (**loadcurry 3.3.2** required).
- Decode triggers with `triggers_with_findpeaks.m`.
- Save snapshot (`.set`+`.fdt`, two-file), **resample to 250 Hz**.
- Remove trigger channel, **trim** to ≤5 s pre-first and post-last event.
- Split channels: `1–64 → SubjA`, `65–128 → SubjB`.
- Apply `standard-10-5-cap385.elp` to A; copy geometry to B (keep B impedances).
- Rename A: `I1` (ch 60), `I2` (ch 64). Remove `M1/M2`. Save to `DyadXX/SubjA` and `DyadXX/SubjB`.

### Trigger decoding (`triggers_with_findpeaks.m`)
Stores numeric **code** in `EEG.event.value` and string **label** in `EEG.event.type`.

Mapping:
```
100240→BlockStart
100241→YES_AKnower
100242→NO_AKnower
100244→YES_BKnower
100248→NO_BKnower
100243→resp3
100252→resp12
else → unknow
```
Also collapses consecutive `BlockStart`, renumbers `urevent`, warns if `>32` blocks.

## Step2_loader_doingPREP

### Dependencies
- **PrepPipeline0.57.0** plugin

### Workflow
The PREP pipeline was used to: high-pass filter data at 1 Hz, detect bad channels, perform a robust average reference, and interpolate bad data.
(https://www.frontiersin.org/articles/10.3389/fninf.2015.00016/full)
Remember to report in the paper how many channel removals were done.

### PREP bad-channel summary

`step2_summarise_PREP_bad_channels.m` scans all HyperYESNO PREP datasets and extracts the channels detected as bad, interpolated, removed, or still noisy.

#### Outputs

- Participant-level summary
- Channel-frequency summary
- Channel indices and labels
- Descriptive statistics
- Results saved as `.xlsx` and `.mat` files

## Step3_loader_doing_ICA_ASR

### Dependencies
- **ICLabel1.7**
- **Viewprops1.5.4**
- **clean_rawdata2.11**
- 
First, we used ICA (extended Infomax) specifically to identify eye movements on the recordings.
Then, we classified components using ICLabel; we removed only those with a high probability (>90%) of corresponding to blinks/saccades.
(ICLabel: Pion-Tonachini et al., NeuroImage 2019 — https://doi.org/10.1016/j.neuroimage.2019.05.026)
We back-project the non-eye ICs to obtain an “eye-clean” continuous dataset, which was submitted to ASR (clean_rawdata) to catch bursts/motion/muscle transients.
(ASR cites here)
Remember to report in the paper the number of windows repaired and the parameters used in the ASR.


## Step 3: Dyad-synchronised ASR, ICA, DIPFIT, and ICLabel

`step3_loader_doing_ASR_ICA.m` loads the exact `_PREP.set` datasets for both members of each dyad and applies ASR independently to participants A and B. ASR is configured to reconstruct burst-contaminated data using a conservative `BurstCriterion` of `20`. Residual windows that remain incompletely repaired are detected using `WindowCriterion = 0.30` and `WindowCriterionTolerances = [-Inf 7]`.

To preserve hyperscanning synchronisation, the union of the residual windows rejected for A and B is removed from both recordings. Therefore, both participants always retain exactly the same samples.

The function then estimates the effective data rank from the numerical rank, average reference, and PREP-interpolated channels; runs extended Infomax ICA with PCA rank reduction; fits one dipole per component using the standard MNI BEM model in DIPFIT; and runs ICLabel. Components are classified but are not automatically removed.

Final datasets are saved as:

- `DyadXX-A_PREP_ASR_ICA.set`
- `DyadXX-B_PREP_ASR_ICA.set`

The obsolete files named exactly `DyadXX-A_ICA.set` and `DyadXX-B_ICA.set`, together with their paired `.fdt` files, are deleted. A processing summary is saved as `Step3_ASR_ICA_summary.xlsx` and `Step3_ASR_ICA_summary.mat`.


## Lagged dyadic Gaussian-copula mutual information

### `lagged_gcmi_dyad`

The `lagged_gcmi_dyad` function calculates lagged Gaussian-copula mutual information (GCMI) between every EEG channel in participant A and every EEG channel in participant B.

The function operates on paired epoched data:

```matlab
dataA   % channels × samples × trials
dataB   % channels × samples × trials
srate   % sampling rate in Hz
```

Trial `k` in participant A must correspond to trial `k` in participant B.

### Analysis procedure

For each EEG channel, the default two-dimensional representation contains:

```text
EEG signal + temporal gradient
```

The gradient is calculated separately within each epoch, preventing artificial derivatives between consecutive trials.

The function then:

1. concatenates the selected epochs and applies `copnorm`;
2. restores the epoched structure;
3. aligns the two participants at each requested lag;
4. uses the same number of samples at every lag;
5. pools the valid samples across trials;
6. calculates the complete `channels A × channels B` GCMI matrix;
7. creates paired-trial permutation surrogates by deranging the trial order of participant B.

The same surrogate permutation is applied to all channels, preserving the complete spatial and temporal structure within each participant while destroying the original trial-to-trial dyadic correspondence.

### Lag convention

```text
Negative lag: participant A precedes participant B
Positive lag: participant B precedes participant A
Zero lag:     simultaneous activity
```

The default requested lag range is:

```matlab
-500:50:500  % milliseconds
```

Requested lags are converted to the nearest integer number of samples. The function stores both the requested and the actual lag values.

### Example

```matlab
results = lagged_gcmi_dyad( ...
    EEG_A.data, ...
    EEG_B.data, ...
    EEG_A.srate, ...
    'LagsMs', -500:50:500, ...
    'NumSurrogates', 19, ...
    'RandomSeed', 1, ...
    'ChannelLabelsA', {EEG_A.chanlocs.labels}, ...
    'ChannelLabelsB', {EEG_B.chanlocs.labels}, ...
    'UseParallel', false, ...
    'OutputFile', 'dyad_lagged_gcmi.mat');
```

### Main outputs

```matlab
results.gcmiObserved
% channelsA × channelsB × lags

results.gcmiSurrogates
% channelsA × channelsB × lags × surrogates

results.gcmiSurrogateMean
results.gcmiSurrogateStd

results.lagsSamples
results.lagsMilliseconds
results.requestedLagsMilliseconds

results.surrogateTrialPermutations
% trials × surrogates
```

GCMI values are expressed in bits. Surrogate means and standard deviations are descriptive outputs; the function does not automatically alter the observed GCMI values or apply statistical thresholds.

### Default options

```matlab
'LagsMs',        -500:50:500
'NumSurrogates', 19
'RandomSeed',    1
'UseParallel',   false
'OutputFile',    ''
'Verbose',       true
```

### External dependency

The only external function required is:

```text
copnorm.m
```

Place `copnorm.m` in the same folder as `lagged_gcmi_dyad.m`, or add Robin Ince's GCMI toolbox to the MATLAB path.

The two-dimensional Gaussian MI calculation and finite-sample bias correction are implemented locally in vectorised form. No separate calls to `mi_gg` are required.

### Important assumptions

- The data must already be filtered into the frequency band of interest.
- Only the EEG channels intended for analysis should be provided.
- Both participants must have the same number of samples per epoch.
- Both participants must have the same number of paired trials.
- Epoch boundaries are respected during lagging.
- A constant number of observations is used at every lag.
- The function calculates only cross-participant connectivity; within-brain connectivity is not calculated.


  ### Step 5: Continuous LCMV source reconstruction

`step5_source_LCMV_continuous_HyperYESNO.m` reconstructs continuous source-level signals for the HyperYESNO dyads while preserving the experimental event markers for later epoching and lagged GCMI analyses.

#### Input

The function loads the cleaned sensor-level datasets:

- `DyadXX-A_PREP_ASR_ICA_EYE70.set`
- `DyadXX-B_PREP_ASR_ICA_EYE70.set`

from the corresponding `SubjA` and `SubjB` folders.

#### Processing

For each participant, the function:

1. verifies that participants A and B have the same sampling rate, number of samples, and event latencies;
2. resamples synchronized copies to 100 Hz by default;
3. uses the corrected explicit MNI DIPFIT coregistration;
4. calculates the Colin27 leadfield with the Desikan–Killiany atlas;
5. estimates an LCMV spatial filter using the ROIconnect/Stefan Haufe `lcmv.m` implementation;
6. retains the three source orientations returned when `onedim = 0`;
7. estimates the first PCA direction within each selected anatomical ROI;
8. combines the LCMV and PCA filters into one sensor-to-ROI projection;
9. applies the projection to the complete continuous recording in memory-efficient blocks; and
10. verifies that the event types and event latencies remain unchanged.

The LCMV filter is returned as:

```matlab
channels × source_vertices × 3_orientations
```

For the current HyperYESNO data and Colin27 source model, the expected dimensions are normally:

```matlab
62 × 5003 × 3
```

The function explicitly reshapes this array to:

```matlab
62 × 15009
```

before selecting the three orientation columns belonging to each ROI vertex.

#### Source network

The output contains one continuous signal for each of 20 bilateral regions:

- pars opercularis;
- pars triangularis;
- superior temporal cortex;
- middle temporal cortex;
- transverse temporal cortex;
- supramarginal cortex;
- inferior parietal cortex;
- precentral cortex;
- rostral middle frontal cortex; and
- precuneus.

#### Output

The continuous ROI-level datasets are saved as:

- `DyadXX-A_PREP_ASR_ICA_EYE70_LCMV_COMM20.set`
- `DyadXX-B_PREP_ASR_ICA_EYE70_LCMV_COMM20.set`

The output remains a continuous EEGLAB dataset:

```matlab
EEG.data      % 20 ROIs × continuous samples
EEG.trials    % 1
EEG.event     % preserved experimental markers
EEG.urevent   % preserved original-event structure
EEG.srate     % 100 Hz by default
```

ICA and DIPFIT fields from the sensor-level dataset are removed from the active ROI dataset because they no longer describe the 20 source signals. The relevant sensor-level information and source-reconstruction parameters are retained as provenance in:

```matlab
EEG.etc.sensor_level_provenance
EEG.etc.source_reconstruction
EEG.roi
```

#### Requirements

- EEGLAB
- DIPFIT
- ROIconnect, specifically its `lcmv.m` function
- FieldTrip or FieldTrip-lite
- MATLAB Signal Processing Toolbox

The GCMI toolbox is not required for this step. Lagged GCMI will be calculated later, after the continuous source datasets have been epoched using the experimental markers.

#### Usage

Test one dyad:

```matlab
eeglab;
close;

summaryTable = step5_source_LCMV_continuous_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1);
```

Process all dyads:

```matlab
summaryTable = step5_source_LCMV_continuous_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    'MakeQCFigures', false);
```

Overwrite an existing test output:

```matlab
summaryTable = step5_source_LCMV_continuous_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'OverwriteExisting', true);
```

#### Quality control

The function creates:

- `Step5_LCMV_COMM20_continuous_summary.xlsx`
- `Step5_LCMV_COMM20_continuous_summary.mat`

Important checks include:

- `MarkersPreserved = true`;
- `NROIs = 20`;
- `SourceFinitePercent` close to 100%;
- `NNearZeroVarianceROIs = 0`;
- `SourceRank` close to 20;
- reasonable first-PC variance explained within each ROI; and
- inspection of the saved ROI-correlation matrices for excessive source redundancy or leakage.

### Step 6: Matched role-normalized epoching for lagged GCMI

`step6_epoch_GCMI_HyperYESNO.m` epochs the continuous source-level HyperYESNO datasets and creates matched Knower–Guesser dataset pairs for the subsequent lagged GCMI analysis.

The function reorganizes the data according to the experimental role of each participant rather than only according to the original `SubjA` and `SubjB` recording folders. This ensures that the later GCMI analysis can always load the Knower dataset first and the Guesser dataset second.

#### Input

By default, the function loads the continuous source-level datasets produced during Step 5:

- `DyadXX-A_PREP_ASR_ICA_EYE70_LCMV_COMM20.set`
- `DyadXX-B_PREP_ASR_ICA_EYE70_LCMV_COMM20.set`

The participant identity corresponds to the folder structure:

- participant A: `DyadXX/SubjA`
- participant B: `DyadXX/SubjB`

The input datasets must be continuous and must contain the original synchronized experimental event markers.

#### Experimental markers

The function processes four experimental situations:

| Marker | Condition | Knower | Guesser |
|---|---|---|---|
| `YES_AKnower` | YES | Participant A | Participant B |
| `NO_AKnower` | NO | Participant A | Participant B |
| `YES_BKnower` | YES | Participant B | Participant A |
| `NO_BKnower` | NO | Participant B | Participant A |

When participant A is the Knower, participant B is automatically assigned the Guesser role. When participant B is the Knower, participant A is assigned the Guesser role.

#### Processing

For each dyad, the function:

1. loads the continuous source-level datasets for participants A and B;
2. verifies that both recordings have:
   - the same sampling rate;
   - the same number of samples;
   - the same number and order of events;
   - identical event types;
   - identical event latencies;
   - the same ROI labels;
3. optionally filters the continuous ROI signals before epoching;
4. identifies the events corresponding to each of the four experimental situations;
5. determines a common set of valid marker latencies;
6. excludes observations when the requested epoch:
   - begins before the start of the recording;
   - finishes after the end of the recording; or
   - crosses an EEGLAB `boundary` event;
7. applies the same valid marker list to participants A and B;
8. creates matched epochs for the Knower and Guesser;
9. optionally applies baseline correction;
10. assigns a unique matched `pair_id` to every Knower–Guesser trial;
11. verifies that the Knower and Guesser files contain the same:
    - number of epochs;
    - sampling rate;
    - samples per epoch;
    - epoch time vector;
    - trial order;
    - pair IDs;
    - original marker latencies; and
12. saves the outputs using role-normalized filenames.

If an observation is invalid for either member of the dyad, it is excluded from both datasets.

#### Output structure

The function creates a `GCMI_Epochs` folder inside each dyad directory:

```text
DyadXX
├── SubjA
├── SubjB
└── GCMI_Epochs
    ├── YES_AKnower
    ├── NO_AKnower
    ├── YES_BKnower
    └── NO_BKnower

