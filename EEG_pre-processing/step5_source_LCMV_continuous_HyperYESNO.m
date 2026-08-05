function summaryTable = step5_source_LCMV_continuous_HyperYESNO( ...
    rootDir, dyads, varargin)
% STEP5_SOURCE_LCMV_CONTINUOUS_HYPERYESNO
% Reconstruct continuous source-level ROI signals while preserving all
% HyperYESNO event markers for later experimental epoching.
%
% The function implements a memory-efficient continuous extension of the
% ROIconnect LCMV + ROI-PCA workflow:
%
%   sensor EEG
%       -> distributed Colin27 leadfield
%       -> ROIconnect LCMV spatial filter
%       -> first PCA direction within each anatomical ROI
%       -> continuous ROI time series
%
% The output remains a continuous EEGLAB dataset. EEG.event and EEG.urevent
% are retained, and event latencies remain aligned between participants A
% and B. The resulting files can therefore be epoched later using the
% original HyperYESNO markers.
%
% WHY THIS FUNCTION DOES NOT CALL POP_ROI_ACTIVITY DIRECTLY
% ---------------------------------------------------------
% pop_roi_activity automatically resamples and converts continuous data into
% fixed-length epochs. In addition, roi_activity constructs a full
% voxel-by-time array before reducing it to ROIs. For an approximately
% one-hour recording, that intermediate array can require many gigabytes.
%
% This function instead:
%
%   1. Uses DIPFIT pop_leadfield to create the Colin27 leadfield.
%   2. Uses ROIconnect's lcmv() implementation to estimate the distributed
%      inverse filter.
%   3. Estimates one PCA spatial direction per selected atlas ROI from a
%      representative subset of the continuous recording.
%   4. Combines the LCMV and PCA filters into one sensor-to-ROI projection.
%   5. Applies the projection to the complete continuous recording in
%      memory-efficient blocks.
%
% DEFAULT INPUT FILES
% -------------------
%   DyadXX/SubjA/DyadXX-A_PREP_ASR_ICA_EYE70.set
%   DyadXX/SubjB/DyadXX-B_PREP_ASR_ICA_EYE70.set
%
% DEFAULT OUTPUT FILES
% --------------------
%   DyadXX/SubjA/DyadXX-A_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
%   DyadXX/SubjB/DyadXX-B_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
%
% Each output contains:
%
%   EEG.data      : 20 ROIs x continuous samples
%   EEG.event     : preserved experimental markers
%   EEG.urevent   : preserved EEGLAB original-event structure
%   EEG.srate     : 100 Hz by default
%   EEG.trials    : 1
%   EEG.chanlocs  : ROI labels rather than scalp-channel labels
%
% DEFAULT 20-NODE NETWORK
% -----------------------
% The fixed bilateral communication network contains:
%
%   - pars opercularis
%   - pars triangularis
%   - superior temporal
%   - middle temporal
%   - transverse temporal
%   - supramarginal
%   - inferior parietal
%   - precentral
%   - rostral middle frontal
%   - precuneus
%
% Each region is represented separately in the left and right hemispheres.
%
% INPUTS
% ------
% rootDir
%   HyperYESNO data root.
%   Default: 'E:\EEG_data_HyperYESNO'
%
% dyads
%   Dyad numbers to process.
%   Default: 1:35
%
% NAME-VALUE OPTIONS
% ------------------
% 'InputSuffix'
%   Exact input suffix.
%   Default: '_PREP_ASR_ICA_EYE70'
%
% 'OutputSuffix'
%   Exact output suffix.
%   Default: '_PREP_ASR_ICA_EYE70_LCMV_COMM20'
%
% 'SourceSamplingRate'
%   Sampling rate of the continuous ROI output.
%   Default: 100 Hz
%
% 'LCMVRegularization'
%   LCMV covariance regularisation coefficient.
%   Default: 0.05
%
% 'PCATrainingSeconds'
%   Approximate amount of evenly distributed continuous data used to
%   estimate the first PCA direction within each ROI.
%   Default: 180 seconds
%
% 'DataBlockSeconds'
%   Block size used for covariance estimation and continuous projection.
%   This controls memory use but does not divide the saved dataset.
%   Default: 60 seconds
%
% 'OverwriteExisting'
%   false: do not overwrite existing source datasets.
%   true : overwrite existing source datasets.
%   Default: false
%
% 'MakeQCFigures'
%   Save one ROI-correlation QC figure per participant.
%   Default: true
%
% OUTPUT
% ------
% summaryTable
%   One row per participant with marker-preservation, covariance, PCA, and
%   source-signal QC information.
%
% The summary is also saved as:
%
%   Step5_LCMV_COMM20_continuous_summary.xlsx
%   Step5_LCMV_COMM20_continuous_summary.mat
%
% EXAMPLES
% --------
% Test one dyad:
%
%   eeglab;
%   close;
%
%   T = step5_source_LCMV_continuous_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1);
%
% Process all dyads:
%
%   T = step5_source_LCMV_continuous_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1:35, ...
%       'MakeQCFigures', false);
%
% Overwrite previous test outputs:
%
%   T = step5_source_LCMV_continuous_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1, ...
%       'OverwriteExisting', true);
%
% DEPENDENCIES
% ------------
% - MATLAB
% - EEGLAB
% - DIPFIT
% - ROIconnect
% - FieldTrip or FieldTrip-lite
% - MATLAB Signal Processing Toolbox
%
% GCMI is not required for this source-reconstruction step.
%
% REVISION
% --------
% The LCMV output is handled as channels x vertices x 3 orientations when
% onedim = 0, matching the supplied Stefan Haufe lcmv.m implementation.
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

%% ========================================================================
% 1. Defaults and input parsing
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

rootDir = char(rootDir);

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, 'InputSuffix', ...
    '_PREP_ASR_ICA_EYE70', ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, 'OutputSuffix', ...
    '_PREP_ASR_ICA_EYE70_LCMV_COMM20', ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, 'SourceSamplingRate', ...
    100, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x > 0);

addParameter(parser, 'LCMVRegularization', ...
    0.05, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x > 0);

addParameter(parser, 'PCATrainingSeconds', ...
    180, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x > 0);

addParameter(parser, 'DataBlockSeconds', ...
    60, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x > 0);

addParameter(parser, 'OverwriteExisting', ...
    false, ...
    @(x) islogical(x) || ...
    (isnumeric(x) && isscalar(x)));

addParameter(parser, 'MakeQCFigures', ...
    true, ...
    @(x) islogical(x) || ...
    (isnumeric(x) && isscalar(x)));

parse(parser, varargin{:});
options = parser.Results;

options.InputSuffix = char(options.InputSuffix);
options.OutputSuffix = char(options.OutputSuffix);
options.OverwriteExisting = logical(options.OverwriteExisting);
options.MakeQCFigures = logical(options.MakeQCFigures);

validateattributes(dyads, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'});

if exist(rootDir, 'dir') ~= 7
    error('HyperYESNO root directory not found: %s', rootDir);
end

%% ========================================================================
% 2. Dependency checks
% ========================================================================

requiredFunctions = { ...
    'pop_loadset', ...
    'pop_saveset', ...
    'pop_resample', ...
    'pop_leadfield', ...
    'ft_prepare_leadfield', ...
    'lcmv', ...
    'eeg_emptyset'};

for iFunction = 1:numel(requiredFunctions)

    if exist(requiredFunctions{iFunction}, 'file') ~= 2
        error(['Required function "%s" was not found on the MATLAB path. ', ...
            'Start EEGLAB and check the required plugins/toolboxes.'], ...
            requiredFunctions{iFunction});
    end
end

if exist('dpss', 'file') ~= 2
    error(['The MATLAB Signal Processing Toolbox was not found. ', ...
        'DIPFIT pop_leadfield requires dpss().']);
end

lcmvPath = which('lcmv');

if ~contains(lower(lcmvPath), 'roiconnect')
    warning(['The active lcmv() function is not obviously located inside ', ...
        'the ROIconnect plugin:\n%s\nConfirm that this is the intended ', ...
        'ROIconnect LCMV implementation.'], ...
        lcmvPath);
end

%% ========================================================================
% 3. Locate and load the Colin27 source model and atlas
% ========================================================================

eeglabRoot = fileparts(which('eeglab.m'));

sourceModelFile = fullfile( ...
    eeglabRoot, ...
    'functions', ...
    'supportfiles', ...
    'head_modelColin27_5003_Standard-10-5-Cap339.mat');

if exist(sourceModelFile, 'file') ~= 2
    error('EEGLAB Colin27 source model not found: %s', ...
        sourceModelFile);
end

% Current default alignment specified in DIPFIT pop_leadfield for the
% Colin27/Desikan-Kiliany source model.
sourceModelToMNI = ...
    [0 -24 -45 0 0 -1.5707963 1000 1000 1000];

atlasInfo = local_load_colin27_atlas(sourceModelFile);

[selectedAtlasIndices, selectedNodeLabels, ...
    selectedAtlasLabels, selectedROIVertices] = ...
    local_select_communication20(atlasInfo);

numberOfROIs = numel(selectedAtlasIndices);

if numberOfROIs ~= 20
    error('The COMM20 network must contain exactly 20 ROIs.');
end

fprintf('\nSelected source network:\n');

for iROI = 1:numberOfROIs
    fprintf('  %2d. %-18s <- %s\n', ...
        iROI, ...
        selectedNodeLabels(iROI), ...
        selectedAtlasLabels(iROI));
end

%% ========================================================================
% 4. Preallocate participant-level summary
% ========================================================================

tags = {'A', 'B'};

nParticipants = numel(dyads) * numel(tags);

summaryRecords = repmat( ...
    local_empty_summary_record(), ...
    nParticipants, ...
    1);

recordCounter = 0;
pipelineTimer = tic;

%% ========================================================================
% 5. Process every dyad
% ========================================================================

for iDyad = 1:numel(dyads)

    d = dyads(iDyad);
    dyadStr = sprintf('Dyad%02d', d);
    dyadTimer = tic;

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('Continuous LCMV source reconstruction: %s\n', dyadStr);
    fprintf('============================================================\n');

    participantFolders = { ...
        fullfile(rootDir, dyadStr, 'SubjA'), ...
        fullfile(rootDir, dyadStr, 'SubjB')};

    participantBases = { ...
        [dyadStr, '-A'], ...
        [dyadStr, '-B']};

    inputFiles = { ...
        [participantBases{1}, options.InputSuffix, '.set'], ...
        [participantBases{2}, options.InputSuffix, '.set']};

    outputFiles = { ...
        [participantBases{1}, options.OutputSuffix, '.set'], ...
        [participantBases{2}, options.OutputSuffix, '.set']};

    inputPaths = { ...
        fullfile(participantFolders{1}, inputFiles{1}), ...
        fullfile(participantFolders{2}, inputFiles{2})};

    outputPaths = { ...
        fullfile(participantFolders{1}, outputFiles{1}), ...
        fullfile(participantFolders{2}, outputFiles{2})};

    recordIndices = recordCounter + (1:2);

    for iTag = 1:2

        recordCounter = recordCounter + 1;

        summaryRecords(recordCounter).Dyad = d;
        summaryRecords(recordCounter).Member = string(tags{iTag});
        summaryRecords(recordCounter).Participant = ...
            string(participantBases{iTag});
        summaryRecords(recordCounter).InputFile = ...
            string(inputPaths{iTag});
        summaryRecords(recordCounter).OutputFile = ...
            string(outputPaths{iTag});
    end

    try

        %% ----------------------------------------------------------------
        % 5.1 Confirm input and output paths
        % -----------------------------------------------------------------

        for iTag = 1:2

            if exist(inputPaths{iTag}, 'file') ~= 2
                error('Input dataset not found: %s', ...
                    inputPaths{iTag});
            end

            if exist(outputPaths{iTag}, 'file') == 2 && ...
                    ~options.OverwriteExisting

                error(['Output already exists and OverwriteExisting is ', ...
                    'false: %s'], ...
                    outputPaths{iTag});
            end
        end

        %% ----------------------------------------------------------------
        % 5.2 Load A and B
        % -----------------------------------------------------------------

        EEG_A = pop_loadset( ...
            'filename', inputFiles{1}, ...
            'filepath', participantFolders{1});

        EEG_B = pop_loadset( ...
            'filename', inputFiles{2}, ...
            'filepath', participantFolders{2});

        EEG_A = eeg_checkset(EEG_A, 'eventconsistency');
        EEG_B = eeg_checkset(EEG_B, 'eventconsistency');

        if EEG_A.trials ~= 1 || EEG_B.trials ~= 1
            error(['The source-reconstruction input must be continuous. ', ...
                '%s contains epoched data.'], ...
                dyadStr);
        end

        local_assert_dyad_alignment(EEG_A, EEG_B, dyadStr);

        originalEventInfoA = local_capture_event_info(EEG_A);
        originalEventInfoB = local_capture_event_info(EEG_B);

        %% ----------------------------------------------------------------
        % 5.3 Create synchronized resampled copies
        % -----------------------------------------------------------------

        if EEG_A.srate ~= options.SourceSamplingRate

            fprintf('Resampling A and B from %.3f Hz to %.3f Hz...\n', ...
                EEG_A.srate, ...
                options.SourceSamplingRate);

            EEG_A = pop_resample( ...
                EEG_A, options.SourceSamplingRate);

            EEG_B = pop_resample( ...
                EEG_B, options.SourceSamplingRate);
        end

        EEG_A = eeg_checkset(EEG_A, 'eventconsistency');
        EEG_B = eeg_checkset(EEG_B, 'eventconsistency');

        local_assert_dyad_alignment(EEG_A, EEG_B, dyadStr);

        resampledEventInfoA = local_capture_event_info(EEG_A);
        resampledEventInfoB = local_capture_event_info(EEG_B);

        %% ----------------------------------------------------------------
        % 5.4 Reconstruct continuous ROI signals
        % -----------------------------------------------------------------

        fprintf('\nReconstructing %s-A...\n', dyadStr);

        [EEG_source_A, qcA] = ...
            local_reconstruct_participant( ...
            EEG_A, ...
            participantBases{1}, ...
            options, ...
            sourceModelFile, ...
            sourceModelToMNI, ...
            atlasInfo, ...
            selectedAtlasIndices, ...
            selectedNodeLabels, ...
            selectedAtlasLabels, ...
            selectedROIVertices, ...
            originalEventInfoA, ...
            resampledEventInfoA);

        clear EEG_A

        fprintf('\nReconstructing %s-B...\n', dyadStr);

        [EEG_source_B, qcB] = ...
            local_reconstruct_participant( ...
            EEG_B, ...
            participantBases{2}, ...
            options, ...
            sourceModelFile, ...
            sourceModelToMNI, ...
            atlasInfo, ...
            selectedAtlasIndices, ...
            selectedNodeLabels, ...
            selectedAtlasLabels, ...
            selectedROIVertices, ...
            originalEventInfoB, ...
            resampledEventInfoB);

        clear EEG_B

        %% ----------------------------------------------------------------
        % 5.5 Verify continuous source alignment and markers
        % -----------------------------------------------------------------

        local_assert_dyad_alignment( ...
            EEG_source_A, EEG_source_B, dyadStr);

        local_assert_event_info_equal( ...
            local_capture_event_info(EEG_source_A), ...
            resampledEventInfoA, ...
            [participantBases{1}, ' source output']);

        local_assert_event_info_equal( ...
            local_capture_event_info(EEG_source_B), ...
            resampledEventInfoB, ...
            [participantBases{2}, ' source output']);

        %% ----------------------------------------------------------------
        % 5.6 Save continuous source datasets
        % -----------------------------------------------------------------

        EEG_source_A = pop_saveset( ...
            EEG_source_A, ...
            'filename', outputFiles{1}, ...
            'filepath', participantFolders{1}, ...
            'savemode', 'twofiles');

        fprintf('Saved: %s\n', outputPaths{1});

        EEG_source_B = pop_saveset( ...
            EEG_source_B, ...
            'filename', outputFiles{2}, ...
            'filepath', participantFolders{2}, ...
            'savemode', 'twofiles');

        fprintf('Saved: %s\n', outputPaths{2});

        %% ----------------------------------------------------------------
        % 5.7 Optional QC figures
        % -----------------------------------------------------------------

        if options.MakeQCFigures

            figurePathA = fullfile( ...
                participantFolders{1}, ...
                [participantBases{1}, ...
                options.OutputSuffix, ...
                '_ROI_correlation_QC.png']);

            figurePathB = fullfile( ...
                participantFolders{2}, ...
                [participantBases{2}, ...
                options.OutputSuffix, ...
                '_ROI_correlation_QC.png']);

            local_save_correlation_figure( ...
                qcA.sourceCorrelationMatrix, ...
                selectedNodeLabels, ...
                [participantBases{1}, ' ROI correlations'], ...
                figurePathA);

            local_save_correlation_figure( ...
                qcB.sourceCorrelationMatrix, ...
                selectedNodeLabels, ...
                [participantBases{2}, ' ROI correlations'], ...
                figurePathB);
        end

        %% ----------------------------------------------------------------
        % 5.8 Fill summary records
        % -----------------------------------------------------------------

        summaryRecords(recordIndices(1)) = ...
            local_fill_summary_record( ...
            summaryRecords(recordIndices(1)), ...
            qcA, ...
            EEG_source_A);

        summaryRecords(recordIndices(2)) = ...
            local_fill_summary_record( ...
            summaryRecords(recordIndices(2)), ...
            qcB, ...
            EEG_source_B);

        elapsedMinutes = toc(dyadTimer) / 60;

        summaryRecords(recordIndices(1)).Status = "completed";
        summaryRecords(recordIndices(2)).Status = "completed";

        summaryRecords(recordIndices(1)).ElapsedMinutes = ...
            elapsedMinutes;
        summaryRecords(recordIndices(2)).ElapsedMinutes = ...
            elapsedMinutes;

        fprintf('\nCompleted %s in %.2f minutes.\n', ...
            dyadStr, elapsedMinutes);

        clear EEG_source_A EEG_source_B

    catch ME

        fprintf(2, '\nFAILED %s\n%s\n', ...
            dyadStr, ME.message);

        for iRecord = recordIndices

            summaryRecords(iRecord).Status = "failed";
            summaryRecords(iRecord).Notes = string(ME.message);
            summaryRecords(iRecord).ElapsedMinutes = ...
                toc(dyadTimer) / 60;
        end

        clear EEG_A EEG_B EEG_source_A EEG_source_B
    end
end

%% ========================================================================
% 6. Save processing summary
% ========================================================================

summaryTable = struct2table(summaryRecords);

summaryExcelFile = fullfile( ...
    rootDir, ...
    'Step5_LCMV_COMM20_continuous_summary.xlsx');

summaryMatFile = fullfile( ...
    rootDir, ...
    'Step5_LCMV_COMM20_continuous_summary.mat');

writetable(summaryTable, summaryExcelFile);
save(summaryMatFile, 'summaryTable');

fprintf('\n');
fprintf('============================================================\n');
fprintf('Continuous source reconstruction finished in %.2f minutes.\n', ...
    toc(pipelineTimer) / 60);
fprintf('Summary Excel file: %s\n', summaryExcelFile);
fprintf('Summary MAT file:   %s\n', summaryMatFile);
fprintf('============================================================\n');

end


%% =========================================================================
% Local function: reconstruct one participant
% =========================================================================

function [EEG_source, qc] = local_reconstruct_participant( ...
    EEG, ...
    participantBase, ...
    options, ...
    sourceModelFile, ...
    sourceModelToMNI, ...
    atlasInfo, ...
    selectedAtlasIndices, ...
    selectedNodeLabels, ...
    selectedAtlasLabels, ...
    selectedROIVertices, ...
    originalEventInfo, ...
    resampledEventInfo)

participantTimer = tic;

%% Verify DIPFIT settings

local_validate_dipfit_settings(EEG, participantBase);

sensorChannelLabels = string({EEG.chanlocs.labels});
sensorChanlocs = EEG.chanlocs;
sensorEtc = EEG.etc;
sensorDipfitProvenance = ...
    local_small_dipfit_provenance(EEG.dipfit);

%% Compute distributed leadfield

fprintf('  Computing Colin27 leadfield...\n');

EEG = pop_leadfield( ...
    EEG, ...
    'sourcemodel', sourceModelFile, ...
    'sourcemodel2mni', sourceModelToMNI, ...
    'downsample', 1);

[leadfield, leadfieldLabels] = ...
    local_convert_fieldtrip_leadfield( ...
    EEG.dipfit.sourcemodel);

numberOfVoxels = size(leadfield, 2);

if numberOfVoxels ~= atlasInfo.numberOfVertices
    error(['Leadfield contains %d vertices, whereas the atlas contains ', ...
        '%d vertices.'], ...
        numberOfVoxels, atlasInfo.numberOfVertices);
end

channelIndices = local_match_channel_labels( ...
    sensorChannelLabels, ...
    leadfieldLabels);

numberOfChannels = numel(channelIndices);

if size(leadfield, 1) ~= numberOfChannels
    error(['Leadfield channel dimension (%d) does not match the selected ', ...
        'sensor channels (%d).'], ...
        size(leadfield, 1), numberOfChannels);
end

%% Apply the same common-average transform used by ROIconnect

averageReferenceMatrix = ...
    eye(numberOfChannels) - ...
    ones(numberOfChannels) ./ numberOfChannels;

leadfieldCAR = reshape( ...
    averageReferenceMatrix * leadfield(:, :), ...
    numberOfChannels, ...
    numberOfVoxels, ...
    3);

%% Estimate sensor covariance using the complete continuous recording

blockSamples = max(1, round( ...
    options.DataBlockSeconds * EEG.srate));

fprintf('  Estimating continuous sensor covariance...\n');

[covarianceMatrix, covarianceQC] = ...
    local_blockwise_covariance( ...
    EEG.data, ...
    channelIndices, ...
    averageReferenceMatrix, ...
    blockSamples);

regularizationAlpha = ...
    options.LCMVRegularization * ...
    trace(covarianceMatrix) / ...
    numberOfChannels;

regularizedCovariance = ...
    covarianceMatrix + ...
    regularizationAlpha * eye(numberOfChannels);

%% Estimate ROIconnect LCMV inverse kernel

fprintf('  Computing ROIconnect LCMV filter...\n');

[~, distributedFilter] = lcmv( ...
    regularizedCovariance, ...
    leadfieldCAR, ...
    struct('alpha', 0, 'onedim', 0));

% With onedim = 0, the Stefan Haufe / ROIconnect lcmv() function returns:
%
%   channels x source vertices x source orientations
%
% For the Colin27 source model this is normally:
%
%   62 x 5003 x 3
%
% The previous version of this function incorrectly expected the last two
% dimensions to have already been flattened into 5003*3 columns.
actualFilterSize = size(distributedFilter);

% Explicitly retain a three-element dimension vector even in the unlikely
% event that MATLAB suppresses a trailing singleton dimension.
if numel(actualFilterSize) < 3
    actualFilterSize(3) = 1;
end

expectedFilterSize = [ ...
    numberOfChannels, ...
    numberOfVoxels, ...
    3];

if ~isequal(actualFilterSize, expectedFilterSize)

    error(['Unexpected LCMV filter dimensions: %d x %d x %d. ', ...
        'Expected %d x %d x %d for onedim = 0.'], ...
        actualFilterSize(1), ...
        actualFilterSize(2), ...
        actualFilterSize(3), ...
        expectedFilterSize(1), ...
        expectedFilterSize(2), ...
        expectedFilterSize(3));
end

fprintf('  LCMV filter dimensions: %d x %d x %d\n', ...
    actualFilterSize(1), ...
    actualFilterSize(2), ...
    actualFilterSize(3));

% Flatten the vertex and orientation dimensions explicitly:
%
%   channels x vertices x orientations
%
% becomes:
%
%   channels x (vertices * orientations)
%
% MATLAB's column-major ordering produces:
%
%   columns 1:N           = orientation 1 for all vertices
%   columns N+1:2N        = orientation 2 for all vertices
%   columns 2N+1:3N       = orientation 3 for all vertices
distributedFilter2D = reshape( ...
    distributedFilter, ...
    numberOfChannels, ...
    numberOfVoxels * 3);

%% Select representative samples for ROI PCA orientation estimation

requestedTrainingSamples = round( ...
    options.PCATrainingSeconds * EEG.srate);

numberOfTrainingSamples = min( ...
    EEG.pnts, ...
    requestedTrainingSamples);

trainingSampleIndices = ...
    local_evenly_spaced_indices( ...
    EEG.pnts, numberOfTrainingSamples);

trainingSensorData = ...
    averageReferenceMatrix * ...
    double(EEG.data( ...
    channelIndices, trainingSampleIndices));

%% Estimate one PCA direction per selected ROI

numberOfROIs = numel(selectedAtlasIndices);

roiSensorFilters = zeros( ...
    numberOfChannels, numberOfROIs);

firstPCVarianceExplained = nan( ...
    numberOfROIs, 1);

roiFilterNorms = nan(numberOfROIs, 1);
roiPolaritySigns = ones(numberOfROIs, 1);
roiCentroidsMNI = nan(numberOfROIs, 3);

fprintf('  Estimating first PCA direction for %d ROIs...\n', ...
    numberOfROIs);

for iROI = 1:numberOfROIs

    vertexIndices = selectedROIVertices{iROI};

    if isempty(vertexIndices)
        error('ROI %s contains no source vertices.', ...
            selectedNodeLabels(iROI));
    end

    if any(vertexIndices < 1) || ...
            any(vertexIndices > numberOfVoxels)

        error('ROI %s contains invalid source-vertex indices.', ...
            selectedNodeLabels(iROI));
    end

    orientationColumns = [ ...
        vertexIndices(:)', ...
        numberOfVoxels + vertexIndices(:)', ...
        2 * numberOfVoxels + vertexIndices(:)'];

    roiDistributedFilter = ...
        distributedFilter2D(:, orientationColumns);

    trainingVoxelActivity = ...
        trainingSensorData' * roiDistributedFilter;

    if ~any(isfinite(trainingVoxelActivity(:)))
        error('ROI %s produced no finite training activity.', ...
            selectedNodeLabels(iROI));
    end

    trainingVoxelActivity( ...
        ~isfinite(trainingVoxelActivity)) = 0;

    [~, singularValue, voxelPCDirection] = ...
        svds(trainingVoxelActivity, 1);

    roiFilter = ...
        roiDistributedFilter * voxelPCDirection;

    % PCA signs are mathematically arbitrary. Fix the sign deterministically
    % by making the largest absolute sensor weight positive.
    [~, maximumWeightIndex] = max(abs(roiFilter));

    if roiFilter(maximumWeightIndex) < 0
        roiFilter = -roiFilter;
        roiPolaritySigns(iROI) = -1;
    end

    roiSensorFilters(:, iROI) = roiFilter;
    roiFilterNorms(iROI) = norm(roiFilter);

    totalTrainingEnergy = ...
        sum(trainingVoxelActivity(:) .^ 2);

    if totalTrainingEnergy > 0
        firstPCVarianceExplained(iROI) = ...
            singularValue(1, 1) ^ 2 / ...
            totalTrainingEnergy;
    end

    roiCentroidsMNI(iROI, :) = mean( ...
        EEG.dipfit.sourcemodel.pos( ...
        vertexIndices, :), ...
        1, ...
        'omitnan');

    clear trainingVoxelActivity
end

clear trainingSensorData distributedFilter distributedFilter2D leadfield leadfieldCAR

%% Apply the combined sensor-to-ROI filter to the full continuous data

fprintf('  Projecting the complete continuous recording...\n');

roiData = zeros( ...
    numberOfROIs, ...
    EEG.pnts, ...
    'single');

for blockStart = 1:blockSamples:EEG.pnts

    blockEnd = min( ...
        EEG.pnts, ...
        blockStart + blockSamples - 1);

    blockIndices = blockStart:blockEnd;

    sensorBlock = ...
        averageReferenceMatrix * ...
        double(EEG.data( ...
        channelIndices, blockIndices));

    % ROIconnect multiplies LCMV voxel activity by 10^3 and reports nA*m.
    roiData(:, blockIndices) = single( ...
        1e3 * ...
        (roiSensorFilters' * sensorBlock));
end

%% Source-level QC

sourceQC = local_source_qc(roiData);

%% Build continuous ROI-level EEGLAB dataset

sourceInfo = struct();

sourceInfo.method = ...
    'ROIconnect LCMV plus first within-ROI PCA spatial direction';

sourceInfo.continuousOutput = true;
sourceInfo.markersPreserved = true;
sourceInfo.atlasName = 'Desikan-Kiliany';
sourceInfo.networkName = 'COMM20';

sourceInfo.sourceModelFile = sourceModelFile;
sourceInfo.sourceModelToMNI = sourceModelToMNI;

sourceInfo.inputSamplingRate = ...
    originalEventInfo.samplingRate;

sourceInfo.outputSamplingRate = EEG.srate;
sourceInfo.lcmvRegularization = ...
    options.LCMVRegularization;

sourceInfo.regularizationAlpha = ...
    regularizationAlpha;

sourceInfo.lcmvFilterDimensions = ...
    actualFilterSize;

sourceInfo.lcmvOrientationMode = ...
    'Three orientations per source vertex (onedim = 0)';

sourceInfo.pcaTrainingSecondsRequested = ...
    options.PCATrainingSeconds;

sourceInfo.pcaTrainingSamplesUsed = ...
    numberOfTrainingSamples;

sourceInfo.pcaTrainingSecondsUsed = ...
    numberOfTrainingSamples / EEG.srate;

sourceInfo.selectedAtlasIndices = ...
    selectedAtlasIndices;

sourceInfo.nodeLabels = ...
    cellstr(selectedNodeLabels);

sourceInfo.atlasLabels = ...
    cellstr(selectedAtlasLabels);

sourceInfo.roiVertices = ...
    selectedROIVertices;

sourceInfo.roiCentroidsMNI = ...
    roiCentroidsMNI;

sourceInfo.sensorChannelIndices = ...
    channelIndices;

sourceInfo.sensorChannelLabels = ...
    cellstr(sensorChannelLabels(channelIndices));

sourceInfo.sensorToROIFilters = ...
    single(roiSensorFilters);

sourceInfo.firstPCVarianceExplained = ...
    firstPCVarianceExplained;

sourceInfo.roiFilterNorms = ...
    roiFilterNorms;

sourceInfo.roiPolaritySigns = ...
    roiPolaritySigns;

sourceInfo.polarityNote = [ ...
    'PCA source polarity is arbitrary. Signs were fixed deterministically ', ...
    'by making the largest absolute sensor-filter coefficient positive.'];

sourceInfo.originalInputEvents = ...
    originalEventInfo;

sourceInfo.resampledOutputEvents = ...
    resampledEventInfo;

sourceInfo.originalSensorDipfit = ...
    sensorDipfitProvenance;

sourceInfo.covarianceQC = ...
    covarianceQC;

sourceInfo.sourceQC = ...
    sourceQC;

sourceInfo.elapsedMinutes = ...
    toc(participantTimer) / 60;

EEG_source = local_build_source_dataset( ...
    EEG, ...
    roiData, ...
    selectedNodeLabels, ...
    selectedAtlasLabels, ...
    roiCentroidsMNI, ...
    sourceInfo, ...
    sensorChanlocs, ...
    sensorEtc, ...
    participantBase, ...
    options.OutputSuffix);

%% Verify markers after dataset conversion

local_assert_event_info_equal( ...
    local_capture_event_info(EEG_source), ...
    resampledEventInfo, ...
    [participantBase, ' source conversion']);

%% Return QC

qc = sourceQC;

qc.sensorRank = covarianceQC.rank;
qc.sensorCovarianceCondition = ...
    covarianceQC.conditionNumber;
qc.sensorCovarianceReciprocalCondition = ...
    covarianceQC.reciprocalCondition;

qc.regularizationAlpha = ...
    regularizationAlpha;

qc.minimumFirstPCVarianceExplained = ...
    min(firstPCVarianceExplained);

qc.medianFirstPCVarianceExplained = ...
    median(firstPCVarianceExplained);

qc.maximumFirstPCVarianceExplained = ...
    max(firstPCVarianceExplained);

qc.numberOfROIs = numberOfROIs;
qc.markerCount = numel(EEG_source.event);
qc.blockStartCount = sum(strcmpi( ...
    string({EEG_source.event.type}), ...
    "BlockStart"));

qc.markersPreserved = true;
qc.sourceElapsedMinutes = ...
    sourceInfo.elapsedMinutes;

end


%% =========================================================================
% Local function: load Colin27 atlas
% =========================================================================

function atlasInfo = local_load_colin27_atlas(sourceModelFile)

sourceModel = load(sourceModelFile);

if isfield(sourceModel, 'atlas') && ...
        isfield(sourceModel.atlas, 'label') && ...
        isfield(sourceModel.atlas, 'colorTable')

    labels = string(sourceModel.atlas.label(:));
    colorTable = double(sourceModel.atlas.colorTable(:));

elseif isfield(sourceModel, 'Atlas') && ...
        ~isempty(sourceModel.Atlas)

    atlasEntry = sourceModel.Atlas(1);

    labels = string({atlasEntry.Scouts.Label})';

    colorTable = zeros( ...
        size(sourceModel.cortex.vertices, 1), 1);

    for iROI = 1:numel(atlasEntry.Scouts)
        colorTable( ...
            atlasEntry.Scouts(iROI).Vertices) = iROI;
    end

else
    error(['Could not identify atlas labels and vertex assignments in ', ...
        'the Colin27 source-model file.']);
end

if isfield(sourceModel, 'cortex') && ...
        isfield(sourceModel.cortex, 'vertices')

    vertices = double(sourceModel.cortex.vertices);

elseif isfield(sourceModel, 'Vertices')

    vertices = double(sourceModel.Vertices);

else
    error('Could not identify source-model vertices.');
end

if numel(colorTable) ~= size(vertices, 1)
    error(['Atlas colorTable length (%d) does not equal the number of ', ...
        'source vertices (%d).'], ...
        numel(colorTable), size(vertices, 1));
end

atlasInfo = struct();

atlasInfo.labels = labels;
atlasInfo.colorTable = colorTable;
atlasInfo.vertices = vertices;
atlasInfo.numberOfVertices = size(vertices, 1);
atlasInfo.numberOfROIs = numel(labels);

end


%% =========================================================================
% Local function: select fixed 20-node communication network
% =========================================================================

function [indices, nodeLabels, atlasLabelsSelected, roiVertices] = ...
    local_select_communication20(atlasInfo)

definitions = { ...
    'L_IFGop',      'parsopercularis',      'L'; ...
    'R_IFGop',      'parsopercularis',      'R'; ...
    'L_IFGtri',     'parstriangularis',      'L'; ...
    'R_IFGtri',     'parstriangularis',      'R'; ...
    'L_STG',        'superiortemporal',      'L'; ...
    'R_STG',        'superiortemporal',      'R'; ...
    'L_MTG',        'middletemporal',        'L'; ...
    'R_MTG',        'middletemporal',        'R'; ...
    'L_Heschl',     'transversetemporal',    'L'; ...
    'R_Heschl',     'transversetemporal',    'R'; ...
    'L_SMG',        'supramarginal',         'L'; ...
    'R_SMG',        'supramarginal',         'R'; ...
    'L_IPL',        'inferiorparietal',       'L'; ...
    'R_IPL',        'inferiorparietal',       'R'; ...
    'L_Precentral', 'precentral',             'L'; ...
    'R_Precentral', 'precentral',             'R'; ...
    'L_RostralMFG', 'rostralmiddlefrontal',   'L'; ...
    'R_RostralMFG', 'rostralmiddlefrontal',   'R'; ...
    'L_Precuneus',  'precuneus',              'L'; ...
    'R_Precuneus',  'precuneus',              'R'};

numberOfNodes = size(definitions, 1);

indices = nan(numberOfNodes, 1);
nodeLabels = string(definitions(:, 1));
atlasLabelsSelected = strings(numberOfNodes, 1);
roiVertices = cell(numberOfNodes, 1);

for iNode = 1:numberOfNodes

    regionToken = definitions{iNode, 2};
    hemisphere = definitions{iNode, 3};

    matches = false(atlasInfo.numberOfROIs, 1);

    for iAtlasROI = 1:atlasInfo.numberOfROIs

        matches(iAtlasROI) = local_region_matches( ...
            atlasInfo.labels(iAtlasROI), ...
            regionToken, ...
            hemisphere);
    end

    candidateIndices = find(matches);

    if numel(candidateIndices) ~= 1

        normalizedLabels = local_normalise_labels( ...
            atlasInfo.labels);

        regionCandidates = atlasInfo.labels(contains( ...
            normalizedLabels, ...
            local_normalise_label(regionToken)));

        error(['Could not uniquely identify %s. Candidates containing ', ...
            '"%s" were: %s'], ...
            definitions{iNode, 1}, ...
            regionToken, ...
            strjoin(regionCandidates, ' | '));
    end

    atlasIndex = candidateIndices(1);

    indices(iNode) = atlasIndex;
    atlasLabelsSelected(iNode) = ...
        atlasInfo.labels(atlasIndex);

    roiVertices{iNode} = find( ...
        atlasInfo.colorTable == atlasIndex);
end

indices = double(indices);

end


function matches = local_region_matches( ...
    atlasLabel, regionToken, hemisphere)

normalizedLabel = local_normalise_label(atlasLabel);
normalizedRegion = local_normalise_label(regionToken);

regionMatches = contains( ...
    normalizedLabel, normalizedRegion);

detectedHemisphere = ...
    local_detect_hemisphere(atlasLabel);

matches = regionMatches && ...
    strcmpi(detectedHemisphere, hemisphere);

end


function hemisphere = local_detect_hemisphere(label)

label = lower(strtrim(char(label)));

isLeft = ...
    contains(label, 'left') || ...
    startsWith(label, 'lh') || ...
    startsWith(label, 'l_') || ...
    startsWith(label, 'l-') || ...
    endsWith(label, ' lh') || ...
    endsWith(label, ' l') || ...
    ~isempty(regexp(label, ...
    '(^|[^a-z])(lh|left|l)($|[^a-z])', ...
    'once'));

isRight = ...
    contains(label, 'right') || ...
    startsWith(label, 'rh') || ...
    startsWith(label, 'r_') || ...
    startsWith(label, 'r-') || ...
    endsWith(label, ' rh') || ...
    endsWith(label, ' r') || ...
    ~isempty(regexp(label, ...
    '(^|[^a-z])(rh|right|r)($|[^a-z])', ...
    'once'));

if isLeft && ~isRight
    hemisphere = 'L';
elseif isRight && ~isLeft
    hemisphere = 'R';
else
    hemisphere = '';
end

end


function output = local_normalise_labels(labels)

output = strings(size(labels));

for iLabel = 1:numel(labels)
    output(iLabel) = ...
        local_normalise_label(labels(iLabel));
end

end


function output = local_normalise_label(label)

output = lower(string(label));
output = regexprep(output, '[^a-z0-9]', '');

end


%% =========================================================================
% Local function: convert FieldTrip leadfield to numeric array
% =========================================================================

function [leadfield, labels] = ...
    local_convert_fieldtrip_leadfield(sourcemodel)

if ~isfield(sourcemodel, 'leadfield') || ...
        isempty(sourcemodel.leadfield)

    error('EEG.dipfit.sourcemodel does not contain a leadfield.');
end

if ~isfield(sourcemodel, 'label') || ...
        isempty(sourcemodel.label)

    error('EEG.dipfit.sourcemodel does not contain channel labels.');
end

labels = string(sourcemodel.label(:));

numberOfChannels = numel(labels);
numberOfVoxels = numel(sourcemodel.leadfield);

leadfield = reshape( ...
    [sourcemodel.leadfield{:}], ...
    numberOfChannels, ...
    3, ...
    numberOfVoxels);

leadfield = permute( ...
    leadfield, [1 3 2]);

leadfield = double(leadfield);

end


%% =========================================================================
% Local function: match leadfield labels to EEGLAB channels
% =========================================================================

function channelIndices = local_match_channel_labels( ...
    sensorLabels, leadfieldLabels)

channelIndices = nan( ...
    numel(leadfieldLabels), 1);

for iLabel = 1:numel(leadfieldLabels)

    match = find(strcmpi( ...
        strtrim(sensorLabels), ...
        strtrim(leadfieldLabels(iLabel))));

    if numel(match) ~= 1
        error(['Could not uniquely match leadfield channel "%s" to the ', ...
            'EEGLAB channel list.'], ...
            leadfieldLabels(iLabel));
    end

    channelIndices(iLabel) = match;
end

channelIndices = double(channelIndices(:)');

end


%% =========================================================================
% Local function: blockwise continuous covariance
% =========================================================================

function [covarianceMatrix, qc] = ...
    local_blockwise_covariance( ...
    data, channelIndices, referenceMatrix, blockSamples)

numberOfChannels = numel(channelIndices);
numberOfSamples = size(data, 2);

sumX = zeros(numberOfChannels, 1);
sumXX = zeros(numberOfChannels, numberOfChannels);

for blockStart = 1:blockSamples:numberOfSamples

    blockEnd = min( ...
        numberOfSamples, ...
        blockStart + blockSamples - 1);

    block = referenceMatrix * double( ...
        data(channelIndices, blockStart:blockEnd));

    sumX = sumX + sum(block, 2);
    sumXX = sumXX + block * block';
end

meanX = sumX / numberOfSamples;

covarianceMatrix = ...
    (sumXX - numberOfSamples * (meanX * meanX')) / ...
    max(numberOfSamples - 1, 1);

covarianceMatrix = ...
    (covarianceMatrix + covarianceMatrix') / 2;

singularValues = svd(covarianceMatrix);

tolerance = ...
    max(size(covarianceMatrix)) * ...
    eps(max(singularValues));

qc = struct();

qc.rank = sum(singularValues > tolerance);
qc.conditionNumber = cond(covarianceMatrix);
qc.reciprocalCondition = rcond(covarianceMatrix);
qc.minimumSingularValue = min(singularValues);
qc.maximumSingularValue = max(singularValues);
qc.numberOfSamples = numberOfSamples;

end


%% =========================================================================
% Local function: evenly spaced sample indices
% =========================================================================

function indices = local_evenly_spaced_indices( ...
    numberAvailable, numberRequested)

if numberRequested >= numberAvailable
    indices = 1:numberAvailable;
    return;
end

indices = unique(round(linspace( ...
    1, numberAvailable, numberRequested)));

if numel(indices) < numberRequested

    unusedIndices = setdiff( ...
        1:numberAvailable, ...
        indices, ...
        'stable');

    numberMissing = ...
        numberRequested - numel(indices);

    indices = sort([ ...
        indices, ...
        unusedIndices(1:numberMissing)]);
end

end


%% =========================================================================
% Local function: construct ROI EEGLAB dataset
% =========================================================================

function EEG_source = local_build_source_dataset( ...
    EEG_sensor, ...
    roiData, ...
    nodeLabels, ...
    atlasLabels, ...
    roiCentroidsMNI, ...
    sourceInfo, ...
    sensorChanlocs, ...
    sensorEtc, ...
    participantBase, ...
    outputSuffix)

EEG_source = EEG_sensor;

numberOfROIs = size(roiData, 1);

EEG_source.data = roiData;
EEG_source.nbchan = numberOfROIs;
EEG_source.trials = 1;
EEG_source.pnts = size(roiData, 2);

EEG_source.setname = ...
    [participantBase, outputSuffix];

EEG_source.filename = '';
EEG_source.filepath = '';
EEG_source.datfile = '';

EEG_source.ref = 'LCMV ROI source signals';

% The output channels are anatomical ROIs rather than scalp electrodes.
EEG_source.chanlocs = repmat( ...
    local_empty_roi_chanloc(), ...
    1, numberOfROIs);

for iROI = 1:numberOfROIs

    EEG_source.chanlocs(iROI).labels = ...
        char(nodeLabels(iROI));

    EEG_source.chanlocs(iROI).type = 'ROI';

    EEG_source.chanlocs(iROI).atlas_label = ...
        char(atlasLabels(iROI));

    EEG_source.chanlocs(iROI).mni_x = ...
        roiCentroidsMNI(iROI, 1);

    EEG_source.chanlocs(iROI).mni_y = ...
        roiCentroidsMNI(iROI, 2);

    EEG_source.chanlocs(iROI).mni_z = ...
        roiCentroidsMNI(iROI, 3);

    EEG_source.chanlocs(iROI).urchan = iROI;
end

EEG_source.urchanlocs = [];
EEG_source.chaninfo = struct();

% ICA and DIPFIT fields refer to the original sensor data and must not be
% interpreted as properties of the new ROI channels.
EEG_source.icaact = [];
EEG_source.icawinv = [];
EEG_source.icasphere = [];
EEG_source.icaweights = [];
EEG_source.icachansind = [];

EEG_source.dipfit = [];
EEG_source.roi = struct();

emptyEEG = eeg_emptyset();

EEG_source.reject = emptyEEG.reject;
EEG_source.stats = emptyEEG.stats;
EEG_source.specdata = [];
EEG_source.specicaact = [];

% Preserve the sensor-level preprocessing metadata in a clearly separated
% provenance field.
EEG_source.etc = struct();

if ~isstruct(sensorEtc)
    sensorEtc = struct();
end

EEG_source.etc.sensor_level_provenance = ...
    sensorEtc;

EEG_source.etc.sensor_level_provenance.chanlocs = ...
    sensorChanlocs;

EEG_source.etc.source_reconstruction = ...
    sourceInfo;

EEG_source.roi.method = 'LCMV';
EEG_source.roi.network = 'COMM20';
EEG_source.roi.atlasName = 'Desikan-Kiliany';
EEG_source.roi.nodeLabels = cellstr(nodeLabels);
EEG_source.roi.atlasLabels = cellstr(atlasLabels);
EEG_source.roi.centroidsMNI = roiCentroidsMNI;
EEG_source.roi.sensorToROIFilters = ...
    sourceInfo.sensorToROIFilters;
EEG_source.roi.firstPCVarianceExplained = ...
    sourceInfo.firstPCVarianceExplained;

existingComments = EEG_source.comments;

if iscell(existingComments)
    existingComments = strjoin(string(existingComments), newline);
end

existingComments = char(string(existingComments));

EEG_source.comments = sprintf( ...
    ['%s\nContinuous ROI source dataset generated using ', ...
    'ROIconnect LCMV and one PCA direction per ROI.'], ...
    existingComments);

EEG_source.saved = 'no';

EEG_source = eeg_checkset( ...
    EEG_source, 'eventconsistency');

EEG_source = eeg_checkset( ...
    EEG_source, 'chanconsist');

end


function chanloc = local_empty_roi_chanloc()

chanloc = struct( ...
    'labels', '', ...
    'type', '', ...
    'theta', [], ...
    'radius', [], ...
    'X', [], ...
    'Y', [], ...
    'Z', [], ...
    'sph_theta', [], ...
    'sph_phi', [], ...
    'sph_radius', [], ...
    'urchan', [], ...
    'ref', '', ...
    'atlas_label', '', ...
    'mni_x', [], ...
    'mni_y', [], ...
    'mni_z', []);

end


%% =========================================================================
% Local function: source-signal QC
% =========================================================================

function qc = local_source_qc(roiData)

X = double(roiData');

roiVariances = var(X, 0, 1);

positiveVariances = ...
    roiVariances(roiVariances > 0 & ...
    isfinite(roiVariances));

if isempty(positiveVariances)
    varianceReference = 0;
else
    varianceReference = median(positiveVariances);
end

nearZeroThreshold = max( ...
    varianceReference * 1e-8, eps);

nearZeroMask = ...
    roiVariances <= nearZeroThreshold | ...
    ~isfinite(roiVariances);

correlationMatrix = corrcoef( ...
    X, 'Rows', 'pairwise');

offDiagonalMask = ...
    ~eye(size(correlationMatrix, 1));

offDiagonalValues = abs( ...
    correlationMatrix(offDiagonalMask));

offDiagonalValues = ...
    offDiagonalValues(isfinite(offDiagonalValues));

sourceCovariance = cov(X, 1);
sourceSingularValues = svd(sourceCovariance);

rankTolerance = ...
    max(size(sourceCovariance)) * ...
    eps(max(sourceSingularValues));

qc = struct();

qc.sourceRank = ...
    sum(sourceSingularValues > rankTolerance);

qc.numberNearZeroVarianceROIs = ...
    sum(nearZeroMask);

qc.nearZeroVarianceROIIndices = ...
    find(nearZeroMask);

qc.minimumROIVariance = ...
    min(roiVariances);

qc.medianROIVariance = ...
    median(roiVariances);

qc.maximumROIVariance = ...
    max(roiVariances);

qc.finitePercent = ...
    100 * mean(isfinite(X(:)));

qc.sourceCorrelationMatrix = ...
    correlationMatrix;

if isempty(offDiagonalValues)

    qc.medianAbsoluteROICorrelation = NaN;
    qc.maximumAbsoluteROICorrelation = NaN;

else

    qc.medianAbsoluteROICorrelation = ...
        median(offDiagonalValues);

    qc.maximumAbsoluteROICorrelation = ...
        max(offDiagonalValues);
end

end


%% =========================================================================
% Local function: DIPFIT validation and provenance
% =========================================================================

function local_validate_dipfit_settings(EEG, participantBase)

requiredFields = { ...
    'hdmfile', ...
    'mrifile', ...
    'chanfile', ...
    'coordformat', ...
    'coord_transform', ...
    'chansel'};

if ~isfield(EEG, 'dipfit') || ...
        isempty(EEG.dipfit)

    error('%s has no DIPFIT settings.', participantBase);
end

for iField = 1:numel(requiredFields)

    fieldName = requiredFields{iField};

    if ~isfield(EEG.dipfit, fieldName) || ...
            isempty(EEG.dipfit.(fieldName))

        error('%s is missing EEG.dipfit.%s.', ...
            participantBase, fieldName);
    end
end

if ~strcmpi(EEG.dipfit.coordformat, 'MNI')
    error('%s DIPFIT coordinate format is not MNI.', ...
        participantBase);
end

if numel(EEG.dipfit.coord_transform) ~= 9 || ...
        any(~isfinite(EEG.dipfit.coord_transform))

    error('%s has an invalid DIPFIT coordinate transformation.', ...
        participantBase);
end

end


function output = local_small_dipfit_provenance(dipfit)

fieldsToCopy = { ...
    'hdmfile', ...
    'mrifile', ...
    'chanfile', ...
    'coordformat', ...
    'coord_transform', ...
    'chansel'};

output = struct();

for iField = 1:numel(fieldsToCopy)

    fieldName = fieldsToCopy{iField};

    if isfield(dipfit, fieldName)
        output.(fieldName) = dipfit.(fieldName);
    end
end

end


%% =========================================================================
% Local function: event capture and verification
% =========================================================================

function eventInfo = local_capture_event_info(EEG)

eventInfo = struct();

eventInfo.samplingRate = EEG.srate;
eventInfo.numberOfSamples = EEG.pnts;
eventInfo.numberOfEvents = numel(EEG.event);

if isempty(EEG.event)

    eventInfo.latencies = [];
    eventInfo.types = strings(0, 1);
    eventInfo.values = cell(0, 1);
    return;
end

eventInfo.latencies = ...
    double([EEG.event.latency]);

eventInfo.types = ...
    string({EEG.event.type});

eventInfo.values = cell( ...
    numel(EEG.event), 1);

for iEvent = 1:numel(EEG.event)

    if isfield(EEG.event, 'value')
        eventInfo.values{iEvent} = ...
            EEG.event(iEvent).value;
    else
        eventInfo.values{iEvent} = [];
    end
end

end


function local_assert_event_info_equal( ...
    observed, expected, description)

if observed.numberOfEvents ~= expected.numberOfEvents
    error('%s: event count changed from %d to %d.', ...
        description, ...
        expected.numberOfEvents, ...
        observed.numberOfEvents);
end

if observed.numberOfSamples ~= expected.numberOfSamples
    error('%s: sample count changed from %d to %d.', ...
        description, ...
        expected.numberOfSamples, ...
        observed.numberOfSamples);
end

if ~isequaln(observed.latencies, expected.latencies)
    error('%s: event latencies changed.', description);
end

if ~isequaln(observed.types, expected.types)
    error('%s: event types changed.', description);
end

end


%% =========================================================================
% Local function: verify dyadic alignment
% =========================================================================

function local_assert_dyad_alignment( ...
    EEG_A, EEG_B, dyadStr)

if EEG_A.trials ~= EEG_B.trials
    error('Trial-count mismatch between A and B in %s.', ...
        dyadStr);
end

if EEG_A.srate ~= EEG_B.srate
    error(['Sampling-rate mismatch in %s: A=%.6f Hz, B=%.6f Hz.'], ...
        dyadStr, ...
        EEG_A.srate, ...
        EEG_B.srate);
end

if EEG_A.pnts ~= EEG_B.pnts
    error(['Sample-count mismatch in %s: A=%d, B=%d.'], ...
        dyadStr, ...
        EEG_A.pnts, ...
        EEG_B.pnts);
end

latenciesA = double([EEG_A.event.latency]);
latenciesB = double([EEG_B.event.latency]);

if numel(latenciesA) ~= numel(latenciesB)
    error(['Event-count mismatch in %s: A=%d, B=%d.'], ...
        dyadStr, ...
        numel(latenciesA), ...
        numel(latenciesB));
end

if any(abs(latenciesA - latenciesB) > 1e-6)
    error('Event latencies are not aligned between A and B in %s.', ...
        dyadStr);
end

end


%% =========================================================================
% Local function: QC figure
% =========================================================================

function local_save_correlation_figure( ...
    correlationMatrix, nodeLabels, figureTitle, outputFile)

figureHandle = figure( ...
    'Visible', 'off', ...
    'Position', [100 100 900 760]);

imagesc(correlationMatrix, [-1 1]);
axis square;
colorbar;

title(figureTitle, 'Interpreter', 'none');

xticks(1:numel(nodeLabels));
yticks(1:numel(nodeLabels));

xticklabels(nodeLabels);
yticklabels(nodeLabels);

xtickangle(90);

set(gca, 'TickLabelInterpreter', 'none');

exportgraphics( ...
    figureHandle, ...
    outputFile, ...
    'Resolution', 160);

close(figureHandle);

end


%% =========================================================================
% Local function: fill summary record
% =========================================================================

function record = local_fill_summary_record( ...
    record, qc, EEG_source)

record.OutputSamplingRate = ...
    EEG_source.srate;

record.OutputSamples = ...
    EEG_source.pnts;

record.OutputDurationMinutes = ...
    EEG_source.pnts / EEG_source.srate / 60;

record.NROIs = ...
    EEG_source.nbchan;

record.NEvents = ...
    qc.markerCount;

record.NBlockStartEvents = ...
    qc.blockStartCount;

record.MarkersPreserved = ...
    qc.markersPreserved;

record.SensorRank = ...
    qc.sensorRank;

record.SensorCovarianceCondition = ...
    qc.sensorCovarianceCondition;

record.SensorCovarianceReciprocalCondition = ...
    qc.sensorCovarianceReciprocalCondition;

record.RegularizationAlpha = ...
    qc.regularizationAlpha;

record.MinimumFirstPCVarianceExplained = ...
    qc.minimumFirstPCVarianceExplained;

record.MedianFirstPCVarianceExplained = ...
    qc.medianFirstPCVarianceExplained;

record.MaximumFirstPCVarianceExplained = ...
    qc.maximumFirstPCVarianceExplained;

record.SourceRank = ...
    qc.sourceRank;

record.NNearZeroVarianceROIs = ...
    qc.numberNearZeroVarianceROIs;

record.SourceFinitePercent = ...
    qc.finitePercent;

record.MedianAbsoluteROICorrelation = ...
    qc.medianAbsoluteROICorrelation;

record.MaximumAbsoluteROICorrelation = ...
    qc.maximumAbsoluteROICorrelation;

record.SourceElapsedMinutes = ...
    qc.sourceElapsedMinutes;

end


%% =========================================================================
% Local function: empty summary record
% =========================================================================

function record = local_empty_summary_record()

record = struct( ...
    'Dyad', NaN, ...
    'Member', "", ...
    'Participant', "", ...
    'InputFile', "", ...
    'OutputFile', "", ...
    'OutputSamplingRate', NaN, ...
    'OutputSamples', NaN, ...
    'OutputDurationMinutes', NaN, ...
    'NROIs', NaN, ...
    'NEvents', NaN, ...
    'NBlockStartEvents', NaN, ...
    'MarkersPreserved', false, ...
    'SensorRank', NaN, ...
    'SensorCovarianceCondition', NaN, ...
    'SensorCovarianceReciprocalCondition', NaN, ...
    'RegularizationAlpha', NaN, ...
    'MinimumFirstPCVarianceExplained', NaN, ...
    'MedianFirstPCVarianceExplained', NaN, ...
    'MaximumFirstPCVarianceExplained', NaN, ...
    'SourceRank', NaN, ...
    'NNearZeroVarianceROIs', NaN, ...
    'SourceFinitePercent', NaN, ...
    'MedianAbsoluteROICorrelation', NaN, ...
    'MaximumAbsoluteROICorrelation', NaN, ...
    'SourceElapsedMinutes', NaN, ...
    'Status', "", ...
    'ElapsedMinutes', NaN, ...
    'Notes', "");

end
