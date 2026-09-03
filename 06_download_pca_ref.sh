#!/bin/bash
# 06_download_pca_ref.sh
#
# Step 6 of 7. Run on the LOGIN node. Downloads the reference PCA files
# from public-statgen into ./pca_ref/. Idempotent.
#
# Files fetched:
#   pca_pcs.eigenvec.allele       (PC loadings per SNP-allele, used for --score)
#   pca_counts.acount             (allele counts, used by --read-freq)
#   centroids_top20_supervised.tsv (super-pop centroids in PC1..PC20)

set -euo pipefail
trap 'echo "[06] ERROR on line $LINENO" >&2' ERR

BASE=https://raw.githubusercontent.com/human-genomics/public-statgen/main/outputs/pca
DIR=pca_ref
mkdir -p "$DIR"

FILES=(
    pca_pcs.eigenvec.allele
    pca_counts.acount
    centroids_top20_supervised.tsv
)

for f in "${FILES[@]}"; do
    if [[ -s "$DIR/$f" ]]; then
        echo "$DIR/$f already present ($(wc -l < "$DIR/$f") lines). Skipping."
        continue
    fi
    curl -L --fail --retry 3 --retry-delay 5 -o "$DIR/$f" "$BASE/$f"
    echo "Downloaded $DIR/$f ($(wc -l < "$DIR/$f") lines)"
done
