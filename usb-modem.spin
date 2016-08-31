{{

usb-modem
------------------------------------------------------------------

Driver for USB Modems which use the Communication Device Class (CDC)

The CDC is a really complex spec, but this driver supports only
the generic data endpoints, which provide a serial-port-like
interface to the modem.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.

}}

OBJ
  hc : "usb-fs-host"

CON
  ' Negative error codes. Most functions in this library can call
  ' "abort" with one of these codes. The range from -100 to -150 is
  ' reserved for device drivers. (See usb-fs-host.spin)

  E_SUCCESS       = 0
  E_NOT_CDC       = -100        ' Device is not CDC class
  E_NO_INTERFACE  = -101        ' No CDC Data interface found
  E_NO_ENDPOINT   = -102        ' Couldn't find both an IN and OUT endpoint

  ' CDC Class constants

  CDC_CLASS       = 2
  CDC_CONTROL_IF  = 2
  CDC_DATA_IF     = 10

  RX_BUFFER_SIZE  = 64

DAT

bulkIn                  word    0
bulkOut                 word    0

rxHead                  byte    0  ' Index of first byte
rxCount                 byte    0  ' Number of buffered bytes
rxBuffer                byte    0[RX_BUFFER_SIZE]

DAT
''
''
''==============================================================================
'' Device Driver Interface
''==============================================================================

PUB Enumerate
  '' Enumerate the available USB devices. This is provided for the convenience
  '' of applications that use no other USB class drivers, so they don't have to
  '' directly import the host controller object as well.

  return hc.Enumerate

PUB Identify

  '' The caller must have already successfully enumerated a USB device.
  '' This function tests whether the device looks like it's compatible
  '' with this driver.
  ''
  '' This function is meant to be non-invasive: it doesn't do any setup,
  '' nor does it try to communicate with the device. If your application
  '' needs to be compatible with several USB device classes, you can call
  '' Identify on multiple drivers before committing to using any one of them.
  ''
  '' Returns 1 if the device is supported, 0 if not. Does not abort.

  return BYTE[hc.DeviceDescriptor + hc#DEVDESC_bDeviceClass] == CDC_CLASS and hc.FindInterface(CDC_DATA_IF) <> 0

PUB Init | epd

  '' (Re)initialize this driver. This must be called after Enumerate
  '' and Identify are both run successfully. All three functions must be
  '' called again if the device disconnects and reconnects, or if it is
  '' power-cycled.

  if BYTE[hc.DeviceDescriptor + hc#DEVDESC_bDeviceClass] <> CDC_CLASS
    abort E_NOT_CDC

  epd := hc.FindInterface(CDC_DATA_IF)
  if not epd
    abort E_NO_INTERFACE

  ' Locate the device's bulk IN/OUT endpoints

  bulkIn~
  bulkOut~

  repeat while epd := hc.NextEndpoint(epd)
    if hc.EndpointType(epd) == hc#TT_BULK
      if hc.EndpointDirection(epd) == hc#DIR_IN
        bulkIn := epd
      else
        bulkOut := epd

  if not (bulkIn and bulkOut)
    abort E_NO_ENDPOINT

  hc.Configure

  ' Clear the receive buffer
  rxHead~
  rxCount~

DAT
''
''==============================================================================
'' Serial port-like CDC Data interface
''============================================================================

PUB Send(buffer, bytes)
  '' Transmit a block of bytes to the modem.
  '' Aborts on error.

  hc.BulkWrite(bulkOut, buffer, bytes)

PUB Receive(buffer, bufferSize) : actual | packet
  '' Receive up to 'bufferSize' bytes, or whatever is currently
  '' available on the device's buffer. Returns the actual number of
  '' bytes we received.

  repeat while bufferSize

    if rxCount
      ' Move data from rxData to caller
      packet := rxCount <# (RX_BUFFER_SIZE - rxHead) <# bufferSize
      bytemove(buffer, @rxBuffer + rxHead, packet)
      buffer += packet
      actual += packet
      bufferSize -= packet
      rxHead += packet
      rxCount -= packet

    else
      ' Buffer is empty. Try to fill it.
      ' Note that this is actually a Bulk IN endpoint, but we're
      ' using it more like interrupt (one packet at a time, no retry on NAK.)

      packet := \hc.InterruptRead(bulkIn, @rxBuffer, RX_BUFFER_SIZE)
      if packet == hc#E_TIMEOUT
        return
      elseif packet < 0
        ' Oh no, data loss :(
        abort packet
      elseif packet =< 2
        ' Packet has no payload (device is out of data)
        return
      else
        ' Buffer is now non-empty
        rxCount := packet - 2
        rxHead~

DAT
{{

TERMS OF USE: MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

}}