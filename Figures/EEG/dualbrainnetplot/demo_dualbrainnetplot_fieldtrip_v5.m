function demo_dualbrainnetplot_fieldtrip_v5
% demo_dualbrainnetplot_fieldtrip_v5
% -------------------------------------------------------------------------
% Minimal demo for the dual-brain inter-brain connectivity plot.
%
% Requirements:
%   FieldTrip on the MATLAB path, because this demo uses:
%       - fieldtrip/template/headmodel/standard_bem.mat
%       - fieldtrip/template/electrode/standard_1005.elc
%
% Before running:
%   addpath('/path/to/fieldtrip');
%   ft_defaults;
% -------------------------------------------------------------------------

% A compact set of 10-20-like labels that should be present in FieldTrip's
% standard_1005.elc template.
labels = {'Fp1','Fp2','F3','F4','C3','C4','P3','P4','O1','O2', ...
          'F7','F8','T7','T8','P7','P8','Fz','Cz','Pz','Oz'};

nChan = numel(labels);
connMatrix = zeros(nChan, nChan);

% Add several example effects. The diagonal entries are intentionally used
% to demonstrate same-electrode inter-brain connections.
connMatrix(1,1)   =  1.0;   % Fp1 A -> Fp1 B
connMatrix(2,2)   = -0.8;   % Fp2 A -> Fp2 B
connMatrix(5,6)   =  0.6;   % C3 A  -> C4 B
connMatrix(6,5)   =  0.5;   % C4 A  -> C3 B
connMatrix(17,18) = -0.7;   % Fz A  -> Cz B
connMatrix(19,20) =  0.9;   % Pz A  -> Oz B

figure('Color', 'w');
biPer_plot_interbrain_brainmesh_v5(connMatrix, 'fieldtrip:standard_1005.elc', ...
    'ChannelLabels', labels, ...
    'ThresholdType', 'nonzero', ...
    'PlotDiagonal', true, ...
    'CoordinateMode', 'native', ...
    'LabelMode', 'names', ...
    'Title', 'Demo: inter-brain links on FieldTrip template brain mesh', ...
    'View', 'oblique');

end
