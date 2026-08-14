function [eventTable, epochData, epochQCTable, dyadSummary, excludedEventTable] = ...
    step_video2_epoch_headmotion_HyperYESNO(varargin)
% STEP_VIDEO2_EPOCH_HEADMOTION_HYPERYESNO
%
% Event-lock the continuous A/B head-motion signals around spoken YES and NO
% responses for the HyperYESNO video analysis.
%
% This is the second stage of the video-analysis pipeline. It intentionally
% focuses on the conservative primary behavioural question:
%
%       Does interpersonal head-motion alignment differ around
%       YES versus NO responses?
%
% The function DOES NOT use Knower/Guesser role in the primary analysis.
% The response speaker (A/B) is retained as descriptive/QC information only.
%
% -------------------------------------------------------------------------
% EVENT DEFINITION
% -------------------------------------------------------------------------
%
% A transcription row is considered a candidate YES/NO response when:
%
%   1) role == "R"
%   2) n_words == 1
%   3) text, after conservative normalization, is exactly "yes" or "no"
%
% IMPORTANT:
%   is_yn is NOT used as an inclusion criterion.
%
% The is_yn value is preserved in the event/QC tables so that discrepancies
% between the transcription metadata and the actual utterance text remain
% auditable.
%
% Examples retained after normalization:
%   "Yes."   "YES!"   "yes,"   "No."   "NO!"
%
% Examples rejected:
%   "Yeah."
%   "Yes, exactly."
%   "I think yes."
%   "No, no."
%
% -------------------------------------------------------------------------
% AUTOMATIC REMOVAL OF CLOSE / DUPLICATED EVENTS
% -------------------------------------------------------------------------
%
% Speech-to-text segmentation occasionally produces implausibly close
% repeated YES/NO response events. Following the analysis decision for this
% project, any candidate YES/NO event having another candidate event less
% than 1.0 s away is excluded automatically.
%
% The default is:
%
%   CloseEventThresholdSec = 1
%
% The comparison uses response onset times within the same dyad.
%
% IMPORTANT:
%   If two or more events form a <1-s cluster, ALL events belonging to that
%   cluster are excluded. Excluded events are saved in excludedEventTable
%   and are therefore not lost from the QC record.
%
% -------------------------------------------------------------------------
% HEAD-MOTION EPOCHING
% -------------------------------------------------------------------------
%
% For each retained YES/NO response, the function extracts the "unitary"
% head-motion signal from both participants:
%
%       M_A(t)
%       M_B(t)
%
% around the response onset.
%
% Default epoch:
%
%       -2 s to +2 s
%
% Default common output sampling rate:
%
%       30 Hz
%
% The original "time_sec" column is always used as the time reference.
% The function does NOT assume that CSV row numbers are temporally aligned
% with an event onset.
%
% Each epoch is evaluated on a common relative-time grid using interp1.
% Missing unitary values are deliberately retained as NaN; they are not
% removed before interpolation, because removing them could spuriously bridge
% periods in which head tracking failed.
%
% -------------------------------------------------------------------------
% EVENT-LEVEL MOTION QC
% -------------------------------------------------------------------------
%
% For every retained event, the function calculates:
%
%   - full temporal coverage for A and B
%   - percentage of finite samples for A
%   - percentage of finite samples for B
%   - percentage of samples finite in BOTH A and B
%   - longest missing-data run for A
%   - longest missing-data run for B
%   - longest paired-missing run
%   - nearest other candidate response in seconds
%   - original is_yn transcription flag
%
% An epoch is flagged ValidEpoch when:
%
%   - both recordings cover the full requested time interval, AND
%   - paired finite A/B samples >= MinPairedValidPct
%
% Default:
%
%       MinPairedValidPct = 90
%
% Invalid epochs are NOT deleted here. They remain in the epoch matrices and
% QC table with ValidEpoch == false. This makes later exclusions explicit and
% auditable.
%
% -------------------------------------------------------------------------
% EXPECTED DIRECTORY STRUCTURE
% -------------------------------------------------------------------------
%
% Motion:
%
%   E:\HyperYESNO_videosCUT\
%       Dyad01\
%           Dyad01-A_cut\
%               Dyad01-A_motion.csv
%           Dyad01-B_cut\
%               Dyad01-B_motion.csv
%
% Transcription:
%
%   E:\VIDEOS_Alej\
%       Dyad01\
%           diarization\
%               ...*utterances.csv
%
% The exact expected transcription filename is tried first. If it is not
% found, the function searches recursively below the dyad's diarization
% directory and prefers a filename containing "diarized_v11".
%
% -------------------------------------------------------------------------
% OUTPUTS
% -------------------------------------------------------------------------
%
% eventTable
%   One row per retained YES/NO event after automatic <1-s close-event
%   exclusion. Contains condition, onset, speaker and transcription QC.
%
% epochData
%   Structure containing the actual event-locked head-motion matrices:
%
%       epochData.relativeTimeSec
%       epochData.targetFs
%       epochData.epochWindowSec
%       epochData.A                 [events x time]
%       epochData.B                 [events x time]
%       epochData.pairedValid       [events x time logical]
%       epochData.condition         [events x 1 string]
%       epochData.dyad              [events x 1 string]
%       epochData.speaker           [events x 1 string]
%       epochData.onsetSec          [events x 1 double]
%       epochData.validEpoch        [events x 1 logical]
%
% epochQCTable
%   One row per retained event with event-level motion QC.
%
% dyadSummary
%   One row per dyad with candidate/exclusion counts and valid epoch counts.
%
% excludedEventTable
%   YES/NO candidates removed because another candidate response occurred
%   less than CloseEventThresholdSec away.
%
% -------------------------------------------------------------------------
% FILES SAVED BY DEFAULT
% -------------------------------------------------------------------------
%
%   E:\HyperYESNO\_videosCUT\_video_analysis\
%
%       HyperYESNO_video_stage2_events_retained.csv
%       HyperYESNO_video_stage2_events_excluded_close.csv
%       HyperYESNO_video_stage2_epoch_QC.csv
%       HyperYESNO_video_stage2_dyad_summary.csv
%       HyperYESNO_video_stage2_epochs.mat
%       HyperYESNO_video_stage2_valid_epochs_by_dyad.png
%
% -------------------------------------------------------------------------
% EXAMPLE
% -------------------------------------------------------------------------
%
% [events, epochs, epochQC, dyads, excluded] = ...
%     step_video2_epoch_headmotion_HyperYESNO;
%
% Custom settings:
%
% [events, epochs, epochQC, dyads, excluded] = ...
%     step_video2_epoch_headmotion_HyperYESNO( ...
%       'EpochWindowSec', [-2 2], ...
%       'TargetFs', 30, ...
%       'CloseEventThresholdSec', 1, ...
%       'MinPairedValidPct', 90);
%
% -------------------------------------------------------------------------
% HyperYESNO project
% -------------------------------------------------------------------------


%% ========================================================================
%  Parse inputs
% =========================================================================

p = inputParser;

addParameter(p, 'MotionRoot', ...
    'E:\HyperYESNO_videosCUT', ...
    @(x) ischar(x) || isstring(x));

addParameter(p, 'TranscriptRoot', ...
    'E:\VIDEOS_Alej', ...
    @(x) ischar(x) || isstring(x));

addParameter(p, 'Dyads', 1:35, ...
    @(x) isnumeric(x) && isvector(x));

addParameter(p, 'EpochWindowSec', [-2 2], ...
    @(x) isnumeric(x) && numel(x) == 2 && x(1) < x(2));

addParameter(p, 'TargetFs', 30, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(p, 'CloseEventThresholdSec', 1, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);

addParameter(p, 'MinPairedValidPct', 90, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 100);

addParameter(p, 'SaveOutputs', true, ...
    @(x) islogical(x) || isnumeric(x));

addParameter(p, 'MakeQCFigure', true, ...
    @(x) islogical(x) || isnumeric(x));

addParameter(p, 'OutputDir', '', ...
    @(x) ischar(x) || isstring(x));

parse(p, varargin{:});

motionRoot      = char(p.Results.MotionRoot);
transcriptRoot  = char(p.Results.TranscriptRoot);
dyads           = p.Results.Dyads(:)';
epochWindowSec  = double(p.Results.EpochWindowSec(:)');
targetFs        = double(p.Results.TargetFs);
closeThreshold  = double(p.Results.CloseEventThresholdSec);
minPairedPct    = double(p.Results.MinPairedValidPct);
saveOutputs     = logical(p.Results.SaveOutputs);
makeQCFigure    = logical(p.Results.MakeQCFigure);
outputDir       = char(p.Results.OutputDir);

if isempty(outputDir)
    outputDir = fullfile(motionRoot, '_video_analysis');
end

if (saveOutputs || makeQCFigure) && ~isfolder(outputDir)
    mkdir(outputDir);
end

% Fixed relative-time grid. Using an integer sample index avoids accumulated
% floating-point error from repeated colon operations.
firstSample = round(epochWindowSec(1) * targetFs);
lastSample  = round(epochWindowSec(2) * targetFs);
relativeTimeSec = (firstSample:lastSample) / targetFs;

nEpochSamples = numel(relativeTimeSec);

fprintf('\n============================================================\n');
fprintf('HyperYESNO video Step 2: YES/NO head-motion epoching\n');
fprintf('============================================================\n');
fprintf('Epoch window: %.3f to %.3f s\n', ...
    relativeTimeSec(1), relativeTimeSec(end));
fprintf('Target sampling rate: %.3f Hz\n', targetFs);
fprintf('Samples per epoch: %d\n', nEpochSamples);
fprintf('Close-event exclusion: < %.3f s\n', closeThreshold);
fprintf('Minimum paired-valid samples: %.1f%%\n\n', minPairedPct);


%% ========================================================================
%  Containers
% =========================================================================

retainedRows = struct([]);
excludedRows = struct([]);
qcRows       = struct([]);
summaryRows  = struct([]);

allEpochA = [];
allEpochB = [];

allDyad       = strings(0,1);
allCondition  = strings(0,1);
allSpeaker    = strings(0,1);
allOnset      = zeros(0,1);
allValidEpoch = false(0,1);


%% ========================================================================
%  Process dyads
% =========================================================================

for d = dyads

    dyadStr = sprintf('Dyad%02d', d);

    fprintf('%s\n', dyadStr);

    %% --------------------------------------------------------------------
    % 1. Read transcription and identify corrected YES/NO candidates
    % ---------------------------------------------------------------------

    transcriptFile = findTranscriptFile(transcriptRoot, dyadStr);

    if isempty(transcriptFile)
        warning('%s: transcription file not found.', dyadStr);

        s = createEmptySummaryRow(dyadStr);
        s.TranscriptFound = false;
        summaryRows = appendStruct(summaryRows, s);

        fprintf('  Transcript missing. Dyad skipped.\n\n');
        continue;
    end

    try
        U = readtable(transcriptFile, ...
            'TextType', 'string', ...
            'VariableNamingRule', 'preserve');

        requiredVars = { ...
            'utt_id', 'start_time', 'end_time', ...
            'role', 'speaker', 'is_yn', 'n_words', 'text'};

        assertRequiredVariables(U, requiredVars, transcriptFile);

        uttID     = getStringColumn(U, 'utt_id');
        startTime = getNumericColumn(U, 'start_time');
        endTime   = getNumericColumn(U, 'end_time');
        role      = upper(strtrim(getStringColumn(U, 'role')));
        speaker   = upper(strtrim(getStringColumn(U, 'speaker')));
        isYN      = getNumericColumn(U, 'is_yn');
        nWords    = getNumericColumn(U, 'n_words');
        rawText   = getStringColumn(U, 'text');

        normText = normalizeYesNoText(rawText);

        isYes = normText == "yes";
        isNo  = normText == "no";

        % Corrected inclusion criterion:
        %   role R + one word + normalized text exactly yes/no.
        % is_yn is deliberately NOT part of this criterion.
        candidateMask = ...
            role == "R" & ...
            nWords == 1 & ...
            (isYes | isNo) & ...
            isfinite(startTime);

        candidateIdx = find(candidateMask);

        % Explicitly sort candidates by response onset. This guarantees that
        % eventTable, epochQCTable and the rows of epochData.A/B retain the
        % same one-to-one chronological ordering even if a transcription CSV
        % is not itself perfectly ordered.
        if ~isempty(candidateIdx)
            [~, candidateOrder] = sort(startTime(candidateIdx));
            candidateIdx = candidateIdx(candidateOrder);
        end

    catch ME
        warning('%s: transcription could not be processed.\n%s', ...
            dyadStr, ME.message);

        s = createEmptySummaryRow(dyadStr);
        s.TranscriptFound = true;
        s.TranscriptReadSuccessful = false;
        summaryRows = appendStruct(summaryRows, s);

        fprintf('  Transcript read failed. Dyad skipped.\n\n');
        continue;
    end

    nCandidates = numel(candidateIdx);

    if nCandidates == 0
        warning('%s: no YES/NO candidates met the corrected criterion.', ...
            dyadStr);

        s = createEmptySummaryRow(dyadStr);
        s.TranscriptFound = true;
        s.TranscriptReadSuccessful = true;
        s.NCandidatesBeforeCloseExclusion = 0;
        summaryRows = appendStruct(summaryRows, s);

        fprintf('  No candidate events.\n\n');
        continue;
    end

    candidateOnsets = startTime(candidateIdx);

    % Calculate nearest other candidate onset and determine which candidate
    % events belong to a <threshold cluster.
    [nearestOtherSec, closeMask] = identifyCloseEvents( ...
        candidateOnsets, closeThreshold);

    retainedCandidateIdx = candidateIdx(~closeMask);
    excludedCandidateIdx = candidateIdx(closeMask);

    retainedNearest = nearestOtherSec(~closeMask);
    excludedNearest = nearestOtherSec(closeMask);

    % Save excluded close events for auditability.
    for ii = 1:numel(excludedCandidateIdx)

        k = excludedCandidateIdx(ii);

        r = createTranscriptEventRow( ...
            dyadStr, ...
            uttID(k), ...
            startTime(k), ...
            endTime(k), ...
            speaker(k), ...
            isYN(k), ...
            nWords(k), ...
            rawText(k), ...
            normText(k), ...
            transcriptFile);

        if normText(k) == "yes"
            r.Condition = "YES";
        else
            r.Condition = "NO";
        end

        r.NearestOtherResponseSec = excludedNearest(ii);
        r.CloseEventExcluded = true;

        excludedRows = appendStruct(excludedRows, r);
    end


    %% --------------------------------------------------------------------
    % 2. Read A/B motion signals
    % ---------------------------------------------------------------------

    [motionA, okA, errA] = readMotionSignal( ...
        motionRoot, dyadStr, "A");

    [motionB, okB, errB] = readMotionSignal( ...
        motionRoot, dyadStr, "B");

    if ~okA
        warning('%s-A motion could not be read: %s', dyadStr, errA);
    end

    if ~okB
        warning('%s-B motion could not be read: %s', dyadStr, errB);
    end


    %% --------------------------------------------------------------------
    % 3. Extract event-locked A/B epochs
    % ---------------------------------------------------------------------

    nRetained = numel(retainedCandidateIdx);

    dyadEpochA = NaN(nRetained, nEpochSamples);
    dyadEpochB = NaN(nRetained, nEpochSamples);

    dyadValid = false(nRetained,1);
    dyadCondition = strings(nRetained,1);

    nYESRetained = 0;
    nNORetained  = 0;
    nYESValid    = 0;
    nNOValid     = 0;

    for ii = 1:nRetained

        k = retainedCandidateIdx(ii);

        onsetSec = startTime(k);
        queryTime = onsetSec + relativeTimeSec;

        if normText(k) == "yes"
            condition = "YES";
            nYESRetained = nYESRetained + 1;
        else
            condition = "NO";
            nNORetained = nNORetained + 1;
        end

        % -------------------------------------------------------------
        % Interpolate using the original time_sec clock.
        %
        % IMPORTANT: readMotionSignal retains NaN unitary values, so
        % missing tracking periods are not silently bridged.
        % -------------------------------------------------------------
        if okA
            epochA = interpolateMotionKeepingMissing( ...
                motionA.timeSec, motionA.unitary, queryTime);
        else
            epochA = NaN(1, nEpochSamples);
        end

        if okB
            epochB = interpolateMotionKeepingMissing( ...
                motionB.timeSec, motionB.unitary, queryTime);
        else
            epochB = NaN(1, nEpochSamples);
        end

        dyadEpochA(ii,:) = epochA;
        dyadEpochB(ii,:) = epochB;

        validA = isfinite(epochA);
        validB = isfinite(epochB);
        pairedValid = validA & validB;

        validPctA = 100 * mean(validA);
        validPctB = 100 * mean(validB);
        pairedValidPct = 100 * mean(pairedValid);

        if okA
            fullCoverageA = ...
                queryTime(1) >= motionA.startSec - 1e-6 && ...
                queryTime(end) <= motionA.endSec + 1e-6;
        else
            fullCoverageA = false;
        end

        if okB
            fullCoverageB = ...
                queryTime(1) >= motionB.startSec - 1e-6 && ...
                queryTime(end) <= motionB.endSec + 1e-6;
        else
            fullCoverageB = false;
        end

        longestMissingA = longestFalseRunSec(validA, targetFs);
        longestMissingB = longestFalseRunSec(validB, targetFs);
        longestPairedMissing = longestFalseRunSec(pairedValid, targetFs);

        validEpoch = ...
            fullCoverageA && ...
            fullCoverageB && ...
            pairedValidPct >= minPairedPct;

        dyadValid(ii) = validEpoch;
        dyadCondition(ii) = condition;

        if validEpoch
            if condition == "YES"
                nYESValid = nYESValid + 1;
            else
                nNOValid = nNOValid + 1;
            end
        end

        % -------------------------------------------------------------
        % Retained event table row
        % -------------------------------------------------------------
        r = createTranscriptEventRow( ...
            dyadStr, ...
            uttID(k), ...
            startTime(k), ...
            endTime(k), ...
            speaker(k), ...
            isYN(k), ...
            nWords(k), ...
            rawText(k), ...
            normText(k), ...
            transcriptFile);

        r.Condition = condition;
        r.NearestOtherResponseSec = retainedNearest(ii);
        r.CloseEventExcluded = false;

        retainedRows = appendStruct(retainedRows, r);

        % -------------------------------------------------------------
        % Event-level epoch QC row
        % -------------------------------------------------------------
        q = struct;

        q.Dyad                   = string(dyadStr);
        q.UttID                  = uttID(k);
        q.Condition              = condition;
        q.OnsetSec               = onsetSec;
        q.Speaker                = speaker(k);
        q.IsYN_QC                = isYN(k);

        q.FullCoverageA          = logical(fullCoverageA);
        q.FullCoverageB          = logical(fullCoverageB);

        q.ValidPctA              = validPctA;
        q.ValidPctB              = validPctB;
        q.PairedValidPct         = pairedValidPct;

        q.LongestMissingRunASec  = longestMissingA;
        q.LongestMissingRunBSec  = longestMissingB;
        q.LongestPairedMissingRunSec = longestPairedMissing;

        q.NearestOtherResponseSec = retainedNearest(ii);

        q.ValidEpoch             = logical(validEpoch);

        qcRows = appendStruct(qcRows, q);
    end


    %% --------------------------------------------------------------------
    % 4. Append this dyad's matrices to global epochData containers
    % ---------------------------------------------------------------------

    if nRetained > 0

        firstGlobalIndex = size(allEpochA, 1) + 1;
        lastGlobalIndex  = firstGlobalIndex + nRetained - 1;

        allEpochA = [allEpochA; dyadEpochA]; %#ok<AGROW>
        allEpochB = [allEpochB; dyadEpochB]; %#ok<AGROW>

        allDyad(firstGlobalIndex:lastGlobalIndex,1) = string(dyadStr);
        allCondition(firstGlobalIndex:lastGlobalIndex,1) = dyadCondition;
        allSpeaker(firstGlobalIndex:lastGlobalIndex,1) = ...
            speaker(retainedCandidateIdx);
        allOnset(firstGlobalIndex:lastGlobalIndex,1) = ...
            startTime(retainedCandidateIdx);
        allValidEpoch(firstGlobalIndex:lastGlobalIndex,1) = dyadValid;
    end


    %% --------------------------------------------------------------------
    % 5. Dyad summary
    % ---------------------------------------------------------------------

    s = createEmptySummaryRow(dyadStr);

    s.TranscriptFound = true;
    s.TranscriptReadSuccessful = true;
    s.MotionAReadSuccessful = okA;
    s.MotionBReadSuccessful = okB;

    s.NCandidatesBeforeCloseExclusion = nCandidates;
    s.NExcludedCloseEvents = sum(closeMask);
    s.NRetainedEvents = nRetained;

    s.NYESRetained = nYESRetained;
    s.NNORetained  = nNORetained;

    s.NValidEpochs = sum(dyadValid);
    s.NInvalidEpochs = sum(~dyadValid);
    s.NYESValid = nYESValid;
    s.NNOValid  = nNOValid;

    if nRetained > 0
        s.ValidEpochPct = 100 * mean(dyadValid);
    end

    if nYESRetained > 0
        s.YESValidPct = 100 * nYESValid / nYESRetained;
    end

    if nNORetained > 0
        s.NOValidPct = 100 * nNOValid / nNORetained;
    end

    if okA
        s.MotionAEstimatedFsHz = motionA.estimatedFsHz;
    end

    if okB
        s.MotionBEstimatedFsHz = motionB.estimatedFsHz;
    end

    summaryRows = appendStruct(summaryRows, s);

    fprintf('  Candidates: %d | removed (<%.1f s): %d | retained: %d\n', ...
        nCandidates, closeThreshold, sum(closeMask), nRetained);

    fprintf('  Retained YES: %d | NO: %d\n', ...
        nYESRetained, nNORetained);

    fprintf('  Valid epochs: %d/%d (%.1f%%)\n', ...
        sum(dyadValid), nRetained, safePercent(sum(dyadValid), nRetained));

    fprintf('\n');

end


%% ========================================================================
%  Convert structures to tables
% =========================================================================

if isempty(retainedRows)
    eventTable = table;
else
    eventTable = struct2table(retainedRows);
    eventTable = sortrows(eventTable, {'Dyad','OnsetSec'});
end

if isempty(excludedRows)
    excludedEventTable = table;
else
    excludedEventTable = struct2table(excludedRows);
    excludedEventTable = sortrows(excludedEventTable, {'Dyad','OnsetSec'});
end

if isempty(qcRows)
    epochQCTable = table;
else
    epochQCTable = struct2table(qcRows);
    epochQCTable = sortrows(epochQCTable, {'Dyad','OnsetSec'});
end

if isempty(summaryRows)
    dyadSummary = table;
else
    dyadSummary = struct2table(summaryRows);
    dyadSummary = sortrows(dyadSummary, 'Dyad');
end


%% ========================================================================
%  Build epochData structure
% =========================================================================

epochData = struct;

epochData.relativeTimeSec = relativeTimeSec;
epochData.targetFs = targetFs;
epochData.epochWindowSec = [relativeTimeSec(1), relativeTimeSec(end)];

epochData.A = allEpochA;
epochData.B = allEpochB;

epochData.pairedValid = isfinite(allEpochA) & isfinite(allEpochB);

epochData.dyad = allDyad;
epochData.condition = allCondition;
epochData.speaker = allSpeaker;
epochData.onsetSec = allOnset;
epochData.validEpoch = allValidEpoch;

epochData.closeEventThresholdSec = closeThreshold;
epochData.minPairedValidPct = minPairedPct;

% Convenience masks for later analysis.
epochData.YES = allCondition == "YES";
epochData.NO  = allCondition == "NO";

epochData.analysisMaskYES = ...
    epochData.YES & epochData.validEpoch;

epochData.analysisMaskNO = ...
    epochData.NO & epochData.validEpoch;


%% ========================================================================
%  Save outputs
% =========================================================================

if saveOutputs

    retainedCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage2_events_retained.csv');

    excludedCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage2_events_excluded_close.csv');

    qcCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage2_epoch_QC.csv');

    summaryCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage2_dyad_summary.csv');

    matFile = fullfile(outputDir, ...
        'HyperYESNO_video_stage2_epochs.mat');

    writetable(eventTable, retainedCSV);
    writetable(excludedEventTable, excludedCSV);
    writetable(epochQCTable, qcCSV);
    writetable(dyadSummary, summaryCSV);

    save(matFile, ...
        'eventTable', ...
        'excludedEventTable', ...
        'epochQCTable', ...
        'dyadSummary', ...
        'epochData', ...
        'motionRoot', ...
        'transcriptRoot', ...
        'dyads', ...
        'epochWindowSec', ...
        'targetFs', ...
        'closeThreshold', ...
        'minPairedPct', ...
        '-v7.3');
end


%% ========================================================================
%  QC figure: valid YES/NO epochs by dyad
% =========================================================================

if makeQCFigure && ~isempty(dyadSummary)

    try
        f = figure( ...
            'Name', 'HyperYESNO Stage 2 - valid epochs by dyad', ...
            'Color', 'w');

        y = [dyadSummary.YESValidPct, dyadSummary.NOValidPct];

        bar(y, 'grouped');

        xlabel('Dyad');
        ylabel('Valid epochs (%)');
        ylim([0 105]);

        xticks(1:height(dyadSummary));
        xticklabels(dyadSummary.Dyad);
        xtickangle(90);

        legend({'YES','NO'}, 'Location', 'bestoutside');

        title(sprintf( ...
            'Usable event-locked head-motion epochs (paired valid >= %.0f%%)', ...
            minPairedPct));

        grid on;

        figFile = fullfile(outputDir, ...
            'HyperYESNO_video_stage2_valid_epochs_by_dyad.png');

        try
            exportgraphics(f, figFile, 'Resolution', 200);
        catch
            saveas(f, figFile);
        end

    catch ME
        warning('Could not create/save Stage 2 QC figure: %s', ME.message);
    end
end


%% ========================================================================
%  Final console summary
% =========================================================================

fprintf('============================================================\n');
fprintf('Stage 2 complete\n');
fprintf('============================================================\n');

fprintf('Retained YES/NO events: %d\n', height(eventTable));
fprintf('Close/duplicate events removed: %d\n', ...
    height(excludedEventTable));

if ~isempty(eventTable)
    fprintf('  YES retained: %d\n', ...
        sum(eventTable.Condition == "YES"));
    fprintf('  NO retained : %d\n', ...
        sum(eventTable.Condition == "NO"));
end

if ~isempty(epochQCTable)
    fprintf('Valid A/B motion epochs: %d/%d (%.1f%%)\n', ...
        sum(epochQCTable.ValidEpoch), ...
        height(epochQCTable), ...
        100 * mean(epochQCTable.ValidEpoch));

    fprintf('  Valid YES: %d\n', ...
        sum(epochQCTable.ValidEpoch & epochQCTable.Condition == "YES"));

    fprintf('  Valid NO : %d\n', ...
        sum(epochQCTable.ValidEpoch & epochQCTable.Condition == "NO"));
end

if saveOutputs
    fprintf('\nSaved outputs to:\n%s\n', outputDir);
end

fprintf('============================================================\n\n');

end


%% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function transcriptFile = findTranscriptFile(transcriptRoot, dyadStr)
% FINDTRANSCRIPTFILE Locate one dyad's utterance CSV.
%
% The function first tries common expected filenames and then searches
% recursively under the dyad's diarization folder for *utterances.csv.

transcriptFile = '';

diarDir = fullfile(transcriptRoot, dyadStr, 'diarization');

if ~isfolder(diarDir)
    return;
end

expectedCandidates = { ...
    fullfile(diarDir, sprintf('%s_diarized_v11_utterances.csv', dyadStr)), ...
    fullfile(diarDir, sprintf('%s-_diarized_v11_utterances.csv', dyadStr)), ...
    fullfile(diarDir, sprintf('%s_diarized_v11_utterances.CSV', dyadStr))};

for i = 1:numel(expectedCandidates)
    if isfile(expectedCandidates{i})
        transcriptFile = expectedCandidates{i};
        return;
    end
end

files = dir(fullfile(diarDir, '**', '*utterances.csv'));

if isempty(files)
    files = dir(fullfile(diarDir, '**', '*utterances.CSV'));
end

if isempty(files)
    return;
end

names = lower(string({files.name}));
preferred = contains(names, 'diarized_v11');

if any(preferred)
    idx = find(preferred, 1, 'first');
else
    idx = 1;
end

transcriptFile = fullfile(files(idx).folder, files(idx).name);

if numel(files) > 1
    warning('%s: multiple utterance files found. Using:\n  %s', ...
        dyadStr, transcriptFile);
end

end


function [motion, ok, errMsg] = readMotionSignal(motionRoot, dyadStr, participant)
% READMOTIONSIGNAL Read time_sec and unitary for one participant.
%
% NaN values in unitary are deliberately retained.

motion = struct;
motion.timeSec = [];
motion.unitary = [];
motion.startSec = NaN;
motion.endSec = NaN;
motion.estimatedFsHz = NaN;
motion.file = "";

ok = false;
errMsg = "";

motionFile = fullfile( ...
    motionRoot, ...
    dyadStr, ...
    sprintf('%s-%s_cut', dyadStr, participant), ...
    sprintf('%s-%s_motion.csv', dyadStr, participant));

motion.file = string(motionFile);

if ~isfile(motionFile)
    errMsg = "File not found: " + string(motionFile);
    return;
end

try
    M = readtable(motionFile, ...
        'TextType', 'string', ...
        'VariableNamingRule', 'preserve');

    assertRequiredVariables(M, {'time_sec','unitary'}, motionFile);

    t = getNumericColumn(M, 'time_sec');
    y = getNumericColumn(M, 'unitary');

    % Remove rows where the time coordinate itself is invalid. Do NOT remove
    % rows merely because unitary is NaN.
    validT = isfinite(t);

    t = t(validT);
    y = y(validT);

    if numel(t) < 2
        errMsg = "Fewer than two finite time samples.";
        return;
    end

    % Ensure chronological ordering.
    [t, order] = sort(t);
    y = y(order);

    % Ensure unique time coordinates for interp1. In the unlikely case of
    % duplicate timestamps, preserve the first sample. This is preferable to
    % averaging because a duplicate is a timing/QC problem, not a signal
    % feature to smooth.
    [t, uniqueIdx] = unique(t, 'stable');
    y = y(uniqueIdx);

    if numel(t) < 2
        errMsg = "Fewer than two unique finite time samples.";
        return;
    end

    dt = diff(t);
    dtPositive = dt(isfinite(dt) & dt > 0);

    if isempty(dtPositive)
        errMsg = "Could not estimate a positive sampling interval.";
        return;
    end

    motion.timeSec = t(:);
    motion.unitary = y(:);
    motion.startSec = t(1);
    motion.endSec = t(end);
    motion.estimatedFsHz = 1 / median(dtPositive);

    ok = true;

catch ME
    errMsg = string(ME.message);
end

end


function epoch = interpolateMotionKeepingMissing(t, y, queryTime)
% INTERPOLATEMOTIONKEEPINGMISSING Interpolate without bridging missing runs.
%
% A standard interpolation after removing NaN signal values would connect
% the samples on either side of a tracking failure, creating artificial
% motion estimates. To prevent that, interpolation is performed separately
% within contiguous runs of finite y values.
%
% Query points outside the original recording or inside missing runs remain
% NaN.

epoch = NaN(size(queryTime));

finiteY = isfinite(y) & isfinite(t);

if ~any(finiteY)
    return;
end

% Find contiguous finite runs in the ORIGINAL signal indexing.
d = diff([false; finiteY(:); false]);

runStart = find(d == 1);
runEnd   = find(d == -1) - 1;

for r = 1:numel(runStart)

    idx = runStart(r):runEnd(r);

    tr = t(idx);
    yr = y(idx);

    if numel(idx) >= 2

        inRun = ...
            queryTime >= tr(1) & ...
            queryTime <= tr(end);

        if any(inRun)
            epoch(inRun) = interp1( ...
                tr, yr, queryTime(inRun), 'linear', NaN);
        end

    elseif numel(idx) == 1

        % A single isolated valid frame cannot support interpolation. Leave
        % the corresponding output as NaN rather than introducing an
        % arbitrary sampling-rate assumption.
        continue;
    end
end

end


function [nearestOtherSec, closeMask] = identifyCloseEvents(onsets, threshold)
% IDENTIFYCLOSEEVENTS Find candidates with another response < threshold away.
%
% All members of a close-event cluster are marked for removal.

onsets = onsets(:);
n = numel(onsets);

nearestOtherSec = NaN(n,1);
closeMask = false(n,1);

if n <= 1
    return;
end

for i = 1:n

    delta = abs(onsets - onsets(i));
    delta(i) = Inf;

    nearestOtherSec(i) = min(delta);

    % User-defined rule: "closer than 1 sec" means strictly less than the
    % threshold, not <= threshold.
    closeMask(i) = nearestOtherSec(i) < threshold;
end

end


function seconds = longestFalseRunSec(validMask, fs)
% LONGESTFALSERUNSEC Duration of the longest consecutive invalid run.

validMask = logical(validMask(:));

if isempty(validMask) || all(validMask)
    seconds = 0;
    return;
end

invalid = ~validMask;

d = diff([false; invalid; false]);
runStart = find(d == 1);
runEnd   = find(d == -1) - 1;

runLengths = runEnd - runStart + 1;

seconds = max(runLengths) / fs;

end


function row = createTranscriptEventRow( ...
    dyadStr, uttID, onsetSec, endSec, speaker, isYN, nWords, ...
    rawText, normText, transcriptFile)
% CREATETRANSCRIPTEVENTROW Fixed event-row field order.

row = struct;

row.Dyad            = string(dyadStr);
row.UttID           = string(uttID);
row.Condition       = "";
row.OnsetSec        = onsetSec;
row.EndSec          = endSec;
row.DurationSec     = endSec - onsetSec;
row.Speaker         = string(speaker);

% is_yn is retained ONLY as QC information.
row.IsYN_QC         = isYN;

row.NWords          = nWords;
row.Text            = string(rawText);
row.NormalizedText  = string(normText);

row.NearestOtherResponseSec = NaN;
row.CloseEventExcluded = false;

row.TranscriptFile  = string(transcriptFile);

end


function s = createEmptySummaryRow(dyadStr)
% CREATEEMPTYSUMMARYROW Fixed dyad-summary field order.

s = struct;

s.Dyad = string(dyadStr);

s.TranscriptFound = false;
s.TranscriptReadSuccessful = false;
s.MotionAReadSuccessful = false;
s.MotionBReadSuccessful = false;

s.NCandidatesBeforeCloseExclusion = NaN;
s.NExcludedCloseEvents = NaN;
s.NRetainedEvents = NaN;

s.NYESRetained = NaN;
s.NNORetained = NaN;

s.NValidEpochs = NaN;
s.NInvalidEpochs = NaN;
s.ValidEpochPct = NaN;

s.NYESValid = NaN;
s.NNOValid = NaN;
s.YESValidPct = NaN;
s.NOValidPct = NaN;

s.MotionAEstimatedFsHz = NaN;
s.MotionBEstimatedFsHz = NaN;

end


function assertRequiredVariables(T, requiredVars, sourceFile)
% ASSERTREQUIREDVARIABLES Confirm that expected table columns exist.

vars = string(T.Properties.VariableNames);

for i = 1:numel(requiredVars)

    if ~any(strcmpi(vars, requiredVars{i}))
        error('Required column "%s" not found in:\n%s', ...
            requiredVars{i}, sourceFile);
    end
end

end


function x = getStringColumn(T, varName)
% GETSTRINGCOLUMN Retrieve a table column by case-insensitive name.

idx = find(strcmpi(T.Properties.VariableNames, varName), 1, 'first');

if isempty(idx)
    error('Column "%s" not found.', varName);
end

x = string(T{:,idx});
x = x(:);

end


function x = getNumericColumn(T, varName)
% GETNUMERICCOLUMN Retrieve a table column and robustly convert to double.

idx = find(strcmpi(T.Properties.VariableNames, varName), 1, 'first');

if isempty(idx)
    error('Column "%s" not found.', varName);
end

raw = T{:,idx};

if isnumeric(raw) || islogical(raw)
    x = double(raw);
else
    x = str2double(string(raw));
end

x = x(:);

end


function normText = normalizeYesNoText(rawText)
% NORMALIZEYESNOTEXT Conservative normalization for standalone YES/NO.
%
% Only punctuation/quotes/brackets at the EDGES of the utterance are
% removed. Internal words are left untouched.

normText = lower(strtrim(string(rawText)));

normText = regexprep(normText, ...
    '^[\s"''“”‘’\(\)\[\]\{\}\.,!\?;:]+', '');

normText = regexprep(normText, ...
    '[\s"''“”‘’\(\)\[\]\{\}\.,!\?;:]+$', '');

normText = strtrim(normText);

end


function rows = appendStruct(rows, newRow)
% APPENDSTRUCT Append a scalar structure to a structure array.

if isempty(rows)
    rows = newRow;
else
    rows(end+1) = newRow; %#ok<AGROW>
end

end


function pct = safePercent(numerator, denominator)
% SAFEPERCENT Avoid divide-by-zero in console output.

if denominator > 0
    pct = 100 * numerator / denominator;
else
    pct = NaN;
end

end
