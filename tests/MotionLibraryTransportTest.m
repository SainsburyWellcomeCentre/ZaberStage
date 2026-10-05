classdef MotionLibraryTransportTest < matlab.unittest.TestCase
% MotionLibraryTransportTest checks the real transport without a stage: construction, refusals.
%
%   Opens only a port that does not exist (COM250), so no device is touched. Skipped where
%   the Zaber Motion Library is not installed.
%
% See also zaberstage.transport.MotionLibraryTransport

    methods (Test)
        function constructorTouchesNothing(testCase)
            t = zaberstage.transport.MotionLibraryTransport('COM250', 'Direct', true);
            testCase.verifyFalse(t.isOpen());
            testCase.verifyEqual(t.Description, 'COM250');
            testCase.verifyError(@() t.listDevices(), ...
                'zaberstage:MotionLibraryTransport:notOpen');
            t.close();   % never throws, even unopened
        end

        function aMissingPortIsReportedClearly(testCase)
            testCase.assumeNotEmpty(which('zaber.motion.ascii.Connection'), ...
                'Zaber Motion Library not installed');
            t = zaberstage.transport.MotionLibraryTransport('COM250', 'Direct', true);
            testCase.verifyError(@() t.open(), 'zaberstage:MotionLibraryTransport:openFailed');
            testCase.verifyFalse(t.isOpen());
        end

        function aStageOnAMissingPortStaysDisconnected(testCase)
            testCase.assumeNotEmpty(which('zaber.motion.ascii.Connection'), ...
                'Zaber Motion Library not installed');
            stage = zaberstage.Stage('Port', 'COM250');
            testCase.verifyError(@() stage.connect(), ...
                'zaberstage:MotionLibraryTransport:openFailed');
            testCase.verifyEqual(stage.State, 'Disconnected');
        end
    end
end
