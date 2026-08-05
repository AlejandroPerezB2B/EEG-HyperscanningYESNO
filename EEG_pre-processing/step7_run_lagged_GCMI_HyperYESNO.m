function [summaryTable, trialCountTable] = ...
    step7_run_lagged_GCMI_HyperYESNO(rootDir, dyads, varargin)
% STEP7_RUN_LAGGED_GCMI_HYPERYESNO
% Run lagged_gcmi_dyad.m on the matched, role-normalized HyperYESNO epochs.
%
% The wrapper always passes:
%
%       dataA = Knower
%       dataB = Guesser
%
% This guarantees a consistent analytical ordering regardless of whether
% the Knower originated from SubjA or SubjB.
%
% IMPORTANT LAG CONVENTION
% ------------------------
% lagged_gcmi_dyad.m follows Robin Ince's original convention:
%
%       negative lag = dataA precedes dataB
%       positive lag = dataB precedes dataA
%
% Because this wrapper always passes Knower as dataA and Guesser as dataB:
%
%       negative lag = Knower precedes Guesser
%       positive lag = Guesser precedes Knower
%
% INPUT DATA
% ----------
% Step 6 role-normalized files are expected under:
%
%   DyadXX/GCMI_Epochs/YES_AKnower/
%   DyadXX/GCMI_Epochs/NO_AKnower/
%   DyadXX/GCMI_Epochs/YES_BKnower/
%   DyadXX/GCMI_Epochs/NO_BKnower/
%
% Example pair:
%
%   Dyad01_YES_AKnower_Knower_fromA.set
%   Dyad01_YES_AKnower_Guesser_fromB.set
%
% TRIAL HANDLING
% --------------
% The wrapper uses all available matched epochs in each situation.
%
% It does not:
%
%   - subsample trials;
%   - balance trial counts across YES and NO;
%   - balance A-Knower and B-Knower situations; or
%   - discard trials to match the smallest condition.
%
% Trial counts are allowed to differ across situations. The exact number of
% trials and observations used for every GCMI estimate is saved in:
%
%   Step7_GCMI_trial_counts.xlsx
%   Step7_GCMI_trial_counts.mat
%
% FILTERING
% ---------
% This wrapper performs no filtering.
%
% lagged_gcmi_dyad.m also performs no filtering and expects the input to
% have already been filtered into the frequency band of interest.
%
% By default, this wrapper verifies that the Step 6 metadata reports:
%
%       8-13 Hz
%
% This metadata check can be disabled if necessary, but no signal filtering
% is performed under any setting.
%
% LAG CONVERSION
% --------------
% Requested lags are supplied in milliseconds to lagged_gcmi_dyad.m.
% That function converts them using:
%
%       lagSamples = round(lagMilliseconds * samplingRate / 1000)
%
% At 100 Hz:
%
%       one sample = 10 ms
%       50 ms      = 5 samples
%       500 ms     = 50 samples
%
% Therefore, the default:
%
%       -500:50:500 ms
%
% becomes exactly:
%
%       -50:5:50 samples
%
% OUTPUT
% ------
% One MAT file is saved for each dyad and situation:
%
%   DyadXX/Lagged_GCMI/SITUATION/
%       DyadXX_SITUATION_lagged_GCMI.mat
%
% The file contains:
%
%   results.gcmiObserved
%   results.gcmiSurrogates
%   results.gcmiSurrogateMean
%   results.gcmiSurrogateStd
%   results.lagsSamples
%   results.lagsMilliseconds
%   results.numberOfTrials
%   results.numberOfObservationsPerLag
%   results.hyperyesno
%
% INPUTS
% ------
% rootDir
%   HyperYESNO data root.
%   Default: 'E:\EEG_data_HyperYESNO'
%
% dyads
%   Dyad numbers to process.
%   Default: 1
%
% NAME-VALUE OPTIONS
% ------------------
% 'Situations'
%   Situations to process. May be a character vector, string, or cell array.
%
%   Allowed values:
%       'YES_AKnower'
%       'NO_AKnower'
%       'YES_BKnower'
%       'NO_BKnower'
%
%   Default: all four situations
%
% 'EpochFolderName'
%   Step 6 output folder inside each dyad.
%   Default: 'GCMI_Epochs'
%
% 'OutputFolderName'
%   GCMI result folder inside each dyad.
%   Default: 'Lagged_GCMI'
%
% 'LagsMs'
%   Requested lag values in milliseconds.
%   Default: -500:50:500
%
% 'NumSurrogates'
%   Number of paired-trial derangement surrogates.
%   Default: 19
%
% 'RandomSeed'
%   Base random seed. A reproducible situation-specific offset is added.
%   Default: 1
%
% 'UseParallel'
%   Use PARFOR inside lagged_gcmi_dyad.m.
%   Default: false
%
% 'ExpectedFilterBandHz'
%   Expected Step 6 filter metadata.
%   Default: [8 13]
%
% 'RequireExpectedFilterBand'
%   true:
%       stop when filter metadata is absent or does not equal the expected
%       band.
%
%   false:
%       report a warning and continue.
%
%   Default: true
%
% 'OverwriteExisting'
%   Overwrite existing GCMI result MAT files.
%   Default: false
%
% 'Verbose'
%   Print progress from the wrapper and lagged_gcmi_dyad.m.
%   Default: true
%
% OUTPUTS
% -------
% summaryTable
%   Detailed one-row-per-dyad-and-situation processing table.
%
% trialCountTable
%   Compact table documenting the trials and observations used in every
%   GCMI calculation.
%
% EXAMPLES
% --------
% First computational-time test: one dyad, one situation, no surrogates.
%
%   eeglab;
%   close;
%
%   [summaryTable, trialCountTable] = ...
%       step7_run_lagged_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       1, ...
%       'Situations', 'YES_AKnower', ...
%       'NumSurrogates', 0);
%
% Run one dyad and one situation with 19 surrogates:
%
%   [summaryTable, trialCountTable] = ...
%       step7_run_lagged_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       1, ...
%       'Situations', 'YES_AKnower', ...
%       'NumSurrogates', 19);
%
% Run all four situations for one dyad:
%
%   [summaryTable, trialCountTable] = ...
%       step7_run_lagged_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       1);
%
% Later, run the complete dataset:
%
%   [summaryTable, trialCountTable] = ...
%       step7_run_lagged_GCMI_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       1:35, ...
%       'NumSurrogates', 19);
%
% DEPENDENCIES
% ------------
% - EEGLAB
% - lagged_gcmi_dyad.m
% - copnorm.m from Robin Ince's GCMI toolbox
% - Parallel Computing Toolbox only when UseParallel=true
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

%% ========================================================================
% 1. Defaults and input parsing
% ========================================================================

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1;
end

rootDir = char(rootDir);

validateattributes(dyads, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'});

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, 'Situations', ...
    {'YES_AKnower', 'NO_AKnower', ...
     'YES_BKnower', 'NO_BKnower'}, ...
    @(x) ischar(x) || isstring(x) || iscell(x));

addParameter(parser, 'EpochFolderName', ...
    'GCMI_Epochs', ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, 'OutputFolderName', ...
    'Lagged_GCMI', ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, 'LagsMs', ...
    -500:50:500, ...
    @(x) isnumeric(x) && isvector(x) && ...
    ~isempty(x) && all(isfinite(x)));

addParameter(parser, 'NumSurrogates', ...
    19, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 0 && x == round(x));

addParameter(parser, 'RandomSeed', ...
    1, ...
    @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x >= 0 && x == round(x));

addParameter(parser, 'UseParallel', ...
    false, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'ExpectedFilterBandHz', ...
    [8 13], ...
    @(x) isempty(x) || ...
    (isnumeric(x) && numel(x) == 2 && ...
    all(isfinite(x)) && x(1) > 0 && x(2) > x(1)));

addParameter(parser, 'RequireExpectedFilterBand', ...
    true, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'OverwriteExisting', ...
    false, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'Verbose', ...
    true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, varargin{:});
options = parser.Results;

options.EpochFolderName = char(options.EpochFolderName);
options.OutputFolderName = char(options.OutputFolderName);
options.LagsMs = double(options.LagsMs(:)');
options.ExpectedFilterBandHz = ...
    double(options.ExpectedFilterBandHz(:)');

selectedSituationNames = ...
    local_normalise_situation_input(options.Situations);

%% ========================================================================
% 2. Dependencies and root folder
% ========================================================================

if exist(rootDir, 'dir') ~= 7
    error('HyperYESNO root directory not found: %s', rootDir);
end

requiredFunctions = { ...
    'pop_loadset', ...
    'lagged_gcmi_dyad', ...
    'copnorm'};

for iFunction = 1:numel(requiredFunctions)

    if exist(requiredFunctions{iFunction}, 'file') ~= 2
        error(['Required function "%s" was not found on the MATLAB path.'], ...
            requiredFunctions{iFunction});
    end
end

if options.UseParallel && ...
        license('test', 'Distrib_Computing_Toolbox') ~= 1

    error(['UseParallel=true requires the MATLAB Parallel Computing ', ...
        'Toolbox.']);
end

%% ========================================================================
% 3. Define and select the four situations
% ========================================================================

allSituations = struct( ...
    'marker', { ...
        'YES_AKnower', ...
        'NO_AKnower', ...
        'YES_BKnower', ...
        'NO_BKnower'}, ...
    'condition', { ...
        'YES', ...
        'NO', ...
        'YES', ...
        'NO'}, ...
    'knowerParticipant', { ...
        'A', ...
        'A', ...
        'B', ...
        'B'}, ...
    'guesserParticipant', { ...
        'B', ...
        'B', ...
        'A', ...
        'A'});

allSituationNames = string({allSituations.marker});

selectedMask = ismember( ...
    allSituationNames, ...
    selectedSituationNames);

situations = allSituations(selectedMask);

if isempty(situations)
    error('No valid situations were selected.');
end

%% ========================================================================
% 4. Preallocate summary records
% ========================================================================

numberOfRecords = numel(dyads) * numel(situations);

records = repmat( ...
    local_empty_summary_record(), ...
    numberOfRecords, ...
    1);

recordCounter = 0;
pipelineTimer = tic;

%% ========================================================================
% 5. Process each dyad and situation
% ========================================================================

for iDyad = 1:numel(dyads)

    d = dyads(iDyad);
    dyadStr = sprintf('Dyad%02d', d);

    for iSituation = 1:numel(situations)

        recordCounter = recordCounter + 1;
        calculationTimer = tic;

        situation = situations(iSituation);

        record = local_empty_summary_record();

        record.Dyad = d;
        record.DyadName = string(dyadStr);
        record.Situation = string(situation.marker);
        record.Condition = string(situation.condition);
        record.KnowerParticipant = ...
            string(situation.knowerParticipant);
        record.GuesserParticipant = ...
            string(situation.guesserParticipant);
        record.RequestedLagStartMs = ...
            options.LagsMs(1);
        record.RequestedLagEndMs = ...
            options.LagsMs(end);
        record.RequestedLagCount = ...
            numel(options.LagsMs);
        record.NumSurrogates = ...
            options.NumSurrogates;
        record.UseParallel = ...
            options.UseParallel;

        if ~isempty(options.ExpectedFilterBandHz)
            record.ExpectedFilterLowHz = ...
                options.ExpectedFilterBandHz(1);
            record.ExpectedFilterHighHz = ...
                options.ExpectedFilterBandHz(2);
        end

        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('Step 7 lagged GCMI: %s %s\n', ...
            dyadStr, situation.marker);
        fprintf('Knower: participant %s; Guesser: participant %s\n', ...
            situation.knowerParticipant, ...
            situation.guesserParticipant);
        fprintf('============================================================\n');

        try

            %% ------------------------------------------------------------
            % 5.1 Construct exact Step 6 file paths
            % -------------------------------------------------------------

            situationFolder = fullfile( ...
                rootDir, ...
                dyadStr, ...
                options.EpochFolderName, ...
                situation.marker);

            knowerFile = sprintf( ...
                '%s_%s_Knower_from%s.set', ...
                dyadStr, ...
                situation.marker, ...
                situation.knowerParticipant);

            guesserFile = sprintf( ...
                '%s_%s_Guesser_from%s.set', ...
                dyadStr, ...
                situation.marker, ...
                situation.guesserParticipant);

            knowerPath = fullfile( ...
                situationFolder, knowerFile);

            guesserPath = fullfile( ...
                situationFolder, guesserFile);

            record.KnowerInputFile = string(knowerPath);
            record.GuesserInputFile = string(guesserPath);

            if exist(knowerPath, 'file') ~= 2
                error('Knower input file not found: %s', knowerPath);
            end

            if exist(guesserPath, 'file') ~= 2
                error('Guesser input file not found: %s', guesserPath);
            end

            %% ------------------------------------------------------------
            % 5.2 Construct exact GCMI output path
            % -------------------------------------------------------------

            outputFolder = fullfile( ...
                rootDir, ...
                dyadStr, ...
                options.OutputFolderName, ...
                situation.marker);

            if exist(outputFolder, 'dir') ~= 7
                mkdir(outputFolder);
            end

            outputFile = fullfile( ...
                outputFolder, ...
                sprintf('%s_%s_lagged_GCMI.mat', ...
                dyadStr, situation.marker));

            record.OutputFile = string(outputFile);

            if exist(outputFile, 'file') == 2 && ...
                    ~options.OverwriteExisting

                error(['Output file already exists and ', ...
                    'OverwriteExisting=false: %s'], ...
                    outputFile);
            end

            %% ------------------------------------------------------------
            % 5.3 Load matched Knower and Guesser epochs
            % -------------------------------------------------------------

            EEG_Knower = pop_loadset( ...
                'filename', knowerFile, ...
                'filepath', situationFolder);

            EEG_Guesser = pop_loadset( ...
                'filename', guesserFile, ...
                'filepath', situationFolder);

            EEG_Knower = eeg_checkset( ...
                EEG_Knower, 'eventconsistency');

            EEG_Guesser = eeg_checkset( ...
                EEG_Guesser, 'eventconsistency');

            validation = local_validate_epoched_pair( ...
                EEG_Knower, ...
                EEG_Guesser, ...
                situation);

            record.PairIDsVerified = ...
                validation.pairIDsVerified;

            record.AnalysisRolesVerified = ...
                validation.analysisRolesVerified;

            record.SamplingRateHz = ...
                EEG_Knower.srate;

            record.NumberOfROIs = ...
                EEG_Knower.nbchan;

            record.NumberOfTrials = ...
                EEG_Knower.trials;

            record.SamplesPerTrial = ...
                EEG_Knower.pnts;

            record.EpochStartMs = ...
                EEG_Knower.xmin * 1000;

            record.EpochEndMs = ...
                EEG_Knower.xmax * 1000;

            %% ------------------------------------------------------------
            % 5.4 Verify the pre-existing 8-13 Hz filter metadata
            % -------------------------------------------------------------

            [filterBandKnower, filterStatusKnower] = ...
                local_get_filter_metadata(EEG_Knower);

            [filterBandGuesser, filterStatusGuesser] = ...
                local_get_filter_metadata(EEG_Guesser);

            filterVerification = ...
                local_verify_filter_metadata( ...
                filterBandKnower, ...
                filterStatusKnower, ...
                filterBandGuesser, ...
                filterStatusGuesser, ...
                options.ExpectedFilterBandHz, ...
                options.RequireExpectedFilterBand, ...
                dyadStr, ...
                situation.marker);

            record.FilterMetadataStatus = ...
                string(filterVerification.status);

            record.FilterVerified = ...
                filterVerification.verified;

            if ~isempty(filterVerification.band)

                record.InputFilterLowHz = ...
                    filterVerification.band(1);

                record.InputFilterHighHz = ...
                    filterVerification.band(2);
            end

            %% ------------------------------------------------------------
            % 5.5 Verify lag conversion at the actual sampling rate
            % -------------------------------------------------------------

            requestedLagSamples = round( ...
                options.LagsMs .* ...
                double(EEG_Knower.srate) ./ ...
                1000);

            [expectedLagSamples, uniqueIndices] = ...
                unique(requestedLagSamples, 'stable');

            expectedRequestedLagsMs = ...
                options.LagsMs(uniqueIndices);

            expectedActualLagsMs = ...
                expectedLagSamples .* ...
                1000 ./ ...
                double(EEG_Knower.srate);

            if options.Verbose

                fprintf('Input filtering: already applied; no filtering now.\n');
                fprintf('Sampling rate:   %.3f Hz\n', EEG_Knower.srate);
                fprintf('Sample period:   %.3f ms\n', ...
                    1000 / EEG_Knower.srate);
                fprintf('Requested lags:  %.3f to %.3f ms\n', ...
                    options.LagsMs(1), options.LagsMs(end));
                fprintf('Actual samples:  %s\n', ...
                    mat2str(expectedLagSamples));
                fprintf('Trials used:     %d (all available matched trials)\n', ...
                    EEG_Knower.trials);
            end

            %% ------------------------------------------------------------
            % 5.6 Create a reproducible situation-specific random seed
            % -------------------------------------------------------------

            effectiveRandomSeed = ...
                options.RandomSeed + ...
                d * 100 + ...
                find(strcmpi( ...
                situation.marker, ...
                {allSituations.marker}), 1);

            record.EffectiveRandomSeed = ...
                effectiveRandomSeed;

            %% ------------------------------------------------------------
            % 5.7 Run lagged_gcmi_dyad.m without any filtering
            % -------------------------------------------------------------

            results = lagged_gcmi_dyad( ...
                EEG_Knower.data, ...
                EEG_Guesser.data, ...
                EEG_Knower.srate, ...
                'LagsMs', options.LagsMs, ...
                'NumSurrogates', options.NumSurrogates, ...
                'RandomSeed', effectiveRandomSeed, ...
                'ChannelLabelsA', ...
                {EEG_Knower.chanlocs.labels}, ...
                'ChannelLabelsB', ...
                {EEG_Guesser.chanlocs.labels}, ...
                'UseParallel', options.UseParallel, ...
                'OutputFile', '', ...
                'Verbose', options.Verbose);

            %% ------------------------------------------------------------
            % 5.8 Confirm the function used the expected lag grid
            % -------------------------------------------------------------

            if ~isequal( ...
                    double(results.lagsSamples), ...
                    double(expectedLagSamples))

                error(['lagged_gcmi_dyad returned unexpected sample ', ...
                    'offsets. Expected %s; observed %s.'], ...
                    mat2str(expectedLagSamples), ...
                    mat2str(results.lagsSamples));
            end

            if ~isequal( ...
                    double(results.requestedLagsMilliseconds), ...
                    double(expectedRequestedLagsMs))

                error(['lagged_gcmi_dyad returned unexpected requested ', ...
                    'lag values after duplicate-offset removal.']);
            end

            if any(abs( ...
                    double(results.lagsMilliseconds) - ...
                    double(expectedActualLagsMs)) > 1e-10)

                error(['lagged_gcmi_dyad returned unexpected actual ', ...
                    'lag values.']);
            end

            %% ------------------------------------------------------------
            % 5.9 Add HyperYESNO-specific provenance
            % -------------------------------------------------------------

            hyperyesno = struct();

            hyperyesno.dyad = d;
            hyperyesno.dyadName = dyadStr;
            hyperyesno.situation = situation.marker;
            hyperyesno.condition = situation.condition;

            hyperyesno.knowerParticipant = ...
                situation.knowerParticipant;

            hyperyesno.guesserParticipant = ...
                situation.guesserParticipant;

            hyperyesno.dataAAnalysisRole = 'Knower';
            hyperyesno.dataBAnalysisRole = 'Guesser';

            hyperyesno.knowerInputFile = ...
                knowerPath;

            hyperyesno.guesserInputFile = ...
                guesserPath;

            hyperyesno.allAvailableTrialsUsed = true;
            hyperyesno.trialBalancingApplied = false;
            hyperyesno.numberOfTrialsUsed = ...
                EEG_Knower.trials;

            hyperyesno.pairIDs = ...
                cellstr(validation.pairIDs);

            hyperyesno.filteringAppliedByWrapper = false;
            hyperyesno.filteringAppliedByLaggedFunction = false;
            hyperyesno.inputFilterBandHz = ...
                filterVerification.band;
            hyperyesno.filterMetadataStatus = ...
                filterVerification.status;

            hyperyesno.requestedLagsMilliseconds = ...
                options.LagsMs;

            hyperyesno.expectedLagSamplesFromSamplingRate = ...
                expectedLagSamples;

            hyperyesno.expectedActualLagsMilliseconds = ...
                expectedActualLagsMs;

            hyperyesno.lagConvention = [ ...
                'negative lag = Knower precedes Guesser; ', ...
                'positive lag = Guesser precedes Knower'];

            hyperyesno.roleOrdering = ...
                'dataA=Knower; dataB=Guesser';

            hyperyesno.step6EpochMetadataKnower = ...
                local_get_epoch_metadata(EEG_Knower);

            hyperyesno.step6EpochMetadataGuesser = ...
                local_get_epoch_metadata(EEG_Guesser);

            hyperyesno.wrapperFunction = mfilename;
            hyperyesno.created = datestr(now, 30);

            results.hyperyesno = hyperyesno;

            %% ------------------------------------------------------------
            % 5.10 Calculate compact QC summaries
            % -------------------------------------------------------------

            observedValues = ...
                results.gcmiObserved(isfinite( ...
                results.gcmiObserved));

            record.ObservedFinitePercent = ...
                100 * numel(observedValues) / ...
                numel(results.gcmiObserved);

            if isempty(observedValues)

                record.ObservedMedianGCMI = NaN;
                record.ObservedMaximumGCMI = NaN;
                record.ObservedMinimumGCMI = NaN;

            else

                record.ObservedMedianGCMI = ...
                    median(observedValues);

                record.ObservedMaximumGCMI = ...
                    max(observedValues);

                record.ObservedMinimumGCMI = ...
                    min(observedValues);
            end

            record.UsableSamplesPerTrial = ...
                results.usableSamplesPerTrial;

            record.NumberOfObservationsPerLag = ...
                results.numberOfObservationsPerLag;

            record.ActualLagSamples = ...
                string(mat2str(results.lagsSamples));

            record.ActualLagsMs = ...
                string(mat2str(results.lagsMilliseconds));

            %% ------------------------------------------------------------
            % 5.11 Save result and complete summary record
            % -------------------------------------------------------------

            save(outputFile, 'results', '-v7.3');

            outputInfo = dir(outputFile);

            record.OutputSizeMB = ...
                outputInfo.bytes / 1024 ^ 2;

            record.Status = "completed";
            record.ElapsedMinutes = ...
                toc(calculationTimer) / 60;

            if options.Verbose

                fprintf('\nSaved HyperYESNO lagged GCMI result:\n%s\n', ...
                    outputFile);

                fprintf('Elapsed time: %.2f minutes\n', ...
                    record.ElapsedMinutes);
            end

            clear EEG_Knower EEG_Guesser results

        catch ME

            record.Status = "failed";
            record.Notes = string(ME.message);
            record.ElapsedMinutes = ...
                toc(calculationTimer) / 60;

            fprintf(2, '\nFAILED %s %s\n%s\n', ...
                dyadStr, situation.marker, ME.message);

            clear EEG_Knower EEG_Guesser results
        end

        records(recordCounter) = record;
    end
end

%% ========================================================================
% 6. Create and save summary tables
% ========================================================================

summaryTable = struct2table(records);

trialCountTable = summaryTable(:, { ...
    'Dyad', ...
    'DyadName', ...
    'Situation', ...
    'Condition', ...
    'KnowerParticipant', ...
    'GuesserParticipant', ...
    'NumberOfTrials', ...
    'SamplesPerTrial', ...
    'UsableSamplesPerTrial', ...
    'NumberOfObservationsPerLag', ...
    'SamplingRateHz', ...
    'EpochStartMs', ...
    'EpochEndMs', ...
    'InputFilterLowHz', ...
    'InputFilterHighHz', ...
    'FilterVerified', ...
    'RequestedLagStartMs', ...
    'RequestedLagEndMs', ...
    'RequestedLagCount', ...
    'ActualLagSamples', ...
    'ActualLagsMs', ...
    'NumSurrogates', ...
    'OutputFile', ...
    'Status', ...
    'ElapsedMinutes', ...
    'Notes'});

summaryExcelFile = fullfile( ...
    rootDir, ...
    'Step7_lagged_GCMI_summary.xlsx');

summaryMatFile = fullfile( ...
    rootDir, ...
    'Step7_lagged_GCMI_summary.mat');

trialExcelFile = fullfile( ...
    rootDir, ...
    'Step7_GCMI_trial_counts.xlsx');

trialMatFile = fullfile( ...
    rootDir, ...
    'Step7_GCMI_trial_counts.mat');

writetable(summaryTable, summaryExcelFile);
save(summaryMatFile, 'summaryTable');

writetable(trialCountTable, trialExcelFile);
save(trialMatFile, 'trialCountTable');

fprintf('\n');
fprintf('============================================================\n');
fprintf('Step 7 finished in %.2f minutes.\n', ...
    toc(pipelineTimer) / 60);
fprintf('Detailed summary: %s\n', summaryExcelFile);
fprintf('Trial-count table: %s\n', trialExcelFile);
fprintf('============================================================\n');

end


%% =========================================================================
% Local function: normalize requested situation input
% =========================================================================

function selectedSituationNames = ...
    local_normalise_situation_input(inputSituations)

allowedNames = [ ...
    "YES_AKnower", ...
    "NO_AKnower", ...
    "YES_BKnower", ...
    "NO_BKnower"];

if ischar(inputSituations)
    selectedSituationNames = string({inputSituations});
elseif isstring(inputSituations)
    selectedSituationNames = inputSituations(:)';
elseif iscell(inputSituations)
    selectedSituationNames = string(inputSituations);
else
    error('Unsupported Situations input type.');
end

selectedSituationNames = ...
    strtrim(selectedSituationNames);

if isempty(selectedSituationNames)
    error('At least one situation must be selected.');
end

for iSituation = 1:numel(selectedSituationNames)

    exactMatch = find(strcmpi( ...
        selectedSituationNames(iSituation), ...
        allowedNames), 1);

    if isempty(exactMatch)

        error(['Unknown situation "%s". Allowed values are: %s.'], ...
            selectedSituationNames(iSituation), ...
            strjoin(allowedNames, ', '));
    end

    selectedSituationNames(iSituation) = ...
        allowedNames(exactMatch);
end

selectedSituationNames = ...
    unique(selectedSituationNames, 'stable');

end


%% =========================================================================
% Local function: validate the role-normalized epoched pair
% =========================================================================

function validation = local_validate_epoched_pair( ...
    EEG_Knower, EEG_Guesser, situation)

if EEG_Knower.trials < 1 || EEG_Guesser.trials < 1
    error('The Knower or Guesser dataset contains no epochs.');
end

if EEG_Knower.trials ~= EEG_Guesser.trials
    error(['Knower and Guesser trial counts differ: ', ...
        '%d versus %d.'], ...
        EEG_Knower.trials, EEG_Guesser.trials);
end

if EEG_Knower.pnts ~= EEG_Guesser.pnts
    error('Knower and Guesser samples-per-trial values differ.');
end

if EEG_Knower.srate ~= EEG_Guesser.srate
    error('Knower and Guesser sampling rates differ.');
end

if EEG_Knower.nbchan ~= EEG_Guesser.nbchan
    error('Knower and Guesser ROI counts differ.');
end

if numel(EEG_Knower.times) ~= ...
        numel(EEG_Guesser.times) || ...
        any(abs(double(EEG_Knower.times) - ...
        double(EEG_Guesser.times)) > 1e-10)

    error('Knower and Guesser epoch time vectors differ.');
end

labelsKnower = string({EEG_Knower.chanlocs.labels});
labelsGuesser = string({EEG_Guesser.chanlocs.labels});

if ~isequal(labelsKnower, labelsGuesser)
    error('Knower and Guesser ROI labels or ROI order differ.');
end

pairIDsKnower = local_get_pair_ids(EEG_Knower);
pairIDsGuesser = local_get_pair_ids(EEG_Guesser);

if numel(pairIDsKnower) ~= EEG_Knower.trials || ...
        numel(pairIDsGuesser) ~= EEG_Guesser.trials

    error('Pair-ID count does not equal the number of epochs.');
end

if ~isequal(pairIDsKnower(:), pairIDsGuesser(:))
    error('Knower and Guesser pair IDs or trial order differ.');
end

analysisRoleKnower = local_get_analysis_role(EEG_Knower);
analysisRoleGuesser = local_get_analysis_role(EEG_Guesser);

rolesVerified = ...
    strcmpi(analysisRoleKnower, 'Knower') && ...
    strcmpi(analysisRoleGuesser, 'Guesser');

if ~rolesVerified

    error(['Role metadata is inconsistent. Knower file reports "%s"; ', ...
        'Guesser file reports "%s".'], ...
        analysisRoleKnower, analysisRoleGuesser);
end

metadataKnower = local_get_epoch_metadata(EEG_Knower);
metadataGuesser = local_get_epoch_metadata(EEG_Guesser);

if isfield(metadataKnower, 'marker') && ...
        ~strcmpi(metadataKnower.marker, situation.marker)

    error('Knower marker metadata does not match %s.', ...
        situation.marker);
end

if isfield(metadataGuesser, 'marker') && ...
        ~strcmpi(metadataGuesser.marker, situation.marker)

    error('Guesser marker metadata does not match %s.', ...
        situation.marker);
end

if isfield(metadataKnower, 'knowerParticipant') && ...
        ~strcmpi( ...
        metadataKnower.knowerParticipant, ...
        situation.knowerParticipant)

    error('Knower participant metadata does not match the situation.');
end

if isfield(metadataGuesser, 'guesserParticipant') && ...
        ~strcmpi( ...
        metadataGuesser.guesserParticipant, ...
        situation.guesserParticipant)

    error('Guesser participant metadata does not match the situation.');
end

if ~isempty(EEG_Knower.epoch) && ...
        isfield(EEG_Knower.epoch, ...
        'original_marker_latency') && ...
        isfield(EEG_Guesser.epoch, ...
        'original_marker_latency')

    latenciesKnower = double( ...
        [EEG_Knower.epoch.original_marker_latency]);

    latenciesGuesser = double( ...
        [EEG_Guesser.epoch.original_marker_latency]);

    if ~isequal(latenciesKnower, latenciesGuesser)
        error(['Original marker latencies differ between the Knower ', ...
            'and Guesser epochs.']);
    end
end

validation = struct();

validation.pairIDs = pairIDsKnower;
validation.pairIDsVerified = true;
validation.analysisRolesVerified = true;

end


%% =========================================================================
% Local function: retrieve Step 6 pair IDs
% =========================================================================

function pairIDs = local_get_pair_ids(EEG)

pairIDs = strings(0, 1);

if isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'hyperyesno_epoching') && ...
        isfield( ...
        EEG.etc.hyperyesno_epoching, ...
        'pairIDs') && ...
        ~isempty( ...
        EEG.etc.hyperyesno_epoching.pairIDs)

    pairIDs = string( ...
        EEG.etc.hyperyesno_epoching.pairIDs);

elseif ~isempty(EEG.epoch) && ...
        isfield(EEG.epoch, 'pair_id')

    pairIDs = string({EEG.epoch.pair_id});
end

pairIDs = pairIDs(:);

if isempty(pairIDs)
    error('No Step 6 pair IDs were found in the dataset.');
end

end


%% =========================================================================
% Local function: retrieve Step 6 analysis role
% =========================================================================

function analysisRole = local_get_analysis_role(EEG)

analysisRole = '';

if isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'hyperyesno_epoching') && ...
        isfield( ...
        EEG.etc.hyperyesno_epoching, ...
        'analysisRole')

    analysisRole = char(string( ...
        EEG.etc.hyperyesno_epoching.analysisRole));
end

end


%% =========================================================================
% Local function: retrieve Step 6 metadata
% =========================================================================

function metadata = local_get_epoch_metadata(EEG)

metadata = struct();

if isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'hyperyesno_epoching') && ...
        isstruct(EEG.etc.hyperyesno_epoching)

    metadata = EEG.etc.hyperyesno_epoching;
end

end


%% =========================================================================
% Local function: read and verify filter metadata
% =========================================================================

function [filterBand, status] = ...
    local_get_filter_metadata(EEG)

filterBand = [];
status = 'missing';

metadata = local_get_epoch_metadata(EEG);

if isfield(metadata, 'filterBandHz')

    candidate = double( ...
        metadata.filterBandHz(:)');

    if isempty(candidate)

        filterBand = [];
        status = 'empty';

    elseif numel(candidate) == 2 && ...
            all(isfinite(candidate))

        filterBand = candidate;
        status = 'available';

    else

        filterBand = candidate;
        status = 'invalid';
    end
end

end


function verification = local_verify_filter_metadata( ...
    filterBandKnower, ...
    statusKnower, ...
    filterBandGuesser, ...
    statusGuesser, ...
    expectedBand, ...
    requireExpectedBand, ...
    dyadStr, ...
    situationMarker)

verification = struct();
verification.verified = false;
verification.band = [];
verification.status = '';

if ~strcmp(statusKnower, 'available') || ...
        ~strcmp(statusGuesser, 'available')

    message = sprintf([ ...
        '%s %s: 8-13 Hz filter metadata is unavailable or invalid. ', ...
        'Knower status=%s; Guesser status=%s.'], ...
        dyadStr, situationMarker, ...
        statusKnower, statusGuesser);

    if requireExpectedBand
        error(message);
    else
        warning('%s', message);
        verification.status = 'metadata unavailable';
        return;
    end
end

if numel(filterBandKnower) ~= 2 || ...
        numel(filterBandGuesser) ~= 2 || ...
        any(abs(filterBandKnower - filterBandGuesser) > 1e-10)

    message = sprintf([ ...
        '%s %s: Knower and Guesser filter metadata differ.'], ...
        dyadStr, situationMarker);

    if requireExpectedBand
        error(message);
    else
        warning('%s', message);
        verification.status = 'A-B filter mismatch';
        return;
    end
end

verification.band = filterBandKnower;

if isempty(expectedBand)

    verification.verified = true;
    verification.status = ...
        'matching A-B metadata; no expected band requested';

    return;
end

if numel(expectedBand) ~= 2 || ...
        any(abs(filterBandKnower - expectedBand) > 1e-10)

    message = sprintf([ ...
        '%s %s: input filter metadata is %s Hz, expected %s Hz.'], ...
        dyadStr, situationMarker, ...
        mat2str(filterBandKnower), ...
        mat2str(expectedBand));

    if requireExpectedBand
        error(message);
    else
        warning('%s', message);
        verification.status = 'unexpected filter band';
        return;
    end
end

verification.verified = true;
verification.status = 'verified';

end


%% =========================================================================
% Local function: empty summary record
% =========================================================================

function record = local_empty_summary_record()

record = struct( ...
    'Dyad', NaN, ...
    'DyadName', "", ...
    'Situation', "", ...
    'Condition', "", ...
    'KnowerParticipant', "", ...
    'GuesserParticipant', "", ...
    'KnowerInputFile', "", ...
    'GuesserInputFile', "", ...
    'OutputFile', "", ...
    'SamplingRateHz', NaN, ...
    'NumberOfROIs', NaN, ...
    'NumberOfTrials', NaN, ...
    'SamplesPerTrial', NaN, ...
    'UsableSamplesPerTrial', NaN, ...
    'NumberOfObservationsPerLag', NaN, ...
    'EpochStartMs', NaN, ...
    'EpochEndMs', NaN, ...
    'ExpectedFilterLowHz', NaN, ...
    'ExpectedFilterHighHz', NaN, ...
    'InputFilterLowHz', NaN, ...
    'InputFilterHighHz', NaN, ...
    'FilterMetadataStatus', "", ...
    'FilterVerified', false, ...
    'PairIDsVerified', false, ...
    'AnalysisRolesVerified', false, ...
    'RequestedLagStartMs', NaN, ...
    'RequestedLagEndMs', NaN, ...
    'RequestedLagCount', NaN, ...
    'ActualLagSamples', "", ...
    'ActualLagsMs', "", ...
    'NumSurrogates', NaN, ...
    'EffectiveRandomSeed', NaN, ...
    'UseParallel', false, ...
    'ObservedFinitePercent', NaN, ...
    'ObservedMinimumGCMI', NaN, ...
    'ObservedMedianGCMI', NaN, ...
    'ObservedMaximumGCMI', NaN, ...
    'OutputSizeMB', NaN, ...
    'Status', "", ...
    'ElapsedMinutes', NaN, ...
    'Notes', "");

end
