#include <Timer.h>
#include "QueryC.h"
#include "Serial.h"

module QueryC {

    uses {
        interface Timer<TMilli> as AggregationTimer;
        interface Timer<TMilli> as CollisionTimer;
        interface Timer<TMilli> as QueryTimer;
        interface Timer<TMilli> as SearchTimer;
        interface Boot;
        interface Leds;
        interface Random;
        interface Read<uint16_t>;
        interface Queue<UnicastMsg_t>  as SendQueue;
        interface Queue<UnicastMsg_t>  as ResultQueue;
        interface Queue<UpdateMsg_t>   as RouteQueue;
        interface Queue<UnicastMsg_t>  as TempQueue;
        /* Radio */
        interface Packet as RadioPacket;
        interface AMPacket as RadioAMPacket;
        interface AMSend as BroadcastAMSend;
        interface Receive as BroadcastReceive;
        interface AMSend as UnicastAMSend;
        interface Receive as UnicastReceive;
        interface SplitControl as RadioControl;
        /* Serial */
        interface Packet as SerialPacket;
        interface AMPacket as SerialAMPacket;
        interface AMSend as SerialAMSend;
        interface Receive as SerialReceive;
        interface SplitControl as SerialControl;
    }
}

implementation {

    Query_t         query[MAX_QUERIES];                     /* Query buffer that contains all the queries */
    route_info_t    routing_table[ROUTING_TABLE_MAX_SIZE];  /* Buffer to store my 1-hop neighbors */
    BroadcastMsg_t  buffer[BUFFER_MAX_SIZE];                /* Buffer to store broadcasted messages */
    BroadcastMsg_t  *bmsg;
    UnicastMsg_t    *umsg;
    UpdateMsg_t     *updmsg;
    Query_t my_qr;
    message_t pkt;                                          /* Message buffer */
    am_addr_t prev_hop;                                     /* The address of previous hop */
    uint8_t one_hop_neighbors[MAX_CHILDREN];                /* Buffer which holds the ids of our 1-hop children */
    uint8_t read[MAX_QUERIES];                              /* Buffer that contains 1 or 0, with 1 indicating if the query at that index corresponding to the query buffer, should read from the sensor or not */
    uint32_t start_time;                                    /* Holds the time when the QueryTimer started */
    uint16_t seq_no = 0;                                    /* Local sequence number */
    uint8_t ack_indicator = 0;                              /* Just to know when to send an update ACK */
    uint8_t fwd_indx = 0, buff_indx = 0, rt_indx = 0;       /* Indexes for buffers */
    uint8_t qr_indx = 0;                                    /* Index for query buffer */
    uint8_t carry = 0, reset = 0;                           /* Carry indicates the number of wrap arounds of the circular buffer, reset is a flag */
    uint8_t siblings = 0;                                   /* Indicates the number of siblings e.g same level nodes in the tree */
    uint8_t aggr_back_off = 0;                              /* A counter that is used to regulate the aggregation timer */
    uint8_t my_children = 0;                                /* Keep track of my children in the routing structure */
    uint8_t search_counter = 0;                             /* Counter for the number of tries a node has broadcasted a "get into the game" broadcast */
    bool busy = FALSE;                                      /* Indicates when a message can be send */
    bool received = FALSE;                                  /* Indicates if we have initiated a route request broadcast */
    bool request_upd = FALSE;                               /* Indicates if there is an entry to-be-inactive in the routing table, so that we can send an update request */
    bool pending_ack = FALSE;                               /* Indicates whether we have a pending ack to send for a new node or not */
    bool flood = FALSE;                                     /* Just a flag to know when a packet is for flooding or unicast */

    /* Forward declaration of tasks */
    task void broadcastMsg();
    task void forwardMsg();
    task void unicastMsg();
    task void bufferMsg();
    task void bufferResult();
    task void update();
    task void requestUpdate();
    task void sendUpdateAck();
    task void serialSend();

    void sendValues();

    /** Recursive function to merge packets for PIGGYBACK or STATS mode
      * head, sub each of them will hold the first packet with the opposite aggregation mode
      */
    void merge(UnicastMsg_t *head, UnicastMsg_t *sub) {
        UnicastMsg_t temp;
        UnicastMsg_t *curr = head;
        UnicastMsg_t *next;
        uint8_t num_vals;
        if(call TempQueue.empty()) {
            /* Add them to the sendqueue if there are no more elements */
            call SendQueue.enqueue(*head);
            if(sub != NULL) {
                call SendQueue.enqueue(*sub);
            }
            return;
        }
        /* Get the next element from the queue */
        temp = call TempQueue.dequeue();
        next = &temp;
        /* If next element has different mode */
        if(head->mode != next->mode) {
            /* Recursive call with next element at the spot of sub */
            if(sub == NULL) {
                merge(head, next);
            }
            else {
                /* Set curr to point to the packet with the same mode as next, and let sub point to the other
                 * This is important so that the proccessing below will work in any case by appropriately setting curr
                 * This will work in any case because by default this function sets sub to the opposite mode of head's
                 */
                curr = sub;
                sub = head;
            }
        }
        if(curr->mode == PIGGYBACK) {
            /* Get the number of values that fit to our buffer */
            num_vals = VALUES_MAX_SIZE - curr->indx;
            if(num_vals > next->indx) {
                /* Copy exactly how many values fit to our buffer, get the whole buffer from next */
                memcpy(curr->values + curr->indx, next->values, next->indx * sizeof(nx_uint16_t));
                /* Copy the ids of the nodes that contributed to the values */
                memcpy(curr->ids + curr->indx, next->ids, next->indx * sizeof(nx_uint8_t));
                /* Update indx to reflect the copy */
                curr->indx += next->indx;
            }
            else {
                /* Copy exactly how many values fit to our buffer but from the end of next buffer */
                memcpy(curr->values + curr->indx, next->values + (next->indx - num_vals), num_vals * sizeof(nx_uint16_t));
                /* Copy the ids of the nodes that contributed to the values */
                memcpy(curr->ids + curr->indx, next->ids + (next->indx - num_vals), num_vals * sizeof(nx_uint8_t));
                /* Update indx to reflect the copy */
                curr->indx += num_vals;
                /* Update indx of next to ignore the copied values of his buffer */
                next->indx = next->indx - num_vals;
                /* Add curr to the sendqueue */
                call SendQueue.enqueue(*curr);
                /* Set next as curr element for next recursion */
                curr = next;
            }
            /* Recursive call */
            merge(curr, sub);
        }
        else if(curr->mode == STATS) {
            /* Set min */
            curr->values[0] = (curr->values[0] < next->values[0]) ? curr->values[0] : next->values[0];
            /* Set max */
            curr->values[2] = (curr->values[2] < next->values[2]) ? next->values[2] : curr->values[2];
            /* Compute average */
            curr->values[1] = ((next->values[1] * next->indx) + (curr->values[1] * curr->indx)) / (next->indx + curr->indx);
            /* Copy the ids of the nodes that contributed to the values */
            memcpy(curr->ids + curr->indx, next->ids, next->indx * sizeof(nx_uint8_t));
            /* Update curr indx to keep track of the number of nodes that contributed to the result */
            curr->indx += next->indx;
            /* Recursive call */
            merge(curr, sub);
        }
    }
    /* Recursive function  which calls another recursive function to merge the packets
     *  It scans the result queue and extracts all the values with the same period and calls merge()
     *  it stops when there aren't any more values in the result queue
     */
    void combine(UnicastMsg_t *curr) {
        uint8_t i, size;
        UnicastMsg_t temp;
        size = call ResultQueue.size();
        for(i=0; i<size; i++) {
            temp = call ResultQueue.dequeue();
            if(curr->period == temp.period) {
                // If you have the same period put it into the TempQueue
                call TempQueue.enqueue(temp);
            }
            else {
                // Otherwise re-put it in the back of the queue
                call ResultQueue.enqueue(temp);
            }
        }
        // Call the recursive function to merge packets from TempQueue
        merge(curr, NULL);
        if(!call ResultQueue.empty()) {
            // Get next element
            temp = call ResultQueue.dequeue();
            // Recursive call
            combine(&temp);
        } else {
        }
    }

    void updateBuffIndx() {
        if(buff_indx >= BUFFER_MAX_SIZE - 1) {
            reset = 1;
            carry++;
            buff_indx = 0;
            return;
        }
        buff_indx++;
    }

    void updateSeq() {
        if(seq_no >= SEQNO_MAX_SIZE) {
            seq_no = 0;
            return;
        }
        seq_no++;
    }

    void updateFwdIndx() {
        if(fwd_indx >= BUFFER_MAX_SIZE - 1) {
            carry--;
            fwd_indx = 0;
            return;
        }
        fwd_indx++;
    }

    void updateRtIndx() {
        if(rt_indx == ROUTING_TABLE_MAX_SIZE) {
            return;
        }
        rt_indx++;
    }

    void updateQrIndx() {
        if(qr_indx == MAX_QUERIES) {
            return;
        }
        qr_indx++;
    }

    void saveToBuffer(BroadcastMsg_t *ptr) {
        // Update hop counter to include myself
        ptr->hop_counter++;
        buffer[buff_indx] = *ptr;
        updateBuffIndx();
    }

    /* Checks if we have already saved the packet, just check node_id and seq_no */
    bool checkBuffer(uint8_t node_id, uint16_t seq) {
        uint8_t i;
        if(node_id == TOS_NODE_ID) {
            return TRUE;
        }
        for(i=0; i<(reset*BUFFER_MAX_SIZE + (1-reset)*buff_indx); i++) {
            if(node_id == buffer[i].qr.originator && seq == buffer[i].qr.seq_no) {
                return TRUE;
            }
        }
        return FALSE;
    }

    /* Returns the index of the first inactive routing entry in the buffer or -1 if it doesn't find any */
    int8_t getInactiveRoutePos() {
        uint8_t i;
        for(i=0; i<rt_indx; i++) {
            if(!routing_table[i].active) {
                return i;
            }
        }
        return -1;
    }

    /* Returns the position in the routing table of the originator or -1 in case it doesn't exist */
    int8_t getRoutingTablePosition(uint8_t originator) {
        uint8_t i;
        for(i=0; i<rt_indx; i++) {
            if(routing_table[i].originator == originator) {
                return i;
            }
        }
        return -1;
    }

    /* Resets the update status in every routing table entry */
    void resetUpdateStatus() {
        uint8_t i;
        for(i=0; i<rt_indx; i++) {
            routing_table[i].updated = FALSE;
        }
    }

    /* Create a new entry in our routing table for the specific originator */
    /* Create a new entry in our routing table for the specific originator */
    void newRoutingTableEntry(am_addr_t next_hop, uint8_t originator, uint8_t hop_counter) {
        int8_t pos;
        if(getRoutingTablePosition(originator) != -1) {
            // In case the originator exists return
            return;
        }
        pos = getInactiveRoutePos();
        if(pos == -1) {
            // No inactive entries
            if(rt_indx != ROUTING_TABLE_MAX_SIZE) {
                // We still have room in buffer
                pos = rt_indx;
            }
            else {
                // No inactive entries and no room in buffer
                return;
            }
        }
        routing_table[pos].next_hop  = next_hop;
        routing_table[pos].originator  = originator;
        routing_table[pos].hop_counter = hop_counter;
        routing_table[pos].missed_updates = 0;
        routing_table[pos].active = TRUE;
        routing_table[pos].updated = FALSE;
        updateRtIndx();
    }

    /* Update an already existent routing entry */
    void updateRoutingTableEntry(int8_t pos, am_addr_t next_hop, uint8_t originator, uint8_t hop_counter) {
        routing_table[pos].next_hop  = next_hop;
        routing_table[pos].originator  = originator;
        routing_table[pos].hop_counter = hop_counter;
        routing_table[pos].missed_updates = 0;
        routing_table[pos].active = TRUE;
        routing_table[pos].updated = FALSE;
    }

    /* Create a unicast message packet with the reading value */
    void packReadValue(uint16_t data, Query_t qr) {
        UnicastMsg_t temp;
        uint8_t i;
        for(i=0; i<3; i++) {
            temp.values[i] = data;
            /* If the mode is STATS we need to set data, to the three first fields in the buffer (min, avg, max) */
            if(qr.mode != STATS) {
                break;
            }
        }
        temp.period     = qr.period;
        temp.mode       = qr.mode;
        temp.originator = qr.originator;
        temp.type       = qr.type;
        temp.indx       = 1;
        temp.path_indx  = 0;
        temp.ids[0]     = TOS_NODE_ID;
        if(temp.mode == NONE) {
            call SendQueue.enqueue(temp);
            sendValues();
        }
        else {
            call ResultQueue.enqueue(temp);
        }
    }

    void adjustTimer(uint16_t new_period, uint8_t indx) {
        uint32_t curr_time, rem, mod;
        uint16_t curr_period;
        uint8_t  i;
        // We multiply everything by 1000 to convert it to milliseconds
        curr_time = call QueryTimer.getNow();
        curr_period = call QueryTimer.getdt();
        mod = curr_time % curr_period;
        rem = curr_period - mod; // time remianing b4 fire
        new_period = new_period * 1000;
        if(new_period > curr_period) {
            query[indx].ignore_counter = new_period / curr_period;
            return;
        }
        if(rem < new_period) {
            /* Ignore the first timer fired event of the newly query period cause remaining time is smaller of previous */
            query[indx].ignore_counter = 1;
            for(i=0; i<qr_indx; i++) {
                if(curr_period != query[i].period) {
                    query[i].ignore_counter += curr_period / new_period - 1;
                }
            }
            start_time = call QueryTimer.getNow();
            call QueryTimer.startPeriodicAt(curr_time + rem, new_period);
        }
        else {
            for(i=0; i<qr_indx; i++) {
                query[i].ignore_counter += ((query[i].period*1000) / new_period) - 1;
            }
            start_time = call QueryTimer.getNow();
            call QueryTimer.startPeriodic(new_period);
        }
    }

    /* Checks if a query is already stored and alive */
    bool queryExists(Query_t qr) {
        uint8_t i;
        for(i=0; i<qr_indx; i++) {
            if(query[i].originator == qr.originator && query[i].seq_no == qr.seq_no && query[i].lifetime > 0) {
                // It's a duplicate
                return TRUE;
            }
        }
        return FALSE;
    }

    /* Returns the index of the first inactive query in the buffer */
    int8_t getInactiveQueryPos() {
        uint8_t i;
        for(i=0; i<qr_indx; i++) {
            if(query[i].lifetime == 0) {
                return i;
            }
        }
        return -1;
    }

    /* Save the last received query to query struct */
    void saveQuery(Query_t qr) {
        if(queryExists(qr)) {
            return;
        }
        else {
            int8_t pos = getInactiveQueryPos();
            if(pos != -1) {
                // We are setting the new query to the spot of the first inactive in our buffer
                query[pos] = qr;
                updateQrIndx();
            }
            else {
                if(qr_indx != MAX_QUERIES) {
                    // No inactive query but we have room in buffer
                    query[qr_indx] = qr;
                    updateQrIndx();
                }
                else {
                    // Means we didn't find any inactive query and buffer is full
                    return;
                }
            }
        }
        if(call QueryTimer.isRunning()) {
            // We need to adjust the timer period
            adjustTimer(qr.period, qr_indx-1);
        }
        else {
            start_time = call QueryTimer.getNow();
            call QueryTimer.startPeriodic(qr.period * 1000);
        }
    }

    /* Checks every query if it's time to read a value from sensor and also updates the lifetime */
    bool needToRead() {
        uint8_t i;
        uint32_t curr_period = call QueryTimer.getdt();
        bool found = FALSE;
        for(i=0; i<qr_indx; i++) {
            // If query is alive and periods have synchronized e.g ignore_counter == 0
            if(query[i].ignore_counter == 0 && query[i].lifetime > 0) { // && query[i].type = SENSOR_TYPE
                if(query[i].type == SENSOR_TYPE) {
                    read[i] = 1;
                    found = TRUE;
                }
                else {
                    query[i].lifetime -= query[i].period;
                    query[i].ignore_counter = query[i].period*1000 / curr_period;
                }
            }
            else {
                query[i].ignore_counter--;
            }
        }
        return found;
    }


    /* Checks whether there are active queries */
    bool noActiveQueries() {
        uint8_t i;
        for(i=0; i<qr_indx; i++) {
            if(query[i].lifetime > 0) {
                return FALSE;
            }
        }
        return TRUE;
    }

    /* Scans the routing table for active entries that did not reply to the unicasts
     * e.g missed_updates == MAX_MISSED_UPDATES and marks them as inactive
     * returns TRUE in case it finds at least one entry that fits the criteria
     */
    bool needToUpdate() {
        uint8_t i;
        bool found = FALSE;
        for(i=0; i<rt_indx; i++) {
            if(routing_table[i].missed_updates == MAX_MISSED_UPDATES && routing_table[i].active) {
                routing_table[i].active = FALSE;
                found = TRUE;
            }
        }
        return found;
    }

    /* Wait a random back-off time before forwarding to avoid collisions */
    void startCollisionTimer() {
        uint16_t delay = 0;
        if(call CollisionTimer.isRunning()) {return;}
        /* This is in case we are in an early stage of the network and we have no knowledge about our siblings */
        if(flood || siblings == 0) {
            delay = call Random.rand16() % 20;
        }
        /* Add some back-off before each send according to our siblings */
        if(siblings != 0) {
            delay = call Random.rand16() % ((siblings + 1) * NETWORK_LAT + 20);
        }
        call CollisionTimer.startOneShot(delay);
    }

    /* This method is used whenever we have elements in the sendQueue,
     * to determine either to send them with unicast or report them via serial to the pc
     */
    void sendValues() {
        UnicastMsg_t temp;
        /* Gets first element without dequeueing it */
        temp = call SendQueue.element(0);
        if(temp.originator != TOS_NODE_ID) {
            startCollisionTimer();
        }
        else {
            post serialSend();
        }
    }

    /* Checks if 1-hop neighbor exists */
    bool neighborAlreadyExist(uint8_t neighbor) {
        uint8_t i;
        for(i=0; i<my_children; i++) {
            if(one_hop_neighbors[i] == neighbor) {
                return TRUE;
            }
        }
        return FALSE;
    }

    void saveOneHopNeighbor(nx_uint8_t path[], uint8_t indx) {
        /* We have to consider `only` the last entry of the path, that will be our 1-hop neighbor */
        if(neighborAlreadyExist(path[indx-1])) {return;}
        /* Check if my children reached max value */
        if(my_children < MAX_CHILDREN) {
            /* Save 1hop neighbor as my child */
            one_hop_neighbors[my_children] = path[indx-1];
            my_children++;
        }
    }

    /**  This task is used after we receive a broadcast msg.
      *  It checks if it's duplicate or not,
      *  starts a timer to forward it in case it's not duplicate,
      *  it checks if we feature the specific query sensor_type to allocate resources
      *  and finally it builds a routing structure from the source of the received message.
      */
    task void bufferMsg() {
        if(!checkBuffer(bmsg->qr.originator, bmsg->qr.seq_no)) {
            saveToBuffer(bmsg);
            flood = TRUE;
            startCollisionTimer();
            saveQuery(bmsg->qr);
            if(getRoutingTablePosition(bmsg->qr.originator) == -1) {
                newRoutingTableEntry(prev_hop, bmsg->qr.originator, bmsg->hop_counter);
            }
        }
        else {
            /* Drop duplicates */
            return;
        }
    }

    /** This task is used when we receive a unicast message.
      * It proccesses the unicast message according to it's aggregation mode.
      */
    task void bufferResult() {
        saveOneHopNeighbor(umsg->path, umsg->path_indx);
        /* Distinguish the various aggregation-modes */
        /* If any packet arrives after our aggregation-timer fired event, we treat it as `none` regardless of it's mode */
        if(umsg->mode == NONE || !call AggregationTimer.isRunning()) {
            if(!call AggregationTimer.isRunning()) {
                aggr_back_off += 1;
                call Leds.led0Toggle();
                ack_indicator++;
            }
            call SendQueue.enqueue(*umsg);
            sendValues();
        }
        else if(umsg->mode == PIGGYBACK) {
            call ResultQueue.enqueue(*umsg);
        }
        else if(umsg->mode == STATS) {
            call ResultQueue.enqueue(*umsg);
        }
    }

    task void forwardMsg() {
        if(!busy) {
            bmsg = (BroadcastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(BroadcastMsg_t)));
            if(bmsg == NULL) {
                return;
            }
            bmsg->group_id      = GROUP_ID;
            bmsg->hop_counter   = buffer[fwd_indx].hop_counter;
            bmsg->qr            = buffer[fwd_indx].qr;
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BroadcastMsg_t)) == SUCCESS) {
                updateFwdIndx();
                busy = TRUE;
            }
        }
    }

    task void broadcastMsg() {
        if(!busy) {
            bmsg = (BroadcastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(BroadcastMsg_t)));
            if(bmsg == NULL) {
                return;
            }
            bmsg->group_id      = GROUP_ID;
            bmsg->hop_counter   = 0;
            bmsg->qr            = my_qr;
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BroadcastMsg_t)) == SUCCESS) {
                updateSeq();
                busy = TRUE;
            }
        }
        else {
            post broadcastMsg();
        }
    }

    task void serialSend() {
        UnicastMsg_t temp;
        uint8_t size;
        if(!busy) {
            umsg = (UnicastMsg_t *) (call SerialPacket.getPayload(&pkt, sizeof(UnicastMsg_t)));
            if(umsg == NULL) {
                return;
            }
            /* Get the first element of the queue, set it's values to the umsg */
            temp = call SendQueue.dequeue();
            if(temp.mode == NONE) {
                size = temp.indx * sizeof(nx_uint16_t);
            }
            else if(temp.mode == PIGGYBACK) {
                size = temp.indx * sizeof(nx_uint16_t);
            }
            else if(temp.mode == STATS) {
                size = 3 * sizeof(nx_uint16_t);
            }
            memcpy(umsg->values, temp.values, size);
            memcpy(umsg->ids, temp.ids, temp.indx * sizeof(nx_uint8_t));
            umsg->period        = temp.period;
            umsg->mode          = temp.mode;
            umsg->originator    = temp.originator;
            umsg->indx          = temp.indx;
            umsg->type          = temp.type;
            memcpy(umsg->path, temp.path, (temp.path_indx) * sizeof(nx_uint8_t));
            umsg->path[temp.path_indx] = TOS_NODE_ID;
            umsg->path_indx = temp.path_indx + 1;
           if(call SerialAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(UnicastMsg_t)) == SUCCESS) {
               busy = TRUE;
           }
        }
    }

    task void unicastMsg() {
        uint8_t size;
        int8_t pos;
        am_addr_t addr;
        UnicastMsg_t temp;
        if(!busy) {
            umsg = (UnicastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(UnicastMsg_t)));
            if(umsg == NULL) {
                return;
            }
            /* Get the first element of the queue, and set the size for the memcpy */
            temp = call SendQueue.dequeue();
            if(temp.mode == NONE) {
                size = temp.indx * sizeof(nx_uint16_t);
            }
            else if(temp.mode == PIGGYBACK) {
                size = temp.indx * sizeof(nx_uint16_t);
            }
            else if(temp.mode == STATS) {
                size = 3 * sizeof(nx_uint16_t);
            }
            memcpy(umsg->values, temp.values, size);
            memcpy(umsg->ids, temp.ids, temp.indx * sizeof(nx_uint8_t));
            umsg->period        = temp.period;
            umsg->mode          = temp.mode;
            umsg->originator    = temp.originator;
            umsg->indx          = temp.indx;
            umsg->type          = temp.type;
            /* Include myself into the route-path */
            /* note: path_indx was initialized with zero */
            memcpy(umsg->path, temp.path, (temp.path_indx) * sizeof(nx_uint8_t));
            umsg->path[temp.path_indx] = TOS_NODE_ID;
            umsg->path_indx = temp.path_indx + 1;
            pos = getRoutingTablePosition(umsg->originator);
            if(pos == -1) {
                return;
            }
            addr = routing_table[pos].next_hop;
            if(call UnicastAMSend.send(addr, &pkt, sizeof(UnicastMsg_t)) == SUCCESS) {
                busy = TRUE;
                if(!routing_table[pos].updated && routing_table[pos].active) {
                    if(++routing_table[pos].missed_updates == MAX_MISSED_UPDATES) {
                        request_upd = TRUE;
                    }
                    routing_table[pos].updated = TRUE;
                }
            }
        }
    }

    /* Broadcast request for route info */
    task void sendUpdateAck() {
        uint8_t i;
        if(!busy) {
            updmsg = (UpdateMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(UpdateMsg_t)));
            if(updmsg == NULL) {
                return;
            }
            /* Set to the packet every originator in my routing table */
            updmsg->route_indx = 0;
            for(i=0; i<rt_indx; i++) {
                if(routing_table[i].active) {
                    updmsg->originator[i]  = routing_table[i].originator;
                    updmsg->hop_counter[i] = routing_table[i].hop_counter;
                    updmsg->next_hop[i]    = routing_table[i].next_hop;
                    updmsg->route_indx++;
                }
            }
            updmsg->query_indx = 0;
            for(i=0; i<qr_indx; i++) {
                if(query[i].lifetime > 0) {
                    updmsg->qr[i] = query[i];
                    updmsg->query_indx++;
                }
            }
            updmsg->addr = call RadioAMPacket.address();
            updmsg->siblings = my_children > 0 ? my_children-1 : my_children;
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(UpdateMsg_t)) == SUCCESS) {
                busy = TRUE;
            }
        }
    }

    /* This task is used to update the routing table, the queries, and siblings */
    task void update() {
        UpdateMsg_t curr;
        uint16_t addr[ROUTING_TABLE_MAX_SIZE];
        uint8_t  buf[ROUTING_TABLE_MAX_SIZE][2];
        uint8_t  sibl[ROUTING_TABLE_MAX_SIZE];
        uint8_t i, j, indx = 0;
        bool found = FALSE;
        /* Set to buf the nodes with the minimum hop_counter towards the originator */
        while(!call RouteQueue.empty()) {
            curr = call RouteQueue.dequeue();
            for(i=0; i<curr.query_indx; i++) {
                saveQuery(curr.qr[i]);
            }
            for(i=0; i<curr.route_indx; i++) {
                if(curr.next_hop[i] == call RadioAMPacket.address()) {
                    continue;
                }
                for(j=0; j<indx; j++) {
                    if(curr.originator[i] == buf[j][0]) {
                        found = TRUE;
                        if(curr.hop_counter[i] < buf[j][1]) {
                            buf[j][1] = curr.hop_counter[i];
                            addr[j]   = curr.addr;
                            sibl[j]   = curr.siblings;
                        }
                    }
                }
                if(!found) {
                    buf[indx][0] = curr.originator[i];
                    // We need the +1 in the right side of the below because every node will broadcast it's own hop_counter so we need to take into
                    // consideration the additional 1hop to reach us, to properly work on the update
                    buf[indx][1] = curr.hop_counter[i] + 1;
                    addr[indx]   = curr.addr;
                    sibl[indx]   = curr.siblings;
                    indx++;
                }
                found = FALSE;
            }
        }
        for(i=0; i<indx; i++) {
            int8_t pos;
            pos = getRoutingTablePosition(buf[i][0]);
            if(pos != -1) {
                // If we have an entry about the originator
                if(buf[i][1] < routing_table[pos].hop_counter || !routing_table[pos].active) {
                    // If our hop_counter is bigger than the one from the received routing update or it's an old table entry
                    updateRoutingTableEntry(pos, addr[i], buf[i][0], buf[i][1]);
                    // Inform everyone about the new entry or the smaller hop_counter
                    post sendUpdateAck();
                }
                else {
                    // Reset missed_updates because we received an ACK update from our next_hop
                    if(routing_table[pos].next_hop == addr[i]) {
                        routing_table[pos].missed_updates = 0;
                        routing_table[pos].active = TRUE;
                    }
                }
                // Check only the updated routing table entries and update siblings accordingly
                for(j=0; j<rt_indx; j++) {
                    if(addr[i] == routing_table[j].next_hop) {
                        // Update siblings only if the message comes from our next_hop e.g the parent
                       if(siblings < sibl[i]) {
                            siblings = sibl[i];
                        }
                    }
                }
            }
            else {
                // If we dont have an entry about the originator
                if(TOS_NODE_ID != buf[i][0]) {
                    // If i didn't receive myself as an originator create a new entry
                    newRoutingTableEntry(addr[i], buf[i][0], buf[i][1]);
                    post sendUpdateAck();
                }
            }
        }
    }

    /* Send a braodacast message with size 1 that indicates you request an update */
    task void requestUpdate() {
        ReqUpdateMsg_t *req;
        if(!busy) {
            req = (ReqUpdateMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(ReqUpdateMsg_t)));
            if(req == NULL) {
                return;
            }
            if(call SearchTimer.isRunning()) {
                // Means we are searching for queries-nodes
                req->new_node = 1;
            } else {
                req->new_node = 0;
            }
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(ReqUpdateMsg_t)) == SUCCESS) {
                busy = TRUE;
            }
        }
    }

    event void Boot.booted() {
        call RadioControl.start();
        call SerialControl.start();
        call SearchTimer.startOneShot(SEARCH_INTERVAL);
    }

    event void SearchTimer.fired() {
        search_counter += 1;
        if(rt_indx != 0 || qr_indx != 0 || search_counter == MAX_SEARCH_TRIES) {
            call SearchTimer.stop();
        }
        else {
            post requestUpdate();
            call SearchTimer.startOneShot((search_counter + 1) * SEARCH_INTERVAL);
        }
    }

    event void AggregationTimer.fired() {
        UnicastMsg_t temp;
        if(request_upd) {
            if(needToUpdate()) {
                post requestUpdate();
                request_upd = FALSE;
            }
        }
        else {
            if(received) {
                // You only need to update this if you have received
                 ack_indicator++;
                 call Leds.led0Toggle();
                 received = FALSE;
            }
            if(ack_indicator == MAX_ACK_INDICATOR) {
                call Leds.led2Toggle();
                post sendUpdateAck();
                received = FALSE;
                ack_indicator = 0;
            }
            else {
                /* This else statement satisfies the need to send an update ack even if ack_indicator isn't at MAX_SIZE
                 * Because we received a request for a newly inserted node
                 */
                 if(pending_ack) {
                    post sendUpdateAck();
                    pending_ack = FALSE;
                 }
            }
            call Leds.led1Toggle();
            if(!call ResultQueue.empty()) {
                /* Reset the updated status in every routing table entry for the next round */
                resetUpdateStatus();
                /* Get first element from the queue and start the recursive function to merge and combine the result packets */
                temp = call ResultQueue.dequeue();
                combine(&temp);
                if(!call SendQueue.empty()) {
                    sendValues();
                }
            }
        }
    }

    event void CollisionTimer.fired() {
        if(flood) {
            post forwardMsg();
            flood = FALSE;
        }
        else {
            post unicastMsg();
        }
    }

    event void QueryTimer.fired() {
        uint16_t t;
        if(needToRead()) {
            call Read.read();
        }
        /** The general formula to compute the waiting period at each node is:
          * f(t) = number of all nodes below me * (network_latency + proccesing_latency + C)
          */
        t = aggr_back_off * (NETWORK_LAT + PROCESS_LAT) + 20;
        call AggregationTimer.startOneShot(t);
        if(noActiveQueries()) {
            call QueryTimer.stop();
        }
    }

    event void Read.readDone(error_t result, uint16_t data) {
        if(result == SUCCESS) {
            uint8_t i;
            uint32_t curr_period = call QueryTimer.getdt();
            for(i=0; i<qr_indx; i++) {
                if(read[i] == 1) {
                    packReadValue(data, query[i]);
                    query[i].lifetime -= query[i].period;
                    if((query[i].period*1000) % curr_period == 0) {
                        query[i].ignore_counter = ((query[i].period*1000) / curr_period) - 1;
                    } else {
                        query[i].ignore_counter = query[i].period*1000 / curr_period;
                    }
                    read[i] = 0;
                }
            }
        }
    }

    event void RadioControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call RadioControl.start();
        }
    }

    event void RadioControl.stopDone(error_t err) {
    }

    event void SerialControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call SerialControl.start();
        }
    }

    event void SerialControl.stopDone(error_t err) {
    }

    event void BroadcastAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            busy = FALSE;
            if(buff_indx > fwd_indx || carry != 0) {
                startCollisionTimer();
            }
            if(!call SendQueue.empty()) {
                sendValues();
            }
        }
    }

    event void UnicastAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            busy = FALSE;
            if(!call SendQueue.empty()) {
                sendValues();
            }
            else if(request_upd) {
                // Means we have an entry at which we have already sent MAX_UNICASTS with no ACK
                // We have to wait for 1hop delay in case we get an ACK
                call AggregationTimer.startOneShot(2 * NETWORK_LAT + PROCESS_LAT + 150);
            }
        }
    }

    event void SerialAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            busy = FALSE;
            if(!call SendQueue.empty()) {
                sendValues();
            }
        }
    }

    event message_t *BroadcastReceive.receive(message_t *msg, void *payload, uint8_t len) {
         if(len == sizeof(ReqUpdateMsg_t)) {
            // We received a special message that indicates we need to send an update
            ReqUpdateMsg_t *req = (ReqUpdateMsg_t *)payload;
            if(req->new_node == 1) {
                // We have to send update Ack when our QueryTimer fires so that the new node will be "synchronized"
                pending_ack = TRUE;
            }
            else {
                post sendUpdateAck();
            }
        }
        else if(len == sizeof(BroadcastMsg_t)) {
            bmsg = (BroadcastMsg_t *)payload;
            prev_hop = call RadioAMPacket.source(msg);
            post bufferMsg();
        }
        else {
            updmsg = (UpdateMsg_t *)payload;
            call RouteQueue.enqueue(*updmsg);
            post update();
        }
        return msg;
    }

    event message_t *UnicastReceive.receive(message_t *msg, void *payload, uint8_t len) {
        /* It's a message with a result from a query */
        umsg = (UnicastMsg_t *)payload;
        received = TRUE;
        post bufferResult();
        return msg;
    }

    event message_t *SerialReceive.receive(message_t *msg, void *payload, uint8_t len) {
        SerialMsg_t *smsg;
        if(len == sizeof(SerialMsg_t)) {
            smsg = (SerialMsg_t *)payload;
            my_qr.lifetime = smsg->lifetime;
            my_qr.period = smsg->period;
            my_qr.mode = smsg->mode;
            my_qr.type = smsg->type;
            my_qr.seq_no = seq_no;
            my_qr.originator = TOS_NODE_ID;
            my_qr.ignore_counter = 0;
            saveQuery(my_qr);
            newRoutingTableEntry(TOS_NODE_ID, TOS_NODE_ID, 0);
            post broadcastMsg();
        }
        return msg;
    }
}
