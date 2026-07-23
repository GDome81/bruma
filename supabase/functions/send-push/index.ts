// Edge Function `send-push` — invia una notifica ANONIMA (🌙) al destinatario
// di ogni nuovo messaggio. Va invocata da un Database Webhook su INSERT della
// tabella `messages` (vedi docs/PUSH_SETUP.md). Due canali:
//   • Web Push (PWA)  → tabella `push_subscriptions` (VAPID).
//   • FCM v1 (APK)    → tabella `fcm_tokens` (service account Firebase).
//
// Payload atteso (webhook Supabase): { type, table, record: <riga messages>, ... }
//
// Segreti (supabase secrets set ...):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT   (Web Push)
//   FCM_SERVICE_ACCOUNT = <contenuto JSON della chiave service-account>  (FCM)
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

// --- FCM v1 -----------------------------------------------------------------

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der;
}

let cachedFcmToken: { value: string; exp: number } | null = null;

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedFcmToken && cachedFcmToken.exp > now + 60) return cachedFcmToken.value;

  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claim))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const json = await res.json();
  if (!json.access_token) {
    throw new Error(`FCM OAuth error: ${JSON.stringify(json)}`);
  }
  cachedFcmToken = {
    value: json.access_token,
    exp: now + (json.expires_in ?? 3600),
  };
  return json.access_token;
}

async function sendFcm(recipientId: string): Promise<void> {
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saRaw) {
    console.log("FCM: secret FCM_SERVICE_ACCOUNT NON impostato → skip");
    return;
  }
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(saRaw);
  } catch {
    console.error("FCM: FCM_SERVICE_ACCOUNT non è JSON valido");
    return;
  }
  if (!sa.project_id || !sa.client_email || !sa.private_key) {
    console.error("FCM: service account incompleto (project_id/client_email/private_key)");
    return;
  }

  const { data: tokens } = await admin
    .from("fcm_tokens")
    .select("id,token")
    .eq("user_id", recipientId);
  console.log(`FCM: ${tokens?.length ?? 0} token per destinatario ${recipientId}`);
  if (!tokens || tokens.length === 0) return;

  let access: string;
  try {
    access = await getFcmAccessToken(sa);
  } catch (e) {
    console.error(`FCM: OAuth error: ${e}`);
    return;
  }
  console.log("FCM: access token OK, invio in corso");

  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages`;

  await Promise.all(tokens.map(async (t) => {
    const body = JSON.stringify({
      message: {
        token: t.token,
        // ANONIMO: nessun nome, nessun contenuto.
        notification: { title: "Bruma", body: "🌙" },
        android: { priority: "HIGH" },
      },
    });
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${access}`,
          "Content-Type": "application/json",
        },
        body,
      });
      console.log(`FCM: send status ${res.status}`);
      if (!res.ok) {
        const errText = await res.text();
        console.error(`FCM: send ${res.status}: ${errText}`);
        // Solo token morto → rimuovilo (NON su INVALID_ARGUMENT, che può
        // indicare un payload errato e cancellerebbe token validi).
        if (res.status === 404 || errText.includes("UNREGISTERED")) {
          await admin.from("fcm_tokens").delete().eq("id", t.id);
        }
      }
    } catch (e) {
      console.error(`FCM: fetch error: ${e}`);
    }
  }));
}

// --- Handler ----------------------------------------------------------------

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

    // Chat silenziata dal destinatario → niente push (né web né FCM).
    const { data: mute } = await admin
      .from("chat_mutes")
      .select("user_id")
      .eq("user_id", recipientId)
      .eq("conversation_id", msg.conversation_id)
      .maybeSingle();
    if (mute) return new Response("muted", { status: 200 });

    // Preferenze suono/vibrazione (default: attivi) — usate dal Web Push.
    const { data: prefs } = await admin
      .from("notif_prefs")
      .select("sound,vibrate")
      .eq("user_id", recipientId)
      .maybeSingle();
    const sound = prefs?.sound ?? true;
    const vibrate = prefs?.vibrate ?? true;

    // 1) Web Push (PWA) — se il destinatario ha subscription.
    const { data: subs } = await admin
      .from("push_subscriptions")
      .select("id,endpoint,p256dh,auth")
      .eq("user_id", recipientId);
    if (subs && subs.length > 0) {
      const body = JSON.stringify({
        title: "Bruma",
        body: "🌙",
        silent: !sound,
        vibrate,
      });
      await Promise.all(subs.map(async (s) => {
        try {
          await webpush.sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
            body,
          );
        } catch (err) {
          const code = (err as { statusCode?: number })?.statusCode;
          if (code === 404 || code === 410) {
            await admin.from("push_subscriptions").delete().eq("id", s.id);
          }
        }
      }));
    }

    // 2) FCM (APK Android) — indipendente dal Web Push.
    await sendFcm(recipientId);

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response(`error: ${e}`, { status: 500 });
  }
});
