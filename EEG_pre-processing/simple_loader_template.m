%% Simple loader over Dyadxx/SubjA|SubjB with name pattern and save
rootDir     = 'D:\EEG_data_HyperYESNO';   % <-- change if needed
dyads       = 1:35;                       % Dyad01..Dyad35
tags        = {'A','B'};                  % SubjA, SubjB
namePattern = '*';                        % suffix after base name (e.g., '', '_filt*', '_filt_asr*')
saveSuffix  = '_PREP';                    % appended before .set when saving

% Make sure EEGLAB is on path and initialized (run eeglab first)
for d = dyads
    dyadStr = sprintf('Dyad%02d', d);
    for ti = 1:numel(tags)
        tag    = tags{ti};                        % 'A' or 'B'
        subjDir= fullfile(rootDir, dyadStr, ['Subj' tag]);
        base   = sprintf('Dyad%02d-%s', d, tag);  % e.g., Dyad04-A

        % Find the .set to load (EEGLAB will auto-load paired .fdt)
        patSet = [base, namePattern, '.set'];
        L = dir(fullfile(subjDir, patSet));
        if isempty(L)
            fprintf('No match in %s for "%s"\n', subjDir, patSet);
            continue
        end
        % If multiple matches, pick the newest
        [~,ix] = max([L.datenum]); setFile = L(ix).name;

        % ---- Load
        EEG = pop_loadset('filename', setFile, 'filepath', subjDir);

        % ==== YOUR PROCESSING GOES HERE ==================================
        % EEG = my_processing_function(EEG);   % <--- place your function
        % =================================================================

        % ---- Save (same folder, new suffix)
        outName = [base, saveSuffix, '.set'];
        EEG = pop_saveset(EEG, 'filename', outName, 'filepath', subjDir);
        fprintf('Saved: %s\n', fullfile(subjDir, outName));
    end
end
