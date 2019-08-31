from TOSSIM import *
import sys
import time
# from SerialMsg import *
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

    t.addChannel("Boot", sys.stdout)
    t.addChannel("Timer", sys.stdout)
    t.addChannel("Timer1", sys.stdout)
    t.addChannel("Buffer", sys.stdout)
    t.addChannel("Receive", sys.stdout)
    t.addChannel("Task", sys.stdout)
    t.addChannel("Forward", sys.stdout)
    t.addChannel("SendDone", sys.stdout)
    t.addChannel("MySerial", sys.stdout)
    t.addChannel("SNRLoss", sys.stdout)

    name = raw_input("Enter file name: ")
    print name # Important
    secs = int(raw_input("Enter simulation seconds: "))
    print secs # Important

    addLinks(name)
    addNoise()

    for i in node_list:
        t.getNode(i).bootAtTime(1 * i)

    # Send serial packet to the mote
    # msg = SerialMsg()
    # msg.set_temp(33)
    # for i in xrange(1):
    #     serialpkt = t.newSerialPacket()
    #     serialpkt.setData(msg.data)
    #     serialpkt.setType(msg.get_amType())
    #     serialpkt.setDestination(0)
    #     serialpkt.deliverNow(0)

    # Run for secs simulated seconds
    while t.time() < secs * t.ticksPerSecond():
        t.runNextEvent()

if __name__ == '__main__':
    try:
        main()
    except:
        sys.exit()
