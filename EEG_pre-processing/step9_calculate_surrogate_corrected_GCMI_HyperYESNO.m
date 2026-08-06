function [step9Data, dyadTable, qcTable] = ...
    step9_calculate_surrogate_corrected_GCMI_HyperYESNO(rootDir, varargin)
% STEP9_CALCULATE_SURROGATE_CORRECTED_GCMI_HYPERYESNO
% Calculate surrogate-corrected lagged GCMI and dyad-level YES-NO contrasts.
%
% This function follows:
%
%   step8_load_group_GCMI_HyperYESNO.m
%
% It loads the validated compact group arrays produced in Step 8 and
% calculates, for every ROI pair, lag, dyad, and situation:
%
%   corrected GCMI = observed GCMI - mean surrogate GCMI
%
% It then calculates two role-specific within-dyad contrasts:
%
%   A-Knower contrast =
%       corrected YES_AKnower - corrected NO_AKnower
%
%   B-Knower contrast =
%       corrected YES_BKnower - corrected NO_BKnower
%
% The primary dyad-level YES-NO contrast is the equally weighted average:
%
%   primary contrast =
%       0.5 * (A-Knower contrast + B-Knower contrast)
%
% With the default settings, the primary contrast is created only when both
% role-specific contrasts are available. Thus, participant A and
% participant B are treated as two repeated realizations of the Knower role,
% rather than as independent observations. The statistical unit remains the
% dyad.
%
% No group-level inferential statistics are performed here. Step 10 will
% use the primary dyad contrast for sign-flip cluster permutation tests.
%
% ARRAY DIMENSIONS
% ----------------
%
% Situation-level arrays:
%
%   Knower ROI x Guesser ROI x Lag x Dyad x Situation
%
% Contrast arrays:
%
%   Knower ROI x Guesser ROI x Lag x Dyad
%
% LAG CONVENTION
% --------------
%
%   negative lag = Knower precedes Guesser
%   positive lag = Guesser precedes Knower
%
% INPUT
% -----
%
% rootDir
%   HyperYESNO data root.
%
%   Default:
%       'E:\EEG_data_HyperYESNO'
%
% OPTIONAL NAME-VALUE INPUTS
% --------------------------
%
% 'Step8File'
%   Step 8 MAT file containing groupData.
%
%   Default:
%       rootDir/Group_GCMI/Step8_HyperYESNO_group_GCMI.mat
%
% 'OutputFolder'
%   Folder used to save Step 9 outputs.
%
%   Default:
%       rootDir/Group_GCMI
%
% 'RequireBothRolesForPrimary'
%   When true, the primary YES-NO contrast is calculated only for dyads
%   having valid A-Knower and B-Knower contrasts.
%
%   When false, a single available role contrast is retained as the primary
%   value for that dyad. This option is provided for sensitivity analyses
%   and is not recommended for the principal inferential analysis.
%
%   Default:
%       true
%
% 'MinimumTrialsPerSituation'
%   Minimum Step 7 trial count required for a situation to contribute to a
%   role-specific contrast. The corrected situation-level array is retained
%   regardless, but the contrast is not calculated below this threshold.
%
%   Default:
%       2
%
% 'MinimumSurrogatesPerSituation'
%   Minimum number of unique surrogate derangements required for a
%   situation to contribute to a role-specific contrast.
%
%   Default:
%       1
%
% 'InternalTolerance'
%   Numerical tolerance used for internal equivalence checks.
%
%   Default:
%       1e-12
%
% 'SaveOutputs'
%   Save the MAT file and Excel summary workbook.
%
%   Default:
%       true
%
% 'Verbose'
%   Print processing information.
%
%   Default:
%       true
%
% OUTPUTS
% -------
%
% step9Data
%   Structure containing the corrected situation arrays, role-specific
%   contrasts, primary dyad contrast, masks, trial/surrogate metadata, ROI
%   labels, and lag information.
%
%   Main fields:
%
%       correctedBySituation
%       yesMinusNoAKnower
%       yesMinusNoBKnower
%       yesMinusNoPrimary
%       correctedYESRoleMean
%       correctedNORoleMean
%       roleDifferenceYESminusNO
%       validSituationForContrast
%       validAKnowerContrast
%       validBKnowerContrast
%       validPrimaryContrast
%
% dyadTable
%   One row per dyad describing available situations, trial counts,
%   surrogate counts, role-specific contrast availability, and primary
%   contrast availability.
%
% qcTable
%   One row per Step 9 warning or exclusion reason.
%
% SAVED OUTPUTS
% -------------
%
%   Group_GCMI/Step9_HyperYESNO_surrogate_corrected_GCMI.mat
%   Group_GCMI/Step9_HyperYESNO_surrogate_corrected_GCMI_QC.xlsx
%
% The Excel workbook contains:
%
%   DyadSummary
%   QC
%   ContrastGuide
%   SituationGuide
%
% EXAMPLE
% -------
%
% [step9Data, dyadTable, qcTable] = ...
%     step9_calculate_surrogate_corrected_GCMI_HyperYESNO( ...
%     'E:\EEG_data_HyperYESNO');
%
% Author: Alejandro Perez
% HyperYESNO project, 2026


%% ========================================================================
% 1. Parse inputs
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

rootDir = char(string(rootDir));

defaultGroupFolder = fullfile(rootDir, 'Group_GCMI');
defaultStep8File = fullfile( ...
    defaultGroupFolder, ...
    'Step8_HyperYESNO_group_GCMI.mat');

parser = inputParser;
parser.FunctionName = mfilename;

addRequired(parser, 'rootDir', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'Step8File', defaultStep8File, ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'OutputFolder', defaultGroupFolder, ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'RequireBothRolesForPrimary', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'MinimumTrialsPerSituation', 2, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && x == round(x));

addParameter(parser, 'MinimumSurrogatesPerSituation', 1, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && x == round(x));

addParameter(parser, 'InternalTolerance', 1e-12, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);

addParameter(parser, 'SaveOutputs', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, rootDir, varargin{:});
options = parser.Results;

step8File = char(string(options.Step8File));
outputFolder = char(string(options.OutputFolder));

if options.SaveOutputs && ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end


%% ========================================================================
% 2. Load Step 8 data
% ========================================================================

if exist(step8File, 'file') ~= 2
    error('step9:MissingStep8File', ...
        'The Step 8 MAT file was not found:\n%s', step8File);
end

loadedStep8 = load(step8File);

if ~isfield(loadedStep8, 'groupData') || ...
        ~isstruct(loadedStep8.groupData)

    error('step9:MissingGroupData', ...
        ['The Step 8 MAT file did not contain a valid structure named ' ...
        'groupData.']);
end

groupData = loadedStep8.groupData;

if isfield(loadedStep8, 'fileTable')
    sourceFileTable = loadedStep8.fileTable;
else
    sourceFileTable = table();
end

if isfield(loadedStep8, 'qcTable')
    sourceStep8QCTable = loadedStep8.qcTable;
else
    sourceStep8QCTable = table();
end

clear loadedStep8


%% ========================================================================
% 3. Validate the Step 8 structure
% ========================================================================

requiredFields = { ...
    'gcmiObserved', ...
    'gcmiSurrogateMean', ...
    'gcmiSurrogateStd', ...
    'validMask', ...
    'numberOfTrials', ...
    'numberOfSurrogatesGenerated', ...
    'dyadNumbers', ...
    'situations', ...
    'roiLabelsKnower', ...
    'roiLabelsGuesser', ...
    'lagsSamples', ...
    'lagsMilliseconds', ...
    'samplingRate'};

missingFields = requiredFields(~isfield(groupData, requiredFields));

if ~isempty(missingFields)
    error('step9:MissingRequiredFields', ...
        'groupData is missing field(s): %s', ...
        strjoin(string(missingFields), ', '));
end

observed = double(groupData.gcmiObserved);
surrogateMean = double(groupData.gcmiSurrogateMean);
surrogateStd = double(groupData.gcmiSurrogateStd);

observedSize = size5(observed);
surrogateMeanSize = size5(surrogateMean);
surrogateStdSize = size5(surrogateStd);

if ~isequal(observedSize, surrogateMeanSize) || ...
        ~isequal(observedSize, surrogateStdSize)

    error('step9:ArrayDimensionMismatch', ...
        ['Observed GCMI, surrogate mean, and surrogate standard ' ...
        'deviation arrays must have identical dimensions.']);
end

numberOfKnowerROIs = observedSize(1);
numberOfGuesserROIs = observedSize(2);
numberOfLags = observedSize(3);
numberOfDyads = observedSize(4);
numberOfSituations = observedSize(5);

dyadNumbers = double(groupData.dyadNumbers(:)');
situations = string(groupData.situations(:)');

if numel(dyadNumbers) ~= numberOfDyads
    error('step9:DyadDimensionMismatch', ...
        ['The number of dyad labels did not match the fourth array ' ...
        'dimension.']);
end

if numel(situations) ~= numberOfSituations
    error('step9:SituationDimensionMismatch', ...
        ['The number of situation labels did not match the fifth array ' ...
        'dimension.']);
end

if numel(unique(situations)) ~= numel(situations)
    error('step9:DuplicateSituations', ...
        'groupData.situations contained duplicate labels.');
end

validMask = logical(groupData.validMask);

if ~isequal(size2(validMask), ...
        [numberOfDyads, numberOfSituations])

    error('step9:ValidMaskDimensionMismatch', ...
        ['groupData.validMask must have dimensions Dyad x Situation.']);
end

numberOfTrials = double(groupData.numberOfTrials);
numberOfSurrogatesGenerated = ...
    double(groupData.numberOfSurrogatesGenerated);

if ~isequal(size2(numberOfTrials), ...
        [numberOfDyads, numberOfSituations])

    error('step9:TrialCountDimensionMismatch', ...
        ['groupData.numberOfTrials must have dimensions Dyad x ' ...
        'Situation.']);
end

if ~isequal(size2(numberOfSurrogatesGenerated), ...
        [numberOfDyads, numberOfSituations])

    error('step9:SurrogateCountDimensionMismatch', ...
        ['groupData.numberOfSurrogatesGenerated must have dimensions ' ...
        'Dyad x Situation.']);
end

if numel(groupData.roiLabelsKnower) ~= numberOfKnowerROIs || ...
        numel(groupData.roiLabelsGuesser) ~= numberOfGuesserROIs

    error('step9:ROILabelDimensionMismatch', ...
        'ROI-label counts did not match the group-array dimensions.');
end

if numel(groupData.lagsMilliseconds) ~= numberOfLags || ...
        numel(groupData.lagsSamples) ~= numberOfLags

    error('step9:LagDimensionMismatch', ...
        'Lag-vector lengths did not match the third array dimension.');
end


%% ========================================================================
% 4. Identify the four required situations by name
% ========================================================================

requiredSituations = [ ...
    "YES_AKnower", ...
    "NO_AKnower", ...
    "YES_BKnower", ...
    "NO_BKnower"];

situationIndex = struct;

for requiredIndex = 1:numel(requiredSituations)

    currentSituation = requiredSituations(requiredIndex);
    matchingIndex = find(situations == currentSituation);

    if isempty(matchingIndex)
        error('step9:RequiredSituationMissing', ...
            'Required situation was absent: %s', currentSituation);
    end

    if numel(matchingIndex) > 1
        error('step9:RequiredSituationDuplicated', ...
            'Required situation appeared more than once: %s', ...
            currentSituation);
    end

    situationIndex.(char(currentSituation)) = matchingIndex;
end

indexYESA = situationIndex.YES_AKnower;
indexNOA = situationIndex.NO_AKnower;
indexYESB = situationIndex.YES_BKnower;
indexNOB = situationIndex.NO_BKnower;


%% ========================================================================
% 5. Calculate surrogate-corrected GCMI
% ========================================================================

correctedBySituation = observed - surrogateMean;

% Force all Step 8-invalid dyad x situation cells to NaN. This prevents an
% invalid file from contributing even if numerical values happen to remain
% in the array.
for dyadIndex = 1:numberOfDyads
    for currentSituationIndex = 1:numberOfSituations
        if ~validMask(dyadIndex, currentSituationIndex)
            correctedBySituation(:, :, :, ...
                dyadIndex, currentSituationIndex) = NaN;
        end
    end
end

% A situation can contribute to a contrast only if it passed Step 8 and
% meets the explicit minimum trial and unique-surrogate requirements.
validSituationForContrast = ...
    validMask & ...
    isfinite(numberOfTrials) & ...
    numberOfTrials >= options.MinimumTrialsPerSituation & ...
    isfinite(numberOfSurrogatesGenerated) & ...
    numberOfSurrogatesGenerated >= ...
        options.MinimumSurrogatesPerSituation;


%% ========================================================================
% 6. Calculate role-specific and primary contrasts
% ========================================================================

contrastArraySize = [ ...
    numberOfKnowerROIs, ...
    numberOfGuesserROIs, ...
    numberOfLags, ...
    numberOfDyads];

yesMinusNoAKnower = nan(contrastArraySize);
yesMinusNoBKnower = nan(contrastArraySize);
yesMinusNoPrimary = nan(contrastArraySize);

correctedYESRoleMean = nan(contrastArraySize);
correctedNORoleMean = nan(contrastArraySize);

% Difference between the two role-specific YES-NO effects. This is stored
% for later robustness analyses but is not the primary contrast.
roleDifferenceYESminusNO = nan(contrastArraySize);

validAKnowerContrast = ...
    validSituationForContrast(:, indexYESA) & ...
    validSituationForContrast(:, indexNOA);

validBKnowerContrast = ...
    validSituationForContrast(:, indexYESB) & ...
    validSituationForContrast(:, indexNOB);

validYESRoleMean = ...
    validSituationForContrast(:, indexYESA) & ...
    validSituationForContrast(:, indexYESB);

validNORoleMean = ...
    validSituationForContrast(:, indexNOA) & ...
    validSituationForContrast(:, indexNOB);

if options.RequireBothRolesForPrimary
    validPrimaryContrast = ...
        validAKnowerContrast & validBKnowerContrast;
else
    validPrimaryContrast = ...
        validAKnowerContrast | validBKnowerContrast;
end

for dyadIndex = 1:numberOfDyads

    if validAKnowerContrast(dyadIndex)

        yesMinusNoAKnower(:, :, :, dyadIndex) = ...
            correctedBySituation(:, :, :, dyadIndex, indexYESA) - ...
            correctedBySituation(:, :, :, dyadIndex, indexNOA);
    end

    if validBKnowerContrast(dyadIndex)

        yesMinusNoBKnower(:, :, :, dyadIndex) = ...
            correctedBySituation(:, :, :, dyadIndex, indexYESB) - ...
            correctedBySituation(:, :, :, dyadIndex, indexNOB);
    end

    if validYESRoleMean(dyadIndex)

        correctedYESRoleMean(:, :, :, dyadIndex) = ...
            0.5 .* ( ...
            correctedBySituation(:, :, :, dyadIndex, indexYESA) + ...
            correctedBySituation(:, :, :, dyadIndex, indexYESB));
    end

    if validNORoleMean(dyadIndex)

        correctedNORoleMean(:, :, :, dyadIndex) = ...
            0.5 .* ( ...
            correctedBySituation(:, :, :, dyadIndex, indexNOA) + ...
            correctedBySituation(:, :, :, dyadIndex, indexNOB));
    end

    if validAKnowerContrast(dyadIndex) && ...
            validBKnowerContrast(dyadIndex)

        yesMinusNoPrimary(:, :, :, dyadIndex) = ...
            0.5 .* ( ...
            yesMinusNoAKnower(:, :, :, dyadIndex) + ...
            yesMinusNoBKnower(:, :, :, dyadIndex));

        roleDifferenceYESminusNO(:, :, :, dyadIndex) = ...
            yesMinusNoAKnower(:, :, :, dyadIndex) - ...
            yesMinusNoBKnower(:, :, :, dyadIndex);

    elseif ~options.RequireBothRolesForPrimary

        if validAKnowerContrast(dyadIndex)
            yesMinusNoPrimary(:, :, :, dyadIndex) = ...
                yesMinusNoAKnower(:, :, :, dyadIndex);

        elseif validBKnowerContrast(dyadIndex)
            yesMinusNoPrimary(:, :, :, dyadIndex) = ...
                yesMinusNoBKnower(:, :, :, dyadIndex);
        end
    end
end


%% ========================================================================
% 7. Internal numerical consistency check
% ========================================================================

completeRoleDyads = ...
    validAKnowerContrast & validBKnowerContrast & ...
    validYESRoleMean & validNORoleMean;

internalMaximumDifference = 0;

for dyadIndex = find(completeRoleDyads(:))'

    primaryFromRoleContrasts = ...
        yesMinusNoPrimary(:, :, :, dyadIndex);

    primaryFromConditionMeans = ...
        correctedYESRoleMean(:, :, :, dyadIndex) - ...
        correctedNORoleMean(:, :, :, dyadIndex);

    currentDifference = maximum_absolute_difference( ...
        primaryFromRoleContrasts, ...
        primaryFromConditionMeans);

    internalMaximumDifference = max( ...
        internalMaximumDifference, currentDifference);
end

if internalMaximumDifference > options.InternalTolerance
    error('step9:InternalContrastMismatch', ...
        ['The two mathematically equivalent primary-contrast ' ...
        'calculations differed by up to %.12g.'], ...
        internalMaximumDifference);
end


%% ========================================================================
% 8. Create dyad summary and QC tables
% ========================================================================

dyadRows = struct([]);
qcRows = struct([]);

for dyadIndex = 1:numberOfDyads

    dyadNumber = dyadNumbers(dyadIndex);
    dyadName = sprintf('Dyad%02d', dyadNumber);

    row = struct;

    row.Dyad = string(dyadName);
    row.DyadNumber = dyadNumber;

    row.Valid_YES_AKnower = ...
        validSituationForContrast(dyadIndex, indexYESA);
    row.Valid_NO_AKnower = ...
        validSituationForContrast(dyadIndex, indexNOA);
    row.Valid_YES_BKnower = ...
        validSituationForContrast(dyadIndex, indexYESB);
    row.Valid_NO_BKnower = ...
        validSituationForContrast(dyadIndex, indexNOB);

    row.Trials_YES_AKnower = ...
        numberOfTrials(dyadIndex, indexYESA);
    row.Trials_NO_AKnower = ...
        numberOfTrials(dyadIndex, indexNOA);
    row.Trials_YES_BKnower = ...
        numberOfTrials(dyadIndex, indexYESB);
    row.Trials_NO_BKnower = ...
        numberOfTrials(dyadIndex, indexNOB);

    row.TrialImbalance_AKnower = ...
        row.Trials_YES_AKnower - row.Trials_NO_AKnower;
    row.TrialImbalance_BKnower = ...
        row.Trials_YES_BKnower - row.Trials_NO_BKnower;

    row.Surrogates_YES_AKnower = ...
        numberOfSurrogatesGenerated(dyadIndex, indexYESA);
    row.Surrogates_NO_AKnower = ...
        numberOfSurrogatesGenerated(dyadIndex, indexNOA);
    row.Surrogates_YES_BKnower = ...
        numberOfSurrogatesGenerated(dyadIndex, indexYESB);
    row.Surrogates_NO_BKnower = ...
        numberOfSurrogatesGenerated(dyadIndex, indexNOB);

    row.AKnowerContrastAvailable = ...
        validAKnowerContrast(dyadIndex);
    row.BKnowerContrastAvailable = ...
        validBKnowerContrast(dyadIndex);
    row.PrimaryContrastAvailable = ...
        validPrimaryContrast(dyadIndex);

    row.NumberValidSituations = sum( ...
        validSituationForContrast(dyadIndex, ...
        [indexYESA, indexNOA, indexYESB, indexNOB]));

    row.PrimaryContrastFinitePercent = ...
        finite_percentage( ...
        yesMinusNoPrimary(:, :, :, dyadIndex));

    dyadRows = append_struct(dyadRows, row);

    % Record why individual situations cannot contribute.
    requiredIndices = [indexYESA, indexNOA, indexYESB, indexNOB];

    for requiredIndex = requiredIndices

        situationName = situations(requiredIndex);

        if ~validMask(dyadIndex, requiredIndex)

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "Step8InvalidSituation", ...
                ['The situation was invalid or missing in Step 8 and ' ...
                'could not contribute to Step 9 contrasts.']);

        elseif numberOfTrials(dyadIndex, requiredIndex) < ...
                options.MinimumTrialsPerSituation

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "BelowMinimumTrialCount", ...
                sprintf(['Found %d trials; Step 9 required at least %d ' ...
                'for a contrast.'], ...
                numberOfTrials(dyadIndex, requiredIndex), ...
                options.MinimumTrialsPerSituation));

        elseif numberOfSurrogatesGenerated(dyadIndex, requiredIndex) < ...
                options.MinimumSurrogatesPerSituation

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "BelowMinimumSurrogateCount", ...
                sprintf(['Found %d unique surrogates; Step 9 required ' ...
                'at least %d for a contrast.'], ...
                numberOfSurrogatesGenerated( ...
                dyadIndex, requiredIndex), ...
                options.MinimumSurrogatesPerSituation));
        end
    end

    if ~validAKnowerContrast(dyadIndex)

        qcRows = add_qc(qcRows, ...
            dyadName, dyadNumber, "A-Knower", ...
            "WARNING", "AKnowerContrastUnavailable", ...
            ['Both YES_AKnower and NO_AKnower were required for the ' ...
            'A-Knower YES-NO contrast.']);
    end

    if ~validBKnowerContrast(dyadIndex)

        qcRows = add_qc(qcRows, ...
            dyadName, dyadNumber, "B-Knower", ...
            "WARNING", "BKnowerContrastUnavailable", ...
            ['Both YES_BKnower and NO_BKnower were required for the ' ...
            'B-Knower YES-NO contrast.']);
    end

    if ~validPrimaryContrast(dyadIndex)

        if options.RequireBothRolesForPrimary
            details = [ ...
                'The primary contrast required both role-specific ' ...
                'YES-NO contrasts.'];
        else
            details = [ ...
                'Neither role-specific YES-NO contrast was available.'];
        end

        qcRows = add_qc(qcRows, ...
            dyadName, dyadNumber, "Primary", ...
            "WARNING", "PrimaryContrastUnavailable", details);
    end

    if validPrimaryContrast(dyadIndex) && ...
            row.PrimaryContrastFinitePercent < 100

        qcRows = add_qc(qcRows, ...
            dyadName, dyadNumber, "Primary", ...
            "WARNING", "NonfinitePrimaryContrastValues", ...
            sprintf('Finite primary contrast values: %.6f%%.', ...
            row.PrimaryContrastFinitePercent));
    end
end

dyadTable = struct_array_to_table(dyadRows);
qcTable = struct_array_to_table(qcRows);

if ~isempty(dyadTable)
    dyadTable = sortrows(dyadTable, 'DyadNumber');
end

if ~isempty(qcTable)
    qcTable = sortrows(qcTable, ...
        {'DyadNumber', 'SituationOrContrast', 'Issue'});
end


%% ========================================================================
% 9. Assemble Step 9 output structure
% ========================================================================

step9Data = struct;

step9Data.step = 9;
step9Data.description = ...
    ['Surrogate-corrected lagged GCMI and within-dyad ' ...
    'YES-NO contrasts'];

step9Data.sourceStep8File = string(step8File);
step9Data.rootDir = string(rootDir);
step9Data.outputFolder = string(outputFolder);

step9Data.arrayDimensionOrderSituation = ...
    'KnowerROI x GuesserROI x Lag x Dyad x Situation';

step9Data.arrayDimensionOrderContrast = ...
    'KnowerROI x GuesserROI x Lag x Dyad';

step9Data.lagConvention = [ ...
    'negative lag = Knower precedes Guesser; ', ...
    'positive lag = Guesser precedes Knower'];

step9Data.correctionDefinition = ...
    'corrected GCMI = observed GCMI - mean surrogate GCMI';

step9Data.AKnowerContrastDefinition = ...
    'corrected YES_AKnower - corrected NO_AKnower';

step9Data.BKnowerContrastDefinition = ...
    'corrected YES_BKnower - corrected NO_BKnower';

step9Data.primaryContrastDefinition = ...
    ['0.5 * [(YES_AKnower - NO_AKnower) + ' ...
    '(YES_BKnower - NO_BKnower)]'];

step9Data.primaryContrastRequiresBothRoles = ...
    options.RequireBothRolesForPrimary;

step9Data.dyadNumbers = dyadNumbers;
step9Data.dyadNames = string(compose('Dyad%02d', dyadNumbers));
step9Data.situations = situations;
step9Data.situationIndices = situationIndex;

step9Data.roiLabelsKnower = ...
    string(groupData.roiLabelsKnower(:));
step9Data.roiLabelsGuesser = ...
    string(groupData.roiLabelsGuesser(:));

step9Data.lagsSamples = ...
    double(groupData.lagsSamples(:)');
step9Data.lagsMilliseconds = ...
    double(groupData.lagsMilliseconds(:)');
step9Data.samplingRate = double(groupData.samplingRate);

step9Data.gcmiObserved = observed;
step9Data.gcmiSurrogateMean = surrogateMean;
step9Data.gcmiSurrogateStd = surrogateStd;
step9Data.correctedBySituation = correctedBySituation;

step9Data.yesMinusNoAKnower = yesMinusNoAKnower;
step9Data.yesMinusNoBKnower = yesMinusNoBKnower;
step9Data.yesMinusNoPrimary = yesMinusNoPrimary;

step9Data.correctedYESRoleMean = correctedYESRoleMean;
step9Data.correctedNORoleMean = correctedNORoleMean;
step9Data.roleDifferenceYESminusNO = ...
    roleDifferenceYESminusNO;

step9Data.validStep8Situation = validMask;
step9Data.validSituationForContrast = ...
    validSituationForContrast;

step9Data.validAKnowerContrast = validAKnowerContrast;
step9Data.validBKnowerContrast = validBKnowerContrast;
step9Data.validYESRoleMean = validYESRoleMean;
step9Data.validNORoleMean = validNORoleMean;
step9Data.validPrimaryContrast = validPrimaryContrast;

step9Data.primaryDyadIndices = ...
    find(validPrimaryContrast);
step9Data.primaryDyadNumbers = ...
    dyadNumbers(validPrimaryContrast);
step9Data.numberOfPrimaryDyads = ...
    sum(validPrimaryContrast);

step9Data.numberOfTrials = numberOfTrials;
step9Data.numberOfSurrogatesGenerated = ...
    numberOfSurrogatesGenerated;

step9Data.internalMaximumContrastDifference = ...
    internalMaximumDifference;

step9Data.settings = options;
step9Data.created = datestr(now, 30);
step9Data.functionName = mfilename;


%% ========================================================================
% 10. Save outputs
% ========================================================================

if options.SaveOutputs

    matFile = fullfile( ...
        outputFolder, ...
        'Step9_HyperYESNO_surrogate_corrected_GCMI.mat');

    save(matFile, ...
        'step9Data', ...
        'dyadTable', ...
        'qcTable', ...
        'sourceFileTable', ...
        'sourceStep8QCTable', ...
        '-v7.3');

    excelFile = fullfile( ...
        outputFolder, ...
        'Step9_HyperYESNO_surrogate_corrected_GCMI_QC.xlsx');

    if exist(excelFile, 'file') == 2
        delete(excelFile);
    end

    write_table_safely(dyadTable, excelFile, 'DyadSummary');
    write_table_safely(qcTable, excelFile, 'QC');

    contrastGuide = table( ...
        [ ...
        "correctedBySituation"; ...
        "yesMinusNoAKnower"; ...
        "yesMinusNoBKnower"; ...
        "yesMinusNoPrimary"; ...
        "correctedYESRoleMean"; ...
        "correctedNORoleMean"; ...
        "roleDifferenceYESminusNO"], ...
        [ ...
        "Observed GCMI minus mean surrogate GCMI"; ...
        "YES_AKnower minus NO_AKnower"; ...
        "YES_BKnower minus NO_BKnower"; ...
        "Equal-weighted mean of the two role-specific YES-NO contrasts"; ...
        "Equal-weighted corrected YES value across A- and B-Knower"; ...
        "Equal-weighted corrected NO value across A- and B-Knower"; ...
        "A-Knower YES-NO contrast minus B-Knower YES-NO contrast"], ...
        [ ...
        string(step9Data.arrayDimensionOrderSituation); ...
        repmat(string(step9Data.arrayDimensionOrderContrast), 6, 1)], ...
        'VariableNames', { ...
        'Array', ...
        'Definition', ...
        'DimensionOrder'});

    writetable(contrastGuide, excelFile, ...
        'Sheet', 'ContrastGuide');

    situationGuide = table( ...
        situations(:), ...
        (1:numberOfSituations)', ...
        'VariableNames', {'Situation', 'SituationIndex'});

    writetable(situationGuide, excelFile, ...
        'Sheet', 'SituationGuide');

    step9Data.savedMatFile = string(matFile);
    step9Data.savedQCWorkbook = string(excelFile);

    % Save again so that the output paths are present inside step9Data.
    save(matFile, ...
        'step9Data', ...
        'dyadTable', ...
        'qcTable', ...
        'sourceFileTable', ...
        'sourceStep8QCTable', ...
        '-v7.3');
end


%% ========================================================================
% 11. Final report
% ========================================================================

if options.Verbose

    fprintf('\n============================================================\n');
    fprintf('Step 9 surrogate correction completed.\n');
    fprintf('Dyads in Step 8 arrays:          %d\n', numberOfDyads);
    fprintf('Valid A-Knower contrasts:        %d\n', ...
        sum(validAKnowerContrast));
    fprintf('Valid B-Knower contrasts:        %d\n', ...
        sum(validBKnowerContrast));
    fprintf('Valid primary dyad contrasts:    %d\n', ...
        sum(validPrimaryContrast));
    fprintf('Primary requires both roles:     %d\n', ...
        options.RequireBothRolesForPrimary);
    fprintf('Internal equivalence difference: %.12g\n', ...
        internalMaximumDifference);
    fprintf('Step 9 QC entries:               %d\n', ...
        height(qcTable));

    if options.SaveOutputs
        fprintf('MAT output:                       %s\n', matFile);
        fprintf('QC workbook:                      %s\n', excelFile);
    end

    fprintf('============================================================\n');
end

end


%% ========================================================================
function outputSize = size5(inputArray)
% SIZE5
% Return exactly the first five array dimensions.

outputSize = size(inputArray);
outputSize(end + 1:5) = 1;
outputSize = outputSize(1:5);

end


%% ========================================================================
function outputSize = size2(inputArray)
% SIZE2
% Return exactly the first two array dimensions.

outputSize = size(inputArray);
outputSize(end + 1:2) = 1;
outputSize = outputSize(1:2);

end


%% ========================================================================
function maximumDifference = maximum_absolute_difference(a, b)
% MAXIMUM_ABSOLUTE_DIFFERENCE
% Compare arrays while treating matching NaN positions as equal.

if ~isequal(size(a), size(b))
    maximumDifference = Inf;
    return
end

if any(xor(isnan(a), isnan(b)), 'all')
    maximumDifference = Inf;
    return
end

difference = abs(a - b);
difference(isnan(a) & isnan(b)) = 0;

finiteDifference = difference(isfinite(difference));

if isempty(finiteDifference)
    maximumDifference = 0;
else
    maximumDifference = max(finiteDifference);
end

end


%% ========================================================================
function percent = finite_percentage(inputArray)
% FINITE_PERCENTAGE
% Percentage of finite values in an array.

if isempty(inputArray)
    percent = NaN;
    return
end

percent = 100 .* sum(isfinite(inputArray(:))) ./ numel(inputArray);

end


%% ========================================================================
function qcRows = add_qc( ...
    qcRows, dyadName, dyadNumber, situationOrContrast, ...
    severity, issue, details)
% ADD_QC
% Append one fixed-type QC row. No cell2table or cell2mat conversions are
% used.

row = struct;

row.Dyad = string(dyadName);
row.DyadNumber = double(dyadNumber);
row.SituationOrContrast = string(situationOrContrast);
row.Severity = string(severity);
row.Issue = string(issue);
row.Details = string(details);

qcRows = append_struct(qcRows, row);

end


%% ========================================================================
function output = append_struct(output, row)
% APPEND_STRUCT
% Append one structure with fixed fields.

if isempty(output)
    output = row;
else
    output(end + 1, 1) = row;
end

end


%% ========================================================================
function T = struct_array_to_table(rows)
% STRUCT_ARRAY_TO_TABLE
% Convert a structure array to a table without cell-array conversions.

if isempty(rows)
    T = table();
else
    T = struct2table(rows);
end

end


%% ========================================================================
function write_table_safely(T, fileName, sheetName)
% WRITE_TABLE_SAFELY
% Ensure that an empty table still produces a valid worksheet.

if width(T) == 0
    T = table("No entries", ...
        'VariableNames', {'Message'});
end

writetable(T, fileName, 'Sheet', sheetName);

end
