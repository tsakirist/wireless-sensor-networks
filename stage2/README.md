# Stage 2 #

### Description ###

Develop an algorithm/mechanism for a **best-effort network-wide broadcast**.

The approach is to propagate a packet to nodes using simple **flooding**. For each broadcast, the system should, eventually, reach a **steady silent state** where nodes stop transmitting packets. To achieve this, duplicate packets should be handled appropriately.

Your mechanism should also try to **avoid collisions** that might occur if two or more nodes that are in range of each other attempt to transmit a packet simultaneously. This is especially important given that the radio support of the sensor nodes is rather simple (there are no sophisticated collision detection/avoidance schemes).

Evaluate your algorithm in TOSSIM for different network topologies (chain, tree, grid), different number of nodes, and different number of concurrent sources. Use an application issues a broadcast periodically.

For each case, **record**:

* the actual per-node transmissions
* the total number of transmissions
* the average per-node transmissions
* the coverage (number of nodes that received a given message)
* the minimum, average and maximum message latency.

Develop a simple application that uses the mechanism to propagate to the network every message it receives over the serial port.
