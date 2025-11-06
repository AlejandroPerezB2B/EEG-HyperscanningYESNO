function result = sync_videos_by_audio(videoA_path, videoB_path, outA_path, outB_path, varargin)
%SYNC_VIDEOS_BY_AUDIO
% Align two .mp4 videos using their audio tracks and save outputs WITH AUDIO.
% - Finds lag via GCC-PHAT on mono-resampled audio.
% - Either trims the earlier start or pads the later start with black frames.
% - Writes aligned video-only MP4s (MATLAB) and aligned stereo audio (WAV),
%   then muxes them with FFmpeg (copy video; AAC audio).
% - Ensures BOTH outputs share the SAME exact duration.
% - Saves a sync log .mat in the *DyadXX* parent folder.
%
% Usage:
%   result = sync_videos_by_audio('camA.mp4','camB.mp4',...
%                                 'Dyad01-A_sync.mp4','Dyad01-B_sync.mp4',...
%                                 'TargetFs',44100,'PadWithBlack',false,...
%                                 'FFmpegPath','C:\ffmpeg\bin\ffmpeg.exe',...
%                                 'UseParallel',true,'Verbose',true);
%
% Name-Value:
%   'TargetFs'     (default 16000)   % resample rate for *lag estimation only*
%   'PadWithBlack' (default false)   % false=trim earlier start; true=pad later start
%   'MaxSearchLag' (default 5)       % seconds
%   'Verbose'      (default true)
%   'FFmpegPath'   (default 'ffmpeg')
%   'UseParallel'  (default false)   % requires Parallel Computing Toolbox
%
% Output fields:
%   .lag_seconds, .fs_target, .strategy, .duration_out [A B], .notes

% -------------------- options --------------------
p = inputParser;
p.addParameter('TargetFs',16000,@(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('PadWithBlack',false,@islogical);
p.addParameter('MaxSearchLag',5,@(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('Verbose',true,@islogical);
p.addParameter('FFmpegPath','ffmpeg',@(s)ischar(s)||isstring(s));
p.addParameter('UseParallel',false,@islogical);
p.parse(varargin{:});
opt = p.Results;

% -------------------- 1) audio for lag --------------------
[aA_mono, fsA_mono] = read_audio_track(videoA_path); % mono, normalized
[aB_mono, fsB_mono] = read_audio_track(videoB_path);

fsT = opt.TargetFs;
aA = resample_to_mono(aA_mono, fsA_mono, fsT);
aB = resample_to_mono(aB_mono, fsB_mono, fsT);
aA = bandlimit_voip(aA, fsT);
aB = bandlimit_voip(aB, fsT);

lagSec = estimate_lag_gcc_phat(aA, aB, fsT, opt.MaxSearchLag);
if opt.Verbose
    fprintf('[sync] Estimated lag = %+0.4f s (positive => B lags A)\n', lagSec);
end

% -------------------- 2) decide windows --------------------
vrA = VideoReader(videoA_path);
vrB = VideoReader(videoB_path);
durA = vrA.Duration; durB = vrB.Duration;

strategy = ternary(opt.PadWithBlack, 'pad_earlier', 'trim_earlier');

trimA = 0; trimB = 0; padA = 0; padB = 0;
if lagSec > 0
    % B starts later => A earlier by lagSec
    if strcmp(strategy,'trim_earlier'), trimA = lagSec; else, padB = lagSec; end
else
    % A starts later => B earlier by -lagSec
    if strcmp(strategy,'trim_earlier'), trimB = -lagSec; else, padA = -lagSec; end
end

if strcmp(strategy,'trim_earlier')
    % align both to the later start; cut to overlapping tail
    outStartA = trimA; outStartB = trimB;
    maxStart  = max(outStartA, outStartB);
    outStartA = maxStart; outStartB = maxStart;
    outDur    = min(durA - outStartA, durB - outStartB);
    outA = [outStartA, outStartA + outDur];
    outB = [outStartB, outStartB + outDur];
else
    % both start at 0; pad earlier stream; duration limited by min tail
    outDur = min(durA + padA, durB + padB);
    outA = [0, outDur];
    outB = [0, outDur];
end

% Guarantee exact same duration numerically (floating fences)
% (Round to nearest frame based on each stream's fps so loop stops identically)
fpsA = vrA.FrameRate; fpsB = vrB.FrameRate;
% prefer a common integer frame count at output based on the *slower* fps
% but since we're not resampling fps, enforce identical end times:
commonEnd = min(outA(2), outB(2));
outA(2) = commonEnd; outB(2) = commonEnd;

% -------------------- 3) write VIDEO-ONLY MP4s --------------------
% We can write A and B in parallel if requested (requires toolbox).
if opt.UseParallel && canUseParallel()
    f1 = parfeval(@write_aligned_video, 0, vrA, outA_path, outA, padA);
    f2 = parfeval(@write_aligned_video, 0, vrB, outB_path, outB, padB);
    % Wait for both
    wait([f1 f2]);
else
    write_aligned_video(vrA, outA_path, outA, padA);
    write_aligned_video(vrB, outB_path, outB, padB);
end

% -------------------- 4) aligned AUDIO (stereo) --------------------
[aA_st, fsA] = audioread(videoA_path); % keep channels
[aB_st, fsB] = audioread(videoB_path);

tmpA_wav = tempname + "_A.wav";
tmpB_wav = tempname + "_B.wav";
build_aligned_audio(aA_st, fsA, outA, padA, tmpA_wav);
build_aligned_audio(aB_st, fsB, outB, padB, tmpB_wav);

% -------------------- 5) mux with ffmpeg --------------------
ff = string(opt.FFmpegPath);
muxedA = append_suffix(outA_path, '_av');
muxedB = append_suffix(outB_path, '_av');

cmdA = sprintf('"%s" -y -i "%s" -i "%s" -c:v copy -c:a aac -b:a 192k -shortest "%s"', ...
               ff, outA_path, tmpA_wav, muxedA);
cmdB = sprintf('"%s" -y -i "%s" -i "%s" -c:v copy -c:a aac -b:a 192k -shortest "%s"', ...
               ff, outB_path, tmpB_wav, muxedB);

[stA, msgA] = system(cmdA);
[stB, msgB] = system(cmdB);
if opt.Verbose
    if stA~=0, warning('ffmpeg mux A failed:\n%s', msgA); end
    if stB~=0, warning('ffmpeg mux B failed:\n%s', msgB); end
end

% overwrite outputs with muxed versions if successful
try
    if stA==0, movefile(muxedA, outA_path, 'f'); end
    if stB==0, movefile(muxedB, outB_path, 'f'); end
catch
    % keep _av files if move fails
end

% -------------------- 6) write LOG in DyadXX folder --------------------
% outA_path looks like ...\DyadXX\DyadXX-A_cut\DyadXX-A_sync.mp4
% Go up two levels to land in DyadXX
dyadFolder = fileparts(fileparts(outA_path));
[~, dyadName] = fileparts(dyadFolder);
logPath = fullfile(dyadFolder, sprintf('%s_sync_log.mat', dyadName));

result = struct();
result.lag_seconds   = lagSec;
result.fs_target     = fsT;
result.strategy      = strategy;
result.duration_out  = [diff(outA), diff(outB)]; % should be equal
result.video_fps     = [fpsA, fpsB];
result.notes         = 'Positive lag => B starts after A (B is later).';

save(logPath, 'result');

if opt.Verbose
    fprintf('[sync] Done. Outputs with audio:\n  %s\n  %s\n', outA_path, outB_path);
    fprintf('[sync] Log: %s\n', logPath);
end
end

% ===================== helpers =====================

function ok = canUseParallel()
ok = license('test','Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
end

function [y, fs] = read_audio_track(videoPath)
% mono + normalized (for *lag estimation only*)
[y, fs] = audioread(videoPath);
if size(y,2) > 1, y = mean(y,2); end
m = max(1e-9, max(abs(y)));
y = y ./ m;
end

function y = resample_to_mono(y, fsIn, fsOut)
if fsIn ~= fsOut, y = resample(y, fsOut, fsIn); end
y = y(:);
end

function y = bandlimit_voip(y, fs)
% ~300–3400 Hz to emphasize speech for cross-correlation
bp = designfilt('bandpassiir','FilterOrder',6, ...
    'HalfPowerFrequency1',300,'HalfPowerFrequency2',3400, ...
    'SampleRate',fs);
y = filtfilt(bp, y);
end

function lagSec = estimate_lag_gcc_phat(x, y, fs, maxLagSec)
N = 2^nextpow2(length(x) + length(y));
X = fft(x, N);
Y = fft(y, N);
R = (X .* conj(Y)) ./ max(1e-12, abs(X .* conj(Y)));
cc = real(ifft(R));
cc = fftshift(cc);
lags = (-N/2:(N/2-1))/fs;
mask = abs(lags) <= maxLagSec;
cc(~mask) = -Inf;
[~, idx] = max(cc);
lagSec = lags(idx);
end

function write_aligned_video(vr, outPath, outInterval, padLead)
% Write only frames in [tStart, tEnd], optionally with black padding at the start.
vw = VideoWriter(outPath, 'MPEG-4');
vw.Quality   = 90;
vw.FrameRate = vr.FrameRate;
open(vw);

% pad with black frames (for pad strategy)
if padLead > 1e-6
    nPad = round(padLead * vw.FrameRate);
    blackFrame = zeros(vr.Height, vr.Width, 3, 'uint8');
    for k = 1:nPad
        writeVideo(vw, blackFrame);
    end
end

tStart = max(0, outInterval(1));
tEnd   = max(tStart, outInterval(2));
vr.CurrentTime = tStart;

dt = 1 / vw.FrameRate;
nextFrameTime = tStart;

while vr.CurrentTime <= tEnd
    if ~hasFrame(vr), break; end
    frame = readFrame(vr);
    if nextFrameTime > tEnd + 1e-3, break; end
    writeVideo(vw, frame);
    nextFrameTime = nextFrameTime + dt;
end

close(vw);
end

function build_aligned_audio(a_st, fs, outInterval, padLead, outWav)
% Build aligned stereo audio matching the video alignment; write to WAV.
tStart = max(0, outInterval(1));
tEnd   = max(tStart, outInterval(2));
iStart = max(1, floor(tStart*fs) + 1);
iEnd   = min(size(a_st,1), ceil(tEnd*fs));
seg    = a_st(iStart:iEnd, :);

% Prepend silence if we padded the video
if padLead > 1e-6
    nPad = round(padLead * fs);
    seg  = [zeros(nPad, size(seg,2)); seg]; %#ok<AGROW>
end

% Enforce exact target length
outDur  = diff(outInterval);
nTarget = round((padLead + outDur)*fs);
if size(seg,1) > nTarget, seg = seg(1:nTarget, :);
elseif size(seg,1) < nTarget, seg(end+1:nTarget, :) = 0;
end

audiowrite(outWav, seg, fs, 'BitsPerSample', 16);
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function p = append_suffix(pathIn, suf)
[folder, name, ext] = fileparts(pathIn);
p = fullfile(folder, [name suf ext]);
end
