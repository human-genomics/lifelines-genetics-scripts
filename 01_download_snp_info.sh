#!/bin/bash
# 01_download_snp_info.sh
#
# Step 1 of 5. Run on the LOGIN node (compute nodes have no outbound
# internet). Idempotent: skips the download if snp.info already exists
# and looks correct.

set -euo pipefail
trap 'echo "[01] ERROR on line $LINENO" >&2' ERR

URL=https://github.com/human-genomics/sbayesrc-liftover/releases/download/v1.0/snp.info
OUT=snp.info

verify() {
    [[ -s "$OUT" ]] || return 1
    head -n 1 "$OUT" | grep -q '^Chrom' || return 1
    return 0
}

if verify; then
    echo "$OUT already present and looks valid ($(wc -l < "$OUT") lines). Skipping."
    exit 0
fi

curl -L --fail --retry 3 --retry-delay 5 -o "$OUT" "$URL"

verify || { echo "ERROR: downloaded $OUT does not look like snp.info" >&2; exit 1; }
echo "Downloaded $(wc -l < "$OUT") lines to ./$OUT"
