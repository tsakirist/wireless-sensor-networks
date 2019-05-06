configuration BroadcastAppC {
}

implementation {

    components BroadcastC, MainC, LedsC, ActiveMessageC, SerialActiveMessageC, RandomC;
    components new TimerMilliC() as Timer;
    components new AMSenderC(AM_MSG);
    components new AMReceiverC(AM_MSG);
    components new SerialAMSenderC(AM_MSG);
    components new SerialAMReceiverC(AM_MSG);

    BroadcastC.Timer    -> Timer;
    BroadcastC.Leds     -> LedsC;
    BroadcastC.Boot     -> MainC;
    BroadcastC.Random   -> RandomC;
    /* Radio */
    BroadcastC.RadioPacket  -> AMSenderC;
    BroadcastC.RadioAMPacket -> AMSenderC;
    BroadcastC.RadioAMSend   -> AMSenderC;
    BroadcastC.RadioReceive  -> AMReceiverC;
    BroadcastC.RadioControl -> ActiveMessageC;
    /* Serial */
    BroadcastC.SerialPacket -> SerialAMSenderC;
    BroadcastC.SerialAMPacket -> SerialAMSenderC;
    BroadcastC.SerialAMSend -> SerialAMSenderC;
    BroadcastC.SerialReceive -> SerialAMReceiverC;
    BroadcastC.SerialControl -> SerialActiveMessageC;
}
