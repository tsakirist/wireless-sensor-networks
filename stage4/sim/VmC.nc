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
            default:
                dbg("Timer", "No valid timer to start!\n");
        }
    }

    /* Stops a timer according to the index of the application in the applications buffer */
    void stopTimer(uint8_t indx) {
        switch(indx) {
            case 0:
                call App0Timer.stop();
                dbg("Timer", "Stopping App0Timer!\n");
                break;
            case 1:
                call App1Timer.stop();
                dbg("Timer", "Stopping App1Timer!\n");
                break;
            case 2:
                call App2Timer.stop();
                dbg("Timer", "Stopping App2Timer!\n");
                break;
            default:
                dbg("Timer", "No valid timer to stop!\n");
        }
    }

    /* Opens the led according to the index of the application in the applications buffer */
    void openLed(uint8_t indx) {
        switch(indx) {
            case 0:
                if(!led0_on) {
                    /*call Leds.led0On();*/
                    dbg("Leds", "Turning led0 on!\n");
                    led0_on = TRUE;
                }
                break;
            case 1:
                if(!led1_on) {
                    /*call Leds.led1On();*/
                    dbg("Leds", "Turning led1 on!\n");
                    led1_on = TRUE;
                }
                break;
            case 2:
                if(!led2_on) {
                    /*call Leds.led2On();*/
                    dbg("Leds", "Turning led2 on!\n");
                    led2_on = TRUE;
                }
                break;
            default:
                dbg("Leds", "No valid led to open!\n");
        }
    }

    /* Closes the led according to the index of the application in the applications buffer */
    void closeLed(uint8_t indx) {
        switch(indx) {
            case 0:
                if(led0_on) {
                    /*call Leds.led0Off();*/
                    dbg("Leds", "Turning led0 off!\n");
                    led0_on = FALSE;
                }
                break;
            case 1:
                if(led1_on) {
                    /*call Leds.led1Off();*/
                    dbg("Leds", "Turning led1 off!\n");
                    led1_on = FALSE;
                }
                break;
            case 2:
                if(led2_on) {
                    /*call Leds.led2Off();*/
                    dbg("Leds", "Turning led2 off!\n");
                    led2_on = FALSE;
                }
                break;
            default:
                dbg("Leds", "No valid led to close!\n");
        }
    }

    /* Reads sensor data from cache or invokes the Read component in case cache data is not fresh */
    void read(application_t *curr_app, uint8_t indx) {
        if(call CacheTimer.isRunning()) {
            /* If data in cache is still fresh take it from there */
            dbg("Read", "Reading from cache, data still fresh! data: %hhu, app.id: %hhu\n", read_val, curr_app->id);
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
                dbg("MySerial", "Received id that already exists, terminating app with id: %hhu\n", id);
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
        uint8_t i;
        application_t *new_app;
        int8_t pos = getAppPosition(amsg->id);
        dbg("MySerial", "Inside save\n");
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
                    dbg("MySerial", "No room for new application!\n");
                    return;
                }
            }
        }
        else {
            /* The app id exists try to terminate it in case it's active */
            terminateApp(amsg->id);
        }
        dbg("MySerial", "pos: %hhu\n", pos);
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
            dbg("MySerial", "id: %hhu, bin_len: %hhu, init_len: %hhu, timer_len: %hhu\n", new_app->id, new_app->bin_len, new_app->init_len, new_app->timer_len);
            dbg("MySerial", "Application: ");
            for(i=0; i<(new_app->init_len + new_app->timer_len); i++) {
                dbg_clear("MySerial", "%x\t", new_app->buf[i]);
            }
            dbg_clear("MySerial", "pos: %hhu\n", pos);
            dbg("MySerial", "new_app.bin_len: %hhu, apps[0].bin_len: %hhu\n", new_app->bin_len, apps[0].bin_len);
        }
        else {
            memcpy(new_app->buf, amsg->buf + 3, (MAX_PAYLOAD - 3) * sizeof(uint8_t));
            new_app->indx = MAX_PAYLOAD - 3;
        }
    }

    /* Saves the extension of the application */
    void extend(app_msg_t *amsg) {
        uint8_t len, i;
        application_t *new_app;
        int8_t pos = getAppPosition(amsg->id);
        dbg("MySerial", "Inside extend\n");
        if(pos == -1) {
            /* The application doesn't exist e.g we never saved the 1st fragment */
            return;
        }
        len = amsg->len;
        new_app = &apps[pos];
        memcpy(new_app->buf + new_app->indx, amsg->buf, len * sizeof(uint8_t));
        new_app->indx += len;
        dbg("MySerial", "len: %hhu, new_app->indx: %hhu, new_app->init_len: %hhu, new_app->timer_len: %hhu\n",
        len, new_app->indx, new_app->init_len, new_app->timer_len);
        if((new_app->init_len + new_app->timer_len) == new_app->indx) {
            new_app->active = TRUE;
            active_apps++;
            post interpreter();
            dbg("MySerial", "id: %hhu, bin_len: %hhu, init_len: %hhu, timer_len: %hhu\n", new_app->id, new_app->bin_len, new_app->init_len, new_app->timer_len);
            dbg("MySerial", "Application: ");
            for(i=0; i<(new_app->init_len + new_app->timer_len); i++) {
                dbg_clear("MySerial", "%x\t", new_app->buf[i]);
            }
            dbg_clear("MySerial", "pos: %hhu\n", pos);
            dbg("MySerial", "new_app.bin_len: %hhu, apps[0].bin_len: %hhu\n", new_app->bin_len, apps[0].bin_len);
        }
    }

    /* Saves the new application to the buffer */
    void saveApplication(app_msg_t *amsg) {
        dbg("MySerial", "fragment: %hhu, id: %hhu\n", amsg->fragment, amsg->id);
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
            default:
                dbg("Execute", "No valid code instruction to execute!\n");
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
            dbg("Interpreter", "No more active apps!\n");
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
            if(apps[app_indx].active && !apps[app_indx].waiting) {
                if(apps[app_indx].pc < apps[app_indx].init_len) {
                    dbg("Interpreter", "Inside pc < init_len \n");
                    break;
                }
                else if((apps[app_indx].pc >= apps[app_indx].init_len) && apps[app_indx].timer_fired) {
                    dbg("Interpreter", "Inside pc >= init_len and timer_fired = TRUE\n");
                    break;
                }
                checked++;
                dbg("Interpreter", "Checked: %hhu\n", checked);
            }
            app_indx = app_indx == num_apps - 1 ? 0 : app_indx + 1;
            dbg("Interpreter", "app_indx: %hhu\n", app_indx);
            if(checked == active_apps) {
                dbg("Interpreter", "Checked == active , returning!\n");
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

    event void Boot.booted() {
        call SerialControl.start();
        dbg("Boot", "Booted!\n");

    }

    event void App0Timer.fired() {
        dbg("Timer", "App0Timer fired! @ %s\n", sim_time_string());
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
        dbg("Timer", "App1Timer fired! @ %s\n", sim_time_string());
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
        dbg("Timer", "App2Timer fired! @ %s\n", sim_time_string());
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
        dbg("Timer", "CacheTimer fired! Data in cache is not fresh! @ %s\n", sim_time_string());
    }

    event void Read.readDone(error_t res, uint16_t data) {
        if(res == SUCCESS) {
            uint8_t i, indx;
            for(i=0; i<num_apps; i++) {
                if(apps[i].waiting) {
                    /* Get the indx of the reg that will store the value */
                    indx = apps[i].reg[0];
                    apps[i].reg[indx] = data;
                    apps[i].waiting = FALSE;
                }
            }
            /* Keep this value in "cache" for a FRESH_INTERVAL to avoid an overly frequent sensor access */
            read_val = data;
            call CacheTimer.startOneShot(FRESH_INTERVAL);
            dbg("Read", "Read value: %hu\n", data);
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
        if(len == sizeof(app_msg_t)) {
            app_msg_t *amsg = (app_msg_t *)payload;
            dbg("MySerial", "\n");
            dbg("MySerial", "Received serial message!\n");
            saveApplication(amsg);
            dbg("MySerial", "\n");
        }
        else if(len == sizeof(term_msg_t)) {
            term_msg_t *tmsg = (term_msg_t *)payload;
            dbg("MySerial", "Received terminate message for application id: %hhu @ %s\n", tmsg->id, sim_time_string());
            terminateApp(tmsg->id);
        }
        return msg;
    }
}
