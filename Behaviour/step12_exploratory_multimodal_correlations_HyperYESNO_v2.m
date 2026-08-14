function [masterTable, correlationTable, rankedCrossDomainTable, descriptivesTable] = ...
    step12_exploratory_multimodal_correlations_HyperYESNO_v2(varargin)
% STEP12_EXPLORATORY_MULTIMODAL_CORRELATIONS_HYPERYesNO
% -------------------------------------------------------------------------
% Exploratory DYAD-level multimodal correlation screen for HyperYESNO.
%
% This function assembles one row per dyad (Dyad01..Dyad35) from four
% already-computed data streams:
%
%   1) EEG: surrogate-corrected lagged GCMI (Step 9)
%   2) Video: surrogate-corrected interpersonal head-motion correlation
%      (video Step 3)
%   3) Behavioural response markers: YES/NO counts, YES proportion and pace
%   4) Post-interaction questionnaire: dyad mean and absolute disagreement
%
% It then performs an exploratory Spearman correlation screen across all
% numeric dyad-level variables, applies Benjamini-Hochberg FDR correction,
% saves the full matrices and a ranked CROSS-DOMAIN correlation table, and
% creates a heatmap plus scatterplots for the strongest cross-domain pairs.
%
% IMPORTANT INTERPRETIVE POINTS
% -------------------------------------------------------------------------
% - The statistical unit is always the DYAD (maximum N = 35).
% - This is explicitly exploratory/multimodal screening, not a confirmatory
%   family of hypothesis tests.
% - The principal neural features are deliberately defined WITHOUT selecting
%   the Step10/Step10b significant connections. This avoids correlating
%   behaviour with neural features selected using the same 35 dyads.
% - Questionnaire Q5 is left in its original wording. No positive composite
%   is created automatically.
% - Marker variables describe registered YES/NO response behaviour. They are
%   not behavioural accuracy or number of correctly guessed targets.
%
% DEFAULT INPUT FILES
% -------------------------------------------------------------------------
% EEG:
%   E:\EEG_data_HyperYESNO\Group_GCMI\
%       Step9_HyperYESNO_surrogate_corrected_GCMI.mat
%
% Response markers:
%   E:\EEG_data_HyperYESNO\
%       HyperYESNO_response_marker_behaviour.mat
%
% Head movement:
%   E:\HyperYESNO_videosCUT\_video_analysis\
%       HyperYESNO_video_stage3_lagged_correlations.mat
%
% Questionnaire:
%   The function searches, in order, for:
%       E:\EEG_data_HyperYESNO\Interaction_Rating_Dyad_Scores.xlsx
%       .\Interaction_Rating_Dyad_Scores.xlsx
%   or specify 'QuestionnaireFile' explicitly.
%
% OUTPUT FOLDER
% -------------------------------------------------------------------------
% Default:
%   E:\EEG_data_HyperYESNO\Group_GCMI\Step12_Multimodal_Correlations\
%
% EXAMPLE
% -------------------------------------------------------------------------
% [masterTable, correlationTable, ranked, descriptives] = ...
%     step12_exploratory_multimodal_correlations_HyperYESNO( ...
%       'QuestionnaireFile', ...
%       'E:\EEG_data_HyperYESNO\Interaction_Rating_Dyad_Scores.xlsx');
%
% To generate scatterplots for the 12 strongest cross-domain associations:
%   'TopScatterPlots', 12
%
% HyperYESNO project, 2026

%% Parse inputs
fprintf('Running Step12 multimodal correlations v2 (robust Excel import)\n');
p = inputParser;
p.FunctionName = mfilename;

addParameter(p, 'RootDir', 'E:\EEG_data_HyperYESNO', ...
    @(x)ischar(x) || isstring(x));
addParameter(p, 'Step9File', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'ResponseMarkerFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'HeadMotionFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'QuestionnaireFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'OutputDir', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'MinPairN', 20, @(x)isnumeric(x) && isscalar(x) && x>=3);
addParameter(p, 'StrongAbsRho', 0.50, @(x)isnumeric(x) && isscalar(x) && x>=0 && x<=1);
addParameter(p, 'TopScatterPlots', 12, @(x)isnumeric(x) && isscalar(x) && x>=0 && mod(x,1)==0);
addParameter(p, 'MakeFigures', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'SaveOutputs', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));
parse(p, varargin{:});
o = p.Results;

rootDir = char(string(o.RootDir));
if isempty(o.Step9File)
    step9File = fullfile(rootDir,'Group_GCMI','Step9_HyperYESNO_surrogate_corrected_GCMI.mat');
else
    step9File = char(string(o.Step9File));
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
if isempty(o.OutputDir)
    outputDir = fullfile(rootDir,'Group_GCMI','Step12_Multimodal_Correlations');
else
    outputDir = char(string(o.OutputDir));
end

questionnaireFile = resolve_questionnaire_file(char(string(o.QuestionnaireFile)), rootDir);

required = {step9File,responseMarkerFile,headMotionFile,questionnaireFile};
for k = 1:numel(required)
    if ~isfile(required{k})
        error('Required input file not found:\n%s',required{k});
    end
end
if (o.SaveOutputs || o.MakeFigures) && ~isfolder(outputDir)
    mkdir(outputDir);
end

if o.Verbose
    fprintf('\n============================================================\n');
    fprintf('HyperYESNO Step 12: exploratory multimodal correlations\n');
    fprintf('============================================================\n');
    fprintf('EEG:           %s\n',step9File);
    fprintf('Responses:     %s\n',responseMarkerFile);
    fprintf('Head movement: %s\n',headMotionFile);
    fprintf('Questionnaire: %s\n',questionnaireFile);
end

%% Master dyad skeleton
DyadNumber = (1:35)';
Dyad = string(compose('Dyad%02d',DyadNumber));
masterTable = table(DyadNumber,Dyad);
featureInfo = table(strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Variable','Domain','Definition'});

%% ------------------------------------------------------------------------
% 1) RESPONSE MARKER BEHAVIOUR
% -------------------------------------------------------------------------
R = load(responseMarkerFile);
if ~isfield(R,'dyadSummary') || ~isfield(R,'roleSummary')
    error('Response marker MAT must contain dyadSummary and roleSummary.');
end
D = R.dyadSummary;
RR = R.roleSummary;

% Overall dyad-level response behaviour.
behVars = {'NumResponses','NumYes','NumNo','YesProportion', ...
    'MedianInterResponseIntervalSec','ResponsesPerActiveMinute'};
behNames = {'Resp_Total','Resp_Yes','Resp_No','Resp_YesProportion', ...
    'Resp_MedianIntervalSec','Resp_PerActiveMinute'};
for v = 1:numel(behVars)
    if ismember(behVars{v}, D.Properties.VariableNames)
        vals = map_table_by_dyad(D, behVars{v});
        masterTable.(behNames{v}) = vals;
        featureInfo = add_feature(featureInfo,behNames{v},'ResponseBehaviour',behVars{v});
    end
end

% Role-specific behaviour retained as exploratory descriptors.
for role = ["A","B"]
    roleMask = upper(string(RR.Knower)) == role;
    Trole = RR(roleMask,:);
    suffix = char(role + "Knower");
    rolePairs = { ...
        'NumResponses',['Resp_Total_' suffix]; ...
        'NumYes',['Resp_Yes_' suffix]; ...
        'NumNo',['Resp_No_' suffix]; ...
        'YesProportion',['Resp_YesProportion_' suffix]; ...
        'MedianInterResponseIntervalSec',['Resp_MedianIntervalSec_' suffix]};
    for q = 1:size(rolePairs,1)
        if ismember(rolePairs{q,1}, Trole.Properties.VariableNames)
            masterTable.(rolePairs{q,2}) = map_table_by_dyad(Trole, rolePairs{q,1});
            featureInfo = add_feature(featureInfo,rolePairs{q,2},'ResponseBehaviourRole', ...
                sprintf('%s during %s-Knower responses',rolePairs{q,1},role));
        end
    end
end

%% ------------------------------------------------------------------------
% 2) EEG GCMI - PREDEFINED NON-CIRCULAR DYAD SUMMARIES
% -------------------------------------------------------------------------
S9 = load(step9File,'step9Data');
if ~isfield(S9,'step9Data')
    error('Step9 MAT does not contain step9Data.');
end
E = S9.step9Data;
requiredE = {'dyadNumbers','lagsMilliseconds','correctedYESRoleMean', ...
    'correctedNORoleMean','yesMinusNoPrimary','numberOfTrials'};
for k = 1:numel(requiredE)
    if ~isfield(E,requiredE{k})
        error('step9Data missing field: %s',requiredE{k});
    end
end

eegDyads = double(E.dyadNumbers(:));
lags = double(E.lagsMilliseconds(:)');
YES = double(E.correctedYESRoleMean);
NO  = double(E.correctedNORoleMean);
DIFF = double(E.yesMinusNoPrimary);

% whole ROI x lag cube mean
masterTable.Neural_YES_Global = map_array_dyad(eegDyads, squeeze(mean(YES,[1 2 3],'omitnan')));
masterTable.Neural_NO_Global  = map_array_dyad(eegDyads, squeeze(mean(NO,[1 2 3],'omitnan')));
masterTable.Neural_YESminusNO_Global = map_array_dyad(eegDyads, squeeze(mean(DIFF,[1 2 3],'omitnan')));
featureInfo = add_feature(featureInfo,'Neural_YES_Global','Neural', ...
    'Mean surrogate-corrected YES GCMI across 20x20 ROI pairs and all lags');
featureInfo = add_feature(featureInfo,'Neural_NO_Global','Neural', ...
    'Mean surrogate-corrected NO GCMI across 20x20 ROI pairs and all lags');
featureInfo = add_feature(featureInfo,'Neural_YESminusNO_Global','Neural', ...
    'Mean role-balanced surrogate-corrected YES-NO GCMI across all ROI pairs and lags');

% zero lag
[~,iZero] = min(abs(lags));
masterTable.Neural_YES_ZeroLag = map_array_dyad(eegDyads, squeeze(mean(YES(:,:,iZero,:),[1 2],'omitnan')));
masterTable.Neural_NO_ZeroLag = map_array_dyad(eegDyads, squeeze(mean(NO(:,:,iZero,:),[1 2],'omitnan')));
masterTable.Neural_YESminusNO_ZeroLag = map_array_dyad(eegDyads, squeeze(mean(DIFF(:,:,iZero,:),[1 2],'omitnan')));
featureInfo = add_feature(featureInfo,'Neural_YES_ZeroLag','Neural','Mean corrected YES GCMI across ROI pairs at zero lag');
featureInfo = add_feature(featureInfo,'Neural_NO_ZeroLag','Neural','Mean corrected NO GCMI across ROI pairs at zero lag');
featureInfo = add_feature(featureInfo,'Neural_YESminusNO_ZeroLag','Neural','Mean corrected YES-NO GCMI across ROI pairs at zero lag');

% theoretically defined lag directions, excluding zero
neg = lags < 0; pos = lags > 0;
masterTable.Neural_YESminusNO_KnowerLeading = map_array_dyad(eegDyads, ...
    squeeze(mean(DIFF(:,:,neg,:),[1 2 3],'omitnan')));
masterTable.Neural_YESminusNO_GuesserLeading = map_array_dyad(eegDyads, ...
    squeeze(mean(DIFF(:,:,pos,:),[1 2 3],'omitnan')));
featureInfo = add_feature(featureInfo,'Neural_YESminusNO_KnowerLeading','Neural', ...
    'Mean primary YES-NO contrast across all negative lags (Knower precedes Guesser)');
featureInfo = add_feature(featureInfo,'Neural_YESminusNO_GuesserLeading','Neural', ...
    'Mean primary YES-NO contrast across all positive lags (Guesser precedes Knower)');

% Trial-count QC covariates from Step9 situation order YES_A,NO_A,YES_B,NO_B.
Tn = double(E.numberOfTrials);
if size(Tn,2) >= 4
    yesTrialMean = mean(Tn(:,[1 3]),2,'omitnan');
    noTrialMean = mean(Tn(:,[2 4]),2,'omitnan');
    masterTable.EEG_TrialsYES_MeanRole = map_array_dyad(eegDyads,yesTrialMean);
    masterTable.EEG_TrialsNO_MeanRole = map_array_dyad(eegDyads,noTrialMean);
    masterTable.EEG_TrialImbalance_YESminusNO = map_array_dyad(eegDyads,yesTrialMean-noTrialMean);
    featureInfo = add_feature(featureInfo,'EEG_TrialsYES_MeanRole','TrialQC','Mean valid EEG YES epochs across A/B Knower roles');
    featureInfo = add_feature(featureInfo,'EEG_TrialsNO_MeanRole','TrialQC','Mean valid EEG NO epochs across A/B Knower roles');
    featureInfo = add_feature(featureInfo,'EEG_TrialImbalance_YESminusNO','TrialQC','YES minus NO valid EEG epoch count, averaged across roles');
end

%% ------------------------------------------------------------------------
% 3) HEAD-MOTION INTERPERSONAL CORRELATION
% -------------------------------------------------------------------------
HM = load(headMotionFile,'results','dyadLagTable');
if isfield(HM,'results') && isfield(HM.results,'YEScorrectedZ')
    H = HM.results;
    hmDyadLabels = string(H.dyadList(:));
    hmDyads = parse_dyad_numbers(hmDyadLabels);
    yesHM = double(H.YEScorrectedZ);
    noHM = double(H.NOcorrectedZ);
    diffHM = double(H.YESminusNO_Z);
    absLagSec = double(H.absLagSec(:)');

    masterTable.Motion_YES_Global = map_array_dyad(hmDyads,mean(yesHM,2,'omitnan'));
    masterTable.Motion_NO_Global = map_array_dyad(hmDyads,mean(noHM,2,'omitnan'));
    masterTable.Motion_YESminusNO_Global = map_array_dyad(hmDyads,mean(diffHM,2,'omitnan'));
    [~,hmZero] = min(abs(absLagSec));
    masterTable.Motion_YES_ZeroLag = map_array_dyad(hmDyads,yesHM(:,hmZero));
    masterTable.Motion_NO_ZeroLag = map_array_dyad(hmDyads,noHM(:,hmZero));
    masterTable.Motion_YESminusNO_ZeroLag = map_array_dyad(hmDyads,diffHM(:,hmZero));

    featureInfo = add_feature(featureInfo,'Motion_YES_Global','HeadMotion','Mean surrogate-corrected Fisher z for YES across all absolute motion lags');
    featureInfo = add_feature(featureInfo,'Motion_NO_Global','HeadMotion','Mean surrogate-corrected Fisher z for NO across all absolute motion lags');
    featureInfo = add_feature(featureInfo,'Motion_YESminusNO_Global','HeadMotion','Mean YES-NO surrogate-corrected head-motion Fisher-z difference across absolute lags');
    featureInfo = add_feature(featureInfo,'Motion_YES_ZeroLag','HeadMotion','Surrogate-corrected head-motion Fisher z for YES at zero lag');
    featureInfo = add_feature(featureInfo,'Motion_NO_ZeroLag','HeadMotion','Surrogate-corrected head-motion Fisher z for NO at zero lag');
    featureInfo = add_feature(featureInfo,'Motion_YESminusNO_ZeroLag','HeadMotion','YES-NO surrogate-corrected head-motion Fisher-z difference at zero lag');
else
    error('Head-motion MAT does not contain the expected results structure.');
end

%% ------------------------------------------------------------------------
% 4) QUESTIONNAIRE
% -------------------------------------------------------------------------
Qmean = readtable(questionnaireFile,'Sheet','Dyad scores','VariableNamingRule','preserve');
Qdiff = readtable(questionnaireFile,'Sheet','Absolute disagreement','VariableNamingRule','preserve');

qDyadMean = get_dyad_column(Qmean);
qDyadDiff = get_dyad_column(Qdiff);
for q = 1:7
    qName = sprintf('Q%d',q);
    if ismember(qName,Qmean.Properties.VariableNames)
        name = sprintf('Quest_Mean_Q%d',q);
        masterTable.(name) = map_values_by_keys(qDyadMean,to_numeric_vector(Qmean.(qName)),DyadNumber);
        featureInfo = add_feature(featureInfo,name,'QuestionnaireMean',sprintf('Dyad mean questionnaire item Q%d',q));
    end
    if ismember(qName,Qdiff.Properties.VariableNames)
        name = sprintf('Quest_Disagreement_Q%d',q);
        masterTable.(name) = map_values_by_keys(qDyadDiff,to_numeric_vector(Qdiff.(qName)),DyadNumber);
        featureInfo = add_feature(featureInfo,name,'QuestionnaireDisagreement',sprintf('Absolute A-B disagreement on questionnaire item Q%d',q));
    end
end

%% ------------------------------------------------------------------------
% Descriptive response counts for paper reporting
% -------------------------------------------------------------------------
descriptivesTable = build_response_descriptives(D,RR);

%% ------------------------------------------------------------------------
% Correlation screen
% -------------------------------------------------------------------------
allFeatureNames = featureInfo.Variable;
% Retain only features actually present in the master table.
keep = ismember(allFeatureNames,string(masterTable.Properties.VariableNames));
featureInfo = featureInfo(keep,:);
allFeatureNames = featureInfo.Variable;
X = nan(height(masterTable),numel(allFeatureNames));
for j = 1:numel(allFeatureNames)
    X(:,j) = double(masterTable.(char(allFeatureNames(j))));
end

nF = numel(allFeatureNames);
Rho = nan(nF); P = nan(nF); N = zeros(nF);
for i = 1:nF
    for j = i:nF
        valid = isfinite(X(:,i)) & isfinite(X(:,j));
        N(i,j) = sum(valid); N(j,i) = N(i,j);
        if N(i,j) >= o.MinPairN && numel(unique(X(valid,i)))>1 && numel(unique(X(valid,j)))>1
            [r,pv] = corr(X(valid,i),X(valid,j),'Type','Spearman','Rows','complete');
            Rho(i,j)=r; Rho(j,i)=r;
            P(i,j)=pv; P(j,i)=pv;
        end
    end
end

% Long-format unique-pair table.
rows = struct([]);
idx = 0;
for i = 1:nF-1
    for j = i+1:nF
        idx = idx+1;
        rows(idx).Variable1 = allFeatureNames(i);
        rows(idx).Domain1 = featureInfo.Domain(i);
        rows(idx).Variable2 = allFeatureNames(j);
        rows(idx).Domain2 = featureInfo.Domain(j);
        rows(idx).N = N(i,j);
        rows(idx).SpearmanRho = Rho(i,j);
        rows(idx).PValue = P(i,j);
        rows(idx).CrossDomain = featureInfo.Domain(i) ~= featureInfo.Domain(j);
    end
end
correlationTable = struct2table(rows);

validP = isfinite(correlationTable.PValue);
correlationTable.FDRq = nan(height(correlationTable),1);
correlationTable.FDRq(validP) = bh_fdr(correlationTable.PValue(validP));
correlationTable.AbsRho = abs(correlationTable.SpearmanRho);
correlationTable.StrongAbsRho = correlationTable.AbsRho >= o.StrongAbsRho;
correlationTable.FDR05 = correlationTable.FDRq <= 0.05;

rankedCrossDomainTable = correlationTable(correlationTable.CrossDomain & ...
    correlationTable.N >= o.MinPairN & isfinite(correlationTable.SpearmanRho),:);
rankedCrossDomainTable = sortrows(rankedCrossDomainTable, ...
    {'AbsRho','PValue'},{'descend','ascend'});

%% Save outputs
if o.SaveOutputs
    matFile = fullfile(outputDir,'Step12_HyperYESNO_multimodal_correlations.mat');
    save(matFile,'masterTable','featureInfo','Rho','P','N','correlationTable', ...
        'rankedCrossDomainTable','descriptivesTable','step9File','responseMarkerFile', ...
        'headMotionFile','questionnaireFile','-v7.3');

    xlsx = fullfile(outputDir,'Step12_HyperYESNO_multimodal_correlations.xlsx');
    if isfile(xlsx), delete(xlsx); end
    writetable(masterTable,xlsx,'Sheet','DyadData');
    writetable(descriptivesTable,xlsx,'Sheet','ResponseDescriptives');
    writetable(featureInfo,xlsx,'Sheet','FeatureDictionary');
    writetable(correlationTable,xlsx,'Sheet','AllPairCorrelations');
    writetable(rankedCrossDomainTable,xlsx,'Sheet','RankedCrossDomain');

    writetable(array2table(Rho,'VariableNames',cellstr(allFeatureNames), ...
        'RowNames',cellstr(allFeatureNames)),xlsx,'Sheet','SpearmanRho','WriteRowNames',true);
    writetable(array2table(P,'VariableNames',cellstr(allFeatureNames), ...
        'RowNames',cellstr(allFeatureNames)),xlsx,'Sheet','PValues','WriteRowNames',true);
end

%% Figures
if o.MakeFigures
    % Full correlation heatmap.
    try
        f = figure('Color','w','Position',[40 40 1500 1200]);
        imagesc(Rho,[-1 1]); axis square;
        colorbar;
        xticks(1:nF); yticks(1:nF);
        xticklabels(allFeatureNames); yticklabels(allFeatureNames);
        xtickangle(90);
        set(gca,'TickLabelInterpreter','none','FontSize',7);
        title('HyperYESNO exploratory dyad-level Spearman correlations');
        exportgraphics(f,fullfile(outputDir,'Step12_multimodal_correlation_heatmap.png'),'Resolution',250);
    catch ME
        warning('Could not create correlation heatmap: %s',ME.message);
    end

    % Strongest cross-domain scatterplots.
    nPlot = min(o.TopScatterPlots,height(rankedCrossDomainTable));
    for k = 1:nPlot
        try
            v1 = char(rankedCrossDomainTable.Variable1(k));
            v2 = char(rankedCrossDomainTable.Variable2(k));
            x = masterTable.(v1); y = masterTable.(v2);
            valid = isfinite(x) & isfinite(y);
            f = figure('Color','w','Position',[100 100 700 600]);
            scatter(x(valid),y(valid),55,'filled'); hold on;
            if sum(valid)>=3
                lsline;
            end
            xlabel(strrep(v1,'_',' '),'Interpreter','none');
            ylabel(strrep(v2,'_',' '),'Interpreter','none');
            title(sprintf('Spearman rho = %.3f, p = %.4g, FDR q = %.4g, N = %d', ...
                rankedCrossDomainTable.SpearmanRho(k), ...
                rankedCrossDomainTable.PValue(k), ...
                rankedCrossDomainTable.FDRq(k), ...
                rankedCrossDomainTable.N(k)));
            grid on; box off;
            fileName = sprintf('TopCorr_%02d_%s__%s.png',k,safe_name(v1),safe_name(v2));
            exportgraphics(f,fullfile(outputDir,fileName),'Resolution',220);
            close(f);
        catch ME
            warning('Could not create scatterplot %d: %s',k,ME.message);
        end
    end
end

if o.Verbose
    fprintf('\nDyads in master table: %d\n',height(masterTable));
    fprintf('Variables screened: %d\n',nF);
    fprintf('Cross-domain pairs: %d\n',height(rankedCrossDomainTable));
    if ~isempty(rankedCrossDomainTable)
        nStrong = sum(rankedCrossDomainTable.StrongAbsRho);
        nFDR = sum(rankedCrossDomainTable.FDR05);
        fprintf('|rho| >= %.2f: %d cross-domain pairs\n',o.StrongAbsRho,nStrong);
        fprintf('FDR q <= .05: %d cross-domain pairs\n',nFDR);
        disp(rankedCrossDomainTable(1:min(15,height(rankedCrossDomainTable)), ...
            {'Variable1','Domain1','Variable2','Domain2','N','SpearmanRho','PValue','FDRq'}));
    end
    fprintf('Output folder: %s\n',outputDir);
    fprintf('============================================================\n\n');
end
end

%% ========================================================================
function questionnaireFile = resolve_questionnaire_file(requested,rootDir)
if ~isempty(requested)
    questionnaireFile = requested;
    return
end
candidates = { ...
    fullfile(rootDir,'Interaction_Rating_Dyad_Scores.xlsx'), ...
    fullfile(pwd,'Interaction_Rating_Dyad_Scores.xlsx')};
questionnaireFile = candidates{1};
for k = 1:numel(candidates)
    if isfile(candidates{k})
        questionnaireFile = candidates{k}; return
    end
end
end

function vals = map_table_by_dyad(T,varName)
if ismember('DyadNumber',T.Properties.VariableNames)
    keys = to_numeric_vector(T.DyadNumber);
elseif ismember('Dyad',T.Properties.VariableNames)
    keys = parse_dyad_numbers(string(T.Dyad));
else
    error('Table has no DyadNumber or Dyad variable.');
end
vals = map_values_by_keys(keys,to_numeric_vector(T.(varName)),(1:35)');
end

function vals = map_array_dyad(keys,data)
vals = map_values_by_keys(double(keys(:)),double(data(:)),(1:35)');
end

function out = map_values_by_keys(keys,values,target)
out = nan(numel(target),1);
for k = 1:numel(target)
    idx = find(keys==target(k),1,'first');
    if ~isempty(idx), out(k)=values(idx); end
end
end

function nums = parse_dyad_numbers(labels)
labels = string(labels(:)); nums = nan(numel(labels),1);
for k=1:numel(labels)
    tok = regexp(labels(k),'\d+','match','once');
    if ~isempty(tok), nums(k)=str2double(tok); end
end
end

function featureInfo = add_feature(featureInfo,varName,domain,definition)
featureInfo = [featureInfo; table(string(varName),string(domain),string(definition), ...
    'VariableNames',featureInfo.Properties.VariableNames)]; %#ok<AGROW>
end

function dyads = get_dyad_column(T)
% Robustly read dyad identifiers regardless of how Excel imported them.
% They may be numeric (1,2,...), strings ("Dyad01"), categorical, or cells.
if ismember('Dyad',T.Properties.VariableNames)
    raw = T.Dyad;
elseif ismember('DyadNumber',T.Properties.VariableNames)
    raw = T.DyadNumber;
else
    % Sometimes imported files may contain an index column before Dyad.
    vars = string(T.Properties.VariableNames);
    j = find(strcmpi(vars,'Dyad'),1);
    if isempty(j), error('Could not identify Dyad column in questionnaire sheet.'); end
    raw = T{:,j};
end

if isnumeric(raw) || islogical(raw)
    dyads = double(raw(:));
else
    % Handles cell arrays, strings, chars and categoricals such as
    % {'Dyad01';'Dyad02'} or {'1';'2'}.
    dyads = parse_dyad_numbers(string(raw));
end
end

function x = to_numeric_vector(raw)
% Convert a table column imported from Excel/MAT into a numeric column.
% MATLAB readtable may return numeric data as cell/string depending on the
% workbook contents and formatting; direct double(cellArray) then fails.
if isnumeric(raw) || islogical(raw)
    x = double(raw(:));
    return
end

if iscell(raw)
    % cell2mat is safe only when every cell is already scalar numeric.
    if all(cellfun(@(c) isnumeric(c) && isscalar(c), raw(:)))
        x = cellfun(@double, raw(:));
        return
    end
end

s = string(raw(:));
s = strtrim(s);
s(ismissing(s) | s=="" | lower(s)=="nan" | lower(s)=="na") = missing;
x = str2double(s);
end

function q = bh_fdr(p)
p = p(:); m = numel(p);
[ps,ord] = sort(p);
qs = ps .* m ./ (1:m)';
qs = flipud(cummin(flipud(qs)));
qs = min(qs,1);
q = nan(m,1); q(ord)=qs;
end

function T = build_response_descriptives(D,RR)
rows = struct([]); n=0;
% Overall + A/B roles.
sets = {D,'Overall'; RR(upper(string(RR.Knower))=="A",:),'A-Knower'; ...
    RR(upper(string(RR.Knower))=="B",:),'B-Knower'};
vars = {'NumResponses','NumYes','NumNo','YesProportion','MedianInterResponseIntervalSec'};
for s=1:size(sets,1)
    T0 = sets{s,1}; label=sets{s,2};
    for v=1:numel(vars)
        if ~ismember(vars{v},T0.Properties.VariableNames), continue; end
        x = to_numeric_vector(T0.(vars{v})); x=x(isfinite(x));
        n=n+1; rows(n).Scope=string(label); rows(n).Measure=string(vars{v});
        rows(n).N=numel(x); rows(n).Mean=mean(x,'omitnan'); rows(n).SD=std(x,0,'omitnan');
        rows(n).Median=median(x,'omitnan'); rows(n).Min=min(x); rows(n).Max=max(x);
    end
end
T = struct2table(rows);
end

function s = safe_name(s)
s = regexprep(s,'[^A-Za-z0-9]+','_');
if strlength(string(s))>60, s=s(1:60); end
end
