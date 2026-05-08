#!/bin/bash
# 10_kinship.sh
#
# Single SLURM job that:
#   (a) Builds ukb_relatedness_rsids.txt from ukb_snp_qc.txt
#       (rsids with in_Relatedness == 1).
#   (b) Subsets each panel's dense pfile to those rsids and converts
#       to PLINK 1 bfile (.bed/.bim/.fam) — needed by plink1 --bmerge.
#   (c) Merges the two bfiles with plink1 --bmerge. Cross-panel kinship
#       reveals genetic relationships *between* GSA and Affymetrix
#       cohorts as well as within each. (No sample overlap is expected;
#       any duplicates that surface will look like identical twins in
#       the .kin0.) Mismatched SNPs are auto-excluded from both bfiles
#       and the merge is retried, following the same pattern used in
#       the user's merge_wgs_imputed.sh script.
#   (d) Runs plink2 --make-king-table on the merged bfile.
#
# Run via SLURM:
#     sbatch run_kinship.sbatch
#   or, end-to-end with download + skip-check:
#     bash run_kinship.sh
#
# Inputs:
#   ./ukb_snp_qc.txt                  (from 09_download_ukb_qc.sh)
#   gsa/dense.{pgen,pvar,psam}        (from 05_extract_dense.sh)
#   affymetrix/dense.{pgen,pvar,psam}
#
# Outputs:
#   gsa/dense_kinship.{bed,bim,fam}        per-panel kinship-SNP bfile
#   affymetrix/dense_kinship.{bed,bim,fam}
#   merged_kinship.{bed,bim,fam}           merged bfile (both panels)
#   merged_kinship.kin0                    KING table on merged data
#
# Tunable via env:
#   KING_CUTOFF   minimum kinship reported in .kin0 (default 0.04,
#                 captures up to ~5th-degree relatives; standard
#                 3rd-degree cutoff would be 0.0884)

set -euo pipefail
trap 'echo "[10] ERROR on line $LINENO (last command: $BASH_COMMAND)" >&2' ERR

UKB_QC=ukb_snp_qc.txt
RELATEDNESS_RSIDS=ukb_relatedness_rsids.txt
MERGED_BASE=merged_kinship
KING_CUTOFF=${KING_CUTOFF:-0.04}

THREADS=${SLURM_CPUS_PER_TASK:-2}
if [[ -n "${SLURM_MEM_PER_NODE:-}" ]] && (( SLURM_MEM_PER_NODE > 2048 )); then
    MEM_MB=$(( SLURM_MEM_PER_NODE - 1024 ))
else
    MEM_MB=${PLINK_MEM_MB:-12000}
fi

# -- modules --
# plink2 is needed for pgen->bed conversion and for KING.
# plink1 is needed for --bmerge (plink2 has no equivalent for bfile merging).
#
# Both PLINK modules belong to the same Lmod "PLINK" family, so loading
# one auto-unloads the other. We load PLINK/1.x FIRST and capture the
# absolute path to its binary (plink1's file on disk remains valid even
# after its module is unloaded). Then we load PLINK/2 LAST so plink2 is
# the one on PATH for the rest of the script.
#
# Module names below match what was visible in ssh_output.txt; if your
# cluster uses different names, run `module avail PLINK` and edit.
module load PLINK/1.9 2>/dev/null \
    || module load PLINK/1.90 2>/dev/null \
    || module load plink/1.9 2>/dev/null \
    || { echo "ERROR: no PLINK 1.x module found. Run 'module avail PLINK' and edit 10_kinship.sh" >&2; exit 1; }

# Resolve which binary name is plink1 (some installs use 'plink', others 'plink1')
PLINK1=$(command -v plink1 || command -v plink || true)
[[ -n "$PLINK1" ]] || { echo "ERROR: neither 'plink1' nor 'plink' on PATH after PLINK 1.x module load" >&2; exit 1; }
# Resolve to absolute path before plink1's module is swapped out
PLINK1=$(readlink -f "$PLINK1")

module load PLINK/2.0-alpha6.20-20250707

echo "=== Pre-flight ==="
echo "  hostname:    $(hostname)"
echo "  job:         ${SLURM_JOB_ID:-<not under SLURM>}"
echo "  cwd:         $(pwd)"
[[ -s "$UKB_QC" ]] \
    || { echo "ERROR: $UKB_QC missing — run 09_download_ukb_qc.sh first" >&2; exit 1; }
command -v plink2 >/dev/null 2>&1 \
    || { echo "ERROR: plink2 not on PATH after module load" >&2; exit 1; }
for panel in gsa affymetrix; do
    [[ -f "$panel/dense.pgen" ]] \
        || { echo "ERROR: $panel/dense.pgen missing — run 05_extract_dense.sh first" >&2; exit 1; }
done
echo "  plink2:      $(plink2 --version 2>&1 | head -n 1)"
echo "  plink1 ($(basename "$PLINK1")): $($PLINK1 --version 2>&1 | head -n 1)"
echo "  resources:   ${THREADS} threads, ${MEM_MB} MB"
echo "  king cutoff: $KING_CUTOFF"
echo

# -- 1. UKB relatedness rsid list (idempotent) --
if [[ -s "$RELATEDNESS_RSIDS" ]]; then
    echo "=== Relatedness rsid list cached ==="
    echo "  $RELATEDNESS_RSIDS: $(wc -l < "$RELATEDNESS_RSIDS") rsids"
else
    echo "=== Extracting in_Relatedness rsids from $UKB_QC ==="
    REL_COL=$(head -1 "$UKB_QC" | tr ' ' '\n' | grep -n '^in_Relatedness$' | cut -d: -f1)
    [[ -n "$REL_COL" ]] \
        || { echo "ERROR: in_Relatedness column not found in $UKB_QC" >&2; exit 1; }
    echo "  in_Relatedness is column $REL_COL"
    awk -v col="$REL_COL" 'NR>1 && $col == 1 {print $1}' "$UKB_QC" \
        | sort -u > "$RELATEDNESS_RSIDS"
    [[ -s "$RELATEDNESS_RSIDS" ]] \
        || { echo "ERROR: no rsids with in_Relatedness == 1" >&2; exit 1; }
    echo "  wrote $(wc -l < "$RELATEDNESS_RSIDS") rsids"
fi
echo

# -- 2. Per-panel: pgen -> bed (subset to UKB relatedness rsids) --
for panel in gsa affymetrix; do
    BFILE_BASE="$panel/dense_kinship"

    if [[ -f "$BFILE_BASE.bed" ]]; then
        echo "=== [$panel] $BFILE_BASE.bed cached ==="
    else
        echo "=== [$panel] subset dense -> bfile ==="
        plink2 \
            --pfile "$panel/dense" \
            --extract "$RELATEDNESS_RSIDS" \
            --threads "$THREADS" \
            --memory "$MEM_MB" \
            --make-bed \
            --out "$BFILE_BASE"
        [[ -f "$BFILE_BASE.bed" ]] \
            || { echo "ERROR: $BFILE_BASE.bed not produced" >&2; exit 1; }
        KEPT=$(wc -l < "$BFILE_BASE.bim")
        echo "  [$panel] $BFILE_BASE has $KEPT variants"
    fi
    echo
done

# -- 3. Merge the two bfiles via plink1 --bmerge, with missnp retry --
if [[ -f "$MERGED_BASE.bed" ]]; then
    echo "=== Merged bfile $MERGED_BASE.bed cached ==="
else
    echo "=== Merging gsa + affymetrix bfiles via plink1 --bmerge ==="

    # First attempt; '|| true' lets us inspect a possible .missnp file
    "$PLINK1" \
        --bfile gsa/dense_kinship \
        --bmerge affymetrix/dense_kinship \
        --memory "$MEM_MB" \
        --threads "$THREADS" \
        --make-bed \
        --out "$MERGED_BASE" \
        || true

    if [[ -f "${MERGED_BASE}-merge.missnp" ]]; then
        N_MISS=$(wc -l < "${MERGED_BASE}-merge.missnp")
        echo "  $N_MISS allele-mismatched variants flagged; excluding from both bfiles and retrying..."

        "$PLINK1" \
            --bfile gsa/dense_kinship \
            --exclude "${MERGED_BASE}-merge.missnp" \
            --memory "$MEM_MB" --threads "$THREADS" \
            --make-bed \
            --out gsa/dense_kinship_clean

        "$PLINK1" \
            --bfile affymetrix/dense_kinship \
            --exclude "${MERGED_BASE}-merge.missnp" \
            --memory "$MEM_MB" --threads "$THREADS" \
            --make-bed \
            --out affymetrix/dense_kinship_clean

        "$PLINK1" \
            --bfile gsa/dense_kinship_clean \
            --bmerge affymetrix/dense_kinship_clean \
            --memory "$MEM_MB" --threads "$THREADS" \
            --make-bed \
            --out "$MERGED_BASE"
    fi

    [[ -f "$MERGED_BASE.bed" ]] \
        || { echo "ERROR: $MERGED_BASE.bed not produced after merge attempts" >&2; exit 1; }

    N_VAR=$(wc -l < "$MERGED_BASE.bim")
    N_SAMP=$(wc -l < "$MERGED_BASE.fam")
    echo "  merged bfile: $N_VAR variants, $N_SAMP samples"
fi
echo

# -- 4. KING kinship on the merged bfile --
if [[ -f "$MERGED_BASE.kin0" ]]; then
    echo "=== $MERGED_BASE.kin0 cached ==="
else
    echo "=== Computing KING kinship on merged bfile (cutoff=$KING_CUTOFF) ==="
    plink2 \
        --bfile "$MERGED_BASE" \
        --make-king-table \
        --king-table-filter "$KING_CUTOFF" \
        --threads "$THREADS" \
        --memory "$MEM_MB" \
        --out "$MERGED_BASE"
    [[ -f "$MERGED_BASE.kin0" ]] \
        || { echo "ERROR: $MERGED_BASE.kin0 not produced" >&2; exit 1; }
    N_PAIRS=$(( $(wc -l < "$MERGED_BASE.kin0") - 1 ))
    echo "  $N_PAIRS sample pairs with kinship >= $KING_CUTOFF"
fi
echo

echo "=== Done ==="
echo "  Merged bfile:   $MERGED_BASE.{bed,bim,fam}"
echo "  Kinship table:  $MERGED_BASE.kin0"
