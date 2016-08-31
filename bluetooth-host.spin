{{

 bluetooth-host  ver 1.0
──────────────────────────────────────────────────────────────────

High-level Bluetooth Host driver for the Parallax Propeller.
Using the bluetooth-hciusb and usb-fs-host objects, this
directly supports USB Bluetooth adapters. This module implements
application-level protocols: L2CAP, RFCOMM, and SDP.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

 ┌───────────────────────────────────────────────────────────┐
 │ Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org> │               
 │ See end of file for terms of use.                         │
 └───────────────────────────────────────────────────────────┘

}}

OBJ
  hci : "bluetooth-hciusb"
  keyring : "bluetooth-keyring"

CON
  ' Standard Bluetooth "Class of Device" constants

  COD_Misc               = $000000
  COD_Computer           = $000100
  COD_Computer_Desktop   = $000104
  COD_Computer_Server    = $000108
  COD_Computer_Laptop    = $00010C
  COD_Computer_Handheld  = $000110
  COD_Computer_Palm      = $000114  
  COD_Phone              = $000200
  COD_Phone_Cellular     = $000204
  COD_Phone_Cordless     = $000208
  COD_Phone_Smart        = $00020C
  COD_Phone_Modem        = $000210  
  COD_LAN                = $000300
  COD_Audio              = $000400
  COD_Audio_Headset      = $000404
  COD_Peripheral         = $000500

  ' Standard Bluetooth Protocol Service Multiplexor (PSM) constants

  PSM_ServiceDiscovery   = $0001
  PSM_RFCOMM             = $0003
  PSM_TelephonyControl   = $0005
  PSM_TCSCordless        = $0007
  PSM_BNEP               = $000F
  PSM_HIDControl         = $0011
  PSM_HIDInterrupt       = $0013
  PSM_UPnP               = $0015
  PSM_AVCTP              = $0017
  PSM_AVDTP              = $0019
  PSM_DynamicBase        = $1001
  
  ' Other Bluetooth constants

  BDADDR_LEN = hci#BDADDR_LEN

  ' Commands for the server cog.
  ' Command IDs are the upper byte, parameters are the low 24 bits.

  C_HCI_Generic         = 1
  C_HCI_WrScanEnable    = 2
  C_HCI_WrLocalName     = 3
  C_HCI_WrLocalClass    = 4
  C_HCI_Inquiry         = 5
  
  ' Various timeouts

  ENUM_TIMEOUT_MS    = 10000
  HCI_TIMEOUT_MS     = 250
  HCI_RETRIES        = 10
  
  ' L2CAP Local Channel ID (LCID) Table: Stored information
  ' about each active L2CAP connection. To save memory, we have a
  ' single global table of L2CAP channels, and we hand out unique
  ' channel numbers to each device that's connected.
  '
  ' The table is indexed according to destination CID. We
  ' support up to LCID_TABLE_SIZE simultaneous L2CAP connections,
  ' using CIDs starting at LCID_FIRST.

  LCI_CONN_ID       = 0      ' Connection ID, or zero if unused
  LCI_REMOTE_CID    = 2      ' Remote channel ID that we're connected to
  LCI_PSM           = 4      ' Protocol Service Multiplexor
  LCI_LEN           = 6      ' Must be a multiple of 2

  LCI_TABLE_SIZE    = 4      ' Max number of PSM/Device tuples

  CID_FIRST         = $0080
  CID_LAST          = CID_FIRST + LCI_TABLE_SIZE

  ' Connection info table: Stored information about each active ACL
  ' connection. We begin the table with the bluetooth address, so
  ' that the public ConnectionAddress routine can also be easily
  ' used internally for other table entries.
  '
  ' The table size here determines the maximum number of devices we
  ' can maintain connections with simultaneously.
  '
  ' Table entries with CID=0 are unused.

  CI_BDADDR          = 0
  CI_CID             = 6
  CI_LEN             = 8      ' Must be a multiple of 4
  
  CI_TABLE_SIZE      = 4      ' Max number of open device connections
  
  ' Inquiry table: Stored information about discoverable Bluetooth
  ' devices nearby, which we've discovered as the result of an Inquiry
  ' command.

  IT_BDADDR          = 0
  IT_CLASS           = 6
  IT_LEN             = 9
  
  IT_TABLE_SIZE      = 8      ' Max number of devices we can discover

  ' Buffer structure: This is a public structure that defines a hub-memory
  ' ring buffer, used for sharing socket data with assembly language cogs

  RING_BASE          = 0      ' First byte in ringbuffer
  RING_MASK          = 2      ' Bit mask for ringbuffer bounds
  RING_ENQUEUE       = 4      ' First empty byte/datagram slot for writing
  RING_DEQUEUE       = 6      ' Oldest non-empty byte/datagram slot
  RING_LEN           = 8
  
  ' Socket table: One entry for each open or potentially-open L2CAP or
  ' RFCOMM connection.

  ST_CHANNEL         = 0      ' For established connections, points to
                              ' Local Channel Info row (PSM + Remote Device).
                              ' If zero, this is a new socket that hasn't yet
                              ' been bound to an endpoint yet.

  ST_PORT            = 2      ' RFCOMM channel or L2CAP PSM
  ST_PORT_L2CAP      = $80    '   OR'ed with ST_PORT to indicate an L2CAP socket
  
  ST_DATAGRAM        = 3      ' Minimum datagram size. All socket reads/writes are
                              '   padded to this size, so the socket can be used
                              '   as a datagram queue rather than a byte queue.
                              '   XXX: Not yet implemented

  ST_RX_CREDITS      = 4      ' Receive flow control credits (us -> peer)
  ST_TX_CREDITS      = 5      ' Transmit flow control credits (peer -> us)
  
  ST_RX_RING         = 6      ' Ring structure pointers, or 0 if ring is disabled
  ST_TX_RING         = 8

  ST_FLAGS           = 10
  
  ST_LEN             = 12
  ST_TABLE_SIZE      = 8      ' Max number of sockets

  ' ST_FLAGS

  STF_CONNECTED      = $0001  ' Connection fully established
  
  ' L2CAP: Basic header

  L2CAP_SIZE         = hci#ACL_HEADER_LEN
  L2CAP_CHANNEL      = L2CAP_SIZE + 2

  L2CAP_HEADER_LEN   = 4

  ' L2CAP: Connectionless data (G-frame)
  
  L2CAP_G_CHANNEL    = $0002
  L2CAP_G_PSM        = L2CAP_CHANNEL + 2
  L2CAP_G_DATA       = L2CAP_G_PSM + 2
  L2CAP_G_DATA_MAX   = hci#ACL_PACKET_SIZE - L2CAP_G_DATA
  
  ' L2CAP: Connection-oriented data (S-frame and I-frame)

  L2CAP_SI_DATA      = L2CAP_CHANNEL + 2
  L2CAP_SI_DATA_MAX  = hci#ACL_PACKET_SIZE - L2CAP_SI_DATA

  ' L2CAP: Signalling packets

  L2CAP_SIG_CHANNEL  = $0001
  L2CAP_SIG_CODE     = L2CAP_CHANNEL + 2
  L2CAP_SIG_ID       = L2CAP_SIG_CODE + 1
  L2CAP_SIG_LEN      = L2CAP_SIG_ID + 1
  L2CAP_SIG_DATA     = L2CAP_SIG_LEN + 2
  L2CAP_SIG_DATA_MAX = hci#ACL_PACKET_SIZE - L2CAP_SIG_DATA

  L2SIG_CmdReject       = $01
  L2SIG_ConnRequest     = $02
  L2SIG_ConnResponse    = $03
  L2SIG_CfgRequest      = $04
  L2SIG_CfgResponse     = $05
  L2SIG_DisconnRequest  = $06
  L2SIG_DisconnResponse = $07
  L2SIG_EchoRequest     = $08
  L2SIG_EchoResponse    = $09
  L2SIG_InfoRequest     = $0A
  L2SIG_InfoResponse    = $0B

  ' RFCOMM: Packet layout

  RFCOMM_ADDRESS        = L2CAP_SI_DATA
  RFCOMM_CONTROL        = RFCOMM_ADDRESS + 1
  RFCOMM_LEN            = RFCOMM_CONTROL + 1
  RFCOMM_DATA           = RFCOMM_LEN + 1
  RFCOMM_DATA_MAX       = hci#ACL_PACKET_SIZE - RFCOMM_DATA

  ' RFCOMM: Multiplexer Control Channel packet layout

  RFCOMM_MCC_TYPE       = RFCOMM_DATA
  RFCOMM_MCC_LEN        = RFCOMM_MCC_TYPE + 1
  RFCOMM_MCC_DATA       = RFCOMM_MCC_LEN + 1
  RFCOMM_MCC_DATA_MAX   = hci#ACL_PACKET_SIZE - RFCOMM_MCC_DATA

  ' RFCOMM: Advertized MTU. Must be smaller than the
  ' remaining space in our ACL buffer, to avoid fragmented
  ' packets. Smaller values will allow us to have finer-grained
  ' flow control, at the expense of more protocol overhead.
  '
  ' Note that RFCOMM_DATA_MAX - 1 corresponds to our maximum size
  ' without exceeding one USB packet.

  RFCOMM_MTU            = RFCOMM_DATA_MAX - 1
  
  ' RFCOMM: Address Field

  RFCOMM_EA             = $01
  RFCOMM_CR             = $02
  RFCOMM_DLCI_SHIFT     = 2

  ' RFCOMM: Control Field

  RFCOMM_PF             = $10
  RFCOMM_TYPE_MASK      = $EF
  RFCOMM_TYPE_SABM      = $2F
  RFCOMM_TYPE_UA        = $63
  RFCOMM_TYPE_DM        = $0F
  RFCOMM_TYPE_DISC      = $43
  RFCOMM_TYPE_UIH       = $EF

  ' RFCOMM: Length field

  RFCOMM_LEN_EA         = $01   ' Extended (16-bit) length
  RFCOMM_LEN_SHIFT      = 1
  
  ' RFCOMM: MCC Type field

  RFCOMM_MCCT_MASK      = $FC
  RFCOMM_MCC_EA         = $01
  RFCOMM_MCC_CR         = $02

  RFCOMM_MCCT_PN        = $80   ' Parameter Negotiation
  RFCOMM_MCCT_PSC       = $40   ' Power Saving Control
  RFCOMM_MCCT_CLD       = $C0   ' Multiplexer Close Down
  RFCOMM_MCCT_TEST      = $20   ' Test
  RFCOMM_MCCT_FCOn      = $A0   ' Flow Control On
  RFCOMM_MCCT_FCOff     = $60   ' Flow Control Off
  RFCOMM_MCCT_MSC       = $E0   ' Modem Status Command
  RFCOMM_MCCT_NSC       = $10   ' Non-supported Command Response
  RFCOMM_MCCT_RPN       = $90   ' Remote Port Negotiation
  RFCOMM_MCCT_RLS       = $50   ' Remote Line Status
  RFCOMM_MCCT_SNC       = $D0   ' Service Negotiation Command

  ' SDP: PDU Layout

  SDPPDU_TYPE           = L2CAP_SI_DATA
  SDPPDU_TRANSACTION    = SDPPDU_TYPE + 1
  SDPPDU_SIZE           = SDPPDU_TRANSACTION + 2
  SDPPDU_DATA           = SDPPDU_SIZE + 2
  SDPPDU_DATA_MAX       = hci#ACL_PACKET_SIZE - SDPPDU_DATA
  
  ' SDP: PDU Types

  SDP_ErrorResponse      = $01
  SDP_SearchRequest      = $02
  SDP_SearchResponse     = $03
  SDP_AttrRequest        = $04
  SDP_AttrResponse       = $05
  SDP_SearchAttrRequest  = $06
  SDP_SearchAttrResponse = $07

  ' SDP: Errors

  SE_BadSDPVersion       = $0001
  SE_BadServiceRecord    = $0002
  SE_BadSyntax           = $0003
  SE_BadPDUSize          = $0004
  SE_BadContinuation     = $0005
  SE_NoResources         = $0006

  ' SDP: Data element types

  DE_TYPE         = %11111 << 3
  DE_Nil          = 0 << 3
  DE_Unsigned     = 1 << 3
  DE_Signed       = 2 << 3
  DE_UUID         = 3 << 3
  DE_Text         = 4 << 3
  DE_Boolean      = 5 << 3
  DE_Sequence     = 6 << 3
  DE_Alternative  = 7 << 3
  DE_URL          = 8 << 3

  ' SDP: Data element sizes

  DE_SIZE         = %111
  DE_1Byte        = 0
  DE_2Bytes       = 1
  DE_4Bytes       = 2
  DE_8Bytes       = 3
  DE_16Bytes      = 4
  DE_Size8        = 5  ' Subsequent byte(s) are a size field
  DE_Size16       = 6
  DE_Size32       = 7

  ' SDP: Common combinations of type and size

  DE_Uint8        = DE_Unsigned | DE_1Byte
  DE_Uint16       = DE_Unsigned | DE_2Bytes
  DE_Uint32       = DE_Unsigned | DE_4Bytes
  DE_Int8         = DE_Signed | DE_1Byte                  
  DE_Int16        = DE_Signed | DE_2Bytes
  DE_Int32        = DE_Signed | DE_4Bytes
  DE_UUID16       = DE_UUID | DE_2Bytes
  DE_UUID32       = DE_UUID | DE_4Bytes
  DE_UUID128      = DE_UUID | DE_16Bytes
  DE_Text8        = DE_Text | DE_Size8
  DE_Seq8         = DE_Sequence | DE_Size8
  
DAT

serverStack   long  0[192]
serverCmd     long  -1
connTable     long  0[CI_TABLE_SIZE * CI_LEN / 4]
aclBuffer     long  0[hci#ACL_PACKET_SIZE / 4]

serverError   word  0           ' Last error from the server cog
hciCommand    word  0           ' In-progress HCI command (0 when done)
lciTable      word  0[LCI_TABLE_SIZE * LCI_LEN / 2]
socketTable   word  0[ST_TABLE_SIZE * ST_LEN / 2]
svcListHead   word  0           ' Linked list of service records
svcListSize   word  0           ' Size of all service lists
pinCodePtr    word  0

aclFragmented byte  0           ' Currently buffering a fragmented ACL packet             
pinCodeLen    byte  0
hciStatus     byte  0           ' Status code from last HCI command
addrStringBuf byte  0[18]       ' Buffer for AddressToString 
localAddr     byte  0[BDADDR_LEN]
inqCount      byte  0           ' Number of devices found so far
inqInProgress byte  0           ' Inquiry in progress?
inqTable      byte  0[IT_TABLE_SIZE * IT_LEN]
  
DAT
''
''
''==============================================================================
'' Initialization
''==============================================================================

PUB Start | deadline, ptr
  '' Get this whole Rube Goldberg machine going...
  ''   - Starts the USB Host Controller (3 cogs)
  ''   - Enumerates the attached USB devices
  ''   - Configures the Bluetooth USB device
  ''   - Starts the Bluetooth host controller (1 cog)
  ''
  '' So, this uses a total of 4 cogs. Our Bluetooth host cog runs
  '' an SDP server and handles incoming connections, so your application
  '' is free to do other things without compromising Bluetooth connectivity.
  ''
  '' By default, we accept incoming connections but this device is not
  '' discoverable. To make it discoverable, call SetName and SetClass
  '' (both optional but recommended) then SetDiscoverable. If other
  '' devices will be pairing with this one, it is also recommended to call
  '' SetFixedPIN.

  ' Initialize the hardware, retrying if it doesn't succeed right away.

  deadline := cnt + clkfreq/1000 * ENUM_TIMEOUT_MS
  result~~
  repeat while result and (cnt - deadline) < 0
    result := \HardwareInit
  if result
    abort

  ' Start the server cog
  if cognew(Server, @serverStack) < 0
    abort hci#E_OUT_OF_COGS

  ' Table-driven HCI initialization (see below)
  ptr := @initTable
  repeat while BYTE[ptr]
    HCIWait(constant(C_HCI_Generic << 24) | ptr)
    ptr += 3 + BYTE[ptr + 2]

DAT
  ' Initialization table:
  '   There are a lot of canned commands we'd like to send to the
  '   Bluetooth adapter during initialization, just to get it into
  '   a known state and set up our general preferences. To keep
  '   memory usage down, this is all table-driven. Each command
  '   begins with a 3-byte header: A two-byte command type, and
  '   one-byte parameter count. Then follows all parameter bytes.
  '   The command list is terminated by a zero byte.

initTable

  byte  hci#CB_Reset, hci#CB, 0

  ' Request info about the Bluetooth adapter
  byte  hci#IP_ReadLocalFeatures, hci#IP, 0
  byte  hci#IP_ReadLocalVersion, hci#IP, 0
  byte  hci#IP_ReadBufferSize, hci#IP, 0
  byte  hci#IP_ReadBDADDR, hci#IP, 0

  ' Clear all event filters
  byte  hci#CB_SetEventFilter, hci#CB, 1, $00

  ' Unmask all events
  byte  hci#CB_SetEventMask, hci#CB, 8, $FF,$FF,$FF,$FF, $FF,$1F,$00,$00

  ' Connection accept timeout = 32000 (20 seconds)
  byte  hci#CB_WriteConnAcceptTimeout, hci#CB, 2, 32000 & $FF, 32000 >> 8

  ' Page timeout = 8192 (5.12 seconds)
  byte  hci#CB_WritePageTimeout, hci#CB, 2, 8192 & $FF, 8192 >> 8

  ' Default link policy settings: Allow all LM modes (rswitch, hold, sniff, park)
  byte  hci#LP_WriteDefaultLPSettings, hci#LP, 2, $0F, $00 

  ' Fixed PIN code (We currently assume there's no user interface
  ' for entering variable PIN codes.)
  byte  hci#CB_WritePINType, hci#CB, 1, $01
                               
  ' Enable authentication for all connections
  byte  hci#CB_WriteAuthenticationEnable, hci#CB, 1, $01

  ' Enable encryption for all connections
  byte  hci#CB_WriteEncryptionMode, hci#CB, 1, $01
  
  byte  0

PUB GetLastError
  '' Returns the last error that was experienced by the server cog.

  result := ~~serverError
  serverError~
  
PUB SetDiscoverable
  '' Make this Bluetooth device discoverable by other devices

  HCIWait(constant(C_HCI_WrScanEnable << 24 | $03))

PUB SetName(str)
  '' Set the human-readable name of this Bluetooth device

  HCIWait(constant(C_HCI_WrLocalName << 24) | str)

PUB SetClass(class)
  '' Set the local device's class, as a packed 24-bit constant.
  '' You can use the standard COD_* constants from this object,
  '' or you can follow the Bluetooth spec in creating a custom
  '' COD for your device. 

  HCIWait(constant(C_HCI_WrLocalClass << 24) | class)

PUB LocalAddress
  '' Return a pointer to the local Bluetooth adapter's address

  return @localAddr

PUB AddService(service)
  '' Add a discoverable service to the SDP server.
  ''
  '' "service" is a pointer to a service record, in the raw
  '' format defined by SDP, prefixed by a single reserved word
  '' which is used internally in this module as a link pointer.
  ''
  '' This function adds exactly one service record. To add
  '' multiple services, call this multiple times.
  ''
  '' (Yes, this gets a bit complicated... see the accompanying examples.
  '' It may also help to read the Bluetooth SDP spec if you plan to alter
  '' service records or write your own.)
  
  WORD[service] := svcListHead
  svcListHead := service
  svcListSize += SkipDE(service += 2) - service

PUB SetFixedPIN(str)
  '' Set a fixed PIN code for this device to use. The code is specified
  '' as a string. We don't copy the string, so this memory must remain valid
  '' until a new PIN is set. The same PIN code will be used for every remote
  '' device.
  ''
  '' According to the Bluetooth spec, PIN codes must be between 1 and 16
  '' bytes long, and they must be composed of decimal digits only.
  ''
  '' SetFixedPIN(0) indicates that this device has no PIN (the default)

  if str
    pinCodePtr := str
    pinCodeLen := strsize(str)
  else
    pinCodePtr~

DAT
''
''
''==============================================================================
'' Device Discovery
''==============================================================================

PUB DiscoverDevices(duration)
  '' Begin looking for nearby discoverable Bluetooth devices.
  ''
  '' Device discovery is asynchronous. After you start discovery,
  '' the Bluetooth host cog will begin storing data about each
  '' device we find.
  ''
  '' Device discovery has a pre-set duration, specified here in
  '' units of 1.28 seconds. Valid durations are 1.28 to 61.44 seconds,
  '' or 1 through 48.
  ''
  '' Discovery results and status can be obtained using the other
  '' functions in this section.

  inqCount~
  longfill(@inqTable, 0, constant(IT_TABLE_SIZE * IT_LEN / 4))
  
  HCIWait(constant(C_HCI_Inquiry << 24) | duration)
  inqInProgress~~
  
PUB DiscoveryInProgress
  '' Returns nonzero as long as an asynchronous device discovery
  '' is in progress. If the discovery has finished because it has
  '' reached the end of its duration, returns zero.

  return inqInProgress

PUB NumDiscoveredDevices
  '' Returns the number of devices we've discovered so far.

  return inqCount

PUB DiscoveredAddr(id)
  '' Returns a pointer to the address of the discovered device
  '' with zero-based index "id".

  return @inqTable + IT_LEN * id

PUB DiscoveredClass(id) | ptr
  '' Returns the 24-bit class of a discovered device with
  '' zero-based index "id".

  ptr := DiscoveredAddr(id) + IT_CLASS
  result := BYTE[ptr++]
  result |= BYTE[ptr++] << 8
  result |= BYTE[ptr] << 16


DAT
''
''
''==============================================================================
'' Sockets
''==============================================================================

PRI SocketNew : ptr
  ' Find an unused socket, initialize it, and return a pointer

  ptr := @socketTable
  repeat ST_TABLE_SIZE
    if WORD[ptr] == 0 and BYTE[ptr + ST_PORT] == 0
      wordfill(ptr, 0, constant(ST_LEN / 2))
      return

    ptr += ST_LEN

  abort hci#E_NO_SOCKET

PUB ListenRFCOMM(channelId, rxRing, txRing) : ptr
  '' Create a new un-bound RFCOMM socket, with the specified
  '' transmit and receive rings, ready to receive a single
  '' incoming connection. Returns a pointer to the new socket.

  ptr := SocketNew
  WORD[ptr + ST_RX_RING] := rxRing
  WORD[ptr + ST_TX_RING] := txRing

  ' Writing the port activates this socket.      
  ' Note that ST_PORT includes the D (direction) bit. 0=server.
  BYTE[ptr + ST_PORT] := channelId << 1
  
PUB SocketFree(ptr)
  '' Free a socket, making it available for reuse.

  BYTE[ptr + ST_PORT]~
  WORD[ptr]~

PUB SocketPeer(ptr)
  '' Look up this socket's peer. If it isn't bound yet, returns zero.
  '' If it's bound, returns a pointer to the peer's BDADDR.

  if result := WORD[ptr]                    ' ST_CHANNEL
    return ConnectionAddress(WORD[result])  ' LCI_CONN_ID 
    
PRI ConnectionAddress(cid) | ptr
  ' Return a pointer to the Bluetooth address for a particular connection ID.
  '
  ' If the connection doesn't exist, aborts with E_NO_CONNECTION.
  ' Note that connections can be torn down at any time, so the caller
  ' must always handle this error somehow. 

  ptr := @connTable
  repeat CI_TABLE_SIZE
    if cid == WORD[ptr + CI_CID]
      return ptr
    ptr += CI_LEN
  abort hci#E_NO_CONNECTION

PRI FindBoundSocket(channel, port) : ptr
  ' Try to locate a bound socket with the given channel
  ' and port. If it can't be found, we try to locate an
  ' unbound socket on this port and bind it
  '
  ' Aborts with E_NO_SOCKET if there is no match.

  ptr := @socketTable
  repeat ST_TABLE_SIZE
    if WORD[ptr] == channel and BYTE[ptr + ST_PORT] == port
      ' It's a bound socket
      return
    ptr += ST_LEN

  ptr := @socketTable
  repeat ST_TABLE_SIZE
    if WORD[ptr] == 0 and BYTE[ptr + ST_PORT] == port
      ' Unbound socket. Bind it.
      WORD[ptr] := channel
      return
    ptr += ST_LEN

  abort hci#E_NO_SOCKET 

PRI SocketRXWrite(socket, ptr, len) | ring, ringMask, ringEnq, ringBase, chunk
  ' Internal function for storing received data in a socket's
  ' RX ring buffer, if that ring exists.

  if ring := WORD[socket + ST_RX_RING]
    ringBase := WORD[ring]
    ringMask := WORD[ring + RING_MASK]
    ringEnq := WORD[ring + RING_ENQUEUE]
    
    repeat while len
      chunk := len <# (ringMask + 1 - ringEnq)
      bytemove(ringBase + ringEnq, ptr, chunk)
      ptr += chunk
      len -= chunk
      ringEnq := ringMask & (ringEnq + chunk)

    WORD[ring + RING_ENQUEUE] := ringEnq

PRI SocketTXRead(socket, ptr, len) : actual | ring, ringMask, ringDeq, ringBase, chunk
  ' Internal function for reading up to 'len' bytes from a socket's TX ring buffer,
  ' if that ring exists and it has data available. Returns the number of bytes
  ' copied, or 0 if no data is available.

  if ring := WORD[socket + ST_TX_RING]
    if actual := len <#= RingByteCount(ring)
      ringBase := WORD[ring]
      ringMask := WORD[ring + RING_MASK]
      ringDeq := WORD[ring + RING_DEQUEUE]
    
      repeat while len
        chunk := len <# (ringMask + 1 - ringDeq)
        bytemove(ptr, ringBase + ringDeq, chunk)
        ptr += chunk
        len -= chunk
        ringDeq := ringMask & (ringDeq + chunk)

      WORD[ring + RING_DEQUEUE] := ringDeq

PRI RingByteCount(ring)
  ' Return the number of bytes queued in a ring

  return (WORD[ring + RING_ENQUEUE] - WORD[ring + RING_DEQUEUE]) & WORD[ring + RING_MASK]  

PRI RingBytesFree(ring)
  ' Return the number of usable free bytes in a ring

  return WORD[ring + RING_MASK] - RingByteCount(ring)

DAT
''
''
''==============================================================================
'' Utilities
''==============================================================================

PUB AddressToString(addr) | pIn, pOut, octet
  '' Convert a 6-byte Bluetooth Device Address
  '' to a human-readable string in the standard format.
  ''
  '' Returns a pointer to a zero-terminated string.
  '' This buffer is valid until the next call to AddressToString.
  ''
  '' For convenience, this function returns "--:--:--:--:--:--" if
  '' addr =< 0, so you can directly pass either pointers or error
  '' codes in and see something human-readable.

  pIn := addr + constant(BDADDR_LEN - 1)
  pOut := @addrStringBuf
  repeat BDADDR_LEN
    octet := BYTE[pIn--] << 24
    repeat 2
      if addr > 0
        BYTE[pOut++] := lookupz((octet <-= 4) & $F : "0".."9", "A".."F")
      else
        BYTE[pOut++] := "-" 
    BYTE[pOut++] := ":"
  BYTE[--pOut] := 0
  return @addrStringBuf

DAT
'
'
'==============================================================================
' Private Implementation
'==============================================================================

PRI HardwareInit
  ' Internal function to initialize the host controller hardware.
  ' We'll retry this until it succeeds, in case the Bluetooth adapter
  ' needs time to wake up, or there's noise on the USB connection.

  hci.Enumerate
  hci.Init

PRI Command(c)
  ' Send a command to the server cog

  repeat while serverCmd
  serverCmd := c

PRI HCIWait(c) | deadline
  ' Tell the server cog to issue an HCI command,
  ' and wait for the response. We'll automatically
  ' retry the command several times, but if it ultimately
  ' fails, we abort with an error code.
  '
  ' This is an indirect way to issue an HCI command via the server
  ' cog. We have to do this for two main reasons: (1) The server
  ' cog owns the USB controller and all HCI buffers, so we can't
  ' send commands without synchronizing with it anyway, and (2)
  ' we may need to process unrelated events and ACL packets while
  ' we're waiting on this command.
  '
  ' Note that we currently never have more than one pending
  ' command at a time, for simplicity's sake.

  repeat HCI_RETRIES

    hciCommand~~
    Command(c)

    deadline := cnt + clkfreq/1000 * HCI_TIMEOUT_MS
    repeat while (cnt - deadline) < 0 and hciCommand

    if not (hciCommand or hciStatus) 
      return 0  ' Success

  if hciCommand
    abort hci#E_NO_RESPONSE
  abort hci#E_CMD_FAIL

PRI Server | err
  ' Main loop for the server cog.

  serverCmd~
  repeat
    err := \ServerPoll
    if err < 0
      serverError := err
    
PRI ServerPoll | tmp, bdaddr
  ' Poll all event sources:
  '    - Server Commands
  '    - HCI Events
  '    - ACL Packets

  if serverCmd
    case serverCmd >> 24
  
      C_HCI_Generic:
        ' Generic execution of an HCI command from hub memory.
        ' Parameter is a pointer to: command type word, parameter count byte, params.
        tmp := serverCmd
        hci.CmdBegin(hciCommand := BYTE[tmp] | (BYTE[tmp + 1] << 8))
        repeat BYTE[tmp += 2]  ' Number of params
          hci.Cmd8(BYTE[++tmp])
        hci.CmdSend

      C_HCI_WrScanEnable:
        hci.CmdBegin(hciCommand := hci#CB_WriteScanEnable)
        hci.Cmd8(serverCmd)
        hci.CmdSend

      C_HCI_WrLocalName:
        hci.CmdBegin(hciCommand := hci#CB_WriteLocalName)
        hci.CmdString(serverCmd)
        hci.Cmd8(0)    ' Some devices need a NUL terminator
        hci.CmdSend

      C_HCI_WrLocalClass:
        hci.CmdBegin(hciCommand := hci#CB_WriteClassOfDevice)
        hci.Cmd24(serverCmd)
        hci.CmdSend

      C_HCI_Inquiry:
        hci.CmdBegin(hciCommand := hci#LC_Inquiry)
        hci.Cmd24($9E8B00)       ' LAP
        hci.Cmd8(serverCmd)      ' Duration
        hci.Cmd8(IT_TABLE_SIZE)  ' Max # of responses
        hci.CmdSend

    serverCmd~  ' Server command is now complete

  case \hci.EvtPoll

    hci#EV_CommandComplete:
      hci.Evt8                    ' Number of commands we can send
      if hci.Evt16 == hciCommand  ' Command type 
        hciStatus := hci.Evt8     ' Command status

        ' Take any command-specific actions on receiving a response
        case hciCommand

          hci#CB_Reset:
            aclFragmented~
        
          hci#IP_ReadBDAddr:
            bytemove(@localAddr, hci.EvtBuffer(BDADDR_LEN), BDADDR_LEN)
        
        hciCommand~  ' HCIWait is now complete

    hci#EV_CommandStatus:
      tmp := hci.Evt8             ' Command status
      hci.Evt8                    ' Number of commands we can send
      if hci.Evt16 == hciCommand  ' Command type
        hciStatus := tmp
        hciCommand~  ' HCIWait is now complete

    hci#EV_ConnRequest:
      ' Accept any incoming connection
      hci.CmdBegin(hci#LC_AcceptConnRequest)
      hci.CmdBDADDR(hci.EvtBuffer(BDADDR_LEN))
      hci.Cmd8($00)               ' Try to become the connection master
      hci.CmdSend      
        
    hci#EV_ConnComplete:
      if hci.Evt8 == 0            ' Connection status (0=success)
        tmp := hci.Evt16          ' Connection handle, BDADDR
        NewConnection(tmp, hci.EvtBuffer(BDADDR_LEN))

        ' Allow all packet types
        hci.CmdBegin(hci#LC_ChgConnPacketType)
        hci.Cmd16(tmp)
        hci.Cmd16($CC18)
        hci.CmdSend

    hci#EV_DisconnectionComplete:
      if hci.Evt8 == 0            ' Disconnection status (0=success)
        EndConnection(hci.Evt16)  ' Connection handle

    hci#EV_InquiryComplete:
      inqInProgress~

    hci#EV_InquiryResult:
      StoreInquiryResult

    hci#EV_LinkKeyRequest:
      if tmp := keyring.LookupKey(bdaddr := hci.EvtBuffer(BDADDR_LEN))
        hci.CmdBegin(hci#LC_LinkKeyRequestReply)
        hci.CmdBDADDR(bdaddr)
        repeat keyring#KEY_LEN
          hci.Cmd8(BYTE[tmp++])
      else
        hci.CmdBegin(hci#LC_LinkKeyRequestNegativeReply)
        hci.CmdBDADDR(bdaddr)
      hci.CmdSend

    hci#EV_LinkKeyNotification:
      bdaddr := hci.EvtBuffer(BDADDR_LEN)
      keyring.StoreKey(bdaddr, hci.EvtBuffer(keyring#KEY_LEN))

    hci#EV_PINCodeRequest:
      if tmp := pinCodePtr               
        hci.CmdBegin(hci#LC_PINCodeRequestReply)
        hci.CmdBDADDR(hci.EvtBuffer(BDADDR_LEN))
        hci.Cmd8(pinCodeLen)
        repeat pinCodeLen
          hci.Cmd8(BYTE[tmp++])
        repeat $10 - pinCodeLen
          hci.Cmd8(0)
      else
        hci.CmdBegin(hci#LC_PINCodeRequestNegativeReply)
        hci.CmdBDADDR(hci.EvtBuffer(BDADDR_LEN))
      hci.CmdSend

  repeat while tmp := hci.ACLRead(@aclBuffer, aclFragmented)
    case tmp

      hci#R_FRAGMENTED:
        ' Continuing a fragmented packet. Ties up the ACL buffer until done.
        aclFragmented := 1
        
      hci#R_COMPLETE:
        ' Finished a full packet. Complete it.
        aclFragmented~      
        ACLReceive

  ' Things we can do only when the ACL buffer is free:
  if not aclFragmented
  
    ' Poll for sockets that need to transmit
    tmp := @socketTable
    repeat ST_TABLE_SIZE
      if WORD[tmp] and (BYTE[tmp + ST_FLAGS] & STF_CONNECTED)' Socket bound and connected
        if BYTE[tmp + ST_PORT] & ST_PORT_L2CAP
          ' XXX: L2CAP socket not implemented yet
        else
          RFCOMMSocketPoll(tmp)
      tmp += ST_LEN
        
PRI NewConnection(cid, bdAddr) | ptr
  ' A new incoming connection was established.
  ' Find an unused connection table entry, and initialize it.
  ' If our connection table is full, aborts with E_NO_CONNECTION.

  ptr := ConnectionAddress(0)
  bytemove(ptr, bdAddr, BDADDR_LEN)
  WORD[ptr + CI_CID] := cid

PRI EndConnection(cid) | lcid, ptr
  ' An connection has terminated, and the corresponding CID
  ' is no longer in use.

  bytefill(ConnectionAddress(cid), 0, CI_LEN)
  
  ' Free all L2CAP channels associated with this connection
  repeat lcid from CID_FIRST to CID_LAST
    ptr := L2ChannelPtr(lcid)
    if WORD[ptr] == cid
      L2ChannelFree(lcid)

PRI StoreInquiryResult | numResults, i, ptr
  ' Store the payload of an EV_InquiryResult in the inquiry table.

  ' There can be multiple responses in one event
  numResults := hci.Evt8

  if numResults
    ' Array of BDADDRs
    repeat i from 0 to numResults-1
      bytemove(ptr := DiscoveredAddr(inqCount + i), hci.EvtBuffer(BDADDR_LEN), BDADDR_LEN)

    ' Ignore the Page_Scan_Repetition_Mode and the two Reserved arrays.
    hci.EvtBuffer(numResults * 3)
  
    ' Class array
    repeat i from 0 to numResults-1
      bytemove(DiscoveredAddr(inqCount + i) + IT_CLASS, hci.EvtBuffer(3), 3)

    inqCount += numResults

DAT
'
'
'==============================================================================
' ACL Layer Implementation
'==============================================================================

PRI ACLReceive | cid, len, lcid    
  ' Handle a single received ACL packet from the HCI.
  ' We know that the packet isn't fragmented, and we know
  ' the ACL length and L2CAP lengths are valid.

  ' First word of the ACL header has the connection ID and the ACL flags.
  ' Make sure it's point-to-point, and extract the connection ID itself.
  
  cid := WORD[@aclBuffer + hci#ACL_HANDLE]  
  if cid & hci#ACL_BC_MASK
    abort hci#E_BROADCAST
  cid &= hci#ACL_HANDLE_MASK

  ' Dispatch to a channel-specific L2CAP packet handler
  case lcid := WORD[@aclBuffer + L2CAP_CHANNEL]

    L2CAP_SIG_CHANNEL:
      ' Signalling packet
      L2SignalReceive

    L2CAP_G_CHANNEL:
      ' Connectionless data (Currently unsupported)
      abort hci#E_BAD_CHANNEL

    other:
      ' Connection-oriented channel
      L2ChannelReceive(lcid)

PRI ACLTransmit(aclLen)
  ' Transmit the currently buffered ACL packet.
  ' Only handles point-to-point non-fragmented packets.
  '
  ' Uses the connection ID that's already in the ACL buffer,
  ' but we do set the rest of the ACL header.

  if aclLen > hci#ACL_DATA_LEN
    abort hci#E_FRAGMENTED

  WORD[@aclbuffer + hci#ACL_HANDLE] := ACLGetConnection | hci#ACL_PB_FIRST
  WORD[@aclBuffer + hci#ACL_TOTAL_LEN] := aclLen

  hci.ACLWrite(@aclBuffer, aclLen + hci#ACL_HEADER_LEN)

PRI ACLGetConnection
  ' Return the connection ID for the current ACL packet

  return WORD[@aclBuffer + hci#ACL_HANDLE] & hci#ACL_HANDLE_MASK

DAT
'
'
'==============================================================================
' L2CAP Layer Implementation
'==============================================================================

PRI L2ChannelPtr(lcid)
  ' Return a pointer to the Local Channel Info table row
  ' for a channel with ID "lcid". Validates the range of lcid only.
  
  lcid -= CID_FIRST
  if lcid => LCI_TABLE_SIZE
    abort hci#E_BAD_CHANNEL

  return @lciTable + lcid * LCI_LEN
    
PRI L2ChannelLookupACL(lcid)
  ' Look up and validate an entry in the Local Channel Info table. 
  ' The connection ID must match the current ACL packet.

  result := L2ChannelPtr(lcid)
  if WORD[result] <> ACLGetConnection
    abort hci#E_BAD_CHANNEL

PRI L2ChannelFree(lcid)
  ' Mark an L2CAP channel as unused

  wordfill(L2ChannelPtr(lcid), 0, constant(LCI_LEN / 2))

PRI L2ChannelNewACL(psm, rcid) : lcid | ptr
  ' Allocate a new L2CAP channel,
  ' using the connection ID from the current ACL packet.

  repeat lcid from CID_FIRST to CID_LAST
    ptr := L2ChannelPtr(lcid)
    if not WORD[ptr]
      ' Channel is free.
      WORD[ptr] := ACLGetConnection
      WORD[ptr + LCI_REMOTE_CID] := rcid
      WORD[ptr + LCI_PSM] := psm
      return

  abort hci#E_NO_CHANNELS
 
PRI L2SignalReceive | psm, scid, dcid
  ' Received an L2CAP Signalling packet.
  ' Handle the packet according to its 8-bit code.
  
  case BYTE[@aclBuffer + L2CAP_SIG_CODE]

    L2SIG_EchoRequest:
      L2SignalTransmit(L2SIG_EchoResponse, WORD[@aclBuffer + L2CAP_SIG_LEN])

    L2SIG_InfoRequest:
      WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 2)] := $0001   ' Not supported
      L2SignalTransmit(L2SIG_InfoResponse, 4)

    L2SIG_ConnRequest:
      ' The connection request includes PSM and Source CID for the connection.
      ' We need to respond with a Destination (local) CID. Since we only need
      ' to support one L2 connection for each PSM on a particular device
      ' connection, we derive our Destionation CID from the PSM itself.
      psm := WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 0)]
      scid := WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 2)]
      WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 0)] := L2ChannelNewACL(psm, scid)
      LONG[@aclBuffer + constant(L2CAP_SIG_DATA + 4)] := 0 ' Connection successful
      L2SignalTransmit(L2SIG_ConnResponse, 8)                         

    L2SIG_DisconnRequest:
      dcid := WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 0)]
      L2ChannelLookupACL(dcid)  ' Validate channel for this connection
      L2ChannelFree(dcid)
      L2SignalTransmit(L2SIG_DisconnResponse, 4)
    
    L2SIG_CfgRequest:
      ' Currently this just always returns success without examining the configuration
      dcid := WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 0)]
      scid := WORD[L2ChannelLookupACL(dcid) + LCI_REMOTE_CID]
      WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 0)] := scid
      WORD[@aclBuffer + constant(L2CAP_SIG_DATA + 4)] := $0000 ' Success
      L2SignalTransmit(L2SIG_CfgResponse, 6)
                                                        
      ' To complete configuration, both sides of the connection have to
      ' request configuration. Take this opportunity to send our request
      ' to the other side.
      L2SignalTransmit(L2SIG_CfgRequest, 4)

    L2SIG_CfgResponse:
      ' Ignore the other side's response to our CfgRequest.
     
    other:      
      WORD[@aclBuffer + L2CAP_SIG_DATA] := 0 ' Command not understood
      L2SignalTransmit(L2SIG_CmdReject, 2)       

PRI L2SignalTransmit(type, len)
  ' Send an L2CAP Signalling packet.
  '
  ' Takes the connection ID and Signal ID that are
  ' currently in the buffer, writes all other fields.

  ' Lengths, from inner to outermost
  WORD[@aclBuffer + L2CAP_SIG_LEN] := len
  WORD[@aclBuffer + L2CAP_SIZE] := len += constant(L2CAP_SIG_DATA - L2CAP_SIG_CODE)

  WORD[@aclBuffer + L2CAP_CHANNEL] := L2CAP_SIG_CHANNEL
  BYTE[@aclBuffer + L2CAP_SIG_CODE] := type

  ACLTransmit(len + constant(L2CAP_SIG_CODE - hci#ACL_HEADER_LEN))

PRI L2ChannelReceive(lcid) | channel
  ' Received an L2CAP packet on a connection-oriented channel.
  ' Dispatch it to a connection-specific handler.
  
  channel := L2ChannelLookupACL(lcid)
  case BYTE[channel + LCI_PSM]

    PSM_ServiceDiscovery:
      SDPReceive(channel)

    PSM_RFCOMM:
      RFCOMMReceive(channel)

PRI L2ChannelTransmit(channel, len)
  ' Send an L2CAP connection-oriented packet.
  ' Writes all fields in the L2CAP and ACL header.
                                      
  WORD[@aclBuffer + L2CAP_SIZE] := len
  WORD[@aclBuffer + L2CAP_CHANNEL] := WORD[channel + LCI_REMOTE_CID]

  ACLTransmit(len + constant(L2CAP_SI_DATA - hci#ACL_HEADER_LEN))

DAT
'
'
'==============================================================================
' RFCOMM Layer Implementation
'==============================================================================

PRI RFCOMMReceive(channel) | address, len, ptr, control, txCredits, socket
  ' Handle one incoming L2CAP packet for the RFCOMM PSM.

  ' Check header
  
  address := BYTE[@aclBuffer + RFCOMM_ADDRESS]
  len := BYTE[@aclBuffer + RFCOMM_LEN]

  if (len & address & RFCOMM_EA) == 0                        ' Don't support extended length/address
    abort hci#E_RFCOMM_PROTO
  len >>= RFCOMM_LEN_SHIFT                                   ' Extract 7-bit length field
  if len > RFCOMM_DATA_MAX                                   ' Length too long? Must be fragmented.
    abort hci#E_FRAGMENTED

  address >>= RFCOMM_DLCI_SHIFT                              ' Extract DLCI portion of Address

  ' Handle each ETSI 07.10 frame type
  
  case (control := BYTE[@aclBuffer + RFCOMM_CONTROL]) & RFCOMM_TYPE_MASK
  
    RFCOMM_TYPE_SABM:
      ' Set Asynchronous Balanced Mode (Establish connection)

      if address == 0
        ' MCC Channel. Always acknowledge
        RFCOMMTransmit(channel, constant(RFCOMM_TYPE_UA | RFCOMM_PF), 0, 0)

      elseif \FindBoundSocket(channel, address) > 0
        ' Bound socket
        RFCOMMTransmit(channel, constant(RFCOMM_TYPE_UA | RFCOMM_PF), 0, 0)
        RFCOMMSendMSC(channel, address)
      else
        ' Refuse the connection
        RFCOMMTransmit(channel, constant(RFCOMM_TYPE_DM | RFCOMM_PF), 0, 0)

    RFCOMM_TYPE_DISC:
      ' Disconnect request
      RFCOMMTransmit(channel, constant(RFCOMM_TYPE_UA | RFCOMM_PF), 0, 0)   ' Acknowledge
  
    RFCOMM_TYPE_UIH:
      ' Unnumbered information (data frame).
      
      ' With credit-based flow control, any UIH frame can include a
      ' count of additional transmit credits for us. So we may need
      ' to strip this byte off the beginning of the packet before
      ' passing it on.

      ptr := @aclBuffer + RFCOMM_DATA
      txCredits~
      if control & RFCOMM_PF
        ' Not included in 'len' at the moment.
        txCredits := BYTE[ptr++]

      BYTE[@aclBuffer + RFCOMM_ADDRESS] ^= RFCOMM_CR   ' Flip command/response bit
                                       
      if address == 0
        ' DLCI 0: Multiplexer Control Channel
        RFCOMMReceiveMCC(channel, ptr, len)
      else
        ' Socket data packet

        socket := FindBoundSocket(channel, address)
        BYTE[socket + ST_TX_CREDITS] += txCredits

        if len
          ' Nonzero-length packets use up receive credits
          BYTE[socket + ST_RX_CREDITS]--
          SocketRXWrite(socket, ptr, len)

          ' Immediately see if we should send more flow control tokens.
          ' This happens again periodically, in case another cog frees
          ' up space in the receive ring.
          RFCOMMSocketPoll(socket)

PRI RFCOMMSendMSC(channel, address)
  ' Send a Modem Status MCC Command to an RFCOMM endpoint.
  ' We can send these at any time, but since the modem status
  ' is static, we don't need to. We must send this once, as
  ' the last step of establishing an RFCOMM connection.

  BYTE[@aclBuffer + RFCOMM_ADDRESS] := constant(RFCOMM_EA | RFCOMM_CR) ' DLCI 0
  BYTE[@aclBuffer + RFCOMM_MCC_DATA] := (address << 2) | %11
  BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 1)] := %1000_1101
  RFCOMMTransmitMCC(channel, constant(RFCOMM_MCC_EA | RFCOMM_MCC_CR | RFCOMM_MCCT_MSC), 2)
  
PRI RFCOMMSocketPoll(socket) | rxCredits, txBytes
  ' Poll for action on an RFCOMM socket. Transmits packets and/or issues more RX credits.
  ' Must be called only on RFCOMM sockets which are bound and connected!
  '
  ' It's most important that we do this right after receiving a packet,
  ' but we also poll each socket periodically in order to resolve flow control
  ' blockages after another cog has made space in our RX ring.

  repeat
    rxCredits := (MaxRXCredits(socket) - BYTE[socket + ST_RX_CREDITS]) #> 0
    BYTE[socket + ST_RX_CREDITS] += rxCredits
    BYTE[@aclBuffer + RFCOMM_DATA] := rxCredits
    
    ' Send data only if we have a TX credit available. If so, this consumes a credit.
    if BYTE[socket + ST_TX_CREDITS]
      if txBytes := SocketTXRead(socket, @aclBuffer + constant(RFCOMM_DATA + 1), constant(RFCOMM_DATA_MAX - 2))
        BYTE[socket + ST_TX_CREDITS]--
    else
      txBytes~
    
    if not (rxCredits or txBytes)
      ' No need to send credits or data
      return

    ' Send one UIH packet with credit prefix
    BYTE[@aclBuffer + RFCOMM_ADDRESS] := RFCOMM_EA | (BYTE[socket + ST_PORT] << RFCOMM_DLCI_SHIFT) 
    RFCOMMTransmit(WORD[socket], constant(RFCOMM_PF | RFCOMM_TYPE_UIH), txBytes, txBytes + 1)
    
PRI RFCOMMTransmit(channel, control, reportedLen, actualLen) | crcLen, ptr, crc, b
  ' Send an RFCOMM frame.
  '
  ' Uses address, and data from the ACL buffer.
  ' Sets the lengths, control, and CRC8.
  '
  ' "reportedLen" is the length to report in the RFCOMM header. It does not include
  ' the flow control token byte.
  '
  ' "actualLen" is the actual length of the RFCOMM payload, including all data
  ' bytes but not the CRC.
  

  crcLen := 3
  if (control & RFCOMM_TYPE_MASK) == RFCOMM_TYPE_UIH
    ' Don't include length
    crcLen--

  BYTE[@aclBuffer + RFCOMM_LEN] := RFCOMM_LEN_EA | (reportedLen << RFCOMM_LEN_SHIFT)
  BYTE[@aclBuffer + RFCOMM_CONTROL] := control

  ' Calculate the CRC-8 of a message, using RFCOMM's polynomial (0x07)
  ' and reflection conventions. This is a small-table implementation,
  ' based on the output of pycrc:
  '
  ' pycrc.py --width=8 --poly=07 --xor-in=0xFF --xor-out=0xFF
  '          --reflect-in=1 --reflect-out=1 --generate=c
  '          --table-idx-width=4 --algorithm=table-driven

  crc := $FF
  ptr := @aclBuffer + RFCOMM_ADDRESS
  repeat crcLen
    b := BYTE[ptr++]
    crc := crc8Table[(crc ^ b) & $F] ^ (crc >> 4)
    crc := crc8Table[(crc ^ (b >> 4)) & $F] ^ (crc >> 4)

  BYTE[@aclBuffer + RFCOMM_DATA + actualLen] := crc ^ $FF
  L2ChannelTransmit(channel, actualLen + 4)

DAT

crc8Table byte $00, $1c, $38, $24, $70, $6c, $48, $54
          byte $e0, $fc, $d8, $c4, $90, $8c, $a8, $b4
  
PRI MaxRXCredits(socket) | ring
  ' Calculate how many receive credits we're allowed to have outstanding.
  ' This is based on a lower bound of the remaining socket buffer space,
  ' and the RFCOMM MTU.
  '
  ' May return zero if the other end is not allowed to transmit yet.
  ' If there is no receive socket, this will always return zero.

  if ring := WORD[socket + ST_RX_RING]
    return RingBytesFree(ring) / RFCOMM_MTU

PRI RFCOMMReceiveMCC(channel, ptr, len) | socket
  ' Received a Multiplexer Controll Channel RFCOMM frame

  ' All of our commands end up modifying the received
  ' frame and sending it back. If the received frame wasn't
  ' at the beginning of the packet, we need to put it there.
  ' (This can happen if the UIH frame came with flow control credits prepended.)

  bytemove(@aclBuffer + RFCOMM_MCC_TYPE, ptr, len)

  case BYTE[ptr]

    ' Parameter negotiation command.
    ' This is where we get initial parameters for flow control
    ' and acknowledgment timers, and it gives us an opportunity
    ' to negotiate the MTU down.
    constant(RFCOMM_MCC_EA | RFCOMM_MCC_CR | RFCOMM_MCCT_PN):

      ' First byte: DLCI.
      ' Don't complain if the socket is unsupported, we'll have the opportunity
      ' to reject it when we handle SABM.
      if (socket := \FindBoundSocket(channel, BYTE[@aclBuffer + RFCOMM_MCC_DATA])) > 0
    
        ' RFCOMM completely redefines the CL1-CL4 bits, and uses them to detect
        ' support for credit-based flow control. If and only if these bits are 15
        ' we must set them to 14. We can operate on the whole byte here, since
        ' the other nybble (I1-4) is required to be zero in RFCOMM. 
        if BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 1)] == $F0
          BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 1)] := $E0

          ' Initialize the flow control credits. The peer gives us
          ' an initial TX value, we give our peer the initial RX value.
          BYTE[socket + ST_TX_CREDITS] := BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 7)]

          ' Unconnected until SABM
          BYTE[socket + ST_FLAGS]~
          
          ' Give out some initial flow control credits
          BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 7)] := BYTE[socket + ST_RX_CREDITS] := MaxRXCredits(socket) <# 7

      ' Set the MTU such that we don't need any fragmented ACL or L2CAP packets
      BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 4)] := RFCOMM_MTU
      BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 5)]~
      
      RFCOMMTransmitMCC(channel, constant(RFCOMM_MCC_EA | RFCOMM_MCCT_PN), 8)                  

    ' Modem status command.
    ' Currently we ignore the other end's status, and just reciprocate
    ' with our own hardcoded modem status.
    constant(RFCOMM_MCC_EA | RFCOMM_MCC_CR | RFCOMM_MCCT_MSC):
      BYTE[@aclBuffer + constant(RFCOMM_MCC_DATA + 1)] := %1000_1101

      ' Send MCC response
      RFCOMMTransmitMCC(channel, constant(RFCOMM_MCC_EA | RFCOMM_MCCT_MSC), 2)

    ' Modem status reponse. This is the last step in establishing an inbound connection.
    constant(RFCOMM_MCC_EA | RFCOMM_MCCT_MSC):
      if (socket := \FindBoundSocket(channel, BYTE[@aclBuffer + RFCOMM_MCC_DATA] >> 2)) > 0
        BYTE[socket + ST_FLAGS] |= STF_CONNECTED
    
    ' Remote Port Negotiation.
    ' We need to reply to this, but we mostly ignore it. This is where
    ' we get serial port settings, useful only when RFCOMM is actually
    ' being used for a hardware serial port. Here we just accept any
    ' settings that the peer asks for.
    constant(RFCOMM_MCC_EA | RFCOMM_MCC_CR | RFCOMM_MCCT_RPN):
      RFCOMMTransmitMCC(channel, constant(RFCOMM_MCC_EA | RFCOMM_MCCT_RPN), 8)
     
    ' Anything else: Respond that this is a non-supported command
    other:
      BYTE[@aclBuffer + RFCOMM_MCC_DATA] := BYTE[@aclBuffer + RFCOMM_MCC_TYPE]
      RFCOMMTransmitMCC(channel, constant(RFCOMM_MCC_EA | RFCOMM_MCCT_NSC), 1)                  

PRI RFCOMMTransmitMCC(channel, type, len)
  ' Transmit a Multiplexer Controll Channel RFCOMM frame.
  ' Uses data from the ACL buffer, but sets the type and length;

  BYTE[@aclBuffer + RFCOMM_MCC_TYPE] := type
  BYTE[@aclBuffer + RFCOMM_MCC_LEN] := (len  << RFCOMM_LEN_SHIFT) | RFCOMM_LEN_EA
  len += 2
  RFCOMMTransmit(channel, RFCOMM_TYPE_UIH, len, len)

DAT
'
'
'==============================================================================
' SDP Server
'==============================================================================
'
' Service Discovery Protocol support for the Propeller Bluetooth stack.
'
' I originally started this by writing a fairly complete-looking SDP
' server, with a searchable service record database, DataElement
' decoding and encoding, and a public function to link your own
' new service records into our database.
' 
' But all of that functionality uses a lot of RAM, and hardly any of it
' actually gets used. Of the three transaction types described by SDP,
' I've only seen PCs ever send one of them- and our service records
' should be small enough that we have no real need to support searching
' or filtering them. This SDP server just sends our entire service
' database in response to any attribute request. It sure isn't spec
' compliant, but it should work in practice, and it takes very little
' memory to implement.
'
' We do have a very simple service "database", where callers can add
' new services by providing pointers to buffers full of already-encoded
' SDP protocol data. See the public AddService routine in the
' Initialization section above.

PRI SDPReceive(channel) | len
  ' Handle one incoming SDP Protocol Data Unit (PDU).
  '
  ' There are three ways to request SDP data:
  ' SearchRequest, AttributeRequest, and SearchAttributeRequest.
  ' The latter combines the functionality of the first two.
  '
  ' Windows (Microsoft stack), Linux (BlueZ), and Mac OS all seem
  ' to use the SearchAttributeRequest exclusively. So, to save
  ' memory, that's the only transaction type we implement.
  '
  ' This is a simplified function which *only* handles this single
  ' request type, and only knows how to send back the entire service
  ' database.

  ' This function is a wrapper around the real SDP receiver.
  ' We handle sending the return PDU, and if the real SDP server
  ' fails we'll make it an error.
  '
  ' The returned length is the length of the returned PDU payload.

  if (len := \SDPProcessPDU) =< 0
    ' Error
    len := 2
    BYTE[@aclBuffer + SDPPDU_TYPE] := SDP_ErrorResponse
    WriteBE16(@aclBuffer + SDPPDU_DATA, SE_BadSyntax)

  WriteBE16(@aclBuffer + SDPPDU_SIZE, len)
  L2ChannelTransmit(channel, len + constant(SDPPDU_DATA - L2CAP_SI_DATA))

PRI SDPProcessPDU : len | inPtr, inEnd, outPtr, outEnd, contIn, contOut, service
  ' Internal function to process one incoming SDP Protocol Data Unit.
  ' On error, we can abort or return a non-positive number, and our
  ' caller will send an error response.
  '
  ' Both the incoming and outgoing responses must fit into one
  ' non-fragmented ACL packet.

  if BYTE[@aclBuffer + SDPPDU_TYPE] <> SDP_SearchAttrRequest
    ' Only SearchAttrRequest is supported. All other requests generate an error
    return

  BYTE[@aclBuffer + SDPPDU_TYPE] := SDP_SearchAttrResponse

  ' Handle an SDP ServiceSearchAttributeRequest PDU.
  ' This is equivalent to ServiceSearch and a ServiceAttribute
  ' combined into a single transaction. We're supposed to find
  ' all service records which match the UUID pattern we were given,
  ' then return any listed attributes from those service records.
  '
  ' But we have so little service data (and 99% of the time, clients
  ' want it all anyway) so we cut corners and always send all service
  ' data, regardless of what request actually came in.
  '
  ' The only real SDP protocol feature we support are continuations,
  ' so that we can send more than one MTU's worth of data back.

  ' "Parse" the incoming packet. All we care about is the
  ' continuation data. If it's present, we assume it's 16 bits.
  ' The rest of the packet consists of a UUID list data element,
  ' 2-byte maximum attribute list length, and an attribute ID list
  ' data element. The continuation data is a 1-byte length followed
  ' by server-defined data. For us, this is always a 16-bit value or
  ' nothing at all. 

  inPtr := SkipDE(SkipDE(@aclBuffer + SDPPDU_DATA) + 2)
  if BYTE[inPtr]
    contIn := ReadBE16(inPtr + 1)
  else
    contIn~
  
  outPtr := @aclBuffer + constant(SDPPDU_DATA + 2)          ' Skip list size header
  outEnd := @aclBuffer + constant(hci#ACL_PACKET_SIZE - 3)  ' Leave room for continuation

  ' Before the services proper: Service list header on the first PDU

  if not contIn
    BYTE[outPtr++] := constant(DE_Sequence | DE_Size16)
    WriteBE16(outPtr, svcListSize)
    outPtr += 2  

  ' Now copy each service in the list, skipping bytes we already sent
  
  service := svcListHead
  contOut~

  repeat while service
    inEnd := SkipDE(inPtr := service + 2)
    service := WORD[service]
    
    repeat while inPtr <> inEnd and outPtr <> outEnd
      if contOut++ => contIn
        ' Include this byte
        BYTE[outPtr++] := BYTE[inPtr]
      inPtr++

  ' Write length of this PDU
  WriteBE16(@aclBuffer + SDPPDU_DATA, outPtr - (@aclBuffer + constant(SDPPDU_DATA + 2)))

  ' Do we need a continuation?

  if contOut < svcListSize
    BYTE[outPtr++] := 2
    WriteBE16(outPtr, contOut)
    outPtr += 2     
  else
    BYTE[outPtr++]~

  return outPtr - (@aclBuffer + SDPPDU_DATA)

PRI WriteBE16(ptr, value)
  ' Write a big-endian 16-bit value to unaligned memory
  BYTE[ptr] := value >> 8
  BYTE[ptr+1] := value

PRI ReadBE16(ptr)
  ' Read a big-endian 16-bit value from unaligned memory
  return (BYTE[ptr] << 8) | BYTE[ptr+1]

PRI SkipDE(ptr) | descriptor
  ' Skip past a variable-sized Data Element in an incoming SDP packet.
  ' Returns a pointer to the item after the data element. This does not
  ' do any bounds checking. The worst that will happen is we read some
  ' bogus data instead of correct data- but never use the returned
  ' pointer for writing without validating it first!

  if descriptor := BYTE[ptr++]   ' Nil (0) is a special case
    case descriptor & DE_SIZE
      DE_1Byte:    ptr++
      DE_2Bytes:   ptr += 2
      DE_4Bytes:   ptr += 4
      DE_8Bytes:   ptr += 8
      DE_16Bytes:  ptr += 16
      DE_Size8:    ptr += BYTE[ptr] + 1
      DE_Size16:   ptr += ReadBE16(ptr) + 2
      DE_Size32:   ptr += ReadBE16(ptr + 2) + 4

  return ptr

  
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