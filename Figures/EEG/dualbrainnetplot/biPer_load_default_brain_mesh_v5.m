function [brainMesh, info, headmodel] = biPer_load_default_brain_mesh_v5(varargin)
% biPer_load_default_brain_mesh_v5
% -------------------------------------------------------------------------
% Load a default anatomical BRAIN surface for the dual-brain connectivity
% plot. The preferred source is FieldTrip's template BEM head model
% 'standard_bem.mat'. If FieldTrip is not available, the function also tries
% to find the same/similar template in an EEGLAB/DIPFIT installation.
%
% Why this function exists:
%   The dual-brain network plot does not need EEGLAB .spl files, because we
%   are not interpolating a scalp field. We only need:
%       1) a surface mesh to provide an anatomical reference, and
%       2) electrode coordinates to anchor the network links.
%
% Output:
%   brainMesh.pos  - Nvertex x 3 vertex coordinates, in mm when possible.
%   brainMesh.tri  - Nface   x 3 triangular faces.
%   info           - structure describing where the mesh came from.
%   headmodel      - the full head model if one was loaded; otherwise [].
%
% Example:
%   [brainMesh, info] = biPer_load_default_brain_mesh_v5;
%   patch('Vertices', brainMesh.pos, 'Faces', brainMesh.tri, ...
%         'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none');
%   axis equal off; camlight; lighting gouraud;
%
% Notes:
%   FieldTrip BEM templates usually include three surfaces. Different
%   examples/documentation may describe the surface order differently, so by
%   default this function does NOT assume that bnd(3) is always the brain.
%   Instead, it chooses the innermost/smallest-radius surface, which is the
%   most robust choice for a brain surface.
% -------------------------------------------------------------------------

% ----------------------------- Parse inputs ------------------------------
p = inputParser;
p.FunctionName = mfilename;

% The default template model used by FieldTrip/EEGLAB-DIPFIT.
addParameter(p, 'HeadModelFile', 'standard_bem.mat', @(x)ischar(x) || isstring(x));

% Which surface should be extracted from a multi-surface BEM model.
% Recommended default: 'innermost', because it usually corresponds to brain.
addParameter(p, 'Surface', 'innermost', @(x)ischar(x) || isstring(x) || isnumeric(x));

% If true, print brief information about the mesh source.
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));

parse(p, varargin{:});
opt = p.Results;

% Initialise outputs.
brainMesh = [];
headmodel = [];
info = struct();
info.source = '';
info.sourceFile = '';
info.surfaceSelection = opt.Surface;
info.surfaceIndex = [];
info.message = '';

% ------------------------- 1. Try FieldTrip reader ------------------------
% ft_read_headmodel knows where FieldTrip templates are located, so this is
% the cleanest path when FieldTrip is on the MATLAB path.
if exist('ft_read_headmodel', 'file') == 2
    try
        headmodel = ft_read_headmodel(char(opt.HeadModelFile));
        info.source = 'FieldTrip ft_read_headmodel';
        info.sourceFile = char(opt.HeadModelFile);
    catch
        % If the short filename did not work, try the explicit FieldTrip
        % template path derived from ft_defaults.
        ftRoot = local_find_fieldtrip_root();
        if ~isempty(ftRoot)
            candidate = fullfile(ftRoot, 'template', 'headmodel', char(opt.HeadModelFile));
            if exist(candidate, 'file') == 2
                try
                    headmodel = ft_read_headmodel(candidate);
                    info.source = 'FieldTrip template/headmodel';
                    info.sourceFile = candidate;
                catch
                    headmodel = [];
                end
            end
        end
    end
end

% ---------------------------- 2. Try MAT load -----------------------------
% This catches cases where the template file is on the MATLAB path but
% FieldTrip's reader is not available.
if isempty(headmodel)
    candidate = '';
    if exist(char(opt.HeadModelFile), 'file') == 2
        candidate = char(opt.HeadModelFile);
    else
        candidate = which(char(opt.HeadModelFile));
    end
    if ~isempty(candidate)
        headmodel = local_load_headmodel_from_mat(candidate);
        if ~isempty(headmodel)
            info.source = 'MAT-file on MATLAB path';
            info.sourceFile = candidate;
        end
    end
end

% ------------------------- 3. Try EEGLAB/DIPFIT ---------------------------
% EEGLAB installations often include DIPFIT, which may contain a standard
% BEM model. This search is intentionally conservative and only looks inside
% EEGLAB's plugin directory if eeglab.m is on the path.
if isempty(headmodel)
    eeglabRoot = local_find_eeglab_root();
    if ~isempty(eeglabRoot)
        candidates = dir(fullfile(eeglabRoot, 'plugins', 'dipfit*', '**', char(opt.HeadModelFile)));
        if isempty(candidates)
            candidates = dir(fullfile(eeglabRoot, 'plugins', '**', char(opt.HeadModelFile)));
        end
        if ~isempty(candidates)
            candidate = fullfile(candidates(1).folder, candidates(1).name);
            headmodel = local_load_headmodel_from_mat(candidate);
            if ~isempty(headmodel)
                info.source = 'EEGLAB/DIPFIT template';
                info.sourceFile = candidate;
            end
        end
    end
end

% ----------------------------- Failure case -------------------------------
if isempty(headmodel)
    error(['Could not find a default brain mesh. Add FieldTrip to the MATLAB path ', ...
           'and run ft_defaults, or pass a custom BrainMesh/HeadModelFile. ', ...
           'Expected template: %s'], char(opt.HeadModelFile));
end

% -------------------------- Extract brain surface -------------------------
[brainMesh, idx] = local_extract_surface(headmodel, opt.Surface);
info.surfaceIndex = idx;

% Make sure the mesh uses FieldTrip's common field names.
brainMesh = local_standardise_mesh(brainMesh);

% Add a unit if the parent head model specifies one.
if isfield(headmodel, 'unit') && ~isfield(brainMesh, 'unit')
    brainMesh.unit = headmodel.unit;
end

% Convert to millimetres when possible. This keeps visual defaults stable.
brainMesh = local_convert_mesh_to_mm(brainMesh);

if opt.Verbose
    fprintf('%s: loaded brain mesh from %s', mfilename, info.source);
    if ~isempty(info.sourceFile)
        fprintf(' (%s)', info.sourceFile);
    end
    fprintf('\n');
    fprintf('%s: selected surface index %d with %d vertices and %d faces.\n', ...
        mfilename, info.surfaceIndex, size(brainMesh.pos,1), size(brainMesh.tri,1));
end

end

% ========================================================================
% Local helper functions
% ========================================================================

function ftRoot = local_find_fieldtrip_root()
% Return FieldTrip root directory if FieldTrip is on the MATLAB path.
ftRoot = '';
ftDefaults = which('ft_defaults');
if ~isempty(ftDefaults)
    ftRoot = fileparts(ftDefaults);
end
end

function eeglabRoot = local_find_eeglab_root()
% Return EEGLAB root directory if EEGLAB is on the MATLAB path.
eeglabRoot = '';
eeglabFile = which('eeglab');
if isempty(eeglabFile)
    eeglabFile = which('eeglab.m');
end
if ~isempty(eeglabFile)
    eeglabRoot = fileparts(eeglabFile);
end
end

function headmodel = local_load_headmodel_from_mat(filename)
% Load a MAT-file and extract a plausible headmodel structure.
headmodel = [];
S = load(filename, '-mat');
fn = fieldnames(S);

% First preference: a variable that already looks like a FieldTrip headmodel.
for k = 1:numel(fn)
    candidate = S.(fn{k});
    if isstruct(candidate) && (isfield(candidate, 'bnd') || local_is_mesh(candidate))
        headmodel = candidate;
        return;
    end
end
end

function tf = local_is_mesh(x)
% True if x resembles a triangulated mesh.
tf = isstruct(x) && ...
     ((isfield(x, 'pos') || isfield(x, 'pnt')) && ...
      (isfield(x, 'tri') || isfield(x, 'tet')));
end

function [mesh, idx] = local_extract_surface(headmodel, surfaceSelection)
% Extract one triangulated surface from either a FieldTrip headmodel or an
% already provided mesh.
if isfield(headmodel, 'bnd')
    surfaces = headmodel.bnd;
else
    surfaces = headmodel;
end

% If the input is a single mesh, return it immediately.
if local_is_mesh(surfaces) && numel(surfaces) == 1
    mesh = surfaces;
    idx = 1;
    return;
end

if ~isstruct(surfaces)
    error('The loaded head model does not contain a valid surface mesh.');
end

nSurf = numel(surfaces);
if nSurf == 0
    error('The loaded head model contains no boundary surfaces.');
end

% Numeric selection: use the requested boundary index directly.
if isnumeric(surfaceSelection)
    idx = surfaceSelection;
    if idx < 1 || idx > nSurf
        error('Requested surface index %d, but the head model contains %d surfaces.', idx, nSurf);
    end
    mesh = surfaces(idx);
    return;
end

% Text selection: choose by radial size. This avoids relying on a fixed BEM
% boundary order across FieldTrip/EEGLAB versions.
surfaceSelection = lower(char(surfaceSelection));
radius = nan(1, nSurf);
for s = 1:nSurf
    tmp = local_standardise_mesh(surfaces(s));
    c = mean(tmp.pos, 1, 'omitnan');
    radius(s) = median(sqrt(sum((tmp.pos - c).^2, 2)), 'omitnan');
end

switch surfaceSelection
    case {'brain', 'inner', 'innermost', 'smallest'}
        [~, idx] = min(radius);
    case {'scalp', 'outer', 'outermost', 'largest', 'skin'}
        [~, idx] = max(radius);
    case {'skull', 'middle'}
        [~, order] = sort(radius, 'ascend');
        idx = order(max(1, round(numel(order)/2)));
    otherwise
        error('Unknown Surface option: %s', surfaceSelection);
end

mesh = surfaces(idx);
end

function mesh = local_standardise_mesh(mesh)
% Convert common FieldTrip mesh variants to fields pos/tri.
if isfield(mesh, 'pnt') && ~isfield(mesh, 'pos')
    mesh.pos = mesh.pnt;
end
if isfield(mesh, 'tet') && ~isfield(mesh, 'tri')
    error('The selected mesh is tetrahedral. A triangular surface mesh with .tri is required.');
end
if ~isfield(mesh, 'pos') || ~isfield(mesh, 'tri')
    error('Mesh must contain fields .pos and .tri, or .pnt and .tri.');
end
mesh.pos = double(mesh.pos);
mesh.tri = double(mesh.tri);
end

function mesh = local_convert_mesh_to_mm(mesh)
% Convert mesh coordinates to mm for stable plotting defaults.
if ~isfield(mesh, 'unit') || isempty(mesh.unit)
    mesh.unit = 'mm';
    return;
end

unit = lower(mesh.unit);
switch unit
    case {'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'}
        scale = 1;
    case {'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'}
        scale = 10;
    case {'m', 'meter', 'meters', 'metre', 'metres'}
        scale = 1000;
    otherwise
        warning('%s: unknown mesh unit "%s". Coordinates were not rescaled.', mfilename, mesh.unit);
        scale = 1;
end
mesh.pos = mesh.pos .* scale;
mesh.unit = 'mm';
end
