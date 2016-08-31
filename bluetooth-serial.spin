{{

 bluetooth-serial  ver 0.1
──────────────────────────────────────────────────────────────────

This is a simplified object for users who just want a Bluetooth
Serial Port device with the minimum of fuss.

This initializes the Bluetooth stack as follows:

 - Device name "Propeller"
 - Class of device: Computer
 - Always discoverable
 - PIN code is "0000"
 - Serial Port Profile

This module then provides full duplex buffered I/O functions which
are compatible with bluetooth-ring, SimpleSerial and FullDuplexSerial.

NOTE: This module auto-flushes all output before returning to the caller,
      for simplicity and for compatibility with other serial port objects.
      This is usually okay, but it can sometimes cause performance problems
      due to sending lots of tiny packets. See bluetooth-ring.TxFlush for
      more on this issue.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

 ┌───────────────────────────────────────────────────────────┐
 │ Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org> │
 │ See end of file for terms of use.                         │
 └───────────────────────────────────────────────────────────┘

}}

CON
  RFCOMM_CHANNEL = 3

OBJ
  bt : "bluetooth-host"
  rxr : "bluetooth-ring"
  txr : "bluetooth-ring"

PUB start
  '' Start the Bluetooth stack and the SPP server.
  '' On error, aborts with an error code from the Bluetooth or USB stack.
  ''
  '' No baud rate is necessary- we ignore the baud rate set by the
  '' SPP client. A USB Bluetooth dongle must be attached to the Propeller
  '' on pins 0 and 1. See usb-fs-host.spin.

  bt.Start

  bt.SetName(string("Propeller"))
  bt.SetClass(bt#COD_Computer)
  bt.SetDiscoverable
  bt.SetFixedPIN(string("0000"))

  bt.AddService(@serialService)
  bt.ListenRFCOMM(RFCOMM_CHANNEL, rxr.Ring, txr.Ring)

DAT

serialService word 0

    byte  bt#DE_Seq8, @t0 - @h0             ' <sequence>
h0

    byte    bt#DE_Uint16, $00,$00           '   ServiceRecordHandle
    byte    bt#DE_Uint32, $00,$01,$00,$02   '     (Arbitrary unique value)

    byte    bt#DE_Uint16, $00,$01           '   ServiceClassIDList
    byte    bt#DE_Seq8, @t1 - @h1           '   <sequence>
h1  byte      bt#DE_UUID16, $11,$01         '     SerialPort
t1

    byte    bt#DE_Uint16, $00,$04           '   ProtocolDescriptorList
    byte    bt#DE_Seq8, @t2 - @h2           '   <sequence>
h2  byte      bt#DE_Seq8, @t3 - @h3         '     <sequence>
h3  byte        bt#DE_UUID16, $01,$00       '       L2CAP
t3  byte      bt#DE_Seq8, @t4 - @h4         '     <sequence>
h4  byte        bt#DE_UUID16, $00,$03       '       RFCOMM
    byte        bt#DE_Uint8, RFCOMM_CHANNEL '       Channel
t4
t2

    byte    bt#DE_Uint16, $00,$05           '   BrowseGroupList
    byte    bt#DE_Seq8, @t5 - @h5           '   <sequence>
h5  byte      bt#DE_UUID16, $10,$02         '     PublicBrowseGroup
t5

    byte    bt#DE_Uint16, $00,$06           '   LanguageBaseAttributeIDList
    byte    bt#DE_Seq8, @t16 - @h16         '   <sequence>
h16 byte      bt#DE_Uint16, $65,$6e         '     Language
    byte      bt#DE_Uint16, $00,$6a         '     Encoding
    byte      bt#DE_Uint16, $01,$00         '     Base attribute ID value
t16

    byte    bt#DE_Uint16, $00,$09           '   BluetoothProfileDescriptorList
    byte    bt#DE_Seq8, @t7 - @h7           '   <sequence>
h7  byte      bt#DE_Seq8, @t8 - @h8         '     <sequence>
h8  byte      bt#DE_UUID16, $11,$01         '       SerialPort
    byte      bt#DE_Uint16, $01,$00         '       Version 1.0
t8
t7

    byte    bt#DE_Uint16, $01,$00           '   ServiceName + Language Base
    byte    bt#DE_Text8, @t19 - @h19
h19 byte      "Serial"
t19

t0

DAT
 '' bluetooth-ring style I/O functions

PUB Char(bytechr)
  txr.Char(bytechr)
  txr.TxFlush

PUB Chars(bytechr, count)
  txr.Chars(bytechr, count)
  txr.TxFlush

PUB CharIn : bytechr
  return rxr.CharIn

PUB Str(stringptr)
  txr.Str(stringptr)
  txr.TxFlush

PUB StrIn(stringptr)
  rxr.StrIn(stringptr)

PUB StrInMax(stringptr, maxcount)
  rxr.StrInMax(stringptr, maxcount)

PUB Dec(value) | i, x
  txr.Dec(value)
  txr.TxFlush

PUB Bin(value, digits)
  txr.Bin(value, digits)
  txr.TxFlush

PUB Hex(value, digits)
  txr.Hex(value, digits)
  txr.TxFlush

PUB CharCount : count
  return rxr.CharCount

PUB RxDiscard : count
  return rxr.RxDiscard

PUB RxCheck : bytechr
  return rxr.RxCheck

DAT
 '' FullDuplexSerial compatibility functions

PUB tx(c)
  txr.Char(c)
  txr.TxFlush

PUB rx : c
  return rxr.CharIn

PUB rxFlush
  rxr.RxDiscard

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