function [sensitivityData, dyadSensitivityTable, lagSummaryTable, selectionLogTable] = ...
    step11b_matched_trial_GCMI_sensitivity_HyperYESNO(rootDir, varargin)
% STEP11B_MATCHED_TRIAL_GCMI_SENSITIVITY_HYPERYESNO
% Recalculate the HyperYESNO YES-NO GCMI contrast after repeatedly matching
% YES and NO trial counts within each dyad and Knower role.
%
% PURPOSE
% -------
% The primary HyperYESNO analysis uses all available valid epochs. Therefore
% YES and NO can have different numbers of trials. This sensitivity analysis
% asks whether the observed YES-NO pattern depends materially on that trial
% imbalance.
%
% For each dyad and role separately:
%
%   matchedN = min(N_YES, N_NO)
%
% The lower-count condition is retained in full. On each repetition, the
% higher-count condition is randomly subsampled to matchedN trials. Crucially,
% the same selected trial indices are applied to the Knower and Guesser data,
% so the genuine trial pairing within that condition is preserved.
%
% The analysis is repeated many times because there are many possible
% subsets of the higher-count condition. The balanced YES-NO contrast is
% then averaged across repetitions.
%
% ANALYSIS MODES
% --------------
% 'Observed' (recommended first pass)
%   Recalculates observed GCMI only. This is the cleanest and much faster
%   test of whether unequal sample size changes the YES-NO GCMI pattern.
%   The all-trials comparator is also observed GCMI, so the comparison is
%   like-for-like.
%
% 'SurrogateCorrected' (stricter, slower follow-up)
%   For each randomly selected subset, computes observed GCMI and paired-
%   trial derangement surrogates, then uses:
%
%       corrected GCMI = observed - mean(surrogates)
%
%   The unchanged lower-count condition is taken directly from the existing
%   Step 9 corrected result, which is preferable because it was estimated
%   from the full original surrogate set.
%
% ROLE BALANCING
% --------------
% For every repetition and dyad:
%
%   contrast_A = YES_AKnower - NO_AKnower
%   contrast_B = YES_BKnower - NO_BKnower
%
%   primary = 0.5 * (contrast_A + contrast_B)
%
% Thus the dyad remains the statistical unit and the two role configurations
% receive equal weight, exactly as in the main Step 9 analysis.
%
% DEFAULTS
% --------
% NumRepeats       = 25  (use 100 for the final observed-only run if runtime permits)
% AnalysisMode     = 'Observed'
% NumSurrogates    = 49  (used only in SurrogateCorrected mode)
% MinimumMatchedTrials = 2
%
% OUTPUTS
% -------
% sensitivityData
%   Full 20 x 20 x lag x dyad mean balanced contrast, SD across repetitions,
%   original all-trials comparator, group maps, lag profiles and metadata.
%
% dyadSensitivityTable
%   One row per dyad with matched trial counts and agreement between the
%   original and balanced connectivity maps.
%
% lagSummaryTable
%   One row per lag comparing the original and balanced group-average
%   YES-minus-NO contrast after averaging across ROI pairs within each dyad.
%
% selectionLogTable
%   Reproducibility log of the randomly selected trials from the larger
%   condition for every dyad x role x repetition.
%
% SAVED OUTPUTS
% -------------
% rootDir/Group_GCMI/Trial_Count_Sensitivity/
%   Step11b_HyperYESNO_matched_trial_GCMI_sensitivity_<mode>.mat
%   Step11b_HyperYESNO_matched_trial_GCMI_sensitivity_<mode>.xlsx
%   Step11b_<mode>_lag_profile.png
%   Step11b_<mode>_original_vs_balanced_map.png
%
% EXAMPLES
% --------
% Recommended first run:
%   [S,T,L,Sel] = step11b_matched_trial_GCMI_sensitivity_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       'AnalysisMode','Observed', ...
%       'NumRepeats',25);
%
% Final observed-only sensitivity after checking runtime:
%   [S,T,L,Sel] = step11b_matched_trial_GCMI_sensitivity_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       'AnalysisMode','Observed', ...
%       'NumRepeats',100);
%
% Stricter surrogate-corrected sensitivity:
%   [S,T,L,Sel] = step11b_matched_trial_GCMI_sensitivity_HyperYESNO( ...
%       'E:\EEG_data_HyperYESNO', ...
%       'AnalysisMode','SurrogateCorrected', ...
%       'NumRepeats',20, ...
%       'NumSurrogates',49);
%
% Author: Alejandro Perez / OpenAI-assisted implementation
% HyperYESNO project, 2026

%% Inputs
if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end
rootDir = char(string(rootDir));

groupFolder = fullfile(rootDir,'Group_GCMI');
defaultStep9 = fullfile(groupFolder,'Step9_HyperYESNO_surrogate_corrected_GCMI.mat');
defaultOutput = fullfile(groupFolder,'Trial_Count_Sensitivity');

p=inputParser;
p.FunctionName=mfilename;
addRequired(p,'rootDir',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'Step9File',defaultStep9,@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'EpochFolderName','GCMI_Epochs',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'AnalysisMode','Observed',@(x)any(strcmpi(string(x),["Observed","SurrogateCorrected"])));
addParameter(p,'NumRepeats',25,@(x)isnumeric(x)&&isscalar(x)&&x>=1&&x==round(x));
addParameter(p,'NumSurrogates',49,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x==round(x));
addParameter(p,'MinimumMatchedTrials',2,@(x)isnumeric(x)&&isscalar(x)&&x>=1&&x==round(x));
addParameter(p,'RandomSeed',20260810,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x==round(x));
addParameter(p,'UseParallelSurrogates',false,@(x)islogical(x)&&isscalar(x));
addParameter(p,'OutputFolder',defaultOutput,@(x)ischar(x)||(isstring(x)&&isscalar(x)));
addParameter(p,'SaveOutputs',true,@(x)islogical(x)&&isscalar(x));
addParameter(p,'SaveFigures',true,@(x)islogical(x)&&isscalar(x));
addParameter(p,'FigureVisible','on',@(x)any(strcmpi(string(x),["on","off"])));
addParameter(p,'Verbose',true,@(x)islogical(x)&&isscalar(x));
parse(p,rootDir,varargin{:});
o=p.Results;

step9File=char(string(o.Step9File));
epochFolderName=char(string(o.EpochFolderName));
outputFolder=char(string(o.OutputFolder));
analysisMode=lower(string(o.AnalysisMode));
figVisible=char(lower(string(o.FigureVisible)));

if exist(step9File,'file')~=2
    error('step11b:MissingStep9','Step 9 file not found:\n%s',step9File);
end
if exist('pop_loadset','file')~=2
    error('step11b:MissingEEGLAB','pop_loadset was not found. Start EEGLAB first.');
end
if exist('lagged_gcmi_dyad','file')~=2 || exist('copnorm','file')~=2
    error('step11b:MissingGCMI','lagged_gcmi_dyad.m and copnorm.m must be on the MATLAB path.');
end
if analysisMode=="surrogatecorrected" && o.NumSurrogates<1
    error('step11b:NeedSurrogates','SurrogateCorrected mode requires NumSurrogates >= 1.');
end
if (o.SaveOutputs||o.SaveFigures) && exist(outputFolder,'dir')~=7
    mkdir(outputFolder);
end

%% Load Step 9
S=load(step9File,'step9Data');
if ~isfield(S,'step9Data') || ~isstruct(S.step9Data)
    error('step11b:InvalidStep9','The MAT file does not contain step9Data.');
end
D=S.step9Data;
req={'dyadNumbers','situations','numberOfTrials','gcmiObserved','correctedBySituation', ...
    'roiLabelsKnower','roiLabelsGuesser','lagsMilliseconds','samplingRate'};
missing=req(~isfield(D,req));
if ~isempty(missing)
    error('step11b:MissingFields','Missing Step 9 fields: %s',strjoin(string(missing),', '));
end

dyads=double(D.dyadNumbers(:));
situations=string(D.situations(:));
counts=double(D.numberOfTrials);
lagsMs=double(D.lagsMilliseconds(:)');
srate=double(D.samplingRate);
roiK=cellstr(string(D.roiLabelsKnower(:)));
roiG=cellstr(string(D.roiLabelsGuesser(:)));

idxYESA=find(situations=="YES_AKnower",1); idxNOA=find(situations=="NO_AKnower",1);
idxYESB=find(situations=="YES_BKnower",1); idxNOB=find(situations=="NO_BKnower",1);
if any(cellfun(@isempty,{idxYESA,idxNOA,idxYESB,idxNOB}))
    error('step11b:MissingSituation','Required YES/NO role situations are missing.');
end

if analysisMode=="observed"
    originalBySituation=double(D.gcmiObserved);
    modeLabel="Observed";
else
    originalBySituation=double(D.correctedBySituation);
    modeLabel="SurrogateCorrected";
end

sz=size(originalBySituation);
if numel(sz)<5, sz(5)=1; end
nK=sz(1); nG=sz(2); nLag=sz(3); nDyad=sz(4);
if nDyad~=numel(dyads) || sz(5)~=numel(situations)
    error('step11b:DimensionMismatch','Step 9 array dimensions do not match metadata.');
end

%% Original all-trials primary comparator
origA=originalBySituation(:,:,:,:,idxYESA)-originalBySituation(:,:,:,:,idxNOA);
origB=originalBySituation(:,:,:,:,idxYESB)-originalBySituation(:,:,:,:,idxNOB);
originalPrimary=0.5*(origA+origB);

%% Output allocation: running mean/variance across repetitions
balancedMean=nan(nK,nG,nLag,nDyad);
balancedSD=nan(nK,nG,nLag,nDyad);
validDyad=false(nDyad,1);
matchedA=nan(nDyad,1); matchedB=nan(nDyad,1);
selectionRows=struct([]);

for d=1:nDyad
    dyadNum=dyads(d);
    dyadStr=sprintf('Dyad%02d',dyadNum);
    nYA=counts(d,idxYESA); nNA=counts(d,idxNOA);
    nYB=counts(d,idxYESB); nNB=counts(d,idxNOB);
    matchedA(d)=min(nYA,nNA); matchedB(d)=min(nYB,nNB);

    if any(~isfinite([nYA nNA nYB nNB])) || ...
            matchedA(d)<o.MinimumMatchedTrials || matchedB(d)<o.MinimumMatchedTrials
        if o.Verbose
            fprintf('%s skipped: insufficient/missing matched trials.\n',dyadStr);
        end
        continue
    end

    validDyad(d)=true;
    if o.Verbose
        fprintf('\n============================================================\n');
        fprintf('%s matched-trial sensitivity (%s)\n',dyadStr,modeLabel);
        fprintf('A-Knower YES/NO: %d/%d -> %d matched\n',nYA,nNA,matchedA(d));
        fprintf('B-Knower YES/NO: %d/%d -> %d matched\n',nYB,nNB,matchedB(d));
        fprintf('============================================================\n');
    end

    % Load only conditions that actually need subsampling.
    cache=struct;
    if nYA>matchedA(d), cache.YESA=load_epoch_pair(rootDir,dyadStr,'YES_AKnower',epochFolderName); end
    if nNA>matchedA(d), cache.NOA =load_epoch_pair(rootDir,dyadStr,'NO_AKnower', epochFolderName); end
    if nYB>matchedB(d), cache.YESB=load_epoch_pair(rootDir,dyadStr,'YES_BKnower',epochFolderName); end
    if nNB>matchedB(d), cache.NOB =load_epoch_pair(rootDir,dyadStr,'NO_BKnower', epochFolderName); end

    % Confirm loaded Step 6 counts against Step 9 counts.
    check_cached_count(cache,'YESA',nYA); check_cached_count(cache,'NOA',nNA);
    check_cached_count(cache,'YESB',nYB); check_cached_count(cache,'NOB',nNB);

    runningMean=zeros(nK,nG,nLag);
    runningM2=zeros(nK,nG,nLag);
    nAccum=0;

    for rep=1:o.NumRepeats
        % Role A
        [yesA,selYA,genYA]=condition_measure('YESA',nYA,matchedA(d),idxYESA, ...
            originalBySituation(:,:,:,d,idxYESA),cache,dyadNum,1,rep,1,o,lagsMs,analysisMode,roiK,roiG);
        [noA,selNA,genNA]=condition_measure('NOA',nNA,matchedA(d),idxNOA, ...
            originalBySituation(:,:,:,d,idxNOA),cache,dyadNum,1,rep,2,o,lagsMs,analysisMode,roiK,roiG);
        % Role B
        [yesB,selYB,genYB]=condition_measure('YESB',nYB,matchedB(d),idxYESB, ...
            originalBySituation(:,:,:,d,idxYESB),cache,dyadNum,2,rep,1,o,lagsMs,analysisMode,roiK,roiG);
        [noB,selNB,genNB]=condition_measure('NOB',nNB,matchedB(d),idxNOB, ...
            originalBySituation(:,:,:,d,idxNOB),cache,dyadNum,2,rep,2,o,lagsMs,analysisMode,roiK,roiG);

        primary=0.5*((yesA-noA)+(yesB-noB));
        nAccum=nAccum+1;
        delta=primary-runningMean;
        runningMean=runningMean+delta/nAccum;
        runningM2=runningM2+delta.*(primary-runningMean);

        selectionRows=append_selection(selectionRows,dyadNum,rep,'A_Knower', ...
            nYA,nNA,matchedA(d),selYA,selNA,genYA,genNA);
        selectionRows=append_selection(selectionRows,dyadNum,rep,'B_Knower', ...
            nYB,nNB,matchedB(d),selYB,selNB,genYB,genNB);
    end

    balancedMean(:,:,:,d)=runningMean;
    if nAccum>1
        balancedSD(:,:,:,d)=sqrt(runningM2/(nAccum-1));
    else
        balancedSD(:,:,:,d)=zeros(nK,nG,nLag);
    end
end

if isempty(selectionRows)
    selectionLogTable=table();
else
    selectionLogTable=struct2table(selectionRows);
end

%% Comparison summaries
analysisDyads=validDyad & squeeze(all(all(all(isfinite(originalPrimary),1),2),3));
if ~any(analysisDyads)
    error('step11b:NoValidDyads','No dyads had complete original and balanced results.');
end

origGroup=mean(originalPrimary(:,:,:,analysisDyads),4,'omitnan');
balGroup=mean(balancedMean(:,:,:,analysisDyads),4,'omitnan');
diffGroup=balGroup-origGroup;

origVec=origGroup(:); balVec=balGroup(:);
validVec=isfinite(origVec)&isfinite(balVec);
if sum(validVec)>2
    C=corrcoef(origVec(validVec),balVec(validVec)); groupMapCorrelation=C(1,2);
    groupMapSignAgreement=mean(sign(origVec(validVec))==sign(balVec(validVec)));
else
    groupMapCorrelation=NaN; groupMapSignAgreement=NaN;
end

% Dyad-level agreement
nValid=sum(analysisDyads);
Dyad=dyads;
DyadName=compose("Dyad%02d",dyads);
ValidForSensitivity=analysisDyads;
MatchedTrials_AKnower=matchedA;
MatchedTrials_BKnower=matchedB;
OriginalMeanAcrossMap=nan(nDyad,1);
BalancedMeanAcrossMap=nan(nDyad,1);
BalancedMinusOriginalMean=nan(nDyad,1);
MapCorrelation=nan(nDyad,1);
MapSignAgreement=nan(nDyad,1);

for d=1:nDyad
    if ~analysisDyads(d), continue; end
    x=originalPrimary(:,:,:,d); y=balancedMean(:,:,:,d);
    OriginalMeanAcrossMap(d)=mean(x(:),'omitnan');
    BalancedMeanAcrossMap(d)=mean(y(:),'omitnan');
    BalancedMinusOriginalMean(d)=BalancedMeanAcrossMap(d)-OriginalMeanAcrossMap(d);
    v=isfinite(x(:))&isfinite(y(:));
    if sum(v)>2
        C=corrcoef(x(v),y(v)); MapCorrelation(d)=C(1,2);
        MapSignAgreement(d)=mean(sign(x(v))==sign(y(v)));
    end
end

dyadSensitivityTable=table(Dyad,DyadName,ValidForSensitivity, ...
    MatchedTrials_AKnower,MatchedTrials_BKnower,OriginalMeanAcrossMap, ...
    BalancedMeanAcrossMap,BalancedMinusOriginalMean,MapCorrelation,MapSignAgreement);

% Lag summary: each dyad contributes one scalar = average over 400 ROI pairs.
LagMs=lagsMs(:);
N_Dyads=repmat(nValid,nLag,1);
OriginalGroupMean=nan(nLag,1); BalancedGroupMean=nan(nLag,1);
BalancedMinusOriginal=nan(nLag,1); OriginalSEM=nan(nLag,1); BalancedSEM=nan(nLag,1);
for l=1:nLag
    xo=nan(nValid,1); xb=nan(nValid,1); q=0;
    for d=find(analysisDyads(:))'
        q=q+1;
        tmp=originalPrimary(:,:,l,d); xo(q)=mean(tmp(:),'omitnan');
        tmp=balancedMean(:,:,l,d); xb(q)=mean(tmp(:),'omitnan');
    end
    OriginalGroupMean(l)=mean(xo,'omitnan'); BalancedGroupMean(l)=mean(xb,'omitnan');
    BalancedMinusOriginal(l)=mean(xb-xo,'omitnan');
    OriginalSEM(l)=std(xo,0,'omitnan')/sqrt(sum(isfinite(xo)));
    BalancedSEM(l)=std(xb,0,'omitnan')/sqrt(sum(isfinite(xb)));
end
lagSummaryTable=table(LagMs,N_Dyads,OriginalGroupMean,OriginalSEM, ...
    BalancedGroupMean,BalancedSEM,BalancedMinusOriginal);

%% Assemble output
sensitivityData=struct;
sensitivityData.analysisMode=modeLabel;
sensitivityData.description='Repeated within-dyad, within-role YES/NO trial-count matching sensitivity analysis';
sensitivityData.numRepeats=o.NumRepeats;
sensitivityData.numSurrogatesRequested=o.NumSurrogates;
sensitivityData.minimumMatchedTrials=o.MinimumMatchedTrials;
sensitivityData.randomSeed=o.RandomSeed;
sensitivityData.dyadNumbers=dyads;
sensitivityData.validDyad=analysisDyads;
sensitivityData.matchedTrialsAKnower=matchedA;
sensitivityData.matchedTrialsBKnower=matchedB;
sensitivityData.lagsMilliseconds=lagsMs;
sensitivityData.roiLabelsKnower=string(roiK(:));
sensitivityData.roiLabelsGuesser=string(roiG(:));
sensitivityData.originalPrimaryAllTrials=originalPrimary;
sensitivityData.balancedPrimaryMeanAcrossRepeats=balancedMean;
sensitivityData.balancedPrimarySDAcrossRepeats=balancedSD;
sensitivityData.balancedMinusOriginal=balancedMean-originalPrimary;
sensitivityData.groupMeanOriginal=origGroup;
sensitivityData.groupMeanBalanced=balGroup;
sensitivityData.groupMeanBalancedMinusOriginal=diffGroup;
sensitivityData.groupMapCorrelation=groupMapCorrelation;
sensitivityData.groupMapSignAgreement=groupMapSignAgreement;
sensitivityData.settings=o;
sensitivityData.created=datestr(now,30);

%% Figures
figureFiles=strings(0,1);
if o.SaveFigures
    f1=figure('Color','w','Visible',figVisible,'Name','Matched-trial GCMI lag profile');
    hold on;
    errorbar(LagMs,OriginalGroupMean,OriginalSEM,'-o','LineWidth',1.3,'DisplayName','All trials');
    errorbar(LagMs,BalancedGroupMean,BalancedSEM,'-o','LineWidth',1.3,'DisplayName','Trial matched');
    yline(0,'--','HandleVisibility','off');
    xlabel('Lag (ms)'); ylabel('Mean YES - NO GCMI across ROI pairs');
    title(sprintf('%s GCMI: all trials versus repeated trial matching',modeLabel));
    legend('Location','best'); grid on; box off;
    file1=fullfile(outputFolder,sprintf('Step11b_%s_lag_profile.png',char(lower(modeLabel))));
    exportgraphics(f1,file1,'Resolution',250); figureFiles(end+1)=string(file1);

    f2=figure('Color','w','Visible',figVisible,'Name','Original vs balanced map');
    scatter(origVec(validVec),balVec(validVec),16,'filled'); hold on;
    lo=min([origVec(validVec);balVec(validVec)]); hi=max([origVec(validVec);balVec(validVec)]);
    plot([lo hi],[lo hi],'--','LineWidth',1.2);
    xlabel('All-trials group map'); ylabel('Trial-matched group map');
    title(sprintf('%s: map agreement, r = %.3f',modeLabel,groupMapCorrelation));
    axis square; grid on; box off;
    file2=fullfile(outputFolder,sprintf('Step11b_%s_original_vs_balanced_map.png',char(lower(modeLabel))));
    exportgraphics(f2,file2,'Resolution',250); figureFiles(end+1)=string(file2);
end
sensitivityData.figureFiles=figureFiles;

%% Save
if o.SaveOutputs
    modeFile=char(lower(modeLabel));
    matFile=fullfile(outputFolder,sprintf('Step11b_HyperYESNO_matched_trial_GCMI_sensitivity_%s.mat',modeFile));
    save(matFile,'sensitivityData','dyadSensitivityTable','lagSummaryTable','selectionLogTable','-v7.3');
    xlsxFile=fullfile(outputFolder,sprintf('Step11b_HyperYESNO_matched_trial_GCMI_sensitivity_%s.xlsx',modeFile));
    if exist(xlsxFile,'file')==2, delete(xlsxFile); end
    writetable(dyadSensitivityTable,xlsxFile,'Sheet','DyadSensitivity');
    writetable(lagSummaryTable,xlsxFile,'Sheet','LagSummary');
    if ~isempty(selectionLogTable)
        writetable(selectionLogTable,xlsxFile,'Sheet','TrialSelections');
    end
end

if o.Verbose
    fprintf('\n============================================================\n');
    fprintf('Step 11b matched-trial sensitivity complete.\n');
    fprintf('Mode: %s\n',modeLabel);
    fprintf('Valid dyads: %d / %d\n',sum(analysisDyads),nDyad);
    fprintf('Group-map correlation all-trials vs balanced: %.4f\n',groupMapCorrelation);
    fprintf('Group-map sign agreement: %.1f%%\n',100*groupMapSignAgreement);
    fprintf('Output folder: %s\n',outputFolder);
    fprintf('============================================================\n');
end
end

%% ------------------------------------------------------------------------
function pair=load_epoch_pair(rootDir,dyadStr,situation,epochFolderName)
folder=fullfile(rootDir,dyadStr,epochFolderName,situation);
if exist(folder,'dir')~=7
    error('step11b:MissingEpochFolder','Epoch folder missing: %s',folder);
end
kf=dir(fullfile(folder,[dyadStr '_' situation '_Knower_from*.set']));
gf=dir(fullfile(folder,[dyadStr '_' situation '_Guesser_from*.set']));
if numel(kf)~=1 || numel(gf)~=1
    error('step11b:EpochFileCount','Expected one Knower and one Guesser SET file in %s',folder);
end
K=pop_loadset('filename',kf(1).name,'filepath',folder);
G=pop_loadset('filename',gf(1).name,'filepath',folder);
if K.trials~=G.trials || K.pnts~=G.pnts || abs(double(K.srate)-double(G.srate))>1e-9
    error('step11b:EpochMismatch','Knower/Guesser epoch mismatch in %s',folder);
end
pair.K=K; pair.G=G; pair.nTrials=K.trials;
end

%% ------------------------------------------------------------------------
function check_cached_count(cache,fieldName,expectedN)
if isfield(cache,fieldName)
    if cache.(fieldName).nTrials~=expectedN
        error('step11b:CountMismatch','%s Step 6 trials (%d) differ from Step 9 count (%d).', ...
            fieldName,cache.(fieldName).nTrials,expectedN);
    end
end
end

%% ------------------------------------------------------------------------
function [measure,selectedIdx,nGenerated] = condition_measure(cacheField,nOriginal,nMatched,~, ...
    originalMeasure,cache,dyadNum,roleIndex,rep,conditionIndex,o,lagsMs,analysisMode,roiK,roiG)
% If already at matched N, no subsampling is needed; use the existing Step 9
% measure exactly. Otherwise recalculate on a random subset.
if nOriginal==nMatched
    measure=originalMeasure;
    selectedIdx=1:nOriginal;
    nGenerated=NaN;
    return
end
if ~isfield(cache,cacheField)
    error('step11b:MissingCache','Missing cached epoch data for %s.',cacheField);
end
pair=cache.(cacheField);
seed=o.RandomSeed + dyadNum*100000 + roleIndex*10000 + rep*10 + conditionIndex;
rng(seed,'twister');
selectedIdx=sort(randperm(nOriginal,nMatched));
Kdata=pair.K.data(:,:,selectedIdx);
Gdata=pair.G.data(:,:,selectedIdx);

if analysisMode=="observed"
    nSurr=0;
else
    nSurr=o.NumSurrogates;
end
res=lagged_gcmi_dyad(Kdata,Gdata,pair.K.srate, ...
    'LagsMs',lagsMs, ...
    'NumSurrogates',nSurr, ...
    'RandomSeed',seed+5000000, ...
    'ChannelLabelsA',roiK, ...
    'ChannelLabelsB',roiG, ...
    'UseParallel',o.UseParallelSurrogates, ...
    'OutputFile','', ...
    'Verbose',false);

if analysisMode=="observed"
    measure=double(res.gcmiObserved);
else
    measure=double(res.gcmiObserved)-double(res.gcmiSurrogateMean);
end
if isfield(res,'numberOfSurrogatesGenerated')
    nGenerated=res.numberOfSurrogatesGenerated;
else
    nGenerated=nSurr;
end
end

%% ------------------------------------------------------------------------
function rows=append_selection(rows,dyadNum,rep,roleName,nY,nN,nMatched,selY,selN,genY,genN)
r.Dyad=dyadNum;
r.DyadName=string(sprintf('Dyad%02d',dyadNum));
r.Repetition=rep;
r.KnowerRole=string(roleName);
r.YESOriginalTrials=nY;
r.NOOriginalTrials=nN;
r.MatchedTrials=nMatched;
r.YESSelectedIndices=string(mat2str(selY));
r.NOSelectedIndices=string(mat2str(selN));
r.YESSurrogatesGenerated=genY;
r.NOSurrogatesGenerated=genN;
if isempty(rows), rows=r; else, rows(end+1,1)=r; end %#ok<AGROW>
end
