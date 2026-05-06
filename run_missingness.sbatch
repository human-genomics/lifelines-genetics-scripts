#!/bin/bash
#SBATCH --job-name=ll_missing
#SBATCH --output=logs/missing.%j.log
#SBATCH --error=logs/missing.%j.log
#SBATCH --time=02:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#
# Submit:  sbatch run_missingness.sbatch  (or via run_all.sh with dependency)
# Status:  squeue -u $USER
# Log:     logs/missing.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 13_missingness.sh "$@"
