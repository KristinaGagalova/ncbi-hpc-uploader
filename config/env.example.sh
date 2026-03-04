# Copy to config/env.sh and edit. Please fill the missing fields
# DO NOT COMMIT env.sh (it's gitignored).

# Local data directory containing *.fastq.gz
export LOCAL_BASE_DIR=""

# How many batches to create/use
export NBATCH="20"

# How to place files into batch dirs: link or move (link recommended)
export SPLIT_MODE="link"

# Remote NCBI base path
export NCBI_HOST="sftp-private.ncbi.nlm.nih.gov"
export NCBI_USER="subftp"
export NCBI_ACCOUNT_DIR=""

# Remote folder prefix;
export REMOTE_PREFIX=""

# Upload glob within each batch
export UPLOAD_GLOB="*fastq.gz"

# lftp parallelism (0/1 disables parallel)
export LFTP_PARALLEL="2"
