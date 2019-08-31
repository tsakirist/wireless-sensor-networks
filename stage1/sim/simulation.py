import sys
import time

from TOSSIM import *
from BlinkMsg import *

t = Tossim([])
#  m = t.mac()
# r = t.radio()
# sf = SerialForwarder(9001)
throttle = Throttle(t, 10)

t.addChannel("Receive", sys.stdout)
t.addChannel("SendDone", sys.stdout)
t.addChannel("BlinkC", sys.stdout)
t.addChannel("LedOn", sys.stdout)
t.addChannel("LedOff", sys.stdout)

interval = int(raw_input("Enter time interval after 100 events:"))

m = t.getNode(0)
m.bootAtTime(1)
# sf.process()
throttle.initialize()

print "***** Starting simulation with interval 1000 msec *****\n"

for i in range(0, 100):
  throttle.checkThrottle()
  t.runNextEvent()
  # sf.process()

# Create the packet
msg = BlinkMsg()
msg.set_interval(interval)

# Make the packet serial and send it to the mote
# for i in xrange(0,5):
serialpkt = t.newSerialPacket()
serialpkt.setData(msg.data)
serialpkt.setType(msg.get_amType())
serialpkt.setDestination(0)
# serialpkt.deliver(0, t.time() + 1)
serialpkt.deliverNow(0)

print "\n***** Changed interval to ", interval,
print " msec *****\n"
for i in range(0, 200):
  throttle.checkThrottle()
  t.runNextEvent()
  # sf.process()

throttle.printStatistics()
