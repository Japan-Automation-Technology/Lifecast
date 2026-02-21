#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

const APPIUM_URL = process.env.LIFECAST_APPIUM_SERVER_URL || 'http://127.0.0.1:4723';
const CAPS_PATH = process.env.LIFECAST_CAPABILITIES_CONFIG || path.join(process.env.HOME || '', '.codex/capabilities/lifecast-ios.json');
const OUT_DIR = process.env.LIFECAST_APPIUM_OUT_DIR || '/Users/takeshi/Desktop/lifecast/.tmp';

async function http(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
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

async function screenshot(sessionId, filePath) {
  const shot = await http('GET', `${APPIUM_URL}/session/${sessionId}/screenshot`);
  const b64 = shot?.value;
  await fs.writeFile(filePath, Buffer.from(b64, 'base64'));
}

async function swipe(sessionId, fromX, fromY, toX, toY, duration = 220) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [{
      type: 'pointer',
      id: 'finger1',
      parameters: { pointerType: 'touch' },
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

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function extractPanelFraction(src) {
  const m = src.match(/([0-9]+)\s*\/\s*([0-9]+)/);
  if (!m) return null;
  return { current: Number(m[1]), total: Number(m[2]) };
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const overviewShot = path.join(OUT_DIR, `appium-ios-home-panel-overview-${ts}.png`);
  const secondShot = path.join(OUT_DIR, `appium-ios-home-panel-next-${ts}.png`);
  const failShot = path.join(OUT_DIR, `appium-ios-home-panel-failure-${ts}.png`);
  const failSource = path.join(OUT_DIR, `appium-ios-home-panel-failure-${ts}.xml`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, 'utf8'));
  caps['appium:noReset'] = true;
  const created = await http('POST', `${APPIUM_URL}/session`, { capabilities: { alwaysMatch: caps, firstMatch: [{}] } });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  try {
    await wait(1400);

    // Dismiss sign-in sheet if it is open
    const closeSignIn =
      (await maybeFindElement(sessionId, 'accessibility id', 'Close')) ||
      (await maybeFindElement(sessionId, '-ios predicate string', 'type == "XCUIElementTypeButton" AND (name == "Close" OR label == "Close")'));
    if (closeSignIn) {
      await click(sessionId, closeSignIn);
      await wait(700);
    }

    // Ensure home tab is active
    const homeTab = await maybeFindElement(sessionId, 'accessibility id', 'house.fill');
    if (homeTab) {
      await click(sessionId, homeTab);
      await wait(500);
    }

    // Open project panel (swipe left on feed video)
    await swipe(sessionId, 320, 360, 70, 360, 220);
    await wait(1100);
    let src = await sourceText(sessionId);

    const openedPanel =
      src.includes('Project Overview') ||
      src.includes('Plan 1 /') ||
      src.includes('Plan 2 /') ||
      src.includes(' / 2') ||
      src.includes(' / 3');
    if (!openedPanel) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Project overview panel not opened. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, overviewShot);

    const firstFraction = extractPanelFraction(src);

    // Move to next panel page (first plan) if available
    let movedToPlanPage = false;
    let secondFraction = firstFraction;
    for (let i = 0; i < 3; i += 1) {
      await swipe(sessionId, 320, 360, 70, 360, 260);
      await wait(900);
      src = await sourceText(sessionId);
      movedToPlanPage = src.includes('Plan 1 /') || src.includes('Plan 2 /');
      secondFraction = extractPanelFraction(src);
      const progressed =
        firstFraction && secondFraction &&
        secondFraction.total > 1 &&
        secondFraction.current > firstFraction.current;
      if (movedToPlanPage || progressed) break;
    }
    const progressedByFraction =
      firstFraction && secondFraction &&
      secondFraction.total > 1 &&
      secondFraction.current > firstFraction.current;

    if (!(movedToPlanPage || progressedByFraction)) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Panel did not move to plan page. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, secondShot);

    console.log(JSON.stringify({
      session_id: sessionId,
      project_overview_opened: true,
      moved_to_plan_page: true,
      overview_screenshot: overviewShot,
      next_page_screenshot: secondShot,
    }, null, 2));
  } finally {
    try { await http('DELETE', `${APPIUM_URL}/session/${sessionId}`); } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
