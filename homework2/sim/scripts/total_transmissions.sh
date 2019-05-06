#!/bin/bash
grep -iE "broadc|forwar" $1 | wc -l
