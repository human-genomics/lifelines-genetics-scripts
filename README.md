# lifelines-genetics-scripts

QC and ancestry pipeline for the [Lifelines](https://www.lifelines-biobank.com/) cohort's two genotyping panels — **GSA** and **Affymetrix** — built on [PLINK 1.9](https://www.cog-genomics.org/plink/) / [PLINK 2](https://www.cog-genomics.org/plink/2.0/) and run on the UMCG SLURM cluster. For each panel the pipeline merges per-chromosome VCFs into a single pfile, relabels variants to rsids, projects samples onto two reference PCAs (super-population and EUR-balanced), and computes allele-frequency / missingness QC. A separate kinship pipeline merges both panels and runs [KING](https://www.kingrelatedness.com/) to surface cross-panel relateds.

## Overview

The pipeline runs in **two steps**, both launched from the **login node**:

```bash
bash run_all.sh        # 1. main QC + ancestry pipeline (chains 7 SLURM jobs)
bash run_kinship.sh    # 2. cross-panel KING kinship — must run AFTER run_all.sh
```

`run_kinship.sh` consumes `dense.pgen` outputs from `run_all.sh`, so it must come second. Both scripts are idempotent: each step's outputs are checked first, and the step is skipped if they already exist. Re-running after success exits in seconds.

### What the pipeline reads

- **Per-panel VCFs** — one VCF per chromosome for each of GSA and Affymetrix.
- **`snp.info`** — Lifelines-supplied variant metadata used for rsid relabeling and reference allele frequencies.
- **Public reference data**, downloaded automatically by `run_all.sh`:
  - The dense rsid list (~500K SNPs).
  - The [public-statgen](https://github.com/jesseICR/public-statgen) reference PCA (super-population assignment).
- **Bundled reference data** in the repo: `eur_pca_balanced.{eigenvec.allele,acount}` and `centroids_pc6.tsv` for EUR-balanced projection.
- **`ukb_snp_qc.txt`** — UK Biobank QC SNP file, downloaded by `run_kinship.sh` to identify the relatedness-SNP subset.

### What the pipeline writes

All outputs land in three locations under the repo root:

- `gsa/` — per-panel intermediates and analyses for the GSA panel.
- `affymetrix/` — same, for the Affymetrix panel.
- Repo root — cross-panel kinship outputs only (`merged_kinship.*`).
- `logs/<step>.<jobid>.log` — combined stdout/stderr per SLURM job.

### DAG

```
run_all.sh:
    extract → relabel ─┬─► dense ─┬─► project
                       │          └─► eur_project
                       ├─► freq
                       └─► missing

run_kinship.sh:
    kinship   (consumes dense.pgen from both panels)
```

## Outputs

### Per-panel files (`gsa/` and `affymetrix/`)

| Step | File | Description |
| --- | --- | --- |
| extract | `merged.{pgen,pvar,psam}` | Full merged pfile across chr 1–22 |
| relabel | `merged_rsid.{pgen,pvar,psam}` | Same data with variant IDs replaced by rsids |
| dense | `dense.{pgen,pvar,psam}` | Subset to ~500K dense rsids (input to ancestry steps) |
| project | `dense_projected.sscore` | Per-sample scores on 20 public-statgen PCs |
| project | **`dense_assigned_superpop.csv`** | Super-population assignment per sample (AFR / AMR / EAS / EUR / SAS) |
| eur_project | `dense_eur_projected.sscore` | Per-sample scores on EUR-balanced PCs |
| eur_project | **`dense_eur_top10_groups.csv`** | Top-10 nearest fine-grained EUR groups per sample |
| freq | `freq.acount` | plink2 `--freq` allele counts |
| freq | `freq_diff_ge_0.1.csv` | Variants with \|A1 freq diff\| ≥ 0.1 vs `snp.info` |
| freq | **`freq_diff_ge_0.2.csv`** | Variants with \|A1 freq diff\| ≥ 0.2 vs `snp.info` (likely strand/allele issues) |
| missing | `missing.smiss` / `missing.vmiss` | plink2 per-sample / per-variant missingness |
| missing | **`missing_samples_gt_1pct.csv`** | Samples with > 1% missingness |
| missing | **`missing_variants_gt_1pct.csv`** | Variants missing in > 1% of samples |

Bold rows are the headline analytic outputs; the others are intermediates.

### Cross-panel files (repo root)

| File | Description |
| --- | --- |
| `merged_kinship.{bed,bim,fam}` | Merged GSA+Affymetrix bfile on UKB-relatedness rsids |
| **`merged_kinship.kin0`** | KING kinship table — includes cross-panel pairs that would be missed if each panel were processed alone |

## Pipeline steps

### `run_all.sh` — per-panel QC and ancestry (7 SLURM jobs)

1. **extract** (`run_extract.sbatch` → `02_extract_plink.sh`) — extracts the SNPs listed in `snp.info` from per-chromosome VCFs and merges into `merged.{pgen,pvar,psam}` for each panel. Longest job in the pipeline (~24h for the full chr 1–22 merge across both panels).
2. **relabel** (`run_relabel.sbatch` → `03_relabel_rsids.sh`) — replaces `chr:pos:ref:alt` variant IDs with rsids using `snp.info`, producing `merged_rsid.*`.
3. **dense** (`run_dense.sbatch` → `05_extract_dense.sh`) — subsets `merged_rsid.*` to ~500K dense rsids, producing `dense.*` (the input pfile for both PCA projections).
4. **project** (`run_project.sbatch` → `07_project_and_assign.sh`) — projects samples onto the public-statgen reference PCA and assigns each sample to a super-population.
5. **freq** (`run_freq.sbatch` → `08_compute_freq.sh`) — computes allele frequencies and flags variants whose A1 frequency differs from `snp.info` by ≥ 0.1 or ≥ 0.2 (a heuristic for strand or allele swaps).
6. **eur_project** (`run_eur_project.sbatch` → `12_project_eur_and_assign_groups.sh`) — projects onto the EUR-balanced PCA and reports the top-10 nearest fine-grained European groups per sample.
7. **missing** (`run_missingness.sbatch` → `13_missingness.sh`) — computes per-sample and per-variant missingness, flagging anything > 1%.

### `run_kinship.sh` — cross-panel KING kinship (1 SLURM job)

8. **kinship** (`run_kinship.sbatch` → `10_kinship.sh`) — subsets each panel's `dense.*` to UKB relatedness rsids, converts to bfile, merges the two panel bfiles with `plink1 --bmerge` (auto-excludes mismatched SNPs and retries), and runs `plink2 --make-king-table` on the merged bfile. The merge is what lets cross-panel relateds appear in the kinship table.

### Smoke test

Before committing to a 24h `extract` run, validate on chr 22 only:

```bash
bash 01_download_snp_info.sh
sbatch run_extract.sbatch 22       # ~5–10 min on a compute node
# inspect logs/extract.<jobid>.log; if happy:
bash run_all.sh
```

## SLURM configuration

Every `run_*.sbatch` requests **64 GB** RAM and emails `mintza@mskcc.org` and `jmurray@invitroresearch.com` on `END` and `FAIL`.

| Script | Time | Notes |
| --- | --- | --- |
| `run_extract.sbatch` | 24h | Longest job — chr 1–22 extract+merge for both panels |
| `run_relabel.sbatch` | 2h | |
| `run_dense.sbatch` | 1h | |
| `run_freq.sbatch` | 1h | |
| `run_missingness.sbatch` | 2h | |
| `run_project.sbatch` | 2h | |
| `run_eur_project.sbatch` | 2h | |
| `run_kinship.sbatch` | 4h | Separate entry point — submitted by `run_kinship.sh` |
