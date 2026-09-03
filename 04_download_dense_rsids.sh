#!/bin/bash
# 04_download_dense_rsids.sh
#
# Step 4 of 5. Run on the LOGIN node. Downloads the dense rsid list
# (a curated subset of snp.info rsids). Idempotent.

set -euo pipefail
trap 'echo "[04] ERROR on line $LINENO" >&2' ERR

URL=https://raw.githubusercontent.com/human-genomics/public-statgen/main/rsids_dense_chr1_22.txt
OUT=rsids_dense_chr1_22.txt

verify() {
    [[ -s "$OUT" ]] || return 1
    head -n 1 "$OUT" | grep -q '^rs[0-9]' || return 1
    return 0
}

if verify; then
    echo "$OUT already present and looks valid ($(wc -l < "$OUT") rsids). Skipping."
    exit 0
fi

curl -L --fail --retry 3 --retry-delay 5 -o "$OUT" "$URL"

verify || { echo "ERROR: downloaded $OUT does not look like an rsid list" >&2; exit 1; }
echo "Downloaded $(wc -l < "$OUT") rsids to ./$OUT"
