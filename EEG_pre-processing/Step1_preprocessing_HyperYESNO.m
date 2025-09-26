%% Batch import + trigger extraction + stuff + save per dyad & participant
% Configure your data root (folder containing the Curry files)
data_path = 'D:\EEG_data_HyperYESNO';
assert(isfolder(data_path), 'Data path not found: %s', data_path);

% Subjects to process (Curry files expected like "Acquisition <ID>.dap")
subject_ids = [41, 45:78];

for k = 1:numel(subject_ids)
    subj    = subject_ids(k);
    dyadStr = sprintf('Dyad%02d', k);
    cfile   = fullfile(data_path, sprintf('Acquisition %d.dap', subj));
    outDir  = fullfile(data_path, dyadStr);
    if ~exist(outDir,'dir'), mkdir(outDir); end

    fprintf('\n=== [%s] Subject %d → %s ===\n', datestr(now,'HH:MM:SS'), subj, dyadStr);

    % --- Load raw Curry data (keep trigger channel, use EEGLAB default locations) ---
    EEG = loadcurry(cfile, 'KeepTriggerChannel','True', 'CurryLocations','False');

    % --- Trigger extraction (your specialized functions) ---
    if subj == 41
        EEG = triggers_with_findpeaks_InFirstDyad(EEG);
    else
        EEG = triggers_with_findpeaks(EEG);
    end

    % --- Save as EEGLAB .set inside the per-dyad folder ---
    setName = sprintf('%s.set', dyadStr);
    EEG.data = single(EEG.data);                % halves size; EEGLAB is fine with single
    EEG = pop_saveset(EEG, 'filename', setName, 'filepath', outDir,'savemode','twofiles');
    EEG = pop_resample(EEG, 250);               % big runtime win
    fprintf('Saved: %s\n', fullfile(outDir, setName));

    % Remove trigger channel
    ti = find(strcmpi({EEG.chanlocs.labels},'TRIGGER'),1);
    EEG = pop_select(EEG,'nochannel',ti);

    % Trim robustly: keep ≤5 s before first event and ≤5 s after last event
    latSamp    = [EEG.event.latency];
    fs     = EEG.srate;
    tFirst = min(latSamp)/fs;    % seconds
    tLast  = max(latSamp)/fs;    % seconds
    tStart  = max(EEG.xmin, tFirst - 5);
    tEnd    = min(EEG.xmax, tLast  + 5);
    EEG     = pop_select(EEG,'time',[tStart tEnd]);

    % Split by channels: 1–64 → SubjA, 65–128 → SubjB
    EEG_A = pop_select(EEG,'channel',1:64);  EEG_A.setname = 'SubjA';
    EEG_B = pop_select(EEG,'channel',65:128); EEG_B.setname = 'SubjB';

    EEG_A.chanlocs(60).labels='I1'; % Change label CB1
    EEG_A.chanlocs(64).labels='I2'; % Change label CB2

    % Preserve the impedance values since chanedit will erase it
    imp = [EEG_A.chanlocs.impedance];
    md_imp = [EEG_A.chanlocs.median_impedance];

    % Load template ONLY on A, then copy geometry to B (preserve B impedances)
    tmpp  = which('standard-10-5-cap385.elp');
    EEG_A = pop_chanedit(EEG_A, 'lookup', tmpp);

    % Put impedance back
    nCh = numel(EEG_A.chanlocs);
    for ch = 1:nCh
        EEG_A.chanlocs(ch).impedance         = imp(ch);
        EEG_A.chanlocs(ch).median_impedance  = md_imp(ch);
    end

    EEG_A = eeg_checkset(EEG_A, 'chanconsist');

    % Copy the new loc values to EEG_B except the impedance ones
    fieldsToCopy = {'labels','type','theta','radius','X','Y','Z', ...
        'sph_theta','sph_phi','sph_radius','urchan','ref'};
    for ch = 1:nCh
        for kf = 1:numel(fieldsToCopy)
            fn = fieldsToCopy{kf};
            EEG_B.chanlocs(ch).(fn) = EEG_A.chanlocs(ch).(fn);
        end
        % keep EEG_B.chanlocs(ch).impedance / .median_impedance as-is
    end

    EEG_B = eeg_checkset(EEG_B, 'chanconsist');

    % Remove mastoids unused
    EEG_A = pop_select( EEG_A, 'rmchannel',{'M1','M2'});
    EEG_B = pop_select( EEG_B, 'rmchannel',{'M1','M2'});

    % Save halves
    subA_dir = fullfile(outDir,'SubjA');
    subB_dir = fullfile(outDir,'SubjB');
    if ~exist(subA_dir,'dir'), mkdir(subA_dir); end
    if ~exist(subB_dir,'dir'), mkdir(subB_dir); end

    EEG_A = pop_saveset(EEG_A, 'filename', sprintf('%s-A.set', dyadStr), 'filepath', subA_dir,'savemode','twofiles');
    EEG_B = pop_saveset(EEG_B, 'filename', sprintf('%s-B.set', dyadStr), 'filepath', subB_dir,'savemode','twofiles');

end


