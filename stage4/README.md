# Stage 4

### Description

Implement basic virtual machine support for the execution of portable application code. The VM environment must support the dynamic loading and unloading of an application, without requiring a system restart or reboot. It must also support the concurrent execution of multiple applications, without any "interference" between them -- each application is given the illusion of running alone in the system.

The loading and unloading of applications must be done via the serial port. Implement a simple protocol that allows a PC client to (i) upload and start the execution of an application, and (ii) terminate the execution of an application. The protocol should be one-way, from the PC client to the node (the other direction, from the node to the PC client, can be used for debugging). The client is responsible for assigning each application a unique identifier that can be used to terminate the application at a later point in time. If the identifier is already taken, the application is overwritten, i.e., the application with the same identifier is stopped/terminated and replaced by the new one.

For simplicity, we assume that application programs are structured in the form of 2 event handlers for: (i) initialization and (ii) timer expiration. In the same spirit of simplicity, the code of event handlers is written using a very primitive instruction set. More details are given below.

### Programming model

#### Application structure

The application consists of the following event handlers:

* The Init handler, which is executed, once, upon application start-up.
* The Timer handler, which is executed each time the application timer expires (assuming the application has set its timer).
For simplicity, each application can use/set at most one timer, and can provide a single handler for it. The equivalent functionality of having different handlers can be implemented by using a global variable in conjunction with switch-case logic inside the single handler.

#### State

Each application can use 6 one-byte general-purpose registers r1-r6.

These registers are allocated and initialized to 0 upon application start-up, **before** the Init handler is executed. The state of these registers **persists** across application handler invocations, i.e., changes made within the Init handler will be visible in the context of the invocation of the Timer handler, and changes made within the Timer handler will be visible in the context of the next invocation of this handler.

Apart from these registers, applications do not have any persistent state. Also, application-level handlers do not have any local variables. All operations must be done using registers *r1-r6*. The programmer is exclusively responsible for managing the register set of the application as needed in order to implement the desired functionality.

#### Execution

Application-level event handlers are run (interpreted) to completion. In other words, if an application-level event (in this case, timer expiration) occurs during the execution (interpretation) of an application-level event handler, the invocation of the respective application-level handler is deferred until the execution of the current application-level event handler is completed.

To be more responsive at the system level, the VM environment should execute application-level handlers (pseudo)concurrently (e.g., instruction-by-instruction). Moreover, the interpretation of application code should not block the system itself, and should be done using a suitable task (that interprets one or more instructions, and then re-posts itself). Of course, the execution state of each application handler must be properly preserved between task invocations (but this is trivial given the above memory model).

### Instructions and binary

#### Instruction set

The (intentionally primitive) instruction set for writing the code of event handlers is specified below.

Note that the instruction code takes only the 4 most significant bit of the first byte. The 4 least significant bits of the first byte are used to encode the number of the register to be used as an argument for this instruction (provided the instruction takes a register as an argument). Also, some instructions have a second argument, which is encoded in a second byte.

| **Code (4 msbits)** | **Mnemonic** | **1st argument (4 lsbits)** | **2nd argument (1 byte)** | **Description** |
|---|---|---|---|---|
| 0x0_ | ret | (none) 0 | (none) | ends handler execution |
| 0x1_ | set | <rx> 1-6 | <val> -127<=val<=127 | rx = val |
| 0x2_ | cpy | <rx> 1-6 | <ry> 1-6 | rx = ry |
| 0x3_ | add | <rx> 1-6 | <ry> 1-6 | rx = rx + ry |
| 0x4_ | sub | <rx> 1-6 | <ry> 1-6 | rx = rx-ry |
| 0x5_ | inc | <rx> 1-6 | (none) | rx = rx + 1 |
| 0x6_ | dec | <rx> 1-6 | (none) | rx = rx-1 |
| 0x7_ | max | <rx> 1-6 | <ry> 1-6 | rx = max(rx,ry) |
| 0x8_ | min | <rx> 1-6 | <ry> 1-6 | rx = min(rx,ry) |
| 0x9_ | bgz | <rx> 1-6 | <off> -127<=off<=127 | if ( rx > 0 ) pc = pc + off |
| 0xA_ | bez | <rx> 1-6 | <off> -127<=off<=127 | if ( rx == 0 ) pc = pc + off |
| 0xB_ | bra | (none) 0 | <off> -127<=off<=127 | pc = pc + off |
| 0xC_ | led | <val> 0-1 | (none) | if ( val != 0 ) turn led on else turn led off |
| 0xD_ | rdb | <rx> 1-6 | (none) | rx = current brightness value |
| 0xE_ | tmr | (none) 0 | <val> 0<=val<=255 | set timer to expire after val seconds (0 cancels the timer) |

**Implementation note**: Some VM instructions can be "complex" to implement (in TinyOS). For example, the rdb instruction requires invoking the brightness sensor component and waiting for the result to be returned via an event. This "waiting" should not block the runtime system, which may execute other (system-level) tasks in the meantime. Also, the VM environment can employ caching techniques to avoid an overly frequent sensor access from different concurrently running applications.

#### Binary format

The application binary has the following structure/format:

| **Position in binary** | **Information at that location** |
|---|---|
| 1 | Length of the application binary (Bin_Len) |
| 2 | Length of Init handler (Init_Len) |
| 3 | Length of Timer handler (Timer_len) |
| 4 | First instruction of Init handler |
| 4 + Init_Len | First instruction of Timer handler (if available) |

An application must provide at least the Init handler. Obviously, Bin_Len = 3 + Init_Len + Timer_Len. Also, since the binary size field is just 1-byte long, an application binary cannot be longer than 255 bytes.

#### Application Examples

Sample application programs are given below.

**App1**

This application does nothing, it simply returns when initialized.

>     --Init--
>        ret
>     --Init--

Here is the assembly code in hex:

>     Init:  00
>     Timer: (empty)

And the full binary file in hex:

>     04 01 00 00

**App2**

This application blinks the LED for 3 seconds, once.

>     --Init--
>        led      1
>        tmr      3
>        ret
>     --Init--
>     --Timer--
>        led      0
>        ret
>     --Timer--

Here is the assembly code in hex:

>     Init:  C1 E0 03 00
>     Timer: C0 00

And the full binary file in hex:

>      09 04 02 C1 E0 03 00 C0 00

**App3**

This application blinks the LED for 3 seconds periodically, every 10 seconds.

>      --Init--
>        led      1
>        set      r1      1
>        tmr      3
>        ret
>     --Init--
>     --Timer--
>        bez      r1      L1
>        led      0
>        set      r1      0
>        tmr      7
>        ret
>     L1 led      1
>        set      r1      1
>        tmr      3
>        ret
>     --Timer--

Here is the assembly code in hex:

>     Init:  C1 11 01 E0 03 00
>     Timer: A1 07 C0 11 00 E0 07 00 C1 11 01 E0 03 00

And the full binary file in hex:

>     17 06 0E C1 11 01 E0 03 00 A1 07 C0 11 00 E0 07 00 C1 11 01 E0 03 00

**App4**

This application reads the brightness sensor every 5 seconds and turns on the LED if the value is less than 50 (in the spirit of Assignment 1).

>     --Init--
>        tmr      5
>        ret
>     --Init--
>     --Timer--
>        rdb      r1
>        set      r2      50
>        sub      r2      r1
>        bgz      r2      L1
>        led      0
>        bra      L2
>     L1 led      1
>     L2 tmr      5
>        ret
>     --Timer--

Here is the assembly code in hex:

>     Init:  E0 05 00
>     Timer: D1 12 32 42 01 92 04 C0 B0 02 C1 E0 05 00

And the full binary file in hex:

>     14 03 0E E0 05 00 D1 12 32 42 01 92 04 C0 B0 02 C1 E0 05 00

### Assembler

The expected source format (in the spirit of the above examples) is as follows (in EBNF-like notation):

>     Program = InitHandler [TimerHandler].
>     InitHandler = InitLabel {Code} InitLabel.
>     TimerHandler = TimerLabel {Code} TimerLabel.
>     InitLabel = "--Init--" "\n".
>     TimerLabel = "--Timer--" "\n".
>     Code = [Labelname] "\t" Instruction "\t" [Argument1] "\t" [Argument2] \n".
>     Instruction = "ret" | ... | "tmr".
>     Argument1 = Regname | UInt8Value | Labelname | BitValue.
>     Argument2 = Regname | Int8Value | Labelname.
>     Regname = "r1" | "r2" | ... | "r6".
>     UInt8Value = 0..255.
>     Int8Value = -127..127.
>     Labelname = String.
>     BitValue = 0..1.

**White space**: Please note that the separator between the "components" of each instruction line are **tabs** (not spaces).

**Disclaimer**: The assembler comes with no guarantee! You use this software at your own risk. Please double check the code being generated. For this purpose, the assembler prints on the screen the code in hex, which you should compare to your own hex produced by hand (at least during the initial phase where the assembler may still have some bugs). You should also check that the binary is properly written in the output file. A simple way to inspect the file contents is by using the xxd program (with the option to print each byte separately):

>     xxd -g1 <filename>

The output printed by the assembler should be identical to that of the xxd program, **except** for the first three bytes of the file (these contain the program metadata, as per the binary format).
