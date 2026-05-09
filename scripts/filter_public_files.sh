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
)

for pattern in "${patterns[@]}"; do
  find "$target_dir" -name "$pattern" -print -exec rm -rf {} +
done

find "$target_dir" -type d -empty -delete
