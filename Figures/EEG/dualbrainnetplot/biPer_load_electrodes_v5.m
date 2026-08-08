function elec = biPer_load_electrodes_v5(electrodeInput, varargin)
% biPer_load_electrodes_v5
% -------------------------------------------------------------------------
% Convert several common electrode-location inputs into a FieldTrip-like
% electrode structure with fields:
%       elec.elecpos   N x 3 electrode coordinates
%       elec.chanpos   N x 3 channel/electrode coordinates
%       elec.label     N x 1 cell array of channel labels
%       elec.unit      coordinate unit, preferably 'mm'
%
% Accepted inputs:
%   1) FieldTrip electrode/sensor structure with elecpos or chanpos.
%   2) EEGLAB EEG structure with EEG.chanlocs.
%   3) EEGLAB chanlocs structure array with X/Y/Z and labels.
%   4) A filename readable by FieldTrip ft_read_sens or EEGLAB readlocs.
%   5) A MAT-file containing elec, EEG, or chanlocs.
%   6) The string 'fieldtrip:standard_1005.elc' to load FieldTrip's
%      template 10-05 electrodes, if FieldTrip is installed.
% -------------------------------------------------------------------------

p = inputParser;
p.FunctionName = mfilename;
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

if nargin < 1 || isempty(electrodeInput)
    error(['No electrode input was provided. Pass EEG.chanlocs, an EEG structure, ', ...
           'a FieldTrip elec structure, or an electrode-position file.']);
end

% ------------------------ FieldTrip template shortcut ---------------------
if ischar(electrodeInput) || isstring(electrodeInput)
    electrodeInput = char(electrodeInput);
    if startsWith(lower(electrodeInput), 'fieldtrip:')
        templateName = extractAfter(electrodeInput, 'fieldtrip:');
        if isempty(templateName)
            templateName = 'standard_1005.elc';
        end
        electrodeInput = local_find_fieldtrip_electrode_file(char(templateName));
    end
end

% ----------------------------- File input --------------------------------
if ischar(electrodeInput) || isstring(electrodeInput)
    filename = char(electrodeInput);
    if exist(filename, 'file') ~= 2
        error('Electrode file not found: %s', filename);
    end
    [~,~,ext] = fileparts(filename);
    ext = lower(ext);

    if strcmp(ext, '.mat')
        elec = local_load_electrodes_from_mat(filename);
    elseif exist('ft_read_sens', 'file') == 2
        elec = ft_read_sens(filename);
    elseif exist('readlocs', 'file') == 2
        chanlocs = readlocs(filename);
        elec = local_chanlocs_to_elec(chanlocs);
    else
        error(['Cannot read electrode file. Add FieldTrip ft_read_sens or ', ...
               'EEGLAB readlocs to the MATLAB path.']);
    end

% ---------------------------- Struct input -------------------------------
elseif isstruct(electrodeInput)
    if isfield(electrodeInput, 'chanlocs')
        elec = local_chanlocs_to_elec(electrodeInput.chanlocs);
    elseif isfield(electrodeInput, 'elecpos') || isfield(electrodeInput, 'chanpos')
        elec = electrodeInput;
    elseif isfield(electrodeInput, 'X') && isfield(electrodeInput, 'Y') && isfield(electrodeInput, 'Z')
        elec = local_chanlocs_to_elec(electrodeInput);
    else
        error('Unrecognised electrode structure. Expected elecpos/chanpos or EEGLAB chanlocs fields.');
    end
else
    error('Unsupported electrode input type.');
end

% -------------------------- Standardise fields ----------------------------
elec = local_standardise_elec(elec);
elec = local_convert_elec_to_mm(elec);

if opt.Verbose
    fprintf('%s: loaded %d electrodes.\n', mfilename, size(elec.elecpos,1));
end
end

% ========================================================================
% Local helpers
% ========================================================================

function filename = local_find_fieldtrip_electrode_file(templateName)
% Locate a template electrode file in FieldTrip's template/electrode folder.
filename = '';
ftDefaults = which('ft_defaults');
if ~isempty(ftDefaults)
    ftRoot = fileparts(ftDefaults);
    candidate = fullfile(ftRoot, 'template', 'electrode', templateName);
    if exist(candidate, 'file') == 2
        filename = candidate;
        return;
    end
end

candidate = which(templateName);
if ~isempty(candidate)
    filename = candidate;
    return;
end

error(['Could not find FieldTrip electrode template %s. ', ...
       'Add FieldTrip to the MATLAB path and run ft_defaults.'], templateName);
end

function elec = local_load_electrodes_from_mat(filename)
% Load electrode information from a MAT-file.
S = load(filename, '-mat');

if isfield(S, 'elec')
    elec = S.elec;
elseif isfield(S, 'sens')
    elec = S.sens;
elseif isfield(S, 'EEG') && isfield(S.EEG, 'chanlocs')
    elec = local_chanlocs_to_elec(S.EEG.chanlocs);
elseif isfield(S, 'chanlocs')
    elec = local_chanlocs_to_elec(S.chanlocs);
else
    fn = fieldnames(S);
    elec = [];
    for k = 1:numel(fn)
        candidate = S.(fn{k});
        if isstruct(candidate) && (isfield(candidate, 'elecpos') || isfield(candidate, 'chanpos'))
            elec = candidate;
            break;
        end
    end
    if isempty(elec)
        error('MAT-file does not contain elec, sens, EEG.chanlocs, or chanlocs: %s', filename);
    end
end
end

function elec = local_chanlocs_to_elec(chanlocs)
% Convert EEGLAB chanlocs into a FieldTrip-like electrode structure.
nChan = numel(chanlocs);
pos = nan(nChan, 3);
labels = cell(nChan, 1);

for c = 1:nChan
    if isfield(chanlocs, 'X') && ~isempty(chanlocs(c).X)
        pos(c,1) = chanlocs(c).X;
    end
    if isfield(chanlocs, 'Y') && ~isempty(chanlocs(c).Y)
        pos(c,2) = chanlocs(c).Y;
    end
    if isfield(chanlocs, 'Z') && ~isempty(chanlocs(c).Z)
        pos(c,3) = chanlocs(c).Z;
    end

    if isfield(chanlocs, 'labels') && ~isempty(chanlocs(c).labels)
        labels{c} = char(chanlocs(c).labels);
    else
        labels{c} = sprintf('E%d', c);
    end
end

if any(isnan(pos(:)))
    error(['Some chanlocs do not contain valid X/Y/Z coordinates. ', ...
           'Use pop_chanedit/readlocs first to define 3-D coordinates.']);
end

elec = struct();
elec.elecpos = pos;
elec.chanpos = pos;
elec.label = labels;

% EEGLAB coordinates are often in roughly head-radius units rather than mm.
% The main plotting function can normalise them visually against the mesh.
elec.unit = 'unknown';
end

function elec = local_standardise_elec(elec)
% Ensure elecpos, chanpos, and label exist.
if ~isfield(elec, 'elecpos') && isfield(elec, 'chanpos')
    elec.elecpos = elec.chanpos;
end
if ~isfield(elec, 'chanpos') && isfield(elec, 'elecpos')
    elec.chanpos = elec.elecpos;
end
if ~isfield(elec, 'elecpos')
    error('Electrode structure must contain elecpos or chanpos.');
end

elec.elecpos = double(elec.elecpos);
elec.chanpos = double(elec.chanpos);

nChan = size(elec.elecpos,1);
if ~isfield(elec, 'label') || isempty(elec.label)
    elec.label = arrayfun(@(x)sprintf('E%d',x), 1:nChan, 'UniformOutput', false)';
end
if ischar(elec.label)
    elec.label = cellstr(elec.label);
end
elec.label = elec.label(:);

if numel(elec.label) ~= nChan
    error('Number of electrode labels (%d) does not match number of electrode positions (%d).', ...
        numel(elec.label), nChan);
end

if ~isfield(elec, 'unit') || isempty(elec.unit)
    elec.unit = 'unknown';
end
end

function elec = local_convert_elec_to_mm(elec)
% Convert common coordinate units to mm. Unknown units are left unchanged;
% the main plotting function can then normalise them for display.
unit = lower(char(elec.unit));
switch unit
    case {'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'}
        scale = 1;
        elec.unit = 'mm';
    case {'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'}
        scale = 10;
        elec.unit = 'mm';
    case {'m', 'meter', 'meters', 'metre', 'metres'}
        scale = 1000;
        elec.unit = 'mm';
    otherwise
        scale = 1;
end

elec.elecpos = elec.elecpos .* scale;
elec.chanpos = elec.chanpos .* scale;
end
