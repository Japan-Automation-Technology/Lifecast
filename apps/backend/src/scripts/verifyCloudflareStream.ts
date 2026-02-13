import { loadEnv } from "../env.js";

loadEnv();

function required(name: string) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`missing env: ${name}`);
  }
  return value.trim();
}

async function main() {
  const accountId = required("CF_ACCOUNT_ID");
  const token = required("CF_STREAM_TOKEN");
  const signingKeyId = required("CF_STREAM_SIGNING_KEY_ID");
  const signingKeyBase64 = required("CF_STREAM_SIGNING_KEY_BASE64");

  let signingPem = "";
  try {
    signingPem = Buffer.from(signingKeyBase64, "base64").toString("utf8");
  } catch {
    throw new Error("CF_STREAM_SIGNING_KEY_BASE64 is not valid base64");
  }
  if (!signingPem.includes("BEGIN") || !signingPem.includes("PRIVATE KEY")) {
    throw new Error("CF_STREAM_SIGNING_KEY_BASE64 decoded value does not look like a PEM private key");
  }

  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${accountId}/stream?limit=1`;
  const res = await fetch(endpoint, {
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });

  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    throw new Error(`Cloudflare API returned non-JSON response (${res.status})`);
  }

  const success = Boolean(json?.success);
  if (!res.ok || !success) {
    const first = Array.isArray(json?.errors) && json.errors.length > 0 ? json.errors[0] : null;
    const msg = first?.message || `Cloudflare API error (${res.status})`;
    throw new Error(msg);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        account_id_configured: true,
        stream_token_configured: true,
        signing_key_id_configured: Boolean(signingKeyId),
        signing_key_pem_decoded: true,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(
    JSON.stringify(
      {
        ok: false,
        message: error instanceof Error ? error.message : String(error),
      },
      null,
      2,
    ),
  );
  process.exit(1);
});

