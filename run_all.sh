#!/bin/bash
# run_all.sh
#
# Convenience entrypoint. Run on the LOGIN node:
#     bash run_all.sh
#
# Steps:
#   1. Downloads snp.info, the dense rsid list, and the public-statgen
#      PCA reference (login node, idempotent). The EUR-balanced PCA
#      reference and centroids_pc6.tsv are shipped with the repo.
#   2. For each compute step, checks whether its final outputs already
#      exist. If yes, skips submitting that sbatch job entirely. If no,
#      submits it with --dependency=afterok on the most recent ancestor
#      that actually ran. So a re-run of run_all.sh after success
#      submits zero jobs and exits in seconds.
#
# DAG:
#   01,04,06 (login)
#         │
#         ▼
#   extract -> relabel ─┬─► dense ─┬─► project
#                       │          └─► eur_project
#                       ├─► freq
#                       └─► missing
#
# Note: kinship is a SEPARATE pipeline (run_kinship.sh) — not in this DAG.
# After this finishes:
#       bash run_kinship.sh
#
# Recommended smoke test before committing to the full pipeline:
#     bash 01_download_snp_info.sh
#     sbatch run_extract.sbatch 22       # chr 22 only, ~5–10 min on compute
#     # inspect logs/extract.<jobid>.log; if happy, then:
#     bash run_all.sh

set -euo pipefail
trap 'echo "[run_all] ERROR on line $LINENO (last command: $BASH_COMMAND)" >&2' ERR

mkdir -p logs

bash 01_download_snp_info.sh
bash 04_download_dense_rsids.sh
bash 06_download_pca_ref.sh

# Submit $script with optional --dependency, unless the step's final
# outputs (checked by $skip_check) already exist. Echoes the job id (or
# empty string if skipped) so the caller can chain dependencies.
maybe_submit() {
    local label=$1
    local script=$2
    local skip_check=$3
    local dep_id=$4

    if eval "$skip_check"; then
        echo "  [skip] $label: outputs already present" >&2
        echo ""
        return 0
    fi

    local args=()
    [[ -n "$dep_id" ]] && args+=(--dependency=afterok:"$dep_id")

    local jobid
    jobid=$(sbatch --parsable "${args[@]}" "$script")
    [[ -n "$jobid" ]] || { echo "ERROR: failed to submit $script" >&2; exit 1; }

    if [[ -n "$dep_id" ]]; then
        echo "  Submitted $label: $jobid (after $dep_id)" >&2
    else
        echo "  Submitted $label: $jobid" >&2
    fi
    echo "$jobid"
}

# Each skip_check tests the final output(s) of the step.
JOB1=$(maybe_submit "extract"     run_extract.sbatch \
    '[[ -f gsa/merged.pgen           && -f affymetrix/merged.pgen           ]]' "")

JOB2=$(maybe_submit "relabel"     run_relabel.sbatch \
    '[[ -f gsa/merged_rsid.pgen      && -f affymetrix/merged_rsid.pgen      ]]' "$JOB1")

JOB3=$(maybe_submit "dense"       run_dense.sbatch \
    '[[ -f gsa/dense.pgen            && -f affymetrix/dense.pgen            ]]' "$JOB2")

JOB4=$(maybe_submit "project"     run_project.sbatch \
    '[[ -f gsa/dense_assigned_superpop.csv && -f affymetrix/dense_assigned_superpop.csv ]]' "$JOB3")

JOB5=$(maybe_submit "freq"        run_freq.sbatch \
    '[[ -f gsa/freq_diff_ge_0.2.csv  && -f affymetrix/freq_diff_ge_0.2.csv  ]]' "$JOB2")

JOB6=$(maybe_submit "eur_project" run_eur_project.sbatch \
    '[[ -f gsa/dense_eur_top10_groups.csv && -f affymetrix/dense_eur_top10_groups.csv ]]' "$JOB3")

JOB7=$(maybe_submit "missing"     run_missingness.sbatch \
    '[[ -f gsa/missing_variants_gt_1pct.csv && -f affymetrix/missing_variants_gt_1pct.csv ]]' "$JOB2")

if [[ -z "${JOB1}${JOB2}${JOB3}${JOB4}${JOB5}${JOB6}${JOB7}" ]]; then
    echo
    echo "All outputs already present. Nothing submitted."
    exit 0
fi

echo
echo "Monitor:  squeue -u \$USER"
echo "Logs:"
[[ -n "$JOB1" ]] && echo "  logs/extract.${JOB1}.log"
[[ -n "$JOB2" ]] && echo "  logs/relabel.${JOB2}.log"
[[ -n "$JOB3" ]] && echo "  logs/dense.${JOB3}.log"
[[ -n "$JOB4" ]] && echo "  logs/project.${JOB4}.log"
[[ -n "$JOB5" ]] && echo "  logs/freq.${JOB5}.log"
[[ -n "$JOB6" ]] && echo "  logs/eur_project.${JOB6}.log"
[[ -n "$JOB7" ]] && echo "  logs/missing.${JOB7}.log"
