%% Wrapper to synchronise all dyads by audio using sync_videos_by_audio.m
% This script:
%  1) Loops over Dyad01 ... Dyad35 inside the base folder.
%  2) For each dyad, finds the A and B .mp4 files by prefix (DyadXX-A_* / DyadXX-B_*).
%  3) Calls sync_videos_by_audio(videoA, videoB, outA, outB).
%  4) Saves outputs in each video's own folder as DyadXX-A_sync.mp4 / DyadXX-B_sync.mp4.
%
% Requirements:
%  - The function sync_videos_by_audio.m must be on the MATLAB path.

clear; clc;

%% ------------------ USER SETTINGS ------------------
% Base folder that contains Dyad01 ... Dyad35 directories
baseFolder = 'D:\HyperYESNO_videosCUT';

% How many dyads to process (Dyad01 .. Dyad35)
nDyads = 35;

% If true, stop the script immediately when a dyad fails.
% If false, continue to the next dyad and report errors at the end.
stopOnError = false;

% Optional parameters passed to sync_videos_by_audio (keep simple by default)
opts.TargetFs     = 16000;   % resample rate used for lag estimation
opts.PadWithBlack = false;   % false = trim earlier video; true = pad later video with black
opts.MaxSearchLag = 5;       % limit lag search (seconds)
opts.Verbose      = true;    % print progress
%% ----------------------------------------------------

% Storage for any errors we encounter (so we can review at the end)
errors = struct('dyad', {}, 'message', {});

fprintf('== Sync run started ==\nBase: %s\n\n', baseFolder);

for k = 1:nDyads
    % --------- Build canonical dyad name "DyadXX" (with zero padding) ---------
    dyadName = sprintf('Dyad%02d', k);

    % --------- Build the A/B subfolder names and absolute paths ---------------
    aFolderName = [dyadName '-A_cut'];      % e.g., 'Dyad01-A_cut'
    bFolderName = [dyadName '-B_cut'];      % e.g., 'Dyad01-B_cut'

    aFolder = fullfile(baseFolder, dyadName, aFolderName);
    bFolder = fullfile(baseFolder, dyadName, bFolderName);

    fprintf('--- %s ---\n', dyadName);

    try
        % ----- Sanity checks: A/B folders must exist --------------------------
        if ~isfolder(aFolder)
            error('Missing folder: %s', aFolder);
        end
        if ~isfolder(bFolder)
            error('Missing folder: %s', bFolder);
        end

        % ----- Find the A and B .mp4 files by prefix --------------------------
        % We search for files starting with "DyadXX-A_" / "DyadXX-B_" and ending in ".mp4"
        % If multiple match, we take the first (you can refine if needed).
        aPattern = sprintf('%s-A_*.mp4', dyadName);
        bPattern = sprintf('%s-B_*.mp4', dyadName);

        aFile = find_first_file(aFolder, aPattern);
        bFile = find_first_file(bFolder, bPattern);

        if isempty(aFile)
            error('No A video found in %s matching "%s".', aFolder, aPattern);
        end
        if isempty(bFile)
            error('No B video found in %s matching "%s".', bFolder, bPattern);
        end

        videoA = fullfile(aFolder, aFile);
        videoB = fullfile(bFolder, bFile);

        % ----- Build output paths (saved into their respective folders) -------
        outA = fullfile(aFolder, sprintf('%s-A_sync.mp4', dyadName));
        outB = fullfile(bFolder, sprintf('%s-B_sync.mp4', dyadName));

        % ----- Report what we're about to do ----------------------------------
        fprintf('A: %s\n', videoA);
        fprintf('B: %s\n', videoB);
        fprintf('-> Out A: %s\n', outA);
        fprintf('-> Out B: %s\n', outB);

        % ----- Call the provided synchronisation function ---------------------
        % Uses simple defaults; adjust opts above if needed.
        result = sync_videos_by_audio( ...
            videoA, videoB, outA, outB, ...
            'TargetFs',     opts.TargetFs, ...
            'PadWithBlack', opts.PadWithBlack, ...
            'MaxSearchLag', opts.MaxSearchLag, ...
            'Verbose',      opts.Verbose);

        % ----- Summarise success for this dyad --------------------------------
        fprintf('[OK] %s | Estimated lag = %+0.3f s | Strategy: %s\n\n', ...
            dyadName, result.lag_seconds, result.strategy);

    catch ME
        % ----- Handle any error: store it and either stop or continue ---------
        fprintf('[ERROR] %s: %s\n\n', dyadName, ME.message);
        errors(end+1).dyad = dyadName; %#ok<SAGROW>
        errors(end).message = ME.message;

        if stopOnError
            rethrow(ME);
        else
            % Continue to next dyad
            continue;
        end
    end
end

% ------------------ Final report ------------------
if isempty(errors)
    fprintf('== All dyads processed successfully. ==\n');
else
    fprintf('== Completed with %d error(s): ==\n', numel(errors));
    for i = 1:numel(errors)
        fprintf('  %s -> %s\n', errors(i).dyad, errors(i).message);
    end
end

%% --------------- Helper: find first file by pattern ------------------------
function fileName = find_first_file(folder, pattern)
% Returns the first file name that matches "pattern" inside "folder".
% If none found, returns ''.
    d = dir(fullfile(folder, pattern));
    if isempty(d)
        fileName = '';
    else
        % Pick the first regular file (skip directories just in case)
        d = d(~[d.isdir]);
        if isempty(d)
            fileName = '';
        else
            fileName = d(1).name;
        end
    end
end
