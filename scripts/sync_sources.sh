#!/bin/bash
echo "Starting sync script..."
export PYTHONPATH=$PYTHONPATH:$(pwd)/packages/api
cd packages/api
./venv/bin/python scripts/import_sources.py --file sources/sources_master.csv > ../../sync_log.txt 2>&1
echo "Sync script finished with exit code $?"
