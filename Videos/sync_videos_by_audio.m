function result = sync_videos_by_audio(videoA_path, videoB_path, outA_path, outB_path, varargin)
%SYNC_VIDEOS_BY_AUDIO Align two .mp4 videos using their audio tracks.
%
% Usage:
%   result = sync_videos_by_audio('cam1.mp4','cam2.mp4',...
%                                 'cam1_synced.mp4','cam2_synced.mp4');
%
% Optional name-value args:
%   'TargetFs'       (default 16000)  % resample rate for alignment
%   'PadWithBlack'   (default false)  % if true, pad the EARLIER video instead of trimming
%   'MaxSearchLag'   (default 5)      % seconds; limit lag search window
%   'Verbose'        (default true)
%
% Output struct fields:
%   .lag_seconds         % positive => B starts AFTER A (B lags A)
%   .fs_target
%   .strategy            % 'trim_earlier' or 'pad_earlier'
%   .duration_out        % [A_out, B_out] in seconds
%   .notes

p = inputParser;
p.addParameter('TargetFs',16000,@(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('PadWithBlack',false,@islogical);
p.addParameter('MaxSearchLag',5,@(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('Verbose',true,@islogical);
p.parse(varargin{:});
opt = p.Results;

% --- 1) Read audio (mono) ---
[aA, fsA] = read_audio_track(videoA_path);
[aB, fsB] = read_audio_track(videoB_path);

% --- 2) Normalise & resample to common fs ---
fsT = opt.TargetFs;
aA = resample_to_mono(aA, fsA, fsT);
aB = resample_to_mono(aB, fsB, fsT);

% Optional: band-limit speech-ish range to improve SNR (300–3400 Hz)
aA = bandlimit_voip(aA, fsT);
aB = bandlimit_voip(aB, fsT);

% --- 3) Estimate lag using GCC-PHAT within a limited window ---
lagSec = estimate_lag_gcc_phat(aA, aB, fsT, opt.MaxSearchLag);

if opt.Verbose
    fprintf('[sync] Estimated lag: %.4f s (positive => B lags A)\n', lagSec);
end

% --- 4) Prepare video readers/writers ---
vrA = VideoReader(videoA_path);
vrB = VideoReader(videoB_path);

% Choose strategy
strategy = ternary(opt.PadWithBlack, 'pad_earlier', 'trim_earlier');

% Compute trim/pad amounts
% If lagSec > 0, B starts later, so A is earlier by lagSec.
% If trimming: trim lag from earlier video start; if padding: pad later video.
trimA = 0; trimB = 0; padA = 0; padB = 0;
if lagSec > 0
    % B lags A => A earlier
    if strcmp(strategy,'trim_earlier'), trimA = lagSec; else, padB = lagSec; end
else
    % A lags B => B earlier
    if strcmp(strategy,'trim_earlier'), trimB = -lagSec; else, padA = -lagSec; end
end

% Compute output durations (start at aligned zero, end at min common length)
durA = vrA.Duration; durB = vrB.Duration;
if strcmp(strategy,'trim_earlier')
    outStartA = trimA; outStartB = trimB;
    maxStart = max(outStartA, outStartB);
    % Align both to the later start
    outStartA = maxStart; outStartB = maxStart;
    % End at min of available tails
    outDur = min(durA - outStartA, durB - outStartB);
    outA = [outStartA, outStartA + outDur];
    outB = [outStartB, outStartB + outDur];
else
    % pad strategy: both start at t=0 in output timeline
    % We'll add black frames (no audio) to the later-starting one.
    % Duration limited by min(dur + pad on the late one, other dur)
    outDur = min(durA + padA, durB + padB);
    outA = [0, outDur];
    outB = [0, outDur];
end

% --- 5) Write aligned videos ---
write_aligned_video(vrA, outA_path, outA, padA);
write_aligned_video(vrB, outB_path, outB, padB);

% --- 6) Save a small log next to outputs ---
result = struct();
result.lag_seconds = lagSec;
result.fs_target = fsT;
result.strategy = strategy;
result.duration_out = [diff(outA), diff(outB)];
result.notes = 'Positive lag means B starts after A (B is later).';

[logDir, base, ~] = fileparts(outA_path);
if isempty(logDir), logDir = pwd; end
save(fullfile(logDir, sprintf('%s_sync_log.mat', base)), 'result');

if opt.Verbose
    fprintf('[sync] Wrote:\n  %s\n  %s\n', outA_path, outB_path);
end
end

% ===== Helpers =====
function [y, fs] = read_audio_track(videoPath)
% Prefer audioread (works for many mp4 files). If it fails, try VideoReader+Audio.
try
    [y, fs] = audioread(videoPath);
catch
    % Some MATLAB versions lack audio from VideoReader; raise a helpful error.
    error('Failed to read audio via audioread. Consider installing codecs or using ffmpeg to extract WAV first.');
end
% Downmix to mono
if size(y,2) > 1, y = mean(y,2); end
% Normalise
y = y ./ max(1e-9, max(abs(y)));
end

function y = resample_to_mono(y, fsIn, fsOut)
if fsIn ~= fsOut
    y = resample(y, fsOut, fsIn);
end
y = y(:);
end

function y = bandlimit_voip(y, fs)
% Simple IIR bandpass ~300–3400 Hz to reduce low/high noise
bp = designfilt('bandpassiir','FilterOrder',6, ...
    'HalfPowerFrequency1',300,'HalfPowerFrequency2',3400, ...
    'SampleRate',fs);
y = filtfilt(bp, y);
end

function lagSec = estimate_lag_gcc_phat(x, y, fs, maxLagSec)
% GCC-PHAT lag estimate limited to +/- maxLagSec
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
% outInterval = [tStart tEnd] within the original video time axis
% padLead (seconds) = amount of black padding to add at the start of the output
vw = VideoWriter(outPath, 'MPEG-4');
vw.Quality = 90;
vw.FrameRate = vr.FrameRate;
open(vw);

% If we need to pad: write black frames first
if padLead > 1e-6
    nPad = round(padLead * vw.FrameRate);
    blackFrame = zeros(vr.Height, vr.Width, 3, 'uint8');
    for k = 1:nPad
        writeVideo(vw, blackFrame);
    end
end

% Seek to tStart and write until tEnd
tStart = max(0, outInterval(1));
tEnd   = max(tStart, outInterval(2));
vr.CurrentTime = tStart;

nextFrameTime = tStart;
dt = 1 / vw.FrameRate;

while vr.CurrentTime <= tEnd
    if ~hasFrame(vr), break; end
    frame = readFrame(vr);
    % Guard against timestamps drifting past tEnd
    if nextFrameTime > tEnd + 1e-3, break; end
    writeVideo(vw, frame);
    nextFrameTime = nextFrameTime + dt;
end

close(vw);
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
