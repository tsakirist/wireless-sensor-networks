# Wireless Sensor Networks CE520 #

## Description
Implementation of a middleware that supports the efficient dissemination and execution of portable application code in the WSN and return of results back to the originator.

The middleware consists of a Virtual Machine enviroment that supports over-the-air programming (OTA) of the nodes, the dynamic loading/un-loading of applications and the concurrent execution of multiple applications.

A custom assembly-like language is used to write the applications that include event handlers and a limited set of instructions.

The underlying communication model of the VM includes the transparent construction of a routing structure that is robust against topology changes and is subsequently used for the in-network processing of the packets.

The middleware was developed in **nesC/TinyOS** and tested on **TOSSIM** and Intel's Imote2 platform.

### Notes

Each directory contains the step-by-step process in order to build the final VM which operates as explained above.
