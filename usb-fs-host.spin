{{

usb-fs-host
------------------------------------------------------------------

This is a software implementation of a simple full-speed
(12 Mb/s) USB 1.1 host controller for the Parallax Propeller.

This module is a self-contained USB stack, including host
controller driver, host controller, and a bit-banging PHY layer.

Software implementations of low-speed (1.5 Mb/s) USB have become
fairly common, but full-speed pushes the limits of even a fairly
powerful microcontroller like the Propeller. So naturally, I
had to cut some corners. See the sizable list of limitations and
caveats below.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

Copyright (c) 2010-2016 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.


Hardware Requirements
---------------------

 - 96 MHz (overclocked) Propeller
 - USB D- attached to P0 with a 47 ohm series resistor
 - USB D+ attached to P1 with a 47 ohm series resistor
 - Pull-down resistors (~47k ohm) from USB D- and D+ to ground

  +-------------------+  USB Host (Type A) Socket
  | ----------------- |
  |  [1] [2] [3] [4]  |  1: Vbus (+5v)  Red
  |-------------------|  2: D-          White
                         3: D+          Green
                         4: GND         Black

              +5v
                |   +-----+
      2x 47ohm  +---| [1] | Vbus
  P0 >---/\/--+-----| [2] | D-
  P1 >---/\/--|-+---| [3] | D+
              | | +-| [4] | GND
              | | | +-----+
      2x 47k  / / |
              | | |
              - - -

  Note: For maximum compatibility and at least some semblance of
        USB spec compliance, all four of these resistors are
        required. And the pull-down resistors are definitely
        necessary if you want to detect device connect/disconnect
        state. However, if you are permanently attaching a single
        device to your Propeller, depending on the device you
        may be able to omit the pull-down resistors and connect
        D-/D+ directly to P0/P1. I recommend you only try this if
        you know what you're doing and/or you're brave :)

  Note: You can modify DPLUS and DMINUS below, to change the pins we use
        for the USB port. This can only be done at compile-time so far,
        since a lot of compile-time literals rely on these values. Also,
        not all pins are supported. Both DPLUS and DMINUS must be between
        P0 and P7, inclusive.

Limitations and Caveats
-----------------------

 - Supports only a single device.
   (One host controller, one port, no hubs.)

 - Pin numbers are currently hardcoded as P0 and P1.
   Clock speed is hardcoded as 96 MHz (overclocked)

 - Requires 3 cogs.

   (We need a peak of 3 cogs during receive, but two
   of them are idle at other times. There is certainly
   room for improvement...)

 - Maximum transmitted packet size is approx. 430 bytes
   Maximum received packet size is approx. 1024 bytes

 - Doesn't even pretend to adhere to the USB spec!
   May not work with all USB devices.

 - Receiver is single-ended and uses a fixed clock rate.
   Does not tolerate line noise well, so use short USB
   cables if you must use a cable at all.

 - Maximum average speed is much less than line rate,
   due to time spent pre-encoding and post-decoding.

 - SOF packets do not have an incrementing frame number
   SOF packets may not be sent on-time due to other traffic

 - We don't detect TX/RX buffer overruns. If it hurts,
   don't do it. (Also, do not use this HC with untrusted
   devices- a babble condition can overwrite cog memory.)

Theory of Operation
-------------------

With the Propeller overclocked to 96 MHz, we have 8 clock cycles
(2 instructions) for every bit. That isn't nearly enough! So, we
cheat, and we do as much work as possible either before sending
a packet, after receiving a packet, or concurrently on another cog.

One cog is responsible for the bulk of the host controller
implementation. This is the transmit/controller cog. It accepts
commands from Spin code, handles pre-processing transmitted
data and post-processing received data, and oversees the process
of sending and receiving packets.

The grunt work of actually transmitting and receiving data is
offloaded from this cog. Transmit is handled by the TX cog's video
generator hardware. It's programmed in "VGA" mode to send two-byte
"pixels" to the D+/D- pins every 8 clock cycles. We pre-calculate
a buffer of "video" data representing each transmitted packet.

Receiving is harder- there's no hardware to help. In software, we
can test a port and shift its value into a buffer in 8 clock cycles,
but we don't have time to do anything else. So we can receive bursts
that are limited by cog memory. To receive continuously, this module
uses two receive cogs, and carefully interleaves them. Each cog
receives 16 bits at a time.

The other demanding operation we need to perform is a data IN
transfer. We need to transmit a token, receive a data packet, then
transmit an ACK. All back-to-back, with just a handful of bit
periods between packets. This is handled by some dedicated code
on the TX cog that does nothing but send low-latency ACKs after
the EOP state.

Since it takes much longer to decode and validate a packet than
we have before we must send an ACK, we use an inefficient but
effective "deferred ACK" strategy for IN transfers.


Programming Model
-----------------

This should look a little familiar to anyone who's written USB
drivers for a PC operating system, or used a user-level USB library
like libusb.

Public functions are provided for each supported transfer type.
(BulkRead, BulkWrite, InterruptRead...) These functions take an
endpoint descriptor, hub memory buffer, and buffer size.

All transfers are synchronous. (So, during a transfer itself,
we're really tying up 5 cogs if you count the one you called from.)
All transfers and most other functions can 'abort' with an error code.
See the E_* constants below. You must use the '\' prefix on function
calls if you want to catch these errors.

Since the transfer functions need to know both an endpoint's address
and its maximum packet size, we refer to endpoints by passing around
pointers to the endpoint's descriptor. In fact, this is how we refer
to interfaces too. This object keeps an in-memory copy of the
configuration descriptor we're using, so this data is always handy.
There are high-level functions for iterating over a device's
descriptors.

When a device is attached, call Enumerate to reset and identify it.
After Enumerate, the device will be in the 'addressed' state. It
will not be configured yet, but we'll have a copy of the device
descriptor and the first configuration descriptor in memory. To use
that default configuration, you can immediately call Configure. Now
the device is ready to use.

This host controller is a singleton object which is intended to
be instantiated only once per Propeller. Multiple objects can declare
OBJs for the host controller, but they will all really be sharing the
same instance. This will prevent you from adding multiple USB
controllers to one system, but there are also other reasons that we
don't currently support that. It's convenient, though, because this
means multiple USB device drivers can use separate instances of the
host controller OBJ to speak to the same USB port. Each device driver
can be invoked conditionally based on the device's class(es).

}}

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

  MAX_TOKEN_RETRIES    = 200    '
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
  ' This is a singleton object, so we use DAT for all variables.
  ' Note that, unlike VARs, these won't be sorted automatically.
  ' Keep variables of the same type together.

txc_command   long      -1                      ' Command buffer: [23:16]=arg, [15:0]=code ptr
rx1_time      long      -1                      ' Trigger time for RX1 cog
rx2_time      long      -1                      ' Trigger time for RX2 cog
rx2_sop       long      -1                      ' Start of packet, calculated by RX2
txc_result    long      0

heap_top      word      0                       ' Top of recycled memory heap

buf_dd        word      0                       ' Device descriptor buffer pointer
buf_cfg       word      0                       ' Configuration descriptor buffer pointer
buf_setup     word      0                       ' SETUP packet buffer pointer

isRunning     byte      0
portc         byte      PORTC_NOT_READY         ' Port connection status
rxdone        byte      $FF
debugFlags    byte      0

DAT
''
''
''==============================================================================
'' Host Controller Setup
''==============================================================================

PUB Start

  '' Starts the software USB host controller, if it isn't already running.
  '' Requires 3 free cogs. May abort if there aren't enough free cogs, or
  '' if we run out of recycled memory while allocating buffers.
  ''
  '' This function typically doesn't need to be invoked explicitly. It will
  '' be called automatically by GetPortConnection and Enumerate.

  if isRunning
    return

  heap_top := @heap_begin
  buf_dd := alloc(DEVDESC_LEN)
  buf_cfg := alloc(CFGDESC_BUFFER_LEN)
  buf_setup := alloc(SETUP_LEN)

  ' Set up pre-cognew parameters
  sof_deadline := cnt
  txp_portc    := @portc
  txp_result   := @txc_result
  txp_rx1_time := @rx1_time
  txp_rx2_time := @rx2_time
  rx2p_sop     := @rx2_sop

  txp_rxdone   := rx1p_done   := rx2p_done   := @rxdone
  txp_rxbuffer := rx1p_buffer := rx2p_buffer := alloc(constant(RX_BUFFER_WORDS * 4))

  if cognew(@controller_cog, @txc_command)<0 or cognew(@rx_cog_1, @rx1_time)<0 or cognew(@rx_cog_2, @rx2_time)<0
    abort E_OUT_OF_COGS

  ' Before we start scribbling over the memory we allocated above, wait for all cogs to start.
  repeat while txc_result or rx1_time or rx2_time

  isRunning~~

PRI alloc(bytes) : ptr
  ' Since this object can only be instantiated once, we have no need for the
  ' cog data in hub memory once we've started our cogs. Repurpose this as buffer
  ' space.

  ptr := heap_top := (heap_top + 3) & !3
  heap_top += bytes
  if heap_top > @heap_end
    abort E_OUT_OF_MEM

PUB FrameWait(count)
  '' Wait for the controller to send 'count' Start Of Frame tokens.
  '' If one SOF has been emitted since the last call to FrameWait, it may
  '' count as the first in 'count'.
  repeat count
    Command(OP_SOF_WAIT, 0)
  Sync

PUB SetDebugFlags(flags)
  '' Set low-level debug flags.
  '' 'flags' should be a combination of DEBUGFLAG_* constants.

  debugFlags := flags

DAT
''
''==============================================================================
'' High-level Device Framework
''==============================================================================

PUB GetPortConnection
  '' Is a device connected? If so, what speed? Returns a PORTC_* constant.
  '' Starts the host controller if it isn't already running.

  Start
  repeat while portc == PORTC_NOT_READY
  return portc

PUB Enumerate | pc
  '' Initialize the attached USB device, and get information about it.
  ''
  ''   1. Reset the device
  ''   2. Assign it an address
  ''   3. Read the device descriptor
  ''   4. Read the first configuration descriptor
  ''
  '' Starts the host controller if it isn't already running.

  ' Port debounce: Make sure the device is in the
  ' same connection state for a couple frames.

  pc := GetPortConnection
  FrameWait(3)
  if GetPortConnection <> pc
    abort E_PORT_BOUNCE

  case pc
    PORTC_NO_DEVICE, PORTC_INVALID:
      abort E_NO_DEVICE
    PORTC_LOW_SPEED:
      abort E_LOW_SPEED

  ' Device reset, and give it some time to wake up
  DeviceReset
  FrameWait(10)
  DefaultMaxPacketSize0

  if 0 > \DeviceAddress
    abort E_DEV_ADDRESS

  ' Read the real max packet length (Must request exactly 8 bytes)
  if 0 > \ControlRead(REQ_GET_DESCRIPTOR, DESC_DEVICE, 0, buf_dd, 8)
    abort E_READ_DD_1

  ' Validate device descriptor header
  if WORD[buf_dd] <> DESCHDR_DEVICE
    abort E_DESC_PARSE

  ' Read the whole descriptor
  if 0 > \ControlRead(REQ_GET_DESCRIPTOR, DESC_DEVICE, 0, buf_dd, DEVDESC_LEN)
    abort E_READ_DD_2

  ReadConfiguration(0)


PUB DefaultMaxPacketSize0

  ' Before we can do any transfers longer than 8 bytes, we need to know the maximum
  ' packet size on EP0. Otherwise we won't be able to determine when a transfer has
  ' ended. So, we'll use a temporary maximum packet size of 8 in order to address the
  ' device and to receive the first 8 bytes of the device descriptor. This should
  ' always be possible using transfers of no more than one packet in length.

  BYTE[buf_dd + DEVDESC_bMaxPacketSize0] := 8


PUB Configure
  '' Switch device configurations. This (re)configures the device according to
  '' the currently loaded configuration descriptor. To use a non-default configuration,
  '' call ReadConfiguration() to load a different descriptor first.

  ResetEndpointToggle
  Control(REQ_SET_CONFIGURATION, BYTE[buf_cfg + CFGDESC_bConfigurationValue], 0)

PUB UnConfigure
  '' Place the device back in its un-configured state.
  '' In the unconfigured state, only the default control endpoint may be used.

  Control(REQ_SET_CONFIGURATION, 0, 0)

PUB ReadConfiguration(index)
  '' Read in a configuration descriptor from the device. Most devices have only one
  '' configuration, and we load it automatically in Enumerate. So you usually don't
  '' need to call this function. But if the device has multiple configurations, you
  '' can use this to get information about them all.
  ''
  '' This does not actually switch configurations. If this newly read configuration
  '' is indeed the one you want to use, call Configure.

  if 0 > \ControlRead(REQ_GET_DESCRIPTOR, DESC_CONFIGURATION | index, 0, buf_cfg, CFGDESC_BUFFER_LEN)
    abort E_READ_CONFIG

  if WORD[buf_cfg] <> DESCHDR_CONFIGURATION
    abort E_DESC_PARSE

PUB DeviceDescriptor : ptr
  '' Get a pointer to the enumerated device's Device Descriptor
  return buf_dd

PUB ConfigDescriptor : ptr
  '' Get a pointer to the last config descriptor read with ReadConfiguration().
  '' If the configuration was longer than CFGDESC_BUFFER_LEN, it will be truncated.
  return buf_cfg

PUB VendorID : devID
  '' Get the enumerated device's 16-bit Vendor ID
  return WORD[buf_dd + DEVDESC_idVendor]

PUB ProductID : devID
  '' Get the enumerated device's 16-bit Product ID
  return WORD[buf_dd + DEVDESC_idProduct]

PUB ClearHalt(epd)
  '' Clear a Halt condition on one endpoint, given a pointer to the endpoint descriptor

  Control(REQ_CLEAR_ENDPOINT_FEATURE, 0, BYTE[epd + EPDESC_bEndpointAddress])


DAT
''
''==============================================================================
'' Configuration Descriptor Parsing
''==============================================================================

PUB NextDescriptor(ptrIn) : ptrOut | endPtr
  '' Advance to the next descriptor within the configuration descriptor.
  '' If there is another descriptor, returns a pointer to it. If we're at
  '' the end of the descriptor or the buffer, returns 0.

  ptrOut := ptrIn + BYTE[ptrIn]
  endPtr := buf_cfg + (WORD[buf_cfg + CFGDESC_wTotalLength] <# CFGDESC_BUFFER_LEN)

  if ptrOut => endPtr
    ptrOut~

PUB NextHeaderMatch(ptrIn, header) : ptrOut
  '' Advance to the next descriptor which matches the specified header.

  repeat while ptrIn := NextDescriptor(ptrIn)
    if UWORD(ptrIn) == header
      return ptrIn
  return 0

PUB FirstInterface : firstIf
  '' Return a pointer to the first interface in the current config
  '' descriptor. If there were no valid interfaces, returns 0.

  return NextInterface(buf_cfg)

PUB NextInterface(curIf) : nextIf
  '' Advance to the next interface after 'curIf' in the current
  '' configuration descriptor. If there are no more interfaces, returns 0.

  return NextHeaderMatch(curIf, DESCHDR_INTERFACE)

PUB NextEndpoint(curIf) : nextIf
  '' Advance to the next endpoint after 'curIf' in the current
  '' configuration descriptor. To get the first endpoint in an interface,
  '' pass in a pointer to the interface descriptor.
  ''
  '' If there are no more endpoints in this interface, returns 0.

  repeat while curIf := NextDescriptor(curIf)
    case UWORD(curIf)
      DESCHDR_ENDPOINT:
        return curIf
      DESCHDR_INTERFACE:
        return 0

  return 0

PUB FindInterface(class) : foundIf
  '' Look for the first interface which has the specified class.
  '' If no such interface exists on the current configuration, returns 0.

  foundIf := FirstInterface
  repeat while foundIf
    if BYTE[foundIf + IFDESC_bInterfaceClass] == class
      return foundIf
    foundIf := NextInterface(foundIf)

PUB EndpointDirection(epd)
  '' Given an endpoint descriptor pointer, test the endpoint direction.
  '' (DIR_IN or DIR_OUT)

  return BYTE[epd + EPDESC_bEndpointAddress] & $80

PUB EndpointType(epd)
  '' Return an endpoint's transfer type (TT_BULK, TT_ISOC, TT_INTERRUPT)

  return BYTE[epd + EPDESC_bmAttributes] & $03


PUB UWORD(addr) : value
  '' Like WORD[addr], but works on unaligned addresses too.
  '' You must use this rather than WORD[] when reading 16-bit values
  '' from descriptors, since descriptors have no alignment guarantees.

  return BYTE[addr] | (BYTE[addr + 1] << 8)


DAT
''
''==============================================================================
'' Device Setup
''==============================================================================

PUB DeviceReset
  '' Asynchronously send a USB bus reset signal.

  Command(OP_RESET, 0)
  ResetEndpointToggle

PUB DeviceAddress | buf

  '' Send a SET_ADDRESS(1) to device 0.
  ''
  '' This should be sent after DeviceReset to transition the
  '' device from the Default state to the Addressed state. All
  '' other transfers here assume the device address is 1.

  WORD[buf_setup] := REQ_SET_ADDRESS
  WORD[buf_setup + SETUP_wValue] := 1
  LONG[buf_setup + SETUP_wIndex]~

  ControlRaw(TOKEN_DEV0_EP0, @buf, 4)

DAT
''
''==============================================================================
'' Control Transfers
''==============================================================================

PUB Control(req, value, index) | buf

  '' Issue a no-data control transfer to an addressed device.

  WORD[buf_setup] := req
  WORD[buf_setup + SETUP_wValue] := value
  WORD[buf_setup + SETUP_wIndex] := index
  WORD[buf_setup + SETUP_wLength]~

  return ControlRaw(TOKEN_DEV1_EP0, @buf, 4)

PUB ControlRead(req, value, index, bufferPtr, length) | toggle

  '' Issue a control IN transfer to an addressed device.
  ''
  '' Returns the number of bytes read.
  '' Aborts on error.

  WORD[buf_setup] := req
  WORD[buf_setup + SETUP_wValue] := value
  WORD[buf_setup + SETUP_wIndex] := index
  WORD[buf_setup + SETUP_wLength] := length

  ' Issues SETUP and IN transactions
  result := ControlRaw(TOKEN_DEV1_EP0, bufferPtr, length)

  ' Status phase (OUT + DATA1)
  toggle := PID_DATA1
  WriteData(PID_OUT, TOKEN_DEV1_EP0, 0, 0, @toggle, MAX_TOKEN_RETRIES)

PUB ControlWrite(req, value, index, bufferPtr, length) | toggle, pktSize0, packetSize

  '' Issue a control OUT transfer to an addressed device.

  WORD[buf_setup] := req
  WORD[buf_setup + SETUP_wValue] := value
  WORD[buf_setup + SETUP_wIndex] := index
  WORD[buf_setup + SETUP_wLength] := length

  toggle := PID_DATA0
  WriteData(PID_SETUP, TOKEN_DEV1_EP0, buf_setup, 8, @toggle, MAX_TOKEN_RETRIES)

  ' Break OUT data into multiple packets if necessary
  pktSize0 := BYTE[buf_dd + DEVDESC_bMaxPacketSize0]
  repeat
    packetSize := length <# pktSize0
    WriteData(PID_OUT, TOKEN_DEV1_EP0, bufferPtr, packetSize, @toggle, MAX_TOKEN_RETRIES)
    bufferPtr += packetSize
    if (length -= packetSize) =< 0

      ' Status stage (always DATA1)
      toggle := PID_DATA1
      return DataIN(TOKEN_DEV1_EP0, @packetSize, 4, pktSize0, @toggle, TXRX_TX_RX_ACK, MAX_TOKEN_RETRIES, 1)

PUB ControlRaw(token, buffer, length) | toggle

  '' Common low-level implementation of no-data and read control transfers.

  toggle := PID_DATA0
  WriteData(PID_SETUP, token, buf_setup, 8, @toggle, MAX_TOKEN_RETRIES)
  return DataIN(token, buffer, length, BYTE[buf_dd + DEVDESC_bMaxPacketSize0], @toggle, TXRX_TX_RX_ACK, MAX_TOKEN_RETRIES, 1)

PUB SetupBuffer
  return buf_setup


DAT
''
''==============================================================================
'' Interrupt Transfers
''==============================================================================

PUB InterruptRead(epd, buffer, length) : actual | epTable

  '' Try to read one packet, up to 'length' bytes, from an Interrupt IN endpoint.
  '' Returns the actual amount of data read.
  '' If no data is available, raises E_TIMEOUT without waiting.
  ''
  '' 'epd' is a pointer to this endpoint's Endpoint Descriptor.

  ' This is different from Bulk in two main ways:
  '
  '   - We give DataIN an artificially large maxPacketSize, since we
  '     never want it to receive more than one packet at a time here.
  '   - We give it a retry of 0, since we don't want to retry on NAK.

  epTable := EndpointTableAddr(epd)
  return DataIN(WORD[epTable], buffer, length, $1000, epTable + EPTABLE_TOGGLE_IN, TXRX_TX_RX, 0, MAX_CRC_RETRIES)


DAT
''
''==============================================================================
'' Bulk Transfers
''==============================================================================

PUB BulkWrite(epd, buffer, length) | packetSize, epTable, maxPacketSize

  '' Write 'length' bytes of data to a Bulk OUT endpoint.
  ''
  '' Always writes at least one packet. If 'length' is zero,
  '' we send a zero-length packet. If 'length' is any other
  '' even multiple of maxPacketLen, we send only maximally-long
  '' packets and no zero-length packet.
  ''
  '' 'epd' is a pointer to this endpoint's Endpoint Descriptor.

  epTable := EndpointTableAddr(epd)
  maxPacketSize := EndpointMaxPacketSize(epd)

  repeat
    packetSize := length <# maxPacketSize

    WriteData(PID_OUT, WORD[epTable], buffer, packetSize, epTable + EPTABLE_TOGGLE_OUT, MAX_TOKEN_RETRIES)

    buffer += packetSize
    if (length -= packetSize) =< 0
      return

PUB BulkRead(epd, buffer, length) : actual | epTable

  '' Read up to 'length' bytes from a Bulk IN endpoint.
  '' Returns the actual amount of data read.
  ''
  '' 'epd' is a pointer to this endpoint's Endpoint Descriptor.

  epTable := EndpointTableAddr(epd)
  return DataIN(WORD[epTable], buffer, length, EndpointMaxPacketSize(epd), epTable + EPTABLE_TOGGLE_IN, TXRX_TX_RX, MAX_TOKEN_RETRIES, MAX_CRC_RETRIES)

DAT

'==============================================================================
' Low-level Transfer Utilities
'==============================================================================

PUB EndpointTableAddr(epd) : addr
  ' Given an endpoint descriptor, return the address of our EndpointTable entry.

  return @EndpointTable + ((BYTE[epd + EPDESC_bEndpointAddress] & $F) << EPTABLE_SHIFT)

PUB EndpointMaxPacketSize(epd) : maxPacketSize
  ' Parse the max packet size out of an endpoint descriptor

  return UWORD(epd + EPDESC_wMaxPacketSize)

PUB ResetEndpointToggle | ep
  ' Reset all endpoints to the default DATA0 toggle

  ep := @EndpointTable
  repeat 16
    BYTE[ep + EPTABLE_TOGGLE_IN] := BYTE[ep + EPTABLE_TOGGLE_OUT] := PID_DATA0
    ep += constant(|< EPTABLE_SHIFT)

PUB DataIN(token, buffer, length, maxPacketLen, togglePtr, txrxFlag, tokenRetries, crcRetries) : actual | packetLen

  ' Issue IN tokens and read the resulting data packets until
  ' a packet smaller than maxPacketLen arrives. On success,
  ' returns the actual number of bytes read. On failure, returns
  ' a negative error code.
  '
  ' 'togglePtr' is a pointer to a byte with either PID_DATA0 or
  ' PID_DATA1, depending on which DATA PID we expect next. Every
  ' time we receive a packet, we toggle this byte from DATA0 to
  ' DATA1 or vice versa.
  '
  ' Each packet will have up to 'retries' additional attempts
  ' if the device responds with a NAK.

  actual~

  ' As long as there's buffer space, send IN tokens. Each IN token
  ' allows the device to send us back up to maxPacketLen bytes of data.
  ' If the device sends a short packet (including zero-byte packets)
  ' it terminates the transfer.

  repeat
    packetLen := ReadDataIN(token, buffer, length, togglePtr, txrxFlag, tokenRetries, crcRetries)
    actual += packetLen
    buffer += packetLen
    length -= packetLen

    if packetLen < maxPacketLen
      return  ' Short packet. Device ended the transfer early.
    if length =< 0
      return  ' Transfer fully completed

PUB WriteData(pid, token, buffer, length, togglePtr, retries)

  ' Transmit a single data packet to an endpoint, as a token followed by DATA.
  '
  ' 'togglePtr' is a pointer to a byte with either PID_DATA0 or
  ' PID_DATA1, depending on which DATA PID we expect next. Every
  ' time we receive a packet, we toggle this byte from DATA0 to
  ' DATA1 or vice versa.
  '
  ' Each packet will have up to 'retries' additional attempts
  ' if the device responds with a NAK.

  repeat
    SendToken(pid, token)
    Command(OP_TX_BEGIN, BYTE[togglePtr])      ' DATA0/1

    if length
      Sync
      txc_result := length
      Command(OP_TX_DATA_PTR, buffer)

    Command(OP_TX_CRC16, 0)
    Command(OP_TX_END, 1)
    Command(OP_TXRX, TXRX_TX_RX)

    Command(OP_RX_PID, 0)
    Sync
    case txc_result

      SYNC_PID_NAK:
        ' Busy. Wait a frame and try again.
        if --retries =< 0
          abort E_TIMEOUT
        FrameWait(TIMEOUT_FRAME_DELAY)

      SYNC_PID_STALL:
        abort E_STALL

      SYNC_PID_ACK:
        BYTE[togglePtr] ^= constant(PID_DATA0 ^ PID_DATA1)
        return E_SUCCESS

      other:
        abort E_PID

PUB RequestDataIN(token, txrxFlag, togglePtr, retries)

  ' Low-level data IN request. Handles data toggle and retry.
  ' This is part of the implementation of DataIN().
  ' Aborts on error, otherwise returns the EOP timestamp.

  repeat
    SendToken(PID_IN, token)

    Command(OP_TXRX, txrxFlag)
    Sync
    result := txc_result

    Command(OP_RX_PID, 0)
    Sync
    case txc_result

      SYNC_PID_NAK:
        ' Busy. Wait a frame and try again.
        if --retries =< 0
          abort E_TIMEOUT
        FrameWait(TIMEOUT_FRAME_DELAY)

      SYNC_PID_STALL:
        abort E_STALL

      SYNC_PID_DATA0, SYNC_PID_DATA1:
        if (txc_result >> 8) <> BYTE[togglePtr]
          abort E_TOGGLE
        if txrxFlag == TXRX_TX_RX_ACK
          ' Only toggle if we're ACK'ing this packet
          BYTE[togglePtr] ^= constant(PID_DATA0 ^ PID_DATA1)
        return

      other:
        abort E_PID

PUB ReadDataIN(token, buffer, length, togglePtr, txrxFlag, tokenRetries, crcRetries)

  ' Low-level data IN request + read to buffer.
  ' This is part of the implementation of DataIN().
  ' Aborts on error, otherwise returns the actual number of bytes read.

  ' This implements our crazy "deferred ACK" scheme, to work around
  ' the fact that we can't decode a packet fast enough to check it prior
  ' to sending the ACK when we're supposed to. In this strategy, we send
  ' multiple IN tokens for each actual packet we intend to read, and postpone
  ' the ACK by one packet. The first packet is never acknowledged. The second
  ' will be ACK'ed only if the first was checked successfully. And so on.
  ' Normally this means that there are two packets: The first one is decoded
  ' but not ACKed, and the second one is ACKed but the contents are ignored.
  ' (We assume it's identical to the first.)
  '
  ' To use deferred ACKs, set txrxFlag to TXRX_TX_RX. To ACK the first
  ' response (before the CRC check) set txrxFlag to TXRX_TX_RX_ACK.
  ' If deferred ACKs are NOT in use, crcRetries must be 1.
  '
  ' We're currently using deferred ACKs only for Bulk and Interrupt INs.
  ' Some devices don't handle non-acknowledged IN packets during control
  ' transfers, so we still have the possibility of CRC errors during control
  ' reads. Luckily, most such transfers can be retried at a higher
  ' protocol level.

  repeat crcRetries

    ' The process of actually decoding the received packet is a bit convoluted,
    ' due to the split of responsibilities between the RX cogs, TX cog, and
    ' Spin code:
    '
    '   - The RX cogs don't really detect the EOP condition, they just stop when
    '     the D- line has been zero for a while. But they do record an accurate
    '     SOP timestamp.
    '
    '   - The TX cog records a fairly accurate EOP timestamp
    '
    '   - Spin code uses these timestamps to figure out the maximum number of
    '     bits that reside in a packet, minus the CRC and header.
    '
    '   - The decoder is given both a bit and byte limit, so it stops writing
    '     when either the buffer fills up or we reach the calculated EOP minus
    '     CRC position.

    ' Calculate the actual packet length.
    '
    ' RequestDataIN returns an EOP timestamp. The TX cog knew when the EOP
    ' was, and the RX2 cog knew when SOP was. We're running at 8 clocks
    ' per bit, or 64 clocks per byte. Convert clocks to bits.
    '
    ' We subtract enough bits to cover the CRC-16 and PID. The decoder needs us
    ' to account for slightly less bits than we're actually receiving, since it
    ' stops after the bit count underflows. To round evenly we could subtract half
    ' a byte, but we only subtract a couple due to the additional CRC-16 bit stuffing
    ' bits we haven't accounted for. (These are guaranteed to cause less than one
    ' byte's worth of difference in the calculation if we do this right.)
    '
    ' The full offset calculation is:
    '
    '    headerBits   = 16
    '    crcBits      = 16
    '    roundingBits = 4
    '
    '    offset = (headerBits + crcBits + roundingBits) * 8 - 4 = 284

    result := (RequestDataIN(token, txrxFlag, togglePtr, tokenRetries) - rx2_sop - 284) ~> 3

    if result =< 0
      result~ ' Zero-length packet. Device ended the transfer early
    elseif length =< 0
      result~ ' We don't want the data, the caller is just checking for a good PID. We're done.
    else
      ' The packet wasn't zero-length. Figure out how many bytes it was while
      ' we were decoding. The parameters for OP_RX_DATA_PTR are very counterintuitive,
      ' see the assembly code for a complete description. After the call, packetLen
      ' contains the number of actual bytes stored.
      Sync
      txc_result := ((length - 1) << 16) | result
      Command(OP_RX_DATA_PTR, buffer)
      Sync
      result := WORD[@txc_result] - buffer

      ' We currently can't tell whether RX_DATA_PTR ended because it hit the
      ' bit limit or because it hit the byte limit. If it hit the bit limit, all
      ' is well and we should be receiving the whole packet. But if it hit the byte
      ' limit, this is actually a babble condition. We stopped short, and the receive
      ' buffer isn't pointing at the actual CRC.
      '
      ' This is why E_CRC can mean either a CRC error or a babble error.

      Command(OP_RX_CRC16, 0)
      Sync
      if txc_result and not (debugFlags & DEBUGFLAG_NO_CRC)
        result := E_CRC

    if result => 0
      ' Success. ACK (if we haven't already) and get out.
      if txrxFlag <> TXRX_TX_RX_ACK
        RequestDataIN(token, TXRX_TX_RX_ACK, togglePtr, tokenRetries)
      return

  ' Out of CRC retries
  abort

PUB SendToken(pid, token)
  ' Enqueue a token in the TX buffer

  Command(OP_TX_BEGIN, pid)
  Command(OP_TX_DATA_16, token)
  Command(OP_TX_END, 10)


DAT

'==============================================================================
' Low-level Command Interface
'==============================================================================

PUB Sync
  ' Wait for the driver cog to finish what it was doing.
  repeat while txc_command

PUB Command(cmd, arg) | packed
  ' Asynchronously execute a low-level driver cog command.
  ' To save space in the driver cog, the conversion from
  ' command ID to address happens here, and we pack the
  ' address and 16-bit argument into the command word.

  packed := lookup(cmd: @cmd_reset, @cmd_tx_begin, @cmd_tx_end, @cmd_txrx, @cmd_tx_data_16, @cmd_tx_data_ptr, @cmd_tx_crc16, @cmd_rx_pid, @cmd_rx_data_ptr, @cmd_rx_crc16, @cmd_sof_wait)
  packed := ((packed - @controller_cog) >> 2) | (arg << 16)
  Sync
  txc_command := packed


DAT

'==============================================================================
' Endpoint State Table
'==============================================================================

' For each endpoint number, we have:
'
' Offset    Size    Description
' ----------------------------------------------------
'  0        Word    Token (device, endpoint, crc5)
'  2        Byte    Toggle for IN endpoint (PID_DATA0 / PID_DATA1)
'  3        Byte    Toggle for OUT endpoint

EndpointTable           word    TOKEN_DEV1_EP0, 0
                        word    TOKEN_DEV1_EP1, 0
                        word    TOKEN_DEV1_EP2, 0
                        word    TOKEN_DEV1_EP3, 0
                        word    TOKEN_DEV1_EP4, 0
                        word    TOKEN_DEV1_EP5, 0
                        word    TOKEN_DEV1_EP6, 0
                        word    TOKEN_DEV1_EP7, 0
                        word    TOKEN_DEV1_EP8, 0
                        word    TOKEN_DEV1_EP9, 0
                        word    TOKEN_DEV1_EP10, 0
                        word    TOKEN_DEV1_EP11, 0
                        word    TOKEN_DEV1_EP12, 0
                        word    TOKEN_DEV1_EP13, 0
                        word    TOKEN_DEV1_EP14, 0
                        word    TOKEN_DEV1_EP15, 0

DAT

heap_begin    ' Begin recyclable memory heap

'==============================================================================
' Controller / Transmitter Cog
'==============================================================================

' This is the "main" cog in the host controller. It processes commands that arrive
' from Spin code. These commands can build encoded USB packets in a local buffer,
' and transmit them. Multiple packets can be buffered back-to-back, to reduce the
' gap between packets to an acceptable level.
'
' This cog also handles triggering our two receiver cogs. Two receiver cogs are
' interleaved, so we can receive packets larger than what will fit in a single
' cog's unrolled loop.
'
' The receiver cogs are also responsible for managing the bus ownership, and the
' handoff between a driven idle state and an undriven idle. We calculate timestamps
' at which the receiver cogs will perform this handoff.

              org
controller_cog

              '======================================================
              ' Cog Initialization
              '======================================================

              ' Initialize the PLL and video generator for 12 MB/s output.
              ' This sets up CTRA as a divide-by-8, with no PLL multiplication.
              ' Use 2bpp "VGA" mode, so we can insert SE0 states easily. Every
              ' two bits we send to waitvid will be two literal bits on D- and D+.

              ' To start with, we leave the pin mask in vcfg set to all zeroes.
              ' At the moment we're actually ready to transmit, we set the mask.
              '
              ' We also re-use this initialization code space for temporary variables.

tx_count      mov       ctra, ctra_value
t1            mov       frqa, frqa_value
l_cmd         mov       vcfg, vcfg_value
codec_buf     mov       vscl, vscl_value

codec_cnt     call      #enc_reset

              '======================================================
              ' Command Processing
              '======================================================

              ' Wait until there's a command available or it's time to send a SOF.
              ' SOF is more important than a command, but we have no way of ensuring
              ' that a SOF won't need to occur during a command- so the SOF might be
              ' late.

cmdret
              wrlong    c_zero, par
              andn      outa, c_00010000

command_loop
              mov       t1, cnt                 ' cnt - sof_deadline, store sign bit
              sub       t1, sof_deadline
              rcl       t1, #1 wc               ' C = deadline is in the future
        if_nc tjz       tx_count, #tx_sof       ' Send the SOF if the buffer is not in use

              rdlong    l_cmd, par wz           ' Look for an incoming command
        if_z  jmp       #command_loop

              movs      :cmdjmp, l_cmd          ' Handler address in low 16 bits
              rol       l_cmd, #16              ' Now parameter is in low 16 bits
:cmdjmp       jmp       #0

              '======================================================
              ' SOF Packets / PORTC Sampling
              '======================================================

              ' If we're due for a SOF and we're between packets,
              ' this routine is called to transmit the SOF packet.
              '
              ' We're allowed to use the transmit buffer, but we must
              ' not return via 'cmdret', since we don't want to clear
              ' our command buffer- if another cog wrote a command
              ' while we're processing the SOF, we would miss it.
              ' So we need to use the lower-level encoder routines
              ' instead of calling other command implementations.
              '
              ' This happens to also be a good time to sample the port
              ' connection status. When the bus is idle, its state tells
              ' us whether a device is connected, and what speed it is.
              ' We need to sample this when the bus is idle, and this
              ' is a convenient time to do so. We can also skip sending
              ' the SOF if the bus isn't in a supported state.

tx_sof
              xor       cmd_sof_wait, c_condition     ' Let an SOF wait through.
                                                      ' (Swap from if_always to if_never)

              mov       t1, ina
              and       t1, #BUS_MASK
              wrbyte    t1, txp_portc                 ' Save idle bus state as PORTC
              cmp       t1, #PORTC_FULL_SPEED wz
        if_nz jmp       #:skip                        ' Only send SOF to full-speed devices

              call      #encode_sync                  ' SYNC field

              mov       codec_buf, sof_frame          ' PID and Token
              mov       codec_cnt, #24
              call      #encode

              call      #encode_eop                   ' End of packet and inter-packet delay

              mov       l_cmd, #0                     ' TX only, no receive
              call      #txrx

:skip
              add       sof_deadline, sof_period

              jmp       #command_loop

              '======================================================
              ' OP_TX_BEGIN
              '======================================================

              ' When we begin a packet, we'll always end up generating
              ' 16 bits (8 sync, 8 pid) which will fill up the first long
              ' of the transmit buffer. So it's legal to use tx_count!=0
              ' to detect whether we're using the transmit buffer.

cmd_tx_begin
              call      #encode_sync

              ' Now NRZI-encode the PID field

              mov       codec_buf, l_cmd
              mov       codec_cnt, #8
              call      #encode

              ' Reset the CRC-16, it should cover only data from after the PID.

              mov       enc_crc16, crc16_mask

              jmp       #cmdret

              '======================================================
              ' OP_TX_END
              '======================================================

cmd_tx_end
              call      #encode_eop
:idle_loop    
              test      l_cmd, #$1FF wz
        if_z  jmp       #cmdret
              call      #encode_idle
              sub       l_cmd, #1
              jmp       #:idle_loop

              '======================================================
              ' OP_TX_DATA_16
              '======================================================

cmd_tx_data_16
              mov       codec_buf, l_cmd
              mov       codec_cnt, #16
              call      #encode

              jmp       #cmdret

              '======================================================
              ' OP_TX_DATA_PTR
              '======================================================

              ' Byte count in "result", hub pointer in l_cmd[15:0].
              '
              ' This would be faster if we processed in 32-bit
              ' chunks when possible (at least 4 bytes left, pointer is
              ' long-aligned) but right now we're optimizing for simplicity
              ' and small code size.

cmd_tx_data_ptr
              rdlong    t1, txp_result

:loop         rdbyte    codec_buf, l_cmd
              mov       codec_cnt, #8
              add       l_cmd, #1
              call      #encode
              djnz      t1, #:loop

              jmp       #cmdret

              '======================================================
              ' OP_TX_CRC16
              '======================================================

cmd_tx_crc16
              mov       codec_buf, enc_crc16
              xor       codec_buf, crc16_mask
              mov       codec_cnt, #16
              call      #encode

              jmp       #cmdret

              '======================================================
              ' OP_TXRX
              '======================================================

cmd_txrx
              call      #txrx
              jmp       #cmdret

              '======================================================
              ' OP_RESET
              '======================================================

cmd_reset

              andn      outa, #BUS_MASK         ' Start driving SE0
              or        dira, #BUS_MASK

              mov       t1, cnt
              add       t1, reset_period
              waitcnt   t1, #0

              andn      dira, #BUS_MASK         ' Stop driving
              mov       sof_deadline, cnt       ' Ignore SOFs that should have occurred

              jmp       #cmdret

              '======================================================
              ' OP_RX_PID
              '======================================================

              ' Receive a 16-bit word, and reset the CRC-16.
              ' For use in receiving and validating a packet's SYNC/PID header.

cmd_rx_pid
              mov       codec_cnt, #16
              call      #decode
              shr       codec_buf, #16
              wrlong    codec_buf, txp_result

              mov       dec_crc16, crc16_mask   ' Reset the CRC-16

              jmp       #cmdret

              '======================================================
              ' OP_RX_DATA_PTR
              '======================================================

              ' Parameters:
              '   - Hub pointer in the command word
              '   - Maximum raw bit count in result[15:0]
              '   - Maximum byte count in result[31:16]
              '
              ' Returns:
              '   - Final write pointer (actual byte count + original pointer)
              '
              ' Always decodes at least one byte.
              '
              ' This would be faster if we processed in 32-bit
              ' chunks when possible (at least 4 bytes left, pointer is
              ' long-aligned) but right now we're optimizing for simplicity.
              '
              ' If this is modified to operate on 32-bit words in the future,
              ' this optimization must only take effect when the remaining bit
              ' count is high enough that we're guaranteed not to hit the bit
              ' limit during the 32-bit word. The returned actual byte count
              ' MUST have one-byte granularity.
              '
              ' We stop receiving when the byte or bit counts underflow. So both
              ' counts should be one byte under the actual values.

cmd_rx_data_ptr
              rdlong    t1, txp_result          ' Byte/bit count

:loop         mov       codec_cnt, #8           ' One byte at a time
              sub       t1, c_00010000          ' Decrements byte count
              call      #decode                 ' Decrements bit count
              shr       codec_buf, #24          ' Right-justify result
              wrbyte    codec_buf, l_cmd        ' Store result
              add       l_cmd, #1               ' Pointer + 1
              test      t1, c_80008000 wz       ' Detect bit or byte underflow
        if_z  jmp       #:loop

              wrword    l_cmd, txp_result
              jmp       #cmdret

              '======================================================
              ' OP_RX_CRC16
              '======================================================

cmd_rx_crc16
              xor       dec_crc16, crc16_mask   ' Save CRC of payload
              mov       t3, dec_crc16

              mov       codec_cnt, #16
              call      #decode

              shr       codec_buf, #16          ' Justify received CRC
              xor       t3, codec_buf           ' Compare
              wrlong    t3, txp_result          ' and return
              jmp       #cmdret

              '======================================================
              ' OP_SOF_WAIT
              '======================================================

              ' Normally this jumps back to the command loop without
              ' completing the command. In tx_sof, this code is modified
              ' to return exactly once.
              '
              ' (The modification works by patching the condition code on the
              ' first instruction in this routine.)

cmd_sof_wait  jmp       #command_loop
              xor       cmd_sof_wait, c_condition       ' Swap from if_never to if_always
              jmp       #cmdret


              '======================================================
              ' Transmit / Receive Front-end
              '======================================================

txrx
              ' Save the raw transmit length, not including padding,
              ' then pad our buffer to a multiple of 16 (one video word).

              mov       tx_count_raw, tx_count
:pad          test      tx_count, #%1111 wz
        if_z  jmp       #:pad_done
              call      #encode_idle
              jmp       #:pad
:pad_done

              ' Reset the receiver state (regardless of whether we're using it)

              wrbyte    v_idle, txp_rxdone      ' Arbitrary nonzero byte

              rcr       l_cmd, #1 wc            ' C = bit0 = RX Enable

              ' Transmitter startup: We need to synchronize with the video PLL,
              ' and transition from an undriven idle state to a driven idle state.
              ' To do this, we need to fill up the video generator register with
              ' idle states before setting DIRA and VCFG.
              '
              ' Since we own the bus at this point, we don't have to hurry.

              mov       vscl, vscl_value                ' Back to normal video speed
              waitvid   v_palette, v_idle
              waitvid   v_palette, v_idle
              movs      vcfg, #BUS_MASK
              or        dira, #DEBUG_TX_MASK | BUS_MASK

              ' Give the receiver cogs a synchronized timestamp to wake up at.

              mov       t1, tx_count_raw
              shl       t1, #3                  ' 8 cycles per bit
              add       t1, #$50                ' Constant offset
              add       t1, cnt
        if_c  wrlong    t1, txp_rx1_time
        if_c  wrlong    t1, txp_rx2_time

              ' Right now tx_count_raw is the number of bits
              ' in the packet. Convert it to a loop count we can
              ' use to line up our EOP with the video generator phase.

              add       tx_count_raw, #15       ' 0 -> 16
              and       tx_count_raw, #%1111    ' Period is 16 bits
              shl       tx_count_raw, #1        ' 2 iters per bit

              ' Transmit our NRZI-encoded packet.
              '
              ' This loop is optimized to do the last waitvid separately, so
              ' that we don't add any extra instructions between it and the
              ' bus release code below.

              movs      :tx_inst1, #tx_buffer
              shr       tx_count, #4            ' Bits -> words

:tx_loop      sub       tx_count, #1 wz
        if_z  jmp       #:tx_loop_last          ' Stop looping before the last word

:tx_inst1     waitvid   v_palette, 0            ' Output all words except the last one
              add       :tx_inst1, #1
              jmp       #:tx_loop

:tx_loop_last mov       :tx_inst2, :tx_inst1    ' Copy last address
              mov       :tx_inst3, :tx_inst1

              ' The last word is special, since we need to stop driving the bus
              ' immediately after the video generator clocks out our EOP bits.
              ' We've already calculated a loop count for how long to delay
              ' between the waitvid and the end of our EOP- but we need to
              ' special-case 0 so we can stop driving immediately after waitvid.

              tjz       tx_count_raw, #:tx_inst3

:tx_inst2     waitvid   v_palette, 0            ' Output last word
              djnz      tx_count_raw, #$        ' Any tx_count_raw >= 1
              andn      dira, #DEBUG_TX_MASK | BUS_MASK
              jmp       #:tx_release_done

:tx_inst3     waitvid   v_palette, 0            ' tx_count_raw == 0
              andn      dira, #DEBUG_TX_MASK | BUS_MASK

:tx_release_done

              ' As soon as we're done transmitting, switch to a 'turbo' vscl value,
              ' so that after the current video word expires we switch to a faster
              ' clock. This will help us synchronize to the video generator faster
              ' when sending ACKs, decreasing the maximum ACK latency.

              mov       vscl, vscl_turbo

              '======================================
              ' Receiver Controller
              '======================================

        if_nc jmp       #:rx_done                       ' Receiver disabled
              rcr       l_cmd, #1 wc                    ' C = bit1 = ACK Enable

              ' First, wait for an EOP signal. This wait needs to have a timeout,
              ' in case we never receive a packet. It also needs to have low latency,
              ' since we use this timing both to send ACK packets and to calculate
              ' the length of the received packet.

              mov       t1, eopwait_iters
:wait_eop     test      c_bus_mask, ina wz
        if_nz djnz      t1, #:wait_eop
              mov       t3, cnt                         ' EOP timestamp

              ' The USB spec gives us a fairly narrow window in which to transmit the ACK.
              ' So, to get predictable latency while also keeping code size down, we
              ' use the video generator in a somewhat odd way. Prior to this code,
              ' we set the video generator to run very quickly, so the variation in
              ' waitvid duration is fairly small. After re-synchronizing to the video
              ' generator, we slow it back down and emit a pre-constructed ACK packet.

        if_c  waitvid   v_palette, v_idle                ' Sync to vid gen. at turbo speed
        if_c  mov       vscl, vscl_value                 ' Back to normal speed at the next waitvid
        if_c  waitvid   v_palette, v_ack1                ' Start ACK after a couple idle cycles
        if_c  or        dira, #DEBUG_ACK_MASK | BUS_MASK ' Take bus ownership during the idle
        if_c  waitvid   v_palette, v_ack2                ' Second half of the ACK + EOP
        if_c  waitvid   v_palette, v_idle                ' Wait for the ack to completely finish
        if_c  andn      dira, #DEBUG_ACK_MASK | BUS_MASK ' Release bus

              ' Time-critical work is over. Save the EOP timestamp. The Spin code
              ' will use this value to calculate actual packet length.

              wrlong    t3, txp_result

              ' Now we're just waiting for the RX cog to finish. Poll RX_DONE.
              ' This shouldn't take long, since we already waited for the EOP.
              ' The RX cogs just need to detect the EOP and finish the word
              ' they're on. We'll be conservative and say they need 64 bit
              ' periods (2 full iterations) to do this job. That's 512
              ' clock cycles, or 32 hub windows.

              mov       t1, #32
:rx_wait      rdbyte    t3, txp_rxdone wz
        if_nz djnz      t1, #:rx_wait

              ' If the timeout expired and our RX cogs still aren't done,
              ' we'll manually wake them up by driving a SE1 onto the bus
              ' for a few cycles.

        if_nz or        outa, #BUS_MASK
        if_nz or        dira, #BUS_MASK
              nop
              nop
        if_nz andn      dira, #BUS_MASK
        if_nz andn      outa, #BUS_MASK

              ' Initialize the decoder, point it at the top of the RX buffer.
              ' The decoder will load the first long on our first invocation.

              mov       dec_rxbuffer, txp_rxbuffer
              mov       dec_nrzi_cnt, #1        ' Mod-32 counter
              mov       dec_nrzi_st, #0
              mov       dec_1cnt, #0
              rdlong    dec_nrzi, dec_rxbuffer
              add       dec_rxbuffer, #4

:rx_done
              '======================================
              ' End of Receiver Controller
              '======================================

              call      #enc_reset              ' Reset the encoder too
              movs      vcfg, #0                ' Disconnect vid gen. from outputs

txrx_ret      ret


              '======================================================
              ' NRZI Encoding and Bit Stuffing
              '======================================================

              ' Encode (NRZI, bit stuffing, and store) up to 32 bits.
              '
              ' The data to be encoded comes from codec_buf, and codec_cnt
              ' specifies how many bits we shift out from the LSB side.
              '
              ' For both space and time efficiency, this routine is also
              ' responsible for updating a running CRC-16. This is only
              ' used for data packets- at all other times it's quietly
              ' ignored.
encode
              rcr       codec_buf, #1 wc

              ' Update the CRC16.
              '
              ' This is equivalent to:
              '
              '   condition = (input_bit ^ (enc_crc16 & 1))
              '   enc_crc16 >>= 1
              '   if condition:
              '     enc_crc16 ^= crc16_poly

              test      enc_crc16, #1 wz
              shr       enc_crc16, #1
    if_z_eq_c xor       enc_crc16, crc16_poly

              ' NRZI-encode one bit.
              '
              ' For every incoming bit, we generate two outgoing bits;
              ' one for D- and one for D+. We can do all of this in three
              ' instructions with SAR and XOR. For example:
              '
              '   Original value of tx_reg:        10 10 10 10
              '   After SAR by 2 bits:          11 10 10 10 10
              '     To invert D-/D+, flip MSB:  01 10 10 10 10
              '    (or)
              '     Avoid inverting by flipping
              '     the next highest bit:       10 10 10 10 10
              '
              ' These two operations correspond
              ' to NRZI encoding 0 and 1, respectively.

              sar       enc_nrzi, #2
        if_nc xor       enc_nrzi, c_80000000     ' NRZI 0
        if_c  xor       enc_nrzi, c_40000000     ' NRZI 1


              ' Bit stuffing: After every six consecutive 1 bits, insert a 0.
              ' If we detect that bit stuffing is necessary, we do the branch
              ' after storing the original bit below, then we come back here to
              ' store the stuffed bit.

        if_nc mov       enc_1cnt, #6 wz
        if_c  sub       enc_1cnt, #1 wz
enc_bitstuff_ret

              ' Every time we fill up enc_nrzi, append it to tx_buffer.
              ' We use another shift register as a modulo-32 counter.

              ror       enc_nrzi_cnt, #1 wc
              add       tx_count, #1
encode_ptr
        if_c  mov       0, enc_nrzi
        if_c  add       encode_ptr, c_dest_1

              ' Insert the stuffed bit if necessary

        if_z  jmp       #enc_bitstuff

              djnz      codec_cnt, #encode
encode_ret    ret

              ' Handle the relatively uncommon case of inserting a zero bit,
              ' for bit stuffing. This duplicates some of the code from above
              ' for NRZI-encoding the extra bit. This bit is *not* included
              ' in the CRC16.

enc_bitstuff  sar       enc_nrzi, #2
              xor       enc_nrzi, c_80000000
              mov       enc_1cnt, #6 wz
              jmp       #enc_bitstuff_ret       ' Count and store this bit


              '======================================================
              ' Encoder / Transmitter Reset
              '======================================================

              ' (Re)initialize the encoder and transmitter registers.
              ' The transmit buffer will now be empty.

enc_reset     mov       enc_nrzi, v_idle
              mov       enc_nrzi_cnt, enc_ncnt_init
              mov       enc_1cnt, #0
              mov       tx_count, #0
              movd      encode_ptr, #tx_buffer
enc_reset_ret ret


              '======================================================
              ' Low-level Encoder
              '======================================================

              ' The main 'encode' function above is the normal case.
              ' But we need to be able to encode special bus states too,
              ' so these functions are slower but more flexible encoding
              ' entry points.
              '

              ' Check whether we need to store the contents of enc_nrzi
              ' after encoding another bit-period worth of data from it.
              ' This is a modified version of the tail end of 'encode' above.

encode_store
              mov       :ptr, encode_ptr
              ror       enc_nrzi_cnt, #1 wc
              add       tx_count, #1
:ptr    if_c  mov       0, enc_nrzi
        if_c  add       encode_ptr, c_dest_1
encode_store_ret ret

              ' Raw NRZI zeroes and ones, with no bit stuffing

encode_raw0
              sar       enc_nrzi, #2
              xor       enc_nrzi, c_80000000
              mov       enc_1cnt, #0
              call      #encode_store
encode_raw0_ret ret

encode_raw1
              sar       enc_nrzi, #2
              xor       enc_nrzi, c_40000000
              call      #encode_store
encode_raw1_ret ret

              ' One cycle of single-ended zero.

encode_se0
              shr       enc_nrzi, #2
              call      #encode_store
encode_se0_ret ret

              ' One cycle of idle bus (J state).

encode_idle
              shr       enc_nrzi, #2
              xor       enc_nrzi, c_80000000
              call      #encode_store
encode_idle_ret ret

              ' Append a raw SYNC field
encode_sync
              mov       t1, #7
:loop         call      #encode_raw0
              djnz      t1, #:loop
              call      #encode_raw1
encode_sync_ret ret

              ' Append a raw EOP.
              '
              ' Note that this makes sure we have at least one idle
              ' bit after the SE0s, but we'll probably have more due
              ' to the padding and bus-release latency in the transmitter.
encode_eop
              call      #encode_se0
              call      #encode_se0
              call      #encode_idle
encode_eop_ret ret


              '======================================================
              ' NRZI Decoder / Bit un-stuffer
              '======================================================

              ' Decode (retrieve, NRZI, bit un-stuff) up to 32 bits.
              '
              ' The data to decode comes from the RX buffer in hub memory.
              ' We decode 'codec_cnt' bits into the *MSBs* of 'codec_buf'.
              '
              ' As with encoding, we also run a CRC-16 here, since it's
              ' a convenient place to do so.
              '
              ' For every raw bit we consume, subtract 1 from t1.
              ' This is used as part of the byte/bit limiting for rx_data_ptr.

decode
              sub       t1, #1

              ' Extract the next bit from the receive buffer.
              '
              ' Our buffering scheme is a bit strange, since we need to have
              ' a 32-bit look ahead buffer at all times, for pseudo-EOP detection.
              '
              ' So, we treat 'dec_nrzi' as a 32-bit shift register which always
              ' contains valid bytes from the RX buffer. It is pre-loaded with the
              ' first word of the receive buffer.
              '
              ' Once every 32 decoded bits (starting with the first bit) we load a
              ' new long from dec_rxbuffer into dec_rxlatch. When we shift bits out
              ' of dec_nrzi, bits from dec_rxlatch replace them.

              ror       dec_nrzi_cnt, #1 wc
        if_c  rdlong    dec_rxlatch, dec_rxbuffer
        if_c  add       dec_rxbuffer, #4
              rcr       dec_rxlatch, #1 wc
              rcr       dec_nrzi, #1 wc

              ' We use a small auxiliary shift register to XOR the current bit
              ' with the last one, even across word boundaries where we might have
              ' to reload the main shift register. This auxiliary shift register
              ' ends up tracking the state ("what was the last bit?") for NRZI decoding.

              rcl       dec_nrzi_st, #1

              cmp       dec_1cnt, #6 wz         ' Skip stuffed bits
        if_z  mov       dec_1cnt, #0
        if_z  jmp       #decode

              test      dec_nrzi_st, #%10 wz    ' Previous bit
              shr       codec_buf, #1
    if_c_ne_z or        codec_buf, c_80000000   ' codec_buf <= !(prev XOR current)
              test      codec_buf, c_80000000 wz ' Move decoded bit to Z

    if_nz     add       dec_1cnt, #1            ' Count consecutive '1' bits
    if_z      mov       dec_1cnt, #0

              ' Update our CRC-16. This performs the same function as the logic
              ' in the encoder above, but it's optimized for our flag usage.

              shr       dec_crc16, #1 wc          ' Shift out CRC LSB into C
    if_z_eq_c xor       dec_crc16, crc16_poly

              djnz      codec_cnt, #decode
decode_ret    ret


              '======================================================
              ' Data
              '======================================================

' Parameters that are set up by Spin code prior to cognew()

sof_deadline  long      0
txp_portc     long      0
txp_result    long      0
txp_rxdone    long      0
txp_rx1_time  long      0
txp_rx2_time  long      0
txp_rxbuffer  long      0

' Constants

c_zero        long      0
c_40000000    long      $40000000
c_80000000    long      $80000000
c_00010000    long      $00010000
c_80008000    long      $80008000
c_dest_1      long      1 << 9
c_condition   long      %000000_0000_1111_000000000_000000000
c_bus_mask    long      BUS_MASK

reset_period  long      96_000 * 10

frqa_value    long      $10000000                       ' 1/8
ctra_value    long      (%00001 << 26) | (%111 << 23)   ' PLL 1:1
vcfg_value    long      (%011 << 28)                    ' Unpack 2-bit -> 8-bit
vscl_value    long      (8 << 12) | (8 * 16)            ' Normal 8 clocks per pixel
vscl_turbo    long      (1 << 12) | (1 * 16)            ' 1 clock per pixel
v_palette     long      (BUS_MASK << 24) | (STATE_J << 16) | (STATE_K) << 8
v_idle        long      %%2222_2222_2222_2222

' Pre-encoded ACK sequence:
'
'    SYNC     ACK      EOP
'    00000001 01001011
'    KJKJKJKK JJKJJKKK 00JJ
'
'    waitvid: %%2200_1112_2122_1121_2121
'
' This encoded sequence requires 40 bits.
' We encode this in two logs, but we don't start
' it immediately. Two reasons:
'
'   - We enable the output drivers immediately
'     after sync'ing to the video generator, So
'     there is about a 1/2 bit delay between
'     starting to send this buffer and when we
'     actually take control over the bus.
'
'   - We need to ensure a minimum inter-packet
'     delay between EOP and ACK.
'
'
'     (Currently we wait 4 bit periods.
'      This may need to be tweaked)

v_ack1        long      %%2122112121212222
v_ack2        long      %%2222222222001112

enc_ncnt_init long      $8000_8000                      ' Shift reg as mod-16 counter

crc16_poly    long      $a001                           ' USB CRC-16 polynomial
crc16_mask    long      $ffff                           ' Init/final mask

' How long will we wait for an EOP, during receive?
'
' This is a two-instruction (test / djnz) loop which takes 8 cycles. So each
' iteration is one bit period, and this is really a count of the maximum number
' of bit periods that could exist between the end of the transmitted packet
' and the EOP on the received packet. So it must account for the max size of the
' receive buffer, plus an estimate of the max inter-packet delay.

eopwait_iters long      ((RX_BUFFER_WORDS * 32) + 128)

' We try to send SOFs every millisecond, but other traffic can preempt them.
' Since we're not even trying to support very timing-sensitive devices, we
' also send a fake (non-incrementing) frame number.

sof_frame     long      %00010_00000000000_1010_0101    ' SOF PID, Frame 0, valid CRC6
sof_period    long      96_000                          ' 96 MHz, 1ms

' Encoder only
enc_nrzi      res       1                               ' Encoded NRZI shift register
enc_1cnt      res       1
enc_nrzi_cnt  res       1                               ' Cyclic bit counter
enc_crc16     res       1

' Decoder only
dec_nrzi      res       1                               ' Encoded NRZI shift register
dec_nrzi_cnt  res       1                               ' Cyclic bit counter
dec_nrzi_st   res       1                               ' State of NRZI decoder
dec_1cnt      res       1
dec_rxbuffer  res       1
dec_rxlatch   res       1
dec_crc16     res       1

tx_count_raw  res       1
t3            res       1

tx_buffer     res       TX_BUFFER_WORDS

              fit


'==============================================================================
' Receiver Cog 1
'==============================================================================

' This receiver cog stores the first 16-bit half of every 32-bit word.

              org
rx_cog_1
              wrlong    rx1_zero, par           ' Notify Start() that we're running.
:restart
              mov       rx1_buffer, rx1p_buffer
              mov       rx1_iters, #RX_BUFFER_WORDS

              ' On the very first iteration, we apply a tiny phase tweak
              ' to adjust the sampling location to the center of each
              ' bit. The RX2 cog can take this into account when calculating
              ' its first sample time, but since the RX1 cog needs to start
              ' sampling immediately, we save this phase shift for the second
              ' sampling iteration. This means that the first iteration will
              ' have somewhat lousier phase alignment than the rest.

              movs      :rx1_period, #(16*8 - 10)

:wait         rdlong    t2, par wz              ' Read trigger timestamp
        if_z  jmp       #:wait
              wrlong    rx1_zero, par           ' One-shot, zero it.

              waitcnt   t2, #0                  ' Wait for trigger time

              ' Now synchronize to the beginning of the next packet.
              ' We sample only D- in the receiver. If we time out,
              ' the controller cog will artificially send a SE1
              ' to bring us out of sleep. (We'd rather not send a SE0,
              ' since we may inadvertently reset the device.)

              waitpne   rx1_zero, rx1_pin

:sample_loop
              test      rx1_pin, ina wc         '  0
              rcr       t2, #1
              test      rx1_pin, ina wc         '  1
              rcr       t2, #1
              test      rx1_pin, ina wc         '  2
              rcr       t2, #1
              test      rx1_pin, ina wc         '  3
              rcr       t2, #1
              test      rx1_pin, ina wc         '  4
              rcr       t2, #1
              test      rx1_pin, ina wc         '  5
              rcr       t2, #1
              test      rx1_pin, ina wc         '  6
              rcr       t2, #1
              test      rx1_pin, ina wc         '  7
              rcr       t2, #1
              test      rx1_pin, ina wc         '  8
              rcr       t2, #1
              test      rx1_pin, ina wc         '  9
              rcr       t2, #1
              test      rx1_pin, ina wc         ' 10
              rcr       t2, #1
              test      rx1_pin, ina wc         ' 11
              rcr       t2, #1
              test      rx1_pin, ina wc         ' 12
              rcr       t2, #1
              test      rx1_pin, ina wc         ' 13
              rcr       t2, #1
              test      rx1_pin, ina wc         ' 14
              rcr       t2, #1
              test      rx1_pin, ina wc         ' 15
              rcr       t2, #1

              ' At this exact moment, the RX2 cog takes over sampling
              ' for us. We can store these 16 bits to hub memory, but we
              ' need to use a waitcnt to resynchronize to USB after
              ' waiting on the hub.
              '
              ' The loop period here is different for the first and the
              ' other iterations. See above.
              '
              ' This constant must be carefully adjusted so that the period
              ' of this loop is exactly 32*8 cycles. For reference, we can
              ' compare the RX1 and RX2 periods to make sure they're equal.

              mov       rx1_cnt, cnt
:rx1_period   add       rx1_cnt, #0
              movs      :rx1_period, #(16*8 - 9)

              shr       t2, #16
              wrword    t2, rx1_buffer
              add       rx1_buffer, #4

              ' Stop either when we fill up the buffer, or when RX2 signals
              ' that it's detected a pseudo-EOP and set RX_DONE.

              sub       rx1_iters, #1 wz
   if_nz      rdbyte    t2, rx1p_done wz
   if_z       jmp       #:restart

              waitcnt   rx1_cnt, #0
              jmp       #:sample_loop

rx1_pin       long      |< DMINUS
rx1_zero      long      0

' Parameters that are set up by Spin code prior to cognew()
rx1p_done     long      0
rx1p_buffer   long      0

rx1_buffer    res       1
rx1_cnt       res       1
rx1_iters     res       1
t2            res       1

              fit


'==============================================================================
' Receiver Cog 2
'==============================================================================

' This receiver cog stores the second 16-bit half of every 32-bit word.
'
' Since this is the last receiver cog to run, we update the RX_LONGS counter
' and detect when we're "done". We don't actually detect EOP conditions (since
' we are only sampling D-) but we decide to finish receiving when an entire word
' (16 bit perods) of the bus looks idle. Due to bit stuffing, this condition never
' occurs while a packet is in progress.
'
' When we detect this pseudo-EOP condition, we'll set the "done" bit (bit 31) in
' RX_LONGS. This tells both the RX1 cog and the controller that we're finished.

              org
rx_cog_2
              wrlong    rx2_zero, par           ' Notify Start() that we're running.
:restart
              mov       rx2_buffer, rx2p_buffer
              mov       rx2_iters, #RX_BUFFER_WORDS

:wait         rdlong    t4, par wz              ' Read trigger timestamp
        if_z  jmp       #:wait
              wrlong    rx2_zero, par           ' One-shot, zero it.

              waitcnt   t4, #0                  ' Wait for trigger time
              waitpne   rx2_zero, rx2_pin       ' Sync to SOP

              ' Save the SOP timestamp. We need this for our own calculations,
              ' plus our Spin code will use this to calculate received packet length.

              mov       rx2_cnt, cnt
              wrlong    rx2_cnt, rx2p_sop

              ' Calculate a sample time that's 180 degrees out of phase
              ' from the RX1 cog's sampling burst. We want to sample every
              ' 8 clock cycles with no gaps.

              add       rx2_cnt, #(16*8 - 5)
              jmp       #:first_sample

:sample_loop

              ' Justify the received word. Also detect our pseudo-EOP condition,
              ' when we've been idle (0) for 16 bits.
              shr       t4, #16 wz

              add       rx2_buffer, #2
              wrword    t4, rx2_buffer
              add       rx2_buffer, #2

              ' Update RX_DONE only after writing to the buffer.
              ' We're done if rx2_iters runs out, or if we're idle.

        if_nz sub       rx2_iters, #1 wz
        if_z  wrbyte    rx2_zero, rx2p_done
        if_z  jmp       #:restart

:first_sample waitcnt   rx2_cnt, #(32*8)

              test      rx2_pin, ina wc         '  0
              rcr       t4, #1
              test      rx2_pin, ina wc         '  1
              rcr       t4, #1
              test      rx2_pin, ina wc         '  2
              rcr       t4, #1
              test      rx2_pin, ina wc         '  3
              rcr       t4, #1
              test      rx2_pin, ina wc         '  4
              rcr       t4, #1
              test      rx2_pin, ina wc         '  5
              rcr       t4, #1
              test      rx2_pin, ina wc         '  6
              rcr       t4, #1
              test      rx2_pin, ina wc         '  7
              rcr       t4, #1
              test      rx2_pin, ina wc         '  8
              rcr       t4, #1
              test      rx2_pin, ina wc         '  9
              rcr       t4, #1
              test      rx2_pin, ina wc         ' 10
              rcr       t4, #1
              test      rx2_pin, ina wc         ' 11
              rcr       t4, #1
              test      rx2_pin, ina wc         ' 12
              rcr       t4, #1
              test      rx2_pin, ina wc         ' 13
              rcr       t4, #1
              test      rx2_pin, ina wc         ' 14
              rcr       t4, #1
              test      rx2_pin, ina wc         ' 15
              rcr       t4, #1

              jmp       #:sample_loop

rx2_pin       long      |< DMINUS
rx2_zero      long      0

' Parameters that are set up by Spin code prior to cognew()
rx2p_done     long      0
rx2p_buffer   long      0
rx2p_sop      long      0

rx2_done_p    res       1
rx2_time_p    res       1
rx2_buffer    res       1
rx2_iters     res       1
rx2_cnt       res       1
t4            res       1

              fit

heap_end    ' Begin recyclable memory heap

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