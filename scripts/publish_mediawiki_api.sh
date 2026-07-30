#!/usr/bin/env bash
set -euo pipefail

: "${MEDIAWIKI_API_URL:=https://ajuda.controleonline.com/api.php}"
: "${MEDIAWIKI_USERNAME:?MEDIAWIKI_USERNAME is required}"
: "${MEDIAWIKI_PASSWORD:?MEDIAWIKI_PASSWORD is required}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cookie_file="$(mktemp)"
trap 'unlink "$cookie_file" 2>/dev/null || true' EXIT

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

publish_page \
  "Project" \
  "$repo_root/mediawiki/Project.wiki" \
  "Atualiza indice publico de tarefas documentadas"

publish_page \
  "Project/Agents-mcp 41 - Governança de mudanças internas" \
  "$repo_root/mediawiki/project/agents-mcp-41-governanca-de-mudancas-internas.wiki" \
  "Documenta tarefa agents-mcp 41 para cliente final"
