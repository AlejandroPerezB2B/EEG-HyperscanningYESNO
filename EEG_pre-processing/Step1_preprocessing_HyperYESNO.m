%% Batch import + trigger extraction + save per dyad
% Configure your data root (folder containing the Curry files)
data_path = 'D:\EEG_data_HyperYESNO';
assert(isfolder(data_path), 'Data path not found: %s', data_path);

% Subjects to process (Curry files expected like "Acquisition <ID>.dap")
subject_ids = [41, 45:47];

for k = 1:numel(subject_ids)
    subj = subject_ids(k);
    dyadIdx = k;                      % running counter for dyads (1..N)
    dyadStr = sprintf('Dyad%02d',dyadIdx);  % e.g., Dyad01, Dyad02, ...

    % Build full path to the Curry file (loadcurry will look for companion files)
    cfile = fullfile(data_path, sprintf('Acquisition %d.dap', subj));

    % Create output folder for this dyad
    outDir = fullfile(data_path, dyadStr);
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

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
        EEG = pop_saveset(EEG, 'filename', setName, 'filepath', outDir);
        fprintf('Saved: %s\n', fullfile(outDir, setName));

end

