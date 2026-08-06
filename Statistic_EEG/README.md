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
4. Calculate cluster mass as the absolute sum of the t statistics within each cluster.
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
- An ROI-pair map of minimum cluster-corrected p values
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
