#!/bin/bash
#SBATCH --job-name=ll_extract
#SBATCH --output=logs/extract.%j.log
#SBATCH --error=logs/extract.%j.log
#SBATCH --time=24:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Full run:    sbatch run_extract.sbatch
# Smoke test:  sbatch run_extract.sbatch 22
# Status:      squeue -u $USER
# Log:         logs/extract.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 02_extract_plink.sh "$@"
