{{

 usb-ft232  ver 1.0
──────────────────────────────────────────────────────────────────

FTDI FT232 USB Serial Port driver for the Parallax Propeller.

This is a USB device driver that allows you to send and receive
serial data via an external FT232 device attached to the usb-fs-host
software USB host controller.

For example, you could use this driver to connect the USB end of
a Prop Plug to a Propeller, and use it to talk to other devices. Not
terribly practical, since this is slower and more resource intensive
than FullDuplexSerial.. but you can also use this to talk to an
off-the-shelf device which includes an FT232 USB interface but no
TTL-level serial port.

My understanding of the FT232 protocol is based on the source to
the Linux ftdi_sio kernel module, by Greg K-H and Bill Ryder.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

 ┌───────────────────────────────────────────────────────────┐
 │ Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org> │
 │ See end of file for terms of use.                         │
 └───────────────────────────────────────────────────────────┘

}}

OBJ
  hc : "usb-fs-host"

CON
  ' Negative error codes. Most functions in this library can call
  ' "abort" with one of these codes. The range from -100 to -150 is
  ' reserved for device drivers. (See usb-fs-host.spin)

  E_SUCCESS       = 0

  ' FTDI device constants.

  FTDI_VID        = $0403
  RX_PACKET_SIZE  = 64

  ' Control requests

  REQ_RESET             = $0040
  REQ_MODEM_CTRL        = $0140
  REQ_SET_FLOW_CTRL     = $0240
  REQ_SET_BAUD_RATE     = $0340
  REQ_SET_DATA          = $0440
  REQ_GET_MODEM_STATUS  = $05c0
  REQ_SET_EVENT_CHAR    = $0640
  REQ_SET_ERROR_CHAR    = $0740
  REQ_SET_LATENCY_TIMER = $0940
  REQ_GET_LATENCY_TIMER = $10c0

DAT

bulkIn                  word    0
bulkOut                 word    0

rxPacket
rxStatus                word    0
rxData                  byte    0[RX_PACKET_SIZE - 2]
rxHead                  byte    0  ' Index of first byte
rxCount                 byte    0  ' Number of buffered bytes

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
  '' Specifically for the FT232 chips, here we'll just look for a vendor
  '' and product ID that matches the defaults provided by FTDI. It's also
  '' possible for FT232 chips to use vendor-specific vendor/product IDs.
  '' If you're using such a device, you can make the identification check
  '' yourself, and skip this function.
  ''
  '' This function is meant to be non-invasive: it doesn't do any setup,
  '' nor does it try to communicate with the device. If your application
  '' needs to be compatible with several USB device classes, you can call
  '' Identify on multiple drivers before committing to using any one of them.
  ''
  '' Returns 1 if the device is supported, 0 if not. Does not abort.

  if hc.VendorID == FTDI_VID
    case hc.ProductID
      $6001, $6006, $6010:
        return 1

  return 0

PUB Init | epd

  '' (Re)initialize this driver. This must be called after Enumerate
  '' and Identify are both run successfully. All three functions must be
  '' called again if the device disconnects and reconnects, or if it is
  '' power-cycled.
  ''
  '' This function sets the device's USB configuration, collects
  '' information about the device's descriptors, and sets default
  '' UART settings.

  bulkIn := hc.NextEndpoint(hc.FirstInterface)
  bulkOut := hc.NextEndpoint(bulkIn)

  rxHead~
  rxCount~
  rxStatus~

  hc.Configure


DAT
''
''==============================================================================
'' Low-level FT232 interface
''============================================================================

PUB SetBaud(baud) | divisor, div8
  '' Change the baud rate to any supported value

  ' This is adapted from ftdi_232bm_baud_base_to_divisor
  ' in the Linux kernel module source.

  div8 := 24_000_000 / baud  ' Divisor * 8
  divisor := (div8 >> 3) | (lookupz(div8&7: 0,3,2,4,1,5,6,7) << 14)

  ' Special cases
  if divisor == 1
    divisor~
  elseif divisor == $4001
    divisor := 1

  hc.Control(REQ_SET_BAUD_RATE, divisor, divisor >> 16)

PUB Send(buffer, bytes)
  '' Transmit a block of bytes to the serial port.
  '' Aborts on error.

  ' Older FTDI devices needed a control byte, but the FT232 does not.
  hc.BulkWrite(bulkOut, buffer, bytes)

PUB Receive(buffer, bufferSize) : actual | packet
  '' Receive up to 'bufferSize' bytes, or whatever is currently
  '' available on the FT232's buffer. Returns the actual number of
  '' bytes we received.

  ' The FTDI chip gives us 64-byte packets, each with a 2-byte
  ' status header. Since the caller may need more or less data,
  ' we end up pumping data from the FTDI chip into a small buffer,
  ' then from that buffer to the caller's buffer.

  repeat while bufferSize

    if rxCount
      ' Move data from rxData to caller
      packet := rxCount <# (RX_PACKET_SIZE - rxHead) <# bufferSize
      bytemove(buffer, @rxData + rxHead, packet)
      buffer += packet
      actual += packet
      bufferSize -= packet
      rxHead += packet
      rxCount -= packet

    else
      ' Buffer is empty. Try to fill it.
      ' Note that this is actually a Bulk IN endpoint, but we're
      ' using it more like interrupt (one packet at a time, no retry on NAK.)

      packet := \hc.InterruptRead(bulkIn, @rxPacket, RX_PACKET_SIZE)
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

{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}