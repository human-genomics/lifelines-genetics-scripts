#!/bin/bash
#SBATCH --job-name=ll_kinship
#SBATCH --output=logs/kinship.%j.log
#SBATCH --error=logs/kinship.%j.log
#SBATCH --time=04:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Submit:  sbatch run_kinship.sbatch
# Status:  squeue -u $USER
# Log:     logs/kinship.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 10_kinship.sh "$@"
