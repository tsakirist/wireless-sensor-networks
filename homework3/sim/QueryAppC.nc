configuration QueryAppC {
}

implementation {

    components QueryC, MainC, LedsC, ActiveMessageC, SerialActiveMessageC, RandomC;

    components new TimerMilliC() as AggregationTimer;
    components new TimerMilliC() as CollisionTimer;
    components new TimerMilliC() as QueryTimer;
    components new TimerMilliC() as SearchTimer;

    components new AMSenderC(AM_BMSG) as BroadcastSender;
    components new AMReceiverC(AM_BMSG) as BroadcastReceiver;
    components new AMSenderC(AM_UMSG) as UnicastSender;
    components new AMReceiverC(AM_UMSG) as UnicastReceiver;
    components new SerialAMSenderC(AM_SMSG);
    components new SerialAMReceiverC(AM_SMSG);

    components new AlternateSensorC(30, 50, 1) as LightSensor;

    components new QueueC(UnicastMsg_t, 10)  as SendQueue;
    components new QueueC(UnicastMsg_t, 10)  as ResultQueue;
    components new QueueC(UpdateMsg_t, 10)   as RouteQueue;
    components new QueueC(UnicastMsg_t, 10)  as TempQueue;

    QueryC.Read             -> LightSensor;
    QueryC.AggregationTimer -> AggregationTimer;
    QueryC.CollisionTimer   -> CollisionTimer;
    QueryC.QueryTimer       -> QueryTimer;
    QueryC.SearchTimer      -> SearchTimer;
    QueryC.Leds             -> LedsC;
    QueryC.Boot             -> MainC;
    QueryC.Random           -> RandomC;
    QueryC.SendQueue        -> SendQueue;
    QueryC.ResultQueue      -> ResultQueue;
    QueryC.RouteQueue       -> RouteQueue;
    QueryC.TempQueue        -> TempQueue;

    /* Radio */
    QueryC.RadioControl     -> ActiveMessageC;
    /* Wiring for broadcasting packets */
    QueryC.RadioPacket      -> BroadcastSender;
    QueryC.RadioAMPacket    -> BroadcastSender;
    QueryC.BroadcastAMSend  -> BroadcastSender;
    QueryC.BroadcastReceive -> BroadcastReceiver;
    /* Wiring for unicasting packets */
    QueryC.UnicastAMSend    -> UnicastSender;
    QueryC.UnicastReceive   -> UnicastReceiver;
    /* Serial */
    QueryC.SerialPacket     -> SerialAMSenderC;
    QueryC.SerialAMPacket   -> SerialAMSenderC;
    QueryC.SerialAMSend     -> SerialAMSenderC;
    QueryC.SerialReceive    -> SerialAMReceiverC;
    QueryC.SerialControl    -> SerialActiveMessageC;
}
