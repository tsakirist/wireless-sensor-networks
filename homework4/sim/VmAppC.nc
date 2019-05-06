configuration VmAppC {
}

implementation {

    components MainC, VmC, LedsC, SerialActiveMessageC;
    components new TimerMilliC() as App0Timer;
    components new TimerMilliC() as App1Timer;
    components new TimerMilliC() as App2Timer;
    components new TimerMilliC() as CacheTimer;
    components new AlternateSensorC(30, 55 , 2) as LightSensor;
    components new SerialAMSenderC(AM_SMSG);
    components new SerialAMReceiverC(AM_SMSG);

    VmC.Read  -> LightSensor;
    VmC.Boot  -> MainC;
    VmC.Leds  -> LedsC;
    VmC.App0Timer   -> App0Timer;
    VmC.App1Timer   -> App1Timer;
    VmC.App2Timer   -> App2Timer;
    VmC.CacheTimer  -> CacheTimer;
    /* Serial AM */
    VmC.SerialControl   -> SerialActiveMessageC;
    VmC.SerialPacket    -> SerialAMSenderC;
    VmC.SerialAMPacket  -> SerialAMSenderC;
    VmC.SerialAMSend    -> SerialAMSenderC;
    VmC.SerialAMReceive -> SerialAMReceiverC;

}
