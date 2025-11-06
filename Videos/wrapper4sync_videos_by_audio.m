%% Wrapper to synchronise all dyads by audio using sync_videos_by_audio.m
% This script:
%  1) Loops over Dyad01 ... Dyad35 inside the base folder.
%  2) For each dyad, finds the A and B .mp4 files by prefix (DyadXX-A_* / DyadXX-B_*).
%  3) Calls sync_videos_by_audio(videoA, videoB, outA, outB).
%  4) Saves outputs in each video's own folder as DyadXX-A_sync.mp4 / DyadXX-B_sync.mp4.
%
% Wrapper to synchronise all dyads using sync_videos_by_audio.m
% Requirements:
%  - The function sync_videos_by_audio.m must be on the MATLAB path.
%  - FFmpeg must be installed. If not in PATH, set opts.FFmpegPath below.

clear; clc;

%% ------------------ USER SETTINGS ------------------
% Base folder that contains Dyad01 ... Dyad35 directories
baseFolder = 'D:\HyperYESNO_videosCUT';

% How many dyads to process (Dyad01 .. Dyad35)
nDyads = 35;

% If true, stop the script immediately when a dyad fails.
% If false, continue to the next dyad and report errors at the end.
stopOnError = false;

% Skip a dyad if the target outputs already exist (prevents rework)
skipIfExists = true;

% -------- Options passed to sync_videos_by_audio --------
opts.TargetFs     = 44100;                      % use native 44.1 kHz for best timing
opts.PadWithBlack = false;                      % false = trim earlier, true = pad later
opts.MaxSearchLag = 5;                          % seconds
opts.Verbose      = true;                       % console progress
opts.UseParallel  = true;                       % write A/B videos concurrently
opts.FFmpegPath   = 'C:\ffmpeg\bin\ffmpeg.exe'; % set to your ffmpeg.exe, or 'ffmpeg' if in PATH
%% ------------------------------------------------------

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
        % If multiple match, we take the first; adjust strategy if needed.
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

        % ----- Skip if outputs already present (optional) ---------------------
        if skipIfExists && isfile(outA) && isfile(outB)
            fprintf('[SKIP] %s outputs already exist.\n\n', dyadName);
            continue;
        end

        % ----- Report what we're about to do ----------------------------------
        fprintf('A: %s\n', videoA);
        fprintf('B: %s\n', videoB);
        fprintf('-> Out A: %s\n', outA);
        fprintf('-> Out B: %s\n', outB);

        % ----- Call the synchronisation function (updated API) ----------------
        t0 = tic;
        result = sync_videos_by_audio( ...
            videoA, videoB, outA, outB, ...
            'TargetFs',     opts.TargetFs, ...
            'PadWithBlack', opts.PadWithBlack, ...
            'MaxSearchLag', opts.MaxSearchLag, ...
            'Verbose',      opts.Verbose, ...
            'UseParallel',  opts.UseParallel, ...
            'FFmpegPath',   opts.FFmpegPath);

        % ----- Summarise success for this dyad --------------------------------
        fprintf('[OK] %s | lag = %+0.3f s | strategy: %s | outDur A=%.3f s, B=%.3f s | %.1f s\n\n', ...
            dyadName, result.lag_seconds, result.strategy, ...
            result.duration_out(1), result.duration_out(2), toc(t0));

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
        % Filter to files (not dirs)
        d = d(~[d.isdir]);
        if isempty(d)
            fileName = '';
        else
            % Choose the most recently modified first (more robust than arbitrary first)
            [~, idx] = max([d.datenum]);
            fileName = d(idx).name;
        end
    end
end
