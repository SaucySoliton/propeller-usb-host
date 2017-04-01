{{

usb-fs-host-debug
------------------------------------------------------------------

Debugging wrapper for usb-fs-host, aka the Poor Man's USB Analyzer.

Logs every function call and every USB transfer to Parallax Serial
Terminal, including hex dumps of all incoming and outgoing buffers.

Usage:
  In the module(s) you want to debug, temporarily replace the
  "usb-fs-host" OBJ reference with "usb-fs-host-debug".

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.

}}

OBJ
  hc : "usb-fs-host"
  term : "Parallax Serial Terminal"

CON
  ' Verbosity options

  SHOW_FRAME_WAIT = 0           ' Show every FrameWait
  SHOW_INTR_TIMEOUT = 0         ' Show Interrupt Read timeouts

  ' Serial port

  BAUD_RATE = 115200

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


PUB Start
  epoch := cnt
  epochSec~

  ' Use StartRxTx instead of Start, since we don't want the 1-second delay.
  term.StartRxTx(31, 30, 0, BAUD_RATE)
  term.clear

  hc.Start

PUB logBegin(name) | timediff
  hideFrameWait~                     ' Only hide consecutive FrameWaits.

  term.char(term#NL)
  logTimestamp
  term.positionX(POS_TAG)
  term.char("[")
  term.str(name)
  term.positionX(POS_ENDTAG)
  term.str(string("] "))

PUB logStatus(code)
  term.str(string(" -> "))
  term.dec(result := code)
  if result == E_PID
    term.char(":")
    term.bin(hc.LastPIDError, 16)
  if result < 0
    abort

PUB logComma
  term.str(string(", "))

PUB logTimestamp | now
  ' Log a timestamp, in seconds and milliseconds.

  ' To avoid rollover, eat full seconds by incrementing epochSec and moving epoch forward.
  now := cnt
  repeat while ((now - epoch) => 80_000_000) or ((now - epoch) < 0)
    epoch += 80_000_000
    epochSec++

  term.dec(epochSec)
  term.char(".")
  dec3((now - epoch) / 80_000)

PUB dec3(n)
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
  logBegin(string("Enumerate"))
  logStatus(\hc.Enumerate)

PUB Configure
  logBegin(string("Configure"))
  logStatus(\hc.Configure)

PUB ReadConfiguration(index)
  logBegin(string("ReadConfiguration"))
  term.hex(index, 2)
  logStatus(\hc.ReadConfiguration(index))

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

PUB DataIN(token, buffer, length, maxPacketLen, togglePtr, txrxFlag, tokenRetries, crcRetries)
  logBegin(string("DataIN  "))
  result := logStatus(\hc.DataIN(token, buffer, length, maxPacketLen, togglePtr, txrxFlag, tokenRetries, crcRetries))
  hexDump(buffer, result)

PUB WriteData(pid, token, buffer, length, togglePtr, retries)
  logBegin(string("WrData  "))
  return hc.WriteData(pid, token, buffer, length, togglePtr, retries)

PUB RequestDataIN(token, txrxFlag, togglePtr, retries)
  logBegin(string("RqDataIN"))
  result := logStatus(\hc.RequestDataIN(token, txrxFlag, togglePtr, retries))

PUB ReadDataIN(token, buffer, length, togglePtr, txrxFlag, tokenRetries, crcRetries)
  logBegin(string("RdDataIN"))
  result := logStatus(\hc.ReadDataIN(token, buffer, length, togglePtr, txrxFlag, tokenRetries, crcRetries))
  hexDump(buffer, result)

PUB SendToken(pid, token, delayAfter)
  logBegin(string("SndToken"))
  term.hex(token, 4)
  logComma
  term.hex(delayAfter, 2)
  result := logStatus(\hc.SendToken(pid, token, delayAfter))


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
PUB GetPortConnection
  return hc.GetPortConnection
PUB DefaultMaxPacketSize0
  return hc.DefaultMaxPacketSize0
PUB Sync
  return hc.Sync
PUB SetupBuffer
  return hc.SetupBuffer
PUB LastPIDError
  return hc.LastPIDError
PUB Command(cmd, arg)
  logBegin(string("DevReset"))
  return hc.Command(cmd, arg)
PUB CommandResult
  return hc.CommandResult
PUB CommandExtra(arg)
  return hc.CommandExtra(arg)
PUB EndpointTableAddr(epd)
  return hc.EndpointTableAddr(epd)
PUB EndpointMaxPacketSize(epd)
  return hc.EndpointMaxPacketSize(epd)
PUB ResetEndpointToggle
  return hc.ResetEndpointToggle


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

  NUM_COGS = 3

  ' Transmit / Receive Size limits.
  '
  ' Transmit size limit is based on free Cog RAM. It can be increased if we save space
  ' in the cog by optimizing the code or removing other data. Receive size is limited only
  ' by available hub ram.
  '
  ' Note that if TX_BUFFER_WORDS is too large the error is detected at compile-time, but
  ' if RX_BUFFER_WORDS is too large we won't detect the error until Start is running!

  TX_BUFFER_WORDS = 205
  RX_BUFFER_WORDS = 256

  ' Maximum stored configuration descriptor size, in bytes. If the configuration
  ' descriptor is longer than this, we'll truncate it. Must be a multiple of 4.

  CFGDESC_BUFFER_LEN = 256

  ' USB data pins.
  '
  ' Important: Both DMINUS and DPLUS must be <= 8, since we
  '            use pin masks in instruction literals, and we
  '            assume we're using the first video generator bank.

  DMINUS = 0
  DPLUS = 1

  ' This module can be very challenging to debug. To make things a little bit easier,
  ' there are several places where debug pin masks are OR'ed into our DIRA values
  ' at compile-time. This doesn't use any additional memory. With a logic analyzer,
  ' you can use this to see exactly when the bus is being driven, and by what code.
  '
  ' To use this, pick some pin(s) to use, put their bit masks here. Attach a pull-up
  ' resistor and logic analyzer probe to each pin. To disable, set all values to zero.
  '
  ' Since the masks must fit in an instruction's immediate data, you must use P0 through P8.

  DEBUG_ACK_MASK   = 0
  DEBUG_TX_MASK    = 0

  ' Low-level debug flags, settable at runtime

  DEBUGFLAG_NO_CRC = $01

  ' Output bus states
  BUS_MASK  = (|< DPLUS) | (|< DMINUS)
  STATE_J   = |< DPLUS
  STATE_K   = |< DMINUS
  STATE_SE0 = 0
  STATE_SE1 = BUS_MASK

  ' Retry options

  MAX_TOKEN_RETRIES    = 200
  MAX_CRC_RETRIES      = 200
  TIMEOUT_FRAME_DELAY  = 10

  ' Number of CRC error retry attempts

  ' Offsets in EndpointTable
  EPTABLE_SHIFT      = 2        ' log2 of entry size
  EPTABLE_TOKEN      = 0        ' word
  EPTABLE_TOGGLE_IN  = 2        ' byte
  EPTABLE_TOGGLE_OUT = 3        ' byte

  ' Port connection status codes
  PORTC_NO_DEVICE  = STATE_SE0     ' No device (pull-down resistors in host)
  PORTC_FULL_SPEED = STATE_J       ' Full speed: pull-up on D+
  PORTC_LOW_SPEED  = STATE_K       ' Low speed: pull-up on D-
  PORTC_INVALID    = STATE_SE1     ' Buggy device? Electrical transient?
  PORTC_NOT_READY  = $FF           ' Haven't checked port status yet

  ' Command opcodes for the controller cog.

  OP_NOP           = 0                 ' Do nothing
  OP_RESET         = 1                 ' Send a USB Reset signal   '
  OP_TX_BEGIN      = 2                 ' Start a TX packet. Includes 8-bit PID
  OP_TX_END        = 3                 ' End a TX packet, arg = # of extra idle bits after
  OP_TXRX          = 4                 ' Transmit and/or receive packets
  OP_TX_DATA_16    = 5                 ' Encode and store a 16-bit word
  OP_TX_DATA_PTR   = 6                 ' Encode data from hub memory.
                                       '   Command arg: pointer
                                       '   "result" IN: Number of bytes
  OP_TX_CRC16      = 7                 ' Encode  a 16-bit CRC of all data since the PID
  OP_RX_PID        = 8                 ' Decode and return a 16-bit PID word, reset CRC-16
  OP_RX_DATA_PTR   = 9                 ' Decode data to hub memory.
                                       '   Command arg: pointer
                                       '   "result" IN: Max number of bytes
                                       '   result OUT:  Actual number of bytes
  OP_RX_CRC16      = 10                ' Decode and check CRC. Returns (actual XOR expected)
  OP_SOF_WAIT      = 11                ' Wait for one SOF to be sent

  ' OP_TXRX parameters

  TXRX_TX_ONLY     = %00
  TXRX_TX_RX       = %01
  TXRX_TX_RX_ACK   = %11

  ' USB PID values / commands

  PID_OUT    = %1110_0001
  PID_IN     = %0110_1001
  PID_SOF    = %1010_0101
  PID_SETUP  = %0010_1101
  PID_DATA0  = %1100_0011
  PID_DATA1  = %0100_1011
  PID_ACK    = %1101_0010
  PID_NAK    = %0101_1010
  PID_STALL  = %0001_1110
  PID_PRE    = %0011_1100

  ' NRZI-decoded representation of a SYNC field, and PIDs which include the SYNC.
  ' These are the form of values returned by OP_RX_PID.

  SYNC_FIELD      = %10000000
  SYNC_PID_ACK    = SYNC_FIELD | (PID_ACK << 8)
  SYNC_PID_NAK    = SYNC_FIELD | (PID_NAK << 8)
  SYNC_PID_STALL  = SYNC_FIELD | (PID_STALL << 8)
  SYNC_PID_DATA0  = SYNC_FIELD | (PID_DATA0 << 8)
  SYNC_PID_DATA1  = SYNC_FIELD | (PID_DATA1 << 8)

  ' USB Tokens (Device ID + Endpoint) with pre-calculated CRC5 values.
  ' Since we only support a single USB device, we only need tokens for
  ' device 0 (the default address) and device 1 (our arbitrary device ID).
  ' For device 0, we only need endpoint zero. For device 1, we include
  ' tokens for every possible endpoint.
  '
  '                  CRC5  EP#  DEV#
  TOKEN_DEV0_EP0  = %00010_0000_0000000
  TOKEN_DEV1_EP0  = %11101_0000_0000001
  TOKEN_DEV1_EP1  = %01011_0001_0000001
  TOKEN_DEV1_EP2  = %11000_0010_0000001
  TOKEN_DEV1_EP3  = %01110_0011_0000001
  TOKEN_DEV1_EP4  = %10111_0100_0000001
  TOKEN_DEV1_EP5  = %00001_0101_0000001
  TOKEN_DEV1_EP6  = %10010_0110_0000001
  TOKEN_DEV1_EP7  = %00100_0111_0000001
  TOKEN_DEV1_EP8  = %01001_1000_0000001
  TOKEN_DEV1_EP9  = %11111_1001_0000001
  TOKEN_DEV1_EP10 = %01100_1010_0000001
  TOKEN_DEV1_EP11 = %11010_1011_0000001
  TOKEN_DEV1_EP12 = %00011_1100_0000001
  TOKEN_DEV1_EP13 = %10101_1101_0000001
  TOKEN_DEV1_EP14 = %00110_1110_0000001
  TOKEN_DEV1_EP15 = %10000_1111_0000001

  ' Standard device requests.
  '
  ' This encodes the first two bytes of the SETUP packet into
  ' one word-sized command. The low byte is bmRequestType,
  ' the high byte is bRequest.

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
  '
  ' These identify a descriptor in REQ_GET_DESCRIPTOR,
  ' via the high byte of wValue. (wIndex is the language ID.)
  '
  ' The 'DESCHDR' variants are the full descriptor header,
  ' including type and length. This matches the first two bytes
  ' of any such static-length descriptor.

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

  ' Negative error codes. Most functions in this library can call
  ' "abort" with one of these codes.
  '
  ' So that multiple levels of the software stack can share
  ' error codes, we define a few reserved ranges:
  '
  '   -1 to -99    : Application
  '   -100 to -150 : Device or device class driver
  '   -150 to -199 : USB host controller
  '
  ' Within the USB host controller range:
  '
  '   -150 to -159 : Device connectivity errors
  '   -160 to -179 : Low-level transfer errors
  '   -180 to -199 : High-level errors (parsing, resource exhaustion)
  '
  ' When adding new errors, please keep existing errors constant
  ' to avoid breaking other modules who may depend on these values.
  ' (But if you're writing another module that uses these values,
  ' please use the constants from this object rather than hardcoding
  ' them!)

  E_SUCCESS       = 0

  E_NO_DEVICE     = -150        ' No device is attached
  E_LOW_SPEED     = -151        ' Low-speed devices are not supported
  E_PORT_BOUNCE   = -152        ' Port connection state changing during Enumerate

  E_TIMEOUT       = -160        ' Timed out waiting for a response
  E_TRANSFER      = -161        ' Generic low-level transfer error
  E_CRC           = -162        ' CRC-16 mismatch and/or babble condition
  E_TOGGLE        = -163        ' DATA0/1 toggle error
  E_PID           = -164        ' Invalid or malformed PID and/or no response
  E_STALL         = -165        ' USB STALL response (pipe error)

  E_DEV_ADDRESS   = -170        ' Enumeration error: Device addressing
  E_READ_DD_1     = -171        ' Enumeration error: First device descriptor read
  E_READ_DD_2     = -172        ' Enumeration error: Second device descriptor read
  E_READ_CONFIG   = -173        ' Enumeration error: Config descriptor read

  E_OUT_OF_COGS   = -180        ' Not enough free cogs, can't initialize
  E_OUT_OF_MEM    = -181        ' Not enough space for the requested buffer sizes
  E_DESC_PARSE    = -182        ' Can't parse a USB descriptor

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
