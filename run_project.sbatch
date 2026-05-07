#!/bin/bash
#SBATCH --job-name=ll_project
#SBATCH --output=logs/project.%j.log
#SBATCH --error=logs/project.%j.log
#SBATCH --time=02:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=2
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Submit:  sbatch run_project.sbatch  (or via run_all.sh with dependency)
# Status:  squeue -u $USER
# Log:     logs/project.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 07_project_and_assign.sh "$@"
