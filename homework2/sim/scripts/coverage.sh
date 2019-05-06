#!/bin/bash
grep -iw  "saved packet nodeId: $2 seqNo: $3" $1 | wc -l
