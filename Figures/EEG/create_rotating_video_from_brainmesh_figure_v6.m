function create_rotating_video_from_brainmesh_figure_v6(figHandle, outputVideoFile, varargin)
% CREATE_ROTATING_VIDEO_FROM_BRAINMESH_FIGURE_V6
% -------------------------------------------------------------------------
% Create a clean MP4 rotation video specifically for the Step10b dual-brain
% figure. This version:
%   1) rotates only the two main brain-panel axes,
%   2) ignores legends/colorbars/annotation objects automatically,
%   3) builds a clean temporary figure containing only the two brain panels,
%   4) exports a cleaner rotating video.
%
% Example:
%   create_rotating_video_from_brainmesh_figure_v6( ...
%       gcf, ...
%       'E:\EEG_data_HyperYESNO\Group_GCMI\Step10b_clean_rotation.mp4', ...
%       'Duration', 10, ...
%       'FrameRate', 24, ...
%       'RotationMode', 'horizontal', ...
%       'ElevationAmplitude', 30);
% 
% the one used for the paper:
% create_rotating_video_from_brainmesh_figure_v6( ...
%     gcf, ...
%     'E:\EEG_data_HyperYESNO\Group_GCMI\Step10b_clean_rotation.mp4', ...
%     'Duration', 12, ...
%     'FrameRate', 24, ...
%     'RotationMode', 'vertical', ...
%     'AzimuthSweep', 360, ...
%     'UsePingPong', false);
%
% Name-value options:
%   'Duration'              : seconds (default 10)
%   'FrameRate'             : frames/s (default 24)
%   'RotationMode'          : 'horizontal' | 'vertical' | 'both'
%   'ElevationAmplitude'    : degrees for elevation modulation (default 30)
%   'AzimuthSweep'          : degrees for azimuth sweep (default 180)
%   'UsePingPong'           : true/false (default true)
%   'FigurePosition'        : [left bottom width height] for temp fig
%   'BackgroundColor'       : figure background (default 'w')
%   'Visible'               : 'on' or 'off' for temp figure (default 'on')
%   'Verbose'               : true/false (default true)
%
% Notes:
% - 'horizontal' changes elevation while preserving each panel's azimuth.
% - 'vertical' changes azimuth while preserving each panel's elevation.
% - 'both' combines both.
% - The function attempts to identify the two brain panels by selecting the
%   two visible axes with the richest 3-D graphics content.
%
% Alejandro Perez / ChatGPT support

if nargin < 1 || isempty(figHandle)
    figHandle = gcf;
end
if nargin < 2 || isempty(outputVideoFile)
    error('Provide an output video path, e.g. ''E:\\EEG_data_HyperYESNO\\rotation.mp4''.');
end
if ~ishandle(figHandle) || ~strcmp(get(figHandle,'Type'),'figure')
    error('figHandle must be a valid figure handle.');
end

p = inputParser;
p.FunctionName = mfilename;
addRequired(p, 'figHandle');
addRequired(p, 'outputVideoFile', @(x)ischar(x) || isstring(x));
addParameter(p, 'Duration', 10, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'FrameRate', 24, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'RotationMode', 'vertical', @(x)any(strcmpi(string(x), ["horizontal","vertical","both"])));
addParameter(p, 'ElevationAmplitude', 30, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'AzimuthSweep', 180, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'UsePingPong', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'FigurePosition', [100 100 1600 700], @(x)isnumeric(x) && numel(x)==4);
addParameter(p, 'BackgroundColor', 'w');
addParameter(p, 'Visible', 'on', @(x)any(strcmpi(string(x), ["on","off"])));
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));
parse(p, figHandle, outputVideoFile, varargin{:});
o = p.Results;

outputVideoFile = char(string(outputVideoFile));
rotationMode = lower(char(string(o.RotationMode)));

% -------------------------------------------------------------------------
% 1) Detect the two main brain axes in the source figure.
% -------------------------------------------------------------------------
sourceAxes = local_find_main_brain_axes(figHandle);
if numel(sourceAxes) < 2
    allAxes = findall(figHandle,'Type','axes');
    error(['Could not identify two Step10b brain-panel axes. The figure contains %d axes, ', ...
           'but fewer than two contain patch/surface/line/scatter graphics. Make sure gcf ', ...
           'is the Step10b brain figure rather than another MATLAB figure.'], numel(allAxes));
end
sourceAxes = sourceAxes(1:2);

if o.Verbose
    fprintf('Detected %d candidate brain axes. Using the top 2.\n', numel(sourceAxes));
end

% -------------------------------------------------------------------------
% 2) Create a clean temporary figure with only the two brain panels.
% -------------------------------------------------------------------------
cleanFig = figure('Color', o.BackgroundColor, ...
                  'Visible', char(string(o.Visible)), ...
                  'Units', 'pixels', ...
                  'Position', o.FigurePosition, ...
                  'Resize', 'off', ...
                  'Name', 'Step10b rotating video (clean)', ...
                  'NumberTitle', 'off');

% Use tiledlayout for clean spacing.
tl = tiledlayout(cleanFig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
cleanAxes = gobjects(2,1);
origViews = nan(2,2);

for iAx = 1:2
    srcAx = sourceAxes(iAx);
    dstAx = nexttile(tl, iAx);
    cleanAxes(iAx) = dstAx;

    % Copy only the 3-D graphical objects. Deliberately exclude text
    % objects, which removes the KNOWER/GUESSER labels and any ROI labels
    % from the video while retaining brain meshes, nodes, and links.
    srcChildren = allchild(srcAx);
    keepChild = false(size(srcChildren));
    for jj = 1:numel(srcChildren)
        try
            typ = lower(string(get(srcChildren(jj),'Type')));
            keepChild(jj) = any(typ == ["patch","surface","scatter","line"]);
        catch
            keepChild(jj) = false;
        end
    end
    srcChildren = srcChildren(keepChild);
    if ~isempty(srcChildren)
        copied = copyobj(flipud(srcChildren), dstAx); %#ok<NASGU>
    end

    % Copy core axis properties.
    local_copy_axes_properties(srcAx, dstAx);

    % Preserve title text if present.
    try
        tStr = get(get(srcAx,'Title'),'String');
        if ~isempty(tStr)
            title(dstAx, tStr, 'Interpreter', 'none');
        end
    catch
    end

    origViews(iAx,:) = get(dstAx, 'View');
end

drawnow;
pause(0.15);
drawnow;

% -------------------------------------------------------------------------
% 3) Prepare video rotation trajectories.
% -------------------------------------------------------------------------
nFrames = max(2, round(o.Duration * o.FrameRate));
t = linspace(0,1,nFrames);

if o.UsePingPong
    phase = sin(2*pi*t);          % smooth elevation modulation
    phase01 = 0.5 - 0.5*cos(2*pi*t); % 0 -> 1 -> 0
else
    phase = sin(2*pi*t);
    phase01 = t;                  % 0 -> 1
end

switch rotationMode
    case 'horizontal'
        azOffset = zeros(1,nFrames);
        elOffset = o.ElevationAmplitude * phase;
    case 'vertical'
        azOffset = o.AzimuthSweep * phase01;
        elOffset = zeros(1,nFrames);
    case 'both'
        azOffset = o.AzimuthSweep * phase01;
        elOffset = o.ElevationAmplitude * phase;
end

% -------------------------------------------------------------------------
% 4) Write the video.
% -------------------------------------------------------------------------
[outDir,~,~] = fileparts(outputVideoFile);
if ~isempty(outDir) && ~exist(outDir, 'dir')
    mkdir(outDir);
end

vw = VideoWriter(outputVideoFile, 'MPEG-4');
vw.FrameRate = o.FrameRate;

% Capture a reference frame after the layout has fully settled. Every
% subsequent frame is forced to exactly these pixel dimensions. This avoids
% VideoWriter failures on HiDPI/multi-monitor systems where getframe can
% occasionally return slightly different image sizes during animation.
for iAx = 1:2
    set(cleanAxes(iAx), 'View', origViews(iAx,:));
end
drawnow; pause(0.10); drawnow;
referenceFrame = getframe(cleanFig);
referenceRGB = referenceFrame.cdata;
targetH = size(referenceRGB,1);
targetW = size(referenceRGB,2);
% MPEG-4 is happiest with even dimensions.
targetH = targetH - mod(targetH,2);
targetW = targetW - mod(targetW,2);
referenceRGB = referenceRGB(1:targetH,1:targetW,:);

open(vw);

if o.Verbose
    fprintf('Creating clean rotating video: %s\n', outputVideoFile);
    fprintf('  Frames: %d\n', nFrames);
    fprintf('  Rotation mode: %s\n', rotationMode);
    fprintf('  Fixed video frame: %d x %d pixels\n', targetW, targetH);
end

for iFrame = 1:nFrames
    for iAx = 1:2
        set(cleanAxes(iAx), 'View', [origViews(iAx,1)+azOffset(iFrame), origViews(iAx,2)+elOffset(iFrame)]);
    end
    drawnow;
    frameNow = getframe(cleanFig);
    rgb = local_force_frame_size(frameNow.cdata, targetH, targetW);
    writeVideo(vw, rgb);

    if o.Verbose && (mod(iFrame, max(1, round(nFrames/10))) == 0 || iFrame == nFrames)
        fprintf('  Frame %d / %d\n', iFrame, nFrames);
    end
end

close(vw);

% Restore original views in temporary fig in case user keeps it open.
for iAx = 1:2
    set(cleanAxes(iAx), 'View', origViews(iAx,:));
end
drawnow;

if o.Verbose
    fprintf('Finished clean rotating video: %s\n', outputVideoFile);
end

end


%% ========================================================================
function axOut = local_find_main_brain_axes(figHandle)
% Return axes sorted by how likely they are to be the two main Step10b
% brain panels. IMPORTANT: axes with Visible="off" are allowed because the
% Step10b plotting function deliberately hides axis decorations while the
% 3-D patch/line objects remain visible.

allAxes = findall(figHandle, 'Type', 'axes');
if isempty(allAxes)
    axOut = gobjects(0);
    return;
end

scores = nan(numel(allAxes),1);
positions = nan(numel(allAxes),4);
keep = false(numel(allAxes),1);

for k = 1:numel(allAxes)
    ax = allAxes(k);

    % Exclude legends / colorbars.
    try
        tag = lower(string(get(ax,'Tag')));
    catch
        tag = "";
    end
    if contains(tag, 'legend') || contains(tag, 'colorbar')
        continue;
    end

    ch = allchild(ax);
    if isempty(ch)
        continue;
    end

    childTypes = strings(numel(ch),1);
    for j = 1:numel(ch)
        try
            childTypes(j) = string(get(ch(j),'Type'));
        catch
            childTypes(j) = "";
        end
    end
    childTypes = lower(childTypes);

    nPatch   = sum(childTypes == "patch");
    nSurface = sum(childTypes == "surface");
    nScatter = sum(childTypes == "scatter");
    nLine    = sum(childTypes == "line");
    nText    = sum(childTypes == "text");

    % The Step10b brain panels contain many cortical patches plus 3-D lines
    % and/or scatter nodes. Ignore axes that contain only text or decoration.
    nGraphic3D = nPatch + nSurface + nScatter + nLine;
    if nGraphic3D == 0
        continue;
    end
    score = 20*nPatch + 20*nSurface + 4*nScatter + 3*nLine + 0.10*nText;

    % Slight preference for larger axes areas.
    try
        pos = get(ax,'Position');
        positions(k,:) = pos;
        score = score + 10*(pos(3)*pos(4));
    catch
        positions(k,:) = [0 0 0 0];
    end

    % Slight preference for axes with 3-D style view different from flat defaults.
    try
        v = get(ax,'View');
        if isnumeric(v) && numel(v)==2
            score = score + 5;
        end
    catch
    end

    scores(k) = score;
    keep(k) = true;
end

cand = allAxes(keep);
if isempty(cand)
    axOut = gobjects(0);
    return;
end

scores = scores(keep);
positions = positions(keep,:);

% Sort primarily by descending score, then by on-screen order (top-to-bottom, left-to-right).
[~, idxScore] = sort(scores, 'descend');
cand = cand(idxScore);
positions = positions(idxScore,:);

% Keep top candidates, then sort them spatially for panel order.
nKeep = min(2, numel(cand));
cand = cand(1:nKeep);
positions = positions(1:nKeep,:);

[~, idxPos] = sortrows([ -positions(:,2), positions(:,1) ]); % top-to-bottom, then left-to-right
axOut = cand(idxPos);
end


%% ========================================================================
function local_copy_axes_properties(srcAx, dstAx)
% Copy the most relevant visual properties from one axes to another.

props = { ...
    'XLim','YLim','ZLim', ...
    'CLim', ...
    'DataAspectRatio','PlotBoxAspectRatio', ...
    'Projection','CameraViewAngle', ...
    'XColor','YColor','ZColor', ...
    'Color', ...
    'Visible', ...
    'Box', ...
    'XGrid','YGrid','ZGrid', ...
    'XTick','YTick','ZTick', ...
    'XTickLabel','YTickLabel','ZTickLabel', ...
    'FontSize', ...
    'LineWidth' ...
    };

for iP = 1:numel(props)
    try
        set(dstAx, props{iP}, get(srcAx, props{iP}));
    catch
    end
end

% Copy axis labels if present.
try
    xlabel(dstAx, get(get(srcAx,'XLabel'),'String'), 'Interpreter', 'none');
catch
end
try
    ylabel(dstAx, get(get(srcAx,'YLabel'),'String'), 'Interpreter', 'none');
catch
end
try
    zlabel(dstAx, get(get(srcAx,'ZLabel'),'String'), 'Interpreter', 'none');
catch
end

% Preserve the exact starting view.
try
    set(dstAx, 'View', get(srcAx,'View'));
catch
end
end


%% ========================================================================
function rgbOut = local_force_frame_size(rgbIn, targetH, targetW)
% Force every frame to identical dimensions for VideoWriter.
% If getframe returns a different size, resize the RGB array. imresize is
% used when available; otherwise a toolbox-free interpolation fallback is
% used.

[h,w,~] = size(rgbIn);
if h == targetH && w == targetW
    rgbOut = rgbIn;
    return;
end

if exist('imresize','file') == 2
    rgbOut = imresize(rgbIn, [targetH targetW]);
    return;
end

% Toolbox-free bilinear interpolation fallback.
[xOld,yOld] = meshgrid(1:w,1:h);
[xNew,yNew] = meshgrid(linspace(1,w,targetW), linspace(1,h,targetH));
rgbOut = zeros(targetH,targetW,3,'uint8');
for cc = 1:3
    plane = interp2(xOld,yOld,double(rgbIn(:,:,cc)),xNew,yNew,'linear');
    plane = min(max(plane,0),255);
    rgbOut(:,:,cc) = uint8(round(plane));
end
end
