# Panel: `zaberstage.gui.StageApp`

```matlab
zaberstage.app()                        % owns its axes: Connect finds the port and every axis
zaberstage.app('Axes', axes)            % owned axes with these settings (see below)
zaberstage.app(stages)                  % attached: a struct x, y, z (a rig's), an array or one Stage
zaberstage.app(stages, 'Parent', tab)   % the panel inside another GUI's figure, panel, tab or grid
zaberstage.app(..., 'Visible', false, 'AutoRefresh', false, 'ShowLog', false, 'Names', {...})
```

The panel shows millimetres; the API (`goTo`, `Positions`, `zaberstage.Stage`) stays in
micrometres.

One panel for every axis of a Zaber controller (the rig's X-MCC drives X, Y and Z on COM14), laid
out like the OBIS laser and Hamamatsu camera panels. Always shown:

| Area | Controls |
|---|---|
| Header | lamp (amber while an axis moves, dim green while connected, grey while disconnected), controller name, state (*Moving*, *Ready*, *Faulted: ...*), **STOP**: stops every axis at once (Esc in a window of its own) |
| Connect | **Connect**: finds the Zaber port (also looked for when the panel opens; the default port, `zaberstage.config().Port`, only when none is found, and a `'Port'` given wins) (`zaberstage.listDevices`: Windows' device list, USB vendor 2939, no traffic) unless one was picked under Details, opens it, and connects every axis; **Disconnect** stops and disconnects them and closes the port. Beside it, the serial number, the number of axes and the port, or what Scan found |
| Axes (mm) | **Step (mm)**, 0.1 at first, **Read**, **Auto refresh** (every `RefreshS`, 0.5 s); one row per axis: name, position (mm, to the um), *homed* or **NOT HOMED** (red), **-** and **+** (one Step), Go to (starts at the axis's position) with **Go**, **Home** (asks first in a visible window: homing runs to the home sensor, whatever your limits say) |
| **Details** | a toggle arrow, folded at first (`showDetails(tf)`); a window of its own grows to fit |

Under Details:

| Area | Controls |
|---|---|
| Connection | Port (editable list) and **Scan** (owned axes, while disconnected) |
| Your limits (mm) | per axis: Min and Max (`LimitsUm`, set at once, no traffic), its travel, its safe range (`SafeLimitsUm`) and *reversed* |
| Log | each axis's recent commands that change something, then the panel's errors (own window only, unless `'ShowLog', true`) |

## Axes

- **Owned, no `Axes`:** the PC's default axes, `zaberstage.config().Axes`
  (`setpref('zaberstage', 'Axes', axes)`, same form as below), with their safe ranges. On the rig
  `LuminoseHF` keeps them equal to `zaber.axes` in `luminose_config.yaml` (every time its config
  loads): X axis 1 reversed, Y axis 2 never below 35000 um, Z axis 3 never above 30000 um.
  With no default set, Connect detects the chain. One device with up to three axes gives X, Y, Z
  (axes 1, 2, 3); otherwise *address.axis* (`1.1`, `1.2`, ...). Every axis gets its whole travel
  as its range: give `Axes` with `SafeLimitsUm` where something can be hit.
- **Owned, with `Axes`:** a struct, one field per axis name (the rows keep its order), each a
  struct of `zaberstage.Stage` options:

  ```matlab
  axes = struct('X', struct('AxisNumber', 1, 'Reversed', true), ...
                'Y', struct('AxisNumber', 2, 'SafeLimitsUm', [35000 Inf]), ...
                'Z', struct('AxisNumber', 3, 'SafeLimitsUm', [-Inf 30000]));
  zaberstage.app('Axes', axes)
  ```

  The rows show before Connect; Connect opens the port and connects them, sharing it.
- **Attached:** the panel shows the stages it is given and never disconnects them on close;
  Connect/Disconnect connect and disconnect those stages only (a shared port stays open).
  A struct's non-Stage fields (a rig's `close` function) are skipped.

## Behaviour

- **Every button goes through `zaberstage.Stage`**, so your limits, the safe range and the
  refusal to home outside it apply to clicks. A refusal goes in the log and an alert and is
  never thrown out of a callback.
- **Moves return at once** (`'Wait', false`): the readback shows them moving, the lamp is amber,
  and STOP answers at any time.
- **Closing** a panel that owns its axes stops and disconnects them and closes the port. An
  attached panel leaves them as they are.
- **Embedding:** with `'Parent'` the panel is a `uipanel` titled *Zaber stage*; `close()` deletes
  only it.
- From code: `jog(name, direction)`, `goTo(name, um)`, `home(name)`, `stopAll()`, `readback()`,
  `Stages`, `Names`, `Positions`.
- `tests/GuiTest.m` drives every control on a simulated three-axis controller with a made-up port
  list, and embeds the panel in a classic `figure`. A human pass is pending (`rig-checks.md`).
