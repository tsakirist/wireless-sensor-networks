from TOSSIM import *
import sys
import time
from SerialMsg import *
import os

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

def main():

    global r, t

    t = Tossim([])
    r = t.radio();

    # t.addChannel("Timer", sys.stdout)
    # t.addChannel("Buffer", sys.stdout)
    # t.addChannel("Receive", sys.stdout)
    # t.addChannel("Forward", sys.stdout)
    t.addChannel("SendDone", sys.stdout)
    # t.addChannel("MySerial", sys.stdout)
    # t.addChannel("Query", sys.stdout)
    t.addChannel("readDone", sys.stdout)
    t.addChannel("Unicast", sys.stdout)
    t.addChannel("SNRLoss", sys.stdout)
    t.addChannel("Update", sys.stdout)
    t.addChannel("bufferResult", sys.stdout)
    # t.addChannel("adjustTimer", sys.stdout)
    # t.addChannel("MySerial", sys.stdout)
    t.addChannel("SearchTimer", sys.stdout)
    t.addChannel("combine", sys.stdout)
    t.addChannel("Merge", sys.stdout)
    t.addChannel("Boot", sys.stdout)
    t.addChannel("QueryTimer", sys.stdout)
    t.addChannel("AggregationTimer", sys.stdout)
    t.addChannel("Results", sys.stdout)
    t.addChannel("Transmit", sys.stdout)
    # t.addChannel("CollisionTimer", sys.stdout)

    # name = raw_input("Enter file name: ")
    # print name # Important
    # secs = int(raw_input("Enter simulation seconds: "))
    # print secs # Important
    name, secs = "top", 300

    addLinks(name)
    addNoise()

    for i in node_list:
        # t.getNode(i).bootAtTime(1*i)
        if(i!=8):
            t.getNode(i).bootAtTime(1 * i)
        else:
        #     # Start node 5 after secs/2 = 15 simulated seconds
            t.getNode(i).bootAtTime(20 * t.ticksPerSecond())

    # Send serial packet to the mote
    msg = SerialMsg()
    msg.set_qr_type(0)
    msg.set_qr_ignore_counter(0)
    msg.set_qr_period(10)
    msg.set_qr_lifetime(100)
    msg.set_qr_mode(1)
    for i in xrange(1):
        serialpkt = t.newSerialPacket()
        serialpkt.setData(msg.data)
        serialpkt.setType(msg.get_amType())
        serialpkt.setDestination(0)
        serialpkt.deliverNow(0)

    # flag1 = True
    # flag2 = True

    # Run for secs simulated seconds
    while t.time() < secs * t.ticksPerSecond():
        t.runNextEvent()
        # This is to remove and add links
        # if t.time() > secs/10 * t.ticksPerSecond() and flag1:
        #     r.remove(4,3)
        #     r.remove(3,4)
        #     print "*"*10
        #     print "Removed links between 3-4"
        #     print "*"*10
        #     flag1 = not flag1
        # if t.time() > secs/9 * t.ticksPerSecond() and flag2:
        #     r.add(4,2,0.0)
        #     r.add(2,4,0.0)
        #     print "*"*10
        #     print "Added links 2-4"
        #     print "*"*10
        #     flag2 = not flag2

        # Broadcast a query after the first one has expired
        # if(flag and t.time() > 180 * t.ticksPerSecond()):
        #     flag = False
        #     serialpkt = t.newSerialPacket()
        #     msg.set_qr_period(5)
        #     serialpkt.setData(msg.data)
        #     serialpkt.setType(msg.get_amType())
        #     serialpkt.setDestination(0)
        #     serialpkt.deliverNow(0)

        # This is to send a second serial packet/query
        # if(t.time() > 30 * t.ticksPerSecond() and flag):
        #     flag = False
        #     serialpkt = t.newSerialPacket()
        #     msg.set_qr_period(5)
        #     serialpkt.setData(msg.data)
        #     serialpkt.setType(msg.get_amType())
        #     serialpkt.setDestination(0)
        #     serialpkt.deliverNow(0)

if __name__ == '__main__':
    try:
        main()
    except:
        sys.exit()
