# dualbrainnetplot v5

This version replaces the previous dual-head `.spl`/`headplot` visualisation with a cleaner dual-brain visualisation.

The plot now uses a template brain mesh as an anatomical reference, places electrodes as floating markers outside the brain, and draws inter-brain links between participant A and participant B electrodes.

## Key design decision

For this figure, the `.spl` file is no longer necessary. The old `.spl` workflow is useful for EEGLAB `headplot` scalp interpolation, but the present figure is a 3-D network visualisation. It only needs:

1. an electrode-position structure or file, and
2. a brain mesh.

By default, the code tries to load FieldTrip's `standard_bem.mat` and extracts the innermost surface as the brain mesh. If FieldTrip is not available, it tries to find the same template through EEGLAB/DIPFIT.

## Main function

```matlab
handles = biPer_plot_interbrain_brainmesh_v5(connMatrix, electrodeInput, ...
    'ChannelLabels', channelLabels);
```

`connMatrix` must be an `N x N` matrix. Rows are electrodes from participant A and columns are electrodes from participant B.

The diagonal is valid and is plotted by default. In other words, `connMatrix(i,i)` is interpreted as the connection between electrode `i` in participant A and electrode `i` in participant B.

## Electrode input

The second input can be:

- `EEG.chanlocs`
- a full EEGLAB `EEG` structure
- a FieldTrip `elec` structure
- an electrode file readable by FieldTrip `ft_read_sens`
- an electrode file readable by EEGLAB `readlocs`
- the shortcut string `'fieldtrip:standard_1005.elc'`

If the electrode file contains more electrodes than the matrix, pass `ChannelLabels` so the function can select and order the correct electrodes.

## Example with FieldTrip template electrodes

```matlab
labels = {'Fp1','Fp2','F3','F4','C3','C4','P3','P4','O1','O2'};
connMatrix = zeros(numel(labels));
connMatrix(1,1) = 1;      % diagonal inter-brain link is valid
connMatrix(5,6) = 0.8;
connMatrix(6,5) = -0.7;

biPer_plot_interbrain_brainmesh_v5(connMatrix, 'fieldtrip:standard_1005.elc', ...
    'ChannelLabels', labels, ...
    'ThresholdType', 'nonzero', ...
    'PlotDiagonal', true);
```

## Example with your existing B2B pipeline

```matlab
handles = biPer_B2B_plot_stats_brainmesh_v5(EEG.chanlocs, ...
    'Measure', 'eeg_ccorr', ...
    'FreqIndex', 2);
```

or, if your channel labels match FieldTrip's template labels:

```matlab
handles = biPer_B2B_plot_stats_brainmesh_v5('fieldtrip:standard_1005.elc', ...
    'Measure', 'eeg_ccorr', ...
    'FreqIndex', 2);
```

## Coordinate modes

`CoordinateMode = 'native'` keeps the electrode positions in their supplied coordinate system after recentering them relative to the brain mesh. This is best when using FieldTrip template electrodes with the FieldTrip template head model.

`CoordinateMode = 'auto'` rescales the electrode cloud so it floats around the brain mesh. This is better for quick visualisation when the electrodes come from EEGLAB `chanlocs` in a non-MNI or unknown coordinate scale.

## Movie export

```matlab
biPer_plot_interbrain_brainmesh_v5(connMatrix, EEG.chanlocs, ...
    'MakeMovie', true, ...
    'MovieFile', 'dualbrain_connectivity.mp4');
```

## Files

- `biPer_plot_interbrain_brainmesh_v5.m` — main plotting function.
- `biPer_load_default_brain_mesh_v5.m` — loads FieldTrip/EEGLAB default brain mesh.
- `biPer_load_electrodes_v5.m` — converts EEGLAB/FieldTrip/file electrode inputs to one common format.
- `biPer_B2B_plot_stats_brainmesh_v5.m` — wrapper for the existing B2B stats pipeline.
- `demo_dualbrainnetplot_fieldtrip_v5.m` — minimal FieldTrip-template demo.

## Important caveat

This is a visualisation function, not a source-localisation coregistration pipeline. For source analysis, electrodes, head model, and source model must be in the same coordinate system and units. For visualisation, `CoordinateMode='auto'` can be useful because it produces a clean display even when channel locations are not fully coregistered.
