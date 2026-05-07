#!/bin/bash
#SBATCH --job-name=ll_eur_project
#SBATCH --output=logs/eur_project.%j.log
#SBATCH --error=logs/eur_project.%j.log
#SBATCH --time=02:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=2
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Submit:  sbatch run_eur_project.sbatch  (or via run_all.sh with dependency)
# Status:  squeue -u $USER
# Log:     logs/eur_project.<jobid>.log

set -euo pipefail
mkdir -p logs
bash 12_project_eur_and_assign_groups.sh "$@"
