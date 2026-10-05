# ZaberStage — Agent Instructions

MATLAB package `zaberstage` to move one axis of a **Zaber motorised stage**, in micrometres, through
the Zaber Motion Library (ASCII protocol). It must work **standalone** (scripts and GUI) and be
**easily embedded** in calibration scripts and Bpod protocols. Its first user is `LuminoseHF`
(`C:\Users\harrislab\MATLAB\LuminoseHF`, `calibration/calibrate_z.m`).

`agent.md` points here.

## Start here (fresh session)

1. Read this file first.
2. Then read the docs in this order:
   - `docs/architecture.md`: decisions D1–D7 and the milestones
   - `docs/zaber-motion.md`: the library calls and what is known about the rig's stage
   - `docs/api-reference.md`
   - `docs/gui.md`
   - `docs/rig-checks.md`
3. Check **Status**. What is left needs the stage, so ask for permission for each run (see
   *Hardware*), and write the results into `docs/rig-checks.md`.
4. Keep **Status** and the docs current as work lands.

## Status

| Milestone | State |
|---|---|
| M1: `Stage`, transports, simulated stage, tests | **Done** (2026-10-05). Moved out of `LuminoseHF` (`zaber/ZaberModel.m`) |
| M2: GUI (`zaberstage.app`) | **Done** on the simulated stage; no human pass yet |
| M3: examples, docs, README | **Done** |
| M4: `LuminoseHF` uses the package | **Done** (2026-10-05): `calibrate_z.m` |
| M5: rig verification | Pending (`docs/rig-checks.md`) |

The suite has 47 tests, all passing headless on R2025b in about 5 s, and the Code Analyzer reports
zero messages.

## Environment

| Thing | Path / value |
|---|---|
| Project (edit here, from WSL) | `/mnt/c/Users/harrislab/MATLAB/ZaberStage` |
| Same path from Windows | `C:\Users\harrislab\MATLAB\ZaberStage` |
| MATLAB | R2025b (`/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe`) |
| Zaber Motion Library | add-on 9.3.2, `%APPDATA%\MathWorks\MATLAB Add-Ons\Toolboxes\Zaber Motion Library` (read-only) |
| Stage on Windows | `COM14`, axis 1 on this rig (`LuminoseHF/luminose_config.yaml`, `zaber:`) |
| Sibling packages (idioms, read-only) | `../OBISLaser` (closest), `../DoricLED`, `../SpinCam`, `../LuminoseFM` |

```bash
# headless MATLAB from WSL: the whole suite (no hardware)
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "cd('C:\Users\harrislab\MATLAB\ZaberStage\tests'); r = run_tests; exit(any([r.Failed]))"
```

If that fails with `Exec format error`, WSL's Windows interop is not registered. Ask the operator
to run `sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'` in a
real terminal.

## Rules

### Workspace boundary
- **Create, edit or delete files only inside this project folder.** Never modify the MATLAB
  path, the Zaber library, Bpod settings or other repositories. Tell the operator instead.
- Resolve paths from the package location. Never hard-code the absolute paths above in code.

### Git
- **The operator handles git manually.** No git commands and no git files unless asked in that
  message.

### Hardware
- **Never touch the real stage without the operator's explicit permission for that specific
  run.** That covers:
  - `connect` on a MotionLibraryTransport to a real port
  - `zaberstage.listDevices('Probe', true)`
  - the GUI on a real port
  - `tests/hardware/`

  A sample, an objective or an animal may be in the travel.
- The tests on `SimulatedTransport`, and `MotionLibraryTransportTest` (which only opens the
  missing `COM250`), need no permission.
- Before a permitted run, ask what is mounted and agree `LimitsUm`. Homing is a separate
  permission: it runs to the end of travel.
- Record every hardware run in `docs/rig-checks.md`.

### Scope
- **No protocol-specific code:** focus positions, scan ranges and camera code belong to the
  client.
- **The user has full control:** every axis command is in the API, limits are set by the user,
  and a refusal is an explicit error that is never silent. The axis's own travel is the one
  ceiling, because it is a hardware fact.

## Architecture in brief

- `zaberstage.Stage` holds one axis: the address, the limits, the state, the log and the record.
- Transports do what they are told on any device and axis (D2):
  - `MotionLibraryTransport` wraps `zaber.motion.ascii.Connection` and `Axis`.
  - `SimulatedTransport` keeps positions and homed state, refuses like the controller, and
    injects faults.
- The library is synchronous and matches each reply to its request, so there is no reply-stealing
  trap as with the OBIS's serial port. The GUI's readback timer may run during a scripted move.

## Conventions

- **Layout:**
  - `+zaberstage/`: `Stage`, `app`, `config`, `listDevices`, `version`
  - `+zaberstage/+transport/`: `Transport`, `MotionLibraryTransport`, `SimulatedTransport`
  - `+zaberstage/+gui/StageApp.m`
  - `examples/`, `tests/` (with `hardware/`), `docs/`
- **Help text, style, errors and lint:** as in `../OBISLaser/CLAUDE.md`, *Conventions*:
  - an H1 line giving the full name; `See also` in every file outside `tests/`
  - lines of at most 100 characters, ASCII comments
  - errors as `zaberstage:<Component>:<reason>`
  - zero Code Analyzer messages
  - `HelpTextTest` checks the help text
- **Units in names:** `Um`, `UmPerS`, `DurationMs`. The API is in micrometres. Only the transport
  speaks the library's `Units`.
- **No variable named `axis`** (a builtin). Use `axisNumber`.
- **Traps:**
  - The library raises its own exception types. They pass through `Stage`, logged, with the
    library's identifiers. The simulated stage uses `zaberstage:SimulatedTransport:*`.
  - `moveRelative` checks the position read now plus the step. A relative move issued during
    another move is checked against where the axis is, not where it is going.

## Tests

- The current suite has 47 tests:
  - `StageTest` (21)
  - `SimulatedTransportTest` (8)
  - `GuiTest` (8)
  - `MotionLibraryTransportTest` (3; two are skipped without the library)
  - `ExamplesTest` (2)
  - `HelpTextTest` (5)
- New behaviour needs a test. `tests/hardware/checkStage.m` is run only with permission.

## Docs rule

- `README.md` is for end users only. `docs/` holds the technical material.
- A change to a public signature, a decision or the status updates the matching doc and
  **Status** in the same piece of work.
- Anything learned about the stage or library goes in `docs/zaber-motion.md`.
