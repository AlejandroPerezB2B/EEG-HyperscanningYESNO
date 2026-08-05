function summaryTable = step4_remove_eye_ICs_HyperYESNO( ...
    rootDir, dyads, eyeThreshold, overwriteExisting)
% STEP4_REMOVE_EYE_ICS_HYPERYESNO
% Automatically remove ICA components classified by ICLabel as Eye with a
% probability greater than a specified threshold.
%
% The default threshold is 0.70. Therefore, a component is removed when:
%
%       ICLabel Eye probability > 0.70
%
% A component with a probability exactly equal to 0.70 is retained.
%
% INPUT DATA
% ----------
% The function loads the exact datasets:
%
%   DyadXX/SubjA/DyadXX-A_PREP_ASR_ICA.set
%   DyadXX/SubjB/DyadXX-B_PREP_ASR_ICA.set
%
% OUTPUT DATA
% -----------
% With the default threshold, the cleaned datasets are saved as:
%
%   DyadXX/SubjA/DyadXX-A_PREP_ASR_ICA_EYE70.set
%   DyadXX/SubjB/DyadXX-B_PREP_ASR_ICA_EYE70.set
%
% The original _PREP_ASR_ICA datasets are not modified.
%
% PROCESSING
% ----------
% For each participant, the function:
%
%   1. Loads the existing _PREP_ASR_ICA dataset.
%   2. Reads the ICLabel classification probabilities.
%   3. Identifies the Eye class by its ICLabel class name, with column 3
%      used only as a fallback for compatibility with standard ICLabel.
%   4. Removes all ICs with Eye probability greater than eyeThreshold using
%      pop_subcomp().
%   5. Retains the remaining ICA weights, ICLabel classifications, and
%      DIPFIT models.
%   6. Stores the original ICLabel matrix, removed component indices, and
%      probabilities in:
%
%      EEG.etc.hyperyesno_step4_eye_ic_removal
%
%   7. Verifies that no samples or event latencies changed. ICA component
%      subtraction does not delete samples, so A and B remain exactly
%      synchronised.
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
% eyeThreshold
%   ICLabel Eye probability threshold.
%   Default: 0.70
%
% overwriteExisting
%   false: do not overwrite an existing output dataset.
%   true : overwrite an existing output dataset.
%   Default: false
%
% OUTPUT
% ------
% summaryTable
%   One row per participant with the original number of components, removed
%   component indices, Eye probabilities, remaining number of components,
%   and processing status.
%
% The summary is also saved as:
%
%   Step4_ICLabel_EYE70_summary.xlsx
%   Step4_ICLabel_EYE70_summary.mat
%
% EXAMPLES
% --------
% Test one dyad:
%
%   eeglab;
%   close;
%
%   summaryTable = step4_remove_eye_ICs_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1, 0.70, false);
%
% Process all dyads:
%
%   summaryTable = step4_remove_eye_ICs_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1:35, 0.70, false);
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

%% ========================================================================
% 1. Defaults
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

if nargin < 3 || isempty(eyeThreshold)
    eyeThreshold = 0.70;
end

if nargin < 4 || isempty(overwriteExisting)
    overwriteExisting = false;
end

rootDir = char(rootDir);

validateattributes(dyads, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'});

validateattributes(eyeThreshold, {'numeric'}, ...
    {'scalar', 'real', 'finite', '>=', 0, '<=', 1});

validateattributes(overwriteExisting, {'logical', 'numeric'}, ...
    {'scalar'});

overwriteExisting = logical(overwriteExisting);

if exist(rootDir, 'dir') ~= 7
    error('HyperYESNO root directory not found: %s', rootDir);
end

requiredFunctions = {'pop_loadset', 'pop_saveset', 'pop_subcomp'};

for iFunction = 1:numel(requiredFunctions)
    if exist(requiredFunctions{iFunction}, 'file') ~= 2
        error(['Required function "%s" was not found. Start EEGLAB ', ...
            'before running this function.'], ...
            requiredFunctions{iFunction});
    end
end

tags = {'A', 'B'};

inputSuffix = '_PREP_ASR_ICA';

thresholdPercent = round(100 * eyeThreshold);
outputSuffix = sprintf('%s_EYE%d', inputSuffix, thresholdPercent);

summaryBaseName = sprintf( ...
    'Step4_ICLabel_EYE%d_summary', thresholdPercent);

%% ========================================================================
% 2. Preallocate participant-level records
% ========================================================================

nParticipants = numel(dyads) * numel(tags);
records = repmat(local_empty_record(), nParticipants, 1);

recordCounter = 0;
pipelineTimer = tic;

%% ========================================================================
% 3. Process every dyad
% ========================================================================

for iDyad = 1:numel(dyads)

    d = dyads(iDyad);
    dyadStr = sprintf('Dyad%02d', d);
    dyadTimer = tic;

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('Step 4 ICLabel Eye removal: %s\n', dyadStr);
    fprintf('Eye threshold: probability > %.2f\n', eyeThreshold);
    fprintf('============================================================\n');

    participantFolders = { ...
        fullfile(rootDir, dyadStr, 'SubjA'), ...
        fullfile(rootDir, dyadStr, 'SubjB')};

    participantBases = { ...
        sprintf('%s-A', dyadStr), ...
        sprintf('%s-B', dyadStr)};

    inputFiles = { ...
        [participantBases{1}, inputSuffix, '.set'], ...
        [participantBases{2}, inputSuffix, '.set']};

    outputFiles = { ...
        [participantBases{1}, outputSuffix, '.set'], ...
        [participantBases{2}, outputSuffix, '.set']};

    inputPaths = { ...
        fullfile(participantFolders{1}, inputFiles{1}), ...
        fullfile(participantFolders{2}, inputFiles{2})};

    outputPaths = { ...
        fullfile(participantFolders{1}, outputFiles{1}), ...
        fullfile(participantFolders{2}, outputFiles{2})};

    % Create the two participant records before attempting the dyad.
    dyadRecordIndices = recordCounter + (1:2);

    for iTag = 1:2

        recordCounter = recordCounter + 1;

        records(recordCounter).Dyad = d;
        records(recordCounter).Member = string(tags{iTag});
        records(recordCounter).Participant = ...
            string(participantBases{iTag});
        records(recordCounter).InputFile = ...
            string(inputPaths{iTag});
        records(recordCounter).OutputFile = ...
            string(outputPaths{iTag});
        records(recordCounter).EyeThreshold = eyeThreshold;
    end

    try

        %% ----------------------------------------------------------------
        % 3.1 Confirm both exact inputs exist
        % -----------------------------------------------------------------

        for iTag = 1:2
            if exist(inputPaths{iTag}, 'file') ~= 2
                error('Input dataset not found: %s', inputPaths{iTag});
            end
        end

        %% ----------------------------------------------------------------
        % 3.2 Protect existing outputs unless overwrite is requested
        % -----------------------------------------------------------------

        existingOutputs = cellfun( ...
            @(filePath) exist(filePath, 'file') == 2, ...
            outputPaths);

        if any(existingOutputs) && ~overwriteExisting

            existingList = strjoin( ...
                string(outputPaths(existingOutputs)), newline);

            error(['One or more output datasets already exist and ', ...
                'overwriteExisting is false:\n%s'], existingList);
        end

        %% ----------------------------------------------------------------
        % 3.3 Load both members of the dyad
        % -----------------------------------------------------------------

        EEG_A = pop_loadset( ...
            'filename', inputFiles{1}, ...
            'filepath', participantFolders{1});

        EEG_B = pop_loadset( ...
            'filename', inputFiles{2}, ...
            'filepath', participantFolders{2});

        EEG_A = eeg_checkset(EEG_A, 'eventconsistency');
        EEG_B = eeg_checkset(EEG_B, 'eventconsistency');

        %% ----------------------------------------------------------------
        % 3.4 Verify dyadic synchronisation before IC removal
        % -----------------------------------------------------------------

        local_assert_dyad_alignment(EEG_A, EEG_B, dyadStr);

        originalSamples = EEG_A.pnts;

        originalLatenciesA = double([EEG_A.event.latency]);
        originalLatenciesB = double([EEG_B.event.latency]);

        %% ----------------------------------------------------------------
        % 3.5 Remove Eye ICs independently from A and B
        % -----------------------------------------------------------------

        fprintf('\nProcessing %s-A...\n', dyadStr);

        [EEG_A, infoA] = local_remove_eye_components( ...
            EEG_A, eyeThreshold);

        fprintf('\nProcessing %s-B...\n', dyadStr);

        [EEG_B, infoB] = local_remove_eye_components( ...
            EEG_B, eyeThreshold);

        %% ----------------------------------------------------------------
        % 3.6 Confirm samples and events remain unchanged
        % -----------------------------------------------------------------

        if EEG_A.pnts ~= originalSamples || EEG_B.pnts ~= originalSamples
            error(['ICA component subtraction unexpectedly changed the ', ...
                'number of samples in %s.'], dyadStr);
        end

        newLatenciesA = double([EEG_A.event.latency]);
        newLatenciesB = double([EEG_B.event.latency]);

        if ~isequal(originalLatenciesA, newLatenciesA) || ...
                ~isequal(originalLatenciesB, newLatenciesB)
            error(['ICA component subtraction unexpectedly changed event ', ...
                'latencies in %s.'], dyadStr);
        end

        local_assert_dyad_alignment(EEG_A, EEG_B, dyadStr);

        %% ----------------------------------------------------------------
        % 3.7 Set output names and save
        % -----------------------------------------------------------------

        EEG_A.setname = [participantBases{1}, outputSuffix];
        EEG_B.setname = [participantBases{2}, outputSuffix];

        EEG_A = pop_saveset( ...
            EEG_A, ...
            'filename', outputFiles{1}, ...
            'filepath', participantFolders{1}, ...
            'savemode', 'twofiles');

        fprintf('Saved: %s\n', outputPaths{1});

        EEG_B = pop_saveset( ...
            EEG_B, ...
            'filename', outputFiles{2}, ...
            'filepath', participantFolders{2}, ...
            'savemode', 'twofiles');

        fprintf('Saved: %s\n', outputPaths{2});

        %% ----------------------------------------------------------------
        % 3.8 Fill participant summary records
        % -----------------------------------------------------------------

        records(dyadRecordIndices(1)) = local_fill_record( ...
            records(dyadRecordIndices(1)), infoA);

        records(dyadRecordIndices(2)) = local_fill_record( ...
            records(dyadRecordIndices(2)), infoB);

        records(dyadRecordIndices(1)).Status = "completed";
        records(dyadRecordIndices(2)).Status = "completed";

        elapsedMinutes = toc(dyadTimer) / 60;

        records(dyadRecordIndices(1)).ElapsedMinutes = ...
            elapsedMinutes;
        records(dyadRecordIndices(2)).ElapsedMinutes = ...
            elapsedMinutes;

        clear EEG_A EEG_B

    catch ME

        fprintf(2, '\nFAILED %s\n%s\n', dyadStr, ME.message);

        for iRecord = dyadRecordIndices
            records(iRecord).Status = "failed";
            records(iRecord).Notes = string(ME.message);
            records(iRecord).ElapsedMinutes = toc(dyadTimer) / 60;
        end

        clear EEG_A EEG_B
    end
end

%% ========================================================================
% 4. Save summary
% ========================================================================

summaryTable = struct2table(records);

summaryExcelFile = fullfile( ...
    rootDir, [summaryBaseName, '.xlsx']);

summaryMatFile = fullfile( ...
    rootDir, [summaryBaseName, '.mat']);

writetable(summaryTable, summaryExcelFile);
save(summaryMatFile, 'summaryTable');

fprintf('\n');
fprintf('============================================================\n');
fprintf('Step 4 finished in %.2f minutes.\n', toc(pipelineTimer) / 60);
fprintf('Summary Excel file: %s\n', summaryExcelFile);
fprintf('Summary MAT file:   %s\n', summaryMatFile);
fprintf('============================================================\n');

end


%% =========================================================================
% Local helper: remove ICLabel Eye components
% =========================================================================

function [EEG, info] = local_remove_eye_components( ...
    EEG, eyeThreshold)
% Remove ICs whose ICLabel Eye probability is greater than the threshold.

if ~isfield(EEG, 'icaweights') || isempty(EEG.icaweights)
    error('The dataset does not contain ICA weights.');
end

if ~isfield(EEG, 'etc') || ...
        ~isfield(EEG.etc, 'ic_classification') || ...
        ~isfield(EEG.etc.ic_classification, 'ICLabel') || ...
        ~isfield( ...
            EEG.etc.ic_classification.ICLabel, ...
            'classifications') || ...
        isempty( ...
            EEG.etc.ic_classification.ICLabel.classifications)

    error(['The dataset does not contain ICLabel classifications. ', ...
        'Run ICLabel before Step 4.']);
end

iclabelStruct = EEG.etc.ic_classification.ICLabel;
classifications = double(iclabelStruct.classifications);

numberOfComponents = size(EEG.icaweights, 1);

if size(classifications, 1) ~= numberOfComponents
    error(['ICLabel contains %d component rows, but the ICA solution ', ...
        'contains %d components.'], ...
        size(classifications, 1), numberOfComponents);
end

% Identify the Eye class by name where possible.
eyeColumn = [];

if isfield(iclabelStruct, 'classes') && ...
        ~isempty(iclabelStruct.classes)

    classNames = string(iclabelStruct.classes);
    eyeColumn = find(strcmpi(strtrim(classNames), "Eye"), 1);
end

% Standard ICLabel column order:
% Brain, Muscle, Eye, Heart, Line Noise, Channel Noise, Other.
if isempty(eyeColumn)

    if size(classifications, 2) < 3
        error('ICLabel classification matrix does not contain an Eye column.');
    end

    eyeColumn = 3;
end

eyeProbabilities = classifications(:, eyeColumn);

% The user requested strictly more than 70%, not greater than or equal.
eyeComponents = find(eyeProbabilities > eyeThreshold);
remainingComponents = setdiff( ...
    1:numberOfComponents, eyeComponents);

fprintf('  Original ICA components:  %d\n', numberOfComponents);
fprintf('  Eye ICs above threshold:  %d\n', numel(eyeComponents));

if isempty(eyeComponents)
    fprintf('  No ICA components were removed.\n');
else
    fprintf('  Removed component indices: %s\n', ...
        strjoin(string(eyeComponents(:)'), ', '));

    fprintf('  Eye probabilities:         %s\n', ...
        strjoin(compose('%.3f', ...
        eyeProbabilities(eyeComponents)), ', '));
end

% Save complete provenance before pop_subcomp reduces the ICA and ICLabel
% structures to the retained components.
removalInfo = struct();

removalInfo.date = char(datetime('now'));
removalInfo.method = ...
    'ICLabel Eye probability threshold followed by pop_subcomp';
removalInfo.eyeThreshold = eyeThreshold;
removalInfo.comparison = 'strictly greater than';
removalInfo.eyeClassColumn = eyeColumn;
removalInfo.originalNumberOfComponents = ...
    numberOfComponents;
removalInfo.originalICLabelClassifications = ...
    classifications;

if isfield(iclabelStruct, 'classes')
    removalInfo.ICLabelClasses = ...
        iclabelStruct.classes;
else
    removalInfo.ICLabelClasses = { ...
        'Brain', 'Muscle', 'Eye', 'Heart', ...
        'Line Noise', 'Channel Noise', 'Other'};
end

removalInfo.removedOriginalComponentIndices = ...
    eyeComponents(:)';
removalInfo.removedEyeProbabilities = ...
    eyeProbabilities(eyeComponents)';
removalInfo.retainedOriginalComponentIndices = ...
    remainingComponents(:)';

% Remove the selected components without opening confirmation plots.
if ~isempty(eyeComponents)
    EEG = pop_subcomp(EEG, eyeComponents(:)', 0);
end

EEG = eeg_checkset(EEG, 'ica');
EEG = eeg_checkset(EEG);

removalInfo.remainingNumberOfComponents = ...
    size(EEG.icaweights, 1);

EEG.etc.hyperyesno_step4_eye_ic_removal = ...
    removalInfo;

info = struct();

info.originalNumberOfComponents = ...
    numberOfComponents;
info.numberOfRemovedEyeComponents = ...
    numel(eyeComponents);
info.removedOriginalComponentIndices = ...
    eyeComponents(:)';
info.removedEyeProbabilities = ...
    eyeProbabilities(eyeComponents)';
info.numberOfRemainingComponents = ...
    size(EEG.icaweights, 1);
info.maximumEyeProbability = ...
    max(eyeProbabilities);

if isempty(eyeComponents)
    info.meanRemovedEyeProbability = NaN;
    info.minimumRemovedEyeProbability = NaN;
else
    info.meanRemovedEyeProbability = ...
        mean(eyeProbabilities(eyeComponents));
    info.minimumRemovedEyeProbability = ...
        min(eyeProbabilities(eyeComponents));
end

end


%% =========================================================================
% Local helper: verify dyadic alignment
% =========================================================================

function local_assert_dyad_alignment(EEG_A, EEG_B, dyadStr)
% Verify that A and B retain the same time samples and event latencies.

if EEG_A.srate ~= EEG_B.srate
    error(['Sampling-rate mismatch in %s: A = %.6f Hz, ', ...
        'B = %.6f Hz.'], ...
        dyadStr, EEG_A.srate, EEG_B.srate);
end

if EEG_A.pnts ~= EEG_B.pnts
    error(['Sample-count mismatch in %s: A = %d, B = %d.'], ...
        dyadStr, EEG_A.pnts, EEG_B.pnts);
end

latenciesA = double([EEG_A.event.latency]);
latenciesB = double([EEG_B.event.latency]);

if numel(latenciesA) ~= numel(latenciesB)
    error(['Event-count mismatch in %s: A = %d, B = %d.'], ...
        dyadStr, numel(latenciesA), numel(latenciesB));
end

if any(abs(latenciesA - latenciesB) > 1e-6)
    error('Event latencies are not aligned in %s.', dyadStr);
end

end


%% =========================================================================
% Local helper: fill participant summary
% =========================================================================

function record = local_fill_record(record, info)

record.NOriginalICs = ...
    info.originalNumberOfComponents;

record.NRemovedEyeICs = ...
    info.numberOfRemovedEyeComponents;

record.RemovedOriginalICIndices = ...
    local_numeric_vector_to_string( ...
    info.removedOriginalComponentIndices, '%d');

record.RemovedEyeProbabilities = ...
    local_numeric_vector_to_string( ...
    info.removedEyeProbabilities, '%.4f');

record.NRemainingICs = ...
    info.numberOfRemainingComponents;

record.MaximumEyeProbability = ...
    info.maximumEyeProbability;

record.MeanRemovedEyeProbability = ...
    info.meanRemovedEyeProbability;

record.MinimumRemovedEyeProbability = ...
    info.minimumRemovedEyeProbability;

end


%% =========================================================================
% Local helper: numeric vector to string
% =========================================================================

function outputString = local_numeric_vector_to_string( ...
    values, numberFormat)

if isempty(values)
    outputString = "";
    return;
end

formattedValues = compose(numberFormat, values(:)');
outputString = strjoin(formattedValues, ", ");

end


%% =========================================================================
% Local helper: empty record
% =========================================================================

function record = local_empty_record()

record = struct( ...
    'Dyad', NaN, ...
    'Member', "", ...
    'Participant', "", ...
    'InputFile', "", ...
    'OutputFile', "", ...
    'EyeThreshold', NaN, ...
    'NOriginalICs', NaN, ...
    'NRemovedEyeICs', NaN, ...
    'RemovedOriginalICIndices', "", ...
    'RemovedEyeProbabilities', "", ...
    'NRemainingICs', NaN, ...
    'MaximumEyeProbability', NaN, ...
    'MeanRemovedEyeProbability', NaN, ...
    'MinimumRemovedEyeProbability', NaN, ...
    'Status', "", ...
    'ElapsedMinutes', NaN, ...
    'Notes', "");

end
