#!/usr/bin/env python3
import json
import os
import secrets
import posixpath
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
API_URL = "https://ajuda.controleonline.com"

PAGES = [
    {
        "title": "Project",
        "file": REPO_ROOT / "mediawiki" / "Project.wiki",
        "summary": "Atualiza indice publico de tarefas documentadas",
    },
    {
        "title": "Project/Agents-mcp 41 - Governança de mudanças internas",
        "file": REPO_ROOT
        / "mediawiki"
        / "project"
        / "agents-mcp-41-governanca-de-mudancas-internas.wiki",
        "summary": "Documenta tarefa agents-mcp 41 para cliente final",
    },
]


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"{name} is required")
    return value


def build_lftp_script(commands: str) -> str:
    return (
        "set cmd:fail-exit true\n"
        "set net:max-retries 2\n"
        "set net:timeout 20\n"
        "set ftp:ssl-allow true\n"
        "set ssl:verify-certificate false\n"
        f"{commands}\n"
        "bye\n"
    )


def run_lftp(commands: str) -> None:
    host = require_env("FTP_HOST")
    port = require_env("FTP_PORT")
    user = require_env("FTP_USER")
    password = require_env("FTP_PASSWORD")
    subprocess.run(
        ["lftp", "-u", f"{user},{password}", "-p", port, host],
        input=build_lftp_script(commands),
        text=True,
        check=True,
    )


def run_lftp_capture(commands: str) -> str:
    host = require_env("FTP_HOST")
    port = require_env("FTP_PORT")
    user = require_env("FTP_USER")
    password = require_env("FTP_PASSWORD")
    result = subprocess.run(
        ["lftp", "-u", f"{user},{password}", "-p", port, host],
        input=build_lftp_script(commands),
        text=True,
        check=True,
        capture_output=True,
    )
    return result.stdout


def detect_mediawiki_dir() -> str:
    output = run_lftp_capture("find / -name api.php")
    candidates = [
        line.strip()
        for line in output.splitlines()
        if line.strip().endswith("/api.php")
    ]
    if not candidates:
        raise SystemExit("MediaWiki api.php was not found in FTP")
    return posixpath.dirname(candidates[0])


def build_payload() -> list[dict[str, str]]:
    pages = []
    for page in PAGES:
        source = page["file"]
        if not source.exists():
            raise SystemExit(f"missing page source: {source}")
        pages.append(
            {
                "title": page["title"],
                "text": source.read_text(encoding="utf-8"),
                "summary": page["summary"],
            }
        )
    return pages


def build_php(secret: str, pages: list[dict[str, str]]) -> str:
    pages_json = json.dumps(pages, ensure_ascii=False)
    secret_json = json.dumps(secret)
    return f"""<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
$expectedKey = {secret_json};
$providedKey = $_GET['key'] ?? '';
if (!is_string($providedKey) || !hash_equals($expectedKey, $providedKey)) {{
    http_response_code(404);
    echo json_encode(['ok' => false]);
    exit;
}}

require_once __DIR__ . '/includes/WebStart.php';

$pages = json_decode({json.dumps(pages_json)}, true, 512, JSON_THROW_ON_ERROR);
$services = MediaWiki\\MediaWikiServices::getInstance();
$user = User::newSystemUser('CodexAutomation', ['steal' => true]);
$saved = [];

foreach ($pages as $page) {{
    $title = Title::newFromText($page['title']);
    if (!$title) {{
        throw new RuntimeException('Invalid title');
    }}

    $content = ContentHandler::makeContent($page['text'], $title);
    $wikiPage = method_exists($services, 'getWikiPageFactory')
        ? $services->getWikiPageFactory()->newFromTitle($title)
        : WikiPage::factory($title);

    $updater = $wikiPage->newPageUpdater($user);
    $updater->setContent(SlotRecord::MAIN, $content);
    $revision = $updater->saveRevision(
        CommentStoreComment::newUnsavedComment($page['summary']),
        EDIT_INTERNAL | EDIT_AUTOSUMMARY
    );

    if (!$revision) {{
        throw new RuntimeException('Revision was not saved');
    }}

    $saved[] = [
        'title' => $title->getPrefixedText(),
        'revision' => $revision->getId(),
    ];
}}

echo json_encode(['ok' => true, 'saved' => $saved], JSON_UNESCAPED_UNICODE);
"""


def main() -> None:
    pages = build_payload()
    secret = secrets.token_urlsafe(32)
    remote_name = f"codex-publish-{secrets.token_hex(8)}.php"
    mediawiki_dir = detect_mediawiki_dir()
    remote_path = posixpath.join(mediawiki_dir, remote_name)

    with tempfile.TemporaryDirectory() as temporary_dir:
        local_script = Path(temporary_dir) / remote_name
        local_script.write_text(build_php(secret, pages), encoding="utf-8")
        try:
            run_lftp(f"put {local_script} -o {remote_path}")
            with urllib.request.urlopen(
                f"{API_URL}/{remote_name}?key={secret}",
                timeout=60,
            ) as response:
                body = response.read().decode("utf-8")
            result = json.loads(body)
            if not result.get("ok"):
                raise SystemExit("MediaWiki publisher did not return ok")
            for saved in result.get("saved", []):
                print(f"saved {saved['title']} rev {saved['revision']}")
        finally:
            run_lftp(f"rm -f {remote_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"publish failed: {exc}", file=sys.stderr)
        raise
