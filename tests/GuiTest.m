classdef GuiTest < matlab.unittest.TestCase
% GuiTest drives zaberstage.gui.StageApp on the simulated stage, with a hidden window.
%
%   Controls are driven as a user would: set a component's Value, then call its callback.
%
% See also zaberstage.gui.StageApp, zaberstage.Stage

    properties
        Transport
        App
    end

    methods (TestMethodSetup)
        function makeApp(testCase)
            testCase.Transport = zaberstage.transport.SimulatedTransport();
            testCase.App = zaberstage.gui.StageApp('Transport', testCase.Transport, ...
                'Visible', false, 'AutoRefresh', false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods (Test)
        function opensWithoutTouchingTheStage(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Connect');
            testCase.verifyEqual(testCase.App.Controls.Go.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
        end

        function connectShowsIdentityAndPosition(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyEqual(testCase.App.Stage.State, 'Ready');
            testCase.verifySubstring(testCase.App.Controls.Identity.Text, 'NOT HOMED');
            testCase.verifyEqual(testCase.App.Controls.Position.Text, '0.00');
            testCase.verifyEqual(testCase.App.Controls.Max.Value, 50000);
        end

        function homeGoAndJogMove(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Home);
            testCase.verifySubstring(testCase.App.Controls.Identity.Text, 'homed');
            testCase.App.Controls.Target.Value = 1000;
            testCase.press(testCase.App.Controls.Go);
            testCase.App.Controls.Step.Value = 25;
            testCase.press(testCase.App.Controls.JogPlus);
            testCase.press(testCase.App.Controls.JogPlus);
            testCase.press(testCase.App.Controls.JogMinus);
            testCase.verifyEqual(testCase.App.Stage.positionUm(), 1025);
            testCase.verifyEqual(testCase.App.Controls.Position.Text, '1025.00');
        end

        function aMoveBeyondTheLimitsIsShownNotThrown(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Home);
            testCase.setValue(testCase.App.Controls.Max, 2000);
            testCase.verifyEqual(testCase.App.Stage.LimitsUm, [0 2000]);
            testCase.App.Controls.Target.Value = 3000;
            testCase.press(testCase.App.Controls.Go);
            testCase.verifySubstring(testCase.App.LastError, 'outside LimitsUm');
            testCase.verifyEqual(testCase.App.Stage.positionUm(), 0);
        end

        function aLimitBeyondTheTravelIsShownAndUndone(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.setValue(testCase.App.Controls.Max, 99999);
            testCase.verifySubstring(testCase.App.LastError, 'beyond the axis');
            testCase.verifyEqual(testCase.App.Controls.Max.Value, 50000);
        end

        function stopAndEscapeStop(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.Transport.clearCalls();
            testCase.press(testCase.App.Controls.Stop);
            fig = testCase.App.Figure;
            fig.KeyPressFcn(fig, struct('Key', 'escape'));
            testCase.verifyNumElements(testCase.Transport.callsOf('stop'), 2);
        end

        function closingAnOwnedStageDisconnectsIt(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.close();
            testCase.verifyFalse(testCase.Transport.isOpen());
        end

        function closingAnAttachedWindowLeavesTheStage(testCase)
            stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport());
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            app = zaberstage.gui.StageApp(stage, 'Visible', false, 'AutoRefresh', false);
            app.close();
            testCase.verifyEqual(stage.State, 'Ready');
        end
    end

    methods (Access = private)
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
