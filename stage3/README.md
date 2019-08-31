# Stage 3

### Description

Provide support for **periodic, long-lived sensor measurement queries** in the wireless sensor network.

Each query has the following parameters:

* sensor type (based on a simple identification scheme)
* sampling period (in seconds)
* lifetime (in seconds)

Each query should be **propagated to all nodes** that feature the respective sensors. For this purpose, reuse the mechanism that was already developed in Assignment 2. When a node receives the query, it checks to see if it features the sensor in question. If so, it creates an entry (allocates resources for it) and starts processing the query immediately. A node can have several queries active at the same time. When the query lifetime expires, the node stops processing the query and removes the respective entry (releases resources).

The results of a query should be returned to the node that originally issued the query. For this purpose, nodes should build a **suitable ad-hoc routing structure** that is used for the propagation of the results back to the query originator. Make your implementation **robust against topology changes**, e.g., due to node movement/failures/additions.

In addition to the above parameters, a query also takes as a parameter the so-called **aggregation mode**:

* **none**: The originator receives individual sensor readings from each node. The routing structure is merely used to forward individual packets towards the originator.
* **piggyback**: The originator receives individual sensor readings from each node, but the routing structure is also exploited to piggy-back readings in a **single packet**, before forwarding them towards the originator. The case where a single packet cannot hold all readings (due to payload limitations) should be handled in an appropriate way.
* **stats**: The originator does not wish to receive individual readings, but the maximum, minimum and average sensor reading over all nodes. The routing structure should be used to perform **in-network processing**, so that each node (ideally) forwards only a single tripplet (min, max, avg) towards the originator.

In all cases, every packet that reaches the originator should include information that enables it to infer the nodes (or at least the number of nodes) that contributed to the value(s) received.

Also, the originator should be able to tell which values belong to which sampling period. Note that aggregation should be applied only to measurements that concern the **same** sampling period.

### Evaluation using TOSSIM

Evaluate your mechanism for different network topologies (chain, tree, grid), for the "none", "piggy-back" and "stats" modes. For each case, record (i) the total number of packet transmissions in the network, (ii) the per-node packet transmissions, (iii) the number of nodes that contribute to the (individual or aggregated) values that successfully reach the originator, and (iv) the result delay for each sampling period. Feel free to add any other metrics that you think are meaningful.

### Evaluation using real nodes

Develop an application that receives query commands from the serial port, propagates corresponding query requests to the network, and reports the results received via serial.

On the PC side, an application should let the user issue query commands to the node, and print the results as they are received from the node.

### Staging

1. Implement query propagation, activation and expiry.
2. Develop a solution that only supports the "none" aggregation mode.
3. Develop a solution that also supports the "piggy-back" aggregation mode.
4. Develop a solution that also supports the "stats" aggregation mode.
5. Add robustness against topology changes.
6. Extend your solution so that a node can handle multiple queries at the same time (the queries may originate from different nodes).
