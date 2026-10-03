// Tiny, tolerant RSS 2.0 / Atom parser (regex based — feeds in the wild are
// rarely valid XML, so a strict parser would drop good items).
import { decodeEntities, stripHtml } from './text.ts';

export interface FeedItem {
  title: string;
  link: string;
  summary: string;
  published: Date | null;
  image: string | null;
}

const tag = (xml: string, name: string) => {
  const m = new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`, 'i').exec(xml);
  return m ? m[1] : '';
};

export function parseFeed(xml: string): FeedItem[] {
  const blocks = xml.match(/<item[\s>][\s\S]*?<\/item>/gi) ?? xml.match(/<entry[\s>][\s\S]*?<\/entry>/gi) ??
    [];
  const items: FeedItem[] = [];
  for (const b of blocks) {
    const title = stripHtml(tag(b, 'title'));
    let link = stripHtml(tag(b, 'link'));
    if (!link) link = /<link[^>]*href="([^"]+)"/i.exec(b)?.[1] ?? '';
    if (!link) link = stripHtml(tag(b, 'guid'));
    const summary = stripHtml(
      tag(b, 'description') || tag(b, 'summary') || tag(b, 'content:encoded') || tag(b, 'content'),
    )
      .slice(0, 700);
    const dateText = stripHtml(
      tag(b, 'pubDate') || tag(b, 'published') || tag(b, 'updated') || tag(b, 'dc:date'),
    );
    const published = dateText ? new Date(dateText) : null;
    const image = /<media:(?:content|thumbnail)[^>]*url="([^"]+)"/i.exec(b)?.[1] ??
      /<enclosure[^>]*url="([^"]+)"[^>]*type="image/i.exec(b)?.[1] ?? null;
    if (title && /^https?:\/\//i.test(link)) {
      items.push({
        title: decodeEntities(title).slice(0, 300),
        link: link.trim(),
        summary,
        published: published && !isNaN(published.getTime()) ? published : null,
        image,
      });
    }
  }
  return items;
}
