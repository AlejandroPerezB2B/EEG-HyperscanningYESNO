function handles = biPer_B2B_plot_stats_brainmesh_v5(electrodeInput, varargin)
% biPer_B2B_plot_stats_brainmesh_v5
% -------------------------------------------------------------------------
% Convenience wrapper for plotting Alejandro's existing B2B statistics using
% the new dual-brain FieldTrip-template visualisation.
%
% This wrapper keeps the original analysis logic:
%   - config_biPer defines paths, channel count, bad channels, labels, etc.
%   - stats_B2B_<measure>_<freqband>.mat contains b2b_4plot.
%   - b2b_4plot rows/columns are the inter-brain channel-by-channel matrix.
%   - bad channels are set to zero before plotting.
%
% Unlike within-brain connectivity plots, the diagonal is meaningful here:
%   b2b_4plot(i,i) = connection/effect between electrode i in participant A
%                    and electrode i in participant B.
% The plotting function therefore includes diagonal entries by default.
%
% Example:
%   handles = biPer_B2B_plot_stats_brainmesh_v5(EEG.chanlocs, ...
%       'Measure', 'eeg_ccorr', ...
%       'FreqIndex', 2, ...
%       'MakeMovie', true);
%
% Example using FieldTrip template electrodes and channel labels from config:
%   handles = biPer_B2B_plot_stats_brainmesh_v5('fieldtrip:standard_1005.elc');
% -------------------------------------------------------------------------

% ----------------------------- Parse inputs ------------------------------
p = inputParser;
p.FunctionName = mfilename;
addParameter(p, 'Measure', 'eeg_ccorr', @(x)ischar(x) || isstring(x));
addParameter(p, 'FreqIndex', 2, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'StatsFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'TitlePrefix', 'B2B', @(x)ischar(x) || isstring(x));
addParameter(p, 'MakeMovie', false, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'MovieFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'ChannelLabels', {}, @(x)iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));

% All unrecognised options are passed to biPer_plot_interbrain_brainmesh_v5.
p.KeepUnmatched = true;
parse(p, varargin{:});
opt = p.Results;
plotOptions = namedargs2cell(p.Unmatched);

% --------------------------- Load project config --------------------------
% This is intentionally the same dependency as your original plotting code.
config_biPer;

measure = char(opt.Measure);
freqIndex = opt.FreqIndex;

if isempty(opt.StatsFile)
    statsFile = fullfile(data_path, ['stats_B2B_' measure '_' freq_bands{1,freqIndex} '.mat']);
else
    statsFile = char(opt.StatsFile);
end

if exist(statsFile, 'file') ~= 2
    error('Statistics file not found: %s', statsFile);
end

S = load(statsFile);
if ~isfield(S, 'b2b_4plot')
    error('The statistics file does not contain b2b_4plot: %s', statsFile);
end

connMatrix = S.b2b_4plot;

% ---------------------------- Remove bad channels -------------------------
% Preserve the matrix size and channel order, but remove unwanted channels
% from the visualisation by setting their effects to zero.
if exist('bad_ch', 'var') && ~isempty(bad_ch)
    connMatrix(bad_ch,:) = 0;
    connMatrix(:,bad_ch) = 0;
end

% --------------------------- Resolve labels -------------------------------
% If the caller did not provide labels, try to reuse the labels from
% config_biPer. In your original plot, XTick_S and YTick_L were used for
% speaker/listener heatmap axes. Here we assume the same electrode order.
channelLabels = opt.ChannelLabels;
if isempty(channelLabels)
    if exist('YTick_L', 'var') && numel(YTick_L) == size(connMatrix,1)
        channelLabels = YTick_L;
    elseif exist('XTick_S', 'var') && numel(XTick_S) == size(connMatrix,1)
        channelLabels = XTick_S;
    end
end

% ------------------------------ Plot title --------------------------------
plotTitle = sprintf('%s %s %s', char(opt.TitlePrefix), measure, freq_bands{1,freqIndex});

% ------------------------------ Movie name --------------------------------
if isempty(opt.MovieFile)
    movieFile = sprintf('%s_%s_%s_dualbrain.mp4', char(opt.TitlePrefix), measure, freq_bands{1,freqIndex});
else
    movieFile = char(opt.MovieFile);
end

% ------------------------------- Plot -------------------------------------
handles = biPer_plot_interbrain_brainmesh_v5(connMatrix, electrodeInput, ...
    'ChannelLabels', channelLabels, ...
    'ThresholdType', 'nonzero', ...
    'PlotDiagonal', true, ...
    'Title', plotTitle, ...
    'MakeMovie', opt.MakeMovie, ...
    'MovieFile', movieFile, ...
    'Verbose', opt.Verbose, ...
    plotOptions{:});

end

function c = namedargs2cell(s)
% Convert a structure of unmatched inputParser options to name-value pairs.
fn = fieldnames(s);
c = cell(1, numel(fn)*2);
for k = 1:numel(fn)
    c{2*k-1} = fn{k};
    c{2*k} = s.(fn{k});
end
end
