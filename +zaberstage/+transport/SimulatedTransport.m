classdef SimulatedTransport < zaberstage.transport.Transport
% zaberstage.transport.SimulatedTransport is a Zaber stage without hardware: moves, records, fails.
%
%   t = zaberstage.transport.SimulatedTransport()
%   t = zaberstage.transport.SimulatedTransport('LimitsUm', [0 50000], 'SpeedUmPerS', 0)
%   stage = zaberstage.Stage('Transport', t);
%
%   One device (address 1, 'X-LSM050A', serial 12345) with one axis, unless Devices is set.
%   Like the real controller it refuses a move on an unhomed axis and a target outside the
%   axis's own limits (as the Motion Library does: errors with the identifiers below), and
%   homing goes to the axis's minimum. With SpeedUmPerS 0 (the default) every move finishes
%   at once; with a speed, a move started without waiting takes distance / speed seconds of
%   real time, so isBusy and stop() can be tested.
%
%   Properties
%       Devices      struct array Address, Name, SerialNumber, AxisCount
%       LimitsUm     every axis's own [min max] (default [0 50000], a 50 mm stage)
%       PeripheralName  reported axis name (default '')
%       SpeedUmPerS  simulated speed; 0 = instant
%       StartHomed   whether axes start homed (default false, as after power-up)
%   Read-only state
%       Calls        struct array Time (s), Command, Device, Axis, Value: every call
%       PositionsUm  map 'device.axis' -> position (um)
%
%   Fault injection
%       failNext(command, identifier)  the next call of command ('moveAbsolute', 'home', ...)
%                                      errors with identifier and changes nothing
%       unplug()                       every later call errors, as a pulled cable does
%       clearCalls(), callsOf(command)
%
%   Errors like the library: 'zaberstage:SimulatedTransport:notHomed' (the library's
%   zaber.motion.exceptions.MovementFailedException), 'zaberstage:SimulatedTransport:outOfRange'
%   (its BADDATA command rejection), 'zaberstage:SimulatedTransport:noDevice',
%   'zaberstage:SimulatedTransport:notOpen', 'zaberstage:SimulatedTransport:unplugged'.
%
% See also zaberstage.transport.Transport, zaberstage.Stage

    properties
        Devices = struct('Address', 1, 'Name', 'X-LSM050A', 'SerialNumber', 12345, ...
            'AxisCount', 1)       % the simulated daisy chain
        LimitsUm = [0 50000]      % every axis's own limits, um
        PeripheralName = ''       % reported axis name
        SpeedUmPerS = 0           % simulated speed; 0 = instant
        StartHomed = false        % axes start homed
    end

    properties (SetAccess = protected)
        Description = 'simulated Zaber'  % for records
    end

    properties (SetAccess = private)
        Calls = struct('Time', {}, 'Command', {}, 'Device', {}, 'Axis', {}, 'Value', {})
        PositionsUm  % containers.Map 'device.axis' -> position, um
    end

    properties (Access = private)
        Opened = false
        Unplugged = false
        Homed        % containers.Map 'device.axis' -> logical
        Moves        % containers.Map 'device.axis' -> struct From, To, Started, Duration
        Failures = struct('Command', {}, 'Identifier', {})
        ClockStart
    end

    methods
        function obj = SimulatedTransport(varargin)
            obj.ClockStart = tic;
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k + 1};
            end
            obj.PositionsUm = containers.Map();
            obj.Homed = containers.Map();
            obj.Moves = containers.Map();
        end

        function open(obj)
            obj.record('open', NaN, NaN, NaN);
            obj.Opened = true;
        end

        function close(obj)
            obj.Opened = false;
        end

        function tf = isOpen(obj)
            tf = obj.Opened;
        end

        function devices = listDevices(obj)
            obj.record('listDevices', NaN, NaN, NaN);
            devices = obj.Devices;
        end

        function info = axisInfo(obj, device, axisNumber)
            key = obj.record('axisInfo', device, axisNumber, NaN);
            info = struct('Name', obj.PeripheralName, 'LimitsUm', obj.LimitsUm, ...
                'IsHomed', obj.Homed(key));
        end

        function home(obj, device, axisNumber, ~)
            key = obj.record('home', device, axisNumber, NaN);
            obj.PositionsUm(key) = obj.LimitsUm(1);
            obj.Homed(key) = true;
            if isKey(obj.Moves, key)
                remove(obj.Moves, key);
            end
        end

        function moveAbsolute(obj, device, axisNumber, um, wait)
            key = obj.record('moveAbsolute', device, axisNumber, um);
            obj.startMove(key, um, wait);
        end

        function moveRelative(obj, device, axisNumber, um, wait)
            key = obj.record('moveRelative', device, axisNumber, um);
            obj.startMove(key, obj.currentUm(key) + um, wait);
        end

        function stop(obj, device, axisNumber)
            key = obj.record('stop', device, axisNumber, NaN);
            obj.PositionsUm(key) = obj.currentUm(key);
            if isKey(obj.Moves, key)
                remove(obj.Moves, key);
            end
        end

        function um = positionUm(obj, device, axisNumber)
            key = obj.record('positionUm', device, axisNumber, NaN);
            um = obj.currentUm(key);
        end

        function tf = isBusy(obj, device, axisNumber)
            key = obj.record('isBusy', device, axisNumber, NaN);
            obj.currentUm(key);
            tf = isKey(obj.Moves, key);
        end

        function waitUntilIdle(obj, device, axisNumber)
            key = obj.record('waitUntilIdle', device, axisNumber, NaN);
            if isKey(obj.Moves, key)
                move = obj.Moves(key);
                obj.PositionsUm(key) = move.To;
                remove(obj.Moves, key);
            end
        end

        function failNext(obj, command, identifier)
            % failNext(command, identifier) makes the next call of command error.
            if nargin < 3
                identifier = 'zaberstage:SimulatedTransport:injected';
            end
            obj.Failures(end + 1) = struct('Command', char(command), ...
                'Identifier', char(identifier));
        end

        function unplug(obj)
            % unplug() makes every later call error, as a pulled cable does.
            obj.Unplugged = true;
        end

        function clearCalls(obj)
            % clearCalls() empties Calls.
            obj.Calls = struct('Time', {}, 'Command', {}, 'Device', {}, 'Axis', {}, ...
                'Value', {});
        end

        function calls = callsOf(obj, command)
            % calls = callsOf(command) is the Calls entries for one command.
            calls = obj.Calls(strcmp({obj.Calls.Command}, command));
        end
    end

    methods (Access = private)
        function key = record(obj, command, device, axisNumber, value)
            % Logs a call, applies the checks every call shares and returns its axis key.
            if obj.Unplugged
                error('zaberstage:SimulatedTransport:unplugged', ...
                    'The simulated stage was unplugged.');
            end
            if ~obj.Opened && ~strcmp(command, 'open')
                error('zaberstage:SimulatedTransport:notOpen', 'The simulated port is not open.');
            end
            obj.Calls(end + 1) = struct('Time', toc(obj.ClockStart), 'Command', command, ...
                'Device', device, 'Axis', axisNumber, 'Value', value);
            key = '';
            for k = 1:numel(obj.Failures)
                if strcmp(obj.Failures(k).Command, command)
                    identifier = obj.Failures(k).Identifier;
                    obj.Failures(k) = [];
                    error(identifier, 'Injected failure of %s.', command);
                end
            end
            if isnan(device)
                return
            end
            match = [obj.Devices.Address] == device;
            if ~any(match) || axisNumber < 1 || axisNumber > obj.Devices(match).AxisCount
                error('zaberstage:SimulatedTransport:noDevice', ...
                    'No axis %d on a device at address %d.', axisNumber, device);
            end
            key = sprintf('%d.%d', device, axisNumber);
            if ~isKey(obj.PositionsUm, key)
                obj.PositionsUm(key) = obj.LimitsUm(1);
                obj.Homed(key) = obj.StartHomed;
            end
        end

        function startMove(obj, key, target, wait)
            % Starts (or completes) a move after the controller's own checks.
            if ~obj.Homed(key)
                error('zaberstage:SimulatedTransport:notHomed', ...
                    'Movement failed: the axis is not homed (simulated).');
            end
            if target < obj.LimitsUm(1) || target > obj.LimitsUm(2)
                error('zaberstage:SimulatedTransport:outOfRange', ...
                    'Command rejected: %g um is outside the axis limits (simulated).', target);
            end
            from = obj.currentUm(key);
            if wait || obj.SpeedUmPerS <= 0
                obj.PositionsUm(key) = target;
                if isKey(obj.Moves, key)
                    remove(obj.Moves, key);
                end
            else
                obj.Moves(key) = struct('From', from, 'To', target, 'Started', ...
                    toc(obj.ClockStart), 'Duration', abs(target - from) / obj.SpeedUmPerS);
            end
        end

        function um = currentUm(obj, key)
            % The axis position now, advancing a move in progress.
            um = obj.PositionsUm(key);
            if ~isKey(obj.Moves, key)
                return
            end
            move = obj.Moves(key);
            elapsed = toc(obj.ClockStart) - move.Started;
            if elapsed >= move.Duration
                um = move.To;
                obj.PositionsUm(key) = um;
                remove(obj.Moves, key);
            else
                um = move.From + (move.To - move.From) * elapsed / move.Duration;
            end
        end
    end
end
