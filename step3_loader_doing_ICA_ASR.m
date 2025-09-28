%% Simple loader over Dyadxx/SubjA|SubjB with name pattern and save
tic
rootDir     = 'D:\EEG_data_HyperYESNO';   % <-- change if needed
dyads       = 1:35;                       % Dyad01..Dyad35
tags        = {'A','B'};                  % SubjA, SubjB
namePattern = '_PREP*';                        % suffix after base name (e.g., '', '_filt*', '_filt_asr*')
saveSuffix  = '_ICA_ASR';                    % appended before .set when saving

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

        % 4) ICA (eyes-only removal)
        rank = eeg_rank(EEG.data);
        EEG = pop_runica(EEG, 'pca', rank, 'extended',1,'interrupt','on');     % or maybe AMICA
        EEG = pop_iclabel(EEG, 'default');
        eyeICs = find(EEG.etc.ic_classification.ICLabel.classifications(:,3) > 0.9); % class 3 = Eye
        EEG = pop_subcomp(EEG, eyeICs, 0);  % remove only ocular ICs (adjust threshold to taste)

        % 5) ASR (clean_rawdata) – conservative settings (example)
        EEG = pop_clean_rawdata(EEG, ...
            'FlatlineCriterion',5, ...        % example; tune for your data
            'ChannelCriterion',0.8, ...       % if you allow any further channel rejection
            'LineNoiseCriterion',4, ...
            'Highpass','off', ...             % already filtered
            'BurstCriterion',5, ...           % conservative; 3 is stricter, higher is looser
            'WindowCriterion',0.25, ...
            'BurstRejection','off');          % repair instead of hard reject (projective)




        % ---- Save (same folder, new suffix)
        outName = [base, saveSuffix, '.set'];
        EEG = pop_saveset(EEG, 'filename', outName, 'filepath', subjDir);
        fprintf('Saved: %s\n', fullfile(subjDir, outName));
    end
end
t = toc;               % seconds
fprintf('Elapsed: %.6f s\n', t);