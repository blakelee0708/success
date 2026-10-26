// 소리 울리기's sending half.
//
// This function is a **sender and nothing else**. Every question about
// whether a ring is allowed — is the caller a guardian of this parent, is
// there a subscription, did the senior agree, which phone, what does it say —
// is answered by `request_phone_ring` in SQL, next to the rules it belongs
// with. See `20261026030000_request_ring.sql`.
//
// That split is deliberate. The gate is then checkable from a development
// environment that cannot deploy or run this file
// (`tool/verify_supabase_ring.py`), and the subscription rule does not end up
// living in two languages with one copy nobody can test.
//
// Deploy:
//   supabase functions deploy ring-phone --project-ref <ref>
// It needs one secret, FCM_SERVICE_ACCOUNT — the whole service-account JSON
// from Firebase console → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성.

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

  // The caller's own JWT, forwarded. The gate reads `auth.uid()`, so a
  // service-role call would have no caller to check and would answer for
  // nobody — the service key is held for the one step that needs it, which is
  // talking to Google.
  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply(401, { error: '로그인이 필요해요.' });

  let seniorProfileId: string;
  let message: string | null;
  try {
    const body = await req.json();
    seniorProfileId = body.senior_profile_id;
    message = body.message ?? null;
    if (!seniorProfileId) throw new Error('senior_profile_id is required');
  } catch (_) {
    return reply(400, { error: 'senior_profile_id is required' });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data, error } = await supabase.rpc('request_phone_ring', {
    p_senior_profile_id: seniorProfileId,
    p_message: message,
  });
  // Every refusal — not a guardian, no subscription, consent not given — is
  // the gate's, and its own wording is what the guardian should read.
  if (error) return reply(403, { error: error.message });

  const target = data?.[0];
  // Not an error. The parent's phone has simply never checked in, which the
  // guardian's dashboard already says in its own words.
  if (!target) return reply(200, { delivered: false, reason: 'no_device' });

  const sa = serviceAccount();
  const token = await accessToken(sa);

  // A **data** message, not a notification. A notification is drawn by
  // Android in the status bar, which is the one place a senior who cannot
  // find their own contacts app will not look — and it would need
  // POST_NOTIFICATIONS on Android 13+. What arrives is drawn by the app as a
  // full-screen layer that says who is asking before it says anything else.
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
          data: {
            type: 'ring',
            from: target.from_name,
            message: target.line,
          },
          android: {
            // The point of the feature is a phone nobody is holding, so it
            // has to be delivered now rather than batched with the next time
            // the phone wakes up by itself. High priority is also what buys a
            // temporary exemption from Doze.
            priority: 'HIGH',
            // A ring that arrives an hour late is worse than none: the
            // guardian has long since rung the landline, and the parent is
            // startled by a phone asking them to call about nothing.
            ttl: '300s',
          },
        },
      }),
    },
  );

  const sent = await res.json();
  if (!res.ok) {
    console.error('fcm rejected the send', sent);
    // UNREGISTERED means the token died with a reinstall. The parent's phone
    // writes a fresh one on its next check-in, so this fixes itself and is
    // not worth alarming the guardian about in those words.
    const status = sent?.error?.details?.[0]?.errorCode ?? sent?.error?.status;
    if (status === 'UNREGISTERED' || status === 'NOT_FOUND') {
      return reply(200, { delivered: false, reason: 'stale_token' });
    }
    return reply(502, { error: '부모님 폰에 보내지 못했어요.' });
  }

  return reply(200, { delivered: true });
});
