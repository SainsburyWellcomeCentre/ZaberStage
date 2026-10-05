classdef StageApp < handle
% zaberstage.gui.StageApp is the control window for a zaberstage.Stage (programmatic uifigure).
%
%   app = zaberstage.gui.StageApp()          owns a new zaberstage.Stage (real stage); closing
%                                            the window stops and disconnects it
%   app = zaberstage.gui.StageApp('Port', 'COM14', 'Transport', t, ...)
%                                            owns a Stage built with these options
%   app = zaberstage.gui.StageApp(stage)     attaches to an existing Stage; closing the
%                                            window never disconnects it
%   app = zaberstage.gui.StageApp(..., 'Visible', false, 'AutoRefresh', false)
%
%   The window: port and Scan, Connect, the device's identity and travel, your limits (Min
%   and Max), the position (read every RefreshS while Auto refresh is ticked), Step with jog
%   buttons, Go to with Go, Home, a log, and STOP (also the Esc key). Every move goes through
%   zaberstage.Stage, so your limits apply to the buttons too. See docs/gui.md.
%
%   Properties (read-only)
%       Stage       the zaberstage.Stage shown
%       OwnsStage   true when the app created it
%       Figure      the uifigure
%       Controls    struct of components (for scripting and tests)
%       LastError   text of the last error shown
%
%   Methods
%       refresh()   redraw every control from the stage object (no traffic)
%       readback()  read the position and show it
%       close()     close the window (stops and disconnects only an owned stage)
%
% See also zaberstage.app, zaberstage.Stage

    properties (SetAccess = private)
        Stage                 % the zaberstage.Stage shown
        OwnsStage = false     % the app created it
        Figure = []           % the uifigure
        Controls = struct()   % components, for scripting and tests
        LastError = ''        % last error shown
    end

    properties
        RefreshS = 0.5        % position readback period while Auto refresh is ticked, s
    end

    properties (Constant, Hidden)
        Danger = [0.80 0.10 0.10]
    end

    properties (Access = private)
        Listeners = {}
        Timer = []
        Closing = false
        Errors = {}
    end

    methods
        function obj = StageApp(varargin)
            visible = true;
            autoRefresh = true;
            if ~isempty(varargin) && isa(varargin{1}, 'zaberstage.Stage')
                stage = varargin{1};
                varargin(1) = [];
                owns = false;
            else
                stage = [];
                owns = true;
            end
            rest = {};
            for k = 1:2:numel(varargin)
                switch lower(char(varargin{k}))
                    case 'visible'
                        visible = logical(varargin{k + 1});
                    case 'autorefresh'
                        autoRefresh = logical(varargin{k + 1});
                    otherwise
                        rest = [rest, varargin(k:min(k + 1, end))]; %#ok<AGROW>
                end
            end
            if owns
                stage = zaberstage.Stage(rest{:});
            elseif ~isempty(rest)
                error('zaberstage:StageApp:invalidOption', ['Only ''Visible'' and ' ...
                    '''AutoRefresh'' can be given when attaching to an existing stage.']);
            end
            obj.Stage = stage;
            obj.OwnsStage = owns;
            obj.build(visible, autoRefresh);
            ref = matlab.lang.WeakReference(obj);
            names = {'StateChanged', 'MoveCompleted'};
            for k = 1:numel(names)
                obj.Listeners{end + 1} = addlistener(stage, names{k}, ...
                    @(~, ~) zaberstage.gui.StageApp.onStageEvent(ref));
            end
            obj.Timer = timer('ExecutionMode', 'fixedSpacing', 'Period', obj.RefreshS, ...
                'BusyMode', 'drop', 'Name', 'zaberstage.gui.StageApp', ...
                'TimerFcn', @(~, ~) zaberstage.gui.StageApp.onTimer(ref));
            if autoRefresh
                start(obj.Timer);
            end
            obj.refresh();
        end

        function delete(obj)
            try
                obj.close();
            catch
                % delete never throws.
            end
        end

        function close(obj)
            % close() closes the window; an owned stage is stopped and disconnected.
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
            if obj.OwnsStage && isvalid(obj.Stage)
                obj.Stage.disconnect();
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function refresh(obj)
            % refresh() redraws every control from the stage object, with no traffic.
            if obj.Closing || isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            stage = obj.Stage;
            c = obj.Controls;
            ready = strcmp(stage.State, 'Ready');
            c.State.Text = stage.State;
            c.Connect.Text = pick(strcmp(stage.State, 'Disconnected'), 'Connect', 'Disconnect');
            c.Port.Enable = strcmp(stage.State, 'Disconnected');
            c.Scan.Enable = c.Port.Enable;
            if ready
                c.Identity.Text = sprintf(['%s %s  S/N %d  axis %d  travel %.0f-%.0f um  ' ...
                    '%s'], stage.Identity.DeviceName, stage.Identity.PeripheralName, ...
                    stage.Identity.SerialNumber, stage.AxisNumber, stage.DeviceLimitsUm, ...
                    [pick(stage.IsHomed, 'homed', 'NOT HOMED'), pick(stage.Reversed, ...
                    '  reversed', ''), safeText(stage.SafeLimitsUm)]);
                c.Min.Value = stage.LimitsUm(1);
                c.Max.Value = stage.LimitsUm(2);
            else
                c.Identity.Text = 'Not connected';
            end
            for name = {'Min', 'Max', 'Step', 'JogMinus', 'JogPlus', 'Target', 'Go', 'Home', ...
                    'Read'}
                c.(name{1}).Enable = ready;
            end
            obj.showLog();
        end

        function readback(obj)
            % readback() reads the position and shows it.
            if ~strcmp(obj.Stage.State, 'Ready')
                return
            end
            obj.guard(@() obj.showPosition());
        end
    end

    methods (Access = private)
        function build(obj, visible, autoRefresh)
            % Lays out the window.
            fig = uifigure('Name', 'Zaber stage', 'Position', [100 100 560 560], ...
                'Visible', matlab.lang.OnOffSwitchState(visible), ...
                'CloseRequestFcn', @(~, ~) obj.close(), ...
                'KeyPressFcn', @(~, evt) obj.onKey(evt));
            obj.Figure = fig;
            grid = uigridlayout(fig, [6 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x', 50});

            row = uigridlayout(grid, [1 5], 'ColumnWidth', {'fit', '1x', 'fit', 'fit', '2x'}, ...
                'Padding', [0 0 0 0]);
            uilabel(row, 'Text', 'Port');
            c.Port = uidropdown(row, 'Editable', 'on', 'Items', obj.portItems(), ...
                'Value', obj.initialPort());
            c.Scan = uibutton(row, 'Text', 'Scan', 'ButtonPushedFcn', @(~, ~) obj.onScan());
            c.Connect = uibutton(row, 'Text', 'Connect', ...
                'ButtonPushedFcn', @(~, ~) obj.onConnect());
            c.State = uilabel(row, 'Text', 'Disconnected');

            c.Identity = uilabel(grid, 'Text', 'Not connected', 'WordWrap', 'on');

            panel = uipanel(grid, 'Title', 'Position (um)');
            inner = uigridlayout(panel, [2 6], 'ColumnWidth', {'fit', '1x', 'fit', 'fit', ...
                'fit', 'fit'});
            c.Position = uilabel(inner, 'Text', '-', 'FontSize', 20, 'FontWeight', 'bold');
            c.Position.Layout.Column = [1 2];
            c.Read = uibutton(inner, 'Text', 'Read', 'ButtonPushedFcn', @(~, ~) obj.readback());
            c.AutoRefresh = uicheckbox(inner, 'Text', 'Auto refresh', 'Value', autoRefresh, ...
                'ValueChangedFcn', @(src, ~) obj.onAutoRefresh(src.Value));
            c.Home = uibutton(inner, 'Text', 'Home', 'ButtonPushedFcn', @(~, ~) obj.onHome());
            uilabel(inner, 'Text', '');
            uilabel(inner, 'Text', 'Go to');
            c.Target = uieditfield(inner, 'numeric');
            c.Go = uibutton(inner, 'Text', 'Go', 'ButtonPushedFcn', @(~, ~) obj.onGo());
            c.JogMinus = uibutton(inner, 'Text', '- Step', ...
                'ButtonPushedFcn', @(~, ~) obj.onJog(-1));
            c.Step = uieditfield(inner, 'numeric', 'Value', 50, 'Limits', [0 Inf]);
            c.JogPlus = uibutton(inner, 'Text', '+ Step', ...
                'ButtonPushedFcn', @(~, ~) obj.onJog(1));

            panel = uipanel(grid, 'Title', 'Your limits (um): moves outside are refused');
            inner = uigridlayout(panel, [1 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'});
            uilabel(inner, 'Text', 'Min');
            c.Min = uieditfield(inner, 'numeric', ...
                'ValueChangedFcn', @(~, ~) obj.onLimits());
            uilabel(inner, 'Text', 'Max');
            c.Max = uieditfield(inner, 'numeric', ...
                'ValueChangedFcn', @(~, ~) obj.onLimits());

            c.Log = uitextarea(grid, 'Editable', 'off', 'FontName', 'Consolas');

            c.Stop = uibutton(grid, 'Text', 'STOP  (Esc)', 'FontSize', 16, ...
                'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', obj.Danger, ...
                'ButtonPushedFcn', @(~, ~) obj.onStop());
            obj.Controls = c;
        end

        function items = portItems(~)
            % The serial ports Windows offers now.
            try
                items = cellstr(serialportlist("all"));
            catch
                items = {};
            end
            if isempty(items)
                items = {''};
            end
        end

        function port = initialPort(obj)
            % The stage's port, else the first one listed.
            port = obj.Stage.Port;
            if isempty(port)
                items = obj.portItems();
                port = items{1};
            end
        end

        function onScan(obj)
            % Lists the ports again.
            obj.Controls.Port.Items = obj.portItems();
        end

        function onConnect(obj)
            % Connects, or disconnects when connected.
            stage = obj.Stage;
            if strcmp(stage.State, 'Disconnected')
                obj.guard(@() connectTo(stage, obj.Controls.Port.Value, ...
                    isa(stage.Transport, 'zaberstage.transport.SimulatedTransport')));
            else
                stage.disconnect();
            end
            obj.refresh();
            obj.readback();
        end

        function onHome(obj)
            % Homes the axis.
            obj.guard(@() obj.Stage.home());
            obj.refresh();
            obj.readback();
        end

        function onGo(obj)
            % Moves to the Go to position.
            obj.guard(@() obj.Stage.moveAbsolute(obj.Controls.Target.Value));
            obj.readback();
        end

        function onJog(obj, direction)
            % Moves one Step in direction (+1 or -1).
            obj.guard(@() obj.Stage.moveRelative(direction * obj.Controls.Step.Value));
            obj.readback();
        end

        function onLimits(obj)
            % Sets your limits from Min and Max.
            obj.guard(@() setLimits(obj.Stage, [obj.Controls.Min.Value obj.Controls.Max.Value]));
            obj.refresh();
        end

        function onStop(obj)
            % Stops the axis, whatever else is happening.
            if ~obj.Stage.stop() && ~strcmp(obj.Stage.State, 'Disconnected')
                obj.showError('STOP was not confirmed by the controller. Check the stage.');
            end
            obj.readback();
        end

        function onKey(obj, evt)
            % Esc is STOP.
            if strcmp(evt.Key, 'escape')
                obj.onStop();
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

        function showPosition(obj)
            % One position read, shown.
            obj.Controls.Position.Text = sprintf('%.2f', obj.Stage.positionUm());
        end

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
            % Shows an error in the log and, when the window is visible, as an alert.
            obj.LastError = message;
            obj.Errors{end + 1} = ['ERROR: ' message];
            obj.showLog();
            if ~isempty(obj.Figure) && isvalid(obj.Figure) && strcmp(obj.Figure.Visible, 'on')
                uialert(obj.Figure, message, 'Zaber stage');
            end
        end

        function showLog(obj)
            % The stage's recent commands that changed something, then the window's errors.
            entries = obj.Stage.log();
            lines = {};
            if height(entries) > 0
                moves = entries(~ismember(entries.Command, {'positionUm', 'isBusy'}), :);
                for k = max(1, height(moves) - 30):height(moves)
                    lines{end + 1} = sprintf('%8.2f  %-14s %10g  %s', moves.Time(k), ...
                        moves.Command{k}, moves.Value(k), moves.Message{k}); %#ok<AGROW>
                end
            end
            obj.Controls.Log.Value = [lines, obj.Errors(max(1, end - 5):end)];
        end
    end

    methods (Static, Hidden)
        function onStageEvent(ref)
            % A stage event redraws the window, if it still exists.
            app = ref.Handle;
            if ~isempty(app) && isvalid(app)
                app.refresh();
            end
        end

        function onTimer(ref)
            % The readback timer; never throws into the timer.
            try
                app = ref.Handle;
                if ~isempty(app) && isvalid(app)
                    app.readback();
                end
            catch
                % A failed read is in the stage's log; the next tick tries again.
            end
        end
    end
end


function connectTo(stage, port, simulated)
% Connects stage on port (a simulated stage keeps its own transport).
if ~simulated
    stage.Port = port;
end
stage.connect();
end


function setLimits(stage, limits)
% Sets the stage's LimitsUm.
stage.LimitsUm = limits;
end


function text = safeText(limits)
% '  safe min-max um', or '' when the stage has no SafeLimitsUm.
    text = '';
    if ~isempty(limits)
        text = sprintf('  safe %.0f-%.0f um', limits);
    end
end

function value = pick(condition, a, b)
% a when condition is true, else b.
if condition
    value = a;
else
    value = b;
end
end
