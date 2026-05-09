#!/usr/bin/env bash
set -euo pipefail

: "${FTP_HOST:?FTP_HOST is required}"
: "${FTP_PORT:?FTP_PORT is required}"
: "${FTP_USER:?FTP_USER is required}"
: "${FTP_PASSWORD:?FTP_PASSWORD is required}"

ftp_ssl_verify="${FTP_SSL_VERIFY:-false}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_root="$repo_root/site/.sync-tmp"
incoming_dir="$work_root/incoming"
site_dir="$repo_root/site"

rm -rf "$work_root"
mkdir -p "$incoming_dir"

lftp -u "$FTP_USER","$FTP_PASSWORD" -p "$FTP_PORT" "$FTP_HOST" <<EOF
set cmd:fail-exit true
set net:max-retries 2
set net:timeout 20
set xfer:clobber true
set ftp:ssl-allow true
set ssl:verify-certificate $ftp_ssl_verify
mirror --verbose --delete --only-newer / "$incoming_dir"
bye
EOF

bash "$repo_root/scripts/filter_public_files.sh" "$incoming_dir"

find "$site_dir" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf {} +
rsync -a --delete --exclude '.gitkeep' "$incoming_dir"/ "$site_dir"/

rm -rf "$work_root"
