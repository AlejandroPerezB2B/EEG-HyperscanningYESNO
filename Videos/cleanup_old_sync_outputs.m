%% cleanup_old_sync_outputs.m
% Delete silent sync outputs created in the previous attempt.
% Removes:
%   DyadXX\DyadXX-A_cut\DyadXX-A_sync.mp4
%   DyadXX\DyadXX-B_cut\DyadXX-B_sync.mp4
%   DyadXX\DyadXX-A_cut\DyadXX-A_sync_sync_log.mat
%
% Tip: set dryRun=false to actually delete.

clear; clc;

% -------- User settings --------
baseFolder = 'D:\HyperYESNO_videosCUT';  % root that contains Dyad01..Dyad35
nDyads     = 35;                         % number of dyads
dryRun     = true;                       % true = just print; false = delete
% --------------------------------

deleted = 0; missing = 0;

fprintf('== Cleanup old (silent) sync outputs ==\nBase: %s\n\n', baseFolder);
if dryRun
    fprintf('DRY RUN: No files will be deleted. Set dryRun=false to delete.\n\n');
end

for k = 3:nDyads
    dyadName = sprintf('Dyad%02d', k);
    aFolder  = fullfile(baseFolder, dyadName, [dyadName '-A_cut']);
    bFolder  = fullfile(baseFolder, dyadName, [dyadName '-B_cut']);

    if ~isfolder(aFolder) || ~isfolder(bFolder)
        fprintf('[%s] Missing A/B folders, skipping.\n', dyadName);
        continue;
    end

    % Targets to delete (old silent outputs)
    targetFiles = {
        fullfile(aFolder, sprintf('%s-A_sync.mp4', dyadName))
        fullfile(bFolder, sprintf('%s-B_sync.mp4', dyadName))
        fullfile(aFolder, sprintf('%s-A_sync_sync_log.mat', dyadName))
    };

    for i = 1:numel(targetFiles)
        f = targetFiles{i};
        if isfile(f)
            if dryRun
                fprintf('[%s] Would delete: %s\n', dyadName, f);
            else
                try
                    delete(f);
                    fprintf('[%s] Deleted: %s\n', dyadName, f);
                    deleted = deleted + 1;
                catch ME
                    fprintf('[%s] ERROR deleting %s: %s\n', dyadName, f, ME.message);
                end
            end
        else
            missing = missing + 1;
            fprintf('[%s] Not found: %s\n', dyadName, f);
        end
    end
end

fprintf('\n== Summary ==\n');
fprintf('Deleted (or would delete if dryRun=true): %d file(s)\n', deleted);
fprintf('Missing/not found: %d file(s)\n', missing);
fprintf('Done.\n');
