#!/bin/bash
WORD=$1
LOG=$2
DATE=`/bin/date`
if grep $WORD $LOG &> /dev/null; then
    /bin/logger "$DATE: I found word, Master!"
    exit 143
else
    exit 143
fi
