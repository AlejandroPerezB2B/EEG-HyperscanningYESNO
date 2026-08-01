### Step 3: Dyad-synchronised ASR, ICA, DIPFIT, and ICLabel

`step3_loader_doing_ASR_ICA.m` loads the exact `_PREP.set` datasets for both members of each dyad and applies ASR independently to participants A and B. ASR is configured to reconstruct burst-contaminated data using a conservative `BurstCriterion` of `20`. Residual windows that remain incompletely repaired are detected using `WindowCriterion = 0.30` and `WindowCriterionTolerances = [-Inf 7]`.

To preserve hyperscanning synchronisation, the union of the residual windows rejected for A and B is removed from both recordings. Therefore, both participants always retain exactly the same samples.

The function then estimates the effective data rank from the numerical rank, average reference, and PREP-interpolated channels; runs extended Infomax ICA with PCA rank reduction; fits one dipole per component using the standard MNI BEM model in DIPFIT; and runs ICLabel. Components are classified but are not automatically removed.

Final datasets are saved as:

- `DyadXX-A_PREP_ASR_ICA.set`
- `DyadXX-B_PREP_ASR_ICA.set`

The obsolete files named exactly `DyadXX-A_ICA.set` and `DyadXX-B_ICA.set`, together with their paired `.fdt` files, are deleted. A processing summary is saved as `Step3_ASR_ICA_summary.xlsx` and `Step3_ASR_ICA_summary.mat`.
