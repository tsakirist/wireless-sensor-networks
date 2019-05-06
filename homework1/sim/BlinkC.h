#ifndef BLINK_H
#define BLINK_H

enum {
    AM_BLINKMSG = 137,
};

typedef nx_struct BlinkMsg {
    nx_uint16_t interval;
    nx_uint16_t brightVal;
} BlinkMsg_t;

#endif
