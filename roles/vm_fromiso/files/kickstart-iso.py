#!/usr/bin/env python
import sys
import pycdlib

iso = pycdlib.PyCdlib()
iso.new(vol_ident="OEMDRV", rock_ridge="1.09")

iso.add_file(sys.argv[1], "/KS.CFG;1", rr_name="ks.cfg")
iso.write(sys.argv[2])
iso.close()
