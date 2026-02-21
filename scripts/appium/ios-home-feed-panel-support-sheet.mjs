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
  await fs.writeFile(filePath, Buffer.from(shot?.value, 'base64'));
}

async function swipe(sessionId, fromX, fromY, toX, toY, duration = 240) {
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

async function tap(sessionId, x, y) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [{
      type: 'pointer',
      id: 'finger1',
      parameters: { pointerType: 'touch' },
      actions: [
        { type: 'pointerMove', duration: 0, x, y },
        { type: 'pointerDown', button: 0 },
        { type: 'pause', duration: 45 },
        { type: 'pointerUp', button: 0 },
      ],
    }],
  });
}

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function hasVisible(source, label) {
  return source.includes(`name=\"${label}\"`) && source.includes('visible="true"');
}

async function ensurePanelClosed(sessionId) {
  for (let i = 0; i < 3; i += 1) {
    const src = await sourceText(sessionId);
    if (!src.includes('Project Overview') && !src.includes('Plan 1 /')) return;
    await swipe(sessionId, 70, 360, 330, 360, 220);
    await wait(700);
  }
}

async function ensureOverviewVisible(sessionId) {
  for (let i = 0; i < 4; i += 1) {
    const src = await sourceText(sessionId);
    if (hasVisible(src, 'Project Overview')) return true;
    await swipe(sessionId, 70, 360, 330, 360, 220);
    await wait(700);
  }
  return false;
}

async function closeSupportSheetIfOpen(sessionId) {
  const closeButton =
    (await maybeFindElement(sessionId, 'accessibility id', 'Close')) ||
    (await maybeFindElement(sessionId, '-ios predicate string', 'type == "XCUIElementTypeButton" AND (name == "Close" OR label == "Close")'));
  if (closeButton) {
    await click(sessionId, closeButton);
    await wait(800);
  }
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const overviewShot = path.join(OUT_DIR, `appium-ios-home-panel-tap-overview-${ts}.png`);
  const planShot = path.join(OUT_DIR, `appium-ios-home-panel-tap-plan-${ts}.png`);
  const failShot = path.join(OUT_DIR, `appium-ios-home-panel-tap-fail-${ts}.png`);
  const failSource = path.join(OUT_DIR, `appium-ios-home-panel-tap-fail-${ts}.xml`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, 'utf8'));
  caps['appium:noReset'] = true;

  const created = await http('POST', `${APPIUM_URL}/session`, { capabilities: { alwaysMatch: caps, firstMatch: [{}] } });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  try {
    await wait(1300);

    const homeTab = await maybeFindElement(sessionId, 'accessibility id', 'house.fill');
    if (homeTab) {
      await click(sessionId, homeTab);
      await wait(500);
    }

    await ensurePanelClosed(sessionId);

    await swipe(sessionId, 330, 360, 70, 360, 220);
    await wait(900);

    const isOverviewVisible = await ensureOverviewVisible(sessionId);
    let src = await sourceText(sessionId);
    if (!isOverviewVisible || !src.includes('Project Overview')) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Project panel overview not visible. source=${failSource} screenshot=${failShot}`);
    }

    // Overview body area tap (image/text region)
    await tap(sessionId, 190, 320);
    await wait(1200);
    src = await sourceText(sessionId);

    if (!(src.includes('1. Select plan') || src.includes('2. Confirm'))) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Overview body tap did not open support sheet. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, overviewShot);
    await closeSupportSheetIfOpen(sessionId);

    // Move to first plan page and tap plan body area
    await swipe(sessionId, 330, 360, 70, 360, 260);
    await wait(900);
    src = await sourceText(sessionId);
    if (src.includes('1. Select plan') || src.includes('2. Confirm')) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Swipe should not open support sheet. source=${failSource} screenshot=${failShot}`);
    }
    if (!src.includes('Plan 1 /') && !src.includes('Plan 2 /')) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Plan page not visible. source=${failSource} screenshot=${failShot}`);
    }

    await tap(sessionId, 190, 410);
    await wait(1200);
    src = await sourceText(sessionId);

    if (!src.includes('2. Confirm')) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Plan body tap did not open confirm step. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, planShot);

    console.log(JSON.stringify({
      session_id: sessionId,
      overview_body_tap_opened_support_sheet: true,
      plan_body_tap_opened_confirm_sheet: true,
      overview_screenshot: overviewShot,
      plan_screenshot: planShot,
    }, null, 2));
  } finally {
    try { await http('DELETE', `${APPIUM_URL}/session/${sessionId}`); } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
