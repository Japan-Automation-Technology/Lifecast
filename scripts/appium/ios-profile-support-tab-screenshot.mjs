#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";

const APPIUM_URL = process.env.LIFECAST_APPIUM_SERVER_URL || "http://127.0.0.1:4723";
const CAPS_PATH = process.env.LIFECAST_CAPABILITIES_CONFIG || path.join(process.env.HOME || "", ".codex/capabilities/lifecast-ios.json");
const OUT_DIR = process.env.LIFECAST_APPIUM_OUT_DIR || "/Users/takeshi/Desktop/lifecast/.tmp";

async function http(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await res.text();
  let json = null;
  try { json = txt ? JSON.parse(txt) : null; } catch {}
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url} :: ${txt}`);
  return json;
}

async function maybeFindElement(sessionId, using, value) {
  try {
    const out = await http("POST", `${APPIUM_URL}/session/${sessionId}/element`, { using, value });
    const el = out?.value;
    return el?.["element-6066-11e4-a52e-4f735466cecf"] || el?.ELEMENT || null;
  } catch {
    return null;
  }
}

async function click(sessionId, elementId) {
  await http("POST", `${APPIUM_URL}/session/${sessionId}/element/${elementId}/click`, {});
}

async function sourceText(sessionId) {
  const out = await http("GET", `${APPIUM_URL}/session/${sessionId}/source`);
  return String(out?.value || "");
}

async function screenshot(sessionId, filePath) {
  const shot = await http("GET", `${APPIUM_URL}/session/${sessionId}/screenshot`);
  const b64 = shot?.value;
  await fs.writeFile(filePath, Buffer.from(b64, "base64"));
}

async function wait(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const supportShot = path.join(OUT_DIR, `appium-ios-profile-support-tab-${ts}.png`);
  const failShot = path.join(OUT_DIR, `appium-ios-profile-support-tab-failure-${ts}.png`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, "utf8"));
  caps["appium:noReset"] = true;
  const created = await http("POST", `${APPIUM_URL}/session`, { capabilities: { alwaysMatch: caps, firstMatch: [{}] } });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error("Failed to create appium session");

  try {
    await wait(1200);
    const meTab =
      (await maybeFindElement(sessionId, "accessibility id", "person.fill")) ||
      (await maybeFindElement(sessionId, "accessibility id", "Me")) ||
      (await maybeFindElement(sessionId, "accessibility id", "person"));
    if (!meTab) {
      await screenshot(sessionId, failShot);
      throw new Error(`Me tab not found. screenshot=${failShot}`);
    }
    await click(sessionId, meTab);
    await wait(900);

    const supportTab = await maybeFindElement(sessionId, "accessibility id", "profile-tab-support");
    if (!supportTab) {
      await screenshot(sessionId, failShot);
      throw new Error(`Support tab not found. screenshot=${failShot}`);
    }
    await click(sessionId, supportTab);
    await wait(1200);

    const src = await sourceText(sessionId);
    const supportTabVisible = src.includes("profile-tab-support");
    const contentVisible = src.includes("No supported projects yet") || src.includes("supporters") || src.includes("Supported");
    if (!supportTabVisible || !contentVisible) {
      await screenshot(sessionId, failShot);
      throw new Error(`Support tab content not visible. screenshot=${failShot}`);
    }

    await screenshot(sessionId, supportShot);
    console.log(JSON.stringify({
      session_id: sessionId,
      support_tab_opened: true,
      screenshot: supportShot
    }, null, 2));
  } finally {
    try { await http("DELETE", `${APPIUM_URL}/session/${sessionId}`); } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
