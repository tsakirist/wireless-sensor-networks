#include "VmC.h"

module VmC {

    uses {
        interface Boot;
        interface Leds;
        interface Read<uint16_t>;
        interface Timer<TMilli> as App0Timer;
        interface Timer<TMilli> as App1Timer;
        interface Timer<TMilli> as App2Timer;
        interface Timer<TMilli> as CacheTimer;
        /* Serial AM */
        interface Packet as SerialPacket;
        interface AMPacket as SerialAMPacket;
        interface AMSend as SerialAMSend;
        interface Receive as SerialAMReceive;
        interface SplitControl as SerialControl;
    }
}

implementation {

    message_t pkt;
    application_t apps[MAX_APPS];       /* Apllications buffer */
    uint8_t num_apps = 0;               /* Total number of applications in buffer */
    uint8_t active_apps = 0;            /* Indicates the number of active applications in the buffer */
    uint8_t app_indx = 0;               /* Current running application index for the task */
    uint8_t read_val;                   /* Hold the sensor reading value */
    bool busy = FALSE;
    /* Flags that represent the states of the Leds.
     * They are used to avoid invoking the Leds component if it's not needed.
     */
    bool led0_on = FALSE;
    bool led1_on = FALSE;
    bool led2_on = FALSE;

    /* Forward declaration of tasks */
    task void interpreter();

    /* Forward declaration of functions */
    void executeInstruction(application_t *, uint8_t, uint8_t, int16_t);
    void saveApplication(app_msg_t *);
    void save(app_msg_t *);
    void extend(app_msg_t *);
    void terminateApp(uint8_t);
    void startTimer(uint8_t, uint16_t);
    void stopTimer(uint8_t);
    void openLed(uint8_t);
    void closeLed(uint8_t);
    void read(application_t *, uint8_t);
    bool hasSecondArg(uint8_t);
    int8_t getAppPosition(uint8_t);
    int8_t getInactiveAppPosition();

    /* Starts a timer according to the index of the application in the applications buffer */
    void startTimer(uint8_t indx, uint16_t interval) {
        switch(indx) {
            case 0:
                call App0Timer.startOneShot(interval * 1000);
                break;
            case 1:
                call App1Timer.startOneShot(interval * 1000);
                break;
            case 2:
                call App2Timer.startOneShot(interval * 1000);
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

    /* Terminate the application with the given id */
    void terminateApp(uint8_t id) {
        uint8_t i;
        for(i=0; i<num_apps; i++) {
            if(apps[i].id == id && apps[i].active) {
                apps[i].active = FALSE;
                active_apps--;
                stopTimer(i);
                closeLed(i);
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
    int8_t getAppPosition(uint8_t id) {
        uint8_t i;
        for(i=0; i<num_apps; i++) {
            if(apps[i].id == id) {
                return i;
            }
        }
        return -1;
    }

    /* Saves the new application */
    void save(app_msg_t *amsg) {
        application_t *new_app;
        // app_msg_t2 *temp = (app_msg_t2 *)call SerialPacket.getPayload(&pkt, sizeof(app_msg_t2));
        int8_t pos = getAppPosition(amsg->id);
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
            terminateApp(amsg->id);
        }
        /* Initialize/Set application info */
        new_app = &apps[pos];
        new_app->bin_len = amsg->buf[0];
        new_app->init_len = amsg->buf[1];
        new_app->timer_len = amsg->buf[2];
        new_app->id = amsg->id;
        new_app->pc = 0;
        new_app->timer_fired = FALSE;
        new_app->pending_timer_fired = FALSE;
        new_app->waiting = FALSE;
        memset(new_app->reg, 0, 6 * sizeof(int8_t));
        if((new_app->bin_len <= MAX_PAYLOAD)) {
            new_app->indx = new_app->init_len + new_app->timer_len;
            memcpy(new_app->buf, amsg->buf + 3, (new_app->indx) * sizeof(uint8_t));
            new_app->active = TRUE;
            active_apps++;
            post interpreter();
        }
        else {
            memcpy(new_app->buf, amsg->buf + 3, (MAX_PAYLOAD - 3) * sizeof(uint8_t));
            new_app->indx = MAX_PAYLOAD - 3;
            // memcpy(temp->buf, new_app->buf, new_app->indx * sizeof(uint8_t));
            // call SerialAMSend.send(AM_BROADCAST_ADDR, &pkt, new_app->indx*sizeof(uint8_t));
        }
    }

    /* Saves the extension of the application */
    void extend(app_msg_t *amsg) {
        uint8_t len;
        application_t *new_app;
        // app_msg_t2 *temp = (app_msg_t2 *)call SerialPacket.getPayload(&pkt, sizeof(app_msg_t2));
        int8_t pos = getAppPosition(amsg->id);
        if(pos == -1) {
            /* The application doesn't exist e.g we never saved the 1st fragment */
            return;
        }
        len = amsg->len;
        new_app = &apps[pos];
        memcpy(new_app->buf + new_app->indx, amsg->buf, len * sizeof(uint8_t));
        new_app->indx += len;
        // memcpy(temp->buf, new_app->buf, new_app->indx * sizeof(uint8_t));
        // call SerialAMSend.send(AM_BROADCAST_ADDR, &pkt, new_app->indx*sizeof(uint8_t));
        if((new_app->init_len + new_app->timer_len) == new_app->indx) {
            new_app->active = TRUE;
            active_apps++;
            post interpreter();
        }
    }

    /* Saves the new application to the buffer */
    void saveApplication(app_msg_t *amsg) {
        if(amsg->fragment == 0) {
            /* In case it's a new application e.g the 1st fragment  */
            save(amsg);
        }
        else {
            /* In case it's an extension of the application e.g 2nd fragment */
            extend(amsg);
        }
    }

    /* Executes the given instruction */
    void executeInstruction(application_t *curr_app, uint8_t code, uint8_t arg1, int16_t arg2) {
        switch(code) {
            case ret:
                if(curr_app->pc >= curr_app->init_len) {
                    /* If you are inside the timer-handler */
                    if(!curr_app->pending_timer_fired) {
                        /* Reset flag only if there wasn't any other timer.fired event while executing the timer-handler */
                        curr_app->timer_fired = FALSE;
                    }
                    else {
                        /* If there was another timer.fired event while executing, curr_app->timer_fired will remain TRUE
                         * and the interpreter will execute the timer-handler again
                         */
                        curr_app->pending_timer_fired = FALSE;
                    }
                }
                /* Set pc to init_len to re-execute from the begining the timer-handler */
                curr_app->pc = curr_app->init_len;
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
                    startTimer(app_indx, arg2);
                }
                break;
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
            default:
                return TRUE;
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
         * 2. Finished init_handler and it's time for timer_handler e.g timer_fired flag
         * If no application meets the above criteria, the task won't repost itself and
         * it will be posted later from a TimerX.fired event.
         */
        for(i=0; i<num_apps; i++) {
            if(apps[app_indx].active) {
                if(apps[app_indx].pc < apps[app_indx].init_len && !apps[app_indx].waiting) {
                    break;
                }
                else if((apps[app_indx].pc >= apps[app_indx].init_len) && apps[app_indx].timer_fired && !apps[app_indx].waiting) {
                    break;
                }
                checked++;
            }
            app_indx = (app_indx == (num_apps - 1)) ? 0 : app_indx + 1;
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
        app_indx = (app_indx == (num_apps - 1)) ? 0 : app_indx + 1;
        post interpreter();
    }

    event void Boot.booted() {
        call SerialControl.start();
    }

    event void App0Timer.fired() {
        if(apps[0].timer_fired) {
            /* Another timer event happened while timer-handler was executing */
            apps[0].pending_timer_fired = TRUE;
        }
        else {
            apps[0].timer_fired = TRUE;
        }
        post interpreter();
    }

    event void App1Timer.fired() {
        if(apps[1].timer_fired) {
            /* Another timer event happened while timer-handler was executing */
            apps[1].pending_timer_fired = TRUE;
        }
        else {
            apps[1].timer_fired = TRUE;
        }
        post interpreter();
    }

    event void App2Timer.fired() {
        if(apps[2].timer_fired) {
            /* Another timer event happened while timer-handler was executing */
            apps[2].pending_timer_fired = TRUE;
        }
        else {
            apps[2].timer_fired = TRUE;
        }
        post interpreter();
    }

    event void CacheTimer.fired() {
    }

    event void Read.readDone(error_t res, uint16_t data) {
        if(res == SUCCESS) {
            uint8_t i, indx;
            term_msg_t *temp = (term_msg_t *)call SerialPacket.getPayload(&pkt, sizeof(term_msg_t));
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
            temp->id = data;
            // call Leds.led2Toggle();
            call SerialAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(term_msg_t));
            call CacheTimer.startOneShot(FRESH_INTERVAL);
            post interpreter();
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
            busy = FALSE;
        }
    }

    event message_t *SerialAMReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(term_msg_t)) {
            term_msg_t *tmsg = (term_msg_t *)payload;
            terminateApp(tmsg->id);
        }
        else {
            app_msg_t *amsg = (app_msg_t *)payload;
            saveApplication(amsg);
        }
        return msg;
    }
}
