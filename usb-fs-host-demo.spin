
CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 6_000_000

OBJ
  hc : "usb-fs-host"
  term : "Parallax Serial Terminal"
  
VAR
  long  buf[8]

PUB main | value, error, i
  term.Start(115200)
  hc.Start
   
  repeat
    error := hc.Enumerate
    if error
      term.str(string("Can't enumerate device ("))
      term.dec(error)
      term.str(string(")", term#NL))
    else
      term.str(string("Found device "))
      term.hex(hc.GetVendorID, 4)
      term.str(string(":"))
      term.hex(hc.GetProductID, 4)
      term.str(string(term#NL))

    repeat i from 0 to hc#DEVDESC_LEN
      term.str(string(" "))
      term.hex(BYTE[hc.GetDeviceDescriptor + i], 2)
    term.str(string(term#NL))

    waitcnt(cnt + clkfreq/5)
    
    