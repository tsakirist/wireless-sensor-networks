#ifndef MY_SERIAL_H
#define MY_SERIAL_H

enum {
    AM_SERIALMSG = 45
};

typedef nx_struct SerialMsg {
    nx_uint8_t temp;
} SerialMsg_t;

#endif
