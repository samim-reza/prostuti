// Text utilities: hashing, normalisation, similarity, clustering.

export async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const ENTITIES: Record<string, string> = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
  '&#8216;': '‘',
  '&#8217;': '’',
  '&#8220;': '“',
  '&#8221;': '”',
  '&#8211;': '–',
  '&#8212;': '—',
};

export function decodeEntities(s: string): string {
  return s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&[a-z#0-9]+;/gi, (m) => ENTITIES[m] ?? m);
}

export function stripHtml(s: string): string {
  return decodeEntities(s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

/** Canonical URL for de-duplication (drops tracking params, fragments, trailing slash). */
export function canonicalUrl(raw: string): string {
  try {
    const u = new URL(raw.trim());
    u.hash = '';
    for (const p of [...u.searchParams.keys()]) {
      if (/^(utm_|fbclid|gclid|ref|cmpid|at_)/i.test(p)) u.searchParams.delete(p);
    }
    u.hostname = u.hostname.replace(/^www\./, '');
    u.pathname = u.pathname.replace(/\/+$/, '') || '/';
    return u.toString().replace(/\/$/, '');
  } catch {
    return raw.trim();
  }
}

export function cosine(a: number[], b: number[]): number {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na && nb ? dot / Math.sqrt(na * nb) : 0;
}

/**
 * Greedy "leader" clustering: each item joins the first cluster whose leader
 * is at least `threshold` similar, otherwise starts a new cluster.
 * O(n·k) with k clusters — fast enough for a few hundred articles and keeps
 * the same story from different newspapers together.
 */
export function leaderCluster<T>(items: T[], vec: (t: T) => number[], threshold = 0.84): T[][] {
  const clusters: { leader: number[]; members: T[] }[] = [];
  for (const item of items) {
    const v = vec(item);
    let best = -1, bestSim = threshold;
    for (let i = 0; i < clusters.length; i++) {
      const s = cosine(v, clusters[i].leader);
      if (s >= bestSim) {
        best = i;
        bestSim = s;
      }
    }
    if (best >= 0) clusters[best].members.push(item);
    else clusters.push({ leader: v, members: [item] });
  }
  return clusters.map((c) => c.members);
}

/** Runs async tasks with bounded concurrency. */
export async function mapLimit<T, R>(
  items: T[],
  limit: number,
  fn: (t: T, i: number) => Promise<R>,
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return out;
}

const BN_DIGITS = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
export const bnDigits = (s: string | number) => String(s).replace(/[0-9]/g, (d) => BN_DIGITS[Number(d)]);

const BN_MONTHS = [
  'জানুয়ারি',
  'ফেব্রুয়ারি',
  'মার্চ',
  'এপ্রিল',
  'মে',
  'জুন',
  'জুলাই',
  'আগস্ট',
  'সেপ্টেম্বর',
  'অক্টোবর',
  'নভেম্বর',
  'ডিসেম্বর',
];
export function bnDate(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return `${bnDigits(d)} ${BN_MONTHS[m - 1]} ${bnDigits(y)}`;
}
