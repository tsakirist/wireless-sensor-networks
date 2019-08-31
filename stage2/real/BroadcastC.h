#ifndef BROADCAST_H
#define BROADCAST_H

enum {
    AM_MSG = 45,
    BUFFER_MAX_SIZE = 5,
    SEQNO_MAX_SIZE = 65535u,
    GROUP_ID = 4,
};

typedef nx_struct BroadcastMsg {
    nx_uint8_t groupId;
    nx_uint16_t nodeId;
    nx_uint16_t seqNo;
} BroadcastMsg_t;

#endif
