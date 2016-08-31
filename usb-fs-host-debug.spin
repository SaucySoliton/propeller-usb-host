{{

 usb-fs-host-debug
──────────────────────────────────────────────────────────────────

Debugging wrapper for usb-fs-host, aka the Poor Man's USB Analyzer.

Logs every function call and every USB transfer to Parallax Serial
Terminal, including hex dumps of all incoming and outgoing buffers.

Usage:
  In the module(s) you want to debug, temporarily replace the
  "usb-fs-host" OBJ reference with "usb-fs-host-debug".

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

 ┌───────────────────────────────────────────────────────────┐
 │ Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org> │               
 │ See end of file for terms of use.                         │
 └───────────────────────────────────────────────────────────┘

}}

OBJ
  hc : "usb-fs-host"
  term : "Parallax Serial Terminal"

CON
  ' Verbosity options

  SHOW_FRAME_WAIT = 0           ' Show every FrameWait
  SHOW_INTR_TIMEOUT = 0         ' Show Interrupt Read timeouts

  ' Serial port

  BAUD_RATE = 1000000

  ' Column positions

  POS_TAG       = 10
  POS_ENDTAG    = POS_TAG + 10
  POS_HEXDUMP   = POS_TAG + 2
  POS_ASCII     = POS_HEXDUMP + 7 + 16*3
  POS_END       = POS_ASCII + 16
  DIVIDER_WIDTH = POS_END - (POS_ENDTAG + 2) 
  
DAT

epoch          long  0
epochSec       long  0
hideFrameWait  byte  0

PRI logBegin(name) | timediff
  hideFrameWait~                     ' Only hide consecutive FrameWaits.

  term.char(term#NL)
  logTimestamp
  term.positionX(POS_TAG)
  term.char("[")
  term.str(name)
  term.positionX(POS_ENDTAG)
  term.str(string("] "))

PRI logStatus(code)
  term.str(string(" -> "))
  term.dec(result := code)
  if result < 0
    abort

PRI logComma
  term.str(string(", "))

PRI logTimestamp | now
  ' Log a timestamp, in seconds and milliseconds.

  ' To avoid rollover, eat full seconds by incrementing epochSec and moving epoch forward.
  now := cnt
  repeat while ((now - epoch) => 96_000_000) or ((now - epoch) < 0)
    epoch += 96_000_000
    epochSec++

  term.dec(epochSec)
  term.char(".")
  dec3((now - epoch) / 96_000)

PRI dec3(n)
  ' 3-digit unsigned decimal number, with leading zeroes
  term.char("0" + ((n / 100) // 10))
  term.char("0" + ((n / 10) // 10))
  term.char("0" + (n // 10))

PUB FrameWait(f)
  if SHOW_FRAME_WAIT or not hideFrameWait
    logBegin(string("FrameWait"))
    repeat DIVIDER_WIDTH
      term.char("-")
  hc.FrameWait(f)
  hideFrameWait~~

PUB Enumerate
  epoch := cnt
  epochSec~

  ' Use StartRxTx instead of Start, since we don't want the 1-second delay.
  term.StartRxTx(31, 30, 0, BAUD_RATE)
  term.clear
  
  logBegin(string("Enumerate"))
  logStatus(\hc.Enumerate)

PUB Configure
  logBegin(string("Configure"))
  logStatus(\hc.Configure)

PUB ClearHalt(epd)
  logBegin(string("ClearHalt"))
  term.hex(epd,2)
  logStatus(\hc.ClearHalt(epd))

PUB DeviceReset
  logBegin(string("DevReset"))
  logStatus(\hc.DeviceReset)

PUB DeviceAddress
  logBegin(string("DevAddr"))
  logStatus(\hc.DeviceAddress)

PUB Control(req, value, index)
  logBegin(string("Control"))
  term.hex(req, 4)
  logComma
  term.hex(value, 4)
  term.char("-")
  term.hex(index, 4)
  logStatus(\hc.Control(req, value, index))

PUB ControlRead(req, value, index, bufferPtr, length)
  logBegin(string("ControlRd"))
  term.hex(req, 4)
  logComma
  term.hex(value, 4)
  term.char("-")
  term.hex(index, 4)
  logComma
  term.hex(length, 4)

  result := logStatus(\hc.ControlRead(req, value, index, bufferPtr, length))
  hexDump(bufferPtr, length)

PUB ControlWrite(req, value, index, bufferPtr, length)
  logBegin(string("ControlWr"))
  term.hex(req, 4)
  logComma
  term.hex(value, 4)
  term.char("-")
  term.hex(index, 4)
  logComma
  term.hex(length, 4)

  result := \logStatus(\hc.ControlWrite(req, value, index, bufferPtr, length))
  hexDump(bufferPtr, length)
  if result < 0
    abort

PUB InterruptRead(epd, buffer, length) : actual
  result := \hc.InterruptRead(epd, buffer, length)

  if result <> E_TIMEOUT or SHOW_INTR_TIMEOUT
    logBegin(string("Intr   Rd"))
    term.hex(epd, 4)
    logComma
    term.hex(buffer, 4)
    logComma
    term.hex(length, 4)
    logStatus(result)

  if result < 0
    abort
  hexDump(buffer, result)

PUB BulkWrite(epd, buffer, length)
  logBegin(string("Bulk   Wr"))
  term.hex(epd, 4)
  logComma
  term.hex(buffer, 4)
  logComma
  term.hex(length, 4)

  result := \logStatus(\hc.BulkWrite(epd, buffer, length))
  hexDump(buffer, length)
  if result < 0
    abort
     
PUB BulkRead(epd, buffer, length) : actual
  logBegin(string("Bulk   Rd"))
  term.hex(epd, 4)
  logComma
  term.hex(buffer, 4)
  logComma
  term.hex(length, 4)

  result := logStatus(\hc.BulkRead(epd, buffer, length))
  hexDump(buffer, result)

PUB DeviceDescriptor
  return hc.DeviceDescriptor
PUB ConfigDescriptor
  return hc.ConfigDescriptor
PUB VendorID
  return hc.VendorID  
PUB ProductID
  return hc.ProductID
PUB NextDescriptor(ptrIn)
  return hc.NextDescriptor(ptrIn)
PUB NextHeaderMatch(ptrIn, header)
  return hc.NextHeaderMatch(ptrIn, header)
PUB FirstInterface
  return hc.FirstInterface
PUB NextInterface(curIf)
  return hc.NextInterface(curIf)
PUB NextEndpoint(curIf)
  return hc.NextEndpoint(curIf)
PUB FindInterface(class)
  return hc.FindInterface(class)
PUB EndpointDirection(epd)
  return hc.EndpointDirection(epd)
PUB EndpointType(epd)
  return hc.EndpointType(epd)
PUB UWORD(addr)
  return hc.UWORD(addr)

PRI hexDump(buffer, bytes) | addr, x, b, lastCol
  ' A basic 16-byte-wide hex/ascii dump

  addr~

  repeat while bytes > 0
    term.char(term#NL)
    term.positionX(POS_HEXDUMP)
    term.hex(addr, 4)
    term.str(string(": "))

    lastCol := (bytes <# 16) - 1

    repeat x from 0 to lastCol
      term.hex(BYTE[buffer + x], 2)
      term.char(" ")

    term.positionX(POS_ASCII)

    repeat x from 0 to lastCol
      b := BYTE[buffer + x]
      case b
        32..126:
          term.char(b)
        other:
          term.char(".")

    addr += 16
    buffer += 16
    bytes -= 16


CON

  ' Port connection status codes
  PORTC_NO_DEVICE  = hc#PORTC_NO_DEVICE
  PORTC_FULL_SPEED = hc#PORTC_FULL_SPEED
  PORTC_LOW_SPEED  = hc#PORTC_LOW_SPEED
  
  ' Standard device requests.

  REQ_CLEAR_DEVICE_FEATURE     = $0100
  REQ_CLEAR_INTERFACE_FEATURE  = $0101
  REQ_CLEAR_ENDPOINT_FEATURE   = $0102
  REQ_GET_CONFIGURATION        = $0880
  REQ_GET_DESCRIPTOR           = $0680
  REQ_GET_INTERFACE            = $0a81
  REQ_GET_DEVICE_STATUS        = $0000
  REQ_GET_INTERFACE_STATUS     = $0001
  REQ_GET_ENDPOINT_STATUS      = $0002
  REQ_SET_ADDRESS              = $0500
  REQ_SET_CONFIGURATION        = $0900
  REQ_SET_DESCRIPTOR           = $0700
  REQ_SET_DEVICE_FEATURE       = $0300
  REQ_SET_INTERFACE_FEATURE    = $0301
  REQ_SET_ENDPOINT_FEATURE     = $0302
  REQ_SET_INTERFACE            = $0b01
  REQ_SYNCH_FRAME              = $0c82

  ' Standard descriptor types.
  
  DESC_DEVICE           = $0100
  DESC_CONFIGURATION    = $0200
  DESC_STRING           = $0300
  DESC_INTERFACE        = $0400
  DESC_ENDPOINT         = $0500

  DESCHDR_DEVICE        = $01_12
  DESCHDR_CONFIGURATION = $02_09
  DESCHDR_INTERFACE     = $04_09
  DESCHDR_ENDPOINT      = $05_07
  
  ' Descriptor Formats

  DEVDESC_bLength             = 0
  DEVDESC_bDescriptorType     = 1
  DEVDESC_bcdUSB              = 2
  DEVDESC_bDeviceClass        = 4
  DEVDESC_bDeviceSubClass     = 5
  DEVDESC_bDeviceProtocol     = 6
  DEVDESC_bMaxPacketSize0     = 7
  DEVDESC_idVendor            = 8
  DEVDESC_idProduct           = 10
  DEVDESC_bcdDevice           = 12
  DEVDESC_iManufacturer       = 14
  DEVDESC_iProduct            = 15
  DEVDESC_iSerialNumber       = 16
  DEVDESC_bNumConfigurations  = 17
  DEVDESC_LEN                 = 18

  CFGDESC_bLength             = 0
  CFGDESC_bDescriptorType     = 1
  CFGDESC_wTotalLength        = 2
  CFGDESC_bNumInterfaces      = 4
  CFGDESC_bConfigurationValue = 5
  CFGDESC_iConfiguration      = 6
  CFGDESC_bmAttributes        = 7
  CFGDESC_MaxPower            = 8

  IFDESC_bLength              = 0
  IFDESC_bDescriptorType      = 1
  IFDESC_bInterfaceNumber     = 2
  IFDESC_bAlternateSetting    = 3
  IFDESC_bNumEndpoints        = 4
  IFDESC_bInterfaceClass      = 5
  IFDESC_bInterfaceSubClass   = 6
  IFDESC_bInterfaceProtocol   = 7
  IFDESC_iInterface           = 8

  EPDESC_bLength              = 0
  EPDESC_bDescriptorType      = 1
  EPDESC_bEndpointAddress     = 2
  EPDESC_bmAttributes         = 3
  EPDESC_wMaxPacketSize       = 4
  EPDESC_bInterval            = 6

  ' SETUP packet format

  SETUP_bmRequestType         = 0
  SETUP_bRequest              = 1
  SETUP_wValue                = 2
  SETUP_wIndex                = 4
  SETUP_wLength               = 6
  SETUP_LEN                   = 8

  ' Endpoint constants

  DIR_IN       = $80
  DIR_OUT      = $00

  TT_CONTROL   = $00
  TT_ISOC      = $01
  TT_BULK      = $02
  TT_INTERRUPT = $03
                
  ' Error codes

  E_SUCCESS       = 0

  E_NO_DEVICE     = -150        ' No device is attached
  E_LOW_SPEED     = -151        ' Low-speed devices are not supported
  
  E_TIMEOUT       = -160        ' Timed out waiting for a response
  E_TRANSFER      = -161        ' Generic low-level transfer error
  E_CRC           = -162        ' CRC-16 mismatch
  E_TOGGLE        = -163        ' DATA0/1 toggle error
  E_PID           = -164        ' Invalid or malformed PID
  E_STALL         = -165        ' USB STALL response (pipe error)
  
  E_OUT_OF_COGS   = -180        ' Not enough free cogs, can't initialize
  E_OUT_OF_MEM    = -181        ' Not enough space for the requested buffer sizes
  E_DESC_PARSE    = -182        ' Can't parse a USB descriptor

DAT
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