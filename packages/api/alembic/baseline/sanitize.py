"""Sanitize a `pg_dump --schema-only` dump from Supabase prod for local replay.

The raw `pg_dump` output contains:
- Postgres role/permission noise: `SET`, `ALTER ... OWNER TO`, `GRANT`, `REVOKE`,
  `ALTER DEFAULT PRIVILEGES`. Strip — they assume Supabase's role layout.
- Supabase-managed cross-schema references: `auth.users` (FK target),
  `auth.uid()` (in RLS policies), `extensions.net.http_post()` (in function
  bodies). Vanilla Postgres has none of these schemas. Strip RLS entirely;
  drop the one auth.users FK; drop the one Supabase-webhook function.
- RLS policies (`ENABLE ROW LEVEL SECURITY`, `CREATE POLICY`). Enforced by
  Supabase's `authenticated` role, not by the app's `postgres` connection.
  Stripping has no effect on local dev or test behavior.

The sanitized output is committed as `prod-schema-2026-04-30.sql` and is the
input to `00000_baseline.py`. It must load cleanly into vanilla Postgres 15.

Usage:
    python sanitize.py prod-schema-raw.sql > prod-schema-2026-04-30.sql
"""
from __future__ import annotations

import re
import sys
from collections.abc import Iterable, Iterator


def _is_strip_line(line: str) -> bool:
    """Single-line strip rules — match start of line."""
    stripped = line.lstrip()
    if stripped.startswith(("SET ", "REVOKE ", "GRANT ")):
        return True
    if stripped.startswith("ALTER DEFAULT PRIVILEGES "):
        return True
    if re.match(r'ALTER (TABLE|FUNCTION|SCHEMA|SEQUENCE) "?\w+', stripped) and " OWNER TO " in line:
        return True
    if re.match(r'COMMENT ON SCHEMA "public"', stripped):
        return True
    if re.match(r'ALTER TABLE [^;]*ENABLE ROW LEVEL SECURITY', stripped):
        return True
    if stripped.startswith("CREATE POLICY "):
        return True
    # pg_dump emits `SELECT pg_catalog.set_config('search_path', '', false);`
    # near the top. Strip it — empty search_path breaks alembic's bookkeeping
    # (which references `alembic_version` unqualified).
    if "pg_catalog.set_config(" in stripped:
        return True
    return False


def _strip_multiline_blocks(lines: list[str]) -> Iterator[str]:
    """Drop two specific multi-line blocks that reference Supabase-only schemas:

    - The `handle_new_user_notion_sync` function (calls `extensions.net.http_post`).
    - The `nps_responses_user_id_fkey` constraint (FK to `auth.users`).
    """
    i = 0
    while i < len(lines):
        line = lines[i]

        # Drop the entire CREATE [OR REPLACE] FUNCTION ... handle_new_user_notion_sync ... $$; block.
        # Newer pg_dump versions emit `CREATE FUNCTION` rather than `CREATE OR REPLACE FUNCTION`.
        if re.search(r"\bCREATE (OR REPLACE )?FUNCTION\b", line) and "handle_new_user_notion_sync" in line:
            # Skip until the closing `$$;`
            while i < len(lines) and not lines[i].rstrip().endswith("$$;"):
                i += 1
            i += 1  # skip the $$; line itself
            # Also skip the trailing ALTER FUNCTION ... OWNER TO ... line if present
            while i < len(lines) and lines[i].strip() == "":
                i += 1
            if i < len(lines) and "handle_new_user_notion_sync" in lines[i] and "OWNER TO" in lines[i]:
                i += 1
            continue

        # Drop the ALTER TABLE ONLY ... ADD CONSTRAINT nps_responses_user_id_fkey FOREIGN KEY ... REFERENCES auth.users block.
        # Match both quoted (`"auth"."users"`) and unquoted (`auth.users`) forms — newer pg_dump emits the latter.
        if re.search(r'REFERENCES\s+"?auth"?\."?users"?', line):
            # Walk backward to find the start of the ALTER TABLE statement (cheap: it's on a recent prior line).
            # Then walk forward until the terminating `;`.
            # In this dump the ALTER TABLE ONLY is 1 line above, and the ADD CONSTRAINT is the line before this one.
            # Easier: emit a comment marker, skip the full statement (current + walk back to "ALTER TABLE ONLY").
            # We yielded the prior lines already, so we need to UN-yield them. Instead: capture lookbehind.
            # Simpler: at the ALTER TABLE ONLY line, peek ahead for the auth.users marker.
            pass  # handled in pre-pass below

        yield line
        i += 1


def _drop_auth_users_fk(lines: list[str]) -> list[str]:
    """Remove multi-line `ALTER TABLE ONLY ...` blocks that target Supabase-only
    objects or alembic's own bookkeeping table:

    - FK to `auth.users` (Supabase-managed schema, absent locally).
    - Any constraint on `alembic_version` (alembic creates that table itself
      and adds its own PK; replaying it from the dump causes a duplicate-PK
      error).
    """
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.lstrip().startswith("ALTER TABLE ONLY"):
            j = i
            block: list[str] = []
            while j < len(lines):
                block.append(lines[j])
                if lines[j].rstrip().endswith(";"):
                    break
                j += 1
            block_text = "".join(block)
            if re.search(r'REFERENCES\s+"?auth"?\."?users"?', block_text):
                i = j + 1
                continue
            if '"public"."alembic_version"' in block_text or '"alembic_version"' in block_text:
                i = j + 1
                continue
            out.extend(block)
            i = j + 1
            continue
        out.append(line)
        i += 1
    return out


def _drop_alembic_version_table(lines: list[str]) -> list[str]:
    """Strip the `CREATE TABLE ... alembic_version (...)` block.

    Alembic creates this table itself with its own PK on `version_num`. Letting
    the dump recreate it causes the subsequent ADD CONSTRAINT on the same
    column to fail with `multiple primary keys`.
    """
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if "CREATE TABLE" in line and "alembic_version" in line:
            while i < len(lines) and not lines[i].rstrip().endswith(";"):
                i += 1
            i += 1
            continue
        out.append(line)
        i += 1
    return out


def _drop_orphan_section_header(lines: list[str], object_name: str) -> list[str]:
    """Drop the 3-line `--\\n-- Name: <object_name>...; Type: ...; ...\\n--\\n` block
    that pg_dump emits before each object. Use after stripping the object body to
    avoid leaving an orphan comment header behind.
    """
    out: list[str] = []
    i = 0
    while i < len(lines):
        if (
            i + 2 < len(lines)
            and lines[i].strip() == "--"
            and object_name in lines[i + 1]
            and lines[i + 1].lstrip().startswith("-- Name:")
            and lines[i + 2].strip() == "--"
        ):
            i += 3
            continue
        out.append(lines[i])
        i += 1
    return out


def sanitize(raw: str) -> str:
    lines = raw.splitlines(keepends=True)
    lines = _drop_auth_users_fk(lines)
    lines = _drop_alembic_version_table(lines)
    lines = _drop_orphan_section_header(lines, "handle_new_user_notion_sync")

    out: list[str] = []
    out.append("-- Sanitized prod schema snapshot — see sanitize.py for what was stripped.\n")
    out.append("-- Generated by packages/api/alembic/baseline/sanitize.py\n")
    out.append("\n")
    # Supabase puts uuid-ossp / pg_trgm in the `extensions` schema. The dump
    # references e.g. `extensions.uuid_generate_v4()`. Mirror that layout
    # locally so the dump applies verbatim.
    out.append("CREATE SCHEMA IF NOT EXISTS extensions;\n")
    out.append('CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;\n')
    out.append("CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;\n")
    out.append("\n")

    skip_block = False
    for line in _strip_multiline_blocks(lines):
        if skip_block:
            if line.rstrip().endswith("$$;"):
                skip_block = False
            continue

        if _is_strip_line(line):
            continue

        # Collapse runs of blank lines.
        if line.strip() == "" and out and out[-1].strip() == "":
            continue

        out.append(line)

    return "".join(out)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: sanitize.py <raw.sql>", file=sys.stderr)
        return 2
    raw = open(argv[1]).read()
    sys.stdout.write(sanitize(raw))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
