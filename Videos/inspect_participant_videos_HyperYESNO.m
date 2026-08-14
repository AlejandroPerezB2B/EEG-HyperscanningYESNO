function [codingTable, dyadSummary] = inspect_participant_videos_HyperYESNO(varargin)
% INSPECT_PARTICIPANT_VIDEOS_HYPERYESNO
%
% Rapid manual review of the 70 HyperYESNO motion-preview videos.
%
% Expected files:
%   <Root>\Dyad##\Dyad##-A_cut\Dyad##-A_motion_preview.mp4
%   <Root>\Dyad##\Dyad##-B_cut\Dyad##-B_motion_preview.mp4
%
% Keyboard controls:
%   F = Female
%   M = Male
%   U = Unclear
%   Right arrow / N / Space = next frame position
%   Left arrow / B          = previous frame position
%   S = skip this participant for now
%   Q = save and quit
%
% Progress is saved after every classification and is automatically loaded
% next time the function is run.
%
% IMPORTANT:
% This function stores a MANUAL VISUAL CATEGORY. A visual classification
% should not be treated as equivalent to self-reported sex or gender.
%
% Example:
%   inspect_participant_videos_HyperYESNO
%
% HyperYESNO project

%% Inputs

p = inputParser;

addParameter(p,'RootDir','E:\HyperYESNO_videosCUT', ...
    @(x)ischar(x)||isstring(x));
addParameter(p,'Dyads',1:35,@(x)isnumeric(x)&&isvector(x));
addParameter(p,'InitialTimeSec',1,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(p,'NavigationStepSec',1,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'SkipExisting',true,@(x)islogical(x)||isnumeric(x));
addParameter(p,'OutputDir','',@(x)ischar(x)||isstring(x));

parse(p,varargin{:});

rootDir = char(p.Results.RootDir);
dyads = p.Results.Dyads(:)';
initialTimeSec = double(p.Results.InitialTimeSec);
navigationStepSec = double(p.Results.NavigationStepSec);
skipExisting = logical(p.Results.SkipExisting);
outputDir = char(p.Results.OutputDir);

% Try the older HyperYESNO path automatically if needed.
if ~isfolder(rootDir)
    altRoot = 'E:\HyperYESNO\_videosCUT';
    if strcmpi(rootDir,'E:\HyperYESNO_videosCUT') && isfolder(altRoot)
        rootDir = altRoot;
        fprintf('Using existing folder:\n%s\n\n',rootDir);
    else
        error('Root folder not found:\n%s',rootDir);
    end
end

if isempty(outputDir)
    outputDir = fullfile(rootDir,'_video_analysis');
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

csvFile = fullfile(outputDir, ...
    'HyperYESNO_video_visual_category_coding.csv');
matFile = fullfile(outputDir, ...
    'HyperYESNO_video_visual_category_coding.mat');
summaryCSV = fullfile(outputDir, ...
    'HyperYESNO_video_visual_category_dyad_summary.csv');

%% Build participant table

nParticipants = numel(dyads)*2;

Participant = strings(nParticipants,1);
Dyad = strings(nParticipants,1);
Member = strings(nParticipants,1);
VisualCategory = strings(nParticipants,1);
FrameTimeSec = NaN(nParticipants,1);
CodedAt = NaT(nParticipants,1);
FileFound = false(nParticipants,1);
VideoFile = strings(nParticipants,1);

r = 0;

for d = dyads
    dyadStr = sprintf('Dyad%02d',d);

    for member = ["A","B"]
        r = r+1;

        Participant(r) = dyadStr + "-" + member;
        Dyad(r) = dyadStr;
        Member(r) = member;

        partDir = fullfile(rootDir,dyadStr, ...
            sprintf('%s-%s_cut',dyadStr,member));

        expectedFile = fullfile(partDir, ...
            sprintf('%s-%s_motion_preview.mp4',dyadStr,member));

        if isfile(expectedFile)
            VideoFile(r) = string(expectedFile);
            FileFound(r) = true;
        else
            f = dir(fullfile(partDir,'*motion_preview.mp4'));

            if numel(f)==1
                VideoFile(r) = string(fullfile(f(1).folder,f(1).name));
                FileFound(r) = true;
            else
                VideoFile(r) = string(expectedFile);
            end
        end
    end
end

codingTable = table(Participant,Dyad,Member,VisualCategory, ...
    FrameTimeSec,CodedAt,FileFound,VideoFile);

%% Load previous coding if present

if isfile(csvFile)
    try
        old = readtable(csvFile,'TextType','string', ...
            'VariableNamingRule','preserve');

        for i = 1:height(codingTable)
            j = find(string(old.Participant)==codingTable.Participant(i),1);

            if isempty(j)
                continue;
            end

            if ismember('VisualCategory',old.Properties.VariableNames)
                codingTable.VisualCategory(i) = ...
                    string(old.VisualCategory(j));
            end

            if ismember('FrameTimeSec',old.Properties.VariableNames)
                codingTable.FrameTimeSec(i) = ...
                    double(old.FrameTimeSec(j));
            end

            if ismember('CodedAt',old.Properties.VariableNames)
                try
                    codingTable.CodedAt(i) = datetime(old.CodedAt(j));
                catch
                end
            end
        end

        fprintf('Loaded previous coding:\n%s\n\n',csvFile);

    catch ME
        warning('Previous coding file could not be loaded: %s',ME.message);
    end
end

%% Create review window

fig = figure( ...
    'Name','HyperYESNO participant video review', ...
    'NumberTitle','off', ...
    'Color','w', ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'WindowKeyPressFcn',@keyCallback, ...
    'CloseRequestFcn',@closeCallback);

ax = axes('Parent',fig,'Position',[0.02 0.08 0.96 0.88]);
axis(ax,'off');

setappdata(fig,'Action','');

%% Review participants

quitRequested = false;

for i = 1:height(codingTable)

    if quitRequested || ~isvalid(fig)
        break;
    end

    if skipExisting && ...
            strlength(strtrim(codingTable.VisualCategory(i)))>0

        fprintf('[%02d/%02d] %s already coded as %s\n', ...
            i,height(codingTable),codingTable.Participant(i), ...
            codingTable.VisualCategory(i));
        continue;
    end

    participant = codingTable.Participant(i);
    videoFile = char(codingTable.VideoFile(i));

    fprintf('\n[%02d/%02d] %s\n', ...
        i,height(codingTable),participant);

    if ~codingTable.FileFound(i) || ~isfile(videoFile)
        warning('Video not found:\n%s',videoFile);
        saveProgress();
        continue;
    end

    try
        v = VideoReader(videoFile);
    catch ME
        warning('Could not open %s: %s',participant,ME.message);
        continue;
    end

    frameTime = min(initialTimeSec,max(0,v.Duration-0.05));
    doneParticipant = false;

    while ~doneParticipant && ~quitRequested

        [frame,actualTime,ok] = getFrameAtTime(v,frameTime);

        if ~ok
            warning('Could not read a frame from %s.',participant);
            break;
        end

        frameTime = actualTime;

        cla(ax);
        image(ax,frame);
        axis(ax,'image');
        axis(ax,'off');

        title(ax,sprintf([ ...
            '%s   |   %d of %d   |   %.2f s\n' ...
            'F Female   M Male   U Unclear   |   ' ...
            'Left/Right or B/N move   |   S Skip   Q Quit'], ...
            participant,i,height(codingTable),frameTime), ...
            'Interpreter','none','FontSize',14,'FontWeight','bold');

        drawnow;

        setappdata(fig,'Action','');
        uiwait(fig);

        if ~isvalid(fig)
            quitRequested = true;
            break;
        end

        action = string(getappdata(fig,'Action'));

        switch action
            case "NEXT"
                frameTime = min(frameTime+navigationStepSec, ...
                    max(0,v.Duration-0.05));

            case "PREVIOUS"
                frameTime = max(0,frameTime-navigationStepSec);

            case "FEMALE"
                codingTable.VisualCategory(i) = "Female";
                codingTable.FrameTimeSec(i) = frameTime;
                codingTable.CodedAt(i) = datetime('now');
                fprintf('  -> Female\n');
                saveProgress();
                doneParticipant = true;

            case "MALE"
                codingTable.VisualCategory(i) = "Male";
                codingTable.FrameTimeSec(i) = frameTime;
                codingTable.CodedAt(i) = datetime('now');
                fprintf('  -> Male\n');
                saveProgress();
                doneParticipant = true;

            case "UNCLEAR"
                codingTable.VisualCategory(i) = "Unclear";
                codingTable.FrameTimeSec(i) = frameTime;
                codingTable.CodedAt(i) = datetime('now');
                fprintf('  -> Unclear\n');
                saveProgress();
                doneParticipant = true;

            case "SKIP"
                fprintf('  -> skipped\n');
                doneParticipant = true;

            case "QUIT"
                quitRequested = true;
                saveProgress();
        end
    end
end

%% Final save and summary

saveProgress();

dyadSummary = makeDyadSummary(codingTable);
writetable(dyadSummary,summaryCSV);

if isvalid(fig)
    delete(fig);
end

fprintf('\n============================================================\n');
fprintf('Visual review summary\n');
fprintf('============================================================\n');
fprintf('Female : %d\n',sum(codingTable.VisualCategory=="Female"));
fprintf('Male   : %d\n',sum(codingTable.VisualCategory=="Male"));
fprintf('Unclear: %d\n',sum(codingTable.VisualCategory=="Unclear"));
fprintf('Uncoded: %d\n',sum(strlength(strtrim( ...
    codingTable.VisualCategory))==0));

fprintf('\nFemale-Female dyads: %d\n', ...
    sum(dyadSummary.Composition=="Female-Female"));
fprintf('Male-Male dyads    : %d\n', ...
    sum(dyadSummary.Composition=="Male-Male"));
fprintf('Mixed dyads        : %d\n', ...
    sum(dyadSummary.Composition=="Mixed"));
fprintf('Incomplete/Unclear : %d\n', ...
    sum(dyadSummary.Composition=="Incomplete/Unclear"));

fprintf('\nSaved to:\n%s\n',outputDir);
fprintf('============================================================\n');

%% Nested callbacks

    function keyCallback(src,event)

        switch lower(event.Key)
            case 'f'
                action = 'FEMALE';
            case 'm'
                action = 'MALE';
            case 'u'
                action = 'UNCLEAR';
            case {'rightarrow','n','space'}
                action = 'NEXT';
            case {'leftarrow','b'}
                action = 'PREVIOUS';
            case 's'
                action = 'SKIP';
            case 'q'
                action = 'QUIT';
            otherwise
                action = '';
        end

        if ~isempty(action)
            setappdata(src,'Action',action);
            uiresume(src);
        end
    end

    function closeCallback(src,~)
        setappdata(src,'Action','QUIT');
        uiresume(src);
    end

    function saveProgress()

        try
            writetable(codingTable,csvFile);

            dyadSummaryCurrent = makeDyadSummary(codingTable);
            writetable(dyadSummaryCurrent,summaryCSV);

            save(matFile,'codingTable','dyadSummaryCurrent','rootDir');

        catch ME
            warning('Could not save progress: %s',ME.message);
        end
    end
end

%% Local functions

function [frame,actualTime,ok] = getFrameAtTime(v,requestedTime)

frame = [];
actualTime = requestedTime;
ok = false;

try
    t = min(max(0,requestedTime),max(0,v.Duration-0.05));
    v.CurrentTime = t;

    if hasFrame(v)
        frame = readFrame(v);
        actualTime = t;
        ok = true;
        return;
    end
catch
end

try
    v.CurrentTime = 0;

    if hasFrame(v)
        frame = readFrame(v);
        actualTime = 0;
        ok = true;
    end
catch
    ok = false;
end
end

function dyadSummary = makeDyadSummary(codingTable)

dyads = unique(codingTable.Dyad,'stable');

Dyad = dyads;
A_Category = strings(numel(dyads),1);
B_Category = strings(numel(dyads),1);
Composition = strings(numel(dyads),1);

for d = 1:numel(dyads)

    ia = find(codingTable.Dyad==dyads(d) & codingTable.Member=="A",1);
    ib = find(codingTable.Dyad==dyads(d) & codingTable.Member=="B",1);

    if ~isempty(ia)
        A_Category(d) = codingTable.VisualCategory(ia);
    end

    if ~isempty(ib)
        B_Category(d) = codingTable.VisualCategory(ib);
    end

    a = A_Category(d);
    b = B_Category(d);

    if a=="Female" && b=="Female"
        Composition(d) = "Female-Female";
    elseif a=="Male" && b=="Male"
        Composition(d) = "Male-Male";
    elseif (a=="Female" && b=="Male") || ...
            (a=="Male" && b=="Female")
        Composition(d) = "Mixed";
    else
        Composition(d) = "Incomplete/Unclear";
    end
end

dyadSummary = table(Dyad,A_Category,B_Category,Composition);
end
