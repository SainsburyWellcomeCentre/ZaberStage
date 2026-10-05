classdef Stage < handle
% zaberstage.Stage moves one axis of a Zaber motorised stage, in micrometres, within your limits.
%
%   stage = zaberstage.Stage('Port', 'COM14')                 axis 1 of the first device
%   stage = zaberstage.Stage('Port', 'COM14', 'AxisNumber', 3, 'LimitsUm', [20000 40000])
%   stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport())
%
%   The constructor never touches the hardware; connect() opens the port, finds the device on
%   the daisy chain and reads the axis's own limits and whether it is homed. It does not home
%   or move: homing moves the stage to its end of travel, which may not be safe with a sample
%   or an objective in place, so it is always an explicit home(). Every move is checked
%   against LimitsUm before anything is sent and refused, never shortened, outside them.
%
%   Properties (read-only)
%       State           'Disconnected' | 'Ready' | 'Faulted'
%       FaultReason     why the object is Faulted, else ''
%       Transport       the zaberstage.transport.Transport in use
%       Identity        struct: DeviceName, SerialNumber, PeripheralName, DeviceAddress
%       DeviceLimitsUm  the axis's own [min max] travel (limit.min, limit.max)
%       IsHomed         whether the axis was homed when last checked
%
%   Properties (settable)
%       Port           serial port, e.g. 'COM14' (default from zaberstage.config)
%       BaudRate       default 115200
%       DeviceAddress  device on the daisy chain, 1-based (default 1)
%       AxisNumber     axis on that device, 1-based (default 1)
%       LimitsUm       your [min max]: moves outside are refused. Empty until connect, which
%                      sets it to DeviceLimitsUm unless you set narrower ones; it must lie
%                      within DeviceLimitsUm.
%       Verbose        print each command (default false)
%       LogCapacity    entries kept by log() (default 1000)
%   Port, BaudRate, DeviceAddress and AxisNumber can change only while Disconnected.
%
%   Methods
%       connect()                         open, find the device, read limits and homed state
%       disconnect()                      stop the axis, close. Idempotent, never throws
%       home('Wait', true)                move to the home sensor (the axis's minimum)
%       moveAbsolute(um, 'Wait', true)    move to a position
%       moveRelative(um, 'Wait', true)    move by a distance from the present position
%       ok = stop()                       decelerate to rest; tried in every state, never throws
%       um = positionUm()                 position now
%       tf = isMoving()                   whether the axis is moving now
%       waitUntilIdle()                   block until the axis stops
%       s = record()                      plain struct for data files
%       t = log()                         table of recent commands
%   With 'Wait', false a move returns as soon as it starts.
%
%   Events: StateChanged, MoveCompleted (after each command that moves; listeners read the
%   properties).
%
%   Errors
%       zaberstage:Stage:notReady            a command needs State Ready
%       zaberstage:Stage:noPort              connect with neither Port nor Transport
%       zaberstage:Stage:noDevice            no device at DeviceAddress, or no such axis
%       zaberstage:Stage:outsideLimits       a target outside LimitsUm (nothing is sent)
%       zaberstage:Stage:badValue            a position that is not one finite number
%       zaberstage:Stage:limitsOutsideDevice LimitsUm beyond the axis's own travel
%       zaberstage:Stage:portLocked          Port, BaudRate, DeviceAddress or AxisNumber
%                                            changed while connected
%       Transport and library errors (an unhomed axis, a pulled cable) pass through with
%       their own identifiers, after being logged.
%
%   Example
%       stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport());
%       stage.connect();
%       stage.home();
%       stage.LimitsUm = [10000 40000];
%       stage.moveAbsolute(29790);
%       stage.moveRelative(-50);
%       stage.disconnect();
%
% See also zaberstage.app, zaberstage.config, zaberstage.listDevices,
%          zaberstage.transport.SimulatedTransport

    properties (SetAccess = private)
        State = 'Disconnected'   % 'Disconnected' | 'Ready' | 'Faulted'
        FaultReason = ''         % why the object is Faulted
        Transport = []           % zaberstage.transport.Transport in use
        Identity = zaberstage.Stage.emptyIdentity()  % DeviceName, SerialNumber, ...
        DeviceLimitsUm = []      % the axis's own travel, um
        IsHomed = false          % homed when last checked
    end

    properties (Dependent)
        Port           % serial port, e.g. 'COM14'
        BaudRate       % bits per second
        DeviceAddress  % device on the daisy chain, 1-based
        AxisNumber     % axis on that device, 1-based
        LimitsUm       % your [min max], um
    end

    properties
        Verbose = false      % print commands
        LogCapacity = 1000   % entries kept by log()
    end

    events
        StateChanged
        MoveCompleted
    end

    properties (Access = private)
        PortValue = ''
        BaudRateValue = 115200
        DeviceValue = 1
        AxisValue = 1
        LimitsValue = []
        OwnsTransport = false
        LogEntries
        ClockStart
        ClockEpoch
    end

    methods
        function obj = Stage(varargin)
            obj.LogEntries = zaberstage.Stage.emptyLog();
            obj.ClockStart = tic;
            obj.ClockEpoch = datetime('now');
            if mod(numel(varargin), 2) ~= 0
                error('zaberstage:Stage:invalidOption', 'Options must be name-value pairs.');
            end
            cfg = zaberstage.config();
            obj.PortValue = cfg.Port;
            obj.BaudRateValue = cfg.BaudRate;
            names = {'Port', 'BaudRate', 'DeviceAddress', 'AxisNumber', 'LimitsUm', ...
                'Verbose', 'LogCapacity'};
            for k = 1:2:numel(varargin)
                name = char(varargin{k});
                value = varargin{k + 1};
                if strcmpi(name, 'Transport')
                    if ~isa(value, 'zaberstage.transport.Transport')
                        error('zaberstage:Stage:invalidOption', ...
                            'Transport must be a zaberstage.transport.Transport.');
                    end
                    obj.Transport = value;
                elseif any(strcmpi(names, name))
                    obj.(names{strcmpi(names, name)}) = value;
                else
                    error('zaberstage:Stage:invalidOption', ['Unknown option "%s". Valid: ' ...
                        'Transport, %s.'], name, strjoin(names, ', '));
                end
            end
        end

        function delete(obj)
            obj.disconnect();
        end

        %% Connection -------------------------------------------------------------------------

        function connect(obj)
            % connect() opens the port, finds the device and reads the axis's limits.
            %
            %   Nothing moves. Errors close the port and leave the object Disconnected.
            if strcmp(obj.State, 'Ready')
                return
            end
            if isempty(obj.Transport) || obj.OwnsTransport
                if isempty(obj.PortValue)
                    error('zaberstage:Stage:noPort', ['No port: give ''Port'' (see ' ...
                        'zaberstage.listDevices) or set a default with setpref(' ...
                        '''zaberstage'', ''Port'', ''COM14'').']);
                end
                obj.Transport = zaberstage.transport.MotionLibraryTransport(obj.PortValue, ...
                    'BaudRate', obj.BaudRateValue);
                obj.OwnsTransport = true;
            end
            obj.FaultReason = '';
            try
                obj.Transport.open();
                devices = obj.call('listDevices', @() obj.Transport.listDevices());
                match = find([devices.Address] == obj.DeviceValue, 1);
                if isempty(match) || obj.AxisValue > devices(match).AxisCount
                    error('zaberstage:Stage:noDevice', ['No axis %d on a device at address ' ...
                        '%d (found: %s).'], obj.AxisValue, obj.DeviceValue, ...
                        describeDevices(devices));
                end
                info = obj.call('axisInfo', @() obj.Transport.axisInfo(obj.DeviceValue, ...
                    obj.AxisValue));
                obj.Identity = struct('DeviceName', devices(match).Name, 'SerialNumber', ...
                    devices(match).SerialNumber, 'PeripheralName', info.Name, ...
                    'DeviceAddress', obj.DeviceValue);
                obj.DeviceLimitsUm = info.LimitsUm;
                obj.IsHomed = info.IsHomed;
                if isempty(obj.LimitsValue)
                    obj.LimitsValue = info.LimitsUm;
                else
                    obj.requireWithinDevice(obj.LimitsValue);
                end
            catch err
                obj.Transport.close();
                obj.DeviceLimitsUm = [];
                rethrow(err);
            end
            obj.setState('Ready');
        end

        function disconnect(obj)
            % disconnect() stops the axis and closes the port. Never throws.
            if isempty(obj.Transport)
                return
            end
            wasConnected = ~strcmp(obj.State, 'Disconnected');
            if wasConnected
                obj.stop();
            end
            try
                obj.Transport.close();
            catch
                % Nothing more can be done for a port that will not close.
            end
            if wasConnected
                obj.setState('Disconnected');
            end
        end

        %% Motion -----------------------------------------------------------------------------

        function home(obj, varargin)
            % home('Wait', true) moves the axis to its home sensor and zeroes it there.
            %
            %   Homing travels to the axis's minimum whatever LimitsUm says: clear the path
            %   first.
            wait = parseWait(varargin);
            obj.requireReady();
            obj.call('home', @() obj.Transport.home(obj.DeviceValue, obj.AxisValue, wait));
            obj.IsHomed = true;
            notify(obj, 'MoveCompleted');
        end

        function moveAbsolute(obj, um, varargin)
            % moveAbsolute(um, 'Wait', true) moves to a position, refused outside LimitsUm.
            wait = parseWait(varargin);
            requireNumber(um);
            obj.requireReady();
            obj.requireWithinLimits(um);
            obj.call('moveAbsolute', @() obj.Transport.moveAbsolute(obj.DeviceValue, ...
                obj.AxisValue, um, wait), um);
            notify(obj, 'MoveCompleted');
        end

        function moveRelative(obj, um, varargin)
            % moveRelative(um, 'Wait', true) moves by um, refused if it would leave LimitsUm.
            %
            %   The target is the position read now plus um, so a move started while the axis
            %   is still moving is checked against where it is, not where it is going.
            wait = parseWait(varargin);
            requireNumber(um);
            obj.requireReady();
            obj.requireWithinLimits(obj.positionUm() + um);
            obj.call('moveRelative', @() obj.Transport.moveRelative(obj.DeviceValue, ...
                obj.AxisValue, um, wait), um);
            notify(obj, 'MoveCompleted');
        end

        function ok = stop(obj)
            % ok = stop() decelerates the axis to rest. Never throws; ok false if it failed.
            ok = false;
            try
                if isempty(obj.Transport) || ~obj.Transport.isOpen()
                    return
                end
                obj.call('stop', @() obj.Transport.stop(obj.DeviceValue, obj.AxisValue));
                ok = true;
                notify(obj, 'MoveCompleted');
            catch
                % The caller is told by ok; throwing here would stop a cleanup halfway.
            end
        end

        function um = positionUm(obj)
            % um = positionUm() is the axis position now.
            obj.requireReady();
            um = obj.call('positionUm', @() obj.Transport.positionUm(obj.DeviceValue, ...
                obj.AxisValue));
        end

        function tf = isMoving(obj)
            % tf = isMoving() is whether the axis is moving now.
            obj.requireReady();
            tf = obj.call('isBusy', @() obj.Transport.isBusy(obj.DeviceValue, obj.AxisValue));
        end

        function waitUntilIdle(obj)
            % waitUntilIdle() blocks until the axis stops.
            obj.requireReady();
            obj.call('waitUntilIdle', @() obj.Transport.waitUntilIdle(obj.DeviceValue, ...
                obj.AxisValue));
            notify(obj, 'MoveCompleted');
        end

        %% Records ----------------------------------------------------------------------------

        function s = record(obj)
            % s = record() is a plain struct describing the stage and the session's commands.
            s = struct();
            s.Package = 'zaberstage';
            s.Version = zaberstage.version();
            s.RecordedAt = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));
            s.State = obj.State;
            s.FaultReason = obj.FaultReason;
            s.Transport = class(obj.Transport);
            s.Connection = '';
            if ~isempty(obj.Transport)
                s.Connection = obj.Transport.Description;
            end
            s.Identity = obj.Identity;
            s.AxisNumber = obj.AxisValue;
            s.DeviceLimitsUm = obj.DeviceLimitsUm;
            s.LimitsUm = obj.LimitsValue;
            s.IsHomed = obj.IsHomed;
            entries = obj.LogEntries;
            times = obj.ClockEpoch + seconds([entries.Time]);
            times.Format = 'yyyy-MM-dd''T''HH:mm:ss.SSS';
            timeText = cellstr(char(times));
            for k = 1:numel(entries)
                entries(k).Time = timeText{k};
            end
            s.Log = entries;
        end

        function t = log(obj)
            % t = log() is a table of recent commands: Time (s), Command, Value, Ok, Message,
            % DurationMs.
            t = struct2table(obj.LogEntries, 'AsArray', true);
        end

        %% Property access --------------------------------------------------------------------

        function value = get.Port(obj)
            value = obj.PortValue;
        end

        function set.Port(obj, value)
            obj.requireUnlocked('Port');
            obj.PortValue = char(value);
        end

        function value = get.BaudRate(obj)
            value = obj.BaudRateValue;
        end

        function set.BaudRate(obj, value)
            obj.requireUnlocked('BaudRate');
            obj.BaudRateValue = value;
        end

        function value = get.DeviceAddress(obj)
            value = obj.DeviceValue;
        end

        function set.DeviceAddress(obj, value)
            obj.requireUnlocked('DeviceAddress');
            obj.DeviceValue = value;
        end

        function value = get.AxisNumber(obj)
            value = obj.AxisValue;
        end

        function set.AxisNumber(obj, value)
            obj.requireUnlocked('AxisNumber');
            obj.AxisValue = value;
        end

        function value = get.LimitsUm(obj)
            value = obj.LimitsValue;
        end

        function set.LimitsUm(obj, value)
            if ~isnumeric(value) || numel(value) ~= 2 || any(~isfinite(value)) ...
                    || value(1) >= value(2)
                error('zaberstage:Stage:badValue', ...
                    'LimitsUm must be [min max] with min < max (um).');
            end
            value = double(value(:)');
            if ~isempty(obj.DeviceLimitsUm)
                obj.requireWithinDevice(value);
            end
            obj.LimitsValue = value;
        end
    end

    methods (Access = private)
        function value = call(obj, command, action, argument)
            % Runs one transport call, logging it with its outcome and duration.
            if nargin < 4
                argument = NaN;
            end
            started = tic;
            try
                if nargout > 0
                    value = action();
                else
                    action();
                end
            catch err
                obj.addLog(command, argument, false, err.message, toc(started));
                rethrow(err);
            end
            obj.addLog(command, argument, true, '', toc(started));
        end

        function addLog(obj, command, value, ok, message, elapsedS)
            % Appends one command to the log, keeping at most LogCapacity entries.
            entry = struct('Time', toc(obj.ClockStart) - elapsedS, 'Command', command, ...
                'Value', value, 'Ok', ok, 'Message', message, 'DurationMs', 1000 * elapsedS);
            obj.LogEntries(end + 1) = entry;
            if numel(obj.LogEntries) > obj.LogCapacity
                obj.LogEntries(1:end - obj.LogCapacity) = [];
            end
            if obj.Verbose
                fprintf('[zaberstage] %s %g %s (%.1f ms)\n', command, value, message, ...
                    1000 * elapsedS);
            end
        end

        function requireWithinLimits(obj, um)
            % Errors unless um lies within LimitsUm.
            if um < obj.LimitsValue(1) || um > obj.LimitsValue(2)
                error('zaberstage:Stage:outsideLimits', ['%g um refused: outside LimitsUm ' ...
                    '[%g %g]. Change LimitsUm first if this is intended.'], um, ...
                    obj.LimitsValue(1), obj.LimitsValue(2));
            end
        end

        function requireWithinDevice(obj, limits)
            % Errors unless limits lie within the axis's own travel.
            if limits(1) < obj.DeviceLimitsUm(1) || limits(2) > obj.DeviceLimitsUm(2)
                error('zaberstage:Stage:limitsOutsideDevice', ['LimitsUm [%g %g] reach ' ...
                    'beyond the axis''s travel [%g %g] um.'], limits(1), limits(2), ...
                    obj.DeviceLimitsUm(1), obj.DeviceLimitsUm(2));
            end
        end

        function requireReady(obj)
            % Errors unless connected.
            if ~strcmp(obj.State, 'Ready')
                error('zaberstage:Stage:notReady', 'The stage is %s; connect() first.', ...
                    obj.State);
            end
        end

        function requireUnlocked(obj, name)
            % Errors while connected: the address cannot change under an open connection.
            if ~strcmp(obj.State, 'Disconnected')
                error('zaberstage:Stage:portLocked', '%s cannot change while connected.', name);
            end
        end

        function setState(obj, state)
            % Changes State and tells listeners.
            if ~strcmp(obj.State, state)
                obj.State = state;
                notify(obj, 'StateChanged');
            end
        end
    end

    methods (Static, Hidden)
        function s = emptyIdentity()
            % Identity before connect.
            s = struct('DeviceName', '', 'SerialNumber', NaN, 'PeripheralName', '', ...
                'DeviceAddress', NaN);
        end

        function s = emptyLog()
            % A log with no entries.
            s = struct('Time', {}, 'Command', {}, 'Value', {}, 'Ok', {}, 'Message', {}, ...
                'DurationMs', {});
        end
    end
end


function wait = parseWait(options)
% The 'Wait' option of a move (default true).
wait = true;
for k = 1:2:numel(options)
    if strcmpi(options{k}, 'Wait')
        wait = logical(options{k + 1});
    else
        error('zaberstage:Stage:invalidOption', 'Unknown option "%s". Valid: Wait.', ...
            char(options{k}));
    end
end
end


function requireNumber(um)
% Errors unless um is one finite number.
if ~isnumeric(um) || ~isscalar(um) || ~isfinite(um)
    error('zaberstage:Stage:badValue', 'A position must be one finite number (um).');
end
end


function text = describeDevices(devices)
% 'address 1: X-LSM050A (1 axis)' for each device, or 'none'.
if isempty(devices)
    text = 'none';
    return
end
parts = arrayfun(@(d) sprintf('address %d: %s (%d axes)', d.Address, d.Name, d.AxisCount), ...
    devices, 'UniformOutput', false);
text = strjoin(parts, '; ');
end
