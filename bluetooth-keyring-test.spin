{{

bluetooth-keyring-test
------------------------------------------------------------------

Test harness for bluetooth-keyring

Copyright (c) 2010 M. Elizabeth Scott <beth@scanlime.org>
See end of file for terms of use.

}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000
  
OBJ
  term : "Parallax Serial Terminal"
  keyring : "bluetooth-keyring"
  bt : "bluetooth-host"

DAT

addr1   byte  $11,$11,$11,$00,$00,$01
addr2   byte  $11,$11,$11,$00,$00,$02
addr3   byte  $12,$34,$56,$78,$9a,$03
addr4   byte  $00,$00,$00,$00,$00,$04
addr5   byte  $00,$00,$00,$00,$00,$05
addr6   byte  $00,$00,$00,$00,$00,$06
addr7   byte  $00,$00,$00,$00,$00,$07
addr8   byte  $00,$00,$00,$00,$00,$08
addr9   byte  $00,$00,$00,$00,$00,$09
addr10  byte  $00,$00,$00,$00,$00,$10
addr11  byte  $00,$00,$00,$00,$00,$11
addr12  byte  $00,$00,$00,$00,$00,$12
addr13  byte  $00,$00,$00,$00,$00,$13
addr14  byte  $00,$00,$00,$00,$00,$14
addr15  byte  $00,$00,$00,$00,$00,$15
addr16  byte  $00,$00,$00,$00,$00,$16
addr17  byte  $00,$00,$00,$00,$00,$17
addr18  byte  $00,$00,$00,$00,$00,$18

key1    byte  $31,$41,$59,$27,$31,$41,$59,$27,$31,$41,$59,$27,$31,$41,$59,$27
key2    byte  $00,$0a,$0b,$0c,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff
key3    byte  $ff,$55,$ff,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff
  
PUB main
  term.start(115200)

  Debug
  term.char(13)

  LookupKey(@addr1)
  LookupKey(@addr2)
  LookupKey(@addr3)
  LookupKey(@addr4)
  LookupKey(@addr5)
  LookupKey(@addr6)
  LookupKey(@addr7)
  LookupKey(@addr8)
  LookupKey(@addr9)
  LookupKey(@addr10)
  LookupKey(@addr11)
  LookupKey(@addr12)
  LookupKey(@addr13)
  LookupKey(@addr14)
  LookupKey(@addr15)
  LookupKey(@addr16)
  LookupKey(@addr17)
  LookupKey(@addr18)
  term.char(13)

  StoreKey(@addr1, @key1)
  StoreKey(@addr2, @key2)
  StoreKey(@addr3, @key3)
  StoreKey(@addr4, @key1)
  StoreKey(@addr5, @key2)
  StoreKey(@addr6, @key3)
  StoreKey(@addr7, @key1)
  StoreKey(@addr8, @key2)
  StoreKey(@addr9, @key3)
  StoreKey(@addr10, @key1)
  StoreKey(@addr11, @key2)
  StoreKey(@addr12, @key3)
  StoreKey(@addr13, @key1)
  StoreKey(@addr14, @key2)
  StoreKey(@addr15, @key3)
  StoreKey(@addr16, @key1)
  StoreKey(@addr17, @key2)
  StoreKey(@addr18, @key3) 
  term.char(13)

  repeat 2
    LookupKey(@addr18)
    LookupKey(@addr17)
    LookupKey(@addr16)
    LookupKey(@addr15)
    LookupKey(@addr14)
    LookupKey(@addr13)
    LookupKey(@addr12)
    LookupKey(@addr11)
    LookupKey(@addr10)
    LookupKey(@addr9)
    LookupKey(@addr8)
    LookupKey(@addr7)
    LookupKey(@addr6)
    LookupKey(@addr5)
    LookupKey(@addr4)
    LookupKey(@addr3)
    LookupKey(@addr2)
    LookupKey(@addr1)
  term.char(13)

  Debug
  term.char(13)

  ' Overwrite a key that's still in memory. This
  ' also makes 5 the oldest key.
  StoreKey(@addr3, @key1)
  StoreKey(@addr4, @key2)

  Debug
  term.char(13)
  
  ' Store a couple new keys
  StoreKey(@addr1, @key3)
  StoreKey(@addr2, @key2)
  term.char(13)

  LookupKey(@addr1)
  LookupKey(@addr2)
  LookupKey(@addr3)
  LookupKey(@addr4)
  LookupKey(@addr5)
  LookupKey(@addr6)
  LookupKey(@addr7)
  LookupKey(@addr8)
  LookupKey(@addr9)
  LookupKey(@addr10)
  LookupKey(@addr11)
  LookupKey(@addr12)
  LookupKey(@addr13)
  LookupKey(@addr14)
  LookupKey(@addr15)
  LookupKey(@addr16)
  LookupKey(@addr17)
  LookupKey(@addr18)
  term.char(13)
  
  LookupKey(@addr1)
  LookupKey(@addr3)
  LookupKey(@addr5)
  LookupKey(@addr7)
  LookupKey(@addr9)
  LookupKey(@addr11)
  LookupKey(@addr13)
  LookupKey(@addr15)
  LookupKey(@addr17)
  term.char(13)

  Debug
  term.char(13)

PRI Debug | addr
  ' Dump out raw contents of the keyring memory

  repeat 20
    term.char("-")
  term.hex(keyRing.FirstEntry, 8)
  
  HexDump(keyring.FirstEntry, 512)

  term.char(13)
  repeat 20
    term.char("-")
  term.char(13)
      
PRI LookupKey(bdaddr) | key
  term.str(string("Key for "))
  term.str(bt.AddressToString(bdaddr))
  key := keyring.LookupKey(bdaddr)
  term.str(string(" = "))
  if key
    repeat keyring#KEY_LEN
      term.hex(BYTE[key++], 2)
  else
    term.str(string("none"))
  term.char(13)  

PRI StoreKey(bdaddr, key)
  term.str(string("Storing "))
  term.str(bt.AddressToString(bdaddr))
  term.str(string(" = "))
  keyring.StoreKey(bdaddr, key)
  repeat keyring#KEY_LEN
    term.hex(BYTE[key++], 2)
  term.char(13)

PRI hexDump(buffer, bytes) | addr, x, b, lastCol
  ' A basic 16-byte-wide hex/ascii dump

  addr~

  repeat while bytes > 0
    term.char(term#NL)
    term.hex(addr, 4)
    term.str(string(": "))

    lastCol := (bytes <# 16) - 1

    repeat x from 0 to lastCol
      term.hex(BYTE[buffer + x], 2)
      term.char(" ")

    term.positionX(constant(7 + 16*3))

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
