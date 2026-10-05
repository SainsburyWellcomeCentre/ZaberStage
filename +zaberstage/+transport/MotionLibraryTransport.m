classdef MotionLibraryTransport < zaberstage.transport.Transport
% zaberstage.transport.MotionLibraryTransport drives Zaber controllers with the Motion Library.
%
%   t = zaberstage.transport.MotionLibraryTransport('COM14')
%   t = zaberstage.transport.MotionLibraryTransport('COM14', 'BaudRate', 115200, 'Direct', true)
%
%   Uses the Zaber Motion Library for MATLAB (ASCII protocol), installed as a MATLAB add-on
%   (verified with 9.3.2; docs/zaber-motion.md). The port is opened by open(), not by the
%   constructor. With 'Direct' false (the default) a port that Zaber Launcher holds is shared
%   through Launcher; with true it is opened directly and fails if Launcher has it.
%
%   Errors with 'zaberstage:MotionLibraryTransport:noLibrary' when the library is not on the
%   path, 'zaberstage:MotionLibraryTransport:openFailed' when the port cannot be opened, and
%   'zaberstage:MotionLibraryTransport:notOpen' before open(). Library errors from moves (an
%   unhomed axis, a position outside the device's own limits) pass through with their
%   zaber.motion identifiers.
%
% See also zaberstage.transport.Transport, zaberstage.Stage

    properties (SetAccess = private)
        Port      % serial port name
        BaudRate  % bits per second
        Direct    % open the port directly, not through Zaber Launcher
    end

    properties (SetAccess = protected)
        Description = ''  % 'COM14'
    end

    properties (Access = private)
        Connection = []
        Devices = {}
    end

    methods
        function obj = MotionLibraryTransport(port, varargin)
            parser = inputParser;
            parser.addRequired('Port', @(x) ischar(x) || isstring(x));
            parser.addParameter('BaudRate', 115200, @(x) isnumeric(x) && isscalar(x));
            parser.addParameter('Direct', false, @(x) islogical(x) || isnumeric(x));
            parser.parse(port, varargin{:});
            obj.Port = char(parser.Results.Port);
            obj.BaudRate = parser.Results.BaudRate;
            obj.Direct = logical(parser.Results.Direct);
            obj.Description = obj.Port;
        end

        function open(obj)
            if obj.isOpen()
                return
            end
            if isempty(which('zaber.motion.ascii.Connection'))
                error('zaberstage:MotionLibraryTransport:noLibrary', ['The Zaber Motion ' ...
                    'Library is not on the path. Install it from the MATLAB Add-On Explorer ' ...
                    '("Zaber Motion Library").']);
            end
            try
                obj.Connection = zaber.motion.ascii.Connection.openSerialPort(obj.Port, ...
                    'baudRate', obj.BaudRate, 'direct', obj.Direct);
            catch err
                error('zaberstage:MotionLibraryTransport:openFailed', ['Could not open %s ' ...
                    '(%s). Check the port and that no other program holds it.'], obj.Port, ...
                    err.message);
            end
        end

        function close(obj)
            try
                if ~isempty(obj.Connection)
                    obj.Connection.close();
                end
            catch
                % Closing must never throw: it runs from delete and cleanup paths.
            end
            obj.Connection = [];
            obj.Devices = {};
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Connection);
        end

        function devices = listDevices(obj)
            obj.requireOpen();
            found = obj.Connection.detectDevices();
            obj.Devices = num2cell(found);
            devices = struct('Address', {}, 'Name', {}, 'SerialNumber', {}, 'AxisCount', {});
            for k = 1:numel(found)
                devices(k) = struct('Address', double(found(k).DeviceAddress), ...
                    'Name', char(found(k).Name), 'SerialNumber', double(found(k).SerialNumber), ...
                    'AxisCount', double(found(k).AxisCount));
            end
        end

        function info = axisInfo(obj, device, axisNumber)
            handle = obj.axisHandle(device, axisNumber);
            micrometres = zaber.motion.Units.LengthMicrometres;
            info = struct();
            info.Name = char(handle.PeripheralName);
            info.LimitsUm = [handle.Settings.get('limit.min', micrometres), ...
                handle.Settings.get('limit.max', micrometres)];
            info.IsHomed = handle.isHomed();
        end

        function home(obj, device, axisNumber, wait)
            obj.axisHandle(device, axisNumber).home('waitUntilIdle', wait);
        end

        function moveAbsolute(obj, device, axisNumber, um, wait)
            obj.axisHandle(device, axisNumber).moveAbsolute(um, ...
                zaber.motion.Units.LengthMicrometres, 'waitUntilIdle', wait);
        end

        function moveRelative(obj, device, axisNumber, um, wait)
            obj.axisHandle(device, axisNumber).moveRelative(um, ...
                zaber.motion.Units.LengthMicrometres, 'waitUntilIdle', wait);
        end

        function stop(obj, device, axisNumber)
            obj.axisHandle(device, axisNumber).stop();
        end

        function um = positionUm(obj, device, axisNumber)
            handle = obj.axisHandle(device, axisNumber);
            um = handle.getPosition(zaber.motion.Units.LengthMicrometres);
        end

        function tf = isBusy(obj, device, axisNumber)
            tf = obj.axisHandle(device, axisNumber).isBusy();
        end

        function waitUntilIdle(obj, device, axisNumber)
            obj.axisHandle(device, axisNumber).waitUntilIdle();
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function handle = axisHandle(obj, device, axisNumber)
            % The library's Axis object for a device address and axis number.
            obj.requireOpen();
            if isempty(obj.Devices)
                obj.listDevices();
            end
            addresses = cellfun(@(d) double(d.DeviceAddress), obj.Devices);
            match = find(addresses == device, 1);
            if isempty(match)
                error('zaberstage:MotionLibraryTransport:noDevice', ...
                    'No device at address %d on %s.', device, obj.Port);
            end
            handle = obj.Devices{match}.getAxis(axisNumber);
        end

        function requireOpen(obj)
            % Errors unless the port is open.
            if ~obj.isOpen()
                error('zaberstage:MotionLibraryTransport:notOpen', ...
                    '%s is not open; call open() first.', obj.Port);
            end
        end
    end
end
