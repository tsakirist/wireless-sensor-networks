import sys
import time
from threading import Thread
import tos

MAX_PAYLOAD = 115


class ApplicationMsg(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self,
                            [('fragment', 'int', 1),
                             ('id', 'int', 1),
                             ('len', 'int', 1),
                             ('originator', 'int', 1),
                             ('buf', 'blob', 110)], payload)


class TerminateMsg(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self, [('id', 'int', 1)], payload)


class ResultMsg(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self,
                            [('seq', 'int', 1),
                             ('reg7','int', 1),
                             ('reg8', 'int', 1),
                             ('originator', 'int', 1),
                             ('id', 'int', 1),
                             ('path_indx', 'int', 1),
                             ('path', 'blob', None)], payload)

    def __str__(self):
        res = "\nreg7: " + str(self.reg7) + "\nreg8: " + str(self.reg8) + "\napp_id: " + str(self.id)
        if self.path_indx > 0:
            if(self.reg7 > 1 and self.reg8 > 1):
                res += "\nnodes: "
                delim = ", "
            else:
                res += "\npath: "
                delim = "->"
            for i in xrange(self.path_indx):
                if i != self.path_indx-1:
                    res += str(self.path[i]) + delim
                else:
                    res += str(self.path[i]) + "\n"
        return res


def main():
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

    am_id = 47
    serial_port = tos.Serial("/dev/ttyUSB0", 115200)
    am = tos.AM(serial_port)

    app_msg = ApplicationMsg()
    t_msg = TerminateMsg()

    print "`"*10
    print "1)This application reads the brightness sensor every 60 seconds and sends the result to the source, without any aggregation."
    print "2)This application reads the brightness sensor every 60 seconds and sends the result to the source, with interception (w/o touching the contents)"
    print "3)This application reads the brightness sensor every 60 seconds and sends the minimum value to the source, with aggregation."
    print ""
    print "`"*10

    # Start threads
    menu_thread = Thread(target=menu, args=(am, am_id, app_msg, t_msg))
    menu_thread.daemon = True
    menu_thread.start()
    rcv_thread = Thread(target=rcv, args=(am,))
    rcv_thread.daemon = True
    rcv_thread.start()

    # Keep main thread alive
    while 1:
        time.sleep(10)

def rcv(am):
    while 1:
        msg = am.read(timeout=0.5)
        if msg is not None and len(msg.data) > 0:
            pkt = ResultMsg(msg.data)
            print pkt


def menu(am, am_id, app_msg, t_msg):
    # app1 = [0x0C, 0x03, 0x05, 0x00, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00]
    app1 = [0x0C, 0x03, 0x05, 0x00, 0xE0, 0x05, 0x00, 0xD7, 0xF0, 0xE0, 0x05, 0x00]   # Changed timer to 5sec
    # app2 = [0x10, 0x03, 0x05, 0x04, 0xE0, 0x3C, 0x00, 0xD7, 0xF0, 0xE0, 0x3C, 0x00, 0x27, 0x09, 0xF0, 0x00]
    app2 = [0x10, 0x03, 0x05, 0x04, 0xE0, 0x05, 0x00, 0xD7, 0xF0, 0xE0, 0x05, 0x00, 0x27, 0x09, 0xF0, 0x00] # Changed timer to 5sec
    # app3 = [0x1C, 0x07, 0x0C, 0x05, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00, 0xD1, 0x57, 0x88, 0x01, 0xF1, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x3C, 0x00,0x37, 0x09, 0x88, 0x0A, 0x00]
    app3 = [0x1C, 0x07, 0x0C, 0x05, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x05, 0x00, 0xD1, 0x57, 0x88, 0x01, 0xF1, 0x17, 0x00, 0x18, 0x7F, 0xE1, 0x05, 0x00,0x37, 0x09, 0x88, 0x0A, 0x00]
    apps = {1:app1, 2:app2, 3:app3}
    while 1:
        choice = int(raw_input("Menu:\n1.Load new application\n2.Terminate application\n"));
        if choice == 2:
            id = int(raw_input("Enter the id of application: "))
            terminate(am, am_id, t_msg, id)
        elif choice == 1:
            app_num = int(raw_input("Which application do you want to run? "))
            id = int(raw_input("Give an id to the application: "))
            app = apps[app_num]
            send(am, am_id, app_msg, app, id)
        else:
            print "Wrong choice!"


def send(am, am_id, app_msg, app, id):
    """
    Function to send the application to the mote and
    try to fragment it in case it's bigger than MAX_PAYLOAD
    """

    size = (MAX_PAYLOAD - 4)
    app_len = len(app)
    frags = app_len / size
    if app_len % size != 0:
        frags += 1
    app_msg.id = id
    for i in xrange(frags):
        buf = app[i*size:(i+1)*size]
        app_msg.buf = buf
        app_msg.len = len(buf)
        app_msg.fragment = i
        app_msg.originator = 0  # This will be changed accordingly from inside the mote
        am.write(app_msg, am_id, None, False)
        time.sleep(0.1)


def terminate(am, am_id, t_msg, id):
    """
    Function to terminate an application
    """

    t_msg.id = id
    am.write(t_msg, am_id, None, False)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit()
