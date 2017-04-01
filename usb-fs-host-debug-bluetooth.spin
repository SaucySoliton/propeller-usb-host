{{

usb-fs-host-debug-bluetooth
------------------------------------------------------------------

Debugging wrapper for usb-fs-host, aka the Poor Man's USB Analyzer.
This is a specialized version of usb-fs-host-debug. Instead of dumping
raw USB transfers, we do some decoding of common Bluetooth protocol bits.

Usage:
  In the module(s) you want to debug, temporarily replace the
  "usb-fs-host" OBJ reference with "usb-fs-host-debug-blyetooth".

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.

}}

OBJ
  hc : "usb-fs-host"
  term : "Parallax Serial Terminal"

CON
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

PRI logBegin(name) | timediff
  term.char(term#NL)
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
  repeat while ((now - epoch) => 80_000_000) or ((now - epoch) < 0)
    epoch += 80_000_000
    epochSec++

  term.dec(epochSec)
  term.char(".")
  dec3((now - epoch) / 80_000)

PRI dec3(n)
  ' 3-digit unsigned decimal number, with leading zeroes
  term.char("0" + ((n / 100) // 10))
  term.char("0" + ((n / 10) // 10))
  term.char("0" + (n // 10))

PUB FrameWait(f)
  hc.FrameWait(f)

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
  if req == $0020
    BluetoothCommand(bufferPtr, length)
  else
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

  if result <> E_TIMEOUT
    if length == $10
      BluetoothEvent(buffer, length)
    elseif length == $40
      BluetoothACLRead(buffer, length)
    else
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
  BluetoothACLWrite(buffer, length)

  result := \logStatus(\hc.BulkWrite(epd, buffer, length))
  hexDump(buffer, length)
  if result < 0
    abort

PUB BulkRead(epd, buffer, length) : actual
  BluetoothEventCont(buffer, length)

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
''
''
''==============================================================================
'' Bluetooth Decoding
''==============================================================================

PRI BluetoothCommand(buf, length)
  logBegin(string("Command"))
  term.str(findName(@commandNameTable, UWORD(buf)))

PRI BluetoothEvent(buf, length)
  logBegin(string("Event"))
  term.str(findName(@eventNameTable, BYTE[buf]))

PRI BluetoothEventCont(buffer, length)
  logBegin(string("Event... "))

PRI BluetoothACLWrite(buf, length)
  logBegin(string("ACL Write"))
  BluetoothACL(buf, length)

PRI BluetoothACLRead(buf, length)
  logBegin(string("ACL  Read"))
  BluetoothACL(buf, length)

PRI BluetoothACL(buf, length) | channel, type, name, len
  term.str(string("conn="))
  term.hex(UWORD(buf), 4)
  logComma

  term.str(string("l2chan="))
  term.hex(channel := UWORD(buf + 6), 4)
  logComma

  if channel == 1
    ' L2CAP Signalling packet
    term.str(findName(@l2SigTable, BYTE[buf + 8]))
    logComma

  else
    ' See if it looks like RFCOMM (we don't track which PSM this is...)
    type := BYTE[buf + 9] & $EF
    name := findName(@rfcommTypeTable, type)
    if BYTE[name]
      ' Assume RFCOMM

      term.str(string("rfchan="))
      term.hex(channel := (BYTE[buf + 8] >> 2), 2)
      if BYTE[buf + 8] & 1
        term.str(string(" EA"))
      if BYTE[buf + 8] & 2
        term.str(string(" CR"))
      logComma

      if BYTE[buf + 9] & $10
        term.str(string("PF "))
      term.str(name)
      logComma

      len := BYTE[buf + 10] >> 1
      term.str(string("len="))
      term.hex(len, 2)
      logComma

      ' Multiplexer Control Channel UIH data
      if channel == 0 and type == $EF and len > 1
        type := BYTE[buf + $B]
        name := findName(@rfcommMCCTable, type & $FC)
        if name
          term.str(name)
          if type & 1
            term.str(string(" EA"))
          if type & 2
            term.str(string(" CR"))
        logComma

PRI findName(table, value) : str | index
  ' Look up a string from a name table

  str := table
  repeat
    index := UWORD(str)
    str += 2
    if index == value or BYTE[str] == 0
      return
    repeat while BYTE[str]
      str++
    str++

DAT

rfcommMCCTable
 byte $80, $00, "MCCT_PN", 0
 byte $40, $00, "MCCT_PSC", 0
 byte $C0, $00, "MCCT_CLD", 0
 byte $20, $00, "MCCT_TEST", 0
 byte $A0, $00, "MCCT_FCOn", 0
 byte $60, $00, "MCCT_FCOff", 0
 byte $E0, $00, "MCCT_MSC", 0
 byte $10, $00, "MCCT_NSC", 0
 byte $90, $00, "MCCT_RPN", 0
 byte $50, $00, "MCCT_RLS", 0
 byte $D0, $00, "MCCT_SNC", 0
 byte 0, 0, 0

rfcommTypeTable
 byte $2F, $00, "RFCOMM_SABM", 0
 byte $63, $00, "RFCOMM_UA", 0
 byte $0F, $00, "RFCOMM_DM", 0
 byte $43, $00, "RFCOMM_DISC", 0
 byte $EF, $00, "RFCOMM_UIH", 0
 byte 0, 0, 0

l2SigTable
 byte $01, $00, "L2SIG_CmdReject", 0
 byte $02, $00, "L2SIG_ConnRequest", 0
 byte $03, $00, "L2SIG_ConnResponse", 0
 byte $04, $00, "L2SIG_CfgRequest", 0
 byte $05, $00, "L2SIG_CfgResponse", 0
 byte $06, $00, "L2SIG_DisconnRequest", 0
 byte $07, $00, "L2SIG_DisconnResponse", 0
 byte $08, $00, "L2SIG_EchoRequest", 0
 byte $09, $00, "L2SIG_EchoResponse", 0
 byte $0A, $00, "L2SIG_InfoRequest", 0
 byte $0B, $00, "L2SIG_InfoResponse", 0
 byte 0, 0, 0

commandNameTable
 byte $01, $04, "LC_Inquiry", 0
 byte $02, $04, "LC_InquiryCancel", 0
 byte $03, $04, "LC_PeriodicInquiryMode", 0
 byte $04, $04, "LC_ExitPeriodicInquiryMode", 0
 byte $05, $04, "LC_CreateConn", 0
 byte $06, $04, "LC_Disconnect", 0
 byte $08, $04, "LC_CreateConnCancel", 0
 byte $09, $04, "LC_AcceptConnRequest", 0
 byte $0a, $04, "LC_RejectConnRequest", 0
 byte $0b, $04, "LC_LinkKeyRequestReply", 0
 byte $0c, $04, "LC_LinkKeyRequestNegativeReply", 0
 byte $0d, $04, "LC_PINCodeRequestReply", 0
 byte $0e, $04, "LC_PINCodeRequestNegativeReply", 0
 byte $0f, $04, "LC_ChgConnPacketType", 0
 byte $11, $04, "LC_AuthenticationRequested", 0
 byte $13, $04, "LC_SetConnEncryption", 0
 byte $15, $04, "LC_ChgConnLinkKey", 0
 byte $17, $04, "LC_MasterLinkKey", 0
 byte $19, $04, "LC_RemNameRequest", 0
 byte $1a, $04, "LC_RemNameRequestCancel", 0
 byte $1b, $04, "LC_ReadRemFeatures", 0
 byte $1c, $04, "LC_ReadRemExtFeatures", 0
 byte $1d, $04, "LC_ReadRemVersion", 0
 byte $1f, $04, "LC_ReadClockOffset", 0
 byte $20, $04, "LC_ReadLMPHandle", 0
 byte $28, $04, "LC_SetupSyncConn", 0
 byte $29, $04, "LC_AcceptSyncConnRequest", 0
 byte $2a, $04, "LC_RejectSyncConnRequest", 0
 byte $01, $08, "LP_HoldMode", 0
 byte $03, $08, "LP_SniffMode", 0
 byte $04, $08, "LP_ExitSniffMode", 0
 byte $05, $08, "LP_ParkState", 0
 byte $06, $08, "LP_ExitParkState", 0
 byte $07, $08, "LP_QoSSetup", 0
 byte $09, $08, "LP_RoleDiscovery", 0
 byte $0b, $08, "LP_SwitchRole", 0
 byte $0c, $08, "LP_ReadLPSettings", 0
 byte $0d, $08, "LP_WriteLPSettings", 0
 byte $0e, $08, "LP_ReadDefaultLPSettings", 0
 byte $0f, $08, "LP_WriteDefaultLPSettings", 0
 byte $10, $08, "LP_FlowSpec", 0
 byte $01, $0c, "CB_SetEventMask", 0
 byte $03, $0c, "CB_Reset", 0
 byte $05, $0c, "CB_SetEventFilter", 0
 byte $08, $0c, "CB_Flush", 0
 byte $09, $0c, "CB_ReadPINType", 0
 byte $0a, $0c, "CB_WritePINType", 0
 byte $0b, $0c, "CB_CreateNewUnitKey", 0
 byte $0d, $0c, "CB_ReadStoredLinkKey", 0
 byte $11, $0c, "CB_WriteStoredLinkKey", 0
 byte $12, $0c, "CB_DeleteStoredLinkKey", 0
 byte $13, $0c, "CB_WriteLocalName", 0
 byte $14, $0c, "CB_ReadLocalName", 0
 byte $15, $0c, "CB_ReadConnAcceptTimeout", 0
 byte $16, $0c, "CB_WriteConnAcceptTimeout", 0
 byte $17, $0c, "CB_ReadPageTimeout", 0
 byte $18, $0c, "CB_WritePageTimeout", 0
 byte $19, $0c, "CB_ReadScanEnable", 0
 byte $1a, $0c, "CB_WriteScanEnable", 0
 byte $1b, $0c, "CB_ReadPageScanActivity", 0
 byte $1c, $0c, "CB_WritePageScanActivity", 0
 byte $1d, $0c, "CB_ReadInquiryScanActivity", 0
 byte $1e, $0c, "CB_WriteInquiryScanActivity", 0
 byte $1f, $0c, "CB_ReadAuthenticationEnable", 0
 byte $20, $0c, "CB_WriteAuthenticationEnable", 0
 byte $21, $0c, "CB_ReadEncryptionMode", 0
 byte $22, $0c, "CB_WriteEncryptionMode", 0
 byte $23, $0c, "CB_ReadClassOfDevice", 0
 byte $24, $0c, "CB_WriteClassOfDevice", 0
 byte $25, $0c, "CB_ReadVoiceSetting", 0
 byte $26, $0c, "CB_WriteVoiceSetting", 0
 byte $27, $0c, "CB_ReadAutomaticFlushTimeout", 0
 byte $28, $0c, "CB_WriteAutomaticFlushTimeout", 0
 byte $29, $0c, "CB_ReadNumBroadcastTrans", 0
 byte $2a, $0c, "CB_WriteNumBroadcastTrans", 0
 byte $2b, $0c, "CB_ReadHoldModeActivity", 0
 byte $2c, $0c, "CB_WriteHoldModeActivity", 0
 byte $2d, $0c, "CB_ReadTransmitPowerLevel", 0
 byte $2e, $0c, "CB_ReadSyncFlowControlEnable", 0
 byte $2f, $0c, "CB_WriteSyncFlowControlEnable", 0
 byte $31, $0c, "CB_SetCtrlToHostFlowControl", 0
 byte $33, $0c, "CB_HostBufferSize", 0
 byte $35, $0c, "CB_HostNumCompletedPackets", 0
 byte $36, $0c, "CB_ReadLinkSupervisionTimeout", 0
 byte $37, $0c, "CB_WriteLinkSupervisionTimeout", 0
 byte $38, $0c, "CB_ReadNumSupportedIAC", 0
 byte $39, $0c, "CB_ReadCurrentIACLAP", 0
 byte $3a, $0c, "CB_WriteCurrentIACLAP", 0
 byte $3b, $0c, "CB_ReadPageScanPeriodMode", 0
 byte $3c, $0c, "CB_WritePageScanPeriodMode", 0
 byte $3f, $0c, "CB_SetAFHHostChannelClass", 0
 byte $42, $0c, "CB_ReadInquiryScanType", 0
 byte $43, $0c, "CB_WriteInquiryScanType", 0
 byte $44, $0c, "CB_ReadInquiryMode", 0
 byte $45, $0c, "CB_WriteInquiryMode", 0
 byte $46, $0c, "CB_ReadPageScanType", 0
 byte $47, $0c, "CB_WritePageScanType", 0
 byte $48, $0c, "CB_ReadAFHChannelAssignMode", 0
 byte $49, $0c, "CB_WriteAFHChannelAssignMode", 0
 byte $01, $10, "IP_ReadLocalVersion", 0
 byte $02, $10, "IP_ReadLocalSupportedCommands", 0
 byte $03, $10, "IP_ReadLocalFeatures", 0
 byte $04, $10, "IP_ReadLocalExtFeatures", 0
 byte $05, $10, "IP_ReadBufferSize", 0
 byte $09, $10, "IP_ReadBDAddr", 0
 byte $01, $14, "SP_ReadFailedContactCounter", 0
 byte $02, $14, "SP_ResetFailedContactCounter", 0
 byte $03, $14, "SP_ReadLinkQuality", 0
 byte $05, $14, "SP_ReadRSSI", 0
 byte $06, $14, "SP_ReadAFHChannelMap", 0
 byte $07, $14, "SP_ReadClock", 0
 byte $01, $18, "Test_ReadLoopbackMode", 0
 byte $02, $18, "Test_WriteLoopbackMode", 0
 byte $03, $18, "Test_EnableDeviceUnderTestMode", 0
 byte $01, $04, "LC_Inquiry", 0
 byte $02, $04, "LC_InquiryCancel", 0
 byte $03, $04, "LC_PeriodicInquiryMode", 0
 byte $04, $04, "LC_ExitPeriodicInquiryMode", 0
 byte $05, $04, "LC_CreateConn", 0
 byte $06, $04, "LC_Disconnect", 0
 byte $08, $04, "LC_CreateConnCancel", 0
 byte $09, $04, "LC_AcceptConnRequest", 0
 byte $0a, $04, "LC_RejectConnRequest", 0
 byte $0b, $04, "LC_LinkKeyRequestReply", 0
 byte $0c, $04, "LC_LinkKeyRequestNegativeReply", 0
 byte $0d, $04, "LC_PINCodeRequestReply", 0
 byte $0e, $04, "LC_PINCodeRequestNegativeReply", 0
 byte $0f, $04, "LC_ChgConnPacketType", 0
 byte $11, $04, "LC_AuthenticationRequested", 0
 byte $13, $04, "LC_SetConnEncryption", 0
 byte $15, $04, "LC_ChgConnLinkKey", 0
 byte $17, $04, "LC_MasterLinkKey", 0
 byte $19, $04, "LC_RemNameRequest", 0
 byte $1a, $04, "LC_RemNameRequestCancel", 0
 byte $1b, $04, "LC_ReadRemFeatures", 0
 byte $1c, $04, "LC_ReadRemExtFeatures", 0
 byte $1d, $04, "LC_ReadRemVersion", 0
 byte $1f, $04, "LC_ReadClockOffset", 0
 byte $20, $04, "LC_ReadLMPHandle", 0
 byte $28, $04, "LC_SetupSyncConn", 0
 byte $29, $04, "LC_AcceptSyncConnRequest", 0
 byte $2a, $04, "LC_RejectSyncConnRequest", 0
 byte $01, $08, "LP_HoldMode", 0
 byte $03, $08, "LP_SniffMode", 0
 byte $04, $08, "LP_ExitSniffMode", 0
 byte $05, $08, "LP_ParkState", 0
 byte $06, $08, "LP_ExitParkState", 0
 byte $07, $08, "LP_QoSSetup", 0
 byte $09, $08, "LP_RoleDiscovery", 0
 byte $0b, $08, "LP_SwitchRole", 0
 byte $0c, $08, "LP_ReadLPSettings", 0
 byte $0d, $08, "LP_WriteLPSettings", 0
 byte $0e, $08, "LP_ReadDefaultLPSettings", 0
 byte $0f, $08, "LP_WriteDefaultLPSettings", 0
 byte $10, $08, "LP_FlowSpec", 0
 byte $01, $0c, "CB_SetEventMask", 0
 byte $03, $0c, "CB_Reset", 0
 byte $05, $0c, "CB_SetEventFilter", 0
 byte $08, $0c, "CB_Flush", 0
 byte $09, $0c, "CB_ReadPINType", 0
 byte $0a, $0c, "CB_WritePINType", 0
 byte $0b, $0c, "CB_CreateNewUnitKey", 0
 byte $0d, $0c, "CB_ReadStoredLinkKey", 0
 byte $11, $0c, "CB_WriteStoredLinkKey", 0
 byte $12, $0c, "CB_DeleteStoredLinkKey", 0
 byte $13, $0c, "CB_WriteLocalName", 0
 byte $14, $0c, "CB_ReadLocalName", 0
 byte $15, $0c, "CB_ReadConnAcceptTimeout", 0
 byte $16, $0c, "CB_WriteConnAcceptTimeout", 0
 byte $17, $0c, "CB_ReadPageTimeout", 0
 byte $18, $0c, "CB_WritePageTimeout", 0
 byte $19, $0c, "CB_ReadScanEnable", 0
 byte $1a, $0c, "CB_WriteScanEnable", 0
 byte $1b, $0c, "CB_ReadPageScanActivity", 0
 byte $1c, $0c, "CB_WritePageScanActivity", 0
 byte $1d, $0c, "CB_ReadInquiryScanActivity", 0
 byte $1e, $0c, "CB_WriteInquiryScanActivity", 0
 byte $1f, $0c, "CB_ReadAuthenticationEnable", 0
 byte $20, $0c, "CB_WriteAuthenticationEnable", 0
 byte $21, $0c, "CB_ReadEncryptionMode", 0
 byte $22, $0c, "CB_WriteEncryptionMode", 0
 byte $23, $0c, "CB_ReadClassOfDevice", 0
 byte $24, $0c, "CB_WriteClassOfDevice", 0
 byte $25, $0c, "CB_ReadVoiceSetting", 0
 byte $26, $0c, "CB_WriteVoiceSetting", 0
 byte $27, $0c, "CB_ReadAutomaticFlushTimeout", 0
 byte $28, $0c, "CB_WriteAutomaticFlushTimeout", 0
 byte $29, $0c, "CB_ReadNumBroadcastTrans", 0
 byte $2a, $0c, "CB_WriteNumBroadcastTrans", 0
 byte $2b, $0c, "CB_ReadHoldModeActivity", 0
 byte $2c, $0c, "CB_WriteHoldModeActivity", 0
 byte $2d, $0c, "CB_ReadTransmitPowerLevel", 0
 byte $2e, $0c, "CB_ReadSyncFlowControlEnable", 0
 byte $2f, $0c, "CB_WriteSyncFlowControlEnable", 0
 byte $31, $0c, "CB_SetCtrlToHostFlowControl", 0
 byte $33, $0c, "CB_HostBufferSize", 0
 byte $35, $0c, "CB_HostNumCompletedPackets", 0
 byte $36, $0c, "CB_ReadLinkSupervisionTimeout", 0
 byte $37, $0c, "CB_WriteLinkSupervisionTimeout", 0
 byte $38, $0c, "CB_ReadNumSupportedIAC", 0
 byte $39, $0c, "CB_ReadCurrentIACLAP", 0
 byte $3a, $0c, "CB_WriteCurrentIACLAP", 0
 byte $3b, $0c, "CB_ReadPageScanPeriodMode", 0
 byte $3c, $0c, "CB_WritePageScanPeriodMode", 0
 byte $3f, $0c, "CB_SetAFHHostChannelClass", 0
 byte $42, $0c, "CB_ReadInquiryScanType", 0
 byte $43, $0c, "CB_WriteInquiryScanType", 0
 byte $44, $0c, "CB_ReadInquiryMode", 0
 byte $45, $0c, "CB_WriteInquiryMode", 0
 byte $46, $0c, "CB_ReadPageScanType", 0
 byte $47, $0c, "CB_WritePageScanType", 0
 byte $48, $0c, "CB_ReadAFHChannelAssignMode", 0
 byte $49, $0c, "CB_WriteAFHChannelAssignMode", 0
 byte $01, $10, "IP_ReadLocalVersion", 0
 byte $02, $10, "IP_ReadLocalSupportedCommands", 0
 byte $03, $10, "IP_ReadLocalFeatures", 0
 byte $04, $10, "IP_ReadLocalExtFeatures", 0
 byte $05, $10, "IP_ReadBufferSize", 0
 byte $09, $10, "IP_ReadBDAddr", 0
 byte $01, $14, "SP_ReadFailedContactCounter", 0
 byte $02, $14, "SP_ResetFailedContactCounter", 0
 byte $03, $14, "SP_ReadLinkQuality", 0
 byte $05, $14, "SP_ReadRSSI", 0
 byte $06, $14, "SP_ReadAFHChannelMap", 0
 byte $07, $14, "SP_ReadClock", 0
 byte $01, $18, "Test_ReadLoopbackMode", 0
 byte $02, $18, "Test_WriteLoopbackMode", 0
 byte $03, $18, "Test_EnableDeviceUnderTestMode", 0
 byte 0, 0, 0

eventNameTable
 byte $01, $00, "EV_InquiryComplete", 0
 byte $02, $00, "EV_InquiryResult", 0
 byte $03, $00, "EV_ConnComplete", 0
 byte $04, $00, "EV_ConnRequest", 0
 byte $05, $00, "EV_DisconnectionComplete", 0
 byte $06, $00, "EV_AuthenticationComplete", 0
 byte $07, $00, "EV_RemNameRequestComplete", 0
 byte $08, $00, "EV_EncryptionChg", 0
 byte $09, $00, "EV_ChgConnLinkKeyComplete", 0
 byte $0a, $00, "EV_MasterLinkKeyComplete", 0
 byte $0b, $00, "EV_ReadRemFeaturesComplete", 0
 byte $0c, $00, "EV_ReadRemVersionComplete", 0
 byte $0d, $00, "EV_QoSSetupComplete", 0
 byte $0e, $00, "EV_CommandComplete", 0
 byte $0f, $00, "EV_CommandStatus", 0
 byte $10, $00, "EV_HardwareError", 0
 byte $11, $00, "EV_FlushOccurred", 0
 byte $12, $00, "EV_RoleChg", 0
 byte $13, $00, "EV_NumberofCompletedPackets", 0
 byte $14, $00, "EV_ModeChg", 0
 byte $15, $00, "EV_ReturnLinkKeys", 0
 byte $16, $00, "EV_PINCodeRequest", 0
 byte $17, $00, "EV_LinkKeyRequest", 0
 byte $18, $00, "EV_LinkKeyNotification", 0
 byte $19, $00, "EV_LoopbackCommand", 0
 byte $1a, $00, "EV_DataBufferOverflow", 0
 byte $1b, $00, "EV_MaxSlotsChg", 0
 byte $1c, $00, "EV_ReadClockOffsetComplete", 0
 byte $1d, $00, "EV_ConnPacketTypeChgd", 0
 byte $1e, $00, "EV_QoSViolation", 0
 byte $20, $00, "EV_PageScanRepetitionModeChg", 0
 byte $21, $00, "EV_HCIFlowSpecComplete", 0
 byte $22, $00, "EV_InquiryResultWithRSSI", 0
 byte $23, $00, "EV_ReadRemExtFeaturesComplete", 0
 byte $2c, $00, "EV_SyncConnComplete", 0
 byte $2d, $00, "EV_SyncConnChgd", 0
 byte 0, 0, 0

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
