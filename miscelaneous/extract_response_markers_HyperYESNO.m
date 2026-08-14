function [responseTable, runTable, dyadSummary, roleSummary, qcTable] = ...
    extract_response_markers_HyperYESNO(rootDir, dyads, varargin)
% EXTRACT_RESPONSE_MARKERS_HYPERYESNO
% Extract minimal behavioural measures from HyperYESNO response markers.
%
% This function intentionally does not depend on BlockStart markers because
% several recordings contain missing or additional BlockStart events.
%
% The direct behavioural information is extracted from:
%
%   YES_AKnower
%   NO_AKnower
%   YES_BKnower
%   NO_BKnower
%
% A "marker run" is defined as a consecutive sequence of response markers
% belonging to the same Knower. A new run begins when the Knower changes,
% or when an optional long-gap threshold is exceeded.
%
% IMPORTANT:
% A marker run is not assumed to be a verified experimental trial. Missing
% response markers can cause two trials to be merged into one run. Run-based
% measures should therefore be treated as secondary descriptive measures.
%
% The function does not estimate the number of correctly guessed targets.
% Accuracy should be obtained from the video recordings.
%
% INPUT FILES
% -----------
%   E:\EEG_data_HyperYESNO\DyadXX\DyadXX.set
%
% INPUTS
% ------
% rootDir : Root data directory.
%           Default: 'E:\EEG_data_HyperYESNO'
%
% dyads   : Numeric vector of dyad numbers.
%           Default: 1:35
%
% OPTIONAL NAME-VALUE ARGUMENTS
% -----------------------------
% 'OutputDir'
%       Folder used to save the output files.
%       Default: rootDir
%
% 'MaxWithinRunGapSec'
%       Optional maximum interval between consecutive responses within the
%       same run. A larger interval starts a new run even if the Knower did
%       not change. Default: Inf, meaning that runs are split only when the
%       Knower changes.
%
% 'WriteExcel'
%       Save all outputs to an Excel workbook. Default: true
%
% 'Verbose'
%       Print progress information. Default: true
%
% OUTPUTS
% -------
% responseTable
%       One row per valid YES/NO marker.
%
% runTable
%       One row per consecutive same-Knower marker run.
%
% dyadSummary
%       One row per dyad with overall YES/NO counts and descriptive timing.
%
% roleSummary
%       One row per dyad and Knower identity.
%
% qcTable
%       Missing files, loading failures, invalid latencies, missing response
%       markers, and descriptive BlockStart counts.
%
% SAVED FILES
% -----------
% HyperYESNO_response_marker_behaviour.xlsx
% HyperYESNO_response_marker_behaviour.mat
%
% EXAMPLE
% -------
% [responseTable, runTable, dyadSummary, roleSummary, qcTable] = ...
%     extract_response_markers_HyperYESNO( ...
%     'E:\EEG_data_HyperYESNO', 1:35);
%
% Author: Alejandro Perez
% HyperYESNO project, 2026

%% Inputs

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

addParameter(parser, 'MaxWithinRunGapSec', Inf, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, 'WriteExcel', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, rootDir, dyads, varargin{:});
opt = parser.Results;

rootDir = char(string(rootDir));
outputDir = char(string(opt.OutputDir));
dyads = unique(round(dyads(:)'), 'stable');

if exist('pop_loadset', 'file') ~= 2
    error(['EEGLAB function pop_loadset was not found. Start EEGLAB or ' ...
        'add EEGLAB to the MATLAB path before running this function.']);
end

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% Accumulators

allResponseRows = struct([]);
allRunRows = struct([]);
allDyadSummaryRows = struct([]);
allRoleSummaryRows = struct([]);
allQCRows = struct([]);

%% Process dyads

for dyadNumber = dyads

    dyadName = sprintf('Dyad%02d', dyadNumber);
    dyadFolder = fullfile(rootDir, dyadName);
    setFileName = sprintf('%s.set', dyadName);
    setFile = fullfile(dyadFolder, setFileName);

    if opt.Verbose
        fprintf('\n[%s] %s\n', dyadName, setFile);
    end

    if ~isfile(setFile)
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "ERROR", "MissingFile", ...
            "Combined EEGLAB dataset was not found.", setFile, NaN);
        continue
    end

    try
        EEG = pop_loadset('filename', setFileName, 'filepath', dyadFolder);
        EEG = eeg_checkset(EEG, 'eventconsistency');
    catch ME
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "ERROR", "LoadFailure", string(ME.message), setFile, NaN);
        continue
    end

    if ~isfield(EEG, 'srate') || isempty(EEG.srate) || ...
            ~isfinite(EEG.srate) || EEG.srate <= 0
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "ERROR", "InvalidSamplingRate", ...
            "EEG.srate was missing or invalid.", setFile, NaN);
        continue
    end

    if ~isfield(EEG, 'event') || isempty(EEG.event)
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "ERROR", "NoEvents", ...
            "The dataset contained no EEGLAB events.", setFile, 0);
        continue
    end

    %% Decode events

    nEvents = numel(EEG.event);
    decodedType = strings(nEvents, 1);
    latencySamples = nan(nEvents, 1);

    for eventIndex = 1:nEvents
        decodedType(eventIndex) = decode_event_marker(EEG.event(eventIndex));

        if isfield(EEG.event(eventIndex), 'latency')
            latencySamples(eventIndex) = ...
                double(EEG.event(eventIndex).latency);
        end
    end

    validLatency = isfinite(latencySamples);

    if any(~validLatency)
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "WARNING", "InvalidEventLatencies", ...
            sprintf('%d events had invalid latencies and were ignored.', ...
            sum(~validLatency)), setFile, sum(~validLatency));
    end

    decodedType = decodedType(validLatency);
    latencySamples = latencySamples(validLatency);

    [latencySamples, order] = sort(latencySamples, 'ascend');
    decodedType = decodedType(order);

    blockStartCount = sum(decodedType == "BlockStart");

    if blockStartCount ~= 32
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "INFO", "NonstandardBlockStartCount", ...
            sprintf(['Found %d BlockStart markers. These markers were not ' ...
            'used for behavioural extraction.'], blockStartCount), ...
            setFile, blockStartCount);
    end

    responseMask = ismember(decodedType, [ ...
        "YES_AKnower", "NO_AKnower", ...
        "YES_BKnower", "NO_BKnower"]);

    responseTypes = decodedType(responseMask);
    responseLatencies = latencySamples(responseMask);

    nResponses = numel(responseTypes);

    if nResponses == 0
        allQCRows = add_qc_row(allQCRows, dyadName, dyadNumber, ...
            "WARNING", "NoResponseMarkers", ...
            "No valid YES/NO response markers were found.", setFile, 0);
        continue
    end

    %% Decode response attributes

    responseValue = strings(nResponses, 1);
    knower = strings(nResponses, 1);
    guesser = strings(nResponses, 1);

    for responseIndex = 1:nResponses

        if startsWith(responseTypes(responseIndex), "YES_")
            responseValue(responseIndex) = "YES";
        else
            responseValue(responseIndex) = "NO";
        end

        if endsWith(responseTypes(responseIndex), "_AKnower")
            knower(responseIndex) = "A";
            guesser(responseIndex) = "B";
        else
            knower(responseIndex) = "B";
            guesser(responseIndex) = "A";
        end
    end

    timeFromRecordingStartSec = ...
        (responseLatencies - 1) / double(EEG.srate);

    intervalFromPreviousResponseSec = nan(nResponses, 1);

    if nResponses >= 2
        intervalFromPreviousResponseSec(2:end) = ...
            diff(responseLatencies) / double(EEG.srate);
    end

    %% Define consecutive same-Knower marker runs

    runNumber = ones(nResponses, 1);

    for responseIndex = 2:nResponses

        knowerChanged = ...
            knower(responseIndex) ~= knower(responseIndex - 1);

        gapExceeded = ...
            intervalFromPreviousResponseSec(responseIndex) > ...
            opt.MaxWithinRunGapSec;

        if knowerChanged || gapExceeded
            runNumber(responseIndex) = runNumber(responseIndex - 1) + 1;
        else
            runNumber(responseIndex) = runNumber(responseIndex - 1);
        end
    end

    %% Response-level rows

    localResponseRows = struct([]);

    for responseIndex = 1:nResponses

        row = struct;
        row.Dyad = string(dyadName);
        row.DyadNumber = double(dyadNumber);
        row.ResponseIndex = double(responseIndex);
        row.MarkerType = responseTypes(responseIndex);
        row.Response = responseValue(responseIndex);
        row.Knower = knower(responseIndex);
        row.Guesser = guesser(responseIndex);
        row.RunNumber = double(runNumber(responseIndex));
        row.LatencySamples = double(responseLatencies(responseIndex));
        row.TimeFromRecordingStartSec = ...
            double(timeFromRecordingStartSec(responseIndex));
        row.IntervalFromPreviousResponseSec = ...
            double(intervalFromPreviousResponseSec(responseIndex));
        row.SourceFile = string(setFile);

        localResponseRows = append_struct(localResponseRows, row);
        allResponseRows = append_struct(allResponseRows, row);
    end

    localResponseTable = struct2table(localResponseRows);

    %% Run-level rows

    localRunRows = struct([]);
    uniqueRuns = unique(runNumber, 'stable');

    for runIndex = 1:numel(uniqueRuns)

        currentRun = uniqueRuns(runIndex);
        inRun = runNumber == currentRun;

        currentLatencies = responseLatencies(inRun);
        currentResponses = responseValue(inRun);
        currentKnower = knower(find(inRun, 1, 'first'));
        currentGuesser = guesser(find(inRun, 1, 'first'));

        runStartLatency = currentLatencies(1);
        runEndLatency = currentLatencies(end);
        runSpanSec = ...
            (runEndLatency - runStartLatency) / double(EEG.srate);

        nRunResponses = numel(currentResponses);
        nRunYes = sum(currentResponses == "YES");
        nRunNo = sum(currentResponses == "NO");
        yesProportion = nRunYes / nRunResponses;

        if nRunResponses >= 2
            runIntervals = ...
                diff(currentLatencies) / double(EEG.srate);
            meanIntervalSec = mean(runIntervals, 'omitnan');
            medianIntervalSec = median(runIntervals, 'omitnan');
        else
            meanIntervalSec = NaN;
            medianIntervalSec = NaN;
        end

        if runSpanSec > 0
            responseRatePerMin = ...
                nRunResponses / (runSpanSec / 60);
        else
            responseRatePerMin = NaN;
        end

        row = struct;
        row.Dyad = string(dyadName);
        row.DyadNumber = double(dyadNumber);
        row.RunNumber = double(currentRun);
        row.Knower = currentKnower;
        row.Guesser = currentGuesser;
        row.FirstResponseIndex = ...
            double(find(inRun, 1, 'first'));
        row.LastResponseIndex = ...
            double(find(inRun, 1, 'last'));
        row.StartLatencySamples = double(runStartLatency);
        row.EndLatencySamples = double(runEndLatency);
        row.StartTimeSec = ...
            double((runStartLatency - 1) / EEG.srate);
        row.EndTimeSec = ...
            double((runEndLatency - 1) / EEG.srate);
        row.RunSpanSec = double(runSpanSec);
        row.NumYes = double(nRunYes);
        row.NumNo = double(nRunNo);
        row.NumResponses = double(nRunResponses);
        row.YesProportion = double(yesProportion);
        row.MeanInterResponseIntervalSec = double(meanIntervalSec);
        row.MedianInterResponseIntervalSec = double(medianIntervalSec);
        row.ResponseRatePerMin = double(responseRatePerMin);
        row.SourceFile = string(setFile);

        localRunRows = append_struct(localRunRows, row);
        allRunRows = append_struct(allRunRows, row);
    end

    localRunTable = struct2table(localRunRows);

    %% Dyad summary

    summaryRow = build_summary_row( ...
        localResponseTable, localRunTable, dyadName, dyadNumber, ...
        blockStartCount, setFile, "ALL");

    allDyadSummaryRows = append_struct( ...
        allDyadSummaryRows, summaryRow);

    %% Role summaries

    for role = ["A", "B"]

        roleResponses = ...
            localResponseTable(localResponseTable.Knower == role, :);

        roleRuns = ...
            localRunTable(localRunTable.Knower == role, :);

        roleRow = build_summary_row( ...
            roleResponses, roleRuns, dyadName, dyadNumber, ...
            blockStartCount, setFile, role);

        allRoleSummaryRows = append_struct( ...
            allRoleSummaryRows, roleRow);
    end

    if opt.Verbose
        fprintf('  Responses: %d | YES: %d | NO: %d | Runs: %d\n', ...
            nResponses, ...
            sum(responseValue == "YES"), ...
            sum(responseValue == "NO"), ...
            numel(uniqueRuns));
    end
end

%% Convert structures to tables

responseTable = struct_array_to_table(allResponseRows);
runTable = struct_array_to_table(allRunRows);
dyadSummary = struct_array_to_table(allDyadSummaryRows);
roleSummary = struct_array_to_table(allRoleSummaryRows);
qcTable = struct_array_to_table(allQCRows);

if ~isempty(responseTable)
    responseTable = sortrows(responseTable, ...
        {'DyadNumber', 'ResponseIndex'});
end

if ~isempty(runTable)
    runTable = sortrows(runTable, ...
        {'DyadNumber', 'RunNumber'});
end

if ~isempty(dyadSummary)
    dyadSummary = sortrows(dyadSummary, 'DyadNumber');
end

if ~isempty(roleSummary)
    roleSummary = sortrows(roleSummary, ...
        {'DyadNumber', 'Knower'});
end

if ~isempty(qcTable)
    qcTable = sortrows(qcTable, ...
        {'DyadNumber', 'Severity', 'Issue'});
end

%% Save outputs

settings = opt;
settings.RootDir = rootDir;
settings.DyadsRequested = dyads;
settings.CreatedOn = datetime('now');

matFile = fullfile( ...
    outputDir, ...
    'HyperYESNO_response_marker_behaviour.mat');

save(matFile, ...
    'responseTable', ...
    'runTable', ...
    'dyadSummary', ...
    'roleSummary', ...
    'qcTable', ...
    'settings', ...
    '-v7.3');

if opt.WriteExcel

    excelFile = fullfile( ...
        outputDir, ...
        'HyperYESNO_response_marker_behaviour.xlsx');

    if isfile(excelFile)
        delete(excelFile);
    end

    write_table_safely(responseTable, excelFile, 'Responses');
    write_table_safely(runTable, excelFile, 'MarkerRuns');
    write_table_safely(dyadSummary, excelFile, 'DyadSummary');
    write_table_safely(roleSummary, excelFile, 'RoleSummary');
    write_table_safely(qcTable, excelFile, 'QC');
end

if opt.Verbose
    fprintf('\nExtraction finished.\n');
    fprintf('Response rows: %d\n', height(responseTable));
    fprintf('Run rows:      %d\n', height(runTable));
    fprintf('Dyad rows:     %d\n', height(dyadSummary));
    fprintf('Role rows:     %d\n', height(roleSummary));
    fprintf('QC rows:       %d\n', height(qcTable));
    fprintf('MAT file:      %s\n', matFile);

    if opt.WriteExcel
        fprintf('Excel file:    %s\n', excelFile);
    end
end

end


%% ========================================================================
function row = build_summary_row(responseTable, runTable, ...
    dyadName, dyadNumber, blockStartCount, setFile, roleLabel)
% BUILD_SUMMARY_ROW
% Create one consistent summary structure for a dyad or Knower role.

row = struct;
row.Dyad = string(dyadName);
row.DyadNumber = double(dyadNumber);
row.Knower = string(roleLabel);
row.BlockStartCount_DescriptiveOnly = double(blockStartCount);

nResponses = height(responseTable);
row.NumResponses = double(nResponses);

if nResponses > 0
    row.NumYes = double(sum(responseTable.Response == "YES"));
    row.NumNo = double(sum(responseTable.Response == "NO"));
    row.YesProportion = row.NumYes / row.NumResponses;

    firstTime = min(responseTable.TimeFromRecordingStartSec);
    lastTime = max(responseTable.TimeFromRecordingStartSec);
    row.ResponseActiveSpanSec = double(lastTime - firstTime);

    if row.ResponseActiveSpanSec > 0
        row.ResponsesPerActiveMinute = ...
            row.NumResponses / (row.ResponseActiveSpanSec / 60);
    else
        row.ResponsesPerActiveMinute = NaN;
    end

    intervals = responseTable.IntervalFromPreviousResponseSec;
    intervals = intervals(isfinite(intervals));

    if isempty(intervals)
        row.MeanInterResponseIntervalSec = NaN;
        row.MedianInterResponseIntervalSec = NaN;
    else
        row.MeanInterResponseIntervalSec = ...
            mean(intervals, 'omitnan');
        row.MedianInterResponseIntervalSec = ...
            median(intervals, 'omitnan');
    end
else
    row.NumYes = 0;
    row.NumNo = 0;
    row.YesProportion = NaN;
    row.ResponseActiveSpanSec = NaN;
    row.ResponsesPerActiveMinute = NaN;
    row.MeanInterResponseIntervalSec = NaN;
    row.MedianInterResponseIntervalSec = NaN;
end

nRuns = height(runTable);
row.NumMarkerRuns = double(nRuns);

if nRuns > 0
    row.MeanResponsesPerRun = ...
        mean(runTable.NumResponses, 'omitnan');
    row.MedianResponsesPerRun = ...
        median(runTable.NumResponses, 'omitnan');
    row.MeanRunSpanSec = ...
        mean(runTable.RunSpanSec, 'omitnan');
    row.MedianRunSpanSec = ...
        median(runTable.RunSpanSec, 'omitnan');
else
    row.MeanResponsesPerRun = NaN;
    row.MedianResponsesPerRun = NaN;
    row.MeanRunSpanSec = NaN;
    row.MedianRunSpanSec = NaN;
end

row.SourceFile = string(setFile);

end


%% ========================================================================
function marker = decode_event_marker(eventStruct)
% DECODE_EVENT_MARKER
% Decode marker labels from EEG.event.type or EEG.event.value.

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
% Recognize text labels and original numeric Curry marker codes.

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
function output = append_struct(output, row)
% APPEND_STRUCT
% Append one structure without using cell arrays or cell2mat.

if isempty(output)
    output = row;
else
    output(end + 1, 1) = row;
end

end


%% ========================================================================
function T = struct_array_to_table(rows)
% STRUCT_ARRAY_TO_TABLE
% Convert a structure array to a table. Return table() when there are no
% rows. No cell2table or cell2mat conversion is used.

if isempty(rows)
    T = table();
else
    T = struct2table(rows);
end

end


%% ========================================================================
function qcRows = add_qc_row(qcRows, dyadName, dyadNumber, ...
    severity, issue, details, sourceFile, observedCount)
% ADD_QC_ROW
% Add a QC entry using a structure with fixed variable types.

row = struct;
row.Dyad = string(dyadName);
row.DyadNumber = double(dyadNumber);
row.Severity = string(severity);
row.Issue = string(issue);
row.Details = string(details);
row.SourceFile = string(sourceFile);
row.ObservedCount = double(observedCount);

qcRows = append_struct(qcRows, row);

end


%% ========================================================================
function write_table_safely(T, fileName, sheetName)
% WRITE_TABLE_SAFELY
% Write a table to Excel. If the table has no variables, write a simple
% message instead so that the workbook can still be created.

if width(T) == 0
    T = table("No data", 'VariableNames', {'Message'});
end

writetable(T, fileName, 'Sheet', sheetName);

end
