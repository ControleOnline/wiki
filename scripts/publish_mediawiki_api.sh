#!/usr/bin/env bash
set -euo pipefail

: "${MEDIAWIKI_API_URL:=https://ajuda.controleonline.com/api.php}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cookie_file="$(mktemp)"
credential_file=""
trap 'unlink "$cookie_file" 2>/dev/null || true; if [[ -n "$credential_file" ]]; then unlink "$credential_file" 2>/dev/null || true; fi' EXIT

load_credentials_from_ftp() {
  : "${FTP_HOST:?FTP_HOST is required when MediaWiki credentials are not in the environment}"
  : "${FTP_PORT:?FTP_PORT is required when MediaWiki credentials are not in the environment}"
  : "${FTP_USER:?FTP_USER is required when MediaWiki credentials are not in the environment}"
  : "${FTP_PASSWORD:?FTP_PASSWORD is required when MediaWiki credentials are not in the environment}"

  local credential_path="${MEDIAWIKI_CREDENTIALS_FTP_PATH:-../.controleonline/mediawiki.env}"
  credential_file="$(mktemp)"

  lftp -u "$FTP_USER","$FTP_PASSWORD" -p "$FTP_PORT" "$FTP_HOST" <<EOF
set cmd:fail-exit true
set net:max-retries 2
set net:timeout 20
set xfer:clobber true
set ftp:ssl-allow true
set ssl:verify-certificate false
get "$credential_path" -o "$credential_file"
bye
EOF

  set -a
  # shellcheck disable=SC1090
  source "$credential_file"
  set +a
}

if [[ -z "${MEDIAWIKI_USERNAME:-}" || -z "${MEDIAWIKI_PASSWORD:-}" ]]; then
  load_credentials_from_ftp
fi

: "${MEDIAWIKI_USERNAME:?MEDIAWIKI_USERNAME is required}"
: "${MEDIAWIKI_PASSWORD:?MEDIAWIKI_PASSWORD is required}"

api_post() {
  curl -fsS \
    --cookie "$cookie_file" \
    --cookie-jar "$cookie_file" \
    -X POST \
    "$MEDIAWIKI_API_URL" \
    "$@"
}

api_get() {
  curl -fsS \
    --cookie "$cookie_file" \
    --cookie-jar "$cookie_file" \
    --get \
    "$MEDIAWIKI_API_URL" \
    "$@"
}

login_token="$(
  api_get \
    --data-urlencode action=query \
    --data-urlencode meta=tokens \
    --data-urlencode type=login \
    --data-urlencode format=json |
    jq -r '.query.tokens.logintoken'
)"

login_result="$(
  api_post \
    --data-urlencode action=login \
    --data-urlencode format=json \
    --data-urlencode lgname="$MEDIAWIKI_USERNAME" \
    --data-urlencode lgpassword="$MEDIAWIKI_PASSWORD" \
    --data-urlencode lgtoken="$login_token" |
    jq -r '.login.result'
)"

if [[ "$login_result" != "Success" ]]; then
  echo "MediaWiki login failed: $login_result" >&2
  exit 1
fi

csrf_token="$(
  api_get \
    --data-urlencode action=query \
    --data-urlencode meta=tokens \
    --data-urlencode type=csrf \
    --data-urlencode format=json |
    jq -r '.query.tokens.csrftoken'
)"

publish_page() {
  local title="$1"
  local file="$2"
  local summary="$3"

  local response
  response="$(
    api_post \
      --data-urlencode action=edit \
      --data-urlencode format=json \
      --data-urlencode title="$title" \
      --data-urlencode text@"$file" \
      --data-urlencode summary="$summary" \
      --data-urlencode token="$csrf_token" \
      --data-urlencode bot=true
  )"

  local result
  result="$(jq -r '.edit.result // .error.code // "unknown"' <<<"$response")"
  if [[ "$result" != "Success" ]]; then
    echo "Failed to publish $title: $result" >&2
    exit 1
  fi

  jq -r '"published \(.edit.title) rev \(.edit.newrevid)"' <<<"$response"
}

remove_page() {
  local title="$1"
  local response
  response="$(
    api_post \
      --data-urlencode action=delete \
      --data-urlencode format=json \
      --data-urlencode title="$title" \
      --data-urlencode reason="Remove conteúdo fora do escopo da documentação de cliente" \
      --data-urlencode token="$csrf_token" || true
  )"

  if [[ "$(jq -r '.delete.title // empty' <<<"$response")" == "$title" ]]; then
    echo "removed $title"
    return
  fi

  if [[ "$(jq -r '.error.code // empty' <<<"$response")" == "missingtitle" ]]; then
    echo "already absent $title"
    return
  fi

  publish_page \
    "$title" \
    "$repo_root/mediawiki/removed-page.wiki" \
    "Remove conteúdo fora do escopo da documentação de cliente"
}

publish_page \
  "Project" \
  "$repo_root/mediawiki/Project.wiki" \
  "Atualiza indice publico de tarefas documentadas"

publish_page \
  "Project/CRM - Edição de endereço de cliente" \
  "$repo_root/mediawiki/project/crm-edicao-endereco-cliente.wiki" \
  "Documenta melhoria de CRM para cliente final"

remove_page "Project/Agents-mcp 41 - Governança de mudanças internas"
