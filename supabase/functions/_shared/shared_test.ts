import { assert, assertEquals } from 'jsr:@std/assert@1';
import { BloomFilter, fromHex, toHex } from './bloom.ts';
import { parseFeed } from './rss.ts';
import { canonicalUrl, cosine, leaderCluster, stripHtml } from './text.ts';

Deno.test('bloom filter: no false negatives, low false positives, hex round-trip', () => {
  const bloom = BloomFilter.create(5000, 0.01);
  for (let i = 0; i < 5000; i++) bloom.add(`url-${i}`);
  for (let i = 0; i < 5000; i++) assert(bloom.mightContain(`url-${i}`));
  let fp = 0;
  for (let i = 0; i < 10000; i++) if (bloom.mightContain(`other-${i}`)) fp++;
  assert(fp / 10000 < 0.03, `false-positive rate too high: ${fp}`);
  const restored = new BloomFilter(bloom.m, bloom.k, fromHex(toHex(bloom.bits)));
  assert(restored.mightContain('url-42'));
});

Deno.test('rss parser handles RSS 2.0 with CDATA and entities', () => {
  const xml = `<rss><channel><item><title><![CDATA[বাংলাদেশ &amp; বিশ্ব]]></title>
    <link>https://example.com/a?utm_source=x</link><description><![CDATA[<p>সংক্ষেপ</p>]]></description>
    <pubDate>Sat, 03 Oct 2026 10:00:00 GMT</pubDate></item></channel></rss>`;
  const items = parseFeed(xml);
  assertEquals(items.length, 1);
  assertEquals(items[0].title, 'বাংলাদেশ & বিশ্ব');
  assertEquals(items[0].summary, 'সংক্ষেপ');
  assert(items[0].published instanceof Date);
});

Deno.test('rss parser handles Atom links', () => {
  const xml =
    `<feed><entry><title>Hello</title><link href="https://example.com/b"/><updated>2026-10-03T10:00:00Z</updated></entry></feed>`;
  assertEquals(parseFeed(xml)[0].link, 'https://example.com/b');
});

Deno.test('canonicalUrl strips tracking params, www and trailing slash', () => {
  assertEquals(
    canonicalUrl('https://www.example.com/news/1/?utm_source=fb&id=2#top'),
    'https://example.com/news/1?id=2',
  );
});

Deno.test('stripHtml removes tags and decodes entities', () => {
  assertEquals(stripHtml('<b>A&nbsp;&amp;&#2453;</b>'), 'A &ক');
});

Deno.test('leader clustering groups near-duplicates', () => {
  const items = [[1, 0], [0.99, 0.05], [0, 1], [0.02, 0.98]];
  const clusters = leaderCluster(items, (v) => v, 0.9);
  assertEquals(clusters.length, 2);
  assert(cosine([1, 0], [1, 0]) > 0.999);
});
