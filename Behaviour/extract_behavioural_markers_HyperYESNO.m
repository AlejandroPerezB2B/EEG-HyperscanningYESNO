function [trialTable, dyadSummary, roleSummary, targetSummary, qcTable] = ...
    extract_behavioural_markers_HyperYESNO(rootDir, dyads, varargin)
% EXTRACT_BEHAVIOURAL_MARKERS_HYPERYESNO
% Extract behavioural measures from the event markers contained in the
% combined HyperYESNO EEG recordings.
%
% The function searches for one combined EEGLAB dataset per dyad:
%
%   E:\EEG_data_HyperYESNO\DyadXX\DyadXX.set
%
% For each standard recording, the function identifies the 32 BlockStart
% markers and treats the interval from one BlockStart to the next as one
% experimental trial. Within each interval, it finds the response markers:
%
%   YES_AKnower
%   NO_AKnower
%   YES_BKnower
%   NO_BKnower
%
% The main behavioural duration is defined as:
%
%   last YES/NO response latency - BlockStart latency
%
% divided by the EEG sampling rate. The function also counts YES and NO
% responses, identifies the Knower and Guesser, and appends the fixed target
% word, category, and semantic hint from the experimental PowerPoint.
%
% IMPORTANT
% ---------
% The response-pad markers do not directly indicate whether the Guesser
% correctly identified the target. Therefore, the output variable
% PutativeOutcome is explicitly exploratory. It combines:
%
%   1. time from BlockStart to the final response;
%   2. whether the final response was YES or NO; and
%   3. proximity to the 60-s trial limit.
%
% A short trial ending in YES is labelled "LikelyGuessedEarly", but this
% should not be treated as verified behavioural accuracy without checking
% the video recordings.
%
% Standard recordings are expected to contain 32 BlockStart markers.
% By default, a dyad with a different number of BlockStart markers is
% reported in the QC table and skipped, while processing continues with the
% next dyad.
%
% INPUTS
% ------
% rootDir : Character vector or string
%           Root data directory. Default:
%           'E:\EEG_data_HyperYESNO'
%
% dyads   : Numeric vector of dyad numbers. Default: 1:35
%
% OPTIONAL NAME-VALUE ARGUMENTS
% -----------------------------
% 'OutputDir'
%       Folder where the Excel and MAT summaries are saved.
%       Default: rootDir
%
% 'ExpectedBlocks'
%       Expected number of experimental BlockStart markers.
%       Default: 32
%
% 'TrialLimitSec'
%       Maximum nominal trial duration.
%       Default: 60
%
% 'NearTimeoutToleranceSec'
%       Number of seconds before the nominal limit used to classify a
%       response as being near the time limit. With the default values,
%       final responses at >=55 s are considered near the limit.
%       Default: 5
%
% 'FirstKnower'
%       Participant who is expected to be Knower in the first experimental
%       trial. Roles alternate on subsequent trials.
%       The experimental PowerPoint places participant B as Knower first.
%       Default: 'B'
%
% 'SkipUnexpectedBlockCount'
%       If true, dyads without exactly ExpectedBlocks BlockStart markers
%       are reported and skipped.
%       Default: true
%
% 'WriteExcel'
%       Save all output tables to one Excel workbook.
%       Default: true
%
% 'Verbose'
%       Print processing information to the Command Window.
%       Default: true
%
% OUTPUTS
% -------
% trialTable
%       One row per valid experimental block. Contains target information,
%       roles, response counts, temporal measures, exploratory completion
%       measures, and trial-level QC information.
%
% dyadSummary
%       One row per processed dyad.
%
% roleSummary
%       One row per dyad and observed Knower/Guesser configuration. This
%       allows behavioural measures to be compared when A is Knower/B is
%       Guesser versus when B is Knower/A is Guesser.
%
% targetSummary
%       One row per target word, summarized across dyads.
%
% qcTable
%       Missing files, loading failures, unexpected block counts, and other
%       recording or marker inconsistencies.
%
% SAVED OUTPUTS
% -------------
% HyperYESNO_behavioural_markers.xlsx
% HyperYESNO_behavioural_markers.mat
%
% The Excel workbook contains:
%   TrialLevel
%   DyadSummary
%   RoleSummary
%   TargetSummary
%   QC
%   TargetSchedule
%
% DEPENDENCIES
% ------------
% MATLAB
% EEGLAB (pop_loadset and eeg_checkset)
%
% EXAMPLE
% -------
% [trialTable, dyadSummary, roleSummary, targetSummary, qcTable] = ...
%     extract_behavioural_markers_HyperYESNO( ...
%     'E:\EEG_data_HyperYESNO', ...
%     1:35);
%
% Author: Alejandro Perez
% HyperYESNO project, 2026

%% Parse inputs

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

parser = inputParser;
parser.FunctionName = mfilename;

addRequired(parser, 'rootDir', @(x) ischar(x) || isstring(x));
addRequired(parser, 'dyads', ...
    @(x) isnumeric(x) && isvector(x) && all(isfinite(x)));

addParameter(parser, 'OutputDir', rootDir, ...
    @(x) ischar(x) || isstring(x));
addParameter(parser, 'ExpectedBlocks', 32, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1 && mod(x, 1) == 0);
addParameter(parser, 'TrialLimitSec', 60, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, 'NearTimeoutToleranceSec', 5, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, 'FirstKnower', 'B', ...
    @(x) any(strcmpi(string(x), ["A", "B"])));
addParameter(parser, 'SkipUnexpectedBlockCount', true, ...
    @(x) islogical(x) && isscalar(x));
addParameter(parser, 'WriteExcel', true, ...
    @(x) islogical(x) && isscalar(x));
addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, rootDir, dyads, varargin{:});
opt = parser.Results;

rootDir = char(string(rootDir));
outputDir = char(string(opt.OutputDir));
dyads = unique(round(dyads(:)'), 'stable');
firstKnower = upper(string(opt.FirstKnower));

nearTimeoutThresholdSec = ...
    opt.TrialLimitSec - opt.NearTimeoutToleranceSec;

if nearTimeoutThresholdSec < 0
    error(['NearTimeoutToleranceSec cannot be larger than ' ...
        'TrialLimitSec.']);
end

if exist('pop_loadset', 'file') ~= 2
    error(['EEGLAB function pop_loadset was not found. Start EEGLAB or ' ...
        'add the EEGLAB folder to the MATLAB path before running this ' ...
        'function.']);
end

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% Fixed experimental target schedule

% The experimental presentation contained 32 analysed targets. Four
% additional object slides appeared after the experiment-ending slides and
% are not included here.
targetSchedule = build_target_schedule(firstKnower);

if height(targetSchedule) ~= opt.ExpectedBlocks
    error(['The fixed target schedule contains %d trials, but ' ...
        'ExpectedBlocks is %d.'], ...
        height(targetSchedule), opt.ExpectedBlocks);
end

%% Marker definitions

responseMarkers = [ ...
    "YES_AKnower", ...
    "NO_AKnower", ...
    "YES_BKnower", ...
    "NO_BKnower"];

%% Accumulators

trialRows = struct([]);
qcRows = cell(0, 7);

%% Process each dyad

for dyadNumber = dyads

    dyadName = sprintf('Dyad%02d', dyadNumber);
    dyadFolder = fullfile(rootDir, dyadName);
    setFileName = sprintf('%s.set', dyadName);
    setFile = fullfile(dyadFolder, setFileName);

    if opt.Verbose
        fprintf('\n[%s] Looking for %s\n', dyadName, setFile);
    end

    if ~isfile(setFile)
        qcRows(end + 1, :) = { ...
            dyadName, dyadNumber, "ERROR", "MissingFile", ...
            "Combined EEGLAB dataset was not found.", ...
            setFile, NaN}; %#ok<AGROW>

        if opt.Verbose
            fprintf('  SKIPPED: file not found.\n');
        end
        continue
    end

    try
        EEG = pop_loadset( ...
            'filename', setFileName, ...
            'filepath', dyadFolder);

        EEG = eeg_checkset(EEG, 'eventconsistency');

    catch ME
        qcRows(end + 1, :) = { ...
            dyadName, dyadNumber, "ERROR", "LoadFailure", ...
            string(ME.message), setFile, NaN}; %#ok<AGROW>

        if opt.Verbose
            fprintf('  SKIPPED: loading failed: %s\n', ME.message);
        end
        continue
    end

    if isempty(EEG.event)
        qcRows(end + 1, :) = { ...
            dyadName, dyadNumber, "ERROR", "NoEvents", ...
            "The dataset contains no EEGLAB events.", ...
            setFile, 0}; %#ok<AGROW>

        if opt.Verbose
            fprintf('  SKIPPED: dataset contains no events.\n');
        end
        continue
    end

    if ~isfield(EEG, 'srate') || isempty(EEG.srate) || ...
            ~isfinite(EEG.srate) || EEG.srate <= 0
        qcRows(end + 1, :) = { ...
            dyadName, dyadNumber, "ERROR", "InvalidSamplingRate", ...
            "EEG.srate is missing or invalid.", ...
            setFile, NaN}; %#ok<AGROW>
        continue
    end

    % Decode marker labels. The helper also recognizes the original numeric
    % Curry codes when they remain in EEG.event.type or EEG.event.value.
    nEvents = numel(EEG.event);
    eventTypes = strings(nEvents, 1);
    eventLatencies = nan(nEvents, 1);

    for eventIndex = 1:nEvents
        eventTypes(eventIndex) = decode_event_marker(EEG.event(eventIndex));

        if isfield(EEG.event(eventIndex), 'latency')
            eventLatencies(eventIndex) = ...
                double(EEG.event(eventIndex).latency);
        end
    end

    % Discard events with unusable latencies, then sort chronologically.
    validLatency = isfinite(eventLatencies);

    if any(~validLatency)
        qcRows(end + 1, :) = { ...
            dyadName, dyadNumber, "WARNING", "InvalidEventLatencies", ...
            sprintf('%d events had missing or invalid latencies and were ignored.', ...
                sum(~validLatency)), ...
            setFile, sum(validLatency)}; %#ok<AGROW>
    end

    eventTypes = eventTypes(validLatency);
    eventLatencies = eventLatencies(validLatency);

    [eventLatencies, sortOrder] = sort(eventLatencies, 'ascend');
    eventTypes = eventTypes(sortOrder);

    blockEventIndices = find(eventTypes == "BlockStart");
    nBlocks = numel(blockEventIndices);
    nResponseMarkers = sum(ismember(eventTypes, responseMarkers));

    if opt.Verbose
        fprintf('  BlockStart markers: %d\n', nBlocks);
        fprintf('  YES/NO response markers: %d\n', nResponseMarkers);
    end

    if nBlocks ~= opt.ExpectedBlocks
        details = sprintf([ ...
            'Expected %d BlockStart markers but found %d. ' ...
            'Response markers found: %d.'], ...
            opt.ExpectedBlocks, nBlocks, nResponseMarkers);

        qcRows(end + 1, :) = { ...
            dyadName, dyadNumber, "ERROR", ...
            "UnexpectedBlockCount", details, setFile, nBlocks}; %#ok<AGROW>

        if opt.SkipUnexpectedBlockCount
            if opt.Verbose
                fprintf('  SKIPPED: unexpected block structure.\n');
            end
            continue
        end
    end

    % When irregular datasets are not skipped, process only the number of
    % trials for which both a BlockStart and target metadata are available.
    nTrialsToProcess = min(nBlocks, height(targetSchedule));

    for trialNumber = 1:nTrialsToProcess

        blockEventIndex = blockEventIndices(trialNumber);
        blockStartLatency = eventLatencies(blockEventIndex);

        if trialNumber < nBlocks
            nextBlockStartLatency = ...
                eventLatencies(blockEventIndices(trialNumber + 1));
            hasNextBlock = true;
        else
            % EEG event latencies are sample-based. EEG.pnts + 1 therefore
            % defines an exclusive upper bound after the final sample.
            nextBlockStartLatency = double(EEG.pnts) + 1;
            hasNextBlock = false;
        end

        % A response at exactly the same sample as the subsequent
        % BlockStart is assigned to the new block, not the previous block.
        inCurrentBlock = ...
            eventLatencies >= blockStartLatency & ...
            eventLatencies < nextBlockStartLatency;

        responseMask = ...
            inCurrentBlock & ismember(eventTypes, responseMarkers);

        responseLatencies = eventLatencies(responseMask);
        responseTypes = eventTypes(responseMask);

        % Sorting is repeated locally for clarity and protection against
        % malformed event ordering.
        [responseLatencies, localOrder] = ...
            sort(responseLatencies, 'ascend');
        responseTypes = responseTypes(localOrder);

        numResponses = numel(responseTypes);
        numYes = sum(startsWith(responseTypes, "YES_"));
        numNo = sum(startsWith(responseTypes, "NO_"));

        if numResponses > 0
            firstResponseLatency = responseLatencies(1);
            lastResponseLatency = responseLatencies(end);

            firstResponseTimeSec = ...
                (firstResponseLatency - blockStartLatency) / EEG.srate;

            trialUseTimeSec = ...
                (lastResponseLatency - blockStartLatency) / EEG.srate;

            lastResponseType = responseTypes(end);

            if startsWith(lastResponseType, "YES_")
                lastResponseValence = "YES";
                lastResponseWasYes = 1;
            else
                lastResponseValence = "NO";
                lastResponseWasYes = 0;
            end

            if numResponses >= 2
                interResponseIntervalsSec = ...
                    diff(responseLatencies) / EEG.srate;

                meanInterResponseIntervalSec = ...
                    mean(interResponseIntervalsSec, 'omitnan');

                medianInterResponseIntervalSec = ...
                    median(interResponseIntervalsSec, 'omitnan');
            else
                meanInterResponseIntervalSec = NaN;
                medianInterResponseIntervalSec = NaN;
            end

            yesProportion = numYes / numResponses;

            if trialUseTimeSec > 0
                responseRatePerMin = ...
                    numResponses / (trialUseTimeSec / 60);
            else
                responseRatePerMin = NaN;
            end

            secondsBeforeLimit = ...
                opt.TrialLimitSec - trialUseTimeSec;

            nearTimeLimit = ...
                trialUseTimeSec >= nearTimeoutThresholdSec;

            % Exploratory, indirect approximation of task completion.
            if nearTimeLimit
                putativeOutcome = "NearTimeLimit";
                putativeEarlyCompletion = 0;
            elseif lastResponseWasYes == 1
                putativeOutcome = "LikelyGuessedEarly";
                putativeEarlyCompletion = 1;
            else
                putativeOutcome = "EarlyEndUncertain";
                putativeEarlyCompletion = 0;
            end

        else
            firstResponseLatency = NaN;
            lastResponseLatency = NaN;
            firstResponseTimeSec = NaN;
            trialUseTimeSec = NaN;
            lastResponseType = "";
            lastResponseValence = "";
            lastResponseWasYes = NaN;
            meanInterResponseIntervalSec = NaN;
            medianInterResponseIntervalSec = NaN;
            yesProportion = NaN;
            responseRatePerMin = NaN;
            secondsBeforeLimit = NaN;
            nearTimeLimit = false;
            putativeOutcome = "NoResponses";
            putativeEarlyCompletion = 0;
        end

        % Total interval between consecutive BlockStart markers. This
        % includes the trial, exchange of the response pad, and time used to
        % advance the presentation.
        if hasNextBlock
            blockStartToNextBlockSec = ...
                (nextBlockStartLatency - blockStartLatency) / EEG.srate;

            if numResponses > 0
                transitionAfterLastResponseSec = ...
                    (nextBlockStartLatency - lastResponseLatency) / EEG.srate;
            else
                transitionAfterLastResponseSec = NaN;
            end
        else
            blockStartToNextBlockSec = NaN;
            transitionAfterLastResponseSec = NaN;
        end

        % Determine roles from the response-marker suffix.
        hasAKnowerMarkers = any(endsWith(responseTypes, "_AKnower"));
        hasBKnowerMarkers = any(endsWith(responseTypes, "_BKnower"));

        if hasAKnowerMarkers && ~hasBKnowerMarkers
            observedKnower = "A";
            observedGuesser = "B";
        elseif hasBKnowerMarkers && ~hasAKnowerMarkers
            observedKnower = "B";
            observedGuesser = "A";
        elseif hasAKnowerMarkers && hasBKnowerMarkers
            observedKnower = "Mixed";
            observedGuesser = "Mixed";
        else
            observedKnower = "Missing";
            observedGuesser = "Missing";
        end

        expectedKnower = targetSchedule.ExpectedKnower(trialNumber);
        expectedGuesser = targetSchedule.ExpectedGuesser(trialNumber);

        roleMatchesSchedule = ...
            observedKnower == expectedKnower && ...
            observedGuesser == expectedGuesser;

        % Trial-level quality-control information.
        trialQC = strings(0, 1);

        if numResponses == 0
            trialQC(end + 1) = "NoResponses"; %#ok<AGROW>
        end

        if observedKnower == "Mixed"
            trialQC(end + 1) = "MixedKnowerMarkers"; %#ok<AGROW>
        end

        if ~roleMatchesSchedule && ...
                observedKnower ~= "Missing" && ...
                observedKnower ~= "Mixed"
            trialQC(end + 1) = "RoleScheduleMismatch"; %#ok<AGROW>
        end

        if isfinite(trialUseTimeSec) && trialUseTimeSec < 0
            trialQC(end + 1) = "NegativeTrialTime"; %#ok<AGROW>
        end

        if isfinite(trialUseTimeSec) && ...
                trialUseTimeSec > opt.TrialLimitSec + 5
            trialQC(end + 1) = "TrialTimeAboveLimitPlus5s"; %#ok<AGROW>
        end

        if isempty(trialQC)
            trialQCFlag = "OK";
        else
            trialQCFlag = strjoin(trialQC, ";");
        end

        % Construct one trial-level output row.
        row = struct;

        row.Dyad = string(dyadName);
        row.DyadNumber = dyadNumber;
        row.TrialNumber = trialNumber;

        row.Category = targetSchedule.Category(trialNumber);
        row.Target = targetSchedule.Target(trialNumber);
        row.Hint = targetSchedule.Hint(trialNumber);

        row.ExpectedKnower = expectedKnower;
        row.ExpectedGuesser = expectedGuesser;
        row.ObservedKnower = observedKnower;
        row.ObservedGuesser = observedGuesser;
        row.RoleMatchesSchedule = roleMatchesSchedule;

        row.SamplingRateHz = double(EEG.srate);
        row.BlockStartLatencySamples = blockStartLatency;
        row.FirstResponseLatencySamples = firstResponseLatency;
        row.LastResponseLatencySamples = lastResponseLatency;
        row.NextBlockStartLatencySamples = ...
            conditional_value(hasNextBlock, nextBlockStartLatency, NaN);

        row.FirstResponseTimeSec = firstResponseTimeSec;
        row.TrialUseTimeSec = trialUseTimeSec;
        row.BlockStartToNextBlockSec = blockStartToNextBlockSec;
        row.TransitionAfterLastResponseSec = ...
            transitionAfterLastResponseSec;

        row.NumYes = numYes;
        row.NumNo = numNo;
        row.NumResponses = numResponses;
        row.YesProportion = yesProportion;
        row.ResponseRatePerMin = responseRatePerMin;

        row.MeanInterResponseIntervalSec = ...
            meanInterResponseIntervalSec;
        row.MedianInterResponseIntervalSec = ...
            medianInterResponseIntervalSec;

        row.LastResponseType = lastResponseType;
        row.LastResponseValence = lastResponseValence;
        row.LastResponseWasYes = lastResponseWasYes;

        row.SecondsBeforeNominalLimit = secondsBeforeLimit;
        row.NearTimeLimit = nearTimeLimit;
        row.PutativeEarlyCompletion = putativeEarlyCompletion;
        row.PutativeOutcome = putativeOutcome;

        row.QCFlag = trialQCFlag;
        row.SourceFile = string(setFile);

        if isempty(trialRows)
            trialRows = row;
        else
            trialRows(end + 1, 1) = row; %#ok<AGROW>
        end
    end

    if opt.Verbose
        fprintf('  Completed: %d trial rows extracted.\n', nTrialsToProcess);
    end
end

%% Convert accumulated trial rows to a table

if isempty(trialRows)
    trialTable = create_empty_trial_table();
else
    trialTable = struct2table(trialRows);

    % Preserve requested dyad ordering and trial ordering.
    trialTable = sortrows( ...
        trialTable, ...
        {'DyadNumber', 'TrialNumber'}, ...
        {'ascend', 'ascend'});
end

%% Create summary tables

dyadSummary = summarise_by_dyad(trialTable);
roleSummary = summarise_by_role(trialTable);
targetSummary = summarise_by_target(trialTable, targetSchedule);

%% Convert QC rows to a table

qcVariableNames = { ...
    'Dyad', ...
    'DyadNumber', ...
    'Severity', ...
    'Issue', ...
    'Details', ...
    'SourceFile', ...
    'ObservedCount'};

if isempty(qcRows)
    qcTable = table( ...
        strings(0, 1), ...
        zeros(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        strings(0, 1), ...
        zeros(0, 1), ...
        'VariableNames', qcVariableNames);
else
    qcTable = cell2table(qcRows, ...
        'VariableNames', qcVariableNames);

    % cell2table preserves the cell-array storage. Convert each variable to
    % its intended output type so the QC sheet is easy to sort and analyse.
    qcTable.Dyad = string(qcTable.Dyad);
    qcTable.DyadNumber = cell2mat(qcTable.DyadNumber);
    qcTable.Severity = string(qcTable.Severity);
    qcTable.Issue = string(qcTable.Issue);
    qcTable.Details = string(qcTable.Details);
    qcTable.SourceFile = string(qcTable.SourceFile);
    qcTable.ObservedCount = cell2mat(qcTable.ObservedCount);
end

%% Save outputs

settings = opt;
settings.RootDir = rootDir;
settings.DyadsRequested = dyads;
settings.NearTimeoutThresholdSec = nearTimeoutThresholdSec;
settings.ResponseMarkers = responseMarkers;
settings.CreatedOn = datetime('now');

matFile = fullfile( ...
    outputDir, ...
    'HyperYESNO_behavioural_markers.mat');

save(matFile, ...
    'trialTable', ...
    'dyadSummary', ...
    'roleSummary', ...
    'targetSummary', ...
    'qcTable', ...
    'targetSchedule', ...
    'settings', ...
    '-v7.3');

if opt.WriteExcel

    excelFile = fullfile( ...
        outputDir, ...
        'HyperYESNO_behavioural_markers.xlsx');

    if isfile(excelFile)
        try
            delete(excelFile);
        catch ME
            warning(['Could not delete the existing Excel file. ' ...
                'It may be open in another program.\n%s'], ME.message);
        end
    end

    try
        writetable(trialTable, excelFile, 'Sheet', 'TrialLevel');
        writetable(dyadSummary, excelFile, 'Sheet', 'DyadSummary');
        writetable(roleSummary, excelFile, 'Sheet', 'RoleSummary');
        writetable(targetSummary, excelFile, 'Sheet', 'TargetSummary');
        writetable(qcTable, excelFile, 'Sheet', 'QC');
        writetable(targetSchedule, excelFile, 'Sheet', 'TargetSchedule');

    catch ME
        warning(['The MAT file was saved, but the Excel workbook could ' ...
            'not be written.\n%s'], ME.message);
    end
end

%% Final report

if opt.Verbose
    fprintf('\n============================================================\n');
    fprintf('HyperYESNO behavioural extraction finished.\n');
    fprintf('Trial rows:             %d\n', height(trialTable));
    fprintf('Processed dyads:        %d\n', height(dyadSummary));
    fprintf('Role-summary rows:      %d\n', height(roleSummary));
    fprintf('Target-summary rows:    %d\n', height(targetSummary));
    fprintf('QC entries:             %d\n', height(qcTable));
    fprintf('MAT output:              %s\n', matFile);

    if opt.WriteExcel
        fprintf('Excel output:            %s\n', excelFile);
    end

    fprintf('============================================================\n');
end

end


%% ========================================================================
function schedule = build_target_schedule(firstKnower)
% BUILD_TARGET_SCHEDULE
% Fixed 32-trial sequence from the experimental PowerPoint.

trialNumber = (1:32)';

category = [ ...
    repmat("Animals", 4, 1); ...
    repmat("Professions", 4, 1); ...
    repmat("Meals", 4, 1); ...
    repmat("Objects", 4, 1); ...
    repmat("Animals", 4, 1); ...
    repmat("Professions", 2, 1); ...
    repmat("Meals", 2, 1); ...
    repmat("Objects", 4, 1); ...
    repmat("Animals", 4, 1)];

target = [ ...
    "Dog"; ...
    "Horse"; ...
    "Elephant"; ...
    "Tiger"; ...
    "Doctor"; ...
    "Teacher"; ...
    "Chef/cooker"; ...
    "Police"; ...
    "Pizza"; ...
    "Burger"; ...
    "Ice Cream"; ...
    "Sushi"; ...
    "Laptop"; ...
    "Toothbrush"; ...
    "Bicycle"; ...
    "Backpack"; ...
    "Dolphin"; ...
    "Giraffe"; ...
    "Penguin"; ...
    "Snake"; ...
    "Lawyer"; ...
    "Pilot"; ...
    "Cake"; ...
    "Hot Dog"; ...
    "Ball"; ...
    "Chair"; ...
    "Book"; ...
    "Car"; ...
    "Monkey"; ...
    "Kangaroo"; ...
    "Eagle"; ...
    "Lion"];

hint = strings(32, 1);

hint(13) = "Technology";
hint(14) = "Cleaning";
hint(15) = "Transport";
hint(16) = "Something you wear";
hint(25) = "Sports";
hint(26) = "Furniture";
hint(27) = "Education";
hint(28) = "Transport";

expectedKnower = strings(32, 1);
expectedGuesser = strings(32, 1);

for trialIndex = 1:32

    if mod(trialIndex, 2) == 1
        expectedKnower(trialIndex) = firstKnower;
    else
        expectedKnower(trialIndex) = opposite_participant(firstKnower);
    end

    expectedGuesser(trialIndex) = ...
        opposite_participant(expectedKnower(trialIndex));
end

schedule = table( ...
    trialNumber, ...
    category, ...
    target, ...
    hint, ...
    expectedKnower, ...
    expectedGuesser, ...
    'VariableNames', { ...
    'TrialNumber', ...
    'Category', ...
    'Target', ...
    'Hint', ...
    'ExpectedKnower', ...
    'ExpectedGuesser'});

end


%% ========================================================================
function marker = decode_event_marker(eventStruct)
% DECODE_EVENT_MARKER
% Decode a marker from EEG.event.type, falling back to EEG.event.value.

marker = "Other";

if isfield(eventStruct, 'type')
    marker = decode_marker_value(eventStruct.type);
end

if marker == "Other" && isfield(eventStruct, 'value')
    marker = decode_marker_value(eventStruct.value);
end

end


%% ========================================================================
function marker = decode_marker_value(value)
% DECODE_MARKER_VALUE
% Recognize both string labels and the original numeric Curry codes.

marker = "Other";

if isempty(value)
    return
end

if iscell(value)
    if isempty(value)
        return
    end
    value = value{1};
end

numericCode = NaN;

if isnumeric(value) || islogical(value)
    numericCode = double(value(1));
else
    markerText = strtrim(string(value));

    if strlength(markerText) == 0
        return
    end

    compactText = upper(regexprep(markerText, '\s+', ''));

    switch compactText
        case "BLOCKSTART"
            marker = "BlockStart";
            return

        case "YES_AKNOWER"
            marker = "YES_AKnower";
            return

        case "NO_AKNOWER"
            marker = "NO_AKnower";
            return

        case "YES_BKNOWER"
            marker = "YES_BKnower";
            return

        case "NO_BKNOWER"
            marker = "NO_BKnower";
            return
    end

    numericCode = str2double(markerText);
end

if ~isfinite(numericCode)
    return
end

switch round(numericCode)
    case 100240
        marker = "BlockStart";

    case 100241
        marker = "YES_AKnower";

    case 100242
        marker = "NO_AKnower";

    case 100244
        marker = "YES_BKnower";

    case 100248
        marker = "NO_BKnower";
end

end


%% ========================================================================
function participant = opposite_participant(participant)
% OPPOSITE_PARTICIPANT
% Return B for A and A for B.

participant = upper(string(participant));

if participant == "A"
    participant = "B";
elseif participant == "B"
    participant = "A";
else
    participant = "Unknown";
end

end


%% ========================================================================
function value = conditional_value(condition, trueValue, falseValue)
% CONDITIONAL_VALUE
% Small helper used to keep assignment statements readable.

if condition
    value = trueValue;
else
    value = falseValue;
end

end


%% ========================================================================
function summaryTable = summarise_by_dyad(trialTable)
% SUMMARISE_BY_DYAD
% Create one behavioural summary row per dyad.

if isempty(trialTable)
    summaryTable = table;
    return
end

dyadNumbers = unique(trialTable.DyadNumber, 'stable');
summaryRows = struct([]);

for rowIndex = 1:numel(dyadNumbers)

    dyadNumber = dyadNumbers(rowIndex);
    subset = trialTable(trialTable.DyadNumber == dyadNumber, :);

    row = calculate_summary_row(subset);
    row.Dyad = subset.Dyad(1);
    row.DyadNumber = dyadNumber;

    if isempty(summaryRows)
        summaryRows = row;
    else
        summaryRows(end + 1, 1) = row; %#ok<AGROW>
    end
end

summaryTable = struct2table(summaryRows);

% Put identifiers first.
summaryTable = movevars( ...
    summaryTable, ...
    {'Dyad', 'DyadNumber'}, ...
    'Before', 1);

summaryTable = sortrows(summaryTable, 'DyadNumber');

end


%% ========================================================================
function summaryTable = summarise_by_role(trialTable)
% SUMMARISE_BY_ROLE
% Create one row per dyad and valid Knower/Guesser configuration.

if isempty(trialTable)
    summaryTable = table;
    return
end

validRole = ...
    ismember(trialTable.ObservedKnower, ["A", "B"]) & ...
    ismember(trialTable.ObservedGuesser, ["A", "B"]);

roleData = trialTable(validRole, :);

if isempty(roleData)
    summaryTable = table;
    return
end

groupKeys = unique( ...
    roleData(:, {'Dyad', 'DyadNumber', ...
    'ObservedKnower', 'ObservedGuesser'}), ...
    'rows', ...
    'stable');

summaryRows = struct([]);

for groupIndex = 1:height(groupKeys)

    subsetMask = ...
        roleData.DyadNumber == groupKeys.DyadNumber(groupIndex) & ...
        roleData.ObservedKnower == ...
            groupKeys.ObservedKnower(groupIndex) & ...
        roleData.ObservedGuesser == ...
            groupKeys.ObservedGuesser(groupIndex);

    subset = roleData(subsetMask, :);

    row = calculate_summary_row(subset);
    row.Dyad = groupKeys.Dyad(groupIndex);
    row.DyadNumber = groupKeys.DyadNumber(groupIndex);
    row.Knower = groupKeys.ObservedKnower(groupIndex);
    row.Guesser = groupKeys.ObservedGuesser(groupIndex);

    if isempty(summaryRows)
        summaryRows = row;
    else
        summaryRows(end + 1, 1) = row; %#ok<AGROW>
    end
end

summaryTable = struct2table(summaryRows);

summaryTable = movevars( ...
    summaryTable, ...
    {'Dyad', 'DyadNumber', 'Knower', 'Guesser'}, ...
    'Before', 1);

summaryTable = sortrows( ...
    summaryTable, ...
    {'DyadNumber', 'Knower'}, ...
    {'ascend', 'ascend'});

end


%% ========================================================================
function summaryTable = summarise_by_target(trialTable, targetSchedule)
% SUMMARISE_BY_TARGET
% Summarize each fixed target word across all processed dyads.

summaryRows = struct([]);

for trialNumber = 1:height(targetSchedule)

    subset = trialTable(trialTable.TrialNumber == trialNumber, :);

    if isempty(subset)
        row = calculate_summary_row(create_empty_trial_table());
    else
        row = calculate_summary_row(subset);
    end

    row.TrialNumber = trialNumber;
    row.Category = targetSchedule.Category(trialNumber);
    row.Target = targetSchedule.Target(trialNumber);
    row.Hint = targetSchedule.Hint(trialNumber);
    row.ExpectedKnower = targetSchedule.ExpectedKnower(trialNumber);
    row.ExpectedGuesser = targetSchedule.ExpectedGuesser(trialNumber);

    if isempty(summaryRows)
        summaryRows = row;
    else
        summaryRows(end + 1, 1) = row; %#ok<AGROW>
    end
end

summaryTable = struct2table(summaryRows);

summaryTable = movevars( ...
    summaryTable, ...
    {'TrialNumber', 'Category', 'Target', 'Hint', ...
    'ExpectedKnower', 'ExpectedGuesser'}, ...
    'Before', 1);

summaryTable = sortrows(summaryTable, 'TrialNumber');

end


%% ========================================================================
function row = calculate_summary_row(subset)
% CALCULATE_SUMMARY_ROW
% Shared summary calculations for dyad, role, and target tables.

row = struct;

row.NTrials = height(subset);
row.NValidTrialTimes = sum(isfinite(subset.TrialUseTimeSec));

row.MeanTrialUseTimeSec = ...
    mean(subset.TrialUseTimeSec, 'omitnan');

row.MedianTrialUseTimeSec = ...
    median(subset.TrialUseTimeSec, 'omitnan');

row.SDTrialUseTimeSec = ...
    std(subset.TrialUseTimeSec, 0, 'omitnan');

row.MeanFirstResponseTimeSec = ...
    mean(subset.FirstResponseTimeSec, 'omitnan');

row.MeanNumYes = ...
    mean(subset.NumYes, 'omitnan');

row.MeanNumNo = ...
    mean(subset.NumNo, 'omitnan');

row.MeanNumResponses = ...
    mean(subset.NumResponses, 'omitnan');

row.MedianNumResponses = ...
    median(subset.NumResponses, 'omitnan');

row.MeanYesProportion = ...
    mean(subset.YesProportion, 'omitnan');

row.MeanResponseRatePerMin = ...
    mean(subset.ResponseRatePerMin, 'omitnan');

row.MeanInterResponseIntervalSec = ...
    mean(subset.MeanInterResponseIntervalSec, 'omitnan');

row.MeanTransitionAfterLastResponseSec = ...
    mean(subset.TransitionAfterLastResponseSec, 'omitnan');

row.LikelyGuessedEarlyCount = ...
    sum(subset.PutativeOutcome == "LikelyGuessedEarly");

if height(subset) > 0
    row.LikelyGuessedEarlyRate = ...
        row.LikelyGuessedEarlyCount / height(subset);
else
    row.LikelyGuessedEarlyRate = NaN;
end

row.NearTimeLimitCount = ...
    sum(subset.PutativeOutcome == "NearTimeLimit");

if height(subset) > 0
    row.NearTimeLimitRate = ...
        row.NearTimeLimitCount / height(subset);
else
    row.NearTimeLimitRate = NaN;
end

row.NoResponseTrialCount = ...
    sum(subset.PutativeOutcome == "NoResponses");

row.RoleMismatchCount = ...
    sum(~subset.RoleMatchesSchedule & ...
    ismember(subset.ObservedKnower, ["A", "B"]));

row.MixedRoleTrialCount = ...
    sum(subset.ObservedKnower == "Mixed");

end


%% ========================================================================
function trialTable = create_empty_trial_table()
% CREATE_EMPTY_TRIAL_TABLE
% Return an empty table with the variables needed by the summary helpers.

trialTable = table( ...
    strings(0, 1), ...  % Dyad
    zeros(0, 1), ...    % DyadNumber
    zeros(0, 1), ...    % TrialNumber
    strings(0, 1), ...  % Category
    strings(0, 1), ...  % Target
    strings(0, 1), ...  % Hint
    strings(0, 1), ...  % ExpectedKnower
    strings(0, 1), ...  % ExpectedGuesser
    strings(0, 1), ...  % ObservedKnower
    strings(0, 1), ...  % ObservedGuesser
    false(0, 1), ...    % RoleMatchesSchedule
    zeros(0, 1), ...    % SamplingRateHz
    zeros(0, 1), ...    % BlockStartLatencySamples
    zeros(0, 1), ...    % FirstResponseLatencySamples
    zeros(0, 1), ...    % LastResponseLatencySamples
    zeros(0, 1), ...    % NextBlockStartLatencySamples
    zeros(0, 1), ...    % FirstResponseTimeSec
    zeros(0, 1), ...    % TrialUseTimeSec
    zeros(0, 1), ...    % BlockStartToNextBlockSec
    zeros(0, 1), ...    % TransitionAfterLastResponseSec
    zeros(0, 1), ...    % NumYes
    zeros(0, 1), ...    % NumNo
    zeros(0, 1), ...    % NumResponses
    zeros(0, 1), ...    % YesProportion
    zeros(0, 1), ...    % ResponseRatePerMin
    zeros(0, 1), ...    % MeanInterResponseIntervalSec
    zeros(0, 1), ...    % MedianInterResponseIntervalSec
    strings(0, 1), ...  % LastResponseType
    strings(0, 1), ...  % LastResponseValence
    zeros(0, 1), ...    % LastResponseWasYes
    zeros(0, 1), ...    % SecondsBeforeNominalLimit
    false(0, 1), ...    % NearTimeLimit
    zeros(0, 1), ...    % PutativeEarlyCompletion
    strings(0, 1), ...  % PutativeOutcome
    strings(0, 1), ...  % QCFlag
    strings(0, 1), ...  % SourceFile
    'VariableNames', { ...
    'Dyad', ...
    'DyadNumber', ...
    'TrialNumber', ...
    'Category', ...
    'Target', ...
    'Hint', ...
    'ExpectedKnower', ...
    'ExpectedGuesser', ...
    'ObservedKnower', ...
    'ObservedGuesser', ...
    'RoleMatchesSchedule', ...
    'SamplingRateHz', ...
    'BlockStartLatencySamples', ...
    'FirstResponseLatencySamples', ...
    'LastResponseLatencySamples', ...
    'NextBlockStartLatencySamples', ...
    'FirstResponseTimeSec', ...
    'TrialUseTimeSec', ...
    'BlockStartToNextBlockSec', ...
    'TransitionAfterLastResponseSec', ...
    'NumYes', ...
    'NumNo', ...
    'NumResponses', ...
    'YesProportion', ...
    'ResponseRatePerMin', ...
    'MeanInterResponseIntervalSec', ...
    'MedianInterResponseIntervalSec', ...
    'LastResponseType', ...
    'LastResponseValence', ...
    'LastResponseWasYes', ...
    'SecondsBeforeNominalLimit', ...
    'NearTimeLimit', ...
    'PutativeEarlyCompletion', ...
    'PutativeOutcome', ...
    'QCFlag', ...
    'SourceFile'});

end
