#ifndef QUERY_H
#define QUERY_H

/** A simple identification scheme for query mode
  * 0: "none",
  * 1: "piggy-back",
  * 2: "stats"
  */
enum {
    NONE,
    PIGGYBACK,
    STATS
};

enum {
    AM_BMSG = 45,
    AM_UMSG = 48,
    AM_SMSG = 49,
    BUFFER_MAX_SIZE = 10,
    ROUTING_TABLE_MAX_SIZE = 5,
    MAX_QUERIES = 5,
    SEQNO_MAX_SIZE = 65535u,
    VALUES_MAX_SIZE = 26,    /* TOSH_DATA_LENGTH - constant struct variables / 4 , 4 = 2(nx_uint16_t)[values] + 1(nx_uint_8t)[ids] + 1(nx_uint_8t)[path] */
    SENSOR_TYPE = 0,         /* The type of sensor we feature */
    NETWORK_LAT = 10,        /* We assume 10ms packet delay to reach next-hop */
    PROCESS_LAT = 30,        /* We assume 30ms proccessing delay at each node */
    MAX_ACK_INDICATOR = 3,   /* Indicates the max number of received messages before sending an update `ACK` */
    MAX_MISSED_UPDATES = 6,  /* Indicates the max number of missed updates before requesting an update */
    SEARCH_INTERVAL = 5000,
    MAX_SEARCH_TRIES = 3,
    MAX_CHILDREN = 10,
    GROUP_ID = 4,
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

typedef struct route_info {
    uint8_t originator;
    uint8_t hop_counter;
    uint8_t missed_updates;
    uint16_t next_hop;
    bool updated;
    bool active;
} route_info_t;

typedef nx_struct UpdateMsg {
    nx_uint8_t originator[ROUTING_TABLE_MAX_SIZE];
    nx_uint8_t hop_counter[ROUTING_TABLE_MAX_SIZE];
    nx_uint16_t next_hop[ROUTING_TABLE_MAX_SIZE];
    nx_uint16_t addr;
    nx_uint8_t route_indx;
    nx_uint8_t siblings;
    /* Query info */
    nx_uint8_t query_indx;
    Query_t qr[MAX_QUERIES];
} UpdateMsg_t;

typedef nx_struct BroadcastMsg {
    nx_uint8_t  group_id;
    nx_uint8_t  hop_counter;
    /* Query fields */
    Query_t qr;
} BroadcastMsg_t;

typedef nx_struct UnicastMsg {
    nx_uint8_t  originator;
    nx_uint8_t  mode;
    nx_uint8_t  type;
    nx_uint16_t period;
    /** Depending on the mode indx will:
      * @PIGGYBACK Indicate the number of values inside the buffer
      * @STATS Indicate the number of nodes that contributed to the statistics
      */
    nx_uint8_t  indx;
    nx_uint8_t  path_indx;
    /** Depending on the mode values[] will:
      * @PIGGYBACK Contain read values up to VALUES_MAX_SIZE
      * @STATS Contain the first three slots contain (min, avg, max)
      */
    nx_uint16_t values[VALUES_MAX_SIZE]; /* The reading values */
    nx_uint8_t ids[VALUES_MAX_SIZE];     /* The node id's that contributed to the values */
    nx_uint8_t path[VALUES_MAX_SIZE];    /* The node id's that the values passed through e.g path-tracking */
} UnicastMsg_t;

typedef nx_struct ReqUpdateMsg {
  nx_uint8_t new_node;
} ReqUpdateMsg_t;

typedef nx_struct SerialMsg {
    nx_uint16_t lifetime;
    nx_uint16_t period;
    nx_uint8_t type;
    nx_uint8_t mode;
} SerialMsg_t;

#endif
