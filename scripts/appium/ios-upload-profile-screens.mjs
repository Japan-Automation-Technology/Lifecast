#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";

const APPIUM_URL = process.env.LIFECAST_APPIUM_SERVER_URL || "http://127.0.0.1:4723";
const CAPS_PATH =
  process.env.LIFECAST_CAPABILITIES_CONFIG || path.join(process.env.HOME || "", ".codex/capabilities/lifecast-ios.json");
const OUT_DIR = process.env.LIFECAST_APPIUM_OUT_DIR || "/Users/takeshi/Desktop/lifecast/.tmp";

async function http(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await res.text();
  let json = null;
  try {
    json = txt ? JSON.parse(txt) : null;
  } catch {}
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

async function findByLabels(sessionId, labels) {
  for (const label of labels) {
    const byAcc = await maybeFindElement(sessionId, "accessibility id", label);
    if (byAcc) return byAcc;
    const byPredicate = await maybeFindElement(
      sessionId,
      "-ios predicate string",
      `name CONTAINS[c] "${label}" OR label CONTAINS[c] "${label}" OR value CONTAINS[c] "${label}"`,
    );
    if (byPredicate) return byPredicate;
  }
  return null;
}

async function click(sessionId, elementId) {
  await http("POST", `${APPIUM_URL}/session/${sessionId}/element/${elementId}/click`, {});
}

async function screenshot(sessionId, filePath) {
  const shot = await http("GET", `${APPIUM_URL}/session/${sessionId}/screenshot`);
  const b64 = shot?.value;
  if (!b64) throw new Error("Screenshot payload missing");
  await fs.writeFile(filePath, Buffer.from(b64, "base64"));
}

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const readyShot = path.join(OUT_DIR, `appium-ios-upload-ready-${ts}.png`);
  const meShot = path.join(OUT_DIR, `appium-ios-me-posted-${ts}.png`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, "utf8"));
  const created = await http("POST", `${APPIUM_URL}/session`, {
    capabilities: { alwaysMatch: caps, firstMatch: [{}] },
  });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  let observed = "UNKNOWN";
  try {
    await wait(1200);
    const createTab = await findByLabels(sessionId, ["Create", "plus.square"]);
    if (!createTab) throw new Error("Create tab not found");
    await click(sessionId, createTab);
    await wait(700);

    const reset = await findByLabels(sessionId, ["Reset"]);
    if (reset) {
      await click(sessionId, reset);
      await wait(300);
    }

    const startUpload = await findByLabels(sessionId, ["Start Upload"]);
    if (!startUpload) throw new Error("Start Upload not found");
    await click(sessionId, startUpload);

    for (let i = 0; i < 100; i += 1) {
      if (await maybeFindElement(sessionId, "accessibility id", "READY")) {
        observed = "READY";
        break;
      }
      if (await maybeFindElement(sessionId, "accessibility id", "FAILED")) {
        observed = "FAILED";
        break;
      }
      await wait(1000);
    }

    await screenshot(sessionId, readyShot);

    const meTab = await findByLabels(sessionId, ["Me", "person"]);
    if (!meTab) throw new Error("Me tab not found");
    await click(sessionId, meTab);
    await wait(800);

    const postedTab = await findByLabels(sessionId, ["Posted"]);
    if (postedTab) {
      await click(sessionId, postedTab);
      await wait(500);
    }

    const refresh = await findByLabels(sessionId, ["Refresh"]);
    if (refresh) {
      await click(sessionId, refresh);
      await wait(1500);
    }

    const posted = await findByLabels(sessionId, ["Posted videos", ".mov", ".mp4", "Refresh"]);
    const postedDetected = Boolean(posted);
    await screenshot(sessionId, meShot);

    console.log(
      JSON.stringify(
        {
          session_id: sessionId,
          observed_state: observed,
          posted_detected: postedDetected,
          ready_screenshot: readyShot,
          me_screenshot: meShot,
        },
        null,
        2,
      ),
    );
  } finally {
    try {
      await http("DELETE", `${APPIUM_URL}/session/${sessionId}`);
    } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
