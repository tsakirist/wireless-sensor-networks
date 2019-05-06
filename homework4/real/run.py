import sys
import time
from threading import Thread
import tos

MAX_PAYLOAD = 115


class ApplicationMsg(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self, [('fragment', 'int', 1), ('id', 'int', 1), ('len', 'int', 1), ('buf', 'blob', 114)], payload)


class TerminateMsg(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self, [('id', 'int', 1)], payload)


def main():
    """
    Pre-defined applications:
    1)	This application does nothing, it simply returns when initialized.
        app = [0x04, 0x01, 0x00, 0x00]

    2)	This application blinks the LED for 3 seconds, once.
        app = [0x09, 0x04, 0x02, 0xC1, 0xE0, 0x03, 0x00, 0xC0, 0x00]

    3)	This application blinks the LED for 3 seconds periodically, every 10 seconds.
        app = [0x17, 0x06, 0x0E, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00, 0xA1, 0x07, 0xC0, 0x11, 0x00, 0xE0, 0x07, 0x00, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00]

    4)	This application reads the brightness sensor every 5 seconds and turns on the LED if the value is less than 50 (in the spirit of Assignment 1).
        app = [0x14, 0x03, 0x0E, 0xE0, 0x05, 0x00, 0xD1, 0x12, 0x32, 0x42, 0x01, 0x92, 0x04, 0xC0, 0xB0, 0x02, 0xC1, 0xE0, 0x05, 0x00]
    """

    am_id = 47
    serial_port = tos.Serial("/dev/ttyUSB0", 115200)
    am = tos.AM(serial_port)

    app_msg = ApplicationMsg()
    t_msg = TerminateMsg()

    print "`"*10
    print "1)This application does nothing, it simply returns when initialized"
    print "2)This application blinks the LED for 3 seconds, once."
    print "3)This application blinks the LED for 3 seconds periodically, every 10 seconds."
    print "4)This application reads the brightness sensor every 5 seconds and turns on the LED if the value is less than 50."
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
			print "Data: ", msg.data
		# if msg is not None and len(msg) > 0:
		# 	pkt = ApplicationMsg(msg.data)
		# 	print pkt
		# 	print len(msg.data)


def menu(am, am_id, app_msg, t_msg):
    app1 = [0x04, 0x01, 0x00, 0x00]
    app2 = [0x09, 0x04, 0x02, 0xC1, 0xE0, 0x03, 0x00, 0xC0, 0x00]
    app3 = [0x17, 0x06, 0x0E, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00, 0xA1, 0x07, 0xC0, 0x11, 0x00, 0xE0, 0x07, 0x00, 0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00]
    app4 = [0x14, 0x03, 0x0E, 0xE0, 0x05, 0x00, 0xD1, 0x12, 0x32, 0x42, 0x01, 0x92, 0x04, 0xC0, 0xB0, 0x02, 0xC1, 0xE0, 0x05, 0x00]
    apps = {1:app1, 2:app2, 3:app3, 4:app4}
    while 1:
        choice = int(raw_input("Menu:\n1.Load new application\n2.Terminate application\n"));
        if choice == 2:
            id = int(raw_input("Enter the id of application: "))
            terminate(am, am_id, t_msg, id)
        elif choice == 1:
            app_num = int(raw_input("Which application do you want to run?"))
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

    size = (MAX_PAYLOAD - 3)
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
