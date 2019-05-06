#ifndef VMC_H
#define VMC_H

enum {
    AM_SMSG = 47,
    MAX_APPS = 3,
    FRESH_INTERVAL = 1000,
    MAX_PAYLOAD = 112,
    /* Instruction set */
    ret = 0x0,
    set,
    cpy,
    add,
    sub,
    inc,
    dec,
    max,
    min,
    bgz,
    bez,
    bra,
    led,
    rdb,
    tmr
};

typedef struct application {
    bool waiting;
    bool active;
    bool timer_fired;
    bool pending_timer_fired;
    uint8_t indx;
    uint8_t pc;
    uint8_t id;
    uint8_t bin_len;
    uint8_t init_len;
    uint8_t timer_len;
    uint8_t buf[252];
    int8_t reg[6];
} application_t;

typedef nx_struct app_msg {
    nx_uint8_t fragment;
    nx_uint8_t id;
    nx_uint8_t len;
    nx_uint8_t buf[MAX_PAYLOAD];
} app_msg_t;

// typedef nx_struct app_msg2 {
//     nx_uint8_t buf[MAX_PAYLOAD];
// } app_msg_t2;

typedef nx_struct term_msg {
    nx_uint8_t id;
} term_msg_t;

#endif
