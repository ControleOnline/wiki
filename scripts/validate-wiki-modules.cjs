const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const gitmodulesPath = path.join(root, '.gitmodules');
const gitmodules = fs.readFileSync(gitmodulesPath, 'utf8');

const paths = [...gitmodules.matchAll(/path\s*=\s*(.+)/g)].map(match => match[1].trim());
const urls = [...gitmodules.matchAll(/url\s*=\s*(.+)/g)].map(match => match[1].trim());

const expectedPaths = ['modules/api-community', 'modules/app-community'];

if (paths.length !== expectedPaths.length) {
  throw new Error(`Expected only ${expectedPaths.length} wiki parent modules, found ${paths.length}`);
}

for (const expectedPath of expectedPaths) {
  if (!paths.includes(expectedPath)) {
    throw new Error(`Missing main wiki module path: ${expectedPath}`);
  }
}

for (const pathValue of paths) {
  if (!/^modules\/(api-community|app-community)$/.test(pathValue)) {
    throw new Error(`Main wiki must only reference parent wikis in modules/<parent>: ${pathValue}`);
  }

  if (pathValue.includes('/api/') || pathValue.includes('/app/')) {
    throw new Error(`Main wiki must not use intermediate API/app directories: ${pathValue}`);
  }
}

for (const url of urls) {
  if (!/^https:\/\/github\.com\/ControleOnline\/(api-community|app-community)\.wiki\.git$/.test(url)) {
    throw new Error(`Unexpected main wiki submodule URL: ${url}`);
  }
}

console.log('Validated main wiki parent modules.');
