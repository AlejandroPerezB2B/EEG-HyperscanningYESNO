function [masterTable, correlationTable, yesProportionPartialTable, featureTable] = ...
    step12b_restricted_multimodal_correlations_HyperYESNO_v2(varargin)
% STEP12B_RESTRICTED_MULTIMODAL_CORRELATIONS_HYPERYESNO
% -------------------------------------------------------------------------
% Restricted, hypothesis-guided DYAD-level multimodal correlation analysis
% for HyperYESNO.
%
% Exactly six variables are entered into the main correlation family:
%
%   1) Q1 naturalness disagreement
%      Absolute A-B difference on questionnaire item Q1:
%      "The interaction felt natural."
%
%   2) YES proportion
%      NumYes / (NumYes + NumNo), pooled across both Knower roles.
%
%   3) Interaction pace
%      Median interval (seconds) between consecutive YES/NO response markers.
%      Smaller values indicate a faster interaction pace.
%
%   4) Neural YES-NO effect at -250 ms
%      For each dyad, mean Step9 surrogate-corrected YES-minus-NO GCMI across
%      only the ROI pairs significant after Step10b WITHIN-LAG spatial FWER
%      correction at -250 ms.
%
%   5) Neural YES-NO effect at +300 ms
%      Same definition at +300 ms.
%
%   6) Head-motion YES-NO effect
%      For each dyad, mean surrogate-corrected Fisher-z YES-minus-NO head-
%      motion correlation across the previously established significant lag
%      interval from approximately 633 to 833 ms.
%
% The statistical unit is the DYAD (maximum N = 35).
%
% MAIN INFERENCE
% --------------
% All 15 unique pairwise Spearman correlations among the six predefined
% variables are calculated. Benjamini-Hochberg FDR correction is applied
% across this 15-test family.
%
% YES-PROPORTION SENSITIVITY
% --------------------------
% YES proportion is inherently related to the relative number of YES and NO
% EEG trials. Therefore, for the five correlations involving YES proportion,
% the function additionally reports a partial Spearman correlation controlling
% the Step9 YES-minus-NO EEG trial-count imbalance.
%
% IMPORTANT CAVEAT ABOUT NEURAL FEATURE EXTRACTION
% ------------------------------------------------
% The -250 and +300 ms ROI masks are the significant Step10b masks obtained
% from the same group of dyads. The behavioural variables were NOT used to
% select these ROI pairs, but this remains a group-effect-defined feature
% extraction and should be described as exploratory in brain-behaviour
% correlations. A leave-one-dyad-out mask definition would be a stricter
% confirmatory extension if required.
%
% DEFAULT INPUT FILES
% -------------------
% EEG Step9:
%   E:\EEG_data_HyperYESNO\Group_GCMI\
%       Step9_HyperYESNO_surrogate_corrected_GCMI.mat
%
% EEG Step10b:
%   E:\EEG_data_HyperYESNO\Group_GCMI\
%       Step10b_HyperYESNO_spatial_cluster_permutation.mat
%
% Response behaviour:
%   E:\EEG_data_HyperYESNO\HyperYESNO_response_marker_behaviour.mat
%
% Head movement:
%   E:\HyperYESNO_videosCUT\_video_analysis\
%       HyperYESNO_video_stage3_lagged_correlations.mat
%
% Questionnaire:
%   E:\EEG_data_HyperYESNO\Interaction_Rating_Dyad_Scores.xlsx
%
% OUTPUTS
% -------
% masterTable
%   One row per dyad with the six analysis variables plus useful QC columns.
%
% correlationTable
%   The 15 pairwise Spearman correlations, raw p values and FDR q values.
%
% yesProportionPartialTable
%   Five partial Spearman correlations involving YES proportion, controlling
%   EEG trial-count imbalance.
%
% featureTable
%   Definitions and provenance for all six primary variables.
%
% EXAMPLE
% -------
% [D,C,P,F] = step12b_restricted_multimodal_correlations_HyperYESNO;
%
% HyperYESNO project, 2026

%% ------------------------------------------------------------------------
% 1) Parse inputs
% -------------------------------------------------------------------------
p = inputParser;
p.FunctionName = mfilename;

addParameter(p,'RootDir','E:\EEG_data_HyperYESNO', ...
    @(x)ischar(x)||isstring(x));
addParameter(p,'Step9File','',@(x)ischar(x)||isstring(x));
addParameter(p,'Step10bFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'ResponseMarkerFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'HeadMotionFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'QuestionnaireFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'OutputDir','',@(x)ischar(x)||isstring(x));
addParameter(p,'NeuralLagsMs',[-250 300], ...
    @(x)isnumeric(x)&&numel(x)==2&&all(isfinite(x)));
addParameter(p,'HeadMotionLagRangeSec',[0.633 0.833], ...
    @(x)isnumeric(x)&&numel(x)==2&&all(isfinite(x))&&all(x>=0));
addParameter(p,'MinimumN',20, ...
    @(x)isnumeric(x)&&isscalar(x)&&x>=4&&x==round(x));
addParameter(p,'FamilyWiseAlpha',0.05, ...
    @(x)isnumeric(x)&&isscalar(x)&&x>0&&x<1);
addParameter(p,'MakeFigures',true,@(x)islogical(x)&&isscalar(x));
addParameter(p,'SaveOutputs',true,@(x)islogical(x)&&isscalar(x));
addParameter(p,'FigureVisible','on', ...
    @(x)any(strcmpi(string(x),["on","off"])));
addParameter(p,'Verbose',true,@(x)islogical(x)&&isscalar(x));
parse(p,varargin{:});
o = p.Results;

rootDir = char(string(o.RootDir));
groupDir = fullfile(rootDir,'Group_GCMI');

if isempty(o.Step9File)
    step9File = fullfile(groupDir,'Step9_HyperYESNO_surrogate_corrected_GCMI.mat');
else
    step9File = char(string(o.Step9File));
end
if isempty(o.Step10bFile)
    step10bFile = fullfile(groupDir,'Step10b_HyperYESNO_spatial_cluster_permutation.mat');
else
    step10bFile = char(string(o.Step10bFile));
end
if isempty(o.ResponseMarkerFile)
    responseMarkerFile = fullfile(rootDir,'HyperYESNO_response_marker_behaviour.mat');
else
    responseMarkerFile = char(string(o.ResponseMarkerFile));
end
if isempty(o.HeadMotionFile)
    headMotionFile = fullfile('E:\HyperYESNO_videosCUT','_video_analysis', ...
        'HyperYESNO_video_stage3_lagged_correlations.mat');
else
    headMotionFile = char(string(o.HeadMotionFile));
end
if isempty(o.QuestionnaireFile)
    questionnaireFile = fullfile(rootDir,'Interaction_Rating_Dyad_Scores.xlsx');
else
    questionnaireFile = char(string(o.QuestionnaireFile));
end
if isempty(o.OutputDir)
    outputDir = fullfile(groupDir,'Step12b_Restricted_Multimodal_Correlations');
else
    outputDir = char(string(o.OutputDir));
end

requiredFiles = {step9File,step10bFile,responseMarkerFile,headMotionFile,questionnaireFile};
for k=1:numel(requiredFiles)
    if exist(requiredFiles{k},'file')~=2
        error('step12b:MissingFile','Required file not found:\n%s',requiredFiles{k});
    end
end
if (o.SaveOutputs||o.MakeFigures) && exist(outputDir,'dir')~=7
    mkdir(outputDir);
end

if o.Verbose
    fprintf('\n============================================================\n');
    fprintf('HyperYESNO Step12b: restricted multimodal correlations\n');
    fprintf('============================================================\n');
    fprintf('Step9:         %s\n',step9File);
    fprintf('Step10b:       %s\n',step10bFile);
    fprintf('Responses:     %s\n',responseMarkerFile);
    fprintf('Head movement: %s\n',headMotionFile);
    fprintf('Questionnaire: %s\n',questionnaireFile);
end

%% ------------------------------------------------------------------------
% 2) Master dyad table
% -------------------------------------------------------------------------
DyadNumber = (1:35)';
Dyad = string(compose('Dyad%02d',DyadNumber));
masterTable = table(DyadNumber,Dyad);

%% ------------------------------------------------------------------------
% 3) Response behaviour: YES proportion and interaction pace
% -------------------------------------------------------------------------
R = load(responseMarkerFile,'dyadSummary');
if ~isfield(R,'dyadSummary') || ~istable(R.dyadSummary)
    error('step12b:ResponseFile','Response MAT must contain table dyadSummary.');
end
D = R.dyadSummary;
needResp = {'YesProportion','MedianInterResponseIntervalSec'};
for k=1:numel(needResp)
    if ~ismember(needResp{k},D.Properties.VariableNames)
        error('step12b:ResponseField','dyadSummary lacks %s.',needResp{k});
    end
end
masterTable.YesProportion = map_table_by_dyad_local(D,'YesProportion');
masterTable.MedianInterResponseIntervalSec = ...
    map_table_by_dyad_local(D,'MedianInterResponseIntervalSec');

% Keep raw counts as QC/descriptive columns if available.
for v = ["NumYes","NumNo","NumResponses"]
    if ismember(v,D.Properties.VariableNames)
        masterTable.(char(v)) = map_table_by_dyad_local(D,char(v));
    end
end

%% ------------------------------------------------------------------------
% 4) Questionnaire: absolute within-dyad disagreement on Q1 only
% -------------------------------------------------------------------------
Q = readtable(questionnaireFile,'Sheet','Absolute disagreement', ...
    'VariableNamingRule','preserve');
qDyads = get_dyad_numbers_local(Q);
q1Var = find_variable_local(Q,'Q1');
q1 = to_numeric_local(Q.(q1Var));
masterTable.Q1_NaturalnessDisagreement = ...
    map_values_local(qDyads,q1,DyadNumber);

%% ------------------------------------------------------------------------
% 5) EEG: Step9 dyad contrasts averaged over significant Step10b ROI pairs
% -------------------------------------------------------------------------
S9 = load(step9File,'step9Data');
if ~isfield(S9,'step9Data')
    error('step12b:Step9','Step9 file lacks step9Data.');
end
E = S9.step9Data;
requiredE = {'yesMinusNoPrimary','dyadNumbers','lagsMilliseconds','numberOfTrials','situations'};
for k=1:numel(requiredE)
    if ~isfield(E,requiredE{k})
        error('step12b:Step9Field','step9Data lacks %s.',requiredE{k});
    end
end

S10 = load(step10bFile,'spatialData');
if ~isfield(S10,'spatialData')
    error('step12b:Step10b','Step10b file lacks spatialData.');
end
SP = S10.spatialData;
requiredSP = {'significantSpatialWithinLagMask','lagsMilliseconds'};
for k=1:numel(requiredSP)
    if ~isfield(SP,requiredSP{k})
        error('step12b:Step10bField','spatialData lacks %s.',requiredSP{k});
    end
end

X = double(E.yesMinusNoPrimary); % K x G x Lag x Dyad
step9Dyads = double(E.dyadNumbers(:));
step9Lags = double(E.lagsMilliseconds(:)');
step10Lags = double(SP.lagsMilliseconds(:)');
sigMask3 = logical(SP.significantSpatialWithinLagMask);

neuralMaskRows = struct([]);
maskRowN = 0;
neuralNames = {'Neural_YESminusNO_m250ms','Neural_YESminusNO_p300ms'};
requestedNeuralLags = double(o.NeuralLagsMs(:)');

for kk = 1:2
    targetLag = requestedNeuralLags(kk);
    idx9 = nearest_lag_index_local(step9Lags,targetLag,1e-6,'Step9');
    idx10 = nearest_lag_index_local(step10Lags,targetLag,1e-6,'Step10b');
    mask = sigMask3(:,:,idx10);
    nEdges = nnz(mask);
    if nEdges==0
        error('step12b:NoSignificantEdges', ...
            'No within-lag spatial-FWER significant ROI pairs at %+g ms.',targetLag);
    end

    dyadVals = nan(numel(step9Dyads),1);
    for d=1:numel(step9Dyads)
        map = X(:,:,idx9,d);
        vals = map(mask);
        if any(isfinite(vals))
            dyadVals(d) = mean(vals,'omitnan');
        end
    end
    masterTable.(neuralNames{kk}) = ...
        map_values_local(step9Dyads,dyadVals,DyadNumber);

    % Transparency table: exact ROI pairs used for this neural summary.
    [ii,jj] = find(mask);
    roiK = strings(size(ii)); roiG = strings(size(jj));
    if isfield(E,'roiLabelsKnower'), labelsK=string(E.roiLabelsKnower(:)); else, labelsK=string((1:size(mask,1))'); end
    if isfield(E,'roiLabelsGuesser'), labelsG=string(E.roiLabelsGuesser(:)); else, labelsG=string((1:size(mask,2))'); end
    for e=1:numel(ii)
        maskRowN=maskRowN+1;
        neuralMaskRows(maskRowN).LagMs = targetLag; %#ok<AGROW>
        neuralMaskRows(maskRowN).KnowerROIIndex = ii(e);
        neuralMaskRows(maskRowN).KnowerROI = labelsK(ii(e));
        neuralMaskRows(maskRowN).GuesserROIIndex = jj(e);
        neuralMaskRows(maskRowN).GuesserROI = labelsG(jj(e));
        if isfield(SP,'spatialFWERWithinLagPMap')
            neuralMaskRows(maskRowN).SpatialFWERWithinLagP = ...
                double(SP.spatialFWERWithinLagPMap(ii(e),jj(e),idx10));
        else
            neuralMaskRows(maskRowN).SpatialFWERWithinLagP = NaN;
        end
        if isfield(SP,'groupMean')
            neuralMaskRows(maskRowN).GroupMeanYESminusNO = ...
                double(SP.groupMean(ii(e),jj(e),idx10));
        else
            neuralMaskRows(maskRowN).GroupMeanYESminusNO = NaN;
        end
    end

    if o.Verbose
        fprintf('Neural lag %+g ms: averaging %d significant ROI pairs.\n',targetLag,nEdges);
    end
end
if isempty(neuralMaskRows), neuralMaskTable=table(); else, neuralMaskTable=struct2table(neuralMaskRows); end

%% EEG trial imbalance for YES-proportion sensitivity analysis
situations = string(E.situations(:));
counts = double(E.numberOfTrials);
idxYA=find(situations=="YES_AKnower",1); idxNA=find(situations=="NO_AKnower",1);
idxYB=find(situations=="YES_BKnower",1); idxNB=find(situations=="NO_BKnower",1);
if any(cellfun(@isempty,{idxYA,idxNA,idxYB,idxNB}))
    error('step12b:Situations','Required Step9 situations were not found.');
end
trialImbalance = (counts(:,idxYA)+counts(:,idxYB)) - ...
                 (counts(:,idxNA)+counts(:,idxNB));
masterTable.EEG_TrialImbalanceYESminusNO = ...
    map_values_local(step9Dyads,trialImbalance,DyadNumber);

%% ------------------------------------------------------------------------
% 6) Head movement: mean YES-NO across significant 633-833 ms interval
% -------------------------------------------------------------------------
H = load(headMotionFile,'results');
if ~isfield(H,'results') || ~isstruct(H.results)
    error('step12b:HeadMotion','Head-motion MAT must contain results.');
end
HR = H.results;
requiredH = {'dyadList','absLagSec','YESminusNO_Z'};
for k=1:numel(requiredH)
    if ~isfield(HR,requiredH{k})
        error('step12b:HeadMotionField','results lacks %s.',requiredH{k});
    end
end
% dyadList is typically stored as strings such as "Dyad01" ... "Dyad35".
% Parse these robustly rather than calling double() on a string/cell array.
hDyads = parse_dyad_ids_local(HR.dyadList);
hLags = double(HR.absLagSec(:)');
hDiff = double(HR.YESminusNO_Z);

% Stage 3 stores YESminusNO_Z as lag x dyad (31 x 35). Convert to
% dyad x lag for the extraction below. Also accept dyad x lag if the
% upstream file format changes in a future run.
if size(hDiff,1)==numel(hLags) && size(hDiff,2)==numel(hDyads)
    hDiff = hDiff';
elseif size(hDiff,1)==numel(hDyads) && size(hDiff,2)==numel(hLags)
    % already dyad x lag
else
    error('step12b:HeadMotionDimensions', ...
        ['YESminusNO_Z has size %d x %d, but expected either lag x dyad ', ...
         '(%d x %d) or dyad x lag (%d x %d).'], ...
        size(hDiff,1),size(hDiff,2),numel(hLags),numel(hDyads), ...
        numel(hDyads),numel(hLags));
end

rangeRequested = sort(double(o.HeadMotionLagRangeSec(:)'));
[~,iStart]=min(abs(hLags-rangeRequested(1)));
[~,iEnd]=min(abs(hLags-rangeRequested(2)));
lo=min(iStart,iEnd); hi=max(iStart,iEnd);
hIdx = lo:hi;
actualHeadRange = [hLags(lo) hLags(hi)];
headVals = mean(hDiff(:,hIdx),2,'omitnan');
masterTable.HeadMotion_YESminusNO_633_833ms = ...
    map_values_local(hDyads,headVals,DyadNumber);
headMotionLagTable = table(hLags(hIdx)',1000*hLags(hIdx)', ...
    'VariableNames',{'AbsLagSec','AbsLagMs'});

nHeadMapped = sum(isfinite(masterTable.HeadMotion_YESminusNO_633_833ms));
if o.Verbose
    fprintf('Head-motion interval requested: %.3f-%.3f s\n',rangeRequested(1),rangeRequested(2));
    fprintf('Head-motion samples used: %.6f-%.6f s (%d lag samples)\n', ...
        actualHeadRange(1),actualHeadRange(2),numel(hIdx));
    fprintf('Head-motion dyads mapped: %d / %d\n',nHeadMapped,height(masterTable));
end
if nHeadMapped < height(masterTable)
    warning('step12b:HeadMotionMissingDyads', ...
        'Head-motion data mapped for only %d of %d dyads.',nHeadMapped,height(masterTable));
end

%% ------------------------------------------------------------------------
% 7) Feature definitions
% -------------------------------------------------------------------------
featureNames = [ ...
    "Q1_NaturalnessDisagreement"; ...
    "YesProportion"; ...
    "MedianInterResponseIntervalSec"; ...
    "Neural_YESminusNO_m250ms"; ...
    "Neural_YESminusNO_p300ms"; ...
    "HeadMotion_YESminusNO_633_833ms"];
domains = ["Questionnaire";"ResponseBehaviour";"ResponseBehaviour";"Neural";"Neural";"HeadMovement"];
definitions = [ ...
    "Absolute A-B difference on Q1: The interaction felt natural."; ...
    "YES markers divided by all YES+NO response markers within the dyad."; ...
    "Median seconds between consecutive registered YES/NO responses; lower = faster pace."; ...
    sprintf("Dyad surrogate-corrected YES-NO GCMI averaged across Step10b within-lag spatial-FWER significant ROI pairs at %+g ms.",requestedNeuralLags(1)); ...
    sprintf("Dyad surrogate-corrected YES-NO GCMI averaged across Step10b within-lag spatial-FWER significant ROI pairs at %+g ms.",requestedNeuralLags(2)); ...
    sprintf("Dyad surrogate-corrected head-motion Fisher-z YES-NO difference averaged across %.3f-%.3f s absolute lag.",actualHeadRange(1),actualHeadRange(2))];
featureTable = table(featureNames,domains,definitions, ...
    'VariableNames',{'Variable','Domain','Definition'});

%% ------------------------------------------------------------------------
% 8) Main 15 pairwise Spearman correlations
% -------------------------------------------------------------------------
nFeat = numel(featureNames);
rows = struct([]); rr=0;
for i=1:nFeat-1
    for j=i+1:nFeat
        x = double(masterTable.(featureNames(i)));
        y = double(masterTable.(featureNames(j)));
        valid = isfinite(x)&isfinite(y);
        n = sum(valid);
        [rho,pval] = spearman_local(x(valid),y(valid));
        if n < o.MinimumN
            rho=NaN; pval=NaN;
        end
        rr=rr+1;
        rows(rr).Variable1 = featureNames(i); %#ok<AGROW>
        rows(rr).Domain1 = domains(i);
        rows(rr).Variable2 = featureNames(j);
        rows(rr).Domain2 = domains(j);
        rows(rr).N = n;
        rows(rr).SpearmanRho = rho;
        rows(rr).PValue = pval;
        rows(rr).AbsRho = abs(rho);
    end
end
correlationTable = struct2table(rows);
correlationTable.FDRq = bh_fdr_local(correlationTable.PValue);
correlationTable.SignificantRawP = correlationTable.PValue < o.FamilyWiseAlpha;
correlationTable.SignificantFDR = correlationTable.FDRq < o.FamilyWiseAlpha;
correlationTable = sortrows(correlationTable,'AbsRho','descend');

%% ------------------------------------------------------------------------
% 9) Partial Spearman sensitivity for YES proportion controlling EEG counts
% -------------------------------------------------------------------------
partialRows = struct([]); pr=0;
yesName = "YesProportion";
for j=1:nFeat
    if featureNames(j)==yesName, continue; end
    x = double(masterTable.(yesName));
    y = double(masterTable.(featureNames(j)));
    z = double(masterTable.EEG_TrialImbalanceYESminusNO);
    valid=isfinite(x)&isfinite(y)&isfinite(z);
    n=sum(valid);
    if n>=o.MinimumN
        [rho,pval] = partial_spearman_local(x(valid),y(valid),z(valid));
    else
        rho=NaN; pval=NaN;
    end
    pr=pr+1;
    partialRows(pr).Variable1 = yesName; %#ok<AGROW>
    partialRows(pr).Variable2 = featureNames(j);
    partialRows(pr).ControlVariable = "EEG_TrialImbalanceYESminusNO";
    partialRows(pr).N = n;
    partialRows(pr).PartialSpearmanRho = rho;
    partialRows(pr).PValue = pval;
    partialRows(pr).AbsRho = abs(rho);
end
yesProportionPartialTable = struct2table(partialRows);
yesProportionPartialTable.FDRq = bh_fdr_local(yesProportionPartialTable.PValue);
yesProportionPartialTable = sortrows(yesProportionPartialTable,'AbsRho','descend');

%% ------------------------------------------------------------------------
% 10) Figures
% -------------------------------------------------------------------------
figureFiles = strings(0,1);
if o.MakeFigures
    vis=char(lower(string(o.FigureVisible)));

    % Correlation heatmap.
    rhoMat=nan(nFeat); pMat=nan(nFeat);
    for i=1:nFeat
        rhoMat(i,i)=1; pMat(i,i)=0;
    end
    for r=1:height(correlationTable)
        i=find(featureNames==correlationTable.Variable1(r),1);
        j=find(featureNames==correlationTable.Variable2(r),1);
        rhoMat(i,j)=correlationTable.SpearmanRho(r); rhoMat(j,i)=rhoMat(i,j);
        pMat(i,j)=correlationTable.PValue(r); pMat(j,i)=pMat(i,j); %#ok<NASGU>
    end
    f=figure('Visible',vis,'Color','w','Position',[100 100 1100 900]);
    imagesc(rhoMat,[-1 1]); axis square; colorbar;
    xticks(1:nFeat); yticks(1:nFeat);
    shortLabels={"Q1 disagreement","YES proportion","Interaction pace", ...
        "Neural -250 ms","Neural +300 ms","Head motion 633-833 ms"};
    xticklabels(shortLabels); yticklabels(shortLabels);
    xtickangle(35);
    title('HyperYESNO restricted dyad-level Spearman correlations');
    for i=1:nFeat
        for j=1:nFeat
            if isfinite(rhoMat(i,j))
                text(j,i,sprintf('%.2f',rhoMat(i,j)), ...
                    'HorizontalAlignment','center','FontSize',9);
            end
        end
    end
    heatFile=fullfile(outputDir,'Step12b_restricted_correlation_heatmap.png');
    exportgraphics(f,heatFile,'Resolution',300); figureFiles(end+1)=string(heatFile); %#ok<AGROW>
    if strcmpi(vis,'off'), close(f); end

    % Six strongest scatterplots, for visual inspection only.
    nPlot=min(6,height(correlationTable));
    fs=figure('Visible',vis,'Color','w','Position',[80 80 1500 900]);
    tl=tiledlayout(fs,2,3,'Padding','compact','TileSpacing','compact');
    for r=1:nPlot
        ax=nexttile(tl,r);
        v1=correlationTable.Variable1(r); v2=correlationTable.Variable2(r);
        x=double(masterTable.(v1)); y=double(masterTable.(v2));
        valid=isfinite(x)&isfinite(y);
        scatter(ax,x(valid),y(valid),35,'filled');
        xlabel(ax,strrep(char(v1),'_',' ')); ylabel(ax,strrep(char(v2),'_',' '));
        title(ax,sprintf('rho = %.2f, p = %.3g, q = %.3g', ...
            correlationTable.SpearmanRho(r),correlationTable.PValue(r),correlationTable.FDRq(r)));
        grid(ax,'on'); box(ax,'off');
    end
    scatterFile=fullfile(outputDir,'Step12b_six_strongest_correlations.png');
    exportgraphics(fs,scatterFile,'Resolution',300); figureFiles(end+1)=string(scatterFile); %#ok<AGROW>
    if strcmpi(vis,'off'), close(fs); end
end

%% ------------------------------------------------------------------------
% 11) Save outputs
% -------------------------------------------------------------------------
settings = o;
settings.RootDir = rootDir;
settings.Step9File = step9File;
settings.Step10bFile = step10bFile;
settings.ResponseMarkerFile = responseMarkerFile;
settings.HeadMotionFile = headMotionFile;
settings.QuestionnaireFile = questionnaireFile;
settings.HeadMotionActualLagRangeSec = actualHeadRange;
settings.HeadMotionLagIndices = hIdx;
settings.NeuralFeatureCaveat = [ ...
    'Neural ROI masks were selected from the full-sample Step10b within-lag ', ...
    'spatial-FWER significant masks. Behaviour did not enter mask selection; ', ...
    'brain-behaviour correlations are nevertheless exploratory.'];

if o.SaveOutputs
    matFile=fullfile(outputDir,'Step12b_HyperYESNO_restricted_multimodal_correlations.mat');
    save(matFile,'masterTable','correlationTable','yesProportionPartialTable', ...
        'featureTable','neuralMaskTable','headMotionLagTable','settings','figureFiles','-v7.3');

    xlsxFile=fullfile(outputDir,'Step12b_HyperYESNO_restricted_multimodal_correlations.xlsx');
    if exist(xlsxFile,'file')==2, delete(xlsxFile); end
    writetable(masterTable,xlsxFile,'Sheet','DyadData');
    writetable(correlationTable,xlsxFile,'Sheet','Correlations');
    writetable(yesProportionPartialTable,xlsxFile,'Sheet','YESPropPartial');
    writetable(featureTable,xlsxFile,'Sheet','FeatureDefinitions');
    if ~isempty(neuralMaskTable), writetable(neuralMaskTable,xlsxFile,'Sheet','NeuralROIMasks'); end
    writetable(headMotionLagTable,xlsxFile,'Sheet','HeadMotionLags');
end

%% ------------------------------------------------------------------------
% 12) Report
% -------------------------------------------------------------------------
if o.Verbose
    fprintf('\nTop restricted correlations:\n');
    disp(correlationTable(1:min(15,height(correlationTable)), ...
        {'Variable1','Variable2','N','SpearmanRho','PValue','FDRq','SignificantFDR'}));
    fprintf('\nYES-proportion sensitivity controlling EEG trial imbalance:\n');
    disp(yesProportionPartialTable(:, ...
        {'Variable1','Variable2','N','PartialSpearmanRho','PValue','FDRq'}));
    fprintf('\nOutput folder: %s\n',outputDir);
    fprintf('============================================================\n\n');
end

end

%% ========================================================================
% Local helpers
% ========================================================================
function nums=parse_dyad_ids_local(raw)
% Robustly convert dyad identifiers such as 1, "1", "Dyad01",
% categorical values, or cell arrays of character vectors to numeric IDs.
if istable(raw)
    nums=get_dyad_numbers_local(raw);
    return
end
if isnumeric(raw) || islogical(raw)
    nums=double(raw(:));
    return
end
s=string(raw(:));
nums=nan(numel(s),1);
for k=1:numel(s)
    tok=regexp(char(s(k)),'\d+','match','once');
    if ~isempty(tok)
        nums(k)=str2double(tok);
    end
end
if any(~isfinite(nums))
    bad=find(~isfinite(nums));
    error('step12b:DyadParse', ...
        'Could not parse %d head-motion dyad identifier(s), first bad index %d.', ...
        numel(bad),bad(1));
end
end

function nums=get_dyad_numbers_local(T)
if ismember('DyadNumber',T.Properties.VariableNames)
    raw=T.DyadNumber;
elseif ismember('Dyad',T.Properties.VariableNames)
    raw=T.Dyad;
else
    vars=string(T.Properties.VariableNames);
    idx=find(strcmpi(vars,'Dyad'),1);
    if isempty(idx), error('Could not identify questionnaire Dyad column.'); end
    raw=T{:,idx};
end
if isnumeric(raw) || islogical(raw)
    nums=double(raw(:));
else
    s=string(raw(:)); nums=nan(numel(s),1);
    for k=1:numel(s)
        tok=regexp(s(k),'\d+','match','once');
        if ~isempty(tok), nums(k)=str2double(tok); end
    end
end
end

function name=find_variable_local(T,wanted)
vars=string(T.Properties.VariableNames);
idx=find(strcmpi(vars,wanted),1);
if isempty(idx), error('Could not find variable %s.',wanted); end
name=char(vars(idx));
end

function x=to_numeric_local(raw)
if isnumeric(raw) || islogical(raw)
    x=double(raw(:)); return
end
if iscell(raw)
    s=string(raw(:));
elseif iscategorical(raw) || isstring(raw) || ischar(raw)
    s=string(raw(:));
else
    s=string(raw(:));
end
x=str2double(s);
end

function vals=map_table_by_dyad_local(T,varName)
keys=get_dyad_numbers_local(T);
values=to_numeric_local(T.(varName));
vals=map_values_local(keys,values,(1:35)');
end

function out=map_values_local(keys,values,target)
keys=double(keys(:)); values=double(values(:)); target=double(target(:));
out=nan(numel(target),1);
for k=1:numel(target)
    idx=find(keys==target(k),1,'first');
    if ~isempty(idx), out(k)=values(idx); end
end
end

function idx=nearest_lag_index_local(lags,target,tol,label)
[d,idx]=min(abs(lags-target));
if d>tol
    error('step12b:LagMissing','%s does not contain requested lag %+g ms (nearest %+g ms).', ...
        label,target,lags(idx));
end
end

function [rho,p]=spearman_local(x,y)
x=x(:); y=y(:); n=numel(x);
if n<3 || numel(unique(x))<2 || numel(unique(y))<2
    rho=NaN; p=NaN; return
end
rx=tiedrank_local(x); ry=tiedrank_local(y);
rho=pearson_local(rx,ry);
if ~isfinite(rho)
    p=NaN; return
end
rho=max(min(rho,1),-1);
if abs(rho)>=1
    p=0; return
end
df=n-2;
t=abs(rho)*sqrt(df/max(1-rho^2,eps));
p=student_t_two_sided_local(t,df);
end

function [rho,p]=partial_spearman_local(x,y,z)
x=x(:);y=y(:);z=z(:);n=numel(x);
if n<4 || numel(unique(x))<2 || numel(unique(y))<2 || numel(unique(z))<2
    rho=NaN;p=NaN;return
end
rx=tiedrank_local(x); ry=tiedrank_local(y); rz=tiedrank_local(z);
Z=[ones(n,1) rz];
ex=rx-Z*(Z\rx); ey=ry-Z*(Z\ry);
rho=pearson_local(ex,ey);
if ~isfinite(rho), p=NaN; return; end
rho=max(min(rho,1),-1);
if abs(rho)>=1, p=0; return; end
df=n-3;
t=abs(rho)*sqrt(df/max(1-rho^2,eps));
p=student_t_two_sided_local(t,df);
end

function r=pearson_local(x,y)
x=x(:);y=y(:);x=x-mean(x);y=y-mean(y);
den=sqrt(sum(x.^2)*sum(y.^2));
if den<=0 || ~isfinite(den), r=NaN; else, r=sum(x.*y)/den; end
end

function r=tiedrank_local(x)
x=x(:); [xs,ord]=sort(x); n=numel(x); rs=zeros(n,1); i=1;
while i<=n
    j=i;
    while j<n && xs(j+1)==xs(i), j=j+1; end
    rs(i:j)=mean(i:j);
    i=j+1;
end
r=zeros(n,1); r(ord)=rs;
end

function p=student_t_two_sided_local(t,df)
if ~isfinite(t) || df<=0, p=NaN; return; end
if t==0, p=1; return; end
x=df/(df+t^2);
p=betainc(x,df/2,0.5);
p=min(max(p,0),1);
end

function q=bh_fdr_local(p)
p=p(:); q=nan(size(p)); valid=isfinite(p); pv=p(valid); m=numel(pv);
if m==0, return; end
[ps,ord]=sort(pv); qs=ps.*m./(1:m)'; qs=flipud(cummin(flipud(qs))); qs=min(qs,1);
qv=nan(m,1); qv(ord)=qs; q(valid)=qv;
end
