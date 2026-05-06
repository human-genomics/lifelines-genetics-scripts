#!/bin/bash
#SBATCH --job-name=ll_relabel
#SBATCH --output=logs/relabel.%j.log
#SBATCH --error=logs/relabel.%j.log
#SBATCH --time=02:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#
# Submit:  sbatch run_relabel.sbatch  (or via run_all.sh with dependency)
# Status:  squeue -u $USER
# Log:     logs/relabel.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 03_relabel_rsids.sh "$@"
