function [positionsUm, values] = example_scan(useHardware, port, measure)
% example_scan steps a Zaber axis through positions and measures something at each.
%
%   [positionsUm, values] = example_scan()                   simulated stage, made-up measure
%   [positionsUm, values] = example_scan(true, 'COM14', @() mean(cam.capture(), 'all'))
%
%   The pattern of a focus scan (LuminoseHF's calibrate_z): remember where the axis
%   started, narrow LimitsUm to the scan so a mistyped position cannot run the stage further,
%   step and measure, and return to the start however the scan ends.
%
%   Returns the positions visited (um) and the measure at each.
%
% See also zaberstage.Stage, example_basic
    if nargin < 1
        useHardware = false;
    end
    if useHardware
        stage = zaberstage.Stage('Port', port);
    else
        stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport( ...
            'StartHomed', true));
        measure = @() rand();
    end
    stage.connect();
    startUm = stage.positionUm();
    if ~useHardware
        startUm = 29790;
        stage.moveAbsolute(startUm);
    end
    positionsUm = startUm + (-500:100:500);
    stage.LimitsUm = [min(positionsUm) max(positionsUm)];
    back = onCleanup(@() returnAndClose(stage, startUm));

    values = zeros(size(positionsUm));
    for k = 1:numel(positionsUm)
        stage.moveAbsolute(positionsUm(k));
        values(k) = measure();
    end
end


function returnAndClose(stage, startUm)
% Back to the start, then disconnect; never throws, as it runs from onCleanup.
try
    stage.moveAbsolute(startUm);
catch
end
stage.disconnect();
end
