import sys
import time
import os
from TOSSIM import *
from TerminateMsg import *
from ApplicationMsg import *

def sendApp(app_msg, app, id):
	# Send the application to the mote and try to fragment it in case it's bigger than MAX_PAYLOAD
	size = (DEFAULT_MESSAGE_SIZE - 3)
	print size
	app_len = len(app)
	frags = app_len / size
	if app_len % size != 0:
		frags += 1
	app_msg.set_id(id)
	for i in xrange(frags):
		buf = app[i*size:(i+1)*size]
		app_msg.set_buf(buf)
		app_msg.set_len(len(buf))
		app_msg.set_fragment(i)
		serialpkt.setData(app_msg.data)
		serialpkt.setType(app_msg.get_amType())
		serialpkt.deliver(0, t.time() + 5*(i+1))

def terminateApp(term_msg, id):
	# Send the terminate msg to the mote
	term_msg.set_id(id)
	serialpkt.setData(term_msg.data)
	serialpkt.setType(term_msg.get_amType())
	serialpkt.setDestination(0)
	serialpkt.deliverNow(0)

def main():
	global t, serialpkt

	t = Tossim([])

	t.addChannel("Boot", sys.stdout)
	# t.addChannel("Execute", sys.stdout)
	# t.addChannel("Interpreter", sys.stdout)
	t.addChannel("Timer", sys.stdout)
	t.addChannel("MySerial", sys.stdout)
	t.addChannel("Read", sys.stdout)
	t.addChannel("Leds", sys.stdout)

	t.getNode(0).bootAtTime(1)

	'''
	Pre-defined applications:
		1)	This application does nothing, it simply returns when initialized.
			app = [0x04, 0x01, 0x00, 0x00]

		2)	This application blinks the LED for 3 seconds, once.
			app = [0x09, 0x04, 0x02, 0xC1, 0xE0, 0x03, 0x00, 0xC0, 0x00]

		3)	This application blinks the LED for 3 seconds periodically, every 10 seconds.
			app = [0x17, 0x06, 0x0E, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00, 0xA1, 0x07, 0xC0, 0x11, 0x00, 0xE0, 0x07, 0x00, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00]

		4)	This application reads the brightness sensor every 5 seconds and turns on the LED if the value is less than 50 (in the spirit of Assignment 1).
			app = [0x14, 0x03, 0x0E, 0xE0, 0x05, 0x00, 0xD1, 0x12, 0x32, 0x42, 0x01, 0x92, 0x04, 0xC0, 0xB0, 0x02, 0xC1, 0xE0, 0x05, 0x00]
	'''

	# Create a serial packet
	serialpkt = t.newSerialPacket()

	# Simulated seconds
	secs = 150

	# Create the application,termination msg
	app_msg = ApplicationMsg()
	term_msg = TerminateMsg()
	app1 = [0x04, 0x01, 0x00, 0x00]
	app2 = [0x09, 0x04, 0x02, 0xC1, 0xE0, 0x03, 0x00, 0xC0, 0x00]
	app3 = [0x17, 0x06, 0x0E, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00, 0xA1, 0x07, 0xC0, 0x11, 0x00, 0xE0, 0x07, 0x00, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00]
	app4 = [0x14, 0x03, 0x0E, 0xE0, 0x05, 0x00, 0xD1, 0x12, 0x32, 0x42, 0x01, 0x92, 0x04, 0xC0, 0xB0, 0x02, 0xC1, 0xE0, 0x05, 0x00]

	# Send new application
	id = 0
	sendApp(app_msg, app4, id)
	id += 1
	sendApp(app_msg, app4, id)
	id += 1
	sendApp(app_msg, app4, id)

	# flag = True
	flag = False

	# Run some events
	while t.time() < secs * t.ticksPerSecond():
	  	t.runNextEvent()
		# # Terminate the application after secs/2 simulated time
		if(t.time() > secs/2 * t.ticksPerSecond() and flag):
			terminateApp(term_msg, id)
			flag = False

if __name__ == "__main__":
	try:
		main()
	except KeyboardInterrupt:
		sys.exit()
