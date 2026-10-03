# Data sources and provenance

Every question in Prostuti carries **where it came from** (`sources` row,
`source_ref`, `source_url`). The app shows it on each question card.

## Question bank

| Source | Kind | What | Status |
|--------|------|------|--------|
| প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক | `curated` | 545 original MCQs across all 10 BCS preliminary subjects, written for Prostuti following the BPSC syllabus and checked twice (numeric answers re-computed programmatically) | `review_status = unverified` until an admin verifies them in **Admin → Questions** |
| প্রস্তুতি এআই · সাম্প্রতিক | `ai_generated` | daily current-affairs MCQs generated from news facts; each links to its source article | grows every day; superseded facts archive their questions |
| Previous BCS / bank papers | `previous_exam` | add via the importer with exact exam name and year | the seed attributes **no** question to a specific past exam unless certain |

**Copyright:** no text from commercial guide books is reproduced. Book titles
may appear only as references in `sources`. Real previous-year papers can be
imported with `tools/import_questions.py` (JSON format documented in
`supabase/seed/questions/README.md`). The importer is idempotent: duplicates are
skipped by a normalised stem hash.

## Syllabus

BPSC BCS Preliminary (200 marks, revised for the 50th BCS): Bangla 30, English 30,
Bangladesh affairs 25, International affairs 25, Geography/environment/disaster 10,
General science 15, Computer & ICT 15, Mathematical reasoning 20, Mental ability 15,
Ethics/values/good governance 15. Source: Prothom Alo,
*50th BCS preliminary exam syllabus published*
(https://en.prothomalo.com/youth/employment/lr0bgxb7cr).

## News (current affairs)

RSS feeds (titles, short summaries and links only; full articles are never stored):

| Outlet | Language | Feed |
|--------|----------|------|
| প্রথম আলো | bn | prothomalo.com/feed/ |
| ইত্তেফাক | bn | ittefaq.com.bd/feed/ |
| বাংলা ট্রিবিউন | bn | banglatribune.com/feed/ |
| জাগো নিউজ | bn | jagonews24.com/rss/rss.xml |
| বিবিসি বাংলা | bn | feeds.bbci.co.uk/bengali/rss.xml |
| Dhaka Tribune | en | dhakatribune.com/feed/ |
| The Daily Star | en | thedailystar.net/frontpage/rss.xml |
| The Business Standard | en | tbsnews.net/top-news/rss.xml |
| BSS | en | bssnews.net/feed |
| BBC World / BBC Science | en | feeds.bbci.co.uk |
| Al Jazeera | en | aljazeera.com/xml/rss/all.xml |
| The Guardian World | en | theguardian.com/world/rss |
| UN News | en | news.un.org/feed |

Feeds are managed in `news_sources`. Broken feeds back off automatically and
recover by themselves. Every note and generated question links back to its articles.

## Exam dates

`exam_schedules` holds approximate dates (`is_confirmed = false`) until BPSC
announces them. Seeded from Prothom Alo reports on the 51st (special) BCS and
the next general BCS circular. Admins update dates in the app, and affected
study plans re-plan automatically.
