#!/usr/bin/env python3
"""Validate the shared skills repository before merge / release.

Checks every skills/<name>/SKILL.md against the Agent Skills specification
(agentskills.io) plus CIM team rules, and checks VERSION / CHANGELOG / tag.

Usage:
    python tools/lint_skills.py                      # check everything (MR / main pipeline)
    python tools/lint_skills.py --tag v1.2.0         # also check the release tag matches VERSION
    python tools/lint_skills.py --index skills-index.json   # write a skill catalogue

Exit code 1 if any ERROR was found. Standard library only (PyYAML is used if installed).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
SECRET_PATTERNS = [
    (re.compile(r"glpat-[0-9A-Za-z_\-]{20,}"), "GitLab personal access token"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS access key"),
    (re.compile(r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|token)\s*[:=]\s*['\"]?[^\s'\"<>{}]{6,}"), "credential-like assignment"),
    (re.compile(r"(?i)(Data Source|Server)=[^;]+;.*(Password|Pwd)=[^;]+"), "connection string with password"),
]
PRIVATE_IP_RE = re.compile(r"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b")
TEXT_SUFFIXES = {".md", ".txt", ".ps1", ".py", ".sh", ".cmd", ".bat", ".json", ".yml", ".yaml", ".xml", ".cs", ".sql", ".config"}


class Report:
    def __init__(self) -> None:
        self.errors = 0
        self.warnings = 0

    def error(self, where: str, msg: str) -> None:
        self.errors += 1
        print(f"ERROR   {where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings += 1
        print(f"WARNING {where}: {msg}")

    def info(self, where: str, msg: str) -> None:
        print(f"INFO    {where}: {msg}")


def split_frontmatter(text: str) -> tuple[str | None, str]:
    text = text.lstrip("﻿")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), "\n".join(lines[i + 1:])
    return None, text


def _unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        return v[1:-1]
    return v


def parse_yaml_subset(src: str) -> dict:
    """Small YAML subset parser: `key: value`, block scalars (| and >), one nested map level."""
    try:
        import yaml  # type: ignore
        data = yaml.safe_load(src)
        return data if isinstance(data, dict) else {}
    except ImportError:
        pass
    result: dict = {}
    lines = src.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not m:
            raise ValueError(f"cannot parse line: {line!r}")
        key, rest = m.group(1), m.group(2).strip()
        i += 1
        if rest in ("|", ">", "|-", ">-", "|+", ">+"):
            block = []
            while i < len(lines) and (lines[i].startswith(" ") or not lines[i].strip()):
                block.append(lines[i].strip())
                i += 1
            result[key] = ("\n" if rest.startswith("|") else " ").join(b for b in block if b).strip()
        elif rest == "":
            nested: dict = {}
            while i < len(lines) and (lines[i].startswith(" ") or not lines[i].strip()):
                if lines[i].strip():
                    nm = re.match(r"^\s+([A-Za-z0-9_.-]+):\s*(.*)$", lines[i])
                    if not nm:
                        raise ValueError(f"cannot parse nested line: {lines[i]!r}")
                    nested[nm.group(1)] = _unquote(nm.group(2))
                i += 1
            result[key] = nested
        else:
            result[key] = _unquote(rest)
    return result


def check_skill(skill_dir: Path, prefix: str, max_lines: int, rep: Report) -> dict | None:
    where = f"skills/{skill_dir.name}"
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        rep.error(where, "missing SKILL.md")
        return None
    text = skill_md.read_text(encoding="utf-8")
    fm_src, body = split_frontmatter(text)
    if fm_src is None:
        rep.error(where, "SKILL.md must start with YAML frontmatter between '---' lines")
        return None
    try:
        fm = parse_yaml_subset(fm_src)
    except Exception as exc:  # noqa: BLE001
        rep.error(where, f"frontmatter is not valid YAML: {exc}")
        return None

    allowed = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
    for key in fm:
        if key not in allowed:
            rep.warn(where, f"unknown frontmatter field '{key}' (spec fields: {', '.join(sorted(allowed))})")

    name = str(fm.get("name", "") or "")
    if not name:
        rep.error(where, "frontmatter 'name' is required")
    else:
        if len(name) > 64:
            rep.error(where, f"name is {len(name)} chars (max 64)")
        if not NAME_RE.match(name):
            rep.error(where, f"name '{name}' must be lowercase a-z, 0-9 and single hyphens, not starting/ending with '-'")
        if name != skill_dir.name:
            rep.error(where, f"name '{name}' must match the folder name '{skill_dir.name}'")
        if prefix and not name.startswith(prefix):
            rep.error(where, f"team rule: shared skill names must start with '{prefix}'")

    desc = str(fm.get("description", "") or "").strip()
    if not desc:
        rep.error(where, "frontmatter 'description' is required")
    elif len(desc) > 1024:
        rep.error(where, f"description is {len(desc)} chars (max 1024)")
    elif len(desc) < 40:
        rep.warn(where, "description is very short; say what the skill does AND when to use it, with keywords")

    comp = fm.get("compatibility")
    if comp is not None and not (1 <= len(str(comp)) <= 500):
        rep.error(where, "compatibility must be 1-500 chars")

    meta = fm.get("metadata")
    if meta is not None:
        if not isinstance(meta, dict):
            rep.error(where, "metadata must be a key: value map")
            meta = {}
        else:
            for k, v in meta.items():
                if not isinstance(v, str):
                    rep.error(where, f"metadata.{k} must be a string (quote it, e.g. \"1.0\")")
    else:
        meta = {}
    if not meta.get("owner"):
        rep.warn(where, "team rule: add metadata.owner (who maintains this skill)")

    n_lines = len(text.splitlines())
    if n_lines > max_lines:
        rep.warn(where, f"SKILL.md has {n_lines} lines; keep it under {max_lines} and move details to references/")
    if not body.strip():
        rep.error(where, "SKILL.md has no instructions after the frontmatter")

    for target in LINK_RE.findall(body):
        if re.match(r"^[a-z]+:", target) or target.startswith("#"):
            continue
        rel = target.split("#", 1)[0]
        if rel and not (skill_dir / rel).exists():
            rep.error(where, f"broken relative link '{target}'")

    for f in sorted(skill_dir.rglob("*")):
        if not f.is_file():
            continue
        rel = f.relative_to(skill_dir).as_posix()
        if f.suffix.lower() in TEXT_SUFFIXES or f.name == "SKILL.md":
            try:
                content = f.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                rep.error(f"{where}/{rel}", "text file is not UTF-8")
                continue
            for pattern, label in SECRET_PATTERNS:
                if pattern.search(content):
                    rep.error(f"{where}/{rel}", f"possible secret ({label}) - never put credentials in skills")
            if PRIVATE_IP_RE.search(content):
                rep.warn(f"{where}/{rel}", "contains an internal IP address; prefer host names or config")
        if rel.startswith("scripts/"):
            rep.info(f"{where}/{rel}", "script file - the agent may execute it; reviewer must check it")

    return {
        "name": name,
        "description": desc,
        "owner": meta.get("owner", ""),
        "files": sorted(p.relative_to(skill_dir).as_posix() for p in skill_dir.rglob("*") if p.is_file()),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="repository root (default: current folder)")
    ap.add_argument("--prefix", default="cim-", help="required skill name prefix ('' to disable)")
    ap.add_argument("--max-lines", type=int, default=500)
    ap.add_argument("--tag", default="", help="release tag being built, e.g. v1.2.0")
    ap.add_argument("--index", default="", help="write a JSON catalogue of the skills to this path")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    rep = Report()
    skills_root = root / "skills"
    if not skills_root.is_dir():
        rep.error("skills", "folder not found")
        return 1

    catalogue = []
    names_lower: dict[str, str] = {}
    for d in sorted(p for p in skills_root.iterdir() if p.is_dir()):
        if d.name.startswith("."):
            continue
        low = d.name.lower()
        if low in names_lower:
            rep.error(f"skills/{d.name}", f"duplicates '{names_lower[low]}' (case-insensitive)")
        names_lower[low] = d.name
        info = check_skill(d, args.prefix, args.max_lines, rep)
        if info:
            catalogue.append(info)
    for f in skills_root.iterdir():
        if f.is_file():
            rep.warn(f"skills/{f.name}", "loose file in skills/ - every skill must be its own folder")

    version_file = root / "VERSION"
    version = version_file.read_text(encoding="utf-8").strip() if version_file.is_file() else ""
    if not SEMVER_RE.match(version):
        rep.error("VERSION", f"must contain a semantic version like 1.2.0 (found '{version}')")
    changelog = root / "CHANGELOG.md"
    if not changelog.is_file():
        rep.error("CHANGELOG.md", "missing")
    elif version and f"## [{version}]" not in changelog.read_text(encoding="utf-8"):
        rep.error("CHANGELOG.md", f"no '## [{version}]' section for the current VERSION")
    if args.tag and args.tag != f"v{version}":
        rep.error("tag", f"tag '{args.tag}' does not match VERSION 'v{version}'")

    if args.index:
        Path(args.index).write_text(
            json.dumps({"version": version, "skills": catalogue}, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Wrote {args.index} ({len(catalogue)} skills)")

    print(f"\n{len(catalogue)} skill(s) checked: {rep.errors} error(s), {rep.warnings} warning(s)")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
