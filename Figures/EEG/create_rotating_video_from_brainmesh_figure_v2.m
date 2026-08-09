function create_rotating_video_from_brainmesh_figure_v2(figHandle, outputVideoFile, varargin)
% CREATE_ROTATING_VIDEO_FROM_BRAINMESH_FIGURE_V2
% More robust version that finds 3-D axes in a figure and writes a rotating MP4.
%
% Example:
%   ax = findall(gcf,'Type','axes');
%   ax
% create_rotating_video_from_brainmesh_figure_v2( ...
%     gcf, ...
%     'E:\EEG_data_HyperYESNO\Group_GCMI\Step10b_B2B_rotation_horizontal.mp4', ...
%     'AxesHandles', ax, ...
%     'Duration', 12, ...
%     'FrameRate', 24, ...
%     'RotationMode', 'vertical', ...
%     'ElevationAmplitude', 35);

if nargin < 1 || isempty(figHandle)
    figHandle = gcf;
end
if nargin < 2 || isempty(outputVideoFile)
    error('Provide an output file path, e.g. ''E:\\EEG_data_HyperYESNO\\brain_rotation.mp4''.');
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
addParameter(p, 'RotationMode', 'horizontal', @(x)any(strcmpi(string(x), ["horizontal","vertical","both"])));
addParameter(p, 'ElevationAmplitude', 30, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'AzimuthSweep', 360, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'UsePingPong', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'AxesHandles', [], @(x)isempty(x) || all(ishandle(x)));
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));
parse(p, figHandle, outputVideoFile, varargin{:});
o = p.Results;

outputVideoFile = char(string(outputVideoFile));
rotationMode = lower(char(string(o.RotationMode)));

if isempty(o.AxesHandles)
    axesHandles = local_find_candidate_axes(figHandle);
else
    axesHandles = o.AxesHandles(:);
end

if isempty(axesHandles)
    error(['No candidate 3-D plotting axes were found. ', ...
           'Try passing them explicitly with ''AxesHandles'', e.g. ax = findall(gcf,''Type'',''axes'').']);
end

origViews = nan(numel(axesHandles),2);
for k = 1:numel(axesHandles)
    try
        origViews(k,:) = get(axesHandles(k), 'View');
    catch
        origViews(k,:) = [0 0];
    end
end

nFrames = max(2, round(o.Duration * o.FrameRate));
t = linspace(0,1,nFrames);
if o.UsePingPong
    phase = sin(2*pi*t);
    phase01 = 0.5 - 0.5*cos(2*pi*t);
else
    phase = sin(2*pi*t);
    phase01 = t;
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

[outDir,~,~] = fileparts(outputVideoFile);
if ~isempty(outDir) && ~exist(outDir, 'dir')
    mkdir(outDir);
end
vw = VideoWriter(outputVideoFile, 'MPEG-4');
vw.FrameRate = o.FrameRate;
open(vw);

drawnow;
if o.Verbose
    fprintf('Creating rotating video: %s\n', outputVideoFile);
    fprintf('  Axes used: %d\n', numel(axesHandles));
end

for iFrame = 1:nFrames
    for k = 1:numel(axesHandles)
        set(axesHandles(k), 'View', [origViews(k,1)+azOffset(iFrame), origViews(k,2)+elOffset(iFrame)]);
    end
    drawnow;
    frame = getframe(figHandle);
    writeVideo(vw, frame);
end
close(vw);

for k = 1:numel(axesHandles)
    set(axesHandles(k), 'View', origViews(k,:));
end
drawnow;

if o.Verbose
    fprintf('Finished video: %s\n', outputVideoFile);
end
end


function axesHandles = local_find_candidate_axes(figHandle)
% Return all visible axes that are likely to be actual plotting axes.
allAxes = findall(figHandle, 'Type', 'axes');
keep = false(size(allAxes));

for k = 1:numel(allAxes)
    ax = allAxes(k);
    try
        tag = string(get(ax,'Tag'));
    catch
        tag = "";
    end

    % Exclude legends / colorbars if they appear as axes-like objects.
    if strcmpi(get(ax,'Visible'),'off')
        continue
    end
    if contains(lower(tag), 'legend') || contains(lower(tag), 'colorbar')
        continue
    end

    ch = allchild(ax);
    if isempty(ch)
        continue
    end

    % Keep axes that contain 3-D relevant graphics.
    childTypes = strings(numel(ch),1);
    for j = 1:numel(ch)
        childTypes(j) = string(get(ch(j),'Type'));
    end

    if any(ismember(lower(childTypes), ["patch","surface","scatter","line"]))
        keep(k) = true;
        continue
    end

    % Fallback: if view property exists and not default empty.
    try
        v = get(ax,'View'); %#ok<NASGU>
        keep(k) = true;
    catch
    end
end

axesHandles = allAxes(keep);

% Preserve order by position (left to right, top to bottom) for multipanel figs.
if numel(axesHandles) > 1
    pos = cell2mat(get(axesHandles, 'Position'));
    [~, ord] = sortrows([ -pos(:,2), pos(:,1) ]); % top-to-bottom, left-to-right
    axesHandles = axesHandles(ord);
end
end
