import sys
import time
import os
from TOSSIM import *
from TerminateMsg import *
from ApplicationMsg import *

"""
Pre-defined applications:
	1)	This application reads the brightness sensor every 60 seconds and sends the result to the source, without any aggregation
		app = [0x0C, 0x03, 0x05, 0x00, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00]

	2)	Same as App1, but each node explicitly intercepts and retransmits towards the source/sink the results of its children (without touching the contents).
		app = [0x10, 0x03, 0x05, 0x04, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00, 0x27, 0x09, 0xF0, 0x00]

	3)	This application reads the brightness sensor every 60 seconds and sends the minimum value to the source, with aggregation.
		app = [0x1C, 0x07, 0x0C, 0x05, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00, 0xD1, 0x57, 0x88, 0x01, 0xF1, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00,
				0x37, 0x09, 0x88, 0x0A, 0x00]
"""

node_list = []

def addLinks(name):
    global r
    with open("topologies/" + name + ".txt", 'r') as f:
        for line in f:
            s = line.split()
            if s:
                r.add(int(s[0]), int(s[1]), float(s[2]))
                if int(s[0]) not in node_list:
                    node_list.append(int(s[0]))
                if int(s[1]) not in node_list:
                    node_list.append(int(s[1]))


def addNoise():
    global r, t
    counter = 0
    with open("topologies/noise/meyer-heavy.txt", "r") as f:
        for line in f:
            counter += 1
            val = line.strip()
            if val:
                for i in node_list:
                    t.getNode(i).addNoiseTraceReading(int(val))
            if counter==100:
                break;
    for i in node_list:
        t.getNode(i).createNoiseModel()


def sendApp(app_msg, app, id, delay):
	# Send the application to the mote and try to fragment it in case it's bigger than MAX_PAYLOAD
	size = (DEFAULT_MESSAGE_SIZE - 3)
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
		# app_msg.set_originator(0)
		serialpkt.setData(app_msg.data)
		serialpkt.setType(app_msg.get_amType())
		serialpkt.deliver(0, t.time() + delay + 5*(i+1))

def terminateApp(term_msg, id, delay):
	# Send the terminate msg to the mote
	term_msg.set_id(id)
	serialpkt.setData(term_msg.data)
	serialpkt.setType(term_msg.get_amType())
	serialpkt.setDestination(0)
	serialpkt.deliver(0, t.time() + delay)

def main():
	global t, r, serialpkt

	t = Tossim([])
	r = t.radio();

	t.addChannel("Boot", sys.stdout)
	# t.addChannel("Execute", sys.stdout)
	# t.addChannel("Interpreter", sys.stdout)
	# t.addChannel("Interpreter2", sys.stdout)
	t.addChannel("Timer", sys.stdout)
	t.addChannel("MySerial", sys.stdout)
	t.addChannel("Read", sys.stdout)
	t.addChannel("Leds", sys.stdout)
	t.addChannel("Receive", sys.stdout)
	t.addChannel("CollisionTimer", sys.stdout)
	t.addChannel("Task", sys.stdout)
	t.addChannel("Transmit", sys.stdout)
	t.addChannel("Buffer", sys.stdout)
	t.addChannel("SNRLoss", sys.stdout)


	# name = raw_input("Enter file name: ")
	# print name # Important
	# secs = int(raw_input("Enter simulation seconds: "))
	# print secs # Important
	name, secs = "top", 300

	addLinks(name)
	addNoise()

	for i in node_list:
	    if(i!=8):
	        t.getNode(i).bootAtTime(1 * i)
	    else:
	    #     # Start node 5 after secs/2 = 15 simulated seconds
	        t.getNode(i).bootAtTime(20 * t.ticksPerSecond())

	# Create a serial packet
	serialpkt = t.newSerialPacket()

	# Create the application,termination msg
	app_msg = ApplicationMsg()
	term_msg = TerminateMsg()
	# app1 = [0x0C, 0x03, 0x05, 0x00, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00]
	# app2 = [0x10, 0x03, 0x05, 0x04, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00, 0x27, 0x09, 0xF0, 0x00]
	# app3 = [0x1C, 0x07, 0x0C, 0x05, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00, 0xD1, 0x57, 0x88, 0x01, 0xF1, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00,0x37, 0x09, 0x88, 0x0A, 0x00]
	app1 = [0x0C, 0x03, 0x05, 0x00, 0xE0, 0x05, 0x00, 0xD7, 0xF0, 0xE0, 0x05, 0x00]   # Changed timer to 5sec
	# app2 = [0x10, 0x03, 0x05, 0x04, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00, 0x27, 0x09, 0xF0, 0x00]
	app2 = [0x10, 0x03, 0x05, 0x04, 0xE0, 0x05, 0x00, 0xD7, 0xF0, 0xE0, 0x05, 0x00, 0x27, 0x09, 0xF0, 0x00] # Changed timer to 5sec
	# app3 = [0x1C, 0x07, 0x0C, 0x05, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00, 0xD1, 0x57, 0x88, 0x01, 0xF1, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00,0x37, 0x09, 0x88, 0x0A, 0x00]
	app3 = [0x1C, 0x07, 0x0C, 0x05, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x05, 0x00, 0xD1, 0x57, 0x88, 0x01, 0xF1, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x05, 0x00,0x37, 0x09, 0x88, 0x0A, 0x00]
	# Send new application
	id = 0
	sendApp(app_msg, app2, id, 0)
	# id = 1
	# sendApp(app_msg, app2, id, 20*t.ticksPerSecond())
	# terminateApp(term_msg, 0, 200*t.ticksPerSecond())

	# flag = True

	# Run some events
	while t.time() < secs * t.ticksPerSecond():
	  	t.runNextEvent()
		# Terminate the application after secs/2 simulated time
		# if(t.time() > secs/2 * t.ticksPerSecond() and flag):
		# 	terminateApp(term_msg, id)
		# 	flag = False

if __name__ == "__main__":
	try:
		main()
	except KeyboardInterrupt:
		sys.exit()
