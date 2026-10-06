function cfg = config(varargin)
% zaberstage.config is the resolved defaults of the zaberstage package.
%
%   cfg = zaberstage.config() returns a struct:
%       RootDir   package root (the folder containing +zaberstage)
%       Port      default serial port for zaberstage.Stage ('' when none is set)
%       BaudRate  default bits per second (115200, the Zaber ASCII default)
%       Axes      default axes for zaberstage.app: a struct, one field per axis name, each a
%                 struct of zaberstage.Stage options (AxisNumber, DeviceAddress, Reversed,
%                 SafeLimitsUm, LimitsUm); struct() when none is set, and the panel then
%                 shows every axis it finds with its whole travel. A client sets the rig's,
%                 e.g. LuminoseHF from its luminose_config.yaml
%       Version   package version (zaberstage.version)
%
%   cfg = zaberstage.config('Port', 'COM14') overrides entries for this call. Persistent
%   overrides use MATLAB preferences, kept per Windows user across sessions:
%       setpref('zaberstage', 'Port', 'COM14')
%       setpref('zaberstage', 'Axes', struct('Z', struct('AxisNumber', 3, ...
%           'SafeLimitsUm', [-Inf 30000])))
%   Precedence: arguments, then preferences, then the defaults above.
%
%   Errors with 'zaberstage:config:invalidOption' for an unknown or malformed option.
%
% See also zaberstage.Stage, zaberstage.listDevices
    cfg = struct();
    cfg.RootDir = fileparts(fileparts(mfilename('fullpath')));
    cfg.Port = '';
    cfg.BaudRate = 115200;
    cfg.Axes = struct();
    cfg.Version = zaberstage.version();

    overridable = {'Port', 'BaudRate', 'Axes'};
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
    if ~isstruct(cfg.Axes) || ~isscalar(cfg.Axes) ...
            || ~all(structfun(@(a) isstruct(a) && isscalar(a), cfg.Axes))
        error('zaberstage:config:invalidOption', ['Axes must be a struct of structs, one ' ...
            'field per axis name (zaberstage.Stage options).']);
    end
end
