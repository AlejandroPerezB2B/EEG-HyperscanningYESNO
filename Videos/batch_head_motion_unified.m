function batch_head_motion_unified()
% Batch runner for head_motion_unified.py across DyadXX folders.
% Requires:
%   - pyenv set to the venv that has mediapipe/opencv/numpy/scipy
%   - run_head_motion_unified.m on the MATLAB path
%
% Looks for:
%   D:\HyperYESNO_videosCUT\DyadXX\DyadXX-A_cut\DyadXX-A_sync.mp4
%   D:\HyperYESNO_videosCUT\DyadXX\DyadXX-B_cut\DyadXX-B_sync.mp4
%
% Produces (per video):
%   DyadXX-*_cut\DyadXX-*_motion.csv
%   DyadXX-*_cut\DyadXX-*_motion_preview.mp4   (if enabled)

%% ---------------- USER SETTINGS ----------------
baseFolder   = 'D:\HyperYESNO_videosCUT';  % root with Dyad01..Dyad35
nDyads       = 35;

scriptPath   = fullfile(pwd,'head_motion_unified.py'); % <- adjust if stored elsewhere

makePreview  = true;    % set false to skip preview MP4s
drawStep     = 1;       % draw every Nth frame in preview (1 = every frame)
beta         = 0.5;     % fusion weight (bbox vs pose)
smoothWin    = 5;       % frames
weightsXYZ   = [1.0 1.0 0.8]; % bbox composite weights (x,y,depth)
angWeights   = [1.0 1.0 1.0]; % yaw,pitch,roll weights
transWeight  = 1.0;     % translation weight in pose composite
depthMode    = 'log';   % 'log' or 'inv'

skipIfExists = true;    % skip if CSV already exists
useParfor    = true;    % requires Parallel Computing Toolbox
%% -----------------------------------------------

% Sanity check for the Python script
if ~isfile(scriptPath)
    error('Cannot find head_motion_unified.py at: %s', scriptPath);
end

% Build a task list (A and B per dyad, if present)
tasks = struct('video',{},'csv',{},'preview',{},'dyad',{});
for k = 1:nDyads
    dy = sprintf('Dyad%02d', k);
    aFolder = fullfile(baseFolder, dy, [dy '-A_cut']);
    bFolder = fullfile(baseFolder, dy, [dy '-B_cut']);

    vidA = fullfile(aFolder, sprintf('%s-A_sync.mp4', dy));
    vidB = fullfile(bFolder, sprintf('%s-B_sync.mp4', dy));

    if isfile(vidA)
        tasks(end+1) = struct( ... %#ok<AGROW>
            'video',   vidA, ...
            'csv',     fullfile(aFolder, sprintf('%s-A_motion.csv', dy)), ...
            'preview', ternary(makePreview, fullfile(aFolder, sprintf('%s-A_motion_preview.mp4', dy)), ""), ...
            'dyad',    dy);
    else
        fprintf('[WARN] Missing A video: %s\n', vidA);
    end

    if isfile(vidB)
        tasks(end+1) = struct( ... %#ok<AGROW>
            'video',   vidB, ...
            'csv',     fullfile(bFolder, sprintf('%s-B_motion.csv', dy)), ...
            'preview', ternary(makePreview, fullfile(bFolder, sprintf('%s-B_motion_preview.mp4', dy)), ""), ...
            'dyad',    dy);
    else
        fprintf('[WARN] Missing B video: %s\n', vidB);
    end
end

fprintf('== Head-motion batch: %d task(s) ==\n', numel(tasks));

% Pack the shared parameters for workers
params = struct( ...
    'scriptPath', scriptPath, ...
    'smoothWin',  smoothWin, ...
    'weightsXYZ', weightsXYZ, ...
    'angWeights', angWeights, ...
    'transWeight',transWeight, ...
    'beta',       beta, ...
    'depthMode',  depthMode, ...
    'drawStep',   drawStep, ...
    'skipIfExists', skipIfExists);

% Run tasks (parallel or serial)
if useParfor && canUseParallel()
    parfor i = 1:numel(tasks)
        run_one_task(tasks(i), params);
    end
else
    for i = 1:numel(tasks)
        run_one_task(tasks(i), params);
    end
end

fprintf('== Done ==\n');
end

% -------------------- SUBFUNCTIONS (not nested) --------------------

function run_one_task(t, params)
% One video task runner (safe for parfor)
try
    if params.skipIfExists && isfile(t.csv)
        fprintf('[SKIP] %s -> %s (exists)\n', t.video, t.csv);
        return;
    end

    % Ensure output folder exists
    outFolder = fileparts(t.csv);
    if ~isfolder(outFolder), mkdir(outFolder); end

    % Call the MATLAB→Python shim (no argparse issues)
    t0 = tic;
    run_head_motion_unified( ...
        string(t.video), string(t.csv), string(t.preview), ...
        'smooth',   params.smoothWin, ...
        'wx',       params.weightsXYZ(1), ...
        'wy',       params.weightsXYZ(2), ...
        'wz',       params.weightsXYZ(3), ...
        'awyaw',    params.angWeights(1), ...
        'awpitch',  params.angWeights(2), ...
        'awroll',   params.angWeights(3), ...
        'alpha',    params.transWeight, ...
        'beta',     params.beta, ...
        'depthmode',params.depthMode, ...
        'drawstep', params.drawStep, ...
        'ScriptPath', params.scriptPath);

    fprintf('[OK]  %-7s  %s  (%.1fs)\n', t.dyad, t.csv, toc(t0));

catch ME
    fprintf('[ERR] %-7s  %s\n       %s\n', t.dyad, t.video, ME.message);
end
end

function tf = canUseParallel()
tf = license('test','Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
