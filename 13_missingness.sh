#!/bin/bash
# 13_missingness.sh
#
# For each panel (gsa, affymetrix), runs plink2 --missing on the full
# rsid-keyed merged pfile (~7M snp.info SNPs), then writes two filtered
# CSVs sorted by missingness fraction (descending):
#
#   $panel/missing_samples_gt_1pct.csv   IID,missing_pct
#       rows: samples missing >1% of variants
#   $panel/missing_variants_gt_1pct.csv  rsid,a1,a2,missing_pct
#       rows: variants missing in >1% of samples (a1 = ALT, a2 = REF)
#
# Output is summary statistics only (no genotypes) and may be exported.
#
# Run via SLURM:
#     sbatch run_missingness.sbatch
#
# Inputs (from 03_relabel_rsids.sh):
#   gsa/merged_rsid.{pgen,pvar,psam}
#   affymetrix/merged_rsid.{pgen,pvar,psam}
#
# Outputs:
#   gsa/missing.smiss             affymetrix/missing.smiss
#   gsa/missing.vmiss             affymetrix/missing.vmiss
#   gsa/missing_samples_gt_1pct.csv   affymetrix/missing_samples_gt_1pct.csv
#   gsa/missing_variants_gt_1pct.csv  affymetrix/missing_variants_gt_1pct.csv

set -euo pipefail
trap 'echo "[13] ERROR on line $LINENO (last command: $BASH_COMMAND)" >&2' ERR

THREADS=${SLURM_CPUS_PER_TASK:-2}
if [[ -n "${SLURM_MEM_PER_NODE:-}" ]] && (( SLURM_MEM_PER_NODE > 2048 )); then
    MEM_MB=$(( SLURM_MEM_PER_NODE - 1024 ))
else
    MEM_MB=${PLINK_MEM_MB:-8000}
fi

module load PLINK/2.0-alpha6.20-20250707

echo "=== Pre-flight ==="
echo "  hostname:    $(hostname)"
echo "  job:         ${SLURM_JOB_ID:-<not under SLURM>}"
echo "  cwd:         $(pwd)"
command -v plink2 >/dev/null 2>&1 \
    || { echo "ERROR: plink2 not on PATH after module load" >&2; exit 1; }
for panel in gsa affymetrix; do
    [[ -f "$panel/merged_rsid.pgen" ]] \
        || { echo "ERROR: $panel/merged_rsid.pgen missing — run 03_relabel_rsids.sh first" >&2; exit 1; }
done
echo "  resources:   ${THREADS} threads, ${MEM_MB} MB"
echo "  plink2:      $(plink2 --version 2>&1 | head -n 1)"
echo

compute_missing() {
    local panel=$1
    local smiss="$panel/missing.smiss"
    local vmiss="$panel/missing.vmiss"

    if [[ -f "$smiss" && -f "$vmiss" ]]; then
        echo "  [$panel] $smiss + $vmiss already exist, skipping plink2"
        return 0
    fi

    echo "  [$panel] computing missingness..."
    plink2 \
        --pfile "$panel/merged_rsid" \
        --missing \
        --threads "$THREADS" \
        --memory "$MEM_MB" \
        --out "$panel/missing"

    [[ -f "$smiss" && -f "$vmiss" ]] \
        || { echo "ERROR: $smiss or $vmiss not produced" >&2; exit 1; }
}

# Filter + sort the per-sample missingness file.
# .smiss columns: #FID IID MISSING_CT OBS_CT F_MISS
filter_samples() {
    local panel=$1
    local smiss="$panel/missing.smiss"
    local out="$panel/missing_samples_gt_1pct.csv"

    if [[ -f "$out" ]]; then
        echo "  [$panel] $out already exists, skipping"
        return 0
    fi

    {
        echo "iid,missing_pct"
        awk '/^#/ {next}
             ($5 + 0) > 0.01 {printf "%s,%.4f\n", $2, $5 * 100}' \
            "$smiss" \
            | sort -t, -k2 -g -r
    } > "$out"

    local n_total=$(awk '/^#/ {next} END {print NR}' "$smiss")
    local n_gt1=$(( $(wc -l < "$out") - 1 ))
    local n_gt10=$(awk '/^#/ {next} ($5 + 0) > 0.10' "$smiss" | wc -l)
    echo "  [$panel] samples >1% missing: $n_gt1 / $n_total"
    echo "  [$panel] samples >10% missing: $n_gt10"
}

# Filter + sort the per-variant missingness file, joining with pvar
# to recover REF/ALT (= A2/A1 in PLINK convention).
# .vmiss columns: #CHROM ID MISSING_CT OBS_CT F_MISS
# .pvar columns:  detect ID/REF/ALT by header.
filter_variants() {
    local panel=$1
    local vmiss="$panel/missing.vmiss"
    local pvar="$panel/merged_rsid.pvar"
    local out="$panel/missing_variants_gt_1pct.csv"

    if [[ -f "$out" ]]; then
        echo "  [$panel] $out already exists, skipping"
        return 0
    fi

    {
        echo "rsid,a1,a2,missing_pct"
        awk '
            # Pass 1: load REF/ALT from pvar by rsid
            NR == FNR {
                if (/^##/) next
                if (/^#CHROM/) {
                    for (i = 1; i <= NF; i++) {
                        if ($i == "ID")  ID_C  = i
                        if ($i == "REF") REF_C = i
                        if ($i == "ALT") ALT_C = i
                    }
                    next
                }
                REF_BY[$ID_C] = $REF_C
                ALT_BY[$ID_C] = $ALT_C
                next
            }
            # Pass 2: vmiss; emit rows >1% missing
            /^#/ { next }
            ($5 + 0) > 0.01 {
                rsid = $2
                a1 = (rsid in ALT_BY) ? ALT_BY[rsid] : "NA"
                a2 = (rsid in REF_BY) ? REF_BY[rsid] : "NA"
                printf "%s,%s,%s,%.4f\n", rsid, a1, a2, $5 * 100
            }
        ' "$pvar" "$vmiss" \
            | sort -t, -k4 -g -r
    } > "$out"

    local n_total=$(awk '/^#/ {next} END {print NR}' "$vmiss")
    local n_gt1=$(( $(wc -l < "$out") - 1 ))
    local n_gt10=$(awk '/^#/ {next} ($5 + 0) > 0.10' "$vmiss" | wc -l)
    echo "  [$panel] variants >1% missing:  $n_gt1 / $n_total"
    echo "  [$panel] variants >10% missing: $n_gt10"
}

for panel in gsa affymetrix; do
    echo "=== $panel ==="
    compute_missing  "$panel"
    filter_samples   "$panel"
    filter_variants  "$panel"
    echo
done

echo "=== Done ==="
echo "  gsa/missing_samples_gt_1pct.csv     affymetrix/missing_samples_gt_1pct.csv"
echo "  gsa/missing_variants_gt_1pct.csv    affymetrix/missing_variants_gt_1pct.csv"
echo "  Raw plink2 output: gsa/missing.{smiss,vmiss}, affymetrix/missing.{smiss,vmiss}"
echo "  All output is summary-level (no individual genotypes) and exportable."
