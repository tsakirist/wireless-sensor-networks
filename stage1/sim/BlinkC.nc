#include <Timer.h>
#include "BlinkC.h"

module BlinkC {

	uses interface Leds;
	uses interface Boot;
	uses interface Timer<TMilli> as Timer;
	uses interface Read<uint16_t>;
	uses interface Packet;
	uses interface AMPacket;
	uses interface AMSend;
	uses interface Receive;
	uses interface SplitControl as AMControl;
}

implementation {

	message_t pkt;
	uint16_t interval = 1000;
	uint16_t threshold = 40;
	uint16_t brightVal;
	bool on = FALSE;
	bool busyRead = FALSE;
	bool busySend = FALSE;

	task void ledToggle() {
		if(brightVal < threshold && !on) {
			dbg("LedOn", "It is dark and we turn led on!\n", sim_time_string());
			call Leds.led2On();
			on = TRUE;
		}
		else if(brightVal >= threshold && on) {
			dbg("LedOff", "It is bright and we turn led off!\n", sim_time_string());
			call Leds.led2Off();
			on = FALSE;
		}
	}

	task void sendMsg() {
		BlinkMsg_t *msg = (BlinkMsg_t *) (call Packet.getPayload(&pkt, sizeof(BlinkMsg_t)));
		if(msg == NULL) {
			return;
		}
		msg->brightVal = brightVal;
		/* The serial stack will send it over serial port regardless of the AM address specified */
		if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BlinkMsg_t)) == SUCCESS) {
			busySend = TRUE;
		}
	}

	event void Boot.booted() {
		call AMControl.start();
	}

	event void AMControl.startDone(error_t err) {
		if(err != SUCCESS) {
			call AMControl.start();
		}
		else {
			call Timer.startPeriodic(interval);
		}
	}

	event void AMControl.stopDone(error_t err) {
	}

	event void Timer.fired() {
		dbg("BlinkC", "Timer fired @ %s.\n", sim_time_string());
		if(!busyRead) {
			call Read.read();
			busyRead = TRUE;
		}
	}

	event void Read.readDone(error_t result, uint16_t data) {
		busyRead = FALSE;
		if(result == SUCCESS) {
			brightVal = data;
			post ledToggle();
			if(!busySend) {
				post sendMsg();
			}
		}
	}

	event void AMSend.sendDone(message_t *msg, error_t err) {
		if(&pkt == msg) {
			BlinkMsg_t *bmsg = (BlinkMsg_t *) (call Packet.getPayload(&pkt, sizeof(BlinkMsg_t)));
			dbg("SendDone", "Message was sent! %hu\n", bmsg->brightVal);
			busySend = FALSE;
		}
	}

	event message_t *Receive.receive(message_t *msg, void *payload, uint8_t len) {
		if(len == sizeof(BlinkMsg_t)) {
			interval = ((BlinkMsg_t *) payload)->interval;
			dbg("Receive", "Received message %hu\n", interval);
			/* Replaces any current timer settings */
			call Timer.startPeriodic(interval);
			call Leds.led0Toggle();
		}
		return msg;
	}
}
