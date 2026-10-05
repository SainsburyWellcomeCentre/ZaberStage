function cfg = config(varargin)
% zaberstage.config is the resolved defaults of the zaberstage package.
%
%   cfg = zaberstage.config() returns a struct:
%       RootDir   package root (the folder containing +zaberstage)
%       Port      default serial port for zaberstage.Stage ('' when none is set)
%       BaudRate  default bits per second (115200, the Zaber ASCII default)
%       Version   package version (zaberstage.version)
%
%   cfg = zaberstage.config('Port', 'COM14') overrides entries for this call. Persistent
%   overrides use MATLAB preferences, kept per Windows user across sessions:
%       setpref('zaberstage', 'Port', 'COM14')
%   Precedence: arguments, then preferences, then the defaults above.
%
%   Errors with 'zaberstage:config:invalidOption' for an unknown or malformed option.
%
% See also zaberstage.Stage, zaberstage.listDevices
    cfg = struct();
    cfg.RootDir = fileparts(fileparts(mfilename('fullpath')));
    cfg.Port = '';
    cfg.BaudRate = 115200;
    cfg.Version = zaberstage.version();

    overridable = {'Port', 'BaudRate'};
    for k = 1:numel(overridable)
        name = overridable{k};
        if ispref('zaberstage', name)
            cfg.(name) = getpref('zaberstage', name);
        end
    end
    if mod(numel(varargin), 2) ~= 0
        error('zaberstage:config:invalidOption', 'Options must be name-value pairs.');
    end
    for k = 1:2:numel(varargin)
        match = strcmpi(overridable, char(varargin{k}));
        if ~any(match)
            error('zaberstage:config:invalidOption', 'Unknown option "%s". Valid: %s.', ...
                char(varargin{k}), strjoin(overridable, ', '));
        end
        cfg.(overridable{match}) = varargin{k + 1};
    end
    cfg.Port = char(cfg.Port);
end
