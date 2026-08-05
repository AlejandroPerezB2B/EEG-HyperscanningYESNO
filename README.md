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


````markdown
### Step 7: Role-normalized lagged GCMI analysis

`step7_run_lagged_GCMI_HyperYESNO.m` runs `lagged_gcmi_dyad.m` on the matched, role-normalized epoch files produced during Step 6.

The wrapper preserves the four experimental situations separately:

| Situation | Condition | Knower | Guesser |
|---|---|---|---|
| `YES_AKnower` | YES | Participant A | Participant B |
| `NO_AKnower` | NO | Participant A | Participant B |
| `YES_BKnower` | YES | Participant B | Participant A |
| `NO_BKnower` | NO | Participant B | Participant A |

The wrapper always passes the recordings to `lagged_gcmi_dyad.m` in the following order:

```matlab
dataA = Knower;
dataB = Guesser;
```

This role-normalized ordering remains constant regardless of whether the Knower originated from the `SubjA` or `SubjB` folder.

#### Input

The function loads the matched Step 6 epoch files from:

```text
DyadXX/GCMI_Epochs/SITUATION/
```

For example:

```text
Dyad01/GCMI_Epochs/YES_AKnower/
├── Dyad01_YES_AKnower_Knower_fromA.set
└── Dyad01_YES_AKnower_Guesser_fromB.set
```

For the reversed role assignment:

```text
Dyad01/GCMI_Epochs/YES_BKnower/
├── Dyad01_YES_BKnower_Knower_fromB.set
└── Dyad01_YES_BKnower_Guesser_fromA.set
```

Before running GCMI, the wrapper verifies that the Knower and Guesser datasets have:

- the same number of matched epochs;
- the same sampling rate;
- the same number of samples per epoch;
- the same epoch time vector;
- the same ROI labels and ROI order;
- the same paired-trial identifiers;
- the correct Knower and Guesser role metadata; and
- the same original marker latencies.

#### Filtering

No filtering is performed during Step 7.

The input data have already been filtered between 8 and 13 Hz during the preceding processing stage. The wrapper passes these data directly to `lagged_gcmi_dyad.m`.

The GCMI function itself also performs no filtering and assumes that the input data already contain the frequency band of interest.

By default, the wrapper checks the Step 6 metadata and requires the reported filter band to be:

```matlab
[8 13]
```

This verification can be controlled using:

```matlab
'ExpectedFilterBandHz', [8 13]
```

and:

```matlab
'RequireExpectedFilterBand', true
```

Setting:

```matlab
'RequireExpectedFilterBand', false
```

allows the calculation to continue when the filtering metadata are absent or differ from the expected values. This option does not apply any filtering; it only changes whether the metadata check is mandatory.

#### Trial handling

All available matched epochs are used independently within each situation.

The wrapper does not:

- balance the number of trials across conditions;
- balance the number of trials across role assignments;
- subsample the larger condition;
- discard trials to match the condition with the smallest number of epochs; or
- combine the two role configurations.

Therefore, the four situations may contain different numbers of trials:

```text
YES_AKnower
NO_AKnower
YES_BKnower
NO_BKnower
```

The exact number of trials used in every calculation is retained in the result file and in the Step 7 summary tables.

Within each situation, the Knower and Guesser must still have the same number of paired epochs.

#### Lag calculation

The requested lag values are supplied in milliseconds:

```matlab
'LagsMs', -500:50:500
```

The lag increment must be positive. Therefore, the intended MATLAB expression is:

```matlab
-500:50:500
```

and not:

```matlab
-500:-50:500
```

The GCMI function converts the requested millisecond values into integer sample offsets using:

```matlab
lagSamples = round(lagMilliseconds * samplingRate / 1000);
```

The source-level data are sampled at 100 Hz. Therefore:

```text
1 sample = 10 ms
50 ms    = 5 samples
500 ms   = 50 samples
```

The requested lag vector:

```matlab
-500:50:500
```

is consequently represented exactly as:

```matlab
-50:5:50
```

samples.

The wrapper independently calculates the expected sample offsets and verifies that they match the values returned by `lagged_gcmi_dyad.m`.

The complete lag vector contains 21 values:

```text
-500, -450, -400, ..., 0, ..., 400, 450, 500 ms
```

#### Lag-direction convention

`lagged_gcmi_dyad.m` uses the following convention:

```text
Negative lag = dataA precedes dataB
Positive lag = dataB precedes dataA
Zero lag     = simultaneous activity
```

Because Step 7 always passes:

```matlab
dataA = Knower;
dataB = Guesser;
```

the interpretation is:

```text
Negative lag = Knower precedes Guesser
Positive lag = Guesser precedes Knower
Zero lag     = simultaneous Knower–Guesser activity
```

This convention is stored in every output file and must be retained in later plotting and statistical analyses.

#### GCMI representation

Each ROI signal is represented by two dimensions:

```text
[ROI signal, temporal gradient]
```

The temporal gradient is calculated separately inside every epoch, preventing an artificial derivative between the final sample of one trial and the first sample of the next trial.

The function performs Gaussian-copula normalization separately for the signal and gradient dimensions and then calculates pairwise mutual information between every Knower ROI and every Guesser ROI.

With 20 ROIs for each participant, every lag produces a:

```text
20 × 20
```

Knower-to-Guesser connectivity matrix.

Across 21 lag values, the observed output has dimensions:

```matlab
20 × 20 × 21
```

#### Constant sample count across lags

The GCMI calculation uses the same number of observations at every lag.

For a maximum lag of 500 ms at 100 Hz, 50 samples are removed from both ends of each epoch before applying the relative temporal shift.

The number of usable samples per epoch is therefore:

```matlab
usableSamplesPerTrial = ...
    samplesPerTrial - 2 * maximumLagSamples;
```

The total number of observations entering each ROI-pair calculation is:

```matlab
numberOfObservationsPerLag = ...
    usableSamplesPerTrial * numberOfTrials;
```

This value is recorded separately for every dyad and experimental situation.

#### Surrogate calculations

Surrogates are created independently within each dyad and each of the four experimental situations:

```text
YES_AKnower
NO_AKnower
YES_BKnower
NO_BKnower
```

Within a situation, the Knower trial order remains fixed and the Guesser trial order is rearranged. Each rearrangement is a derangement:

```text
No Guesser epoch remains paired with its original Knower epoch.
```

The same permutation is applied to every Guesser ROI, the signal and temporal-gradient dimensions, and all samples within each epoch. The procedure therefore preserves each participant's within-trial spatial and temporal structure while disrupting the original Knower–Guesser trial correspondence.

`NumSurrogates` is interpreted as the requested maximum number of surrogates:

```matlab
'NumSurrogates', 499
```

The updated generator retains only unique permutations. The actual number of surrogates is adapted to the number of paired trials available in that specific dyad and situation:

```text
actual number = min(requested number, possible unique derangements)
```

For small trial counts, the complete derangement space is limited:

| Paired trials | Possible unique derangements |
|---:|---:|
| 2 | 1 |
| 3 | 2 |
| 4 | 9 |
| 5 | 44 |
| 6 | 265 |
| 7 | 1,854 |
| 8 | 14,833 |

Thus, when 499 surrogates are requested for a situation containing six trials, the function generates all 265 possible unique derangements rather than repeating permutations. With seven or more trials, 499 unique derangements can normally be sampled.

For small derangement spaces, all possible permutations are enumerated and sampled without replacement. For larger spaces, random derangements are generated while previously used permutations are tracked and rejected. A final validation confirms that no permutation contains a fixed point and that no two retained permutations are identical.

The following metadata document the procedure:

```matlab
results.numberOfSurrogatesRequested
results.numberOfSurrogatesGenerated
results.maximumUniqueDerangements
results.maximumUniqueDerangementsKnown
results.maximumUniqueDerangementsDisplay
results.allUniqueDerangementsUsed
results.surrogateGenerationMode
results.duplicateSurrogatePermutationsPrevented
results.surrogateGenerationAttempts
```

When the total number of possible derangements is larger than the requested number, the exact maximum is not calculated unnecessarily. In that case, `maximumUniqueDerangements` is `NaN`, `maximumUniqueDerangementsKnown` is `false`, and `maximumUniqueDerangementsDisplay` reports that the available number exceeds the requested value.

The surrogate distributions remain condition-specific: YES and NO epochs are never mixed, and A-Knower and B-Knower configurations are never combined during surrogate generation.

#### Vectorized calculation and runtime

The function does not call a separate GCMI calculation for each of the 400 ROI pairs.

Instead, all ROI-pair combinations are calculated simultaneously using vectorized matrix operations. Copula normalization and temporal-gradient calculation are performed once per situation and reused across the observed calculation and all surrogate permutations.

For one situation with 21 lags and 499 generated surrogates, the function calculates:

```text
21 × (1 observed + 499 surrogates)
= 10,500 complete 20 × 20 matrices
```

For all four situations:

```text
4 × 10,500
= 42,000 complete 20 × 20 matrices
```

Despite this number of matrices, the calculation can be relatively fast because the channel-pair computations are vectorized and MATLAB matrix operations may use multithreaded numerical libraries even when explicit parallel processing is disabled.

#### Parallel processing

Parallel processing is disabled by default:

```matlab
'UseParallel', false
```

When enabled:

```matlab
'UseParallel', true
```

the surrogate loop for each lag is executed using `parfor`.

This option requires the MATLAB Parallel Computing Toolbox.

For the current 20-ROI analysis, the serial vectorized implementation may already be sufficiently fast, so parallel processing should only be enabled after comparing its runtime and memory requirements.

#### Output structure

For every dyad and situation, the wrapper creates:

```text
DyadXX/Lagged_GCMI/SITUATION/
```

For example:

```text
Dyad01/Lagged_GCMI/YES_AKnower/
└── Dyad01_YES_AKnower_lagged_GCMI.mat
```

The output MAT file contains a `results` structure.

Important observed and surrogate outputs include:

```matlab
results.gcmiObserved
results.gcmiSurrogates
results.gcmiSurrogateMean
results.gcmiSurrogateStd
```

Their expected dimensions are:

```matlab
size(results.gcmiObserved)
% 20 × 20 × 21

size(results.gcmiSurrogates)
% 20 × 20 × 21 × numberOfSurrogates
```

Lag information is stored in:

```matlab
results.requestedLagsMilliseconds
results.lagsSamples
results.lagsMilliseconds
```

Data-size and trial information are stored in:

```matlab
results.samplingRate
results.samplesPerTrial
results.usableSamplesPerTrial
results.numberOfTrials
results.numberOfObservationsPerLag
results.numberOfChannelsA
results.numberOfChannelsB
```

ROI labels are stored in:

```matlab
results.channelLabelsA
results.channelLabelsB
```

The unique surrogate trial permutations and their generation metadata are stored in:

```matlab
results.surrogateTrialPermutations
results.numberOfSurrogatesRequested
results.numberOfSurrogatesGenerated
results.maximumUniqueDerangements
results.maximumUniqueDerangementsKnown
results.maximumUniqueDerangementsDisplay
results.allUniqueDerangementsUsed
results.surrogateGenerationMode
results.duplicateSurrogatePermutationsPrevented
results.surrogateGenerationAttempts
```

#### HyperYESNO metadata

The wrapper adds project-specific metadata under:

```matlab
results.hyperyesno
```

This includes:

```matlab
results.hyperyesno.dyad
results.hyperyesno.dyadName
results.hyperyesno.situation
results.hyperyesno.condition
results.hyperyesno.knowerParticipant
results.hyperyesno.guesserParticipant
results.hyperyesno.dataAAnalysisRole
results.hyperyesno.dataBAnalysisRole
results.hyperyesno.numberOfTrialsUsed
results.hyperyesno.pairIDs
results.hyperyesno.inputFilterBandHz
results.hyperyesno.filteringAppliedByWrapper
results.hyperyesno.trialBalancingApplied
results.hyperyesno.requestedLagsMilliseconds
results.hyperyesno.expectedLagSamplesFromSamplingRate
results.hyperyesno.lagConvention
results.hyperyesno.roleOrdering
results.hyperyesno.requestedNumSurrogates
results.hyperyesno.actualNumSurrogates
results.hyperyesno.maximumUniqueDerangements
results.hyperyesno.maximumUniqueDerangementsKnown
results.hyperyesno.maximumUniqueDerangementsDisplay
results.hyperyesno.allUniqueDerangementsUsed
results.hyperyesno.surrogateGenerationMode
results.hyperyesno.duplicateSurrogatePermutationsPrevented
```

The expected values include:

```matlab
results.hyperyesno.dataAAnalysisRole
% 'Knower'

results.hyperyesno.dataBAnalysisRole
% 'Guesser'

results.hyperyesno.filteringAppliedByWrapper
% false

results.hyperyesno.trialBalancingApplied
% false
```

#### Trial-count table

The function creates a compact table documenting how many trials and samples were used for every calculation:

```text
Step7_GCMI_trial_counts.xlsx
Step7_GCMI_trial_counts.mat
```

Each row corresponds to one dyad and one experimental situation.

The table includes:

- dyad number;
- experimental situation;
- YES or NO condition;
- Knower participant;
- Guesser participant;
- number of trials;
- samples per trial;
- usable samples per trial after lag trimming;
- number of observations per lag;
- sampling rate;
- epoch start and end;
- input filter band;
- requested lag range;
- actual sample offsets;
- actual lag values;
- requested and actually generated numbers of unique surrogates;
- maximum available derangements when known;
- surrogate-generation mode;
- result-file location;
- processing status; and
- elapsed calculation time.

A more detailed processing table is also created:

```text
Step7_lagged_GCMI_summary.xlsx
Step7_lagged_GCMI_summary.mat
```

#### Usage

Test one dyad and one situation without surrogates:

```matlab
eeglab;
close;

[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'Situations', 'YES_AKnower', ...
    'NumSurrogates', 0);
```

Test one dyad and one situation with up to 499 unique surrogates:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'Situations', 'YES_AKnower', ...
    'NumSurrogates', 499, ...
    'OverwriteExisting', true);
```

Run all four situations for one dyad:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'NumSurrogates', 499);
```

Run selected situations:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'Situations', { ...
        'YES_AKnower', ...
        'NO_AKnower'});
```

Enable parallel processing:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'NumSurrogates', 499, ...
    'UseParallel', true);
```

Process all dyads:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    'NumSurrogates', 499, ...
    'UseParallel', false, ...
    'OverwriteExisting', true);
```

Overwrite previously created result files:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1, ...
    'NumSurrogates', 499, ...
    'OverwriteExisting', true);
```

#### Dependencies

Step 7 requires:

- EEGLAB;
- `step7_run_lagged_GCMI_HyperYESNO.m`;
- `lagged_gcmi_dyad.m`;
- `copnorm.m` from Robin Ince's GCMI toolbox; and
- the MATLAB Parallel Computing Toolbox only when `UseParallel` is enabled.

No additional filtering toolbox is required during Step 7 because the input epochs have already been filtered into the 8–13 Hz alpha band.
````
