# Question bank seed files

Each `*.json` file is an array of question objects imported by
`tools/import_questions.ts` (idempotent — duplicates are skipped by `stem_hash`).

```jsonc
{
  "subject": "bangla",              // subjects.code
  "topic": "bn_samas",              // topics.code (optional → subject's general topic)
  "stem": "‘নীলকণ্ঠ’ কোন সমাস?",
  "options": ["বহুব্রীহি", "কর্মধারয়", "তৎপুরুষ", "দ্বিগু"],
  "correct_index": 0,               // 0-based
  "explanation": "নীল কণ্ঠ যার — বহুব্রীহি সমাস (শিব অর্থে)।",
  "difficulty": 2,                  // 1 (easy) … 5 (hard)
  "language": "bn",                 // "bn" | "en"
  "exam_tags": ["bcs", "bank"],
  "source_kind": "curated",         // previous_exam | book | newspaper | website | curated
  "source_name": "প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক",
  "source_year": null,              // e.g. 2023 for a previous exam
  "source_ref": null                // human-readable, e.g. "৪৪তম বিসিএস প্রিলিমিনারি"
}
```

Rules: questions are attributed to a specific previous exam **only** when that
attribution is certain; everything else is labelled curated practice. No
copyrighted book text is reproduced. Time-sensitive facts (office holders,
latest statistics) belong to the daily AI pipeline, not to this seed.
