
CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 6_000_000

OBJ
  hc : "usb-fs-host"
  term : "Parallax Serial Terminal"
  
VAR
  long  buf[8]
  byte  cfg[2048]

PUB main | value, error, i
  term.Start(115200)
  hc.Start

  repeat
    error := hc.Enumerate

    term.str(string(term#CS))
    
    if error
      term.str(string(term#NL, term#NL, "Can't enumerate device ("))
      term.dec(error)
      term.str(string(" "))
      term.hex(error, 8)
      term.str(string(")"))
    else
      term.str(string(term#NL, term#NL, "Found device "))
      term.hex(hc.GetVendorID, 4)
      term.str(string(":"))
      term.hex(hc.GetProductID, 4)
                                      
    term.str(string(term#NL, term#NL, "Device Descriptor:", term#NL))    
    repeat i from 0 to hc#DEVDESC_LEN - 1
      term.str(string(" "))
      term.hex(BYTE[hc.GetDeviceDescriptor + i], 2)

    if 0
      term.str(string(term#NL, "Config Descriptor:", term#NL, " "))
      value := hc.ControlRead(hc#REQ_GET_DESCRIPTOR, hc#DESC_CONFIGURATION | 1, 0, @cfg, 2048)
      term.hex(value, 8)
      if value > 0
        repeat i from 0 to value-1
          term.str(string(" "))
          term.hex(cfg[i], 2)

    if not error
      term.str(string(term#NL, term#NL, "SetConfiguration: "))
      error := hc.SetConfiguration(1)
      term.dec(error)

    if not error
      waitcnt(cnt + clkfreq * 2)
      
      repeat while hc.GetPortConnection <> hc#PORTC_NO_DEVICE
        value := hc.InterruptRead(1, @cfg, 64)
        if value <> hc#E_TIMEOUT
          term.str(string(term#NL, "EP1 IN ["))
          term.hex(value, 2)
          term.str(string("] "))
          repeat i from 0 to 31
            term.str(string(" "))
            term.hex(cfg[i], 2)
            
    