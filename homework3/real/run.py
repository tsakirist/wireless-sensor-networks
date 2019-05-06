import sys
import time
from threading import Thread
import tos


class QueryMsg(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self,
                            [('lifetime', 'int', 2),
                             ('period', 'int', 2),
                             ('type', 'int', 1),
                             ('mode', 'int', 1)], payload)

    def __str__(self):
        return "Lifetime: %d, Period: %d, Type: %d, Mode: %d" % (self.lifetime, self.period, self.type, self.mode)


class Result(tos.Packet):

    def __init__(self, payload=None):
        tos.Packet.__init__(self,
                            [('originator', 'int', 1),
                             ('mode', 'int', 1),
                             ('type', 'int', 1),
                             ('period', 'int', 2),
                             ('indx', 'int', 1),
                             ('path_indx', 'int', 1),
                             ('results', 'blob', 52),
                             ('ids', 'blob', 26),
                             ('path', 'blob', 26)], payload)

    def __str__(self):
        res = "Period: " + str(self.period)
        if self.mode == 0:
            res += "\nMode: NONE"
        elif self.mode == 1:
            res += "\nMode: PIGGYBACK"
        elif self.mode == 2:
            res += "\nMode: STATS"
        res += "\nType: " + str(self.type)
        arr = self.results
        values = map(lambda x, y: (x << 8) | y, arr[::2], arr[1::2])
        res += "\nValues: "
        if self.mode == 2:
            res += "min: " + str(values[0]) + " "
            res += "avg: " + str(values[1]) + " "
            res += "max: " + str(values[2]) + " "
            res += "\nNumber of nodes that contributed: " + str(self.indx)
        else:
            for i in range(self.indx):
                res += str(values[i]) + " "
        res += "\nIds that contributed: "
        for i in range(self.indx):
            res += str(self.ids[i]) + " "
        if self.mode == 0:
            res += "\nPath: "
            for i in range(self.path_indx):
                res += str(self.path[i])
                if i < self.path_indx - 1:
                    res += " -> "
        res += "\n"
        return res


def main():

    query = QueryMsg()
    am_id = 49
    serial_port = tos.Serial("/dev/ttyUSB0", 115200)
    am = tos.AM(serial_port)

    # Start main threads
    recv_thread = Thread(target=receive, args=(am,))
    send_thread = Thread(target=send, args=(query, am, am_id))
    recv_thread.daemon = True
    send_thread.daemon = True
    recv_thread.start()
    send_thread.start()

    # Keep main thread alive
    while 1:
        time.sleep(10)


def receive(am):

    while 1:
        pkt = am.read(timeout=0.5)
        if pkt is not None and len(pkt.data) > 0:
            temp = Result(pkt.data)
            print temp
            # print [i << 8 | j for (i, j) in zip(arr[::2], arr[1::2])]


def send(query, am, am_id):

    while 1:
        print "Input the Query info.."
        query.type = int(raw_input("Type: "))
        query.mode = int(raw_input("Mode: "))
        query.period = int(raw_input("Period: "))
        query.lifetime = int(raw_input("Lifetime: "))
        print query
        am.write(query, am_id, None, False)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit()
