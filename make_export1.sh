#!/bin/bash
# make_export1.sh
#
# Copies 10 summary-level outputs (5 per panel × 2 panels) into ./export1/
# under the repo root, renamed with a "gsa_" or "affymetrix_" prefix so
# both panels' files coexist in one flat directory.
#
# Run from anywhere — uses an absolute ROOT path.

set -euo pipefail
trap 'echo "[make_export1] ERROR on line $LINENO" >&2' ERR

ROOT="/groups/umcg-lifelines/tmp02/projects/ov26_01365/lifelines-genetics-scripts"

mkdir -p "$ROOT/export1"

FILES=(
    dense_assigned_superpop.csv
    dense_eur_top10_groups.csv
    freq.acount
    missing.vmiss
    missing_samples_gt_1pct.csv
)

for panel in gsa affymetrix; do
    for file in "${FILES[@]}"; do
        src="$ROOT/$panel/$file"
        dst="$ROOT/export1/${panel}_${file}"
        if [[ ! -f "$src" ]]; then
            echo "ERROR: missing $src" >&2
            exit 1
        fi
        cp "$src" "$dst"
    done
done

echo "✅ Done! All 10 files have been copied to $ROOT/export1"
ls -lh "$ROOT/export1"
