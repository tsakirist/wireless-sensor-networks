import sys
import tos
import time

def main():
    tx_pkt = tos.Packet([('value', 'int', 1)], [])
    AM_ID = 45

    serial_port = tos.Serial("/dev/ttyUSB0", 115200)
    am = tos.AM(serial_port)

    while 1:
        raw_input("Press enter to send serial packet")
        tx_pkt.value = 1
        print "Sending a serial packet..."
        am.write(tx_pkt, AM_ID)
        # time.sleep(10)

if __name__ == '__main__':
    main()
