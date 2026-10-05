% example_basic walks through every zaberstage.Stage command on the simulated stage.
%
%   Runs as it is with no hardware. Set useHardware = true and port to drive a real stage:
%   then clear the travel first, because home() runs the axis to its end.
%
% See also zaberstage.Stage, example_scan

useHardware = false;
port = 'COM14';

if useHardware
    stage = zaberstage.Stage('Port', port); %#ok<UNRCH> % reached once useHardware is set
else
    stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport());
end
cleanup = onCleanup(@() stage.disconnect());   % stops the axis however the script ends

stage.connect();                               % nothing moves
disp(stage.Identity)
fprintf('Travel %.0f to %.0f um, homed: %d\n', stage.DeviceLimitsUm, stage.IsHomed);

stage.home();                                  % to the home sensor; required after power-up
stage.LimitsUm = [20000 40000];                % refuse anything outside 20-40 mm
stage.moveAbsolute(29790);
stage.moveRelative(-50);
fprintf('Now at %.1f um\n', stage.positionUm());

try
    stage.moveAbsolute(45000);                 % outside LimitsUm: refused, nothing sent
catch err
    fprintf('Refused as expected: %s\n', err.message);
end

session = stage.record();                      % save this with your data
stage.disconnect();
