# Experiment EEG-Hyperscanning-YESNO

### Task and Procedure

Participants completed a dyadic yes/no guessing task/game similar to the Hedbanz board game. They were seated side by side at a shared workstation, each facing the screen of a laptop. Response pads were placed at the centre of the table, between the laptops. In each round, one participant (“Knower”) viewed a target word on the screen; the partner (“Guesser”) could not see the word and attempted to identify it by asking yes/no questions (the file "Picture of Experimental EEG hyperscannning.jpg" is a picture of the setup). Participants were instructed to ask relevant, information-seeking questions (e.g., “Does it meow?”; “Is it a pet?”) and to avoid elimination strategies based on unrelated or negated queries (e.g., “Is it not a bird?”). A printed sheet with suggested questions per category (´Question template for participants.docx´) was available as an optional aid. The Knower answered aloud and simultaneously registered each response on the response pad using role-specific keys for each participant. Button presses were sent as triggers to the EEG acquisition system. At the end of the round, the roles switched. The beginning of each turn was detected using a photodiode attached to one of the screens and also served as a trigger for the EEG.  

Stimuli were 32 target words drawn from four superordinate categories: Animals, Professions, Meals, and Objects. The "Guesser" received information about the category corresponding to the turn. Example items included dog, horse, lion (Animals); doctor, teacher, pilot (Professions); pizza, sushi, cake (Meals); and laptop, toothbrush, chair (Objects). In the case of the broader Object category, an additional hint was provided (e.g., "transport" for Object "car"). The presentation order of the target words was identical for all dyads. Each round lasted 60 seconds maximum. However, if a round concluded before (i.e., a correct guess), participants could advance immediately to the subsequent trial. Both partners shared control of the presentation to proceed and could advance the trial when ready (self-paced). The file "PowerPointHyperYESNO_Clean.pptx" is the presentation used.

Before the main task, participants completed two practice trials to familiarise themselves with the procedure and response pad. Sessions were also video-recorded with the laptops' front cameras. Participants were asked to keep their gaze on the screen and remain within the camera frame during the entire experiment. We also asked participants to fill out an "Interaction Rating Scale" (included here) at the end of the experiment.

An EEG hyperscanning setup was implemented using two 64-channel Neuvo amplifiers from NeuroScan. The file "SynAmpsRT - 2 subjects - Quik-Cap 64.xml" contains the workspace used for the recording. They can copy it to:
C:\Users\<user_name>\AppData\Roaming\Neuroscan\Curry 7\Acquisition\DeviceConfigurations

The AppData folder may be hidden.

The file "Acquisition configuration in Curry.png" is a screenshot showing an example of how the configuration could look in Curry.   
Find attached an example configuration that they can use to record data from two subjects. The idea is to use the same labels on both headboxes, but append "-2" to the labels on the second headbox.

Curry 7 cannot separate channels of two headboxes into different groups (unlike Curry 9), so they'd have to separate the data in post-processing.
The impedance check will work for both headboxes simultaneously. However, the location of the little impedance windows will not be nicely separated, so values from both caps will be displayed intertwined (unlike in Curry 9).

## Step1_preprocessing_HyperYESNO.m

Script to import, trigger extraction, trim, split, and save\
Minimal MATLAB script to load Curry EEG, decode triggers, trim, split by participants (A/B), and save EEGLAB sets per dyad.\
Cedrus response pads (model RB) were used to record the participant's YES/NO responses. The Trigger channel showed a number that we need to code. Along with that, we also need to decode the photodiod signal, marking the onset of the trial.

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

## Step2_loader_doingPREP.m

### Dependencies
- **PrepPipeline0.57.0** plugin

### Workflow
The PREP pipeline was used to: high-pass filter data at 1 Hz, detect bad channels, perform a robust average reference, and interpolate bad data.

### step2_summarise_PREP_bad_channels.m
Use it to scan all HyperYESNO PREP datasets and extract the channels detected as bad, interpolated, removed, or still noisy.

#### Outputs

- Participant-level summary
- Channel-frequency summary
- Channel indices and labels
- Descriptive statistics
- Results saved as `.xlsx` and `.mat` files

## step3_loader_doing_ASR_ICA.m

The following EEGLAB plugins must also be installed:

- **clean_rawdata** — used for Artifact Subspace Reconstruction (ASR)
- **Picard** — used to perform ICA
- **DIPFIT** — used for electrode coregistration and dipole fitting
- **ICLabel** — used to classify the independent components

### Main processing steps

1. Load the `_PREP.set` files for participants A and B.
2. Apply ASR independently to each participant.
3. Identify residual noisy time intervals.
4. Remove the union of rejected intervals from both participants.
5. Preserve the exact temporal synchronisation between participants.
6. Estimate the effective rank of each dataset.
7. Run Picard ICA using PCA rank reduction.
8. Coregister the electrode locations with the standard MNI head model.
9. Fit one equivalent dipole to each independent component using DIPFIT.
10. Classify the independent components using ICLabel.

### Output EEG files

The processed EEG datasets are saved as:

```text
DyadXX-A_PREP_ASR_ICA.set
DyadXX-B_PREP_ASR_ICA.set
```

### Summary files

The function creates a summary table containing information about:

- Samples rejected by ASR
- Percentage of data removed
- Number of interpolated channels
- Numerical and effective ICA rank
- Number of ICA components
- ICA, DIPFIT, and ICLabel processing times
- Processing status and errors

The summary table is saved as:

```text
Step3_ASR_ICA_summary.xlsx
Step3_ASR_ICA_summary.mat
```

### Example

```matlab
eeglab;
close;

summaryTable = step3_loader_doing_ASR_ICA( ...
    'E:\EEG_data_HyperYESNO', 1:35);
```

## step4_remove_eye_ICs_HyperYESNO.m

Automatically removes independent components classified by **ICLabel** as eye-related artifacts.

By default, components are removed when their Eye probability is **greater than 0.70**. Components with a probability exactly equal to `0.70` are retained.

### Main processing steps

1. Load the `_PREP_ASR_ICA.set` datasets for participants A and B.
2. Read the ICLabel classification probabilities.
3. Identify components classified as Eye above the selected threshold.
4. Remove these components using `pop_subcomp`.
5. Confirm that the number of samples and event latencies remain unchanged.
6. Save new cleaned datasets without modifying the original files.

### Output files

With the default threshold, the cleaned datasets are saved as:

```text
DyadXX-A_PREP_ASR_ICA_EYE70.set
DyadXX-B_PREP_ASR_ICA_EYE70.set
```

The function also saves a participant-level summary as:

```text
Step4_ICLabel_EYE70_summary.xlsx
Step4_ICLabel_EYE70_summary.mat
```

### Example

```matlab
summaryTable = step4_remove_eye_ICs_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', 1:35, 0.70, false);
```

## step5_source_LCMV_continuous_HyperYESNO.m

Converts the cleaned sensor-level EEG recordings into continuous source-level signals for 20 bilateral regions of interest (**COMM20**).

The following EEGLAB plugins are required:

- **DIPFIT**
- **ROIconnect**
- **FieldTrip** or **FieldTrip-lite**
- **MATLAB Signal Processing Toolbox**

The function preserves all experimental markers so that the source-level data can be epoched later according to the HyperYESNO conditions.

### Main processing steps

1. Load the `_PREP_ASR_ICA_EYE70.set` datasets for participants A and B.
2. Resample both recordings to **100 Hz** while preserving their synchronisation.
3. Generate a distributed Colin27 leadfield.
4. Calculate an LCMV spatial filter using ROIconnect.
5. Extract one principal component from each anatomical ROI.
6. Project the complete continuous EEG recording into 20 ROI signals.
7. Verify that event markers remain unchanged and aligned between participants.
8. Save the continuous source-level datasets.

### COMM20 network

The source network contains the left and right versions of the following regions:

- Pars opercularis
- Pars triangularis
- Superior temporal cortex
- Middle temporal cortex
- Transverse temporal cortex
- Supramarginal cortex
- Inferior parietal cortex
- Precentral cortex
- Rostral middle frontal cortex
- Precuneus

### Output files

The default source-level datasets are saved as:

```text
DyadXX-A_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
DyadXX-B_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
```

Each output dataset contains:

- 20 continuous ROI signals
- Preserved experimental events
- A default sampling rate of 100 Hz
- ROI labels instead of scalp-channel labels

The processing summary is saved as:

```text
Step5_LCMV_COMM20_continuous_summary.xlsx
Step5_LCMV_COMM20_continuous_summary.mat
```

Optional ROI-correlation quality-control figures can also be generated for each participant.

### Example

```matlab
eeglab;
close;

summaryTable = step5_source_LCMV_continuous_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', 1:35, ...
    'MakeQCFigures', false);
```

## step6_epoch_GCMI_HyperYESNO.m

Epochs the continuous source-level ROI datasets and prepares matched **Knower–Guesser** dataset pairs for later lagged-GCMI analysis.

The function processes four experimental situations:

- `YES_AKnower`
- `NO_AKnower`
- `YES_BKnower`
- `NO_BKnower`

The output files are organised by analytical role rather than participant identity. Therefore, the Knower dataset is always saved first and the Guesser dataset second.

### Main processing steps

1. Load the continuous `_LCMV_COMM20.set` datasets for participants A and B.
2. Confirm that both recordings have matching samples, ROI labels, events, and event latencies.
3. Optionally filter the continuous ROI signals before epoching.
4. Identify valid markers for each experimental situation.
5. Exclude epochs that extend outside the recording or cross a boundary event.
6. Remove the same invalid epochs from both participants.
7. Create identical trial-pair IDs for the Knower and Guesser datasets.
8. Optionally apply baseline correction.
9. Save the matched epoched datasets and trial-pair tables.

### Default input files

```text
DyadXX/SubjA/DyadXX-A_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
DyadXX/SubjB/DyadXX-B_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
```

### Output structure

The outputs are saved inside:

```text
DyadXX/GCMI_Epochs/
```

For example:

```text
DyadXX/GCMI_Epochs/YES_AKnower/
├── DyadXX_YES_AKnower_Knower_fromA.set
├── DyadXX_YES_AKnower_Guesser_fromB.set
└── DyadXX_YES_AKnower_trial_pairs.csv
```

Equivalent folders are created for:

```text
NO_AKnower
YES_BKnower
NO_BKnower
```

### Optional processing

The function supports:

- Continuous filtering before epoching
- Baseline correction after epoching
- Saving trial-pair tables
- Overwriting existing output files

Filtering is disabled by default.

### Summary files

The processing summary is saved in the HyperYESNO root directory as:

```text
Step6_GCMI_epoching_summary.xlsx
Step6_GCMI_epoching_summary.mat
```

### Example

```matlab
eeglab;
close;

summaryTable = step6_epoch_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    [-2 1], ...
    'FilterBand', [2 10]);
```

## step7_run_lagged_GCMI_HyperYESNO.m

Runs lagged Gaussian-Copula Mutual Information (**GCMI**) analysis on the matched Knower–Guesser epochs created in Step 6.

The following functions are required:

- `lagged_gcmi_dyad.m`
- `copnorm.m` from Robin Ince's GCMI toolbox

The **MATLAB Parallel Computing Toolbox** is required only when:

```matlab
'UseParallel', true
```

The function always provides the data to the function `lagged_gcmi_dyad.m` in the following order:

```text
dataA = Knower
dataB = Guesser
```

This ensures consistent role ordering across all dyads and experimental situations.

### Experimental situations

The function can process:

- `YES_AKnower`
- `NO_AKnower`
- `YES_BKnower`
- `NO_BKnower`

By default, all four situations are analysed.

### Lag convention

The lag convention is:

- **Negative lag:** the Knower precedes the Guesser.
- **Positive lag:** the Guesser precedes the Knower.
- **Zero lag:** simultaneous Knower and Guesser activity.

The default lag range is:

```text
-500:50:500 ms
```

At the default sampling rate of 100 Hz, this corresponds to:

```text
-50:5:50 samples
```

### Main processing steps

1. Load the matched Knower and Guesser datasets created in Step 6.
2. Verify that both datasets contain the same trials, ROI labels, sampling rate, epoch duration, and pair IDs.
3. Confirm the Knower–Guesser role metadata.
4. Verify that the input data were previously filtered between 8 and 13 Hz.
5. Convert the requested lag values from milliseconds to samples.
6. Run `lagged_gcmi_dyad` using all available matched trials.
7. Generate trial-permutation surrogate data.
8. Save the GCMI results and processing summaries.

### Trial handling

The function uses all available matched trials for each experimental situation.

It does not:

- Equalise the number of trials across conditions.
- Subsample trials.
- Match trial counts to the smallest condition.
- Balance A-Knower and B-Knower situations.

### Filtering

This function does not filter the EEG signals.

By default, it checks that the Step 6 metadata indicate that the data were previously filtered between:

```text
8–13 Hz
```

### Output files

One GCMI result file is saved for each dyad and experimental situation:

```text
DyadXX/Lagged_GCMI/SITUATION/
└── DyadXX_SITUATION_lagged_GCMI.mat
```

For example:

```text
Dyad01/Lagged_GCMI/YES_AKnower/
└── Dyad01_YES_AKnower_lagged_GCMI.mat
```

Each result file contains:

- Observed GCMI values
- Surrogate GCMI values
- Surrogate means and standard deviations
- Lag values in samples and milliseconds
- Number of trials
- Number of observations per lag
- HyperYESNO-specific processing metadata

### Summary files

The detailed processing summary is saved as:

```text
Step7_lagged_GCMI_summary.xlsx
Step7_lagged_GCMI_summary.mat
```

The trial-count summary is saved as:

```text
Step7_GCMI_trial_counts.xlsx
Step7_GCMI_trial_counts.mat
```

### Example

Run all four situations for one dyad:

```matlab
eeglab;
close;

[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1);
```

Run the complete dataset with 499 surrogates:

```matlab
[summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    1:35, ...
    'NumSurrogates', 499, ...
    'OverwriteExisting', true);
```

## lagged_gcmi_dyad.m

This is the function that calculates lagged Gaussian-copula mutual information (**GCMI**) between every channel in participant A and every channel in participant B. The function step7_run_lagged_GCMI_HyperYESNO.m is a wrapper for this.

The input data must be epoched and organised as:

```text
channels × samples × trials
```

Trial `k` in participant A must correspond to trial `k` in participant B.

The function requires:
- `copnorm.m` from Robin Ince's GCMI toolbox
- MATLAB Parallel Computing Toolbox is required if 'UseParallel', true\
No other external GCMI function is required because the two-dimensional Gaussian mutual-information calculation is implemented locally.

### Signal representation

Each EEG channel is represented using two dimensions:

```text
[channel signal, temporal gradient]
```

The temporal gradient is calculated separately within each epoch, avoiding artificial derivatives between consecutive trials.

### Main processing steps

1. Check that both participants have matching epoch lengths and trial counts.
2. Calculate the temporal gradient within each epoch.
3. Apply Gaussian-copula normalisation using `copnorm`.
4. Convert the requested lag values from milliseconds to samples.
5. Pool valid samples across trials while preserving epoch boundaries.
6. Calculate GCMI for every participant-A × participant-B channel pair.
7. Generate paired-trial permutation surrogates.
8. Return the observed and surrogate lagged-connectivity matrices.

### Lag convention

The function uses the following convention:

- **Negative lag:** participant A precedes participant B.
- **Positive lag:** participant B precedes participant A.
- **Zero lag:** simultaneous activity.

The default lag range is:

```text
-500:50:500 ms
```

The actual lag values depend on the sampling rate because lags must be represented as whole samples.

### Surrogate analysis

Surrogate datasets are generated by changing the trial order of participant B while leaving participant A unchanged.

Every surrogate permutation is a **derangement**, meaning that no participant-B trial remains paired with its original participant-A trial.

The function:

- Prevents duplicate surrogate permutations.
- Uses all possible derangements when fewer exist than requested.
- Preserves the complete within-participant structure of each epoch.
- Uses a reproducible random seed.

The default requested number of surrogates is:

```text
499
```

### Important assumptions

- The input datasets must contain the same number of paired trials.
- Both participants must have epochs of equal duration.
- The signals must already be filtered into the frequency band of interest.
- No filtering is performed by this function.
- A constant number of observations is used at every lag.
- Statistical thresholding is not performed automatically.

### Output

The returned `results` structure includes:

- `gcmiObserved`: observed channel × channel × lag GCMI values
- `gcmiSurrogates`: surrogate channel × channel × lag × surrogate values
- `gcmiSurrogateMean`: mean across surrogates
- `gcmiSurrogateStd`: standard deviation across surrogates
- `lagsSamples`: actual lags in samples
- `lagsMilliseconds`: actual lags in milliseconds
- `requestedLagsMilliseconds`: originally requested lag values
- `surrogateTrialPermutations`: trial order used for every surrogate
- `numberOfTrials`: number of paired trials
- `numberOfObservationsPerLag`: pooled observations used at each lag
- `channelLabelsA` and `channelLabelsB`: optional channel labels
- `settings`: analysis and surrogate-generation settings

### Example

```matlab
results = lagged_gcmi_dyad( ...
    EEG_A.data, ...
    EEG_B.data, ...
    EEG_A.srate, ...
    'LagsMs', -500:50:500, ...
    'NumSurrogates', 499, ...
    'ChannelLabelsA', {EEG_A.chanlocs.labels}, ...
    'ChannelLabelsB', {EEG_B.chanlocs.labels}, ...
    'OutputFile', 'dyad_lagged_gcmi.mat');
```
