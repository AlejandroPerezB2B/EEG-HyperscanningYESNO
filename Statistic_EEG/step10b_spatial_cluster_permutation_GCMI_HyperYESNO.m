function [spatialData, clusterTable, roiNeighbourTable, qcTable] = ...
    step10b_spatial_cluster_permutation_GCMI_HyperYESNO(rootDir, varargin)
% STEP10B_SPATIAL_CLUSTER_PERMUTATION_GCMI_HYPERYESNO
% Spatial cluster-based permutation analysis of the surrogate-corrected
% YES-minus-NO lagged GCMI effect in HyperYESNO.
%
% This is an alternative/complementary analysis to the existing Step 10.
% It does not modify Step 10.
%
% INPUT EFFECT
% ------------
% The function uses step9Data.yesMinusNoPrimary:
%
%   0.5 * [(YES_AKnower - NO_AKnower) + ...
%          (YES_BKnower - NO_BKnower)]
%
% The statistical unit is the DYAD.
%
% SPATIAL CLUSTERING
% ------------------
% Lags are analysed separately. A cluster can never extend from one lag to
% another.
%
% Two Desikan-Killiany ROIs are neighbours only when their cortical parcels
% share a boundary on the FreeSurfer fsaverage cortical surface. The
% boundary relation is derived directly from the triangular mesh: two
% parcels are adjacent when at least one mesh edge has one endpoint in each
% parcel.
%
% Conservative endpoint-wise adjacency is then used for inter-brain
% connections. For a connection (Knower ROI i, Guesser ROI j):
%
%   (i,j) ~ (k,j) when i and k are neighbouring Knower ROIs
%   (i,j) ~ (i,l) when j and l are neighbouring Guesser ROIs
%
% Connections for which BOTH endpoints change are not directly adjacent.
%
% PERMUTATION INFERENCE
% ---------------------
% At each lag independently:
%   1) calculate a one-sample t statistic against zero for all 400 edges;
%   2) threshold the t map using a two-sided cluster-forming alpha;
%   3) form positive and negative spatial clusters using edge adjacency;
%   4) define cluster mass as abs(sum(t));
%   5) sign-flip complete dyad maps under the null.
%
% Two corrected p values are reported for every observed cluster:
%
% SpatialFWERWithinLagP
%   Corrects across all inter-brain connections at that specific lag.
%
% GlobalFWERAcrossLagsP
%   Uses the maximum spatial cluster mass across all independently analysed
%   lags for each permutation. Lags still do NOT form clusters together;
%   this simply corrects for inspecting the full lag set.
%
% The latter is the more conservative value for an exploratory lag search.
%
% FREESURFER / FIELDTRIP REQUIREMENTS
% ----------------------------------
% The first run requires FieldTrip and a FreeSurfer fsaverage directory
% containing:
%
%   label/lh.aparc.annot
%   label/rh.aparc.annot
%   surf/lh.pial
%   surf/rh.pial
%
% FieldTrip reads these with ft_read_atlas. The resulting ROI adjacency is
% cached in Group_GCMI so later runs do not need to reread the surfaces.
%
% INPUTS
% ------
% rootDir
%   Default: 'E:\EEG_data_HyperYESNO'
%
% NAME-VALUE OPTIONS
% ------------------
% 'Step9File'            default Group_GCMI/Step9_HyperYESNO_...
% 'FsAverageDir'         default '' (auto-detect environment variables)
% 'AdjacencyCacheFile'   default Group_GCMI/HyperYESNO_DK20_...
% 'NumPermutations'      default 10000
% 'ClusterFormingAlpha'  default 0.05
% 'FamilyWiseAlpha'      default 0.05
% 'RandomSeed'           default 20260807
% 'PermutationBatchSize' default 200
% 'MinimumDyads'         default 10
% 'SaveOutputs'          default true
% 'SaveFigures'          default true
% 'FigureVisible'        default 'off'
% 'FigureFormat'         default 'png'
% 'Verbose'              default true
%
% EXAMPLE
% -------
% [spatialData, clusterTable, roiNeighbourTable, qcTable] = ...
%     step10b_spatial_cluster_permutation_GCMI_HyperYESNO( ...
%     'E:\EEG_data_HyperYESNO', ...
%     'FsAverageDir', 'C:\path\to\freesurfer\subjects\fsaverage');
%
% Author: Alejandro Perez
% HyperYESNO project, 2026

%% 1. Inputs
if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end
rootDir = char(string(rootDir));

groupFolder = fullfile(rootDir, 'Group_GCMI');
defaultStep9File = fullfile(groupFolder, ...
    'Step9_HyperYESNO_surrogate_corrected_GCMI.mat');
defaultCacheFile = fullfile(groupFolder, ...
    'HyperYESNO_DK20_surface_boundary_adjacency.mat');

p = inputParser;
p.FunctionName = mfilename;
addRequired(p,'rootDir',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'Step9File',defaultStep9File,@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'FsAverageDir','',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'AdjacencyCacheFile',defaultCacheFile,@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'NumPermutations',10000,@(x)isnumeric(x)&&isscalar(x)&&x>=1&&x==round(x));
addParameter(p,'ClusterFormingAlpha',0.05,@(x)isnumeric(x)&&isscalar(x)&&x>0&&x<1);
addParameter(p,'FamilyWiseAlpha',0.05,@(x)isnumeric(x)&&isscalar(x)&&x>0&&x<1);
addParameter(p,'RandomSeed',20260807,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x==round(x));
addParameter(p,'PermutationBatchSize',200,@(x)isnumeric(x)&&isscalar(x)&&x>=1&&x==round(x));
addParameter(p,'MinimumDyads',10,@(x)isnumeric(x)&&isscalar(x)&&x>=2&&x==round(x));
addParameter(p,'SaveOutputs',true,@(x)islogical(x)&&isscalar(x));
addParameter(p,'SaveFigures',true,@(x)islogical(x)&&isscalar(x));
addParameter(p,'FigureVisible','off',@(x)any(strcmpi(string(x),["on","off"])));
addParameter(p,'FigureFormat','png',@(x)any(strcmpi(string(x),["png","pdf","svg"])));
addParameter(p,'Verbose',true,@(x)islogical(x)&&isscalar(x));
parse(p,rootDir,varargin{:});
o = p.Results;

step9File = char(string(o.Step9File));
cacheFile = char(string(o.AdjacencyCacheFile));
figureVisible = char(lower(string(o.FigureVisible)));
figureFormat = char(lower(string(o.FigureFormat)));

if (o.SaveOutputs || o.SaveFigures) && ~exist(groupFolder,'dir')
    mkdir(groupFolder);
end
figureFolder = fullfile(groupFolder,'Step10b_Spatial_Figures');
if o.SaveFigures && ~exist(figureFolder,'dir')
    mkdir(figureFolder);
end

%% 2. Load Step 9
if exist(step9File,'file') ~= 2
    error('step10b:MissingStep9File','Step 9 file not found:\n%s',step9File);
end
S = load(step9File);
if ~isfield(S,'step9Data') || ~isstruct(S.step9Data)
    error('step10b:MissingStep9Data','No valid step9Data structure found.');
end
step9Data = S.step9Data;
if isfield(S,'dyadTable'), sourceStep9DyadTable = S.dyadTable; else, sourceStep9DyadTable = table(); end
if isfield(S,'qcTable'), sourceStep9QCTable = S.qcTable; else, sourceStep9QCTable = table(); end
clear S

req = {'yesMinusNoPrimary','validPrimaryContrast','dyadNumbers', ...
    'roiLabelsKnower','roiLabelsGuesser','lagsSamples','lagsMilliseconds', ...
    'samplingRate','primaryContrastDefinition','lagConvention'};
missing = req(~isfield(step9Data,req));
if ~isempty(missing)
    error('step10b:MissingFields','Missing Step 9 field(s): %s',strjoin(string(missing),', '));
end

X = double(step9Data.yesMinusNoPrimary);
sz = size4(X);
nK = sz(1); nG = sz(2); nLag = sz(3); nAllDyad = sz(4);
dyadNumbers = double(step9Data.dyadNumbers(:)');
validPrimary = logical(step9Data.validPrimaryContrast(:));
roiK = string(step9Data.roiLabelsKnower(:));
roiG = string(step9Data.roiLabelsGuesser(:));
lagsMs = double(step9Data.lagsMilliseconds(:)');
lagsSamples = double(step9Data.lagsSamples(:)');

if numel(dyadNumbers)~=nAllDyad || numel(validPrimary)~=nAllDyad
    error('step10b:DyadMismatch','Dyad metadata do not match data dimensions.');
end
if numel(roiK)~=nK || numel(roiG)~=nG
    error('step10b:ROIMismatch','ROI labels do not match data dimensions.');
end
if numel(lagsMs)~=nLag || numel(lagsSamples)~=nLag || any(diff(lagsMs)<=0)
    error('step10b:LagMismatch','Lag metadata are inconsistent.');
end

%% 3. Complete dyads
finiteDyad = false(nAllDyad,1);
for d = 1:nAllDyad
    finiteDyad(d) = all(isfinite(X(:,:,:,d)),'all');
end
analysisMask = validPrimary & finiteDyad;
analysisDyadNumbers = dyadNumbers(analysisMask);
nDyad = sum(analysisMask);

qcRows = struct([]);
for d = 1:nAllDyad
    if ~validPrimary(d)
        qcRows = add_qc(qcRows,dyadNumbers(d),'PrimaryContrastUnavailable', ...
            'Step 9 did not provide a valid primary YES-minus-NO contrast.');
    elseif ~finiteDyad(d)
        qcRows = add_qc(qcRows,dyadNumbers(d),'NonfinitePrimaryContrast', ...
            'The primary contrast contained nonfinite values.');
    end
end
if nDyad < o.MinimumDyads
    error('step10b:TooFewDyads','Only %d complete dyads were available.',nDyad);
end
X = X(:,:,:,analysisMask);

%% 4. Anatomical ROI adjacency from fsaverage Desikan-Killiany
[roiAdjK,roiAdjG,roiNeighbourTable,adjacencyProvenance] = ...
    obtain_adjacency(roiK,roiG,char(string(o.FsAverageDir)),cacheFile,o.Verbose);

%% 5. Conservative endpoint-wise connection adjacency
[edgeAdj,edgeTable,edgeNeighbours] = build_edge_adjacency(roiAdjK,roiAdjG,roiK,roiG);
nEdge = height(edgeTable);
if nEdge ~= nK*nG
    error('step10b:EdgeCount','Unexpected inter-brain edge count.');
end

%% 6. Data matrix and observed t statistics
% MATLAB column-major edge indexing: edge = i + (j-1)*nK.
edgeLagDyad = reshape(X,nEdge,nLag,nDyad);
dataMatrix = reshape(edgeLagDyad,nEdge*nLag,nDyad);
sumX = sum(dataMatrix,2);
sumSq = sum(dataMatrix.^2,2);
[tVec,meanVec,sdVec] = one_sample_t_from_sums(sumX,sumSq,nDyad);
semVec = sdVec./sqrt(nDyad);

tEdgeLag = reshape(tVec,nEdge,nLag);
meanEdgeLag = reshape(meanVec,nEdge,nLag);
tMap = reshape(tVec,nK,nG,nLag);
meanMap = reshape(meanVec,nK,nG,nLag);
sdMap = reshape(sdVec,nK,nG,nLag);
semMap = reshape(semVec,nK,nG,nLag);
df = nDyad-1;
pointwiseP = student_t_two_sided_p(tMap,df);
tCrit = student_t_two_sided_critical(o.ClusterFormingAlpha,df);

%% 7. Observed spatial clusters, separately at each lag
obsClusters = struct([]);
obsMaxByLag = zeros(1,nLag);
for L = 1:nLag
    [C,mx] = collect_clusters(tEdgeLag(:,L),tCrit,edgeNeighbours,L,lagsMs(L));
    obsMaxByLag(L) = mx;
    if ~isempty(C)
        if isempty(obsClusters), obsClusters = C; else, obsClusters = [obsClusters; C]; end %#ok<AGROW>
    end
end
obsMaxAcrossLags = max(obsMaxByLag);

%% 8. Unique dyad sign patterns
[signPatterns,signInfo] = generate_sign_patterns(nDyad,o.NumPermutations,o.RandomSeed);
nPerm = size(signPatterns,1);

%% 9. Permutation null distributions
nullMaxByLag = zeros(nPerm,nLag);
nullMaxAcrossLags = zeros(nPerm,1);
batch = min(o.PermutationBatchSize,nPerm);
nBatch = ceil(nPerm/batch);

for b = 1:nBatch
    i1 = (b-1)*batch+1;
    i2 = min(b*batch,nPerm);
    idx = i1:i2;
    signedSums = dataMatrix * signPatterns(idx,:)';
    permT = t_from_signed_sums(signedSums,sumSq,nDyad);
    for q = 1:numel(idx)
        T = reshape(permT(:,q),nEdge,nLag);
        currentAcross = 0;
        for L = 1:nLag
            mx = max_cluster_mass(T(:,L),tCrit,edgeNeighbours);
            nullMaxByLag(idx(q),L) = mx;
            currentAcross = max(currentAcross,mx);
        end
        nullMaxAcrossLags(idx(q)) = currentAcross;
    end
    if o.Verbose
        fprintf('Step10b permutations: %d/%d\n',i2,nPerm);
    end
end

%% 10. Correct observed clusters
pSpatialMap = ones(nEdge,nLag);
pGlobalMap = ones(nEdge,nLag);
sigSpatial = false(nEdge,nLag);
sigGlobal = false(nEdge,nLag);
clusterRows = struct([]);

for c = 1:numel(obsClusters)
    C = obsClusters(c);
    L = C.LagIndex;
    pSpatial = (1 + sum(nullMaxByLag(:,L) >= C.AbsoluteMass))/(nPerm+1);
    pGlobal = (1 + sum(nullMaxAcrossLags >= C.AbsoluteMass))/(nPerm+1);
    members = C.ConnectionIndices;
    pSpatialMap(members,L) = pSpatial;
    pGlobalMap(members,L) = pGlobal;
    if pSpatial <= o.FamilyWiseAlpha, sigSpatial(members,L) = true; end
    if pGlobal <= o.FamilyWiseAlpha, sigGlobal(members,L) = true; end

    peakEdge = C.PeakConnectionIndex;
    row = struct;
    row.ClusterID = double(c);
    row.LagIndex = double(L);
    row.LagMs = double(C.LagMs);
    row.ClusterSign = C.Sign;
    row.NumberOfConnections = double(numel(members));
    row.SignedClusterMass = double(C.SignedMass);
    row.AbsoluteClusterMass = double(C.AbsoluteMass);
    row.PeakT = double(C.PeakT);
    row.PeakConnectionIndex = double(peakEdge);
    row.PeakKnowerROI = edgeTable.KnowerROI(peakEdge);
    row.PeakGuesserROI = edgeTable.GuesserROI(peakEdge);
    row.MeanEffectWithinCluster = double(mean(meanEdgeLag(members,L),'all'));
    row.EffectAtPeakConnection = double(meanEdgeLag(peakEdge,L));
    row.SpatialFWERWithinLagP = double(pSpatial);
    row.SignificantSpatialWithinLag = logical(pSpatial <= o.FamilyWiseAlpha);
    row.GlobalFWERAcrossLagsP = double(pGlobal);
    row.SignificantGlobalAcrossLags = logical(pGlobal <= o.FamilyWiseAlpha);
    row.NumberOfDyads = double(nDyad);
    row.ConnectionIndices = string(mat2str(members(:)'));
    row.Connections = connection_list(members,edgeTable);
    clusterRows = append_struct(clusterRows,row);
end
clusterTable = struct_array_to_table(clusterRows);
if ~isempty(clusterTable)
    clusterTable = sortrows(clusterTable, ...
        {'GlobalFWERAcrossLagsP','SpatialFWERWithinLagP','AbsoluteClusterMass'}, ...
        {'ascend','ascend','descend'});
end

pSpatialMap3 = reshape(pSpatialMap,nK,nG,nLag);
pGlobalMap3 = reshape(pGlobalMap,nK,nG,nLag);
sigSpatial3 = reshape(sigSpatial,nK,nG,nLag);
sigGlobal3 = reshape(sigGlobal,nK,nG,nLag);

%% 11. Lag summaries
minSpatialP = ones(1,nLag);
minGlobalP = ones(1,nLag);
nClusters = zeros(1,nLag);
nSigSpatial = zeros(1,nLag);
nSigGlobal = zeros(1,nLag);
if ~isempty(clusterTable)
    for L = 1:nLag
        r = clusterTable.LagIndex==L;
        nClusters(L)=sum(r);
        if any(r)
            minSpatialP(L)=min(clusterTable.SpatialFWERWithinLagP(r));
            minGlobalP(L)=min(clusterTable.GlobalFWERAcrossLagsP(r));
            nSigSpatial(L)=sum(clusterTable.SignificantSpatialWithinLag(r));
            nSigGlobal(L)=sum(clusterTable.SignificantGlobalAcrossLags(r));
        end
    end
end
lagSummaryTable = table((1:nLag)',lagsMs(:),obsMaxByLag(:),minSpatialP(:),minGlobalP(:), ...
    nClusters(:),nSigSpatial(:),nSigGlobal(:), ...
    'VariableNames',{'LagIndex','LagMs','ObservedMaximumClusterMass', ...
    'MinimumSpatialFWERWithinLagP','MinimumGlobalFWERAcrossLagsP', ...
    'NumberObservedClusters','NumberSignificantSpatialClusters', ...
    'NumberSignificantGlobalClusters'});

%% 12. Output structure
spatialData = struct;
spatialData.step = "10b";
spatialData.description = "Spatial clustering of inter-brain connections, independently at each lag";
spatialData.sourceStep9File = string(step9File);
spatialData.inputContrastField = "yesMinusNoPrimary";
spatialData.inputContrastDefinition = string(step9Data.primaryContrastDefinition);
spatialData.lagConvention = string(step9Data.lagConvention);
spatialData.clusterTopology = "Spatial connection adjacency only; lags are never connected";
spatialData.roiNeighbourDefinition = ["Two Desikan-Killiany parcels are neighbours when they share " + ...
    "at least one triangular-mesh edge on the fsaverage cortical surface"];
spatialData.connectionNeighbourDefinition = ["Conservative endpoint-wise adjacency: one endpoint stays " + ...
    "identical and the other moves to an anatomical ROI neighbour"];
spatialData.roiLabelsKnower = roiK;
spatialData.roiLabelsGuesser = roiG;
spatialData.roiAdjacencyKnower = roiAdjK;
spatialData.roiAdjacencyGuesser = roiAdjG;
spatialData.connectionAdjacency = edgeAdj;
spatialData.connectionTable = edgeTable;
spatialData.adjacencyProvenance = adjacencyProvenance;
spatialData.lagsSamples = lagsSamples;
spatialData.lagsMilliseconds = lagsMs;
spatialData.samplingRate = double(step9Data.samplingRate);
spatialData.analysisDyadMask = analysisMask;
spatialData.analysisDyadNumbers = analysisDyadNumbers;
spatialData.numberOfDyads = nDyad;
spatialData.groupMean = meanMap;
spatialData.groupSD = sdMap;
spatialData.groupSEM = semMap;
spatialData.observedT = tMap;
spatialData.pointwiseParametricP = pointwiseP;
spatialData.degreesOfFreedom = df;
spatialData.clusterFormingAlpha = o.ClusterFormingAlpha;
spatialData.clusterFormingThresholdT = tCrit;
spatialData.familyWiseAlpha = o.FamilyWiseAlpha;
spatialData.observedMaximumClusterMassByLag = obsMaxByLag;
spatialData.observedMaximumClusterMassAcrossLags = obsMaxAcrossLags;
spatialData.nullMaximumClusterMassByLag = nullMaxByLag;
spatialData.nullMaximumClusterMassAcrossLags = nullMaxAcrossLags;
spatialData.spatialFWERWithinLagPMap = pSpatialMap3;
spatialData.globalFWERAcrossLagsPMap = pGlobalMap3;
spatialData.significantSpatialWithinLagMask = sigSpatial3;
spatialData.significantGlobalAcrossLagsMask = sigGlobal3;
spatialData.minimumSpatialFWERWithinLagP = minSpatialP;
spatialData.minimumGlobalFWERAcrossLagsP = minGlobalP;
spatialData.signPatterns = signPatterns;
spatialData.signGenerationInfo = signInfo;
spatialData.numberOfPermutationsRequested = o.NumPermutations;
spatialData.numberOfPermutationsGenerated = nPerm;
spatialData.settings = o;
spatialData.created = datestr(now,30);
spatialData.functionName = mfilename;

qcTable = struct_array_to_table(qcRows);

%% 13. Save outputs
matFile = fullfile(groupFolder,'Step10b_HyperYESNO_spatial_cluster_permutation.mat');
excelFile = fullfile(groupFolder,'Step10b_HyperYESNO_spatial_cluster_permutation.xlsx');
if o.SaveOutputs
    if exist(excelFile,'file')==2, delete(excelFile); end
    write_table_safely(clusterTable,excelFile,'SpatialClusters');
    writetable(lagSummaryTable,excelFile,'Sheet','LagSummary');
    writetable(roiNeighbourTable,excelFile,'Sheet','ROINeighbours');
    writetable(edgeTable,excelFile,'Sheet','Connections');
    write_table_safely(qcTable,excelFile,'QC');
    dyadTable = table(string(compose('Dyad%02d',analysisDyadNumbers(:))),analysisDyadNumbers(:), ...
        'VariableNames',{'Dyad','DyadNumber'});
    writetable(dyadTable,excelFile,'Sheet','AnalysisDyads');
    spatialData.savedMatFile = string(matFile);
    spatialData.savedWorkbook = string(excelFile);
    save(matFile,'spatialData','clusterTable','lagSummaryTable','roiNeighbourTable','qcTable', ...
        'sourceStep9DyadTable','sourceStep9QCTable','-v7.3');
end

%% 14. Figures
figureFiles = strings(0,1);
if o.SaveFigures
    f1 = fullfile(figureFolder,['Step10b_DK20_ROI_adjacency.' figureFormat]);
    figure_roi_adjacency(roiAdjK,roiK,f1,figureVisible);
    figureFiles(end+1)=string(f1);

    f2 = fullfile(figureFolder,['Step10b_minimum_corrected_p_by_lag.' figureFormat]);
    figure_lag_summary(lagsMs,minSpatialP,minGlobalP,o.FamilyWiseAlpha,f2,figureVisible);
    figureFiles(end+1)=string(f2);

    % One three-panel connectivity figure per lag.
    for L = 1:nLag
        f = fullfile(figureFolder,sprintf('Step10b_spatial_lag_%+05dms.%s',round(lagsMs(L)),figureFormat));
        figure_lag_map(tMap(:,:,L),pSpatialMap3(:,:,L),pGlobalMap3(:,:,L), ...
            sigSpatial3(:,:,L),sigGlobal3(:,:,L),roiK,roiG,lagsMs(L),o.FamilyWiseAlpha,f,figureVisible);
        figureFiles(end+1)=string(f); %#ok<AGROW>
    end
end
spatialData.figureFiles = figureFiles;
if o.SaveOutputs
    save(matFile,'spatialData','clusterTable','lagSummaryTable','roiNeighbourTable','qcTable', ...
        'sourceStep9DyadTable','sourceStep9QCTable','-v7.3');
end

%% 15. Report
if o.Verbose
    if isempty(clusterTable)
        nObs=0; nSW=0; nGL=0;
    else
        nObs=height(clusterTable);
        nSW=sum(clusterTable.SignificantSpatialWithinLag);
        nGL=sum(clusterTable.SignificantGlobalAcrossLags);
    end
    fprintf('\n============================================================\n');
    fprintf('Step 10b spatial cluster analysis completed.\n');
    fprintf('Dyads:                              %d\n',nDyad);
    fprintf('ROI x ROI connections:             %d\n',nEdge);
    fprintf('Lags analysed separately:          %d\n',nLag);
    fprintf('Unique sign permutations:          %d\n',nPerm);
    fprintf('Cluster-forming threshold:         |t| >= %.6f\n',tCrit);
    fprintf('Observed spatial clusters:         %d\n',nObs);
    fprintf('Significant within-lag clusters:   %d\n',nSW);
    fprintf('Significant all-lag-corrected:     %d\n',nGL);
    fprintf('Adjacency source:                  %s\n',char(adjacencyProvenance.Source));
    if o.SaveOutputs
        fprintf('MAT:                                %s\n',matFile);
        fprintf('Excel:                              %s\n',excelFile);
    end
    fprintf('============================================================\n');
end
end

%% ========================================================================
function [adjK,adjG,neighbourTable,prov] = obtain_adjacency(roiK,roiG,fsDir,cacheFile,verbose)
% Load a matching cache or derive adjacency from fsaverage surface meshes.

if exist(cacheFile,'file')==2
    C = load(cacheFile);
    req = {'roiLabelsKnowerCached','roiLabelsGuesserCached','roiAdjacencyKnowerCached', ...
        'roiAdjacencyGuesserCached','roiNeighbourTableCached','adjacencyProvenanceCached'};
    if all(isfield(C,req)) && isequal(string(C.roiLabelsKnowerCached(:)),string(roiK(:))) && ...
            isequal(string(C.roiLabelsGuesserCached(:)),string(roiG(:)))
        adjK = logical(C.roiAdjacencyKnowerCached);
        adjG = logical(C.roiAdjacencyGuesserCached);
        neighbourTable = C.roiNeighbourTableCached;
        prov = C.adjacencyProvenanceCached;
        prov.Source = "validated cached fsaverage Desikan-Killiany surface-boundary adjacency";
        if verbose, fprintf('Using cached ROI adjacency: %s\n',cacheFile); end
        return
    end
end

if exist('ft_read_atlas','file')~=2
    error('step10b:FieldTripMissing','ft_read_atlas is not on the MATLAB path.');
end
fsDir = resolve_fsaverage(fsDir);
lhAnnot=fullfile(fsDir,'label','lh.aparc.annot'); rhAnnot=fullfile(fsDir,'label','rh.aparc.annot');
lhPial=fullfile(fsDir,'surf','lh.pial'); rhPial=fullfile(fsDir,'surf','rh.pial');
files={lhAnnot,rhAnnot,lhPial,rhPial};
for k=1:numel(files)
    if exist(files{k},'file')~=2
        error('step10b:MissingFsAverageFile','Required fsaverage file missing:\n%s',files{k});
    end
end
if verbose, fprintf('Reading fsaverage Desikan-Killiany surfaces...\n'); end
lh=ft_read_atlas({lhAnnot,lhPial});
rh=ft_read_atlas({rhAnnot,rhPial});
[lhAdj,lhLabels]=surface_parcel_adjacency(lh);
[rhAdj,rhLabels]=surface_parcel_adjacency(rh);
[adjK,mapK]=map_project_rois(roiK,lhAdj,lhLabels,rhAdj,rhLabels);
[adjG,mapG]=map_project_rois(roiG,lhAdj,lhLabels,rhAdj,rhLabels);
neighbourTable=make_roi_neighbour_table(adjK,roiK,mapK);
prov=struct;
prov.Source="FreeSurfer fsaverage Desikan-Killiany surface mesh";
prov.Definition="Parcels share at least one triangular-mesh edge";
prov.FsAverageDir=string(fsDir);
prov.LeftAnnotation=string(lhAnnot); prov.RightAnnotation=string(rhAnnot);
prov.LeftSurface=string(lhPial); prov.RightSurface=string(rhPial);
prov.KnowerMappingTable=mapK; prov.GuesserMappingTable=mapG;
prov.Created=datestr(now,30);

roiLabelsKnowerCached=roiK; %#ok<NASGU>
roiLabelsGuesserCached=roiG; %#ok<NASGU>
roiAdjacencyKnowerCached=adjK; %#ok<NASGU>
roiAdjacencyGuesserCached=adjG; %#ok<NASGU>
roiNeighbourTableCached=neighbourTable; %#ok<NASGU>
adjacencyProvenanceCached=prov; %#ok<NASGU>
save(cacheFile,'roiLabelsKnowerCached','roiLabelsGuesserCached','roiAdjacencyKnowerCached', ...
    'roiAdjacencyGuesserCached','roiNeighbourTableCached','adjacencyProvenanceCached','-v7.3');
end

%% ========================================================================
function fsDir = resolve_fsaverage(fsDir)
if ~isempty(strtrim(fsDir))
    if exist(fsDir,'dir')~=7, error('step10b:FsAverageDir','FsAverageDir does not exist: %s',fsDir); end
    return
end
subjectsDir=getenv('SUBJECTS_DIR');
if ~isempty(subjectsDir)
    c=fullfile(subjectsDir,'fsaverage');
    if exist(c,'dir')==7, fsDir=c; return; end
end
fsHome=getenv('FREESURFER_HOME');
if ~isempty(fsHome)
    c=fullfile(fsHome,'subjects','fsaverage');
    if exist(c,'dir')==7, fsDir=c; return; end
end
error('step10b:FsAverageNotFound',[ ...
    'Could not locate FreeSurfer fsaverage. Supply it explicitly using, e.g.,\n' ...
    '''FsAverageDir'',''C:\path\to\freesurfer\subjects\fsaverage''']);
end

%% ========================================================================
function [A,labels] = surface_parcel_adjacency(atlas)
% Two parcels are neighbours if a mesh edge crosses directly between them.
if ~isfield(atlas,'pos') || ~isfield(atlas,'tri')
    error('step10b:SurfaceAtlas','Atlas must contain pos and tri.');
end
if isfield(atlas,'aparc') && isfield(atlas,'aparclabel')
    parcel=double(atlas.aparc(:)); labels=string(atlas.aparclabel(:));
else
    [pf,lf]=detect_parcellation_fields(atlas);
    parcel=double(atlas.(pf)(:)); labels=string(atlas.(lf)(:));
end
n=numel(labels);
if numel(parcel)~=size(atlas.pos,1)
    error('step10b:ParcelLength','Parcellation length does not match surface vertices.');
end
pos=unique(parcel(parcel>0));
if isempty(pos) || any(pos~=round(pos)) || max(pos)>n
    error('step10b:ParcelEncoding','Unexpected surface parcel encoding.');
end
tri=double(atlas.tri);
edges=sort([tri(:,[1 2]);tri(:,[2 3]);tri(:,[3 1])],2);
edges=unique(edges,'rows');
a=parcel(edges(:,1)); b=parcel(edges(:,2));
keep=a>0 & b>0 & a~=b; a=a(keep); b=b(keep);
A=false(n);
if ~isempty(a)
    A(sub2ind([n n],a,b))=true;
    A(sub2ind([n n],b,a))=true;
end
A(1:n+1:end)=false;
end

%% ========================================================================
function [pf,lf]=detect_parcellation_fields(atlas)
fn=fieldnames(atlas); nVert=size(atlas.pos,1); pf=''; lf='';
for k=1:numel(fn)
    f=fn{k};
    if endsWith(f,'label'), continue; end
    v=atlas.(f);
    candidate=[f 'label'];
    if isnumeric(v)&&isvector(v)&&numel(v)==nVert&&isfield(atlas,candidate)
        pf=f; lf=candidate; return
    end
end
error('step10b:ParcellationField','Could not identify surface parcellation fields.');
end

%% ========================================================================
function [A,mapTable]=map_project_rois(projectLabels,lhAdj,lhLabels,rhAdj,rhLabels)
n=numel(projectLabels); hemi=strings(n,1); dk=strings(n,1); idx=nan(n,1);
for r=1:n
    [hemi(r),dk(r)]=hyperyesno_to_dk(projectLabels(r));
    if hemi(r)=="L", m=find_label(dk(r),lhLabels); else, m=find_label(dk(r),rhLabels); end
    if numel(m)~=1
        error('step10b:AtlasLabel','Could not uniquely match ROI %s to DK label %s.',projectLabels(r),dk(r));
    end
    idx(r)=m;
end
A=false(n);
for i=1:n-1
    for j=i+1:n
        if hemi(i)~=hemi(j), continue; end
        if hemi(i)=="L", tf=lhAdj(idx(i),idx(j)); else, tf=rhAdj(idx(i),idx(j)); end
        if tf, A(i,j)=true; A(j,i)=true; end
    end
end
mapTable=table((1:n)',projectLabels(:),hemi,dk,idx, ...
    'VariableNames',{'ROIIndex','HyperYESNOROI','Hemisphere','DesikanKillianyLabel','AtlasParcelIndex'});
end

%% ========================================================================
function [hemi,dk]=hyperyesno_to_dk(label)
label=string(label);
if startsWith(label,"L_",'IgnoreCase',true), hemi="L"; base=lower(extractAfter(label,2));
elseif startsWith(label,"R_",'IgnoreCase',true), hemi="R"; base=lower(extractAfter(label,2));
else, error('step10b:Hemisphere','ROI label must start with L_ or R_: %s',label); end
switch base
    case "ifgop", dk="parsopercularis";
    case "ifgtri", dk="parstriangularis";
    case "stg", dk="superiortemporal";
    case "mtg", dk="middletemporal";
    case "heschl", dk="transversetemporal";
    case "smg", dk="supramarginal";
    case "ipl", dk="inferiorparietal";
    case "precentral", dk="precentral";
    case "rostralmfg", dk="rostralmiddlefrontal";
    case "precuneus", dk="precuneus";
    otherwise, error('step10b:ROIMap','No DK mapping defined for %s.',label);
end
end

%% ========================================================================
function idx=find_label(target,labels)
t=normalize_label(target); n=strings(size(labels));
for k=1:numel(labels), n(k)=normalize_label(labels(k)); end
idx=find(n==t);
end
function s=normalize_label(s)
s=lower(string(s));
s=regexprep(s,'^(ctx[-_]?lh[-_]?|ctx[-_]?rh[-_]?|lh[-_]|rh[-_])','');
s=regexprep(s,'[^a-z0-9]','');
end

%% ========================================================================
function T=make_roi_neighbour_table(A,labels,mapTable)
rows=struct([]); n=numel(labels);
for i=1:n-1
    for j=i+1:n
        if ~A(i,j), continue; end
        row=struct;
        row.ROI1Index=double(i); row.ROI1=labels(i); row.ROI1DesikanKilliany=mapTable.DesikanKillianyLabel(i);
        row.ROI2Index=double(j); row.ROI2=labels(j); row.ROI2DesikanKilliany=mapTable.DesikanKillianyLabel(j);
        row.Hemisphere=mapTable.Hemisphere(i);
        row.NeighbourDefinition="shared cortical surface boundary";
        rows=append_struct(rows,row);
    end
end
T=struct_array_to_table(rows);
end

%% ========================================================================
function [A,T,neighbours]=build_edge_adjacency(adjK,adjG,roiK,roiG)
nK=numel(roiK); nG=numel(roiG); n=nK*nG; A=sparse(n,n);
for j=1:nG
    for i=1:nK
        e=sub2ind([nK nG],i,j);
        nk=find(adjK(i,:));
        for k=nk
            e2=sub2ind([nK nG],k,j); A(e,e2)=1;
        end
        ng=find(adjG(j,:));
        for l=ng
            e2=sub2ind([nK nG],i,l); A(e,e2)=1;
        end
    end
end
A=logical(A|A'); A(1:n+1:end)=false;
neighbours=cell(n,1);
rows=repmat(struct('ConnectionIndex',NaN,'KnowerROIIndex',NaN,'KnowerROI',"", ...
    'GuesserROIIndex',NaN,'GuesserROI',"",'NumberOfConnectionNeighbours',NaN),n,1);
for j=1:nG
    for i=1:nK
        e=sub2ind([nK nG],i,j); neighbours{e}=find(A(e,:));
        rows(e).ConnectionIndex=e; rows(e).KnowerROIIndex=i; rows(e).KnowerROI=roiK(i);
        rows(e).GuesserROIIndex=j; rows(e).GuesserROI=roiG(j);
        rows(e).NumberOfConnectionNeighbours=numel(neighbours{e});
    end
end
T=struct2table(rows);
end

%% ========================================================================
function [clusters,mx]=collect_clusters(t,crit,neigh,L,lagMs)
clusters=struct([]); mx=0;
for signCode=[1 -1]
    if signCode==1, active=t>=crit; signLabel="positive"; else, active=t<=-crit; signLabel="negative"; end
    comps=components(active,neigh);
    for c=1:numel(comps)
        m=comps{c}; mass=sum(t(m)); am=abs(mass);
        if signCode==1, [peak,ii]=max(t(m)); else, [peak,ii]=min(t(m)); end
        row=struct('LagIndex',double(L),'LagMs',double(lagMs),'Sign',signLabel, ...
            'ConnectionIndices',double(m(:)'),'SignedMass',double(mass), ...
            'AbsoluteMass',double(am),'PeakT',double(peak), ...
            'PeakConnectionIndex',double(m(ii)));
        clusters=append_struct(clusters,row); mx=max(mx,am);
    end
end
end

%% ========================================================================
function mx=max_cluster_mass(t,crit,neigh)
mx=0;
for active={t>=crit,t<=-crit}
    comps=components(active{1},neigh);
    for c=1:numel(comps), mx=max(mx,abs(sum(t(comps{c})))); end
end
end

%% ========================================================================
function C=components(active,neigh)
active=logical(active(:)); n=numel(active); visited=false(n,1); C=cell(0,1);
for seed=find(active)'
    if visited(seed), continue; end
    queue=seed; visited(seed)=true; member=zeros(0,1); q=1;
    while q<=numel(queue)
        u=queue(q); q=q+1; member(end+1,1)=u; %#ok<AGROW>
        v=neigh{u};
        if isempty(v), continue; end
        v=v(active(v) & ~visited(v));
        if ~isempty(v), visited(v)=true; queue=[queue v(:)']; end %#ok<AGROW>
    end
    C{end+1,1}=member(:)'; %#ok<AGROW>
end
end

%% ========================================================================
function s=connection_list(indices,T)
parts=strings(numel(indices),1);
for k=1:numel(indices)
    e=indices(k); parts(k)=T.KnowerROI(e)+" -> "+T.GuesserROI(e);
end
s=strjoin(parts,'; ');
end

%% ========================================================================
function [t,mu,sd]=one_sample_t_from_sums(sumX,sumSq,n)
mu=sumX./n; num=sumSq-n.*mu.^2; num=max(num,0); sd=sqrt(num./(n-1)); se=sd./sqrt(n);
t=zeros(size(mu)); ok=se>0; t(ok)=mu(ok)./se(ok); t(~ok & mu>0)=Inf; t(~ok & mu<0)=-Inf;
end
function t=t_from_signed_sums(sumX,sumSq,n)
mu=sumX./n; num=sumSq-n.*mu.^2; num=max(num,0); se=sqrt((num./(n-1))./n);
t=zeros(size(mu)); ok=se>0; t(ok)=mu(ok)./se(ok); t(~ok & mu>0)=Inf; t(~ok & mu<0)=-Inf;
end
function p=student_t_two_sided_p(t,df)
x=df./(df+abs(t).^2); p=betainc(x,df/2,0.5); p(isinf(abs(t)))=0; p=min(max(p,0),1);
end
function tc=student_t_two_sided_critical(alpha,df)
x=betaincinv(alpha,df/2,0.5); tc=sqrt(df.*(1-x)./x);
end

%% ========================================================================
function [patterns,info]=generate_sign_patterns(nDyad,nRequested,seed)
nFree=nDyad-1;
if nFree<=52, maxUnique=2^nFree-1; else, maxUnique=Inf; end
n=min(nRequested,maxUnique); rng(seed,'twister');
if isfinite(maxUnique) && n==maxUnique && maxUnique<=2^20-1
    codes=uint64((1:maxUnique)'); neg=false(maxUnique,nFree);
    for k=1:nFree, neg(:,k)=logical(bitget(codes,k)); end
    mode="all unique two-sided patterns";
else
    neg=false(0,nFree);
    while size(neg,1)<n
        remaining=n-size(neg,1); prop=rand(max(1000,ceil(1.5*remaining)),nFree)<0.5;
        prop=prop(any(prop,2),:); neg=unique([neg;prop],'rows','stable');
        if size(neg,1)>n, neg=neg(1:n,:); end
    end
    mode="random unique two-sided patterns";
end
patterns=ones(n,nDyad); patterns(:,2:end)=1-2*double(neg);
info=struct('Mode',mode,'FirstDyadFixedPositive',true,'ObservedPatternExcluded',true, ...
    'GlobalInverseDuplicatesPrevented',true,'MaximumUniquePatterns',maxUnique, ...
    'NumberRequested',nRequested,'NumberGenerated',n,'RandomSeed',seed);
end

%% ========================================================================
function figure_roi_adjacency(A,labels,file,vis)
f=figure('Visible',vis,'Color','w','Position',[100 100 950 850]);
imagesc(double(A)); axis image; set(gca,'YDir','normal'); colormap(parula(2)); colorbar;
title('Desikan-Killiany ROI adjacency: shared cortical-surface boundary');
xticks(1:numel(labels)); xticklabels(cellstr(labels)); xtickangle(90);
yticks(1:numel(labels)); yticklabels(cellstr(labels));
set(gca,'TickLabelInterpreter','none','FontSize',8); exportgraphics(f,file,'Resolution',300); close(f);
end

function figure_lag_summary(lags,p1,p2,alpha,file,vis)
f=figure('Visible',vis,'Color','w','Position',[100 100 1050 700]); hold on;
plot(lags,-log10(p1),'-o','LineWidth',1.5,'DisplayName','Spatial FWER within lag');
plot(lags,-log10(p2),'-s','LineWidth',1.5,'DisplayName','Global FWER across lag search');
yline(-log10(alpha),'--',sprintf('p = %.3f',alpha),'LineWidth',1.2); xline(0,':');
xlabel('Lag (ms): negative = Knower precedes Guesser; positive = Guesser precedes Knower');
ylabel('-log_{10}(minimum cluster-corrected p)');
title('Spatial clusters calculated independently at each lag'); legend('Location','best'); box off;
exportgraphics(f,file,'Resolution',300); close(f);
end

function figure_lag_map(t,p1,p2,s1,s2,roiK,roiG,lagMs,alpha,file,vis)
f=figure('Visible',vis,'Color','w','Position',[100 100 1850 650]); tl=tiledlayout(f,1,3,'Padding','compact','TileSpacing','compact');
nexttile; imagesc(t); axis image; set(gca,'YDir','normal'); m=max(abs(t),[],'all'); if m>0, clim([-m m]); end
colormap(gca,blue_white_red(256)); colorbar; title(sprintf('Observed YES-NO t map at %+g ms',lagMs)); apply_ticks(roiK,roiG);
nexttile; imagesc(-log10(max(p1,realmin))); axis image; set(gca,'YDir','normal'); colormap(gca,parula(256)); colorbar; hold on;
[r,c]=find(s1); plot(c,r,'ko','MarkerSize',8,'LineWidth',1.4); title(sprintf('Spatial FWER within lag\ncircles: p <= %.3f',alpha)); apply_ticks(roiK,roiG);
nexttile; imagesc(-log10(max(p2,realmin))); axis image; set(gca,'YDir','normal'); colormap(gca,parula(256)); colorbar; hold on;
[r,c]=find(s2); plot(c,r,'ko','MarkerSize',8,'LineWidth',1.4); title(sprintf('Global FWER across lag search\ncircles: p <= %.3f',alpha)); apply_ticks(roiK,roiG);
title(tl,sprintf('Spatial inter-brain clusters at %+g ms',lagMs)); exportgraphics(f,file,'Resolution',300); close(f);
end
function apply_ticks(roiK,roiG)
xlabel('Guesser ROI'); ylabel('Knower ROI'); xticks(1:numel(roiG)); xticklabels(cellstr(roiG)); xtickangle(90);
yticks(1:numel(roiK)); yticklabels(cellstr(roiK)); set(gca,'TickLabelInterpreter','none','FontSize',8);
end
function C=blue_white_red(n)
if mod(n,2), n=n+1; end; h=n/2;
C=[[linspace(0,1,h)' linspace(0,1,h)' ones(h,1)]; [ones(h,1) linspace(1,0,h)' linspace(1,0,h)']];
end

%% ========================================================================
function rows=add_qc(rows,dyadNumber,issue,details)
row=struct('Dyad',string(sprintf('Dyad%02d',dyadNumber)),'DyadNumber',double(dyadNumber), ...
    'Issue',string(issue),'Details',string(details)); rows=append_struct(rows,row);
end
function output=append_struct(output,row)
if isempty(output), output=row; else, output(end+1,1)=row; end
end
function T=struct_array_to_table(rows)
if isempty(rows), T=table(); else, T=struct2table(rows); end
end
function s=size4(x)
s=size(x); s(end+1:4)=1; s=s(1:4);
end
function write_table_safely(T,file,sheet)
if width(T)==0, T=table("No entries",'VariableNames',{'Message'}); end
writetable(T,file,'Sheet',sheet);
end
