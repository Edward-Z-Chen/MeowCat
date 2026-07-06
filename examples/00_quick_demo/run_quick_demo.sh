#!/usr/bin/env bash
# =============================================================================
# MeowCat quick demo — two examples in one command.
#
#   Demo 1 (ex01): Train + impute on a single Visium sample (VIS_P11_LUAD).
#   Demo 2 (ex06): Predict on a new H&E slide (P24_LUAD_Xenium) with a
#                  pre-trained model.
#
# Both demos start from pre-extracted UNI features
# (single_super_emb.h5ad) so the slow HistoSweep + UNI extraction stage is
# skipped. `meowcat prepare-visium` (ex01) and `meowcat infer` (ex06) both
# regenerate embeddings-hist from single_super_emb.h5ad on the fly.
#
# Prerequisites
#   - The he_anno conda env is installed and activated.
#   - ~20 GB free disk in this folder.
#
# Usage
#   conda activate he_anno
#   bash run_quick_demo.sh > 07052026_quick_demo.txt 2>&1 &
#
# Idempotent: the download step is skipped if the sample folder already exists.
# =============================================================================
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${DEMO_DIR}"

# ---------------------------------------------------------------------------
# Box shared direct-download links for the pre-extracted demo bundles
# (ex01_from_features.tar.gz and ex06_from_features.tar.gz).
# ---------------------------------------------------------------------------
BOX_EX01="https://upenn.box.com/shared/static/637aawkpvrxqhop51saqt4runadrli40.gz"
BOX_EX06="https://upenn.box.com/shared/static/fby0bit7h5p2ob3fibg0mbx2cdovpo8v.gz"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
render_config() {
    # Substitute __DEMO_DIR__ placeholder in the shipped config template.
    local src="$1" dst="$2"
    sed "s|__DEMO_DIR__|${DEMO_DIR}|g" "${src}" > "${dst}"
}

download_and_extract() {
    local url="$1" dest_dir="$2" marker="$3"
    if [ -e "${marker}" ]; then
        echo "[skip] ${marker} already present"
        return
    fi
    if [ -z "${url}" ]; then
        echo "ERROR: Box URL not set for ${dest_dir}. Edit BOX_EX01/BOX_EX06 in this script." >&2
        exit 1
    fi
    mkdir -p "${dest_dir}"
    local tmp_tar="${DEMO_DIR}/_download.tar.gz"
    echo "[download] ${url} -> ${dest_dir}"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail -o "${tmp_tar}" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${tmp_tar}" "${url}"
    else
        echo "ERROR: need curl or wget to download demo data." >&2
        exit 1
    fi
    echo "[extract] -> ${dest_dir}"
    tar -xzf "${tmp_tar}" -C "${dest_dir}"
    rm -f "${tmp_tar}"
}

echo "============================================"
echo " MeowCat quick demo"
echo " Demo dir: ${DEMO_DIR}"
echo "============================================"

# ---------------------------------------------------------------------------
# Demo 1: Visium train + impute (ex01)
# ---------------------------------------------------------------------------
echo
echo "=== Demo 1: Visium train + impute (VIS_P11_LUAD) ==="
mkdir -p ex01/input ex01/output
download_and_extract "${BOX_EX01}" "${DEMO_DIR}/ex01/input" "${DEMO_DIR}/ex01/input/VIS_P11_LUAD"

render_config config_ex01.yaml ex01/config.yaml
CFG1="${DEMO_DIR}/ex01/config.yaml"

echo "[Step 3.5] Visium metadata + embeddings-hist"
meowcat prepare-visium         --config "${CFG1}"
echo "[Step 4] Batch preparation"
meowcat prepare-visium-batches --config "${CFG1}"
echo "[Step 5] Training (Recon -> Visium MSE)"
meowcat train                  --config "${CFG1}"
echo "[Step 6] Prediction"
meowcat predict                --config "${CFG1}"
echo "[Step 6] Visualization"
meowcat visualize              --config "${CFG1}"
echo "[Step 7] Slide wrap"
meowcat slide                  --config "${CFG1}"

# ---------------------------------------------------------------------------
# Demo 2: Predict on new H&E with pre-trained model (ex06)
# ---------------------------------------------------------------------------
echo
echo "=== Demo 2: Predict on new H&E (P24_LUAD_Xenium) ==="
mkdir -p ex06/output
# The ex06 tarball contains BOTH input/ and model/ at its top level, so extract
# into the ex06 root and use the input sample dir as the idempotency marker.
download_and_extract "${BOX_EX06}" "${DEMO_DIR}/ex06" "${DEMO_DIR}/ex06/input/P24_LUAD_Xenium"

render_config config_ex06.yaml ex06/config.yaml
CFG6="${DEMO_DIR}/ex06/config.yaml"

meowcat infer --config "${CFG6}" --start-from 6

echo
echo "============================================"
echo " Done."
echo "   Demo 1 results: ${DEMO_DIR}/ex01/output/"
echo "   Demo 2 results: ${DEMO_DIR}/ex06/output/"
echo "============================================"
