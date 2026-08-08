function handles = biPer_plot_interbrain_brainmesh_v5(connMatrix, electrodeInput, varargin)
% biPer_plot_interbrain_brainmesh_v5
% -------------------------------------------------------------------------
% Plot inter-brain connectivity as links between two sets of EEG electrodes,
% using a FieldTrip/EEGLAB template BRAIN mesh as an anatomical reference.
%
% This function intentionally replaces the previous dual-head .spl/headplot
% approach. It does NOT interpolate a scalp field. Instead, it draws:
%   1) a left brain mesh,
%   2) a right brain mesh,
%   3) scalp-level electrode markers floating around each brain, and
%   4) inter-brain links defined by connMatrix.
%
% Critical point for hyperscanning matrices:
%   connMatrix(i,i) is NOT ignored. The diagonal is meaningful here because
%   it represents the connection between electrode i in participant A and
%   electrode i in participant B. The diagonal is included by default.
%
% Basic usage:
%   handles = biPer_plot_interbrain_brainmesh_v5(connMatrix, EEG.chanlocs);
%
% Recommended usage with explicit labels:
%   handles = biPer_plot_interbrain_brainmesh_v5(connMatrix, EEG.chanlocs, ...
%       'ChannelLabels', {'Fp1','Fp2','F3','F4', ...}, ...
%       'LabelMode', 'names');
%
% Usage with FieldTrip template electrodes:
%   handles = biPer_plot_interbrain_brainmesh_v5(connMatrix, ...
%       'fieldtrip:standard_1005.elc', ...
%       'ChannelLabels', myLabels);
%
% Inputs:
%   connMatrix     - N x N inter-brain connectivity/statistics matrix.
%                    Rows are electrodes from brain/person A.
%                    Columns are electrodes from brain/person B.
%                    The diagonal is valid and plotted unless PlotDiagonal=false.
%
%   electrodeInput - EEG.chanlocs, EEG structure, FieldTrip elec structure,
%                    electrode-position file, or 'fieldtrip:standard_1005.elc'.
%
% Selected options:
%   'BrainMesh'          [] or mesh/headmodel/file. Empty = use default template.
%   'Surface'            'innermost' extracts the brain surface from BEM model.
%   'CoordinateMode'     'auto' rescales electrodes around the brain mesh.
%                        'native' keeps electrode coordinates as supplied.
%   'ChannelLabels'      labels used to select/order electrodes for both brains.
%   'ChannelLabelsA'     labels used to select/order participant A electrodes.
%   'ChannelLabelsB'     labels used to select/order participant B electrodes.
%   'ThresholdType'      'nonzero', 'abs', or 'range'.
%   'MinAbsValue'        minimum abs(value) when ThresholdType='abs'.
%   'ValueRange'         [min max] when ThresholdType='range'.
%   'PlotDiagonal'       true by default.
%   'MaxLinks'           maximum number of links to draw, by absolute value.
%   'MakeMovie'          false/true, export rotating MP4 when true.
%
% Dependencies:
%   FieldTrip is recommended so that the function can load standard_bem.mat.
%   EEGLAB is useful for reading EEGLAB chanlocs files. Neither toolbox is
%   required if you pass already loaded mesh and electrode structures.
% -------------------------------------------------------------------------

% ----------------------------- Validate matrix ----------------------------
if nargin < 1 || isempty(connMatrix)
    error('A connectivity matrix must be provided.');
end
if ~isnumeric(connMatrix) || ndims(connMatrix) ~= 2
    error('connMatrix must be a numeric 2-D matrix.');
end
if size(connMatrix,1) ~= size(connMatrix,2)
    error(['connMatrix must be square because the diagonal represents ', ...
           'same-electrode inter-brain connections. Received %d x %d.'], ...
           size(connMatrix,1), size(connMatrix,2));
end
nChan = size(connMatrix,1);

% ------------------------------- Parse inputs -----------------------------
p = inputParser;
p.FunctionName = mfilename;

% Mesh and coordinate options.
addParameter(p, 'BrainMesh', [], @(x)true);
addParameter(p, 'HeadModelFile', 'standard_bem.mat', @(x)ischar(x) || isstring(x));
addParameter(p, 'Surface', 'innermost', @(x)ischar(x) || isstring(x) || isnumeric(x));
addParameter(p, 'CoordinateMode', 'auto', @(x)ischar(x) || isstring(x));
addParameter(p, 'ElectrodeOutwardOffset', 8, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'ElectrodeRadiusScale', 1.22, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'BrainSeparation', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'MirrorBrainB', false, @(x)islogical(x) || isnumeric(x));

% Channel selection/order options.
addParameter(p, 'ChannelLabels', {}, @(x)iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'ChannelLabelsA', {}, @(x)iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'ChannelLabelsB', {}, @(x)iscell(x) || isstring(x) || ischar(x));

% Threshold/link options.
addParameter(p, 'ThresholdType', 'nonzero', @(x)ischar(x) || isstring(x));
addParameter(p, 'MinAbsValue', 0, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'ValueRange', [-Inf Inf], @(x)isnumeric(x) && numel(x)==2);
addParameter(p, 'PlotDiagonal', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'MaxLinks', Inf, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'LinkWidthRange', [0.5 5], @(x)isnumeric(x) && numel(x)==2);
addParameter(p, 'LinkAlpha', 0.65, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'PositiveLinkColor', [0.80 0.20 0.10], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'NegativeLinkColor', [0.10 0.35 0.90], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'ZeroLinkColor', [0.45 0.45 0.45], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'UseCurvedLinks', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'LinkArcHeight', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'CurvePoints', 30, @(x)isnumeric(x) && isscalar(x));

% Appearance options.
addParameter(p, 'BrainColorA', [0.78 0.80 0.84], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'BrainColorB', [0.70 0.74 0.80], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'BrainAlpha', 0.22, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'BrainEdgeColor', 'none', @(x)ischar(x) || isstring(x) || isnumeric(x));
addParameter(p, 'ElectrodeColorA', [0.05 0.05 0.05], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'ElectrodeColorB', [0.05 0.05 0.05], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'ElectrodeSize', 70, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'ElectrodeEdgeColor', [1 1 1], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'LabelMode', 'names', @(x)ischar(x) || isstring(x));
addParameter(p, 'LabelFontSize', 9, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'LabelColor', [0 0 0], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'LabelBackground', [1 1 1], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'LabelMargin', 1.5, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'LabelOffset', 5, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'ShowBrain', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'ShowElectrodes', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'View', [0 20], @(x)ischar(x) || isstring(x) || (isnumeric(x) && numel(x)==2));
addParameter(p, 'Title', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'FigureHandle', [], @(x)isempty(x) || ishghandle(x));
addParameter(p, 'AxesHandle', [], @(x)isempty(x) || ishghandle(x));
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));

% Movie options.
addParameter(p, 'MakeMovie', false, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'MovieFile', 'dualbrain_connectivity.mp4', @(x)ischar(x) || isstring(x));
addParameter(p, 'MovieFrameRate', 15, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'MovieDuration', 8, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'MovieElevation', 20, @(x)isnumeric(x) && isscalar(x));

parse(p, varargin{:});
opt = p.Results;

% ------------------------------ Load mesh --------------------------------
% The default is FieldTrip/EEGLAB's standard BEM template; we extract the
% innermost surface as the brain mesh.
[brainMesh, meshInfo] = local_get_brain_mesh(opt);

% ---------------------------- Load electrodes -----------------------------
elec = biPer_load_electrodes_v5(electrodeInput, 'Verbose', opt.Verbose);

% -------------------------- Resolve channel labels ------------------------
% If ChannelLabelsA/B are not supplied, use ChannelLabels for both brains.
labelsBoth = local_to_cellstr(opt.ChannelLabels);
labelsA = local_to_cellstr(opt.ChannelLabelsA);
labelsB = local_to_cellstr(opt.ChannelLabelsB);

if isempty(labelsA)
    labelsA = labelsBoth;
end
if isempty(labelsB)
    labelsB = labelsBoth;
end

[posA0, labelsA] = local_select_electrodes(elec, labelsA, nChan, 'A');
[posB0, labelsB] = local_select_electrodes(elec, labelsB, nChan, 'B');

% -------------------------- Prepare coordinates ---------------------------
% The two electrode clouds are prepared against the same brain mesh. In
% 'auto' mode, electrode positions are normalised to float outside the brain
% mesh. In 'native' mode, coordinates are only recentered and optionally
% pushed outward.
[posA0, posB0, brainLocal] = local_prepare_geometry(posA0, posB0, brainMesh, opt);

% Decide how far apart the two brains should be.
if isempty(opt.BrainSeparation)
    xRange = max(brainLocal(:,1)) - min(brainLocal(:,1));
    opt.BrainSeparation = xRange * 2.4;
end
if isempty(opt.LinkArcHeight)
    opt.LinkArcHeight = opt.BrainSeparation * 0.18;
end

% Construct translated brain and electrode coordinates.
shiftA = [-opt.BrainSeparation/2 0 0];
shiftB = [ opt.BrainSeparation/2 0 0];

brainApos = brainLocal + shiftA;
brainBlocal = brainLocal;
posBlocal = posB0;

% Optional mirror for a facing-brains layout. The same transformation is
% applied to the right brain mesh and its electrodes.
if opt.MirrorBrainB
    brainBlocal(:,1) = -brainBlocal(:,1);
    posBlocal(:,1) = -posBlocal(:,1);
end

brainBpos = brainBlocal + shiftB;
posA = posA0 + shiftA;
posB = posBlocal + shiftB;

% ----------------------------- Create figure ------------------------------
if isempty(opt.AxesHandle)
    if isempty(opt.FigureHandle)
        fig = figure('Color', 'w', 'Name', 'Inter-brain connectivity');
    else
        fig = opt.FigureHandle;
        figure(fig);
    end
    ax = axes('Parent', fig);
else
    ax = opt.AxesHandle;
    fig = ancestor(ax, 'figure');
end

axes(ax); %#ok<LAXES>
cla(ax);
hold(ax, 'on');

% ------------------------------- Plot brains ------------------------------
handles = struct();
handles.figure = fig;
handles.axes = ax;
handles.meshInfo = meshInfo;
handles.brainA = [];
handles.brainB = [];
handles.electrodesA = [];
handles.electrodesB = [];
handles.labelsA = gobjects(0);
handles.labelsB = gobjects(0);
handles.links = gobjects(0);
handles.linkTable = table();
handles.posA = posA;
handles.posB = posB;
handles.labelsA_text = labelsA;
handles.labelsB_text = labelsB;

if opt.ShowBrain
    handles.brainA = patch(ax, 'Vertices', brainApos, 'Faces', brainMesh.tri, ...
        'FaceColor', opt.BrainColorA, 'FaceAlpha', opt.BrainAlpha, ...
        'EdgeColor', opt.BrainEdgeColor, 'FaceLighting', 'gouraud', ...
        'SpecularStrength', 0.15, 'DiffuseStrength', 0.65, ...
        'AmbientStrength', 0.45, 'Tag', 'BrainA');

    handles.brainB = patch(ax, 'Vertices', brainBpos, 'Faces', brainMesh.tri, ...
        'FaceColor', opt.BrainColorB, 'FaceAlpha', opt.BrainAlpha, ...
        'EdgeColor', opt.BrainEdgeColor, 'FaceLighting', 'gouraud', ...
        'SpecularStrength', 0.15, 'DiffuseStrength', 0.65, ...
        'AmbientStrength', 0.45, 'Tag', 'BrainB');
end

% ------------------------------ Plot links --------------------------------
[linkHandles, linkTable] = local_plot_links(ax, connMatrix, posA, posB, labelsA, labelsB, opt);
handles.links = linkHandles;
handles.linkTable = linkTable;

% ---------------------------- Plot electrodes -----------------------------
if opt.ShowElectrodes
    handles.electrodesA = scatter3(ax, posA(:,1), posA(:,2), posA(:,3), ...
        opt.ElectrodeSize, 'MarkerFaceColor', opt.ElectrodeColorA, ...
        'MarkerEdgeColor', opt.ElectrodeEdgeColor, 'LineWidth', 0.75, ...
        'Tag', 'ElectrodesA');

    handles.electrodesB = scatter3(ax, posB(:,1), posB(:,2), posB(:,3), ...
        opt.ElectrodeSize, 'MarkerFaceColor', opt.ElectrodeColorB, ...
        'MarkerEdgeColor', opt.ElectrodeEdgeColor, 'LineWidth', 0.75, ...
        'Tag', 'ElectrodesB');
end

% ------------------------------- Plot labels ------------------------------
labelMode = lower(char(opt.LabelMode));
if ~strcmp(labelMode, 'off') && ~strcmp(labelMode, 'none')
    handles.labelsA = local_plot_labels(ax, posA, labelsA, 'A', opt);
    handles.labelsB = local_plot_labels(ax, posB, labelsB, 'B', opt);
end

% ---------------------------- Lighting/camera -----------------------------
axis(ax, 'equal');
axis(ax, 'off');
grid(ax, 'off');

% Add simple lights. camlight is robust across MATLAB versions.
camlight(ax, 'headlight');
camlight(ax, 'right');
lighting(ax, 'gouraud');
material(ax, 'dull');

% Set a useful initial view.
local_apply_view(ax, opt.View);

if ~isempty(opt.Title)
    title(ax, char(opt.Title), 'FontWeight', 'bold');
end

rotate3d(fig, 'on');
drawnow;

% ------------------------------- Movie export -----------------------------
if opt.MakeMovie
    local_write_movie(fig, ax, opt);
end

if opt.Verbose
    if isempty(handles.linkTable) || ~ismember('IsDiagonal', handles.linkTable.Properties.VariableNames)
        nDiagLinks = 0;
    else
        nDiagLinks = sum(handles.linkTable.IsDiagonal);
    end
    fprintf('%s: plotted %d inter-brain links. Diagonal links included: %d.\n', ...
        mfilename, height(handles.linkTable), nDiagLinks);
end
end

% ========================================================================
% Local helper functions
% ========================================================================

function [brainMesh, meshInfo] = local_get_brain_mesh(opt)
% Resolve the requested brain mesh from default template, file, or struct.
if isempty(opt.BrainMesh)
    [brainMesh, meshInfo] = biPer_load_default_brain_mesh_v5( ...
        'HeadModelFile', opt.HeadModelFile, ...
        'Surface', opt.Surface, ...
        'Verbose', opt.Verbose);
    return;
end

meshInfo = struct();
meshInfo.source = 'User BrainMesh';
meshInfo.sourceFile = '';
meshInfo.surfaceSelection = opt.Surface;
meshInfo.surfaceIndex = [];

if ischar(opt.BrainMesh) || isstring(opt.BrainMesh)
    filename = char(opt.BrainMesh);
    if exist(filename, 'file') ~= 2
        error('BrainMesh file not found: %s', filename);
    end
    S = load(filename, '-mat');
    [brainMesh, idx] = local_extract_mesh_from_loaded_struct(S, opt.Surface);
    meshInfo.source = 'User mesh file';
    meshInfo.sourceFile = filename;
    meshInfo.surfaceIndex = idx;
elseif isstruct(opt.BrainMesh)
    [brainMesh, idx] = local_extract_mesh_from_loaded_struct(opt.BrainMesh, opt.Surface);
    meshInfo.surfaceIndex = idx;
else
    error('BrainMesh must be empty, a filename, or a mesh/headmodel structure.');
end

brainMesh = local_standardise_mesh_for_plot(brainMesh);
end

function [mesh, idx] = local_extract_mesh_from_loaded_struct(S, surfaceSelection)
% Extract mesh/headmodel from a loaded MAT struct or direct struct.
if isfield(S, 'pos') || isfield(S, 'pnt') || isfield(S, 'bnd')
    candidate = S;
else
    fn = fieldnames(S);
    candidate = [];
    for k = 1:numel(fn)
        tmp = S.(fn{k});
        if isstruct(tmp) && (isfield(tmp, 'pos') || isfield(tmp, 'pnt') || isfield(tmp, 'bnd'))
            candidate = tmp;
            break;
        end
    end
    if isempty(candidate)
        error('Could not find a mesh/headmodel structure in BrainMesh input.');
    end
end

if isfield(candidate, 'bnd')
    surfaces = candidate.bnd;
else
    surfaces = candidate;
end

if numel(surfaces) == 1 && (isfield(surfaces, 'pos') || isfield(surfaces, 'pnt'))
    mesh = surfaces;
    idx = 1;
else
    % Select one surface from a multi-surface BEM/headmodel. We use the same
    % principle as the default loader: 'brain'/'innermost' means the surface
    % with the smallest median radius; 'scalp'/'outermost' means largest.
    if isnumeric(surfaceSelection)
        idx = surfaceSelection;
        if idx < 1 || idx > numel(surfaces)
            error('Requested surface index %d, but BrainMesh contains %d surfaces.', idx, numel(surfaces));
        end
    else
        radius = nan(1, numel(surfaces));
        for s = 1:numel(surfaces)
            tmp = local_standardise_mesh_for_plot(surfaces(s));
            c = mean(tmp.pos, 1, 'omitnan');
            radius(s) = median(sqrt(sum((tmp.pos - c).^2, 2)), 'omitnan');
        end
        switch lower(char(surfaceSelection))
            case {'brain','inner','innermost','smallest'}
                [~, idx] = min(radius);
            case {'scalp','outer','outermost','largest','skin'}
                [~, idx] = max(radius);
            case {'skull','middle'}
                [~, order] = sort(radius, 'ascend');
                idx = order(max(1, round(numel(order)/2)));
            otherwise
                error('Unknown Surface option: %s', char(surfaceSelection));
        end
    end
    mesh = surfaces(idx);
end
end

function mesh = local_standardise_mesh_for_plot(mesh)
% Convert mesh to pos/tri fields and mm units if possible.
if isfield(mesh, 'pnt') && ~isfield(mesh, 'pos')
    mesh.pos = mesh.pnt;
end
if ~isfield(mesh, 'pos') || ~isfield(mesh, 'tri')
    error('Brain mesh must contain .pos/.tri or .pnt/.tri.');
end
mesh.pos = double(mesh.pos);
mesh.tri = double(mesh.tri);
if ~isfield(mesh, 'unit') || isempty(mesh.unit)
    mesh.unit = 'mm';
end

unit = lower(char(mesh.unit));
switch unit
    case {'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'}
        scale = 1;
    case {'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'}
        scale = 10;
    case {'m', 'meter', 'meters', 'metre', 'metres'}
        scale = 1000;
    otherwise
        scale = 1;
end
mesh.pos = mesh.pos .* scale;
mesh.unit = 'mm';
end

function labels = local_to_cellstr(labels)
% Convert label input to cellstr column.
if isempty(labels)
    labels = {};
elseif isstring(labels)
    labels = cellstr(labels(:));
elseif ischar(labels)
    labels = cellstr(labels);
elseif iscell(labels)
    labels = labels(:);
else
    error('Channel labels must be a cell array, string array, or char array.');
end
end

function [pos, labelsOut] = local_select_electrodes(elec, requestedLabels, nExpected, sideName)
% Select and order electrode coordinates to match the connectivity matrix.
allLabels = elec.label(:);
allPos = elec.elecpos;

if isempty(requestedLabels)
    if size(allPos,1) ~= nExpected
        error(['The connectivity matrix is %d x %d, but the electrode input ', ...
               'contains %d electrodes. Provide ChannelLabels/ChannelLabels%s ', ...
               'so the function can select and order the correct electrodes.'], ...
               nExpected, nExpected, size(allPos,1), sideName);
    end
    pos = allPos;
    labelsOut = allLabels;
    return;
end

if numel(requestedLabels) ~= nExpected
    error('ChannelLabels%s contains %d labels, but connMatrix requires %d.', ...
        sideName, numel(requestedLabels), nExpected);
end

idx = nan(nExpected, 1);
for k = 1:nExpected
    idx(k) = local_match_label(requestedLabels{k}, allLabels);
end

missing = isnan(idx);
if any(missing)
    error('Could not find these ChannelLabels%s in the electrode file: %s', ...
        sideName, strjoin(requestedLabels(missing), ', '));
end

pos = allPos(idx, :);
labelsOut = requestedLabels(:);
end

function idx = local_match_label(label, allLabels)
% Match labels robustly: exact case-insensitive first, then remove spaces.
label = char(label);
idx = find(strcmpi(label, allLabels), 1, 'first');
if ~isempty(idx)
    return;
end

clean = @(s)lower(regexprep(char(s), '[\s_\-]', ''));
labelClean = clean(label);
allClean = cellfun(clean, allLabels, 'UniformOutput', false);
idx = find(strcmp(labelClean, allClean), 1, 'first');
if isempty(idx)
    idx = nan;
end
end

function [posA, posB, brainLocal] = local_prepare_geometry(posA, posB, brainMesh, opt)
% Recenter mesh and electrodes, optionally normalising electrodes around
% the brain mesh for a clean visual display.
brainCenter = mean(brainMesh.pos, 1, 'omitnan');
brainLocal = brainMesh.pos - brainCenter;

coordinateMode = lower(char(opt.CoordinateMode));
switch coordinateMode
    case {'native', 'mni'}
        % Keep original coordinate relationships, only express them relative
        % to the brain centre.
        posA = posA - brainCenter;
        posB = posB - brainCenter;

    case {'auto', 'normalise', 'normalize', 'visual'}
        % Fit the electrode cloud around the brain mesh. This is a visual
        % alignment, not a source-localisation coregistration.
        targetRadius = median(sqrt(sum(brainLocal.^2, 2)), 'omitnan') * opt.ElectrodeRadiusScale;
        posA = local_normalise_electrode_cloud(posA, targetRadius);
        posB = local_normalise_electrode_cloud(posB, targetRadius);

    otherwise
        error('Unknown CoordinateMode: %s', coordinateMode);
end

% Push electrodes outward so they float over the anatomical reference rather
% than intersecting the brain mesh.
posA = local_push_outward(posA, opt.ElectrodeOutwardOffset);
posB = local_push_outward(posB, opt.ElectrodeOutwardOffset);
end

function pos = local_normalise_electrode_cloud(pos, targetRadius)
% Recentre and isotropically rescale an electrode cloud.
centre = mean(pos, 1, 'omitnan');
local = pos - centre;
r = sqrt(sum(local.^2, 2));
sourceRadius = median(r, 'omitnan');
if sourceRadius <= 0 || isnan(sourceRadius)
    error('Electrode positions have zero or invalid spatial extent.');
end
pos = local .* (targetRadius / sourceRadius);
end

function pos = local_push_outward(pos, offset)
% Move each electrode further away from the origin by a fixed offset.
r = sqrt(sum(pos.^2, 2));
r(r == 0) = eps;
pos = pos + (pos ./ r) .* offset;
end

function [linkHandles, linkTable] = local_plot_links(ax, connMatrix, posA, posB, labelsA, labelsB, opt)
% Determine which matrix entries should be plotted and draw the links.
nChan = size(connMatrix,1);
mask = local_threshold_matrix(connMatrix, opt);

% Explicitly retain or remove diagonal entries according to PlotDiagonal.
if ~opt.PlotDiagonal
    mask(1:nChan+1:end) = false;
end

% Optionally restrict to the strongest MaxLinks links by absolute value.
if isfinite(opt.MaxLinks) && nnz(mask) > opt.MaxLinks
    values = abs(connMatrix(mask));
    [~, order] = sort(values(:), 'descend');
    linearIdx = find(mask);
    keep = false(size(mask));
    keep(linearIdx(order(1:opt.MaxLinks))) = true;
    mask = keep;
end

[I, J] = find(mask);
nLinks = numel(I);
linkHandles = gobjects(nLinks, 1);

if nLinks == 0
    linkTable = table();
    return;
end

absVals = abs(connMatrix(mask));
minAbs = min(absVals);
maxAbs = max(absVals);
widthMin = min(opt.LinkWidthRange);
widthMax = max(opt.LinkWidthRange);

sourceLabel = cell(nLinks, 1);
targetLabel = cell(nLinks, 1);
value = nan(nLinks, 1);
isDiagonal = false(nLinks, 1);

for k = 1:nLinks
    i = I(k);
    j = J(k);
    v = connMatrix(i,j);

    % Scale line width by absolute connection strength/statistic.
    if maxAbs > minAbs
        width = widthMin + ((abs(v) - minAbs) / (maxAbs - minAbs)) * (widthMax - widthMin);
    else
        width = mean([widthMin widthMax]);
    end

    % Assign colour by sign. This preserves the interpretation of positive
    % and negative effects while still plotting the diagonal if present.
    if v > 0
        col = opt.PositiveLinkColor;
    elseif v < 0
        col = opt.NegativeLinkColor;
    else
        col = opt.ZeroLinkColor;
    end

    p0 = posA(i,:);
    p2 = posB(j,:);

    if opt.UseCurvedLinks
        xyz = local_bezier_curve(p0, p2, opt.LinkArcHeight, opt.CurvePoints);
        linkHandles(k) = plot3(ax, xyz(:,1), xyz(:,2), xyz(:,3), '-', ...
            'Color', local_apply_alpha_to_color(col, opt.LinkAlpha), 'LineWidth', width, ...
            'Tag', 'InterBrainLink');
    else
        linkHandles(k) = plot3(ax, [p0(1) p2(1)], [p0(2) p2(2)], [p0(3) p2(3)], '-', ...
            'Color', local_apply_alpha_to_color(col, opt.LinkAlpha), 'LineWidth', width, ...
            'Tag', 'InterBrainLink');
    end

    sourceLabel{k} = labelsA{i};
    targetLabel{k} = labelsB{j};
    value(k) = v;
    isDiagonal(k) = i == j;
end

linkTable = table(I, J, sourceLabel, targetLabel, value, isDiagonal, ...
    'VariableNames', {'IndexA','IndexB','LabelA','LabelB','Value','IsDiagonal'});
end

function mask = local_threshold_matrix(connMatrix, opt)
% Create a logical matrix indicating which connections should be shown.
thresholdType = lower(char(opt.ThresholdType));
switch thresholdType
    case {'nonzero', 'nz'}
        mask = connMatrix ~= 0 & ~isnan(connMatrix);
    case {'abs', 'absolute'}
        mask = abs(connMatrix) >= opt.MinAbsValue & ~isnan(connMatrix);
    case {'range'}
        lo = min(opt.ValueRange);
        hi = max(opt.ValueRange);
        mask = connMatrix >= lo & connMatrix <= hi & ~isnan(connMatrix);
    otherwise
        error('Unknown ThresholdType: %s', thresholdType);
end
end

function xyz = local_bezier_curve(p0, p2, arcHeight, nPoints)
% Quadratic Bezier curve between two electrodes. The control point is raised
% in Z to reduce visual overlap with the brain meshes.
t = linspace(0, 1, nPoints)';
p1 = (p0 + p2) ./ 2;
p1(3) = p1(3) + arcHeight;
xyz = ((1-t).^2) .* p0 + (2*(1-t).*t) .* p1 + (t.^2) .* p2;
end

function hText = local_plot_labels(ax, pos, labels, prefix, opt)
% Plot electrode labels slightly outside each electrode marker.
labelMode = lower(char(opt.LabelMode));
nChan = size(pos,1);
hText = gobjects(nChan, 1);

labelPos = local_push_outward(pos, opt.LabelOffset);

for k = 1:nChan
    switch labelMode
        case {'names', 'name', 'labels'}
            labelString = labels{k};
        case {'numbers', 'number', 'indices', 'index'}
            labelString = sprintf('%s%d', prefix, k);
        otherwise
            labelString = labels{k};
    end

    hText(k) = text(ax, labelPos(k,1), labelPos(k,2), labelPos(k,3), labelString, ...
        'FontSize', opt.LabelFontSize, 'FontWeight', 'bold', ...
        'Color', opt.LabelColor, 'BackgroundColor', opt.LabelBackground, ...
        'Margin', opt.LabelMargin, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none', ...
        'Tag', ['Label' prefix]);
end
end

function local_apply_view(ax, viewOpt)
% Apply numeric or named 3-D view.
if isnumeric(viewOpt)
    view(ax, viewOpt(1), viewOpt(2));
    return;
end

switch lower(char(viewOpt))
    case {'front'}
        view(ax, 0, 15);
    case {'top'}
        view(ax, 0, 90);
    case {'right'}
        view(ax, 90, 15);
    case {'left'}
        view(ax, -90, 15);
    case {'oblique'}
        view(ax, 35, 25);
    otherwise
        error('Unknown View option: %s', char(viewOpt));
end
end


function rgb = local_apply_alpha_to_color(rgb, alphaValue)
% MATLAB line objects do not reliably support RGBA colours across versions.
% To obtain a softer appearance, blend the requested colour with white.
alphaValue = max(0, min(1, alphaValue));
rgb = alphaValue .* rgb + (1 - alphaValue) .* [1 1 1];
end

function local_write_movie(fig, ax, opt)
% Export a simple rotating MP4 video of the current figure.
movieFile = char(opt.MovieFile);
[folder,~,ext] = fileparts(movieFile);
if isempty(ext)
    movieFile = [movieFile '.mp4'];
end
if ~isempty(folder) && exist(folder, 'dir') ~= 7
    mkdir(folder);
end

writer = VideoWriter(movieFile, 'MPEG-4');
writer.FrameRate = opt.MovieFrameRate;
open(writer);

nFrames = max(2, round(opt.MovieDuration * opt.MovieFrameRate));
azimuths = linspace(0, 360, nFrames+1);
azimuths(end) = [];

for f = 1:nFrames
    view(ax, azimuths(f), opt.MovieElevation);
    drawnow;
    writeVideo(writer, getframe(fig));
end

close(writer);
fprintf('%s: movie written to %s\n', mfilename, movieFile);
end
