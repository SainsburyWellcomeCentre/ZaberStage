function devices = listDevices(varargin)
% zaberstage.listDevices lists the serial ports and which of them are Zaber controllers.
%
%   devices = zaberstage.listDevices()               ports Windows offers now (no traffic)
%   devices = zaberstage.listDevices('Probe', true)  also detects the Zaber devices on each
%                                                    free port
%
%   Returns a table, one row per port Windows offers now:
%       Port         'COM14'
%       Available    not held by another program
%       IsZaber      the port is a Zaber USB controller (USB vendor 2939, e.g. an X-MCC).
%                    Read from the Windows registry, with no traffic on any port. A
%                    controller behind a USB-serial adapter is not recognised: probe for it
%       Description  the device's name in Device Manager, or ''
%       Devices      text such as 'address 1: X-MCC3 (3 axes)', empty unless probed or
%                    when none answered
%
%   Probing opens each free port with the Zaber Motion Library and sends its device
%   detection, which another kind of device on that port also receives. Probe only on a PC
%   where that is harmless, or name the port yourself. Detection moves nothing.
%
%   Example
%       devices = zaberstage.listDevices();
%       port = devices.Port(devices.IsZaber);   % e.g. {'COM14'}
%
% See also zaberstage.Stage, zaberstage.config, zaberstage.app, serialportlist
    parser = inputParser;
    parser.addParameter('Probe', false, @(x) islogical(x) || isnumeric(x));
    parser.parse(varargin{:});

    listed = cellstr(serialportlist("all"));
    free = cellstr(serialportlist("available"));
    port = listed(:);
    available = ismember(port, free);
    [usbPorts, usbNames] = zaberUsbPorts();
    [isZaber, where] = ismember(upper(port), upper(usbPorts));
    description = repmat({''}, numel(port), 1);
    description(isZaber) = usbNames(where(isZaber));
    found = repmat({''}, numel(port), 1);
    if parser.Results.Probe
        for k = find(available(:))'
            found{k} = probe(port{k});
        end
        isZaber = isZaber | ~cellfun(@isempty, found);
    end
    devices = table(port, available, isZaber, description, found, 'VariableNames', ...
        {'Port', 'Available', 'IsZaber', 'Description', 'Devices'});
end


function [ports, names] = zaberUsbPorts()
% The COM ports Windows has given Zaber USB devices (vendor 2939), and their names.
%
%   Reads HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_2939&PID_*\<instance>: FriendlyName
%   and Device Parameters\PortName. Entries stay after a device is unplugged, so the
%   caller keeps only ports Windows offers now. Never throws: off Windows, or if the
%   registry cannot be read, nothing is found.
ports = {};
names = {};
if ~ispc()
    return
end
try
    % .NET must be started before its names resolve; NET.isNETSupported starts it
    if ~NET.isNETSupported
        return
    end
    machine = Microsoft.Win32.Registry.LocalMachine;
    usb = machine.OpenSubKey('SYSTEM\CurrentControlSet\Enum\USB');
    if isempty(usb)
        return
    end
    closeUsb = onCleanup(@() usb.Close());
    devices = usb.GetSubKeyNames();
    for d = 1:devices.Length
        device = char(devices(d));
        if ~startsWith(device, 'VID_2939', 'IgnoreCase', true)
            continue
        end
        instances = usb.OpenSubKey(device);
        instanceNames = instances.GetSubKeyNames();
        for k = 1:instanceNames.Length
            instance = instances.OpenSubKey(instanceNames(k));
            parameters = instance.OpenSubKey('Device Parameters');
            if ~isempty(parameters)
                portName = char(parameters.GetValue('PortName', ''));
                parameters.Close();
                if ~isempty(portName)
                    ports{end + 1} = portName; %#ok<AGROW>
                    names{end + 1} = char(instance.GetValue('FriendlyName', '')); %#ok<AGROW>
                end
            end
            instance.Close();
        end
        instances.Close();
    end
catch
    % A registry that cannot be read means no port is recognised; the user picks one.
end
end


function text = probe(port)
% The Zaber devices that answer on port, as text, or '' when none does.
text = '';
transport = zaberstage.transport.MotionLibraryTransport(port, 'Direct', true);
cleanup = onCleanup(@() transport.close());
try
    transport.open();
    devices = transport.listDevices();
    parts = arrayfun(@(d) sprintf('address %d: %s (%d axes)', d.Address, d.Name, ...
        d.AxisCount), devices, 'UniformOutput', false);
    text = strjoin(parts, '; ');
catch
    % A port that will not open or answer has no Zaber device for this purpose.
end
end
