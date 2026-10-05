function varargout = app(varargin)
% zaberstage.app opens the stage control window.
%
%   zaberstage.app()               opens a window that owns its own zaberstage.Stage
%   zaberstage.app(stage)          attaches to an existing zaberstage.Stage (never
%                                  disconnects it)
%   zaberstage.app(..., 'Name', value)  options of zaberstage.gui.StageApp
%   a = zaberstage.app(...)        returns the zaberstage.gui.StageApp object
%
% See also zaberstage.gui.StageApp, zaberstage.Stage
    appObject = zaberstage.gui.StageApp(varargin{:});
    if nargout > 0
        varargout{1} = appObject;
    end
end
