// moderate-content — asynchronous AI moderation for posts and comments.
// Called by Postgres triggers through pg_net right after an insert, so
// posting stays instant; clearly abusive content is hidden within seconds
// and the author is told why.
import { HttpError, json, readJson, serve } from '../_shared/http.ts';
import { admin, requireCron } from '../_shared/supabase.ts';
import { moderate } from '../_shared/openai.ts';

const BLOCK_SCORE = 0.85;

serve(async (req) => {
  requireCron(req);
  const { type, id } = await readJson<{ type?: string; id?: string }>(req);
  if (!id || (type !== 'post' && type !== 'comment')) throw new HttpError(400, 'invalid_target');

  const table = type === 'post' ? 'posts' : 'comments';
  const { data: row } = await admin.from(table).select('id, author_id, body').eq('id', id).maybeSingle();
  if (!row?.body?.trim()) return json({ skipped: true });

  const result = await moderate(row.body);
  if (result.flagged && result.maxScore >= BLOCK_SCORE) {
    await admin.from(table).update({ is_hidden: true }).eq('id', id);
    await admin.rpc('notify_user', {
      p_user: row.author_id,
      p_type: 'system',
      p_title: type === 'post' ? 'আপনার পোস্টটি লুকানো হয়েছে' : 'আপনার মন্তব্যটি লুকানো হয়েছে',
      p_body: 'কমিউনিটি নীতিমালা লঙ্ঘনের সম্ভাবনা থাকায় এটি স্বয়ংক্রিয়ভাবে লুকানো হয়েছে। ভুল মনে হলে সাপোর্টে জানান।',
      p_data: { [type === 'post' ? 'post_id' : 'comment_id']: id },
      p_category: 'social',
      p_title_en: type === 'post' ? 'Your post was hidden' : 'Your comment was hidden',
      p_body_en:
        'It was hidden automatically because it may break the community guidelines. Contact support if this looks wrong.',
    });
    return json({
      hidden: true,
      categories: Object.keys(result.categories).filter((k) => result.categories[k]),
    });
  }
  return json({ hidden: false });
});
