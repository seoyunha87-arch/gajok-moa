// Supabase Edge Function: send-push
// Triggered by a Database Webhook on INSERT into public.notifications.
// Sends a Web Push message to every device subscribed for that family.
//
// Required secrets (Edge Functions -> send-push -> Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.)

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;

webpush.setVapidDetails("mailto:seoyunha87@gmail.com", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;
    if (!record || !record.family_id || !record.message) {
      return new Response("ignored", { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: subs } = await supabase
      .from("push_subscriptions")
      .select("*")
      .eq("family_id", record.family_id);

    if (!subs || subs.length === 0) {
      return new Response("no subscriptions", { status: 200 });
    }

    const body = JSON.stringify({
      title: "가족모아",
      body: record.message,
      url: "./",
    });

    await Promise.allSettled(
      subs.map((s) =>
        webpush
          .sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
            body
          )
          .catch(async (err) => {
            // Subscription is gone (expired/unsubscribed) - clean it up.
            if (err.statusCode === 404 || err.statusCode === 410) {
              await supabase.from("push_subscriptions").delete().eq("id", s.id);
            }
          })
      )
    );

    return new Response("sent", { status: 200 });
  } catch (err) {
    return new Response(String(err), { status: 500 });
  }
});
