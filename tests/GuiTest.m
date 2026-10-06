classdef GuiTest < matlab.unittest.TestCase
% GuiTest drives zaberstage.gui.StageApp on a simulated three-axis controller, hidden.
%
%   The port list is made up ('ListDevices'), so no test opens a real port. Controls are
%   driven as a user would: set a component's Value, then call its callback.
%
% See also zaberstage.gui.StageApp, zaberstage.Stage

    properties
        Transport
        App
    end

    methods (TestMethodSetup)
        function makeApp(testCase)
            testCase.Transport = threeAxes();
            % 'Axes', struct(): every axis found, whatever default this PC has set
            testCase.App = zaberstage.gui.StageApp('Transport', testCase.Transport, ...
                'Visible', false, 'AutoRefresh', false, 'ListDevices', @() ports(true), ...
                'Axes', struct());
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods (Test)
        function opensWithoutTouchingTheStage(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Connect');
            testCase.verifyEmpty(testCase.App.Stages);
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                zaberstage.gui.StageApp.OffColour);
        end

        function connectFindsEveryAxis(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyEqual(testCase.App.Names, {'X', 'Y', 'Z'});
            testCase.verifyEqual({testCase.App.Stages.State}, {'Ready', 'Ready', 'Ready'});
            testCase.verifyEqual([testCase.App.Stages.AxisNumber], [1 2 3]);
            testCase.verifyNumElements(testCase.App.Controls.Axes, 3);
            testCase.verifySubstring(testCase.App.Controls.Name.Text, 'X-MCC3');
            testCase.verifySubstring(testCase.App.Controls.Identity.Text, '3 axes');
            testCase.verifyEqual(testCase.App.Controls.Axes(2).Homed.Text, 'NOT HOMED');
            testCase.verifyEqual(testCase.App.Controls.Axes(1).Position.Text, '0.000');
            testCase.verifyEqual(testCase.App.Controls.Axes(1).Target.Value, 0);
        end

        function eachAxisMovesOnItsOwn(testCase)
            testCase.connectAndHome();
            app = testCase.App;
            app.Controls.Step.Value = 0.025;   % mm
            testCase.press(app.Controls.Axes(1).JogPlus);
            testCase.press(app.Controls.Axes(1).JogPlus);
            testCase.press(app.Controls.Axes(3).JogPlus);
            testCase.press(app.Controls.Axes(3).JogMinus);
            app.Controls.Axes(2).Target.Value = 1;   % mm
            testCase.press(app.Controls.Axes(2).Go);
            testCase.verifyEqual(app.Positions, [50 1000 0], 'AbsTol', 1e-9);   % um
            testCase.verifyEqual(app.Controls.Axes(2).Position.Text, '1.000');
        end

        function movesAreSentWithoutWaiting(testCase)
            testCase.connectAndHome();
            testCase.Transport.clearCalls();
            testCase.App.goTo('Y', 500);
            call = testCase.Transport.callsOf('moveAbsolute');
            testCase.verifyEqual(call(end).Axis, 2);
            testCase.verifyEqual(testCase.App.Stages(2).log().Command{end - 2}, 'moveAbsolute');
        end

        function aMoveOutsideTheLimitsIsShownNotThrown(testCase)
            testCase.connectAndHome();
            app = testCase.App;
            testCase.setValue(app.Controls.Axes(3).Max, 2);   % mm
            testCase.verifyEqual(app.Stages(3).LimitsUm, [0 2000]);
            app.goTo('Z', 3000);
            testCase.verifySubstring(app.LastError, 'outside LimitsUm');
            testCase.verifyEqual(app.Stages(3).positionUm(), 0);
        end

        function aLimitBeyondTheTravelIsShownAndUndone(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.setValue(testCase.App.Controls.Axes(1).Max, 99.999);
            testCase.verifySubstring(testCase.App.LastError, 'beyond the axis');
            testCase.verifyEqual(testCase.App.Controls.Axes(1).Max.Value, 50);   % mm
        end

        function stopAndEscapeStopEveryAxis(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.Transport.clearCalls();
            testCase.press(testCase.App.Controls.Stop);
            testCase.verifyEqual(sort([testCase.Transport.callsOf('stop').Axis]), [1 2 3]);
            fig = testCase.App.Figure;
            fig.KeyPressFcn(fig, struct('Key', 'escape'));
            testCase.verifyNumElements(testCase.Transport.callsOf('stop'), 6);
        end

        function lampIsAmberWhileMoving(testCase)
            testCase.Transport.SpeedUmPerS = 1000;
            testCase.connectAndHome();
            testCase.App.goTo('X', 2000);   % two seconds of simulated travel
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                zaberstage.gui.StageApp.MoveColour);
            testCase.verifyEqual(testCase.App.Controls.State.Text, 'Moving');
            testCase.App.stopAll();
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                zaberstage.gui.StageApp.DimFactor * zaberstage.gui.StageApp.ReadyColour);
        end

        function homeIsRefusedOutsideTheSafeRange(testCase)
            axesGiven = struct('Z', struct('AxisNumber', 3, 'SafeLimitsUm', [1000 Inf]));
            app = zaberstage.gui.StageApp('Transport', threeAxes(), 'Axes', axesGiven, ...
                'Visible', false, 'AutoRefresh', false, 'ListDevices', @() ports(true));
            testCase.addTeardown(@() app.close());
            testCase.verifyEqual(app.Names, {'Z'});
            testCase.press(app.Controls.Connect);
            testCase.press(app.Controls.Axes(1).Home);
            testCase.verifySubstring(app.LastError, 'outside SafeLimitsUm');
            testCase.verifySubstring(app.Controls.Axes(1).Travel.Text, 'safe 1 to Inf');
            testCase.verifySubstring(app.Controls.Axes(1).Travel.Text, 'travel 0-50 mm');
        end

        function defaultAxesComeFromThePreferences(testCase)
            saved = [];
            if ispref('zaberstage', 'Axes')
                saved = getpref('zaberstage', 'Axes');
            end
            testCase.addTeardown(@() restoreAxes(saved));
            setpref('zaberstage', 'Axes', struct('Z', struct('AxisNumber', 3, ...
                'SafeLimitsUm', [-Inf 30000])));
            app = zaberstage.gui.StageApp('Transport', threeAxes(), 'Visible', false, ...
                'AutoRefresh', false, 'ListDevices', @() ports(true));
            testCase.addTeardown(@() app.close());
            testCase.verifyEqual(app.Names, {'Z'});
            testCase.verifyEqual(app.Stages(1).SafeLimitsUm, [-Inf 30000]);
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            testCase.verifyEqual(app.Stages(1).LimitsUm, [0 30000]);
        end

        function axesOptionNamesAndSettings(testCase)
            axesGiven = struct('focus', struct('AxisNumber', 3), 'side', struct( ...
                'AxisNumber', 1, 'Reversed', true));
            app = zaberstage.gui.StageApp('Transport', threeAxes(), 'Axes', axesGiven, ...
                'Visible', false, 'AutoRefresh', false, 'ListDevices', @() ports(true));
            testCase.addTeardown(@() app.close());
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            testCase.verifyEqual(app.Names, {'focus', 'side'});
            testCase.verifyEqual([app.Stages.AxisNumber], [3 1]);
            testCase.verifyTrue(app.Stages(2).Reversed);
            testCase.verifySubstring(app.Controls.Axes(2).Travel.Text, 'reversed');
        end

        function connectFindsTheZaberPort(testCase)
            app = zaberstage.gui.StageApp('Visible', false, 'AutoRefresh', false, ...
                'ListDevices', @() ports(true), 'Axes', struct());
            testCase.addTeardown(@() app.close());
            testCase.verifyEqual(app.Controls.Port.Value, 'COM14');
            testCase.verifySubstring(app.Controls.Identity.Text, 'Found the Zaber');
        end

        function noZaberPortIsShown(testCase)
            app = zaberstage.gui.StageApp('Visible', false, 'AutoRefresh', false, ...
                'ListDevices', @() ports(false), 'Axes', struct());
            testCase.addTeardown(@() app.close());
            testCase.verifySubstring(app.Controls.Identity.Text, 'No Zaber controller');
        end

        function disconnectStopsAndClosesThePort(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyEqual({testCase.App.Stages.State}, ...
                {'Disconnected', 'Disconnected', 'Disconnected'});
            testCase.verifyFalse(testCase.Transport.isOpen());
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Connect');
        end

        function closingOwnedAxesDisconnectsThem(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.close();
            testCase.verifyFalse(testCase.Transport.isOpen());
        end

        function goToStartsAtThePosition(testCase)
            transport = threeAxes();
            transport.StartHomed = true;
            transport.open();
            stage = zaberstage.Stage('Transport', transport, 'SharedTransport', true, ...
                'AxisNumber', 2);
            stage.connect();
            stage.moveAbsolute(31234);
            stage.disconnect();
            app = zaberstage.gui.StageApp(stage, 'Visible', false, 'AutoRefresh', false);
            testCase.addTeardown(@() app.close());
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            testCase.verifyEqual(app.Controls.Axes(1).Target.Value, 31.234, 'AbsTol', 1e-12);
            app.Controls.Axes(1).Go.ButtonPushedFcn(app.Controls.Axes(1).Go, []);
            testCase.verifyEqual(stage.positionUm(), 31234);   % Go at once moves nothing
        end

        function attachesToARigStruct(testCase)
            transport = threeAxes();
            transport.open();
            rig = struct();
            for name = {'x', 'y', 'z'}
                rig.(name{1}) = zaberstage.Stage('Transport', transport, ...
                    'SharedTransport', true, 'AxisNumber', find(strcmp({'x', 'y', 'z'}, ...
                    name{1})));
                rig.(name{1}).connect();
            end
            rig.close = @() transport.close();   % a non-Stage field is skipped
            app = zaberstage.gui.StageApp(rig, 'Visible', false, 'AutoRefresh', false);
            testCase.verifyEqual(app.Names, {'X', 'Y', 'Z'});
            testCase.verifyEqual(app.Controls.Connect.Text, 'Disconnect');
            app.close();
            testCase.verifyEqual(rig.y.State, 'Ready');   % attached: left connected
            testCase.verifyTrue(transport.isOpen());
            rig.close();
        end

        function detailsHoldPortAndLimits(testCase)
            testCase.press(testCase.App.Controls.Connect);
            c = testCase.App.Controls;
            testCase.verifyEqual(c.DetailsArea.Visible, matlab.lang.OnOffSwitchState('off'));
            height = testCase.App.Figure.Position(4);
            testCase.setValue(c.Details, true);
            testCase.verifyGreaterThan(testCase.App.Figure.Position(4), height);
            testCase.verifyTrue(isDescendant(c.Port, c.DetailsArea));
            testCase.verifyTrue(isDescendant(c.Axes(1).Min, c.DetailsArea));
            testCase.verifyFalse(isDescendant(c.Axes(1).Go, c.DetailsArea));
            testCase.setValue(c.Details, false);
            testCase.verifyEqual(testCase.App.Figure.Position(4), height);
        end

        function embedsInAClassicFigure(testCase)
            host = figure('Visible', 'off');
            testCase.addTeardown(@() delete(host));
            holder = uipanel(host, 'Units', 'pixels', 'Position', [10 10 600 300]);
            app = zaberstage.gui.StageApp('Transport', threeAxes(), 'Parent', holder, ...
                'AutoRefresh', false, 'ListDevices', @() ports(true), 'Axes', struct());
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            testCase.verifyNumElements(app.Stages, 3);
            testCase.verifyEmpty(app.Controls.Log);
            app.close();
            testCase.verifyTrue(isvalid(host));
            testCase.verifyEmpty(holder.Children);
        end
    end

    methods (Access = private)
        function connectAndHome(testCase)
            % Connects and homes every axis.
            testCase.press(testCase.App.Controls.Connect);
            for k = 1:numel(testCase.App.Stages)
                testCase.App.home(testCase.App.Names{k});
            end
        end

        function press(~, button)
            % Calls a button's callback as a click would.
            button.ButtonPushedFcn(button, []);
        end

        function setValue(~, component, value)
            % Sets a component's value and calls its callback as an edit would.
            component.Value = value;
            component.ValueChangedFcn(component, []);
        end
    end
end


function t = threeAxes()
% A simulated X-MCC3: one device, three axes.
t = zaberstage.transport.SimulatedTransport('Devices', struct('Address', 1, 'Name', ...
    'X-MCC3', 'SerialNumber', 4242, 'AxisCount', 3));
end


function devices = ports(withZaber)
% A port table like zaberstage.listDevices: COM3 (not Zaber) and, if asked, COM14.
names = {'COM3'};
isZaber = false;
if withZaber
    names{end + 1} = 'COM14';
    isZaber(end + 1) = true;
end
n = numel(names);
devices = table(names(:), true(n, 1), isZaber(:), repmat({''}, n, 1), repmat({''}, n, 1), ...
    'VariableNames', {'Port', 'Available', 'IsZaber', 'Description', 'Devices'});
end


function tf = isDescendant(component, ancestorComponent)
% True when component sits somewhere inside ancestorComponent.
tf = false;
node = component.Parent;
while ~isempty(node) && ~isa(node, 'matlab.ui.Figure')
    if node == ancestorComponent
        tf = true;
        return
    end
    node = node.Parent;
end
end


function restoreAxes(saved)
% Puts this PC's default axes back as they were before a test.
if isempty(saved)
    if ispref('zaberstage', 'Axes')
        rmpref('zaberstage', 'Axes');
    end
else
    setpref('zaberstage', 'Axes', saved);
end
end
