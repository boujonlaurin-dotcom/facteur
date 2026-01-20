#!/bin/bash
echo "Starting checks..." > check_log.txt
pwd >> check_log.txt
echo "PATH: $PATH" >> check_log.txt
which python3 >> check_log.txt
python3 --version >> check_log.txt
python3 scripts/verify_briefing_flow.py >> check_log.txt 2>&1
echo "Finished checks." >> check_log.txt
