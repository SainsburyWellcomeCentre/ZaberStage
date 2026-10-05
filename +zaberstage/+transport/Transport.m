classdef (Abstract) Transport < handle
% zaberstage.transport.Transport is the link between zaberstage.Stage and Zaber controllers.
%
%   A transport opens one serial port, lists the Zaber devices on its daisy chain, and moves
%   and reads one axis at a time, in micrometres. zaberstage.Stage adds limits, states, the
%   log and the record on top; a transport only does what it is told.
%
%   Subclasses implement:
%       open()                                 open the port; errors if it cannot
%       close()                                close the port; never throws
%       tf = isOpen()
%       devices = listDevices()                struct array: Address, Name, SerialNumber,
%                                              AxisCount (detects the chain)
%       info = axisInfo(device, axisNumber)          struct: Name (peripheral), LimitsUm [min max],
%                                              IsHomed
%       home(device, axisNumber, wait)
%       moveAbsolute(device, axisNumber, um, wait)
%       moveRelative(device, axisNumber, um, wait)
%       stop(device, axisNumber)                     decelerate to rest
%       um = positionUm(device, axisNumber)
%       tf = isBusy(device, axisNumber)
%       waitUntilIdle(device, axisNumber)
%
%   device is the 1-based address on the chain, axisNumber the 1-based axis on that device.
%
%   Description (read-only)  where the transport goes, e.g. 'COM14', for records.
%
% See also zaberstage.transport.MotionLibraryTransport, zaberstage.transport.SimulatedTransport,
%          zaberstage.Stage

    properties (Abstract, SetAccess = protected)
        Description  % where the transport goes, for records
    end

    methods (Abstract)
        open(obj)
        close(obj)
        tf = isOpen(obj)
        devices = listDevices(obj)
        info = axisInfo(obj, device, axisNumber)
        home(obj, device, axisNumber, wait)
        moveAbsolute(obj, device, axisNumber, um, wait)
        moveRelative(obj, device, axisNumber, um, wait)
        stop(obj, device, axisNumber)
        um = positionUm(obj, device, axisNumber)
        tf = isBusy(obj, device, axisNumber)
        waitUntilIdle(obj, device, axisNumber)
    end
end
