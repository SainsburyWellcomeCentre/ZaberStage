function report = checkStage(port, limitsUm)
% checkStage runs rig checks 1 and 3-5 of docs/rig-checks.md against the real stage.
%
%   report = checkStage('COM14', [27790 31790])
%
%   Needs the operator's permission for this run (CLAUDE.md, Hardware), with limitsUm agreed
%   for what is mounted. It does not home (rig check 2 is separate): the axis must already be
%   homed. The axis returns to where it started and the port is closed however the script
%   ends.
%
%   Returns the stage's record() and the operator's notes, for docs/rig-checks.md.
%
% See also zaberstage.Stage
    stage = zaberstage.Stage('Port', port);
    stage.connect();
    disp(stage.Identity);
    fprintf('Travel %.0f-%.0f um, homed %d\n', stage.DeviceLimitsUm, stage.IsHomed);
    if ~stage.IsHomed
        stage.disconnect();
        error('checkStage:notHomed', 'The axis is not homed: run rig check 2 first.');
    end
    stage.LimitsUm = limitsUm;
    startUm = stage.positionUm();
    back = onCleanup(@() returnAndClose(stage, startUm));
    report = struct('Notes', {{}});

    % 3. Moves inside the limits.
    middle = mean(limitsUm);
    stage.moveAbsolute(middle);
    for step = [50 -50]
        stage.moveRelative(step);
        report.Notes{end + 1} = sprintf('at %.2f um after %+g: %s', stage.positionUm(), ...
            step, input('Gauge or focus agrees (y/n, note)? ', 's'));
    end

    % 4. A refusal sends nothing.
    try
        stage.moveAbsolute(limitsUm(2) + 1);
    catch err
        fprintf('Refused as expected: %s\n', err.message);
    end

    % 5. Stop a long move.
    stage.moveAbsolute(limitsUm(1), 'Wait', false);
    pause(0.2);
    report.Notes{end + 1} = sprintf('stop() returned %d, moving after: %d', stage.stop(), ...
        stage.isMoving());
    report.Record = stage.record();
end


function returnAndClose(stage, startUm)
% Back to the start, then disconnect; never throws, as it runs from onCleanup.
try
    stage.moveAbsolute(startUm);
catch
end
stage.disconnect();
end
