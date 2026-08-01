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

ensure_logo_asset() {
  local logo_file="$repo_root/mediawiki/files/Controle-Online-logo.png"
  local logo_source_url="${LOGO_SOURCE_URL:-https://www.controleonline.com/wp-content/uploads/2026/05/logo-controle-branco-1.png}"

  if [[ ! -f "$logo_file" ]]; then
    mkdir -p "$(dirname "$logo_file")"
    curl -fsSL "$logo_source_url" -o "$logo_file"
  fi

  echo "$logo_file"
}

upload_file "Controle-Online-logo.png" "$(ensure_logo_asset)" "Logo oficial da Controle Online"

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

upload_file() {
  local filename="$1"
  local file="$2"
  local comment="$3"

  if [[ ! -f "$file" ]]; then
    echo "skipped missing optional upload $filename"
    return
  fi

  local response
  response="$(
    curl -fsS \
      --cookie "$cookie_file" \
      --cookie-jar "$cookie_file" \
      -X POST \
      "$MEDIAWIKI_API_URL" \
      -F action=upload \
      -F format=json \
      -F filename="$filename" \
      -F file=@"$file" \
      -F comment="$comment" \
      -F ignorewarnings=1 \
      -F token="$csrf_token"
  )"

  local result
  result="$(jq -r '.upload.result // .error.code // "unknown"' <<<"$response")"
  if [[ "$result" != "Success" && "$result" != "Warning" ]]; then
    echo "Failed to upload $filename: $result" >&2
    exit 1
  fi

  jq -r '"uploaded \(.upload.filename // "'"$filename"'")"' <<<"$response"
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

publish_page "Página principal" "$repo_root/mediawiki/pagina-principal.wiki" "Atualiza a home com layout corporativo"
publish_page "Project" "$repo_root/mediawiki/Project.wiki" "Organiza Central de Ajuda por aplicativos"
publish_page "AltSenha" "$repo_root/mediawiki/altsenha.wiki" "Importa a pagina publica de alteração de senha"
publish_page "Cadastro de Clientes" "$repo_root/mediawiki/cadastro-de-clientes.wiki" "Importa a pagina publica de cadastro de clientes"
publish_page "Cduser" "$repo_root/mediawiki/cduser.wiki" "Importa a pagina publica de cadastro de usuario"
publish_page "Clientes" "$repo_root/mediawiki/clientes.wiki" "Importa a pagina publica de clientes"
publish_page "Contas" "$repo_root/mediawiki/contas.wiki" "Importa a pagina publica de contas"
publish_page "Filters" "$repo_root/mediawiki/filters.wiki" "Importa a pagina publica de filtros"
publish_page "Fornecedores" "$repo_root/mediawiki/fornecedores.wiki" "Importa a pagina publica de fornecedores"
publish_page "Links" "$repo_root/mediawiki/links.wiki" "Importa a pagina publica de links"
publish_page "Pedidos" "$repo_root/mediawiki/pedidos.wiki" "Importa a pagina publica de pedidos"
publish_page "Resultados" "$repo_root/mediawiki/resultados.wiki" "Importa a pagina publica de resultados"
publish_page "Project/Admin" "$repo_root/mediawiki/project/admin.wiki" "Publica indice de ajuda do Admin"
publish_page "Project/CRM" "$repo_root/mediawiki/project/crm.wiki" "Publica indice de ajuda do CRM"
publish_page "Project/CRM/Clientes" "$repo_root/mediawiki/project/crm-clientes.wiki" "Publica indice de ajuda de clientes do CRM"
publish_page "Project/CRM/Comissões" "$repo_root/mediawiki/project/crm-comissoes.wiki" "Publica indice de comissoes do CRM"
publish_page "Project/CRM/Contratos" "$repo_root/mediawiki/project/crm-contratos.wiki" "Publica indice de contratos do CRM"
publish_page "Project/CRM/Conversas" "$repo_root/mediawiki/project/crm-conversas.wiki" "Publica indice de conversas do CRM"
publish_page "Project/CRM/Oportunidades" "$repo_root/mediawiki/project/crm-oportunidades.wiki" "Publica indice de oportunidades do CRM"
publish_page "Project/CRM/Propostas" "$repo_root/mediawiki/project/crm-propostas.wiki" "Publica indice de propostas do CRM"
publish_page "Project/CRM - Edição de endereço de cliente" "$repo_root/mediawiki/project/crm-edicao-endereco-cliente.wiki" "Refaz pagina CRM como passo a passo de ajuda"
publish_page "Project/CRM - Editar contato de cliente" "$repo_root/mediawiki/project/crm-editar-contato-cliente.wiki" "Adiciona passo a passo de editar contato de cliente"
publish_page "Project/Delivery" "$repo_root/mediawiki/project/delivery.wiki" "Publica indice de ajuda do Delivery"
publish_page "Project/Manager" "$repo_root/mediawiki/project/manager.wiki" "Publica indice de ajuda do Manager"
publish_page "Project/POS" "$repo_root/mediawiki/project/pos.wiki" "Publica indice de ajuda do POS"
publish_page "Project/PPC" "$repo_root/mediawiki/project/ppc.wiki" "Publica indice de ajuda do PPC"
publish_page "Project/Produtos - Busca em grupos de produtos" "$repo_root/mediawiki/project/produtos-busca-grupos-produtos.wiki" "Documenta melhoria de produtos para cliente final"
publish_page "Project/Service" "$repo_root/mediawiki/project/service.wiki" "Publica indice de ajuda do Service"
publish_page "Project/Shop" "$repo_root/mediawiki/project/shop.wiki" "Publica indice de ajuda do Shop"
publish_page "MediaWiki:Common.css" "$repo_root/mediawiki/system/common.css.wiki" "Aplica o tema corporativo global"
publish_page "MediaWiki:Sidebar" "$repo_root/mediawiki/system/sidebar.wiki" "Simplifica a navegação lateral da wiki"
publish_page "MediaWiki:Copyright" "$repo_root/mediawiki/system/copyright.wiki" "Exibe o site institucional no rodapé"

remove_page "Project/Agents-mcp 41 - Governança de mudanças internas"
