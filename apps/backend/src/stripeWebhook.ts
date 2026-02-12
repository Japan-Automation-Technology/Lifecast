import { createHmac, timingSafeEqual } from "node:crypto";

function parseStripeSignature(header: string) {
  const parts = header.split(",");
  let timestamp = "";
  const signatures: string[] = [];

  for (const part of parts) {
    const [rawKey, rawValue] = part.split("=");
    const key = rawKey?.trim();
    const value = rawValue?.trim();
    if (!key || !value) continue;
    if (key === "t") timestamp = value;
    if (key === "v1") signatures.push(value);
  }

  return { timestamp, signatures };
}

export function verifyStripeWebhookSignature(input: {
  signatureHeader: string;
  payload: string;
  endpointSecret: string;
}) {
  const { timestamp, signatures } = parseStripeSignature(input.signatureHeader);
  if (!timestamp || signatures.length === 0) {
    return false;
  }

  const signedPayload = `${timestamp}.${input.payload}`;
  const expected = createHmac("sha256", input.endpointSecret).update(signedPayload, "utf8").digest("hex");
  const expectedBuffer = Buffer.from(expected, "utf8");

  for (const candidate of signatures) {
    const candidateBuffer = Buffer.from(candidate, "utf8");
    if (candidateBuffer.length !== expectedBuffer.length) continue;
    if (timingSafeEqual(candidateBuffer, expectedBuffer)) {
      return true;
    }
  }
  return false;
}
