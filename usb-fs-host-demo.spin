
CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 6_000_000

OBJ
  hc : "usb-fs-host"
  term : "Parallax Serial Terminal"
  
VAR
  long  buf[8]

PUB main | value, i
  term.Start(115200)
  hc.Start
   
  repeat
    hc.Enumerate
    
    ' Trigger scope
    hc.Sync
    DIRA := OUTA := 8
    OUTA := 0

    longfill(@buf, $DEADBEEF, 8)
    value := hc.ControlRead(hc#REQ_GET_DESCRIPTOR, hc#DESC_STRING | 3, $0904, @buf, $1a)
     
    term.str(string(term#NL, term#NL))
    term.hex(value, 8)
    term.str(string(" "))
    term.bin(value, 32)

    repeat i from 0 to 7
      term.str(string(term#NL, "   "))
      term.hex(buf[i], 8)

    waitcnt(cnt + clkfreq/5)
    
    