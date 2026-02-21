#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

const APPIUM_URL = process.env.LIFECAST_APPIUM_SERVER_URL || 'http://127.0.0.1:4723';
const CAPS_PATH = process.env.LIFECAST_CAPABILITIES_CONFIG || path.join(process.env.HOME || '', '.codex/capabilities/lifecast-ios.json');
const SCREENSHOT_PATH = process.env.LIFECAST_APPIUM_SCREENSHOT_PATH || '/Users/takeshi/Desktop/lifecast/.tmp/appium-ios-create.png';
const SOURCE_PATH = process.env.LIFECAST_APPIUM_SOURCE_PATH || '/Users/takeshi/Desktop/lifecast/.tmp/appium-ios-create.xml';

async function http(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await res.text();
  let json = null;
  try { json = txt ? JSON.parse(txt) : null; } catch {}
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${url} :: ${txt}`);
  }
  return json;
}

async function findElement(sessionId, using, value) {
  const out = await http('POST', `${APPIUM_URL}/session/${sessionId}/element`, { using, value });
  const element = out?.value;
  const elementId = element?.['element-6066-11e4-a52e-4f735466cecf'] || element?.ELEMENT;
  if (!elementId) {
    throw new Error(`Element not found: ${using}=${value}`);
  }
  return elementId;
}

async function maybeFindElement(sessionId, using, value) {
  try {
    return await findElement(sessionId, using, value);
  } catch {
    return null;
  }
}

async function click(sessionId, elementId) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/element/${elementId}/click`, {});
}

async function pause(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function sourceText(sessionId) {
  const out = await http('GET', `${APPIUM_URL}/session/${sessionId}/source`);
  return String(out?.value || '');
}

async function saveScreenshot(sessionId, filePath) {
  const shot = await http('GET', `${APPIUM_URL}/session/${sessionId}/screenshot`);
  const b64 = shot?.value;
  if (!b64) return;
  await fs.writeFile(filePath, Buffer.from(b64, 'base64'));
}

async function main() {
  if (process.env.LIFECAST_ALLOW_CREATE_UPLOAD_SMOKE !== '1') {
    throw new Error(
      'Deprecated flow: ios-smoke.mjs intentionally disabled by default. Use smoke:ios:upload-profile or smoke:ios:posted-feed for UI checks. If you must run create-upload smoke, set LIFECAST_ALLOW_CREATE_UPLOAD_SMOKE=1.'
    );
  }

  await fs.mkdir(path.dirname(SCREENSHOT_PATH), { recursive: true });

  const capsRaw = await fs.readFile(CAPS_PATH, 'utf8');
  const caps = JSON.parse(capsRaw);

  const createSession = await http('POST', `${APPIUM_URL}/session`, {
    capabilities: {
      alwaysMatch: caps,
      firstMatch: [{}],
    },
  });

  const sessionId = createSession?.value?.sessionId || createSession?.sessionId;
  if (!sessionId) {
    throw new Error(`Failed to create session: ${JSON.stringify(createSession)}`);
  }

  let failed = false;
  try {
    // Bottom tab: Create
    const createTab =
      (await maybeFindElement(sessionId, 'accessibility id', 'Create')) ||
      (await maybeFindElement(sessionId, 'accessibility id', 'plus.square.fill')) ||
      (await maybeFindElement(
        sessionId,
        '-ios predicate string',
        'type == "XCUIElementTypeButton" AND (name CONTAINS[c] "Create" OR label CONTAINS[c] "Create")',
      ));
    if (!createTab) {
      throw new Error('Create tab not found');
    }
    await click(sessionId, createTab);
    await pause(1200);

    const chooseButton =
      (await maybeFindElement(sessionId, 'accessibility id', 'Choose Video')) ||
      (await maybeFindElement(
        sessionId,
        '-ios predicate string',
        'type == "XCUIElementTypeButton" AND (name CONTAINS[c] "Choose Video" OR label CONTAINS[c] "Choose Video")',
      ));
    if (!chooseButton) {
      await saveScreenshot(sessionId, SCREENSHOT_PATH);
      throw new Error(`Choose Video button not found. screenshot=${SCREENSHOT_PATH}`);
    }
    await click(sessionId, chooseButton);
    await pause(900);

    const src = await sourceText(sessionId);
    const pickerOpened =
      src.includes('Private Access to Photos') ||
      src.includes('Photo Library') ||
      src.includes('Collections') ||
      src.includes('Recents') ||
      src.includes('Videos');
    if (!pickerOpened) {
      await fs.writeFile(SOURCE_PATH, src, 'utf8');
      await saveScreenshot(sessionId, SCREENSHOT_PATH);
      throw new Error(`Video picker did not open from Create tab. source=${SOURCE_PATH} screenshot=${SCREENSHOT_PATH}`);
    }

    const shot = await http('GET', `${APPIUM_URL}/session/${sessionId}/screenshot`);
    const b64 = shot?.value;
    if (!b64) {
      throw new Error('Screenshot payload missing');
    }
    await fs.writeFile(SCREENSHOT_PATH, Buffer.from(b64, 'base64'));

    const result = {
      appium_url: APPIUM_URL,
      session_id: sessionId,
      assertions: {
        create_tab_opened: true,
        choose_video_button_tapped: true,
        video_picker_opened: true,
      },
      screenshot: SCREENSHOT_PATH,
    };
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    failed = true;
    console.error('[ios-smoke] failed', error instanceof Error ? error.message : String(error));
    throw error;
  } finally {
    try {
      await http('DELETE', `${APPIUM_URL}/session/${sessionId}`);
    } catch (e) {
      if (!failed) {
        console.warn('[ios-smoke] failed to close session', e instanceof Error ? e.message : String(e));
      }
    }
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
