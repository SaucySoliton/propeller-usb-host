{{

bluetooth-keyring
------------------------------------------------------------------

The keyring module is responsible for storing link keys for devices
we're paired with. We have room to store a fixed number of link
keys in RAM, so we keep track of the most recently used keys and
evict old ones when necessary. When a new key is stored, we back
up our data to EEPROM.

To maintain robustness even if power loss occurs during a write,
we keep the link keys on EEPROM pages which don't overlap with any
other code or data, and we use simple data structures that can't
be put into an inconsistent state.

We want to store how 'recent' a key is, but we also don't want
any easily corruptable data structures like linked lists. We'd also
like to rewrite the fewest number of pages possible when updating
the stored keys. So we choose a 32-bit generation number. Each time
we write a new key, we look for the highest generation number and
add one. A 32-bit number is larger than the expected number of cycles
in the EEPROM's lifetime, so we should not expect overflow. If overflow
occurs, it means there was data corruption- so the whole keyring should
be zeroed.

The latest version of this file lives at
https://github.com/scanlime/propeller-usb-host

Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.

}}

CON
  ' Error codes
  E_EEPROM = -50

  EEPROM_SCL = 28
  EEPROM_SDA = 29
  EEPROM_ADDRESS = $A0

  PAGE_SIZE   = 64
  ENTRY_LEN   = 32     ' Pad to something even
  ENTRY_SHIFT = 5      ' log2(ENTRY_LEN)
  NUM_KEYS    = 8
  NUM_PAGES   = NUM_KEYS / 2
  BDADDR_LEN  = 6
  KEY_LEN     = 16

  ' Allocate at least NUM_PAGES page-aligned pages. This means we may need
  ' up to one additional page prior to the allocated pages, to ensure alignment.
  TOTAL_LONGS = (NUM_PAGES+1) * PAGE_SIZE / 4

  ' Entry offsets
  O_SEQUENCE = 0
  O_BDADDR   = O_SEQUENCE + 4
  O_KEY      = O_BDADDR + BDADDR_LEN

DAT

' Initialize to $FF to test overflow logic.
dataStore  long $FFFFFFFF[TOTAL_LONGS]

PUB FirstEntry
  ' Get a pointer to the first entry
  ' (PUB only for debugging!)

  return (@dataStore + 63) & !63

PRI OldestEntry : oldPtr | ptr
  ' Look for the oldest entry in the database, and return a pointer to it

  oldPtr := ptr := FirstEntry
  repeat constant(NUM_KEYS - 1)
    ptr += ENTRY_LEN
    if LONG[ptr] < LONG[oldPtr]
      oldPtr := ptr

PRI NextGeneration : nextGen | ptr, id
  ' Calculate the next generation number. If overflow is detected, erase everything

  ptr := FirstEntry
  repeat NUM_KEYS
    id := LONG[ptr] + 1

    if id =< 0
      ' Overflow!
      longfill(@dataStore, 0, TOTAL_LONGS)
      ptr := FirstEntry
      repeat NUM_KEYS
        Commit(ptr)
        ptr += ENTRY_LEN
      return 1

    ptr += ENTRY_LEN
    nextGen #>= id

PUB LookupKey(bdaddr) | ptr, bdaddrPtr, match, gen
  '' Look for a key matching the given bdaddr. If found, returns a pointer
  '' to the key, good until the next keyring call. If not found, returns zero.

  ptr := FirstEntry
  gen := NextGeneration

  repeat NUM_KEYS
    match~~
    bdaddrPtr := bdaddr
    ptr += O_BDADDR
    repeat BDADDR_LEN
      match &= (BYTE[ptr++] == BYTE[bdaddrPtr++])

    if match
      ' Only update the generation number if this wasn't already the most recent
      if LONG[ptr - O_KEY] + 1 <> gen
        LONG[ptr - O_KEY] := gen
        Commit(ptr)
      return ptr

    ptr += constant(ENTRY_LEN - O_KEY)

PUB StoreKey(bdaddr, key) | newKey, gen
  '' Overwrite the key for a particular bdaddr. If there was an old key,
  '' overwrites it. If no key has been stored yet, overwrites the oldest
  '' key in the database.

  gen := NextGeneration

  if not (newKey := LookupKey(bdaddr))
    newKey := OldestEntry
    bytemove(newKey += O_BDADDR, bdaddr, BDADDR_LEN)
    newKey += BDADDR_LEN

  LONG[newKey - O_KEY] := gen
  bytemove(newKey, key, KEY_LEN)
  Commit(newKey)

PRI Commit(address) | shiftreg, bytecount
  ' Store an entry's page to EEPROM, given the entry's address

  outa[EEPROM_SCL]~~   ' SCL high
  dira[EEPROM_SCL]~~   ' Drive SCL
  outa[EEPROM_SCL]~    ' SCL low
  outa[EEPROM_SCL]~~   ' SCL high

  address &= !63

  ' Issue page-write I2C commands.

  ' I2C Start
  dira[EEPROM_SDA]~~    ' Drive SDA low
  outa[EEPROM_SCL]~     ' Drive SCL low

  ' We have a 32-bit data buffer that starts out filled with the three-byte header,
  ' then we re-fill it with longs from hub memory. We're sending the least significant
  ' byte first, but most significant bit first. To be consistent with this byte order,
  ' we need to swap the bytes in our address.

  shiftreg := EEPROM_ADDRESS | (address & $FF00) | (address << 16)
  bytecount := 3

  ' One 64-byte pages: 16 data longs plus header
  repeat 17

    shiftreg ->= 8  ' Left-justify the least-significant byte

    ' Loop over each byte in the shift register (3 for header, 4 for data)
    repeat bytecount
      repeat 8
        dira[EEPROM_SDA] := shiftreg => 0   ' SDA = shiftreg MSB
        outa[EEPROM_SCL]~~                  ' Drive SCL high
        shiftreg <-= 1                      ' Right one bit
        outa[EEPROM_SCL]~                   ' Drive SCL low

      dira[EEPROM_SDA]~                     ' Let SDA float
      outa[EEPROM_SCL]~~                    ' Drive SCL high
      if ina[EEPROM_SDA]                    ' Check for ACK
        abort E_EEPROM
      outa[EEPROM_SCL]~                     ' Drive SCL low

      shiftreg ->= 16                       ' Next byte

    shiftreg := LONG[address]
    address += 4
    bytecount := 4

  ' I2C Stop
  dira[EEPROM_SDA]~~    ' Drive SDA low
  outa[EEPROM_SCL]~~    ' Drive SCL high
  dira[EEPROM_SDA]~     ' Float SDA high

  ' Wait for page write. Datasheet says the max write time is 5ms.
  ' This is just a really conservative hardcoded delay. It's 5ms at 96 MHz.
  ' (This takes less memory than polling for completion.)
  waitcnt(cnt + constant(96_000_000 / 1000 * 5))

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