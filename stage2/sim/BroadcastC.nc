#include <Timer.h>
#include "BroadcastC.h"
#include "Serial.h"

module BroadcastC {

    uses {
        interface Boot;
        interface Leds;
        interface Timer<TMilli> as Timer0;
        interface Timer<TMilli> as Timer1;
        interface Random;
        /* Radio */
        interface Packet as RadioPacket;
        interface AMPacket as RadioAMPacket;
        interface AMSend as RadioAMSend;
        interface Receive as RadioReceive;
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

    BroadcastMsg_t *bmsg;
    SerialMsg_t *smsg;
    message_t pkt;
    uint16_t buffer[BUFFER_MAX_SIZE][2], seqNo = 0;
    uint8_t fwdIndx = 0, counter = 0, carry = 0, reset = 0;
    bool busy = FALSE;

    void updateCounter() {
        if(counter >= BUFFER_MAX_SIZE - 1) {
            reset = 1;
            carry++;
            counter = 0;
            return;
        }
        counter++;
    }

    void updateSeq() {
        if(seqNo >= SEQNO_MAX_SIZE) {
            seqNo = 0;
            return;
        }
        seqNo++;
    }

    void updateFwdIndx() {
        if(fwdIndx >= BUFFER_MAX_SIZE - 1) {
            carry--;
            fwdIndx = 0;
            return;
        }
        fwdIndx++;
    }

    void saveToBuffer() {
        buffer[counter][0] = bmsg->nodeId;
        buffer[counter][1] = bmsg->seqNo;
        dbg("Buffer", "Saved packet nodeId: %hu seqNo: %hu @ %s\n", bmsg->nodeId, bmsg->seqNo, sim_time_string());
        updateCounter();
    }

    /* Checks if we have already forwarded the packet */
    bool checkBuffer() {
        uint8_t i;
        if(bmsg->nodeId == TOS_NODE_ID) {
            dbg("Buffer", "Node %hu packet dropped\n", TOS_NODE_ID);
            return TRUE;
        }
        for(i=0; i<(reset*BUFFER_MAX_SIZE + (1-reset)*counter); i++) {
            if(bmsg->nodeId == buffer[i][0] && bmsg->seqNo == buffer[i][1]) {
                dbg("Buffer", "Node %hu packet dropped\n", TOS_NODE_ID);
                return TRUE;
            }
        }
        return FALSE;
    }


    void startTimer() {
        uint16_t delay;
        if(call Timer1.isRunning()) {return;}
        delay = call Random.rand16() % 50;
        dbg("Timer1", "Timer1 @ Timer1 delay: %hu\n", delay);
        call Timer1.startOneShot(delay);
    }

    task void forwardMsg() {
        if(!busy) {
            bmsg = (BroadcastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(BroadcastMsg_t)));
            if(bmsg == NULL) {
                return;
            }
            bmsg->groupId = TOS_NODE_ID;
            /*bmsg->groupId = GROUP_ID;*/
            bmsg->nodeId = buffer[fwdIndx][0];
            bmsg->seqNo = buffer[fwdIndx][1];
            dbg("Forward", "Node %hu forwarding packet nodeId: %hu seqNo: %hu @ %s\n", TOS_NODE_ID, bmsg->nodeId, bmsg->seqNo, sim_time_string());
            if(call RadioAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BroadcastMsg_t)) == SUCCESS) {
                updateFwdIndx();
                busy = TRUE;
            }
        }
    }

    task void bufferMsg() {
        if(checkBuffer()) {
            return;
        }
        saveToBuffer();
        startTimer();
    }

    task void broadcastMsg() {
        if(!busy) {
            bmsg = (BroadcastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(BroadcastMsg_t)));
            dbg("Task", "Node %hu broadcasting %hu @ %s\n", TOS_NODE_ID, seqNo, sim_time_string());
            if(bmsg == NULL) {
                return;
            }
            bmsg->groupId = TOS_NODE_ID;
            /*bmsg->groupId = GROUP_ID;*/
            bmsg->nodeId  = TOS_NODE_ID;
            bmsg->seqNo   = seqNo;
            if(call RadioAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BroadcastMsg_t)) == SUCCESS) {
                updateSeq();
                busy = TRUE;
            }
        }
        else {
            post broadcastMsg();
        }
    }

    event void Boot.booted() {
        /*call AMControl.start();*/
        call RadioControl.start();
        call SerialControl.start();
        dbg("Boot", "Booted @ %s\n", sim_time_string());
    }

    event void Timer0.fired() {
        dbg("Timer0", "Timer0 fired @ %s\n", sim_time_string());
        post broadcastMsg();
    }

    event void Timer1.fired() {
        dbg("Timer1", "Timer1 fired @ %s\n", sim_time_string());
        post forwardMsg();
    }

    event void RadioControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call RadioControl.start();
        }
        else {
            // if(TOS_NODE_ID%4==0) {
            if(TOS_NODE_ID ==8) {
                call Timer0.startPeriodic(1000);
            }
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

    event void RadioAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
            dbg("SendDone", "Sent packet @ %s\n", sim_time_string());
            if(counter > fwdIndx || carry != 0) {
                startTimer();
            }
            busy = FALSE;
        }
    }

    event void SerialAMSend.sendDone(message_t *msg, error_t err) {
    }

    event message_t *RadioReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(BroadcastMsg_t)) {
            bmsg = (BroadcastMsg_t *)payload;
            dbg("Receive", "Node %hu from: %hu, received packet nodeId: %hu seqNo: %hu @ %s\n", TOS_NODE_ID, bmsg->groupId ,bmsg->nodeId, bmsg->seqNo, sim_time_string());
            /*if(GROUP_ID != bmsg->groupId) {
                return msg;
            }*/
            post bufferMsg();
        }
        return msg;
    }

    event message_t *SerialReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(SerialMsg_t)) {
            smsg = (SerialMsg_t *) payload;
            dbg("MySerial", "Received serial pkt %hhu\nTrying to broadcast it..", smsg->temp);
            post broadcastMsg();
        }
        return msg;
    }
}
