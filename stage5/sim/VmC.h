#ifndef VMC_H
#define VMC_H

enum {
    AM_BMSG = 45,
    AM_UMSG = 46,
    AM_SMSG = 47,
    MAX_APPS = 3,
    FRESH_INTERVAL = 1000,
    MAX_PAYLOAD = 100,
    MAX_NODES = 50,
    MAX_CHILDREN = 10,
    BUFFER_MAX_SIZE = 10,
    ROUTING_TABLE_MAX_SIZE = 5,
    SEQNO_MAX_SIZE = 65535u,
    CLSN_DELAY = 20,
    AGGR_DELAY = 60,
    GROUP_ID = 4,
    /* These are required for the mig */
    AM_APP_MSG = 47,
    AM_SERIAL_TERM_MSG = 47,
};

enum {
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
    tmr,
    snd,
};

typedef struct route_info {
    uint8_t originator;
    uint16_t next_hop;
} route_info_t;

typedef struct application {
    bool waiting;
    bool active;
    bool timer_fired;
    bool received;
    bool aggr_mode;
    uint8_t seq;
    uint8_t originator;
    uint8_t indx;
    uint8_t pc;
    uint8_t id;
    uint8_t bin_len;
    uint8_t init_len;
    uint8_t timer_len;
    uint8_t msg_len;
    uint8_t buf[252];
    int8_t reg[11];
} application_t;

typedef nx_struct app_msg {
    nx_uint8_t fragment;
    nx_uint8_t id;
    nx_uint8_t len;
    nx_uint8_t originator;
    nx_uint8_t buf[MAX_PAYLOAD];
} app_msg_t;

typedef nx_struct term_msg {
    nx_uint8_t id;
    nx_uint8_t originator;
    nx_uint16_t addr;
} term_msg_t;

typedef nx_struct serial_term_msg {
    nx_uint8_t id;
} serial_term_msg_t;

typedef nx_struct broadcast_msg {
    nx_uint8_t group_id;
    nx_uint16_t seq_no;
    app_msg_t app;
} broadcast_msg_t;

typedef nx_struct unicast_msg {
    nx_uint8_t seq;
    nx_uint8_t reg7;
    nx_uint8_t reg8;
    nx_uint8_t originator;
    nx_uint8_t id;
    nx_uint8_t path_indx;
    nx_uint8_t path[MAX_NODES];
} unicast_msg_t;

typedef struct path_track {
    uint8_t path_indx;
    uint8_t path[MAX_NODES];
} path_track_t;

typedef nx_struct inform_msg {
    nx_uint8_t siblings;
} inform_msg_t;

#endif
