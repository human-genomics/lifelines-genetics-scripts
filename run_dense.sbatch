#!/bin/bash
#SBATCH --job-name=ll_dense
#SBATCH --output=logs/dense.%j.log
#SBATCH --error=logs/dense.%j.log
#SBATCH --time=01:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=2
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Submit:  sbatch run_dense.sbatch  (or via run_all.sh with dependency)
# Status:  squeue -u $USER
# Log:     logs/dense.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 05_extract_dense.sh "$@"
