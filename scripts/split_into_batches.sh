#!/usr/bin/env bash
set -euo pipefail

# Load config if present
if [[ -f "config/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "config/env.sh"
fi

BASE_DIR="${LOCAL_BASE_DIR:-$(pwd)}"
NBATCH="${NBATCH:-20}"
MODE="${SPLIT_MODE:-link}"

if ! [[ "$NBATCH" =~ ^[0-9]+$ ]] || (( NBATCH < 1 )); then
  echo "NBATCH must be a positive integer. Got: $NBATCH" >&2
  exit 1
fi
if [[ "$MODE" != "link" && "$MODE" != "move" ]]; then
  echo "SPLIT_MODE must be link or move. Got: $MODE" >&2
  exit 1
fi

shopt -s nullglob

files=( "$BASE_DIR"/*.fastq.gz )
if (( ${#files[@]} == 0 )); then
  echo "No *.fastq.gz found in: $BASE_DIR" >&2
  exit 1
fi

# Create batch dirs
for i in $(seq -w 1 "$NBATCH"); do
  mkdir -p "$BASE_DIR/batch${i}"
done

tmp_samples="$(mktemp)"
tmp_map="$(mktemp)"
trap 'rm -f "$tmp_samples" "$tmp_map"' EXIT

# sample = everything before first underscore
for f in "${files[@]}"; do
  bn="$(basename "$f")"
  sample="${bn%%_*}"
  size=$(stat -c%s "$f")
  printf "%s\t%s\t%s\n" "$sample" "$size" "$f" >> "$tmp_map"
done

# totals per sample, largest first
awk -F'\t' '{sum[$1]+=$2} END{for(s in sum) print s"\t"sum[s]}' "$tmp_map" \
  | sort -k2,2nr > "$tmp_samples"

declare -a batch_total batch_name
for i in $(seq 1 "$NBATCH"); do
  batch_total[$i]=0
  batch_name[$i]=$(printf "batch%02d" "$i")
done

out_tsv="$BASE_DIR/batch_assignment.tsv"
echo -e "sample\tbytes\tbatch" > "$out_tsv"

while IFS=$'\t' read -r sample total_bytes; do
  # choose smallest bin
  best=1
  best_val=${batch_total[1]}
  for i in $(seq 2 "$NBATCH"); do
    if (( batch_total[$i] < best_val )); then
      best=$i
      best_val=${batch_total[$i]}
    fi
  done

  echo -e "${sample}\t${total_bytes}\t${batch_name[$best]}" >> "$out_tsv"
  target_dir="$BASE_DIR/${batch_name[$best]}"

  # place all sample files
  while IFS=$'\t' read -r s size path; do
    [[ "$s" == "$sample" ]] || continue
    if [[ "$MODE" == "link" ]]; then
      ln -sf "$path" "$target_dir/$(basename "$path")"
    else
      mv -n "$path" "$target_dir/"
    fi
  done < "$tmp_map"

  batch_total[$best]=$(( batch_total[$best] + total_bytes ))
done < "$tmp_samples"

echo
echo "Batch totals:"
for i in $(seq 1 "$NBATCH"); do
  printf "%s\t%s bytes\n" "${batch_name[$i]}" "${batch_total[$i]}"
done
echo "Wrote: $out_tsv"
