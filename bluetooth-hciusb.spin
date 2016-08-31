{{

bluetooth-hciusb
------------------------------------------------------------------

USB Bluetooth HCI driver for the Parallax Propeller.

You can use this module directly if you'd like low-level access to the
Bluetooth adapter, but this module does not provide any support for
higher-level protocols like SDP, L2CAP, and RFCOMM. Those protocols
are implemented by the companion bluetooth-host.spin object.

This implements the low-level Bluetooth Host Controller Interface (HCI)
using the USB transport, via the software USB host controller object.
See usb-fs-host.spin for information on attaching USB device hardware
to the Propeller.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.

}}

OBJ
'  hc : "usb-fs-host-debug-bluetooth"
  hc : "usb-fs-host"

CON
  ' Negative error codes. Most functions in this library can call
  ' "abort" with one of these codes. The range from -100 to -150 is
  ' reserved for device drivers. (See usb-fs-host.spin)

  E_SUCCESS       = 0
  E_NOT_BLUETOOTH = -100        ' Not a Bluetooth USB device
  E_NO_ENDPOINT   = -101        ' Couldn't find all required endpoints
  E_INVALID_EVT   = -102        ' Malformed event header
  E_SHORT_EVT     = -103        ' Event response ended too soon
  E_NO_RESPONSE   = -105        ' The device didn't respond to an HCI command
  E_CMD_MISMATCH  = -106        ' Command completion didn't match command
  E_CMD_FAIL      = -107        ' Command returned unsuccessful status
  E_OUT_OF_COGS   = -108        ' No more cogs for the Bluetooth stack
  E_NO_CONNECTION = -109        ' Connection doesn't exist
  E_BROADCAST     = -110        ' Unsupported broadcast packet
  E_FRAGMENTED    = -111        ' Unsupported fragmented packet
  E_BAD_CHANNEL   = -112        ' Bad L2CAP channel
  E_NO_CHANNELS   = -113        ' Out of L2CAP channels
  E_RFCOMM_PROTO  = -114        ' Bad or unsupported RFCOMM frame
  E_NO_SOCKET     = -115        ' Out of sockets / Can't find matching socket
  E_ACL_LEN       = -116        ' ACL length mismatch error
  E_ACL_SYNC      = -117        ' Mismatched first/continuation ACL packets

  ' Non-error result codes

  R_NONE          = 0           ' No result
  R_COMPLETE      = 1           ' Received a complete packet
  R_FRAGMENTED    = 2           ' Received part of a fragmented packet

  ' Bluetooth USB HCI class constants

  CLASS_WIRELESS   = $E0
  SUBCLASS_RF      = $01
  PROTOCOL_BT      = $01

  ' Note: Both the command and event buffer sizes should be 256,
  ' to handle the maximum command and event lengths. But in practice,
  ' that's a lot more buffer space than we'll ever need. These smaller
  ' buffer sizes should work for everything except particularly long
  ' device names.

  MAX_CMD_SIZE     = 64
  MAX_EVT_SIZE     = 64

  MAX_CMD_PARAMS   = MAX_CMD_SIZE - 3
  MAX_EVT_PARAMS   = MAX_EVT_SIZE - 2
  EVT_PACKET_SIZE  = 16
  REQ_COMMAND      = $0020
  BDADDR_LEN       = 6

  ' HCI-specified ACL Header on received/transmitted packets

  ACL_HANDLE       = 0          ' Connection handle and status field
  ACL_TOTAL_LEN    = 2          ' Total length field
  ACL_HEADER_LEN   = 4          ' Header is 4 bytes per packet

  ACL_PACKET_SIZE  = 64
  ACL_DATA_LEN     = ACL_PACKET_SIZE - ACL_HEADER_LEN

  ACL_HANDLE_MASK  = $0FFF

  ACL_PB_MASK      = %11 << 12  ' Packet Boundary flag
  ACL_PB_CONT      = %01 << 12
  ACL_PB_FIRST     = %10 << 12

  ACL_BC_MASK      = %11 << 14  ' Broadcast flag
  ACL_BC_PTP       = %00 << 14  ' (Point to point = 0)
  ACL_BC_NONPARK   = %01 << 14
  ACL_BC_PARK      = %10 << 14

  ' Technically this layer shouldn't know about L2CAP, but we
  ' snoop into the L2CAP header a bit so we know the total length
  ' of fragmented ACL packets.

  L2CAP_LEN        = ACL_HEADER_LEN
  L2CAP_HEADER_LEN = ACL_HEADER_LEN + 4

DAT

intrIn                  word    0
bulkIn                  word    0
bulkOut                 word    0
evtPointer              word    0

' HCI Command Buffer
hciCommand
cmdOpcode               word    0
cmdNumParams            byte    0
cmdParams               byte    0[MAX_CMD_PARAMS]

' HCI Event Buffer
hciEvent
evtOpcode               byte    0
evtNumParams            byte    0
evtParams               byte    0[MAX_EVT_PARAMS]

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

PUB Identify | ifp

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

  ifp := hc.FindInterface(CLASS_WIRELESS)
  return ifp and BYTE[ifp + hc#IFDESC_bInterfaceSubClass] == SUBCLASS_RF and BYTE[ifp + hc#IFDESC_bInterfaceProtocol] == PROTOCOL_BT

PUB Init | epd

  '' (Re)initialize this driver. This must be called after Enumerate
  '' and Identify are both run successfully. All three functions must be
  '' called again if the device disconnects and reconnects, or if it is
  '' power-cycled.
  ''
  '' This function does communicate with the device, so it may abort with
  '' any driver or host controller error code.

  epd := hc.FindInterface(CLASS_WIRELESS)
  if not Identify
    abort E_NOT_BLUETOOTH

  ' Locate the device's bulk IN/OUT and interrupt IN endpoints

  bulkIn~
  bulkOut~
  intrIn~

  repeat while epd := hc.NextEndpoint(epd)
    case hc.EndpointType(epd)
      hc#TT_BULK:
        if hc.EndpointDirection(epd) == hc#DIR_IN
          bulkIn := epd
        else
          bulkOut := epd
      hc#TT_INTERRUPT:
        if hc.EndpointDirection(epd) == hc#DIR_IN
          intrIn := epd

  if not (bulkIn and bulkOut and intrIn)
    abort E_NO_ENDPOINT

  hc.Configure

DAT
''
''==============================================================================
'' ACL Packet Interface
''==============================================================================

PUB ACLWrite(buffer, len)
  '' Write an ACL packet or packet fragment.
  '' The supplied buffer and length must already include the HCI ACL header.

  hc.BulkWrite(bulkOut, buffer, len)

PUB ACLRead(buffer, continue) | chunk, chunkLen, chunkHandle, remaining, savedBytes
  '' Poll for the first part of an ACL packet.
  '' The buffer must always be ACL_PACKET_SIZE bytes.
  ''
  '' Returns R_NONE, R_COMPLETE, or R_FRAGMENTED on success.
  '' If the header is invalid or we have a USB error, aborts.
  ''
  '' If continue=0, expects to see the first part of a fragmented
  '' packet. If continue=1, expects to see subsequent parts.
  ''
  '' We set our MTUs so as to avoid fragmented ACL packets, but it seems
  '' that some Bluetooth controllers like to send them on rare occasion
  '' anyway. So we handle them, but this is very much optimized for low
  '' memory rather than high speed. We receive them in-place in the ACL
  '' buffer, so that we don't need a separate reassembly buffer.
  ''
  '' This routine is also responsible for validating the header of
  '' received ACL packets. If we return successfully, the caller can
  '' rely on the ACL packet length to be sane.

  remaining := ACL_PACKET_SIZE
  chunk := buffer

  if continue
    ' If we're continuing, receive the additional data in-place.
    ' Temporarily overwrite the last 4 bytes of the previous chunk
    ' with this chunk's ACL header.

    remaining -= WORD[buffer + ACL_TOTAL_LEN]
    chunk += WORD[buffer + ACL_TOTAL_LEN]

    if remaining =< 0
      ' Packet is too long for our buffer
      abort E_FRAGMENTED

    bytemove(@savedBytes, chunk, ACL_HEADER_LEN)

  result := \hc.InterruptRead(bulkIn, chunk, remaining)

  ' Immediately restore saved bytes, before we have any chances to return.
  chunkLen := hc.UWORD(chunk + ACL_TOTAL_LEN)
  chunkHandle := hc.UWORD(chunk + ACL_HANDLE)

  if continue
    bytemove(chunk, @savedBytes, ACL_HEADER_LEN)

  if result == hc#E_TIMEOUT or result == 0
    ' No data ready.
    ' Also: Ignore zero-length packets. We'll see one here if a
    ' previous non-fragmented ACL packet was exactly the same
    ' length as the USB max packet size.
    return R_NONE

  if result < 0
    ' Other receive error
    abort

  if result < ACL_HEADER_LEN
    ' Too short!
    abort E_ACL_LEN

  if (chunkLen + ACL_HEADER_LEN) <> result
    ' ACL header length doesn't match USB packet length.
    ' Note that "ACL_TOTAL_LEN" isn't the total after packet
    ' assembly, that's only in the L2CAP header.
    abort E_ACL_LEN

  if (chunkHandle & ACL_PB_MASK) <> lookupz(continue: ACL_PB_FIRST, ACL_PB_CONT)
    ' Out of sync: This wasn't the first packet, it was a continuation
    abort E_ACL_SYNC

  if continue
    ' If this was a continuation, put the saved bytes back and update
    ' the total ACL packet length.

    WORD[buffer + ACL_TOTAL_LEN] += chunkLen

  ' Is it complete yet?
  if WORD[buffer + L2CAP_LEN] + constant(L2CAP_HEADER_LEN - ACL_HEADER_LEN) == WORD[buffer + ACL_TOTAL_LEN]
    return R_COMPLETE
  return R_FRAGMENTED

DAT
''
''==============================================================================
'' HCI Command Interface
''==============================================================================

PUB CmdBegin(opcode)
  '' Begin a new HCI command, with the specified opcode. The command
  '' starts out with no parameters.

  cmdOpcode := opcode
  cmdNumParams~

PUB Cmd8(b)
  '' Append a one-byte parameter to the current HCI command

  cmdNumParams <#= constant(MAX_CMD_PARAMS - 1)
  cmdParams[cmdNumParams++] := b

PUB Cmd16(w)
  '' Append a two-byte parameter to the current HCI command

  Cmd8(w)
  Cmd8(w >> 8)

PUB Cmd24(t)
  '' Append a three-byte parameter to the current HCI command

  Cmd16(t)
  Cmd8(t >> 16)

PUB Cmd32(l)
  '' Append a four-byte parameter to the current HCI command

  Cmd16(l)
  Cmd16(l >> 16)

PUB CmdString(str)
  '' Append a zero-terminated string to the current HCI command

  repeat strsize(str)
    Cmd8(BYTE[str++])

PUB CmdBDADDR(ptr)
  '' Append a bluetooth address to the current HCI command

  repeat BDADDR_LEN
    Cmd8(BYTE[ptr++])

PUB CmdSend
  '' Send the current HCI command.
  '' This does not disturb the contents of the command buffer,
  '' so it's possible to re-send the same command if necessary.

  hc.ControlWrite(REQ_COMMAND, 0, 0, @hciCommand, 3 + cmdNumParams)

''
''==============================================================================
'' HCI Event Interface
''==============================================================================

PUB EvtPoll | retval, length
  '' Check whether there is an HCI Event ready.
  '' If so, receive the whole event and return the event opcode.
  '' The parameters will be waiting in the event buffer.
  ''
  '' If no event is ready, returns 0.

  ' Don't poll faster than once per USB frame
  hc.FrameWait(1)

  evtPointer := @evtParams

  ' Poll for exactly one packet. This tells us how big the event is.
  retval := \hc.InterruptRead(intrIn, @hciEvent, EVT_PACKET_SIZE)
  if retval == hc#E_TIMEOUT
    return 0
  elseif retval == hc#E_PID
    ' XXX: Where are these coming from?
    return 0
  elseif retval < 0
    abort retval
  elseif retval < 2
    abort E_INVALID_EVT

  ' Now read the rest, if the event didn't fit entirely in one packet.
  ' This time we want to to a blocking read, and we have an exact
  ' upper bound on the number of bytes to read. (We're not relying on
  ' short packets to end the transfer)
  '
  ' So, oddly enough, now this looks just like a bulk transfer.
  ' Continue it as such.

  evtNumParams <#= constant(MAX_EVT_PARAMS - 1)
  length := evtNumParams + 2 - retval

  if length > 0
    if hc.BulkRead(intrIn, @hciEvent + retval, length) <> length
      abort E_SHORT_EVT

  return evtOpcode

PUB EvtSize
  '' Return the number of event parameter bytes remaining.
  '' This number will decrease as event parameters are consumed
  '' by the HCIevt_* functions.

  return evtNumParams

PUB Evt8
  '' Consumes one byte from the event parameter list, and returns it.

  evtNumParams--
  return BYTE[evtPointer++]

PUB Evt16
  '' Consumes a 16-bit word from the event parameter list, and returns it.

  result := Evt8
  result |= Evt8 << 8

PUB Evt24
  '' Consumes a 24-bit word from the event parameter list, and returns it.

  result := Evt16
  result |= Evt8 << 16

PUB EvtBuffer(len)
  '' Return a pointer to the current position in the event parameter buffer,
  '' and consume "len" bytes.

  result := evtPointer
  evtNumParams -= len
  evtPointer += len


CON

  ' High bytes for HCI commands, based on OGF

  LC = ($01 << 2)
  LP = ($02 << 2)
  CB = ($03 << 2)
  IP = ($04 << 2)
  SP = ($05 << 2)

  ' Bluetooth HCI Commands

  LC_Inquiry                     = $0001 | ($01 << 10)  ' $0401
  LC_InquiryCancel               = $0002 | ($01 << 10)  ' $0402
  LC_PeriodicInquiryMode         = $0003 | ($01 << 10)  ' $0403
  LC_ExitPeriodicInquiryMode     = $0004 | ($01 << 10)  ' $0404
  LC_CreateConn                  = $0005 | ($01 << 10)  ' $0405
  LC_Disconnect                  = $0006 | ($01 << 10)  ' $0406
  LC_CreateConnCancel            = $0008 | ($01 << 10)  ' $0408
  LC_AcceptConnRequest           = $0009 | ($01 << 10)  ' $0409
  LC_RejectConnRequest           = $000a | ($01 << 10)  ' $040a
  LC_LinkKeyRequestReply         = $000b | ($01 << 10)  ' $040b
  LC_LinkKeyRequestNegativeReply = $000c | ($01 << 10)  ' $040c
  LC_PINCodeRequestReply         = $000d | ($01 << 10)  ' $040d
  LC_PINCodeRequestNegativeReply = $000e | ($01 << 10)  ' $040e
  LC_ChgConnPacketType           = $000f | ($01 << 10)  ' $040f
  LC_AuthenticationRequested     = $0011 | ($01 << 10)  ' $0411
  LC_SetConnEncryption           = $0013 | ($01 << 10)  ' $0413
  LC_ChgConnLinkKey              = $0015 | ($01 << 10)  ' $0415
  LC_MasterLinkKey               = $0017 | ($01 << 10)  ' $0417
  LC_RemNameRequest              = $0019 | ($01 << 10)  ' $0419
  LC_RemNameRequestCancel        = $001a | ($01 << 10)  ' $041a
  LC_ReadRemFeatures             = $001b | ($01 << 10)  ' $041b
  LC_ReadRemExtFeatures          = $001c | ($01 << 10)  ' $041c
  LC_ReadRemVersion              = $001d | ($01 << 10)  ' $041d
  LC_ReadClockOffset             = $001f | ($01 << 10)  ' $041f
  LC_ReadLMPHandle               = $0020 | ($01 << 10)  ' $0420
  LC_SetupSyncConn               = $0028 | ($01 << 10)  ' $0428
  LC_AcceptSyncConnRequest       = $0029 | ($01 << 10)  ' $0429
  LC_RejectSyncConnRequest       = $002a | ($01 << 10)  ' $042a
  LP_HoldMode                    = $0001 | ($02 << 10)  ' $0801
  LP_SniffMode                   = $0003 | ($02 << 10)  ' $0803
  LP_ExitSniffMode               = $0004 | ($02 << 10)  ' $0804
  LP_ParkState                   = $0005 | ($02 << 10)  ' $0805
  LP_ExitParkState               = $0006 | ($02 << 10)  ' $0806
  LP_QoSSetup                    = $0007 | ($02 << 10)  ' $0807
  LP_RoleDiscovery               = $0009 | ($02 << 10)  ' $0809
  LP_SwitchRole                  = $000b | ($02 << 10)  ' $080b
  LP_ReadLPSettings              = $000c | ($02 << 10)  ' $080c
  LP_WriteLPSettings             = $000d | ($02 << 10)  ' $080d
  LP_ReadDefaultLPSettings       = $000e | ($02 << 10)  ' $080e
  LP_WriteDefaultLPSettings      = $000f | ($02 << 10)  ' $080f
  LP_FlowSpec                    = $0010 | ($02 << 10)  ' $0810
  CB_SetEventMask                = $0001 | ($03 << 10)  ' $0c01
  CB_Reset                       = $0003 | ($03 << 10)  ' $0c03
  CB_SetEventFilter              = $0005 | ($03 << 10)  ' $0c05
  CB_Flush                       = $0008 | ($03 << 10)  ' $0c08
  CB_ReadPINType                 = $0009 | ($03 << 10)  ' $0c09
  CB_WritePINType                = $000a | ($03 << 10)  ' $0c0a
  CB_CreateNewUnitKey            = $000b | ($03 << 10)  ' $0c0b
  CB_ReadStoredLinkKey           = $000d | ($03 << 10)  ' $0c0d
  CB_WriteStoredLinkKey          = $0011 | ($03 << 10)  ' $0c11
  CB_DeleteStoredLinkKey         = $0012 | ($03 << 10)  ' $0c12
  CB_WriteLocalName              = $0013 | ($03 << 10)  ' $0c13
  CB_ReadLocalName               = $0014 | ($03 << 10)  ' $0c14
  CB_ReadConnAcceptTimeout       = $0015 | ($03 << 10)  ' $0c15
  CB_WriteConnAcceptTimeout      = $0016 | ($03 << 10)  ' $0c16
  CB_ReadPageTimeout             = $0017 | ($03 << 10)  ' $0c17
  CB_WritePageTimeout            = $0018 | ($03 << 10)  ' $0c18
  CB_ReadScanEnable              = $0019 | ($03 << 10)  ' $0c19
  CB_WriteScanEnable             = $001a | ($03 << 10)  ' $0c1a
  CB_ReadPageScanActivity        = $001b | ($03 << 10)  ' $0c1b
  CB_WritePageScanActivity       = $001c | ($03 << 10)  ' $0c1c
  CB_ReadInquiryScanActivity     = $001d | ($03 << 10)  ' $0c1d
  CB_WriteInquiryScanActivity    = $001e | ($03 << 10)  ' $0c1e
  CB_ReadAuthenticationEnable    = $001f | ($03 << 10)  ' $0c1f
  CB_WriteAuthenticationEnable   = $0020 | ($03 << 10)  ' $0c20
  CB_ReadEncryptionMode          = $0021 | ($03 << 10)  ' $0c21
  CB_WriteEncryptionMode         = $0022 | ($03 << 10)  ' $0c22
  CB_ReadClassOfDevice           = $0023 | ($03 << 10)  ' $0c23
  CB_WriteClassOfDevice          = $0024 | ($03 << 10)  ' $0c24
  CB_ReadVoiceSetting            = $0025 | ($03 << 10)  ' $0c25
  CB_WriteVoiceSetting           = $0026 | ($03 << 10)  ' $0c26
  CB_ReadAutomaticFlushTimeout   = $0027 | ($03 << 10)  ' $0c27
  CB_WriteAutomaticFlushTimeout  = $0028 | ($03 << 10)  ' $0c28
  CB_ReadNumBroadcastTrans       = $0029 | ($03 << 10)  ' $0c29
  CB_WriteNumBroadcastTrans      = $002a | ($03 << 10)  ' $0c2a
  CB_ReadHoldModeActivity        = $002b | ($03 << 10)  ' $0c2b
  CB_WriteHoldModeActivity       = $002c | ($03 << 10)  ' $0c2c
  CB_ReadTransmitPowerLevel      = $002d | ($03 << 10)  ' $0c2d
  CB_ReadSyncFlowControlEnable   = $002e | ($03 << 10)  ' $0c2e
  CB_WriteSyncFlowControlEnable  = $002f | ($03 << 10)  ' $0c2f
  CB_SetCtrlToHostFlowControl    = $0031 | ($03 << 10)  ' $0c31
  CB_HostBufferSize              = $0033 | ($03 << 10)  ' $0c33
  CB_HostNumCompletedPackets     = $0035 | ($03 << 10)  ' $0c35
  CB_ReadLinkSupervisionTimeout  = $0036 | ($03 << 10)  ' $0c36
  CB_WriteLinkSupervisionTimeout = $0037 | ($03 << 10)  ' $0c37
  CB_ReadNumSupportedIAC         = $0038 | ($03 << 10)  ' $0c38
  CB_ReadCurrentIACLAP           = $0039 | ($03 << 10)  ' $0c39
  CB_WriteCurrentIACLAP          = $003a | ($03 << 10)  ' $0c3a
  CB_ReadPageScanPeriodMode      = $003b | ($03 << 10)  ' $0c3b
  CB_WritePageScanPeriodMode     = $003c | ($03 << 10)  ' $0c3c
  CB_SetAFHHostChannelClass      = $003f | ($03 << 10)  ' $0c3f
  CB_ReadInquiryScanType         = $0042 | ($03 << 10)  ' $0c42
  CB_WriteInquiryScanType        = $0043 | ($03 << 10)  ' $0c43
  CB_ReadInquiryMode             = $0044 | ($03 << 10)  ' $0c44
  CB_WriteInquiryMode            = $0045 | ($03 << 10)  ' $0c45
  CB_ReadPageScanType            = $0046 | ($03 << 10)  ' $0c46
  CB_WritePageScanType           = $0047 | ($03 << 10)  ' $0c47
  CB_ReadAFHChannelAssignMode    = $0048 | ($03 << 10)  ' $0c48
  CB_WriteAFHChannelAssignMode   = $0049 | ($03 << 10)  ' $0c49
  IP_ReadLocalVersion            = $0001 | ($04 << 10)  ' $1001
  IP_ReadLocalSupportedCommands  = $0002 | ($04 << 10)  ' $1002
  IP_ReadLocalFeatures           = $0003 | ($04 << 10)  ' $1003
  IP_ReadLocalExtFeatures        = $0004 | ($04 << 10)  ' $1004
  IP_ReadBufferSize              = $0005 | ($04 << 10)  ' $1005
  IP_ReadBDAddr                  = $0009 | ($04 << 10)  ' $1009
  SP_ReadFailedContactCounter    = $0001 | ($05 << 10)  ' $1401
  SP_ResetFailedContactCounter   = $0002 | ($05 << 10)  ' $1402
  SP_ReadLinkQuality             = $0003 | ($05 << 10)  ' $1403
  SP_ReadRSSI                    = $0005 | ($05 << 10)  ' $1405
  SP_ReadAFHChannelMap           = $0006 | ($05 << 10)  ' $1406
  SP_ReadClock                   = $0007 | ($05 << 10)  ' $1407
  Test_ReadLoopbackMode          = $0001 | ($06 << 10)  ' $1801
  Test_WriteLoopbackMode         = $0002 | ($06 << 10)  ' $1802
  Test_EnableDeviceUnderTestMode = $0003 | ($06 << 10)  ' $1803

  ' Bluetooth HCI Events

  EV_InquiryComplete             = $01
  EV_InquiryResult               = $02
  EV_ConnComplete                = $03
  EV_ConnRequest                 = $04
  EV_DisconnectionComplete       = $05
  EV_AuthenticationComplete      = $06
  EV_RemNameRequestComplete      = $07
  EV_EncryptionChg               = $08
  EV_ChgConnLinkKeyComplete      = $09
  EV_MasterLinkKeyComplete       = $0a
  EV_ReadRemFeaturesComplete     = $0b
  EV_ReadRemVersionComplete      = $0c
  EV_QoSSetupComplete            = $0d
  EV_CommandComplete             = $0e
  EV_CommandStatus               = $0f
  EV_HardwareError               = $10
  EV_FlushOccurred               = $11
  EV_RoleChg                     = $12
  EV_NumberofCompletedPackets    = $13
  EV_ModeChg                     = $14
  EV_ReturnLinkKeys              = $15
  EV_PINCodeRequest              = $16
  EV_LinkKeyRequest              = $17
  EV_LinkKeyNotification         = $18
  EV_LoopbackCommand             = $19
  EV_DataBufferOverflow          = $1a
  EV_MaxSlotsChg                 = $1b
  EV_ReadClockOffsetComplete     = $1c
  EV_ConnPacketTypeChgd          = $1d
  EV_QoSViolation                = $1e
  EV_PageScanRepetitionModeChg   = $20
  EV_HCIFlowSpecComplete         = $21
  EV_InquiryResultWithRSSI       = $22
  EV_ReadRemExtFeaturesComplete  = $23
  EV_SyncConnComplete            = $2c
  EV_SyncConnChgd                = $2d

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