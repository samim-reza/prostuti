// dispatch-notifications — runs every 15 minutes.
//
//   1. Morning routine: inside the configured window (default 06:30 BD) queue
//      one personalised "today's routine" notification per learner — exactly
//      once per day (pipeline_runs idempotency key).
//   2. Push outbox: deliver pending pushes via FCM when configured (batched,
//      invalid tokens pruned). Without FCM the in-app inbox (Realtime) and
//      on-device scheduled reminders cover notifications.
import { json, serve } from '../_shared/http.ts';
import { admin, bdMinutesNow, bdToday, requireCronOrStaff } from '../_shared/supabase.ts';
import { isEnabled, sendPush } from '../_shared/fcm.ts';
import { mapLimit } from '../_shared/text.ts';

serve(async (req) => {
  await requireCronOrStaff(req);
  const report: Record<string, unknown> = {};

  const { data: cfg } = await admin.from('app_config').select('value').eq('key', 'morning_routine_time')
    .maybeSingle();
  const [h, m] = String(cfg?.value ?? '06:30').split(':').map(Number);
  const target = (h || 6) * 60 + (m || 0);
  const now = bdMinutesNow();
  if (now >= target && now < target + 60) {
    const { data: claimed } = await admin.rpc('claim_pipeline_run', {
      p_key: `morning_routine:${bdToday()}`,
    });
    if (claimed === true) {
      const { data: count } = await admin.rpc('queue_morning_routines');
      report.morning_routines = count;
    }
  }

  if (isEnabled()) {
    const { data: pending } = await admin
      .from('push_outbox')
      .select('id, user_id, title, body, data, attempts')
      .is('sent_at', null)
      .lt('attempts', 5)
      .order('created_at')
      .limit(500);
    const userIds = [...new Set((pending ?? []).map((p) => p.user_id))];
    const { data: tokens } = userIds.length
      ? await admin.from('device_tokens').select('token, user_id').in('user_id', userIds)
      : { data: [] };
    const byUser = new Map<string, string[]>();
    for (const t of tokens ?? []) byUser.set(t.user_id, [...(byUser.get(t.user_id) ?? []), t.token]);

    let sent = 0, invalid = 0;
    await mapLimit(pending ?? [], 10, async (p) => {
      const targets = byUser.get(p.user_id) ?? [];
      const data = Object.fromEntries(Object.entries(p.data ?? {}).map(([k, v]) => [k, String(v)]));
      let ok = false;
      for (const token of targets) {
        const r = await sendPush(token, p.title, p.body ?? '', data);
        if (r === 'ok') ok = true;
        if (r === 'invalid') {
          invalid++;
          await admin.from('device_tokens').delete().eq('token', token);
        }
      }
      if (ok || targets.length === 0) sent++;
      await admin.from('push_outbox').update(
        ok || targets.length === 0
          ? {
            sent_at: new Date().toISOString(),
            attempts: p.attempts + 1,
            last_error: targets.length ? null : 'no_device',
          }
          : { attempts: p.attempts + 1, last_error: 'send_failed' },
      ).eq('id', p.id);
    });
    report.push = { pending: pending?.length ?? 0, sent, invalid_tokens: invalid };
  } else {
    report.push = 'fcm_disabled';
  }

  return json(report);
});
