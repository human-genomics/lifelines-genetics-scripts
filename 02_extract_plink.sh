#!/bin/bash
# 02_extract_plink.sh
#
# Step 2 of 5. Extracts variants listed in snp.info from both Lifelines
# imputed panels (GSA v3, Affymetrix v2) and merges autosomes per panel.
#
# Run via SLURM (default):
#     sbatch run_extract.sbatch
#
# Smoke-test on a single chromosome (still policy-compliant via sbatch):
#     sbatch run_extract.sbatch 22
#
# Inputs:
#   ./snp.info  (from 01_download_snp_info.sh)
#   /groups/umcg-lifelines/rsc02/releases/{gsa_imputed/v3,affymetrix_imputed/v2}/...
#
# Outputs:
#   gsa/merged.{pgen,pvar,psam}
#   affymetrix/merged.{pgen,pvar,psam}
#
# Idempotent: skips chromosomes whose .pgen already exists, so a re-run
# after a partial failure resumes where it left off.

set -euo pipefail
trap 'echo "[02] ERROR on line $LINENO (last command: $BASH_COMMAND)" >&2' ERR

# -- paths --
GSA_DIR=/groups/umcg-lifelines/rsc02/releases/gsa_imputed/v3/Imputed/VCF
AFFY_DIR=/groups/umcg-lifelines/rsc02/releases/affymetrix_imputed/v2/VCF
SNPINFO=snp.info

# -- resources: prefer SLURM allocation, fall back to env or sane default --
THREADS=${SLURM_CPUS_PER_TASK:-2}
if [[ -n "${SLURM_MEM_PER_NODE:-}" ]] && (( SLURM_MEM_PER_NODE > 4096 )); then
    MEM_MB=$(( SLURM_MEM_PER_NODE - 2048 ))   # leave 2 GB headroom for plink2 overshoot
else
    MEM_MB=${PLINK_MEM_MB:-12000}
fi

# -- chromosomes (default 1..22; pass args to override, e.g. for smoke test) --
if [[ $# -gt 0 ]]; then
    CHROMS=("$@")
else
    CHROMS=({1..22})
fi

# -- module --
module load PLINK/2.0-alpha6.20-20250707

preflight() {
    echo "=== Pre-flight ==="
    echo "  hostname:    $(hostname)"
    echo "  job:         ${SLURM_JOB_ID:-<not under SLURM>}"
    echo "  cwd:         $(pwd)"

    [[ -s "$SNPINFO" ]] || { echo "ERROR: $SNPINFO missing or empty" >&2; exit 1; }
    head -n 1 "$SNPINFO" | grep -q '^Chrom' \
        || { echo "ERROR: $SNPINFO header does not start with 'Chrom'" >&2; exit 1; }
    command -v plink2 >/dev/null 2>&1 \
        || { echo "ERROR: plink2 not on PATH after module load" >&2; exit 1; }

    local missing=0
    for chr in "${CHROMS[@]}"; do
        local gsa_vcf="$GSA_DIR/chr_${chr}_gsa_v3_imputed.vcf.gz"
        local affy_vcf="$AFFY_DIR/${chr}.UGLI2_r2.vcf.gz"
        [[ -r "$gsa_vcf"  ]] || { echo "ERROR: unreadable $gsa_vcf"  >&2; missing=1; }
        [[ -r "$affy_vcf" ]] || { echo "ERROR: unreadable $affy_vcf" >&2; missing=1; }
    done
    (( missing == 0 )) || exit 1

    echo "  snp.info:    $(wc -l < "$SNPINFO") lines"
    echo "  chromosomes: ${CHROMS[*]}"
    echo "  resources:   ${THREADS} threads, ${MEM_MB} MB"
    echo "  plink2:      $(plink2 --version 2>&1 | head -n 1)"
    echo
}

build_id_lists() {
    # snp.info columns: 1=Chrom 2=rsid 3=Index 4=GenPos 5=PhysPos 6=A1(ALT) 7=A2(REF)
    # Canonical chr:pos:ref:alt = chr:pos:A2:A1.
    if [[ -s extract_ids.txt && -s rsid_map.txt ]]; then
        echo "=== ID lists already built ==="
        echo "  extract_ids.txt: $(wc -l < extract_ids.txt) ids"
        echo
        return 0
    fi
    echo "=== Building variant ID lists ==="
    awk 'NR>1 {print $1":"$5":"$7":"$6}'       "$SNPINFO" | sort -u > extract_ids.txt
    awk 'NR>1 {print $2"\t"$1":"$5":"$7":"$6}' "$SNPINFO"           > rsid_map.txt
    echo "  extract_ids.txt: $(wc -l < extract_ids.txt) ids"
    echo
}

extract_chr() {
    local panel=$1 outdir=$2 chr=$3

    if [[ -f "$outdir/chr_${chr}.pgen" ]]; then
        echo "  [$panel chr$chr] already done, skipping"
        return 0
    fi

    local vcf
    if [[ "$panel" = "gsa" ]]; then
        vcf="$GSA_DIR/chr_${chr}_gsa_v3_imputed.vcf.gz"
    else
        vcf="$AFFY_DIR/${chr}.UGLI2_r2.vcf.gz"
    fi

    echo "  [$panel chr$chr] extracting from $(basename "$vcf")"
    plink2 \
        --vcf "$vcf" dosage=DS \
        --double-id \
        --allow-extra-chr \
        --max-alleles 2 \
        --set-all-var-ids '@:#:$r:$a' \
        --new-id-max-allele-len 50 missing \
        --extract extract_ids.txt \
        --threads "$THREADS" \
        --memory "$MEM_MB" \
        --make-pgen \
        --out "$outdir/chr_${chr}"

    [[ -f "$outdir/chr_${chr}.pgen" ]] \
        || { echo "ERROR: $outdir/chr_${chr}.pgen not produced" >&2; exit 1; }
}

merge_panel() {
    local panel=$1 outdir=$2

    if (( ${#CHROMS[@]} < 2 )); then
        echo "  [$panel] only ${#CHROMS[@]} chromosome(s); skipping merge"
        return 0
    fi
    if [[ -f "$outdir/merged.pgen" ]]; then
        echo "  [$panel] merged.pgen already exists, skipping merge"
        return 0
    fi

    : > "$outdir/merge_list.txt"
    for chr in "${CHROMS[@]}"; do
        echo "$outdir/chr_${chr}" >> "$outdir/merge_list.txt"
    done

    echo "  [$panel] merging ${#CHROMS[@]} chromosomes"
    plink2 \
        --pmerge-list "$outdir/merge_list.txt" \
        --threads "$THREADS" \
        --memory "$MEM_MB" \
        --make-pgen \
        --out "$outdir/merged"

    [[ -f "$outdir/merged.pgen" ]] \
        || { echo "ERROR: $outdir/merged.pgen not produced" >&2; exit 1; }
    echo "  [$panel] merged: $(wc -l < "$outdir/merged.pvar") variant lines (incl. header)"
}

run_panel() {
    local panel=$1 outdir=$2
    echo "=== $panel ==="
    mkdir -p "$outdir"
    for chr in "${CHROMS[@]}"; do
        extract_chr "$panel" "$outdir" "$chr"
    done
    merge_panel "$panel" "$outdir"
    echo
}

preflight
build_id_lists
run_panel gsa         gsa
run_panel affymetrix  affymetrix

echo "=== Done ==="
echo "  GSA:        gsa/merged.{pgen,pvar,psam}"
echo "  Affymetrix: affymetrix/merged.{pgen,pvar,psam}"
echo "  Next step:  sbatch run_relabel.sbatch"
