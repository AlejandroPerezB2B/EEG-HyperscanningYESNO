function [eventTable, motionQCTable, dyadSummary, candidateTable] = step_video1_extract_events_motionQC_HyperYESNO(varargin)
% STEP_VIDEO1_EXTRACT_EVENTS_MOTIONQC_HYPERYESNO
%
% First-stage video-analysis function for the HyperYESNO project.
%
% The function performs two deliberately separate operations:
%
%   1) Extracts high-confidence YES/NO response events from the diarized
%      speech-to-text CSV files.
%
%   2) Performs basic quality control (QC) on the continuous head-motion
%      time series for participants A and B.
%
% No interpersonal synchrony, cross-correlation, GCMI, or event-related
% head-motion analysis is performed here. The purpose of this function is
% to create clean inputs for those later analyses.
%
% -------------------------------------------------------------------------
% EXPECTED DIRECTORY STRUCTURE
% -------------------------------------------------------------------------
%
% Motion data:
%
%   E:\HyperYESNO_videosCUT\
%       Dyad01\
%           Dyad01-A_cut\
%               Dyad01-A_motion.csv
%           Dyad01-B_cut\
%               Dyad01-B_motion.csv
%       ...
%       Dyad35\
%
% Transcriptions:
%
%   E:\VIDEOS_Alej\
%       Dyad01\
%           diarization\
%               Dyad01_diarized_v11_utterances.csv
%
% If the exact expected transcription filename is not found, the function
% searches recursively under the dyad's "diarization" folder for files
% matching *utterances.csv. If more than one is found, a file containing
% "diarized_v11" is preferred.
%
% -------------------------------------------------------------------------
% YES/NO EVENT DEFINITION
% -------------------------------------------------------------------------
%
% An utterance is retained as a strict YES/NO event only when:
%
%   role    == "R"
%   is_yn   == 1
%   n_words == 1
%   text, after conservative normalization, is exactly "yes" or "no"
%
% Text normalization:
%   - trims leading/trailing whitespace
%   - converts to lowercase
%   - removes terminal punctuation such as . ! ? , ; :
%
% Examples retained:
%   "Yes."   "yes"   "YES!"   "No."
%
% Examples not retained:
%   "Yeah."
%   "Yes, exactly."
%   "I think yes."
%   "No, no."
%
% Importantly, every exact one-word textual YES/NO candidate is also written
% to candidateTable, together with the metadata checks that determine whether
% it passes the strict event definition. This makes exclusions auditable.
%
% -------------------------------------------------------------------------
% QUESTION / RESPONSE ROLE VALIDATION
% -------------------------------------------------------------------------
%
% For each strict YES/NO response, the function searches backward for the
% most recent preceding utterance labelled role == "Q".
%
% The role assignment is treated as valid when:
%   - the response speaker is A or B;
%   - a preceding Q utterance is found;
%   - the question speaker is A or B;
%   - question and response speakers are different;
%   - the question-response temporal gap is not larger than the user-defined
%     MaxQuestionResponseGapSec.
%
% If valid:
%   Responder  = Knower
%   Questioner = Guesser
%
% This assignment is stored for later use, but the YES/NO condition analysis
% does not depend on it.
%
% -------------------------------------------------------------------------
% MOTION QC
% -------------------------------------------------------------------------
%
% For each Dyad x Participant (A/B), the function reads:
%
%   time_sec
%   has_face
%   unitary
%
% and calculates:
%
%   - number of samples
%   - recording start/end/duration
%   - estimated sampling rate from median(diff(time_sec))
%   - timing irregularity
%   - number of large time gaps
%   - percentage of samples with a detected face
%   - percentage of missing unitary values
%   - behavior of unitary when has_face == 0
%   - basic descriptive statistics of unitary
%
% The function NEVER assumes a fixed 30-Hz frame rate. The actual time_sec
% column is the source of truth.
%
% -------------------------------------------------------------------------
% OUTPUTS
% -------------------------------------------------------------------------
%
% eventTable
%   One row per strict YES/NO event.
%
% motionQCTable
%   One row per participant video (up to 70 rows).
%
% dyadSummary
%   One row per dyad, summarizing event counts and motion QC.
%
% candidateTable
%   One row per textual one-word YES/NO candidate, including pass/fail flags
%   for role, is_yn, n_words, and the final strict event criterion.
%
% The tables are also saved by default as CSV files and together in a MAT
% file.
%
% -------------------------------------------------------------------------
% EXAMPLE
% -------------------------------------------------------------------------
%
%   [events, motionQC, dyads, candidates] = ...
%       step_video1_extract_events_motionQC_HyperYESNO;
%
% Or with custom paths:
%
%   [events, motionQC, dyads, candidates] = ...
%       step_video1_extract_events_motionQC_HyperYESNO( ...
%       'MotionRoot', 'E:\HyperYESNO_videosCUT', ...
%       'TranscriptRoot', 'E:\VIDEOS_Alej');
%
% -------------------------------------------------------------------------
% Author: Alejandro Perez / HyperYESNO project
% -------------------------------------------------------------------------


%% Parse inputs

p = inputParser;

addParameter(p, 'MotionRoot', ...
    'E:\HyperYESNO_videosCUT', ...
    @(x) ischar(x) || isstring(x));

addParameter(p, 'TranscriptRoot', ...
    'E:\VIDEOS_Alej', ...
    @(x) ischar(x) || isstring(x));

addParameter(p, 'Dyads', 1:35, ...
    @(x) isnumeric(x) && isvector(x));

addParameter(p, 'MaxQuestionResponseGapSec', 15, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);

addParameter(p, 'SaveOutputs', true, ...
    @(x) islogical(x) || isnumeric(x));

addParameter(p, 'OutputDir', '', ...
    @(x) ischar(x) || isstring(x));

parse(p, varargin{:});

motionRoot      = char(p.Results.MotionRoot);
transcriptRoot  = char(p.Results.TranscriptRoot);
dyads           = p.Results.Dyads(:)';
maxQRGapSec     = p.Results.MaxQuestionResponseGapSec;
saveOutputs     = logical(p.Results.SaveOutputs);
outputDir       = char(p.Results.OutputDir);

if isempty(outputDir)
    outputDir = fullfile(motionRoot, '_video_analysis');
end

if saveOutputs && ~isfolder(outputDir)
    mkdir(outputDir);
end


%% Containers

eventRows     = struct([]);
candidateRows = struct([]);
motionRows    = struct([]);
summaryRows   = struct([]);


%% Process dyads

fprintf('\n============================================================\n');
fprintf('HyperYESNO video analysis: event extraction + motion QC\n');
fprintf('============================================================\n\n');

for d = dyads

    dyadStr = sprintf('Dyad%02d', d);

    fprintf('%s\n', dyadStr);

    %% --------------------------------------------------------------------
    % 1. Locate and read diarization / utterance file
    % ---------------------------------------------------------------------

    transcriptFile = findTranscriptFile(transcriptRoot, dyadStr);

    transcriptFound = ~isempty(transcriptFile);

    nUtterances                = NaN;
    nExactYesNoText            = 0;
    nStrictEvents              = 0;
    nYES                       = 0;
    nNO                        = 0;
    nRoleValid                 = 0;
    nRoleInvalid               = 0;
    nCandidatesFailedMetadata  = 0;

    if transcriptFound

        try
            U = readtable(transcriptFile, ...
                'TextType', 'string', ...
                'VariableNamingRule', 'preserve');

            requiredVars = {'utt_id', 'start_time', 'end_time', 'role', ...
                'speaker', 'is_yn', 'n_words', 'text'};

            assertRequiredVariables(U, requiredVars, transcriptFile);

            nUtterances = height(U);

            uttID     = getStringColumn(U, 'utt_id');
            startTime = getNumericColumn(U, 'start_time');
            endTime   = getNumericColumn(U, 'end_time');
            role      = upper(strtrim(getStringColumn(U, 'role')));
            speaker   = upper(strtrim(getStringColumn(U, 'speaker')));
            isYN      = getNumericColumn(U, 'is_yn');
            nWords    = getNumericColumn(U, 'n_words');
            rawText   = getStringColumn(U, 'text');

            normText = normalizeYesNoText(rawText);

            % Textual candidate = normalized text itself is exactly yes/no.
            % We additionally retain n_words in candidateTable so metadata
            % inconsistencies can be inspected.
            isTextYes = normText == "yes";
            isTextNo  = normText == "no";
            isExactYesNoText = isTextYes | isTextNo;

            passesRole   = role == "R";
            passesIsYN   = isYN == 1;
            passesNWords = nWords == 1;

            strictEvent = isExactYesNoText & ...
                passesRole & passesIsYN & passesNWords;

            nExactYesNoText           = sum(isExactYesNoText);
            nStrictEvents             = sum(strictEvent);
            nCandidatesFailedMetadata = sum(isExactYesNoText & ~strictEvent);

            % -------------------------------------------------------------
            % Save ALL textual Yes/No candidates for audit/QC
            % -------------------------------------------------------------
            candidateIdx = find(isExactYesNoText);

            for ii = 1:numel(candidateIdx)

                k = candidateIdx(ii);

                c = struct;
                c.Dyad               = string(dyadStr);
                c.UttID              = uttID(k);
                c.StartSec           = startTime(k);
                c.EndSec             = endTime(k);
                c.DurationSec        = endTime(k) - startTime(k);
                c.Role               = role(k);
                c.Speaker            = speaker(k);
                c.IsYN               = isYN(k);
                c.NWords             = nWords(k);
                c.Text               = rawText(k);
                c.NormalizedText     = normText(k);
                c.PassesRoleR        = logical(passesRole(k));
                c.PassesIsYN         = logical(passesIsYN(k));
                c.PassesOneWord      = logical(passesNWords(k));
                c.StrictEvent        = logical(strictEvent(k));
                c.TranscriptFile     = string(transcriptFile);

                candidateRows = appendStruct(candidateRows, c);
            end

            % -------------------------------------------------------------
            % Extract strict YES/NO events
            % -------------------------------------------------------------
            strictIdx = find(strictEvent);

            for ii = 1:numel(strictIdx)

                k = strictIdx(ii);

                e = struct;

                e.Dyad            = string(dyadStr);
                e.UttID           = uttID(k);

                if normText(k) == "yes"
                    e.Condition = "YES";
                else
                    e.Condition = "NO";
                end

                e.OnsetSec        = startTime(k);
                e.EndSec          = endTime(k);
                e.DurationSec     = endTime(k) - startTime(k);
                e.Responder       = speaker(k);
                e.Text            = rawText(k);
                e.NormalizedText  = normText(k);

                % Search for the most recent previous Q utterance.
                [qFound, qIdx] = findPreviousQuestion( ...
                    role, startTime, endTime, k, startTime(k));

                e.QuestionFound = qFound;

                if qFound
                    e.QuestionUttID      = uttID(qIdx);
                    e.Questioner         = speaker(qIdx);
                    e.QuestionStartSec   = startTime(qIdx);
                    e.QuestionEndSec     = endTime(qIdx);
                    e.QuestionText       = rawText(qIdx);
                    e.QuestionResponseGapSec = startTime(k) - endTime(qIdx);
                else
                    e.QuestionUttID      = string(missing);
                    e.Questioner         = string(missing);
                    e.QuestionStartSec   = NaN;
                    e.QuestionEndSec     = NaN;
                    e.QuestionText       = string(missing);
                    e.QuestionResponseGapSec = NaN;
                end

                responderKnown = any(e.Responder == ["A", "B"]);
                questionerKnown = qFound && any(e.Questioner == ["A", "B"]);

                if qFound && responderKnown && questionerKnown
                    e.SpeakerOpposed = e.Responder ~= e.Questioner;
                else
                    e.SpeakerOpposed = false;
                end

                if qFound
                    gapAcceptable = ...
                        isfinite(e.QuestionResponseGapSec) && ...
                        e.QuestionResponseGapSec >= -0.25 && ...
                        e.QuestionResponseGapSec <= maxQRGapSec;
                else
                    gapAcceptable = false;
                end

                e.GapAcceptable = logical(gapAcceptable);

                e.RoleValid = logical( ...
                    responderKnown && ...
                    questionerKnown && ...
                    e.SpeakerOpposed && ...
                    gapAcceptable);

                % Only assign Knower/Guesser when role validation passes.
                if e.RoleValid
                    e.Knower  = e.Responder;
                    e.Guesser = e.Questioner;
                else
                    e.Knower  = string(missing);
                    e.Guesser = string(missing);
                end

                e.TranscriptFile = string(transcriptFile);

                eventRows = appendStruct(eventRows, e);
            end

            % Counts for this dyad
            if any(strictEvent)
                nYES = sum(strictEvent & isTextYes);
                nNO  = sum(strictEvent & isTextNo);

                % RoleValid was determined event-by-event; retrieve the
                % current dyad's event rows after table construction below.
                % For now, recompute using a temporary logical vector.
                thisRoleValid = false(sum(strictEvent), 1);
                jj = 0;

                for k = strictIdx(:)'
                    jj = jj + 1;

                    [qFound, qIdx] = findPreviousQuestion( ...
                        role, startTime, endTime, k, startTime(k));

                    if qFound
                        qSpeaker = speaker(qIdx);
                        rSpeaker = speaker(k);
                        qrGap = startTime(k) - endTime(qIdx);

                        thisRoleValid(jj) = ...
                            any(rSpeaker == ["A","B"]) && ...
                            any(qSpeaker == ["A","B"]) && ...
                            rSpeaker ~= qSpeaker && ...
                            isfinite(qrGap) && ...
                            qrGap >= -0.25 && ...
                            qrGap <= maxQRGapSec;
                    end
                end

                nRoleValid   = sum(thisRoleValid);
                nRoleInvalid = sum(~thisRoleValid);
            end

        catch ME
            warning('%s: could not process transcript.\n%s', ...
                dyadStr, ME.message);
            transcriptFound = false;
        end

    else
        warning('%s: transcript file not found.', dyadStr);
    end


    %% --------------------------------------------------------------------
    % 2. Motion QC for participants A and B
    % ---------------------------------------------------------------------

    fsA = NaN;
    fsB = NaN;
    durationA = NaN;
    durationB = NaN;
    facePctA = NaN;
    facePctB = NaN;
    motionAFound = false;
    motionBFound = false;
    startA = NaN;
    endA = NaN;
    startB = NaN;
    endB = NaN;

    for participant = ["A", "B"]

        motionFile = fullfile( ...
            motionRoot, ...
            dyadStr, ...
            sprintf('%s-%s_cut', dyadStr, participant), ...
            sprintf('%s-%s_motion.csv', dyadStr, participant));

        m = createEmptyMotionQCRow(dyadStr, participant, motionFile);

        if isfile(motionFile)

            m.FileFound = true;

            try
                M = readtable(motionFile, ...
                    'TextType', 'string', ...
                    'VariableNamingRule', 'preserve');

                requiredMotionVars = {'time_sec', 'has_face', 'unitary'};
                assertRequiredVariables(M, requiredMotionVars, motionFile);

                t       = getNumericColumn(M, 'time_sec');
                hasFace = getNumericColumn(M, 'has_face');
                unitary = getNumericColumn(M, 'unitary');

                m.NSamples = numel(t);

                finiteT = isfinite(t);

                if any(finiteT)
                    m.StartSec    = min(t(finiteT));
                    m.EndSec      = max(t(finiteT));
                    m.DurationSec = m.EndSec - m.StartSec;
                end

                % Timing QC uses positive finite successive differences only.
                dtAll = diff(t);
                dt = dtAll(isfinite(dtAll) & dtAll > 0);

                m.TimeStrictlyIncreasing = all( ...
                    isfinite(dtAll) & dtAll > 0);

                if ~isempty(dt)

                    medDt = median(dt);

                    m.MedianDtSec = medDt;
                    m.EstimatedFsHz = 1 / medDt;

                    if medDt > 0
                        m.DtCV = std(dt) / medDt;
                        m.LargeTimeGapCount = sum(dt > 2.5 * medDt);
                        m.MaxDtSec = max(dt);
                    end
                end

                % Face detection QC
                validFace = isfinite(hasFace);

                if any(validFace)
                    m.FaceDetectedPct = ...
                        100 * mean(hasFace(validFace) ~= 0);
                end

                noFace = validFace & hasFace == 0;
                m.NoFaceNSamples = sum(noFace);

                % Unitary QC
                m.UnitaryMissingPct = ...
                    100 * mean(~isfinite(unitary));

                finiteUnitary = unitary(isfinite(unitary));

                if ~isempty(finiteUnitary)
                    m.UnitaryMean   = mean(finiteUnitary);
                    m.UnitarySD     = std(finiteUnitary);
                    m.UnitaryMedian = median(finiteUnitary);
                    m.UnitaryMin    = min(finiteUnitary);
                    m.UnitaryMax    = max(finiteUnitary);
                end

                % What happens to unitary when no face is detected?
                if any(noFace)

                    uNoFace = unitary(noFace);

                    m.UnitaryNaNWhenNoFacePct = ...
                        100 * mean(~isfinite(uNoFace));

                    finiteNoFace = isfinite(uNoFace);

                    if any(finiteNoFace)
                        m.UnitaryZeroWhenNoFacePct = ...
                            100 * mean(abs(uNoFace(finiteNoFace)) < 1e-12);
                    end
                end

                % Useful diagnostic: exact repeated consecutive unitary
                % values. This is not necessarily an error; it only helps
                % identify held values in problematic tracking periods.
                if numel(unitary) > 1
                    u1 = unitary(1:end-1);
                    u2 = unitary(2:end);
                    validPair = isfinite(u1) & isfinite(u2);

                    if any(validPair)
                        m.UnitaryRepeatedConsecutivePct = ...
                            100 * mean(u1(validPair) == u2(validPair));
                    end
                end

            catch ME
                m.ReadSuccessful = false;
                m.ErrorMessage = string(ME.message);

                warning('%s-%s: could not process motion CSV.\n%s', ...
                    dyadStr, participant, ME.message);
            end

        else
            warning('%s-%s: motion CSV not found:\n  %s', ...
                dyadStr, participant, motionFile);
        end

        if m.FileFound && strlength(m.ErrorMessage) == 0
            m.ReadSuccessful = true;
        end

        motionRows = appendStruct(motionRows, m);

        % Save a few fields for dyad-level summary.
        if participant == "A"
            motionAFound = m.FileFound && m.ReadSuccessful;
            fsA       = m.EstimatedFsHz;
            durationA = m.DurationSec;
            facePctA  = m.FaceDetectedPct;
            startA    = m.StartSec;
            endA      = m.EndSec;
        else
            motionBFound = m.FileFound && m.ReadSuccessful;
            fsB       = m.EstimatedFsHz;
            durationB = m.DurationSec;
            facePctB  = m.FaceDetectedPct;
            startB    = m.StartSec;
            endB      = m.EndSec;
        end
    end


    %% --------------------------------------------------------------------
    % 3. Dyad-level summary
    % ---------------------------------------------------------------------

    s = struct;

    s.Dyad                        = string(dyadStr);
    s.TranscriptFound             = logical(transcriptFound);
    s.NUtterances                 = nUtterances;
    s.NExactYesNoTextCandidates   = nExactYesNoText;
    s.NStrictEvents               = nStrictEvents;
    s.NYES                        = nYES;
    s.NNO                         = nNO;
    s.NRoleValid                  = nRoleValid;
    s.NRoleInvalid                = nRoleInvalid;
    s.NCandidatesFailedMetadata   = nCandidatesFailedMetadata;

    s.MotionAFound                = logical(motionAFound);
    s.MotionBFound                = logical(motionBFound);
    s.EstimatedFsAHz              = fsA;
    s.EstimatedFsBHz              = fsB;
    s.DurationASec                = durationA;
    s.DurationBSec                = durationB;
    s.FaceDetectedAPct            = facePctA;
    s.FaceDetectedBPct            = facePctB;

    if motionAFound && motionBFound
        s.CommonStartSec = max(startA, startB);
        s.CommonEndSec   = min(endA, endB);
        s.CommonDurationSec = max(0, s.CommonEndSec - s.CommonStartSec);
        s.AbsFsDifferenceHz = abs(fsA - fsB);
        s.AbsDurationDifferenceSec = abs(durationA - durationB);
    else
        s.CommonStartSec = NaN;
        s.CommonEndSec = NaN;
        s.CommonDurationSec = NaN;
        s.AbsFsDifferenceHz = NaN;
        s.AbsDurationDifferenceSec = NaN;
    end

    summaryRows = appendStruct(summaryRows, s);

    fprintf('  Events: %d YES, %d NO | role-valid: %d/%d\n', ...
        nYES, nNO, nRoleValid, nStrictEvents);

    if motionAFound && motionBFound
        fprintf('  Motion Fs: A %.3f Hz | B %.3f Hz | face: A %.1f%%, B %.1f%%\n', ...
            fsA, fsB, facePctA, facePctB);
    else
        fprintf('  Motion QC incomplete for this dyad.\n');
    end

    fprintf('\n');

end


%% Convert accumulated structures to tables

if isempty(eventRows)
    eventTable = table;
else
    eventTable = struct2table(eventRows);
end

if isempty(candidateRows)
    candidateTable = table;
else
    candidateTable = struct2table(candidateRows);
end

if isempty(motionRows)
    motionQCTable = table;
else
    motionQCTable = struct2table(motionRows);
end

if isempty(summaryRows)
    dyadSummary = table;
else
    dyadSummary = struct2table(summaryRows);
end


%% Sort outputs where possible

if ~isempty(eventTable)
    eventTable = sortrows(eventTable, {'Dyad', 'OnsetSec'});
end

if ~isempty(candidateTable)
    candidateTable = sortrows(candidateTable, {'Dyad', 'StartSec'});
end

if ~isempty(motionQCTable)
    motionQCTable = sortrows(motionQCTable, {'Dyad', 'Participant'});
end

if ~isempty(dyadSummary)
    dyadSummary = sortrows(dyadSummary, 'Dyad');
end


%% Save outputs

if saveOutputs

    eventsCSV = fullfile(outputDir, ...
        'HyperYESNO_video_yesno_events.csv');

    candidatesCSV = fullfile(outputDir, ...
        'HyperYESNO_video_yesno_candidates_QC.csv');

    motionCSV = fullfile(outputDir, ...
        'HyperYESNO_video_motion_QC.csv');

    summaryCSV = fullfile(outputDir, ...
        'HyperYESNO_video_dyad_summary.csv');

    matFile = fullfile(outputDir, ...
        'HyperYESNO_video_stage1_events_motionQC.mat');

    writetable(eventTable, eventsCSV);
    writetable(candidateTable, candidatesCSV);
    writetable(motionQCTable, motionCSV);
    writetable(dyadSummary, summaryCSV);

    save(matFile, ...
        'eventTable', ...
        'candidateTable', ...
        'motionQCTable', ...
        'dyadSummary', ...
        'motionRoot', ...
        'transcriptRoot', ...
        'dyads', ...
        'maxQRGapSec', ...
        '-v7.3');

    fprintf('============================================================\n');
    fprintf('Saved outputs to:\n%s\n', outputDir);
    fprintf('============================================================\n\n');
end


%% Final console summary

fprintf('Total strict YES/NO events: %d\n', height(eventTable));

if ~isempty(eventTable)
    fprintf('  YES: %d\n', sum(eventTable.Condition == "YES"));
    fprintf('  NO : %d\n', sum(eventTable.Condition == "NO"));
    fprintf('  Role-valid: %d (%.1f%%)\n', ...
        sum(eventTable.RoleValid), ...
        100 * mean(eventTable.RoleValid));
end

fprintf('Motion recordings successfully read: %d/%d\n\n', ...
    sum(motionQCTable.ReadSuccessful), height(motionQCTable));

end


%% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function transcriptFile = findTranscriptFile(transcriptRoot, dyadStr)
% Locate the utterance CSV for one dyad.
%
% First try the expected filename. If it does not exist, search recursively
% below the dyad's diarization folder.

transcriptFile = '';

diarDir = fullfile(transcriptRoot, dyadStr, 'diarization');

if ~isfolder(diarDir)
    return;
end

expectedFile = fullfile( ...
    diarDir, ...
    sprintf('%s_diarized_v11_utterances.csv', dyadStr));

if isfile(expectedFile)
    transcriptFile = expectedFile;
    return;
end

% Also try a literal construction corresponding to possible variants where
% the filename may contain an additional separator.
candidateNames = { ...
    sprintf('%s_diarized_v11_utterances.csv', dyadStr), ...
    sprintf('%s-_diarized_v11_utterances.csv', dyadStr), ...
    sprintf('%s_diarized_v11_utterances.CSV', dyadStr)};

for i = 1:numel(candidateNames)
    f = fullfile(diarDir, candidateNames{i});

    if isfile(f)
        transcriptFile = f;
        return;
    end
end

% Recursive fallback.
files = dir(fullfile(diarDir, '**', '*utterances.csv'));

if isempty(files)
    files = dir(fullfile(diarDir, '**', '*utterances.CSV'));
end

if isempty(files)
    return;
end

% Prefer a filename containing "diarized_v11".
names = string({files.name});
preferred = contains(lower(names), 'diarized_v11');

if any(preferred)
    idx = find(preferred, 1, 'first');
else
    idx = 1;
end

transcriptFile = fullfile(files(idx).folder, files(idx).name);

if numel(files) > 1
    warning('%s: multiple *utterances.csv files found. Using:\n  %s', ...
        dyadStr, transcriptFile);
end

end


function assertRequiredVariables(T, requiredVars, sourceFile)
% Confirm that a table contains all expected columns.

vars = string(T.Properties.VariableNames);

for i = 1:numel(requiredVars)

    if ~any(strcmpi(vars, requiredVars{i}))
        error('Required column "%s" not found in:\n%s', ...
            requiredVars{i}, sourceFile);
    end
end

end


function x = getStringColumn(T, varName)
% Retrieve a table variable by case-insensitive name and convert to string.

idx = find(strcmpi(T.Properties.VariableNames, varName), 1, 'first');

if isempty(idx)
    error('Column "%s" not found.', varName);
end

x = string(T{:, idx});
x = x(:);

end


function x = getNumericColumn(T, varName)
% Retrieve a table variable by case-insensitive name and convert robustly
% to double.

idx = find(strcmpi(T.Properties.VariableNames, varName), 1, 'first');

if isempty(idx)
    error('Column "%s" not found.', varName);
end

raw = T{:, idx};

if isnumeric(raw) || islogical(raw)
    x = double(raw);
else
    x = str2double(string(raw));
end

x = x(:);

end


function normText = normalizeYesNoText(rawText)
% Conservative text normalization used only to identify standalone YES/NO.
%
% The expression strips whitespace and selected punctuation from the start
% and end of the utterance, but does not change words inside the utterance.

normText = lower(strtrim(string(rawText)));

% Remove quotation marks / brackets / punctuation at the edges.
normText = regexprep(normText, ...
    '^[\s"''“”‘’\(\)\[\]\{\}\.,!\?;:]+', '');

normText = regexprep(normText, ...
    '[\s"''“”‘’\(\)\[\]\{\}\.,!\?;:]+$', '');

normText = strtrim(normText);

end


function [qFound, qIdx] = findPreviousQuestion(role, startTime, endTime, ...
    responseIdx, responseOnset)
% Find the latest preceding utterance labelled Q.
%
% Preference is given to a question whose end_time is not later than the
% response onset. If none satisfies that condition, the latest earlier row
% labelled Q is returned, allowing a small overlap to be assessed later.

qFound = false;
qIdx = NaN;

if responseIdx <= 1
    return;
end

priorIdx = (1:responseIdx-1)';

isQ = role(priorIdx) == "Q";

% Prefer Q utterances that have ended before the response onset.
endedBeforeResponse = ...
    isfinite(endTime(priorIdx)) & ...
    endTime(priorIdx) <= responseOnset + 0.25;

candidate = priorIdx(isQ & endedBeforeResponse);

if isempty(candidate)
    % Fallback: any prior Q row.
    candidate = priorIdx(isQ);
end

if isempty(candidate)
    return;
end

% Because rows are chronological in the intended files, the final matching
% row is normally the latest one. To remain robust, choose the candidate with
% the largest finite start_time if possible.
candidateStarts = startTime(candidate);

if any(isfinite(candidateStarts))
    [~, localIdx] = max(candidateStarts);
    qIdx = candidate(localIdx);
else
    qIdx = candidate(end);
end

qFound = true;

end


function rows = appendStruct(rows, newRow)
% Append a scalar structure to a structure array.

if isempty(rows)
    rows = newRow;
else
    rows(end+1) = newRow; %#ok<AGROW>
end

end


function m = createEmptyMotionQCRow(dyadStr, participant, motionFile)
% Create a motion-QC row with fixed field order/types.

m = struct;

m.Dyad                         = string(dyadStr);
m.Participant                  = string(participant);
m.MotionFile                   = string(motionFile);
m.FileFound                    = false;
m.ReadSuccessful               = false;
m.ErrorMessage                 = "";

m.NSamples                     = NaN;
m.StartSec                     = NaN;
m.EndSec                       = NaN;
m.DurationSec                  = NaN;

m.MedianDtSec                  = NaN;
m.EstimatedFsHz                = NaN;
m.DtCV                         = NaN;
m.MaxDtSec                     = NaN;
m.LargeTimeGapCount            = NaN;
m.TimeStrictlyIncreasing       = false;

m.FaceDetectedPct              = NaN;
m.NoFaceNSamples               = NaN;

m.UnitaryMissingPct            = NaN;
m.UnitaryNaNWhenNoFacePct      = NaN;
m.UnitaryZeroWhenNoFacePct     = NaN;
m.UnitaryRepeatedConsecutivePct = NaN;

m.UnitaryMean                  = NaN;
m.UnitarySD                    = NaN;
m.UnitaryMedian                = NaN;
m.UnitaryMin                   = NaN;
m.UnitaryMax                   = NaN;

end
