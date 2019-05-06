configuration BlinkAppC {
}

implementation {

	components MainC, BlinkC, LedsC, SerialActiveMessageC;
	components new TimerMilliC() as Timer;
	components new SerialAMSenderC(AM_BLINKMSG);
	components new SerialAMReceiverC(AM_BLINKMSG);
	components new HamamatsuS1087ParC() as LightSensor;

	BlinkC.Read 	-> LightSensor;
	BlinkC.Timer	-> Timer;
	BlinkC.Leds 	-> LedsC;
	BlinkC.Boot 	-> MainC;
	BlinkC.Packet 	-> SerialAMSenderC;
	BlinkC.AMPacket	-> SerialAMSenderC;
	BlinkC.AMSend	-> SerialAMSenderC;
	BlinkC.Receive	-> SerialAMReceiverC;
	BlinkC.AMControl-> SerialActiveMessageC;

}
