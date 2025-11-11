function rerun_failed_head_motion_unified()
% Re-run head-motion extraction ONLY for selected (previously failed) videos.
% Requires:
%   - run_head_motion_unified.m on the MATLAB path
%   - head_motion_unified.py available (set scriptPath below)
%   - pyenv pointing to your venv with mediapipe/opencv/numpy/scipy
%
% Targets (A/B) re-run list is defined below.

%% ---------------- USER SETTINGS ----------------
baseFolder   = 'D:\HyperYESNO_videosCUT';   % root with DyadXX subfolders
scriptPath   = fullfile(pwd,'head_motion_unified.py'); % adjust if stored elsewhere

% Only these targets will be re-run:
targets = { ...
    'Dyad17','A'; ...
    'Dyad17','B'; ...
    'Dyad16','A'; ...
    'Dyad16','B'; ...
    'Dyad15','A'; ...
    'Dyad15','B'; ...
    'Dyad14','A'; ...
    'Dyad14','B'; ...
    'Dyad13','A'; ...
    'Dyad13','B';  ...
    'Dyad12','A'; ...
    'Dyad12','B';  ...
    'Dyad11','A'; ...
    'Dyad11','B'; ...
    'Dyad10','A'; ...
    'Dyad10','B'; ...
};

% Processing options (match your batch defaults if desired)
makePreview   = true;     % write preview MP4
drawStep      = 1;        % draw every Nth frame in preview
beta          = 0.5;      % fusion weight (bbox vs pose)
smoothWin     = 5;        % frames
weightsXYZ    = [1.0 1.0 0.8];  % bbox composite weights (x,y,depth)
angWeights    = [1.0 1.0 1.0];  % yaw,pitch,roll weights
transWeight   = 1.0;      % translation weight in pose composite
depthMode     = 'log';    % 'log' or 'inv'

overwriteExisting = true; % re-run even if CSV already exists
useParfor         = true; % parallel if toolbox available
%% -----------------------------------------------

% Sanity check
if ~isfile(scriptPath)
    error('Cannot find head_motion_unified.py at: %s', scriptPath);
end

% Build task list from the specific targets
tasks = struct('dyad',{},'side',{},'video',{},'csv',{},'preview',{});
for i = 1:size(targets,1)
    dy   = string(targets{i,1});
    side = upper(string(targets{i,2}));
    if side ~= "A" && side ~= "B"
        warning('Skipping invalid side for %s: "%s"', dy, side); %#ok<SPWRN>
        continue;
    end
    cutFolder = sprintf('%s-%s_cut', dy, side);
    vidName   = sprintf('%s-%s_sync.mp4', dy, side);
    outCSV    = sprintf('%s-%s_motion.csv', dy, side);
    outPrev   = sprintf('%s-%s_motion_preview.mp4', dy, side);

    folder = fullfile(baseFolder, dy, cutFolder);
    video  = fullfile(folder, vidName);
    csvOut = fullfile(folder, outCSV);
    prev   = fullfile(folder, outPrev);

    if ~isfile(video)
        fprintf('[MISS] %s-%s video not found: %s\n', dy, side, video);
        continue;
    end

    tasks(end+1) = struct( ... %#ok<AGROW>
        'dyad',    dy, ...
        'side',    side, ...
        'video',   video, ...
        'csv',     csvOut, ...
        'preview', ternary(makePreview, prev, "") );
end

if isempty(tasks)
    fprintf('No valid tasks to run.\n');
    return;
end

fprintf('== Rerun head-motion: %d task(s) ==\n', numel(tasks));

% Pack shared params
params = struct( ...
    'scriptPath',    scriptPath, ...
    'smoothWin',     smoothWin, ...
    'weightsXYZ',    weightsXYZ, ...
    'angWeights',    angWeights, ...
    'transWeight',   transWeight, ...
    'beta',          beta, ...
    'depthMode',     depthMode, ...
    'drawStep',      drawStep, ...
    'overwrite',     overwriteExisting);

% Run (parallel or serial)
if useParfor && canUseParallel()
    parfor i = 1:numel(tasks)
        run_one_task(tasks(i), params);
    end
else
    for i = 1:numel(tasks)
        run_one_task(tasks(i), params);
    end
end

fprintf('== Rerun complete ==\n');
end

% -------------------- SUBFUNCTIONS (not nested) --------------------
function run_one_task(t, p)
try
    % Ensure output folder exists
    outFolder = fileparts(t.csv);
    if ~isfolder(outFolder), mkdir(outFolder); end

    if ~p.overwrite && isfile(t.csv)
        fprintf('[SKIP] %s-%s -> %s (exists)\n', t.dyad, t.side, t.csv);
        return;
    end

    t0 = tic;
    run_head_motion_unified( ...
        string(t.video), string(t.csv), string(t.preview), ...
        'smooth',   p.smoothWin, ...
        'wx',       p.weightsXYZ(1), ...
        'wy',       p.weightsXYZ(2), ...
        'wz',       p.weightsXYZ(3), ...
        'awyaw',    p.angWeights(1), ...
        'awpitch',  p.angWeights(2), ...
        'awroll',   p.angWeights(3), ...
        'alpha',    p.transWeight, ...
        'beta',     p.beta, ...
        'depthmode',p.depthMode, ...
        'drawstep', p.drawStep, ...
        'ScriptPath', p.scriptPath);

    fprintf('[OK]  %-7s-%s  %s  (%.1fs)\n', t.dyad, t.side, t.csv, toc(t0));

catch ME
    fprintf('[ERR] %-7s-%s  %s\n       %s\n', t.dyad, t.side, t.video, ME.message);
end
end

function tf = canUseParallel()
tf = license('test','Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
