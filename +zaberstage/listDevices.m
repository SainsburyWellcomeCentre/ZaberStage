function devices = listDevices(varargin)
% zaberstage.listDevices lists the serial ports and, if asked, the Zaber devices on each.
%
%   devices = zaberstage.listDevices()               ports Windows offers now (no traffic)
%   devices = zaberstage.listDevices('Probe', true)  also detects the Zaber devices on each
%                                                    free port
%
%   Returns a table: Port, Available (not held by another program), Devices (text such as
%   'address 1: X-LSM050A (1 axes)', empty unless probed or when none answered).
%
%   Probing opens each free port with the Zaber Motion Library and sends its device
%   detection, which another kind of device on that port also receives. Probe only on a PC
%   where that is harmless, or name the port yourself. Detection moves nothing.
%
% See also zaberstage.Stage, zaberstage.config, serialportlist
    parser = inputParser;
    parser.addParameter('Probe', false, @(x) islogical(x) || isnumeric(x));
    parser.parse(varargin{:});

    listed = cellstr(serialportlist("all"));
    free = cellstr(serialportlist("available"));
    port = listed(:);
    available = ismember(port, free);
    found = repmat({''}, numel(port), 1);
    if parser.Results.Probe
        for k = find(available(:))'
            found{k} = probe(port{k});
        end
    end
    devices = table(port, available, found, 'VariableNames', {'Port', 'Available', 'Devices'});
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
