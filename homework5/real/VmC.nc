#include "VmC.h"

module VmC {

    uses {
        interface Boot;
        interface Leds;
        interface Random;
        interface Read<uint16_t>;
        interface Timer<TMilli> as App0Timer;
        interface Timer<TMilli> as App1Timer;
        interface Timer<TMilli> as App2Timer;
        interface Timer<TMilli> as CacheTimer;
        interface Timer<TMilli> as CollisionTimer;
        interface Queue<unicast_msg_t> as SendQueue;
        interface Queue<unicast_msg_t> as HandlerQueue;
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

    broadcast_msg_t buffer[BUFFER_MAX_SIZE];                    /* Buffer to store broadcasted messages */
    route_info_t routing_table[ROUTING_TABLE_MAX_SIZE];         /* Routing table */
    application_t apps[MAX_APPS];                               /* Apllications buffer */
    path_track_t p_track[MAX_APPS];                             /* Buffer that stores info about the path a single packet has taken for a specific app_id */
    uint8_t children_buf[MAX_CHILDREN];
    broadcast_msg_t *bmsg;
    unicast_msg_t *umsg;
    app_msg_t *amsg;
    term_msg_t tmsg;                                            /* Hold the termination info along with the address e.g either bcast or unicast */
    message_t pkt;                                              /* Message buffer */
    am_addr_t prev_hop;                                         /* The address of previous hop */
    uint16_t seq_no = 0;                                        /* Local sequence number */
    uint8_t children = 0;                                       /* Counter to hold the nubmer of my children */
    uint8_t siblings = 0;
    uint8_t all_nodes = 0;
    uint8_t pkt_send = 0;
    uint8_t global_period = 0;
    uint8_t period_counter = 0;                                 /* Local period counter, it's mainly used to ignore the second period while adjusting the back_off */
    uint8_t aggr_back_off = 0;                                  /* A counter that is used to adjust the timer in aggregation mode */
    uint8_t carry = 0, reset = 0;                               /* Carry indicates the number of wrap arounds of the circular buffer, reset is a flag */
    uint8_t fwd_indx = 0, buff_indx = 0, rt_indx = 0;           /* Indexes for buffers */
    uint8_t num_apps = 0;                                       /* Total number of applications in buffer */
    uint8_t active_apps = 0;                                    /* Indicates the number of active applications in the buffer */
    uint8_t app_indx = 0;                                       /* Current running application index for the task */
    uint8_t read_val;                                           /* Hold the sensor reading value */
    bool busy  = FALSE;                                        /* Indicates when a message can be send */
    bool flood = FALSE;                                        /* Just a flag to know when a packet is for flood or unicast */
    /* Flags that represent the states of the Leds.
     * They are used to avoid invoking the Leds component if it's not needed.
     */
    bool led0_on = FALSE;
    bool led1_on = FALSE;
    bool led2_on = FALSE;

    /* Forward declaration of tasks */
    task void interpreter();
    task void bufferMsg();
    task void bufferResult();
    task void broadcastMsg();
    task void forwardMsg();
    task void unicastMsg();
    task void serialMsg();
    task void terminateMsg();
    task void informMsg();

    /* Forward declaration of functions */
    void executeInstruction(application_t *, uint8_t, uint8_t, int16_t);
    void saveApplication(app_msg_t *);
    void save(app_msg_t *);
    void extend(app_msg_t *);
    void terminateApp(uint8_t, uint8_t);
    void startCollisionTimer();
    void startTimer(uint8_t, uint8_t, uint16_t);
    void stopTimer(uint8_t);
    void openLed(uint8_t);
    void closeLed(uint8_t);
    void read(application_t *, uint8_t);
    void setAppUniPayload(uint8_t);
    void setTermPayload(uint8_t, uint8_t, uint16_t);
    void sendValue();
    void updateBuffIndx();
    void updateSeq();
    void updateFwdIndx();
    void updateRtIndx();
    void saveToBuffer(broadcast_msg_t *);
    void newRoutingTableEntry(am_addr_t, uint8_t);
    void saveChild(uint8_t);
    bool checkBuffer(uint8_t, uint16_t);
    bool hasSecondArg(uint8_t);
    bool childExists(uint8_t);
    int8_t getAppPosition(uint8_t, uint8_t);
    int8_t getInactiveAppPosition();
    int8_t getRoutingTablePosition(uint8_t);

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

    void saveToBuffer(broadcast_msg_t *ptr) {
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
            if(node_id == buffer[i].app.originator && seq == buffer[i].seq_no) {
                return TRUE;
            }
        }
        return FALSE;
    }

    /* Returns true in case the give id exists as next_hop inside my routing_table */
    bool isMyParent(uint16_t id) {
        uint8_t i;
        for(i=0; i<rt_indx; i++) {
            if(routing_table[i].next_hop == id) {
                return TRUE;
            }
        }
        return FALSE;
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

    /* Create a new entry in our routing table for the specific originator */
    void newRoutingTableEntry(am_addr_t next_hop, uint8_t originator) {
        int8_t pos;
        if(getRoutingTablePosition(originator) != -1) {
            // In case the originator exists return
            return;
        }
        if(rt_indx != ROUTING_TABLE_MAX_SIZE) {
            // We still have room in buffer
            pos = rt_indx;
        }
        else {
            // No room in buffer
            return;
        }
        routing_table[pos].next_hop  = next_hop;
        routing_table[pos].originator  = originator;
        updateRtIndx();
    }

    /* Wait a random back-off time before forwarding to avoid collisions */
    void startCollisionTimer() {
        uint16_t delay = 0;
        if(call CollisionTimer.isRunning()) {return;}
        /* Add some back-off before each send according to our siblings */
        if(flood) {
            delay = call Random.rand16() % 20;
        }
        else {
            if(siblings != 0) {
                delay = call Random.rand16() % (siblings * CLSN_DELAY);
            }
        }
        call CollisionTimer.startOneShot(delay);
    }

    /* Starts a timer according to the index of the application in the applications buffer */
    void startTimer(uint8_t indx, uint8_t mode, uint16_t interval) {
        interval *= 1000;
        if(mode == 0) {
            apps[indx].aggr_mode = FALSE;
        }
        else if(mode == 1) {
            /* In case it's in aggregation mode adjust the interval accordingly */
            apps[indx].aggr_mode = TRUE;
            if(aggr_back_off != 0) {
                interval += aggr_back_off * AGGR_DELAY + CLSN_DELAY;
            }
        }
        switch(indx) {
            case 0:
                call App0Timer.startOneShot(interval);
                break;
            case 1:
                call App1Timer.startOneShot(interval);
                break;
            case 2:
                call App2Timer.startOneShot(interval);
                break;
        }
    }

    /* Stops a timer according to the index of the application in the applications buffer */
    void stopTimer(uint8_t indx) {
        switch(indx) {
            case 0:
                call App0Timer.stop();
                break;
            case 1:
                call App1Timer.stop();
                break;
            case 2:
                call App2Timer.stop();
                break;
            default:
        }
    }

    /* Opens the led according to the index of the application in the applications buffer */
    void openLed(uint8_t indx) {
        switch(indx) {
            case 0:
                if(!led0_on) {
                    call Leds.led0On();
                    led0_on = TRUE;
                }
                break;
            case 1:
                if(!led1_on) {
                    call Leds.led1On();
                    led1_on = TRUE;
                }
                break;
            case 2:
                if(!led2_on) {
                    call Leds.led2On();
                    led2_on = TRUE;
                }
                break;
        }
    }

    /* Closes the led according to the index of the application in the applications buffer */
    void closeLed(uint8_t indx) {
        switch(indx) {
            case 0:
                if(led0_on) {
                    call Leds.led0Off();
                    led0_on = FALSE;
                }
                break;
            case 1:
                if(led1_on) {
                    call Leds.led1Off();
                    led1_on = FALSE;
                }
                break;
            case 2:
                if(led2_on) {
                    call Leds.led2Off();
                    led2_on = FALSE;
                }
                break;
        }
    }

    /* Reads sensor data from cache or invokes the Read component in case cache data is not fresh */
    void read(application_t *curr_app, uint8_t indx) {
        if(call CacheTimer.isRunning()) {
            /* If data in cache is still fresh take it from there */
            curr_app->reg[indx] = read_val;
        }
        else {
            /* Keep track of the register (in the 0th spot of the reg buffer), when readDone signals set the value to that register */
            curr_app->reg[0] = indx;
            curr_app->waiting = TRUE;
            call Read.read();
        }
    }

    /* Sends the value either unicast or serial according to the originator field */
    void sendValue() {
        /* Peak at the first element in the SendQueue and check for the originator field */
        unicast_msg_t temp;
        temp = call SendQueue.element(0);
        if(temp.originator == TOS_NODE_ID) {
            post serialMsg();
        }
        else {
            startCollisionTimer();
        }
        if(global_period == 2 && children) {
            pkt_send++;
            if(pkt_send == all_nodes + 1) {
                post informMsg();
            }
        }
    }

    /* Initiliazes the fields of the unicast msg and enqueues it for a later send */
    void setAppUniPayload(uint8_t indx) {
        unicast_msg_t temp;
        application_t *curr_app = &apps[indx];
        temp.seq        = curr_app->seq;
        temp.reg7       = curr_app->reg[7];
        temp.reg8       = curr_app->reg[8];
        temp.originator = curr_app->originator;
        temp.id         = curr_app->id;
        temp.path_indx  = 0;
        /* If you're in the timer_handler just set your id */
        if(curr_app->pc >= curr_app->init_len && curr_app->pc < curr_app->init_len + curr_app->timer_len) {
            if(curr_app->aggr_mode) {
                memcpy(temp.path, p_track[indx].path, p_track[indx].path_indx * sizeof(uint8_t));
                temp.path_indx = p_track[indx].path_indx;
            }
        }
        /* If you're in the msg_handler just add your id to the path that already exists */
        else {
            memcpy(temp.path+temp.path_indx, p_track[indx].path, p_track[indx].path_indx * sizeof(uint8_t));
            temp.path_indx += p_track[indx].path_indx;
        }
        call SendQueue.enqueue(temp);
    }

    /* Sets the fields of the termination message */
    void setTermPayload(uint8_t id, uint8_t originator, uint16_t addr) {
        tmsg.id = id;
        tmsg.addr = addr;
        tmsg.originator = originator;
    }

    /* Terminate the application with the given id,originator and flood a termination msg to the network */
    void terminateApp(uint8_t id, uint8_t originator) {
        uint8_t i;
        for(i=0; i<num_apps; i++) {
            if(apps[i].id == id && apps[i].originator == originator && apps[i].active) {
                apps[i].active = FALSE;
                active_apps--;
                stopTimer(i);
                closeLed(i);
                post terminateMsg();
                return;
            }
        }
    }

    /* Returns the position of an inactive application or -1 in case it doesn't exist */
    int8_t getInactiveAppPosition() {
        uint8_t i;
        for(i=0; i<num_apps; i++) {
            if(!apps[i].active) {
                return i;
            }
        }
        return -1;
    }

    /* Returns the position of the application in the apps buffer with `id` or -1 in case it doesn't exist */
    int8_t getAppPosition(uint8_t id, uint8_t originator) {
        uint8_t i;
        for(i=0; i<num_apps; i++) {
            if(apps[i].id == id && apps[i].originator == originator && apps[i].active) {
                return i;
            }
        }
        return -1;
    }

    bool childExists(uint8_t id) {
        uint8_t i;
        for(i=0; i<children; i++) {
            if(children_buf[i] == id) {
                return TRUE;
            }
        }
        return FALSE;
    }

    void saveChild(uint8_t id) {
        if(!childExists(id)) {
            children_buf[children] = id;
            children++;
        }
    }

    /* Saves the new application */
    void save(app_msg_t *app) {
        application_t *new_app;
        int8_t pos = getAppPosition(app->id, app->originator);
        if(pos == -1) {
        /* In case the app id doesn't exist check if we have room in buffer */
            if(num_apps < MAX_APPS) {
                /* If we have room in the buffer */
                pos = num_apps++;
            }
            else {
                pos = getInactiveAppPosition();
                /* In case there is no room check for inactive entries */
                if(pos == -1) {
                    return;
                }
            }
        }
        else {
            /* The app id exists try to terminate it in case it's active */
            terminateApp(app->id, app->originator);
        }
        /* Initialize/Set application info */
        new_app = &apps[pos];
        new_app->originator = app->originator;
        new_app->bin_len = app->buf[0];
        new_app->init_len = app->buf[1];
        new_app->timer_len = app->buf[2];
        new_app->msg_len = app->buf[3];
        new_app->id = app->id;
        new_app->pc = 0;
        new_app->seq = 0;
        new_app->timer_fired = FALSE;
        new_app->waiting = FALSE;
        new_app->received = FALSE;
        new_app->aggr_mode = FALSE;
        memset(new_app->reg, 0, 11 * sizeof(int8_t));
        if((new_app->bin_len <= MAX_PAYLOAD)) {
            new_app->indx = new_app->init_len + new_app->timer_len + new_app->msg_len;
            memcpy(new_app->buf, app->buf + 4, (new_app->indx) * sizeof(uint8_t));
            new_app->active = TRUE;
            active_apps++;
            post interpreter();
            call Leds.led2Toggle();
        }
        else {
            memcpy(new_app->buf, app->buf + 4, (MAX_PAYLOAD - 4) * sizeof(uint8_t));
            new_app->indx = MAX_PAYLOAD - 4;
        }
    }

    /* Saves the extension of the application */
    void extend(app_msg_t *app) {
        uint8_t len;
        application_t *new_app;
        int8_t pos = getAppPosition(app->id, app->originator);
        if(pos == -1) {
            /* The application doesn't exist e.g we never saved the 1st fragment */
            return;
        }
        len = app->len;
        new_app = &apps[pos];
        memcpy(new_app->buf + new_app->indx, app->buf, len * sizeof(uint8_t));
        new_app->indx += len;
        if((new_app->init_len + new_app->timer_len + new_app->msg_len) == new_app->indx) {
            new_app->active = TRUE;
            active_apps++;
            post interpreter();
        }
    }

    /* Saves the new application to the buffer */
    void saveApplication(app_msg_t *app) {
        if(app->fragment == 0) {
            /* In case it's a new application e.g the 1st fragment  */
            save(app);
        }
        else {
            /* In case it's an extension of the application e.g 2nd fragment */
            extend(app);
        }
    }


    /* Executes the given instruction */
    void executeInstruction(application_t *curr_app, uint8_t code, uint8_t arg1, int16_t arg2) {
        switch(code) {
            case ret:
                /* In case we are in the init_handler */
                if(curr_app->pc <= curr_app->init_len) {
                    /* Give priority to the message handler */
                    if(curr_app->received) {
                        curr_app->pc = curr_app->init_len + curr_app->timer_len;
                    }
                    /* If we didn't receive set it to the beggining of timer_handler */
                    else {
                        curr_app->pc = curr_app->init_len;
                    }
                }
                /* In case we are in the timer_handler */
                else if(curr_app->pc <= curr_app->init_len + curr_app->timer_len) {
                    if(curr_app->received && !curr_app->aggr_mode) {
                        /* We only set the pc to the message_handler only if we received a packet that isn't in aggregation mode,
                         * this is important because once timer_handler, in aggregation mode has executed, we don't want to
                         * execute the message_handler after because that packet was late, so the middleware will have to
                         * route it transparently.
                         */
                        curr_app->pc = curr_app->init_len + curr_app->timer_len;
                    }
                    /* If we didn't receive set it to the beggining of timer_handler */
                    else {
                        curr_app->pc = curr_app->init_len;
                    }
                    curr_app->timer_fired = FALSE;
                    curr_app->seq = !curr_app->seq;
                    /* Re-initialize to zero everything */
                    p_track[app_indx].path_indx = 0;
                    memset(&p_track[app_indx], 0, MAX_NODES * sizeof(uint8_t));
                }
                /* In case we are in the message_handler */
                else {
                    /* Give priority to the message handler */
                    if(!call HandlerQueue.empty()) {
                        unicast_msg_t temp =  call HandlerQueue.dequeue();
                        curr_app->pc = curr_app->init_len + curr_app->timer_len;
                        curr_app->reg[9]  = temp.reg7;
                        curr_app->reg[10] = temp.reg8;
                        /* Copy the received path to the local buffer of that application id so that we can use it later from sendValue() */
                        memcpy(p_track[app_indx].path+p_track[app_indx].path_indx, umsg->path, umsg->path_indx * sizeof(uint8_t));
                        p_track[app_indx].path_indx += umsg->path_indx;
                    }
                    /* If we don't have any other received msgs set it to the beggining of timer_handler */
                    else {
                        curr_app->received = FALSE;
                        curr_app->pc = curr_app->init_len;
                        if(!curr_app->aggr_mode) {
                            p_track[app_indx].path_indx = 0;
                            memset(&p_track[app_indx], 0, MAX_NODES * sizeof(uint8_t));
                        }
                    }
                }
                break;
            case set:
                curr_app->reg[arg1] = arg2;
                break;
            case cpy:
                curr_app->reg[arg1] = curr_app->reg[arg2];
                break;
            case add:
                curr_app->reg[arg1] += curr_app->reg[arg2];
                break;
            case sub:
                curr_app->reg[arg1] -= curr_app->reg[arg2];
                break;
            case inc:
                curr_app->reg[arg1]++;
                break;
            case dec:
                curr_app->reg[arg1]--;
                break;
            case max:
                curr_app->reg[arg1] = curr_app->reg[arg1] < curr_app->reg[arg2] ? curr_app->reg[arg2] : curr_app->reg[arg1];
                break;
            case min:
                curr_app->reg[arg1] = curr_app->reg[arg1] < curr_app->reg[arg2] ? curr_app->reg[arg1] : curr_app->reg[arg2];
                break;
            case bgz:
                curr_app->pc = curr_app->reg[arg1] > 0 ? curr_app->pc - 1 + arg2 : curr_app->pc;
                break;
            case bez:
                curr_app->pc = curr_app->reg[arg1] == 0 ? curr_app->pc - 1 + arg2 : curr_app->pc;
                break;
            case bra:
                curr_app->pc = curr_app->pc - 1 + arg2;
                break;
            case led:
                if(arg1 != 0) {
                    openLed(app_indx);
                }
                else {
                    closeLed(app_indx);
                }
                break;
            case rdb:
                read(curr_app, arg1);
                break;
            case tmr:
                if(arg2 == 0) {
                    stopTimer(app_indx);
                }
                else if(arg2 > 0) {
                    startTimer(app_indx, arg1, arg2);
                }
                break;
            case snd:
                setAppUniPayload(app_indx);
                sendValue();
        }
    }

    /* Checks if we need to read one more byte for the instruction */
    bool hasSecondArg(uint8_t code) {
        switch(code) {
            case ret:
                return FALSE;
            case inc:
                return FALSE;
            case dec:
                return FALSE;
            case led:
                return FALSE;
            case rdb:
                return FALSE;
            case snd:
                return FALSE;
            default:
                return TRUE;
        }
    }

    /**  This task is used after we receive a broadcast msg.
      *  It checks if it's duplicate or not,
      *  starts a timer to forward it in case it's not duplicate,
      *  and finally it builds a routing structure from the source of the received message.
      */
    task void bufferMsg() {
        if(!checkBuffer(bmsg->app.originator, bmsg->seq_no)) {
            saveToBuffer(bmsg);
            flood = TRUE;
            startCollisionTimer();
            saveApplication(&bmsg->app);
            if(getRoutingTablePosition(bmsg->app.originator) == -1) {
                newRoutingTableEntry(prev_hop, bmsg->app.originator);
            }
        }
        else {
            /* Drop duplicates */
            return;
        }
    }

    /* This task checks the unicast message received */
    task void bufferResult() {
        int8_t pos = getAppPosition(umsg->id, umsg->originator);
        /* If it is 1-hop neighbor e.g child, take into consideration only the first period */
        if(global_period == 1) {
            if(umsg->path_indx == 1) {
                saveChild(umsg->path[0]);
            }
            all_nodes++;
        }
        if(pos == -1) {
            setTermPayload(umsg->id, umsg->originator, prev_hop);
            post terminateMsg();
        }
        else {
            bool mw_send = FALSE;
            /* In case there is NO message handler indicate the middleware to send it transparently */
            if(apps[pos].msg_len == 0) {
                mw_send = TRUE;
            }
            /* In case we received a message for an app that has aggregation mode on */
            if(apps[pos].aggr_mode) {
                /* If we receive a packet for a previous period, we have to adjust the back_off so that we can include it in the next periods */
                if(((apps[pos].pc > apps[pos].init_len) && (apps[pos].pc <= apps[pos].init_len + apps[pos].timer_len)) || (apps[pos].seq != umsg->seq)) {
                    /* In case timer_handler has started or it has finished and the sequence nubmers are different */
                    if(period_counter != 2) {
                        /* We have to ignore the second period because the second period didn't take into consideration the back_off that was previously computed */
                        aggr_back_off++;
                    }
                    mw_send = TRUE;
                }
            }
            if(mw_send) {
                call SendQueue.enqueue(*umsg);
                sendValue();
                return;
            }
            apps[pos].received = TRUE;
            /* In case no event_handler is executing at the moment for the specific application,
             * you have to set the appropriate fields and post the task
             */
            if(apps[pos].pc == apps[pos].init_len && !apps[pos].timer_fired) {
                /*call Leds.led0Toggle();*/
                /* Set app pc to the beggining of the message handler */
                apps[pos].pc = apps[pos].init_len + apps[pos].timer_len;
                /* Overwrite r9-r10 with the contents of the newly arrived result message */
                apps[pos].reg[9]  = umsg->reg7;
                apps[pos].reg[10] = umsg->reg8;
                /* Copy the received path to the local buffer of that application id so that we can use it later from sendValue() */
                memcpy(p_track[pos].path+p_track[pos].path_indx, umsg->path, umsg->path_indx * sizeof(uint8_t));
                p_track[pos].path_indx += umsg->path_indx;
                post interpreter();
            }
            /* In case an event handler is executing, enqueue it and raise a flag that will be processed from a ret instruction */
            else {
                call HandlerQueue.enqueue(*umsg);
            }
        }
    }

    /* This task is responsible for executing the instructions pseudo-concurrently 1-by-1
     * in a context of a Round Robin algorithm among all the active apllications
     */
    task void interpreter() {
        uint8_t code, arg1, curr_byte, checked = 0, i;
        uint16_t arg2 = 0;
        application_t *curr_app;
        /* Stop if we have no more active apps */
        if(active_apps == 0) {
            return;
        }
        /* Check if we have an application that should run
         * This can happen in two cases:
         * 1. Hasn't finished the init_handler
         * 2. Finished init_handler and it's time for timer_handler or message_handler
         * If no application meets the above criteria, the task won't repost itself and
         * it will be posted later from a TimerX.fired event or Receive.event.
         */
        for(i=0; i<num_apps; i++) {
            if(apps[app_indx].active) {
                if(!apps[app_indx].waiting) {
                    /* Init_handler */
                    if(apps[app_indx].pc < apps[app_indx].init_len) {
                        break;
                    }
                    /* Timer_handler */
                    else if((apps[app_indx].pc >= apps[app_indx].init_len && apps[app_indx].pc < apps[app_indx].init_len + apps[app_indx].timer_len) && apps[app_indx].timer_fired) {
                        break;
                    }
                    /* Message_handler */
                    else if((apps[app_indx].pc >= apps[app_indx].init_len + apps[app_indx].timer_len) && apps[app_indx].received) {
                        break;
                    }
                }
                checked++;
            }
            app_indx = app_indx == num_apps - 1 ? 0 : app_indx + 1;
            if(checked == active_apps) {
                return;
            }
        }
        curr_app = &apps[app_indx];                         /* Get the next active application */
        curr_byte = curr_app->buf[curr_app->pc++];          /* Get the first byte */
        code = (curr_byte & 0xf0) >> 4;                     /* Take the 4 MSB of the byte */
        arg1 = (curr_byte & 0x0f);                          /* Take the 4 LSB of the byte */
        if(hasSecondArg(code)) {
            arg2 = curr_app->buf[curr_app->pc++];           /* Get the second byte */
        }
        executeInstruction(curr_app, code, arg1, arg2);
        app_indx = app_indx == num_apps - 1 ? 0 : app_indx + 1;
        post interpreter();
    }

    /* It's used to broadcast either a new application or a terminate message */
    task void broadcastMsg() {
        if(!busy) {
            bmsg = (broadcast_msg_t *) (call RadioPacket.getPayload(&pkt, sizeof(broadcast_msg_t)));
            if(bmsg == NULL) {
                return;
            }
            bmsg->group_id      = GROUP_ID;
            bmsg->seq_no        = seq_no;
            bmsg->app           = *amsg;
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(broadcast_msg_t)) == SUCCESS) {
                updateSeq();
                busy = TRUE;
            }
        }
        else {
            post broadcastMsg();
        }
    }

    /* It's used to flood/forward a received broadcast mesasge */
    task void forwardMsg() {
        if(!busy) {
            bmsg = (broadcast_msg_t *) (call RadioPacket.getPayload(&pkt, sizeof(broadcast_msg_t)));
            if(bmsg == NULL) {
                return;
            }
            memcpy(bmsg, &buffer[fwd_indx], sizeof(broadcast_msg_t));
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(broadcast_msg_t)) == SUCCESS) {
                updateFwdIndx();
                busy = TRUE;
            }
        }
    }

    /* It's used to send either a result from an application or a terminate message but unicast to a specific node */
    task void unicastMsg() {
        if(!busy) {
            int8_t pos;
            am_addr_t addr;
            unicast_msg_t *temp = (unicast_msg_t *) (call RadioPacket.getPayload(&pkt, sizeof(unicast_msg_t)));
            if(temp == NULL) {
                return;
            }
            *temp = call SendQueue.dequeue();
            temp->path[temp->path_indx] = TOS_NODE_ID;
            temp->path_indx++;
            pos = getRoutingTablePosition(temp->originator);
            if(pos == -1) {
                return;
            }
            addr = routing_table[pos].next_hop;
            if(call UnicastAMSend.send(addr, &pkt, sizeof(unicast_msg_t)) == SUCCESS) {
                call Leds.led1Toggle();
                busy = TRUE;
            }
        }
    }

    /* It's used to send the results from applications to the serial */
    task void serialMsg() {
        if(!busy) {
            unicast_msg_t *temp = (unicast_msg_t *) (call SerialPacket.getPayload(&pkt, sizeof(unicast_msg_t)));
            if(temp == NULL) {
                return;
            }
            *temp = call SendQueue.dequeue();
            temp->path[temp->path_indx] = TOS_NODE_ID;
            temp->path_indx++;
            if(call SerialAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(unicast_msg_t)) == SUCCESS) {
                busy = TRUE;
            }
        }
    }

    /* It's used to send either broadcast or unicast a terminate message for an application */
    task void terminateMsg() {
        if(!busy) {
            term_msg_t *temp = (term_msg_t *) (call RadioPacket.getPayload(&pkt, sizeof(term_msg_t)));
            if(temp == NULL) {
                return;
            }
            memcpy(temp, &tmsg, sizeof(term_msg_t));
            /* Depending on the address we either broadcast-flood or unicast */
            if(temp->addr == AM_BROADCAST_ADDR) {
                if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(term_msg_t)) == SUCCESS) {
                    busy = TRUE;
                }
            }
            else {
                if(call UnicastAMSend.send(temp->addr, &pkt, sizeof(term_msg_t)) == SUCCESS) {
                    busy = TRUE;
                }
            }
        }
    }

    /* It's used to inform children about their siblings so that they can adjust their collision timer accordingly */
    task void informMsg() {
        if(!busy) {
            inform_msg_t *imsg = (inform_msg_t *) (call RadioPacket.getPayload(&pkt, sizeof(inform_msg_t)));
            if(imsg == NULL) {
                return;
            }
            imsg->siblings = children;
            if(call BroadcastAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(inform_msg_t)) == SUCCESS) {
                busy = TRUE;
            }
        }
    }

    event void Boot.booted() {
        call RadioControl.start();
        call SerialControl.start();
        call Leds.led2Toggle();
    }

    event void App0Timer.fired() {
        apps[0].timer_fired = TRUE;
        if(apps[0].aggr_mode && period_counter < 3) {
            period_counter++;
        }
        post interpreter();
    }

    event void App1Timer.fired() {
        apps[1].timer_fired = TRUE;
        if(apps[1].aggr_mode && period_counter < 3) {
            period_counter++;
        }
        post interpreter();
    }

    event void App2Timer.fired() {
        apps[2].timer_fired = TRUE;
        if(apps[2].aggr_mode && period_counter < 3) {
            period_counter++;
        }
        post interpreter();
    }

    event void CacheTimer.fired() {
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

    event void Read.readDone(error_t res, uint16_t data) {
        if(res == SUCCESS) {
            uint8_t i, indx;
            /* Because registers are 1 byte we need to take care of values > 1 byte */
            read_val = data > 127 ? 127 : data;
            for(i=0; i<num_apps; i++) {
                if(apps[i].waiting) {
                    /* Get the indx of the reg that will store the value */
                    indx = apps[i].reg[0];
                    apps[i].reg[indx] = read_val;
                    apps[i].waiting = FALSE;
                }
            }
            /* Keep this value in "cache" for a FRESH_INTERVAL to avoid an overly frequent sensor access */
            call CacheTimer.startOneShot(FRESH_INTERVAL);
            post interpreter();
        }
    }

    event void RadioControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call RadioControl.start();
        }
    }

    event void RadioControl.stopDone(error_t err) {
    }

    event void BroadcastAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            if(buff_indx > fwd_indx || carry != 0) {
                flood = TRUE;
                startCollisionTimer();
            }
            if(!call SendQueue.empty()) {
                sendValue();
            }
            busy = FALSE;
        }
    }

    event void UnicastAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            if(!call SendQueue.empty()) {
                sendValue();
            }
            busy = FALSE;
        }
    }

    event void SerialControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call SerialControl.start();
        }
    }

    event void SerialControl.stopDone(error_t err) {
    }

    event void SerialAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            if(!call SendQueue.empty()) {
                sendValue();
            }
            busy = FALSE;
        }
    }

    event message_t *BroadcastReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(inform_msg_t)) {
            inform_msg_t *imsg = (inform_msg_t *)payload;
            prev_hop = call RadioAMPacket.source(msg);
            /* This ensures that we take into consideration inform packets from parent and not from children */
            if(isMyParent(prev_hop)) {
                /* Update current siblings */
                siblings = imsg->siblings;
            }
        }
        else if(len == sizeof(term_msg_t)) {
            /* Terminate the app in case we received a flood-terminate msg */
            tmsg = *(term_msg_t *)payload;
            terminateApp(tmsg.id, tmsg.originator);
            call Leds.led0Toggle();
        }
        else {
            bmsg = (broadcast_msg_t *)payload;
            if(bmsg->group_id != GROUP_ID) {
                return msg;
            }
            prev_hop = call RadioAMPacket.source(msg);
            post bufferMsg();
        }
        return msg;
    }

    event message_t *UnicastReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(term_msg_t)) {
            tmsg = *(term_msg_t *)payload;
            setTermPayload(tmsg.id, tmsg.originator, AM_BROADCAST_ADDR);
            terminateApp(tmsg.id, tmsg.originator);
        }
        else {
            umsg = (unicast_msg_t *)payload;
            prev_hop = call RadioAMPacket.source(msg);
            post bufferResult();
        }
        return msg;
    }

    event message_t *SerialReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(serial_term_msg_t)) {
            serial_term_msg_t *stmsg = (serial_term_msg_t *)payload;
            setTermPayload(stmsg->id, TOS_NODE_ID, AM_BROADCAST_ADDR);
            terminateApp(tmsg.id, tmsg.originator);
        }
        else {
            amsg = (app_msg_t *)payload;
            amsg->originator = TOS_NODE_ID;
            post broadcastMsg();
            saveApplication(amsg);
        }
        return msg;
    }
}
