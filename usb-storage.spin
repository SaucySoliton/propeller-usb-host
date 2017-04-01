{{

usb-storage
------------------------------------------------------------------

USB Mass Storage Class driver for the Parallax Propeller.

This module provides several interfaces:
  - A low-level SCSI interface
  - A simple sector read/write interface
  - An FSRW compatibility shim, so this module can be
    used with FSRW as an sdspi module.

This is a pretty simple driver that just implements the bulk-only
protocol, and has limited error handling ability. This module
provides support for raw SCSI commands, and it implements simple
block-level read/write entry points.

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
  E_NO_INTERFACE  = -100        ' No mass storage interface found
  E_NO_ENDPOINT   = -101        ' Couldn't find both an IN and OUT endpoint
  E_NOT_SCSI      = -102        ' Device doesn't use SCSI commands
  E_NOT_BULKONLY  = -103        ' Device doesn't use the bulk-only protocol
  E_CSW_LEN       = -104        ' Unexpected CSW length
  E_CSW_SIGNATURE = -105        ' Unexpected CSW signature
  E_CSW_TAG       = -106        ' Unexpected CSW tag
  E_COMMAND_FAIL  = -107        ' SCSI command reported failure
  E_PHASE_ERROR   = -108        ' Mass storage protocol phase aerror
  E_CSW_STATUS    = -109        ' Other unsuccessful CSW status code
  E_INCOMPLETE    = -110        ' Read or write was incomplete
  E_SECTOR_SIZE   = -111        ' Disk has unsupported sector size

  ' 512 bytes is the de-facto standard. This is also the only size
  ' supported by FSRW. So, that's what we mandate.

  SECTORSIZE  = 512
  SECTORSHIFT = 9

  ' Defaults

  DEFAULT_TIMEOUT = 2000        ' 2 seconds

  ' USB storage class constants

  CLASS_MASS_STORAGE   = 8
  SUBCLASS_SCSI        = 6
  PROTOCOL_BULK_ONLY   = $50

  REQ_STORAGE_RESET    = $FF21

  CBW_LEN              = 31     ' USB command block wrapper
  CSW_LEN              = 13     ' USB command status wrapper
  CB_LEN               = 16     ' Max SCSI command block

  CBW_SIGNATURE_VALUE  = $43425355  ' "USBC"
  CSW_SIGNATURE_VALUE  = $53425355  ' "USBS"

  DIR_OUT              = $00    ' CBW direction flags
  DIR_IN               = $80

  CSW_STATUS_PASS      = $00
  CSW_STATUS_FAIL      = $01
  CSW_STATUS_PHASE_ERR = $02

  REPLY_LEN            = 48

DAT

' Command Block Wrapper (CBW)

cbw
cbw_signature           long    CBW_SIGNATURE_VALUE
cbw_tag                 long    1               ' Arbitrary value
cbw_transferLength      long    0               ' Placeholder
cbw_flags               byte    0               ' Placeholder
cbw_lun                 byte    0
cbw_cbLength            byte    0
cbw_cb                  byte    0[CB_LEN]       ' SCSI command block
                        byte    0               ' (Pad to 32 bytes)

' Command Status Wraper (CSW)

csw
csw_signature           long    0
csw_tag                 long    0
csw_dataResidue         long    0
csw_status              byte    0
                        byte    0, 0            ' (Pad to 15 bytes)

' Device Configuration

interfaceNum            byte    0
bulkIn                  word    0
bulkOut                 word    0

' Temporary buffer for small SCSI replies

reply_buf               byte    0[REPLY_LEN]

' Device information

sector_size             long    0
num_sectors             long    0


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

  return hc.FindInterface(CLASS_MASS_STORAGE) <> 0

PUB Init | epd

  '' (Re)initialize this driver. This must be called after Enumerate
  '' and Identify are both run successfully. All three functions must be
  '' called again if the device disconnects and reconnects, or if it is
  '' power-cycled.
  ''
  '' This function sets the device's USB configuration, collects information
  '' about the device and storage media, and prepares us to read and write
  '' disk blocks or issue other SCSI commands.
  ''
  '' This function does communicate with the device, so it may abort with
  '' any driver or host controller error code.

  ' Look for the mass storage interface, and make sure we're compatible.
  ' The mass storage spec allows command formats other than SCSI, but we don't
  ' support them. And we only support the bulk-only protocol, not CBI.

  epd := hc.FindInterface(CLASS_MASS_STORAGE)
  if not epd
    abort E_NO_INTERFACE

  if BYTE[epd + hc#IFDESC_bInterfaceSubClass] <> SUBCLASS_SCSI
    abort E_NOT_SCSI

  if BYTE[epd + hc#IFDESC_bInterfaceProtocol] <> PROTOCOL_BULK_ONLY
    abort E_NOT_BULKONLY

  interfaceNum := BYTE[epd + hc#IFDESC_bInterfaceNumber]

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
  StorageReset

  ' Read the disk size and block size
  SCSI_CB_Begin(READ_CAPACITY, 6)
  SCSI_Query(8, DEFAULT_TIMEOUT)
  num_sectors := SCSI_RB_Long(0)
  if SECTORSIZE <> SCSI_RB_Long(4)
    abort E_SECTOR_SIZE


DAT
''
''==============================================================================
'' Native block-level interface
''==============================================================================

PUB NumSectors
  return num_sectors

PUB ReadSectors(buffer, start, count)
  '' Read sectors into 'buffer'.
  '' Reads 'count' disk sectors, starting at logical block address 'start'.

  ' The READ_10 command should be sufficient for us. The transfer length
  ' of 16 bits is enough to fill the prop's RAM hundreds of times over,
  ' and the 32-bit LBA will address 2 terabytes with the common 512-byte
  ' block size.

  SCSI_CB_Begin(READ_10, 10)
  SCSI_CB_Long(2, start)
  SCSI_CB_Word(7, count)

  if SCSI_Command(buffer, count << SECTORSHIFT, DIR_IN, DEFAULT_TIMEOUT)
    abort E_INCOMPLETE

PUB WriteSectors(buffer, start, count)
  '' Write sectors from 'buffer'.
  '' Writes 'count' disk sectors, starting at logical block address 'start'.

  SCSI_CB_Begin(WRITE_10, 10)
  SCSI_CB_Long(2, start)
  SCSI_CB_Word(7, count)

  if SCSI_Command(buffer, count << SECTORSHIFT, DIR_OUT, DEFAULT_TIMEOUT)
    abort E_INCOMPLETE

DAT
''
''==============================================================================
'' FSRW Compatibility Layer
''==============================================================================

PUB release
  '' FSRW Compatibility. Has no effect.

PUB stop
  '' FSRW Compatibility. Has no effect.

PUB start_explicit(do, clk, di, ds)
  '' FSRW Compatibility.
  ''   - Starts the USB controller if it isn't already running
  ''   - Resets and enumerates the attached device
  ''     (Assumes it's a USB device)
  ''   - Initializes the storage driver

  hc.Enumerate
  Init

PUB readblock(n, buf)
  '' FSRW Compatibility.
  ReadSectors(buf, n, 1)

PUB writeblock(n, buf)
  '' FSRW Compatibility.
  WriteSectors(buf, n, 1)

DAT
''
''==============================================================================
'' SCSI Command Layer
''==============================================================================

PUB StorageReset
  '' Issue a Bulk-Only Mass Storage Reset.

  hc.Control(REQ_STORAGE_RESET, 0, interfaceNum)
  hc.ClearHalt(bulkIn)
  hc.ClearHalt(bulkOut)

  ' If a CSW is waiting, parse it. But if anything's wrong, don't worry.
  \ReadCSW

  hc.FrameWait(10)

PUB TestUnitReady(timeoutMS)
  '' Ping the device at the SCSI level, to make sure it's ready.
  '' Waits up to 'timeoutMS' for the device to respond. Aborts on error.

  SCSI_CB_Begin(TEST_UNIT_READY, 6)
  SCSI_Command(0, 0, DIR_OUT, timeoutMS)

PUB SCSI_CB_Begin(opcode, length)
  '' Begin a new SCSI command buffer. Sets the length and the opcode.
  '' By default, the rest of the command will be all zeroes.

  bytefill(@cbw_cb, 0, CB_LEN)
  cbw_cbLength := length
  SCSI_CB_Byte(0, opcode)

PUB SCSI_CB_Byte(offset, value)
  '' Sets one byte to the SCSI command buffer.

  BYTE[@cbw_cb + offset] := value

PUB SCSI_CB_Word(offset, value)
  '' Sets one big-endian word in the SCSI command buffer

  SCSI_CB_Byte(offset, value >> 8)
  SCSI_CB_Byte(offset+1, value)

PUB SCSI_CB_Long(offset, value)
  '' Sets one big-endian long in the SCSI command buffer

  SCSI_CB_Word(offset, value >> 16)
  SCSI_CB_Word(offset+2, value)

PUB SCSI_RB_Byte(offset)
  '' Parse out one byte from the SCSI_Query reply buffer

  return BYTE[@reply_buf + offset]

PUB SCSI_RB_Word(offset)
  '' Parse out one big-endian word from the SCSI_Query reply buffer

  return (SCSI_RB_Byte(offset) << 8) | SCSI_RB_Byte(offset+1)

PUB SCSI_RB_Long(offset)
  '' Parse out one big-endian long from the SCSI_Query reply buffer

  return (SCSI_RB_Word(offset) << 16) | SCSI_RB_Word(offset+2)

PUB SCSI_Command(buffer, dataLen, flags, timeoutMS) | deadline
  '' Issue the SCSI command which was constructed using the SCSI_CB_*
  '' functions. The command may be either a read or a write. "flags" should
  '' be either DIR_IN or DIR_OUT. If 'dataLen' is nonzero, this
  '' determines whether this function writes to or reads from 'buffer'.
  ''
  '' If the transfer fails, we automatically retry for the specified amount
  '' of time. If the failure persists, we abort with an appropriate error code.
  '' The timeout is specified in milliseconds.
  ''
  '' Returns the "residue" (the difference between the requested transfer
  '' length and the actual length.)

  deadline := cnt + 80_000 * timeoutMS
  cbw_transferLength := dataLen
  cbw_flags := flags

  repeat while (cnt - deadline) < 0
    if (result := \SCSI_CommandTry(buffer, dataLen, flags)) => 0
      return
    else
      case result
        hc#E_STALL, hc#E_PID, hc#E_TIMEOUT:
          StorageReset
        hc#E_NO_DEVICE:
          abort
  abort

PRI SCSI_CommandTry(buffer, dataLen, flags)
  ' One interation of SCSI_Command().
  ' Aborts on error, otherwise returns the residue value.

  hc.BulkWrite(bulkOut, @cbw, CBW_LEN)

  if dataLen
    if flags ' IN
      hc.BulkRead(bulkIn, buffer, dataLen)
    else
      hc.BulkWrite(bulkOut, buffer, dataLen)

  return ReadCSW

PRI ReadCSW
  ' Read the Command Status Wrapper, and parse it.
  ' If anything's wrong, aborts with an appropriate
  ' error code. Otherwise, returns the data residue value.

  if hc.BulkRead(bulkIn, @csw, CSW_LEN) <> CSW_LEN
    abort E_CSW_LEN
  if csw_signature <> CSW_SIGNATURE_VALUE
    abort E_CSW_SIGNATURE
  if csw_tag <> cbw_tag
    abort E_CSW_TAG

  case csw_status

    CSW_STATUS_PASS:
      return csw_dataResidue

    CSW_STATUS_FAIL:
      abort E_COMMAND_FAIL

    CSW_STATUS_PHASE_ERR:
      abort E_PHASE_ERROR

    other:
      abort E_CSW_STATUS

PUB SCSI_Query(replyLen, timeoutMS)
  '' Issue a small SCSI read into an internal reply buffer, which can
  '' be conveniently parsed using the SCSI_RB_* functions.
  ''
  '' replyLen must be <= REPLY_LEN.

  return SCSI_Command(@reply_buf, replyLen, DIR_IN, timeoutMS)


CON

  ' SCSI opcodes

  TEST_UNIT_READY                = $00
  REZERO_UNIT                    = $01
  REQUEST_SENSE                  = $03
  FORMAT_UNIT                    = $04
  READ_BLOCK_LIMITS              = $05
  REASSIGN_BLOCKS                = $07
  INITIALIZE_ELEMENT_STATUS      = $07
  READ_6                         = $08
  WRITE_6                        = $0a
  SEEK_6                         = $0b
  READ_REVERSE                   = $0f
  WRITE_FILEMARKS                = $10
  SPACE                          = $11
  INQUIRY                        = $12
  RECOVER_BUFFERED_DATA          = $14
  MODE_SELECT                    = $15
  RESERVE                        = $16
  SCSI_RELEASE                   = $17   ' (Renamed to not collide with FSRW)
  COPY                           = $18
  ERASE                          = $19
  MODE_SENSE                     = $1a
  START_STOP                     = $1b
  RECEIVE_DIAGNOSTIC             = $1c
  SEND_DIAGNOSTIC                = $1d
  ALLOW_MEDIUM_REMOVAL           = $1e
  SET_WINDOW                     = $24
  READ_CAPACITY                  = $25
  READ_10                        = $28
  WRITE_10                       = $2a
  SEEK_10                        = $2b
  POSITION_TO_ELEMENT            = $2b
  WRITE_VERIFY                   = $2e
  VERIFY                         = $2f
  SEARCH_HIGH                    = $30
  SEARCH_EQUAL                   = $31
  SEARCH_LOW                     = $32
  SET_LIMITS                     = $33
  PRE_FETCH                      = $34
  READ_POSITION                  = $34
  SYNCHRONIZE_CACHE              = $35
  LOCK_UNLOCK_CACHE              = $36
  READ_DEFECT_DATA               = $37
  MEDIUM_SCAN                    = $38
  COMPARE                        = $39
  COPY_VERIFY                    = $3a
  WRITE_BUFFER                   = $3b
  READ_BUFFER                    = $3c
  UPDATE_BLOCK                   = $3d
  READ_LONG                      = $3e
  WRITE_LONG                     = $3f
  CHANGE_DEFINITION              = $40
  WRITE_SAME                     = $41
  READ_TOC                       = $43
  LOG_SELECT                     = $4c
  LOG_SENSE                      = $4d
  MODE_SELECT_10                 = $55
  RESERVE_10                     = $56
  RELEASE_10                     = $57
  MODE_SENSE_10                  = $5a
  PERSISTENT_RESERVE_IN          = $5e
  PERSISTENT_RESERVE_OUT         = $5f
  REPORT_LUNS                    = $a0
  MAINTENANCE_IN                 = $a3
  MOVE_MEDIUM                    = $a5
  EXCHANGE_MEDIUM                = $a6
  READ_12                        = $a8
  WRITE_12                       = $aa
  WRITE_VERIFY_12                = $ae
  SEARCH_HIGH_12                 = $b0
  SEARCH_EQUAL_12                = $b1
  SEARCH_LOW_12                  = $b2
  READ_ELEMENT_STATUS            = $b8
  SEND_VOLUME_TAG                = $b6
  WRITE_LONG_2                   = $ea
  READ_16                        = $88
  WRITE_16                       = $8a
  VERIFY_16                      = $8f
  SERVICE_ACTION_IN              = $9e


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
