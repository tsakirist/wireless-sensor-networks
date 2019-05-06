We use the following command to generate the MIG BlinkMsg.py  (which converts the BlinkC.h to a python class):

    mig python -target=null -python-classname=BlinkMsg BlinkC.h BlinkMsg -o BlinkMsg.py

We also use for the simulation the following command:

    make micaz sim-sf
