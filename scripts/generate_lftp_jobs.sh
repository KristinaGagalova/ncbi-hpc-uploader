#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source config/env.sh

mkdir -p lftp slurm logs

for i in $(seq -w 1 "$NBATCH"); do
  BATCH="batch${i}"
  LOCAL_DIR="${LOCAL_BASE_DIR}/${BATCH}"
  REMOTE_DIR="${REMOTE_PREFIX}${i}"
  LFTP_SCRIPT="lftp/${BATCH}.lftp"
  SBATCH_SCRIPT="slurm/${BATCH}.sbatch"

  if [[ ! -d "$LOCAL_DIR" ]]; then
    echo "Skipping ${BATCH} (missing ${LOCAL_DIR})"
    continue
  fi

  # Create lftp script from template
  sed \
    -e "s|{{NCBI_ACCOUNT_DIR}}|${NCBI_ACCOUNT_DIR}|g" \
    -e "s|{{REMOTE_DIR}}|${REMOTE_DIR}|g" \
    -e "s|{{LOCAL_DIR}}|${LOCAL_DIR}|g" \
    -e "s|{{UPLOAD_GLOB}}|${UPLOAD_GLOB}|g" \
    -e "s|{{LFTP_PARALLEL}}|${LFTP_PARALLEL}|g" \
    lftp/upload_batch.lftp.template > "${LFTP_SCRIPT}"

  # Create sbatch script from template
  sed \
    -e "s|{{BATCH}}|${BATCH}|g" \
    -e "s|{{LOCAL_DIR}}|${LOCAL_DIR}|g" \
    -e "s|{{REMOTE_DIR}}|${REMOTE_DIR}|g" \
    -e "s|{{LFTP_SCRIPT}}|${LFTP_SCRIPT}|g" \
    slurm/upload_batch.sbatch.template > "${SBATCH_SCRIPT}"

  chmod +x "${SBATCH_SCRIPT}"
  echo "Generated: ${LFTP_SCRIPT} and ${SBATCH_SCRIPT}"
done
