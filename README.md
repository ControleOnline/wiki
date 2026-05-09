# ControleOnline Wiki

Este repositório público espelha o conteúdo público de `ajuda.controleonline.com`.

## Estrutura

- `site/`: conteúdo público que pode ser publicado
- `.github/workflows/sync-from-ftp.yml`: sincroniza o conteúdo do FTP para o repositório
- `.github/workflows/deploy.yml`: publica `site/` no FTP quando `master` recebe alterações

## Segredos esperados

- `FTP_HOST`
- `FTP_PORT`
- `FTP_USER`
- `FTP_PASSWORD`

## Regras de segurança

- Não versionar segredos, credenciais, backups, logs ou arquivos de ambiente.
- A sincronização do FTP remove padrões sensíveis antes de qualquer commit.
- O deploy publica apenas o diretório `site/`.
