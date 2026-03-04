#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/verify_remote_sizes.sh batch01 SUB123456_related_data [--all|--ok]
#
# Default: print only MISSING/PARTIAL
#   --all : print OK + MISSING + PARTIAL
#   --ok  : print only OK matches
#
# Debug:
#   DEBUG=1 ./scripts/verify_remote_sizes.sh batch01 SUB123456_related_data --all

BATCH="${1:-}"
REMOTE_SUBDIR="${2:-}"
MODE="${3:-}"
DEBUG="${DEBUG:-0}"

if [[ -z "$BATCH" || -z "$REMOTE_SUBDIR" ]]; then
  echo "Usage: $0 <batchXX> <remote_subdir_name> [--all|--ok]" >&2
  exit 1
fi

if [[ -n "$MODE" && "$MODE" != "--all" && "$MODE" != "--ok" ]]; then
  echo "Unknown option: $MODE (use --all or --ok)" >&2
  exit 1
fi

# shellcheck disable=SC1091
source ../config/env.sh

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
need lftp
need stat
need awk
need wc
need head
need find
need sort

LOCAL_DIR="${LOCAL_BASE_DIR}/${BATCH}"
if [[ ! -d "$LOCAL_DIR" ]]; then
  echo "Local batch directory not found: $LOCAL_DIR" >&2
  exit 1
fi

# Collect local fastqs (files OR symlinks)
mapfile -t local_files < <(find "$LOCAL_DIR" -maxdepth 1 \( -type f -o -type l \) -name "*.fastq.gz" | sort)
if (( ${#local_files[@]} == 0 )); then
  echo "No *.fastq.gz found in: $LOCAL_DIR" >&2
  exit 1
fi

# Temp files
REMOTE_RAW="$(mktemp)"
REMOTE_SIZES="$(mktemp)"
trap 'rm -f "$REMOTE_RAW" "$REMOTE_SIZES"' EXIT

REMOTE_PATH="${NCBI_ACCOUNT_DIR}/${REMOTE_SUBDIR}"

if (( DEBUG == 1 )); then
  echo "DEBUG: LOCAL_DIR=$LOCAL_DIR"
  echo "DEBUG: REMOTE_PATH=$REMOTE_PATH"
  echo "DEBUG: NCBI_HOST=$NCBI_HOST"
  echo "DEBUG: local file count=${#local_files[@]}"
  echo
fi

# Try MLSD first (machine readable)
MLSD_OK=0
if lftp -u "${NCBI_USER},${NCBI_PASS}" "sftp://${NCBI_HOST}" -e "
  set net:timeout 30;
  set net:max-retries 1;
  cd ${REMOTE_PATH};
  mlsd;
  bye
" > "$REMOTE_RAW" 2>/dev/null; then
  # If mlsd returns something that looks like type=file;size=...
  if grep -q "size=" "$REMOTE_RAW"; then
    MLSD_OK=1
    awk -F';' '
      {
        name=$NF; sub(/^ /,"",name);
        size="";
        for(i=1;i<=NF;i++){
          if($i ~ /^size=/){ s=$i; sub(/^size=/,"",s); size=s }
        }
        if(size ~ /^[0-9]+$/ && name != "" && name != "." && name != "..") print name "\t" size;
      }
    ' "$REMOTE_RAW" > "$REMOTE_SIZES"
  fi
fi

# Fallback to cls -l if MLSD not usable
if (( MLSD_OK == 0 )); then
  lftp -u "${NCBI_USER},${NCBI_PASS}" "sftp://${NCBI_HOST}" -e "
    set net:timeout 30;
    set net:max-retries 1;
    cd ${REMOTE_PATH};
    cls -l;
    bye
  " > "$REMOTE_RAW"

  # Robust parser:
  # - filename is last field
  # - size is often $4 (your server)
  awk '
    {
      name=$NF
      size=""
      if($4 ~ /^[0-9]+$/) size=$4
      else if($4 ~ /^[0-9]+$/) size=$4
      if(size ~ /^[0-9]+$/ && name != "" && name != "." && name != "..") print name "\t" size
    }
  ' "$REMOTE_RAW" > "$REMOTE_SIZES"
fi

remote_entries="$(wc -l < "$REMOTE_SIZES" | tr -d ' ')"

if (( DEBUG == 1 )); then
  echo "DEBUG: remote size entries=$remote_entries (MLSD_OK=$MLSD_OK)"
  echo "DEBUG: first 10 remote entries:"
  head -n 10 "$REMOTE_SIZES" || true
  echo
fi

if (( remote_entries == 0 )); then
  echo "ERROR: Could not parse any remote file sizes from: $REMOTE_PATH" >&2
  echo "Likely causes:" >&2
  echo "  - Wrong REMOTE_SUBDIR (folder empty / different) OR" >&2
  echo "  - Server listing format changed (need different parser)" >&2
  echo >&2
  echo "To debug, run manually:" >&2
  echo "  lftp -u \"${NCBI_USER},<PASS>\" \"sftp://${NCBI_HOST}\" -e \"cd ${REMOTE_PATH}; cls -l; bye\"" >&2
  exit 3
fi

echo "Comparing local vs remote sizes for ${BATCH} -> ${REMOTE_SUBDIR}"
echo "Local:  ${LOCAL_DIR}"
echo "Remote: ${REMOTE_PATH}"
echo

bad=0
checked=0
okcount=0
missing=0
partial=0

for lf in "${local_files[@]}"; do
  bn="$(basename "$lf")"

  # Important: -L dereferences symlinks (SPLIT_MODE=link)
  lsize="$(stat -Lc%s "$lf")"

  rsize="$(awk -F'\t' -v n="$bn" '$1==n{print $2}' "$REMOTE_SIZES" | head -n1 || true)"

  checked=$((checked+1))

  if (( DEBUG == 1 )) && (( checked <= 5 )); then
    echo "DEBUG: $bn local=$lsize remote=${rsize:-NONE}"
  fi

  if [[ -z "${rsize:-}" ]]; then
    missing=$((missing+1))
    bad=$((bad+1))
    if [[ "$MODE" != "--ok" ]]; then
      echo "MISSING  $bn"
    fi
    continue
  fi

  if [[ "$rsize" != "$lsize" ]]; then
    partial=$((partial+1))
    bad=$((bad+1))
    if [[ "$MODE" != "--ok" ]]; then
      echo "PARTIAL  $bn  local=$lsize  remote=$rsize"
    fi
    continue
  fi

  okcount=$((okcount+1))
  if [[ "$MODE" == "--all" || "$MODE" == "--ok" ]]; then
    echo "OK       $bn  bytes=$lsize"
  fi
done

echo
echo "Checked: $checked"
echo "OK:      $okcount"
echo "Missing: $missing"
echo "Partial: $partial"
echo

if (( bad == 0 )); then
  echo "OK: all files present and sizes match."
else
  echo "PROBLEM: $bad files are missing or size-mismatched."
  echo "Suggestion: delete partials on remote and re-upload affected files."
  exit 2
fi
