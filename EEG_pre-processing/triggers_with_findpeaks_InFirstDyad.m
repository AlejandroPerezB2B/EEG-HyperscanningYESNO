function EEG = triggers_with_findpeaks_InFirstDyad(EEG)
% Takes the information contained in the trigger channel of the EEG data
% recorded from Nueuroscan amplifiers with Curry software (old version) and
% creates events according to the event markers used ONLY in the PILOT dyad
% of HyperYESNO experiment.
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

lab(1000001) = 'YES_AKnower';
lab(1100001) = 'NO_AKnower';
lab(1200001) = 'NO_BKnower';
lab(1200002) = 'YES_BKnower';

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

EEG.event(1:7) = [];                                             % remove
for k = 1:numel(EEG.event), EEG.event(k).urevent = k; end         % reindex urevent

end
