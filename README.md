# ZaberStage

MATLAB control of a **Zaber motorised stage** through the Zaber Motion Library. One axis of any
device on a daisy chain is moved in micrometres, inside limits you set. The repo has a
scriptable driver, a control window, and a simulated stage for testing. It is built to run
standalone, in calibration scripts, or inside Bpod protocols.

> **Status: not yet run against the stage (2026-10-05).** Everything has been tested on the
> simulated stage (47 tests). The library calls are the ones the previous lab code made on this
> stage, plus the reads of limits and homed state added here. Follow
> [docs/rig-checks.md](docs/rig-checks.md) before relying on it, with nothing in the stage's path.

## Features

- **Every axis command:** absolute and relative moves, homing, stop, position, a moving flag,
  and waiting until idle. Moves can block until done or return as soon as they start.
- **Your limits:** `LimitsUm` defaults to the axis's own travel. A move outside your limits is
  refused before anything is sent, never shortened.
- **Safe by default:** connecting never moves anything; homing is always an explicit call; the
  axis is stopped when you disconnect, delete the object or close the window; `stop()` works in
  every state.
- **A control panel for every axis:** X, Y, Z in one panel, each with its position, jog by a
  step, go to, Home; a large **STOP** for all of them (Esc does the same); Connect finds the
  controller; limits and the log fold away under Details. It opens as a window of its own or
  inside another program's window.
- **A simulated stage:** it refuses moves until homed, takes real time per move if you give it a
  speed, and can be told to fail or lose its cable.
- **A session record:** every command, with its time and duration, as a plain struct.

## Requirements

- Windows 10/11, 64-bit; MATLAB R2025b (the only release tested)
- The **Zaber Motion Library** add-on (MATLAB Add-On Explorer, "Zaber Motion Library"; this
  rig has 9.3.2). The simulated stage and the tests do not need it.
- A Zaber controller or integrated stage on a serial (USB) port. Close Zaber Launcher, or let
  it share the port (the default).

## Installation

1. Place this folder anywhere, e.g. `C:\Users\<you>\MATLAB\ZaberStage`.
2. Add the folder (not its subfolders) to the MATLAB path:
   ```matlab
   addpath('C:\Users\<you>\MATLAB\ZaberStage'); savepath
   ```
3. Optionally, store your stage's port:
   ```matlab
   zaberstage.listDevices('Probe', true)     % ports, and the Zaber devices on each
   setpref('zaberstage', 'Port', 'COM14')
   ```
4. Check the installation without touching the hardware:
   ```matlab
   cd(fullfile(fileparts(which('zaberstage.version')), 'tests')); run_tests
   ```

## Quick start

```matlab
stage = zaberstage.Stage('Port', 'COM14', 'AxisNumber', 1);
stage.connect();                       % finds the device, reads travel and homed state
stage.home();                          % needed once after power-up: runs to the home end

stage.LimitsUm = [20000 40000];        % refuse anything outside 20-40 mm
stage.moveAbsolute(29790);             % um; returns when the move is done
stage.moveRelative(-50);
stage.positionUm()

stage.moveAbsolute(35000, 'Wait', false);   % returns at once
stage.isMoving()
stage.stop();

stage.disconnect();                    % stops the axis, closes the port
```

There are walk-throughs in [`examples/`](examples):
- `example_basic.m`: every command
- `example_scan.m`: a focus scan that steps, measures and returns to the start

Both run on the simulated stage; set `useHardware = true` for the real one.

## Control window

```matlab
zaberstage.app()            % finds the controller and shows every axis on it
zaberstage.app('Axes', axes)  % named axes with their safe ranges (docs/gui.md)
zaberstage.app(stages)      % controls stages you already connected (leaves them connected)
```

See [docs/gui.md](docs/gui.md).

## Testing without hardware

```matlab
stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport());
```

## Safety

A motorised stage can drive an objective into a sample, or a sample into a holder.

- `LimitsUm` is yours: set it to the range that is safe with what is mounted. Moves outside it
  are refused.
- **`home()` ignores `LimitsUm`.** It always runs to the axis's home end, so clear the path
  first.
- The controller enforces its own travel limits as well. The software cannot know about
  obstacles inside them.
- `stop()` decelerates the axis. It is not an emergency stop for the controller's power: keep
  the physical stop button within reach.

## Documentation

Technical documentation is in [`docs/`](docs):
- `architecture.md`
- `api-reference.md`
- `zaber-motion.md`: the library calls used
- `gui.md`
- `integration.md`: scripts and Bpod
- `rig-checks.md`
