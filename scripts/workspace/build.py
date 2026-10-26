"""Gera os dados do database-workspace.html a partir do repositório.

O HTML da raiz é a própria interface; este script só reescreve o bloco
<script id="ws-data" type="application/json"> com:
  - o catálogo do PostgreSQL (saída de introspect.sql num banco com as migrations aplicadas);
  - o conteúdo de todos os arquivos versionados de postgre/, mongo/, redis/, neo4j/ e .github/;
  - os contratos do MongoDB, o keyspace do Redis e o histórico do git.

Uso:
  # banco descartável com as migrations aplicadas (mesmas variáveis PG* do CI)
  psql -X -A -t -q -v ON_ERROR_STOP=1 -f scripts/workspace/introspect.sql > catalog.json
  python scripts/workspace/build.py --catalog catalog.json

  # ou deixe o script chamar o psql com as variáveis PG* do ambiente
  python scripts/workspace/build.py
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HTML = ROOT / "database-workspace.html"
INTROSPECT = Path(__file__).with_name("introspect.sql")

TEXT_EXT = {".py", ".sql", ".sh", ".js", ".json", ".md", ".redis", ".conf", ".yml", ".yaml", ".txt", ".ipynb", ".example", ".cypher"}
SCOPES = ("postgre/", "mongo/", "redis/", "neo4j/", "scripts/", ".github/", "README.md", ".env.example")
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".svg", ".webp"}

START = '<script id="ws-data" type="application/json">'
END = "</script>"


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True).stdout


def load_catalog(path):
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    out = subprocess.run(["psql", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", "-f", str(INTROSPECT)],
                         capture_output=True, text=True, encoding="utf-8", check=True).stdout
    return json.loads(out)


def notebook_code(raw):
    nb = json.loads(raw)
    cells = []
    for cell in nb.get("cells", []):
        src = "".join(cell.get("source", []))
        if cell.get("cell_type") == "markdown":
            cells.append("\n".join("# " + line for line in src.splitlines()))
        elif cell.get("cell_type") == "code":
            cells.append(src)
    return "\n\n".join(cells)


def collect_files():
    files, images = [], []
    for path in git("ls-files").splitlines():
        if not path.startswith(SCOPES):
            continue
        p = ROOT / path
        ext = p.suffix.lower() if p.suffix else p.name.lower()
        if ext in IMAGE_EXT:
            images.append(path)
            continue
        if ext not in TEXT_EXT and not path.endswith(".env.example"):
            continue
        raw = p.read_text(encoding="utf-8").replace("\r\n", "\n")
        lang = {".sql": "sql", ".sh": "bash", ".js": "js", ".json": "json", ".md": "md", ".redis": "redis",
                ".conf": "conf", ".yml": "yaml", ".yaml": "yaml", ".ipynb": "python", ".py": "python", ".cypher": "cypher"}.get(ext, "text")
        if ext == ".ipynb":
            raw = notebook_code(raw)
        files.append({"path": path, "lang": lang, "content": raw})
    return files, images


CREATE_RE = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:UNIQUE\s+)?(TABLE|VIEW|MATERIALIZED\s+VIEW|FUNCTION|PROCEDURE|TRIGGER|INDEX)"
    r"\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:CONCURRENTLY\s+)?(?:public\.)?\"?(\w+)\"?",
    re.IGNORECASE,
)
ADD_CONSTRAINT_RE = re.compile(r"ADD\s+CONSTRAINT\s+\"?(\w+)\"?", re.IGNORECASE)


def object_sources(files):
    """Para cada objeto: o arquivo do dicionário que o define e as migrations que o criam ou alteram."""
    sources = {}
    for f in files:
        if f["lang"] != "sql" or "/rollback/" in f["path"] or "/tests/" in f["path"] or "/docs/" in f["path"]:
            continue
        is_migration = "/migrations/" in f["path"]
        found = {m.group(2).lower() for m in CREATE_RE.finditer(f["content"])}
        found |= {m.group(1).lower() for m in ADD_CONSTRAINT_RE.finditer(f["content"])}
        for name in found:
            entry = sources.setdefault(name, {"dictionary": [], "migrations": []})
            bucket = entry["migrations"] if is_migration else entry["dictionary"]
            if f["path"] not in bucket:
                bucket.append(f["path"])
    for entry in sources.values():
        entry["migrations"].sort()
    return sources


def mongo_model(files):
    by_path = {f["path"]: f["content"] for f in files}
    collections = []
    for path, content in sorted(by_path.items()):
        m = re.match(r"mongo/schemas/(\w+)\.schema\.json$", path)
        if m:
            collections.append({"name": m.group(1), "file": path, "schema": json.loads(content)})
    indexes = []
    idx_js = by_path.get("mongo/indexes/create_indexes.js", "")
    comment = None
    for line in idx_js.splitlines():
        line = line.strip()
        if line.startswith("//"):
            comment = line.lstrip("/ ").strip()
            continue
        m = re.match(r"dbi\.(\w+)\.createIndex\((\{.*?\}),\s*(\{.*\})\);", line)
        if m:
            keys = re.findall(r"(\w+):\s*(-?1)", m.group(2))
            name = re.search(r"name:\s*'([^']+)'", m.group(3))
            indexes.append({"collection": m.group(1), "keys": [[k, int(v)] for k, v in keys],
                            "name": name.group(1) if name else None, "unique": "unique: true" in m.group(3),
                            "comment": comment})
            comment = None
    return {"collections": collections, "indexes": indexes}


def md_tables(md):
    """Tabelas markdown de um documento, como listas de linhas (cabeçalho incluso)."""
    tables, current = [], []
    for line in md.splitlines() + [""]:
        if line.strip().startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                current.append(cells)
        elif current:
            tables.append(current)
            current = []
    return tables


def redis_model(files):
    by_path = {f["path"]: f["content"] for f in files}
    keyspace = by_path.get("redis/docs/KEYSPACE.md", "")
    keys = []
    for table in md_tables(keyspace):
        if table and table[0][:2] == ["Padrão da chave", "Tipo"]:
            for row in table[1:]:
                keys.append({"pattern": row[0].strip("`"), "type": row[1], "ttl": row[2], "owner": row[3].strip("`")})
    commands = []
    for path, content in sorted(by_path.items()):
        m = re.match(r"redis/commands/([\w-]+)/([\w-]+)\.redis$", path)
        if m:
            summary = next((l.lstrip("# ").strip() for l in content.splitlines() if l.startswith("#")), "")
            touched = sorted(set(re.findall(r"(?:inventra:[\w:-]+|rt:[\w:{}<>-]+|kar:[\w:{}<>-]+)", content)))
            commands.append({"group": m.group(1), "name": m.group(2), "file": path, "summary": summary, "keys": touched})
    return {"keys": keys, "commands": commands}


def history():
    sep = "\x1f"
    out = git("log", "-n", "80", f"--pretty=format:%x1e%H{sep}%h{sep}%an{sep}%ad{sep}%s", "--date=iso-strict", "--name-status")
    commits = []
    for block in out.split("\x1e"):
        block = block.strip("\n")
        if not block:
            continue
        head, *rest = block.split("\n")
        full, short, author, date, subject = head.split(sep)
        changes = []
        for line in rest:
            parts = line.split("\t")
            if len(parts) >= 2:
                changes.append([parts[0][0], parts[-1]])
        commits.append({"hash": full, "short": short, "author": author, "date": date, "subject": subject, "files": changes})
    return commits


def remote_url():
    try:
        url = git("remote", "get-url", "origin").strip()
    except subprocess.CalledProcessError:
        return None
    url = re.sub(r"^git@github\.com:", "https://github.com/", url)
    return re.sub(r"\.git$", "", url)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", help="JSON gerado por introspect.sql (sem ele, chama o psql com as variáveis PG*)")
    args = ap.parse_args()

    catalog = load_catalog(args.catalog)
    files, images = collect_files()
    data = {
        "repo": remote_url(),
        "branch": git("rev-parse", "--abbrev-ref", "HEAD").strip(),
        "commit": git("rev-parse", "--short", "HEAD").strip(),
        "postgres": catalog,
        "sources": object_sources(files),
        "mongo": mongo_model(files),
        "redis": redis_model(files),
        "files": files,
        "images": images,
        "history": history(),
    }

    # "<" vira <: nenhum "</script>" ou "<!--" dos arquivos fecha o bloco de dados
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    html = HTML.read_text(encoding="utf-8")
    start = html.index(START) + len(START)
    end = html.index(END, start)
    HTML.write_text(html[:start] + payload + html[end:], encoding="utf-8", newline="\n")
    print(f"{HTML.name}: {len(files)} arquivos, {len(catalog['tables'])} tabelas, "
          f"{len(catalog['views'])} views, {len(catalog['routines'])} rotinas, {len(payload) // 1024} KB de dados")


if __name__ == "__main__":
    sys.exit(main())
