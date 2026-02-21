#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

const APPIUM_URL = process.env.LIFECAST_APPIUM_SERVER_URL || 'http://127.0.0.1:4723';
const CAPS_PATH = process.env.LIFECAST_CAPABILITIES_CONFIG || path.join(process.env.HOME || '', '.codex/capabilities/lifecast-ios.json');
const OUT_DIR = process.env.LIFECAST_APPIUM_OUT_DIR || '/Users/takeshi/Desktop/lifecast/.tmp';

async function http(method, url, body) {
  const res = await fetch(url, { method, headers: { 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const txt = await res.text();
  let json = null;
  try { json = txt ? JSON.parse(txt) : null; } catch {}
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url} :: ${txt}`);
  return json;
}

async function sourceText(sessionId) {
  const out = await http('GET', `${APPIUM_URL}/session/${sessionId}/source`);
  return String(out?.value || '');
}

async function maybeFindElement(sessionId, using, value) {
  try {
    const out = await http('POST', `${APPIUM_URL}/session/${sessionId}/element`, { using, value });
    const el = out?.value;
    return el?.['element-6066-11e4-a52e-4f735466cecf'] || el?.ELEMENT || null;
  } catch {
    return null;
  }
}

async function click(sessionId, elementId) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/element/${elementId}/click`, {});
}

async function swipe(sessionId, fromX, fromY, toX, toY, duration = 240) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [{
      type: 'pointer', id: 'finger1', parameters: { pointerType: 'touch' },
      actions: [
        { type: 'pointerMove', duration: 0, x: fromX, y: fromY },
        { type: 'pointerDown', button: 0 },
        { type: 'pause', duration: 30 },
        { type: 'pointerMove', duration, x: toX, y: toY },
        { type: 'pointerUp', button: 0 },
      ],
    }],
  });
}

async function screenshot(sessionId, filePath) {
  const shot = await http('GET', `${APPIUM_URL}/session/${sessionId}/screenshot`);
  await fs.writeFile(filePath, Buffer.from(shot?.value, 'base64'));
}

async function wait(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const beforeShot = path.join(OUT_DIR, `appium-ios-home-panel-close-before-${ts}.png`);
  const afterShot = path.join(OUT_DIR, `appium-ios-home-panel-close-after-${ts}.png`);
  const failSource = path.join(OUT_DIR, `appium-ios-home-panel-close-fail-${ts}.xml`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, 'utf8'));
  caps['appium:noReset'] = true;
  const created = await http('POST', `${APPIUM_URL}/session`, { capabilities: { alwaysMatch: caps, firstMatch: [{}] } });
  const sessionId = created?.value?.sessionId || created?.sessionId;

  try {
    await wait(1300);

    // Dismiss sign-in sheet if visible
    const closeSignIn =
      (await maybeFindElement(sessionId, 'accessibility id', 'Close')) ||
      (await maybeFindElement(sessionId, '-ios predicate string', 'type == "XCUIElementTypeButton" AND (name == "Close" OR label == "Close")'));
    if (closeSignIn) {
      await click(sessionId, closeSignIn);
      await wait(700);
    }

    // Ensure home tab
    const homeTab = await maybeFindElement(sessionId, 'accessibility id', 'house.fill');
    if (homeTab) {
      await click(sessionId, homeTab);
      await wait(500);
    }

    // open panel
    await swipe(sessionId, 320, 360, 70, 360, 220);
    await wait(900);
    let src = await sourceText(sessionId);
    if (!src.includes('Project Overview')) {
      throw new Error('Project panel not opened');
    }
    await screenshot(sessionId, beforeShot);

    // close panel from overview (right swipe)
    await swipe(sessionId, 70, 360, 320, 360, 240);
    await wait(900);
    src = await sourceText(sessionId);
    await screenshot(sessionId, afterShot);

    const closed = !src.includes('Project Overview') && !src.includes('Plan 1 /');
    if (!closed) {
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Panel did not close from overview. source=${failSource} after=${afterShot}`);
    }

    console.log(JSON.stringify({ panel_closed_from_overview: true, before_screenshot: beforeShot, after_screenshot: afterShot }, null, 2));
  } finally {
    try { await http('DELETE', `${APPIUM_URL}/session/${sessionId}`); } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
