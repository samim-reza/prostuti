# Add-ons, features and payments

Every capability is a **feature code**. Whether it is free or paid is **data**:
the `features` and `addons` tables. The product can be repackaged at any time
without shipping an app update.

| Feature | Default | Notes |
|---------|---------|-------|
| `daily_notes` | free | today's current-affairs notes |
| `question_bank`, `previous_year` | free | practice with sources |
| `social` | free | feed, friends, chat |
| `daily_exam` | paid | daily current-affairs exam + leaderboard |
| `model_test` | paid (1/day free) | full BCS-pattern model tests |
| `ai_explain` | paid (3/day free) | AI explanations |
| `ai_study_plan` | paid | personal plan, routine, readiness |
| `smart_practice` | paid (1/day free) | weak-topic exams |
| `ad_free` | paid | download notes without ads |

| Add-on | Features | Price |
|--------|----------|-------|
| সাম্প্রতিক প্লাস | daily_exam | ৳49 / 30 days |
| এক্সাম প্রো | model_test, ai_explain | ৳99 / 30 days |
| এআই স্টাডি প্ল্যানার | ai_study_plan, smart_practice | ৳149 / 30 days |
| বিজ্ঞাপনমুক্ত | ad_free | ৳29 / 30 days |
| **প্রস্তুতি প্রো** | everything | ৳249 / 30 days (**7-day free trial on sign-up**) |

## How access is checked

* **Server (authoritative):** `require_feature('<code>')` inside RPCs and Edge
  Functions. A locked feature returns **HTTP 402**. Free quotas are
  rate-limited per Bangladesh day.
* **Client (UX only):** `featureAccessProvider` holds the map returned by
  `get_feature_access()`, cached for 10 minutes. `EntitlementGate` and
  `showLockedSheet` show the upsell.

## Granting access today

* Trial: automatic at sign-up (`addons.trial_days`).
* Promo codes: `insert into promo_codes …`; users redeem in **Add-ons**.
* Admin grant: `select admin_grant_addon('<user uuid>', 'prostuti_pro', 30);`

## Adding a payment gateway later

The client has a `PaymentProvider` interface (`features/addons/data/`) and the
database has a `payments` table. To go live with bKash, Nagad, SSLCommerz or
Google Play Billing:

1. Implement a provider (client) that starts checkout.
2. Add an Edge Function webhook (`payments-<provider>`) that verifies the
   gateway signature, writes `payments`, and inserts a `user_entitlements` row
   with `source = 'purchase'`.
3. Never grant entitlements from the client.

> Google Play policy requires Play Billing for digital goods sold inside
> Play-distributed apps. Direct gateways suit sideloaded/web distribution.
