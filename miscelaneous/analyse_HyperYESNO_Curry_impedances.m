function results = analyse_HyperYESNO_Curry_impedances(rootDir, varargin)
% ANALYSE_HYPERYESNO_CURRY_IMPEDANCES
% Batch-extract and summarise electrode impedances from CURRY recordings.
%
% This function is tailored to the EEG HyperYESNO dataset, in which each
% CURRY acquisition contains two simultaneous recordings: the first half of
% channels belongs to participant A and the second half to participant B.
%
% The function does NOT load the large EEG signal file. Instead, it reads
% the small CURRY companion/header files in which impedance values are
% stored:
%   Legacy CURRY:   Acquisition ##.dat + Acquisition ##.dap/.rs3
%   Newer CURRY:    Acquisition ##.cdt + Acquisition ##.cdt.dpa/.dpo
%
% CURRY can retain up to ten impedance checks. The final retained check is
% used as the best available proxy for the impedance immediately before the
% EEG recording started. All available checks are also exported so that
% changes across repeated impedance checks can be inspected.
%
% USAGE
%   results = analyse_HyperYESNO_Curry_impedances;
%
%   results = analyse_HyperYESNO_Curry_impedances( ...
%       'E:\EEG_data_HyperYESNO\Raw_data_Neuroscan_McMaster');
%
%   % Apply an explicit 5-kOhm criterion instead of the data-driven cutoff:
%   results = analyse_HyperYESNO_Curry_impedances([], ...
%       'BadCutoffKOhm', 5);
%
% NAME-VALUE OPTIONS
%   'OutputDir'                Folder for MAT, XLSX and figures.
%   'NamePattern'              Acquisition filename pattern. Default:
%                              'Acquisition*'.
%   'BadCutoffKOhm'            Absolute cutoff used to flag high impedance.
%                              Default [] = robust data-driven cutoff.
%   'ConsistentBadFraction'    Minimum fraction of participants exceeding
%                              the cutoff for a channel/cap flag. Default .25.
%   'ExpectedAcquisitions'     Expected number of dyad recordings. Default 35.
%   'CreateFigures'            Save diagnostic PNG figures. Default true.
%   'WriteExcel'               Save an XLSX workbook. Default true.
%   'Verbose'                  Print progress. Default true.
%
% OUTPUT
%   results.StartImpedanceKOhm  Participants x channels table. There should
%                               be 70 rows for 35 dyads. Row names identify
%                               Dyad##_A and Dyad##_B.
%   results.ParticipantSummary  Mean/median/max impedance per participant.
%   results.ChannelSummary      Channel-wise summary and likely-bad flags,
%                               including separate A-cap and B-cap rates.
%   results.AllSnapshotsLong    Every available impedance measurement.
%   results.SnapshotSummary     Summary of each retained impedance check.
%   results.AcquisitionLog      File-level extraction and QC information.
%   results.GlobalSummary       Dataset-level impedance statistics.
%
% IMPORTANT INTERPRETATION
%   The function distinguishes three quantities:
%     1) HeaderConfiguredThresholdKOhm: only available if CURRY stored an
%        explicit threshold/limit field in the companion file.
%     2) BadCutoffUsedKOhm: the user-specified or robust analytical cutoff
%        used to identify repeatedly high-impedance channels.
%     3) ObservedMaxKOhm/P95/P99: descriptive values from the final checks.
%   If the configured threshold is absent, the exact operator/software
%   threshold cannot be recovered from impedance values alone.
%
% Author: Alejandro Perez / OpenAI coding assistance
% EEG HyperYESNO project, August 2026

% -------------------------------------------------------------------------
% Input handling
% -------------------------------------------------------------------------
if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO\Raw_data_Neuroscan_McMaster';
end

p = inputParser;
p.FunctionName = mfilename;
addRequired(p, 'rootDir', @(x) ischar(x) || isstring(x));
addParameter(p, 'OutputDir', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'NamePattern', 'Acquisition*', @(x) ischar(x) || isstring(x));
addParameter(p, 'BadCutoffKOhm', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x > 0));
addParameter(p, 'ConsistentBadFraction', 0.25, @(x) isscalar(x) && isnumeric(x) && x > 0 && x <= 1);
addParameter(p, 'ExpectedAcquisitions', 35, @(x) isscalar(x) && isnumeric(x) && x >= 1);
addParameter(p, 'CreateFigures', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'WriteExcel', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Verbose', true, @(x) islogical(x) || isnumeric(x));
parse(p, rootDir, varargin{:});
opt = p.Results;

rootDir = char(rootDir);
if isempty(opt.OutputDir)
    outputDir = fullfile(rootDir, 'Impedance_analysis');
else
    outputDir = char(opt.OutputDir);
end

if ~isfolder(rootDir)
    error('Root folder does not exist: %s', rootDir);
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

% -------------------------------------------------------------------------
% Find and naturally sort the CURRY primary data files
% -------------------------------------------------------------------------
files = findCurryPrimaryFiles(rootDir, char(opt.NamePattern));
if isempty(files)
    error(['No .dat or .cdt files matching "%s" were found recursively ' ...
           'under: %s'], char(opt.NamePattern), rootDir);
end

if opt.Verbose
    fprintf('\nFound %d CURRY acquisition files.\n', numel(files));
end
if numel(files) ~= opt.ExpectedAcquisitions
    warning('Expected %d acquisitions but found %d.', ...
        opt.ExpectedAcquisitions, numel(files));
end

% -------------------------------------------------------------------------
% Extract all acquisitions into participant-level structures
% -------------------------------------------------------------------------
participants = emptyParticipantStruct();
logRows = emptyLogStruct();
headerThresholds = [];

for iFile = 1:numel(files)
    thisFile = files(iFile).fullpath;
    dyadID = sprintf('Dyad%02d', iFile);

    if opt.Verbose
        fprintf('[%02d/%02d] %s -> %s\n', ...
            iFile, numel(files), files(iFile).name, dyadID);
    end

    thisLog = initialiseLogRow(files(iFile), dyadID);

    try
        curry = readCurryImpedanceHeader(thisFile);
        thisLog.HeaderFile = string(curry.headerFile);
        thisLog.NChannelsOriginal = curry.nChannels;
        thisLog.NSnapshots = size(curry.impedanceKOhm, 1);
        thisLog.UnitDetected = string(curry.unitDetected);
        thisLog.HeaderThresholdKOhm = curry.headerThresholdKOhm;
        thisLog.RecordingStartTime = curry.recordingStartTime;

        if isfinite(curry.headerThresholdKOhm)
            headerThresholds(end+1, 1) = curry.headerThresholdKOhm; %#ok<AGROW>
        end

        [labelsA, valuesA, labelsB, valuesB, splitInfo] = ...
            splitDyadicImpedances(curry.labels, curry.impedanceKOhm);

        thisLog.NChannelsAIncluded = numel(labelsA);
        thisLog.NChannelsBIncluded = numel(labelsB);
        thisLog.SplitMethod = string(splitInfo);

        times = curry.impedanceTimes;
        if isempty(times)
            times = NaT(size(curry.impedanceKOhm, 1), 1);
        end

        participants(end+1) = makeParticipant( ... %#ok<AGROW>
            sprintf('%s_A', dyadID), dyadID, 'A', files(iFile), ...
            labelsA, valuesA, times, curry.recordingStartTime);
        participants(end+1) = makeParticipant( ... %#ok<AGROW>
            sprintf('%s_B', dyadID), dyadID, 'B', files(iFile), ...
            labelsB, valuesB, times, curry.recordingStartTime);

        thisLog.Status = "OK";
        thisLog.Message = "";

    catch ME
        thisLog.Status = "FAILED";
        thisLog.Message = string(ME.message);
        warning('Failed to extract %s: %s', files(iFile).name, ME.message);
    end

    logRows(end+1) = thisLog; %#ok<AGROW>
end

if isempty(participants)
    AcquisitionLog = struct2table(logRows);
    save(fullfile(outputDir, 'HyperYESNO_impedance_failed_log.mat'), ...
        'AcquisitionLog');
    error('No valid participant impedance data were extracted. Inspect AcquisitionLog.');
end

% -------------------------------------------------------------------------
% Create the requested participants x channels start-impedance table
% -------------------------------------------------------------------------
allChannelLabels = collectStableChannelUnion(participants);
variableNames = makeTableVariableNames(allChannelLabels);

nParticipants = numel(participants);
nChannels = numel(allChannelLabels);
startMatrix = nan(nParticipants, nChannels);
participantIDs = strings(nParticipants, 1);

for iP = 1:nParticipants
    participantIDs(iP) = string(participants(iP).ParticipantID);
    finalValues = participants(iP).SnapshotsKOhm( ...
        participants(iP).FinalSnapshotIndex, :);

    for iLocal = 1:numel(participants(iP).Labels)
        iGlobal = find(strcmpi(participants(iP).Labels{iLocal}, ...
            allChannelLabels), 1, 'first');
        if isempty(iGlobal)
            continue;
        end

        newValue = finalValues(iLocal);
        if isnan(startMatrix(iP, iGlobal))
            startMatrix(iP, iGlobal) = newValue;
        else
            startMatrix(iP, iGlobal) = meanFinite( ...
                [startMatrix(iP, iGlobal), newValue]);
        end
    end
end

StartImpedanceKOhm = array2table(startMatrix, ...
    'VariableNames', variableNames, ...
    'RowNames', cellstr(participantIDs));

% -------------------------------------------------------------------------
% Determine analytical cutoff for likely bad channels
% -------------------------------------------------------------------------
allFinalValues = startMatrix(isfinite(startMatrix) & startMatrix >= 0);
if isempty(allFinalValues)
    error('The extracted impedance table contains no finite values.');
end

if isempty(opt.BadCutoffKOhm)
    globalMedian = median(allFinalValues);
    robustSigma = 1.4826 * median(abs(allFinalValues - globalMedian));
    if robustSigma == 0 || ~isfinite(robustSigma)
        robustSigma = max(globalMedian * 0.10, eps);
    end
    badCutoffKOhm = max([5, 2 * globalMedian, ...
        globalMedian + 6 * robustSigma]);
    cutoffSource = "Robust data-driven: max(5, 2*median, median+6*MADsigma)";
else
    badCutoffKOhm = opt.BadCutoffKOhm;
    cutoffSource = "User specified";
end

% -------------------------------------------------------------------------
% Participant-level summary
% -------------------------------------------------------------------------
participantMean = nan(nParticipants, 1);
participantMedian = nan(nParticipants, 1);
participantP95 = nan(nParticipants, 1);
participantMax = nan(nParticipants, 1);
participantNAbove = zeros(nParticipants, 1);
participantFractionAbove = nan(nParticipants, 1);
participantNValid = zeros(nParticipants, 1);
finalSnapshotTime = NaT(nParticipants, 1);
finalSecondsFromStart = nan(nParticipants, 1);

for iP = 1:nParticipants
    x = startMatrix(iP, :);
    x = x(isfinite(x));
    participantNValid(iP) = numel(x);
    if isempty(x), continue; end
    participantMean(iP) = mean(x);
    participantMedian(iP) = median(x);
    participantP95(iP) = percentileFinite(x, 95);
    participantMax(iP) = max(x);
    participantNAbove(iP) = sum(x > badCutoffKOhm);
    participantFractionAbove(iP) = participantNAbove(iP) / numel(x);
    iFinal = participants(iP).FinalSnapshotIndex;
    if numel(participants(iP).Times) >= iFinal
        finalSnapshotTime(iP) = participants(iP).Times(iFinal);
    end
    if ~isnat(finalSnapshotTime(iP)) && ...
            ~isnat(participants(iP).RecordingStartTime)
        finalSecondsFromStart(iP) = seconds( ...
            finalSnapshotTime(iP) - participants(iP).RecordingStartTime);
    end
end

ParticipantSummary = table( ...
    participantIDs, ...
    string({participants.DyadID})', ...
    string({participants.Cap})', ...
    [participants.AcquisitionNumber]', ...
    string({participants.AcquisitionFile})', ...
    [participants.FinalSnapshotIndex]', ...
    [participants.NSnapshots]', finalSnapshotTime, finalSecondsFromStart, ...
    participantNValid, participantMean, participantMedian, participantP95, ...
    participantMax, participantNAbove, participantFractionAbove, ...
    'VariableNames', { ...
    'ParticipantID','DyadID','Cap','AcquisitionNumber','AcquisitionFile', ...
    'FinalSnapshotIndex','NSnapshots','FinalSnapshotTime', ...
    'FinalSecondsFromRecordingStart','NValidChannels', ...
    'MeanKOhm','MedianKOhm','P95KOhm','MaxKOhm', ...
    'NAboveBadCutoff','FractionAboveBadCutoff'});

% -------------------------------------------------------------------------
% Channel-level summary, including cap-specific consistency
% -------------------------------------------------------------------------
isCapA = strcmp({participants.Cap}, 'A')';
isCapB = strcmp({participants.Cap}, 'B')';

chNValid = zeros(nChannels, 1);
chMean = nan(nChannels, 1);
chMedian = nan(nChannels, 1);
chP95 = nan(nChannels, 1);
chMax = nan(nChannels, 1);
chNAbove = zeros(nChannels, 1);
chBadFraction = nan(nChannels, 1);
chBadFractionA = nan(nChannels, 1);
chBadFractionB = nan(nChannels, 1);
chNValidA = zeros(nChannels, 1);
chNValidB = zeros(nChannels, 1);

for iCh = 1:nChannels
    x = startMatrix(:, iCh);
    xValid = x(isfinite(x));
    chNValid(iCh) = numel(xValid);
    if ~isempty(xValid)
        chMean(iCh) = mean(xValid);
        chMedian(iCh) = median(xValid);
        chP95(iCh) = percentileFinite(xValid, 95);
        chMax(iCh) = max(xValid);
        chNAbove(iCh) = sum(xValid > badCutoffKOhm);
        chBadFraction(iCh) = chNAbove(iCh) / numel(xValid);
    end

    xA = x(isCapA & isfinite(x));
    xB = x(isCapB & isfinite(x));
    chNValidA(iCh) = numel(xA);
    chNValidB(iCh) = numel(xB);
    if ~isempty(xA), chBadFractionA(iCh) = mean(xA > badCutoffKOhm); end
    if ~isempty(xB), chBadFractionB(iCh) = mean(xB > badCutoffKOhm); end
end

channelMedianFinite = chMedian(isfinite(chMedian));
medianOfChannelMedians = median(channelMedianFinite);
channelMedianMADsigma = 1.4826 * median(abs( ...
    channelMedianFinite - medianOfChannelMedians));
if channelMedianMADsigma == 0 || ~isfinite(channelMedianMADsigma)
    channelMedianMADsigma = max(medianOfChannelMedians * 0.10, eps);
end
relativeMedianOutlier = chMedian > ...
    (medianOfChannelMedians + 4 * channelMedianMADsigma);

consistentOverall = chBadFraction >= opt.ConsistentBadFraction;
consistentCapA = chBadFractionA >= opt.ConsistentBadFraction;
consistentCapB = chBadFractionB >= opt.ConsistentBadFraction;
likelyBad = consistentOverall | consistentCapA | consistentCapB | relativeMedianOutlier;

ChannelSummary = table( ...
    string(allChannelLabels(:)), string(variableNames(:)), ...
    chNValid, chMean, chMedian, chP95, chMax, chNAbove, chBadFraction, ...
    chNValidA, chBadFractionA, chNValidB, chBadFractionB, ...
    consistentOverall, consistentCapA, consistentCapB, ...
    relativeMedianOutlier, likelyBad, ...
    'VariableNames', { ...
    'ChannelLabel','TableVariableName','NValidParticipants', ...
    'MeanKOhm','MedianKOhm','P95KOhm','MaxKOhm', ...
    'NAboveBadCutoff','BadFractionOverall', ...
    'NValidCapA','BadFractionCapA','NValidCapB','BadFractionCapB', ...
    'ConsistentlyBadOverall','ConsistentlyBadCapA','ConsistentlyBadCapB', ...
    'RelativeMedianOutlier','LikelyBadChannel'});

% Put the most suspicious channels first.
priority = max([replaceNaN(chBadFraction, -1), ...
                replaceNaN(chBadFractionA, -1), ...
                replaceNaN(chBadFractionB, -1)], [], 2);
ChannelSummary.PriorityScore = priority;
ChannelSummary = sortrows(ChannelSummary, ...
    {'LikelyBadChannel','PriorityScore','MedianKOhm'}, ...
    {'descend','descend','descend'});

% -------------------------------------------------------------------------
% Long table with all available impedance snapshots
% -------------------------------------------------------------------------
[AllSnapshotsLong, SnapshotSummary] = buildSnapshotTables( ...
    participants, badCutoffKOhm);

% -------------------------------------------------------------------------
% Acquisition log and global summary
% -------------------------------------------------------------------------
AcquisitionLog = struct2table(logRows);

if isempty(headerThresholds)
    configuredThreshold = NaN;
    configuredThresholdAvailable = false;
else
    configuredThreshold = median(headerThresholds);
    configuredThresholdAvailable = true;
end

% A descriptive upper envelope excluding channels already flagged as likely
% broken. This can help approximate the practical range accepted during
% setup, but it is not treated as the exact CURRY acquisition threshold.
nonFlaggedMask = ~likelyBad;
if any(nonFlaggedMask)
    nonFlaggedValues = startMatrix(:, nonFlaggedMask);
    nonFlaggedValues = nonFlaggedValues(isfinite(nonFlaggedValues));
else
    nonFlaggedValues = allFinalValues;
end

GlobalSummary = table( ...
    numel(files), sum(AcquisitionLog.Status == "OK"), ...
    sum(AcquisitionLog.Status == "FAILED"), nParticipants, nChannels, ...
    configuredThresholdAvailable, configuredThreshold, ...
    badCutoffKOhm, cutoffSource, ...
    mean(allFinalValues), median(allFinalValues), ...
    percentileFinite(allFinalValues, 95), ...
    percentileFinite(allFinalValues, 99), max(allFinalValues), ...
    percentileFinite(nonFlaggedValues, 99), max(nonFlaggedValues), ...
    sum(ChannelSummary.LikelyBadChannel), ...
    'VariableNames', { ...
    'NFilesFound','NFilesSuccessful','NFilesFailed','NParticipants', ...
    'NChannelsInWideTable','ConfiguredThresholdAvailable', ...
    'HeaderConfiguredThresholdKOhm','BadCutoffUsedKOhm', ...
    'BadCutoffSource','ObservedMeanStartKOhm','ObservedMedianStartKOhm', ...
    'ObservedP95StartKOhm','ObservedP99StartKOhm', ...
    'ObservedMaxStartKOhm','EmpiricalP99ExcludingFlaggedKOhm', ...
    'EmpiricalMaxExcludingFlaggedKOhm','NLikelyBadChannels'});

% -------------------------------------------------------------------------
% Package and save
% -------------------------------------------------------------------------
results = struct();
results.StartImpedanceKOhm = StartImpedanceKOhm;
results.ParticipantSummary = ParticipantSummary;
results.ChannelSummary = ChannelSummary;
results.AllSnapshotsLong = AllSnapshotsLong;
results.SnapshotSummary = SnapshotSummary;
results.AcquisitionLog = AcquisitionLog;
results.GlobalSummary = GlobalSummary;
results.ChannelLabelToVariableName = table( ...
    string(allChannelLabels(:)), string(variableNames(:)), ...
    'VariableNames', {'ChannelLabel','TableVariableName'});
results.Options = opt;
results.RootDir = rootDir;
results.OutputDir = outputDir;

matFile = fullfile(outputDir, 'HyperYESNO_Curry_impedance_analysis.mat');
save(matFile, 'results', '-v7.3');

if opt.WriteExcel
    xlsxFile = fullfile(outputDir, 'HyperYESNO_Curry_impedance_analysis.xlsx');
    if isfile(xlsxFile)
        delete(xlsxFile);
    end

    StartExport = StartImpedanceKOhm;
    StartExport.Properties.RowNames = {};
    StartExport = addvars(StartExport, participantIDs, ...
        'Before', 1, 'NewVariableNames', 'ParticipantID');

    writetable(StartExport, xlsxFile, 'Sheet', 'Start_impedance_kOhm');
    writetable(ParticipantSummary, xlsxFile, 'Sheet', 'Participant_summary');
    writetable(ChannelSummary, xlsxFile, 'Sheet', 'Channel_summary');
    writetable(SnapshotSummary, xlsxFile, 'Sheet', 'Snapshot_summary');
    writetable(AllSnapshotsLong, xlsxFile, 'Sheet', 'All_snapshots_long');
    writetable(AcquisitionLog, xlsxFile, 'Sheet', 'Acquisition_log');
    writetable(GlobalSummary, xlsxFile, 'Sheet', 'Global_summary');
    writetable(results.ChannelLabelToVariableName, xlsxFile, ...
        'Sheet', 'Channel_name_map');
end

if opt.CreateFigures
    createDiagnosticFigures(startMatrix, participantIDs, allChannelLabels, ...
        ChannelSummary, SnapshotSummary, badCutoffKOhm, outputDir);
end

% -------------------------------------------------------------------------
% Command-window report
% -------------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('CURRY impedance extraction completed\n');
fprintf('Successful acquisitions: %d/%d\n', ...
    sum(AcquisitionLog.Status == "OK"), numel(files));
fprintf('Participants:            %d\n', nParticipants);
fprintf('Channels in wide table:  %d\n', nChannels);
fprintf('Mean final impedance:    %.2f kOhm\n', ...
    GlobalSummary.ObservedMeanStartKOhm);
fprintf('Median final impedance:  %.2f kOhm\n', ...
    GlobalSummary.ObservedMedianStartKOhm);
fprintf('Analytical bad cutoff:   %.2f kOhm (%s)\n', ...
    badCutoffKOhm, cutoffSource);
if configuredThresholdAvailable
    fprintf('Header threshold:        %.2f kOhm\n', configuredThreshold);
else
    fprintf('Header threshold:        not stored/detected\n');
end
fprintf('Likely bad channels:     %d\n', ...
    GlobalSummary.NLikelyBadChannels);
fprintf('Results folder:          %s\n', outputDir);
fprintf('============================================================\n\n');

if any(ChannelSummary.LikelyBadChannel)
    disp(ChannelSummary(ChannelSummary.LikelyBadChannel, ...
        {'ChannelLabel','MedianKOhm','BadFractionOverall', ...
         'BadFractionCapA','BadFractionCapB','LikelyBadChannel'}));
end

end

% =========================================================================
% Local functions
% =========================================================================

function files = findCurryPrimaryFiles(rootDir, namePattern)
patterns = {[namePattern '.dat'], [namePattern '.cdt']};
files = struct('name', {}, 'folder', {}, 'fullpath', {}, ...
    'acquisitionNumber', {}, 'extension', {});

for iPat = 1:numel(patterns)
    d = dir(fullfile(rootDir, '**', patterns{iPat}));
    d = d(~[d.isdir]);
    for i = 1:numel(d)
        [~, ~, ext] = fileparts(d(i).name);
        tok = regexp(d(i).name, '(?i)Acquisition\s*0*(\d+)', ...
            'tokens', 'once');
        if isempty(tok)
            acqNumber = Inf;
        else
            acqNumber = str2double(tok{1});
        end
        newRow.name = d(i).name;
        newRow.folder = d(i).folder;
        newRow.fullpath = fullfile(d(i).folder, d(i).name);
        newRow.acquisitionNumber = acqNumber;
        newRow.extension = lower(ext);
        files(end+1) = newRow; %#ok<AGROW>
    end
end

if isempty(files), return; end

% Remove duplicate exports with the same folder and base filename. If both
% .cdt and .dat exist, prefer .cdt because its companion file generally
% contains labels and impedance metadata together.
baseKeys = strings(numel(files), 1);
extPriority = zeros(numel(files), 1);
for i = 1:numel(files)
    [~, baseName, ~] = fileparts(files(i).name);
    baseKeys(i) = lower(string(fullfile(files(i).folder, baseName)));
    extPriority(i) = double(~strcmpi(files(i).extension, '.cdt'));
end
Tdedup = table((1:numel(files))', baseKeys, extPriority, ...
    'VariableNames', {'Index','BaseKey','ExtensionPriority'});
Tdedup = sortrows(Tdedup, {'BaseKey','ExtensionPriority'});
[~, firstByBase] = unique(Tdedup.BaseKey, 'stable');
files = files(Tdedup.Index(firstByBase));

% Natural numeric order; unknown numbers go last.
acqNums = [files.acquisitionNumber]';
names = lower(string({files.name})');
T = table((1:numel(files))', acqNums, names, ...
    'VariableNames', {'Index','AcquisitionNumber','Name'});
T = sortrows(T, {'AcquisitionNumber','Name'});
files = files(T.Index);
end

function curry = readCurryImpedanceHeader(dataFile)
[folder, name, ext] = fileparts(dataFile);
ext = lower(ext);

switch ext
    case '.dat'
        headerCandidates = {fullfile(folder, [name '.dap'])};
        labelCandidates = {fullfile(folder, [name '.rs3'])};
    case '.cdt'
        headerCandidates = {[dataFile '.dpa'], [dataFile '.dpo']};
        labelCandidates = headerCandidates;
    otherwise
        error('Unsupported CURRY primary extension: %s', ext);
end

headerFile = firstExistingFile(headerCandidates);
if isempty(headerFile)
    error('No CURRY parameter/header companion file was found for %s.', dataFile);
end

headerText = fileread(headerFile);
nChannels = parseScalarField(headerText, {'NumChannels','NUM_CHANNELS'});
if ~isfinite(nChannels) || nChannels < 1
    error('Could not determine NumChannels from %s.', headerFile);
end
nChannels = round(nChannels);

[impedanceRaw, validRows] = parseNumericListMatrix( ...
    headerText, 'IMPEDANCE_VALUES', nChannels);
if isempty(impedanceRaw)
    error('No IMPEDANCE_VALUES list was found in %s.', headerFile);
end
impedanceRaw(impedanceRaw == -1) = NaN;

% CURRY files commonly store impedances in Ohms, although the list itself
% does not always declare its unit. Detect the scale conservatively.
finitePositive = impedanceRaw(isfinite(impedanceRaw) & impedanceRaw >= 0);
if isempty(finitePositive)
    error('IMPEDANCE_VALUES was present but contained no finite values.');
end

if median(finitePositive) > 200
    impedanceKOhm = impedanceRaw / 1000;
    unitDetected = 'Ohm -> converted to kOhm';
    wasOhm = true;
else
    impedanceKOhm = impedanceRaw;
    unitDetected = 'kOhm (values retained)';
    wasOhm = false;
end

% Parse optional timestamps. They have seven columns:
% year, month, day, hour, minute, second, millisecond.
[timeNumbers, ~] = parseNumericListMatrix(headerText, 'IMPEDANCE_TIMES', 7);
impedanceTimes = NaT(size(impedanceKOhm, 1), 1);
if ~isempty(timeNumbers)
    if size(timeNumbers, 1) >= max(validRows)
        timeNumbers = timeNumbers(validRows, :);
    elseif size(timeNumbers, 1) ~= size(impedanceKOhm, 1)
        timeNumbers = [];
    end

    if ~isempty(timeNumbers)
        nTime = min(size(timeNumbers, 1), size(impedanceKOhm, 1));
        for i = 1:nTime
            t = timeNumbers(i, :);
            if all(isfinite(t)) && t(1) > 1900 && t(2) >= 1 && ...
                    t(3) >= 1 && t(4) >= 0
                try
                    impedanceTimes(i) = datetime( ...
                        t(1), t(2), t(3), t(4), t(5), ...
                        t(6) + t(7)/1000);
                catch
                    impedanceTimes(i) = NaT;
                end
            end
        end
    end
end

% If multiple valid timestamps exist, ensure chronological order.
validTime = find(~isnat(impedanceTimes));
if numel(validTime) >= 2 && numel(validTime) == numel(impedanceTimes)
    [~, order] = sort(impedanceTimes);
    impedanceTimes = impedanceTimes(order);
    impedanceKOhm = impedanceKOhm(order, :);
end

% Labels may be stored in the parameter file (.dpa/.dpo), or separately in
% the legacy .rs3 file.
labelText = '';
labelFile = firstExistingFile(labelCandidates);
if ~isempty(labelFile)
    labelText = fileread(labelFile);
end
labels = parseCurryLabels(labelText, nChannels);
if numel(labels) ~= nChannels
    error('Label count (%d) does not match NumChannels (%d).', ...
        numel(labels), nChannels);
end

recordingStartTime = parseRecordingStartTime(headerText);

thresholdCandidates = parseHeaderImpedanceThresholds(headerText);
if isempty(thresholdCandidates)
    headerThresholdKOhm = NaN;
else
    if wasOhm
        thresholdCandidates(thresholdCandidates > 200) = ...
            thresholdCandidates(thresholdCandidates > 200) / 1000;
    end
    headerThresholdKOhm = median(thresholdCandidates(isfinite(thresholdCandidates)));
end

curry = struct();
curry.headerFile = headerFile;
curry.nChannels = nChannels;
curry.labels = labels;
curry.impedanceKOhm = impedanceKOhm;
curry.impedanceTimes = impedanceTimes;
curry.unitDetected = unitDetected;
curry.headerThresholdKOhm = headerThresholdKOhm;
curry.recordingStartTime = recordingStartTime;
end

function recordingStartTime = parseRecordingStartTime(text)
recordingStartTime = NaT;
y = parseScalarField(text, {'StartYear'});
mo = parseScalarField(text, {'StartMonth'});
d = parseScalarField(text, {'StartDay'});
h = parseScalarField(text, {'StartHour'});
mi = parseScalarField(text, {'StartMin'});
se = parseScalarField(text, {'StartSec'});
ms = parseScalarField(text, {'StartMillisec'});
if ~isfinite(ms), ms = 0; end
if all(isfinite([y mo d h mi se])) && y > 1900 && mo >= 1 && ...
        d >= 1 && h >= 0
    try
        recordingStartTime = datetime(y, mo, d, h, mi, se + ms/1000);
    catch
        recordingStartTime = NaT;
    end
end
end

function file = firstExistingFile(candidates)
file = '';
for i = 1:numel(candidates)
    if isfile(candidates{i})
        file = candidates{i};
        return;
    end
end
end

function value = parseScalarField(text, fieldNames)
value = NaN;
for i = 1:numel(fieldNames)
    expression = ['(?im)^\s*' regexptranslate('escape', fieldNames{i}) ...
        '\s*=\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)'];
    token = regexp(text, expression, 'tokens', 'once');
    if ~isempty(token)
        value = str2double(token{1});
        return;
    end
end
end

function [matrix, validRows] = parseNumericListMatrix(text, listName, nColumns)
matrix = [];
validRows = [];
expression = ['(?ms)^\s*' regexptranslate('escape', listName) ...
    '\s+START_LIST[^\r\n]*\r?\n(.*?)^\s*' ...
    regexptranslate('escape', listName) '\s+END_LIST'];
token = regexp(text, expression, 'tokens', 'once');
if isempty(token), return; end

numbers = sscanf(token{1}, '%f');
if isempty(numbers), return; end
if mod(numel(numbers), nColumns) ~= 0
    error('%s contains %d values, not divisible by %d columns.', ...
        listName, numel(numbers), nColumns);
end

matrixAll = reshape(numbers, nColumns, []).';
if strcmpi(listName, 'IMPEDANCE_VALUES')
    missing = matrixAll == -1 | ~isfinite(matrixAll);
    validMask = ~all(missing, 2);
else
    validMask = true(size(matrixAll, 1), 1);
end
validRows = find(validMask);
matrix = matrixAll(validMask, :);
end

function labels = parseCurryLabels(text, nChannels)
labels = {};
if ~isempty(text)
    expression = ['(?ms)^\s*LABELS(?:_[A-Za-z0-9]+)?\s+' ...
        'START_LIST[^\r\n]*\r?\n(.*?)^\s*LABELS' ...
        '(?:_[A-Za-z0-9]+)?\s+END_LIST'];
    blocks = regexp(text, expression, 'tokens');
    for iB = 1:numel(blocks)
        lines = regexp(blocks{iB}{1}, '\r?\n', 'split');
        for iL = 1:numel(lines)
            thisLabel = strtrim(lines{iL});
            thisLabel = regexprep(thisLabel, '\s*#.*$', '');
            if ~isempty(thisLabel)
                labels{end+1} = thisLabel; %#ok<AGROW>
            end
        end
    end
end

if numel(labels) < nChannels
    for i = (numel(labels)+1):nChannels
        labels{i} = sprintf('EEG%03d', i); %#ok<AGROW>
    end
elseif numel(labels) > nChannels
    labels = labels(1:nChannels);
end
end

function thresholds = parseHeaderImpedanceThresholds(text)
thresholds = [];
lines = regexp(text, '\r?\n', 'split');
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if isempty(regexpi(line, 'impedance', 'once')) || ...
            isempty(regexpi(line, 'threshold|limit|maximum|max', 'once'))
        continue;
    end
    token = regexp(line, '=\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)', ...
        'tokens', 'once');
    if ~isempty(token)
        value = str2double(token{1});
        if isfinite(value) && value > 0
            thresholds(end+1, 1) = value; %#ok<AGROW>
        end
    end
end
end

function [labelsA, valuesA, labelsB, valuesB, splitInfo] = ...
        splitDyadicImpedances(labels, values)
labels = labels(:)';
nChannels = numel(labels);
if size(values, 2) ~= nChannels
    error('Impedance matrix and label count do not agree.');
end

if mod(nChannels, 2) ~= 0
    globalKeep = ~cellfun(@isTriggerLabel, labels);
    if mod(sum(globalKeep), 2) ~= 0
        error(['Odd number of channels (%d), and removing globally labelled ' ...
               'trigger channels did not produce two equal halves.'], nChannels);
    end
    labels = labels(globalKeep);
    values = values(:, globalKeep);
    nChannels = numel(labels);
    splitInfo = 'Removed global trigger-like channel(s), then split equal halves';
else
    splitInfo = 'Split original channel order into equal halves';
end

half = nChannels / 2;
idxA = 1:half;
idxB = (half+1):nChannels;

[labelsA, valuesA] = cleanParticipantBlock(labels(idxA), values(:, idxA));
[labelsB, valuesB] = cleanParticipantBlock(labels(idxB), values(:, idxB));

if isempty(labelsA) || isempty(labelsB)
    error('No usable channels remained after participant split/exclusions.');
end
end

function [labelsOut, valuesOut] = cleanParticipantBlock(labelsIn, valuesIn)
canonical = cellfun(@canonicalChannelLabel, labelsIn, ...
    'UniformOutput', false);
exclude = false(size(canonical));
for i = 1:numel(canonical)
    exclude(i) = ismember(upper(canonical{i}), {'M1','M2'}) || ...
        isTriggerLabel(canonical{i});
end

labelsOut = canonical(~exclude);
valuesOut = valuesIn(:, ~exclude);

% If normalisation created duplicated names, merge them using their mean.
[uniqueLower, ~, group] = unique(lower(string(labelsOut)), 'stable');
if numel(uniqueLower) < numel(labelsOut)
    mergedValues = nan(size(valuesOut, 1), numel(uniqueLower));
    mergedLabels = cell(1, numel(uniqueLower));
    for iG = 1:numel(uniqueLower)
        idx = group == iG;
        mergedLabels{iG} = labelsOut{find(idx, 1, 'first')};
        for iRow = 1:size(valuesOut, 1)
            mergedValues(iRow, iG) = meanFinite(valuesOut(iRow, idx));
        end
    end
    labelsOut = mergedLabels;
    valuesOut = mergedValues;
end
end

function label = canonicalChannelLabel(label)
label = strtrim(char(label));
label = regexprep(label, '(?i)^(A|B)\s*[:_\-]\s*', '');
label = regexprep(label, '(?i)\s*[:_\-]\s*(A|B)$', '');
label = regexprep(label, '(?i)\s*\((A|B)\)$', '');
label = regexprep(label, '\s+', '');
label = upper(label);
end

function tf = isTriggerLabel(label)
x = lower(strtrim(char(label)));
xCompact = regexprep(x, '[\s_\-]', '');
tf = contains(xCompact, 'trigger') || ...
     ismember(xCompact, {'trig','trg','status','marker','event', ...
                         'stim','sti014','triggerchannel'});
end

function p = makeParticipant(participantID, dyadID, cap, fileInfo, ...
        labels, snapshots, times, recordingStartTime)
validRows = find(any(isfinite(snapshots), 2));
if isempty(validRows)
    error('%s contains no finite impedance snapshot for cap %s.', ...
        fileInfo.name, cap);
end

p = struct();
p.ParticipantID = participantID;
p.DyadID = dyadID;
p.Cap = cap;
p.AcquisitionNumber = fileInfo.acquisitionNumber;
p.AcquisitionFile = fileInfo.name;
p.AcquisitionFullPath = fileInfo.fullpath;
p.Labels = labels;
p.SnapshotsKOhm = snapshots;
p.Times = times;
p.RecordingStartTime = recordingStartTime;
p.FinalSnapshotIndex = validRows(end);
p.NSnapshots = size(snapshots, 1);
end

function labels = collectStableChannelUnion(participants)
labels = {};
for iP = 1:numel(participants)
    for iL = 1:numel(participants(iP).Labels)
        candidate = participants(iP).Labels{iL};
        if ~any(strcmpi(candidate, labels))
            labels{end+1} = candidate; %#ok<AGROW>
        end
    end
end
end

function names = makeTableVariableNames(labels)
names = matlab.lang.makeValidName(labels, 'ReplacementStyle', 'delete');
for i = 1:numel(names)
    if isempty(names{i})
        names{i} = sprintf('Channel%03d', i);
    end
end
names = matlab.lang.makeUniqueStrings(names, {}, namelengthmax);
end

function [longTable, snapshotTable] = buildSnapshotTables(participants, cutoff)
participantCol = strings(0,1);
dyadCol = strings(0,1);
capCol = strings(0,1);
acqNumberCol = zeros(0,1);
acqFileCol = strings(0,1);
snapshotCol = zeros(0,1);
timeCol = NaT(0,1);
recordingStartCol = NaT(0,1);
secondsFromStartCol = nan(0,1);
channelCol = strings(0,1);
impedanceCol = zeros(0,1);
aboveCol = false(0,1);

sumParticipant = strings(0,1);
sumDyad = strings(0,1);
sumCap = strings(0,1);
sumAcq = zeros(0,1);
sumSnapshot = zeros(0,1);
sumTime = NaT(0,1);
sumRecordingStart = NaT(0,1);
sumSecondsFromStart = nan(0,1);
sumNValid = zeros(0,1);
sumMean = zeros(0,1);
sumMedian = zeros(0,1);
sumP95 = zeros(0,1);
sumMax = zeros(0,1);
sumFractionAbove = zeros(0,1);

for iP = 1:numel(participants)
    P = participants(iP);
    nSnap = size(P.SnapshotsKOhm, 1);
    nCh = numel(P.Labels);

    for iS = 1:nSnap
        x = P.SnapshotsKOhm(iS, :)';
        nNew = nCh;
        participantCol(end+1:end+nNew,1) = string(P.ParticipantID); %#ok<AGROW>
        dyadCol(end+1:end+nNew,1) = string(P.DyadID); %#ok<AGROW>
        capCol(end+1:end+nNew,1) = string(P.Cap); %#ok<AGROW>
        acqNumberCol(end+1:end+nNew,1) = P.AcquisitionNumber; %#ok<AGROW>
        acqFileCol(end+1:end+nNew,1) = string(P.AcquisitionFile); %#ok<AGROW>
        snapshotCol(end+1:end+nNew,1) = iS; %#ok<AGROW>
        if numel(P.Times) >= iS
            thisTime = P.Times(iS);
            timeCol(end+1:end+nNew,1) = thisTime; %#ok<AGROW>
        else
            thisTime = NaT;
            timeCol(end+1:end+nNew,1) = NaT; %#ok<AGROW>
        end
        recordingStartCol(end+1:end+nNew,1) = P.RecordingStartTime; %#ok<AGROW>
        if ~isnat(thisTime) && ~isnat(P.RecordingStartTime)
            thisSeconds = seconds(thisTime - P.RecordingStartTime);
        else
            thisSeconds = NaN;
        end
        secondsFromStartCol(end+1:end+nNew,1) = thisSeconds; %#ok<AGROW>
        channelCol(end+1:end+nNew,1) = string(P.Labels(:)); %#ok<AGROW>
        impedanceCol(end+1:end+nNew,1) = x; %#ok<AGROW>
        aboveCol(end+1:end+nNew,1) = isfinite(x) & x > cutoff; %#ok<AGROW>

        valid = x(isfinite(x));
        sumParticipant(end+1,1) = string(P.ParticipantID); %#ok<AGROW>
        sumDyad(end+1,1) = string(P.DyadID); %#ok<AGROW>
        sumCap(end+1,1) = string(P.Cap); %#ok<AGROW>
        sumAcq(end+1,1) = P.AcquisitionNumber; %#ok<AGROW>
        sumSnapshot(end+1,1) = iS; %#ok<AGROW>
        if numel(P.Times) >= iS
            thisSummaryTime = P.Times(iS);
            sumTime(end+1,1) = thisSummaryTime; %#ok<AGROW>
        else
            thisSummaryTime = NaT;
            sumTime(end+1,1) = NaT; %#ok<AGROW>
        end
        sumRecordingStart(end+1,1) = P.RecordingStartTime; %#ok<AGROW>
        if ~isnat(thisSummaryTime) && ~isnat(P.RecordingStartTime)
            sumSecondsFromStart(end+1,1) = seconds( ...
                thisSummaryTime - P.RecordingStartTime); %#ok<AGROW>
        else
            sumSecondsFromStart(end+1,1) = NaN; %#ok<AGROW>
        end
        sumNValid(end+1,1) = numel(valid); %#ok<AGROW>
        if isempty(valid)
            sumMean(end+1,1) = NaN; %#ok<AGROW>
            sumMedian(end+1,1) = NaN; %#ok<AGROW>
            sumP95(end+1,1) = NaN; %#ok<AGROW>
            sumMax(end+1,1) = NaN; %#ok<AGROW>
            sumFractionAbove(end+1,1) = NaN; %#ok<AGROW>
        else
            sumMean(end+1,1) = mean(valid); %#ok<AGROW>
            sumMedian(end+1,1) = median(valid); %#ok<AGROW>
            sumP95(end+1,1) = percentileFinite(valid, 95); %#ok<AGROW>
            sumMax(end+1,1) = max(valid); %#ok<AGROW>
            sumFractionAbove(end+1,1) = mean(valid > cutoff); %#ok<AGROW>
        end
    end
end

longTable = table(participantCol, dyadCol, capCol, acqNumberCol, ...
    acqFileCol, snapshotCol, timeCol, recordingStartCol, ...
    secondsFromStartCol, channelCol, impedanceCol, aboveCol, ...
    'VariableNames', {'ParticipantID','DyadID','Cap','AcquisitionNumber', ...
    'AcquisitionFile','SnapshotIndex','Timestamp','RecordingStartTime', ...
    'SecondsFromRecordingStart','ChannelLabel','ImpedanceKOhm', ...
    'AboveBadCutoff'});

snapshotTable = table(sumParticipant, sumDyad, sumCap, sumAcq, ...
    sumSnapshot, sumTime, sumRecordingStart, sumSecondsFromStart, ...
    sumNValid, sumMean, sumMedian, sumP95, sumMax, sumFractionAbove, ...
    'VariableNames', {'ParticipantID','DyadID','Cap','AcquisitionNumber', ...
    'SnapshotIndex','Timestamp','RecordingStartTime', ...
    'SecondsFromRecordingStart','NValidChannels','MeanKOhm','MedianKOhm', ...
    'P95KOhm','MaxKOhm','FractionAboveBadCutoff'});
end

function createDiagnosticFigures(startMatrix, participantIDs, channelLabels, ...
        channelSummary, snapshotSummary, cutoff, outputDir)
try
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Position', [100 100 1500 850]);
    imagesc(startMatrix);
    colorbar;
    xlabel('Channel');
    ylabel('Participant');
    title(sprintf('Final retained impedance check (kOhm); cutoff = %.2f kOhm', cutoff));
    set(gca, 'XTick', 1:numel(channelLabels), ...
        'XTickLabel', channelLabels, 'XTickLabelRotation', 90);
    if numel(participantIDs) <= 80
        set(gca, 'YTick', 1:numel(participantIDs), ...
            'YTickLabel', participantIDs);
    end
    saveas(fig, fullfile(outputDir, '01_start_impedance_heatmap.png'));
    close(fig);
catch ME
    warning('Could not create impedance heatmap: %s', ME.message);
end

try
    plotTable = channelSummary;
    plotTable = sortrows(plotTable, 'MedianKOhm', 'descend');
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Position', [100 100 1500 700]);
    bar(plotTable.MedianKOhm);
    hold on;
    yline(cutoff, '--', 'Analytical cutoff');
    hold off;
    ylabel('Median final impedance (kOhm)');
    xlabel('Channel');
    title('Channel-wise median impedance, sorted descending');
    set(gca, 'XTick', 1:height(plotTable), ...
        'XTickLabel', plotTable.ChannelLabel, 'XTickLabelRotation', 90);
    saveas(fig, fullfile(outputDir, '02_channel_median_impedance.png'));
    close(fig);
catch ME
    warning('Could not create channel summary figure: %s', ME.message);
end

try
    multi = snapshotSummary;
    allIDs = unique(multi.ParticipantID, 'stable');
    nPerID = zeros(numel(allIDs), 1);
    for iID = 1:numel(allIDs)
        nPerID(iID) = sum(multi.ParticipantID == allIDs(iID));
    end
    multiIDs = allIDs(nPerID > 1);
    multi = multi(ismember(multi.ParticipantID, multiIDs), :);
    if ~isempty(multi)
        fig = figure('Visible', 'off', 'Color', 'w', ...
            'Position', [100 100 1300 700]);
        hold on;
        ids = unique(multi.ParticipantID, 'stable');
        for i = 1:numel(ids)
            rows = multi.ParticipantID == ids(i);
            plot(multi.SnapshotIndex(rows), multi.MeanKOhm(rows), '-o');
        end
        hold off;
        xlabel('Retained impedance-check index');
        ylabel('Mean impedance across included channels (kOhm)');
        title('Impedance changes where multiple checks were retained');
        grid on;
        saveas(fig, fullfile(outputDir, '03_impedance_snapshot_dynamics.png'));
        close(fig);
    end
catch ME
    warning('Could not create snapshot dynamics figure: %s', ME.message);
end
end

function q = percentileFinite(x, p)
x = sort(x(isfinite(x)));
if isempty(x)
    q = NaN;
    return;
end
if numel(x) == 1
    q = x;
    return;
end
p = min(max(p, 0), 100);
pos = 1 + (numel(x)-1) * p/100;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    q = x(lo);
else
    q = x(lo) + (pos-lo) * (x(hi)-x(lo));
end
end

function m = meanFinite(x)
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = mean(x);
end
end

function x = replaceNaN(x, replacement)
x(isnan(x)) = replacement;
end

function s = emptyParticipantStruct()
s = struct('ParticipantID', {}, 'DyadID', {}, 'Cap', {}, ...
    'AcquisitionNumber', {}, 'AcquisitionFile', {}, ...
    'AcquisitionFullPath', {}, 'Labels', {}, 'SnapshotsKOhm', {}, ...
    'Times', {}, 'RecordingStartTime', {}, ...
    'FinalSnapshotIndex', {}, 'NSnapshots', {});
end

function s = emptyLogStruct()
s = struct('AcquisitionNumber', {}, 'DyadID', {}, 'AcquisitionFile', {}, ...
    'AcquisitionFullPath', {}, 'HeaderFile', {}, 'NChannelsOriginal', {}, ...
    'NSnapshots', {}, 'NChannelsAIncluded', {}, 'NChannelsBIncluded', {}, ...
    'UnitDetected', {}, 'HeaderThresholdKOhm', {}, ...
    'RecordingStartTime', {}, 'SplitMethod', {}, ...
    'Status', {}, 'Message', {});
end

function row = initialiseLogRow(fileInfo, dyadID)
row = struct();
row.AcquisitionNumber = fileInfo.acquisitionNumber;
row.DyadID = string(dyadID);
row.AcquisitionFile = string(fileInfo.name);
row.AcquisitionFullPath = string(fileInfo.fullpath);
row.HeaderFile = "";
row.NChannelsOriginal = NaN;
row.NSnapshots = NaN;
row.NChannelsAIncluded = NaN;
row.NChannelsBIncluded = NaN;
row.UnitDetected = "";
row.HeaderThresholdKOhm = NaN;
row.RecordingStartTime = NaT;
row.SplitMethod = "";
row.Status = "NOT_RUN";
row.Message = "";
end
