# Using the stage from scripts and protocols

## Scripts (calibration, focus scans)

1. Connect.
2. Read where the axis is.
3. Narrow `LimitsUm` to the scan, so a mistyped position cannot run the stage further.
4. Step and measure.
5. Return to the start in an `onCleanup`, so it happens however the script ends.

`examples/example_scan.m` is the pattern. `LuminoseHF/calibration/calibrate_z.m` uses it with
the Hamamatsu camera.

```matlab
stage = zaberstage.Stage('Port', 'COM14');
stage.connect();
start = stage.positionUm();
stage.LimitsUm = start + [-3000 3000];
back = onCleanup(@() stage.moveAbsolute(start));
for z = start + (-3000:50:3000)
    stage.moveAbsolute(z);
    % measure
end
```

## Bpod protocols

- Connect once in setup and disconnect in your cleanup.
- Move between trials, not from a soft-code callback. A move blocks MATLAB until it is done
  unless you pass `'Wait', false`, and then check `isMoving()` before the trial that needs the
  new position.
- Save `stage.record()` with the session data.
- For an emulator session, pass `'Transport', zaberstage.transport.SimulatedTransport()`.
