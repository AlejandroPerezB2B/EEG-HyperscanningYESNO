function results = lagged_gcmi_dyad(dataA, dataB, srate, varargin)
% LAGGED_GCMI_DYAD Calculate lagged inter-brain GCMI for one epoched dyad.
%
% This function calculates Gaussian-copula mutual information (GCMI)
% between every channel in participant A and every channel in participant B.
% The result is a channels-A x channels-B x lags connectivity array.
%
% The default representation is two-dimensional. Each EEG channel is
% represented by:
%
%       [channel signal, temporal gradient]
%
% This follows the lagged-MI example originally shared by Robin Ince. The
% temporal gradient is calculated separately within each epoch, so no
% artificial derivative is introduced between the end of one epoch and the
% beginning of the next.
%
% Paired-trial permutation surrogates are also calculated. For each
% surrogate, the trial order of participant B is rearranged while the trial
% order of participant A is left unchanged. Every permutation is a
% derangement: no B trial remains paired with its original A trial.
% Surrogate permutations are unique within each calculation. If fewer unique
% derangements exist than requested, all available unique derangements are
% used and the actual number of surrogates is reduced automatically. The same
% permutation is applied to every channel and to both dimensions (signal and
% gradient), preserving the complete within-participant structure of each
% epoch while destroying the original trial-to-trial dyadic correspondence.
%
% -------------------------------------------------------------------------
% REQUIRED INPUTS
% -------------------------------------------------------------------------
%
% dataA
%       Epoched EEG data for participant A, arranged as:
%
%           channels x samples x trials
%
% dataB
%       Epoched EEG data for participant B, arranged as:
%
%           channels x samples x trials
%
%       Trial k in participant A must correspond to trial k in participant
%       B in the observed data.
%
% srate
%       Sampling rate in Hz.
%
% -------------------------------------------------------------------------
% OPTIONAL NAME-VALUE INPUTS
% -------------------------------------------------------------------------
%
% 'LagsMs'
%       Requested lags in milliseconds.
%
%       Default:
%           -500:50:500
%
%       Requested lags are converted to the nearest integer number of
%       samples. The function returns both the requested and the actual lag
%       values, because some sampling rates cannot represent every requested
%       millisecond value exactly. For example, 50 ms corresponds to 12.5
%       samples at 250 Hz.
%
% 'NumSurrogates'
%       Requested maximum number of unique paired-trial derangement
%       surrogates.
%
%       Default:
%           499
%
%       The actual number is adapted to the number of paired trials. If the
%       requested number exceeds the number of mathematically possible unique
%       derangements, all possible unique derangements are used. Duplicate
%       surrogate permutations are never retained.
%
% 'RandomSeed'
%       Seed used to generate reproducible trial derangements.
%
%       Default:
%           1
%
% 'ChannelLabelsA'
% 'ChannelLabelsB'
%       Optional channel labels. These are stored in the output but are not
%       used to reorder or otherwise modify the data.
%
%       Default:
%           {}
%
% 'UseParallel'
%       When true, surrogate matrices for each lag are calculated using a
%       PARFOR loop. This requires the Parallel Computing Toolbox.
%
%       Default:
%           false
%
% 'OutputFile'
%       Optional path to a .mat file. When supplied, the results structure
%       is saved using MATLAB Version 7.3 format.
%
%       Default:
%           ''
%
% 'Verbose'
%       Print progress information.
%
%       Default:
%           true
%
% -------------------------------------------------------------------------
% OUTPUT
% -------------------------------------------------------------------------
%
% results.gcmiObserved
%       channelsA x channelsB x lags array containing observed lagged GCMI
%       values in bits.
%
% results.gcmiSurrogates
%       channelsA x channelsB x lags x surrogates array containing the
%       lagged GCMI matrices for all paired-trial permutations.
%
% results.gcmiSurrogateMean
% results.gcmiSurrogateStd
%       Convenience summaries across the surrogate dimension. These are
%       descriptive outputs only; the function does not perform statistical
%       thresholding or correct the observed GCMI values.
%
% results.lagsSamples
% results.lagsMilliseconds
%       Actual lags used after conversion to integer samples.
%
% results.requestedLagsMilliseconds
%       Original requested lag values.
%
% results.surrogateTrialPermutations
%       trials x generated-surrogates matrix. Column s gives the unique
%       B-trial order used for surrogate s.
%
% results.numberOfSurrogatesRequested
% results.numberOfSurrogatesGenerated
% results.maximumUniqueDerangements
% results.surrogateGenerationMode
% results.allUniqueDerangementsUsed
%       Metadata documenting the adaptive unique-surrogate generation.
%
% -------------------------------------------------------------------------
% EXTERNAL DEPENDENCY
% -------------------------------------------------------------------------
%
% The function uses Robin Ince's original:
%
%       copnorm.m
%
% Place copnorm.m in the same folder as this function, or add the GCMI
% toolbox MATLAB folder to the MATLAB path. No other external GCMI function
% is required. The fixed 2D Gaussian MI calculation is implemented locally
% in vectorised form to avoid thousands of separate calls to mi_gg.
%
% The vectorised calculation follows the same Gaussian log-determinant
% expression and analytic finite-sample bias correction used by mi_gg for
% two-dimensional x and y variables.
%
% -------------------------------------------------------------------------
% IMPORTANT ANALYSIS ASSUMPTIONS
% -------------------------------------------------------------------------
%
% 1. The input should already contain only the EEG channels to analyse.
% 2. The input should already be filtered into the frequency range of
%    interest. No filtering is performed here.
% 3. Epochs must have the same duration for both participants.
% 4. The function pools valid samples across trials for each lag, while
%    respecting epoch boundaries during lagging.
% 5. A constant number of samples is used for every lag. All lags discard
%    max(abs(lag)) samples from both ends of each epoch before the relative
%    shift is applied.
%
% -------------------------------------------------------------------------
% LAG CONVENTION
% -------------------------------------------------------------------------
%
% The convention follows Robin Ince's original lagged-MI example:
%
%       negative lag  -> participant A precedes participant B
%       positive lag  -> participant B precedes participant A
%       zero lag      -> simultaneous samples
%
% -------------------------------------------------------------------------
% EXAMPLE
% -------------------------------------------------------------------------
%
% results = lagged_gcmi_dyad( ...
%     EEG_A.data, ...
%     EEG_B.data, ...
%     EEG_A.srate, ...
%     'LagsMs', -500:50:500, ...
%     'NumSurrogates', 499, ...
%     'ChannelLabelsA', {EEG_A.chanlocs.labels}, ...
%     'ChannelLabelsB', {EEG_B.chanlocs.labels}, ...
%     'OutputFile', '303_1_303_2_lagged_gcmi.mat');
%
% AUTHORS
%
%   Alejandro Perez
%   OpenAI-assisted implementation based on Robin Ince's GCMI framework
%
% -------------------------------------------------------------------------


%% Parse the required inputs and the small set of optional parameters.

parser = inputParser;
parser.FunctionName = mfilename;

addRequired(parser, 'dataA', @(x) isnumeric(x) && ndims(x) == 3);
addRequired(parser, 'dataB', @(x) isnumeric(x) && ndims(x) == 3);
addRequired(parser, 'srate', @(x) isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x > 0);

addParameter(parser, 'LagsMs', -500:50:500, ...
    @(x) isnumeric(x) && isvector(x) && all(isfinite(x)));

addParameter(parser, 'NumSurrogates', 499, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && x == round(x));

addParameter(parser, 'RandomSeed', 1, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && x == round(x));

addParameter(parser, 'ChannelLabelsA', {}, ...
    @(x) iscell(x) || isstring(x) || ischar(x));

addParameter(parser, 'ChannelLabelsB', {}, ...
    @(x) iscell(x) || isstring(x) || ischar(x));

addParameter(parser, 'UseParallel', false, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'OutputFile', '', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, dataA, dataB, srate, varargin{:});
options = parser.Results;

% Store text inputs in a consistent form.
options.OutputFile = char(options.OutputFile);
channelLabelsA = cellstr(string(options.ChannelLabelsA));
channelLabelsB = cellstr(string(options.ChannelLabelsB));


%% Perform only the basic dimensional checks required by the calculation.
%
% These checks are intentionally limited. The function assumes that the
% user has already selected appropriate channels and corresponding epochs.

[numberOfChannelsA, samplesPerTrialA, numberOfTrialsA] = size(dataA);
[numberOfChannelsB, samplesPerTrialB, numberOfTrialsB] = size(dataB);

if samplesPerTrialA ~= samplesPerTrialB
    error('lagged_gcmi_dyad:DifferentEpochLengths', ...
        'Participants A and B must have the same number of samples per trial.');
end

if numberOfTrialsA ~= numberOfTrialsB
    error('lagged_gcmi_dyad:DifferentTrialCounts', ...
        'Participants A and B must have the same number of paired trials.');
end

if options.NumSurrogates > 0 && numberOfTrialsA < 2
    error('lagged_gcmi_dyad:TooFewTrialsForSurrogates', ...
        'At least two trials are required for paired-trial permutation.');
end

if ~isempty(channelLabelsA) && numel(channelLabelsA) ~= numberOfChannelsA
    error('lagged_gcmi_dyad:ChannelLabelsA', ...
        'ChannelLabelsA must contain one label per channel in dataA.');
end

if ~isempty(channelLabelsB) && numel(channelLabelsB) ~= numberOfChannelsB
    error('lagged_gcmi_dyad:ChannelLabelsB', ...
        'ChannelLabelsB must contain one label per channel in dataB.');
end

if exist('copnorm', 'file') ~= 2
    error('lagged_gcmi_dyad:MissingCopnorm', ...
        ['copnorm.m was not found. Place Robin Ince''s copnorm.m in the ' ...
         'same folder as lagged_gcmi_dyad.m or add the GCMI toolbox to ' ...
         'the MATLAB path.']);
end


%% Convert the requested millisecond lags to integer sample offsets.
%
% The millisecond grid cannot always be represented exactly by a particular
% sampling rate. We therefore retain the requested values for reference and
% use the nearest integer sample offsets for the actual calculation.

requestedLagsMs = double(options.LagsMs(:)');
lagsSamples = round(requestedLagsMs .* double(srate) ./ 1000);

% Two requested lags could theoretically map to the same sample offset at a
% low sampling rate. Keep only the first occurrence of each actual offset.
[lagsSamples, uniqueLagIndices] = unique(lagsSamples, 'stable');
requestedLagsMs = requestedLagsMs(uniqueLagIndices);
actualLagsMs = lagsSamples .* 1000 ./ double(srate);

numberOfLags = numel(lagsSamples);
maximumLagSamples = max(abs(lagsSamples));

% Constant-sample lagging uses the middle part of each epoch as a common
% anchor interval. Every lag therefore contributes exactly this many
% samples from every trial.
usableSamplesPerTrial = samplesPerTrialA - 2 * maximumLagSamples;

if usableSamplesPerTrial < 5
    error('lagged_gcmi_dyad:EpochTooShort', ...
        ['The epochs are too short for the requested lag range. ' ...
         'At least five common samples per trial must remain after trimming.']);
end

numberOfObservations = usableSamplesPerTrial * numberOfTrialsA;


%% Generate a reproducible set of unique paired-trial derangements.
%
% NumSurrogates is interpreted as a requested maximum. The generator adapts
% the actual number to the number of paired trials. For example, two trials
% permit only one unique derangement, whereas six trials permit 265. When
% fewer unique derangements exist than requested, every available unique
% derangement is used. Otherwise, the requested number is sampled without
% replacement from the space of derangements.

[surrogateTrialPermutations, surrogateInfo] = ...
    generate_unique_derangements( ...
    numberOfTrialsA, ...
    options.NumSurrogates, ...
    options.RandomSeed);

numberOfSurrogates = surrogateInfo.actualNumSurrogates;


%% Convert the data to samples x channels x trials and double precision.
%
% EEGLAB uses channels x samples x trials, whereas the GCMI toolbox uses
% samples as the first dimension. Double precision is retained during the
% copula transform, covariance calculations and log-determinants.

signalA = permute(double(dataA), [2 1 3]);
signalB = permute(double(dataB), [2 1 3]);


%% Calculate the temporal gradient separately inside every epoch.
%
% This reproduces Robin Ince's gradient_dim1 convention:
%
%   - forward difference at the first sample;
%   - backward difference at the last sample;
%   - unscaled central difference at interior samples.
%
% The lack of division by two is unimportant after rank-based copula
% normalisation, because positive rescaling does not alter sample ranks.

gradientA = temporal_gradient_by_trial(signalA);
gradientB = temporal_gradient_by_trial(signalB);


%% Apply global copula normalisation once before lagging.
%
% Robin Ince's original computationally efficient procedure is followed:
%
%   1. concatenate all epochs;
%   2. copula-normalise every channel independently;
%   3. restore the original epoch structure;
%   4. perform lagging within each epoch.
%
% Signal and gradient dimensions are normalised separately. This operation
% is performed only once and reused for the observed data and all surrogate
% trial pairings.

if options.Verbose
    fprintf('\nPreparing dyadic GCMI analysis\n');
    fprintf('------------------------------\n');
    fprintf('Participant A channels:       %d\n', numberOfChannelsA);
    fprintf('Participant B channels:       %d\n', numberOfChannelsB);
    fprintf('Paired trials:                %d\n', numberOfTrialsA);
    fprintf('Samples per trial:            %d\n', samplesPerTrialA);
    fprintf('Usable samples per trial:     %d\n', usableSamplesPerTrial);
    fprintf('Pooled observations per lag:  %d\n', numberOfObservations);
    fprintf('Actual lag range:             %.3f to %.3f ms\n', ...
        actualLagsMs(1), actualLagsMs(end));
    fprintf('Number of lags:               %d\n', numberOfLags);
    fprintf('Surrogates requested:        %d\n', ...
        options.NumSurrogates);
    fprintf('Unique surrogates generated: %d\n', ...
        numberOfSurrogates);
    fprintf('Surrogate generation mode:   %s\n\n', ...
        surrogateInfo.generationMode);
end

copulaSignalA = copnorm_epochs(signalA);
copulaSignalB = copnorm_epochs(signalB);
copulaGradientA = copnorm_epochs(gradientA);
copulaGradientB = copnorm_epochs(gradientB);

% Raw and gradient arrays are no longer required after copula
% normalisation. Clearing them reduces peak memory consumption.
clear signalA signalB gradientA gradientB dataA dataB


%% Preallocate the observed and surrogate lagged connectivity arrays.
%
% Calculations are performed in double precision and retained as double
% precision. With 62 x 62 channels, 21 lags and 19 surrogates, the complete
% surrogate array occupies approximately 12 MB.

gcmiObserved = zeros( ...
    numberOfChannelsA, numberOfChannelsB, numberOfLags);

gcmiSurrogates = zeros( ...
    numberOfChannelsA, numberOfChannelsB, ...
    numberOfLags, numberOfSurrogates);


%% Calculate the analytic finite-sample bias once.
%
% Constant-sample lagging guarantees the same number of observations at
% every lag and for every surrogate. The bias term is therefore identical
% throughout the analysis.
%
% Each channel is represented by two dimensions in participant A and two
% dimensions in participant B, so this is the same correction used by:
%
%       mi_gg(x, y, true, false)
%
% when x and y each contain two columns.

analyticBiasBits = gaussian_mi_bias_bits(2, 2, numberOfObservations);


%% Main lag loop.
%
% For each lag:
%
%   1. choose the same number of valid samples from every epoch;
%   2. pool those samples across trials;
%   3. calculate the observed channel-by-channel 2D GCMI matrix;
%   4. repeat after each derangement of participant B's trial order.
%
% The computationally expensive channel-pair calculation is vectorised.
% Instead of calling mi_gg separately for every pair, the function computes
% all signal/gradient cross-covariance matrices using matrix multiplication
% and evaluates the equivalent 2D Gaussian log-determinants simultaneously.

commonAnchor = (maximumLagSamples + 1): ...
    (samplesPerTrialA - maximumLagSamples);

for lagIndex = 1:numberOfLags

    currentLag = lagsSamples(lagIndex);

    % Robin Ince's lag convention:
    %
    %   currentLag < 0: A is earlier and B is later.
    %   currentLag > 0: B is earlier and A is later.
    %
    % The commonAnchor interval has already removed the maximum lag from
    % both epoch edges. Adding the positive part of the lag to A or the
    % negative part to B keeps all selected indices valid and constant in
    % number.
    indicesA = commonAnchor + max(currentLag, 0);
    indicesB = commonAnchor + max(-currentLag, 0);

    % Retain an epoch-wise representation for participant B because trial
    % order will be permuted independently for every surrogate.
    blockA0 = copulaSignalA(indicesA, :, :);
    blockA1 = copulaGradientA(indicesA, :, :);
    blockB0 = copulaSignalB(indicesB, :, :);
    blockB1 = copulaGradientB(indicesB, :, :);

    % Concatenate participant A trials once. Participant A is unchanged in
    % all paired-trial surrogates.
    pooledA0 = concatenate_trials(blockA0);
    pooledA1 = concatenate_trials(blockA1);

    % The observed data use the original one-to-one trial correspondence.
    pooledB0 = concatenate_trials(blockB0);
    pooledB1 = concatenate_trials(blockB1);

    gcmiObserved(:, :, lagIndex) = pairwise_gcmi_2d( ...
        pooledA0, pooledA1, pooledB0, pooledB1, analyticBiasBits);

    % Each surrogate reorders complete participant-B epochs. Filtering,
    % gradients and copula normalisation are not recalculated.
    if numberOfSurrogates > 0

        surrogateMatrices = zeros( ...
            numberOfChannelsA, numberOfChannelsB, ...
            numberOfSurrogates);

        if options.UseParallel

            parfor surrogateIndex = 1:numberOfSurrogates

                permutation = double( ...
                    surrogateTrialPermutations(:, surrogateIndex));

                surrogateB0 = concatenate_trials( ...
                    blockB0(:, :, permutation));

                surrogateB1 = concatenate_trials( ...
                    blockB1(:, :, permutation));

                surrogateMatrices(:, :, surrogateIndex) = ...
                    pairwise_gcmi_2d( ...
                        pooledA0, pooledA1, ...
                        surrogateB0, surrogateB1, ...
                        analyticBiasBits);

            end

        else

            for surrogateIndex = 1:numberOfSurrogates

                permutation = double( ...
                    surrogateTrialPermutations(:, surrogateIndex));

                surrogateB0 = concatenate_trials( ...
                    blockB0(:, :, permutation));

                surrogateB1 = concatenate_trials( ...
                    blockB1(:, :, permutation));

                surrogateMatrices(:, :, surrogateIndex) = ...
                    pairwise_gcmi_2d( ...
                        pooledA0, pooledA1, ...
                        surrogateB0, surrogateB1, ...
                        analyticBiasBits);

            end

        end

        gcmiSurrogates(:, :, lagIndex, :) = surrogateMatrices;

    end

    if options.Verbose
        fprintf('Completed lag %3d/%3d: requested %+8.3f ms, actual %+8.3f ms\n', ...
            lagIndex, numberOfLags, requestedLagsMs(lagIndex), ...
            actualLagsMs(lagIndex));
    end

end


%% Assemble a compact results structure.
%
% No inferential decisions are made here. The observed GCMI and every
% surrogate realization are retained so that statistical procedures can be
% selected later without rerunning the expensive connectivity calculation.

results = struct;

results.gcmiObserved = gcmiObserved;
results.gcmiSurrogates = gcmiSurrogates;

if numberOfSurrogates > 0
    results.gcmiSurrogateMean = mean(gcmiSurrogates, 4);
    results.gcmiSurrogateStd = std(gcmiSurrogates, 0, 4);
else
    results.gcmiSurrogateMean = [];
    results.gcmiSurrogateStd = [];
end

results.requestedLagsMilliseconds = requestedLagsMs;
results.lagsSamples = lagsSamples;
results.lagsMilliseconds = actualLagsMs;

results.samplingRate = double(srate);
results.samplesPerTrial = samplesPerTrialA;
results.usableSamplesPerTrial = usableSamplesPerTrial;
results.numberOfTrials = numberOfTrialsA;
results.numberOfObservationsPerLag = numberOfObservations;
results.numberOfChannelsA = numberOfChannelsA;
results.numberOfChannelsB = numberOfChannelsB;
results.channelLabelsA = channelLabelsA;
results.channelLabelsB = channelLabelsB;

results.surrogateTrialPermutations = surrogateTrialPermutations;
results.numberOfSurrogatesRequested = ...
    surrogateInfo.requestedNumSurrogates;
results.numberOfSurrogatesGenerated = ...
    surrogateInfo.actualNumSurrogates;
results.maximumUniqueDerangements = ...
    surrogateInfo.maximumUniqueDerangements;
results.maximumUniqueDerangementsKnown = ...
    surrogateInfo.maximumUniqueDerangementsKnown;
results.maximumUniqueDerangementsDisplay = ...
    surrogateInfo.maximumUniqueDerangementsDisplay;
results.allUniqueDerangementsUsed = ...
    surrogateInfo.allUniqueDerangementsUsed;
results.surrogateGenerationMode = ...
    surrogateInfo.generationMode;
results.duplicateSurrogatePermutationsPrevented = true;
results.surrogateGenerationAttempts = ...
    surrogateInfo.numberOfGenerationAttempts;
results.analyticBiasBits = analyticBiasBits;

results.settings = struct;
results.settings.representation = '2d_signal_plus_gradient';
results.settings.gradientMethod = 'Robin_Ince_gradient_dim1';
results.settings.copnormMode = 'global_across_selected_trials';
results.settings.lagSampleMode = 'constant';
results.settings.lagConvention = [ ...
    'negative: A precedes B; positive: B precedes A'];
results.settings.trialAggregation = 'pooled';
results.settings.surrogateMethod = 'paired_trial_permutation';
results.settings.permutationType = 'derangement';
results.settings.requestedNumSurrogates = options.NumSurrogates;
results.settings.numSurrogates = numberOfSurrogates;
results.settings.actualNumSurrogates = numberOfSurrogates;
results.settings.uniqueSurrogatePermutations = true;
results.settings.adaptiveSurrogateCount = true;
results.settings.surrogateGenerationMode = ...
    surrogateInfo.generationMode;
results.settings.randomSeed = options.RandomSeed;
results.settings.useParallel = options.UseParallel;
results.settings.biasCorrection = true;
results.settings.externalDependency = 'copnorm.m from Robin Ince GCMI';
results.settings.function = mfilename;
results.settings.created = datestr(now, 30);


%% Optionally save the complete output using Version 7.3 MAT format.
%
% Version 7.3 supports large arrays and allows partial loading later if the
% number of surrogates is increased substantially.

if ~isempty(options.OutputFile)

    outputFolder = fileparts(options.OutputFile);

    if ~isempty(outputFolder) && ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    save(options.OutputFile, 'results', '-v7.3');

    if options.Verbose
        fprintf('\nSaved lagged GCMI results:\n%s\n', options.OutputFile);
    end

end

if options.Verbose
    fprintf('\nLagged dyadic GCMI calculation completed.\n\n');
end

end


%% ========================================================================
function gradientData = temporal_gradient_by_trial(signalData)
% TEMPORAL_GRADIENT_BY_TRIAL Reproduce gradient_dim1 within every epoch.
%
% INPUT/OUTPUT FORMAT
%       samples x channels x trials

[numberOfSamples, ~, ~] = size(signalData);

gradientData = zeros(size(signalData), 'like', signalData);

% Forward difference at the first sample of every trial.
gradientData(1, :, :) = ...
    signalData(2, :, :) - signalData(1, :, :);

% Backward difference at the final sample of every trial.
gradientData(numberOfSamples, :, :) = ...
    signalData(numberOfSamples, :, :) - ...
    signalData(numberOfSamples - 1, :, :);

% Unscaled central difference for all interior samples.
gradientData(2:numberOfSamples-1, :, :) = ...
    signalData(3:numberOfSamples, :, :) - ...
    signalData(1:numberOfSamples-2, :, :);

end


%% ========================================================================
function copulaData = copnorm_epochs(epochData)
% COPNORM_EPOCHS Concatenate epochs, copnorm channels, and restore epochs.
%
% INPUT/OUTPUT FORMAT
%       samples x channels x trials

[numberOfSamples, numberOfChannels, numberOfTrials] = size(epochData);

% Move trials next to samples before reshaping, ensuring each channel is a
% single column containing all observations across all selected epochs.
concatenatedData = reshape( ...
    permute(epochData, [1 3 2]), ...
    numberOfSamples * numberOfTrials, ...
    numberOfChannels);

% Robin Ince's copnorm operates down the first dimension, independently for
% every column.
concatenatedData = copnorm(concatenatedData);

% Restore samples x channels x trials.
copulaData = permute( ...
    reshape(concatenatedData, ...
        numberOfSamples, numberOfTrials, numberOfChannels), ...
    [1 3 2]);

end


%% ========================================================================
function pooledData = concatenate_trials(epochData)
% CONCATENATE_TRIALS Pool corresponding epoch samples without mixing edges.
%
% INPUT FORMAT
%       samples x channels x trials
%
% OUTPUT FORMAT
%       pooled samples x channels

[numberOfSamples, numberOfChannels, numberOfTrials] = size(epochData);

pooledData = reshape( ...
    permute(epochData, [1 3 2]), ...
    numberOfSamples * numberOfTrials, ...
    numberOfChannels);

end


%% ========================================================================
function gcmiMatrix = pairwise_gcmi_2d( ...
    signalA, gradientA, signalB, gradientB, analyticBiasBits)
% PAIRWISE_GCMI_2D Vectorised 2D Gaussian-copula MI for all channel pairs.
%
% Each channel in participant A is represented by [signalA, gradientA].
% Each channel in participant B is represented by [signalB, gradientB].
%
% Inputs have observations along rows and channels along columns. The data
% have already been copula-normalised globally. They are demeaned again here
% using exactly the lag-specific observations entering this calculation,
% reproducing mi_gg(..., biascorrect=true, demeaned=false).
%
% The function evaluates:
%
%       I(X;Y) = 0.5 * log2( det(Cx) det(Cy) / det(Cxy) ) - bias
%
% for every channel pair. A 2 x 2 Schur complement is used to obtain the
% joint determinant efficiently, avoiding construction of thousands of
% individual 4 x 4 covariance matrices.

numberOfObservations = size(signalA, 1);

% Demean the exact lag-specific observations. Global copula normalisation
% produces approximately zero-mean columns, but lag trimming and trial
% permutation can change the mean slightly.
signalA = signalA - mean(signalA, 1);
gradientA = gradientA - mean(gradientA, 1);
signalB = signalB - mean(signalB, 1);
gradientB = gradientB - mean(gradientB, 1);

covarianceScale = 1 / (numberOfObservations - 1);

% Participant-A 2 x 2 marginal covariance terms, one set per A channel.
a00 = sum(signalA .* signalA, 1)' .* covarianceScale;
a01 = sum(signalA .* gradientA, 1)' .* covarianceScale;
a11 = sum(gradientA .* gradientA, 1)' .* covarianceScale;

% Participant-B 2 x 2 marginal covariance terms, one set per B channel.
b00 = sum(signalB .* signalB, 1) .* covarianceScale;
b01 = sum(signalB .* gradientB, 1) .* covarianceScale;
b11 = sum(gradientB .* gradientB, 1) .* covarianceScale;

% Four cross-covariance matrices contain all signal/gradient combinations
% for every A-channel x B-channel pair.
c00 = (signalA' * signalB) .* covarianceScale;
c01 = (signalA' * gradientB) .* covarianceScale;
c10 = (gradientA' * signalB) .* covarianceScale;
c11 = (gradientA' * gradientB) .* covarianceScale;

% Determinants of the 2 x 2 marginal covariance matrices.
determinantA = a00 .* a11 - a01 .^ 2;
determinantB = b00 .* b11 - b01 .^ 2;

if any(determinantA <= 0) || any(determinantB <= 0)
    error('lagged_gcmi_dyad:NonPositiveMarginalCovariance', ...
        ['A signal/gradient covariance matrix was not positive definite. ' ...
         'Check for constant or duplicated channel data.']);
end

% Elements of inv(CA), represented as channel-A column vectors. MATLAB's
% implicit expansion then applies each inverse to all B channels.
inverseA00 =  a11 ./ determinantA;
inverseA01 = -a01 ./ determinantA;
inverseA11 =  a00 ./ determinantA;

% First calculate inv(CA) * CAB for every channel pair.
m00 = inverseA00 .* c00 + inverseA01 .* c10;
m01 = inverseA00 .* c01 + inverseA01 .* c11;
m10 = inverseA01 .* c00 + inverseA11 .* c10;
m11 = inverseA01 .* c01 + inverseA11 .* c11;

% Calculate CAB' * inv(CA) * CAB. Only three unique terms are required
% because the result is symmetric.
q00 = c00 .* m00 + c10 .* m10;
q01 = c00 .* m01 + c10 .* m11;
q11 = c01 .* m01 + c11 .* m11;

% Schur complement of CA in the joint covariance matrix:
%
%       S = CB - CAB' inv(CA) CAB
%
% The determinant of the full 4 x 4 covariance is det(CA) * det(S).
s00 = b00 - q00;
s01 = b01 - q01;
s11 = b11 - q11;

determinantSchur = s00 .* s11 - s01 .^ 2;

if any(determinantSchur(:) <= 0)
    error('lagged_gcmi_dyad:NonPositiveJointCovariance', ...
        ['A joint signal/gradient covariance matrix was not positive ' ...
         'definite. Check for constant, duplicated, or numerically ' ...
         'degenerate channel data.']);
end

% det(CA) cancels between the numerator and the Schur-complement form of
% det(CXY), leaving det(CB)/det(S). This is mathematically identical to the
% log-determinant expression used by mi_gg.
gcmiMatrix = 0.5 .* log2(determinantB ./ determinantSchur);

% Apply Robin Ince's analytic finite-sample bias correction. Small negative
% estimates are mathematically possible after bias correction and are not
% forcibly truncated to zero.
gcmiMatrix = gcmiMatrix - analyticBiasBits;

end


%% ========================================================================
function biasBits = gaussian_mi_bias_bits(dimX, dimY, numberOfObservations)
% GAUSSIAN_MI_BIAS_BITS Analytic bias correction used by Robin Ince's mi_gg.

biasBits = gaussian_entropy_bias_bits(dimX, numberOfObservations) + ...
    gaussian_entropy_bias_bits(dimY, numberOfObservations) - ...
    gaussian_entropy_bias_bits(dimX + dimY, numberOfObservations);

end


%% ========================================================================
function biasBits = gaussian_entropy_bias_bits( ...
    numberOfDimensions, numberOfObservations)
% GAUSSIAN_ENTROPY_BIAS_BITS Bias of the Gaussian log-determinant entropy.

ln2 = log(2);

dTerm = (ln2 - log(numberOfObservations - 1)) / 2;

psiTerms = sum( ...
    psi((numberOfObservations - (1:numberOfDimensions)) / 2) / 2);

biasBits = (numberOfDimensions * dTerm + psiTerms) / ln2;

end


%% ========================================================================
function [permutationMatrix, info] = generate_unique_derangements( ...
    numberOfTrials, requestedNumSurrogates, randomSeed)
% GENERATE_UNIQUE_DERANGEMENTS Create unique trial-pair surrogates.
%
% NumSurrogates is treated as a requested maximum. The returned number is:
%
%   min(requestedNumSurrogates, number of possible derangements)
%
% when the latter can be determined below the requested cap. Every returned
% column is unique and contains no fixed points.

info = struct;
info.requestedNumSurrogates = double(requestedNumSurrogates);
info.actualNumSurrogates = 0;
info.maximumUniqueDerangements = NaN;
info.maximumUniqueDerangementsKnown = false;
info.maximumUniqueDerangementsDisplay = "0";
info.allUniqueDerangementsUsed = false;
info.generationMode = "none";
info.numberOfGenerationAttempts = 0;
maximumUniqueDerangements = NaN;

if requestedNumSurrogates == 0
    permutationMatrix = zeros(numberOfTrials, 0, 'uint32');
    return;
end

if numberOfTrials < 2
    error('lagged_gcmi_dyad:TooFewTrialsForSurrogates', ...
        'At least two paired trials are required for surrogates.');
end

[maximumCountAtCap, maximumCountKnown] = ...
    count_derangements_up_to_cap( ...
    numberOfTrials, requestedNumSurrogates);

if maximumCountKnown
    maximumUniqueDerangements = maximumCountAtCap;
    actualNumSurrogates = min( ...
        requestedNumSurrogates, maximumUniqueDerangements);

    info.maximumUniqueDerangements = ...
        double(maximumUniqueDerangements);
    info.maximumUniqueDerangementsKnown = true;
    info.maximumUniqueDerangementsDisplay = ...
        string(maximumUniqueDerangements);
else
    % The exact count is larger than the requested number. Its precise value
    % is unnecessary because only the requested number will be generated.
    actualNumSurrogates = requestedNumSurrogates;
    info.maximumUniqueDerangementsDisplay = ...
        ">=" + string(requestedNumSurrogates + 1);
end

info.actualNumSurrogates = double(actualNumSurrogates);
info.allUniqueDerangementsUsed = ...
    maximumCountKnown && ...
    actualNumSurrogates == maximumUniqueDerangements;

previousRandomState = rng;
randomStateCleanup = onCleanup(@() rng(previousRandomState)); %#ok<NASGU>
rng(randomSeed, 'twister');

% When the complete derangement space is small enough to enumerate safely,
% enumerate it once and sample without replacement. This is particularly
% important for 2-6 trials, where requesting 499 surrogates yields all 1,
% 2, 9, 44, or 265 possible derangements, respectively.
shouldEnumerate = ...
    numberOfTrials <= 9 && ...
    maximumCountKnown && ...
    (info.allUniqueDerangementsUsed || ...
    actualNumSurrogates >= 0.25 * maximumUniqueDerangements);

if shouldEnumerate
    candidatePermutations = perms(1:numberOfTrials);
    originalOrder = 1:numberOfTrials;
    isDerangement = all( ...
        candidatePermutations ~= originalOrder, 2);
    candidatePermutations = ...
        candidatePermutations(isDerangement, :);

    if size(candidatePermutations, 1) ~= maximumUniqueDerangements
        error('lagged_gcmi_dyad:DerangementEnumerationMismatch', ...
            ['Internal derangement enumeration returned %d permutations, ' ...
             'but %d were expected.'], ...
            size(candidatePermutations, 1), maximumUniqueDerangements);
    end

    selectedRows = randperm( ...
        size(candidatePermutations, 1), actualNumSurrogates);

    permutationMatrix = uint32( ...
        candidatePermutations(selectedRows, :)');

    info.numberOfGenerationAttempts = ...
        size(candidatePermutations, 1);

    if info.allUniqueDerangementsUsed
        info.generationMode = "all_unique_derangements";
    else
        info.generationMode = ...
            "sampled_without_replacement_from_enumerated_derangements";
    end
else
    permutationMatrix = zeros( ...
        numberOfTrials, actualNumSurrogates, 'uint32');

    usedPermutationKeys = containers.Map( ...
        'KeyType', 'char', 'ValueType', 'logical');

    generatedCount = 0;
    generationAttempts = 0;
    maximumAttempts = max(100000, actualNumSurrogates * 2000);

    while generatedCount < actualNumSurrogates
        generationAttempts = generationAttempts + 1;

        if generationAttempts > maximumAttempts
            error('lagged_gcmi_dyad:UniqueDerangementGenerationFailed', ...
                ['Could not generate %d unique derangements after %d ' ...
                 'attempts. Reduce NumSurrogates or inspect the number ' ...
                 'of paired trials.'], ...
                actualNumSurrogates, maximumAttempts);
        end

        candidate = random_derangement(numberOfTrials);
        candidateKey = sprintf('%u_', uint32(candidate));

        if ~isKey(usedPermutationKeys, candidateKey)
            generatedCount = generatedCount + 1;
            permutationMatrix(:, generatedCount) = uint32(candidate);
            usedPermutationKeys(candidateKey) = true;
        end
    end

    info.numberOfGenerationAttempts = generationAttempts;
    info.generationMode = "unique_random_derangement_sample";
end

% Final defensive verification. These checks are inexpensive relative to the
% GCMI calculation and prevent a malformed surrogate set from being saved.
originalOrder = uint32((1:numberOfTrials)');

if any(any(permutationMatrix == originalOrder))
    error('lagged_gcmi_dyad:FixedPointInSurrogate', ...
        'A generated surrogate permutation contains a fixed point.');
end

if size(unique(permutationMatrix', 'rows'), 1) ~= actualNumSurrogates
    error('lagged_gcmi_dyad:DuplicateSurrogatePermutation', ...
        'Duplicate surrogate permutations were generated unexpectedly.');
end

end


%% ========================================================================
function [countAtCap, countIsExact] = count_derangements_up_to_cap( ...
    numberOfTrials, cap)
% COUNT_DERANGEMENTS_UP_TO_CAP Count !n without numerical overflow.
%
% The subfactorial recurrence is:
%
%   !0 = 1
%   !1 = 0
%   !n = (n - 1) * (!(n - 1) + !(n - 2))
%
% The calculation stops as soon as the final count is known to exceed the
% requested cap. Exact large counts are not needed for adaptive generation.

if numberOfTrials == 0
    countAtCap = 1;
    countIsExact = true;
    return;
end

if numberOfTrials == 1
    countAtCap = 0;
    countIsExact = true;
    return;
end

previousPrevious = 1;  % !0
previous = 0;          % !1

for currentN = 2:numberOfTrials
    current = (currentN - 1) * ...
        (previous + previousPrevious);

    if current > cap
        countAtCap = cap;
        countIsExact = false;
        return;
    end

    previousPrevious = previous;
    previous = current;
end

countAtCap = previous;
countIsExact = true;

end


%% ========================================================================
function permutation = random_derangement(numberOfTrials)
% RANDOM_DERANGEMENT Generate a random permutation with no fixed points.
%
% For the typical number of experimental trials, repeatedly drawing a
% random permutation is both simple and fast: the probability that a random
% permutation is a derangement approaches 1/e.

if numberOfTrials == 2
    permutation = [2; 1];
    return;
end

originalOrder = (1:numberOfTrials)';

while true
    permutation = randperm(numberOfTrials)';

    if all(permutation ~= originalOrder)
        return;
    end
end

end
