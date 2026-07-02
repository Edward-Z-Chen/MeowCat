# MeowCat Pipeline — Function & Step I/O Reference

This document traces every function in `pipeline.py` and verifies that the
arguments, inputs, and outputs match the downstream scripts they invoke.
Issues and suggestions are collected in the final section.

---

## Helper Functions

### `_pkg(relpath: str) -> str`
Resolves a path relative to the `meowcat/` package directory.

### `_samples(cfg, override) -> List[str]`
- **Input:** `cfg.project.data_root`, `cfg.project.sample_pattern`, optional override list
- **Output:** List of sample folder names (basenames of directories matching the glob)

---

## Step 1 — RCTD Deconvolution

### `cmd_rctd(cfg) -> List[str]`

| | pipeline.py builds | Script expects |
|---|---|---|
| Command | `Rscript Preprocess/RCTD_deconvolution.R --no-save` | Manual R script; paths hardcoded inside |

- **Config used:** (none — script has internal paths)
- **Inputs (disk):** Reference single-cell atlas, Visium count matrices (paths hardcoded in R script)
- **Outputs (disk):** `<sample>/deconvolution_rctd/major_prop.csv` per Visium sample — RCTD cell-type proportion matrix
- **Note:** Not parameterized via CLI; user must edit the R script directly before running.

---

## Step 1.5 — Visium Metadata Preparation

### `cmd_prepare_visium_sample(cfg, sample) -> List[str]`

| Arg | pipeline.py passes | `prepare_visium_inputs.py` expects |
|---|---|---|
| `--sample_dir` | `<data_root>/<sample>` | Required, str |
| `--target_mpp` | `cfg.preprocess.target_mpp` (default 0.5) | Optional, float, default 0.5 |

- **Inputs (disk):**
  - `<sample_dir>/pixel-size-raw.txt` — raw MPP (written by `get_pixel_size.py`)
  - `<sample_dir>/deconvolution_rctd/major_prop.csv` — RCTD output (written by Step 1)
  - `<sample_dir>/spatial/tissue_positions_list.csv` (or `tissue_positions.csv`)
  - `<sample_dir>/spatial/scalefactors_json.json`
- **Outputs (disk):**
  - `<sample_dir>/anno-names.txt` — cell-type names (one per line)
  - `<sample_dir>/anno_matrix.tsv` — spot × cell-type proportions
  - `<sample_dir>/locs-raw.tsv` — spot x/y in raw fullres pixels
  - `<sample_dir>/locs.tsv` — spot x/y scaled to processed-image pixels
  - `<sample_dir>/radius-raw.txt` — spot radius in raw pixels
  - `<sample_dir>/radius.txt` — spot radius in processed-image pixels
  - `<sample_dir>/pixel-size.txt` — target MPP

**Dependency:** Requires `pixel-size-raw.txt` from Step 3 sub-step 1 (`get_pixel_size.py`).

---

## Step 1.6 — Visium QC Visualization

### `cmd_visualize_visium(cfg, samples) -> List[str]`

| Arg | pipeline.py passes | `visualize_visium_prep.py` expects |
|---|---|---|
| `--data_root` | `cfg.project.data_root` | Required, str |
| `--out_root` | `cfg.project.out_root` | Required, str |
| `--sample_pattern` | `cfg.project.sample_pattern` | Optional, str, default `"*"` |
| `--samples` | comma-joined sample list (if provided) | Optional, str |

- **Inputs (disk, per sample):**
  - `<sample_dir>/anno-names.txt`, `anno_matrix.tsv`, `locs.tsv`, `radius.txt`
  - `<sample_dir>/he.jpg` (or `.jpeg`, `.tiff`, `.tif`)
- **Outputs (disk):**
  - `<out_root>/<sample>/visium_viz/celltype_<ct>.png`
  - `<out_root>/<sample>/visium_viz/argmax_spots.png`

---

## Step 2 — Resolution Check

### `cmd_check_resolution(cfg) -> List[str]`

| Arg | pipeline.py passes | `audit_resolution.py` expects |
|---|---|---|
| `--base_dir` | `cfg.project.data_root` | Required, str |
| `--pattern` | `cfg.project.sample_pattern` | Optional, str, default `"GBM*"` |
| `--raw_flag` | `cfg.preprocess.raw_flag` | Optional, str, default `"he_raw"` |
| `--target_mpp` | `str(cfg.preprocess.target_mpp)` | Optional, float, default 0.5 |

- **Inputs (disk):** Raw H&E images matching `raw_flag` in each sample folder
- **Outputs (disk):** Console only — printed table of actual vs. target MPP

**Match: OK** — all arguments align.

---

## Step 3 / 6a — Per-Sample Preprocessing

### `cmds_preprocess_sample(cfg, sample) -> List[List[str]]`

Returns 6 sequential sub-commands for one sample:

---

### Sub-step 1: `get_pixel_size.py`

| Arg | pipeline.py passes | Script expects |
|---|---|---|
| `--read_dir` | `<data_root>/<sample>` | Required, str |
| `--save_dir` | `<data_root>/<sample>` | Required, str |
| `--sample` | sample name | Optional, str, default `"AAAA"` |
| `--raw_flag` | `cfg.preprocess.raw_flag` | Optional, str, default `"he-raw"` |

- **Inputs:** Raw H&E image in `<read_dir>/` (found via `get_image_filename()` with `raw_flag`)
- **Outputs:** `<save_dir>/pixel-size-raw.txt` — single float (MPP)

**Match: OK**

---

### Sub-step 2: `RunPreprocess.py`

| Arg | pipeline.py passes | Script expects |
|---|---|---|
| `--read_dir` | `<data_root>/<sample>` | Required, str |
| `--save_dir` | `<data_root>/<sample>` | Required, str |
| `--sample` | sample name | Optional, str, default `"AAAA"` |
| `--raw_flag` | `cfg.preprocess.raw_flag` | Optional, str, default `"he-raw"` |
| `--pad` | `cfg.preprocess.pad` (default 224) | Optional, int, default 16 |
| `--scale_value` | `{scale}` placeholder → resolved in `cli.py` | Optional, float, default 1.0 |

- **Inputs:** Raw H&E image, `pixel-size-raw.txt` (read by cli.py to compute scale)
- **Outputs:** `<save_dir>/he.jpg` or `<save_dir>/he.tiff` (rescaled + padded image)

**Match: OK** — The `{scale}` placeholder is resolved in `cli.py` by reading `pixel-size-raw.txt` and dividing by `target_mpp`.

---

### Sub-step 3: `RunHistoSweep.py`

| Arg | pipeline.py passes | Script expects |
|---|---|---|
| `--read_dir` | `<data_root>/<sample>` | Optional, str, default `"AAAA"` |
| `--save_dir` | `"mask"` (hardcoded — must match UNI_extract_features.py expectation) | Optional, str, default `"BBBB"` |

- **Inputs:** `<read_dir>/he.jpg` or `he.tiff` (processed image from sub-step 2)
- **Outputs:** `<read_dir>/<save_dir>/mask-small.png` and `<read_dir>/<save_dir>/mask.png`
  - With default `save_dir="./mask/"`, masks are at `<sample_dir>/mask/mask.png`

**Match: OK** — Downstream scripts (`UNI_extract_features.py`, `visualize_prediction_results.py`) look for `<sample>/mask/mask-small.png`, which is consistent.

**Note:** Pipeline does NOT pass `--pixel_size_raw` or `--pixel_size` arguments that the script accepts. The script defaults both to 0.5. If images are at a different resolution, mask quality could be affected.

---

### Sub-step 4: `UNI_extract_features.py`

| Arg | pipeline.py passes | Script expects |
|---|---|---|
| `--read_path` | `<data_root>/<sample>` | Required, str |
| `--save_dir` | `<data_root>/<sample>` | Required, str |
| `--weight_dir` | `cfg.preprocess.uni_weights` | Optional, str (has hardcoded default) |
| `--sample` | sample name | Required, str |

- **Inputs:** `<read_path>/he.jpg` (or `.tiff`), `<read_path>/mask/mask-small.png`, `<read_path>/mask/mask.png`, UNI model weights
- **Outputs:**
  - `<save_dir>/local_emb.npy` — local patch embeddings
  - `<save_dir>/coords.npy` — patch coordinates
  - `<save_dir>/grid_coords.npy` — grid coordinates
  - `<save_dir>/image.txt` — image dimension metadata
  - `<save_dir>/global_emb.npy` (or `.h5ad` or `.rds` based on `--output_format`, default `h5ad`)

**Note:** Pipeline does NOT pass `--device`, `--batch_size`, `--output_format`, etc. The script defaults are used. The default `--output_format` is `"h5ad"`, which means `global_emb.h5ad` is written.

---

### Sub-step 5: `UNI_fuse_features.py`

| Arg | pipeline.py passes | Script expects |
|---|---|---|
| `--read_global_path` | `<data_root>/<sample>` | Required, str |
| `--read_local_path` | `<data_root>/<sample>` | Required, str |
| `--save_dir` | `<data_root>/<sample>` | Required, str |
| `--sample` | sample name | Required, str |
| `--mode` | `cfg.preprocess.fusion_mode` (default `"single"`) | Optional, str, default `"single"` |

- **Inputs:**
  - `<read_global_path>/global_emb.h5ad` (or `.npy`/`.rds` depending on `--input_format`, default `h5ad`)
  - `<read_local_path>/local_emb.npy`, `coords.npy`, `grid_coords.npy`, `image.txt`
  - `<read_local_path>/mask/mask-small.png`
- **Outputs:**
  - `<save_dir>/single_super_emb.h5ad` (when mode=`"single"`)
  - or `<save_dir>/multi_super_emb.h5ad` (when mode=`"multi"`)

**Note:** The output is `single_super_emb.h5ad`, NOT `embeddings-hist.pickle`. Downstream scripts (`batched_data_preparing.py`, `predict_cdan_multireso.py`) expect the dense `[H,W,C]` `embeddings-hist.pickle`/`.npy` grid, which is produced by a separate conversion step — `meowcat prepare-visium` (Visium samples) or `meowcat prepare-xenium` (Xenium samples).

---

### Sub-step 6: `prepare_visium_inputs.py`

| Arg | pipeline.py passes | Script expects |
|---|---|---|
| `--sample_dir` | `<data_root>/<sample>` | Required, str |
| `--target_mpp` | `str(cfg.preprocess.target_mpp)` | Optional, float, default 0.5 |

- **Inputs:** `pixel-size-raw.txt`, RCTD output, Visium spatial data (same as Step 1.5)
- **Outputs:** `anno-names.txt`, `anno_matrix.tsv`, `locs.tsv`, `locs-raw.tsv`, `radius.txt`, `radius-raw.txt`, `pixel-size.txt`

**Note:** This step is Visium-specific and skips gracefully for non-Visium samples. It is also independently callable via `meowcat prepare-visium` (Step 1.5).

---

## Step 4 — Batch Preparation

### `cmd_prepare_batches(cfg, config_path) -> List[str]`

| Arg | pipeline.py passes | `batched_data_preparing.py` expects |
|---|---|---|
| `--config` | path to the YAML config file | Optional (parsed via `_ap.parse_known_args()`) |

- **Config fields consumed (via YAML override):**
  - `project.data_root` → `PREFIX`
  - `batches.out_dir` → `OUT_DIR`
  - `visium.keep_frac` → `KEEP_FRAC` (fallback: `batches.keep_frac`)
  - `visium.strategy` → `STRATEGY` (fallback: `batches.strategy`)
  - `visium.seed` → `SEED` (fallback: `batches.seed`)
  - `visium.include_only` → `INCLUDE_ONLY` (fallback: `batches.include_only`)
  - `visium.exclude_set` → `EXCLUDE_SET` (fallback: `batches.exclude_set`)
- **Inputs (disk, per Visium sample):**
  - `<PREFIX>/<sample>/embeddings-hist.pickle` — fused UNI features [H,W,C]
  - `<PREFIX>/<sample>/anno-names.txt` — cell-type names
  - `<PREFIX>/<sample>/anno_matrix.tsv` — spot-level proportions
  - `<PREFIX>/<sample>/radius.txt` — spot radius
  - `<PREFIX>/<sample>/locs.tsv` — spot locations (scaled)
- **Inputs (disk, per Xenium sample):**
  - Xenium h5ad, parquet data (paths partially hardcoded in script)
- **Outputs (disk):**
  - `<OUT_DIR>/batch_vis_XXX_x.npy` — [N, T, C] float16 (Visium spot tokens)
  - `<OUT_DIR>/batch_vis_XXX_y.npy` — [N, K] float32 (soft proportions)
  - `<OUT_DIR>/batch_vis_XXX_d.npy` — [N] int64 (domain IDs)
  - `<OUT_DIR>/batch_xen_XXX_x.npy` / `_y.npy` / `_d.npy` — (Xenium equivalents)

**Note:** The `embeddings-hist` grid consumed here is built by `prepare-visium` (Visium) or `prepare-xenium` (Xenium).

---

## Step 5 — Training

### `cmd_train(cfg) -> List[str]`

| Arg | pipeline.py passes | `train_by_batch_cdan5_trainc_final2.py` expects |
|---|---|---|
| positional `prefix` | `cfg.batches.out_dir` | Required — "Working directory with batches/ subfolder" |
| `--n-states` | `cfg.train.n_states` (default 2) | Optional, int, default 5 |
| `--adv-lambda` | `cfg.train.adv_lambda` (default 0.0) | Optional, float, default 0.0 |
| `--freeze-encoder-n` | `cfg.train.freeze_encoder_n` (default 2) | Optional, int, default 0 |
| `--recon-weight` | `cfg.train.recon_weight` (default 0.1) | Optional, float, default 0.0 |
| `--recon-mask-ratio` | `cfg.train.recon_mask_ratio` (default 0.3) | Optional, float, default 0.3 |
| `--save-every-n-epochs` | `cfg.train.save_every_n_epochs` (default 10) | Optional, int, default 10 |
| `--xenium-weight` | `cfg.train.xenium_weight` (default 0.01) | Optional, float, default 1.0 |
| `--monitor-metric` | `cfg.train.monitor_metric` (default `"val_weak_mse"`) | Optional, str, default `"val_loss"` |
| `--device` | `cfg.train.device` (default `"cuda"`) | Optional, str, default `"cuda"` |
| `--two-stage` | flag if `cfg.train.two_stage` | store_true |
| `--epochs1` | `cfg.train.epochs1` (default 15) | Optional, int, default 0 |
| `--sequential-training` | flag if `cfg.train.sequential_training` | store_true |
| `--visium-epochs` | `cfg.train.visium_epochs` (default 100) | Optional, int, default 100 |
| `--xenium-epochs` | `cfg.train.xenium_epochs` (default 100) | Optional, int, default 50 |
| `--oos-sample` | `cfg.train.oos_sample` (optional) | Optional, str |
| `--oos-tmpdir` | `cfg.train.oos_tmpdir` (optional) | Optional, str |

- **Batch directory logic:** The training script first looks for `{prefix}/batches/`. If not found, it falls back to using `{prefix}` itself if batch files exist there directly.
- **Inputs (disk):** `batch_*_x.npy`, `batch_*_y.npy`, `batch_*_d.npy` in the resolved batch directory
- **Outputs (disk):**
  - `<prefix>/states/00/model.ckpt`, `<prefix>/states/01/model.ckpt`, ... (one per state)
  - Lightning logs and metrics inside each state directory

**Note:** Checkpoints are saved under `{cfg.batches.out_dir}/states/`.

---

## Step 6b — Prediction

### `cmd_predict_sample(cfg, sample) -> List[str]`

| Arg | pipeline.py passes | `predict_cdan_multireso.py` expects |
|---|---|---|
| positional `prefix` | `cfg.batches.out_dir` | Required — top-level PREFIX (contains `states/*`) |
| positional `n_states` | `cfg.predict.n_states` (default 2) | Required, int |
| positional `sample_name` | sample name | Required, str |
| `--data-root` | `cfg.project.data_root` | Optional — where per-sample data lives (falls back to `prefix`) |
| `--device` | `cfg.predict.device` (default `"cuda"`) | Optional, str, default `"cuda"` |
| `--tokens-per-chunk` | `cfg.predict.tokens_per_chunk` (default 70000) | Optional, int, default 16384 |
| `--chunks-per-batch` | `cfg.predict.chunks_per_batch` (default 2) | Optional, int, default 1 |
| `--out-pkl-name` | `cfg.predict.out_pkl_name` (default `"pred_fullgrid_outputs.pkl"`) | Optional, str, default `"pred_fullgrid_outputs.pkl"` |

- **Inputs (disk):**
  - `<prefix>/states/00/model.ckpt` ... `<prefix>/states/<n-1>/model.ckpt` — trained checkpoints (from `cfg.batches.out_dir`)
  - `<data_root>/<sample>/embeddings-hist.pickle` or `.npy` — [H,W,C] feature embeddings
  - `<data_root>/<sample>/anno-names.txt` — cell-type names
- **Outputs (disk):**
  - `<data_root>/<sample>/<out_pkl_name>` — dict with `z_map [H,W,D]`, `p_map [H,W,K]`, `ctypes`, etc.

**Note:** Checkpoints are located via the positional prefix (`cfg.batches.out_dir`), and per-sample data via `--data-root` (`cfg.project.data_root`), so the two may live in different directories.

---

## Step 6b — Visualization

### `cmd_visualize_sample(cfg, sample) -> List[str]`

| Arg | pipeline.py passes | `visualize_prediction_results.py` expects |
|---|---|---|
| `--data-root` | `cfg.project.data_root` | Required, str |
| `--data-root-ori` | `cfg.project.data_root` | Optional, str (defaults to `--data-root`) |
| `--sample` | sample name | Required, str |
| `--pkl-name` | `cfg.predict.out_pkl_name` | Optional, str (must provide `--pkl-name` or `--pkl-path`) |
| `--out-root` | `cfg.project.out_root` | Required, str |
| `--n-clusters` | `cfg.visualize.n_clusters` (default 6) | Optional, int, default 6 |
| `--pca-comp` | `cfg.visualize.pca_comp` (default 100) | Optional, int, default 100 |
| `--random-seed` | `cfg.visualize.random_seed` (default 0) | Optional, int, default 0 |
| `--p-lo` | `cfg.visualize.p_lo` (default 5) | Optional, float, default 5.0 |
| `--p-hi` | `cfg.visualize.p_hi` (default 95) | Optional, float, default 95.0 |
| `--save-highlights` | flag if `cfg.visualize.save_highlights` | store_true |

- **Inputs (disk):**
  - `<data_root>/<sample>/<pkl_name>` — prediction pickle (from Step 6b predict)
  - `<data_root_ori>/<sample>/mask/mask-small.png` — tissue mask
  - `<data_root>/<sample>/anno-names.txt` — cell-type names (optional, used if not in pickle)
- **Outputs (disk):**
  - `<out_root>/<sample>/clusters/<sample>_kmeans_k<n>.png`
  - `<out_root>/<sample>/cluster_highlights/<sample>_cluster_<id>.png` (if `--save-highlights`)
  - `<out_root>/<sample>/celltype_intensity_percentiles/masked_<ct>.png`
  - `<out_root>/<sample>/<sample>_predicted_celltype_map.png`
  - `<out_root>/<sample>/summary.txt`

**Match: OK** — arguments align correctly with the script.

---

## Step 7 — Slide Wrap

### `cmd_slide(cfg) -> List[str]`

| Arg | pipeline.py passes | `visualize_slide_wrap.py` expects |
|---|---|---|
| `--out-root` | `cfg.project.out_root` | Required, Path |
| `--pptx` | resolved path (absolute or relative to `out_root`) | Required, Path |
| `--intensity-cols` | `cfg.slide.intensity_cols` (default 3) | Optional, int, default 3 |
| `--intensity-rows` | `cfg.slide.intensity_rows` (default 2) | Optional, int, default 2 |
| `--highlight-cols` | `cfg.slide.highlight_cols` (default 4) | Optional, int, default 4 |
| `--highlight-rows` | `cfg.slide.highlight_rows` (default 3) | Optional, int, default 3 |

- **Inputs (disk):**
  - `<out_root>/<sample>/clusters/*.png`
  - `<out_root>/<sample>/<sample>_predicted_celltype_map.png`
  - `<out_root>/<sample>/cluster_highlights/*.png` (optional)
  - `<out_root>/<sample>/celltype_intensity_percentiles/*.png`
  - `<out_root>/<sample>/summary.txt` (optional)
- **Outputs (disk):**
  - `<pptx>` — PowerPoint presentation

**Match: OK**

---

## `run-all` Command (cli.py)

Executes steps in order:
1. `cmd_rctd` (Step 1)
2. `cmd_check_resolution` (Step 2)
3. `cmd_preprocess` (Step 3, includes `prepare_visium` as last sub-step)
4. `cmd_prepare_batches` (Step 4)
5. `cmd_train` (Step 5)
6. `cmd_predict` (Step 6b)
7. `cmd_visualize` (Step 6b)
8. `cmd_slide` (Step 7)

**Note:** Does NOT include `visualize-visium` (Step 1.6), which is a QC-only step.

---

## Data Flow Summary

```
Raw H&E image + spatial data
        │
        ▼
[Step 1] RCTD ──────────► major_prop.csv (Visium only)
        │
        ▼
[Step 2] audit_resolution  (console check, no files)
        │
        ▼
[Step 3] Preprocess per sample:
   3.1  get_pixel_size     ──► pixel-size-raw.txt
   3.2  RunPreprocess      ──► he.jpg / he.tiff
   3.3  RunHistoSweep      ──► mask/mask.png, mask/mask-small.png
   3.4  UNI_extract        ──► local_emb.npy, global_emb.h5ad, coords.npy, ...
   3.5  UNI_fuse           ──► single_super_emb.h5ad
        │
        ▼
[Step 3.5] Embeddings-hist + Visium metadata (separate commands, split by modality):
   prepare-visium (VIS) ──► embeddings-hist.pickle/.npy + anno-names.txt, anno_matrix.tsv, locs.tsv, radius.txt
   prepare-xenium (XEN) ──► embeddings-hist.pickle/.npy
        │
        ▼
[Step 4] batched_data_preparing ──► batch_vis_*_x/y/d.npy, batch_xen_*_x/y/d.npy
        │
        ▼
[Step 5] train             ──► {batches.out_dir}/states/XX/model.ckpt
        │
        ▼
[Step 6] predict           ──► pred_fullgrid_outputs.pkl
        │
        ▼
[Step 6] visualize         ──► argmax_map.png, intensity maps, cluster maps
        │
        ▼
[Step 7] slide_wrap        ──► results.pptx
```
