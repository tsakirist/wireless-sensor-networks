#ifndef MY_SERIAL_H
#define MY_SERIAL_H

enum {
    AM_SMSG = 45
};

typedef nx_struct Query {
    nx_uint8_t  ignore_counter;
    nx_uint8_t  type;
    nx_uint8_t  originator;
    nx_uint8_t  mode;
    nx_uint16_t period;
    nx_uint16_t lifetime;
    nx_uint16_t seq_no;
} Query_t;

typedef nx_struct SMsg {
    Query_t qr;
} SerialMsg_t;

#endif
