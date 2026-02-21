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

async function setElementValue(sessionId, elementId, text) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/element/${elementId}/value`, {
    text,
    value: Array.from(text),
  });
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

async function doubleTap(sessionId, x, y) {
  await http('POST', `${APPIUM_URL}/session/${sessionId}/actions`, {
    actions: [{
      type: 'pointer',
      id: 'finger1',
      parameters: { pointerType: 'touch' },
      actions: [
        { type: 'pointerMove', duration: 0, x, y },
        { type: 'pointerDown', button: 0 },
        { type: 'pause', duration: 35 },
        { type: 'pointerUp', button: 0 },
        { type: 'pause', duration: 70 },
        { type: 'pointerMove', duration: 0, x, y },
        { type: 'pointerDown', button: 0 },
        { type: 'pause', duration: 35 },
        { type: 'pointerUp', button: 0 },
      ],
    }],
  });
}

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function ensureAuthenticated(sessionId) {
  let src = await sourceText(sessionId);
  if (!src.includes('name="Sign In"') && !src.includes('label="Sign In"')) {
    const supportButton =
      (await maybeFindElement(sessionId, 'accessibility id', 'Support')) ||
      (await maybeFindElement(sessionId, 'accessibility id', 'suit.heart.fill'));
    if (supportButton) {
      await click(sessionId, supportButton);
      await wait(900);
      src = await sourceText(sessionId);
    }
  }
  if (!src.includes('name="Sign In"') && !src.includes('label="Sign In"')) return;

  const signUpTab =
    (await maybeFindElement(sessionId, 'accessibility id', 'Sign up')) ||
    (await maybeFindElement(sessionId, '-ios predicate string', 'type == "XCUIElementTypeButton" AND (name == "Sign up" OR label == "Sign up")'));
  if (signUpTab) {
    await click(sessionId, signUpTab);
    await wait(250);
  }

  const emailField =
    (await maybeFindElement(sessionId, '-ios predicate string', 'type == "XCUIElementTypeTextField" AND (value == "Email" OR name == "Email" OR label == "Email")')) ||
    (await maybeFindElement(sessionId, 'accessibility id', 'Email'));
  const passwordField =
    (await maybeFindElement(sessionId, '-ios predicate string', 'type == "XCUIElementTypeSecureTextField" AND (value == "Password" OR name == "Password" OR label == "Password")')) ||
    (await maybeFindElement(sessionId, 'accessibility id', 'Password'));
  if (!emailField || !passwordField) return;

  const seed = Date.now();
  await setElementValue(sessionId, emailField, `codex_ios_${seed}@example.com`);
  await setElementValue(sessionId, passwordField, 'Passw0rd!Passw0rd!');

  const submitButton =
    (await maybeFindElement(sessionId, 'accessibility id', 'Create account with Email')) ||
    (await maybeFindElement(sessionId, 'accessibility id', 'Sign in with Email'));
  if (submitButton) {
    await click(sessionId, submitButton);
  }

  for (let i = 0; i < 12; i += 1) {
    await wait(700);
    src = await sourceText(sessionId);
    if (!src.includes('name="Sign In"') && !src.includes('label="Sign In"')) return;
  }
}

async function signUpIfNeeded(sessionId) {
  let src = await sourceText(sessionId);
  if (!src.includes('name="Sign In"') && !src.includes('label="Sign In"')) return false;
  await ensureAuthenticated(sessionId);
  src = await sourceText(sessionId);
  if (src.includes('name="Sign In"') || src.includes('label="Sign In"')) {
    throw new Error('Sign-in sheet remained visible after signup attempt.');
  }
  return true;
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const shotPath = path.join(OUT_DIR, `appium-ios-home-panel-doubletap-like-${ts}.png`);
  const failShot = path.join(OUT_DIR, `appium-ios-home-panel-doubletap-like-fail-${ts}.png`);
  const failSource = path.join(OUT_DIR, `appium-ios-home-panel-doubletap-like-fail-${ts}.xml`);

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

    await ensureAuthenticated(sessionId);

    await swipe(sessionId, 330, 360, 70, 360, 220);
    await wait(900);

    let src = await sourceText(sessionId);
    if (!src.includes('Project Overview')) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Project panel not open. source=${failSource} screenshot=${failShot}`);
    }

    const beforeLiked = src.includes('name="heart.fill"') || src.includes('label="heart.fill"');

    await doubleTap(sessionId, 190, 320);
    await wait(1200);
    src = await sourceText(sessionId);
    if (await signUpIfNeeded(sessionId)) {
      await swipe(sessionId, 330, 360, 70, 360, 220);
      await wait(900);
      src = await sourceText(sessionId);
      if (!src.includes('Project Overview')) {
        await screenshot(sessionId, failShot);
        await fs.writeFile(failSource, src, 'utf8');
        throw new Error(`Project panel not open after auth. source=${failSource} screenshot=${failShot}`);
      }
      await doubleTap(sessionId, 190, 320);
      await wait(1200);
      src = await sourceText(sessionId);
    }

    if (src.includes('1. Select plan') || src.includes('2. Confirm')) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Double tap should not open support sheet. source=${failSource} screenshot=${failShot}`);
    }

    const afterLiked = src.includes('name="heart.fill"') || src.includes('label="heart.fill"');
    if (afterLiked === beforeLiked) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, 'utf8');
      throw new Error(`Like state did not toggle after double tap. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, shotPath);
    console.log(JSON.stringify({
      session_id: sessionId,
      double_tap_toggled_like: true,
      did_not_open_support_sheet: true,
      screenshot: shotPath,
    }, null, 2));
  } finally {
    try { await http('DELETE', `${APPIUM_URL}/session/${sessionId}`); } catch {}
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err));
  process.exit(1);
});
