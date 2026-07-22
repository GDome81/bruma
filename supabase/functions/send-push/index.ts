// Edge Function `send-push` — invia una Web Push ANONIMA (🌙) al destinatario
// di ogni nuovo messaggio. Va invocata da un Database Webhook su INSERT della
// tabella `messages` (vedi docs/PUSH_SETUP.md).
//
// Payload atteso (webhook Supabase): { type, table, record: <riga messages>, ... }
//
// Segreti richiesti (supabase secrets set ...):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (es. mailto:tu@dominio)
// Iniettati automaticamente da Supabase:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY")!;
const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY")!;
const vapidSubject = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@bruma.app";

webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);

const admin = createClient(supabaseUrl, serviceKey);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const msg = payload?.record;
    if (!msg?.conversation_id || !msg?.sender_id) {
      return new Response("ignored", { status: 200 });
    }

    // Trova il destinatario (l'altro utente della conversazione).
    const { data: conv } = await admin
      .from("conversations")
      .select("user_a,user_b")
      .eq("id", msg.conversation_id)
      .maybeSingle();
    if (!conv) return new Response("no conversation", { status: 200 });

    const recipientId = conv.user_a === msg.sender_id ? conv.user_b : conv.user_a;
    if (!recipientId) return new Response("no recipient", { status: 200 });

    // Subscription push del destinatario.
    const { data: subs } = await admin
      .from("push_subscriptions")
      .select("id,endpoint,p256dh,auth")
      .eq("user_id", recipientId);
    if (!subs || subs.length === 0) {
      return new Response("no subscriptions", { status: 200 });
    }

    // Payload ANONIMO: nessun nome, nessun contenuto.
    const body = JSON.stringify({ title: "Bruma", body: "🌙" });

    await Promise.all(
      subs.map(async (s) => {
        try {
          await webpush.sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
            body,
          );
        } catch (err) {
          // 404/410 = subscription scaduta → rimuovila.
          const code = (err as { statusCode?: number })?.statusCode;
          if (code === 404 || code === 410) {
            await admin.from("push_subscriptions").delete().eq("id", s.id);
          }
        }
      }),
    );

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response(`error: ${e}`, { status: 500 });
  }
});
