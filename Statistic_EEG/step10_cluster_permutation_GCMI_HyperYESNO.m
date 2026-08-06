function [step10Data, clusterTable, qcTable] = ...
    step10_cluster_permutation_GCMI_HyperYESNO(rootDir, varargin)
% STEP10_CLUSTER_PERMUTATION_GCMI_HYPERYESNO
% Group-level lag-cluster permutation test for the primary HyperYESNO GCMI
% contrast.
%
% This function follows:
%
%   step9_calculate_surrogate_corrected_GCMI_HyperYESNO.m
%
% The input to the principal analysis is:
%
%   step9Data.yesMinusNoPrimary
%
% containing one surrogate-corrected YES-minus-NO contrast for each dyad:
%
%   0.5 * [(YES_AKnower - NO_AKnower) + ...
%          (YES_BKnower - NO_BKnower)]
%
% The statistical unit is the dyad.
%
% STATISTICAL APPROACH
% --------------------
%
% 1. A one-sample t statistic against zero is calculated at every:
%
%       Knower ROI x Guesser ROI x Lag
%
% 2. Candidate clusters are formed across adjacent lag samples within each
%    ROI pair. No spatial adjacency is imposed between ROI pairs.
%
% 3. Positive and negative clusters are identified separately using a
%    two-sided cluster-forming threshold.
%
% 4. Cluster mass is the absolute value of the sum of t statistics within
%    the cluster.
%
% 5. Under the null hypothesis, the sign of the complete YES-minus-NO
%    contrast is independently flipped for each dyad. The same sign is
%    applied to every ROI pair and lag within that dyad.
%
% 6. For each permutation, only the largest cluster mass across all ROI
%    pairs, all lags, and both signs is retained.
%
% 7. Observed clusters are compared with this maximum-cluster null
%    distribution, controlling the family-wise error rate across the full
%    20 x 20 x 21 analysis.
%
% SIGN-PATTERN GENERATION
% -----------------------
%
% The generator prevents duplicate sign patterns. Because a sign pattern
% and its global inverse produce the same maximum absolute cluster mass in
% a two-sided test, the first dyad is fixed to +1. The all-positive pattern
% corresponding to the observed data is excluded from the null sample.
%
% When the requested number of permutations exceeds the number of unique
% two-sided sign patterns, all available unique patterns are used.
%
% ARRAY DIMENSIONS
% ----------------
%
% Input contrast:
%
%   Knower ROI x Guesser ROI x Lag x Dyad
%
% Group statistical maps:
%
%   Knower ROI x Guesser ROI x Lag
%
% LAG CONVENTION
% --------------
%
%   negative lag = Knower precedes Guesser
%   positive lag = Guesser precedes Knower
%
% REQUIRED INPUT
% --------------
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
% 'Step9File'
%   Step 9 MAT file.
%
%   Default:
%       rootDir/Group_GCMI/
%       Step9_HyperYESNO_surrogate_corrected_GCMI.mat
%
% 'OutputFolder'
%   Folder used to save Step 10 outputs.
%
%   Default:
%       rootDir/Group_GCMI
%
% 'NumPermutations'
%   Requested number of unique sign-flip permutations.
%
%   Default:
%       10000
%
% 'ClusterFormingAlpha'
%   Two-sided pointwise threshold used to form lag clusters.
%
%   Default:
%       0.05
%
% 'FamilyWiseAlpha'
%   Cluster-corrected significance threshold.
%
%   Default:
%       0.05
%
% 'RandomSeed'
%   Random-number seed used to generate sign patterns.
%
%   Default:
%       20260805
%
% 'PermutationBatchSize'
%   Number of permutations processed together when calculating t maps.
%   Larger values can improve speed but require more memory.
%
%   Default:
%       200
%
% 'MinimumDyads'
%   Minimum number of complete dyads required.
%
%   Default:
%       10
%
% 'SaveOutputs'
%   Save the MAT file and Excel workbook.
%
%   Default:
%       true
%
% 'SaveFigures'
%   Generate and save group figures.
%
%   Default:
%       true
%
% 'FigureVisible'
%   Figure visibility: 'on' or 'off'.
%
%   Default:
%       'off'
%
% 'FigureFormat'
%   Figure output format: 'png', 'pdf', or 'svg'.
%
%   Default:
%       'png'
%
% 'Verbose'
%   Print progress information.
%
%   Default:
%       true
%
% OUTPUTS
% -------
%
% step10Data
%   Structure containing:
%
%       analysisData
%       analysisDyadNumbers
%       groupMean
%       groupSEM
%       observedT
%       pointwiseParametricP
%       clusterFormingThresholdT
%       nullMaximumClusterMass
%       significantClusterMask
%       minimumClusterPByROIPair
%       signedPeakTByROIPair
%       signPatterns
%
% clusterTable
%   One row per observed supra-threshold lag cluster.
%
% qcTable
%   Dyads excluded because their primary contrast was unavailable or
%   contained nonfinite values.
%
% SAVED OUTPUTS
% -------------
%
%   Group_GCMI/Step10_HyperYESNO_primary_cluster_permutation.mat
%   Group_GCMI/Step10_HyperYESNO_primary_cluster_permutation.xlsx
%
% Figures are saved in:
%
%   Group_GCMI/Step10_Figures
%
% EXAMPLE
% -------
%
% [step10Data, clusterTable, qcTable] = ...
%     step10_cluster_permutation_GCMI_HyperYESNO( ...
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

defaultOutputFolder = fullfile(rootDir, 'Group_GCMI');
defaultStep9File = fullfile( ...
    defaultOutputFolder, ...
    'Step9_HyperYESNO_surrogate_corrected_GCMI.mat');

parser = inputParser;
parser.FunctionName = mfilename;

addRequired(parser, 'rootDir', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'Step9File', defaultStep9File, ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'OutputFolder', defaultOutputFolder, ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'NumPermutations', 10000, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && x == round(x));

addParameter(parser, 'ClusterFormingAlpha', 0.05, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x > 0 && x < 1);

addParameter(parser, 'FamilyWiseAlpha', 0.05, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x > 0 && x < 1);

addParameter(parser, 'RandomSeed', 20260805, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && x == round(x));

addParameter(parser, 'PermutationBatchSize', 200, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 1 && x == round(x));

addParameter(parser, 'MinimumDyads', 10, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 2 && x == round(x));

addParameter(parser, 'SaveOutputs', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'SaveFigures', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'FigureVisible', 'off', ...
    @(x) any(strcmpi(string(x), ["on", "off"])));

addParameter(parser, 'FigureFormat', 'png', ...
    @(x) any(strcmpi(string(x), ["png", "pdf", "svg"])));

addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, rootDir, varargin{:});
options = parser.Results;

step9File = char(string(options.Step9File));
outputFolder = char(string(options.OutputFolder));
figureVisible = char(lower(string(options.FigureVisible)));
figureFormat = char(lower(string(options.FigureFormat)));

if (options.SaveOutputs || options.SaveFigures) && ...
        ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

figureFolder = fullfile(outputFolder, 'Step10_Figures');

if options.SaveFigures && ~exist(figureFolder, 'dir')
    mkdir(figureFolder);
end


%% ========================================================================
% 2. Load Step 9
% ========================================================================

if exist(step9File, 'file') ~= 2
    error('step10:MissingStep9File', ...
        'The Step 9 MAT file was not found:\n%s', step9File);
end

loadedStep9 = load(step9File);

if ~isfield(loadedStep9, 'step9Data') || ...
        ~isstruct(loadedStep9.step9Data)

    error('step10:MissingStep9Data', ...
        ['The Step 9 MAT file did not contain a valid structure named ' ...
        'step9Data.']);
end

step9Data = loadedStep9.step9Data;

if isfield(loadedStep9, 'dyadTable')
    sourceStep9DyadTable = loadedStep9.dyadTable;
else
    sourceStep9DyadTable = table();
end

if isfield(loadedStep9, 'qcTable')
    sourceStep9QCTable = loadedStep9.qcTable;
else
    sourceStep9QCTable = table();
end

clear loadedStep9


%% ========================================================================
% 3. Validate Step 9 fields
% ========================================================================

requiredFields = { ...
    'yesMinusNoPrimary', ...
    'validPrimaryContrast', ...
    'dyadNumbers', ...
    'roiLabelsKnower', ...
    'roiLabelsGuesser', ...
    'lagsSamples', ...
    'lagsMilliseconds', ...
    'samplingRate'};

missingFields = requiredFields(~isfield(step9Data, requiredFields));

if ~isempty(missingFields)
    error('step10:MissingRequiredFields', ...
        'step9Data is missing field(s): %s', ...
        strjoin(string(missingFields), ', '));
end

primaryContrast = double(step9Data.yesMinusNoPrimary);
contrastSize = size4(primaryContrast);

numberOfKnowerROIs = contrastSize(1);
numberOfGuesserROIs = contrastSize(2);
numberOfLags = contrastSize(3);
numberOfStep9Dyads = contrastSize(4);

dyadNumbers = double(step9Data.dyadNumbers(:)');
validPrimaryContrast = ...
    logical(step9Data.validPrimaryContrast(:));

if numel(dyadNumbers) ~= numberOfStep9Dyads
    error('step10:DyadDimensionMismatch', ...
        ['The dyad-number vector did not match the fourth dimension of ' ...
        'yesMinusNoPrimary.']);
end

if numel(validPrimaryContrast) ~= numberOfStep9Dyads
    error('step10:ValidityDimensionMismatch', ...
        ['validPrimaryContrast did not match the fourth dimension of ' ...
        'yesMinusNoPrimary.']);
end

roiLabelsKnower = string(step9Data.roiLabelsKnower(:));
roiLabelsGuesser = string(step9Data.roiLabelsGuesser(:));
lagsSamples = double(step9Data.lagsSamples(:)');
lagsMilliseconds = double(step9Data.lagsMilliseconds(:)');

if numel(roiLabelsKnower) ~= numberOfKnowerROIs || ...
        numel(roiLabelsGuesser) ~= numberOfGuesserROIs

    error('step10:ROILabelDimensionMismatch', ...
        'ROI-label counts did not match the contrast dimensions.');
end

if numel(lagsSamples) ~= numberOfLags || ...
        numel(lagsMilliseconds) ~= numberOfLags

    error('step10:LagDimensionMismatch', ...
        'Lag-vector lengths did not match the contrast dimensions.');
end

if numel(unique(lagsMilliseconds)) ~= numberOfLags
    error('step10:DuplicateLags', ...
        'The lag vector contained duplicate values.');
end

if any(diff(lagsMilliseconds) <= 0)
    error('step10:NonascendingLags', ...
        'Lags must be ordered from negative to positive.');
end


%% ========================================================================
% 4. Select complete dyads
% ========================================================================

finiteDyadMask = false(numberOfStep9Dyads, 1);

for dyadIndex = 1:numberOfStep9Dyads
    finiteDyadMask(dyadIndex) = ...
        all(isfinite(primaryContrast(:, :, :, dyadIndex)), 'all');
end

analysisDyadMask = validPrimaryContrast & finiteDyadMask;
analysisDyadIndices = find(analysisDyadMask);
analysisDyadNumbers = dyadNumbers(analysisDyadMask);

numberOfDyads = numel(analysisDyadIndices);

qcRows = struct([]);

for dyadIndex = 1:numberOfStep9Dyads

    dyadNumber = dyadNumbers(dyadIndex);
    dyadName = sprintf('Dyad%02d', dyadNumber);

    if ~validPrimaryContrast(dyadIndex)

        qcRows = add_qc(qcRows, ...
            dyadName, dyadNumber, ...
            "PrimaryContrastUnavailable", ...
            ['Step 9 did not provide a valid equal-weighted primary ' ...
            'YES-minus-NO contrast.']);

    elseif ~finiteDyadMask(dyadIndex)

        finitePercent = 100 .* ...
            sum(isfinite(primaryContrast(:, :, :, dyadIndex)), 'all') ./ ...
            (numberOfKnowerROIs * numberOfGuesserROIs * numberOfLags);

        qcRows = add_qc(qcRows, ...
            dyadName, dyadNumber, ...
            "NonfinitePrimaryContrast", ...
            sprintf(['The primary contrast contained nonfinite values ' ...
            '(%.6f%% finite) and the dyad was excluded.'], ...
            finitePercent));
    end
end

if numberOfDyads < options.MinimumDyads
    error('step10:TooFewDyads', ...
        ['Only %d complete dyads were available. At least %d were ' ...
        'required.'], numberOfDyads, options.MinimumDyads);
end

analysisData = primaryContrast(:, :, :, analysisDyadMask);

% Flatten the ROI-pair and lag dimensions for efficient matrix operations.
numberOfTests = ...
    numberOfKnowerROIs * numberOfGuesserROIs * numberOfLags;

dataMatrix = reshape(analysisData, numberOfTests, numberOfDyads);

if any(~isfinite(dataMatrix), 'all')
    error('step10:UnexpectedNonfiniteAnalysisData', ...
        'Nonfinite values remained after complete-dyad selection.');
end


%% ========================================================================
% 5. Observed group statistics
% ========================================================================

degreesOfFreedom = numberOfDyads - 1;

sumData = sum(dataMatrix, 2);
sumSquaresData = sum(dataMatrix .^ 2, 2);

[observedTVector, groupMeanVector, groupSDVector] = ...
    one_sample_t_from_sums( ...
    sumData, sumSquaresData, numberOfDyads);

groupSEMVector = groupSDVector ./ sqrt(numberOfDyads);

observedT = reshape(observedTVector, ...
    numberOfKnowerROIs, numberOfGuesserROIs, numberOfLags);

groupMean = reshape(groupMeanVector, ...
    numberOfKnowerROIs, numberOfGuesserROIs, numberOfLags);

groupSD = reshape(groupSDVector, ...
    numberOfKnowerROIs, numberOfGuesserROIs, numberOfLags);

groupSEM = reshape(groupSEMVector, ...
    numberOfKnowerROIs, numberOfGuesserROIs, numberOfLags);

pointwiseParametricP = ...
    student_t_two_sided_p(observedT, degreesOfFreedom);

clusterFormingThresholdT = ...
    student_t_two_sided_critical( ...
    options.ClusterFormingAlpha, degreesOfFreedom);

[observedClusters, observedMaximumClusterMass] = ...
    collect_lag_clusters( ...
    observedT, clusterFormingThresholdT, lagsMilliseconds);


%% ========================================================================
% 6. Generate unique two-sided sign patterns
% ========================================================================

[signPatterns, signGenerationInfo] = ...
    generate_unique_sign_patterns( ...
    numberOfDyads, ...
    options.NumPermutations, ...
    options.RandomSeed);

numberOfPermutations = size(signPatterns, 1);

if options.Verbose
    fprintf('\nGenerated %d unique sign patterns (%s).\n', ...
        numberOfPermutations, signGenerationInfo.Mode);
end


%% ========================================================================
% 7. Permutation maximum-cluster distribution
% ========================================================================

nullMaximumClusterMass = zeros(numberOfPermutations, 1);

batchSize = min(options.PermutationBatchSize, numberOfPermutations);
numberOfBatches = ceil(numberOfPermutations / batchSize);

for batchIndex = 1:numberOfBatches

    firstPermutation = (batchIndex - 1) * batchSize + 1;
    lastPermutation = min( ...
        batchIndex * batchSize, numberOfPermutations);

    currentIndices = firstPermutation:lastPermutation;

    % signPatterns is Permutation x Dyad. Matrix multiplication computes
    % the sign-flipped sum for every test and permutation in the batch.
    currentSigns = signPatterns(currentIndices, :)';
    permutedSums = dataMatrix * currentSigns;

    numberInBatch = numel(currentIndices);
    permutedT = t_from_signed_sums( ...
        permutedSums, ...
        sumSquaresData, ...
        numberOfDyads);

    for localPermutationIndex = 1:numberInBatch

        currentTMap = reshape( ...
            permutedT(:, localPermutationIndex), ...
            numberOfKnowerROIs, ...
            numberOfGuesserROIs, ...
            numberOfLags);

        nullMaximumClusterMass( ...
            currentIndices(localPermutationIndex)) = ...
            maximum_lag_cluster_mass( ...
            currentTMap, clusterFormingThresholdT);
    end

    if options.Verbose
        fprintf('Permutation batch %d of %d completed (%d/%d).\n', ...
            batchIndex, numberOfBatches, ...
            lastPermutation, numberOfPermutations);
    end
end


%% ========================================================================
% 8. Correct observed clusters
% ========================================================================

significantClusterMask = false( ...
    numberOfKnowerROIs, numberOfGuesserROIs, numberOfLags);

minimumClusterPByROIPair = ones( ...
    numberOfKnowerROIs, numberOfGuesserROIs);

significantPairMask = false( ...
    numberOfKnowerROIs, numberOfGuesserROIs);

clusterRows = struct([]);

for clusterIndex = 1:numel(observedClusters)

    currentCluster = observedClusters(clusterIndex);

    correctedP = ...
        (1 + sum(nullMaximumClusterMass >= ...
        currentCluster.AbsoluteMass)) ./ ...
        (numberOfPermutations + 1);

    isSignificant = correctedP <= options.FamilyWiseAlpha;

    roiKnowerIndex = currentCluster.KnowerROIIndex;
    roiGuesserIndex = currentCluster.GuesserROIIndex;
    lagIndices = ...
        currentCluster.StartLagIndex:currentCluster.EndLagIndex;

    minimumClusterPByROIPair( ...
        roiKnowerIndex, roiGuesserIndex) = min( ...
        minimumClusterPByROIPair( ...
        roiKnowerIndex, roiGuesserIndex), ...
        correctedP);

    if isSignificant
        significantClusterMask( ...
            roiKnowerIndex, roiGuesserIndex, lagIndices) = true;

        significantPairMask( ...
            roiKnowerIndex, roiGuesserIndex) = true;
    end

    clusterMeanEffect = mean( ...
        groupMean(roiKnowerIndex, roiGuesserIndex, lagIndices), ...
        'all');

    peakEffect = groupMean( ...
        roiKnowerIndex, ...
        roiGuesserIndex, ...
        currentCluster.PeakLagIndex);

    row = struct;

    row.ClusterID = double(clusterIndex);
    row.KnowerROIIndex = double(roiKnowerIndex);
    row.KnowerROI = roiLabelsKnower(roiKnowerIndex);
    row.GuesserROIIndex = double(roiGuesserIndex);
    row.GuesserROI = roiLabelsGuesser(roiGuesserIndex);

    row.ClusterSign = currentCluster.Sign;
    row.StartLagIndex = double(currentCluster.StartLagIndex);
    row.EndLagIndex = double(currentCluster.EndLagIndex);
    row.StartLagMs = double(currentCluster.StartLagMs);
    row.EndLagMs = double(currentCluster.EndLagMs);
    row.NumberOfLags = double(currentCluster.NumberOfLags);

    row.SignedClusterMass = double(currentCluster.SignedMass);
    row.AbsoluteClusterMass = double(currentCluster.AbsoluteMass);
    row.PeakT = double(currentCluster.PeakT);
    row.PeakLagIndex = double(currentCluster.PeakLagIndex);
    row.PeakLagMs = double(currentCluster.PeakLagMs);

    row.MeanEffectWithinCluster = double(clusterMeanEffect);
    row.EffectAtPeakLag = double(peakEffect);

    row.ClusterCorrectedP = double(correctedP);
    row.SignificantFWER = logical(isSignificant);
    row.NumberOfDyads = double(numberOfDyads);

    clusterRows = append_struct(clusterRows, row);
end

clusterTable = struct_array_to_table(clusterRows);

if ~isempty(clusterTable)
    clusterTable = sortrows(clusterTable, ...
        {'ClusterCorrectedP', 'AbsoluteClusterMass'}, ...
        {'ascend', 'descend'});
end


%% ========================================================================
% 9. Descriptive ROI-pair maps
% ========================================================================

signedPeakTByROIPair = zeros( ...
    numberOfKnowerROIs, numberOfGuesserROIs);

peakLagMsByROIPair = nan( ...
    numberOfKnowerROIs, numberOfGuesserROIs);

for knowerROIIndex = 1:numberOfKnowerROIs
    for guesserROIIndex = 1:numberOfGuesserROIs

        currentT = squeeze(observedT( ...
            knowerROIIndex, guesserROIIndex, :));

        [~, peakIndex] = max(abs(currentT));

        signedPeakTByROIPair( ...
            knowerROIIndex, guesserROIIndex) = ...
            currentT(peakIndex);

        peakLagMsByROIPair( ...
            knowerROIIndex, guesserROIIndex) = ...
            lagsMilliseconds(peakIndex);
    end
end

negativeLog10MinimumClusterP = ...
    -log10(max(minimumClusterPByROIPair, realmin));


%% ========================================================================
% 10. Create Step 10 structure
% ========================================================================

step10Data = struct;

step10Data.step = 10;
step10Data.description = ...
    ['Two-sided dyad sign-flip lag-cluster permutation test of the ' ...
    'primary surrogate-corrected YES-minus-NO GCMI contrast'];

step10Data.sourceStep9File = string(step9File);
step10Data.rootDir = string(rootDir);
step10Data.outputFolder = string(outputFolder);

step10Data.inputContrastField = "yesMinusNoPrimary";
step10Data.inputContrastDefinition = ...
    string(step9Data.primaryContrastDefinition);

step10Data.arrayDimensionOrderInput = ...
    'KnowerROI x GuesserROI x Lag x Dyad';

step10Data.arrayDimensionOrderMaps = ...
    'KnowerROI x GuesserROI x Lag';

step10Data.clusterAdjacency = ...
    'Adjacent lag samples within each ROI pair only';

step10Data.multipleComparisonControl = ...
    ['Maximum absolute cluster mass across all ROI pairs, all lags, ' ...
    'and both signs'];

step10Data.lagConvention = ...
    string(step9Data.lagConvention);

step10Data.roiLabelsKnower = roiLabelsKnower;
step10Data.roiLabelsGuesser = roiLabelsGuesser;
step10Data.lagsSamples = lagsSamples;
step10Data.lagsMilliseconds = lagsMilliseconds;
step10Data.samplingRate = double(step9Data.samplingRate);

step10Data.analysisDyadMask = analysisDyadMask;
step10Data.analysisDyadIndices = analysisDyadIndices;
step10Data.analysisDyadNumbers = analysisDyadNumbers;
step10Data.numberOfDyads = numberOfDyads;

step10Data.analysisData = analysisData;
step10Data.groupMean = groupMean;
step10Data.groupSD = groupSD;
step10Data.groupSEM = groupSEM;

step10Data.observedT = observedT;
step10Data.pointwiseParametricP = pointwiseParametricP;
step10Data.degreesOfFreedom = degreesOfFreedom;

step10Data.clusterFormingAlpha = ...
    options.ClusterFormingAlpha;
step10Data.clusterFormingThresholdT = ...
    clusterFormingThresholdT;
step10Data.familyWiseAlpha = ...
    options.FamilyWiseAlpha;

step10Data.observedMaximumClusterMass = ...
    observedMaximumClusterMass;
step10Data.nullMaximumClusterMass = ...
    nullMaximumClusterMass;

step10Data.signPatterns = signPatterns;
step10Data.signGenerationInfo = signGenerationInfo;
step10Data.numberOfPermutationsRequested = ...
    options.NumPermutations;
step10Data.numberOfPermutationsGenerated = ...
    numberOfPermutations;
step10Data.randomSeed = options.RandomSeed;

step10Data.significantClusterMask = ...
    significantClusterMask;
step10Data.minimumClusterPByROIPair = ...
    minimumClusterPByROIPair;
step10Data.negativeLog10MinimumClusterP = ...
    negativeLog10MinimumClusterP;
step10Data.significantPairMask = ...
    significantPairMask;

step10Data.signedPeakTByROIPair = ...
    signedPeakTByROIPair;
step10Data.peakLagMsByROIPair = ...
    peakLagMsByROIPair;

step10Data.numberOfObservedClusters = ...
    numel(observedClusters);

if isempty(clusterTable)
    step10Data.numberOfSignificantClusters = 0;
else
    step10Data.numberOfSignificantClusters = ...
        sum(clusterTable.SignificantFWER);
end

step10Data.settings = options;
step10Data.created = datestr(now, 30);
step10Data.functionName = mfilename;


%% ========================================================================
% 11. QC table
% ========================================================================

qcTable = struct_array_to_table(qcRows);

if ~isempty(qcTable)
    qcTable = sortrows(qcTable, ...
        {'DyadNumber', 'Issue'});
end


%% ========================================================================
% 12. Save numerical outputs
% ========================================================================

if options.SaveOutputs

    matFile = fullfile( ...
        outputFolder, ...
        'Step10_HyperYESNO_primary_cluster_permutation.mat');

    excelFile = fullfile( ...
        outputFolder, ...
        'Step10_HyperYESNO_primary_cluster_permutation.xlsx');

    if exist(excelFile, 'file') == 2
        delete(excelFile);
    end

    write_table_safely(clusterTable, excelFile, 'Clusters');
    write_table_safely(qcTable, excelFile, 'QC');

    analysisDyadTable = table( ...
        string(compose('Dyad%02d', analysisDyadNumbers(:))), ...
        analysisDyadNumbers(:), ...
        'VariableNames', {'Dyad', 'DyadNumber'});

    writetable(analysisDyadTable, excelFile, ...
        'Sheet', 'AnalysisDyads');

    settingsTable = table( ...
        [ ...
        "Number of dyads"; ...
        "Degrees of freedom"; ...
        "Permutations requested"; ...
        "Permutations generated"; ...
        "Cluster-forming alpha"; ...
        "Cluster-forming t threshold"; ...
        "Family-wise alpha"; ...
        "Random seed"], ...
        [ ...
        numberOfDyads; ...
        degreesOfFreedom; ...
        options.NumPermutations; ...
        numberOfPermutations; ...
        options.ClusterFormingAlpha; ...
        clusterFormingThresholdT; ...
        options.FamilyWiseAlpha; ...
        options.RandomSeed], ...
        'VariableNames', {'Setting', 'Value'});

    writetable(settingsTable, excelFile, ...
        'Sheet', 'Settings');

    step10Data.savedMatFile = string(matFile);
    step10Data.savedWorkbook = string(excelFile);

    save(matFile, ...
        'step10Data', ...
        'clusterTable', ...
        'qcTable', ...
        'sourceStep9DyadTable', ...
        'sourceStep9QCTable', ...
        '-v7.3');
end


%% ========================================================================
% 13. Generate figures
% ========================================================================

figureFiles = strings(0, 1);

if options.SaveFigures

    summaryFile = fullfile( ...
        figureFolder, ...
        ['Step10_primary_ROI_pair_summary.' figureFormat]);

    create_roi_pair_summary_figure( ...
        signedPeakTByROIPair, ...
        negativeLog10MinimumClusterP, ...
        significantPairMask, ...
        roiLabelsKnower, ...
        roiLabelsGuesser, ...
        options.FamilyWiseAlpha, ...
        summaryFile, ...
        figureVisible);

    figureFiles(end + 1, 1) = string(summaryFile);

    nullFile = fullfile( ...
        figureFolder, ...
        ['Step10_null_maximum_cluster_mass.' figureFormat]);

    create_null_distribution_figure( ...
        nullMaximumClusterMass, ...
        clusterTable, ...
        options.FamilyWiseAlpha, ...
        nullFile, ...
        figureVisible);

    figureFiles(end + 1, 1) = string(nullFile);

    if ~isempty(clusterTable)

        significantRows = find(clusterTable.SignificantFWER);

        for rowIndex = significantRows(:)'

            currentRow = clusterTable(rowIndex, :);

            safeKnower = sanitize_filename( ...
                currentRow.KnowerROI);
            safeGuesser = sanitize_filename( ...
                currentRow.GuesserROI);

            profileFile = fullfile( ...
                figureFolder, ...
                sprintf([ ...
                'Step10_cluster_%03d_%s_to_%s_%+g_to_%+gms.%s'], ...
                currentRow.ClusterID, ...
                safeKnower, ...
                safeGuesser, ...
                currentRow.StartLagMs, ...
                currentRow.EndLagMs, ...
                figureFormat));

            create_cluster_profile_figure( ...
                lagsMilliseconds, ...
                squeeze(groupMean( ...
                currentRow.KnowerROIIndex, ...
                currentRow.GuesserROIIndex, :)), ...
                squeeze(groupSEM( ...
                currentRow.KnowerROIIndex, ...
                currentRow.GuesserROIIndex, :)), ...
                currentRow, ...
                numberOfDyads, ...
                profileFile, ...
                figureVisible);

            figureFiles(end + 1, 1) = string(profileFile);
        end
    end
end

step10Data.figureFiles = figureFiles;

if options.SaveOutputs
    save(matFile, ...
        'step10Data', ...
        'clusterTable', ...
        'qcTable', ...
        'sourceStep9DyadTable', ...
        'sourceStep9QCTable', ...
        '-v7.3');
end


%% ========================================================================
% 14. Final report
% ========================================================================

if options.Verbose

    fprintf('\n============================================================\n');
    fprintf('Step 10 cluster permutation analysis completed.\n');
    fprintf('Complete dyads analysed:          %d\n', numberOfDyads);
    fprintf('Degrees of freedom:               %d\n', ...
        degreesOfFreedom);
    fprintf('Unique permutations generated:    %d\n', ...
        numberOfPermutations);
    fprintf('Cluster-forming threshold:        |t| >= %.6f\n', ...
        clusterFormingThresholdT);
    fprintf('Observed supra-threshold clusters:%d\n', ...
        step10Data.numberOfObservedClusters);
    fprintf('FWER-significant clusters:        %d\n', ...
        step10Data.numberOfSignificantClusters);
    fprintf('Excluded dyads:                   %d\n', ...
        height(qcTable));

    if options.SaveOutputs
        fprintf('MAT output:                       %s\n', matFile);
        fprintf('Excel output:                     %s\n', excelFile);
    end

    if options.SaveFigures
        fprintf('Figure folder:                    %s\n', ...
            figureFolder);
    end

    fprintf('============================================================\n');
end

end


%% ========================================================================
function [tValues, means, standardDeviations] = ...
    one_sample_t_from_sums(sumValues, sumSquares, sampleSize)
% ONE_SAMPLE_T_FROM_SUMS
% Calculate one-sample t statistics from sums and sums of squares.

means = sumValues ./ sampleSize;

varianceNumerator = ...
    sumSquares - sampleSize .* means .^ 2;

% Small negative values can arise from floating-point cancellation.
varianceNumerator = max(varianceNumerator, 0);

variances = varianceNumerator ./ (sampleSize - 1);
standardDeviations = sqrt(variances);
standardErrors = standardDeviations ./ sqrt(sampleSize);

tValues = zeros(size(means));

nonzeroSE = standardErrors > 0;
tValues(nonzeroSE) = ...
    means(nonzeroSE) ./ standardErrors(nonzeroSE);

zeroSEPositiveMean = ...
    ~nonzeroSE & means > 0;
zeroSENegativeMean = ...
    ~nonzeroSE & means < 0;

tValues(zeroSEPositiveMean) = Inf;
tValues(zeroSENegativeMean) = -Inf;

end


%% ========================================================================
function tValues = t_from_signed_sums( ...
    signedSums, invariantSumSquares, sampleSize)
% T_FROM_SIGNED_SUMS
% Calculate permutation t statistics efficiently. Sign flips preserve the
% sum of squared observations.

means = signedSums ./ sampleSize;

varianceNumerator = ...
    invariantSumSquares - sampleSize .* means .^ 2;

varianceNumerator = max(varianceNumerator, 0);
variances = varianceNumerator ./ (sampleSize - 1);
standardErrors = sqrt(variances ./ sampleSize);

tValues = zeros(size(means));

nonzeroSE = standardErrors > 0;
tValues(nonzeroSE) = ...
    means(nonzeroSE) ./ standardErrors(nonzeroSE);

zeroSEPositiveMean = ...
    ~nonzeroSE & means > 0;
zeroSENegativeMean = ...
    ~nonzeroSE & means < 0;

tValues(zeroSEPositiveMean) = Inf;
tValues(zeroSENegativeMean) = -Inf;

end


%% ========================================================================
function pValues = student_t_two_sided_p(tValues, degreesOfFreedom)
% STUDENT_T_TWO_SIDED_P
% Two-sided Student t probabilities calculated with BETAINC, avoiding a
% dependency on the Statistics and Machine Learning Toolbox.

absoluteT = abs(tValues);

x = degreesOfFreedom ./ ...
    (degreesOfFreedom + absoluteT .^ 2);

pValues = betainc( ...
    x, degreesOfFreedom / 2, 0.5);

pValues(isinf(absoluteT)) = 0;
pValues = min(max(pValues, 0), 1);

end


%% ========================================================================
function criticalT = student_t_two_sided_critical(alpha, degreesOfFreedom)
% STUDENT_T_TWO_SIDED_CRITICAL
% Two-sided Student t critical value calculated with BETAINCINV.

x = betaincinv( ...
    alpha, degreesOfFreedom / 2, 0.5);

criticalT = sqrt( ...
    degreesOfFreedom .* (1 - x) ./ x);

end


%% ========================================================================
function [clusters, maximumMass] = collect_lag_clusters( ...
    tMap, threshold, lagValues)
% COLLECT_LAG_CLUSTERS
% Identify all positive and negative clusters across adjacent lags within
% each ROI pair.

mapSize = size(tMap);
mapSize(end + 1:3) = 1;

numberOfKnowerROIs = mapSize(1);
numberOfGuesserROIs = mapSize(2);

clusters = struct([]);
maximumMass = 0;

for knowerROIIndex = 1:numberOfKnowerROIs
    for guesserROIIndex = 1:numberOfGuesserROIs

        tVector = squeeze(tMap( ...
            knowerROIIndex, guesserROIIndex, :));

        positiveRuns = logical_runs(tVector >= threshold);
        negativeRuns = logical_runs(tVector <= -threshold);

        for runIndex = 1:size(positiveRuns, 1)

            startIndex = positiveRuns(runIndex, 1);
            endIndex = positiveRuns(runIndex, 2);
            indices = startIndex:endIndex;

            signedMass = sum(tVector(indices));
            absoluteMass = abs(signedMass);

            [peakT, localPeak] = max(tVector(indices));
            peakIndex = indices(localPeak);

            row = make_cluster_row( ...
                knowerROIIndex, ...
                guesserROIIndex, ...
                startIndex, ...
                endIndex, ...
                "positive", ...
                signedMass, ...
                absoluteMass, ...
                peakT, ...
                peakIndex, ...
                lagValues);

            clusters = append_struct(clusters, row);
            maximumMass = max(maximumMass, absoluteMass);
        end

        for runIndex = 1:size(negativeRuns, 1)

            startIndex = negativeRuns(runIndex, 1);
            endIndex = negativeRuns(runIndex, 2);
            indices = startIndex:endIndex;

            signedMass = sum(tVector(indices));
            absoluteMass = abs(signedMass);

            [peakT, localPeak] = min(tVector(indices));
            peakIndex = indices(localPeak);

            row = make_cluster_row( ...
                knowerROIIndex, ...
                guesserROIIndex, ...
                startIndex, ...
                endIndex, ...
                "negative", ...
                signedMass, ...
                absoluteMass, ...
                peakT, ...
                peakIndex, ...
                lagValues);

            clusters = append_struct(clusters, row);
            maximumMass = max(maximumMass, absoluteMass);
        end
    end
end

end


%% ========================================================================
function row = make_cluster_row( ...
    knowerROIIndex, guesserROIIndex, startIndex, endIndex, ...
    signLabel, signedMass, absoluteMass, peakT, peakIndex, lagValues)
% MAKE_CLUSTER_ROW
% Construct one fixed-field cluster structure.

row = struct;

row.KnowerROIIndex = double(knowerROIIndex);
row.GuesserROIIndex = double(guesserROIIndex);
row.StartLagIndex = double(startIndex);
row.EndLagIndex = double(endIndex);
row.StartLagMs = double(lagValues(startIndex));
row.EndLagMs = double(lagValues(endIndex));
row.NumberOfLags = double(endIndex - startIndex + 1);

row.Sign = string(signLabel);
row.SignedMass = double(signedMass);
row.AbsoluteMass = double(absoluteMass);
row.PeakT = double(peakT);
row.PeakLagIndex = double(peakIndex);
row.PeakLagMs = double(lagValues(peakIndex));

end


%% ========================================================================
function maximumMass = maximum_lag_cluster_mass(tMap, threshold)
% MAXIMUM_LAG_CLUSTER_MASS
% Return only the largest absolute lag-cluster mass across the complete map.

mapSize = size(tMap);
mapSize(end + 1:3) = 1;

numberOfKnowerROIs = mapSize(1);
numberOfGuesserROIs = mapSize(2);

maximumMass = 0;

for knowerROIIndex = 1:numberOfKnowerROIs
    for guesserROIIndex = 1:numberOfGuesserROIs

        tVector = squeeze(tMap( ...
            knowerROIIndex, guesserROIIndex, :));

        positiveRuns = logical_runs(tVector >= threshold);

        for runIndex = 1:size(positiveRuns, 1)
            indices = ...
                positiveRuns(runIndex, 1):positiveRuns(runIndex, 2);

            maximumMass = max( ...
                maximumMass, ...
                abs(sum(tVector(indices))));
        end

        negativeRuns = logical_runs(tVector <= -threshold);

        for runIndex = 1:size(negativeRuns, 1)
            indices = ...
                negativeRuns(runIndex, 1):negativeRuns(runIndex, 2);

            maximumMass = max( ...
                maximumMass, ...
                abs(sum(tVector(indices))));
        end
    end
end

end


%% ========================================================================
function runs = logical_runs(mask)
% LOGICAL_RUNS
% Return the start and end indices of contiguous true samples.

mask = logical(mask(:));

changes = diff([false; mask; false]);

starts = find(changes == 1);
ends = find(changes == -1) - 1;

runs = [starts, ends];

end


%% ========================================================================
function [signPatterns, info] = generate_unique_sign_patterns( ...
    numberOfDyads, requestedPermutations, randomSeed)
% GENERATE_UNIQUE_SIGN_PATTERNS
% Generate unique two-sided sign patterns. The first dyad is fixed to +1,
% eliminating the global sign-inversion duplication. The observed
% all-positive pattern is excluded.

if numberOfDyads < 2
    error('step10:InsufficientDyadsForSigns', ...
        'At least two dyads are required for sign-flip permutations.');
end

numberOfFreeSigns = numberOfDyads - 1;

if numberOfFreeSigns <= 52
    maximumUniquePatterns = 2 ^ numberOfFreeSigns - 1;
else
    maximumUniquePatterns = Inf;
end

numberToGenerate = min( ...
    requestedPermutations, maximumUniquePatterns);

rng(randomSeed, 'twister');

% Enumerate all patterns when the complete space is requested and remains
% computationally manageable.
enumerationLimit = 2 ^ 20 - 1;

if isfinite(maximumUniquePatterns) && ...
        numberToGenerate == maximumUniquePatterns && ...
        maximumUniquePatterns <= enumerationLimit

    codes = uint64((1:maximumUniquePatterns)');
    freeNegative = false(maximumUniquePatterns, numberOfFreeSigns);

    for bitIndex = 1:numberOfFreeSigns
        freeNegative(:, bitIndex) = ...
            logical(bitget(codes, bitIndex));
    end

    mode = "all_unique_two_sided_patterns";

else
    freeNegative = false(0, numberOfFreeSigns);

    while size(freeNegative, 1) < numberToGenerate

        remaining = numberToGenerate - size(freeNegative, 1);
        proposalCount = max(1000, ceil(remaining * 1.5));

        proposals = ...
            rand(proposalCount, numberOfFreeSigns) < 0.5;

        % Exclude the all-positive observed pattern.
        proposals = proposals(any(proposals, 2), :);

        freeNegative = unique( ...
            [freeNegative; proposals], ...
            'rows', ...
            'stable');

        if size(freeNegative, 1) > numberToGenerate
            freeNegative = ...
                freeNegative(1:numberToGenerate, :);
        end
    end

    mode = "random_unique_two_sided_patterns";
end

signPatterns = ones(numberToGenerate, numberOfDyads);
signPatterns(:, 2:end) = ...
    1 - 2 .* double(freeNegative);

info = struct;
info.Mode = mode;
info.FirstDyadFixedPositive = true;
info.ObservedAllPositivePatternExcluded = true;
info.GlobalSignInverseDuplicatesPrevented = true;
info.DuplicatePatternsPrevented = true;
info.MaximumUniquePatterns = maximumUniquePatterns;
info.NumberRequested = requestedPermutations;
info.NumberGenerated = numberToGenerate;
info.RandomSeed = randomSeed;

end


%% ========================================================================
function create_roi_pair_summary_figure( ...
    signedPeakT, negativeLog10P, significantPairMask, ...
    knowerLabels, guesserLabels, familyWiseAlpha, ...
    outputFile, figureVisible)
% CREATE_ROI_PAIR_SUMMARY_FIGURE
% Produce two ROI-pair heat maps.

figureHandle = figure( ...
    'Visible', figureVisible, ...
    'Color', 'w', ...
    'Position', [100, 100, 1500, 650]);

layout = tiledlayout(figureHandle, 1, 2, ...
    'Padding', 'compact', ...
    'TileSpacing', 'compact');

nexttile(layout, 1);

imagesc(signedPeakT);
axis image;
set(gca, 'YDir', 'normal');

maximumAbsoluteT = max(abs(signedPeakT), [], 'all');

if maximumAbsoluteT > 0
    clim([-maximumAbsoluteT, maximumAbsoluteT]);
end

colormap(gca, blue_white_red_colormap(256));
colorbar;

title('Signed peak t statistic across lags');
xlabel('Guesser ROI');
ylabel('Knower ROI');

apply_roi_ticks(knowerLabels, guesserLabels);

nexttile(layout, 2);

imagesc(negativeLog10P);
axis image;
set(gca, 'YDir', 'normal');
colormap(gca, parula(256));
colorbar;

hold on;
[significantRows, significantColumns] = ...
    find(significantPairMask);

plot(significantColumns, significantRows, ...
    'ko', ...
    'MarkerSize', 8, ...
    'LineWidth', 1.5);

thresholdDisplay = -log10(familyWiseAlpha);
title(sprintf([ ...
    '-log_{10} minimum cluster-corrected p\n' ...
    'circles: p_{FWER} <= %.3f; threshold = %.3f'], ...
    familyWiseAlpha, thresholdDisplay));

xlabel('Guesser ROI');
ylabel('Knower ROI');

apply_roi_ticks(knowerLabels, guesserLabels);

exportgraphics(figureHandle, outputFile, ...
    'Resolution', 300);

close(figureHandle);

end


%% ========================================================================
function create_null_distribution_figure( ...
    nullMaximumMass, clusterTable, familyWiseAlpha, ...
    outputFile, figureVisible)
% CREATE_NULL_DISTRIBUTION_FIGURE
% Plot the permutation distribution of the maximum cluster mass.

figureHandle = figure( ...
    'Visible', figureVisible, ...
    'Color', 'w', ...
    'Position', [100, 100, 900, 650]);

histogram(nullMaximumMass, 50, ...
    'Normalization', 'probability');

hold on;

criticalMass = empirical_upper_quantile( ...
    nullMaximumMass, 1 - familyWiseAlpha);

xline(criticalMass, '--', ...
    sprintf('FWER %.3f threshold', familyWiseAlpha), ...
    'LineWidth', 1.5, ...
    'LabelVerticalAlignment', 'middle');

if ~isempty(clusterTable)

    significantRows = find(clusterTable.SignificantFWER);

    for rowIndex = significantRows(:)'
        xline(clusterTable.AbsoluteClusterMass(rowIndex), ...
            '-', ...
            sprintf('Cluster %d', ...
            clusterTable.ClusterID(rowIndex)), ...
            'LineWidth', 1.2);
    end
end

xlabel('Maximum absolute cluster mass');
ylabel('Permutation probability');
title('Sign-flip null distribution');
box off;

exportgraphics(figureHandle, outputFile, ...
    'Resolution', 300);

close(figureHandle);

end


%% ========================================================================
function create_cluster_profile_figure( ...
    lagValues, meanValues, semValues, clusterRow, ...
    numberOfDyads, outputFile, figureVisible)
% CREATE_CLUSTER_PROFILE_FIGURE
% Plot the mean primary contrast and SEM across all lags for one
% FWER-significant ROI pair.

meanValues = meanValues(:)';
semValues = semValues(:)';
lagValues = lagValues(:)';

figureHandle = figure( ...
    'Visible', figureVisible, ...
    'Color', 'w', ...
    'Position', [100, 100, 950, 650]);

upperValues = meanValues + semValues;
lowerValues = meanValues - semValues;

patch( ...
    [lagValues, fliplr(lagValues)], ...
    [upperValues, fliplr(lowerValues)], ...
    [0.85, 0.85, 0.85], ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.7);

hold on;

plot(lagValues, meanValues, ...
    'k-', ...
    'LineWidth', 2);

yline(0, ':', 'LineWidth', 1);

currentLimits = ylim;

clusterStart = clusterRow.StartLagMs;
clusterEnd = clusterRow.EndLagMs;

if clusterStart == clusterEnd
    lagStep = median(diff(lagValues));
    clusterStart = clusterStart - lagStep / 2;
    clusterEnd = clusterEnd + lagStep / 2;
end

patch( ...
    [clusterStart, clusterEnd, clusterEnd, clusterStart], ...
    [currentLimits(1), currentLimits(1), ...
     currentLimits(2), currentLimits(2)], ...
    [0.75, 0.75, 0.75], ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.25);

% Redraw the line above the highlighted region.
plot(lagValues, meanValues, ...
    'k-', ...
    'LineWidth', 2);

xlabel([ ...
    'Lag (ms): negative = Knower precedes Guesser; ' ...
    'positive = Guesser precedes Knower']);

ylabel('Surrogate-corrected YES - NO GCMI');

title(sprintf([ ...
    '%s -> %s | %s cluster, %g to %g ms\n' ...
    'p_{FWER} = %.4f, peak t = %.3f at %g ms, N = %d'], ...
    char(clusterRow.KnowerROI), ...
    char(clusterRow.GuesserROI), ...
    char(clusterRow.ClusterSign), ...
    clusterRow.StartLagMs, ...
    clusterRow.EndLagMs, ...
    clusterRow.ClusterCorrectedP, ...
    clusterRow.PeakT, ...
    clusterRow.PeakLagMs, ...
    numberOfDyads), ...
    'Interpreter', 'none');

box off;
xlim([min(lagValues), max(lagValues)]);

exportgraphics(figureHandle, outputFile, ...
    'Resolution', 300);

close(figureHandle);

end


%% ========================================================================
function apply_roi_ticks(knowerLabels, guesserLabels)
% APPLY_ROI_TICKS
% Apply ROI labels to a heat map.

xticks(1:numel(guesserLabels));
xticklabels(cellstr(guesserLabels));
xtickangle(90);

yticks(1:numel(knowerLabels));
yticklabels(cellstr(knowerLabels));

set(gca, 'TickLabelInterpreter', 'none', ...
    'FontSize', 8);

end


%% ========================================================================
function colourMap = blue_white_red_colormap(numberOfColours)
% BLUE_WHITE_RED_COLORMAP
% Simple diverging colour map.

if mod(numberOfColours, 2) ~= 0
    numberOfColours = numberOfColours + 1;
end

halfNumber = numberOfColours / 2;

blueToWhite = [ ...
    linspace(0, 1, halfNumber)', ...
    linspace(0, 1, halfNumber)', ...
    ones(halfNumber, 1)];

whiteToRed = [ ...
    ones(halfNumber, 1), ...
    linspace(1, 0, halfNumber)', ...
    linspace(1, 0, halfNumber)'];

colourMap = [blueToWhite; whiteToRed];

end


%% ========================================================================
function quantileValue = empirical_upper_quantile(values, probability)
% EMPIRICAL_UPPER_QUANTILE
% Conservative empirical quantile without requiring a statistics toolbox.

sortedValues = sort(values(:), 'ascend');

index = ceil(probability * numel(sortedValues));
index = min(max(index, 1), numel(sortedValues));

quantileValue = sortedValues(index);

end


%% ========================================================================
function safeName = sanitize_filename(inputText)
% SANITIZE_FILENAME
% Replace non-alphanumeric filename characters.

safeName = regexprep(char(string(inputText)), ...
    '[^A-Za-z0-9_-]+', '_');

safeName = regexprep(safeName, '_+', '_');
safeName = regexprep(safeName, '^_|_$', '');

if isempty(safeName)
    safeName = 'ROI';
end

end


%% ========================================================================
function qcRows = add_qc( ...
    qcRows, dyadName, dyadNumber, issue, details)
% ADD_QC
% Append a fixed-field QC row without cell-array table conversion.

row = struct;

row.Dyad = string(dyadName);
row.DyadNumber = double(dyadNumber);
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
% Convert a structure array to a table without cell2table or cell2mat.

if isempty(rows)
    T = table();
else
    T = struct2table(rows);
end

end


%% ========================================================================
function outputSize = size4(inputArray)
% SIZE4
% Return exactly the first four dimensions.

outputSize = size(inputArray);
outputSize(end + 1:4) = 1;
outputSize = outputSize(1:4);

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
