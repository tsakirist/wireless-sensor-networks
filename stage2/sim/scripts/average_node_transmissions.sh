#!/bin/bash
per_node=$(sh ./node_transmissions.sh $1 $2)
total=$(sh ./total_transmissions.sh $1)
res=$(echo "scale=3; $per_node/$total" | bc -l)
per=$(echo "$res * 100" | bc -l)
echo "Percentage: $per%"
