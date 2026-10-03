-- ============================================================================
-- 0010 · Reference data
-- Syllabus: BPSC BCS preliminary (200 marks, revised for the 50th BCS):
--   Bangla 30 · English 30 · Bangladesh affairs 25 · International affairs 25
--   Geography 10 · General science 15 · Computer & ICT 15
--   Mathematical reasoning 20 · Mental ability 15 · Ethics & good governance 15
-- Topic ids: subject_id * 100 + n  (x99 = the subject's "general" topic)
-- Everything here is idempotent (upserts) so it can be re-applied safely.
-- ============================================================================

insert into public.subjects (id, code, name_bn, name_en, bcs_marks, placement_group, icon, color, sort) values
  (1,  'bangla',         'বাংলা ভাষা ও সাহিত্য',                         'Bangla Language & Literature',     30, 'bangla',  'menu_book',      '#0E7C66', 1),
  (2,  'english',        'ইংরেজি ভাষা ও সাহিত্য',                         'English Language & Literature',    30, 'english', 'translate',      '#3559E0', 2),
  (3,  'bd_affairs',     'বাংলাদেশ বিষয়াবলি',                             'Bangladesh Affairs',               25, 'gk',      'flag',           '#006A4E', 3),
  (4,  'international',  'আন্তর্জাতিক বিষয়াবলি',                          'International Affairs',            25, 'gk',      'public',         '#7A4BD6', 4),
  (5,  'geography',      'ভূগোল, পরিবেশ ও দুর্যোগ ব্যবস্থাপনা',             'Geography, Environment & Disaster', 10, 'gk',      'terrain',        '#2E8B57', 5),
  (6,  'science',        'সাধারণ বিজ্ঞান',                                 'General Science',                  15, 'gk',      'science',        '#E07A1F', 6),
  (7,  'computer',       'কম্পিউটার ও তথ্যপ্রযুক্তি',                        'Computer & ICT',                   15, 'gk',      'computer',       '#1F8FB3', 7),
  (8,  'math',           'গাণিতিক যুক্তি',                                 'Mathematical Reasoning',           20, 'math',    'calculate',      '#D9480F', 8),
  (9,  'mental_ability', 'মানসিক দক্ষতা',                                  'Mental Ability',                   15, 'math',    'psychology',     '#C2255C', 9),
  (10, 'ethics',         'নৈতিকতা, মূল্যবোধ ও সুশাসন',                       'Ethics, Values & Good Governance', 15, 'gk',      'balance',        '#5C7CFA', 10)
on conflict (id) do update set
  code = excluded.code, name_bn = excluded.name_bn, name_en = excluded.name_en, bcs_marks = excluded.bcs_marks,
  placement_group = excluded.placement_group, icon = excluded.icon, color = excluded.color, sort = excluded.sort;

insert into public.topics (id, subject_id, code, name_bn, name_en, weight, is_general, sort) values
  -- বাংলা
  (101, 1, 'bn_phonology',     'ধ্বনি, বর্ণ ও উচ্চারণ',                        'Phonology, Script & Pronunciation', 1.0, false, 1),
  (102, 1, 'bn_word',          'শব্দ ও পদ প্রকরণ',                             'Words & Parts of Speech',           1.5, false, 2),
  (103, 1, 'bn_sandhi',        'সন্ধি',                                       'Sandhi',                            1.0, false, 3),
  (104, 1, 'bn_samas',         'সমাস',                                        'Compound Words (Samas)',            1.0, false, 4),
  (105, 1, 'bn_karak',         'কারক ও বিভক্তি',                               'Case & Inflection',                 1.0, false, 5),
  (106, 1, 'bn_prokriti',      'প্রকৃতি-প্রত্যয় ও উপসর্গ',                      'Roots, Suffixes & Prefixes',        1.0, false, 6),
  (107, 1, 'bn_spelling',      'বানান ও বাক্যশুদ্ধি',                           'Spelling & Sentence Correction',    1.5, false, 7),
  (108, 1, 'bn_idioms',        'বাগধারা, প্রবাদ ও এককথায় প্রকাশ',               'Idioms, Proverbs & One-word',       1.5, false, 8),
  (109, 1, 'bn_synonyms',      'সমার্থক, বিপরীতার্থক ও পারিভাষিক শব্দ',          'Synonyms, Antonyms & Terminology',  1.5, false, 9),
  (110, 1, 'bn_lit_ancient',   'প্রাচীন ও মধ্যযুগের সাহিত্য',                     'Ancient & Medieval Literature',     2.0, false, 10),
  (111, 1, 'bn_lit_modern',    'আধুনিক যুগের সাহিত্য',                          'Modern Literature',                 2.5, false, 11),
  (112, 1, 'bn_lit_tagore_nazrul', 'রবীন্দ্রনাথ ও নজরুল',                      'Rabindranath & Nazrul',             2.0, false, 12),
  (113, 1, 'bn_lit_bangladesh','বাংলাদেশের সাহিত্য ও মুক্তিযুদ্ধ',                 'Literature of Bangladesh',          1.5, false, 13),
  (114, 1, 'bn_lit_periodicals','পত্রপত্রিকা ও ছদ্মনাম',                         'Periodicals & Pen Names',           1.0, false, 14),
  (199, 1, 'bn_general',       'বাংলা — বিবিধ',                                'Bangla — Miscellaneous',            0.5, true,  99),
  -- English
  (201, 2, 'en_parts_of_speech',   'Parts of Speech',                          'Parts of Speech',                   1.5, false, 1),
  (202, 2, 'en_tense_verb',        'Tense, Verb & Agreement',                  'Tense, Verb & Agreement',           1.5, false, 2),
  (203, 2, 'en_voice_narration',   'Voice & Narration',                        'Voice & Narration',                 1.0, false, 3),
  (204, 2, 'en_preposition_article','Preposition & Article',                   'Preposition & Article',             1.5, false, 4),
  (205, 2, 'en_correction',        'Sentence Correction & Structure',          'Sentence Correction & Structure',   1.5, false, 5),
  (206, 2, 'en_vocabulary',        'Vocabulary: Synonym & Antonym',            'Vocabulary: Synonym & Antonym',     2.0, false, 6),
  (207, 2, 'en_idioms',            'Idioms & Phrases',                         'Idioms & Phrases',                  1.5, false, 7),
  (208, 2, 'en_spelling_analogy',  'Spelling, One-word & Analogy',             'Spelling, One-word & Analogy',      1.0, false, 8),
  (209, 2, 'en_lit_early',         'Old English to Renaissance (Shakespeare)', 'Old English to Renaissance',        2.0, false, 9),
  (210, 2, 'en_lit_romantic_victorian','Romantic & Victorian Literature',      'Romantic & Victorian Literature',   2.0, false, 10),
  (211, 2, 'en_lit_modern',        'Modern & American Literature',             'Modern & American Literature',      1.5, false, 11),
  (212, 2, 'en_literary_terms',    'Literary Terms & Quotations',              'Literary Terms & Quotations',       1.0, false, 12),
  (299, 2, 'en_general',           'English — Miscellaneous',                  'English — Miscellaneous',           0.5, true,  99),
  -- বাংলাদেশ বিষয়াবলি
  (301, 3, 'bd_ancient_medieval',  'প্রাচীন ও মধ্যযুগের বাংলা',                   'Ancient & Medieval Bengal',         1.5, false, 1),
  (302, 3, 'bd_british_pakistan',  'ব্রিটিশ ও পাকিস্তান আমল',                     'British & Pakistan Period',         2.0, false, 2),
  (303, 3, 'bd_liberation_war',    'মহান মুক্তিযুদ্ধ',                             'Liberation War 1971',               2.5, false, 3),
  (304, 3, 'bd_constitution',      'বাংলাদেশের সংবিধান',                          'Constitution of Bangladesh',        2.0, false, 4),
  (305, 3, 'bd_government',        'সরকার, সংসদ ও রাজনীতি',                       'Government, Parliament & Politics', 1.5, false, 5),
  (306, 3, 'bd_economy',           'অর্থনীতি, বাজেট ও উন্নয়ন',                      'Economy, Budget & Development',     2.0, false, 6),
  (307, 3, 'bd_population_culture','জনসংখ্যা, সংস্কৃতি ও নৃগোষ্ঠী',                 'Population, Culture & Ethnic Groups',1.5, false, 7),
  (308, 3, 'bd_resources',         'কৃষি, শিল্প ও প্রাকৃতিক সম্পদ',                  'Agriculture, Industry & Resources', 1.0, false, 8),
  (309, 3, 'bd_foreign_relations', 'বাংলাদেশের পররাষ্ট্রনীতি',                     'Foreign Relations',                 1.0, false, 9),
  (310, 3, 'bd_current',           'সাম্প্রতিক বাংলাদেশ',                         'Current Affairs: Bangladesh',       2.5, false, 10),
  (399, 3, 'bd_general',           'বাংলাদেশ — বিবিধ',                            'Bangladesh — Miscellaneous',        0.5, true,  99),
  -- আন্তর্জাতিক বিষয়াবলি
  (401, 4, 'int_world_history',    'বিশ্ব ইতিহাস',                                'World History',                     1.5, false, 1),
  (402, 4, 'int_organizations',    'আন্তর্জাতিক সংস্থা ও জাতিসংঘ',                 'International Organizations & UN',  2.5, false, 2),
  (403, 4, 'int_treaties_conflicts','চুক্তি, সম্মেলন ও সংঘাত',                      'Treaties, Summits & Conflicts',     2.0, false, 3),
  (404, 4, 'int_world_economy',    'বিশ্ব অর্থনীতি ও বাণিজ্য',                      'World Economy & Trade',             1.0, false, 4),
  (405, 4, 'int_countries',        'দেশ, রাজধানী ও মুদ্রা',                         'Countries, Capitals & Currencies',  1.0, false, 5),
  (406, 4, 'int_awards_people',    'পুরস্কার ও ব্যক্তিত্ব',                          'Awards & Personalities',            1.5, false, 6),
  (407, 4, 'int_current',          'সাম্প্রতিক বিশ্ব',                              'Current Affairs: World',            2.5, false, 7),
  (408, 4, 'int_geopolitics',      'আন্তর্জাতিক রাজনীতি ও কূটনীতি',                 'Geopolitics & Diplomacy',           1.5, false, 8),
  (499, 4, 'int_general',          'আন্তর্জাতিক — বিবিধ',                          'International — Miscellaneous',     0.5, true,  99),
  -- ভূগোল
  (501, 5, 'geo_bangladesh',       'বাংলাদেশের ভূগোল',                            'Geography of Bangladesh',           2.0, false, 1),
  (502, 5, 'geo_world',            'বিশ্ব ভূগোল',                                  'World Geography',                   1.5, false, 2),
  (503, 5, 'geo_environment',      'পরিবেশ ও জলবায়ু পরিবর্তন',                     'Environment & Climate Change',      1.5, false, 3),
  (504, 5, 'geo_disaster',         'দুর্যোগ ব্যবস্থাপনা',                           'Disaster Management',               1.5, false, 4),
  (599, 5, 'geo_general',          'ভূগোল — বিবিধ',                                'Geography — Miscellaneous',         0.5, true,  99),
  -- সাধারণ বিজ্ঞান
  (601, 6, 'sci_physics',          'পদার্থবিজ্ঞান',                                'Physics',                           1.5, false, 1),
  (602, 6, 'sci_chemistry',        'রসায়ন',                                      'Chemistry',                         1.5, false, 2),
  (603, 6, 'sci_biology',          'জীববিজ্ঞান',                                   'Biology',                           1.5, false, 3),
  (604, 6, 'sci_health',           'খাদ্য, পুষ্টি ও স্বাস্থ্য',                       'Food, Nutrition & Health',          1.0, false, 4),
  (605, 6, 'sci_everyday',         'দৈনন্দিন বিজ্ঞান',                              'Everyday Science',                  1.0, false, 5),
  (606, 6, 'sci_space_earth',      'মহাকাশ ও ভূবিজ্ঞান',                            'Space & Earth Science',             1.0, false, 6),
  (699, 6, 'sci_general',          'বিজ্ঞান — বিবিধ',                               'Science — Miscellaneous',           0.5, true,  99),
  -- কম্পিউটার
  (701, 7, 'ict_fundamentals',     'কম্পিউটার পরিচিতি ও হার্ডওয়্যার',                'Computer Fundamentals & Hardware',  1.5, false, 1),
  (702, 7, 'ict_software',         'সফটওয়্যার ও অপারেটিং সিস্টেম',                  'Software & Operating Systems',      1.0, false, 2),
  (703, 7, 'ict_number_system',    'সংখ্যা পদ্ধতি ও লজিক গেট',                      'Number Systems & Logic Gates',      1.5, false, 3),
  (704, 7, 'ict_network',          'ডেটা কমিউনিকেশন, নেটওয়ার্ক ও ইন্টারনেট',          'Networking & Internet',             1.5, false, 4),
  (705, 7, 'ict_database_programming','ডেটাবেজ ও প্রোগ্রামিং',                      'Database & Programming',            1.0, false, 5),
  (706, 7, 'ict_security_emerging','সাইবার নিরাপত্তা ও আধুনিক প্রযুক্তি',             'Cyber Security & Emerging Tech',    1.0, false, 6),
  (707, 7, 'ict_office',           'অফিস অ্যাপ্লিকেশন',                             'Office Applications',               0.5, false, 7),
  (799, 7, 'ict_general',          'কম্পিউটার — বিবিধ',                            'ICT — Miscellaneous',               0.5, true,  99),
  -- গাণিতিক যুক্তি
  (801, 8, 'math_arithmetic',      'পাটিগণিত (শতকরা, লাভ-ক্ষতি, সুদ, অনুপাত)',       'Arithmetic',                        2.5, false, 1),
  (802, 8, 'math_algebra',         'বীজগণিত',                                     'Algebra',                           2.0, false, 2),
  (803, 8, 'math_geometry',        'জ্যামিতি ও পরিমিতি',                            'Geometry & Mensuration',            2.0, false, 3),
  (804, 8, 'math_number_theory',   'সংখ্যাতত্ত্ব, ল.সা.গু ও গ.সা.গু',                'Number Theory, LCM & GCD',          1.0, false, 4),
  (805, 8, 'math_sets_probability','সেট, বিন্যাস-সমাবেশ ও সম্ভাবনা',                'Sets, Permutation & Probability',   1.0, false, 5),
  (806, 8, 'math_series_log',      'ধারা ও লগারিদম',                               'Series & Logarithm',                1.0, false, 6),
  (899, 8, 'math_general',         'গণিত — বিবিধ',                                'Math — Miscellaneous',              0.5, true,  99),
  -- মানসিক দক্ষতা
  (901, 9, 'ma_verbal',            'ভাষাগত যৌক্তিক বিচার',                         'Verbal Reasoning',                  1.5, false, 1),
  (902, 9, 'ma_numerical',         'সংখ্যাগত ক্ষমতা',                               'Numerical Ability',                 1.5, false, 2),
  (903, 9, 'ma_spatial',           'স্থানাঙ্ক ও দৃশ্যমান যুক্তি',                      'Spatial & Visual Reasoning',        1.0, false, 3),
  (904, 9, 'ma_mechanical',        'যান্ত্রিক দক্ষতা',                               'Mechanical Reasoning',              1.0, false, 4),
  (905, 9, 'ma_problem_solving',   'সমস্যা সমাধান',                                'Problem Solving',                   1.0, false, 5),
  (906, 9, 'ma_language',          'বানান ও ভাষাগত দক্ষতা',                         'Spelling & Language Skill',         1.0, false, 6),
  (999, 9, 'ma_general',           'মানসিক দক্ষতা — বিবিধ',                         'Mental Ability — Miscellaneous',    0.5, true,  99),
  -- নৈতিকতা
  (1001, 10, 'eth_concepts',       'নৈতিকতা ও মূল্যবোধের ধারণা',                    'Ethics & Values',                   1.5, false, 1),
  (1002, 10, 'eth_governance',     'সুশাসন',                                      'Good Governance',                   1.5, false, 2),
  (1003, 10, 'eth_integrity',      'শুদ্ধাচার ও জাতীয় শুদ্ধাচার কৌশল',                'National Integrity Strategy',       1.0, false, 3),
  (1004, 10, 'eth_philosophers',   'দার্শনিক ও নৈতিক তত্ত্ব',                         'Philosophers & Ethical Theories',   1.0, false, 4),
  (1005, 10, 'eth_law_rights',     'আইন, অধিকার ও প্রতিষ্ঠান',                       'Law, Rights & Institutions',        1.0, false, 5),
  (1099, 10, 'eth_general',        'নৈতিকতা — বিবিধ',                              'Ethics — Miscellaneous',            0.5, true,  99)
on conflict (id) do update set
  subject_id = excluded.subject_id, code = excluded.code, name_bn = excluded.name_bn, name_en = excluded.name_en,
  weight = excluded.weight, is_general = excluded.is_general, sort = excluded.sort;

insert into public.exam_types (code, name_bn, name_en, description_bn, sort) values
  ('bcs',     'বিসিএস',                    'BCS',                       'বাংলাদেশ সিভিল সার্ভিস প্রিলিমিনারি, লিখিত ও মৌখিক', 1),
  ('bank',    'ব্যাংক নিয়োগ',               'Bank Jobs',                 'সরকারি ও বেসরকারি ব্যাংকের নিয়োগ পরীক্ষা',          2),
  ('primary', 'প্রাথমিক শিক্ষক নিয়োগ',       'Primary Teacher',           'প্রাথমিক বিদ্যালয়ের সহকারী শিক্ষক নিয়োগ',            3),
  ('ntrca',   'শিক্ষক নিবন্ধন (NTRCA)',     'NTRCA Teacher Registration','বেসরকারি শিক্ষক নিবন্ধন পরীক্ষা',                    4),
  ('govt',    'অন্যান্য সরকারি চাকরি',        'Other Govt Jobs',           '৯ম–২০তম গ্রেডের বিভিন্ন সরকারি নিয়োগ',               5)
on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en,
  description_bn = excluded.description_bn, sort = excluded.sort;

-- Approximate dates (is_confirmed = false). Admins update them from the app;
-- every affected study plan is then re-planned automatically.
insert into public.exam_schedules (id, exam_type, title_bn, title_en, expected_date, is_confirmed, source_url, notes) values
  (1, 'bcs', '৫১তম বিসিএস (বিশেষ - স্বাস্থ্য) প্রিলিমিনারি', '51st BCS (Special, Health) Preliminary',
      '2026-11-28', false, 'https://en.prothomalo.com/youth/education/su7x69iyig',
      'BPSC plans the MCQ exam in November 2026; update once the date is announced.'),
  (2, 'bcs', 'পরবর্তী সাধারণ বিসিএস প্রিলিমিনারি (সম্ভাব্য)', 'Next General BCS Preliminary (tentative)',
      '2027-05-14', false, 'https://en.prothomalo.com/youth/employment/pdi96cgep6',
      'General BCS circular expected in November 2026; date is an estimate.'),
  (3, 'bank', 'সমন্বিত ব্যাংক নিয়োগ পরীক্ষা (সম্ভাব্য)', 'Combined Bank Recruitment (tentative)',
      '2027-02-19', false, null, 'Estimate; update when Bangladesh Bank publishes the schedule.'),
  (4, 'primary', 'প্রাথমিক সহকারী শিক্ষক নিয়োগ (সম্ভাব্য)', 'Primary Assistant Teacher (tentative)',
      '2027-03-12', false, null, 'Estimate; update when DPE publishes the schedule.')
on conflict (id) do nothing;
select setval(pg_get_serial_sequence('public.exam_schedules', 'id'), greatest((select max(id) from public.exam_schedules), 1));

insert into public.sources (kind, name, publisher, url, license_note) values
  ('curated',      'প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক', 'Prostuti', null,
   'Original practice questions written for Prostuti following the BPSC syllabus.'),
  ('ai_generated', 'প্রস্তুতি এআই · সাম্প্রতিক', 'Prostuti', null,
   'Generated daily from news facts; each question links to its source articles.')
on conflict (kind, name) do nothing;

-- ---------------------------------------------------------------------------
-- Features & add-ons (prices in BDT; all editable without an app release)
-- ---------------------------------------------------------------------------
insert into public.features (code, name_bn, name_en, description_bn, is_free, free_daily_quota, sort) values
  ('daily_notes',    'দৈনিক সাম্প্রতিক নোট',      'Daily current-affairs notes', 'প্রতিদিনের গুরুত্বপূর্ণ তথ্য, পত্রিকা থেকে বাছাই করা', true,  null, 1),
  ('question_bank',  'প্রশ্নব্যাংক অনুশীলন',        'Question bank practice',      'বিষয় ও টপিকভিত্তিক অনুশীলন',                        true,  null, 2),
  ('previous_year',  'বিগত বছরের প্রশ্ন',           'Previous year questions',     'বিগত বিসিএস ও ব্যাংক পরীক্ষার প্রশ্ন',                 true,  null, 3),
  ('social',         'কমিউনিটি ও চ্যাট',            'Community & chat',            'নিউজফিড, বন্ধু ও মেসেজ',                              true,  null, 4),
  ('daily_exam',     'দৈনিক সাম্প্রতিক পরীক্ষা',     'Daily current-affairs exam',  'প্রতিদিনের নোট থেকে পরীক্ষা ও লিডারবোর্ড',             false, null, 5),
  ('model_test',     'পূর্ণাঙ্গ মডেল টেস্ট',          'Full model tests',            'বিসিএস প্যাটার্নে ২৫/৫০/১০০/২০০ নম্বরের মডেল টেস্ট',     false, 1,    6),
  ('ai_explain',     'এআই ব্যাখ্যা',                 'AI explanations',             'যেকোনো প্রশ্নের বিস্তারিত ব্যাখ্যা',                    false, 3,    7),
  ('ai_study_plan',  'এআই স্টাডি প্ল্যান',            'AI study plan',               'লেভেল অনুযায়ী ব্যক্তিগত রুটিন ও অগ্রগতি',               false, null, 8),
  ('smart_practice', 'দুর্বল টপিক পরীক্ষা',           'Weak-topic exams',            'আপনার দুর্বল টপিক থেকে স্মার্ট পরীক্ষা',                 false, 1,    9),
  ('ad_free',        'বিজ্ঞাপনমুক্ত',                'Ad-free',                     'বিজ্ঞাপন ছাড়াই নোট ডাউনলোড',                          false, null, 10)
on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en,
  description_bn = excluded.description_bn, is_free = excluded.is_free,
  free_daily_quota = excluded.free_daily_quota, sort = excluded.sort;

insert into public.addons (code, name_bn, name_en, description_bn, description_en, features, price_bdt, period_days, trial_days, badge, color, icon, sort) values
  ('samprotik_plus', 'সাম্প্রতিক প্লাস', 'Current Affairs Plus',
   'প্রতিদিনের সাম্প্রতিক পরীক্ষা, র‍্যাঙ্কিং ও লিডারবোর্ড', 'Daily current-affairs exams with ranking',
   array['daily_exam'], 49, 30, 0, null, '#0E7C66', 'newspaper', 1),
  ('exam_pro', 'এক্সাম প্রো', 'Exam Pro',
   'আনলিমিটেড মডেল টেস্ট ও এআই ব্যাখ্যা', 'Unlimited model tests and AI explanations',
   array['model_test', 'ai_explain'], 99, 30, 0, null, '#3559E0', 'quiz', 2),
  ('ai_planner', 'এআই স্টাডি প্ল্যানার', 'AI Study Planner',
   'ব্যক্তিগত রুটিন, দুর্বল টপিক পরীক্ষা ও প্রস্তুতির অগ্রগতি', 'Personal routine, weak-topic exams and readiness tracking',
   array['ai_study_plan', 'smart_practice'], 149, 30, 0, null, '#7A4BD6', 'auto_awesome', 3),
  ('ad_free', 'বিজ্ঞাপনমুক্ত', 'Ad-free',
   'বিজ্ঞাপন ছাড়াই নোট ডাউনলোড', 'Download notes without ads',
   array['ad_free'], 29, 30, 0, null, '#495057', 'block', 4),
  ('prostuti_pro', 'প্রস্তুতি প্রো', 'Prostuti Pro',
   'সব প্রিমিয়াম ফিচার একসাথে — সবচেয়ে সাশ্রয়ী', 'Every premium feature in one plan',
   array['daily_exam', 'model_test', 'ai_explain', 'ai_study_plan', 'smart_practice', 'ad_free'], 249, 30, 7,
   'সেরা মূল্য', '#F42A41', 'workspace_premium', 0)
on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en,
  description_bn = excluded.description_bn, description_en = excluded.description_en,
  features = excluded.features, price_bdt = excluded.price_bdt, period_days = excluded.period_days,
  trial_days = excluded.trial_days, badge = excluded.badge, color = excluded.color, icon = excluded.icon,
  sort = excluded.sort;

-- ---------------------------------------------------------------------------
-- News sources (RSS). The pipeline disables a feed temporarily after repeated
-- failures and re-enables it automatically.
-- ---------------------------------------------------------------------------
insert into public.news_sources (name, homepage, rss_url, language, region, category_hint, priority) values
  ('প্রথম আলো',          'https://www.prothomalo.com',   'https://www.prothomalo.com/feed/',                         'bn', 'BD',  null,          9),
  ('ইত্তেফাক',            'https://www.ittefaq.com.bd',    'https://www.ittefaq.com.bd/feed/',                         'bn', 'BD',  null,          7),
  ('বাংলা ট্রিবিউন',       'https://www.banglatribune.com', 'https://www.banglatribune.com/feed/',                      'bn', 'BD',  null,          7),
  ('Dhaka Tribune',       'https://www.dhakatribune.com',  'https://www.dhakatribune.com/feed/',                       'en', 'BD',  null,          8),
  ('The Daily Star',      'https://www.thedailystar.net',  'https://www.thedailystar.net/frontpage/rss.xml',           'en', 'BD',  null,          9),
  ('The Business Standard','https://www.tbsnews.net',      'https://www.tbsnews.net/top-news/rss.xml',                 'en', 'BD',  'economy',     7),
  ('বাসস (BSS)',          'https://www.bssnews.net',       'https://www.bssnews.net/feed',                             'en', 'BD',  null,          6),
  ('জাগো নিউজ',           'https://www.jagonews24.com',    'https://www.jagonews24.com/rss/rss.xml',                   'bn', 'BD',  null,          5),
  ('বিবিসি বাংলা',          'https://www.bbc.com/bengali',   'https://feeds.bbci.co.uk/bengali/rss.xml',                 'bn', 'INT', null,          9),
  ('BBC World',           'https://www.bbc.com/news/world','https://feeds.bbci.co.uk/news/world/rss.xml',              'en', 'INT', null,          9),
  ('BBC Science',         'https://www.bbc.com/news/science_and_environment', 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml', 'en', 'INT', 'science_tech', 6),
  ('Al Jazeera',          'https://www.aljazeera.com',     'https://www.aljazeera.com/xml/rss/all.xml',                'en', 'INT', null,          8),
  ('The Guardian World',  'https://www.theguardian.com/world', 'https://www.theguardian.com/world/rss',                'en', 'INT', null,          7),
  ('UN News',             'https://news.un.org',           'https://news.un.org/feed/subscribe/en/news/all/rss.xml',   'en', 'INT', 'organizations', 8)
on conflict (rss_url) do update set name = excluded.name, homepage = excluded.homepage,
  language = excluded.language, region = excluded.region, category_hint = excluded.category_hint,
  priority = excluded.priority;

-- ---------------------------------------------------------------------------
-- Remote config (public)
-- ---------------------------------------------------------------------------
insert into public.app_config (key, value, description) values
  ('min_app_version',      '"1.0.0"'::jsonb,  'Clients below this version are asked to update'),
  ('latest_app_version',   '"1.0.0"'::jsonb,  'Shown as an optional update prompt'),
  ('default_schedule_id',  '2'::jsonb,        'Exam schedule targeted by new study plans'),
  ('morning_routine_time', '"06:30"'::jsonb,  'Asia/Dhaka time the daily routine notification goes out'),
  ('notes_ready_time',     '"06:00"'::jsonb,  'Asia/Dhaka time notes are expected to be ready'),
  ('ads',                  '{"rewarded_enabled": true, "android_rewarded_unit": "", "ios_rewarded_unit": ""}'::jsonb,
                           'Ad unit ids; empty → Google test ids'),
  ('support',              '{"email": "support@prostuti.app", "facebook": ""}'::jsonb, 'Support links'),
  ('maintenance',          '{"enabled": false, "message_bn": ""}'::jsonb, 'Show a maintenance banner'),
  ('placement',            '{"per_group": 10, "duration_minutes": 25}'::jsonb, 'Placement test shape')
on conflict (key) do nothing;
