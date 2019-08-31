#!/usr/bin/env python

import sys
import tos
from threading import Thread

def main():
	global am, tx_pkt, AM_ID
	# Create a packet with field interval 2bytes
	tx_pkt = tos.Packet([('interval',  'int', 2)],[])

	AM_ID=137

	serial_port = tos.Serial("/dev/ttyUSB0",115200)
	am = tos.AM(serial_port)

	try:
		recv_thread = Thread(target = receive, 	args = ())
		send_thread = Thread(target = send, 	args = ())
		recv_thread.start()
		send_thread.start()
	except:
		print "Error starting threads"
		sys.exit()

def receive():
	# Receiver thread to observe sensor readings
	global am
	while 1:
		pkt = am.read(timeout=0.5)
		if pkt is not None:
			print "Type: ", pkt.type
			print "Destination: ", pkt.destination
			print "Source: ", pkt.source
			print "Data: ", pkt.data

def send():
	# Sender thread to adjust the reading interval
	global am, tx_pkt
	while 1:
		tx_pkt.interval = int(raw_input())
		am.write(tx_pkt, AM_ID)

if __name__ == '__main__':
	try:
		main()
	except KeyboardInterrupt:
		sys.exit()
