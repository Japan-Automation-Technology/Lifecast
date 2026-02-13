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

async function tapAt(sessionId, x, y) {
  await http("POST", `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [
      {
        type: "pointer",
        id: "finger1",
        parameters: { pointerType: "touch" },
        actions: [
          { type: "pointerMove", duration: 0, x, y },
          { type: "pointerDown", button: 0 },
          { type: "pause", duration: 80 },
          { type: "pointerUp", button: 0 },
        ],
      },
    ],
  });
}

async function getText(sessionId, elementId) {
  const result = await http("GET", `${APPIUM_URL}/session/${sessionId}/element/${elementId}/text`);
  return String(result?.value ?? "");
}

async function swipeUp(sessionId) {
  const rectResp = await http("GET", `${APPIUM_URL}/session/${sessionId}/window/rect`);
  const rect = rectResp?.value || {};
  const w = Number(rect.width || 390);
  const h = Number(rect.height || 844);
  const centerX = Math.floor(w * 0.5);
  const startY = Math.floor(h * 0.72);
  const endY = Math.floor(h * 0.26);

  await http("POST", `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [
      {
        type: "pointer",
        id: "finger1",
        parameters: { pointerType: "touch" },
        actions: [
          { type: "pointerMove", duration: 0, x: centerX, y: startY },
          { type: "pointerDown", button: 0 },
          { type: "pointerMove", duration: 260, x: centerX, y: endY },
          { type: "pointerUp", button: 0 },
        ],
      },
    ],
  });
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
  const gridShot = path.join(OUT_DIR, `appium-ios-posted-grid-${ts}.png`);
  const feedShot = path.join(OUT_DIR, `appium-ios-posted-feed-${ts}.png`);
  const swipeShot = path.join(OUT_DIR, `appium-ios-posted-feed-swipe-${ts}.png`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, "utf8"));
  caps["appium:noReset"] = false;
  const created = await http("POST", `${APPIUM_URL}/session`, {
    capabilities: { alwaysMatch: caps, firstMatch: [{}] },
  });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  try {
    await wait(1200);
    const meTab = await findByLabels(sessionId, ["Me", "person"]);
    if (!meTab) throw new Error("Me tab not found");
    await click(sessionId, meTab);
    await wait(700);

    const postedTab = await findByLabels(sessionId, ["Posts", "Posted"]);
    if (postedTab) {
      await click(sessionId, postedTab);
    } else {
      const rectResp = await http("GET", `${APPIUM_URL}/session/${sessionId}/window/rect`);
      const rect = rectResp?.value || {};
      const w = Number(rect.width || 390);
      const h = Number(rect.height || 844);
      await tapAt(sessionId, Math.floor(w * 0.50), Math.floor(h * 0.36));
    }
    await wait(700);

    await screenshot(sessionId, gridShot);

    const firstVideo =
      (await maybeFindElement(sessionId, "accessibility id", "posted-grid-video-0")) ||
      (await maybeFindElement(sessionId, "accessibility id", "Open posted 0")) ||
      (await maybeFindElement(
        sessionId,
        "-ios predicate string",
        `name CONTAINS[c] "Open posted 0" OR label CONTAINS[c] "Open posted 0"`,
      )) ||
      (await maybeFindElement(
        sessionId,
        "-ios predicate string",
        `name CONTAINS[c] ".mov" OR label CONTAINS[c] ".mov"`,
      ));
    if (firstVideo) {
      await click(sessionId, firstVideo);
    } else {
      const rectResp = await http("GET", `${APPIUM_URL}/session/${sessionId}/window/rect`);
      const rect = rectResp?.value || {};
      const w = Number(rect.width || 390);
      const h = Number(rect.height || 844);
      await tapAt(sessionId, Math.floor(w * 0.28), Math.floor(h * 0.66));
    }
    await wait(900);

    const feed = await maybeFindElement(sessionId, "accessibility id", "posted-feed-view");
    const backFeed = await maybeFindElement(sessionId, "accessibility id", "posted-feed-back");
    const closeFeed = await findByLabels(sessionId, ["Close"]);
    if (!feed && !backFeed && !closeFeed) {
      const srcResp = await http("GET", `${APPIUM_URL}/session/${sessionId}/source`);
      const srcPath = path.join(OUT_DIR, `appium-ios-posted-feed-failure-source-${ts}.xml`);
      await fs.writeFile(srcPath, String(srcResp?.value || ""), "utf8");
      const failShot = path.join(OUT_DIR, `appium-ios-posted-feed-failure-${ts}.png`);
      await screenshot(sessionId, failShot);
      throw new Error(`posted feed view not found after tap. source=${srcPath} screenshot=${failShot}`);
    }

    const counter = await maybeFindElement(sessionId, "accessibility id", "posted-feed-counter");
    const before = counter ? await getText(sessionId, counter) : "";
    await screenshot(sessionId, feedShot);

    await swipeUp(sessionId);
    await wait(900);
    const counterAfter = counter ? await getText(sessionId, counter) : "";
    await screenshot(sessionId, swipeShot);

    console.log(
      JSON.stringify(
        {
          session_id: sessionId,
          opened_feed: true,
          has_back_button: Boolean(backFeed),
          counter_before_swipe: before,
          counter_after_swipe: counterAfter,
          grid_screenshot: gridShot,
          feed_screenshot: feedShot,
          swipe_screenshot: swipeShot,
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
