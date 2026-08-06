## analyse_HyperYESNO_Curry_impedances.m

The `` function extracts and summarises electrode impedance values from the raw CURRY recordings of the HyperYESNO dataset.

Each CURRY acquisition contains the simultaneous recordings of one dyad. The function divides the channels into:

- Participant A: first half of the channels
- Participant B: second half of the channels

Mastoid channels (`M1` and `M2`) and trigger-related channels are excluded from the analysis.

### Main processing steps

1. Find all matching CURRY `.dat` or `.cdt` acquisition files.
2. Read impedance values from the associated CURRY header files.
3. Split each acquisition into participants A and B.
4. Convert impedance values to kΩ when necessary.
5. Use the final available impedance check as the best estimate of impedance before recording.
6. Create participant-level and channel-level summaries.
7. Detect channels with consistently high impedance.
8. Export all available impedance snapshots for further inspection.
9. Save summary tables and diagnostic figures.

### Default input folder

```text
E:\EEG_data_HyperYESNO\Raw_data_Neuroscan_McMaster
```

The function supports both legacy and newer CURRY formats:

```text
Legacy CURRY:
Acquisition ##.dat
Acquisition ##.dap
Acquisition ##.rs3

Newer CURRY:
Acquisition ##.cdt
Acquisition ##.cdt.dpa
Acquisition ##.cdt.dpo
```

### Main outputs

The returned `results` structure contains:

- `StartImpedanceKOhm`: participants × channels impedance table
- `ParticipantSummary`: participant-level impedance statistics
- `ChannelSummary`: channel-level statistics and likely bad-channel flags
- `AllSnapshotsLong`: all retained impedance measurements
- `SnapshotSummary`: summary of each impedance check
- `AcquisitionLog`: extraction and quality-control information
- `GlobalSummary`: dataset-level impedance statistics

For 35 dyads, the main impedance table should contain approximately 70 participant rows.

### Saved files

By default, the results are saved inside:

```text
Raw_data_Neuroscan_McMaster/Impedance_analysis/
```

The main output files are:

```text
HyperYESNO_Curry_impedance_analysis.mat
HyperYESNO_Curry_impedance_analysis.xlsx
```

The Excel workbook contains separate sheets for:

- Starting impedance values
- Participant summaries
- Channel summaries
- Impedance-check summaries
- All impedance snapshots
- Acquisition logs
- Global statistics
- Channel-name mappings

### Diagnostic figures

When figure generation is enabled, the function saves:

```text
01_start_impedance_heatmap.png
02_channel_median_impedance.png
03_impedance_snapshot_dynamics.png
```

### Bad-channel criterion

A fixed impedance cutoff can be provided manually.

When no cutoff is specified, the function calculates a robust data-driven cutoff using the median and median absolute deviation of the impedance values.

A channel is flagged as potentially problematic when it repeatedly exceeds the cutoff across participants or shows an unusually high median impedance.

### Requirements

- **MATLAB**
- Raw CURRY acquisition files and their associated header files

No EEGLAB plugin is required because the function reads the CURRY header files directly and does not load the complete EEG signal data.

### Example

Run the analysis using the default folder:

```matlab
results = analyse_HyperYESNO_Curry_impedances;
```

Specify the input folder:

```matlab
results = analyse_HyperYESNO_Curry_impedances( ...
    'E:\EEG_data_HyperYESNO\Raw_data_Neuroscan_McMaster');
```

Use a fixed 5-kΩ bad-channel cutoff:

```matlab
results = analyse_HyperYESNO_Curry_impedances( ...
    'E:\EEG_data_HyperYESNO\Raw_data_Neuroscan_McMaster', ...
    'BadCutoffKOhm', 5);
```
