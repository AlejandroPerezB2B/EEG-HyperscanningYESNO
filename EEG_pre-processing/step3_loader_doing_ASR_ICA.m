function summaryTable = step3_loader_doing_ASR_ICA(rootDir, dyads)
% STEP3_LOADER_DOING_ASR_ICA
% Apply dyad-synchronised ASR cleaning, ICA, DIPFIT, and ICLabel to the
% HyperYESNO PREP datasets.
%
% This function is designed specifically for the HyperYESNO folder
% structure:
%
%   rootDir
%   ├── Dyad01
%   │   ├── SubjA
%   │   │   └── Dyad01-A_PREP.set
%   │   └── SubjB
%   │       └── Dyad01-B_PREP.set
%   ├── Dyad02
%   │   └── ...
%   └── Dyad35
%
% MAIN PROCESSING STEPS
% ---------------------
% 1. Load the exact _PREP.set file for participants A and B.
%
% 2. Run Artifact Subspace Reconstruction (ASR) independently for A and B.
%    ASR is configured to RECONSTRUCT burst-contaminated data rather than
%    immediately deleting it.
%
% 3. After ASR reconstruction, identify residual windows that clean_rawdata
%    considers incompletely repaired.
%
% 4. Combine the two participant-specific sample masks. If a time interval
%    is rejected for either participant, the same samples are removed from
%    both recordings. This preserves exact A-B sample alignment.
%
% 5. Estimate the effective rank of each cleaned dataset. The estimate uses:
%       - the numerical rank of the data covariance matrix;
%       - the expected rank after average referencing;
%       - the number of channels interpolated by PREP.
%
% 6. Run Picard Infomax ICA with explicit PCA rank reduction.
%    Picard uses a faster Newton/L-BFGS optimisation than MATLAB runica.
%
% 7. Explicitly coregister each participant's channel montage to DIPFIT's
%    standard MNI boundary-element model, then fit one equivalent current
%    dipole to every independent component.
%
% 8. Run ICLabel. Components are classified but are NOT automatically
%    removed in this function.
%
% 9. Save the final files using the suffix:
%
%       _PREP_ASR_ICA.set
%
% 10. Delete the obsolete legacy files named exactly:
%
%       DyadXX-A_ICA.set / .fdt
%       DyadXX-B_ICA.set / .fdt
%
%     The deletion is deliberately exact. Files such as
%     DyadXX-A_PREP_ASR_ICA.set are not deleted.
%
% ASR SETTINGS
% ------------
% The input data have already been processed with PREP. Therefore:
%
%   - additional channel rejection is disabled;
%   - additional high-pass filtering is disabled;
%   - line-noise-based channel rejection is disabled;
%   - ASR burst reconstruction uses BurstCriterion = 20;
%   - residual-window rejection uses WindowCriterion = 0.30;
%   - residual-window tolerances are [-Inf 7].
%
% BurstCriterion = 20 is a conservative ASR threshold. WindowCriterion =
% 0.30 is at the lax end of the range documented for clean_rawdata, meaning
% that deletion is reserved for residual windows containing widespread
% abnormal activity after ASR reconstruction.
%
% INPUTS
% ------
% rootDir : HyperYESNO data root.
%           Default: 'E:\EEG_data_HyperYESNO'
%
% dyads   : Dyad numbers to process.
%           Default: 1:35
%
% OUTPUT
% ------
% summaryTable : One row per dyad, including the number and percentage of
%                synchronously removed samples, PREP interpolation counts,
%                effective ICA ranks, and output filenames.
%
% The same table is saved to:
%
%   Step3_ASR_ICA_summary.xlsx
%   Step3_ASR_ICA_summary.mat
%
% DEPENDENCIES
% ------------
% - MATLAB
% - EEGLAB
% - clean_rawdata
% - Picard
% - DIPFIT
% - ICLabel
%
% The input data are expected to be continuous and sampled at 250 Hz.
%
% EXAMPLE
% -------
% eeglab;
% close;
%
% summaryTable = step3_loader_doing_ASR_ICA( ...
%     'E:\EEG_data_HyperYESNO', 1:35);
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

%% ========================================================================
% 1. User-configurable defaults
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

rootDir = char(rootDir);

% Exact input and output suffixes.
inputSuffix  = '_PREP';
outputSuffix = '_PREP_ASR_ICA';

% Exact suffix used only by the obsolete previous step-3 output.
legacyICASuffix = '_ICA';

% HyperYESNO data were resampled to 250 Hz during Step 1.
expectedSamplingRate = 250;

% Conservative ASR burst threshold.
asrBurstCriterion = 20;

% Lax residual-window rejection threshold. A window is rejected only when
% more than 30% of channels remain abnormal after ASR reconstruction.
asrWindowCriterion = 0.30;

% Standard-deviation tolerances used to detect residual high-power windows.
asrWindowTolerances = [-Inf 7];

% Base seeds make ASR and ICA processing more reproducible. A unique seed is
% derived from the dyad number and processing stage.
baseRandomSeed = 31000;

%% ========================================================================
% 2. Check folders and required functions
% ========================================================================

if exist(rootDir, 'dir') ~= 7
    error('HyperYESNO root directory not found: %s', rootDir);
end

requiredFunctions = { ...
    'pop_loadset', ...
    'pop_saveset', ...
    'clean_artifacts', ...
    'pop_runica', ...
    'picard', ...
    'pop_dipfit_settings', ...
    'coregister', ...
    'pop_multifit', ...
    'iclabel'};

for iFunction = 1:numel(requiredFunctions)

    if exist(requiredFunctions{iFunction}, 'file') ~= 2
        error(['Required function "%s" was not found on the MATLAB path. ', ...
            'Start EEGLAB and confirm that the required plugin is installed.'], ...
            requiredFunctions{iFunction});
    end
end

%% ========================================================================
% 3. Preallocate one summary record per dyad
% ========================================================================

summaryRecords = repmat(local_empty_summary_record(), numel(dyads), 1);

pipelineTimer = tic;

%% ========================================================================
% 4. Process each dyad
% ========================================================================

for iDyad = 1:numel(dyads)

    d = dyads(iDyad);
    dyadTimer = tic;

    dyadStr = sprintf('Dyad%02d', d);

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('Processing %s\n', dyadStr);
    fprintf('============================================================\n');

    record = local_empty_summary_record();
    record.Dyad = d;
    record.DyadName = string(dyadStr);

    % Participant-specific identifiers and folders.
    baseA = sprintf('%s-A', dyadStr);
    baseB = sprintf('%s-B', dyadStr);

    subjDirA = fullfile(rootDir, dyadStr, 'SubjA');
    subjDirB = fullfile(rootDir, dyadStr, 'SubjB');

    inputFileA = [baseA, inputSuffix, '.set'];
    inputFileB = [baseB, inputSuffix, '.set'];

    inputPathA = fullfile(subjDirA, inputFileA);
    inputPathB = fullfile(subjDirB, inputFileB);

    outputFileA = [baseA, outputSuffix, '.set'];
    outputFileB = [baseB, outputSuffix, '.set'];

    record.InputFileA = string(inputPathA);
    record.InputFileB = string(inputPathB);
    record.OutputFileA = string(fullfile(subjDirA, outputFileA));
    record.OutputFileB = string(fullfile(subjDirB, outputFileB));

    try

        %% ----------------------------------------------------------------
        % 4.1 Delete only the obsolete, exact _ICA outputs
        % -----------------------------------------------------------------

        local_delete_legacy_ica_files( ...
            subjDirA, baseA, legacyICASuffix);

        local_delete_legacy_ica_files( ...
            subjDirB, baseB, legacyICASuffix);

        %% ----------------------------------------------------------------
        % 4.2 Confirm that both exact PREP inputs exist
        % -----------------------------------------------------------------

        if exist(inputPathA, 'file') ~= 2
            error('PREP input not found for participant A: %s', inputPathA);
        end

        if exist(inputPathB, 'file') ~= 2
            error('PREP input not found for participant B: %s', inputPathB);
        end

        %% ----------------------------------------------------------------
        % 4.3 Load the two PREP datasets
        % -----------------------------------------------------------------

        fprintf('Loading participant A: %s\n', inputFileA);
        EEG_A = pop_loadset( ...
            'filename', inputFileA, ...
            'filepath', subjDirA);

        fprintf('Loading participant B: %s\n', inputFileB);
        EEG_B = pop_loadset( ...
            'filename', inputFileB, ...
            'filepath', subjDirB);

        EEG_A = eeg_checkset(EEG_A, 'eventconsistency');
        EEG_B = eeg_checkset(EEG_B, 'eventconsistency');

        %% ----------------------------------------------------------------
        % 4.4 Verify the properties required for dyadic synchronisation
        % -----------------------------------------------------------------

        if EEG_A.trials ~= 1 || EEG_B.trials ~= 1
            error('%s must contain continuous, non-epoched datasets.', dyadStr);
        end

        if EEG_A.srate ~= EEG_B.srate
            error(['Sampling-rate mismatch in %s: A = %.6f Hz, ', ...
                'B = %.6f Hz.'], ...
                dyadStr, EEG_A.srate, EEG_B.srate);
        end

        if EEG_A.srate ~= expectedSamplingRate
            error(['Unexpected sampling rate in %s: %.6f Hz. ', ...
                'The Step-3 function expects 250-Hz data.'], ...
                dyadStr, EEG_A.srate);
        end

        if EEG_A.pnts ~= EEG_B.pnts
            error(['Sample-count mismatch before ASR in %s: ', ...
                'A = %d, B = %d.'], ...
                dyadStr, EEG_A.pnts, EEG_B.pnts);
        end

        % Because A and B were split from one simultaneous recording, their
        % event latencies should be identical before cleaning.
        local_assert_event_latency_alignment(EEG_A, EEG_B, dyadStr);

        originalNumberOfSamples = EEG_A.pnts;

        record.OriginalSamples = originalNumberOfSamples;
        record.OriginalDurationSeconds = ...
            originalNumberOfSamples / EEG_A.srate;

        %% ----------------------------------------------------------------
        % 4.5 Run ASR reconstruction independently for A and B
        % -----------------------------------------------------------------

        % ASR is participant-specific because the artifact subspace and
        % calibration data differ between the two people. Sample deletion is
        % not participant-specific: it will be synchronised afterwards.

        fprintf('\nRunning ASR reconstruction for %s-A...\n', dyadStr);

        rng(baseRandomSeed + d * 10 + 1, 'twister');

        [EEG_A_repaired, retainMaskA] = local_run_asr_repair( ...
            EEG_A, ...
            asrBurstCriterion, ...
            asrWindowCriterion, ...
            asrWindowTolerances);

        clear EEG_A

        fprintf('\nRunning ASR reconstruction for %s-B...\n', dyadStr);

        rng(baseRandomSeed + d * 10 + 2, 'twister');

        [EEG_B_repaired, retainMaskB] = local_run_asr_repair( ...
            EEG_B, ...
            asrBurstCriterion, ...
            asrWindowCriterion, ...
            asrWindowTolerances);

        clear EEG_B

        %% ----------------------------------------------------------------
        % 4.6 Form the union of rejected samples
        % -----------------------------------------------------------------

        % A sample is retained only when it survived the residual-window
        % test for BOTH participants. Therefore:
        %
        %   retainMaskDyad = retainMaskA AND retainMaskB
        %
        % Equivalently, the rejected samples are the UNION of the samples
        % rejected for A and B.

        retainMaskDyad = retainMaskA & retainMaskB;

        if ~any(retainMaskDyad)
            error(['ASR residual-window screening rejected all samples in ', ...
                '%s. No output was saved.'], dyadStr);
        end

        removedMaskA = ~retainMaskA;
        removedMaskB = ~retainMaskB;
        removedMaskDyad = ~retainMaskDyad;

        record.SamplesRejectedByA = sum(removedMaskA);
        record.SamplesRejectedByB = sum(removedMaskB);
        record.SamplesRejectedByEither = sum(removedMaskDyad);

        record.PercentRejectedByA = ...
            100 * record.SamplesRejectedByA / originalNumberOfSamples;

        record.PercentRejectedByB = ...
            100 * record.SamplesRejectedByB / originalNumberOfSamples;

        record.PercentRejectedByEither = ...
            100 * record.SamplesRejectedByEither / originalNumberOfSamples;

        record.RetainedSamples = sum(retainMaskDyad);
        record.RetainedDurationSeconds = ...
            record.RetainedSamples / expectedSamplingRate;

        removedIntervalsA = local_false_mask_to_intervals(retainMaskA);
        removedIntervalsB = local_false_mask_to_intervals(retainMaskB);
        removedIntervalsDyad = ...
            local_false_mask_to_intervals(retainMaskDyad);

        record.NRejectedIntervalsA = size(removedIntervalsA, 1);
        record.NRejectedIntervalsB = size(removedIntervalsB, 1);
        record.NRejectedIntervalsDyad = size(removedIntervalsDyad, 1);

        fprintf('\nDyadic ASR residual-window summary for %s\n', dyadStr);
        fprintf('  A rejected:      %d samples (%.3f%%)\n', ...
            record.SamplesRejectedByA, record.PercentRejectedByA);
        fprintf('  B rejected:      %d samples (%.3f%%)\n', ...
            record.SamplesRejectedByB, record.PercentRejectedByB);
        fprintf('  Union rejected:  %d samples (%.3f%%)\n', ...
            record.SamplesRejectedByEither, ...
            record.PercentRejectedByEither);

        %% ----------------------------------------------------------------
        % 4.7 Apply exactly the same sample mask to both repaired datasets
        % -----------------------------------------------------------------

        EEG_A_sync = local_apply_retain_mask( ...
            EEG_A_repaired, retainMaskDyad);

        clear EEG_A_repaired

        EEG_B_sync = local_apply_retain_mask( ...
            EEG_B_repaired, retainMaskDyad);

        clear EEG_B_repaired

        if EEG_A_sync.pnts ~= EEG_B_sync.pnts
            error(['Internal synchronisation error after sample removal ', ...
                'in %s.'], dyadStr);
        end

        % Applying the same mask to event-identical recordings should retain
        % identical event latencies, including inserted boundary events.
        local_assert_event_latency_alignment( ...
            EEG_A_sync, EEG_B_sync, dyadStr);

        %% ----------------------------------------------------------------
        % 4.8 Store ASR and synchronisation provenance
        % -----------------------------------------------------------------

        asrInfo = struct();

        asrInfo.inputSuffix = inputSuffix;
        asrInfo.outputSuffix = outputSuffix;
        asrInfo.samplingRate = expectedSamplingRate;

        asrInfo.channelCleaning = 'off';
        asrInfo.highpassFiltering = 'off';
        asrInfo.lineNoiseChannelCleaning = 'off';

        asrInfo.burstCriterion = asrBurstCriterion;
        asrInfo.burstRejection = 'off';
        asrInfo.windowCriterion = asrWindowCriterion;
        asrInfo.windowCriterionTolerances = ...
            asrWindowTolerances;

        asrInfo.originalNumberOfSamples = ...
            originalNumberOfSamples;

        asrInfo.retainedNumberOfSamples = ...
            sum(retainMaskDyad);

        asrInfo.rejectedNumberOfSamples = ...
            sum(~retainMaskDyad);

        asrInfo.rejectedPercentage = ...
            100 * sum(~retainMaskDyad) / originalNumberOfSamples;

        asrInfo.individualRejectedIntervalsA = ...
            removedIntervalsA;

        asrInfo.individualRejectedIntervalsB = ...
            removedIntervalsB;

        asrInfo.dyadicUnionRejectedIntervals = ...
            removedIntervalsDyad;

        % Store the dyadic mask using the clean_rawdata convention. The mask
        % refers to the sample positions in the original PREP dataset.
        EEG_A_sync.etc.clean_sample_mask = retainMaskDyad;
        EEG_B_sync.etc.clean_sample_mask = retainMaskDyad;

        EEG_A_sync.etc.hyperyesno_step3.asr = asrInfo;
        EEG_B_sync.etc.hyperyesno_step3.asr = asrInfo;

        %% ----------------------------------------------------------------
        % 4.9 ICA, DIPFIT, and ICLabel for participant A
        % -----------------------------------------------------------------

        fprintf('\nRunning ICA, DIPFIT, and ICLabel for %s-A...\n', dyadStr);

        rng(baseRandomSeed + d * 10 + 3, 'twister');

        [EEG_A_final, rankInfoA] = ...
            local_run_ica_dipfit_iclabel(EEG_A_sync);

        clear EEG_A_sync

        EEG_A_final.setname = [baseA, outputSuffix];

        EEG_A_final.etc.hyperyesno_step3.rank = rankInfoA;
        EEG_A_final.etc.hyperyesno_step3.iclabelComponentsRemoved = false;

        record.NInterpolatedChannelsA = ...
            rankInfoA.numberOfPREPInterpolatedChannels;

        record.NumericalRankA = rankInfoA.numericalRank;
        record.ExpectedRankA = rankInfoA.expectedRank;
        record.EffectiveICARankA = rankInfoA.effectiveRank;
        record.NICAComponentsA = size(EEG_A_final.icaweights, 1);
        record.ICAElapsedMinutesA = rankInfoA.icaElapsedMinutes;
        record.DIPFITElapsedMinutesA = rankInfoA.dipfitElapsedMinutes;
        record.ICLabelElapsedMinutesA = rankInfoA.iclabelElapsedMinutes;

        EEG_A_final = pop_saveset( ...
            EEG_A_final, ...
            'filename', outputFileA, ...
            'filepath', subjDirA, ...
            'savemode', 'twofiles');

        fprintf('Saved: %s\n', fullfile(subjDirA, outputFileA));

        clear EEG_A_final

        %% ----------------------------------------------------------------
        % 4.10 ICA, DIPFIT, and ICLabel for participant B
        % -----------------------------------------------------------------

        fprintf('\nRunning ICA, DIPFIT, and ICLabel for %s-B...\n', dyadStr);

        rng(baseRandomSeed + d * 10 + 4, 'twister');

        [EEG_B_final, rankInfoB] = ...
            local_run_ica_dipfit_iclabel(EEG_B_sync);

        clear EEG_B_sync

        EEG_B_final.setname = [baseB, outputSuffix];

        EEG_B_final.etc.hyperyesno_step3.rank = rankInfoB;
        EEG_B_final.etc.hyperyesno_step3.iclabelComponentsRemoved = false;

        record.NInterpolatedChannelsB = ...
            rankInfoB.numberOfPREPInterpolatedChannels;

        record.NumericalRankB = rankInfoB.numericalRank;
        record.ExpectedRankB = rankInfoB.expectedRank;
        record.EffectiveICARankB = rankInfoB.effectiveRank;
        record.NICAComponentsB = size(EEG_B_final.icaweights, 1);
        record.ICAElapsedMinutesB = rankInfoB.icaElapsedMinutes;
        record.DIPFITElapsedMinutesB = rankInfoB.dipfitElapsedMinutes;
        record.ICLabelElapsedMinutesB = rankInfoB.iclabelElapsedMinutes;

        EEG_B_final = pop_saveset( ...
            EEG_B_final, ...
            'filename', outputFileB, ...
            'filepath', subjDirB, ...
            'savemode', 'twofiles');

        fprintf('Saved: %s\n', fullfile(subjDirB, outputFileB));

        clear EEG_B_final

        %% ----------------------------------------------------------------
        % 4.11 Complete the dyad summary record
        % -----------------------------------------------------------------

        record.BurstCriterion = asrBurstCriterion;
        record.WindowCriterion = asrWindowCriterion;
        record.Status = "completed";
        record.ElapsedMinutes = toc(dyadTimer) / 60;

        fprintf('\nCompleted %s in %.2f minutes.\n', ...
            dyadStr, record.ElapsedMinutes);

    catch ME

        record.Status = "failed";
        record.Notes = string(ME.message);
        record.ElapsedMinutes = toc(dyadTimer) / 60;

        fprintf(2, '\nFAILED %s\n%s\n', dyadStr, ME.message);

        % Clear any large datasets before continuing to the next dyad.
        clear EEG_A EEG_B EEG_A_repaired EEG_B_repaired
        clear EEG_A_sync EEG_B_sync EEG_A_final EEG_B_final
    end

    summaryRecords(iDyad) = record;
end

%% ========================================================================
% 5. Create and save the processing summary
% ========================================================================

summaryTable = struct2table(summaryRecords);

summaryExcelFile = fullfile( ...
    rootDir, 'Step3_ASR_ICA_summary.xlsx');

summaryMatFile = fullfile( ...
    rootDir, 'Step3_ASR_ICA_summary.mat');

writetable(summaryTable, summaryExcelFile);

save(summaryMatFile, 'summaryTable');

fprintf('\n');
fprintf('============================================================\n');
fprintf('Step 3 finished in %.2f minutes.\n', toc(pipelineTimer) / 60);
fprintf('Summary Excel file: %s\n', summaryExcelFile);
fprintf('Summary MAT file:   %s\n', summaryMatFile);
fprintf('============================================================\n');

end


%% =========================================================================
% Local function: run ASR reconstruction and obtain residual-window mask
% =========================================================================

function [EEGRepaired, retainMask] = local_run_asr_repair( ...
    EEG, burstCriterion, windowCriterion, windowTolerances)
% Run clean_rawdata's ASR stage while preserving the full-length repaired
% dataset and separately obtaining the mask of residual unrecoverable
% windows.
%
% clean_artifacts returns:
%
%   first output  = repaired data after final residual-window deletion;
%   third output  = ASR-repaired data before final window deletion.
%
% We retain the third output and use the first output only to recover
% EEG.etc.clean_sample_mask. Sample deletion is performed later using the
% union of the two participants' masks.

originalNumberOfSamples = EEG.pnts;

% Remove masks from any previous clean_rawdata execution. PREP normally
% does not create these fields, but clearing them prevents an old mask from
% being combined with the current Step-3 mask.
if isfield(EEG, 'etc') && isfield(EEG.etc, 'clean_sample_mask')
    EEG.etc = rmfield(EEG.etc, 'clean_sample_mask');
end

if isfield(EEG, 'etc') && isfield(EEG.etc, 'clean_channel_mask')
    EEG.etc = rmfield(EEG.etc, 'clean_channel_mask');
end

[EEGAfterWindowScreening, ~, EEGRepaired] = clean_artifacts( ...
    EEG, ...
    'FlatlineCriterion',          'off', ...
    'ChannelCriterion',           'off', ...
    'LineNoiseCriterion',         'off', ...
    'Highpass',                   'off', ...
    'BurstCriterion',             burstCriterion, ...
    'BurstRejection',             'off', ...
    'WindowCriterion',            windowCriterion, ...
    'WindowCriterionTolerances',  windowTolerances, ...
    'Distance',                   'Euclidian');

% clean_windows stores a logical mask referring to the samples in the
% full-length input recording.
if isfield(EEGAfterWindowScreening, 'etc') && ...
        isfield(EEGAfterWindowScreening.etc, 'clean_sample_mask') && ...
        ~isempty(EEGAfterWindowScreening.etc.clean_sample_mask)

    retainMask = logical( ...
        EEGAfterWindowScreening.etc.clean_sample_mask(:)');

else
    % If no final sample mask was generated, no residual windows were
    % rejected.
    retainMask = true(1, originalNumberOfSamples);
end

if numel(retainMask) ~= originalNumberOfSamples
    error(['clean_rawdata returned a sample mask of length %d, but the ', ...
        'input dataset contained %d samples.'], ...
        numel(retainMask), originalNumberOfSamples);
end

if EEGRepaired.pnts ~= originalNumberOfSamples
    error(['The ASR repair output unexpectedly changed the number of ', ...
        'samples before dyadic synchronisation.']);
end

EEGRepaired = eeg_checkset(EEGRepaired, 'eventconsistency');

end


%% =========================================================================
% Local function: apply one sample mask to an EEGLAB dataset
% =========================================================================

function EEG = local_apply_retain_mask(EEG, retainMask)
% Remove all samples marked false while retaining EEGLAB event information.
% The same retainMask is passed to A and B.

retainMask = logical(retainMask(:)');

if numel(retainMask) ~= EEG.pnts
    error(['The dyadic sample mask contains %d samples, but the dataset ', ...
        'contains %d samples.'], numel(retainMask), EEG.pnts);
end

if all(retainMask)
    % No time interval needs to be removed.
    EEG = eeg_checkset(EEG, 'eventconsistency');
    return;
end

% Convert the logical mask into inclusive [startSample endSample] intervals
% that should be retained.
changes = diff([false, retainMask, false]);

intervalStarts = find(changes == 1);
intervalEnds   = find(changes == -1) - 1;

retainIntervals = [intervalStarts(:), intervalEnds(:)];

EEG = pop_select(EEG, 'point', retainIntervals);
EEG = eeg_checkset(EEG, 'eventconsistency');

end


%% =========================================================================
% Local function: ICA, DIPFIT, and ICLabel
% =========================================================================

function [EEG, rankInfo] = local_run_ica_dipfit_iclabel(EEG)
% Estimate effective data rank, run extended Infomax ICA, fit one dipole per
% component using the standard MNI BEM model, and run ICLabel.
%
% No independent component is removed automatically.

%% Determine the PREP-interpolated channels

interpolatedChannels = local_get_prep_interpolated_channels(EEG);
numberOfInterpolatedChannels = numel(interpolatedChannels);

%% Estimate the numerical rank from the channel covariance matrix

% Reshape is included for safety in case EEGLAB stores the continuous data
% with an unexpected singleton dimension.
X = double(reshape(EEG.data, EEG.nbchan, []));

% Remove the temporal mean of each channel before calculating covariance.
X = X - mean(X, 2);

% A channel-by-channel covariance matrix is computationally much smaller
% than performing an SVD directly on the complete channels-by-time matrix.
numberOfSamples = size(X, 2);

if numberOfSamples < 2
    error('The dataset contains too few samples for ICA.');
end

channelCovariance = (X * X') / (numberOfSamples - 1);

singularValues = svd(channelCovariance);

if isempty(singularValues) || max(singularValues) == 0
    error('The data covariance matrix has zero rank.');
end

rankTolerance = ...
    max(size(channelCovariance)) * eps(max(singularValues));

numericalRank = sum(singularValues > rankTolerance);

clear X channelCovariance singularValues

%% Calculate the expected rank after referencing and interpolation

% PREP used average referencing. Average-referenced channel data have at
% most nbchan - 1 independent dimensions.
expectedRank = EEG.nbchan - 1;

% Every interpolated channel is a linear combination of other channels and
% can reduce the maximum effective rank by one additional dimension.
expectedRank = expectedRank - numberOfInterpolatedChannels;

expectedRank = max(expectedRank, 1);

% Use the most conservative rank estimate supported by both the numerical
% data and the PREP processing history.
effectiveRank = min(numericalRank, expectedRank);

if effectiveRank < 1
    error('The estimated effective rank is invalid: %d.', effectiveRank);
end

rankInfo = struct();

rankInfo.numberOfChannels = EEG.nbchan;
rankInfo.interpolatedChannelIndices = interpolatedChannels;
rankInfo.numberOfPREPInterpolatedChannels = ...
    numberOfInterpolatedChannels;

rankInfo.numericalRank = numericalRank;
rankInfo.expectedRank = expectedRank;
rankInfo.effectiveRank = effectiveRank;
rankInfo.rankToleranceMethod = ...
    'max(size(covariance))*eps(max(singularValue))';

fprintf('  Channels:                 %d\n', EEG.nbchan);
fprintf('  PREP interpolated:        %d\n', ...
    numberOfInterpolatedChannels);
fprintf('  Numerical rank:           %d\n', numericalRank);
fprintf('  Expected PREP rank:       %d\n', expectedRank);
fprintf('  Effective ICA rank:       %d\n', effectiveRank);

%% Run Picard Infomax ICA with explicit PCA rank control

% MATLAB runica uses gradient-descent optimisation and can take several
% hours for long continuous recordings with approximately 60 components.
% Picard optimises an Infomax objective using a faster Newton/L-BFGS
% procedure. The 'standard' mode is used to obtain the unconstrained Picard
% solution rather than the orthogonal Picard-O solution.
fprintf('  ICA input samples:        %d\n', EEG.pnts);
fprintf('  ICA input duration:       %.2f minutes\n', ...
    EEG.pnts / EEG.srate / 60);
fprintf('  ICA algorithm:            Picard (standard mode)\n');

icaTimer = tic;

EEG = pop_runica( ...
    EEG, ...
    'icatype', 'picard', ...
    'mode', 'standard', ...
    'pca', effectiveRank);

rankInfo.icaAlgorithm = 'picard-standard';
rankInfo.icaElapsedMinutes = toc(icaTimer) / 60;

fprintf('  ICA elapsed time:         %.2f minutes\n', ...
    rankInfo.icaElapsedMinutes);

EEG = eeg_checkset(EEG);

%% Configure and run DIPFIT with explicit MNI coregistration

dipfitTimer = tic;

numberOfComponents = size(EEG.icaweights, 1);

% Do not rely only on:
%
%   pop_dipfit_settings(EEG, 'model', 'standardBEM')
%
% because automatic recognition of the original channel-location template
% may fail or return an inappropriate transformation. Instead, estimate the
% coordinate transformation explicitly for every dataset by matching the
% current channel montage to DIPFIT's standard MNI 10-05 montage.
[EEG, coregistrationInfo] = ...
    local_configure_dipfit_mni_coregistration(EEG);

rankInfo.dipfitCoordinateTransform = ...
    coregistrationInfo.coordinateTransform;

rankInfo.dipfitTemplateChannelFile = ...
    coregistrationInfo.templateChannelFile;

rankInfo.dipfitHeadModelFile = ...
    coregistrationInfo.headModelFile;

rankInfo.dipfitMRIFile = ...
    coregistrationInfo.mriFile;

% Fit one equivalent current dipole to every independent component.
% A threshold of 100 asks pop_multifit to retain the fitted model for all
% components rather than rejecting models at this stage.
EEG = pop_multifit( ...
    EEG, ...
    1:numberOfComponents, ...
    'threshold', 100, ...
    'dipplot', 'off', ...
    'plotopt', {'normlen', 'on'});

rankInfo.dipfitElapsedMinutes = toc(dipfitTimer) / 60;

fprintf('  DIPFIT coordinate transform: %s\n', ...
    mat2str(coregistrationInfo.coordinateTransform, 6));

fprintf('  DIPFIT elapsed time:      %.2f minutes\n', ...
    rankInfo.dipfitElapsedMinutes);

%% Run ICLabel

iclabelTimer = tic;

EEG = iclabel(EEG, 'default');

rankInfo.iclabelElapsedMinutes = toc(iclabelTimer) / 60;

fprintf('  ICLabel elapsed time:     %.2f minutes\n', ...
    rankInfo.iclabelElapsedMinutes);

% ICLabel classifications are stored in:
%
% EEG.etc.ic_classification.ICLabel.classifications
%
% No automatic IC rejection is performed here. This preserves the complete
% ICA solution for later visual inspection and criterion selection.

EEG = eeg_checkset(EEG);

end


%% =========================================================================
% Local function: explicit MNI coregistration for DIPFIT
% =========================================================================

function [EEG, coregistrationInfo] = ...
    local_configure_dipfit_mni_coregistration(EEG)
% Explicitly align the current EEGLAB channel coordinates to DIPFIT's
% standard MNI BEM montage.
%
% EEGLAB channel coordinates and the MNI head model use different axis
% conventions. The transformation should be stored in
% EEG.dipfit.coord_transform rather than being applied manually to
% EEG.chanlocs, because EEGLAB scalp plotting expects the EEGLAB channel
% coordinate convention.
%
% This function estimates the transformation separately for every dataset,
% following the same procedure used successfully in the user's previous
% DIPFIT pipeline.

%% Locate the active DIPFIT installation

dipfitRoot = fileparts(which('pop_dipfit_settings'));

if isempty(dipfitRoot)
    error('Could not locate the active DIPFIT installation.');
end

templateChannelFilePath = fullfile( ...
    dipfitRoot, 'standard_BEM', 'elec', 'standard_1005.elc');

headModelFilePath = fullfile( ...
    dipfitRoot, 'standard_BEM', 'standard_vol.mat');

mriFilePath = fullfile( ...
    dipfitRoot, 'standard_BEM', 'standard_mri.mat');

requiredFiles = { ...
    templateChannelFilePath, ...
    headModelFilePath, ...
    mriFilePath};

for iFile = 1:numel(requiredFiles)
    if exist(requiredFiles{iFile}, 'file') ~= 2
        error('Required DIPFIT template file not found: %s', ...
            requiredFiles{iFile});
    end
end

%% Confirm that channel coordinates are available

haveXYZ = isfield(EEG.chanlocs, 'X') && ...
    any(~arrayfun(@(channel) isempty(channel.X), EEG.chanlocs));

if ~haveXYZ

    % Recover standard coordinates by matching the current channel labels to
    % the same MNI montage used by DIPFIT.
    EEG = pop_chanedit( ...
        EEG, ...
        'lookup', templateChannelFilePath);

    EEG = eeg_checkset(EEG, 'chanconsist');
end

% Verify that every channel selected for DIPFIT has finite XYZ coordinates.
channelX = nan(1, EEG.nbchan);
channelY = nan(1, EEG.nbchan);
channelZ = nan(1, EEG.nbchan);

for iChannel = 1:EEG.nbchan

    if ~isempty(EEG.chanlocs(iChannel).X)
        channelX(iChannel) = EEG.chanlocs(iChannel).X;
    end

    if ~isempty(EEG.chanlocs(iChannel).Y)
        channelY(iChannel) = EEG.chanlocs(iChannel).Y;
    end

    if ~isempty(EEG.chanlocs(iChannel).Z)
        channelZ(iChannel) = EEG.chanlocs(iChannel).Z;
    end
end

channelsWithCoordinates = ...
    find(isfinite(channelX) & isfinite(channelY) & isfinite(channelZ));

if isempty(channelsWithCoordinates)
    error('No channels contain valid XYZ coordinates for DIPFIT.');
end

if numel(channelsWithCoordinates) < EEG.nbchan
    warning(['%d of %d channels have valid XYZ coordinates. DIPFIT will ', ...
        'use only those channels.'], ...
        numel(channelsWithCoordinates), EEG.nbchan);
end

%% Estimate the transformation to the MNI template montage

% 'warp','auto' estimates translation, rotation, and scaling from matching
% channel labels. 'manual','off' makes the procedure suitable for batch
% processing while still calculating a participant-specific transform.
[~, coordinateTransformParameters] = coregister( ...
    EEG.chanlocs, ...
    templateChannelFilePath, ...
    'warp', 'auto', ...
    'manual', 'off');

if isempty(coordinateTransformParameters) || ...
        ~isnumeric(coordinateTransformParameters) || ...
        numel(coordinateTransformParameters) ~= 9 || ...
        any(~isfinite(coordinateTransformParameters))

    error(['DIPFIT coregistration did not return a valid nine-parameter ', ...
        'coordinate transformation.']);
end

coordinateTransformParameters = ...
    double(coordinateTransformParameters(:)');

%% Store explicit DIPFIT settings

EEG = pop_dipfit_settings( ...
    EEG, ...
    'hdmfile', headModelFilePath, ...
    'mrifile', mriFilePath, ...
    'chanfile', templateChannelFilePath, ...
    'coordformat', 'MNI', ...
    'coord_transform', coordinateTransformParameters, ...
    'chansel', channelsWithCoordinates, ...
    'plotalignment', 'off');

EEG = eeg_checkset(EEG);

%% Save provenance

coregistrationInfo = struct();

coregistrationInfo.coordinateTransform = ...
    coordinateTransformParameters;

coregistrationInfo.templateChannelFile = ...
    templateChannelFilePath;

coregistrationInfo.headModelFile = ...
    headModelFilePath;

coregistrationInfo.mriFile = ...
    mriFilePath;

coregistrationInfo.channelsUsed = ...
    channelsWithCoordinates;

EEG.etc.hyperyesno_step3.dipfitCoregistration = ...
    coregistrationInfo;

end


%% =========================================================================
% Local function: recover PREP interpolated-channel indices
% =========================================================================

function interpolatedChannels = ...
    local_get_prep_interpolated_channels(EEG)
% Recover the channels interpolated by PREP while supporting the field names
% used by different PREP output versions.

interpolatedChannels = [];

if ~isfield(EEG, 'etc') || ...
        ~isfield(EEG.etc, 'noiseDetection') || ...
        isempty(EEG.etc.noiseDetection)
    return;
end

noiseDetection = EEG.etc.noiseDetection;

% Common PREP field.
if isfield(noiseDetection, 'interpolatedChannelNumbers') && ...
        ~isempty(noiseDetection.interpolatedChannelNumbers)

    interpolatedChannels = ...
        noiseDetection.interpolatedChannelNumbers;

% Alternative nested PREP field.
elseif isfield(noiseDetection, 'reference') && ...
        isfield(noiseDetection.reference, 'interpolatedChannels') && ...
        isfield(noiseDetection.reference.interpolatedChannels, 'all') && ...
        ~isempty(noiseDetection.reference.interpolatedChannels.all)

    interpolatedChannels = ...
        noiseDetection.reference.interpolatedChannels.all;

% Fallback to the robust-reference bad-channel list when the interpolation
% list was not saved explicitly.
elseif isfield(noiseDetection, 'reference') && ...
        isfield(noiseDetection.reference, 'badChannels') && ...
        isfield(noiseDetection.reference.badChannels, 'all') && ...
        ~isempty(noiseDetection.reference.badChannels.all)

    interpolatedChannels = ...
        noiseDetection.reference.badChannels.all;
end

if islogical(interpolatedChannels)
    interpolatedChannels = find(interpolatedChannels);
end

if iscell(interpolatedChannels)
    interpolatedChannels = cell2mat(interpolatedChannels);
end

interpolatedChannels = double(interpolatedChannels(:)');
interpolatedChannels = interpolatedChannels( ...
    isfinite(interpolatedChannels) & ...
    interpolatedChannels >= 1 & ...
    interpolatedChannels <= EEG.nbchan & ...
    interpolatedChannels == round(interpolatedChannels));

interpolatedChannels = unique(interpolatedChannels, 'sorted');

end


%% =========================================================================
% Local function: verify event-latency alignment
% =========================================================================

function local_assert_event_latency_alignment(EEG_A, EEG_B, dyadStr)
% Verify that the two participants have the same event-latency vector.
%
% Event types are not compared because EEGLAB may represent otherwise
% equivalent event labels using different MATLAB data types. The critical
% property for sample synchronisation is event latency.

latenciesA = double([EEG_A.event.latency]);
latenciesB = double([EEG_B.event.latency]);

if numel(latenciesA) ~= numel(latenciesB)
    error(['Event-count mismatch between A and B in %s: ', ...
        'A = %d, B = %d.'], ...
        dyadStr, numel(latenciesA), numel(latenciesB));
end

if isempty(latenciesA)
    return;
end

if any(abs(latenciesA - latenciesB) > 1e-6)
    error('Event latencies are not aligned between A and B in %s.', ...
        dyadStr);
end

end


%% =========================================================================
% Local function: convert rejected samples into intervals
% =========================================================================

function rejectedIntervals = local_false_mask_to_intervals(retainMask)
% Convert false runs in a retained-sample mask into inclusive
% [startSample endSample] intervals in the original PREP sample space.

retainMask = logical(retainMask(:)');

rejectedMask = ~retainMask;

if ~any(rejectedMask)
    rejectedIntervals = zeros(0, 2);
    return;
end

changes = diff([false, rejectedMask, false]);

intervalStarts = find(changes == 1);
intervalEnds   = find(changes == -1) - 1;

rejectedIntervals = [intervalStarts(:), intervalEnds(:)];

end


%% =========================================================================
% Local function: remove obsolete exact _ICA files
% =========================================================================

function local_delete_legacy_ica_files( ...
    subjectFolder, participantBase, legacyICASuffix)
% Delete only the obsolete files named exactly Base_ICA.set and Base_ICA.fdt.
%
% Do not use a wildcard such as *_ICA.set because the new output
% _PREP_ASR_ICA.set also ends with "_ICA.set".

legacySetFile = fullfile( ...
    subjectFolder, [participantBase, legacyICASuffix, '.set']);

legacyFdtFile = fullfile( ...
    subjectFolder, [participantBase, legacyICASuffix, '.fdt']);

if exist(legacySetFile, 'file') == 2
    delete(legacySetFile);
    fprintf('Deleted obsolete file: %s\n', legacySetFile);
end

if exist(legacyFdtFile, 'file') == 2
    delete(legacyFdtFile);
    fprintf('Deleted obsolete file: %s\n', legacyFdtFile);
end

end


%% =========================================================================
% Local function: empty summary record
% =========================================================================

function record = local_empty_summary_record()
% Create one empty record with fixed field names and data types.

record = struct( ...
    'Dyad', NaN, ...
    'DyadName', "", ...
    'InputFileA', "", ...
    'InputFileB', "", ...
    'OutputFileA', "", ...
    'OutputFileB', "", ...
    'OriginalSamples', NaN, ...
    'OriginalDurationSeconds', NaN, ...
    'SamplesRejectedByA', NaN, ...
    'SamplesRejectedByB', NaN, ...
    'SamplesRejectedByEither', NaN, ...
    'PercentRejectedByA', NaN, ...
    'PercentRejectedByB', NaN, ...
    'PercentRejectedByEither', NaN, ...
    'NRejectedIntervalsA', NaN, ...
    'NRejectedIntervalsB', NaN, ...
    'NRejectedIntervalsDyad', NaN, ...
    'RetainedSamples', NaN, ...
    'RetainedDurationSeconds', NaN, ...
    'BurstCriterion', NaN, ...
    'WindowCriterion', NaN, ...
    'NInterpolatedChannelsA', NaN, ...
    'NInterpolatedChannelsB', NaN, ...
    'NumericalRankA', NaN, ...
    'NumericalRankB', NaN, ...
    'ExpectedRankA', NaN, ...
    'ExpectedRankB', NaN, ...
    'EffectiveICARankA', NaN, ...
    'EffectiveICARankB', NaN, ...
    'NICAComponentsA', NaN, ...
    'NICAComponentsB', NaN, ...
    'ICAElapsedMinutesA', NaN, ...
    'ICAElapsedMinutesB', NaN, ...
    'DIPFITElapsedMinutesA', NaN, ...
    'DIPFITElapsedMinutesB', NaN, ...
    'ICLabelElapsedMinutesA', NaN, ...
    'ICLabelElapsedMinutesB', NaN, ...
    'Status', "", ...
    'ElapsedMinutes', NaN, ...
    'Notes', "");

end
