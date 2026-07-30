#!/usr/bin/env bash
set -euo pipefail

: "${FTP_HOST:?FTP_HOST is required}"
: "${FTP_PORT:?FTP_PORT is required}"
: "${FTP_USER:?FTP_USER is required}"
: "${FTP_PASSWORD:?FTP_PASSWORD is required}"
: "${MEDIAWIKI_USERNAME:?MEDIAWIKI_USERNAME is required}"
: "${MEDIAWIKI_PASSWORD:?MEDIAWIKI_PASSWORD is required}"

credential_path="${MEDIAWIKI_CREDENTIALS_FTP_PATH:-../.controleonline/mediawiki.env}"

case "$credential_path" in
  ""|"/"|"/public_html"*|"public_html"*|"/htdocs"*|"htdocs"*|"/www"*|"www"*)
    echo "Refusing to write MediaWiki credentials inside a public web directory: $credential_path" >&2
    exit 1
    ;;
esac

quote_env_value() {
  printf "%q" "$1"
}

credential_dir="$(dirname "$credential_path")"
credential_file="$(mktemp)"
trap 'unlink "$credential_file" 2>/dev/null || true' EXIT

{
  printf 'MEDIAWIKI_API_URL=%s\n' "$(quote_env_value "${MEDIAWIKI_API_URL:-https://ajuda.controleonline.com/api.php}")"
  printf 'MEDIAWIKI_USERNAME=%s\n' "$(quote_env_value "$MEDIAWIKI_USERNAME")"
  printf 'MEDIAWIKI_PASSWORD=%s\n' "$(quote_env_value "$MEDIAWIKI_PASSWORD")"
} > "$credential_file"

lftp -u "$FTP_USER","$FTP_PASSWORD" -p "$FTP_PORT" "$FTP_HOST" <<EOF
set cmd:fail-exit true
set net:max-retries 2
set net:timeout 20
set ftp:ssl-allow true
set ssl:verify-certificate false
mkdir -p "$credential_dir"
put "$credential_file" -o "$credential_path"
bye
EOF

echo "MediaWiki credentials stored on FTP outside the public web directory."
