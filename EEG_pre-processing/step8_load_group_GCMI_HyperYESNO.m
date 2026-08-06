function [groupData, fileTable, qcTable] = ...
    step8_load_group_GCMI_HyperYESNO(rootDir, dyads, varargin)
% STEP8_LOAD_GROUP_GCMI_HYPERYESNO
% Load and quality-check the Step 7 lagged-GCMI results for HyperYESNO.
%
% This function is the group-level loading and validation stage following:
%
%   step7_run_lagged_GCMI_HyperYESNO.m
%
% For every requested dyad and situation, the function:
%
%   1. locates the Step 7 MAT file;
%   2. loads the results structure;
%   3. verifies array dimensions;
%   4. verifies ROI labels and their ordering;
%   5. verifies lag samples and lag values;
%   6. verifies trial and surrogate metadata;
%   7. checks that surrogate permutations are unique derangements;
%   8. creates consistent group-level arrays; and
%   9. saves compact group data and QC tables.
%
% The full four-dimensional surrogate arrays are verified sequentially but
% are NOT retained in groupData. Retaining every surrogate realization for
% 35 dyads and four situations would require several gigabytes of memory.
% The original Step 7 files remain the authoritative source for the full
% surrogate distributions.
%
% GROUP ARRAY DIMENSION ORDER
% ---------------------------
%
%   Knower ROI x Guesser ROI x Lag x Dyad x Situation
%
% The four situations are stored in this fixed order:
%
%   1. YES_AKnower
%   2. NO_AKnower
%   3. YES_BKnower
%   4. NO_BKnower
%
% Because Step 7 always passed dataA=Knower and dataB=Guesser, the first ROI
% dimension always corresponds to the Knower and the second always
% corresponds to the Guesser.
%
% LAG CONVENTION
% --------------
%
%   negative lag = Knower precedes Guesser
%   positive lag = Guesser precedes Knower
%
% INPUT FILES
% -----------
%
%   rootDir/DyadXX/Lagged_GCMI/SITUATION/
%       DyadXX_SITUATION_lagged_GCMI.mat
%
% REQUIRED INPUTS
% ---------------
%
% rootDir
%   HyperYESNO data root.
%   Default:
%       'E:\EEG_data_HyperYESNO'
%
% dyads
%   Numeric vector of dyads to load.
%   Default:
%       1:35
%
% OPTIONAL NAME-VALUE INPUTS
% --------------------------
%
% 'Situations'
%   Situations to load. Their order in the group arrays follows the order
%   supplied here.
%
%   Default:
%       {'YES_AKnower','NO_AKnower', ...
%        'YES_BKnower','NO_BKnower'}
%
% 'InputFolderName'
%   Step 7 output folder inside every dyad.
%
%   Default:
%       'Lagged_GCMI'
%
% 'OutputFolder'
%   Folder used to save the Step 8 outputs.
%
%   Default:
%       fullfile(rootDir, 'Group_GCMI')
%
% 'ExpectedROICount'
%   Expected number of ROIs for both participants.
%
%   Default:
%       20
%
% 'ExpectedLagsMs'
%   Expected actual lag grid in milliseconds.
%
%   Default:
%       -500:50:500
%
% 'ExpectedSamplingRate'
%   Expected source-level sampling rate in Hz.
%
%   Default:
%       100
%
% 'MinimumTrialsWarning'
%   Files with fewer trials are retained but flagged.
%
%   Default:
%       5
%
% 'MinimumSurrogatesWarning'
%   Files with fewer generated surrogates are retained but flagged.
%   Low surrogate counts are expected when only a small number of unique
%   trial derangements is mathematically possible.
%
%   Default:
%       19
%
% 'VerifySurrogateSummaries'
%   Recalculate the surrogate mean and standard deviation from the full
%   surrogate array and compare them with the stored summaries.
%
%   Default:
%       true
%
% 'SummaryTolerance'
%   Absolute tolerance used when comparing stored and recalculated
%   surrogate summaries.
%
%   Default:
%       1e-10
%
% 'SaveOutputs'
%   Save the compact MAT file and Excel QC workbook.
%
%   Default:
%       true
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
% groupData
%   Structure containing compact group-level arrays and metadata.
%
%   Important fields:
%
%       groupData.gcmiObserved
%       groupData.gcmiSurrogateMean
%       groupData.gcmiSurrogateStd
%       groupData.validMask
%       groupData.numberOfTrials
%       groupData.numberOfSurrogatesGenerated
%       groupData.roiLabelsKnower
%       groupData.roiLabelsGuesser
%       groupData.lagsMilliseconds
%       groupData.dyadNumbers
%       groupData.situations
%
% fileTable
%   One row per requested dyad and situation, including loading status,
%   dimensions, trials, surrogates, and finite-value summaries.
%
% qcTable
%   One row per QC issue. Files can have more than one issue.
%
% SAVED OUTPUTS
% -------------
%
%   Group_GCMI/Step8_HyperYESNO_group_GCMI.mat
%   Group_GCMI/Step8_HyperYESNO_group_GCMI_QC.xlsx
%
% The Excel workbook contains:
%
%   FileSummary
%   QC
%   ArrayGuide
%
% EXAMPLE
% -------
%
% [groupData, fileTable, qcTable] = ...
%     step8_load_group_GCMI_HyperYESNO( ...
%     'E:\EEG_data_HyperYESNO', ...
%     1:35);
%
% Author: Alejandro Perez
% HyperYESNO project, 2026


%% ========================================================================
% 1. Inputs
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

defaultSituations = { ...
    'YES_AKnower', ...
    'NO_AKnower', ...
    'YES_BKnower', ...
    'NO_BKnower'};

parser = inputParser;
parser.FunctionName = mfilename;

addRequired(parser, 'rootDir', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addRequired(parser, 'dyads', ...
    @(x) isnumeric(x) && isvector(x) && ...
    all(isfinite(x)) && all(x > 0) && ...
    all(x == round(x)));

addParameter(parser, 'Situations', defaultSituations, ...
    @(x) ischar(x) || isstring(x) || iscellstr(x));

addParameter(parser, 'InputFolderName', 'Lagged_GCMI', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'OutputFolder', ...
    fullfile(char(rootDir), 'Group_GCMI'), ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'ExpectedROICount', 20, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 1 && x == round(x));

addParameter(parser, 'ExpectedLagsMs', -500:50:500, ...
    @(x) isnumeric(x) && isvector(x) && all(isfinite(x)));

addParameter(parser, 'ExpectedSamplingRate', 100, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);

addParameter(parser, 'MinimumTrialsWarning', 5, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 1 && x == round(x));

addParameter(parser, 'MinimumSurrogatesWarning', 19, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 0 && x == round(x));

addParameter(parser, 'VerifySurrogateSummaries', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'SummaryTolerance', 1e-10, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 0);

addParameter(parser, 'SaveOutputs', true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, rootDir, dyads, varargin{:});
options = parser.Results;

rootDir = char(string(rootDir));
inputFolderName = char(string(options.InputFolderName));
outputFolder = char(string(options.OutputFolder));

dyads = unique(double(dyads(:)'), 'stable');
situations = cellstr(string(options.Situations(:)'));

allowedSituations = string(defaultSituations);

if any(~ismember(string(situations), allowedSituations))
    invalid = string(situations(~ismember(string(situations), ...
        allowedSituations)));

    error('step8:InvalidSituation', ...
        'Unknown situation(s): %s', strjoin(invalid, ', '));
end

expectedLagsMs = double(options.ExpectedLagsMs(:)');

if numel(unique(expectedLagsMs)) ~= numel(expectedLagsMs)
    error('step8:DuplicateExpectedLags', ...
        'ExpectedLagsMs must not contain duplicate values.');
end

if options.SaveOutputs && ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

numberOfDyads = numel(dyads);
numberOfSituations = numel(situations);


%% ========================================================================
% 2. Define situation metadata
% ========================================================================

situationCondition = strings(1, numberOfSituations);
situationKnower = strings(1, numberOfSituations);
situationGuesser = strings(1, numberOfSituations);

for situationIndex = 1:numberOfSituations

    situationName = string(situations{situationIndex});

    if startsWith(situationName, "YES_")
        situationCondition(situationIndex) = "YES";
    else
        situationCondition(situationIndex) = "NO";
    end

    if endsWith(situationName, "_AKnower")
        situationKnower(situationIndex) = "A";
        situationGuesser(situationIndex) = "B";
    else
        situationKnower(situationIndex) = "B";
        situationGuesser(situationIndex) = "A";
    end
end


%% ========================================================================
% 3. Initialize metadata matrices and row structures
% ========================================================================

validMask = false(numberOfDyads, numberOfSituations);

numberOfTrials = nan(numberOfDyads, numberOfSituations);
numberOfObservationsPerLag = nan(numberOfDyads, numberOfSituations);
numberOfSurrogatesRequested = nan(numberOfDyads, numberOfSituations);
numberOfSurrogatesGenerated = nan(numberOfDyads, numberOfSituations);
maximumUniqueDerangements = nan(numberOfDyads, numberOfSituations);
allUniqueDerangementsUsed = false(numberOfDyads, numberOfSituations);

surrogateGenerationMode = strings( ...
    numberOfDyads, numberOfSituations);

resultFilePaths = strings(numberOfDyads, numberOfSituations);
loadStatus = strings(numberOfDyads, numberOfSituations);

fileRows = struct([]);
qcRows = struct([]);

% The numerical group arrays are allocated only after the first valid file
% establishes the reference dimensions, labels, and lag grid.
groupArraysAllocated = false;

gcmiObserved = [];
gcmiSurrogateMean = [];
gcmiSurrogateStd = [];

reference = struct;
reference.numberOfKnowerROIs = NaN;
reference.numberOfGuesserROIs = NaN;
reference.numberOfLags = NaN;
reference.roiLabelsKnower = strings(0, 1);
reference.roiLabelsGuesser = strings(0, 1);
reference.lagsSamples = [];
reference.lagsMilliseconds = [];
reference.requestedLagsMilliseconds = [];
reference.samplingRate = NaN;
reference.sourceFile = "";


%% ========================================================================
% 4. Load and validate each result file
% ========================================================================

for dyadIndex = 1:numberOfDyads

    dyadNumber = dyads(dyadIndex);
    dyadName = sprintf('Dyad%02d', dyadNumber);

    for situationIndex = 1:numberOfSituations

        situationName = situations{situationIndex};

        resultFile = fullfile( ...
            rootDir, ...
            dyadName, ...
            inputFolderName, ...
            situationName, ...
            sprintf('%s_%s_lagged_GCMI.mat', ...
            dyadName, situationName));

        resultFilePaths(dyadIndex, situationIndex) = ...
            string(resultFile);

        record = initialize_file_record( ...
            dyadName, ...
            dyadNumber, ...
            situationName, ...
            situationCondition(situationIndex), ...
            situationKnower(situationIndex), ...
            situationGuesser(situationIndex), ...
            resultFile);

        if options.Verbose
            fprintf('\n[%s | %s]\n', dyadName, situationName);
        end

        %% ----------------------------------------------------------------
        % 4.1 File existence and loading
        % -----------------------------------------------------------------

        if exist(resultFile, 'file') ~= 2

            record.Status = "missing_file";
            record.IncludedInGroupArrays = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "MissingFile", ...
                "The expected Step 7 result file was not found.", ...
                resultFile);

            fileRows = append_struct(fileRows, record);
            loadStatus(dyadIndex, situationIndex) = record.Status;

            if options.Verbose
                fprintf('  Missing file.\n');
            end
            continue
        end

        try
            loaded = load(resultFile, 'results');
        catch ME
            record.Status = "load_failure";
            record.IncludedInGroupArrays = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "LoadFailure", ...
                string(ME.message), resultFile);

            fileRows = append_struct(fileRows, record);
            loadStatus(dyadIndex, situationIndex) = record.Status;

            if options.Verbose
                fprintf('  Load failure: %s\n', ME.message);
            end
            continue
        end

        if ~isfield(loaded, 'results') || ...
                ~isstruct(loaded.results)

            record.Status = "invalid_results_variable";
            record.IncludedInGroupArrays = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "InvalidResultsVariable", ...
                ['The MAT file did not contain a valid structure named ' ...
                'results.'], resultFile);

            fileRows = append_struct(fileRows, record);
            loadStatus(dyadIndex, situationIndex) = record.Status;
            continue
        end

        results = loaded.results;
        clear loaded

        %% ----------------------------------------------------------------
        % 4.2 Required fields
        % -----------------------------------------------------------------

        requiredFields = { ...
            'gcmiObserved', ...
            'gcmiSurrogates', ...
            'gcmiSurrogateMean', ...
            'gcmiSurrogateStd', ...
            'lagsSamples', ...
            'lagsMilliseconds', ...
            'requestedLagsMilliseconds', ...
            'samplingRate', ...
            'numberOfTrials', ...
            'numberOfObservationsPerLag', ...
            'numberOfChannelsA', ...
            'numberOfChannelsB', ...
            'channelLabelsA', ...
            'channelLabelsB', ...
            'surrogateTrialPermutations', ...
            'numberOfSurrogatesRequested', ...
            'numberOfSurrogatesGenerated'};

        missingFields = requiredFields( ...
            ~isfield(results, requiredFields));

        if ~isempty(missingFields)

            record.Status = "missing_required_fields";
            record.IncludedInGroupArrays = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "MissingRequiredFields", ...
                "Missing field(s): " + ...
                strjoin(string(missingFields), ', '), ...
                resultFile);

            fileRows = append_struct(fileRows, record);
            loadStatus(dyadIndex, situationIndex) = record.Status;

            clear results
            continue
        end

        %% ----------------------------------------------------------------
        % 4.3 Basic dimensions and metadata
        % -----------------------------------------------------------------

        observedSize = size(results.gcmiObserved);
        observedSize(end + 1:3) = 1;

        nKnowerROIs = observedSize(1);
        nGuesserROIs = observedSize(2);
        nLags = observedSize(3);

        surrogateSize = size(results.gcmiSurrogates);
        surrogateSize(end + 1:4) = 1;
        nSurrogatesInArray = surrogateSize(4);

        labelsKnower = string(results.channelLabelsA(:));
        labelsGuesser = string(results.channelLabelsB(:));

        lagsSamples = double(results.lagsSamples(:)');
        lagsMilliseconds = ...
            double(results.lagsMilliseconds(:)');
        requestedLagsMilliseconds = ...
            double(results.requestedLagsMilliseconds(:)');

        record.NumKnowerROIs = nKnowerROIs;
        record.NumGuesserROIs = nGuesserROIs;
        record.NumLags = nLags;
        record.SamplingRateHz = double(results.samplingRate);
        record.NumTrials = double(results.numberOfTrials);
        record.NumObservationsPerLag = ...
            double(results.numberOfObservationsPerLag);
        record.NumSurrogatesRequested = ...
            double(results.numberOfSurrogatesRequested);
        record.NumSurrogatesGenerated = ...
            double(results.numberOfSurrogatesGenerated);
        record.NumSurrogatesStored = nSurrogatesInArray;

        if isfield(results, 'maximumUniqueDerangements')
            record.MaximumUniqueDerangements = ...
                double(results.maximumUniqueDerangements);
        end

        if isfield(results, 'allUniqueDerangementsUsed')
            record.AllUniqueDerangementsUsed = ...
                logical(results.allUniqueDerangementsUsed);
        end

        if isfield(results, 'surrogateGenerationMode')
            record.SurrogateGenerationMode = ...
                string(results.surrogateGenerationMode);
        end

        record.ObservedFinitePercent = ...
            100 * sum(isfinite(results.gcmiObserved(:))) / ...
            numel(results.gcmiObserved);

        if isempty(results.gcmiSurrogates)
            record.SurrogateFinitePercent = NaN;
        else
            record.SurrogateFinitePercent = ...
                100 * sum(isfinite(results.gcmiSurrogates(:))) / ...
                numel(results.gcmiSurrogates);
        end

        %% ----------------------------------------------------------------
        % 4.4 Within-file validation
        % -----------------------------------------------------------------

        fileIsValid = true;

        % Expected ROI dimensions.
        if nKnowerROIs ~= options.ExpectedROICount || ...
                nGuesserROIs ~= options.ExpectedROICount

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "UnexpectedROIDimensions", ...
                sprintf(['Expected %d x %d ROI dimensions but found ' ...
                '%d x %d.'], ...
                options.ExpectedROICount, ...
                options.ExpectedROICount, ...
                nKnowerROIs, nGuesserROIs), ...
                resultFile);
        end

        % Stored channel-count metadata.
        if double(results.numberOfChannelsA) ~= nKnowerROIs || ...
                double(results.numberOfChannelsB) ~= nGuesserROIs

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "ChannelCountMetadataMismatch", ...
                ['numberOfChannelsA/B did not match the dimensions of ' ...
                'gcmiObserved.'], ...
                resultFile);
        end

        % ROI labels.
        if numel(labelsKnower) ~= nKnowerROIs || ...
                numel(labelsGuesser) ~= nGuesserROIs

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "ROILabelCountMismatch", ...
                ['The number of ROI labels did not match the GCMI ' ...
                'array dimensions.'], ...
                resultFile);
        end

        if numel(unique(labelsKnower)) ~= numel(labelsKnower) || ...
                numel(unique(labelsGuesser)) ~= numel(labelsGuesser)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "DuplicateROILabels", ...
                "ROI labels were not unique.", resultFile);
        end

        % Lag dimensions.
        if nLags ~= numel(lagsSamples) || ...
                nLags ~= numel(lagsMilliseconds)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "LagDimensionMismatch", ...
                ['The lag vectors did not match the third dimension of ' ...
                'gcmiObserved.'], ...
                resultFile);
        end

        if ~isequal(lagsMilliseconds, expectedLagsMs)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "UnexpectedLagGrid", ...
                "Expected " + string(mat2str(expectedLagsMs)) + ...
                " ms but found " + ...
                string(mat2str(lagsMilliseconds)) + " ms.", ...
                resultFile);
        end

        % Sampling rate.
        if abs(double(results.samplingRate) - ...
                options.ExpectedSamplingRate) > 1e-10

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "UnexpectedSamplingRate", ...
                sprintf('Expected %.12g Hz but found %.12g Hz.', ...
                options.ExpectedSamplingRate, ...
                double(results.samplingRate)), ...
                resultFile);
        end

        % Surrogate array dimensions.
        expectedSurrogateFirstThree = ...
            [nKnowerROIs, nGuesserROIs, nLags];

        if ~isequal(surrogateSize(1:3), ...
                expectedSurrogateFirstThree)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "SurrogateArrayDimensionMismatch", ...
                ['The first three dimensions of gcmiSurrogates did not ' ...
                'match gcmiObserved.'], ...
                resultFile);
        end

        if nSurrogatesInArray ~= ...
                double(results.numberOfSurrogatesGenerated)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "SurrogateCountMismatch", ...
                sprintf(['The surrogate array stored %d realizations, ' ...
                'whereas metadata reported %d.'], ...
                nSurrogatesInArray, ...
                double(results.numberOfSurrogatesGenerated)), ...
                resultFile);
        end

        % Surrogate summary dimensions.
        if ~isequal(size3(results.gcmiSurrogateMean), ...
                expectedSurrogateFirstThree) || ...
                ~isequal(size3(results.gcmiSurrogateStd), ...
                expectedSurrogateFirstThree)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "SurrogateSummaryDimensionMismatch", ...
                ['The stored surrogate mean or standard deviation did ' ...
                'not match gcmiObserved.'], ...
                resultFile);
        end

        % Trial-permutation checks.
        permutations = ...
            double(results.surrogateTrialPermutations);

        expectedPermutationSize = [ ...
            double(results.numberOfTrials), ...
            double(results.numberOfSurrogatesGenerated)];

        actualPermutationSize = size(permutations);
        actualPermutationSize(end + 1:2) = 1;

        if ~isequal(actualPermutationSize(1:2), ...
                expectedPermutationSize)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "PermutationMatrixDimensionMismatch", ...
                sprintf(['Expected a %d x %d trial-permutation matrix ' ...
                'but found %d x %d.'], ...
                expectedPermutationSize(1), ...
                expectedPermutationSize(2), ...
                actualPermutationSize(1), ...
                actualPermutationSize(2)), ...
                resultFile);
        elseif ~isempty(permutations)

            nTrials = size(permutations, 1);
            nGenerated = size(permutations, 2);
            originalOrder = (1:nTrials)';

            columnsArePermutations = true(1, nGenerated);
            columnsAreDerangements = true(1, nGenerated);

            for surrogateIndex = 1:nGenerated

                currentPermutation = ...
                    permutations(:, surrogateIndex);

                columnsArePermutations(surrogateIndex) = ...
                    isequal(sort(currentPermutation), originalOrder);

                columnsAreDerangements(surrogateIndex) = ...
                    all(currentPermutation ~= originalOrder);
            end

            if any(~columnsArePermutations)

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "InvalidTrialPermutation", ...
                    ['At least one surrogate column was not a valid ' ...
                    'permutation of the trial indices.'], ...
                    resultFile);
            end

            if any(~columnsAreDerangements)

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "NonDerangementSurrogate", ...
                    ['At least one surrogate retained an original ' ...
                    'Knower-Guesser trial pairing.'], ...
                    resultFile);
            end

            numberOfUniqueColumns = ...
                size(unique(permutations', 'rows'), 1);

            record.NumUniqueSurrogatePermutations = ...
                numberOfUniqueColumns;

            if numberOfUniqueColumns ~= nGenerated

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "DuplicateSurrogatePermutations", ...
                    sprintf(['Stored %d surrogate columns but only %d ' ...
                    'were unique.'], ...
                    nGenerated, numberOfUniqueColumns), ...
                    resultFile);
            end
        end

        % HyperYESNO provenance.
        if ~isfield(results, 'hyperyesno') || ...
                ~isstruct(results.hyperyesno)

            fileIsValid = false;

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "ERROR", "MissingHyperYESNOProvenance", ...
                "The results.hyperyesno structure was absent.", ...
                resultFile);
        else
            provenance = results.hyperyesno;

            if ~isfield(provenance, 'dyad') || ...
                    double(provenance.dyad) ~= dyadNumber

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "DyadMetadataMismatch", ...
                    "The stored dyad metadata did not match the file path.", ...
                    resultFile);
            end

            if ~isfield(provenance, 'situation') || ...
                    ~strcmp(string(provenance.situation), ...
                    string(situationName))

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "SituationMetadataMismatch", ...
                    ['The stored situation metadata did not match the ' ...
                    'folder and filename.'], ...
                    resultFile);
            end

            if ~isfield(provenance, 'dataAAnalysisRole') || ...
                    ~strcmpi(string(provenance.dataAAnalysisRole), ...
                    "Knower") || ...
                    ~isfield(provenance, 'dataBAnalysisRole') || ...
                    ~strcmpi(string(provenance.dataBAnalysisRole), ...
                    "Guesser")

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "RoleOrderingMismatch", ...
                    ['Step 8 requires dataA=Knower and dataB=Guesser, ' ...
                    'but the stored provenance did not confirm this.'], ...
                    resultFile);
            end
        end

        % Optional recalculation of surrogate summaries.
        if options.VerifySurrogateSummaries && ...
                nSurrogatesInArray > 0

            recalculatedMean = ...
                mean(results.gcmiSurrogates, 4);

            recalculatedStd = ...
                std(results.gcmiSurrogates, 0, 4);

            meanDifference = maximum_absolute_difference( ...
                recalculatedMean, ...
                results.gcmiSurrogateMean);

            stdDifference = maximum_absolute_difference( ...
                recalculatedStd, ...
                results.gcmiSurrogateStd);

            record.SurrogateMeanMaximumDifference = ...
                meanDifference;

            record.SurrogateStdMaximumDifference = ...
                stdDifference;

            if meanDifference > options.SummaryTolerance

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "SurrogateMeanMismatch", ...
                    sprintf(['Stored and recalculated surrogate means ' ...
                    'differed by up to %.12g.'], meanDifference), ...
                    resultFile);
            end

            if stdDifference > options.SummaryTolerance

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "SurrogateStdMismatch", ...
                    sprintf(['Stored and recalculated surrogate standard ' ...
                    'deviations differed by up to %.12g.'], ...
                    stdDifference), ...
                    resultFile);
            end
        end

        %% ----------------------------------------------------------------
        % 4.5 Non-excluding warnings
        % -----------------------------------------------------------------

        if double(results.numberOfTrials) < ...
                options.MinimumTrialsWarning

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "LowTrialCount", ...
                sprintf(['Only %d paired trials were available; the file ' ...
                'was retained.'], ...
                double(results.numberOfTrials)), ...
                resultFile);
        end

        if double(results.numberOfSurrogatesGenerated) < ...
                options.MinimumSurrogatesWarning

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "LowSurrogateCount", ...
                sprintf(['Only %d unique derangements were available; ' ...
                'the file was retained.'], ...
                double(results.numberOfSurrogatesGenerated)), ...
                resultFile);
        end

        if record.ObservedFinitePercent < 100

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "NonfiniteObservedValues", ...
                sprintf('Observed finite values: %.6f%%.', ...
                record.ObservedFinitePercent), ...
                resultFile);
        end

        if isfinite(record.SurrogateFinitePercent) && ...
                record.SurrogateFinitePercent < 100

            qcRows = add_qc(qcRows, ...
                dyadName, dyadNumber, situationName, ...
                "WARNING", "NonfiniteSurrogateValues", ...
                sprintf('Surrogate finite values: %.6f%%.', ...
                record.SurrogateFinitePercent), ...
                resultFile);
        end

        %% ----------------------------------------------------------------
        % 4.6 Establish or verify the group reference
        % -----------------------------------------------------------------

        if fileIsValid && ~groupArraysAllocated

            reference.numberOfKnowerROIs = nKnowerROIs;
            reference.numberOfGuesserROIs = nGuesserROIs;
            reference.numberOfLags = nLags;
            reference.roiLabelsKnower = labelsKnower;
            reference.roiLabelsGuesser = labelsGuesser;
            reference.lagsSamples = lagsSamples;
            reference.lagsMilliseconds = lagsMilliseconds;
            reference.requestedLagsMilliseconds = ...
                requestedLagsMilliseconds;
            reference.samplingRate = double(results.samplingRate);
            reference.sourceFile = string(resultFile);

            gcmiObserved = nan( ...
                nKnowerROIs, ...
                nGuesserROIs, ...
                nLags, ...
                numberOfDyads, ...
                numberOfSituations);

            gcmiSurrogateMean = nan(size(gcmiObserved));
            gcmiSurrogateStd = nan(size(gcmiObserved));

            groupArraysAllocated = true;

            if options.Verbose
                fprintf('  Established the group reference from this file.\n');
            end
        end

        if fileIsValid && groupArraysAllocated

            consistencyIssues = strings(0, 1);

            if nKnowerROIs ~= reference.numberOfKnowerROIs || ...
                    nGuesserROIs ~= ...
                    reference.numberOfGuesserROIs || ...
                    nLags ~= reference.numberOfLags

                consistencyIssues(end + 1) = ...
                    "array dimensions"; %#ok<AGROW>
            end

            if ~isequal(labelsKnower, ...
                    reference.roiLabelsKnower)

                consistencyIssues(end + 1) = ...
                    "Knower ROI labels/order"; %#ok<AGROW>
            end

            if ~isequal(labelsGuesser, ...
                    reference.roiLabelsGuesser)

                consistencyIssues(end + 1) = ...
                    "Guesser ROI labels/order"; %#ok<AGROW>
            end

            if ~isequal(lagsSamples, ...
                    reference.lagsSamples)

                consistencyIssues(end + 1) = ...
                    "lag samples"; %#ok<AGROW>
            end

            if ~isequal(lagsMilliseconds, ...
                    reference.lagsMilliseconds)

                consistencyIssues(end + 1) = ...
                    "lag milliseconds"; %#ok<AGROW>
            end

            if abs(double(results.samplingRate) - ...
                    reference.samplingRate) > 1e-10

                consistencyIssues(end + 1) = ...
                    "sampling rate"; %#ok<AGROW>
            end

            if ~isempty(consistencyIssues)

                fileIsValid = false;

                qcRows = add_qc(qcRows, ...
                    dyadName, dyadNumber, situationName, ...
                    "ERROR", "GroupReferenceMismatch", ...
                    "Mismatch in: " + ...
                    strjoin(consistencyIssues, ', ') + ".", ...
                    resultFile);
            end
        end

        %% ----------------------------------------------------------------
        % 4.7 Add valid data to the group arrays
        % -----------------------------------------------------------------

        if fileIsValid

            gcmiObserved(:, :, :, dyadIndex, situationIndex) = ...
                double(results.gcmiObserved);

            gcmiSurrogateMean(:, :, :, dyadIndex, situationIndex) = ...
                double(results.gcmiSurrogateMean);

            gcmiSurrogateStd(:, :, :, dyadIndex, situationIndex) = ...
                double(results.gcmiSurrogateStd);

            validMask(dyadIndex, situationIndex) = true;

            numberOfTrials(dyadIndex, situationIndex) = ...
                double(results.numberOfTrials);

            numberOfObservationsPerLag(dyadIndex, situationIndex) = ...
                double(results.numberOfObservationsPerLag);

            numberOfSurrogatesRequested(dyadIndex, situationIndex) = ...
                double(results.numberOfSurrogatesRequested);

            numberOfSurrogatesGenerated(dyadIndex, situationIndex) = ...
                double(results.numberOfSurrogatesGenerated);

            if isfield(results, 'maximumUniqueDerangements')
                maximumUniqueDerangements(dyadIndex, situationIndex) = ...
                    double(results.maximumUniqueDerangements);
            end

            if isfield(results, 'allUniqueDerangementsUsed')
                allUniqueDerangementsUsed(dyadIndex, situationIndex) = ...
                    logical(results.allUniqueDerangementsUsed);
            end

            if isfield(results, 'surrogateGenerationMode')
                surrogateGenerationMode(dyadIndex, situationIndex) = ...
                    string(results.surrogateGenerationMode);
            end

            record.Status = "loaded";
            record.IncludedInGroupArrays = true;

            if options.Verbose
                fprintf(['  Loaded: %d x %d ROIs, %d lags, ' ...
                    '%d trials, %d surrogates.\n'], ...
                    nKnowerROIs, nGuesserROIs, nLags, ...
                    double(results.numberOfTrials), ...
                    double(results.numberOfSurrogatesGenerated));
            end
        else
            record.Status = "failed_validation";
            record.IncludedInGroupArrays = false;

            if options.Verbose
                fprintf('  Excluded from group arrays after validation.\n');
            end
        end

        fileRows = append_struct(fileRows, record);
        loadStatus(dyadIndex, situationIndex) = record.Status;

        clear results permutations recalculatedMean recalculatedStd
    end
end


%% ========================================================================
% 5. Assemble outputs
% ========================================================================

if ~groupArraysAllocated

    error('step8:NoValidFiles', ...
        ['No valid Step 7 result files were available. Consult the QC ' ...
        'messages printed above and confirm the input paths.']);
end

groupData = struct;

groupData.step = 8;
groupData.description = ...
    'Validated compact group arrays from Step 7 lagged GCMI';

groupData.rootDir = rootDir;
groupData.inputFolderName = inputFolderName;
groupData.outputFolder = outputFolder;

groupData.dyadNumbers = dyads;
groupData.dyadNames = string(compose('Dyad%02d', dyads));

groupData.situations = string(situations);
groupData.conditions = situationCondition;
groupData.knowerParticipants = situationKnower;
groupData.guesserParticipants = situationGuesser;

groupData.arrayDimensionOrder = ...
    'KnowerROI x GuesserROI x Lag x Dyad x Situation';

groupData.lagConvention = [ ...
    'negative lag = Knower precedes Guesser; ', ...
    'positive lag = Guesser precedes Knower'];

groupData.roiLabelsKnower = reference.roiLabelsKnower;
groupData.roiLabelsGuesser = reference.roiLabelsGuesser;
groupData.lagsSamples = reference.lagsSamples;
groupData.lagsMilliseconds = reference.lagsMilliseconds;
groupData.requestedLagsMilliseconds = ...
    reference.requestedLagsMilliseconds;
groupData.samplingRate = reference.samplingRate;

groupData.gcmiObserved = gcmiObserved;
groupData.gcmiSurrogateMean = gcmiSurrogateMean;
groupData.gcmiSurrogateStd = gcmiSurrogateStd;

groupData.validMask = validMask;
groupData.numberOfTrials = numberOfTrials;
groupData.numberOfObservationsPerLag = ...
    numberOfObservationsPerLag;
groupData.numberOfSurrogatesRequested = ...
    numberOfSurrogatesRequested;
groupData.numberOfSurrogatesGenerated = ...
    numberOfSurrogatesGenerated;
groupData.maximumUniqueDerangements = ...
    maximumUniqueDerangements;
groupData.allUniqueDerangementsUsed = ...
    allUniqueDerangementsUsed;
groupData.surrogateGenerationMode = ...
    surrogateGenerationMode;

groupData.resultFilePaths = resultFilePaths;
groupData.loadStatus = loadStatus;

groupData.fullSurrogatesRetainedInMemory = false;
groupData.fullSurrogateSource = ...
    'Original Step 7 MAT files listed in groupData.resultFilePaths';

groupData.referenceFile = reference.sourceFile;
groupData.created = datestr(now, 30);
groupData.loaderFunction = mfilename;
groupData.settings = options;

fileTable = struct_array_to_table(fileRows);
qcTable = struct_array_to_table(qcRows);

if ~isempty(fileTable)
    fileTable = sortrows(fileTable, ...
        {'DyadNumber', 'Situation'});
end

if ~isempty(qcTable)
    qcTable = sortrows(qcTable, ...
        {'DyadNumber', 'Situation', 'Severity', 'Issue'});
end


%% ========================================================================
% 6. Save outputs
% ========================================================================

if options.SaveOutputs

    matFile = fullfile( ...
        outputFolder, ...
        'Step8_HyperYESNO_group_GCMI.mat');

    save(matFile, ...
        'groupData', ...
        'fileTable', ...
        'qcTable', ...
        '-v7.3');

    excelFile = fullfile( ...
        outputFolder, ...
        'Step8_HyperYESNO_group_GCMI_QC.xlsx');

    if exist(excelFile, 'file') == 2
        delete(excelFile);
    end

    write_table_safely(fileTable, excelFile, 'FileSummary');
    write_table_safely(qcTable, excelFile, 'QC');

    arrayGuide = table( ...
        ["gcmiObserved"; ...
         "gcmiSurrogateMean"; ...
         "gcmiSurrogateStd"], ...
        repmat(string(groupData.arrayDimensionOrder), 3, 1), ...
        repmat(string(groupData.lagConvention), 3, 1), ...
        'VariableNames', { ...
        'Array', ...
        'DimensionOrder', ...
        'LagConvention'});

    writetable(arrayGuide, excelFile, 'Sheet', 'ArrayGuide');

    groupData.savedMatFile = string(matFile);
    groupData.savedQCWorkbook = string(excelFile);

    % Save once more so the output paths are also present in groupData.
    save(matFile, ...
        'groupData', ...
        'fileTable', ...
        'qcTable', ...
        '-v7.3');
end


%% ========================================================================
% 7. Final report
% ========================================================================

if options.Verbose

    totalRequested = numberOfDyads * numberOfSituations;
    totalLoaded = sum(validMask(:));

    fprintf('\n============================================================\n');
    fprintf('Step 8 group loading completed.\n');
    fprintf('Requested files:              %d\n', totalRequested);
    fprintf('Valid files loaded:           %d\n', totalLoaded);
    fprintf('Files not loaded:             %d\n', ...
        totalRequested - totalLoaded);
    fprintf('Dyads represented:            %d of %d\n', ...
        sum(any(validMask, 2)), numberOfDyads);
    fprintf('Complete dyads (all states):  %d of %d\n', ...
        sum(all(validMask, 2)), numberOfDyads);
    fprintf('QC entries:                   %d\n', height(qcTable));
    fprintf('Array order:                  %s\n', ...
        groupData.arrayDimensionOrder);

    if options.SaveOutputs
        fprintf('MAT output:                   %s\n', matFile);
        fprintf('QC workbook:                  %s\n', excelFile);
    end

    fprintf('============================================================\n');
end

end


%% ========================================================================
function record = initialize_file_record( ...
    dyadName, dyadNumber, situationName, condition, ...
    knower, guesser, resultFile)
% INITIALIZE_FILE_RECORD
% Create a fixed-type record for one requested Step 7 file.

record = struct;

record.Dyad = string(dyadName);
record.DyadNumber = double(dyadNumber);
record.Situation = string(situationName);
record.Condition = string(condition);
record.KnowerParticipant = string(knower);
record.GuesserParticipant = string(guesser);
record.ResultFile = string(resultFile);

record.Status = "not_processed";
record.IncludedInGroupArrays = false;

record.NumKnowerROIs = NaN;
record.NumGuesserROIs = NaN;
record.NumLags = NaN;
record.SamplingRateHz = NaN;

record.NumTrials = NaN;
record.NumObservationsPerLag = NaN;

record.NumSurrogatesRequested = NaN;
record.NumSurrogatesGenerated = NaN;
record.NumSurrogatesStored = NaN;
record.NumUniqueSurrogatePermutations = NaN;
record.MaximumUniqueDerangements = NaN;
record.AllUniqueDerangementsUsed = false;
record.SurrogateGenerationMode = "";

record.ObservedFinitePercent = NaN;
record.SurrogateFinitePercent = NaN;

record.SurrogateMeanMaximumDifference = NaN;
record.SurrogateStdMaximumDifference = NaN;

end


%% ========================================================================
function qcRows = add_qc( ...
    qcRows, dyadName, dyadNumber, situationName, ...
    severity, issue, details, resultFile)
% ADD_QC
% Append one QC row using a structure array. No cell2table or cell2mat
% conversions are used.

row = struct;

row.Dyad = string(dyadName);
row.DyadNumber = double(dyadNumber);
row.Situation = string(situationName);
row.Severity = string(severity);
row.Issue = string(issue);
row.Details = string(details);
row.ResultFile = string(resultFile);

qcRows = append_struct(qcRows, row);

end


%% ========================================================================
function output = append_struct(output, row)
% APPEND_STRUCT
% Append a structure with a fixed set of fields.

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
function outputSize = size3(inputArray)
% SIZE3
% Return exactly the first three dimensions, including trailing singleton
% dimensions.

outputSize = size(inputArray);
outputSize(end + 1:3) = 1;
outputSize = outputSize(1:3);

end


%% ========================================================================
function maximumDifference = maximum_absolute_difference(a, b)
% MAXIMUM_ABSOLUTE_DIFFERENCE
% Compare arrays while handling matching NaN positions.

if ~isequal(size(a), size(b))
    maximumDifference = Inf;
    return
end

matchingNaN = isnan(a) & isnan(b);
difference = abs(a - b);
difference(matchingNaN) = 0;

if any(xor(isnan(a), isnan(b)), 'all')
    maximumDifference = Inf;
    return
end

finiteDifference = difference(isfinite(difference));

if isempty(finiteDifference)
    maximumDifference = 0;
else
    maximumDifference = max(finiteDifference);
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
