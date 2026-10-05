classdef SimulatedTransportTest < matlab.unittest.TestCase
% SimulatedTransportTest checks that the simulated stage behaves as docs/zaber-motion.md says.
%
% See also zaberstage.transport.SimulatedTransport

    properties
        Transport
    end

    methods (TestMethodSetup)
        function openTransport(testCase)
            testCase.Transport = zaberstage.transport.SimulatedTransport();
            testCase.Transport.open();
        end
    end

    methods (Test)
        function listsItsChain(testCase)
            devices = testCase.Transport.listDevices();
            testCase.verifyEqual(devices.Address, 1);
            testCase.verifyEqual(devices.AxisCount, 1);
        end

        function startsUnhomedAndRefusesMoves(testCase)
            t = testCase.Transport;
            info = t.axisInfo(1, 1);
            testCase.verifyFalse(info.IsHomed);
            testCase.verifyError(@() t.moveAbsolute(1, 1, 10, true), ...
                'zaberstage:SimulatedTransport:notHomed');
        end

        function homingGoesToTheMinimum(testCase)
            t = zaberstage.transport.SimulatedTransport('LimitsUm', [5 100]);
            t.open();
            t.home(1, 1, true);
            testCase.verifyEqual(t.positionUm(1, 1), 5);
            testCase.verifyTrue(t.axisInfo(1, 1).IsHomed);
        end

        function targetsBeyondTheTravelAreRejected(testCase)
            t = testCase.Transport;
            t.home(1, 1, true);
            testCase.verifyError(@() t.moveAbsolute(1, 1, 50001, true), ...
                'zaberstage:SimulatedTransport:outOfRange');
            testCase.verifyError(@() t.moveRelative(1, 1, -1, true), ...
                'zaberstage:SimulatedTransport:outOfRange');
            testCase.verifyEqual(t.positionUm(1, 1), 0);
        end

        function unknownAxesAreRejected(testCase)
            testCase.verifyError(@() testCase.Transport.positionUm(1, 2), ...
                'zaberstage:SimulatedTransport:noDevice');
            testCase.verifyError(@() testCase.Transport.positionUm(2, 1), ...
                'zaberstage:SimulatedTransport:noDevice');
        end

        function aTimedMoveProgresses(testCase)
            t = zaberstage.transport.SimulatedTransport('SpeedUmPerS', 2000, 'StartHomed', true);
            t.open();
            t.moveAbsolute(1, 1, 100, false);   % 50 ms
            testCase.verifyTrue(t.isBusy(1, 1));
            pause(0.1);
            testCase.verifyFalse(t.isBusy(1, 1));
            testCase.verifyEqual(t.positionUm(1, 1), 100);
        end

        function faultsAreInjected(testCase)
            t = testCase.Transport;
            t.failNext('home', 'zaber:test:x');
            testCase.verifyError(@() t.home(1, 1, true), 'zaber:test:x');
            testCase.verifyFalse(t.axisInfo(1, 1).IsHomed);
            t.home(1, 1, true);
            t.unplug();
            testCase.verifyError(@() t.positionUm(1, 1), 'zaberstage:SimulatedTransport:unplugged');
        end

        function callsAreRecordedAndAClosedPortRefuses(testCase)
            t = testCase.Transport;
            t.home(1, 1, true);
            testCase.verifyNumElements(t.callsOf('home'), 1);
            t.clearCalls();
            testCase.verifyEmpty(t.Calls);
            t.close();
            testCase.verifyError(@() t.positionUm(1, 1), 'zaberstage:SimulatedTransport:notOpen');
        end
    end
end
