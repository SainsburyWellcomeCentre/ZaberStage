classdef StageTest < matlab.unittest.TestCase
% StageTest checks zaberstage.Stage's connection, moves, limits, errors and records.
%
%   Runs on zaberstage.transport.SimulatedTransport only; no hardware is touched.
%
% See also zaberstage.Stage, zaberstage.transport.SimulatedTransport

    properties
        Transport
        Stage
    end

    methods (TestMethodSetup)
        function makeStage(testCase)
            testCase.Transport = zaberstage.transport.SimulatedTransport();
            testCase.Stage = zaberstage.Stage('Transport', testCase.Transport);
            testCase.addTeardown(@() delete(testCase.Stage));
        end
    end

    methods (Test)
        %% Connection

        function constructorTouchesNothing(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.Stage.State, 'Disconnected');
        end

        function connectReadsIdentityAndLimitsAndMovesNothing(testCase)
            testCase.Stage.connect();
            stage = testCase.Stage;
            testCase.verifyEqual(stage.State, 'Ready');
            testCase.verifyEqual(stage.Identity.DeviceName, 'X-LSM050A');
            testCase.verifyEqual(stage.Identity.SerialNumber, 12345);
            testCase.verifyEqual(stage.DeviceLimitsUm, [0 50000]);
            testCase.verifyEqual(stage.LimitsUm, [0 50000]);
            testCase.verifyFalse(stage.IsHomed);
            commands = {testCase.Transport.Calls.Command};
            testCase.verifyEmpty(intersect(commands, {'home', 'moveAbsolute', ...
                'moveRelative'}));
        end

        function aMissingDeviceOrAxisIsNamed(testCase)
            stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'AxisNumber', 2);
            testCase.verifyError(@() stage.connect(), 'zaberstage:Stage:noDevice');
            testCase.verifyEqual(stage.State, 'Disconnected');
            testCase.verifyFalse(stage.Transport.isOpen());
            stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'DeviceAddress', 3);
            testCase.verifyError(@() stage.connect(), 'zaberstage:Stage:noDevice');
        end

        function connectWithNoPortSaysHowToGiveOne(testCase)
            stage = zaberstage.Stage('Port', '');
            testCase.verifyError(@() stage.connect(), 'zaberstage:Stage:noPort');
        end

        function limitsSetBeforeConnectMustFitTheTravel(testCase)
            stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'LimitsUm', [10000 60000]);
            testCase.verifyError(@() stage.connect(), 'zaberstage:Stage:limitsOutsideDevice');
            stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'LimitsUm', [10000 20000]);
            stage.connect();
            testCase.verifyEqual(stage.LimitsUm, [10000 20000]);
        end

        function addressCannotChangeWhileConnected(testCase)
            testCase.Stage.connect();
            for name = {'Port', 'BaudRate', 'DeviceAddress', 'AxisNumber', 'Reversed', ...
                    'SafeLimitsUm'}
                testCase.verifyError(@() setProperty(testCase.Stage, name{1}, 2), ...
                    'zaberstage:Stage:portLocked');
            end
        end

        function disconnectStopsAndCloses(testCase)
            testCase.Stage.connect();
            testCase.Stage.disconnect();
            testCase.verifyNotEmpty(testCase.Transport.callsOf('stop'));
            testCase.verifyFalse(testCase.Transport.isOpen());
            testCase.Stage.disconnect();   % idempotent
        end

        function axesSharingATransportLeaveItOpen(testCase)
            t = zaberstage.transport.SimulatedTransport('StartHomed', true, 'Devices', ...
                struct('Address', 1, 'Name', 'X-MCC3', 'SerialNumber', 1, 'AxisCount', 2));
            x = zaberstage.Stage('Transport', t, 'AxisNumber', 1, 'SharedTransport', true);
            y = zaberstage.Stage('Transport', t, 'AxisNumber', 2, 'SharedTransport', true);
            testCase.addTeardown(@() t.close());
            x.connect();
            y.connect();
            x.disconnect();
            testCase.verifyTrue(t.isOpen());
            testCase.verifyEqual(x.State, 'Disconnected');
            y.moveAbsolute(1000);
            testCase.verifyEqual(y.positionUm(), 1000);
            bad = zaberstage.Stage('Transport', t, 'AxisNumber', 3, 'SharedTransport', true);
            testCase.verifyError(@() bad.connect(), 'zaberstage:Stage:noDevice');
            testCase.verifyTrue(t.isOpen());   % a failed connect leaves it too
            y.disconnect();
            testCase.verifyTrue(t.isOpen());
        end

        %% Moves

        function homeThenMove(testCase)
            testCase.Stage.connect();
            testCase.Stage.home();
            testCase.verifyTrue(testCase.Stage.IsHomed);
            testCase.verifyEqual(testCase.Stage.positionUm(), 0);
            testCase.Stage.moveAbsolute(29790);
            testCase.verifyEqual(testCase.Stage.positionUm(), 29790);
            testCase.Stage.moveRelative(-50.5);
            testCase.verifyEqual(testCase.Stage.positionUm(), 29739.5, 'AbsTol', 1e-9);
        end

        function aReversedAxisCountsTheOtherWay(testCase)
            stage = zaberstage.Stage('Transport', testCase.Transport, 'Reversed', true, ...
                'LimitsUm', [20000 40000]);
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            stage.home();
            testCase.verifyEqual(stage.positionUm(), 50000);   % home is the top of the travel
            testCase.verifyEqual(stage.DeviceLimitsUm, [0 50000]);
            stage.moveAbsolute(29790);
            testCase.verifyEqual(testCase.Transport.PositionsUm('1.1'), 20210);
            testCase.verifyEqual(stage.positionUm(), 29790);
            stage.moveRelative(50);   % towards home on the controller
            testCase.verifyEqual(testCase.Transport.PositionsUm('1.1'), 20160);
            testCase.verifyEqual(stage.positionUm(), 29840);
            testCase.verifyError(@() stage.moveRelative(10200), ...
                'zaberstage:Stage:outsideLimits');   % checked in the reversed coordinates
            log = stage.log();
            testCase.verifyEqual(log.Value(strcmp(log.Command, 'moveAbsolute')), 29790);
            testCase.verifyTrue(stage.record().Reversed);
            testCase.verifyError(@() zaberstage.Stage('Reversed', 'yes'), ...
                'zaberstage:Stage:badValue');
        end

        function safeLimitsCannotBeWidenedOrLeft(testCase)
            stage = zaberstage.Stage('Transport', testCase.Transport, 'SafeLimitsUm', ...
                [10000 40000]);
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            testCase.verifyEqual(stage.LimitsUm, [10000 40000]);   % the default
            testCase.verifyError(@() stage.home(), 'zaberstage:Stage:homeOutsideSafe');
            testCase.verifyEmpty(testCase.Transport.callsOf('home'));
            testCase.verifyError(@() setProperty(stage, 'LimitsUm', [5000 20000]), ...
                'zaberstage:Stage:limitsOutsideSafe');
            stage.LimitsUm = [20000 30000];   % narrowing is fine
            testCase.verifyEqual(stage.LimitsUm, [20000 30000]);
            testCase.verifyEqual(stage.record().SafeLimitsUm, [10000 40000]);
            stage.disconnect();
            stage.SafeLimitsUm = [25000 40000];   % narrower than LimitsUm: they reset to it
            stage.connect();
            testCase.verifyEqual(stage.LimitsUm, [25000 40000]);
            testCase.verifyError(@() zaberstage.Stage('SafeLimitsUm', [2 1]), ...
                'zaberstage:Stage:badValue');
            wide = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'SafeLimitsUm', [0 60000]);
            wide.connect();
            testCase.verifyEqual(wide.LimitsUm, [0 50000]);   % the travel is the tighter end
            wide.disconnect();
            outside = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'SafeLimitsUm', [60000 70000]);
            testCase.verifyError(@() outside.connect(), 'zaberstage:Stage:limitsOutsideDevice');
        end

        function aSafeRangeCanBeOpenAtOneEnd(testCase)
            stage = zaberstage.Stage('Transport', testCase.Transport, 'SafeLimitsUm', ...
                [35000 Inf]);
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            testCase.verifyEqual(stage.LimitsUm, [35000 50000]);
            testCase.verifyError(@() setProperty(stage, 'LimitsUm', [30000 50000]), ...
                'zaberstage:Stage:limitsOutsideSafe');
            testCase.verifyError(@() stage.home(), 'zaberstage:Stage:homeOutsideSafe');
            open = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'SafeLimitsUm', [-Inf 30000]);
            testCase.addTeardown(@() delete(open));
            open.connect();
            testCase.verifyEqual(open.LimitsUm, [0 30000]);
            open.home();   % the home end, 0, is safe
            testCase.verifyError(@() open.moveAbsolute(30001), 'zaberstage:Stage:outsideLimits');
            for bad = {[NaN 1], [Inf Inf], [-Inf -Inf]}
                testCase.verifyError(@() zaberstage.Stage('SafeLimitsUm', bad{1}), ...
                    'zaberstage:Stage:badValue');
            end
        end

        function aSafeHomeEndCanBeHomed(testCase)
            stage = zaberstage.Stage('Transport', testCase.Transport, 'SafeLimitsUm', [0 40000]);
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            stage.home();
            testCase.verifyEqual(stage.positionUm(), 0);
            testCase.verifyError(@() stage.moveAbsolute(45000), 'zaberstage:Stage:outsideLimits');
            reversed = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport(), ...
                'Reversed', true, 'SafeLimitsUm', [0 40000]);   % home reads 50000
            testCase.addTeardown(@() delete(reversed));
            reversed.connect();
            testCase.verifyError(@() reversed.home(), 'zaberstage:Stage:homeOutsideSafe');
        end

        function anUnhomedAxisRefusesToMove(testCase)
            testCase.Stage.connect();
            testCase.verifyError(@() testCase.Stage.moveAbsolute(100), ...
                'zaberstage:SimulatedTransport:notHomed');
            entries = testCase.Stage.log();
            testCase.verifyFalse(entries.Ok(end));
            testCase.verifySubstring(entries.Message{end}, 'not homed');
        end

        function movesOutsideTheLimitsAreRefusedAndNotSent(testCase)
            testCase.Stage.connect();
            testCase.Stage.home();
            testCase.Stage.LimitsUm = [20000 40000];
            testCase.Stage.moveAbsolute(30000);
            testCase.Transport.clearCalls();
            testCase.verifyError(@() testCase.Stage.moveAbsolute(40000.1), ...
                'zaberstage:Stage:outsideLimits');
            testCase.verifyError(@() testCase.Stage.moveRelative(-10001), ...
                'zaberstage:Stage:outsideLimits');
            testCase.verifyEmpty(testCase.Transport.callsOf('moveAbsolute'));
            testCase.verifyEmpty(testCase.Transport.callsOf('moveRelative'));
            testCase.Stage.moveRelative(10000);
            testCase.verifyEqual(testCase.Stage.positionUm(), 40000);
        end

        function limitsMustBeOrderedAndWithinTheTravel(testCase)
            testCase.Stage.connect();
            testCase.verifyError(@() setProperty(testCase.Stage, 'LimitsUm', [-1 100]), ...
                'zaberstage:Stage:limitsOutsideDevice');
            testCase.verifyError(@() setProperty(testCase.Stage, 'LimitsUm', [100 100]), ...
                'zaberstage:Stage:badValue');
            testCase.verifyError(@() setProperty(testCase.Stage, 'LimitsUm', 5), ...
                'zaberstage:Stage:badValue');
        end

        function badPositionsAreRefused(testCase)
            testCase.Stage.connect();
            for value = {NaN, Inf, [1 2], 'ten'}
                testCase.verifyError(@() testCase.Stage.moveAbsolute(value{1}), ...
                    'zaberstage:Stage:badValue');
            end
            testCase.verifyError(@() testCase.Stage.moveAbsolute(1, 'Fast', true), ...
                'zaberstage:Stage:invalidOption');
        end

        function aMoveWithoutWaitingCanBeStopped(testCase)
            transport = zaberstage.transport.SimulatedTransport('SpeedUmPerS', 1000, ...
                'StartHomed', true);
            stage = zaberstage.Stage('Transport', transport);
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            stage.moveAbsolute(10000, 'Wait', false);   % 10 s at 1 mm/s
            testCase.verifyTrue(stage.isMoving());
            pause(0.05);
            testCase.verifyTrue(stage.stop());
            testCase.verifyFalse(stage.isMoving());
            position = stage.positionUm();
            testCase.verifyGreaterThan(position, 0);
            testCase.verifyLessThan(position, 10000);
        end

        function waitUntilIdleFinishesTheMove(testCase)
            transport = zaberstage.transport.SimulatedTransport('SpeedUmPerS', 1000, ...
                'StartHomed', true);
            stage = zaberstage.Stage('Transport', transport);
            testCase.addTeardown(@() delete(stage));
            stage.connect();
            stage.moveAbsolute(500, 'Wait', false);
            stage.waitUntilIdle();
            testCase.verifyEqual(stage.positionUm(), 500);
        end

        function commandsNeedAConnection(testCase)
            testCase.verifyError(@() testCase.Stage.home(), 'zaberstage:Stage:notReady');
            testCase.verifyError(@() testCase.Stage.moveAbsolute(1), 'zaberstage:Stage:notReady');
            testCase.verifyError(@() testCase.Stage.positionUm(), 'zaberstage:Stage:notReady');
        end

        %% Faults

        function stopNeverThrows(testCase)
            testCase.verifyFalse(testCase.Stage.stop());   % never connected
            testCase.Stage.connect();
            testCase.Transport.unplug();
            testCase.verifyFalse(testCase.Stage.stop());
            testCase.Stage.disconnect();
            testCase.verifyEqual(testCase.Stage.State, 'Disconnected');
        end

        function libraryErrorsPassThroughAndAreLogged(testCase)
            testCase.Stage.connect();
            testCase.Stage.home();
            testCase.Transport.failNext('moveAbsolute', 'zaber:test:stalled');
            testCase.verifyError(@() testCase.Stage.moveAbsolute(100), 'zaber:test:stalled');
            testCase.verifyEqual(testCase.Stage.State, 'Ready');
            entries = testCase.Stage.log();
            testCase.verifyEqual(entries.Command{end}, 'moveAbsolute');
            testCase.verifyFalse(entries.Ok(end));
        end

        %% Events and records

        function eventsFire(testCase)
            seen = {};
            l1 = addlistener(testCase.Stage, 'StateChanged', @(~, ~) note('state'));
            l2 = addlistener(testCase.Stage, 'MoveCompleted', @(~, ~) note('move'));
            cleanup = onCleanup(@() delete([l1 l2]));
            testCase.Stage.connect();
            testCase.Stage.home();
            testCase.verifyEqual(seen, {'state', 'move'});
            clear cleanup
            function note(what)
                seen{end + 1} = what;
            end
        end

        function recordIsPlainData(testCase)
            testCase.Stage.connect();
            testCase.Stage.home();
            testCase.Stage.moveAbsolute(1000);
            s = testCase.Stage.record();
            testCase.verifyEqual(s.Package, 'zaberstage');
            testCase.verifyEqual(s.Version, zaberstage.version());
            testCase.verifyEqual(s.LimitsUm, [0 50000]);
            testCase.verifyEqual(s.Connection, 'simulated Zaber');
            testCase.verifyTrue(ischar(s.Log(1).Time));
            testCase.verifyFalse(any(structfun(@isobject, s)));
            moves = s.Log(strcmp({s.Log.Command}, 'moveAbsolute'));
            testCase.verifyEqual(moves(end).Value, 1000);
        end

        function logKeepsOnlyItsCapacity(testCase)
            testCase.Stage.LogCapacity = 4;
            testCase.Stage.connect();
            testCase.Stage.home();
            for k = 1:10
                testCase.Stage.moveAbsolute(k);
            end
            entries = testCase.Stage.log();
            testCase.verifyEqual(height(entries), 4);
            testCase.verifyEqual(entries.Value(end), 10);
        end

        function unknownOptionsAreRefused(testCase)
            testCase.verifyError(@() zaberstage.Stage('Speed', 3), ...
                'zaberstage:Stage:invalidOption');
        end
    end
end


function setProperty(object, name, value)
% Sets a property, for verifyError.
object.(name) = value;
end
