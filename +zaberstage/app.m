function varargout = app(varargin)
% zaberstage.app opens the stage control panel, with every axis of a Zaber controller.
%
%   zaberstage.app()               a window that owns its axes: Connect finds the Zaber
%                                  port and every axis on it (X, Y, Z...)
%   zaberstage.app('Axes', axes)   owned axes with these settings (a struct, one field per
%                                  axis name, each a struct of zaberstage.Stage options)
%   zaberstage.app(stages)         attaches to existing zaberstage.Stage objects (a struct
%                                  x, y, z..., an array or one Stage; never disconnects them)
%   zaberstage.app(..., 'Name', value)  options of zaberstage.gui.StageApp
%   a = zaberstage.app(...)        returns the zaberstage.gui.StageApp object
%
% See also zaberstage.gui.StageApp, zaberstage.Stage
    appObject = zaberstage.gui.StageApp(varargin{:});
    if nargout > 0
        varargout{1} = appObject;
    end
end
