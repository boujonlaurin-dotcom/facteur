#!/bin/bash
export PYTHONPATH=$PYTHONPATH:$(pwd)/packages/api
cd packages/api
./venv/bin/python scripts/import_sources.py --file sources/sources_candidates.csv
