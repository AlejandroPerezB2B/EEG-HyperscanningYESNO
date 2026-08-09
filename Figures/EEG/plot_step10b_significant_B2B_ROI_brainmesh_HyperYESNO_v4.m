function [plotData, summaryStruct] = plot_step10b_significant_B2B_ROI_brainmesh_HyperYESNO_v4(step10bMatFile, varargin)
% PLOT_STEP10B_SIGNIFICANT_B2B_ROI_BRAINMESH_HYPERYESNO_V3
% -------------------------------------------------------------------------
% Publication-oriented dual-brain visualisation of the HyperYESNO Step 10b
% spatial cluster-permutation results.
%
% V3 differs from the earlier plotting helpers in four important ways:
%
%   1) The cortical meshes are the high-resolution FreeSurfer fsaverage
%      PIAL surfaces, rather than FieldTrip's coarse standard_bem surface.
%
%   2) The 20 HyperYESNO source ROIs are shown directly on the cortical
%      surface using their Desikan-Killiany parcels.
%
%   3) Significant inter-brain connections are drawn as elevated 3-D cubic
%      Bezier arcs, making dense links easier to distinguish.
%
%   4) The requested lags are displayed in a single panelled figure with a
%      common effect-size/line-width scale and an explicit legend.
%
% -------------------------------------------------------------------------
% STATISTICAL INPUT USED FOR THE FIGURE
% -------------------------------------------------------------------------
% The function uses ONLY the lag-specific spatial FWER results from Step10b:
%
%   spatialData.spatialFWERWithinLagPMap(:,:,lagIndex)
%
% A connection is plotted when:
%
%   SpatialFWERWithinLagP <= Alpha
%
% The global-across-lags corrected p-value map is NOT used for deciding
% which links are shown in this figure.
%
% Effect direction and magnitude are taken from:
%
%   spatialData.groupMean(:,:,lagIndex)
%
% which is the group mean of Step 9's primary contrast:
%
%   0.5 * [(YES_AKnower - NO_AKnower) +
%          (YES_BKnower - NO_BKnower)]
%
% Therefore:
%
%   positive effect  = surrogate-corrected GCMI is larger for YES than NO
%   negative effect  = surrogate-corrected GCMI is larger for NO than YES
%
% The line colour encodes this sign, while line width encodes the absolute
% magnitude of the group-mean YES-minus-NO effect. Width scaling is shared
% across all displayed lags so panels are directly comparable.
%
% -------------------------------------------------------------------------
% LAG CONVENTION
% -------------------------------------------------------------------------
% The plotting function preserves the Step 9/10b lag convention:
%
%   negative lag = Knower precedes Guesser
%   positive lag = Guesser precedes Knower
%
% Curved lines are connectivity links, NOT causal arrows. No arrowheads are
% drawn because lagged GCMI at a selected temporal offset should not be
% represented as a directed causal connection.
%
% -------------------------------------------------------------------------
% REQUIREMENTS
% -------------------------------------------------------------------------
% A full FieldTrip installation must be on the MATLAB path because the
% function uses ft_read_atlas to read FreeSurfer files.
%
% FsAverageDir must contain:
%
%   label/lh.aparc.annot
%   label/rh.aparc.annot
%   surf/lh.pial
%   surf/rh.pial
%
% Example folder:
%
%   E:\EEG_data_HyperYESNO\fsaverage
%
% -------------------------------------------------------------------------
% BASIC EXAMPLE
% -------------------------------------------------------------------------
%
% [plotData, summaryStruct] = ...
%     plot_step10b_significant_B2B_ROI_brainmesh_HyperYESNO_v3( ...
%     'E:\EEG_data_HyperYESNO\Group_GCMI\Step10b_HyperYESNO_spatial_cluster_permutation.mat', ...
%     'FsAverageDir', 'E:\EEG_data_HyperYESNO\fsaverage', ...
%     'LagsToPlot', [-250 300], ...
%     'SaveFigures', true);
%
% -------------------------------------------------------------------------
% USEFUL OPTIONS
% -------------------------------------------------------------------------
%
% 'LagsToPlot'           default [-250 300]
% 'Alpha'                default [] -> uses Step10b familyWiseAlpha
% 'MeshReduction'        default 0.45; use 1 for full pial mesh
% 'ROIPatchReduction'    default 0.65; use 1 for full parcel surfaces
% 'BrainSeparation'      default [] -> estimated from fsaverage dimensions
% 'ArcHeight'            default [] -> estimated from brain separation
% 'ArcSpread'            default 22 mm
% 'ArcPoints'            default 80
% 'LinkWidthRange'       default [1.5 6.0]
% 'ShowAllROINodes'      default true
% 'ShowConnectedLabels'  default true
% 'ShowAllROILabels'     default false
% 'FigureVisible'        default 'on'
% 'SaveFigures'          default true
% 'SaveTables'           default true
% 'FigureFormat'         default 'png'
% 'ExportResolution'     default 600 dpi
% 'View'                 default [0 12]
%
% MeshReduction and ROIPatchReduction are fractions accepted by reducepatch.
% Setting them to 1 retains the original FreeSurfer surface resolution.
%
% -------------------------------------------------------------------------
% OUTPUTS
% -------------------------------------------------------------------------
% plotData(k) contains the exact matrices and significant-connection table
% used for panel k.
%
% summaryStruct contains the fsaverage geometry, ROI coordinates, common
% line-width scale, combined significant-connection table, and saved files.
%
% Author: Alejandro Perez / ChatGPT support
% HyperYESNO project, 2026


%% 1. Parse inputs
if nargin < 1 || isempty(step10bMatFile)
    error('A Step 10b MAT file must be provided.');
end

p = inputParser;
p.FunctionName = mfilename;
addRequired(p, 'step10bMatFile', @(x)ischar(x) || (isstring(x) && isscalar(x)));
addParameter(p, 'FsAverageDir', '', @(x)ischar(x) || (isstring(x) && isscalar(x)));
addParameter(p, 'LagsToPlot', [-250 300], @(x)isnumeric(x) && isvector(x) && ~isempty(x));
addParameter(p, 'Alpha', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
addParameter(p, 'MeshReduction', 0.45, @(x)isnumeric(x) && isscalar(x) && x>0 && x<=1);
addParameter(p, 'ROIPatchReduction', 0.65, @(x)isnumeric(x) && isscalar(x) && x>0 && x<=1);
addParameter(p, 'BrainSeparation', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
addParameter(p, 'NodeOutwardOffset', 4.5, @(x)isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'KnowerYaw', -90, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'GuesserYaw', 90, @(x)isnumeric(x) && isscalar(x));
addParameter(p, 'ArcHeight', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
addParameter(p, 'ArcHeightMultiplier', 3.0, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'ArcSpread', 22, @(x)isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'ArcPoints', 80, @(x)isnumeric(x) && isscalar(x) && x>=10 && x==round(x));
addParameter(p, 'LinkWidthRange', [0.8 2.4], @(x)isnumeric(x) && numel(x)==2 && all(x>0));
addParameter(p, 'PositiveLinkColor', [0.86 0.18 0.12], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'NegativeLinkColor', [0.12 0.30 0.86], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'CortexColor', [0.76 0.78 0.80], @(x)isnumeric(x) && numel(x)==3);
addParameter(p, 'CortexAlpha', 0.20, @(x)isnumeric(x) && isscalar(x) && x>=0 && x<=1);
addParameter(p, 'ROIAlpha', 0.78, @(x)isnumeric(x) && isscalar(x) && x>=0 && x<=1);
addParameter(p, 'ShowAllROINodes', true, @(x)islogical(x) && isscalar(x));
addParameter(p, 'ShowROILabels', true, @(x)islogical(x) && isscalar(x));
addParameter(p, 'ShowConnectedLabels', true, @(x)islogical(x) && isscalar(x));
addParameter(p, 'ShowAllROILabels', false, @(x)islogical(x) && isscalar(x));
addParameter(p, 'NodeSize', 24, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'ConnectedNodeSize', 58, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'LabelFontSize', 8, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'LabelRadialOffset', 8.0, @(x)isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'LabelVerticalOffset', 18.0, @(x)isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'RoleLabelVerticalOffset', 42.0, @(x)isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'View', [0 12], @(x)isnumeric(x) && numel(x)==2);
addParameter(p, 'FigurePosition', [40 80 1820 820], @(x)isnumeric(x) && numel(x)==4);
addParameter(p, 'FigureVisible', 'on', @(x)any(strcmpi(string(x), ["on","off"])));
addParameter(p, 'SaveFigures', true, @(x)islogical(x) && isscalar(x));
addParameter(p, 'SaveTables', true, @(x)islogical(x) && isscalar(x));
addParameter(p, 'OutputFolder', '', @(x)ischar(x) || (isstring(x) && isscalar(x)));
addParameter(p, 'FigureFormat', 'png', @(x)any(strcmpi(string(x), ["png","pdf","svg"])));
addParameter(p, 'ExportResolution', 600, @(x)isnumeric(x) && isscalar(x) && x>=72);
addParameter(p, 'Verbose', true, @(x)islogical(x) && isscalar(x));
parse(p, step10bMatFile, varargin{:});
o = p.Results;

step10bMatFile = char(string(step10bMatFile));
figureVisible = char(lower(string(o.FigureVisible)));
figureFormat = char(lower(string(o.FigureFormat)));
requestedLags = double(o.LagsToPlot(:)');
if ~o.ShowROILabels
    o.ShowConnectedLabels = false;
    o.ShowAllROILabels = false;
end

if exist(step10bMatFile, 'file') ~= 2
    error('Step 10b MAT file not found:\n%s', step10bMatFile);
end
if exist('ft_read_atlas', 'file') ~= 2
    error(['ft_read_atlas is not on the MATLAB path. Use the full FieldTrip ', ...
           'installation and run ft_defaults before this function.']);
end

if isempty(o.OutputFolder)
    outputFolder = fullfile(fileparts(step10bMatFile), 'Step10b_B2B_ROI_Pial_Figures');
else
    outputFolder = char(string(o.OutputFolder));
end
if (o.SaveFigures || o.SaveTables) && exist(outputFolder, 'dir') ~= 7
    mkdir(outputFolder);
end


%% 2. Load and validate Step 10b results
S = load(step10bMatFile);
if ~isfield(S, 'spatialData') || ~isstruct(S.spatialData)
    error('The MAT file does not contain a valid spatialData structure.');
end
spatialData = S.spatialData;

requiredFields = {'groupMean','spatialFWERWithinLagPMap','lagsMilliseconds', ...
    'roiLabelsKnower','roiLabelsGuesser','familyWiseAlpha'};
for k = 1:numel(requiredFields)
    if ~isfield(spatialData, requiredFields{k})
        error('spatialData is missing required field: %s', requiredFields{k});
    end
end

roiK = string(spatialData.roiLabelsKnower(:));
roiG = string(spatialData.roiLabelsGuesser(:));
lagsMs = double(spatialData.lagsMilliseconds(:));

if isempty(o.Alpha)
    alpha = double(spatialData.familyWiseAlpha);
else
    alpha = double(o.Alpha);
end

nK = numel(roiK);
nG = numel(roiG);
if size(spatialData.groupMean,1) ~= nK || size(spatialData.groupMean,2) ~= nG
    error('ROI metadata do not match spatialData.groupMean dimensions.');
end

lagIndices = nan(size(requestedLags));
for k = 1:numel(requestedLags)
    idx = find(abs(lagsMs-requestedLags(k)) < 1e-9, 1, 'first');
    if isempty(idx)
        error('Requested lag %g ms is not present in spatialData.lagsMilliseconds.', requestedLags(k));
    end
    lagIndices(k) = idx;
end


%% 3. Read high-resolution fsaverage pial surfaces and atlas labels
fsDir = resolve_fsaverage_local(char(string(o.FsAverageDir)));
requiredFsFiles = { ...
    fullfile(fsDir,'label','lh.aparc.annot'), ...
    fullfile(fsDir,'label','rh.aparc.annot'), ...
    fullfile(fsDir,'surf','lh.pial'), ...
    fullfile(fsDir,'surf','rh.pial')};
for k = 1:numel(requiredFsFiles)
    if exist(requiredFsFiles{k}, 'file') ~= 2
        error('Required fsaverage file not found:\n%s', requiredFsFiles{k});
    end
end

if o.Verbose
    fprintf('Reading high-resolution fsaverage Desikan-Killiany pial surfaces...\n');
end

lh = ft_read_atlas({requiredFsFiles{1}, requiredFsFiles{3}});
rh = ft_read_atlas({requiredFsFiles{2}, requiredFsFiles{4}});

validate_surface_atlas(lh, 'left');
validate_surface_atlas(rh, 'right');


%% 4. Build reusable display geometry
% Base cortical meshes are reduced only for graphics performance. ROI anchor
% locations and parcel membership are always derived from the original
% high-resolution fsaverage surfaces.
baseMeshL = reduce_mesh(lh.pos, lh.tri, o.MeshReduction);
baseMeshR = reduce_mesh(rh.pos, rh.tri, o.MeshReduction);

roiGeomK = build_roi_geometry(roiK, lh, rh, o.ROIPatchReduction, o.NodeOutwardOffset);
roiGeomG = build_roi_geometry(roiG, lh, rh, o.ROIPatchReduction, o.NodeOutwardOffset);

allRegionNames = unique([string({roiGeomK.BaseName})'; string({roiGeomG.BaseName})'], 'stable');
regionColors = pastel_region_colours(numel(allRegionNames));
for k = 1:numel(roiGeomK)
    roiGeomK(k).Color = regionColors(find(allRegionNames==roiGeomK(k).BaseName,1),:);
end
for k = 1:numel(roiGeomG)
    roiGeomG(k).Color = regionColors(find(allRegionNames==roiGeomG(k).BaseName,1),:);
end

allSurfacePos = [double(lh.pos); double(rh.pos)];
brainWidth = max(allSurfacePos(:,1))-min(allSurfacePos(:,1));
brainDepth = max(allSurfacePos(:,2))-min(allSurfacePos(:,2));
brainHeight = max(allSurfacePos(:,3))-min(allSurfacePos(:,3));
brainCentre = mean([min(allSurfacePos,[],1); max(allSurfacePos,[],1)],1);

if isempty(o.BrainSeparation)
    brainSeparation = max(245, 1.55*brainWidth);
else
    brainSeparation = o.BrainSeparation;
end
if isempty(o.ArcHeight)
    arcHeight = max(55, 0.24*brainSeparation);
else
    arcHeight = o.ArcHeight;
end

shiftK = [-brainSeparation/2 0 0] - brainCentre;
shiftG = [ brainSeparation/2 0 0] - brainCentre;


%% 5. Extract only within-lag spatial-FWER significant connections
plotData = repmat(empty_plotdata_struct(), numel(requestedLags), 1);
allAbsEffects = [];
connectionTables = cell(numel(requestedLags),1);

for k = 1:numel(requestedLags)
    L = lagIndices(k);
    effectMatrix = double(spatialData.groupMean(:,:,L));
    pMatrix = double(spatialData.spatialFWERWithinLagPMap(:,:,L));

    % IMPORTANT: the figure uses the spatial FWER p-value map itself as the
    % inferential criterion. Global-across-lag p values are not consulted.
    sigMask = isfinite(pMatrix) & pMatrix <= alpha & isfinite(effectMatrix);

    weightedEffect = effectMatrix .* sigMask;
    signedBinary = zeros(size(effectMatrix));
    signedBinary(sigMask & effectMatrix>0) = 1;
    signedBinary(sigMask & effectMatrix<0) = -1;

    T = make_connection_summary_table(roiK, roiG, effectMatrix, pMatrix, sigMask, requestedLags(k));
    connectionTables{k} = T;

    plotData(k).lagMs = requestedLags(k);
    plotData(k).lagIndex = L;
    plotData(k).groupMeanEffect = effectMatrix;
    plotData(k).spatialFWERWithinLagP = pMatrix;
    plotData(k).significantMask = sigMask;
    plotData(k).weightedEffectMatrix = weightedEffect;
    plotData(k).signedBinaryMatrix = signedBinary;
    plotData(k).significantConnectionTable = T;
    plotData(k).numberSignificantConnections = nnz(sigMask);
    plotData(k).numberYESGreaterNO = nnz(sigMask & effectMatrix>0);
    plotData(k).numberNOGreaterYES = nnz(sigMask & effectMatrix<0);

    vals = abs(effectMatrix(sigMask));
    allAbsEffects = [allAbsEffects; vals(:)]; %#ok<AGROW>
end

if isempty(allAbsEffects)
    widthEffectRange = [0 1];
else
    widthEffectRange = [min(allAbsEffects) max(allAbsEffects)];
    if widthEffectRange(1) == widthEffectRange(2)
        widthEffectRange = [0 widthEffectRange(2)];
    end
end


%% 6. Create panelled dual-brain figure
nPanel = numel(requestedLags);
fig = figure('Color','w', 'Visible',figureVisible, ...
    'Position',o.FigurePosition, 'Name','HyperYESNO significant inter-brain GCMI', ...
    'NumberTitle','off', 'Renderer','opengl');

tl = tiledlayout(fig, 1, nPanel, 'Padding','compact', 'TileSpacing','compact');

panelAxes = gobjects(nPanel,1);
for k = 1:nPanel
    ax = nexttile(tl, k);
    panelAxes(k) = ax;
    hold(ax,'on');

    handles = plot_dual_pial_panel(ax, ...
        baseMeshL, baseMeshR, roiGeomK, roiGeomG, ...
        plotData(k).groupMeanEffect, plotData(k).significantMask, ...
        shiftK, shiftG, widthEffectRange, arcHeight, o, k);

    plotData(k).axesHandle = ax;
    plotData(k).plotHandles = handles;

    if requestedLags(k) < 0
        lagMeaning = 'Knower precedes Guesser';
    elseif requestedLags(k) > 0
        lagMeaning = 'Guesser precedes Knower';
    else
        lagMeaning = 'zero lag';
    end

    title(ax, sprintf(['%+g ms  (%s)\n', ...
        '%d links:  YES>NO = %d,  NO>YES = %d'], ...
        requestedLags(k), lagMeaning, ...
        plotData(k).numberSignificantConnections, ...
        plotData(k).numberYESGreaterNO, ...
        plotData(k).numberNOGreaterYES), ...
        'FontWeight','bold', 'FontSize',11, 'Interpreter','none');

    view(ax, o.View);
    axis(ax,'equal');
    axis(ax,'off');

    % Give all panels the same spatial limits.
    xPad = 0.18*brainWidth;
    yPad = 0.20*brainDepth;
    zPad = max(arcHeight+18, 0.18*brainHeight);
    xlim(ax, [-brainSeparation/2-brainWidth/2-xPad, brainSeparation/2+brainWidth/2+xPad]);
    ylim(ax, [-brainDepth/2-yPad, brainDepth/2+yPad]);
    zlim(ax, [-brainHeight/2-0.15*brainHeight, brainHeight/2+zPad]);

    camlight(ax,'headlight');
    camlight(ax,'right');
    lighting(ax,'gouraud');

    % Compact semantic legend in every panel so each can also be exported or
    % cropped independently without losing its interpretation.
    hYes = plot3(ax,nan,nan,nan,'-','Color',o.PositiveLinkColor,'LineWidth',3.5);
    hNo  = plot3(ax,nan,nan,nan,'-','Color',o.NegativeLinkColor,'LineWidth',3.5);
    hThin = plot3(ax,nan,nan,nan,'-','Color',[0.35 0.35 0.35],'LineWidth',min(o.LinkWidthRange));
    hThick = plot3(ax,nan,nan,nan,'-','Color',[0.35 0.35 0.35],'LineWidth',max(o.LinkWidthRange));
    lg = legend(ax,[hYes hNo hThin hThick], ...
        {'YES > NO','NO > YES','smaller |YES-NO|','larger |YES-NO|'}, ...
        'Location','southoutside','Orientation','horizontal','Box','off','FontSize',8);
    lg.Interpreter = 'none';
end

sgtitle(tl, sprintf(['HyperYESNO: surrogate-corrected lagged GCMI, YES - NO\n', ...
    'Only within-lag spatial FWER significant connections (p <= %.3f)'], alpha), ...
    'FontWeight','bold','FontSize',13,'Interpreter','none');

annotation(fig,'textbox',[0.02 0.005 0.96 0.045], ...
    'String',['Left brain = Knower ROI; right brain = Guesser ROI. ', ...
              'Curved links indicate significant inter-brain ROI pairs, not causal direction. ', ...
              'Line width is scaled to |group mean YES-NO surrogate-corrected GCMI| across all displayed panels.'], ...
    'HorizontalAlignment','center','VerticalAlignment','middle', ...
    'EdgeColor','none','FontSize',8,'Interpreter','none');


%% 7. Save figure and result table
savedFigureFile = "";
if o.SaveFigures
    lagText = strjoin(arrayfun(@(x)sprintf('%+gms',x),requestedLags,'UniformOutput',false),'_');
    lagText = regexprep(lagText,'\+','plus');
    lagText = regexprep(lagText,'-','minus');
    savedFigureFile = string(fullfile(outputFolder, ...
        sprintf('Step10b_B2B_pial_spatialFWER_%s.%s',lagText,figureFormat)));

    if strcmpi(figureFormat,'png')
        exportgraphics(fig, char(savedFigureFile), 'Resolution',o.ExportResolution);
    else
        % Rasterising high-density pial meshes keeps PDF/SVG file size and
        % export time manageable while retaining the requested resolution.
        exportgraphics(fig, char(savedFigureFile), 'ContentType','image', ...
            'Resolution',o.ExportResolution);
    end
end

nonEmpty = ~cellfun(@isempty, connectionTables);
if any(nonEmpty)
    combinedConnectionTable = vertcat(connectionTables{nonEmpty});
else
    combinedConnectionTable = table();
end

savedTableFile = "";
if o.SaveTables
    savedTableFile = string(fullfile(outputFolder, ...
        'Step10b_B2B_pial_spatialFWER_significant_connections.csv'));
    if isempty(combinedConnectionTable)
        Tempty = table("No significant connections at requested lags", ...
            'VariableNames',{'Message'});
        writetable(Tempty, char(savedTableFile));
    else
        writetable(combinedConnectionTable, char(savedTableFile));
    end
end

for k = 1:numel(plotData)
    plotData(k).figureHandle = fig;
    plotData(k).savedFigureFile = savedFigureFile;
end


%% 8. Summary output and console report
roiColourTable = table(allRegionNames, regionColors(:,1), regionColors(:,2), regionColors(:,3), ...
    'VariableNames',{'ROIBaseName','R','G','B'});

summaryStruct = struct();
summaryStruct.step10bFile = string(step10bMatFile);
summaryStruct.fsAverageDir = string(fsDir);
summaryStruct.alpha = alpha;
summaryStruct.inferenceUsedForPlot = "spatialFWERWithinLagPMap only";
summaryStruct.globalAcrossLagsFWERUsed = false;
summaryStruct.requestedLagsMs = requestedLags;
summaryStruct.lagIndices = lagIndices;
summaryStruct.roiLabelsKnower = roiK;
summaryStruct.roiLabelsGuesser = roiG;
summaryStruct.roiGeometryKnower = roiGeomK;
summaryStruct.roiGeometryGuesser = roiGeomG;
summaryStruct.roiColourTable = roiColourTable;
summaryStruct.effectWidthRange = widthEffectRange;
summaryStruct.lineWidthRange = o.LinkWidthRange;
summaryStruct.brainSeparation = brainSeparation;
summaryStruct.arcHeight = arcHeight;
summaryStruct.meshReduction = o.MeshReduction;
summaryStruct.roiPatchReduction = o.ROIPatchReduction;
summaryStruct.combinedSignificantConnectionTable = combinedConnectionTable;
summaryStruct.figureHandle = fig;
summaryStruct.panelAxes = panelAxes;
summaryStruct.savedFigureFile = savedFigureFile;
summaryStruct.savedConnectionTableFile = savedTableFile;
summaryStruct.created = string(datestr(now,30));
summaryStruct.functionName = string(mfilename);

if o.Verbose
    fprintf('\n============================================================\n');
    fprintf('Step10b dual-pial brain figure completed.\n');
    fprintf('Inference used: within-lag spatial FWER p <= %.3f ONLY\n',alpha);
    for k = 1:numel(plotData)
        fprintf('\nLag %+g ms\n',plotData(k).lagMs);
        fprintf('  Significant connections: %d\n',plotData(k).numberSignificantConnections);
        fprintf('  YES > NO:                %d\n',plotData(k).numberYESGreaterNO);
        fprintf('  NO > YES:                %d\n',plotData(k).numberNOGreaterYES);
        if ~isempty(plotData(k).significantConnectionTable)
            disp(plotData(k).significantConnectionTable(:, ...
                {'KnowerROI','GuesserROI','MeanSurrogateCorrectedYESminusNO', ...
                 'SpatialFWERWithinLagP','Direction'}));
        end
    end
    if o.SaveFigures
        fprintf('\nFigure: %s\n',char(savedFigureFile));
    end
    if o.SaveTables
        fprintf('Table:  %s\n',char(savedTableFile));
    end
    fprintf('============================================================\n');
end

end


%% ========================================================================
function out = empty_plotdata_struct()
out = struct( ...
    'lagMs',[], ...
    'lagIndex',[], ...
    'groupMeanEffect',[], ...
    'spatialFWERWithinLagP',[], ...
    'significantMask',[], ...
    'weightedEffectMatrix',[], ...
    'signedBinaryMatrix',[], ...
    'significantConnectionTable',table(), ...
    'numberSignificantConnections',0, ...
    'numberYESGreaterNO',0, ...
    'numberNOGreaterYES',0, ...
    'axesHandle',[], ...
    'plotHandles',struct(), ...
    'figureHandle',[], ...
    'savedFigureFile',"");
end


%% ========================================================================
function fsDir = resolve_fsaverage_local(fsDir)
if ~isempty(strtrim(fsDir))
    if exist(fsDir,'dir')~=7
        error('The supplied FsAverageDir does not exist:\n%s',fsDir);
    end
    return
end

subjectsDir = getenv('SUBJECTS_DIR');
if ~isempty(subjectsDir)
    candidate = fullfile(subjectsDir,'fsaverage');
    if exist(candidate,'dir')==7
        fsDir = candidate;
        return
    end
end

fsHome = getenv('FREESURFER_HOME');
if ~isempty(fsHome)
    candidate = fullfile(fsHome,'subjects','fsaverage');
    if exist(candidate,'dir')==7
        fsDir = candidate;
        return
    end
end

error(['Could not locate fsaverage. Supply it explicitly, for example: ', ...
    '''FsAverageDir'',''E:\EEG_data_HyperYESNO\fsaverage''']);
end


%% ========================================================================
function validate_surface_atlas(atlas, hemiName)
if ~isfield(atlas,'pos') || ~isfield(atlas,'tri')
    error('The %s fsaverage surface does not contain pos and tri.',hemiName);
end
[parcelField,labelField] = detect_surface_parcellation_fields_local(atlas); %#ok<ASGLU>
if isempty(parcelField) || isempty(labelField)
    error('Could not identify the parcellation in the %s atlas.',hemiName);
end
end


%% ========================================================================
function mesh = reduce_mesh(pos,tri,fraction)
mesh = struct();
if fraction >= 0.999
    mesh.vertices = double(pos);
    mesh.faces = double(tri);
else
    P = struct('vertices',double(pos),'faces',double(tri));
    R = reducepatch(P,fraction);
    mesh.vertices = double(R.vertices);
    mesh.faces = double(R.faces);
end
end


%% ========================================================================
function geom = build_roi_geometry(roiLabels,lh,rh,patchReduction,nodeOffset)
% Derive a surface anchor and a display patch for every selected DK parcel.

[lhParcelField,lhLabelField] = detect_surface_parcellation_fields_local(lh);
[rhParcelField,rhLabelField] = detect_surface_parcellation_fields_local(rh);

lhParcel = double(lh.(lhParcelField)(:));
rhParcel = double(rh.(rhParcelField)(:));
lhLabels = string(lh.(lhLabelField)(:));
rhLabels = string(rh.(rhLabelField)(:));

lhTri = double(lh.tri);
rhTri = double(rh.tri);
lhParcelTri = [lhParcel(lhTri(:,1)) lhParcel(lhTri(:,2)) lhParcel(lhTri(:,3))];
rhParcelTri = [rhParcel(rhTri(:,1)) rhParcel(rhTri(:,2)) rhParcel(rhTri(:,3))];

wholePos = [double(lh.pos);double(rh.pos)];
wholeCentre = mean([min(wholePos,[],1);max(wholePos,[],1)],1);

geom = repmat(struct('Label',"",'Hemisphere',"",'DKLabel',"",'BaseName',"", ...
    'AtlasParcelIndex',NaN,'Anchor',[NaN NaN NaN],'PatchVertices',[], ...
    'PatchFaces',[],'Color',[0.7 0.7 0.7]),numel(roiLabels),1);

for r = 1:numel(roiLabels)
    projectLabel = string(roiLabels(r));
    [hemi,dkLabel,baseName] = hyperyesno_to_dk_label_local(projectLabel);

    if hemi == "L"
        atlasLabels = lhLabels;
        parcel = lhParcel;
        pos = double(lh.pos);
        tri = lhTri;
        parcelTri = lhParcelTri;
    else
        atlasLabels = rhLabels;
        parcel = rhParcel;
        pos = double(rh.pos);
        tri = rhTri;
        parcelTri = rhParcelTri;
    end

    idx = find_normalized_label_local(dkLabel,atlasLabels);
    if isempty(idx)
        error('Could not find Desikan-Killiany parcel %s for ROI %s.',dkLabel,projectLabel);
    end

    vertexMask = parcel==idx;
    vertexIndices = find(vertexMask);
    if isempty(vertexIndices)
        error('No fsaverage vertices were found for ROI %s.',projectLabel);
    end

    parcelCentroid = mean(pos(vertexIndices,:),1);
    d2 = sum((pos(vertexIndices,:)-parcelCentroid).^2,2);
    [~,ii] = min(d2);
    anchor = pos(vertexIndices(ii),:);

    outward = anchor-wholeCentre;
    if norm(outward)>0
        anchor = anchor + nodeOffset*(outward./norm(outward));
    end

    faceMask = all(parcelTri==idx,2);
    parcelFaces = tri(faceMask,:);
    if isempty(parcelFaces)
        error('No cortical faces were found for ROI %s.',projectLabel);
    end

    parcelMesh = extract_submesh(pos,parcelFaces);
    if patchReduction < 0.999 && size(parcelMesh.faces,1)>20
        parcelMesh = reduce_mesh(parcelMesh.vertices,parcelMesh.faces,patchReduction);
    end

    geom(r).Label = projectLabel;
    geom(r).Hemisphere = hemi;
    geom(r).DKLabel = dkLabel;
    geom(r).BaseName = baseName;
    geom(r).AtlasParcelIndex = idx;
    geom(r).Anchor = anchor;
    geom(r).PatchVertices = parcelMesh.vertices;
    geom(r).PatchFaces = parcelMesh.faces;
end
end


%% ========================================================================
function mesh = extract_submesh(pos,faces)
used = unique(faces(:));
map = zeros(size(pos,1),1);
map(used) = 1:numel(used);
mesh.vertices = pos(used,:);
mesh.faces = map(faces);
end


%% ========================================================================
function colours = pastel_region_colours(n)
% Muted categorical colours keep the vivid red/blue statistical links
% visually dominant while still making the selected parcels separable.
if n<=0
    colours = zeros(0,3);
    return
end
h = linspace(0,1,n+1)';
h(end) = [];
s = 0.34*ones(n,1);
v = 0.88*ones(n,1);
colours = hsv2rgb([h s v]);
end


%% ========================================================================
function handles = plot_dual_pial_panel(ax,baseL,baseR,geomK,geomG,effectMatrix,sigMask, ...
    shiftK,shiftG,widthEffectRange,arcHeight,o,panelIndex)

handles = struct();

% ----- Transform brains so that they face each other -----
baseLK = transform_mesh_local(baseL, o.KnowerYaw, shiftK);
baseRK = transform_mesh_local(baseR, o.KnowerYaw, shiftK);
baseLG = transform_mesh_local(baseL, o.GuesserYaw, shiftG);
baseRG = transform_mesh_local(baseR, o.GuesserYaw, shiftG);
geomKp = transform_geom_local(geomK, o.KnowerYaw, shiftK);
geomGp = transform_geom_local(geomG, o.GuesserYaw, shiftG);

% ----- Base cortical surfaces: Knower -----
hBaseK(1) = patch(ax,'Vertices',baseLK.vertices,'Faces',baseLK.faces, ...
    'FaceColor',o.CortexColor,'FaceAlpha',o.CortexAlpha,'EdgeColor','none', ...
    'AmbientStrength',0.45,'DiffuseStrength',0.65,'SpecularStrength',0.06);
hBaseK(2) = patch(ax,'Vertices',baseRK.vertices,'Faces',baseRK.faces, ...
    'FaceColor',o.CortexColor,'FaceAlpha',o.CortexAlpha,'EdgeColor','none', ...
    'AmbientStrength',0.45,'DiffuseStrength',0.65,'SpecularStrength',0.06);

% ----- Base cortical surfaces: Guesser -----
hBaseG(1) = patch(ax,'Vertices',baseLG.vertices,'Faces',baseLG.faces, ...
    'FaceColor',o.CortexColor,'FaceAlpha',o.CortexAlpha,'EdgeColor','none', ...
    'AmbientStrength',0.45,'DiffuseStrength',0.65,'SpecularStrength',0.06);
hBaseG(2) = patch(ax,'Vertices',baseRG.vertices,'Faces',baseRG.faces, ...
    'FaceColor',o.CortexColor,'FaceAlpha',o.CortexAlpha,'EdgeColor','none', ...
    'AmbientStrength',0.45,'DiffuseStrength',0.65,'SpecularStrength',0.06);

% ----- Overlay the selected Desikan-Killiany parcels -----
hParcelK = gobjects(numel(geomKp),1);
for r = 1:numel(geomKp)
    hParcelK(r) = patch(ax,'Vertices',geomKp(r).PatchVertices, ...
        'Faces',geomK(r).PatchFaces,'FaceColor',geomK(r).Color, ...
        'FaceAlpha',o.ROIAlpha,'EdgeColor','none', ...
        'AmbientStrength',0.45,'DiffuseStrength',0.72,'SpecularStrength',0.08);
end

hParcelG = gobjects(numel(geomGp),1);
for r = 1:numel(geomGp)
    hParcelG(r) = patch(ax,'Vertices',geomGp(r).PatchVertices, ...
        'Faces',geomG(r).PatchFaces,'FaceColor',geomG(r).Color, ...
        'FaceAlpha',o.ROIAlpha,'EdgeColor','none', ...
        'AmbientStrength',0.45,'DiffuseStrength',0.72,'SpecularStrength',0.08);
end

% ----- Determine connected ROIs -----
connectedK = any(sigMask,2);
connectedG = any(sigMask,1)';

% ----- ROI nodes -----
hNodesK = gobjects(numel(geomKp),1);
hNodesG = gobjects(numel(geomGp),1);
for r = 1:numel(geomKp)
    if o.ShowAllROINodes || connectedK(r)
        p = geomKp(r).Anchor;
        if connectedK(r), sz=o.ConnectedNodeSize; else, sz=o.NodeSize; end
        hNodesK(r) = scatter3(ax,p(1),p(2),p(3),sz,geomKp(r).Color,'filled', ...
            'MarkerEdgeColor',[0.15 0.15 0.15],'LineWidth',0.7);
    end
end
for r = 1:numel(geomGp)
    if o.ShowAllROINodes || connectedG(r)
        p = geomGp(r).Anchor;
        if connectedG(r), sz=o.ConnectedNodeSize; else, sz=o.NodeSize; end
        hNodesG(r) = scatter3(ax,p(1),p(2),p(3),sz,geomGp(r).Color,'filled', ...
            'MarkerEdgeColor',[0.15 0.15 0.15],'LineWidth',0.7);
    end
end

% ----- Curved inter-brain links -----
[I,J] = find(sigMask);
nLink = numel(I);
hLinks = gobjects(nLink,1);
for q = 1:nLink
    i = I(q); j = J(q);
    effect = effectMatrix(i,j);
    p0 = geomKp(i).Anchor;
    p3 = geomGp(j).Anchor;

    width = effect_to_width(abs(effect),widthEffectRange,o.LinkWidthRange);
    if effect>=0
        colour = o.PositiveLinkColor;
    else
        colour = o.NegativeLinkColor;
    end

    % Deterministic lateral spread makes overlapping arcs easier to follow.
    % The panel index is included so that exactly overlapping connections in
    % separate panels are not artificially jittered in an identical visual
    % sequence when link counts differ.
    if nLink>1
        phase = 2*pi*(q-1)/nLink + 0.17*(panelIndex-1);
        lateral = o.ArcSpread*sin(phase);
    else
        lateral = 0;
    end

    xyz = cubic_bezier_arc(p0,p3,arcHeight,lateral,o.ArcPoints);
    hLinks(q) = plot3(ax,xyz(:,1),xyz(:,2),xyz(:,3),'-', ...
        'Color',colour,'LineWidth',width);
end

% ----- Labels -----
if o.ShowConnectedLabels || o.ShowAllROILabels
    label_roi_nodes(ax,geomKp,connectedK,o,'K');
    label_roi_nodes(ax,geomGp,connectedG,o,'G');
end

% ----- Role labels above the brains -----
allK = reshape([geomKp.Anchor],3,[])';
allG = reshape([geomGp.Anchor],3,[])';
text(ax,mean(allK(:,1)),mean(allK(:,2)),max(allK(:,3))+o.RoleLabelVerticalOffset,'KNOWER', ...
    'FontWeight','bold','HorizontalAlignment','center','FontSize',10, ...
    'BackgroundColor','w','Margin',2,'Interpreter','none');
text(ax,mean(allG(:,1)),mean(allG(:,2)),max(allG(:,3))+o.RoleLabelVerticalOffset,'GUESSER', ...
    'FontWeight','bold','HorizontalAlignment','center','FontSize',10, ...
    'BackgroundColor','w','Margin',2,'Interpreter','none');

handles.baseKnower = hBaseK;
handles.baseGuesser = hBaseG;
handles.parcelsKnower = hParcelK;
handles.parcelsGuesser = hParcelG;
handles.nodesKnower = hNodesK;
handles.nodesGuesser = hNodesG;
handles.links = hLinks;
end


%% ========================================================================
function width = effect_to_width(absEffect,effectRange,widthRange)
loE = effectRange(1); hiE = effectRange(2);
loW = min(widthRange); hiW = max(widthRange);
if hiE<=loE || ~isfinite(absEffect)
    width = mean([loW hiW]);
else
    fraction = (absEffect-loE)/(hiE-loE);
    fraction = min(max(fraction,0),1);
    width = loW + fraction*(hiW-loW);
end
end


%% ========================================================================
function xyz = cubic_bezier_arc(p0,p3,height,lateral,nPoints)
% Cubic Bezier link with an elevated midpoint and a lateral Y displacement.
% Both control points are raised in Z, producing a smooth bridge-like arc.

delta = p3-p0;
p1 = p0 + 0.32*delta + [0 lateral height];
p2 = p0 + 0.68*delta + [0 lateral height];

t = linspace(0,1,nPoints)';
oneMinus = 1-t;
xyz = (oneMinus.^3).*p0 + ...
      (3*(oneMinus.^2).*t).*p1 + ...
      (3*oneMinus.*(t.^2)).*p2 + ...
      (t.^3).*p3;
end


%% ========================================================================
function label_roi_nodes(ax,geom,connected,o,prefix)
for r = 1:numel(geom)
    show = o.ShowAllROILabels || (o.ShowConnectedLabels && connected(r));
    if ~show
        continue
    end
    p = geom(r).Anchor;
    outward = p;
    outward(3) = outward(3) + o.LabelVerticalOffset;
    if norm(outward)>0
        offset = o.LabelRadialOffset*outward./norm(outward);
    else
        offset = [0 0 o.LabelRadialOffset];
    end
    labelPos = p + offset + [0 0 o.LabelVerticalOffset];
    text(ax,labelPos(1),labelPos(2),labelPos(3),char(geom(r).Label), ...
        'FontSize',o.LabelFontSize,'FontWeight','bold','Color',[0.10 0.10 0.10], ...
        'BackgroundColor',[1 1 1],'Margin',1.0, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'Interpreter','none','Tag',['ROIlabel_' prefix]);
end
end

%% ========================================================================
function meshOut = transform_mesh_local(meshIn, yawDeg, shiftVec)
meshOut = meshIn;
meshOut.vertices = rotate_points_z_local(meshIn.vertices, yawDeg) + shiftVec;
end


%% ========================================================================
function geomOut = transform_geom_local(geomIn, yawDeg, shiftVec)
geomOut = geomIn;
for ii = 1:numel(geomIn)
    geomOut(ii).PatchVertices = rotate_points_z_local(geomIn(ii).PatchVertices, yawDeg) + shiftVec;
    geomOut(ii).Anchor = rotate_points_z_local(geomIn(ii).Anchor, yawDeg) + shiftVec;
end
end


%% ========================================================================
function ptsOut = rotate_points_z_local(ptsIn, yawDeg)
R = [cosd(yawDeg) -sind(yawDeg) 0; sind(yawDeg) cosd(yawDeg) 0; 0 0 1];
ptsOut = ptsIn * R.';
end


%% ========================================================================
function T = make_connection_summary_table(roiK,roiG,effectMatrix,pMatrix,sigMask,lagMs)
[I,J] = find(sigMask);
if isempty(I)
    T = table();
    return
end

n = numel(I);
KnowerROI = strings(n,1);
GuesserROI = strings(n,1);
MeanEffect = nan(n,1);
P = nan(n,1);
Direction = strings(n,1);

for q = 1:n
    KnowerROI(q) = roiK(I(q));
    GuesserROI(q) = roiG(J(q));
    MeanEffect(q) = effectMatrix(I(q),J(q));
    P(q) = pMatrix(I(q),J(q));
    if MeanEffect(q)>0
        Direction(q) = "YES > NO";
    elseif MeanEffect(q)<0
        Direction(q) = "NO > YES";
    else
        Direction(q) = "zero effect";
    end
end

T = table(repmat(lagMs,n,1),I,KnowerROI,J,GuesserROI,MeanEffect,P,Direction, ...
    'VariableNames',{'LagMs','KnowerROIIndex','KnowerROI','GuesserROIIndex', ...
    'GuesserROI','MeanSurrogateCorrectedYESminusNO','SpatialFWERWithinLagP','Direction'});

[~,ord] = sort(abs(T.MeanSurrogateCorrectedYESminusNO),'descend');
T = T(ord,:);
end


%% ========================================================================
function [parcelField,labelField] = detect_surface_parcellation_fields_local(atlas)
parcelField = '';
labelField = '';

if isfield(atlas,'aparc') && isfield(atlas,'aparclabel')
    parcelField = 'aparc';
    labelField = 'aparclabel';
    return
end

fn = fieldnames(atlas);
nVert = size(atlas.pos,1);
for k = 1:numel(fn)
    f = fn{k};
    if endsWith(f,'label')
        continue
    end
    v = atlas.(f);
    candidate = [f 'label'];
    if isnumeric(v) && isvector(v) && numel(v)==nVert && isfield(atlas,candidate)
        labels = atlas.(candidate);
        if iscell(labels) || isstring(labels)
            parcelField = f;
            labelField = candidate;
            return
        end
    end
end
error('Could not identify FreeSurfer surface parcellation fields.');
end


%% ========================================================================
function [hemisphere,dkLabel,baseName] = hyperyesno_to_dk_label_local(projectLabel)
projectLabel = string(projectLabel);

if startsWith(projectLabel,"L_",'IgnoreCase',true)
    hemisphere = "L";
    baseName = extractAfter(projectLabel,2);
elseif startsWith(projectLabel,"R_",'IgnoreCase',true)
    hemisphere = "R";
    baseName = extractAfter(projectLabel,2);
else
    error('ROI label must start with L_ or R_: %s',projectLabel);
end

switch lower(baseName)
    case "ifgop"
        dkLabel = "parsopercularis";
    case "ifgtri"
        dkLabel = "parstriangularis";
    case "stg"
        dkLabel = "superiortemporal";
    case "mtg"
        dkLabel = "middletemporal";
    case "heschl"
        dkLabel = "transversetemporal";
    case "smg"
        dkLabel = "supramarginal";
    case "ipl"
        dkLabel = "inferiorparietal";
    case "precentral"
        dkLabel = "precentral";
    case "rostralmfg"
        dkLabel = "rostralmiddlefrontal";
    case "precuneus"
        dkLabel = "precuneus";
    otherwise
        error('No Desikan-Killiany mapping is defined for ROI %s.',projectLabel);
end
end


%% ========================================================================
function idx = find_normalized_label_local(target,labels)
target = normalize_label_local(target);
normalized = strings(size(labels));
for k = 1:numel(labels)
    normalized(k) = normalize_label_local(labels(k));
end
idx = find(normalized==target,1,'first');
end

function s = normalize_label_local(s)
s = lower(string(s));
s = regexprep(s,'^(ctx[-_]?lh[-_]?|ctx[-_]?rh[-_]?|lh[-_]|rh[-_])','');
s = regexprep(s,'[^a-z0-9]','');
end
