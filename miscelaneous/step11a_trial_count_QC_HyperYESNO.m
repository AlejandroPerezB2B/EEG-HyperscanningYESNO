function [roleCountTable, dyadCountTable, groupSummaryTable] = ...
    step11a_trial_count_QC_HyperYESNO(rootDir, varargin)
% STEP11A_TRIAL_COUNT_QC_HYPERYESNO
% Quantify YES/NO trial-count imbalance for the HyperYESNO GCMI analysis.
%
% This is the first part of the trial-count sensitivity analysis. It does
% not recalculate GCMI. It reads the exact trial counts retained by Step 7
% (via Step 9) and asks, separately for A-Knower and B-Knower situations,
% whether YES and NO contributed different numbers of matched dyadic epochs.
%
% The matched trial count used by the subsequent sensitivity analysis is:
%
%   matchedN(dyad,role) = min(N_YES, N_NO)
%
% Thus the lower-count condition is retained completely and the higher-count
% condition can later be repeatedly subsampled to matchedN trials.
%
% OUTPUTS
% -------
% roleCountTable
%   One row per dyad x Knower role (35 x 2 = 70 rows).
%
% dyadCountTable
%   One row per dyad, summarising both roles.
%
% groupSummaryTable
%   Group-level descriptive summary for A-Knower, B-Knower and pooled roles.
%
% SAVED OUTPUTS
% -------------
% rootDir/Group_GCMI/Trial_Count_Sensitivity/
%   Step11a_HyperYESNO_trial_count_QC.mat
%   Step11a_HyperYESNO_trial_count_QC.xlsx
%   Step11a_trial_counts_scatter.png
%   Step11a_trial_count_imbalance_by_dyad.png
%
% EXAMPLE
% -------
% [roleCountTable, dyadCountTable, groupSummaryTable] = ...
%     step11a_trial_count_QC_HyperYESNO('E:\EEG_data_HyperYESNO');
%
% Author: Alejandro Perez / OpenAI-assisted implementation
% HyperYESNO project, 2026

%% Inputs
if nargin < 1 || isempty(rootDir)
    rootDir = 'E:\EEG_data_HyperYESNO';
end
rootDir = char(string(rootDir));

groupFolder = fullfile(rootDir, 'Group_GCMI');
defaultStep9 = fullfile(groupFolder, ...
    'Step9_HyperYESNO_surrogate_corrected_GCMI.mat');
defaultOutput = fullfile(groupFolder, 'Trial_Count_Sensitivity');

p = inputParser;
p.FunctionName = mfilename;
addRequired(p, 'rootDir', @(x)ischar(x) || (isstring(x)&&isscalar(x)));
addParameter(p, 'Step9File', defaultStep9, ...
    @(x)ischar(x) || (isstring(x)&&isscalar(x)));
addParameter(p, 'OutputFolder', defaultOutput, ...
    @(x)ischar(x) || (isstring(x)&&isscalar(x)));
addParameter(p, 'SaveOutputs', true, @(x)islogical(x)&&isscalar(x));
addParameter(p, 'SaveFigures', true, @(x)islogical(x)&&isscalar(x));
addParameter(p, 'FigureVisible', 'on', ...
    @(x)any(strcmpi(string(x), ["on","off"])));
addParameter(p, 'Verbose', true, @(x)islogical(x)&&isscalar(x));
parse(p, rootDir, varargin{:});
o = p.Results;

step9File = char(string(o.Step9File));
outputFolder = char(string(o.OutputFolder));
figVisible = char(lower(string(o.FigureVisible)));

if exist(step9File, 'file') ~= 2
    error('step11a:MissingStep9', 'Step 9 file not found:\n%s', step9File);
end
if (o.SaveOutputs || o.SaveFigures) && exist(outputFolder,'dir') ~= 7
    mkdir(outputFolder);
end

%% Load Step 9
S = load(step9File, 'step9Data');
if ~isfield(S,'step9Data') || ~isstruct(S.step9Data)
    error('step11a:InvalidStep9', 'The MAT file does not contain step9Data.');
end
D = S.step9Data;

required = {'dyadNumbers','situations','numberOfTrials'};
missing = required(~isfield(D,required));
if ~isempty(missing)
    error('step11a:MissingFields', 'Missing Step 9 fields: %s', ...
        strjoin(string(missing), ', '));
end

dyads = double(D.dyadNumbers(:));
situations = string(D.situations(:));
trialCounts = double(D.numberOfTrials);

if size(trialCounts,1) ~= numel(dyads) || size(trialCounts,2) ~= numel(situations)
    error('step11a:DimensionMismatch', ...
        'numberOfTrials dimensions do not match dyad/situation metadata.');
end

idxYESA = find(situations == "YES_AKnower",1);
idxNOA  = find(situations == "NO_AKnower",1);
idxYESB = find(situations == "YES_BKnower",1);
idxNOB  = find(situations == "NO_BKnower",1);
if any(cellfun(@isempty,{idxYESA,idxNOA,idxYESB,idxNOB}))
    error('step11a:MissingSituation', 'One or more required situations are missing.');
end

%% Build one row per dyad x role
nDyad = numel(dyads);
nRows = nDyad*2;
Dyad = nan(nRows,1);
DyadName = strings(nRows,1);
KnowerRole = strings(nRows,1);
YES_Trials = nan(nRows,1);
NO_Trials = nan(nRows,1);
MatchedTrials = nan(nRows,1);
SignedDifferenceYESminusNO = nan(nRows,1);
AbsoluteDifference = nan(nRows,1);
PercentDifferenceRelativeToSmaller = nan(nRows,1);
LargerCondition = strings(nRows,1);
TrialsDiscardedFromLargerCondition = nan(nRows,1);

r = 0;
for d = 1:nDyad
    for role = 1:2
        r = r + 1;
        if role == 1
            iY = idxYESA; iN = idxNOA; roleName = "A_Knower";
        else
            iY = idxYESB; iN = idxNOB; roleName = "B_Knower";
        end
        ny = trialCounts(d,iY);
        nn = trialCounts(d,iN);
        mn = min(ny,nn);

        Dyad(r) = dyads(d);
        DyadName(r) = compose("Dyad%02d",dyads(d));
        KnowerRole(r) = roleName;
        YES_Trials(r) = ny;
        NO_Trials(r) = nn;
        MatchedTrials(r) = mn;
        SignedDifferenceYESminusNO(r) = ny-nn;
        AbsoluteDifference(r) = abs(ny-nn);
        TrialsDiscardedFromLargerCondition(r) = abs(ny-nn);

        if isfinite(mn) && mn > 0
            PercentDifferenceRelativeToSmaller(r) = 100*abs(ny-nn)/mn;
        end
        if ny > nn
            LargerCondition(r) = "YES";
        elseif nn > ny
            LargerCondition(r) = "NO";
        elseif isfinite(ny) && isfinite(nn)
            LargerCondition(r) = "Equal";
        else
            LargerCondition(r) = "Missing";
        end
    end
end

roleCountTable = table(Dyad,DyadName,KnowerRole,YES_Trials,NO_Trials, ...
    MatchedTrials,SignedDifferenceYESminusNO,AbsoluteDifference, ...
    PercentDifferenceRelativeToSmaller,LargerCondition, ...
    TrialsDiscardedFromLargerCondition);

%% One row per dyad
A = roleCountTable(roleCountTable.KnowerRole=="A_Knower",:);
B = roleCountTable(roleCountTable.KnowerRole=="B_Knower",:);

Dyad = dyads;
DyadName = compose("Dyad%02d",dyads);
YES_AKnower = A.YES_Trials;
NO_AKnower = A.NO_Trials;
Matched_AKnower = A.MatchedTrials;
YES_BKnower = B.YES_Trials;
NO_BKnower = B.NO_Trials;
Matched_BKnower = B.MatchedTrials;
TotalYES = YES_AKnower + YES_BKnower;
TotalNO = NO_AKnower + NO_BKnower;
TotalSignedDifferenceYESminusNO = TotalYES-TotalNO;
TotalAbsoluteDifference = abs(TotalSignedDifferenceYESminusNO);
MeanAbsoluteRoleImbalance = mean([A.AbsoluteDifference B.AbsoluteDifference],2,'omitnan');
MinimumMatchedTrialsAcrossRoles = min([Matched_AKnower Matched_BKnower],[],2);

dyadCountTable = table(Dyad,DyadName,YES_AKnower,NO_AKnower,Matched_AKnower, ...
    YES_BKnower,NO_BKnower,Matched_BKnower,TotalYES,TotalNO, ...
    TotalSignedDifferenceYESminusNO,TotalAbsoluteDifference, ...
    MeanAbsoluteRoleImbalance,MinimumMatchedTrialsAcrossRoles);

%% Group summary
labels = ["A_Knower";"B_Knower";"Pooled_roles"];
meanYES = nan(3,1); meanNO = nan(3,1); medianYES = nan(3,1); medianNO = nan(3,1);
meanSigned = nan(3,1); medianSigned = nan(3,1); meanAbs = nan(3,1); medianAbs = nan(3,1);
propYESMore = nan(3,1); propNOMore = nan(3,1); propEqual = nan(3,1); medianMatched = nan(3,1);

for k = 1:3
    if k==1
        y=A.YES_Trials; n=A.NO_Trials; m=A.MatchedTrials;
    elseif k==2
        y=B.YES_Trials; n=B.NO_Trials; m=B.MatchedTrials;
    else
        y=[A.YES_Trials;B.YES_Trials]; n=[A.NO_Trials;B.NO_Trials]; m=[A.MatchedTrials;B.MatchedTrials];
    end
    delta=y-n;
    valid=isfinite(y)&isfinite(n);
    meanYES(k)=mean(y(valid),'omitnan'); meanNO(k)=mean(n(valid),'omitnan');
    medianYES(k)=median(y(valid),'omitnan'); medianNO(k)=median(n(valid),'omitnan');
    meanSigned(k)=mean(delta(valid),'omitnan'); medianSigned(k)=median(delta(valid),'omitnan');
    meanAbs(k)=mean(abs(delta(valid)),'omitnan'); medianAbs(k)=median(abs(delta(valid)),'omitnan');
    propYESMore(k)=mean(delta(valid)>0); propNOMore(k)=mean(delta(valid)<0); propEqual(k)=mean(delta(valid)==0);
    medianMatched(k)=median(m(valid),'omitnan');
end

groupSummaryTable = table(labels,meanYES,meanNO,medianYES,medianNO, ...
    meanSigned,medianSigned,meanAbs,medianAbs,propYESMore,propNOMore, ...
    propEqual,medianMatched, ...
    'VariableNames',{'Role','MeanYES','MeanNO','MedianYES','MedianNO', ...
    'MeanYESminusNO','MedianYESminusNO','MeanAbsoluteImbalance', ...
    'MedianAbsoluteImbalance','ProportionYESMore','ProportionNOMore', ...
    'ProportionEqual','MedianMatchedTrials'});

%% Figures
figureFiles = strings(0,1);
if o.SaveFigures
    % Scatter YES vs NO
    f1 = figure('Color','w','Visible',figVisible,'Name','HyperYESNO trial-count QC');
    tiledlayout(f1,1,2,'Padding','compact','TileSpacing','compact');
    roleTables = {A,B}; roleTitles = {'A-Knower','B-Knower'};
    limMax = max([roleCountTable.YES_Trials;roleCountTable.NO_Trials],[],'omitnan');
    if ~isfinite(limMax), limMax=1; end
    for k=1:2
        ax=nexttile;
        scatter(ax,roleTables{k}.YES_Trials,roleTables{k}.NO_Trials,42,'filled'); hold(ax,'on');
        plot(ax,[0 limMax],[0 limMax],'--','LineWidth',1.2);
        xlabel(ax,'YES trials'); ylabel(ax,'NO trials'); title(ax,roleTitles{k});
        axis(ax,'square'); xlim(ax,[0 limMax*1.05]); ylim(ax,[0 limMax*1.05]); grid(ax,'on'); box(ax,'off');
    end
    sgtitle(f1,'Trial counts entering the all-trials GCMI analysis');
    file1=fullfile(outputFolder,'Step11a_trial_counts_scatter.png');
    exportgraphics(f1,file1,'Resolution',250); figureFiles(end+1)=string(file1);

    % Signed imbalance by dyad
    f2 = figure('Color','w','Visible',figVisible,'Name','HyperYESNO trial imbalance');
    tiledlayout(f2,2,1,'Padding','compact','TileSpacing','compact');
    ax=nexttile; bar(ax,dyads,A.SignedDifferenceYESminusNO); yline(ax,0,'--');
    xlabel(ax,'Dyad'); ylabel(ax,'YES - NO trials'); title(ax,'A-Knower'); box(ax,'off');
    ax=nexttile; bar(ax,dyads,B.SignedDifferenceYESminusNO); yline(ax,0,'--');
    xlabel(ax,'Dyad'); ylabel(ax,'YES - NO trials'); title(ax,'B-Knower'); box(ax,'off');
    file2=fullfile(outputFolder,'Step11a_trial_count_imbalance_by_dyad.png');
    exportgraphics(f2,file2,'Resolution',250); figureFiles(end+1)=string(file2);
end

%% Save
if o.SaveOutputs
    matFile=fullfile(outputFolder,'Step11a_HyperYESNO_trial_count_QC.mat');
    save(matFile,'roleCountTable','dyadCountTable','groupSummaryTable','figureFiles','step9File','-v7.3');

    xlsxFile=fullfile(outputFolder,'Step11a_HyperYESNO_trial_count_QC.xlsx');
    if exist(xlsxFile,'file')==2, delete(xlsxFile); end
    writetable(roleCountTable,xlsxFile,'Sheet','DyadRoleCounts');
    writetable(dyadCountTable,xlsxFile,'Sheet','DyadSummary');
    writetable(groupSummaryTable,xlsxFile,'Sheet','GroupSummary');
end

if o.Verbose
    fprintf('\n============================================================\n');
    fprintf('Step 11a trial-count QC complete.\n');
    fprintf('Dyads: %d\n',nDyad);
    fprintf('Median matched trials A-Knower: %.1f\n',median(A.MatchedTrials,'omitnan'));
    fprintf('Median matched trials B-Knower: %.1f\n',median(B.MatchedTrials,'omitnan'));
    fprintf('Output folder: %s\n',outputFolder);
    fprintf('============================================================\n');
end
end
