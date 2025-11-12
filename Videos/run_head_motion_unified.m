function run_head_motion_unified(inVideo, outCSV, outPreview, varargin)
% Call Python function run(...) inside head_motion_unified.py directly.
% Requires: pyenv points to the correct Python; packages installed in that env.

% ---- Parse optional params (same names as your CLI flags) ----
p = inputParser;
p.addParameter('smooth',   5);
p.addParameter('wx',       1.0);
p.addParameter('wy',       1.0);
p.addParameter('wz',       0.8);
p.addParameter('awyaw',    1.0);
p.addParameter('awpitch',  1.0);
p.addParameter('awroll',   1.0);
p.addParameter('alpha',    1.0);      % trans_weight
p.addParameter('beta',     0.5);      % fusion weight
p.addParameter('depthmode','log');    % 'log' or 'inv'
p.addParameter('drawstep', 1);
p.addParameter('ScriptPath', fullfile(pwd,'head_motion_unified.py')); % path to the .py file
p.parse(varargin{:});
o = p.Results;

% ---- Import the module from its file path ----
scriptPath = string(o.ScriptPath);
scriptDir  = string(fileparts(scriptPath));
scriptName = "head_motion_unified";   % module name alias

% Ensure the folder is on sys.path
pyrun(sprintf("import sys; p=r'%s';\nif p not in sys.path: sys.path.insert(0,p)", scriptDir));

% Import (or reload) the module
pyrun(sprintf("import importlib, %s as hm; importlib.reload(hm)", scriptName));

% Build Python call
pycall = sprintf([ ...
    "import %s as hm\n" + ...
    "hm.run(video_path=r'%s', out_csv=r'%s', out_preview=r'%s', " + ...
    "smooth_win=%d, weights_xyz=(%g,%g,%g), ang_weights=(%g,%g,%g), " + ...
    "trans_weight=%g, beta=%g, depth_mode='%s', draw_step=%d)\n"], ...
    scriptName, inVideo, outCSV, outPreview, ...
    o.smooth, o.wx, o.wy, o.wz, o.awyaw, o.awpitch, o.awroll, ...
    o.alpha, o.beta, o.depthmode, o.drawstep);

% Execute
pyrun(pycall);
end
