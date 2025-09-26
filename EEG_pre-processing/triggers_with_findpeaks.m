function EEG = triggers_with_findpeaks(EEG)
% Takes the information contained in the trigger channel of the EEG data
% recorded from Nueuroscan amplifiers with Curry software (old version) and 
% creates events according to the event markers used on HyperYESNO experiment.
%
% Input:  EEG data in EEGLAB format (.set)
% Output: .set including on the EEG.event: conditions names and codes
%
% Author: Alejandro Perez, Tenerife, 2025-09-25

trigLab = 'TRIGGER';
% Pick trigger channel by label
ti = find(strcmpi({EEG.chanlocs.labels}, trigLab), 1);
if isempty(ti), error('Trigger channel not found'); end
trig = EEG.data(ti,:);

[pks,locs] = findpeaks(trig,'MinPeakHeight',100239); % value of the base mask

% Mapping: numeric code -> label
lab = containers.Map('KeyType','double','ValueType','char');
lab(100240) = 'BlockStart';
lab(100241) = 'YES_AKnower';
lab(100242) = 'NO_AKnower';
lab(100244) = 'YES_BKnower';
lab(100248) = 'NO_BKnower';
lab(100243) = 'resp3';
lab(100252) = 'resp12';

% Build EEGLAB events with numeric in .value and recoded string in .type
n = numel(pks);
EEG.event = repmat(struct('type','','latency',0,'urevent',0,'value',NaN), 1, n);
for k = 1:n
    code = double(pks(k));
    EEG.event(k).value   = code;                       % keep the number here
    EEG.event(k).type = 'unknow';
    % recoded label
    if isKey(lab,code), EEG.event(k).type = lab(code); end

    EEG.event(k).latency = double(locs(k));            % sample index
    EEG.event(k).urevent = k;
end

EEG = eeg_checkset(EEG,'eventconsistency');

% --- Post-pass: drop consecutive 'BlockStart' (keep the last), renumber urevent
isB  = strcmp({EEG.event.type}, 'BlockStart');
d    = diff([false isB false]);                                       % run starts/ends
sRun = find(d==1); eRun = find(d==-1)-1;

kill = [];
for r = 1:numel(sRun)
    if eRun(r) > sRun(r)                                              % run length >= 2
        kill = [kill sRun(r):eRun(r)-1];                              %#ok<AGROW>
    end
end
if ~isempty(kill)
    EEG.event(kill) = [];                                             % remove duplicates
    for k = 1:numel(EEG.event), EEG.event(k).urevent = k; end         % reindex urevent
end
EEG = eeg_checkset(EEG,'eventconsistency');

if sum(strcmp({EEG.event.type},'BlockStart'))>32, warning('Case %s has more than the 32 trials expected.', EEG.filename); end

end
