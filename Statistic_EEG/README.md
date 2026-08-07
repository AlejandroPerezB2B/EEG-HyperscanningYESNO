## step10_cluster_permutation_GCMI_HyperYESNO.m

Performs the group-level statistical analysis of the primary surrogate-corrected YES–NO GCMI contrast created in Step 9.

The statistical unit is the **dyad**.

### Input contrast

The principal analysis uses:

```matlab
step9Data.yesMinusNoPrimary
```

This contrast is defined as:

```text
0.5 × [(YES_AKnower − NO_AKnower) +
       (YES_BKnower − NO_BKnower)]
```

The input array has the following dimensions:

```text
Knower ROI × Guesser ROI × Lag × Dyad
```

### Statistical approach

The function performs a two-sided sign-flip cluster permutation test:

1. Calculate a one-sample t statistic against zero for every Knower ROI × Guesser ROI × lag combination.
2. Identify positive and negative supra-threshold clusters.
3. Form clusters across adjacent lag samples within each ROI pair.
4. Calculate cluster mass as the absolute sum of the t-statistics within each cluster.
5. Randomly reverse the sign of each dyad's complete YES–NO contrast.
6. Retain the maximum cluster mass across all ROI pairs, lags, and signs for each permutation.
7. Compare the observed clusters with the maximum-cluster null distribution.

No spatial adjacency is imposed between different ROI pairs. Clustering is performed only across consecutive lag values within each ROI pair.

### Multiple-comparison correction

The maximum-cluster permutation procedure controls the family-wise error rate across the complete analysis:

```text
20 Knower ROIs × 20 Guesser ROIs × 21 lags
```

Positive and negative clusters are tested together using the same two-sided null distribution.

### Sign-flip permutations

The function generates unique sign patterns and prevents duplicate permutations.

To avoid equivalent global sign inversions:

- The first dyad is fixed to `+1`.
- The all-positive pattern corresponding to the observed data is excluded.
- A sign pattern and its complete inverse are treated as equivalent.

If fewer unique sign patterns exist than requested, all available patterns are used.

### Default settings

```text
Number of permutations:       10,000
Cluster-forming alpha:        0.05
Family-wise alpha:            0.05
Random seed:                  20260805
Permutation batch size:       200
Minimum number of dyads:      10
```

### Lag convention

- **Negative lag:** the Knower precedes the Guesser.
- **Positive lag:** the Guesser precedes the Knower.

### Main outputs

The function returns:

- `step10Data`: statistical maps, permutation results, masks, and metadata
- `clusterTable`: one row per observed supra-threshold cluster
- `qcTable`: dyads excluded from the analysis and the reason for exclusion

Important fields in `step10Data` include:

- `analysisData`
- `analysisDyadNumbers`
- `groupMean`
- `groupSD`
- `groupSEM`
- `observedT`
- `pointwiseParametricP`
- `clusterFormingThresholdT`
- `nullMaximumClusterMass`
- `significantClusterMask`
- `significantPairMask`
- `minimumClusterPByROIPair`
- `signedPeakTByROIPair`
- `peakLagMsByROIPair`
- `signPatterns`

### Cluster table

For every observed cluster, `clusterTable` reports:

- Knower and Guesser ROI
- Cluster sign
- Start and end lag
- Number of included lags
- Cluster mass
- Peak t statistic
- Peak lag
- Mean effect within the cluster
- Cluster-corrected p value
- Family-wise significance status

### Dyad inclusion

A dyad is included only when:

- Step 9 marked its primary contrast as valid.
- All ROI-pair and lag values are finite.
- The total number of complete dyads meets the minimum requirement.

Excluded dyads are documented in `qcTable`.

### Saved files

By default, the numerical outputs are saved in:

```text
E:\EEG_data_HyperYESNO\Group_GCMI
```

The saved files are:

```text
Step10_HyperYESNO_primary_cluster_permutation.mat
Step10_HyperYESNO_primary_cluster_permutation.xlsx
```

The Excel workbook contains:

- `Clusters`
- `QC`
- `AnalysisDyads`
- `Settings`

### Figures

Figures are saved by default in:

```text
Group_GCMI/Step10_Figures
```

The function generates:

- An ROI-pair summary of signed peak t-statistics
- An ROI-pair map of minimum cluster-corrected p-values
- The permutation null distribution of maximum cluster mass
- A lag profile for every FWER-significant cluster

Supported figure formats are:

```text
PNG
PDF
SVG
```

### Example

```matlab
[step10Data, clusterTable, qcTable] = ...
    step10_cluster_permutation_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO');
```

Run the analysis without saving figures:

```matlab
[step10Data, clusterTable, qcTable] = ...
    step10_cluster_permutation_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'SaveFigures', false);
```

Use a different number of permutations:

```matlab
[step10Data, clusterTable, qcTable] = ...
    step10_cluster_permutation_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'NumPermutations', 5000);
```

## visualize_lag_peaks_GCMI_HyperYESNO.m

The function provides a descriptive analysis of the lag at which different HyperYESNO GCMI measures reach their peak.

This function complements Steps 9 and 10 but does **not** replace the cluster-based permutation analysis performed in Step 10.

### Purpose

Step 10 evaluates statistical significance across all lags using cluster-based permutation testing.

This visualisation function instead asks descriptive questions such as:

- At which lag is corrected GCMI largest?
- Do peak values tend to occur when the Knower precedes the Guesser?
- Do individual dyads show similar peak-lag patterns?
- Which ROI pairs tend to peak at negative, zero, or positive lags?

These peak estimates are descriptive. Inferential conclusions should be based on the Step 10 cluster-corrected results.

### Available measures

The function supports several GCMI measures.

#### `CorrectedOverall`

Equal-weighted mean of corrected YES and corrected NO GCMI:

```text
0.5 × (corrected YES role mean + corrected NO role mean)
```

This is the most direct measure for asking when overall interpersonal GCMI is largest.

#### `CorrectedYES`

Surrogate-corrected GCMI during YES responses, averaged across the two Knower roles.

#### `CorrectedNO`

Surrogate-corrected GCMI during NO responses, averaged across the two Knower roles.

#### `PrimaryContrast`

Primary surrogate-corrected YES-minus-NO contrast.

This identifies the lag at which the YES–NO difference is largest rather than the lag at which GCMI itself is largest.

#### `AKnowerContrast`

A-Knower surrogate-corrected YES-minus-NO contrast.

#### `BKnowerContrast`

B-Knower surrogate-corrected YES-minus-NO contrast.

### Peak criteria

Three peak-selection criteria are available.

#### `maximum`

Selects the largest signed value across lags.

This is recommended for corrected GCMI measures.

#### `maximumabsolute`

Selects the value with the largest absolute magnitude while retaining its original sign.

This is recommended for two-sided YES-minus-NO contrasts.

#### `auto`

Automatically selects:

```text
maximum          → corrected GCMI measures
maximumabsolute  → YES-minus-NO contrasts
```

This is the default option.

### Lag convention

```text
Negative lag = Knower precedes Guesser
Zero lag     = no temporal offset
Positive lag = Guesser precedes Knower
```

### Main processing steps

1. Load the Step 9 surrogate-corrected GCMI results.
2. Select the requested GCMI measure.
3. Identify complete dyads for that measure.
4. Optionally restrict the analysis to the dyads included in Step 10.
5. Calculate the group-average lag profile for every ROI pair.
6. Identify the peak lag and peak value for every ROI pair.
7. Calculate peak lags separately for every dyad and ROI pair.
8. Summarise the distribution of negative, zero, and positive peak lags.
9. Calculate a global lag profile across all ROI pairs.
10. Save numerical summaries and descriptive figures.

### Dyad selection

By default:

```matlab
'UseStep10Dyads', true
```

When the Step 10 result file is available, the visualisation is restricted to the dyads included in the Step 10 statistical analysis.

This ensures that descriptive figures and inferential analyses are based on the same set of dyads.

### Main outputs

The function returns:

- `peakData`
- `pairTable`
- `dyadTable`
- `dyadPairTable`

#### `peakData`

Contains numerical peak maps, individual-dyad peak arrays, global lag profiles, and analysis metadata.

Important fields include:

- `groupMean`
- `groupSEM`
- `groupPeakValue`
- `groupPeakLagMs`
- `groupPeakDirection`
- `dyadPeakValue`
- `dyadPeakLagMs`
- `medianDyadPeakLagMs`
- `meanDyadPeakLagMs`
- `negativePeakProportion`
- `zeroPeakProportion`
- `positivePeakProportion`
- `dyadPeakLagProportions`
- `globalLagMean`
- `globalLagSEM`
- `globalPeakValue`
- `globalPeakLagMs`
- `globalPeakDirection`

#### `pairTable`

Contains one row for every:

```text
Knower ROI × Guesser ROI
```

It reports information such as:

- Group peak lag
- Group peak value
- Peak direction
- Median individual-dyad peak lag
- Mean individual-dyad peak lag
- Proportion of negative peaks
- Proportion of zero-lag peaks
- Proportion of positive peaks
- Dominant peak direction

#### `dyadTable`

Contains one row per analysed dyad.

It summarizes:

- Median peak lag across ROI pairs
- Mean peak lag across ROI pairs
- Proportion of negative peaks
- Proportion of zero-lag peaks
- Proportion of positive peaks
- Dominant temporal direction

#### `dyadPairTable`

Contains one row for every:

```text
Dyad × Knower ROI × Guesser ROI
```

It reports the selected peak lag, peak value, and temporal direction for every ROI pair within every dyad.

### Saved outputs

By default, outputs are saved in:

```text
E:\EEG_data_HyperYESNO\Group_GCMI\Lag_Peak_Visualizations
```

The filenames depend on the selected measure and peak criterion.

For example:

```text
LagPeaks_CorrectedOverall_maximum.mat
LagPeaks_CorrectedOverall_maximum.xlsx
```

The Excel workbook contains:

- `ROIPairSummary`
- `DyadSummary`
- `DyadROIPairPeaks`
- `GlobalLagProfile`

### Figures

The function generates several descriptive figures.

#### Group peak-lag heatmap

Displays the peak lag for every Knower ROI × Guesser ROI pair.

#### Group peak-value heatmap

Displays the GCMI value at the selected peak lag.

#### Median individual peak-lag heatmap

Displays the median peak lag across individual dyads for every ROI pair.

#### Direction-proportion maps

Three maps show the proportion of dyads whose peak occurs at:

- Negative lag: Knower precedes Guesser
- Zero lag
- Positive lag: Guesser precedes Knower

#### Dyad-by-lag peak distribution

Shows, for every dyad, the proportion of ROI pairs whose peak occurs at each lag.

#### Global lag profile

Averages the selected measure across all ROI pairs and displays its mean and SEM across dyads as a function of lag.

The global peak lag is explicitly marked.

### Supported figure formats

```text
PNG
PDF
SVG
```

The default format is:

```text
PNG
```

### Examples

Visualise the peak of overall surrogate-corrected GCMI:

```matlab
[peakData, pairTable, dyadTable, dyadPairTable] = ...
    visualize_lag_peaks_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'Measure', 'CorrectedOverall');
```

Visualise the peak of corrected GCMI during YES responses:

```matlab
[peakData, pairTable, dyadTable, dyadPairTable] = ...
    visualize_lag_peaks_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'Measure', 'CorrectedYES');
```

Visualise the strongest primary YES-minus-NO effect:

```matlab
[peakData, pairTable, dyadTable, dyadPairTable] = ...
    visualize_lag_peaks_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'Measure', 'PrimaryContrast', ...
    'PeakCriterion', 'maximumabsolute');
```

Run the analysis without restricting it to the Step 10 dyad set:

```matlab
[peakData, pairTable, dyadTable, dyadPairTable] = ...
    visualize_lag_peaks_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'Measure', 'CorrectedOverall', ...
    'UseStep10Dyads', false);
```

Run the analysis without saving figures:

```matlab
[peakData, pairTable, dyadTable, dyadPairTable] = ...
    visualize_lag_peaks_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'SaveFigures', false);
```
