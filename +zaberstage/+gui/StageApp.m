classdef StageApp < handle
% zaberstage.gui.StageApp is the control panel for a Zaber controller's axes (X, Y, Z...).
%
%   app = zaberstage.gui.StageApp()            owns its axes: the default ones
%                                              (zaberstage.config().Axes, with their safe
%                                              ranges) when set, else Connect detects every
%                                              axis on the Zaber port it finds
%   app = zaberstage.gui.StageApp('Port', 'COM14', 'Axes', axes, 'Transport', t)
%                                              owns axes with these settings: Axes is a
%                                              struct, one field per axis name, each a
%                                              struct of zaberstage.Stage options
%                                              (DeviceAddress, AxisNumber, Reversed,
%                                              SafeLimitsUm, LimitsUm)
%   app = zaberstage.gui.StageApp(stages)      attaches to existing zaberstage.Stage
%                                              objects: a struct whose Stage fields are the
%                                              axes (other fields are skipped, so a rig's
%                                              struct x, y, z, close works), an array, or
%                                              one Stage. Closing never disconnects them
%   app = zaberstage.gui.StageApp(..., 'Parent', container)
%                                              builds the panel inside container (a figure,
%                                              uipanel, uitab or uigridlayout of another
%                                              GUI) instead of a window of its own
%   app = zaberstage.gui.StageApp(..., 'Visible', false, 'AutoRefresh', false,
%                                 'ShowLog', false, 'Names', {'X', 'Y'})
%   app = zaberstage.gui.StageApp(..., 'ListDevices', fcn)   how ports are found (tests):
%                                              fcn() returns a table like
%                                              zaberstage.listDevices
%
%   The header shows the controller and what it is doing, with STOP, which stops every
%   axis at once (Esc in a window of its own); its lamp is amber while an axis moves.
%   Connect finds the Zaber port (zaberstage.listDevices, which reads Windows' device list
%   and sends nothing) unless one was picked under Details, and connects. One row per
%   axis: its position (read every RefreshS while Auto refresh is ticked), homed or NOT
%   HOMED, jog - and + by Step, Go to with Go, and Home. The panel shows mm; the API
%   (goTo, Positions, zaberstage.Stage) stays in um. Moves return at once, so STOP
%   always answers. Details (folded away at first) holds the port with Scan, each axis's
%   limits (Min and Max, with its travel and safe range) and a log. Every command goes
%   through zaberstage.Stage, so its limits apply to the buttons. See docs/gui.md.
%
%   Properties (read-only)
%       Stages      the zaberstage.Stage objects shown, one per axis
%       Names       their names, e.g. {'X', 'Y', 'Z'}
%       OwnsStages  true when the app made them (and their transport)
%       Figure      the figure holding the panel (its own uifigure, or the host's)
%       Root        the panel's outermost container (delete it to remove the panel)
%       Controls    struct of components; Controls.Axes(k) those of axis k
%       LastError   text of the last error shown
%       Positions   the positions last read, um, one per axis (NaN unknown)
%
%   Properties (settable)
%       RefreshS    position readback period while Auto refresh is ticked, s (default 0.5)
%
%   Methods
%       refresh()              redraw every control from the stage objects (no traffic)
%       readback()             read every axis's position and show it
%       jog(name, direction)   move axis name one Step, direction +1 or -1
%       goTo(name, um)         move axis name to um
%       home(name)             home axis name
%       ok = stopAll()         stop every axis (STOP); never throws
%       showDetails(tf)        unfold or fold away the port, limits and log
%       close()                close the panel (stops and disconnects only owned axes)
%
% See also zaberstage.app, zaberstage.Stage, zaberstage.listDevices

    properties (SetAccess = private)
        Stages = zaberstage.Stage.empty   % one per axis
        Names = {}                        % axis names
        OwnsStages = false                % the app made them
        Figure = []                       % figure holding the panel
        Root = []                         % outermost container of the panel
        Controls = struct()               % components, for scripting and tests
        LastError = ''                    % last error shown
        Positions = []                    % positions last read, um
    end

    properties
        RefreshS = 0.5        % readback period while Auto refresh is ticked, s
    end

    properties (Constant, Hidden)
        Danger = [0.80 0.10 0.10]
        MoveColour = [0.95 0.65 0.10]  % the lamp while an axis moves
        ReadyColour = [0.20 0.75 0.30] % the lamp, dimmed, while connected
        OffColour = [0.55 0.55 0.55]   % the lamp while disconnected
        DimFactor = 0.35
        Faint = [0.45 0.45 0.45]
    end

    properties (Access = private)
        Listeners = {}
        Timer = []
        Closing = false
        OwnsFigure = true
        Grid = []
        DetailsRow = 0
        Errors = {}
        AxisOptions = struct()     % owned: the Axes option, or empty for every axis found
        Transport = []             % owned: the transport the axes share
        OwnsTransport = false      % the app made the transport (and closes it)
        PortValue = ''             % owned: the port asked for
        ListDevices = @zaberstage.listDevices
        PortChosen = false         % the port was picked by hand: Connect uses it as it is
        ScanMessage = ''
        Moving = []                % per axis, from the last readback
    end

    methods
        function obj = StageApp(varargin)
            visible = true;
            autoRefresh = true;
            parent = [];
            showLog = [];
            names = {};
            stages = [];
            axesGiven = false;
            portGiven = false;
            if ~isempty(varargin) && (isa(varargin{1}, 'zaberstage.Stage') ...
                    || isstruct(varargin{1}))
                [stages, names] = stagesFrom(varargin{1});
                varargin(1) = [];
            end
            rest = {};
            for k = 1:2:numel(varargin)
                switch lower(char(varargin{k}))
                    case 'visible'
                        visible = logical(varargin{k + 1});
                    case 'autorefresh'
                        autoRefresh = logical(varargin{k + 1});
                    case 'parent'
                        parent = varargin{k + 1};
                    case 'showlog'
                        showLog = logical(varargin{k + 1});
                    case 'names'
                        names = cellstr(varargin{k + 1});
                    case 'listdevices'
                        obj.ListDevices = varargin{k + 1};
                    case 'axes'
                        obj.AxisOptions = varargin{k + 1};
                        axesGiven = true;
                    case 'transport'
                        obj.Transport = varargin{k + 1};
                    case 'port'
                        obj.PortValue = char(varargin{k + 1});
                        portGiven = true;
                    otherwise
                        rest = [rest, varargin(k:min(k + 1, end))]; %#ok<AGROW>
                end
            end
            if ~isempty(rest)
                error('zaberstage:StageApp:invalidOption', 'Unknown option "%s".', ...
                    char(rest{1}));
            end
            if isempty(stages)
                obj.OwnsStages = true;
                cfg = zaberstage.config();
                if isempty(obj.PortValue)
                    obj.PortValue = cfg.Port;
                end
                if ~axesGiven
                    obj.AxisOptions = cfg.Axes;  % the PC's default axes and safe ranges
                end
                if ~isempty(fieldnames(obj.AxisOptions))
                    [stages, names] = obj.makeStages(fieldnames(obj.AxisOptions)');
                end
            elseif ~isempty(obj.Transport) || ~isempty(fieldnames(obj.AxisOptions))
                error('zaberstage:StageApp:invalidOption', ['''Transport'', ''Axes'' and ' ...
                    '''Port'' are for a panel that makes its own axes, not one attached to ' ...
                    'stages.']);
            end
            if isempty(showLog)
                showLog = isempty(parent);
            end
            obj.build(parent, visible, autoRefresh, showLog);
            obj.setStages(stages, names);
            obj.Timer = timer('ExecutionMode', 'fixedSpacing', 'Period', obj.RefreshS, ...
                'BusyMode', 'drop', 'Name', 'zaberstage.gui.StageApp', ...
                'TimerFcn', @(~, ~) zaberstage.gui.StageApp.onTimer( ...
                matlab.lang.WeakReference(obj)));
            if autoRefresh
                start(obj.Timer);
            end
            obj.scanPorts(portGiven);  % a port given wins; else look, and the default is
            obj.refresh();             % the fallback when no controller is found
        end

        function delete(obj)
            try
                obj.close();
            catch
                % delete never throws.
            end
        end

        function close(obj)
            % close() closes the panel; owned axes are stopped and disconnected.
            if obj.Closing
                return
            end
            obj.Closing = true;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            cellfun(@delete, obj.Listeners);
            obj.Listeners = {};
            if obj.OwnsStages
                obj.disconnectAll();
            end
            if obj.OwnsFigure
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    delete(obj.Figure);
                end
            elseif ~isempty(obj.Root) && isvalid(obj.Root)
                delete(obj.Root);
            end
        end

        function refresh(obj)
            % refresh() redraws every control from the stage objects, with no traffic.
            if obj.Closing || isempty(obj.Root) || ~isvalid(obj.Root)
                return
            end
            c = obj.Controls;
            ready = obj.isConnected();
            anyFault = any(strcmp({obj.Stages.State}, 'Faulted'));
            c.Connect.Text = ternary(ready || anyFault, 'Disconnect', 'Connect');
            if anyFault
                faulted = obj.Stages(strcmp({obj.Stages.State}, 'Faulted'));
                c.State.Text = sprintf('Faulted: %s', faulted(1).FaultReason);
            elseif any(obj.Moving)
                c.State.Text = 'Moving';
            else
                c.State.Text = ternary(ready, 'Ready', 'Disconnected');
            end
            if ready
                first = obj.Stages(1);
                c.Name.Text = sprintf('Zaber %s', first.Identity.DeviceName);
                c.Identity.Text = sprintf('S/N %d   %d ax%s   %s', ...
                    first.Identity.SerialNumber, numel(obj.Stages), ...
                    ternary(isscalar(obj.Stages), 'is', 'es'), first.Transport.Description);
            else
                c.Name.Text = 'Zaber stage';
                c.Identity.Text = strtrim(['Not connected. ' obj.ScanMessage]);
            end
            if obj.OwnsFigure && ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.Name = c.Name.Text;
            end
            c.EmissionLamp.Color = ternary(any(obj.Moving), obj.MoveColour, ...
                ternary(ready, obj.DimFactor * obj.ReadyColour, obj.OffColour));
            c.Port.Enable = ~ready && obj.OwnsStages && isempty(obj.Transport);
            c.Scan.Enable = c.Port.Enable;
            c.Step.Enable = ready;
            c.Read.Enable = ready;
            for k = 1:numel(obj.Stages)
                obj.refreshAxis(k);
            end
            obj.showLog();
        end

        function readback(obj)
            % readback() reads every connected axis's position and whether it moves.
            for k = 1:numel(obj.Stages)
                stage = obj.Stages(k);
                if ~strcmp(stage.State, 'Ready')
                    continue
                end
                try
                    obj.Positions(k) = stage.positionUm();
                    obj.Moving(k) = stage.isMoving();
                catch err
                    obj.Moving(k) = false;
                    obj.showError(err.message);
                end
            end
            obj.refresh();
        end

        function jog(obj, name, direction)
            % jog(name, direction) moves axis name one Step, +1 or -1.
            k = obj.axisIndex(name);
            step = direction * 1000 * obj.Controls.Step.Value;  % mm in the panel, um below
            obj.guard(@() obj.Stages(k).moveRelative(step, 'Wait', false));
            obj.readback();
        end

        function goTo(obj, name, um)
            % goTo(name, um) moves axis name to um.
            k = obj.axisIndex(name);
            obj.guard(@() obj.Stages(k).moveAbsolute(um, 'Wait', false));
            obj.readback();
        end

        function home(obj, name)
            % home(name) homes axis name (its home sensor end; refused outside SafeLimitsUm).
            k = obj.axisIndex(name);
            obj.guard(@() obj.Stages(k).home('Wait', false));
            obj.readback();
        end

        function ok = stopAll(obj)
            % ok = stopAll() stops every axis. Never throws; ok false if any did not confirm.
            ok = true;
            for k = 1:numel(obj.Stages)
                if ~strcmp(obj.Stages(k).State, 'Disconnected')
                    ok = obj.Stages(k).stop() && ok;
                end
            end
            if ~ok
                obj.showError('STOP was not confirmed by every axis. Check the stage.');
            end
            try
                obj.readback();
            catch
                % STOP must not throw.
            end
        end

        function showDetails(obj, tf)
            % showDetails(tf) unfolds (true) or folds away (false) the port, limits and log.
            tf = logical(tf);
            c = obj.Controls;
            c.Details.Value = tf;
            c.Details.Text = [char(ternary(tf, 9662, 9656)) '  Details'];
            c.DetailsArea.Visible = tf;
            extra = ternary(isempty(c.Log), 160 + 30 * numel(obj.Stages), ...
                310 + 30 * numel(obj.Stages));  % px the details take
            obj.Grid.RowHeight{obj.DetailsRow} = ternary(tf, ternary(isempty(c.Log), ...
                'fit', extra), 0);
            if obj.OwnsFigure && ~isempty(obj.Figure) && isvalid(obj.Figure)
                position = obj.Figure.Position;
                grow = ternary(tf, extra, -extra);
                % grows downwards, keeping the title bar where it is, but never off screen
                obj.Figure.Position = [position(1), max(position(2) - grow, 40), ...
                    position(3), position(4) + grow];
            end
        end
    end

    methods (Access = private)
        function build(obj, parent, visible, autoRefresh, showLog)
            % Lays out the panel, in a window of its own or inside parent.
            if isempty(parent)
                fig = uifigure('Name', 'Zaber stage', 'Position', [100 400 640 275], ...
                    'Visible', matlab.lang.OnOffSwitchState(visible), ...
                    'CloseRequestFcn', @(~, ~) obj.close(), ...
                    'KeyPressFcn', @(~, evt) obj.onKey(evt));
                obj.Figure = fig;
                obj.OwnsFigure = true;
                root = uigridlayout(fig, [1 1], 'Padding', [0 0 0 0]);
            else
                obj.Figure = ancestor(parent, 'figure');
                obj.OwnsFigure = false;
                root = uipanel(parent, 'Title', 'Zaber stage', 'FontWeight', 'bold');
                if ~isa(parent, 'matlab.ui.container.GridLayout')
                    root.Units = 'normalized';
                    root.Position = [0 0 1 1];
                end
            end
            obj.Root = root;
            rows = {'fit', 'fit', 'fit', 'fit', 0};
            grid = uigridlayout(root, [numel(rows) 1], 'RowHeight', rows, 'RowSpacing', 6);
            obj.Grid = grid;
            obj.DetailsRow = numel(rows);

            % Header: the controller, what it is doing, STOP
            row = uigridlayout(grid, [1 4], 'ColumnWidth', {20, '1x', 'fit', 120}, ...
                'Padding', [0 0 0 0]);
            c.EmissionLamp = uilamp(row, 'Color', obj.OffColour);
            c.Name = uilabel(row, 'Text', 'Zaber stage', 'FontSize', 16, 'FontWeight', 'bold');
            c.State = uilabel(row, 'Text', 'Disconnected');
            c.Stop = uibutton(row, 'Text', 'STOP', 'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], 'BackgroundColor', obj.Danger, ...
                'Tooltip', 'Stop every axis (Esc)', 'ButtonPushedFcn', @(~, ~) obj.stopAll());

            % Connect (it finds the port first) and what is connected
            row = uigridlayout(grid, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [0 0 0 0]);
            c.Connect = uibutton(row, 'Text', 'Connect', 'Tooltip', ['Find the Zaber ' ...
                'port and connect every axis (the port can be chosen under Details)'], ...
                'ButtonPushedFcn', @(~, ~) obj.onConnect());
            c.Identity = uilabel(row, 'Text', 'Not connected', 'WordWrap', 'on', ...
                'FontColor', obj.Faint);

            % Axes: one row each, built by setStages
            panel = uipanel(grid, 'Title', 'Axes (mm)');
            inner = uigridlayout(panel, [2 1], 'RowHeight', {'fit', 'fit'}, ...
                'Padding', [6 6 6 6]);
            row = uigridlayout(inner, [1 5], 'ColumnWidth', {'fit', 80, '1x', 'fit', 'fit'}, ...
                'Padding', [0 0 0 0]);
            uilabel(row, 'Text', 'Step (mm)');
            c.Step = uieditfield(row, 'numeric', 'Value', 0.1, 'Limits', [0 Inf], ...
                'LowerLimitInclusive', 'off', 'ValueDisplayFormat', '%g', ...
                'Tooltip', 'How far - and + move, mm');
            uilabel(row, 'Text', '');
            c.Read = uibutton(row, 'Text', 'Read', 'ButtonPushedFcn', @(~, ~) obj.readback());
            c.AutoRefresh = uicheckbox(row, 'Text', 'Auto refresh', 'Value', autoRefresh, ...
                'ValueChangedFcn', @(src, ~) obj.onAutoRefresh(src.Value));
            c.AxisGrid = uigridlayout(inner, [1 8], 'ColumnWidth', {40, 110, 80, 40, 40, ...
                90, 40, 60}, 'Padding', [0 0 0 0], 'RowHeight', {'fit'});
            c.Axes = struct([]);

            c.Details = uibutton(grid, 'state', 'Text', [char(9656) '  Details'], ...
                'Value', false, 'HorizontalAlignment', 'left', ...
                'Tooltip', 'Show or hide the port, the limits and the log', ...
                'ValueChangedFcn', @(src, ~) obj.showDetails(src.Value));
            rows = {'fit', 'fit'};
            if showLog
                rows{end + 1} = '1x';
            end
            details = uigridlayout(grid, [numel(rows) 1], 'RowHeight', rows, ...
                'Padding', [0 0 0 0], 'Visible', 'off');
            c.DetailsArea = details;

            panel = uipanel(details, 'Title', 'Connection');
            inner = uigridlayout(panel, [1 4], 'ColumnWidth', {'fit', 120, 'fit', '1x'});
            uilabel(inner, 'Text', 'Port');
            c.Port = uidropdown(inner, 'Editable', 'on', 'Items', {''}, 'Value', '', ...
                'ValueChangedFcn', @(~, ~) obj.onPortChosen());
            c.Scan = uibutton(inner, 'Text', 'Scan', 'Tooltip', ['List the ports and select ' ...
                'the Zaber controller''s'], 'ButtonPushedFcn', @(~, ~) obj.onScan());
            uilabel(inner, 'Text', '');

            panel = uipanel(details, 'Title', 'Your limits (mm): moves outside are refused');
            c.LimitGrid = uigridlayout(panel, [1 6], 'ColumnWidth', {40, 'fit', 100, 'fit', ...
                100, '1x'}, 'RowHeight', {'fit'});

            if showLog
                c.Log = uitextarea(details, 'Editable', 'off', 'FontName', 'Consolas');
            else
                c.Log = [];
            end
            obj.Controls = c;
        end

        function setStages(obj, stages, names)
            % Shows stages, one row each, and listens to them.
            cellfun(@delete, obj.Listeners);
            obj.Listeners = {};
            if isempty(stages)
                stages = zaberstage.Stage.empty;  % no axes until Connect finds them
            end
            obj.Stages = stages;
            if numel(names) ~= numel(stages)
                names = defaultNames(stages);
            end
            obj.Names = names;
            obj.Positions = nan(1, numel(stages));
            obj.Moving = false(1, numel(stages));
            ref = matlab.lang.WeakReference(obj);
            for k = 1:numel(stages)
                for event = {'StateChanged', 'MoveCompleted'}
                    obj.Listeners{end + 1} = addlistener(stages(k), event{1}, ...
                        @(~, ~) zaberstage.gui.StageApp.onStageEvent(ref));
                end
            end
            obj.buildAxisRows();
        end

        function buildAxisRows(obj)
            % One row per axis under Axes, and one under Your limits.
            c = obj.Controls;
            delete(c.AxisGrid.Children);
            delete(c.LimitGrid.Children);
            n = numel(obj.Stages);
            c.AxisGrid.RowHeight = repmat({'fit'}, 1, max(n, 1));
            c.LimitGrid.RowHeight = repmat({'fit'}, 1, max(n, 1));
            rows = struct([]);
            if n == 0
                hint = uilabel(c.AxisGrid, 'Text', 'Connect to list the axes.', ...
                    'FontColor', obj.Faint);
                hint.Layout.Column = [1 8];
                hint = uilabel(c.LimitGrid, 'Text', '', 'FontColor', obj.Faint);
                hint.Layout.Column = [1 6];
            end
            for k = 1:n
                name = obj.Names{k};
                r = struct();
                r.Name = uilabel(c.AxisGrid, 'Text', name, 'FontWeight', 'bold', ...
                    'FontSize', 14);
                r.Position = uilabel(c.AxisGrid, 'Text', '-', 'FontWeight', 'bold', ...
                    'FontSize', 14, 'HorizontalAlignment', 'right');
                r.Homed = uilabel(c.AxisGrid, 'Text', '', 'FontSize', 11);
                r.JogMinus = uibutton(c.AxisGrid, 'Text', '-', 'FontWeight', 'bold', ...
                    'Tooltip', sprintf('%s down one Step', name), ...
                    'ButtonPushedFcn', @(~, ~) obj.jog(name, -1));
                r.JogPlus = uibutton(c.AxisGrid, 'Text', '+', 'FontWeight', 'bold', ...
                    'Tooltip', sprintf('%s up one Step', name), ...
                    'ButtonPushedFcn', @(~, ~) obj.jog(name, 1));
                r.Target = uieditfield(c.AxisGrid, 'numeric', 'ValueDisplayFormat', ...
                    '%.3f', 'Tooltip', sprintf('Where Go moves %s, mm', name));
                r.Go = uibutton(c.AxisGrid, 'Text', 'Go', 'ButtonPushedFcn', ...
                    @(~, ~) obj.goTo(name, 1000 * ...
                    obj.Controls.Axes(obj.axisIndex(name)).Target.Value));
                r.Home = uibutton(c.AxisGrid, 'Text', 'Home', 'Tooltip', sprintf(['%s to ' ...
                    'its home sensor (clear the path first)'], name), ...
                    'ButtonPushedFcn', @(~, ~) obj.onHome(name));
                uilabel(c.LimitGrid, 'Text', name, 'FontWeight', 'bold');
                uilabel(c.LimitGrid, 'Text', 'Min');
                r.Min = uieditfield(c.LimitGrid, 'numeric', 'ValueDisplayFormat', '%.3f', ...
                    'ValueChangedFcn', ...
                    @(~, ~) obj.onLimits(name));
                uilabel(c.LimitGrid, 'Text', 'Max');
                r.Max = uieditfield(c.LimitGrid, 'numeric', 'ValueDisplayFormat', '%.3f', ...
                    'ValueChangedFcn', ...
                    @(~, ~) obj.onLimits(name));
                r.Travel = uilabel(c.LimitGrid, 'Text', '', 'FontColor', obj.Faint);
                if isempty(rows)
                    rows = r;
                else
                    rows(k) = r;
                end
            end
            c.Axes = rows;
            obj.Controls = c;
        end

        function refreshAxis(obj, k)
            % Axis k's row and limits from its stage object.
            stage = obj.Stages(k);
            r = obj.Controls.Axes(k);
            ready = strcmp(stage.State, 'Ready');
            if ready && ~isnan(obj.Positions(k))
                r.Position.Text = sprintf('%.3f', obj.Positions(k) / 1000);
            elseif ~ready
                r.Position.Text = '-';
            end
            if ready
                r.Homed.Text = ternary(stage.IsHomed, 'homed', 'NOT HOMED');
                r.Homed.FontColor = ternary(stage.IsHomed, obj.Faint, obj.Danger);
                r.Min.Value = stage.LimitsUm(1) / 1000;
                r.Max.Value = stage.LimitsUm(2) / 1000;
                travel = sprintf('travel %g-%g mm', stage.DeviceLimitsUm / 1000);
                if ~isempty(stage.SafeLimitsUm)
                    travel = sprintf('%s, safe %g to %g', travel, stage.SafeLimitsUm / 1000);
                end
                if stage.Reversed
                    travel = [travel ', reversed'];
                end
                r.Travel.Text = [travel '  ' stage.Identity.PeripheralName];
            else
                r.Homed.Text = '';
                r.Travel.Text = '';
            end
            for name = {'JogMinus', 'JogPlus', 'Target', 'Go', 'Home', 'Min', 'Max'}
                r.(name{1}).Enable = ready;
            end
        end

        %% Connection -------------------------------------------------------------------------

        function onConnect(obj)
            % Finds the port (unless picked by hand), connects every axis; or disconnects.
            if obj.isConnected() || any(strcmp({obj.Stages.State}, 'Faulted'))
                obj.disconnectAll();
                obj.Moving(:) = false;
                obj.refresh();
                return
            end
            if obj.OwnsStages
                obj.guard(@() obj.connectOwned());
            else
                for k = 1:numel(obj.Stages)
                    obj.guard(@() obj.Stages(k).connect());
                end
            end
            obj.readback();
            % Go to starts where each axis is, so Go pressed at once moves nothing
            for k = 1:numel(obj.Stages)
                if ~isnan(obj.Positions(k))
                    obj.Controls.Axes(k).Target.Value = obj.Positions(k) / 1000;
                end
            end
        end

        function connectOwned(obj)
            % Opens the port (the given transport, else the Zaber port found), makes the
            % axes (the Axes option, or every axis detected) and connects them.
            if ~obj.PortChosen && isempty(obj.Transport)
                obj.scanPorts(false);
            end
            transport = obj.Transport;
            if isempty(transport)
                port = obj.Controls.Port.Value;
                if isempty(port)
                    error('zaberstage:StageApp:noPort', ['No port: plug the controller in, ' ...
                        'or choose its port under Details.']);
                end
                transport = zaberstage.transport.MotionLibraryTransport(port);
                obj.OwnsTransport = true;
            end
            transport.open();
            try
                if isempty(fieldnames(obj.AxisOptions))
                    devices = transport.listDevices();
                    names = {};
                    options = {};
                    single = isscalar(devices) && devices.AxisCount <= 3;
                    for d = 1:numel(devices)
                        for a = 1:devices(d).AxisCount
                            if single
                                names{end + 1} = char('X' + a - 1); %#ok<AGROW>
                            else
                                label = sprintf('%d.%d', devices(d).Address, a);
                                names{end + 1} = label; %#ok<AGROW>
                            end
                            options{end + 1} = {'DeviceAddress', devices(d).Address, ...
                                'AxisNumber', a}; %#ok<AGROW>
                        end
                    end
                    stages = zaberstage.Stage.empty;
                    for k = 1:numel(names)
                        stages(k) = zaberstage.Stage('Transport', transport, ...
                            'SharedTransport', true, options{k}{:});
                    end
                    obj.setStages(stages, names);
                else
                    [stages, names] = obj.makeStages(fieldnames(obj.AxisOptions)', transport);
                    obj.setStages(stages, names);
                end
                for k = 1:numel(obj.Stages)
                    obj.Stages(k).connect();
                end
            catch err
                obj.disconnectAll();
                rethrow(err);
            end
            obj.Transport = transport;
        end

        function [stages, names] = makeStages(obj, names, transport)
            % Stages from the Axes option, sharing transport ([] until Connect makes one).
            if nargin < 3
                transport = obj.Transport;
            end
            stages = zaberstage.Stage.empty;
            for k = 1:numel(names)
                settings = obj.AxisOptions.(names{k});
                if isstruct(settings)
                    pairs = reshape([fieldnames(settings)'; struct2cell(settings)'], 1, []);
                else
                    pairs = settings;
                end
                if isempty(transport)
                    stages(k) = zaberstage.Stage('Port', obj.PortValue, pairs{:});
                else
                    stages(k) = zaberstage.Stage('Transport', transport, ...
                        'SharedTransport', true, pairs{:});
                end
            end
        end

        function disconnectAll(obj)
            % Stops and disconnects every axis; an owned port is closed.
            for k = 1:numel(obj.Stages)
                if isvalid(obj.Stages(k))
                    obj.Stages(k).disconnect();
                end
            end
            if obj.OwnsStages && ~isempty(obj.Transport) && obj.OwnsTransport
                obj.Transport.close();
                obj.Transport = [];
                obj.OwnsTransport = false;
            elseif obj.OwnsStages && ~isempty(obj.Transport)
                obj.Transport.close();  % a transport given to the panel: its port only
            end
        end

        function tf = isConnected(obj)
            % Whether any axis is connected.
            tf = ~isempty(obj.Stages) && any(strcmp({obj.Stages.State}, 'Ready'));
        end

        function onScan(obj)
            % Lists the ports again and selects the Zaber controller's.
            obj.PortChosen = false;
            obj.scanPorts(false);
            obj.refresh();
        end

        function onPortChosen(obj)
            % A port picked by hand: Connect uses it without scanning.
            obj.PortChosen = true;
        end

        function scanPorts(obj, keepPort)
            % Lists the ports and selects the given port (keepPort), else the Zaber one.
            try
                devices = obj.ListDevices();
            catch err
                devices = table(cell(0, 1), false(0, 1), false(0, 1), cell(0, 1), ...
                    cell(0, 1), 'VariableNames', {'Port', 'Available', 'IsZaber', ...
                    'Description', 'Devices'});
                obj.ScanMessage = sprintf('Could not list the ports: %s', err.message);
            end
            items = cellstr(devices.Port(:)');
            found = devices(devices.IsZaber, :);
            if keepPort && ~isempty(obj.PortValue)
                port = obj.PortValue;
                obj.ScanMessage = '';
            elseif isempty(found)
                port = obj.Controls.Port.Value;
                if isempty(port)
                    port = obj.PortValue;
                end
                obj.ScanMessage = ['No Zaber controller found among the ports: choose its ' ...
                    'port under Details.'];
            else
                free = found(found.Available, :);
                if ~isempty(free)
                    found = free;
                end
                port = found.Port{1};
                obj.ScanMessage = sprintf('Found the Zaber controller on %s.', port);
                if ~found.Available(1)
                    obj.ScanMessage = [obj.ScanMessage ' It is in use by another program ' ...
                        '(close Zaber Launcher or the other MATLAB).'];
                end
            end
            if ~isempty(port) && ~ismember(port, items)
                items{end + 1} = port;
            end
            if isempty(items)
                items = {''};
                port = '';
            end
            obj.Controls.Port.Items = items;
            obj.Controls.Port.Value = port;
        end

        %% Moves and limits -------------------------------------------------------------------

        function onHome(obj, name)
            % Homes after a confirmation in a visible window: homing runs to the end of travel.
            if ~isempty(obj.Figure) && isvalid(obj.Figure) && strcmp(obj.Figure.Visible, 'on')
                answer = uiconfirm(obj.Figure, sprintf(['Home %s? It runs to its home ' ...
                    'sensor, whatever your limits say. Clear the path first.'], name), ...
                    'Home', 'Options', {'Home', 'Cancel'}, 'DefaultOption', 2, ...
                    'CancelOption', 2);
                if ~strcmp(answer, 'Home')
                    return
                end
            end
            obj.home(name);
        end

        function onLimits(obj, name)
            % Sets axis name's LimitsUm from its Min and Max.
            k = obj.axisIndex(name);
            r = obj.Controls.Axes(k);
            obj.guard(@() setProperty(obj.Stages(k), 'LimitsUm', ...
                1000 * [r.Min.Value r.Max.Value]));
            obj.refresh();
        end

        function k = axisIndex(obj, name)
            % The index of axis name.
            k = find(strcmpi(obj.Names, char(name)), 1);
            if isempty(k)
                error('zaberstage:StageApp:noAxis', 'No axis "%s" (axes: %s).', char(name), ...
                    strjoin(obj.Names, ', '));
            end
        end

        function onKey(obj, evt)
            % Esc is STOP.
            if strcmp(evt.Key, 'escape')
                obj.stopAll();
            end
        end

        function onAutoRefresh(obj, tf)
            % Starts or stops the readback timer.
            if tf && strcmp(obj.Timer.Running, 'off')
                start(obj.Timer);
            elseif ~tf && strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
        end

        %% Errors and log ---------------------------------------------------------------------

        function ok = guard(obj, action)
            % Runs a user action; an error is shown, not thrown.
            ok = false;
            try
                action();
                ok = true;
            catch err
                obj.showError(err.message);
            end
        end

        function showError(obj, message)
            % Shows an error in the log and, when the panel is visible, as an alert.
            obj.LastError = message;
            obj.Errors{end + 1} = ['ERROR: ' message];
            obj.showLog();
            fig = obj.Figure;
            if ~isempty(fig) && isvalid(fig) && strcmp(fig.Visible, 'on')
                try
                    uialert(fig, message, 'Zaber stage');
                catch
                    warndlg(message, 'Zaber stage');  % a host figure that takes no uialert
                end
            end
        end

        function showLog(obj)
            % Every axis's recent commands that changed something, then the panel's errors.
            if isempty(obj.Controls.Log)
                return
            end
            lines = {};
            for k = 1:numel(obj.Stages)
                entries = obj.Stages(k).log();
                if height(entries) == 0
                    continue
                end
                moves = entries(~ismember(entries.Command, {'positionUm', 'isBusy'}), :);
                for j = max(1, height(moves) - 15):height(moves)
                    lines{end + 1} = sprintf('%8.2f  %-3s %-14s %10g  %s', moves.Time(j), ...
                        obj.Names{k}, moves.Command{j}, moves.Value(j), ...
                        moves.Message{j}); %#ok<AGROW>
                end
            end
            obj.Controls.Log.Value = [lines, obj.Errors(max(1, end - 5):end)];
        end
    end

    methods (Static, Hidden)
        function onStageEvent(ref)
            % A stage event redraws the panel, if it still exists.
            app = ref.Handle;
            if ~isempty(app) && isvalid(app)
                app.refresh();
            end
        end

        function onTimer(ref)
            % The readback timer; never throws into the timer.
            try
                app = ref.Handle;
                if ~isempty(app) && isvalid(app) && app.isConnected()
                    app.readback();
                end
            catch
                % A failed read is in the stage's log; the next tick tries again.
            end
        end
    end
end


function [stages, names] = stagesFrom(given)
% The zaberstage.Stage objects in given (a struct, an array or one Stage), and their names.
stages = zaberstage.Stage.empty;
names = {};
if isstruct(given)
    for field = fieldnames(given)'
        value = given.(field{1});
        if isa(value, 'zaberstage.Stage') && isscalar(value)
            stages(end + 1) = value; %#ok<AGROW>
            names{end + 1} = upper(field{1}); %#ok<AGROW>
        end
    end
    if isempty(stages)
        error('zaberstage:StageApp:invalidOption', 'The struct holds no zaberstage.Stage.');
    end
else
    stages = given(:)';
end
end


function names = defaultNames(stages)
% X, Y, Z for up to three axes, else Axis 1, Axis 2, ...
if numel(stages) <= 3
    names = arrayfun(@(k) char('X' + k - 1), 1:numel(stages), 'UniformOutput', false);
else
    names = arrayfun(@(k) sprintf('Axis %d', k), 1:numel(stages), 'UniformOutput', false);
end
end


function setProperty(object, name, value)
% Sets a property, for guard.
object.(name) = value;
end


function value = ternary(condition, a, b)
% a when condition is true, else b.
if condition
    value = a;
else
    value = b;
end
end
