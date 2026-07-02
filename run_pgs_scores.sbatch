#!/bin/bash
#SBATCH --job-name=ll_pgs_scores
#SBATCH --output=logs/pgs_scores.%j.log
#SBATCH --error=logs/pgs_scores.%j.log
#SBATCH --time=08:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --mail-user=mintza@mskcc.org,jmurray@invitroresearch.com
#SBATCH --mail-type=END,FAIL
#
# Submit:  sbatch run_pgs_scores.sbatch
# Status:  squeue -u $USER
# Log:     logs/pgs_scores.<jobid>.log

set -euo pipefail
ROOT=${LIFELINES_ROOT:-${SLURM_SUBMIT_DIR:-$(pwd)}}
cd "$ROOT"
mkdir -p logs
bash "$ROOT/14_score_pgs.sh" "$@"
