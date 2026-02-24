#!/bin/bash -x
pnut-ts -I .. -I ../UTILS SD_demo_shell.spin2
pnut-term-ts -u -r SD_demo_shell.bin
