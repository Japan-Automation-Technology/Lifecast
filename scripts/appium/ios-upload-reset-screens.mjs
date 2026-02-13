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

async function findElement(sessionId, using, value) {
  const out = await http('POST', `${APPIUM_URL}/session/${sessionId}/element`, { using, value });
  const el = out?.value;
  const id = el?.['element-6066-11e4-a52e-4f735466cecf'] || el?.ELEMENT;
  if (!id) throw new Error(`Element not found: ${using}=${value}`);
  return id;
}

async function findByLabels(sessionId, labels) {
  for (const label of labels) {
    const byAccessibility = await maybeFindElement(sessionId, 'accessibility id', label);
    if (byAccessibility) return byAccessibility;
    const byPredicate = await maybeFindElement(
      sessionId,
      '-ios predicate string',
      `name CONTAINS[c] "${label}" OR label CONTAINS[c] "${label}" OR value CONTAINS[c] "${label}"`,
    );
    if (byPredicate) return byPredicate;
  }
  throw new Error(`Element not found with labels: ${labels.join(', ')}`);
}

async function maybeFindElement(sessionId, using, value) {
  try { return await findElement(sessionId, using, value); } catch { return null; }
}

async function click(sessionId, elementId) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/element/${elementId}/click`, {});
}

async function tapAt(sessionId, x, y) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [
      {
        type: 'pointer',
        id: 'finger1',
        parameters: { pointerType: 'touch' },
        actions: [
          { type: 'pointerMove', duration: 0, x, y },
          { type: 'pointerDown', button: 0 },
          { type: 'pause', duration: 80 },
          { type: 'pointerUp', button: 0 },
        ],
      },
    ],
  });
}

async function screenshot(sessionId, filePath) {
  const shot = await http('GET', `${APPIUM_URL}/session/${sessionId}/screenshot`);
  const b64 = shot?.value;
  if (!b64) throw new Error('Screenshot payload missing');
  await fs.writeFile(filePath, Buffer.from(b64, 'base64'));
}

async function wait(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const processingShot = path.join(OUT_DIR, `appium-ios-upload-processing-${ts}.png`);
  const resetShot = path.join(OUT_DIR, `appium-ios-upload-reset-${ts}.png`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, 'utf8'));
  const created = await http('POST', `${APPIUM_URL}/session`, {
    capabilities: { alwaysMatch: caps, firstMatch: [{}] },
  });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  let observed = 'UNKNOWN';
  try {
    await wait(1500);
    // Prefer explicit tab button id/name, then fall back.
    const createTab =
      (await maybeFindElement(sessionId, 'accessibility id', 'plus.square')) ||
      (await maybeFindElement(sessionId, '-ios predicate string', `type == "XCUIElementTypeButton" AND (name == "plus.square" OR label == "Create")`)) ||
      (await maybeFindElement(sessionId, 'accessibility id', 'Create'));
    if (createTab) {
      await click(sessionId, createTab);
    } else {
      const rectResp = await http('GET', `${APPIUM_URL}/session/${sessionId}/window/rect`);
      const rect = rectResp?.value || {};
      const w = Number(rect.width || 390);
      const h = Number(rect.height || 844);
      await tapAt(sessionId, Math.floor(w * 0.5), Math.floor(h - 34));
    }
    await wait(1000);

    let startUpload = null;
    for (let i = 0; i < 12; i += 1) {
      startUpload = await maybeFindElement(sessionId, 'accessibility id', 'Start Upload');
      if (!startUpload) {
        startUpload = await maybeFindElement(sessionId, '-ios predicate string', `name == "Start Upload" OR label == "Start Upload"`);
      }
      if (startUpload) break;
      await wait(400);
    }
    if (!startUpload) {
      const debugShot = path.join(OUT_DIR, `appium-ios-debug-before-start-${ts}.png`);
      const srcResp = await http('GET', `${APPIUM_URL}/session/${sessionId}/source`);
      const src = srcResp?.value || '';
      const srcPath = path.join(OUT_DIR, `appium-ios-debug-before-start-${ts}.xml`);
      await screenshot(sessionId, debugShot);
      await fs.writeFile(srcPath, String(src), 'utf8');
      throw new Error(`Element not found: Start Upload. debug_screenshot=${debugShot} debug_source=${srcPath}`);
    }
    await click(sessionId, startUpload);

    for (let i = 0; i < 35; i += 1) {
      if (await maybeFindElement(sessionId, 'accessibility id', 'PROCESSING')) { observed = 'PROCESSING'; break; }
      if (await maybeFindElement(sessionId, 'accessibility id', 'READY')) { observed = 'READY'; break; }
      if (await maybeFindElement(sessionId, 'accessibility id', 'FAILED')) { observed = 'FAILED'; break; }
      await wait(500);
    }

    await screenshot(sessionId, processingShot);

    const resetBtn = await findByLabels(sessionId, ['Reset']);
    await click(sessionId, resetBtn);
    await wait(700);

    await screenshot(sessionId, resetShot);

    console.log(JSON.stringify({
      session_id: sessionId,
      observed_state_before_reset: observed,
      processing_screenshot: processingShot,
      reset_screenshot: resetShot,
    }, null, 2));
  } finally {
    try { await http('DELETE', `${APPIUM_URL}/session/${sessionId}`); } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
