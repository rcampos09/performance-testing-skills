#!/usr/bin/env python3
"""
Structural validator for performance-testing-skills.
Checks every skill under skills/<name>/SKILL.md against the Agent Skills spec.
Exits 0 on success, 1 if any check fails.
"""

import json
import re
import sys
from pathlib import Path

import yaml

SKILLS_DIR = Path("skills")
MAX_SKILL_MD_LINES = 500
MAX_NAME_LEN = 64
MAX_DESC_LEN = 1024
NAME_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")

errors = []
warnings = []


def error(skill: str, msg: str):
    errors.append(f"  ❌ [{skill}] {msg}")


def warn(skill: str, msg: str):
    warnings.append(f"  ⚠️  [{skill}] {msg}")


def parse_frontmatter(text: str):
    """Extract YAML frontmatter between --- delimiters."""
    if not text.startswith("---"):
        return None, text
    end = text.find("\n---", 3)
    if end == -1:
        return None, text
    raw_yaml = text[3:end].strip()
    body = text[end + 4:]
    try:
        return yaml.safe_load(raw_yaml), body
    except yaml.YAMLError as e:
        return {"__parse_error__": str(e)}, ""


def validate_skill(skill_dir: Path):
    skill_name = skill_dir.name
    skill_md = skill_dir / "SKILL.md"

    # ── SKILL.md must exist ───────────────────────────────────────────────────
    if not skill_md.exists():
        error(skill_name, "SKILL.md not found")
        return

    content = skill_md.read_text(encoding="utf-8")
    lines = content.splitlines()

    # ── Line count ────────────────────────────────────────────────────────────
    if len(lines) > MAX_SKILL_MD_LINES:
        warn(
            skill_name,
            f"SKILL.md has {len(lines)} lines (max {MAX_SKILL_MD_LINES}). "
            "Move reference material to references/",
        )

    # ── Frontmatter ───────────────────────────────────────────────────────────
    fm, _ = parse_frontmatter(content)

    if fm is None:
        error(skill_name, "Missing YAML frontmatter (--- delimiters not found)")
        return

    if "__parse_error__" in fm:
        error(skill_name, f"Invalid YAML in frontmatter: {fm['__parse_error__']}")
        return

    # name
    name = fm.get("name")
    if not name:
        error(skill_name, "frontmatter missing required field: name")
    else:
        if name != skill_name:
            error(
                skill_name,
                f"frontmatter 'name' ({name!r}) does not match directory name ({skill_name!r})",
            )
        if len(name) > MAX_NAME_LEN:
            error(skill_name, f"'name' exceeds {MAX_NAME_LEN} chars ({len(name)})")
        if not NAME_RE.match(name):
            error(
                skill_name,
                f"'name' ({name!r}) must be lowercase letters, digits, and single hyphens only — "
                "no leading/trailing hyphens, no consecutive hyphens",
            )

    # description
    desc = fm.get("description")
    if not desc:
        error(skill_name, "frontmatter missing required field: description")
    else:
        desc_str = str(desc).strip()
        if len(desc_str) > MAX_DESC_LEN:
            error(
                skill_name,
                f"'description' exceeds {MAX_DESC_LEN} chars ({len(desc_str)})",
            )
        if len(desc_str) < 50:
            warn(skill_name, "'description' is very short — include WHAT it does AND WHEN to trigger")

    # license (recommended, not required)
    if not fm.get("license"):
        warn(skill_name, "frontmatter missing recommended field: license")

    # ── evals/evals.json (optional but validated if present) ─────────────────
    evals_file = skill_dir / "evals" / "evals.json"
    if evals_file.exists():
        validate_evals(skill_name, evals_file)


def validate_evals(skill_name: str, evals_file: Path):
    try:
        data = json.loads(evals_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        error(skill_name, f"evals/evals.json is not valid JSON: {e}")
        return

    if not isinstance(data, dict):
        error(skill_name, "evals/evals.json must be a JSON object")
        return

    if "skill_name" not in data:
        error(skill_name, "evals/evals.json missing 'skill_name' field")

    evals = data.get("evals")
    if not isinstance(evals, list):
        error(skill_name, "evals/evals.json missing 'evals' array")
        return

    if len(evals) == 0:
        warn(skill_name, "evals/evals.json has an empty 'evals' array")

    for i, ev in enumerate(evals):
        prefix = f"evals[{i}]"
        for field in ("id", "prompt", "expected_output"):
            if field not in ev:
                error(skill_name, f"{prefix} missing required field: {field}")

        assertions = ev.get("assertions", [])
        if not isinstance(assertions, list) or len(assertions) == 0:
            warn(skill_name, f"{prefix} has no assertions — add at least one to make the eval useful")
        else:
            for j, a in enumerate(assertions):
                for field in ("name", "description"):
                    if field not in a:
                        error(skill_name, f"{prefix}.assertions[{j}] missing field: {field}")


def main():
    if not SKILLS_DIR.exists():
        print("❌ 'skills/' directory not found. Run from repo root.")
        sys.exit(1)

    skill_dirs = sorted(
        d for d in SKILLS_DIR.iterdir() if d.is_dir() and not d.name.startswith(".")
    )

    if not skill_dirs:
        print("⚠️  No skill directories found under skills/")
        sys.exit(0)

    print(f"🔍 Validating {len(skill_dirs)} skill(s)...\n")

    for skill_dir in skill_dirs:
        validate_skill(skill_dir)

    # ── Report ────────────────────────────────────────────────────────────────
    if warnings:
        print("Warnings:")
        for w in warnings:
            print(w)
        print()

    if errors:
        print("Errors:")
        for e in errors:
            print(e)
        print(f"\n💥 Validation failed — {len(errors)} error(s) found.")
        sys.exit(1)

    print(f"✅ All {len(skill_dirs)} skill(s) passed validation.")
    if warnings:
        print(f"   {len(warnings)} warning(s) — review but not blocking.")


if __name__ == "__main__":
    main()
