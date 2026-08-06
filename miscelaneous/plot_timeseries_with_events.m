function plot_timeseries_with_events(t, y, evtLat, evtVal, varargin)
% Plot a time series y(t) and overlay event values at given latencies.
% - t:       Nx1 vector of time stamps (seconds) for y
% - y:       Nx1 vector of signal values
% - evtLat:  Mx1 vector of event latencies (seconds OR samples)
% - evtVal:  Mx1 vector of event values (plotted at evtLat on same time axis)
%
% Name-Value:
%   'LatencyUnits' : 'seconds' (default) or 'samples'
%   'Fs'           : sample rate (required if 'LatencyUnits'='samples' and t not given as indices)
%   'UseSecondY'   : true/false (default=false). If true, event values go on right y-axis.
%
% use example: plot_timeseries_with_events(EEG.times/1000, EEG.data(129,:), ([EEG.event.latency])/1000, [EEG.event.type] )

p = inputParser;
p.addParameter('LatencyUnits','seconds',@(s)ischar(s) || isstring(s));
p.addParameter('Fs',[],@(x)isnumeric(x)&&isscalar(x));
p.addParameter('UseSecondY',false,@islogical);
p.parse(varargin{:});
u  = lower(string(p.Results.LatencyUnits));
fs = p.Results.Fs;
useYY = p.Results.UseSecondY;

% --- sanity ---
t   = t(:); y = y(:); evtLat = evtLat(:); evtVal = evtVal(:);
assert(numel(t)==numel(y), 't and y must have same length.');
assert(numel(evtLat)==numel(evtVal), 'evtLat and evtVal must have same length.');

% --- convert event latencies to time (seconds) if needed ---
switch u
    case "seconds"
        evtTime = evtLat;
    case "samples"
        if ~isempty(fs)
            % If t starts at t0, align using t0 (not assumed 0)
            t0 = t(1);
            evtTime = t0 + (evtLat-1)/fs;   % MATLAB 1-based indexing
        else
            % If fs not given, try mapping direct indices to t
            idx = round(evtLat);
            assert(all(idx>=1 & idx<=numel(t)), 'Sample indices out of range.');
            evtTime = t(idx);
        end
    otherwise
        error('LatencyUnits must be "seconds" or "samples".');
end

% Keep events within the plotted time range
inRange = evtTime>=t(1) & evtTime<=t(end) & isfinite(evtVal);
evtTime = evtTime(inRange);
evtVal  = evtVal(inRange);

% --- plot ---
figure; 
if useYY
    yyaxis left
end
plot(t, y, 'LineWidth', 1.2); hold on
xlabel('Time (s)'); ylabel('Signal');
xlim([t(1) t(end)]); grid on

if useYY
    yyaxis right
    stem(evtTime, evtVal, 'filled', 'MarkerSize', 5); 
    ylabel('Event value')
else
    stem(evtTime, evtVal, 'filled', 'MarkerSize', 5); 
    ylabel('Signal / Event value')
end

% Optional styling
title('Time series with event values');
legend('Time series','Events','Location','best');
end
