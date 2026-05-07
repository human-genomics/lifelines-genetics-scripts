#!/bin/bash
#SBATCH --job-name=ll_freq
#SBATCH --output=logs/freq.%j.log
#SBATCH --error=logs/freq.%j.log
#SBATCH --time=01:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=2
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Submit:  sbatch run_freq.sbatch  (or via run_all.sh with dependency)
# Status:  squeue -u $USER
# Log:     logs/freq.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 08_compute_freq.sh "$@"
