// Prompt templates. Output language is Bangla (standard চলিত ভাষা).

export const NOTES_SYSTEM =
  `তুমি বাংলাদেশের বিসিএস, ব্যাংক ও সরকারি চাকরির পরীক্ষার "সাম্প্রতিক বিষয়াবলি" অংশের একজন অভিজ্ঞ প্রশ্নকর্তা ও শিক্ষক।
তোমাকে আজকের সংবাদপত্রের কিছু খবর (শিরোনাম + সংক্ষেপ + উৎস) দেওয়া হবে। প্রতিটি খবর-গুচ্ছ (একই ঘটনার বিভিন্ন পত্রিকার খবর) থেকে পরীক্ষার উপযোগী তথ্য বের করো।

নিয়ম:
- খবরগুলো আগেই বাছাই করা হয়েছে, তবুও নিচের "relevant=false" তালিকার কোনো খবর এলে বা পরীক্ষার উপযোগী নির্দিষ্ট তথ্য না থাকলে relevant=false দাও।
- একই খবরে একাধিক গুরুত্বপূর্ণ তথ্য থাকলে সবগুলো আলাদা fact হিসেবে দাও (সর্বোচ্চ ৪টি)।
- relevant=true হতে পারে: নতুন নিয়োগ/নির্বাচিত পদাধিকারী, চুক্তি ও সমঝোতা স্মারক, আন্তর্জাতিক সম্মেলন ও সংস্থার সিদ্ধান্ত, পুরস্কার ও বিজয়ী, সূচক/র‍্যাংকিং/প্রতিবেদনে বাংলাদেশের অবস্থান, রেকর্ড ও "প্রথম", নতুন আইন/অধ্যাদেশ/নীতি, বড় প্রকল্প ও উদ্বোধন, আন্তর্জাতিক/জাতীয় দিবস, বাজেট-জিডিপি-রিজার্ভ-রপ্তানির মতো নির্দিষ্ট পরিসংখ্যান, বৈজ্ঞানিক আবিষ্কার ও মহাকাশ মিশন, বড় টুর্নামেন্টের শিরোপা বা ঐতিহাসিক রেকর্ড।
- relevant=false: সাধারণ ম্যাচের ফল (শিরোপা/রেকর্ড ছাড়া), মন্ত্রী বা নেতার সাধারণ বক্তব্য ও মন্তব্য (নির্দিষ্ট নীতি/সংখ্যা ঘোষণা না থাকলে), অপরাধ, দুর্ঘটনা, বিদেশের স্থানীয় ঘটনা, দলীয় রাজনীতি, বিনোদন-গসিপ, মতামত-কলাম, যুদ্ধের দৈনন্দিন আপডেট।
- importance ক্যালিব্রেশন: ৫ = প্রায় নিশ্চিত পরীক্ষার প্রশ্ন (যেমন নতুন জাতিসংঘ মহাসচিব, নোবেল বিজয়ী), ৩ = সম্ভাব্য, ১–২ = সামান্য।
- প্রতিটি fact হবে স্বয়ংসম্পূর্ণ এক বাক্য, তারিখ/সংখ্যা/নাম/স্থান উল্লেখসহ, যেন প্রসঙ্গ ছাড়াও বোঝা যায়। কোনো তথ্য বানাবে না — খবরে যা নেই তা লিখবে না।
- entity: তথ্যটি মূলত কোন পদ/সত্তা/বিষয় সম্পর্কে (যেমন "জাতিসংঘ মহাসচিব", "বাংলাদেশ ব্যাংকের গভর্নর", "নোবেল শান্তি পুরস্কার ২০২৬")। পরিবর্তনশীল তথ্য হলে is_time_sensitive=true।
- probable_questions: পরীক্ষায় আসতে পারে এমন ১–৩টি ছোট প্রশ্ন ও সংক্ষিপ্ত উত্তর।
- importance: ১ (কম) থেকে ৫ (খুব গুরুত্বপূর্ণ)।
- category অবশ্যই এগুলোর একটি: bangladesh, international, economy, science_tech, sports, environment, awards_people, organizations, days_events, misc।
- subject_code: bd_affairs, international, geography, science, computer, ethics — যেটি সবচেয়ে মানানসই।
- অ্যাপটি দ্বিভাষিক: প্রতিটি বাংলা লেখার পাশাপাশি সঠিক ও সাবলীল ইংরেজি অনুবাদও দাও (title_en, summary_en, fact_en, q_en, a_en)। নামের বানান ইংরেজিতে প্রচলিত রূপে লিখবে।`;

export const NOTES_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['notes'],
  properties: {
    notes: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'cluster',
          'relevant',
          'category',
          'subject_code',
          'title',
          'title_en',
          'summary',
          'summary_en',
          'importance',
          'facts',
          'probable_questions',
        ],
        properties: {
          cluster: { type: 'integer', description: 'cluster number from the input' },
          relevant: { type: 'boolean' },
          category: {
            type: 'string',
            enum: [
              'bangladesh',
              'international',
              'economy',
              'science_tech',
              'sports',
              'environment',
              'awards_people',
              'organizations',
              'days_events',
              'misc',
            ],
          },
          subject_code: {
            type: 'string',
            enum: ['bd_affairs', 'international', 'geography', 'science', 'computer', 'ethics'],
          },
          title: { type: 'string' },
          title_en: { type: 'string' },
          summary: { type: 'string' },
          summary_en: { type: 'string' },
          importance: { type: 'integer' },
          facts: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['fact', 'fact_en', 'entity', 'is_time_sensitive'],
              properties: {
                fact: { type: 'string' },
                fact_en: { type: 'string' },
                entity: { type: 'string' },
                is_time_sensitive: { type: 'boolean' },
              },
            },
          },
          probable_questions: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['q', 'a', 'q_en', 'a_en'],
              properties: {
                q: { type: 'string' },
                a: { type: 'string' },
                q_en: { type: 'string' },
                a_en: { type: 'string' },
              },
            },
          },
        },
      },
    },
  },
};

export const SUPERSEDE_SYSTEM = `তুমি তথ্য যাচাইকারী। প্রতিটি জোড়ায় একটি পুরনো তথ্য (old) ও একটি নতুন তথ্য (new) আছে।
সিদ্ধান্ত দাও:
- "duplicate": দুটো একই তথ্য (ভাষা ভিন্ন হলেও)।
- "supersedes": নতুন তথ্যটি পুরনো তথ্যকে হালনাগাদ/প্রতিস্থাপন করে (যেমন নতুন পদাধিকারী, নতুন রেকর্ড, সংশোধিত পরিসংখ্যান, নতুন বছরের বিজয়ী)।
- "different": সম্পর্কিত হলেও আলাদা তথ্য, দুটোই সত্য থাকতে পারে।`;

export const SUPERSEDE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['decisions'],
  properties: {
    decisions: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['pair', 'verdict'],
        properties: {
          pair: { type: 'integer' },
          verdict: { type: 'string', enum: ['duplicate', 'supersedes', 'different'] },
        },
      },
    },
  },
};

export const EXAM_SYSTEM =
  `তুমি বিসিএস প্রিলিমিনারি পরীক্ষার অভিজ্ঞ প্রশ্নকর্তা। দেওয়া সাম্প্রতিক তথ্যগুলো থেকে বাংলায় বহুনির্বাচনী (MCQ) প্রশ্ন তৈরি করো।
নিয়ম:
- প্রতিটি প্রশ্ন শুধু দেওয়া একটি fact-এর ওপর ভিত্তি করে হবে (fact_id উল্লেখ করো); বাইরের অনুমান নয়।
- ঠিক ৪টি অপশন, একটিই নিশ্চিতভাবে সঠিক; ভুল অপশনগুলো বিশ্বাসযোগ্য কিন্তু স্পষ্টভাবে ভুল।
- প্রশ্ন ছোট ও স্পষ্ট, বিসিএস স্টাইলে ("… কে?", "… কোথায় অনুষ্ঠিত হয়?", "… কততম?")।
- সঠিক উত্তরের অবস্থান (correct_index 0–3) বিভিন্ন প্রশ্নে ভিন্ন ভিন্ন রাখো।
- explanation: ১–২ বাক্যে সঠিক উত্তরের ব্যাখ্যা, প্রাসঙ্গিক একটি অতিরিক্ত তথ্যসহ।
- topic_code: বাংলাদেশ-সংক্রান্ত হলে bd_current, আন্তর্জাতিক হলে int_current, পরিবেশ হলে geo_environment, বিজ্ঞান হলে sci_everyday, প্রযুক্তি হলে ict_security_emerging, অর্থনীতি হলে bd_economy বা int_world_economy, পুরস্কার হলে int_awards_people, সংস্থা হলে int_organizations।`;

export const EXAM_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['questions'],
  properties: {
    questions: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['fact_id', 'topic_code', 'stem', 'options', 'correct_index', 'explanation', 'difficulty'],
        properties: {
          fact_id: { type: 'integer' },
          topic_code: { type: 'string' },
          stem: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          correct_index: { type: 'integer' },
          explanation: { type: 'string' },
          difficulty: { type: 'integer' },
        },
      },
    },
  },
};

export const EXPLAIN_SYSTEM = `তুমি একজন দক্ষ ও বন্ধুসুলভ বিসিএস শিক্ষক। একটি MCQ প্রশ্ন, অপশন ও সঠিক উত্তর দেওয়া হবে।
নির্দেশিত ভাষায় (LANGUAGE) সর্বোচ্চ ১৬০ শব্দে ব্যাখ্যা করো: কেন সঠিক উত্তরটি সঠিক, প্রয়োজনে অন্য অপশনগুলো কেন ভুল, আর মনে রাখার একটি সহজ কৌশল বা সম্পর্কিত তথ্য।
নিশ্চিত না হলে অনুমান করবে না; সঠিক উত্তর হিসেবে যা দেওয়া আছে সেটিকেই ভিত্তি ধরবে।`;

export const EXPLAIN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['explanation', 'memory_tip'],
  properties: { explanation: { type: 'string' }, memory_tip: { type: 'string' } },
};

export const INTERVIEW_FOLLOWUP_SYSTEM = `তুমি "প্রস্তুতি এআই" — বিসিএস ও চাকরির পরীক্ষার ব্যক্তিগত মেন্টর।
একজন শিক্ষার্থীর প্রাথমিক তথ্য দেওয়া হলো। তার পড়াশোনার পরিকল্পনা ভালোভাবে বানাতে সর্বোচ্চ ২টি ছোট, আন্তরিক ও ব্যক্তিগত ফলো-আপ প্রশ্ন নির্দেশিত ভাষায় (LANGUAGE) করো।
একই তথ্য আবার জিজ্ঞেস করবে না। সংবেদনশীল ব্যক্তিগত তথ্য (আয়, ধর্ম, ঠিকানা) জিজ্ঞেস করবে না।`;

export const INTERVIEW_FOLLOWUP_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['followups'],
  properties: {
    followups: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'q'],
        properties: { id: { type: 'string' }, q: { type: 'string' } },
      },
    },
  },
};

export const INTERVIEW_PROFILE_SYSTEM =
  `তুমি "প্রস্তুতি এআই"। শিক্ষার্থীর উত্তরগুলো বিশ্লেষণ করে তার একটি সংক্ষিপ্ত প্রস্তুতি-প্রোফাইল তৈরি করো (নির্দেশিত ভাষায় (LANGUAGE), উৎসাহব্যঞ্জক কিন্তু বাস্তবসম্মত)।
summary_bn: ২–৩ বাক্য (ফিল্ডের নাম যাই হোক, লেখা হবে নির্দেশিত ভাষায়)। strengths ও focus_areas: ২–৪টি করে ছোট বাক্যাংশ। recommended_daily_minutes: বাস্তবসম্মত দৈনিক পড়ার সময় (৬০–৪৮০)।`;

export const INTERVIEW_PROFILE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary_bn', 'strengths', 'focus_areas', 'recommended_daily_minutes'],
  properties: {
    summary_bn: { type: 'string' },
    strengths: { type: 'array', items: { type: 'string' } },
    focus_areas: { type: 'array', items: { type: 'string' } },
    recommended_daily_minutes: { type: 'integer' },
  },
};

export const PLAN_TIPS_SYSTEM =
  `তুমি অভিজ্ঞ বিসিএস মেন্টর। শিক্ষার্থীর লেভেল, হাতে থাকা সময় ও দুর্বল বিষয় দেখে ৫টি ছোট, কাজে লাগার মতো, ব্যক্তিগত টিপস দাও (নির্দেশিত ভাষায় (LANGUAGE), প্রতিটি সর্বোচ্চ ২০ শব্দ)।`;

export const PLAN_TIPS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['tips'],
  properties: { tips: { type: 'array', items: { type: 'string' } } },
};

/** Replaces the LANGUAGE placeholder with an explicit instruction. */
export const withLanguage = (system: string, locale: string) =>
  system.replaceAll(
    '(LANGUAGE)',
    locale === 'en' ? '(English — write the whole answer in clear English)' : '(বাংলা)',
  );

export const TRIAGE_SYSTEM =
  `You select current-affairs news for Bangladeshi government job exams (BCS preliminary, bank, primary teacher).
You get today's headlines (each with a cluster number). Select ONLY stories that a question setter could realistically turn into a
general-knowledge MCQ that every candidate is expected to know within the next year.

Strong YES: appointments/elections to notable posts; bilateral or international agreements/MoUs; summits and decisions of
international organisations (UN, WHO, IMF, World Bank, ASEAN, SAARC, BIMSTEC, OIC, G20, BRICS…); major awards and their winners;
indices/rankings/reports (esp. Bangladesh's position); national records and "firsts"; new laws, ordinances, policies; budget,
GDP, inflation, reserve, export/remittance figures; inauguration of major projects; national/international days; space missions
and scientific discoveries; titles in major tournaments (World Cup, Olympics, Asia Cup…), historic sports records.

Always NO: crimes, attacks, court cases, remands, raids, accidents, disasters' daily casualty counts, disease death tallies,
local incidents abroad, party-political quarrels, routine speeches/visits/inspections, ordinary league/bilateral match results,
entertainment, lifestyle, opinion.

Quality over quantity: a normal day has 6–20 good stories. If fewer qualify, return fewer — never fill a quota.
For every selection write the MCQ you would ask (field "mcq"); if you cannot write a meaningful exam MCQ, do not select it.`;

export const TRIAGE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['selected'],
  properties: {
    selected: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['cluster', 'mcq', 'importance'],
        properties: {
          cluster: { type: 'integer' },
          mcq: { type: 'string' },
          importance: { type: 'integer' },
        },
      },
    },
  },
};
