configuration VmAppC {
}

implementation {

    components MainC, VmC, LedsC, ActiveMessageC, SerialActiveMessageC, RandomC;

    components new TimerMilliC() as App0Timer;
    components new TimerMilliC() as App1Timer;
    components new TimerMilliC() as App2Timer;
    components new TimerMilliC() as CacheTimer;
    components new TimerMilliC() as CollisionTimer;

    components new AlternateSensorC(30, 55 , 2) as LightSensor;

    components new AMSenderC(AM_BMSG) as BroadcastSender;
    components new AMReceiverC(AM_BMSG) as BroadcastReceiver;
    components new AMSenderC(AM_UMSG) as UnicastSender;
    components new AMReceiverC(AM_UMSG) as UnicastReceiver;
    components new SerialAMSenderC(AM_SMSG);
    components new SerialAMReceiverC(AM_SMSG);

    components new QueueC(unicast_msg_t, 10) as SendQueue;
    components new QueueC(unicast_msg_t, 10) as HandlerQueue;

    VmC.Read            -> LightSensor;
    VmC.Boot            -> MainC;
    VmC.Leds            -> LedsC;
    VmC.Random          -> RandomC;
    VmC.App0Timer       -> App0Timer;
    VmC.App1Timer       -> App1Timer;
    VmC.App2Timer       -> App2Timer;
    VmC.CacheTimer      -> CacheTimer;
    VmC.CollisionTimer  -> CollisionTimer;
    VmC.SendQueue       -> SendQueue;
    VmC.HandlerQueue    -> HandlerQueue;
    /* Radio */
    VmC.RadioControl    -> ActiveMessageC;
    /* Wiring for broadcasting packets */
    VmC.RadioPacket     -> BroadcastSender;
    VmC.RadioAMPacket   -> BroadcastSender;
    VmC.BroadcastAMSend -> BroadcastSender;
    VmC.BroadcastReceive-> BroadcastReceiver;
    /* Wiring for unicasting packets */
    VmC.UnicastAMSend   -> UnicastSender;
    VmC.UnicastReceive  -> UnicastReceiver;
    /* Serial */
    VmC.SerialPacket    -> SerialAMSenderC;
    VmC.SerialAMPacket  -> SerialAMSenderC;
    VmC.SerialAMSend    -> SerialAMSenderC;
    VmC.SerialReceive   -> SerialAMReceiverC;
    VmC.SerialControl   -> SerialActiveMessageC;
}
