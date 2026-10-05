classdef ExamplesTest < matlab.unittest.TestCase
% ExamplesTest runs the files in examples/ end to end on the simulated stage.
%
%   The examples default to the simulated transport, so this never touches hardware. It
%   also keeps the examples from drifting away from the API.
%
% See also zaberstage.Stage

    properties
        ExamplesDir
    end

    methods (TestMethodSetup)
        function addExamplesToPath(testCase)
            testCase.ExamplesDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'examples');
            previous = path();
            testCase.addTeardown(@() path(previous));
            addpath(testCase.ExamplesDir);
        end
    end

    methods (Test)
        function basicScriptRuns(testCase)
            run(fullfile(testCase.ExamplesDir, 'example_basic.m'));
            testCase.verifyEqual(session.LimitsUm, [20000 40000]);
            testCase.verifyTrue(session.IsHomed);
            testCase.verifyEqual(stage.State, 'Disconnected');
        end

        function scanVisitsEveryPosition(testCase)
            [positions, values] = example_scan();
            testCase.verifyEqual(positions, 29790 + (-500:100:500));
            testCase.verifySize(values, size(positions));
        end
    end
end
