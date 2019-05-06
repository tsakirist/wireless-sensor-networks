# Assignment 5

### Description

Extend the VM environment developed in **Assignment 4** in order to produce a "complete" platform for applications that implement long-running queries with built-in support for returning results back to the originator (node that injected the application in the WSN), exploiting the mechanisms that have already been developed under **Assignment 2** and **Assignment 3**.

An application is injected into the WSN via a PC connected to a node via serial port, using the PC-to-node protocol developed as a part of **Assignment 4**. In turn, this node acts as the originator, and propagates the application to the entire network, in the spirit of the query dissemination in **Assignment 3**. Each node that receives a new application starts executing it, as per **Assignment 4**. To keep the implementation simple, application binaries are assumed to fit into a single network packet (this is feasible, at least for simple applications). Finally, the VM runtime environment comes with built-in support for returning the results to the source node (sink), in the spirit of the mechanism that was developed in **Assignment 3**.

Applications are removed from the WSN in a similar fashion. More specifically, the removal request is sent from the PC to the originator node, as per **Assignment 4**. In turn, the originator removes the application locally, and propagates the removal request to the rest of the network, via a best-effort broadcast **Assignment 2**. Once an application has been removed, the node automatically drops any data packets of that application which may be received from other nodes (that have not yet removed the application), and notifies the sender to remove the application. This "repair" mechanism is needed in case the original application removal request has not reached all nodes.

**Optional**: Feel free to provide an implementation that supports large applications, with fragmentation and reassembly of the binary into/from several packets. Obviously, in this case, a node can start executing an application only if its entire binary has been successfully received.

### Application binary

The application binary is extended to include a Message handler, which is invoked when a result message is received. This handler should be introduced **only** if the application wishes to intercept a message received, e.g., to perform in-network aggregation. The new, extended format is:

| **Position in binary** | **Information at that location** |
|---|---|
| 0 | Length of the application binary (LBin) |
| 1 | Length of *Init* handler (LInit) |
| 2 | Length of *Timer* handler (LTimer) |
| 3 | Length of *Msg* handler (LMsg) |
| 4 | First instruction of *Init* handler |
| 4 + LInit | First instruction of *Timer* handler |
| 4 + LInit + LTimer | First instruction of *Msg* handler |

Obviously, *LBin* = *4* + *LInit* + *LTimer* + *LMsg*.

### Execution model

The execution model remains the **same** (as before).

In addition, the runtime invokes the Message handler of an application when a message arrives for it.

### Application state

In addition to the general-purpose registers *r1-r6*, there are four additional special registers *r7-r8* and *r9-r10*, which are used for storing the (at most) 2-byte payload of outgoing and incoming application-level messages, respectively.

| **Mnemonic** | **Description** |
|---|---|
| r1-r6 | General purpose registers |
| r7-r8 | Outgoing message payload |
| r9-r10 | Incoming message payload |

Like the general-purpose registers, *r7, r8, r9, r10* are 1-byte long and are automatically initialized to 0 when application execution starts, and their state persists across handler invocations. However, *r9-r10* are automatically **overwritten** with the contents of a newly arrived result message, before invoking the *Message* handler of the application.

**Note:** For simplicity, only 2-byte application-level messages are supported. The application programmer is free to decide how to exploit these 2 bytes. For instance, when raw results are sent to the sink, only 1 byte could be used, whereas 2 bytes could be used in case of an aggregated result, with the second byte recording the number of values used to compute the aggregate.

### Underlying communication model

For each application that is propagated in the network, the VM runtime environment builds a routing structure, which is subsequently used to send results back to the originator. The building of the routing structure is transparent for the application (the programmer does not write any code for this). The sending of messages towards the originator is supported via the new *snd* instruction (see next).

The aggregation of results (in-network processing) is achieved by introducing a special timer option for aggregation. Instruction wise, this is done by extending the format and semantics of the *tmr* instruction (see next). When the application sets the timer in aggregation mode, the system automatically **adjusts** the actual timeout, depending on the node's position in the routing structure, so that the node waits to receive the results coming from other nodes. This adjustment is __transparent__ for the application programmer (the application code remains the same for all nodes).

If the application does not provide a *Message handler*, the system __transparently__ routes result messages back to the originator, without involving the application. Else, the message received is **not** routed to the originator, but is passed to the application by invoking the *Message handler*. In turn, the application can process and store the message contents, and/or decide to send a message of its own towards the originator using the *snd* instruction.

### Instruction set

The VM instruction set is **extended** as follows:

| **Code (4 msbits)** | **Mnemonic** | **1st argument (4 lsbits)** | **2nd argument (1 byte)** | **Description** |
|---|---|---|---|---|
| 0x0\_-0xD\_ | **as before** | **as before** | **as before** | **as before** |
| 0xE_ | tmr | <mode> 0-1 | <val> | Set timer to expire after val seconds (=0 cancels the timer): mode==0 (normal timeout mode), mode==1 (aggregation timeout mode) |
| 0xF_ | snd | 0 (send r7), 1 (send r7 & r8) | none | Send contents of r7-r8 towards the application sink;at the sink, this instruction should send the message over serial to the PC |



#### Application Examples

Some examples in pseudo-assembly and in raw binary format (ready for execution) follow.

**App1**

This application reads the brightness sensor every 60 seconds and sends the result to the source, without any aggregation.

>     --Init--
>        tmr      0     60
>        ret
>     --Init--
>     --Timer--
>        rdb      r7
>        snd      0
>        tmr      0     60
>        ret
>     --Timer--

Here is the assembly code in hex:

>     Init:  E0 3C 00
>     Timer: D7 F0 E0 3C 00

And the full binary file in hex:

>     0C 03 05 00 E0 3C 00 D7 F0 E0 3C 00

**App2**

Same as App1, but each node explicitly intercepts and retransmits towards the source/sink the results of its children (without touching the contents).

>     --Init--
>        tmr      0     60
>        ret
>     --Init--
>     --Timer--
>        rdb      r7
>        snd      0
>        tmr      0     60
>        ret
>     --Timer--
>     --Msg--
>        cpy      r7     r9     // copy received payload into transmission payload
>        snd      0
>        ret
>     --Msg--

Here is the assembly code in hex:

>     Init:  E0 3C 00
>     Timer: D7 F0 E0 3C 00
>     Msg:   27 09 F0 00

And the full binary file in hex:

>      10 03 05 04 E0 3C 00 D7 F0 E0 3C 00 27 09 F0 00

**App3**

This application reads the brightness sensor every 60 seconds and sends the minimum value to the source, with aggregation.

>      --Init--
>        set      r7     0      // init aggregation counter
>        set      r8     127    // init minimum value
>        tmr      1      60     // use aggregation mode
>        ret
>     --Init--
>     --Timer--
>        rdb      r1
>        inc      r7            // increment aggregation counter
>        min      r8      r1    // adjust minimum value
>        snd      1
>        set      r7      0     // init aggregation counter
>        set      r8      127   // adjust minimum value
>        tmr      1       60    // use aggregation mode
>        ret
>     --Timer--
>     --Msg--
>        add      r7     r9    // increment aggregation counter
>        min      r8     r10   // adjust minimum value
>        ret
>     --Msg--

Here is the assembly code in hex:

>     Init:  17 00 18 7F E1 3C 00
>     Timer: D1 57 88 01 F1 17 00 18 7F E1 3C 00
>     Msg:   37 09 88 0A 00

And the full binary file in hex:

>     1C 07 0C 05 17 00 18 7F E1 3C 00 D1 57 88 01 F1 17 00 18 7F E1 3C 00 37 09 88 0A 00

### Assembler

The updated version of the assembler (in Perl) for binary code generation can be found on **wsnasm2**.

The new features are briefly as follows:

* checking and code generation for (signed) int8 values
* checking and code generation for extended register set (r1-r10)
* checking and code generation for extended timer instruction
* checking and code generation for send instruction
* checking and code generation for message handler
* support for the new/extended binary format
