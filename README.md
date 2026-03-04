# ncbi-hpc-uploader

Utilities to split large FASTQ collections into balanced batches and upload them to the NCBI SFTP preload space from HPC environments (e.g. Pawsey / Setonix).
This tool helps manage large sequencing datasets by automatically grouping files into balanced batches and generating upload scripts.

## What it does
* Groups files by sample ID (prefix before the first _)
* Balances samples across batch01..batchNN using greedy bin packing by total size
* Creates batch directories (symlink mode recommended)
* Generates per-batch lftp upload scripts
Optionally generates SLURM sbatch jobs for automated uploads

Produces a `batch_assignment.tsv` file summarizing the distribution

## Repository structure
```
ncbi-hpc-uploader
├── config
│   └── env.example.sh
├── scripts
│   ├── split_into_batches.sh
│   ├── generate_lftp_jobs.sh
│   └── submit_all.sh
├── lftp
│   └── upload_batch.lftp.template
├── slurm
│   └── upload_batch.sbatch.template
└── README.md
```

## Setup
Clone the repository and create a local configuration file.
``
cp config/env.example.sh config/env.sh
```
Edit the configuration file:
```
nano config/env.sh
```
Example configuration:
```
export LOCAL_BASE_DIR="/scratch/project/data/fastq"
export NBATCH="20"
export SPLIT_MODE="link"

export NCBI_HOST="sftp-private.ncbi.nlm.nih.gov"
export NCBI_USER="subftp"
export NCBI_PASS="your_ncbi_password"

export NCBI_ACCOUNT_DIR="uploads/your_account_directory"
export REMOTE_PREFIX="submission_batch"

export UPLOAD_GLOB="*fastq.gz"
Step 1 — Split FASTQ files into balanced batches
```
Run:
```
./scripts/split_into_batches.sh
```
This will:
* group FASTQ files by sample
* compute total size per sample
* distribute samples across batch01..batchNN
* create symlinked batch directories
generate
* batch_assignment.tsv

Example override:
```
NBATCH=20 SPLIT_MODE=link LOCAL_BASE_DIR=/data ./scripts/split_into_batches.sh
```
After running, your directory will look like:
```
batch01/
batch02/
batch03/
...
batch20/
```
Each batch contains FASTQ files belonging to a balanced set of samples.

## Step 2 — Generate upload scripts

Generate lftp and optional SLURM scripts:
```
./scripts/generate_lftp_jobs.sh
```
This creates:
```
lftp/batch01.lftp
lftp/batch02.lftp
...

slurm/batch01.sbatch
slurm/batch02.sbatch
...
```
Each script uploads a specific batch to the NCBI preload directory.

## Step 3 — Upload the data
Option 1 — Interactive upload (recommended)

Run lftp from a login or data transfer node:
```
lftp -u $NCBI_USER,$NCBI_PASS sftp://$NCBI_HOST -f lftp/batch01.lftp
```
You can repeat for each batch.

## Option 2 — Automated upload using SLURM

If your HPC system allows outbound SFTP from compute nodes, submit all jobs:
```
./scripts/submit_all.sh
```
This will submit one SLURM job per batch.

Monitor jobs with:
```
squeue -u $USER
```

## Authentication

Authentication is handled via environment variables defined in config/env.sh.

These variables are passed to lftp:
```
lftp -u "$NCBI_USER,$NCBI_PASS" "sftp://$NCBI_HOST"
```
This expands to the standard SFTP login:
```
lftp -u subftp,<password> sftp://sftp-private.ncbi.nlm.nih.gov
```

## Security notes

`config/env.sh` contains credentials and must not be committed

`.gitignore` excludes this file from version control

`config/env.example.sh` provides a template without credentials

To create your local configuration:
```
cp config/env.example.sh config/env.sh
```

## Example workflow
```
# configure environment
cp config/env.example.sh config/env.sh
nano config/env.sh

# split FASTQ files
./scripts/split_into_batches.sh

# generate upload scripts
./scripts/generate_lftp_jobs.sh

# upload interactively
lftp -u $NCBI_USER,$NCBI_PASS sftp://$NCBI_HOST -f lftp/batch01.lftp
Output files
file	description
batch_assignment.tsv	sample → batch mapping
batchXX/	batch directories containing FASTQ symlinks
lftp/*.lftp	upload scripts
slurm/*.sbatch	optional HPC upload jobs
```

## Requirements

* bash ≥ 4
* lftp
* SLURM (optional)

## License

MIT License
