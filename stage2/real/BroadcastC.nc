#include <Timer.h>
#include "BroadcastC.h"

module BroadcastC {

    uses {
        interface Boot;
        interface Leds;
        interface Timer<TMilli> as Timer;
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
    message_t pkt;
    uint16_t buffer[BUFFER_MAX_SIZE][2], seqNo = 0;
    uint8_t fwdIndx = 0, counter = 0, carry = 0, reset = 0;;
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
        /* Handle overflow of sequence number */
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
        updateCounter();
    }

    /* Checks if we have already forwarded the packet */
    bool checkBuffer() {
        uint8_t i;
        if(bmsg->nodeId == TOS_NODE_ID) {
            return TRUE;
        }
        for(i=0; i<(reset*BUFFER_MAX_SIZE + (1-reset)*counter); i++) {
            if(bmsg->nodeId == buffer[i][0] && bmsg->seqNo == buffer[i][1]) {
                return TRUE;
            }
        }
        return FALSE;
    }


    void startTimer() {
        uint16_t delay;
        if(call Timer.isRunning()) {
            return;
        }
        delay = call Random.rand16() % 50;
        call Timer.startOneShot(delay);
    }

    task void forwardMsg() {
        if(!busy) {
            bmsg = (BroadcastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(BroadcastMsg_t)));
            if(bmsg == NULL) {
                return;
            }
            bmsg->groupId = GROUP_ID;
            bmsg->nodeId = buffer[fwdIndx][0];
            bmsg->seqNo = buffer[fwdIndx][1];
            if(call RadioAMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BroadcastMsg_t)) == SUCCESS) {
                /* Light the yellow led on when forwarding a packet */
                call Leds.led1Toggle();
                updateFwdIndx();
                busy = TRUE;
            }
        }
    }

    task void bufferMsg() {
        if(checkBuffer()) {
            /* Light the red led on when dropping packet */
            call Leds.led0Toggle();
            return;
        }
        saveToBuffer();
        startTimer();
    }

    task void broadcastMsg() {
        if(!busy) {
            bmsg = (BroadcastMsg_t *) (call RadioPacket.getPayload(&pkt, sizeof(BroadcastMsg_t)));
            if(bmsg == NULL) {
                return;
            }
            bmsg->groupId = GROUP_ID;
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
        call RadioControl.start();
        call SerialControl.start();
    }

    event void Timer.fired() {
        post forwardMsg();
    }

    event void RadioControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call RadioControl.start();
        }
    }

    event void SerialControl.startDone(error_t err) {
        if(err != SUCCESS) {
            call SerialControl.start();
        }
    }

    event void RadioControl.stopDone(error_t err ) {
    }

    event void SerialControl.stopDone(error_t err) {
    }

    event void RadioAMSend.sendDone(message_t *msg, error_t err) {
        if(&pkt == msg) {
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
            if(GROUP_ID != bmsg->groupId) {
                return msg;
            }
            /* Light the blue led on when receiving a packet */
            call Leds.led2Toggle();
            post bufferMsg();
        }
        return msg;
    }

    event message_t *SerialReceive.receive(message_t *msg, void *payload, uint8_t len) {
        if(len == sizeof(nx_uint8_t)) {
            post broadcastMsg();
        }
        return msg;
    }
}
