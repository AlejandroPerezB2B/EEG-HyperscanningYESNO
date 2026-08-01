%% Simple loader over Dyadxx/SubjA|SubjB with name pattern and save
tic
rootDir     = 'E:\EEG_data_HyperYESNO';   % HyperYESNO data root, change if needed
dyads       = 1:35;                       % Dyad01..Dyad35
tags        = {'A','B'};                  % SubjA, SubjB
saveSuffix  = '_PREP';                    % appended before .set when saving

% Make sure EEGLAB is on path and initialized (run eeglab first)
for d = dyads
    dyadStr = sprintf('Dyad%02d', d);
    for ti = 1:numel(tags)
        tag    = tags{ti};                        % 'A' or 'B'
        subjDir= fullfile(rootDir, dyadStr, ['Subj' tag]);
        base   = sprintf('Dyad%02d-%s', d, tag);  % e.g., Dyad04-A

        % Find the .set to load (EEGLAB will auto-load paired .fdt)
        setFile = [base, '.set'];
        setPath = fullfile(subjDir, setFile);

        if ~isfile(setPath)
            fprintf('Raw input file not found: %s\n', setPath);
            continue
        end

        % ---- Load
        % EEGLAB automatically loads the paired .fdt file when required.
        EEG = pop_loadset('filename', setFile, 'filepath', subjDir);

        % ==== YOUR PROCESSING GOES HERE ==================================
        % EEG = my_processing_function(EEG);   % <--- place your function
        % =================================================================

        % channels to use (example)
        ch = 1:62;                 % your data channels
        fs = EEG.srate;            % PREP uses EEG.srate internally; this line is just for clarity

        params = struct();

        % --- Reference stage ---
        params.reference = struct( ...
            'ignoreBoundaryEvents', true, ...
            'channels',             ch, ...
            'evaluationChannels',   ch, ...
            'rereferencedChannels', ch, ...
            'referenceType',        'Robust', ...
            'meanEstimateType',     'Median', ...
            'maxIterations',        4, ...
            'interpolationOrder',   'Post-reference', ...
            'keepFiltered',         true, ...
            'removeInterpolatedChannels', false );

        % --- Detrend stage (simple HP) ---
        params.detrend = struct( ...
            'channels',   ch, ...
            'type',       'High Pass', ...
            'cutoff',     1, ...
            'stepSize',   0.02 );

        % --- Line-noise stage (disabled) ---
        params.lineNoise = struct( ...
            'channels',        1:0, ...   % empty row vectors → skip line-noise
            'lineFrequencies', 1:0, ...
            'Fs',              fs, ...
            'lineNoiseMethod', 'none' );

        % --- Report stage ---
        params.report = struct( ...
            'reportMode', 'skipReport', ...
            'publishOn',  false);

        % Run PREP
        EEG = pop_prepPipeline(EEG, params);




        % ---- Save (same folder, new suffix)
        outName = [base, saveSuffix, '.set'];
        EEG = pop_saveset(EEG, 'filename', outName, 'filepath', subjDir);
        fprintf('Saved: %s\n', fullfile(subjDir, outName));
    end
end
t = toc;               % seconds
fprintf('Elapsed: %.6f s\n', t);