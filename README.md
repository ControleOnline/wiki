# ControleOnline Wiki

Este repositório público mantém uma cópia sanitizada do conteúdo público de `ajuda.controleonline.com`.

## Estrutura

- `site/`: espelho público sanitizado do FTP, sem arquivos sensíveis, banco, cache, uploads ou imagens
- `mediawiki/`: fontes em wikitext para páginas criadas pela API/runtime do MediaWiki
- `.github/workflows/sync-from-ftp.yml`: sincroniza o conteúdo do FTP para o repositório
- `.github/workflows/deploy.yml`: publicação manual de `site/` no FTP, para uso controlado
- `.github/workflows/publish-mediawiki-api.yml`: publica fontes wikitext pela API do MediaWiki
- `.github/workflows/store-mediawiki-credentials.yml`: grava credenciais MediaWiki em arquivo privado no FTP, fora do diretório público

## Segredos esperados

- `FTP_HOST`
- `FTP_PORT`
- `FTP_USER`
- `FTP_PASSWORD`
- `MEDIAWIKI_USERNAME`
- `MEDIAWIKI_PASSWORD`

## Regras de segurança

- Não versionar segredos, credenciais, backups, logs ou arquivos de ambiente.
- Não versionar banco de dados, dumps, caches, uploads ou imagens do servidor.
- A sincronização do FTP remove padrões sensíveis e mídia antes de qualquer commit.
- O deploy é manual e publica apenas o diretório `site/`; não use esse fluxo para substituir uma instalação completa do MediaWiki com mídia excluída do git.
- Páginas do MediaWiki não devem ser publicadas como HTML estático. Use wikitext e publique pela API do MediaWiki/projeto.
- Credenciais MediaWiki ficam no FTP em `../.controleonline/mediawiki.env`, fora do diretório público, e nunca devem ser copiadas para `site/`, commits ou logs.
