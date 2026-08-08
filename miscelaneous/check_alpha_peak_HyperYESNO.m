%% check_alpha_peak_HyperYESNO.m
% Simple participant-level check for an alpha spectral peak in HyperYESNO.
%
% The script:
%   1. Loads the continuous broadband 20-ROI LCMV source datasets created
%      by step5_source_LCMV_continuous_HyperYESNO.m.
%   2. Computes a Welch PSD separately for each of the 20 ROIs.
%   3. Converts each ROI PSD to dB and averages the PSDs across ROIs.
%      IMPORTANT: the ROI time series themselves are NOT averaged.
%   4. Searches the participant-level mean spectrum for a local peak
%      between 8 and 13 Hz.
%   5. Saves a summary table and figures showing the spectrum of every
%      participant.
%
% No division is made by YES/NO condition or Knower/Guesser role.
%
% Requirements:
%   - EEGLAB on the MATLAB path
%   - MATLAB Signal Processing Toolbox (pwelch, hann, findpeaks)
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

clear;
clc;

%% ------------------------------------------------------------------------
% Settings
% -------------------------------------------------------------------------

rootDir = 'E:\EEG_data_HyperYESNO';

dyads = 1:35;
members = {'A','B'};

inputSuffix = '_PREP_ASR_ICA_EYE70_LCMV_COMM20';

alphaBand = [8 13];       % Hz
searchRange = [3 30];     % Hz: range in which local spectral peaks are found
plotRange = [2 30];       % Hz

welchWindowSeconds = 4;   % gives ~0.25-Hz spectral resolution at 100 Hz
welchOverlapFraction = 0.50;

% A small amount of smoothing is used ONLY for locating local maxima.
% The saved/illustrated participant spectrum remains the Welch estimate.
peakSmoothingHz = 0.50;

outputDir = fullfile(rootDir, 'Alpha_peak_check');

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% ------------------------------------------------------------------------
% Dependency checks
% -------------------------------------------------------------------------

requiredFunctions = {'pop_loadset','pwelch','hann','findpeaks'};

for iFunction = 1:numel(requiredFunctions)
    if exist(requiredFunctions{iFunction}, 'file') ~= 2
        error(['Required function "%s" was not found. Start EEGLAB and ', ...
               'make sure the Signal Processing Toolbox is available.'], ...
               requiredFunctions{iFunction});
    end
end

%% ------------------------------------------------------------------------
% Storage
% -------------------------------------------------------------------------

records = struct( ...
    'Participant', {}, ...
    'Dyad', {}, ...
    'Member', {}, ...
    'NROIs', {}, ...
    'SamplingRate_Hz', {}, ...
    'AlphaPeakDetected', {}, ...
    'AlphaPeakFrequency_Hz', {}, ...
    'AlphaPeakPower_dB', {}, ...
    'AlphaPeakProminence_dB', {}, ...
    'InputFile', {});

frequencyVector = [];
participantSpectraDb = [];
participantLabels = strings(0,1);

recordCounter = 0;

%% ------------------------------------------------------------------------
% Loop over all 70 participants
% -------------------------------------------------------------------------

for d = dyads

    dyadStr = sprintf('Dyad%02d', d);

    for iMember = 1:numel(members)

        member = members{iMember};

        participantLabel = sprintf('%02d%s', d, member);
        participantBase = sprintf('%s-%s', dyadStr, member);

        participantFolder = fullfile( ...
            rootDir, dyadStr, ['Subj' member]);

        inputFile = [participantBase inputSuffix '.set'];
        inputPath = fullfile(participantFolder, inputFile);

        fprintf('\n------------------------------------------------------------\n');
        fprintf('Participant %s\n', participantLabel);
        fprintf('------------------------------------------------------------\n');

        if exist(inputPath, 'file') ~= 2
            warning('Dataset not found: %s', inputPath);
            continue;
        end

        %% Load continuous ROI dataset

        EEG = pop_loadset( ...
            'filename', inputFile, ...
            'filepath', participantFolder);

        if EEG.trials ~= 1
            error('%s is not continuous.', inputPath);
        end

        if EEG.nbchan ~= 20
            warning('%s contains %d ROIs rather than 20.', ...
                participantLabel, EEG.nbchan);
        end

        fs = EEG.srate;

        % pwelch expects samples x signals when multiple signals are supplied.
        roiData = double(EEG.data');

        if any(~isfinite(roiData(:)))
            error('%s contains NaN or Inf source values.', participantLabel);
        end

        % Remove the mean separately from each ROI.
        roiData = roiData - mean(roiData, 1);

        %% Welch PSD for all ROIs at once

        windowLength = round(welchWindowSeconds * fs);

        if size(roiData,1) < windowLength
            error('%s is shorter than the Welch window.', participantLabel);
        end

        window = hann(windowLength, 'periodic');

        overlapSamples = round( ...
            welchOverlapFraction * windowLength);

        % nfft = windowLength -> frequency-bin spacing is approximately
        % 1 / welchWindowSeconds = 0.25 Hz.
        nfft = windowLength;

        [roiPSD, f] = pwelch( ...
            roiData, ...
            window, ...
            overlapSamples, ...
            nfft, ...
            fs, ...
            'onesided', ...
            'psd');

        % roiPSD dimensions:
        %   frequencies x ROIs

        %% Collapse power across the 20 ROIs

        % Average log-power rather than averaging the source time series.
        % This gives every ROI equal weight in describing spectral shape
        % and avoids cancellation caused by arbitrary source polarity.
        roiPSDdb = 10 * log10(roiPSD);

        meanPSDdb = mean(roiPSDdb, 2, 'omitnan');

        %% Detect a local alpha peak

        freqStep = median(diff(f));
        smoothingBins = max(1, round(peakSmoothingHz / freqStep));

        smoothPSDdb = smoothdata( ...
            meanPSDdb, ...
            'movmean', ...
            smoothingBins);

        searchMask = ...
            f >= searchRange(1) & ...
            f <= searchRange(2);

        fSearch = f(searchMask);
        ySearch = smoothPSDdb(searchMask);

        [peakValues, peakLocations, ~, peakProminences] = ...
            findpeaks( ...
                ySearch, ...
                fSearch, ...
                'MinPeakDistance', 1);

        alphaPeakMask = ...
            peakLocations >= alphaBand(1) & ...
            peakLocations <= alphaBand(2);

        if any(alphaPeakMask)

            alphaLocations = peakLocations(alphaPeakMask);
            alphaValues = peakValues(alphaPeakMask);
            alphaProminences = peakProminences(alphaPeakMask);

            % If more than one local maximum lies within 8-13 Hz, retain
            % the most prominent one.
            [alphaPeakProminence, bestPeak] = ...
                max(alphaProminences);

            alphaPeakFrequency = alphaLocations(bestPeak);
            alphaPeakPower = alphaValues(bestPeak);
            alphaPeakDetected = true;

        else

            alphaPeakFrequency = NaN;
            alphaPeakPower = NaN;
            alphaPeakProminence = NaN;
            alphaPeakDetected = false;
        end

        fprintf('Alpha peak detected: %d\n', alphaPeakDetected);

        if alphaPeakDetected
            fprintf('Peak frequency:      %.2f Hz\n', alphaPeakFrequency);
            fprintf('Peak prominence:     %.2f dB\n', alphaPeakProminence);
        end

        %% Store participant spectrum on a common frequency vector

        plotMask = ...
            f >= plotRange(1) & ...
            f <= plotRange(2);

        thisF = f(plotMask);
        thisSpectrum = meanPSDdb(plotMask);

        if isempty(frequencyVector)

            frequencyVector = thisF;
            participantSpectraDb = nan( ...
                numel(dyads) * numel(members), ...
                numel(frequencyVector));

        elseif numel(thisF) ~= numel(frequencyVector) || ...
                any(abs(thisF - frequencyVector) > 1e-10)

            % This should not normally be needed because all Step-5 files
            % are expected to be at 100 Hz, but interpolation keeps the
            % script robust to a different sampling rate.
            thisSpectrum = interp1( ...
                thisF, ...
                thisSpectrum, ...
                frequencyVector, ...
                'linear', ...
                NaN);
        end

        recordCounter = recordCounter + 1;

        participantSpectraDb(recordCounter,:) = ...
            thisSpectrum(:)';

        participantLabels(recordCounter,1) = ...
            string(participantLabel);

        records(recordCounter).Participant = ...
            string(participantLabel);

        records(recordCounter).Dyad = d;
        records(recordCounter).Member = string(member);
        records(recordCounter).NROIs = EEG.nbchan;
        records(recordCounter).SamplingRate_Hz = fs;
        records(recordCounter).AlphaPeakDetected = alphaPeakDetected;
        records(recordCounter).AlphaPeakFrequency_Hz = alphaPeakFrequency;
        records(recordCounter).AlphaPeakPower_dB = alphaPeakPower;
        records(recordCounter).AlphaPeakProminence_dB = alphaPeakProminence;
        records(recordCounter).InputFile = string(inputPath);

        clear EEG roiData roiPSD roiPSDdb
    end
end

%% ------------------------------------------------------------------------
% Trim unused storage and create summary table
% -------------------------------------------------------------------------

if recordCounter == 0
    error('No Step-5 ROI datasets were found.');
end

participantSpectraDb = ...
    participantSpectraDb(1:recordCounter,:);

participantLabels = ...
    participantLabels(1:recordCounter);

summaryTable = struct2table(records);

%% ------------------------------------------------------------------------
% Save numerical results
% -------------------------------------------------------------------------

excelFile = fullfile( ...
    outputDir, ...
    'Alpha_peak_participant_summary.xlsx');

matFile = fullfile( ...
    outputDir, ...
    'Alpha_peak_participant_results.mat');

writetable(summaryTable, excelFile);

save( ...
    matFile, ...
    'summaryTable', ...
    'frequencyVector', ...
    'participantSpectraDb', ...
    'participantLabels', ...
    'alphaBand', ...
    'searchRange', ...
    'plotRange', ...
    'welchWindowSeconds', ...
    'welchOverlapFraction');

%% ------------------------------------------------------------------------
% Figure 1: one spectrum per participant
% -------------------------------------------------------------------------

nParticipants = height(summaryTable);

nColumns = 10;
nRows = ceil(nParticipants / nColumns);

fig1 = figure( ...
    'Color', 'w', ...
    'Position', [50 50 1800 1100]);

tiledlayout( ...
    nRows, ...
    nColumns, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

for iParticipant = 1:nParticipants

    nexttile;

    plot( ...
        frequencyVector, ...
        participantSpectraDb(iParticipant,:), ...
        'LineWidth', 1);

    hold on;

    xline(alphaBand(1), '--');
    xline(alphaBand(2), '--');

    if summaryTable.AlphaPeakDetected(iParticipant)

        plot( ...
            summaryTable.AlphaPeakFrequency_Hz(iParticipant), ...
            summaryTable.AlphaPeakPower_dB(iParticipant), ...
            'o', ...
            'MarkerSize', 4, ...
            'LineWidth', 1);
    end

    xlim(plotRange);

    title( ...
        summaryTable.Participant(iParticipant), ...
        'FontSize', 8);

    set(gca, ...
        'FontSize', 6, ...
        'Box', 'off');

    if mod(iParticipant - 1, nColumns) == 0
        ylabel('PSD (dB/Hz)');
    end

    if iParticipant > nParticipants - nColumns
        xlabel('Hz');
    end
end

sgtitle('Participant-level source spectra averaged across 20 ROIs');

individualFigureFile = fullfile( ...
    outputDir, ...
    'Alpha_peak_individual_spectra.png');

exportgraphics( ...
    fig1, ...
    individualFigureFile, ...
    'Resolution', 200);

%% ------------------------------------------------------------------------
% Figure 2: all participants and grand mean
% -------------------------------------------------------------------------

fig2 = figure( ...
    'Color', 'w', ...
    'Position', [100 100 900 600]);

hold on;

for iParticipant = 1:nParticipants
    plot( ...
        frequencyVector, ...
        participantSpectraDb(iParticipant,:), ...
        'LineWidth', 0.5);
end

grandMeanPSDdb = mean( ...
    participantSpectraDb, ...
    1, ...
    'omitnan');

plot( ...
    frequencyVector, ...
    grandMeanPSDdb, ...
    'k', ...
    'LineWidth', 3);

xline(alphaBand(1), '--');
xline(alphaBand(2), '--');

xlabel('Frequency (Hz)');
ylabel('Mean PSD across ROIs (dB/Hz)');
title('All participant spectra and grand mean');
xlim(plotRange);
box off;

grandMeanFigureFile = fullfile( ...
    outputDir, ...
    'Alpha_peak_all_participants.png');

exportgraphics( ...
    fig2, ...
    grandMeanFigureFile, ...
    'Resolution', 200);

%% ------------------------------------------------------------------------
% Print summary
% -------------------------------------------------------------------------

nDetected = sum(summaryTable.AlphaPeakDetected);
percentDetected = 100 * nDetected / nParticipants;

fprintf('\n============================================================\n');
fprintf('ALPHA PEAK CHECK COMPLETE\n');
fprintf('============================================================\n');
fprintf('Participants analysed:          %d\n', nParticipants);
fprintf('Participants with 8-13 Hz peak: %d/%d (%.1f%%)\n', ...
    nDetected, nParticipants, percentDetected);

if nDetected > 0
    fprintf('Median alpha peak frequency:    %.2f Hz\n', ...
        median( ...
            summaryTable.AlphaPeakFrequency_Hz( ...
                summaryTable.AlphaPeakDetected), ...
            'omitnan'));

    fprintf('Median peak prominence:         %.2f dB\n', ...
        median( ...
            summaryTable.AlphaPeakProminence_dB( ...
                summaryTable.AlphaPeakDetected), ...
            'omitnan'));
end

fprintf('\nSaved:\n');
fprintf('  %s\n', excelFile);
fprintf('  %s\n', matFile);
fprintf('  %s\n', individualFigureFile);
fprintf('  %s\n', grandMeanFigureFile);
fprintf('============================================================\n');
