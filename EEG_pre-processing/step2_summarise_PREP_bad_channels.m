function [participantTable, channelFrequencyTable, overallSummary, participantChannelTable] = ...
    step2_summarise_PREP_bad_channels(rootDir, dyads, namePattern, outputFile)
% STEP2_SUMMARISE_PREP_BAD_CHANNELS Summarise PREP bad-channel information.
%
% This function goes through all HyperYESNO dyads and both participants,
% loads only the metadata from each PREP-processed EEGLAB dataset, and
% extracts the channel-quality information stored by the PREP pipeline.
%
% The function creates four MATLAB tables:
%
%   1) participantTable
%      One row per participant, including:
%        - number and percentage of channels detected as bad;
%        - channel indices and labels;
%        - number of interpolated channels;
%        - number of channels actually removed from the dataset;
%        - channels that remained noisy after PREP;
%        - counts for the individual PREP detection methods.
%
%   2) channelFrequencyTable
%      One row per channel, showing how often that channel was detected as
%      bad, interpolated, removed, or still noisy across participants.
%      This is the most useful table for checking whether frontopolar
%      channels are consistently affected.
%
%   3) overallSummary
%      Dataset-level descriptive statistics, including the mean, standard
%      deviation, median, minimum, and maximum number of bad channels.
%
%   4) participantChannelTable
%      Long-format table with one row per participant and original channel.
%      It contains logical flags for the different PREP detection methods.
%
% The tables are also written to an Excel workbook, with one sheet per
% table, and saved together in a MATLAB .mat file.
%
% IMPORTANT TERMINOLOGY
% ---------------------
% PREP normally DETECTS bad channels and may INTERPOLATE them. A channel
% identified in:
%
%   EEG.etc.noiseDetection.reference.badChannels.all
%
% is not necessarily absent from EEG.data after PREP. Therefore, this
% function reports separately:
%
%   - bad channels detected during robust referencing;
%   - interpolated channels;
%   - channels explicitly removed from the dataset;
%   - channels that remained noisy.
%
% DEFAULT HYPERYESNO FOLDER STRUCTURE
% ----------------------------------
% rootDir
%   Dyad01
%       SubjA
%           Dyad01-A_PREP.set
%       SubjB
%           Dyad01-B_PREP.set
%   Dyad02
%       ...
%
% USAGE
% -----
% Use all defaults:
%
%   [participantTable, channelFrequencyTable, overallSummary, ...
%       participantChannelTable] = step2_summarise_PREP_bad_channels;
%
% Specify a different root directory:
%
%   rootDir = 'E:\EEG_data_HyperYESNO';
%   [participantTable, channelFrequencyTable, overallSummary, ...
%       participantChannelTable] = ...
%       step2_summarise_PREP_bad_channels(rootDir);
%
% Specify a different filename pattern:
%
%   % Loads files such as Dyad01-A_PREP.set
%   namePattern = '_PREP';
%
%   % A wildcard can be used, but exact patterns are safer because a broad
%   % wildcard may also match files from later processing stages.
%   namePattern = '_PREP*';
%
% OUTPUT FILES
% ------------
% By default, the following files are created in rootDir:
%
%   PREP_bad_channel_summary.xlsx
%   PREP_bad_channel_summary.mat
%
% REQUIREMENTS
% ------------
% EEGLAB must be on the MATLAB path. The function uses:
%
%   pop_loadset(..., 'loadmode', 'info')
%
% so that the large EEG data matrix or paired .fdt file is not loaded.
%
% Author: Alejandro Perez / OpenAI
% HyperYESNO project

%% ------------------------------------------------------------------------
% 1. Input defaults
% -------------------------------------------------------------------------

if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end

if nargin < 2 || isempty(dyads)
    dyads = 1:35;
end

if nargin < 3 || isempty(namePattern)
    namePattern = '_PREP';
end

if nargin < 4 || isempty(outputFile)
    outputFile = fullfile(rootDir, 'PREP_bad_channel_summary.xlsx');
end

% Convert text inputs to character vectors for compatibility with older
% MATLAB and EEGLAB versions.
rootDir    = char(rootDir);
namePattern = char(namePattern);
outputFile = char(outputFile);

% HyperYESNO contains two participants per dyad.
tags = {'A', 'B'};

% Check that EEGLAB is available before entering the batch loop.
if exist('pop_loadset', 'file') ~= 2
    error(['EEGLAB was not found on the MATLAB path. Start EEGLAB or add ', ...
        'the EEGLAB folder to the MATLAB path before running this function.']);
end

% Create the output folder if it does not already exist.
outputFolder = fileparts(outputFile);

if isempty(outputFolder)
    outputFolder = pwd;
    outputFile = fullfile(outputFolder, outputFile);
elseif ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% ------------------------------------------------------------------------
% 2. Preallocate participant records
% -------------------------------------------------------------------------

nExpectedParticipants = numel(dyads) * numel(tags);

participantRecords = repmat(local_empty_participant_record(), ...
    nExpectedParticipants, 1);

% Each cell will contain the long-format channel table for one participant.
participantChannelTables = cell(nExpectedParticipants, 1);

participantCounter = 0;

%% ------------------------------------------------------------------------
% 3. Go through each dyad and each participant
% -------------------------------------------------------------------------

for d = dyads

    % Example: d = 4 produces 'Dyad04'.
    dyadStr = sprintf('Dyad%02d', d);

    for ti = 1:numel(tags)

        participantCounter = participantCounter + 1;

        tag = tags{ti};

        % Create the participant identifiers and folder path.
        participantName = sprintf('Dyad%02d-%s', d, tag);
        participantFolder = fullfile(rootDir, dyadStr, ['Subj' tag]);

        % Begin with an empty record. Missing files or invalid PREP
        % structures can therefore still be represented in the final table.
        record = local_empty_participant_record();

        record.Dyad        = d;
        record.Member      = string(tag);
        record.Participant = string(participantName);
        record.Folder      = string(participantFolder);

        %% Find the PREP-processed .set file

        % Example with namePattern = '_PREP':
        %   Dyad04-A_PREP.set
        setPattern = [participantName, namePattern, '.set'];
        matchingFiles = dir(fullfile(participantFolder, setPattern));

        if isempty(matchingFiles)

            record.FileFound = false;
            record.Notes = "No file matched: " + string(setPattern);

            fprintf('No match in %s for "%s"\n', ...
                participantFolder, setPattern);

            participantRecords(participantCounter) = record;
            continue;

        end

        record.FileFound = true;

        % If a wildcard matched several files, use the newest file, matching
        % the convention used in the earlier HyperYESNO batch scripts.
        if numel(matchingFiles) > 1

            [~, newestIndex] = max([matchingFiles.datenum]);
            selectedFile = matchingFiles(newestIndex);

            record.Notes = string(sprintf( ...
                '%d files matched; newest file used.', ...
                numel(matchingFiles)));

        else
            selectedFile = matchingFiles(1);
        end

        record.File = string(selectedFile.name);

        fprintf('\nReading PREP information: %s\n', ...
            fullfile(participantFolder, selectedFile.name));

        %% Load only EEGLAB metadata

        try
            EEG = pop_loadset( ...
                'filename', selectedFile.name, ...
                'filepath', participantFolder, ...
                'loadmode', 'info', ...
                'check', 'off');
        catch ME

            record.Notes = local_append_note(record.Notes, ...
                "Could not load dataset: " + string(ME.message));

            participantRecords(participantCounter) = record;
            continue;

        end

        % Number of channels physically present in the current EEGLAB
        % dataset. This can remain unchanged even when PREP interpolated
        % several bad channels.
        if isfield(EEG, 'nbchan') && ~isempty(EEG.nbchan)
            record.NCurrentChannels = double(EEG.nbchan);
        end

        %% Check for the PREP output structure

        if ~isfield(EEG, 'etc') || ...
                ~isfield(EEG.etc, 'noiseDetection') || ...
                isempty(EEG.etc.noiseDetection)

            record.Notes = local_append_note(record.Notes, ...
                "EEG.etc.noiseDetection was not found.");

            participantRecords(participantCounter) = record;
            continue;

        end

        noiseDetection = EEG.etc.noiseDetection;

        %% Extract PREP processing status

        [prepStatus, statusFound] = local_get_nested_field( ...
            noiseDetection, {'errors', 'status'});

        if statusFound && ~isempty(prepStatus)
            record.PREPStatus = string(prepStatus);
        else
            record.PREPStatus = "unknown";
        end

        %% Extract the bad-channel structure and method-specific results

        [badChannelStruct, badStructFound] = local_get_nested_field( ...
            noiseDetection, {'reference', 'badChannels'});

        if ~badStructFound || ~isstruct(badChannelStruct)
            badChannelStruct = struct();
        end

        % PREP may identify channels using several complementary criteria.
        badNaNs = local_get_first_numeric_field( ...
            badChannelStruct, {'badChannelsFromNaNs'});

        badNoData = local_get_first_numeric_field( ...
            badChannelStruct, {'badChannelsFromNoData'});

        badHFNoise = local_get_first_numeric_field( ...
            badChannelStruct, {'badChannelsFromHFNoise'});

        badCorrelation = local_get_first_numeric_field( ...
            badChannelStruct, {'badChannelsFromCorrelation'});

        badDeviation = local_get_first_numeric_field( ...
            badChannelStruct, {'badChannelsFromDeviation'});

        badRANSAC = local_get_first_numeric_field( ...
            badChannelStruct, ...
            {'badChannelsFromRansac', 'badChannelsFromRANSAC'});

        % Different PREP releases have used slightly different capitalisation
        % or pluralisation for the dropout field.
        badDropout = local_get_first_numeric_field( ...
            badChannelStruct, ...
            {'badChannelsFromDropOuts', ...
             'badChannelsFromDropouts', ...
             'badChannelsFromDropout'});

        %% Extract the overall bad-channel list

        [badChannelsRaw, badChannelsFound] = local_get_nested_field( ...
            noiseDetection, {'reference', 'badChannels', 'all'});

        if badChannelsFound

            badChannels = local_normalise_indices(badChannelsRaw);
            record.BadChannelSource = ...
                "EEG.etc.noiseDetection.reference.badChannels.all";

        else

            % Fallback 1:
            % Reconstruct the overall list from the individual detection
            % methods if the .all field is absent.
            methodUnion = unique([ ...
                badNaNs, ...
                badNoData, ...
                badHFNoise, ...
                badCorrelation, ...
                badDeviation, ...
                badRANSAC, ...
                badDropout]);

            if ~isempty(methodUnion)

                badChannels = methodUnion;
                badChannelsFound = true;
                record.BadChannelSource = ...
                    "Union of PREP method-specific bad-channel fields";

            else

                % Fallback 2:
                % Older or modified PREP outputs may retain the interpolated
                % channel list but not the badChannels.all field.
                [fallbackBad, fallbackFound] = local_get_nested_field( ...
                    noiseDetection, ...
                    {'reference', 'interpolatedChannels', 'all'});

                if ~fallbackFound
                    [fallbackBad, fallbackFound] = local_get_nested_field( ...
                        noiseDetection, {'interpolatedChannelNumbers'});
                end

                if fallbackFound
                    badChannels = local_normalise_indices(fallbackBad);
                    badChannelsFound = true;
                    record.BadChannelSource = ...
                        "Fallback: PREP interpolated-channel list";
                else
                    badChannels = [];
                    record.BadChannelSource = "Not found";
                end
            end
        end

        %% Extract channels interpolated by PREP

        [interpolatedRaw, interpolatedFound] = local_get_nested_field( ...
            noiseDetection, ...
            {'reference', 'interpolatedChannels', 'all'});

        if ~interpolatedFound
            [interpolatedRaw, interpolatedFound] = local_get_nested_field( ...
                noiseDetection, {'interpolatedChannelNumbers'});
        end

        if interpolatedFound
            interpolatedChannels = local_normalise_indices(interpolatedRaw);
        else
            interpolatedChannels = [];
        end

        %% Extract channels explicitly removed from the dataset

        [removedRaw, removedFound] = local_get_nested_field( ...
            noiseDetection, {'removedChannelNumbers'});

        if removedFound
            removedChannels = local_normalise_indices(removedRaw);
        else
            removedChannels = [];
        end

        %% Extract channels that remained noisy after PREP

        [stillNoisyRaw, stillNoisyFound] = local_get_nested_field( ...
            noiseDetection, {'stillNoisyChannelNumbers'});

        if ~stillNoisyFound
            [stillNoisyRaw, stillNoisyFound] = local_get_nested_field( ...
                noiseDetection, ...
                {'reference', 'noisyStatistics', 'noisyChannels', 'all'});
        end

        if stillNoisyFound
            stillNoisyChannels = local_normalise_indices(stillNoisyRaw);
        else
            stillNoisyChannels = [];
        end

        %% Recover the original channel labels

        % PREP stores the labels before processing in:
        %
        %   EEG.etc.noiseDetection.originalChannelLabels
        %
        % This is preferable to EEG.chanlocs when some channels were later
        % removed from the current dataset.
        [originalLabels, labelSource] = ...
            local_get_original_channel_labels(EEG, noiseDetection);

        record.ChannelLabelSource = labelSource;

        % Determine the largest channel index referenced by any PREP field.
        allReportedIndices = [ ...
            badChannels, ...
            interpolatedChannels, ...
            removedChannels, ...
            stillNoisyChannels, ...
            badNaNs, ...
            badNoData, ...
            badHFNoise, ...
            badCorrelation, ...
            badDeviation, ...
            badRANSAC, ...
            badDropout];

        if isempty(allReportedIndices)
            largestReportedIndex = 0;
        else
            largestReportedIndex = max(allReportedIndices);
        end

        % If the original labels are unavailable or incomplete, create
        % placeholder labels so that no reported index is silently lost.
        if numel(originalLabels) < largestReportedIndex

            oldNumberOfLabels = numel(originalLabels);
            originalLabels(end + 1:largestReportedIndex, 1) = ...
                "Ch" + string((oldNumberOfLabels + 1:largestReportedIndex)');

            record.Notes = local_append_note(record.Notes, ...
                "Some original labels were unavailable; ChN placeholders used.");
        end

        record.NOriginalChannels = numel(originalLabels);

        %% Validate all channel indices against the original channel list

        [badChannels, invalidBad] = ...
            local_validate_indices(badChannels, numel(originalLabels));

        [interpolatedChannels, invalidInterpolated] = ...
            local_validate_indices(interpolatedChannels, numel(originalLabels));

        [removedChannels, invalidRemoved] = ...
            local_validate_indices(removedChannels, numel(originalLabels));

        [stillNoisyChannels, invalidStillNoisy] = ...
            local_validate_indices(stillNoisyChannels, numel(originalLabels));

        [badNaNs, invalidNaNs] = ...
            local_validate_indices(badNaNs, numel(originalLabels));

        [badNoData, invalidNoData] = ...
            local_validate_indices(badNoData, numel(originalLabels));

        [badHFNoise, invalidHFNoise] = ...
            local_validate_indices(badHFNoise, numel(originalLabels));

        [badCorrelation, invalidCorrelation] = ...
            local_validate_indices(badCorrelation, numel(originalLabels));

        [badDeviation, invalidDeviation] = ...
            local_validate_indices(badDeviation, numel(originalLabels));

        [badRANSAC, invalidRANSAC] = ...
            local_validate_indices(badRANSAC, numel(originalLabels));

        [badDropout, invalidDropout] = ...
            local_validate_indices(badDropout, numel(originalLabels));

        invalidIndices = unique([ ...
            invalidBad, ...
            invalidInterpolated, ...
            invalidRemoved, ...
            invalidStillNoisy, ...
            invalidNaNs, ...
            invalidNoData, ...
            invalidHFNoise, ...
            invalidCorrelation, ...
            invalidDeviation, ...
            invalidRANSAC, ...
            invalidDropout]);

        if ~isempty(invalidIndices)
            record.Notes = local_append_note(record.Notes, ...
                "Ignored invalid channel indices: " + ...
                local_indices_to_string(invalidIndices));
        end

        %% Fill the participant-level summary record

        record.NBadChannels = numel(badChannels);
        record.BadChannelIndices = local_indices_to_string(badChannels);
        record.BadChannelLabels = ...
            local_indices_to_label_string(badChannels, originalLabels);

        if record.NOriginalChannels > 0
            record.PercentBadChannels = ...
                100 * record.NBadChannels / record.NOriginalChannels;
        end

        record.NInterpolatedChannels = numel(interpolatedChannels);
        record.InterpolatedChannelIndices = ...
            local_indices_to_string(interpolatedChannels);
        record.InterpolatedChannelLabels = ...
            local_indices_to_label_string( ...
                interpolatedChannels, originalLabels);

        record.NRemovedChannels = numel(removedChannels);
        record.RemovedChannelIndices = ...
            local_indices_to_string(removedChannels);
        record.RemovedChannelLabels = ...
            local_indices_to_label_string(removedChannels, originalLabels);

        record.NStillNoisyChannels = numel(stillNoisyChannels);
        record.StillNoisyChannelIndices = ...
            local_indices_to_string(stillNoisyChannels);
        record.StillNoisyChannelLabels = ...
            local_indices_to_label_string( ...
                stillNoisyChannels, originalLabels);

        record.NBadNaNs        = numel(badNaNs);
        record.NBadNoData      = numel(badNoData);
        record.NBadHFNoise     = numel(badHFNoise);
        record.NBadCorrelation = numel(badCorrelation);
        record.NBadDeviation   = numel(badDeviation);
        record.NBadRANSAC      = numel(badRANSAC);
        record.NBadDropout     = numel(badDropout);

        % A participant is included when an overall bad-channel list was
        % available and PREP did not explicitly report an unprocessed file.
        record.IncludedInSummary = badChannelsFound && ...
            ~strcmpi(record.PREPStatus, "unprocessed");

        if ~badChannelsFound
            record.Notes = local_append_note(record.Notes, ...
                "No overall PREP bad-channel list was available.");
        end

        %% Create the long-format participant-by-channel table

        if record.IncludedInSummary && ~isempty(originalLabels)

            channelIndex = (1:numel(originalLabels))';

            participantChannelTables{participantCounter} = table( ...
                repmat(d, numel(originalLabels), 1), ...
                repmat(string(tag), numel(originalLabels), 1), ...
                repmat(string(participantName), numel(originalLabels), 1), ...
                channelIndex, ...
                originalLabels(:), ...
                ismember(channelIndex, badChannels(:)), ...
                ismember(channelIndex, interpolatedChannels(:)), ...
                ismember(channelIndex, removedChannels(:)), ...
                ismember(channelIndex, stillNoisyChannels(:)), ...
                ismember(channelIndex, badNaNs(:)), ...
                ismember(channelIndex, badNoData(:)), ...
                ismember(channelIndex, badHFNoise(:)), ...
                ismember(channelIndex, badCorrelation(:)), ...
                ismember(channelIndex, badDeviation(:)), ...
                ismember(channelIndex, badRANSAC(:)), ...
                ismember(channelIndex, badDropout(:)), ...
                'VariableNames', { ...
                    'Dyad', ...
                    'Member', ...
                    'Participant', ...
                    'ChannelIndex', ...
                    'ChannelLabel', ...
                    'IsBad', ...
                    'IsInterpolated', ...
                    'IsRemoved', ...
                    'IsStillNoisy', ...
                    'BadByNaN', ...
                    'BadByNoData', ...
                    'BadByHFNoise', ...
                    'BadByCorrelation', ...
                    'BadByDeviation', ...
                    'BadByRANSAC', ...
                    'BadByDropout'});
        end

        participantRecords(participantCounter) = record;

    end
end

%% ------------------------------------------------------------------------
% 4. Convert participant records to a table
% -------------------------------------------------------------------------

participantTable = struct2table(participantRecords);

% Keep the participant rows in dyad/member order.
participantTable = sortrows(participantTable, {'Dyad', 'Member'});

%% ------------------------------------------------------------------------
% 5. Combine all participant-by-channel tables
% -------------------------------------------------------------------------

nonEmptyChannelTables = ~cellfun(@isempty, participantChannelTables);

if any(nonEmptyChannelTables)
    participantChannelTable = vertcat( ...
        participantChannelTables{nonEmptyChannelTables});
else
    participantChannelTable = local_empty_participant_channel_table();
end

%% ------------------------------------------------------------------------
% 6. Calculate how frequently each channel was affected
% -------------------------------------------------------------------------

if ~isempty(participantChannelTable)

    % Group by both original index and label. Under a consistent montage,
    % every participant should contribute once to each group.
    [groupIndex, channelIndex, channelLabel] = findgroups( ...
        participantChannelTable.ChannelIndex, ...
        participantChannelTable.ChannelLabel);

    nParticipantsAvailable = splitapply( ...
        @numel, participantChannelTable.IsBad, groupIndex);

    nBad = splitapply( ...
        @sum, participantChannelTable.IsBad, groupIndex);

    nInterpolated = splitapply( ...
        @sum, participantChannelTable.IsInterpolated, groupIndex);

    nRemoved = splitapply( ...
        @sum, participantChannelTable.IsRemoved, groupIndex);

    nStillNoisy = splitapply( ...
        @sum, participantChannelTable.IsStillNoisy, groupIndex);

    nBadNaN = splitapply( ...
        @sum, participantChannelTable.BadByNaN, groupIndex);

    nBadNoData = splitapply( ...
        @sum, participantChannelTable.BadByNoData, groupIndex);

    nBadHFNoise = splitapply( ...
        @sum, participantChannelTable.BadByHFNoise, groupIndex);

    nBadCorrelation = splitapply( ...
        @sum, participantChannelTable.BadByCorrelation, groupIndex);

    nBadDeviation = splitapply( ...
        @sum, participantChannelTable.BadByDeviation, groupIndex);

    nBadRANSAC = splitapply( ...
        @sum, participantChannelTable.BadByRANSAC, groupIndex);

    nBadDropout = splitapply( ...
        @sum, participantChannelTable.BadByDropout, groupIndex);

    channelFrequencyTable = table( ...
        channelIndex, ...
        channelLabel, ...
        nParticipantsAvailable, ...
        nBad, ...
        100 .* nBad ./ nParticipantsAvailable, ...
        nInterpolated, ...
        100 .* nInterpolated ./ nParticipantsAvailable, ...
        nRemoved, ...
        100 .* nRemoved ./ nParticipantsAvailable, ...
        nStillNoisy, ...
        100 .* nStillNoisy ./ nParticipantsAvailable, ...
        nBadNaN, ...
        nBadNoData, ...
        nBadHFNoise, ...
        nBadCorrelation, ...
        nBadDeviation, ...
        nBadRANSAC, ...
        nBadDropout, ...
        'VariableNames', { ...
            'ChannelIndex', ...
            'ChannelLabel', ...
            'NParticipantsAvailable', ...
            'NBad', ...
            'PercentBad', ...
            'NInterpolated', ...
            'PercentInterpolated', ...
            'NRemoved', ...
            'PercentRemoved', ...
            'NStillNoisy', ...
            'PercentStillNoisy', ...
            'NBadNaN', ...
            'NBadNoData', ...
            'NBadHFNoise', ...
            'NBadCorrelation', ...
            'NBadDeviation', ...
            'NBadRANSAC', ...
            'NBadDropout'});

    % Put the most consistently affected channels at the top.
    channelFrequencyTable = sortrows( ...
        channelFrequencyTable, ...
        {'NBad', 'NInterpolated', 'ChannelIndex'}, ...
        {'descend', 'descend', 'ascend'});

    channelFrequencyTable.RankByBadFrequency = ...
        (1:height(channelFrequencyTable))';

    channelFrequencyTable = movevars( ...
        channelFrequencyTable, ...
        'RankByBadFrequency', ...
        'Before', 1);

else
    channelFrequencyTable = local_empty_channel_frequency_table();
end

%% ------------------------------------------------------------------------
% 7. Calculate overall descriptive statistics
% -------------------------------------------------------------------------

included = participantTable.IncludedInSummary;

badCounts = participantTable.NBadChannels(included);
badPercentages = participantTable.PercentBadChannels(included);
interpolatedCounts = participantTable.NInterpolatedChannels(included);
removedCounts = participantTable.NRemovedChannels(included);
stillNoisyCounts = participantTable.NStillNoisyChannels(included);

overallSummary = table( ...
    nExpectedParticipants, ...
    sum(participantTable.FileFound), ...
    sum(included), ...
    sum(~participantTable.FileFound), ...
    sum(participantTable.FileFound & ~included), ...
    local_mean_or_nan(badCounts), ...
    local_std_or_nan(badCounts), ...
    local_median_or_nan(badCounts), ...
    local_min_or_nan(badCounts), ...
    local_max_or_nan(badCounts), ...
    local_mean_or_nan(badPercentages), ...
    local_mean_or_nan(interpolatedCounts), ...
    local_mean_or_nan(removedCounts), ...
    local_mean_or_nan(stillNoisyCounts), ...
    'VariableNames', { ...
        'NParticipantsExpected', ...
        'NFilesFound', ...
        'NParticipantsIncluded', ...
        'NMissingFiles', ...
        'NFilesExcludedFromSummary', ...
        'MeanBadChannels', ...
        'SDBadChannels', ...
        'MedianBadChannels', ...
        'MinimumBadChannels', ...
        'MaximumBadChannels', ...
        'MeanPercentBadChannels', ...
        'MeanInterpolatedChannels', ...
        'MeanRemovedChannels', ...
        'MeanStillNoisyChannels'});

%% ------------------------------------------------------------------------
% 8. Save the tables
% -------------------------------------------------------------------------

% Delete an existing workbook first so that obsolete sheets are not retained.
if exist(outputFile, 'file') == 2
    delete(outputFile);
end

writetable(participantTable, ...
    outputFile, 'Sheet', 'ParticipantSummary');

writetable(channelFrequencyTable, ...
    outputFile, 'Sheet', 'ChannelFrequency');

writetable(overallSummary, ...
    outputFile, 'Sheet', 'OverallSummary');

writetable(participantChannelTable, ...
    outputFile, 'Sheet', 'ParticipantChannelDetail');

% Save the MATLAB tables as well, preserving logical and numeric types.
[outputFolder, outputBaseName] = fileparts(outputFile);

matOutputFile = fullfile( ...
    outputFolder, [outputBaseName, '.mat']);

save(matOutputFile, ...
    'participantTable', ...
    'channelFrequencyTable', ...
    'overallSummary', ...
    'participantChannelTable');

%% ------------------------------------------------------------------------
% 9. Display the main results
% -------------------------------------------------------------------------

fprintf('\nPREP bad-channel summary completed.\n');
fprintf('Participants expected: %d\n', nExpectedParticipants);
fprintf('PREP files found: %d\n', sum(participantTable.FileFound));
fprintf('Participants included: %d\n', sum(included));

if any(included)
    fprintf('Mean number of bad channels: %.2f\n', ...
        overallSummary.MeanBadChannels);
    fprintf('Median number of bad channels: %.2f\n', ...
        overallSummary.MedianBadChannels);
end

fprintf('Excel output: %s\n', outputFile);
fprintf('MATLAB output: %s\n\n', matOutputFile);

% Display the overall summary and the channels most frequently marked bad.
disp(overallSummary);

if ~isempty(channelFrequencyTable)
    nRowsToDisplay = min(15, height(channelFrequencyTable));
    disp(channelFrequencyTable(1:nRowsToDisplay, :));
end

end


%% =========================================================================
% Local helper functions
% =========================================================================

function record = local_empty_participant_record()
% Create one empty participant-level record with fixed field types.

record = struct( ...
    'Dyad', NaN, ...
    'Member', "", ...
    'Participant', "", ...
    'Folder', "", ...
    'File', "", ...
    'FileFound', false, ...
    'PREPStatus', "", ...
    'IncludedInSummary', false, ...
    'NOriginalChannels', NaN, ...
    'NCurrentChannels', NaN, ...
    'NBadChannels', NaN, ...
    'PercentBadChannels', NaN, ...
    'BadChannelIndices', "", ...
    'BadChannelLabels', "", ...
    'BadChannelSource', "", ...
    'NInterpolatedChannels', NaN, ...
    'InterpolatedChannelIndices', "", ...
    'InterpolatedChannelLabels', "", ...
    'NRemovedChannels', NaN, ...
    'RemovedChannelIndices', "", ...
    'RemovedChannelLabels', "", ...
    'NStillNoisyChannels', NaN, ...
    'StillNoisyChannelIndices', "", ...
    'StillNoisyChannelLabels', "", ...
    'NBadNaNs', NaN, ...
    'NBadNoData', NaN, ...
    'NBadHFNoise', NaN, ...
    'NBadCorrelation', NaN, ...
    'NBadDeviation', NaN, ...
    'NBadRANSAC', NaN, ...
    'NBadDropout', NaN, ...
    'ChannelLabelSource', "", ...
    'Notes', "");
end


function [value, found] = local_get_nested_field(inputStruct, fieldPath)
% Safely retrieve a value from a nested structure.
%
% Example:
%   [value, found] = local_get_nested_field(S, ...
%       {'reference', 'badChannels', 'all'});

value = inputStruct;
found = true;

for iField = 1:numel(fieldPath)

    thisField = fieldPath{iField};

    if isstruct(value) && isfield(value, thisField)
        value = value.(thisField);
    else
        value = [];
        found = false;
        return;
    end
end
end


function indices = local_get_first_numeric_field(inputStruct, fieldNames)
% Return the first available numeric channel-index field.

indices = [];

if ~isstruct(inputStruct)
    return;
end

for iField = 1:numel(fieldNames)

    thisField = fieldNames{iField};

    if isfield(inputStruct, thisField)
        indices = local_normalise_indices(inputStruct.(thisField));
        return;
    end
end
end


function indices = local_normalise_indices(rawIndices)
% Convert a PREP channel-index field into a sorted numeric row vector.

if isempty(rawIndices)
    indices = [];
    return;
end

% Some saved structures may wrap numeric arrays inside a cell.
if iscell(rawIndices)
    try
        rawIndices = cell2mat(rawIndices);
    catch
        indices = [];
        return;
    end
end

% A logical vector is interpreted as a channel mask.
if islogical(rawIndices)
    rawIndices = find(rawIndices);
end

if ~isnumeric(rawIndices)
    indices = [];
    return;
end

indices = double(rawIndices(:)');

% Retain only finite, positive integer channel indices.
indices = indices( ...
    isfinite(indices) & ...
    indices > 0 & ...
    indices == round(indices));

indices = unique(indices, 'sorted');
end


function [validIndices, invalidIndices] = ...
    local_validate_indices(indices, numberOfChannels)
% Separate channel indices into valid and invalid values.

indices = local_normalise_indices(indices);

if isempty(indices)
    validIndices = [];
    invalidIndices = [];
    return;
end

isValid = indices >= 1 & indices <= numberOfChannels;

validIndices = indices(isValid);
invalidIndices = indices(~isValid);
end


function [labels, source] = ...
    local_get_original_channel_labels(EEG, noiseDetection)
% Recover original labels, preferring the copy saved by PREP.

labels = strings(0, 1);
source = "Unavailable";

if isfield(noiseDetection, 'originalChannelLabels') && ...
        ~isempty(noiseDetection.originalChannelLabels)

    labels = local_convert_labels_to_string( ...
        noiseDetection.originalChannelLabels);

    source = ...
        "EEG.etc.noiseDetection.originalChannelLabels";

elseif isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && ...
        isfield(EEG.chanlocs, 'labels')

    labels = local_convert_labels_to_string( ...
        {EEG.chanlocs.labels});

    source = "EEG.chanlocs.labels";
elseif isfield(EEG, 'nbchan') && ~isempty(EEG.nbchan) && EEG.nbchan > 0
    labels = "Ch" + string((1:double(EEG.nbchan))');
    source = "Generated from EEG.nbchan";
end

% Replace empty labels with explicit channel-number placeholders.
for iChannel = 1:numel(labels)
    if strlength(strtrim(labels(iChannel))) == 0
        labels(iChannel) = "Ch" + string(iChannel);
    end
end
end


function labels = local_convert_labels_to_string(rawLabels)
% Convert common EEGLAB/PREP label formats into a string column vector.

if isempty(rawLabels)
    labels = strings(0, 1);
    return;
end

% Unwrap a single nested cell, if present.
if iscell(rawLabels) && numel(rawLabels) == 1 && ...
        iscell(rawLabels{1})
    rawLabels = rawLabels{1};
end

try
    if ischar(rawLabels)
        % A character matrix stores one label per row.
        labels = string(cellstr(rawLabels));
        labels = labels(:);
    else
        labels = string(rawLabels(:));
    end
catch
    labels = strings(0, 1);
end
end


function textOutput = local_indices_to_string(indices)
% Convert a numeric vector into a compact comma-separated string.

indices = local_normalise_indices(indices);

if isempty(indices)
    textOutput = "";
else
    textOutput = strjoin(string(indices), ", ");
end
end


function textOutput = ...
    local_indices_to_label_string(indices, originalLabels)
% Convert channel indices into a comma-separated channel-label string.

indices = local_normalise_indices(indices);

if isempty(indices)
    textOutput = "";
else
    textOutput = strjoin(originalLabels(indices), ", ");
end
end


function outputNote = local_append_note(existingNote, newNote)
% Append a note while avoiding leading or repeated separators.

existingNote = string(existingNote);
newNote = string(newNote);

if strlength(existingNote) == 0
    outputNote = newNote;
elseif strlength(newNote) == 0
    outputNote = existingNote;
else
    outputNote = existingNote + " | " + newNote;
end
end


function value = local_mean_or_nan(x)
% Mean with NaN returned for an empty input.

x = x(~isnan(x));

if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end


function value = local_std_or_nan(x)
% Sample standard deviation with NaN returned for fewer than two values.

x = x(~isnan(x));

if numel(x) < 2
    value = NaN;
else
    value = std(x);
end
end


function value = local_median_or_nan(x)
% Median with NaN returned for an empty input.

x = x(~isnan(x));

if isempty(x)
    value = NaN;
else
    value = median(x);
end
end


function value = local_min_or_nan(x)
% Minimum with NaN returned for an empty input.

x = x(~isnan(x));

if isempty(x)
    value = NaN;
else
    value = min(x);
end
end


function value = local_max_or_nan(x)
% Maximum with NaN returned for an empty input.

x = x(~isnan(x));

if isempty(x)
    value = NaN;
else
    value = max(x);
end
end


function outputTable = local_empty_participant_channel_table()
% Create an empty table with the long-format output variables.

outputTable = table( ...
    zeros(0, 1), ...
    strings(0, 1), ...
    strings(0, 1), ...
    zeros(0, 1), ...
    strings(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    false(0, 1), ...
    'VariableNames', { ...
        'Dyad', ...
        'Member', ...
        'Participant', ...
        'ChannelIndex', ...
        'ChannelLabel', ...
        'IsBad', ...
        'IsInterpolated', ...
        'IsRemoved', ...
        'IsStillNoisy', ...
        'BadByNaN', ...
        'BadByNoData', ...
        'BadByHFNoise', ...
        'BadByCorrelation', ...
        'BadByDeviation', ...
        'BadByRANSAC', ...
        'BadByDropout'});
end


function outputTable = local_empty_channel_frequency_table()
% Create an empty table with the channel-frequency output variables.

outputTable = table( ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    strings(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), ...
    'VariableNames', { ...
        'RankByBadFrequency', ...
        'ChannelIndex', ...
        'ChannelLabel', ...
        'NParticipantsAvailable', ...
        'NBad', ...
        'PercentBad', ...
        'NInterpolated', ...
        'PercentInterpolated', ...
        'NRemoved', ...
        'PercentRemoved', ...
        'NStillNoisy', ...
        'PercentStillNoisy', ...
        'NBadNaN', ...
        'NBadNoData', ...
        'NBadHFNoise', ...
        'NBadCorrelation', ...
        'NBadDeviation', ...
        'NBadRANSAC', ...
        'NBadDropout'});
end
