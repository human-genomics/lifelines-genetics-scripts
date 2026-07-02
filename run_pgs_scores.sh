#!/bin/bash
# run_pgs_scores.sh
#
# PGS scoring entrypoint. Run on the LOGIN node after merged_rsid pfiles
# have been produced, usually after run_all.sh has completed:
#     bash run_pgs_scores.sh
#
# This downloads the public EGFR and HDL score files from S3, validates
# their simple PLINK score layout, and submits one SLURM scoring job.

set -euo pipefail
trap 'echo "[run_pgs_scores] ERROR on line $LINENO (last command: $BASH_COMMAND)" >&2' ERR

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

SCORE_DIR=pgs_scores
EXPECTED_SCORE_LINES=7356519

EGFR_URL=http://elvehoj.s3-website-us-east-1.amazonaws.com/egfr.plink_score.snpinfo_a1.tsv
HDL_URL=http://elvehoj.s3-website-us-east-1.amazonaws.com/hdl.plink_score.snpinfo_a1.tsv

EGFR_SCORE="$SCORE_DIR/egfr.plink_score.snpinfo_a1.tsv"
HDL_SCORE="$SCORE_DIR/hdl.plink_score.snpinfo_a1.tsv"

mkdir -p logs "$SCORE_DIR"

verify_score_file() {
    local score_file=$1

    [[ -s "$score_file" ]] || return 1
    head -n 1 "$score_file" | grep -qx $'SNP\tA1\tBETA' || return 1

    local n_lines
    n_lines=$(wc -l < "$score_file")
    [[ "$n_lines" -eq "$EXPECTED_SCORE_LINES" ]]
}

download_score_file() {
    local label=$1
    local url=$2
    local out=$3
    local tmp="${out}.tmp"

    if verify_score_file "$out"; then
        echo "[$label] $out already present and valid ($(wc -l < "$out") lines). Skipping download."
        return 0
    fi

    echo "[$label] downloading public score file..."
    echo "  $url"
    rm -f "$tmp"

    if command -v wget >/dev/null 2>&1; then
        wget --tries=3 --timeout=30 -O "$tmp" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl -L --fail --retry 3 --retry-delay 5 -o "$tmp" "$url"
    else
        echo "ERROR: neither wget nor curl is available for downloading score files" >&2
        exit 1
    fi

    if ! verify_score_file "$tmp"; then
        echo "ERROR: downloaded $label score file failed validation: $tmp" >&2
        exit 1
    fi

    mv "$tmp" "$out"
    echo "[$label] downloaded $(wc -l < "$out") lines to $out"
}

all_outputs_exist() {
    [[ -f gsa/pgs/egfr.sscore &&
       -f gsa/pgs/hdl.sscore &&
       -f affymetrix/pgs/egfr.sscore &&
       -f affymetrix/pgs/hdl.sscore ]]
}

download_score_file egfr "$EGFR_URL" "$EGFR_SCORE"
download_score_file hdl  "$HDL_URL"  "$HDL_SCORE"

if all_outputs_exist; then
    echo "[skip] pgs_scores: all four .sscore outputs already exist"
    echo "All outputs already present. Nothing submitted."
    exit 0
fi

for panel in gsa affymetrix; do
    [[ -f "$panel/merged_rsid.pgen" ]] || {
        echo "ERROR: $panel/merged_rsid.pgen missing - run 03_relabel_rsids.sh first" >&2
        exit 1
    }
done

JOB=$(sbatch \
    --parsable \
    --chdir="$ROOT" \
    --export=ALL,LIFELINES_ROOT="$ROOT" \
    "$ROOT/run_pgs_scores.sbatch")
[[ -n "$JOB" ]] || { echo "ERROR: failed to submit run_pgs_scores.sbatch" >&2; exit 1; }
echo "Submitted PGS scoring job: $JOB"

echo
echo "Monitor:  squeue -u \$USER"
echo "Log:      logs/pgs_scores.${JOB}.log"
