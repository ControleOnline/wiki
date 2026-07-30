#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:?target directory is required}"

if [[ ! -d "$target_dir" ]]; then
  echo "target directory not found: $target_dir" >&2
  exit 1
fi

patterns=(
  ".git"
  ".svn"
  ".hg"
  ".env"
  ".env.*"
  "*.env"
  "mediawiki.env"
  "*.key"
  "*.pem"
  "*.p12"
  "*.pfx"
  "*.crt"
  "*.csr"
  "*.der"
  "id_rsa"
  "id_dsa"
  "authorized_keys"
  "wp-config.php"
  "configuration.php"
  "config.php"
  "config.local.php"
  "LocalSettings.php"
  "LocalSettings.*.php"
  "local.xml"
  ".htpasswd"
  ".user.ini"
  "*.sql"
  "*.sql.gz"
  "*.sqlite"
  "*.sqlite3"
  "*.db"
  "*.bak"
  "*.backup"
  "*.old"
  "*.orig"
  "*.log"
  "error_log"
  "access_log"
  "php_errorlog"
  "*.zip"
  "*.tar"
  "*.tar.gz"
  "*.tgz"
  "*.rar"
  "*.7z"
  "*.jpg"
  "*.jpeg"
  "*.png"
  "*.gif"
  "*.webp"
  "*.svg"
  "*.ico"
  "*.bmp"
  "*.tif"
  "*.tiff"
  "*.avif"
  "*.heic"
  "*.heif"
)

directories=(
  ".controleonline"
  "archive"
  "cache"
  "deleted"
  "images"
  "mwstore"
  "temp"
  "thumb"
  "uploads"
)

for pattern in "${patterns[@]}"; do
  find "$target_dir" -name "$pattern" -print -exec rm -rf {} +
done

for directory in "${directories[@]}"; do
  find "$target_dir" -type d -name "$directory" -print -exec rm -rf {} +
done

find "$target_dir" -type d -empty -delete
