#!/bin/bash
# 14_score_pgs.sh
#
# Scores the two public SBayesRC-derived PGS files against the full
# rsid-keyed Lifelines pfiles for both genotyping panels.
#
# Run via SLURM:
#     sbatch run_pgs_scores.sbatch
# or, end-to-end with download + skip-check:
#     bash run_pgs_scores.sh
#
# Inputs:
#   pgs_scores/egfr.plink_score.snpinfo_a1.tsv  (from run_pgs_scores.sh)
#   pgs_scores/hdl.plink_score.snpinfo_a1.tsv   (from run_pgs_scores.sh)
#   gsa/merged_rsid.{pgen,pvar,psam}            (from 03_relabel_rsids.sh)
#   affymetrix/merged_rsid.{pgen,pvar,psam}
#
# Outputs:
#   gsa/pgs/egfr.sscore
#   gsa/pgs/hdl.sscore
#   affymetrix/pgs/egfr.sscore
#   affymetrix/pgs/hdl.sscore

set -euo pipefail
trap 'echo "[14] ERROR on line $LINENO (last command: $BASH_COMMAND)" >&2' ERR

ROOT=${LIFELINES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
cd "$ROOT"

SCORE_DIR=pgs_scores
EXPECTED_SCORE_LINES=7356519

EGFR_SCORE="$SCORE_DIR/egfr.plink_score.snpinfo_a1.tsv"
HDL_SCORE="$SCORE_DIR/hdl.plink_score.snpinfo_a1.tsv"

THREADS=${SLURM_CPUS_PER_TASK:-4}
if [[ -n "${SLURM_MEM_PER_NODE:-}" ]] && (( SLURM_MEM_PER_NODE > 2048 )); then
    MEM_MB=$(( SLURM_MEM_PER_NODE - 1024 ))
else
    MEM_MB=${PLINK_MEM_MB:-16000}
fi

# This scoring job only needs PLINK/2. Do not load PLINK/1.x here:
# both versions share the same Lmod "PLINK" family on the UMCG cluster,
# and loading PLINK/1.x after this would unload plink2.
module load PLINK/2.0-alpha6.20-20250707

verify_score_file() {
    local score_file=$1

    [[ -s "$score_file" ]] || {
        echo "ERROR: missing or empty score file: $score_file" >&2
        return 1
    }
    head -n 1 "$score_file" | grep -qx $'SNP\tA1\tBETA' || {
        echo "ERROR: $score_file does not have expected header: SNP<TAB>A1<TAB>BETA" >&2
        return 1
    }

    local n_lines
    n_lines=$(wc -l < "$score_file")
    [[ "$n_lines" -eq "$EXPECTED_SCORE_LINES" ]] || {
        echo "ERROR: $score_file has $n_lines lines; expected $EXPECTED_SCORE_LINES" >&2
        return 1
    }
}

echo "=== Pre-flight ==="
echo "  hostname:    $(hostname)"
echo "  job:         ${SLURM_JOB_ID:-<not under SLURM>}"
echo "  cwd:         $(pwd)"
command -v plink2 >/dev/null 2>&1 \
    || { echo "ERROR: plink2 not on PATH after module load" >&2; exit 1; }
for score_file in "$EGFR_SCORE" "$HDL_SCORE"; do
    verify_score_file "$score_file"
done
for panel in gsa affymetrix; do
    for ext in pgen pvar psam; do
        [[ -f "$panel/merged_rsid.$ext" ]] || {
            echo "ERROR: $panel/merged_rsid.$ext missing - run 03_relabel_rsids.sh first" >&2
            exit 1
        }
    done
done
echo "  resources:   ${THREADS} threads, ${MEM_MB} MB"
echo "  plink2:      $(plink2 --version 2>&1 | head -n 1)"
echo "  score rows:  $(( EXPECTED_SCORE_LINES - 1 )) variants per trait"
echo

score_trait() {
    local panel=$1
    local trait=$2
    local score_file=$3
    local outdir="$panel/pgs"
    local outbase="$outdir/$trait"
    local sscore="$outbase.sscore"

    mkdir -p "$outdir"

    if [[ -f "$sscore" ]]; then
        echo "  [$panel/$trait] $sscore already exists, skipping"
        return 0
    fi

    echo "  [$panel/$trait] scoring with $(basename "$score_file")..."
    plink2 \
        --pfile "$panel/merged_rsid" \
        --score "$score_file" 1 2 3 header cols=+scoresums \
        --threads "$THREADS" \
        --memory "$MEM_MB" \
        --out "$outbase"

    [[ -f "$sscore" ]] || {
        echo "ERROR: scoring did not produce $sscore" >&2
        exit 1
    }

    local n_samples
    n_samples=$(( $(wc -l < "$sscore") - 1 ))
    echo "  [$panel/$trait] wrote scores for $n_samples samples to $sscore"
}

for panel in gsa affymetrix; do
    echo "=== $panel ==="
    score_trait "$panel" egfr "$EGFR_SCORE"
    score_trait "$panel" hdl  "$HDL_SCORE"
    echo
done

echo "=== Done ==="
echo "  GSA:        gsa/pgs/egfr.sscore"
echo "              gsa/pgs/hdl.sscore"
echo "  Affymetrix: affymetrix/pgs/egfr.sscore"
echo "              affymetrix/pgs/hdl.sscore"
