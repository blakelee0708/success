// 가족 메시지's notification half.
//
// The parent sends a message; their children's phones get an ordinary
// status-bar notification. The exact opposite of what FCM does for the
// senior, and for the same reason: a status-bar entry is the one place a
// parent who cannot find their contacts app will not look, and the first
// place their child will.
//
// **A `notification` payload, not a `data` one.** That is the whole reason
// this is cheap where 소리 울리기 is not. Android draws a notification
// message itself while the app is backgrounded or not running at all - no
// background handler, no native code, nothing to bring forward, and nothing
// for Play to review. 소리 울리기 cannot use it because a notification
// cannot make a noise on a silenced phone.
//
// Every question about *whether* this may be sent is answered by
// `notify_family_message` in SQL, which is the same split `ring-phone`
// documents at length. This file only sends.
//
// **The OAuth half below is a copy of `ring-phone`'s**, deliberately. A
// shared module would have to be deployed alongside both functions, and this
// container has no `supabase` CLI to do that with - the deploy goes through
// the Management API one file at a time. What is duplicated is standard JWT
// minting against a key that is read from the environment, so a rotation
// reaches both copies for free. If this ever needs a third caller, extract
// it then.
//
// Deploy:
//   supabase functions deploy notify-message --project-ref <ref>
// It needs the same FCM_SERVICE_ACCOUNT secret `ring-phone` does.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri: string;
}

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) throw new Error('FCM_SERVICE_ACCOUNT is not set');
  return JSON.parse(raw);
}

/** PEM → the CryptoKey `crypto.subtle.sign` wants. */
async function signingKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    // The JSON carries the newlines as `\n`, and whitespace of any kind is
    // not base64.
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

function b64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === 'string'
    ? bytes
    : String.fromCharCode(...bytes);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * The OAuth access token FCM v1 wants.
 *
 * Minted here rather than with a library: the legacy server key is gone, so
 * it is a service account or nothing, and the whole exchange is one signed
 * JWT. It is not cached — a ring is rare and a stale token held across a key
 * rotation fails in a way nobody would think to look for.
 */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      await signingKey(sa.private_key),
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  const assertion = `${header}.${claims}.${b64url(signature)}`;

  const res = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`token exchange failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reply(405, { error: 'POST only' });

  // The caller's own JWT, forwarded. The gate reads `auth.uid()` to check
  // this really is the phone the message was sent from.
  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply(401, { error: '로그인이 필요해요.' });

  let messageId: string;
  try {
    const body = await req.json();
    messageId = body.message_id;
    if (!messageId) throw new Error('message_id is required');
  } catch (_) {
    return reply(400, { error: 'message_id is required' });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data, error } = await supabase.rpc('notify_family_message', {
    p_message_id: messageId,
  });
  if (error) return reply(403, { error: error.message });

  const targets = (data ?? []) as Array<
    { push_token: string; title: string; body: string }
  >;
  // Not an error, and the commonest case early on: a family whose children
  // have not opened the dashboard since this shipped has no address to send
  // to. The message itself is already delivered either way.
  if (targets.length === 0) return reply(200, { sent: 0 });

  let sa: ServiceAccount;
  let token: string;
  try {
    sa = serviceAccount();
    token = await accessToken(sa);
  } catch (e) {
    console.error('the sender could not authenticate to FCM', e);
    return reply(500, {
      error: '알림을 보내지 못했어요.',
      reason: 'sender_unconfigured',
    });
  }

  // One POST per guardian. A family has one or two children in it, so there
  // is nothing to batch and a per-token result is what tells a dead address
  // apart from a broken sender.
  let sent = 0;
  const stale: string[] = [];
  for (const target of targets) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: target.push_token,
            notification: { title: target.title, body: target.body },
            android: {
              // Not HIGH. A message from a parent is worth a buzz now rather
              // than at the next wake-up, but it is not the phone-nobody-is
              // -holding case that bought 소리 울리기 its Doze exemption, and
              // spending that budget on every message is how an app gets its
              // high-priority allowance throttled.
              priority: 'NORMAL',
              // A day. Past that the guardian has either opened the app or
              // the news has stopped being news, and a notification arriving
              // on Thursday about Tuesday is worse than none.
              ttl: '86400s',
              notification: { channel_id: 'family_messages' },
            },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
      continue;
    }
    const failed = await res.json();
    const status = failed?.error?.details?.[0]?.errorCode ??
      failed?.error?.status;
    // A token that died with a reinstall. The guardian's next dashboard open
    // writes a fresh one, so it fixes itself; it is reported rather than
    // treated as a failure of the send.
    if (status === 'UNREGISTERED' || status === 'NOT_FOUND') {
      stale.push(status);
      continue;
    }
    console.error('fcm rejected a message notification', failed);
  }

  // Never an error status. The message is in the conversation whatever
  // happened here, and the parent's phone must not show them a failure for
  // something that did not fail.
  return reply(200, { sent, stale: stale.length });
});
