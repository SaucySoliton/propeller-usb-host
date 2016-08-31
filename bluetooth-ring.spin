{{

 bluetooth-ring  ver 1.0
──────────────────────────────────────────────────────────────────

This is a simple utility class for one receive or transmit
ring buffer, for use with bluetooth-host.

This object is optional: the ring buffer protocol is designed to
be easy for you to reimplement in your own Spin or Assembly code.
This object is just a convenience for dealing with common use
cases. Includes high-level string methods which are based on
and compatible with Parallax Serial Terminal / FullDuplexSerial.

Ring buffers are hub-memory objects with a specific structure:

  word base         ' Pointer to the first byte of the buffer
  word mask         ' Bitmask for ring buffer pointers. This is
                      the buffer's power-of-two length minus 1.
  word enqueue      ' First empty byte, where new data is written
  word dequeue      ' Oldest non-empty byte, where data is read

These control words must always be written and read with word
operations, so that we can support a single concurrent reader
and writer without any locking. The ring is empty when enqueue
and dequeue are equal. The maximum usable fill level of the ring
is 'mask', or size-1. (One byte is not used, since it would then
be impossible to know the difference between a full and an empty
ring.)

Note that a single ring is always only used for either transmit
or receive. A bidirectional socket will have two rings. If you're
using a ring for transmit, never call its receive functions, and
vice versa! Each ring must have only one reader and one writer.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

 ┌───────────────────────────────────────────────────────────┐
 │ Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org> │
 │ Copyright (c) 2006-2009 Parallax, Inc.                    │
 │ See end of file for terms of use.                         │
 └───────────────────────────────────────────────────────────┘

}}

CON
  ' Tweak this all you like, but it needs to be a power of two,
  ' and for it to be useful this must be at least as large as the
  ' packet size we're using (RFCOMM MTU, or L2CAP datagram size).
  '
  ' Larger buffer sizes can increase throughput by allowing us to
  ' safely give our peer more flow control tokens. If the buffer
  ' size is too low, bandwidth will be limited by round-trip
  ' latency.

  RING_SIZE = 512

  RING_MASK = RING_SIZE - 1

  ' Default buffer fill level for auto-flush
  AUTOFLUSH_LEVEL = RING_SIZE / 2

  ' Newline character for line-based IO
  NL = 13

VAR
  ' Shared ring header
  word  base
  word  mask
  word  enqueue
  word  dequeue

  ' Private data
  word  pendingEnq     ' Pending value for 'enqueue'

  ' Ring data
  byte  buffer[RING_SIZE]

PUB Ring
{{Return a pointer to the ring buffer data structure. This is what you pass
  to your Bluetooth sockets.}}

  if not mask
    ' First time initialization
    mask := RING_MASK
    base := @buffer
    enqueue~
    dequeue~
    pendingEnq~

  return @base

PUB Char(bytechr)
{{Send single-byte character.  Waits for room in transmit buffer if necessary.
This does not automatically flush data to the transmitter, since that would lead
to many tiny packets, or a tiny packet followed by a larger one. Instead, we only
flush when a sufficient amount of data has been queued. The caller should use
TxFlush to explicitly flush at the end of a transmission, otherwise some data
may remain in the buffer for an unlimited amount of time.

(Note that some other networking stacks have different solutions to this problem,
such as the infamous 'Nagle Algorithm' in TCP. Explicit flushing is the only
algorithm supported by this particular ring implementation, since it avoids adding
any more latency than is necessary.)

  Parameter:
    bytechr - character (ASCII byte value) to send.}}

  if ((pendingEnq - dequeue) & RING_MASK) => AUTOFLUSH_LEVEL
    enqueue := pendingEnq

  repeat until (dequeue <> ((pendingEnq + 1) & RING_MASK))

  buffer[pendingEnq] := bytechr
  pendingEnq := (pendingEnq + 1) & RING_MASK

PUB Chars(bytechr, count)
{{Send multiple copies of a single-byte character. Waits for room in transmit buffer if necessary.
  Parameters:
    bytechr - character (ASCII byte value) to send.
    count   - number of bytechrs to send.}}

  repeat count
    Char(bytechr)

PUB CharIn : bytechr
{{Receive single-byte character.  Waits until character received.
  Returns: $00..$FF}}

  repeat while (bytechr := RxCheck) < 0

PUB Str(stringptr)
{{Send zero terminated string.
  Parameter:
    stringptr - pointer to zero terminated string to send.}}

  repeat strsize(stringptr)
    Char(byte[stringptr++])

PUB StrIn(stringptr)
{{Receive a string (carriage return terminated) and stores it (zero terminated) starting at stringptr.
Waits until full string received.
  Parameter:
    stringptr - pointer to memory in which to store received string characters.
                Memory reserved must be large enough for all string characters plus a zero terminator.}}

  StrInMax(stringptr, -1)

PUB StrInMax(stringptr, maxcount)
{{Receive a string of characters (either carriage return terminated or maxcount in length) and stores it (zero terminated)
starting at stringptr.  Waits until either full string received or maxcount characters received.
  Parameters:
    stringptr - pointer to memory in which to store received string characters.
                Memory reserved must be large enough for all string characters plus a zero terminator (maxcount + 1).
    maxcount  - maximum length of string to receive, or -1 for unlimited.}}

  repeat while (maxcount--)                                                     'While maxcount not reached
    if (byte[stringptr++] := CharIn) == NL                                      'Get chars until NL
      quit
  byte[stringptr+(byte[stringptr-1] == NL)]~                                    'Zero terminate string; overwrite NL or append 0 char

PUB Dec(value) | i, x
{{Send value as decimal characters.
  Parameter:
    value - byte, word, or long value to send as decimal characters.}}

  x := value == NEGX                                                            'Check for max negative
  if value < 0
    value := ||(value+x)                                                        'If negative, make positive; adjust for max negative
    Char("-")                                                                   'and output sign

  i := 1_000_000_000                                                            'Initialize divisor

  repeat 10                                                                     'Loop for 10 digits
    if value => i
      Char(value / i + "0" + x*(i == 1))                                        'If non-zero digit, output digit; adjust for max negative
      value //= i                                                               'and digit from value
      result~~                                                                  'flag non-zero found
    elseif result or i == 1
      Char("0")                                                                 'If zero digit (or only digit) output it
    i /= 10                                                                     'Update divisor

PUB Bin(value, digits)
{{Send value as binary characters up to digits in length.
  Parameters:
    value  - byte, word, or long value to send as binary characters.
    digits - number of binary digits to send.  Will be zero padded if necessary.}}

  value <<= 32 - digits
  repeat digits
    Char((value <-= 1) & 1 + "0")

PUB Hex(value, digits)
{{Send value as hexadecimal characters up to digits in length.
  Parameters:
    value  - byte, word, or long value to send as hexadecimal characters.
    digits - number of hexadecimal digits to send.  Will be zero padded if necessary.}}

  value <<= (8 - digits) << 2
  repeat digits
    Char(lookupz((value <-= 4) & $F : "0".."9", "A".."F"))

PUB CharCount : count
{{Get count of characters in buffer. }}

  return (enqueue - dequeue) & RING_MASK

PUB RxDiscard : count | enq
{{Flush receive buffer. Returns the exact number of discarded bytes.}}

  ' Latch the enqueue pointer, so we're sure to dequeue the
  ' same number of bytes we claim to be dequeueing.
  enq := enqueue

  count := (enq - dequeue) & RING_MASK
  dequeue := enq

PUB RxCheck : bytechr
{{Check if character received; return immediately.
  Returns: -1 if no byte received, $00..$FF if character received.}}

  bytechr~~
  if enqueue <> dequeue
    bytechr := buffer[dequeue]
    dequeue := (dequeue + 1) & RING_MASK

PUB TxFlush
{{ Make all queued TX data available for transmission. We don't automatically
send every single byte, since this tends to cause a tiny packet to be sent at
the beginning of every transmission. Instead, the caller should TxFlush as soon
as at least one packet's worth of data is queued for transmission.

Note that we may also flush the transmit buffer any time it is full, or
it contains more than a configurable amount of buffered data. }}

  enqueue := pendingEnq


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