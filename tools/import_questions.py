#!/usr/bin/env python3
"""
Imports question-bank JSON files into Postgres (idempotent).

    python3 tools/import_questions.py supabase/seed/questions/*.json   # prints SQL
    python3 tools/import_questions.py --apply supabase/seed/questions/*.json

* Validates every question (4 distinct options, correct index in range,
  known subject/topic codes are resolved in SQL).
* Creates missing `sources` rows on the fly (kind + name is the key), so every
  question keeps its provenance.
* Duplicates are skipped by the database's `stem_hash` unique constraint, so
  re-running the import (or importing overlapping banks) is safe.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VALID_KINDS = {"previous_exam", "book", "newspaper", "website", "ai_generated", "curated"}


def lit(value):
    """SQL literal using dollar quoting (safe for Bangla text and quotes)."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    tag = "$q$"
    while tag in text:
        tag = tag[:-1] + "x$"
    return f"{tag}{text}{tag}"


def validate(q, where):
    errors = []
    for key in ("subject", "stem", "options", "correct_index"):
        if key not in q:
            errors.append(f"missing {key}")
    opts = q.get("options") or []
    if not (2 <= len(opts) <= 5):
        errors.append("options must have 2–5 items")
    if len(set(map(str, opts))) != len(opts):
        errors.append("options must be distinct")
    ci = q.get("correct_index")
    if not isinstance(ci, int) or not (0 <= ci < len(opts)):
        errors.append("correct_index out of range")
    if q.get("source_kind", "curated") not in VALID_KINDS:
        errors.append(f"bad source_kind {q.get('source_kind')}")
    if errors:
        raise SystemExit(f"{where}: " + "; ".join(errors))


def build_sql(files):
    out = ["begin;", "create temp table _import (doc jsonb) on commit drop;"]
    total = 0
    for f in files:
        data = json.loads(Path(f).read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise SystemExit(f"{f}: expected a JSON array")
        for i, q in enumerate(data):
            validate(q, f"{f}[{i}]")
            out.append(f"insert into _import values ({lit(json.dumps(q, ensure_ascii=False))}::jsonb);")
            total += 1
    out.append("""
insert into public.sources (kind, name, year, exam_type)
select distinct (doc->>'source_kind')::public.source_kind,
       coalesce(doc->>'source_name', 'প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক'),
       nullif(doc->>'source_year', '')::int,
       case when doc->>'source_kind' = 'previous_exam' then coalesce(doc->'exam_tags'->>0, 'bcs') end
  from _import
on conflict (kind, name) do nothing;

with ins as (
  insert into public.questions
    (subject_id, topic_id, stem, options, correct_index, explanation, difficulty, language,
     source_id, source_ref, source_url, exam_tags, year, status, review_status)
  select s.id, t.id, i.doc->>'stem', i.doc->'options', (i.doc->>'correct_index')::smallint,
         i.doc->>'explanation', coalesce((i.doc->>'difficulty')::smallint, 2), coalesce(i.doc->>'language', 'bn'),
         src.id, i.doc->>'source_ref', i.doc->>'source_url',
         coalesce((select array_agg(x) from jsonb_array_elements_text(i.doc->'exam_tags') x), '{}'),
         nullif(i.doc->>'source_year', '')::int, 'published', 'unverified'
    from _import i
    join public.subjects s on s.code = i.doc->>'subject'
    left join public.topics t on t.code = i.doc->>'topic'
    left join public.sources src on src.kind = coalesce(i.doc->>'source_kind', 'curated')::public.source_kind
                                and src.name = coalesce(i.doc->>'source_name', 'প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক')
  on conflict (stem_hash) do nothing
  returning 1
)
select count(*) as inserted from ins;
""")
    out.append("select count(*) as unknown_subjects from _import i where not exists (select 1 from public.subjects s where s.code = i.doc->>'subject');")
    out.append("commit;")
    return "\n".join(out), total


def main():
    args = sys.argv[1:]
    apply = "--apply" in args
    files = [a for a in args if not a.startswith("--")]
    if not files:
        files = sorted(str(p) for p in (ROOT / "supabase/seed/questions").glob("*.json"))
    sql, total = build_sql(files)
    if not apply:
        print(sql)
        return
    print(f"importing {total} questions from {len(files)} files…")
    tmp = ROOT / "supabase/.temp"
    tmp.mkdir(parents=True, exist_ok=True)
    path = tmp / "import_questions.sql"
    path.write_text(sql, encoding="utf-8")
    subprocess.run([str(ROOT / "tools/db.sh"), "file", str(path)], check=True)
    path.unlink()


if __name__ == "__main__":
    main()
