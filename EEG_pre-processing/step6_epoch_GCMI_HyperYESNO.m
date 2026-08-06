function summaryTable = step6_epoch_GCMI_HyperYESNO(rootDir, dyads, epochWindowSeconds, varargin)
% STEP6_EPOCH_GCMI_HYPERYESNO
% Epoch continuous HyperYESNO ROI datasets and save matched, role-normalized
% Knower/Guesser files for later lagged-GCMI analysis.
%
% FOUR EXPERIMENTAL SITUATIONS
% ----------------------------
% YES_AKnower: Knower = A, Guesser = B
% NO_AKnower : Knower = A, Guesser = B
% YES_BKnower: Knower = B, Guesser = A
% NO_BKnower : Knower = B, Guesser = A
%
% The input is organized by participant identity (SubjA/SubjB), whereas the
% output is organized by analytical role (Knower/Guesser). This ensures that
% a later GCMI wrapper can always load the Knower dataset first and the
% Guesser dataset second, regardless of whether the Knower came from SubjA
% or SubjB.
%
% DEFAULT INPUTS
% --------------
% DyadXX/SubjA/DyadXX-A_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
% DyadXX/SubjB/DyadXX-B_PREP_ASR_ICA_EYE70_LCMV_COMM20.set
%
% DEFAULT OUTPUT STRUCTURE
% ------------------------
% DyadXX/GCMI_Epochs/YES_AKnower/
%   DyadXX_YES_AKnower_Knower_fromA.set
%   DyadXX_YES_AKnower_Guesser_fromB.set
%
% DyadXX/GCMI_Epochs/NO_AKnower/
% DyadXX/GCMI_Epochs/YES_BKnower/
% DyadXX/GCMI_Epochs/NO_BKnower/
%
% MATCHING RULE
% -------------
% A common marker list is established once from the aligned dyad event
% structure. Any epoch that extends outside the recording or crosses a
% boundary event is excluded from BOTH participants. The remaining epochs
% are extracted in the same order and receive identical pair IDs.
%
% FILTERING
% ---------
% Optional filtering is applied to the continuous ROI signals before
% epoching. This avoids filtering each short epoch independently.
%
% INPUTS
% ------
% rootDir
%   HyperYESNO root directory.
%   Default: 'E:\EEG_data_HyperYESNO'
%
% dyads
%   Dyad numbers to process.
%   Default: 1:35
%
% epochWindowSeconds
%   Two-element epoch window relative to the marker, in seconds.
%   Example: [-2 1]
%
% NAME-VALUE OPTIONS
% ------------------
% 'InputSuffix'
%   Default: '_PREP_ASR_ICA_EYE70_LCMV_COMM20'
%
% 'OutputFolderName'
%   Default: 'GCMI_Epochs'
%
% 'FilterBand'
%   [] or [low high] in Hz. Filtering is performed before epoching.
%   Default: []
%
% 'BaselineWindowSeconds'
%   [] or [start end] relative to the marker, in seconds.
%   Default: []
%
% 'OverwriteExisting'
%   Default: false
%
% 'SaveTrialTables'
%   Default: true
%
% OUTPUT
% ------
% summaryTable
%   One row per dyad and experimental situation.
%
% EXAMPLES
% --------
% Test one dyad:
%
%   eeglab;
%   close;
%
%   T = step6_epoch_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1, [-2 1]);
%
% Apply a 2-10 Hz continuous filter before epoching:
%
%   T = step6_epoch_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1, [-2 1], ...
%       'FilterBand', [2 10]);
%
% Process all dyads:
%
%   T = step6_epoch_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', 1:35, [-2 1], ...
%       'FilterBand', [2 10]);
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

%% ========================================================================
% 1. Defaults and options
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

if nargin < 3 || isempty(epochWindowSeconds)
    error(['Specify epochWindowSeconds explicitly, for example ', ...
        '[-2 1].']);
end

rootDir = char(rootDir);
epochWindowSeconds = double(epochWindowSeconds(:)');

validateattributes(dyads, {'numeric'}, ...
    {'vector','integer','positive','finite'});

validateattributes(epochWindowSeconds, {'numeric'}, ...
    {'vector','numel',2,'real','finite'});

if epochWindowSeconds(2) <= epochWindowSeconds(1)
    error('epochWindowSeconds must satisfy end > start.');
end

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, 'InputSuffix', ...
    '_PREP_ASR_ICA_EYE70_LCMV_COMM20', ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, 'OutputFolderName', ...
    'GCMI_Epochs', ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, 'FilterBand', [], ...
    @(x) isempty(x) || ...
    (isnumeric(x) && numel(x) == 2 && ...
    all(isfinite(x)) && x(1) > 0 && x(2) > x(1)));

addParameter(parser, 'BaselineWindowSeconds', [], ...
    @(x) isempty(x) || ...
    (isnumeric(x) && numel(x) == 2 && ...
    all(isfinite(x)) && x(2) > x(1)));

addParameter(parser, 'OverwriteExisting', false, ...
    @(x) islogical(x) || (isnumeric(x) && isscalar(x)));

addParameter(parser, 'SaveTrialTables', true, ...
    @(x) islogical(x) || (isnumeric(x) && isscalar(x)));

parse(parser, varargin{:});
options = parser.Results;

options.InputSuffix = char(options.InputSuffix);
options.OutputFolderName = char(options.OutputFolderName);
options.FilterBand = double(options.FilterBand(:)');
options.BaselineWindowSeconds = ...
    double(options.BaselineWindowSeconds(:)');
options.OverwriteExisting = logical(options.OverwriteExisting);
options.SaveTrialTables = logical(options.SaveTrialTables);

if ~isempty(options.BaselineWindowSeconds)
    if options.BaselineWindowSeconds(1) < epochWindowSeconds(1) || ...
            options.BaselineWindowSeconds(2) > epochWindowSeconds(2)
        error(['BaselineWindowSeconds must lie entirely inside ', ...
            'epochWindowSeconds.']);
    end
end

if exist(rootDir, 'dir') ~= 7
    error('HyperYESNO root directory not found: %s', rootDir);
end

%% ========================================================================
% 2. Dependencies
% ========================================================================

requiredFunctions = {'pop_loadset','pop_saveset','pop_epoch','eeg_checkset'};

if ~isempty(options.FilterBand)
    requiredFunctions{end+1} = 'pop_eegfiltnew';
end

if ~isempty(options.BaselineWindowSeconds)
    requiredFunctions{end+1} = 'pop_rmbase';
end

for iFunction = 1:numel(requiredFunctions)
    if exist(requiredFunctions{iFunction}, 'file') ~= 2
        error(['Required function "%s" was not found. Start EEGLAB ', ...
            'and check the installation.'], requiredFunctions{iFunction});
    end
end

%% ========================================================================
% 3. Experimental situations
% ========================================================================

situations = struct( ...
    'marker', {'YES_AKnower','NO_AKnower','YES_BKnower','NO_BKnower'}, ...
    'condition', {'YES','NO','YES','NO'}, ...
    'knowerParticipant', {'A','A','B','B'}, ...
    'guesserParticipant', {'B','B','A','A'});

nSituations = numel(situations);

%% ========================================================================
% 4. Summary allocation
% ========================================================================

records = repmat(local_empty_record(), numel(dyads)*nSituations, 1);
recordCounter = 0;
pipelineTimer = tic;

%% ========================================================================
% 5. Process dyads
% ========================================================================

for iDyad = 1:numel(dyads)

    d = dyads(iDyad);
    dyadStr = sprintf('Dyad%02d', d);
    dyadTimer = tic;

    fprintf('\n============================================================\n');
    fprintf('Step 6 role-normalized epoching: %s\n', dyadStr);
    fprintf('Epoch window: [%.3f %.3f] s\n', ...
        epochWindowSeconds(1), epochWindowSeconds(2));

    if isempty(options.FilterBand)
        fprintf('Continuous filter: none\n');
    else
        fprintf('Continuous filter: %.3f-%.3f Hz\n', ...
            options.FilterBand(1), options.FilterBand(2));
    end
    fprintf('============================================================\n');

    folderA = fullfile(rootDir, dyadStr, 'SubjA');
    folderB = fullfile(rootDir, dyadStr, 'SubjB');

    baseA = [dyadStr '-A'];
    baseB = [dyadStr '-B'];

    inputFileA = [baseA options.InputSuffix '.set'];
    inputFileB = [baseB options.InputSuffix '.set'];

    inputPathA = fullfile(folderA, inputFileA);
    inputPathB = fullfile(folderB, inputFileB);

    outputRoot = fullfile(rootDir, dyadStr, options.OutputFolderName);

    dyadRecordIndices = recordCounter + (1:nSituations);

    for iSituation = 1:nSituations
        recordCounter = recordCounter + 1;
        records(recordCounter).Dyad = d;
        records(recordCounter).DyadName = string(dyadStr);
        records(recordCounter).Situation = string(situations(iSituation).marker);
        records(recordCounter).Condition = string(situations(iSituation).condition);
        records(recordCounter).KnowerParticipant = ...
            string(situations(iSituation).knowerParticipant);
        records(recordCounter).GuesserParticipant = ...
            string(situations(iSituation).guesserParticipant);
        records(recordCounter).EpochStartSeconds = epochWindowSeconds(1);
        records(recordCounter).EpochEndSeconds = epochWindowSeconds(2);

        if ~isempty(options.FilterBand)
            records(recordCounter).FilterLowHz = options.FilterBand(1);
            records(recordCounter).FilterHighHz = options.FilterBand(2);
        end

        if ~isempty(options.BaselineWindowSeconds)
            records(recordCounter).BaselineStartSeconds = ...
                options.BaselineWindowSeconds(1);
            records(recordCounter).BaselineEndSeconds = ...
                options.BaselineWindowSeconds(2);
        end
    end

    try
        %% Load and validate continuous source datasets

        if exist(inputPathA, 'file') ~= 2
            error('Input dataset not found: %s', inputPathA);
        end

        if exist(inputPathB, 'file') ~= 2
            error('Input dataset not found: %s', inputPathB);
        end

        EEG_A = pop_loadset('filename', inputFileA, 'filepath', folderA);
        EEG_B = pop_loadset('filename', inputFileB, 'filepath', folderB);

        EEG_A = eeg_checkset(EEG_A, 'eventconsistency');
        EEG_B = eeg_checkset(EEG_B, 'eventconsistency');

        if EEG_A.trials ~= 1 || EEG_B.trials ~= 1
            error('Step 6 inputs must be continuous datasets.');
        end

        local_assert_continuous_alignment(EEG_A, EEG_B, dyadStr);

        %% Optional continuous filtering

        if ~isempty(options.FilterBand)

            eventsBeforeA = local_event_signature(EEG_A);
            eventsBeforeB = local_event_signature(EEG_B);

            EEG_A = pop_eegfiltnew(EEG_A, ...
                'locutoff', options.FilterBand(1), ...
                'hicutoff', options.FilterBand(2), ...
                'plotfreqz', 0);

            EEG_B = pop_eegfiltnew(EEG_B, ...
                'locutoff', options.FilterBand(1), ...
                'hicutoff', options.FilterBand(2), ...
                'plotfreqz', 0);

            EEG_A = eeg_checkset(EEG_A, 'eventconsistency');
            EEG_B = eeg_checkset(EEG_B, 'eventconsistency');

            local_assert_signature_equal(...
                local_event_signature(EEG_A), eventsBeforeA, ...
                [dyadStr '-A after filtering']);

            local_assert_signature_equal(...
                local_event_signature(EEG_B), eventsBeforeB, ...
                [dyadStr '-B after filtering']);

            local_assert_continuous_alignment(EEG_A, EEG_B, dyadStr);
        end

        %% Process four situations

        for iSituation = 1:nSituations

            situationTimer = tic;
            situation = situations(iSituation);
            recordIndex = dyadRecordIndices(iSituation);

            fprintf('\n------------------------------------------------------------\n');
            fprintf('%s: %s\n', dyadStr, situation.marker);
            fprintf('Knower from %s; Guesser from %s\n', ...
                situation.knowerParticipant, ...
                situation.guesserParticipant);
            fprintf('------------------------------------------------------------\n');

            try
                situationFolder = fullfile(outputRoot, situation.marker);

                if exist(situationFolder, 'dir') ~= 7
                    mkdir(situationFolder);
                end

                knowerFile = sprintf('%s_%s_Knower_from%s.set', ...
                    dyadStr, situation.marker, situation.knowerParticipant);

                guesserFile = sprintf('%s_%s_Guesser_from%s.set', ...
                    dyadStr, situation.marker, situation.guesserParticipant);

                knowerPath = fullfile(situationFolder, knowerFile);
                guesserPath = fullfile(situationFolder, guesserFile);

                records(recordIndex).KnowerOutputFile = string(knowerPath);
                records(recordIndex).GuesserOutputFile = string(guesserPath);

                if ~options.OverwriteExisting && ...
                        (exist(knowerPath, 'file') == 2 || ...
                        exist(guesserPath, 'file') == 2)
                    error(['One or both outputs already exist and ', ...
                        'OverwriteExisting is false.']);
                end

                % Identify common valid markers once.
                markerInfo = local_find_valid_markers(...
                    EEG_A, situation.marker, epochWindowSeconds);

                records(recordIndex).NMarkersFound = markerInfo.numberFound;
                records(recordIndex).NValidMatchedEpochs = markerInfo.numberValid;
                records(recordIndex).NExcludedBeforeStart = ...
                    markerInfo.numberExcludedBeforeStart;
                records(recordIndex).NExcludedAfterEnd = ...
                    markerInfo.numberExcludedAfterEnd;
                records(recordIndex).NExcludedBoundary = ...
                    markerInfo.numberExcludedBoundary;

                if markerInfo.numberValid < 1
                    error('No valid matched epochs remained for %s.', ...
                        situation.marker);
                end

                % Relabel invalid target events so pop_epoch can select only
                % the jointly accepted marker list.
                EEG_A_work = local_relabel_invalid_events(...
                    EEG_A, situation.marker, markerInfo.invalidEventIndices);

                EEG_B_work = local_relabel_invalid_events(...
                    EEG_B, situation.marker, markerInfo.invalidEventIndices);

                EEG_A_epoch = pop_epoch(EEG_A_work, {situation.marker}, ...
                    epochWindowSeconds, 'newname', ...
                    sprintf('%s_%s_fromA', dyadStr, situation.marker), ...
                    'epochinfo', 'yes');

                EEG_B_epoch = pop_epoch(EEG_B_work, {situation.marker}, ...
                    epochWindowSeconds, 'newname', ...
                    sprintf('%s_%s_fromB', dyadStr, situation.marker), ...
                    'epochinfo', 'yes');

                EEG_A_epoch = eeg_checkset(EEG_A_epoch, 'eventconsistency');
                EEG_B_epoch = eeg_checkset(EEG_B_epoch, 'eventconsistency');

                if EEG_A_epoch.trials ~= markerInfo.numberValid || ...
                        EEG_B_epoch.trials ~= markerInfo.numberValid
                    error(['pop_epoch returned A=%d and B=%d trials, ', ...
                        'but %d valid markers were expected.'], ...
                        EEG_A_epoch.trials, EEG_B_epoch.trials, ...
                        markerInfo.numberValid);
                end

                % Optional baseline correction after epoching.
                if ~isempty(options.BaselineWindowSeconds)
                    baselineMs = options.BaselineWindowSeconds * 1000;
                    EEG_A_epoch = pop_rmbase(EEG_A_epoch, baselineMs);
                    EEG_B_epoch = pop_rmbase(EEG_B_epoch, baselineMs);
                end

                % Create identical trial-pair IDs for both participants.
                pairIDs = strings(markerInfo.numberValid, 1);

                for iTrial = 1:markerInfo.numberValid
                    pairIDs(iTrial) = sprintf('%s_%s_Trial%03d', ...
                        dyadStr, situation.marker, iTrial);
                end

                EEG_A_epoch = local_attach_metadata(...
                    EEG_A_epoch, dyadStr, situation, 'A', ...
                    epochWindowSeconds, options, markerInfo, pairIDs);

                EEG_B_epoch = local_attach_metadata(...
                    EEG_B_epoch, dyadStr, situation, 'B', ...
                    epochWindowSeconds, options, markerInfo, pairIDs);

                % Normalize by role.
                if strcmpi(situation.knowerParticipant, 'A')
                    EEG_Knower = EEG_A_epoch;
                    EEG_Guesser = EEG_B_epoch;
                else
                    EEG_Knower = EEG_B_epoch;
                    EEG_Guesser = EEG_A_epoch;
                end

                EEG_Knower.setname = erase(knowerFile, '.set');
                EEG_Guesser.setname = erase(guesserFile, '.set');

                EEG_Knower.etc.hyperyesno_epoching.analysisRole = 'Knower';
                EEG_Guesser.etc.hyperyesno_epoching.analysisRole = 'Guesser';

                local_assert_epoched_pair(...
                    EEG_Knower, EEG_Guesser, pairIDs, situation.marker);

                % Save role-normalized pair.
                EEG_Knower = pop_saveset(EEG_Knower, ...
                    'filename', knowerFile, ...
                    'filepath', situationFolder, ...
                    'savemode', 'twofiles');

                EEG_Guesser = pop_saveset(EEG_Guesser, ...
                    'filename', guesserFile, ...
                    'filepath', situationFolder, ...
                    'savemode', 'twofiles');

                fprintf('Saved Knower: %s\n', knowerPath);
                fprintf('Saved Guesser: %s\n', guesserPath);

                % Save explicit pairing table.
                trialTable = table(...
                    (1:markerInfo.numberValid)', ...
                    pairIDs, ...
                    repmat(string(situation.marker), markerInfo.numberValid, 1), ...
                    repmat(string(situation.condition), markerInfo.numberValid, 1), ...
                    repmat(string(situation.knowerParticipant), markerInfo.numberValid, 1), ...
                    repmat(string(situation.guesserParticipant), markerInfo.numberValid, 1), ...
                    markerInfo.validOriginalEventIndices(:), ...
                    markerInfo.validOriginalLatencies(:), ...
                    markerInfo.validOriginalLatencies(:) ./ EEG_A.srate, ...
                    'VariableNames', {...
                    'TrialNumber','PairID','Marker','Condition', ...
                    'KnowerParticipant','GuesserParticipant', ...
                    'OriginalEventIndex','OriginalEventLatencySamples', ...
                    'OriginalEventTimeSeconds'});

                if options.SaveTrialTables
                    trialTablePath = fullfile(situationFolder, ...
                        sprintf('%s_%s_trial_pairs.csv', ...
                        dyadStr, situation.marker));
                    writetable(trialTable, trialTablePath);
                    records(recordIndex).TrialTableFile = ...
                        string(trialTablePath);
                end

                records(recordIndex).Status = "completed";
                records(recordIndex).ElapsedMinutes = ...
                    toc(situationTimer) / 60;

                clear EEG_A_work EEG_B_work EEG_A_epoch EEG_B_epoch
                clear EEG_Knower EEG_Guesser

            catch situationError
                records(recordIndex).Status = "failed";
                records(recordIndex).Notes = string(situationError.message);
                records(recordIndex).ElapsedMinutes = ...
                    toc(situationTimer) / 60;

                fprintf(2, '\nFAILED %s %s\n%s\n', ...
                    dyadStr, situation.marker, situationError.message);

                clear EEG_A_work EEG_B_work EEG_A_epoch EEG_B_epoch
                clear EEG_Knower EEG_Guesser
            end
        end

        fprintf('\nFinished %s in %.2f minutes.\n', ...
            dyadStr, toc(dyadTimer) / 60);

        clear EEG_A EEG_B

    catch dyadError
        fprintf(2, '\nFAILED %s\n%s\n', dyadStr, dyadError.message);

        for recordIndex = dyadRecordIndices
            if records(recordIndex).Status == ""
                records(recordIndex).Status = "failed";
                records(recordIndex).Notes = string(dyadError.message);
                records(recordIndex).ElapsedMinutes = ...
                    toc(dyadTimer) / 60;
            end
        end

        clear EEG_A EEG_B
    end
end

%% ========================================================================
% 6. Save summary
% ========================================================================

summaryTable = struct2table(records);

summaryExcelFile = fullfile(rootDir, ...
    'Step6_GCMI_epoching_summary.xlsx');

summaryMatFile = fullfile(rootDir, ...
    'Step6_GCMI_epoching_summary.mat');

writetable(summaryTable, summaryExcelFile);
save(summaryMatFile, 'summaryTable');

fprintf('\n============================================================\n');
fprintf('Step 6 finished in %.2f minutes.\n', toc(pipelineTimer)/60);
fprintf('Summary Excel file: %s\n', summaryExcelFile);
fprintf('Summary MAT file:   %s\n', summaryMatFile);
fprintf('============================================================\n');

end


%% =========================================================================
% Find valid target markers
% =========================================================================

function markerInfo = local_find_valid_markers(EEG, marker, epochWindowSeconds)

eventTypes = string({EEG.event.type});
eventLatencies = double([EEG.event.latency]);

markerEventIndices = find(strcmpi(eventTypes, marker));
boundaryLatencies = eventLatencies(strcmpi(eventTypes, "boundary"));

nFound = numel(markerEventIndices);
validMask = false(nFound, 1);
excludeBefore = false(nFound, 1);
excludeAfter = false(nFound, 1);
excludeBoundary = false(nFound, 1);

startOffset = epochWindowSeconds(1) * EEG.srate;
endOffset = epochWindowSeconds(2) * EEG.srate;

for iMarker = 1:nFound
    eventIndex = markerEventIndices(iMarker);
    markerLatency = eventLatencies(eventIndex);

    epochStart = markerLatency + startOffset;
    epochEnd = markerLatency + endOffset;

    if epochStart < 1
        excludeBefore(iMarker) = true;
        continue;
    end

    if epochEnd > EEG.pnts
        excludeAfter(iMarker) = true;
        continue;
    end

    if any(boundaryLatencies >= epochStart & ...
            boundaryLatencies <= epochEnd)
        excludeBoundary(iMarker) = true;
        continue;
    end

    validMask(iMarker) = true;
end

validIndices = markerEventIndices(validMask);
invalidIndices = markerEventIndices(~validMask);

markerInfo = struct();
markerInfo.marker = marker;
markerInfo.numberFound = nFound;
markerInfo.numberValid = sum(validMask);
markerInfo.numberExcludedBeforeStart = sum(excludeBefore);
markerInfo.numberExcludedAfterEnd = sum(excludeAfter);
markerInfo.numberExcludedBoundary = sum(excludeBoundary);
markerInfo.allOriginalEventIndices = markerEventIndices(:)';
markerInfo.validOriginalEventIndices = validIndices(:)';
markerInfo.invalidEventIndices = invalidIndices(:)';
markerInfo.validOriginalLatencies = eventLatencies(validIndices);
markerInfo.validMask = validMask(:)';

end


%% =========================================================================
% Relabel invalid target events
% =========================================================================

function EEG = local_relabel_invalid_events(EEG, marker, invalidEventIndices)

replacementType = ['EXCLUDED_' marker];

for iEvent = 1:numel(invalidEventIndices)
    EEG.event(invalidEventIndices(iEvent)).type = replacementType;
end

EEG = eeg_checkset(EEG, 'eventconsistency');

end


%% =========================================================================
% Attach pairing and role metadata
% =========================================================================

function EEG = local_attach_metadata(EEG, dyadStr, situation, ...
    sourceParticipant, epochWindowSeconds, options, markerInfo, pairIDs)

if EEG.trials ~= numel(pairIDs)
    error('Pair-ID count does not match the number of epochs.');
end

for iTrial = 1:EEG.trials
    EEG.epoch(iTrial).pair_id = char(pairIDs(iTrial));
    EEG.epoch(iTrial).condition = situation.condition;
    EEG.epoch(iTrial).marker = situation.marker;
    EEG.epoch(iTrial).source_participant = sourceParticipant;
    EEG.epoch(iTrial).knower_participant = ...
        situation.knowerParticipant;
    EEG.epoch(iTrial).guesser_participant = ...
        situation.guesserParticipant;
    EEG.epoch(iTrial).original_marker_event_index = ...
        markerInfo.validOriginalEventIndices(iTrial);
    EEG.epoch(iTrial).original_marker_latency = ...
        markerInfo.validOriginalLatencies(iTrial);
end

metadata = struct();
metadata.dyad = dyadStr;
metadata.marker = situation.marker;
metadata.condition = situation.condition;
metadata.sourceParticipant = sourceParticipant;
metadata.knowerParticipant = situation.knowerParticipant;
metadata.guesserParticipant = situation.guesserParticipant;

if strcmpi(sourceParticipant, situation.knowerParticipant)
    metadata.analysisRole = 'Knower';
else
    metadata.analysisRole = 'Guesser';
end

metadata.epochWindowSeconds = epochWindowSeconds;
metadata.filterBandHz = options.FilterBand;
metadata.baselineWindowSeconds = options.BaselineWindowSeconds;
metadata.numberMarkersFound = markerInfo.numberFound;
metadata.numberValidMatchedEpochs = markerInfo.numberValid;
metadata.numberExcludedBeforeStart = ...
    markerInfo.numberExcludedBeforeStart;
metadata.numberExcludedAfterEnd = ...
    markerInfo.numberExcludedAfterEnd;
metadata.numberExcludedBoundary = ...
    markerInfo.numberExcludedBoundary;
metadata.validOriginalEventIndices = ...
    markerInfo.validOriginalEventIndices;
metadata.validOriginalMarkerLatencies = ...
    markerInfo.validOriginalLatencies;
metadata.pairIDs = cellstr(pairIDs);
metadata.pairingConvention = 'Knower first, Guesser second';
metadata.lagConventionForFutureGCMI = ...
    ['Positive lag = Knower leads Guesser; ', ...
    'negative lag = Guesser leads Knower'];

if ~isfield(EEG, 'etc') || isempty(EEG.etc)
    EEG.etc = struct();
end

EEG.etc.hyperyesno_epoching = metadata;
EEG = eeg_checkset(EEG, 'eventconsistency');

end


%% =========================================================================
% Continuous A-B alignment
% =========================================================================

function local_assert_continuous_alignment(EEG_A, EEG_B, dyadStr)

if EEG_A.srate ~= EEG_B.srate
    error('Sampling-rate mismatch in %s.', dyadStr);
end

if EEG_A.pnts ~= EEG_B.pnts
    error('Sample-count mismatch in %s.', dyadStr);
end

if EEG_A.nbchan ~= EEG_B.nbchan
    error('ROI-count mismatch in %s.', dyadStr);
end

labelsA = string({EEG_A.chanlocs.labels});
labelsB = string({EEG_B.chanlocs.labels});

if ~isequal(labelsA, labelsB)
    error('ROI labels differ between A and B in %s.', dyadStr);
end

local_assert_signature_equal(...
    local_event_signature(EEG_A), ...
    local_event_signature(EEG_B), ...
    [dyadStr ' A-B event alignment']);

end


%% =========================================================================
% Event signatures
% =========================================================================

function signature = local_event_signature(EEG)

signature = struct();
signature.numberOfSamples = EEG.pnts;
signature.samplingRate = EEG.srate;
signature.numberOfEvents = numel(EEG.event);

if isempty(EEG.event)
    signature.types = strings(0,1);
    signature.latencies = [];
else
    signature.types = string({EEG.event.type});
    signature.latencies = double([EEG.event.latency]);
end

end


function local_assert_signature_equal(observed, expected, description)

if observed.numberOfSamples ~= expected.numberOfSamples
    error('%s: sample count differs.', description);
end

if observed.samplingRate ~= expected.samplingRate
    error('%s: sampling rate differs.', description);
end

if observed.numberOfEvents ~= expected.numberOfEvents
    error('%s: event count differs.', description);
end

if ~isequal(observed.types, expected.types)
    error('%s: event types or order differ.', description);
end

if numel(observed.latencies) ~= numel(expected.latencies) || ...
        any(abs(observed.latencies - expected.latencies) > 1e-6)
    error('%s: event latencies differ.', description);
end

end


%% =========================================================================
% Final epoched-pair checks
% =========================================================================

function local_assert_epoched_pair(EEG_Knower, EEG_Guesser, ...
    expectedPairIDs, marker)

if EEG_Knower.trials ~= EEG_Guesser.trials
    error('Knower/Guesser trial counts differ for %s.', marker);
end

if EEG_Knower.pnts ~= EEG_Guesser.pnts
    error('Knower/Guesser epoch lengths differ for %s.', marker);
end

if EEG_Knower.srate ~= EEG_Guesser.srate
    error('Knower/Guesser sampling rates differ for %s.', marker);
end

if ~isequal(EEG_Knower.times, EEG_Guesser.times)
    error('Knower/Guesser epoch time vectors differ for %s.', marker);
end

knowerPairIDs = string({EEG_Knower.epoch.pair_id});
guesserPairIDs = string({EEG_Guesser.epoch.pair_id});

if ~isequal(knowerPairIDs(:), expectedPairIDs(:))
    error('Knower pair IDs are incorrect for %s.', marker);
end

if ~isequal(guesserPairIDs(:), expectedPairIDs(:))
    error('Guesser pair IDs are incorrect for %s.', marker);
end

if ~isequal(knowerPairIDs, guesserPairIDs)
    error('Knower/Guesser pair-ID order differs for %s.', marker);
end

knowerLatencies = [EEG_Knower.epoch.original_marker_latency];
guesserLatencies = [EEG_Guesser.epoch.original_marker_latency];

if ~isequal(knowerLatencies, guesserLatencies)
    error('Original marker latencies differ for %s.', marker);
end

end


%% =========================================================================
% Empty summary record
% =========================================================================

function record = local_empty_record()

record = struct(...
    'Dyad', NaN, ...
    'DyadName', "", ...
    'Situation', "", ...
    'Condition', "", ...
    'KnowerParticipant', "", ...
    'GuesserParticipant', "", ...
    'EpochStartSeconds', NaN, ...
    'EpochEndSeconds', NaN, ...
    'FilterLowHz', NaN, ...
    'FilterHighHz', NaN, ...
    'BaselineStartSeconds', NaN, ...
    'BaselineEndSeconds', NaN, ...
    'NMarkersFound', NaN, ...
    'NValidMatchedEpochs', NaN, ...
    'NExcludedBeforeStart', NaN, ...
    'NExcludedAfterEnd', NaN, ...
    'NExcludedBoundary', NaN, ...
    'KnowerOutputFile', "", ...
    'GuesserOutputFile', "", ...
    'TrialTableFile', "", ...
    'Status', "", ...
    'ElapsedMinutes', NaN, ...
    'Notes', "");

end
