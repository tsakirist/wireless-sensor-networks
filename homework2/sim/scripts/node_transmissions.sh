#!/bin/bash
grep -iE "node $2 broad|node $2 forwar" $1 | wc -l
