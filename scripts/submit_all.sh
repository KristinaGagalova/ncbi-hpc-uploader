#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source config/env.sh

for i in $(seq -w 1 "$NBATCH"); do
  SBATCH_SCRIPT="slurm/batch${i}.sbatch"
  if [[ -f "$SBATCH_SCRIPT" ]]; then
    echo "Submitting ${SBATCH_SCRIPT}"
    sbatch "$SBATCH_SCRIPT"
  fi
done
