function [results, groupStatsTable, dyadLagTable, artifactQCTable] = ...
    step_video3_lagged_headmotion_correlation_HyperYESNO(varargin)
% STEP_VIDEO3_LAGGED_HEADMOTION_CORRELATION_HYPERYESNO
%
% Primary interpersonal head-motion analysis for the HyperYESNO video data.
%
% This function compares lagged A-B head-motion correlation between YES and
% NO response epochs. The inferential unit is the DYAD, not the individual
% response.
%
% -------------------------------------------------------------------------
% PRIMARY QUESTION
% -------------------------------------------------------------------------
%
%   Does interpersonal head-motion alignment differ around YES versus NO
%   responses?
%
% Knower/Guesser direction is deliberately NOT used in this primary video
% analysis. Participant labels A and B are retained only as the two members
% of each dyad.
%
% -------------------------------------------------------------------------
% INPUT
% -------------------------------------------------------------------------
%
% By default the function loads:
%
%   E:\HyperYESNO\_videosCUT_video_analysis\
%       HyperYESNO_video_stage2_epochs.mat
%
% created by:
%
%   step_video2_epoch_headmotion_HyperYESNO.m
%
% The MAT file must contain epochData with:
%
%   epochData.A             [events x time]
%   epochData.B             [events x time]
%   epochData.dyad
%   epochData.condition     ("YES" / "NO")
%   epochData.validEpoch
%   epochData.targetFs
%   epochData.relativeTimeSec
%
% -------------------------------------------------------------------------
% EXTREME TRACKING-ARTIFACT HANDLING
% -------------------------------------------------------------------------
%
% Rare very large unitary-motion excursions are treated as tracking/pose
% estimation discontinuities and are excluded from the correlation.
%
% Default rule:
%
%       unitary > 5  --> mask as NaN
%
% plus one neighboring frame on either side.
%
% No smoothing or replacement is performed. Masking is deliberately used
% instead of smoothing because smoothing could introduce artificial temporal
% covariance between the two participants.
%
% The threshold and number of neighboring frames can be changed:
%
%   'ArtifactThreshold', 5
%   'ArtifactNeighborFrames', 1
%
% Set ArtifactThreshold = Inf to disable this masking.
%
% -------------------------------------------------------------------------
% LAGGED CORRELATION
% -------------------------------------------------------------------------
%
% Default lag search:
%
%       -1.0 to +1.0 seconds
%
% in one-frame steps at the Stage-2 sampling rate (normally 30 Hz).
%
% Lag convention:
%
%   positive lag:
%       corr[A(t), B(t + lag)]
%       i.e. A precedes B
%
%   negative lag:
%       corr[A(t + |lag|), B(t)]
%       i.e. B precedes A
%
% Because A/B direction has no common psychological meaning across dyads in
% the conservative primary analysis, the final inferential curves are
% symmetrized:
%
%       z_sym(|lag|) = mean( z(-|lag|), z(+|lag|) )
%
% Thus the primary lag axis is:
%
%       0 ... 1 s
%
% and represents temporal separation irrespective of which participant
% moved first.
%
% -------------------------------------------------------------------------
% HOW CORRELATIONS ARE AGGREGATED
% -------------------------------------------------------------------------
%
% Correlation is first calculated separately for every event at every lag.
% Pearson r is Fisher transformed:
%
%       z = atanh(r)
%
% and then averaged across valid events belonging to the same:
%
%       Dyad x Condition x Lag
%
% Therefore, regardless of whether a dyad has 40 or 200 responses, it
% contributes ONE YES curve and ONE NO curve to the group inference.
%
% Event epochs are never concatenated across their boundaries for lagging.
%
% -------------------------------------------------------------------------
% WITHIN-DYAD PSEUDO-SYNCHRONY / SURROGATE CONTROL
% -------------------------------------------------------------------------
%
% A response-locked pseudo-synchrony baseline is estimated separately
% within each dyad and condition.
%
% For each surrogate:
%
%       A epoch i  is paired with a DIFFERENT B epoch pi(i)
%
% using a random derangement (no event remains paired with itself).
%
% This preserves:
%   - the YES/NO condition
%   - each participant's response-locked movement structure
%   - the marginal distributions
%   - within-epoch temporal autocorrelation
%
% while disrupting the genuine simultaneous A-B relationship.
%
% The mean surrogate Fisher-z curve is subtracted from the real curve:
%
%       z_corrected = z_real - mean(z_surrogate)
%
% Default number of surrogates:
%
%       99
%
% This surrogate distribution is used as a correction/baseline. Statistical
% inference for YES versus NO is performed across dyads using sign flips.
%
% -------------------------------------------------------------------------
% GROUP-LEVEL INFERENCE
% -------------------------------------------------------------------------
%
% For every absolute lag:
%
%       Delta_z = z_corrected(YES) - z_corrected(NO)
%
% A paired dyad-level t statistic is calculated across dyads.
%
% Sign-flip permutations are then used for:
%
%   1) uncorrected two-sided permutation p values at each lag
%   2) maximum-|t| family-wise error correction across ALL tested absolute
%      lags
%
% Default:
%
%       NumPermutations = 10000
%
% No individual response is treated as an independent group observation.
%
% -------------------------------------------------------------------------
% DEFAULT ANALYSIS SETTINGS
% -------------------------------------------------------------------------
%
%   MaxLagSec               = 1
%   ArtifactThreshold       = 5
%   ArtifactNeighborFrames  = 1
%   MinPairsPerEvent        = 60
%   MinEventsPerCondition   = 10
%   NumSurrogates           = 99
%   NumPermutations         = 10000
%   RandomSeed              = 20260810
%
% -------------------------------------------------------------------------
% OUTPUTS
% -------------------------------------------------------------------------
%
% results
%   Full MATLAB structure containing settings, signed and symmetric lag
%   curves, surrogate curves, corrected curves, YES-NO differences and
%   permutation statistics.
%
% groupStatsTable
%   One row per absolute lag with group means, SEM, t statistic,
%   permutation p values and max-|t| FWER-corrected p values.
%
% dyadLagTable
%   Long-format table with one row per:
%
%       Dyad x Condition x absolute lag
%
%   containing the real, surrogate and surrogate-corrected Fisher-z values.
%
% artifactQCTable
%   One row per Dyad x Participant reporting how many epoch samples were
%   masked by the extreme-motion rule.
%
% -------------------------------------------------------------------------
% SAVED FILES
% -------------------------------------------------------------------------
%
% By default:
%
%   HyperYESNO_video_stage3_group_lag_stats.csv
%   HyperYESNO_video_stage3_dyad_lagged_correlations.csv
%   HyperYESNO_video_stage3_artifact_QC.csv
%   HyperYESNO_video_stage3_lagged_correlations.mat
%   HyperYESNO_video_stage3_YES_NO_curves.png
%   HyperYESNO_video_stage3_YES_minus_NO.png
%
% -------------------------------------------------------------------------
% EXAMPLE
% -------------------------------------------------------------------------
%
% [results, groupStats, dyadLag, artifactQC] = ...
%     step_video3_lagged_headmotion_correlation_HyperYESNO;
%
% A more computationally intensive surrogate run:
%
% [results, groupStats, dyadLag, artifactQC] = ...
%     step_video3_lagged_headmotion_correlation_HyperYESNO( ...
%       'NumSurrogates', 499);
%
% -------------------------------------------------------------------------
% HyperYESNO project
% -------------------------------------------------------------------------


%% ========================================================================
% Parse inputs
% =========================================================================

p = inputParser;

defaultStage2 = fullfile( ...
    'E:\HyperYESNO_videosCUT', ...
    '_video_analysis', ...
    'HyperYESNO_video_stage2_epochs.mat');

addParameter(p, 'Stage2Mat', defaultStage2, ...
    @(x) ischar(x) || isstring(x));

addParameter(p, 'OutputDir', '', ...
    @(x) ischar(x) || isstring(x));

addParameter(p, 'MaxLagSec', 1, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);

addParameter(p, 'ArtifactThreshold', 5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(p, 'ArtifactNeighborFrames', 1, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && mod(x,1) == 0);

addParameter(p, 'MinPairsPerEvent', 60, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 3);

addParameter(p, 'MinEventsPerCondition', 10, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 2);

addParameter(p, 'NumSurrogates', 99, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && mod(x,1) == 0);

addParameter(p, 'NumPermutations', 10000, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1 && mod(x,1) == 0);

addParameter(p, 'RandomSeed', 20260810, ...
    @(x) isnumeric(x) && isscalar(x));

addParameter(p, 'SaveOutputs', true, ...
    @(x) islogical(x) || isnumeric(x));

addParameter(p, 'MakeFigures', true, ...
    @(x) islogical(x) || isnumeric(x));

parse(p, varargin{:});

stage2Mat = char(p.Results.Stage2Mat);
outputDir = char(p.Results.OutputDir);

maxLagSec              = double(p.Results.MaxLagSec);
artifactThreshold      = double(p.Results.ArtifactThreshold);
artifactNeighborFrames = double(p.Results.ArtifactNeighborFrames);
minPairsPerEvent       = double(p.Results.MinPairsPerEvent);
minEventsPerCondition  = double(p.Results.MinEventsPerCondition);
numSurrogates          = double(p.Results.NumSurrogates);
numPermutations        = double(p.Results.NumPermutations);
randomSeed             = double(p.Results.RandomSeed);

saveOutputs = logical(p.Results.SaveOutputs);
makeFigures = logical(p.Results.MakeFigures);

if ~isfile(stage2Mat)
    error('Stage-2 MAT file not found:\n%s', stage2Mat);
end

if isempty(outputDir)
    outputDir = fileparts(stage2Mat);
end

if (saveOutputs || makeFigures) && ~isfolder(outputDir)
    mkdir(outputDir);
end

rng(randomSeed, 'twister');


%% ========================================================================
% Load and validate Stage-2 epochs
% =========================================================================

S = load(stage2Mat, 'epochData');

if ~isfield(S, 'epochData')
    error('The Stage-2 MAT file does not contain "epochData".');
end

E = S.epochData;

requiredFields = { ...
    'A', 'B', 'dyad', 'condition', ...
    'validEpoch', 'targetFs', 'relativeTimeSec'};

for i = 1:numel(requiredFields)
    if ~isfield(E, requiredFields{i})
        error('epochData is missing required field "%s".', ...
            requiredFields{i});
    end
end

A = double(E.A);
B = double(E.B);

if ~isequal(size(A), size(B))
    error('epochData.A and epochData.B must have identical dimensions.');
end

nEvents = size(A,1);
nTime   = size(A,2);

dyad      = string(E.dyad(:));
condition = upper(string(E.condition(:)));
validEpoch = logical(E.validEpoch(:));

if numel(dyad) ~= nEvents || ...
        numel(condition) ~= nEvents || ...
        numel(validEpoch) ~= nEvents
    error('Event metadata lengths do not match epochData.A/B rows.');
end

fs = double(E.targetFs);

if ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('epochData.targetFs must be a positive scalar.');
end

relativeTimeSec = double(E.relativeTimeSec(:)');

if numel(relativeTimeSec) ~= nTime
    error('epochData.relativeTimeSec does not match the epoch matrix width.');
end

dyadList = unique(dyad, 'stable');
nDyads = numel(dyadList);

conditionNames = ["YES", "NO"];
nConditions = numel(conditionNames);


%% ========================================================================
% Define lag vectors
% =========================================================================

maxLagSamples = round(maxLagSec * fs);

signedLagSamples = -maxLagSamples:maxLagSamples;
signedLagSec = signedLagSamples / fs;

absLagSamples = 0:maxLagSamples;
absLagSec = absLagSamples / fs;

nSignedLags = numel(signedLagSamples);
nAbsLags = numel(absLagSamples);


%% ========================================================================
% Extreme motion artifact masking
% =========================================================================

fprintf('\n============================================================\n');
fprintf('HyperYESNO video Step 3: lagged head-motion correlation\n');
fprintf('============================================================\n');
fprintf('Stage-2 events: %d\n', nEvents);
fprintf('Dyads: %d\n', nDyads);
fprintf('Sampling rate: %.6f Hz\n', fs);
fprintf('Lag search: %.3f to %.3f s (%d signed lags)\n', ...
    signedLagSec(1), signedLagSec(end), nSignedLags);
fprintf('Artifact rule: unitary > %.3f, plus +/- %d frame(s)\n', ...
    artifactThreshold, artifactNeighborFrames);
fprintf('Surrogates per dyad/condition: %d\n', numSurrogates);
fprintf('Group sign-flip permutations: %d\n\n', numPermutations);

[Aclean, artifactMaskA, extremeCenterA] = maskExtremeMotion( ...
    A, artifactThreshold, artifactNeighborFrames);

[Bclean, artifactMaskB, extremeCenterB] = maskExtremeMotion( ...
    B, artifactThreshold, artifactNeighborFrames);

artifactQCRows = struct([]);

for d = 1:nDyads

    dMask = dyad == dyadList(d) & validEpoch;

    for participant = ["A", "B"]

        if participant == "A"
            X = A;
            centerMask = extremeCenterA;
            expandedMask = artifactMaskA;
        else
            X = B;
            centerMask = extremeCenterB;
            expandedMask = artifactMaskB;
        end

        finiteInput = isfinite(X(dMask,:));

        q = struct;
        q.Dyad = dyadList(d);
        q.Participant = participant;
        q.NValidStage2Epochs = sum(dMask);
        q.NFiniteEpochSamplesBeforeMask = sum(finiteInput(:));
        q.NExtremeCenterSamples = sum(centerMask(dMask,:), 'all');
        q.NMaskedSamplesIncludingNeighbors = ...
            sum(expandedMask(dMask,:) & finiteInput, 'all');

        if q.NFiniteEpochSamplesBeforeMask > 0
            q.PctFiniteSamplesMasked = ...
                100 * q.NMaskedSamplesIncludingNeighbors / ...
                q.NFiniteEpochSamplesBeforeMask;
        else
            q.PctFiniteSamplesMasked = NaN;
        end

        artifactQCRows = appendStruct(artifactQCRows, q);
    end
end

artifactQCTable = struct2table(artifactQCRows);


%% ========================================================================
% Allocate dyad x condition x signed-lag arrays
% =========================================================================

realSignedZ = NaN(nDyads, nConditions, nSignedLags);
surrogateSignedMeanZ = NaN(nDyads, nConditions, nSignedLags);
correctedSignedZ = NaN(nDyads, nConditions, nSignedLags);

nEventsUsed = zeros(nDyads, nConditions);
nEventsContributingReal = NaN(nDyads, nConditions, nSignedLags);

% Optional storage of surrogate SD for QC.
surrogateSignedSDZ = NaN(nDyads, nConditions, nSignedLags);


%% ========================================================================
% Dyad x condition lagged correlation
% =========================================================================

for d = 1:nDyads

    fprintf('%s\n', dyadList(d));

    for c = 1:nConditions

        condName = conditionNames(c);

        idx = ...
            dyad == dyadList(d) & ...
            condition == condName & ...
            validEpoch;

        Acond = Aclean(idx,:);
        Bcond = Bclean(idx,:);

        nThis = size(Acond,1);
        nEventsUsed(d,c) = nThis;

        fprintf('  %s: %d Stage-2 valid epochs', condName, nThis);

        if nThis < minEventsPerCondition
            fprintf(' -> insufficient, skipped.\n');
            continue;
        end

        % -------------------------------------------------------------
        % Real event-by-event lagged correlations.
        % -------------------------------------------------------------
        [realCurveZ, nContrib] = meanEventLaggedFisherZ( ...
            Acond, Bcond, signedLagSamples, minPairsPerEvent);

        realSignedZ(d,c,:) = reshape(realCurveZ, 1, 1, []);
        nEventsContributingReal(d,c,:) = reshape(nContrib, 1, 1, []);

        % -------------------------------------------------------------
        % Surrogate / pseudo-synchrony baseline.
        % -------------------------------------------------------------
        if numSurrogates > 0

            surrogateCurves = NaN(numSurrogates, nSignedLags);

            for surr = 1:numSurrogates

                perm = randomDerangement(nThis);

                Bsur = Bcond(perm,:);

                surrogateCurves(surr,:) = ...
                    meanEventLaggedFisherZ( ...
                    Acond, Bsur, signedLagSamples, minPairsPerEvent);
            end

            surrogateMean = mean(surrogateCurves, 1, 'omitnan');
            surrogateSD   = std(surrogateCurves, 0, 1, 'omitnan');

            surrogateSignedMeanZ(d,c,:) = reshape(surrogateMean, 1, 1, []);
            surrogateSignedSDZ(d,c,:) = reshape(surrogateSD, 1, 1, []);

            correctedSignedZ(d,c,:) = reshape( ...
                realCurveZ - surrogateMean, 1, 1, []);

        else
            % If surrogates are explicitly disabled, corrected == real.
            surrogateSignedMeanZ(d,c,:) = zeros(1,1,nSignedLags);
            surrogateSignedSDZ(d,c,:) = zeros(1,1,nSignedLags);
            correctedSignedZ(d,c,:) = realCurveZ;
        end

        fprintf(' -> done.\n');
    end

    fprintf('\n');
end


%% ========================================================================
% Symmetrize +/- signed lag curves
% =========================================================================

realSymZ = symmetrizeSignedLagArray( ...
    realSignedZ, signedLagSamples, absLagSamples);

surrogateSymMeanZ = symmetrizeSignedLagArray( ...
    surrogateSignedMeanZ, signedLagSamples, absLagSamples);

correctedSymZ = symmetrizeSignedLagArray( ...
    correctedSignedZ, signedLagSamples, absLagSamples);

surrogateSymSDZ = symmetrizeSignedLagArray( ...
    surrogateSignedSDZ, signedLagSamples, absLagSamples);


%% ========================================================================
% YES - NO dyad differences
% =========================================================================

yesIdx = find(conditionNames == "YES");
noIdx  = find(conditionNames == "NO");

yesCorrected = squeeze(correctedSymZ(:,yesIdx,:));
noCorrected  = squeeze(correctedSymZ(:,noIdx,:));

yesReal = squeeze(realSymZ(:,yesIdx,:));
noReal  = squeeze(realSymZ(:,noIdx,:));

yesSurrogate = squeeze(surrogateSymMeanZ(:,yesIdx,:));
noSurrogate  = squeeze(surrogateSymMeanZ(:,noIdx,:));

differenceZ = yesCorrected - noCorrected;


%% ========================================================================
% Group means and SEM
% =========================================================================

groupYesCorrectedMean = mean(yesCorrected, 1, 'omitnan');
groupNoCorrectedMean  = mean(noCorrected, 1, 'omitnan');

groupYesCorrectedSEM = nanSEM(yesCorrected, 1);
groupNoCorrectedSEM  = nanSEM(noCorrected, 1);

groupYesRealMean = mean(yesReal, 1, 'omitnan');
groupNoRealMean  = mean(noReal, 1, 'omitnan');

groupYesSurrogateMean = mean(yesSurrogate, 1, 'omitnan');
groupNoSurrogateMean  = mean(noSurrogate, 1, 'omitnan');

groupDifferenceMean = mean(differenceZ, 1, 'omitnan');
groupDifferenceSEM  = nanSEM(differenceZ, 1);


%% ========================================================================
% Dyad-level paired sign-flip inference with max-|t| FWER correction
% =========================================================================

stats = signFlipMaxT( ...
    differenceZ, ...
    numPermutations, ...
    randomSeed + 1);

observedT = stats.observedT;
pPermutationUncorrected = stats.pUncorrected;
pPermutationFWER = stats.pFWER;
nDyadsAtLag = stats.nDyads;


%% ========================================================================
% Build group statistics table
% =========================================================================

groupStatsTable = table;

groupStatsTable.AbsLagSec = absLagSec(:);
groupStatsTable.AbsLagMs  = 1000 * absLagSec(:);

groupStatsTable.NDyads = nDyadsAtLag(:);

groupStatsTable.YES_RealMeanZ = groupYesRealMean(:);
groupStatsTable.NO_RealMeanZ  = groupNoRealMean(:);

groupStatsTable.YES_SurrogateMeanZ = groupYesSurrogateMean(:);
groupStatsTable.NO_SurrogateMeanZ  = groupNoSurrogateMean(:);

groupStatsTable.YES_CorrectedMeanZ = groupYesCorrectedMean(:);
groupStatsTable.NO_CorrectedMeanZ  = groupNoCorrectedMean(:);

groupStatsTable.YES_CorrectedSEM = groupYesCorrectedSEM(:);
groupStatsTable.NO_CorrectedSEM  = groupNoCorrectedSEM(:);

groupStatsTable.YESminusNO_MeanZ = groupDifferenceMean(:);
groupStatsTable.YESminusNO_SEM   = groupDifferenceSEM(:);

groupStatsTable.Tstat = observedT(:);
groupStatsTable.Pperm = pPermutationUncorrected(:);
groupStatsTable.PmaxT_FWER = pPermutationFWER(:);

groupStatsTable.SignificantFWER05 = ...
    groupStatsTable.PmaxT_FWER < 0.05;


%% ========================================================================
% Build long-format dyad x condition x absolute-lag table
% =========================================================================

nRows = nDyads * nConditions * nAbsLags;

DyadCol       = strings(nRows,1);
ConditionCol  = strings(nRows,1);
AbsLagSecCol  = NaN(nRows,1);
AbsLagMsCol   = NaN(nRows,1);
NEventsCol    = NaN(nRows,1);

RealZCol      = NaN(nRows,1);
SurrogateZCol = NaN(nRows,1);
CorrectedZCol = NaN(nRows,1);

RealRCol      = NaN(nRows,1);
SurrogateRCol = NaN(nRows,1);

row = 0;

for d = 1:nDyads
    for c = 1:nConditions
        for l = 1:nAbsLags

            row = row + 1;

            DyadCol(row)      = dyadList(d);
            ConditionCol(row) = conditionNames(c);
            AbsLagSecCol(row) = absLagSec(l);
            AbsLagMsCol(row)  = 1000 * absLagSec(l);
            NEventsCol(row)   = nEventsUsed(d,c);

            realZ = realSymZ(d,c,l);
            surZ  = surrogateSymMeanZ(d,c,l);
            corZ  = correctedSymZ(d,c,l);

            RealZCol(row)      = realZ;
            SurrogateZCol(row) = surZ;
            CorrectedZCol(row) = corZ;

            % Fisher-z back-transform only for the actual real/surrogate
            % correlations. CorrectedZ is a DIFFERENCE in z space and is
            % therefore intentionally not labelled as a Pearson r.
            RealRCol(row)      = tanh(realZ);
            SurrogateRCol(row) = tanh(surZ);
        end
    end
end

dyadLagTable = table( ...
    DyadCol, ...
    ConditionCol, ...
    AbsLagSecCol, ...
    AbsLagMsCol, ...
    NEventsCol, ...
    RealRCol, ...
    RealZCol, ...
    SurrogateRCol, ...
    SurrogateZCol, ...
    CorrectedZCol, ...
    'VariableNames', { ...
        'Dyad', ...
        'Condition', ...
        'AbsLagSec', ...
        'AbsLagMs', ...
        'NEvents', ...
        'RealR', ...
        'RealZ', ...
        'SurrogateMeanR', ...
        'SurrogateMeanZ', ...
        'CorrectedZ'});


%% ========================================================================
% Assemble results structure
% =========================================================================

results = struct;

results.settings = struct;
results.settings.stage2Mat = string(stage2Mat);
results.settings.outputDir = string(outputDir);
results.settings.fs = fs;
results.settings.maxLagSec = maxLagSec;
results.settings.artifactThreshold = artifactThreshold;
results.settings.artifactNeighborFrames = artifactNeighborFrames;
results.settings.minPairsPerEvent = minPairsPerEvent;
results.settings.minEventsPerCondition = minEventsPerCondition;
results.settings.numSurrogates = numSurrogates;
results.settings.numPermutations = numPermutations;
results.settings.randomSeed = randomSeed;

results.dyadList = dyadList;
results.conditionNames = conditionNames;

results.signedLagSamples = signedLagSamples;
results.signedLagSec = signedLagSec;

results.absLagSamples = absLagSamples;
results.absLagSec = absLagSec;

results.nEventsUsed = nEventsUsed;
results.nEventsContributingReal = nEventsContributingReal;

results.realSignedZ = realSignedZ;
results.surrogateSignedMeanZ = surrogateSignedMeanZ;
results.surrogateSignedSDZ = surrogateSignedSDZ;
results.correctedSignedZ = correctedSignedZ;

results.realSymZ = realSymZ;
results.surrogateSymMeanZ = surrogateSymMeanZ;
results.surrogateSymSDZ = surrogateSymSDZ;
results.correctedSymZ = correctedSymZ;

results.YEScorrectedZ = yesCorrected;
results.NOcorrectedZ = noCorrected;
results.YESminusNO_Z = differenceZ;

results.group = struct;
results.group.YEScorrectedMeanZ = groupYesCorrectedMean;
results.group.YEScorrectedSEM = groupYesCorrectedSEM;
results.group.NOcorrectedMeanZ = groupNoCorrectedMean;
results.group.NOcorrectedSEM = groupNoCorrectedSEM;
results.group.YESminusNO_MeanZ = groupDifferenceMean;
results.group.YESminusNO_SEM = groupDifferenceSEM;

results.statistics = stats;

results.artifactMaskSummary = artifactQCTable;


%% ========================================================================
% Save outputs
% =========================================================================

if saveOutputs

    groupCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage3_group_lag_stats.csv');

    dyadCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage3_dyad_lagged_correlations.csv');

    artifactCSV = fullfile(outputDir, ...
        'HyperYESNO_video_stage3_artifact_QC.csv');

    matFile = fullfile(outputDir, ...
        'HyperYESNO_video_stage3_lagged_correlations.mat');

    writetable(groupStatsTable, groupCSV);
    writetable(dyadLagTable, dyadCSV);
    writetable(artifactQCTable, artifactCSV);

    save(matFile, ...
        'results', ...
        'groupStatsTable', ...
        'dyadLagTable', ...
        'artifactQCTable', ...
        '-v7.3');
end


%% ========================================================================
% Figures
% =========================================================================

if makeFigures

    % -----------------------------------------------------------------
    % Figure 1: YES and NO surrogate-corrected curves
    % -----------------------------------------------------------------
    try
        f1 = figure( ...
            'Name', 'HyperYESNO - YES/NO head-motion correlation', ...
            'Color', 'w');

        hold on;

        x = absLagSec;

        hYes = plot( ...
            x, ...
            groupYesCorrectedMean, ...
            'LineWidth', 2);

        hNo = plot( ...
            x, ...
            groupNoCorrectedMean, ...
            'LineWidth', 2);

        errorbar( ...
            x, ...
            groupYesCorrectedMean, ...
            groupYesCorrectedSEM, ...
            'LineStyle', 'none', ...
            'HandleVisibility', 'off');

        errorbar( ...
            x, ...
            groupNoCorrectedMean, ...
            groupNoCorrectedSEM, ...
            'LineStyle', 'none', ...
            'HandleVisibility', 'off');

        yline(0, '--', 'HandleVisibility', 'off');

        xlabel('Absolute lag (s)');
        ylabel('Surrogate-corrected Fisher z');
        title('Interpersonal head-motion correlation around YES and NO responses');

        legend([hYes, hNo], {'YES','NO'}, 'Location', 'best');
        grid on;
        box off;

        fig1File = fullfile(outputDir, ...
            'HyperYESNO_video_stage3_YES_NO_curves.png');

        try
            exportgraphics(f1, fig1File, 'Resolution', 200);
        catch
            saveas(f1, fig1File);
        end

    catch ME
        warning('Could not create YES/NO correlation figure: %s', ME.message);
    end

    % -----------------------------------------------------------------
    % Figure 2: YES - NO difference and FWER significance
    % -----------------------------------------------------------------
    try
        f2 = figure( ...
            'Name', 'HyperYESNO - YES minus NO head-motion correlation', ...
            'Color', 'w');

        hold on;

        errorbar( ...
            x, ...
            groupDifferenceMean, ...
            groupDifferenceSEM, ...
            'LineWidth', 1.5);

        plot( ...
            x, ...
            groupDifferenceMean, ...
            'LineWidth', 2);

        yline(0, '--');

        sig = pPermutationFWER < 0.05;

        if any(sig)

            yRange = max(groupDifferenceMean + groupDifferenceSEM, ...
                [], 'omitnan') - ...
                min(groupDifferenceMean - groupDifferenceSEM, ...
                [], 'omitnan');

            if ~isfinite(yRange) || yRange == 0
                yRange = 1;
            end

            sigY = min(groupDifferenceMean - groupDifferenceSEM, ...
                [], 'omitnan') - 0.08 * yRange;

            plot( ...
                x(sig), ...
                repmat(sigY, 1, sum(sig)), ...
                'o', ...
                'MarkerFaceColor', 'auto', ...
                'DisplayName', 'max-|t| FWER p < .05');
        end

        xlabel('Absolute lag (s)');
        ylabel('YES - NO surrogate-corrected Fisher z');
        title('YES versus NO difference in interpersonal head-motion correlation');

        grid on;
        box off;

        fig2File = fullfile(outputDir, ...
            'HyperYESNO_video_stage3_YES_minus_NO.png');

        try
            exportgraphics(f2, fig2File, 'Resolution', 200);
        catch
            saveas(f2, fig2File);
        end

    catch ME
        warning('Could not create YES-NO difference figure: %s', ME.message);
    end
end


%% ========================================================================
% Console summary
% =========================================================================

fprintf('============================================================\n');
fprintf('Stage 3 complete\n');
fprintf('============================================================\n');

fprintf('Artifact masking across Stage-2 valid epoch samples:\n');

totalFinite = sum(artifactQCTable.NFiniteEpochSamplesBeforeMask, 'omitnan');
totalMasked = sum(artifactQCTable.NMaskedSamplesIncludingNeighbors, 'omitnan');

if totalFinite > 0
    fprintf('  %d / %d finite epoch-samples masked (%.4f%%)\n', ...
        totalMasked, totalFinite, 100 * totalMasked / totalFinite);
end

fprintf('\nMinimum max-|t| FWER-corrected p across lags: %.6f\n', ...
    min(pPermutationFWER, [], 'omitnan'));

sigLags = absLagSec(pPermutationFWER < 0.05);

if isempty(sigLags)
    fprintf('No absolute lag survived max-|t| FWER correction at p < .05.\n');
else
    fprintf('FWER-significant absolute lags (s):\n');
    fprintf('  %.4f', sigLags);
    fprintf('\n');
end

if saveOutputs
    fprintf('\nSaved outputs to:\n%s\n', outputDir);
end

fprintf('============================================================\n\n');

end


%% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function [Xclean, expandedMask, centerMask] = maskExtremeMotion( ...
    X, threshold, neighborFrames)
% MASKEXTREMEMOTION Replace extreme unitary values and immediate neighbors
% with NaN.
%
% Only finite values above threshold are considered artifact centers.

Xclean = X;

if isinf(threshold)
    centerMask = false(size(X));
    expandedMask = false(size(X));
    return;
end

centerMask = isfinite(X) & X > threshold;

if neighborFrames <= 0
    expandedMask = centerMask;
else
    kernel = ones(1, 2 * neighborFrames + 1);
    expandedMask = conv2(double(centerMask), kernel, 'same') > 0;
end

% Do not turn an originally missing value into anything else; setting it to
% NaN again is harmless.
Xclean(expandedMask) = NaN;

end


function [meanCurveZ, nContributingEvents] = meanEventLaggedFisherZ( ...
    A, B, lagSamples, minPairs)
% MEANEVENTLAGGEDFISHERZ
%
% Compute one Pearson correlation per EVENT per lag, Fisher transform each r,
% then average Fisher z values across events.
%
% A and B are [events x time].

nEvents = size(A,1);
nLags = numel(lagSamples);

meanCurveZ = NaN(1, nLags);
nContributingEvents = zeros(1, nLags);

for l = 1:nLags

    k = lagSamples(l);

    if k > 0
        % Positive lag: A precedes B.
        Xa = A(:, 1:end-k);
        Xb = B(:, 1+k:end);

    elseif k < 0
        kk = abs(k);

        % Negative lag: B precedes A.
        Xa = A(:, 1+kk:end);
        Xb = B(:, 1:end-kk);

    else
        Xa = A;
        Xb = B;
    end

    zEvent = rowwisePearsonFisherZ(Xa, Xb, minPairs);

    nContributingEvents(l) = sum(isfinite(zEvent));

    if nContributingEvents(l) > 0
        meanCurveZ(l) = mean(zEvent, 'omitnan');
    end
end

% Preserve expected row orientation.
meanCurveZ = reshape(meanCurveZ, 1, nLags);

if nEvents == 0
    meanCurveZ(:) = NaN;
end

end


function z = rowwisePearsonFisherZ(X, Y, minPairs)
% ROWWISEPEARSONFISHERZ Pairwise-complete Pearson r for each matrix row.
%
% This implementation uses only base MATLAB operations and does not require
% the Statistics and Machine Learning Toolbox.

nRows = size(X,1);
z = NaN(nRows,1);

for i = 1:nRows

    x = X(i,:);
    y = Y(i,:);

    valid = isfinite(x) & isfinite(y);

    n = sum(valid);

    if n < minPairs
        continue;
    end

    x = x(valid);
    y = y(valid);

    x = x - mean(x);
    y = y - mean(y);

    denom = sqrt(sum(x.^2) * sum(y.^2));

    if ~isfinite(denom) || denom <= 0
        continue;
    end

    r = sum(x .* y) / denom;

    % Numerical guard for atanh.
    r = max(min(r, 0.999999), -0.999999);

    z(i) = atanh(r);
end

end


function perm = randomDerangement(n)
% RANDOMDERANGEMENT Random permutation with no fixed points.
%
% For the event counts in this project, rejection sampling is efficient.

if n < 2
    error('A derangement requires at least two events.');
end

identity = (1:n)';

for attempt = 1:1000

    perm = randperm(n)';

    if all(perm ~= identity)
        return;
    end
end

% Extremely unlikely fallback: use a random non-zero cyclic shift.
shift = randi(n - 1);
perm = circshift(identity, shift);

end


function symArray = symmetrizeSignedLagArray( ...
    signedArray, signedLagSamples, absLagSamples)
% SYMMETRIZESIGNEDLAGARRAY
%
% signedArray dimensions:
%   dyad x condition x signed lag
%
% Output:
%   dyad x condition x absolute lag

nD = size(signedArray,1);
nC = size(signedArray,2);
nAbs = numel(absLagSamples);

symArray = NaN(nD, nC, nAbs);

for a = 1:nAbs

    k = absLagSamples(a);

    if k == 0

        idx0 = find(signedLagSamples == 0, 1, 'first');
        symArray(:,:,a) = signedArray(:,:,idx0);

    else

        idxNeg = find(signedLagSamples == -k, 1, 'first');
        idxPos = find(signedLagSamples ==  k, 1, 'first');

        pair = cat(4, ...
            signedArray(:,:,idxNeg), ...
            signedArray(:,:,idxPos));

        symArray(:,:,a) = mean(pair, 4, 'omitnan');
    end
end

end


function sem = nanSEM(X, dim)
% NANSEM Standard error of the mean ignoring NaN values.

n = sum(isfinite(X), dim);
sd = std(X, 0, dim, 'omitnan');

sem = sd ./ sqrt(n);
sem(n == 0) = NaN;

end


function stats = signFlipMaxT(D, nPerm, seed)
% SIGNFLIPMAXT Paired sign-flip permutation test with max-|t| correction.
%
% D:
%   dyad x lag matrix of YES-NO differences.
%
% The same random dyad sign pattern is used simultaneously at every lag,
% which is required for maximum-statistic family-wise correction.

rng(seed, 'twister');

[nDyadsTotal, nLags] = size(D);

observedT = NaN(1,nLags);
nDyads = zeros(1,nLags);

for l = 1:nLags

    x = D(:,l);
    x = x(isfinite(x));

    nDyads(l) = numel(x);

    observedT(l) = oneSampleT(x);
end

% One sign per dyad per permutation. The same sign matrix is applied to all
% lags, while each lag may use a subset of finite dyads.
signs = ones(nPerm, nDyadsTotal);
signs(rand(nPerm, nDyadsTotal) < 0.5) = -1;

tPerm = NaN(nPerm, nLags);

for l = 1:nLags

    valid = isfinite(D(:,l));
    x = D(valid,l);

    n = numel(x);

    if n < 2
        continue;
    end

    signSub = signs(:,valid);

    % Sum of signed values for every permutation.
    sumSigned = signSub * x;

    % Sum of squares is invariant under sign flips.
    sumSq = sum(x.^2);

    meanPerm = sumSigned / n;

    % Sample variance using sufficient statistics:
    %   sum((x - mean)^2) = sum(x^2) - sum(x)^2 / n
    varPerm = ...
        (sumSq - (sumSigned.^2) / n) / (n - 1);

    sePerm = sqrt(varPerm / n);

    t = meanPerm ./ sePerm;

    % Handle zero-variance edge cases.
    zeroSE = sePerm == 0;

    t(zeroSE & meanPerm == 0) = 0;
    t(zeroSE & meanPerm > 0) = Inf;
    t(zeroSE & meanPerm < 0) = -Inf;

    tPerm(:,l) = t;
end

absTPerm = abs(tPerm);

% Row-wise maximum across tested lags.
maxAbsT = max(absTPerm, [], 2, 'omitnan');

pUncorrected = NaN(1,nLags);
pFWER = NaN(1,nLags);

for l = 1:nLags

    if ~isfinite(observedT(l))
        continue;
    end

    validPerm = isfinite(absTPerm(:,l));

    pUncorrected(l) = ...
        (1 + sum(absTPerm(validPerm,l) >= abs(observedT(l)))) / ...
        (1 + sum(validPerm));

    validMax = isfinite(maxAbsT);

    pFWER(l) = ...
        (1 + sum(maxAbsT(validMax) >= abs(observedT(l)))) / ...
        (1 + sum(validMax));
end

stats = struct;
stats.observedT = observedT;
stats.nDyads = nDyads;
stats.pUncorrected = pUncorrected;
stats.pFWER = pFWER;
stats.numPermutations = nPerm;
stats.maxAbsTPermutation = maxAbsT;

end


function t = oneSampleT(x)
% ONESAMPLET One-sample t statistic against zero.

x = x(isfinite(x));
n = numel(x);

if n < 2
    t = NaN;
    return;
end

m = mean(x);
s = std(x, 0);

if s == 0
    if m == 0
        t = 0;
    elseif m > 0
        t = Inf;
    else
        t = -Inf;
    end
    return;
end

t = m / (s / sqrt(n));

end


function rows = appendStruct(rows, newRow)
% APPENDSTRUCT Append scalar structure to a structure array.

if isempty(rows)
    rows = newRow;
else
    rows(end+1) = newRow; %#ok<AGROW>
end

end
