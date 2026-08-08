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

## Step 10b — Spatial cluster-based permutation analysis

**Function:** `step10b_spatial_cluster_permutation_GCMI_HyperYESNO.m`

This function performs a spatial cluster-based permutation analysis of the surrogate-corrected **YES–NO lagged GCMI difference**.

It is an alternative and complementary analysis to the original Step 10. Whereas the original Step 10 forms clusters across adjacent lags within each ROI pair, Step 10b analyses each lag separately and forms clusters across anatomically neighbouring **inter-brain connections**.

### Input contrast

The function uses the primary dyad-level contrast generated in Step 9:

```matlab
step9Data.yesMinusNoPrimary
```

defined as:

```text
0.5 × [(YES_AKnower − NO_AKnower) +
       (YES_BKnower − NO_BKnower)]
```

The **dyad is the statistical unit**.

The sign of the contrast is therefore interpreted as:

```text
positive value → surrogate-corrected GCMI is larger for YES than NO
negative value → surrogate-corrected GCMI is larger for NO than YES
```

---

### Independent analysis of each lag

The lag dimension is not used to form clusters.

Each lag is analysed independently:

```text
-500 ms
-450 ms
...
0 ms
...
+450 ms
+500 ms
```

A spatial cluster can therefore never extend from one lag to another.

At each lag, the complete `20 × 20` Knower-ROI × Guesser-ROI connectivity matrix is analysed independently.

---

### Anatomical ROI neighbourhood

The 20 source ROIs correspond to parcels from the **Desikan–Killiany cortical parcellation**.

Two ROIs are considered neighbours only when their cortical parcels **share a boundary on the cortical surface**.

This relationship is derived from the FreeSurfer `fsaverage` cortical mesh. Two parcels are considered adjacent when at least one triangular-mesh edge directly connects:

- a vertex belonging to the first parcel, and
- a vertex belonging to the second parcel.

Euclidean distance between ROI centroids is therefore **not** used to determine anatomical adjacency.

Left- and right-hemisphere parcels are not considered neighbours across the interhemispheric fissure.

---

### Inter-brain connection neighbourhood

Spatial clustering is performed over **inter-brain connections**, rather than individual ROIs.

For an inter-brain connection:

```text
Knower ROI i → Guesser ROI j
```

another connection is considered adjacent when one endpoint remains identical and the other changes to an anatomically neighbouring ROI.

For example:

```text
(i,j) ~ (k,j)
```

when Knower ROIs `i` and `k` are anatomical neighbours.

Similarly:

```text
(i,j) ~ (i,l)
```

when Guesser ROIs `j` and `l` are anatomical neighbours.

Connections in which **both endpoints change simultaneously** are not directly considered neighbours.

This provides a conservative endpoint-wise definition of spatial adjacency.

---

### Statistical procedure

At each lag independently, the function:

1. Calculates a one-sample t statistic against zero for each of the 400 inter-brain ROI connections.
2. Applies a two-sided cluster-forming threshold.
3. Identifies supra-threshold connections.
4. Forms positive and negative spatial clusters separately.
5. Groups connections according to the anatomical connection-neighbour graph.
6. Calculates cluster mass as:

```text
absolute cluster mass = |sum of t values within the cluster|
```

7. Generates a permutation null distribution by sign-flipping the complete YES–NO connectivity map of each dyad.

During each permutation, the same sign is applied to all ROI pairs and all lags belonging to a particular dyad.

The default settings are:

```matlab
'NumPermutations',      10000
'ClusterFormingAlpha',  0.05
'FamilyWiseAlpha',      0.05
'RandomSeed',           20260807
'PermutationBatchSize', 200
'MinimumDyads',         10
```

---

### Spatial FWER correction within each lag

For every permutation and every lag, the largest spatial cluster mass observed anywhere in the `20 × 20` connectivity matrix is retained.

The corresponding corrected p-value is:

```matlab
SpatialFWERWithinLagP
```

This controls the family-wise error rate across all inter-brain connections **within that particular lag**.

The corresponding output matrices are:

```matlab
spatialData.spatialFWERWithinLagPMap
spatialData.significantSpatialWithinLagMask
```

with dimensions:

```text
Knower ROI × Guesser ROI × Lag
```

This analysis answers:

> At this particular lag, is the spatial YES–NO cluster significant after correcting across the complete inter-brain connectivity matrix?

---

### Global FWER correction across the lag search

The function also calculates a more conservative correction accounting for the fact that all lag-specific analyses were inspected.

For each permutation, the largest spatial cluster mass observed at **any independently analysed lag** is retained.

The corresponding corrected p-value is:

```matlab
GlobalFWERAcrossLagsP
```

with the associated outputs:

```matlab
spatialData.globalFWERAcrossLagsPMap
spatialData.significantGlobalAcrossLagsMask
```

Importantly, lags still do **not** form clusters with one another.

This correction only accounts for the multiple lag-specific spatial analyses included in the exploratory lag search.

---

### Desikan–Killiany ROI mapping

The HyperYESNO ROI labels are mapped to the following Desikan–Killiany parcels:

| HyperYESNO ROI | Desikan–Killiany parcel |
|---|---|
| `IFGop` | `parsopercularis` |
| `IFGtri` | `parstriangularis` |
| `STG` | `superiortemporal` |
| `MTG` | `middletemporal` |
| `Heschl` | `transversetemporal` |
| `SMG` | `supramarginal` |
| `IPL` | `inferiorparietal` |
| `Precentral` | `precentral` |
| `RostralMFG` | `rostralmiddlefrontal` |
| `Precuneus` | `precuneus` |

The `L_` and `R_` prefixes specify the hemisphere.

---

### Requirements

The first run requires:

- MATLAB
- FieldTrip
- access to a FreeSurfer `fsaverage` directory containing:

```text
fsaverage/
├── label/
│   ├── lh.aparc.annot
│   └── rh.aparc.annot
└── surf/
    ├── lh.pial
    └── rh.pial
```

The cortical surfaces and Desikan–Killiany parcellations are read using:

```matlab
ft_read_atlas
```

The resulting 20-ROI anatomical adjacency matrix is cached so that subsequent runs do not need to reread the FreeSurfer surfaces.

The cached file is:

```text
Group_GCMI/
└── HyperYESNO_DK20_surface_boundary_adjacency.mat
```

---

### Example

```matlab
[spatialData, clusterTable, roiNeighbourTable, qcTable] = ...
    step10b_spatial_cluster_permutation_GCMI_HyperYESNO( ...
    'E:\EEG_data_HyperYESNO', ...
    'FsAverageDir', 'C:\MATLAB\fsaverage');
```

---

### Main outputs

#### `spatialData`

Contains the complete statistical results.

Group-level descriptive statistics:

```matlab
spatialData.groupMean
spatialData.groupSD
spatialData.groupSEM
spatialData.observedT
spatialData.pointwiseParametricP
```

Anatomical adjacency information:

```matlab
spatialData.roiAdjacencyKnower
spatialData.roiAdjacencyGuesser
spatialData.connectionAdjacency
spatialData.connectionTable
spatialData.adjacencyProvenance
```

Lag-specific spatial FWER correction:

```matlab
spatialData.spatialFWERWithinLagPMap
spatialData.significantSpatialWithinLagMask
```

Global FWER correction across the lag search:

```matlab
spatialData.globalFWERAcrossLagsPMap
spatialData.significantGlobalAcrossLagsMask
```

Permutation null distributions:

```matlab
spatialData.nullMaximumClusterMassByLag
spatialData.nullMaximumClusterMassAcrossLags
```

---

#### `clusterTable`

Contains one row for each observed spatial cluster, including:

- lag;
- cluster sign;
- number of connections;
- signed cluster mass;
- absolute cluster mass;
- peak t statistic;
- peak Knower ROI;
- peak Guesser ROI;
- mean YES–NO effect within the cluster;
- effect at the peak connection;
- spatial FWER-corrected p-value within the lag;
- global FWER-corrected p-value across lags;
- significance status;
- list of connections belonging to the cluster.

---

#### `roiNeighbourTable`

Lists the pairs of ROIs considered anatomical neighbours according to their shared cortical-surface boundary.

This table is useful for checking the anatomical topology used to construct the inter-brain connection clusters.

---

#### `qcTable`

Reports dyads excluded because:

- a valid Step 9 primary contrast was unavailable, or
- the primary contrast contained non-finite values.

---

### Saved outputs

Results are saved under:

```text
E:\EEG_data_HyperYESNO\Group_GCMI\
```

including:

```text
Step10b_HyperYESNO_spatial_cluster_permutation.mat
Step10b_HyperYESNO_spatial_cluster_permutation.xlsx
HyperYESNO_DK20_surface_boundary_adjacency.mat
```

The Excel workbook contains the following sheets:

```text
SpatialClusters
LagSummary
ROINeighbours
Connections
QC
AnalysisDyads
```

---

### Figures

Figures are saved in:

```text
Group_GCMI/
└── Step10b_Spatial_Figures/
```

The function generates:

- the Desikan–Killiany ROI adjacency matrix;
- a summary of the minimum corrected p-value at each lag;
- one three-panel spatial connectivity figure for every analysed lag.

For each lag, the three-panel figure shows:

1. the observed YES–NO t-statistic matrix;
2. the spatial FWER-corrected result within that lag;
3. the globally corrected result accounting for the complete lag search.

---

### Interpretation of significant effects

The group-level effect matrix is:

```matlab
spatialData.groupMean
```

Because the analysed contrast is:

```text
YES − NO
```

the sign of each effect is interpreted as:

```text
positive effect → surrogate-corrected GCMI is larger for YES
negative effect → surrogate-corrected GCMI is larger for NO
```

For example, to extract the spatially FWE-corrected effects at `-250 ms`:

```matlab
lagIndex = find( ...
    spatialData.lagsMilliseconds == -250, ...
    1, ...
    'first');

effectMatrix = ...
    spatialData.groupMean(:,:,lagIndex);

significantMask = ...
    spatialData.significantSpatialWithinLagMask(:,:,lagIndex);

significantEffect = ...
    effectMatrix .* significantMask;
```

The resulting matrix can be interpreted as:

```text
positive non-zero value → YES > NO
negative non-zero value → NO > YES
zero                    → not significant
```

The same procedure can be used for any other lag, for example `300 ms`:

```matlab
lagIndex = find( ...
    spatialData.lagsMilliseconds == 300, ...
    1, ...
    'first');

effectMatrix = ...
    spatialData.groupMean(:,:,lagIndex);

significantMask = ...
    spatialData.significantSpatialWithinLagMask(:,:,lagIndex);

significantEffect = ...
    effectMatrix .* significantMask;
```

Source: `step10b_spatial_cluster_permutation_GCMI_HyperYESNO.m`. :contentReference[oaicite:0]{index=0}
