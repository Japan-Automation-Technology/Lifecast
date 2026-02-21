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

async function maybeFindElements(sessionId, using, value) {
  try {
    const out = await http("POST", `${APPIUM_URL}/session/${sessionId}/elements`, { using, value });
    const list = out?.value ?? [];
    return list
      .map((el) => el?.["element-6066-11e4-a52e-4f735466cecf"] || el?.ELEMENT)
      .filter(Boolean);
  } catch {
    return [];
  }
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
          { type: "pause", duration: 60 },
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

async function sourceText(sessionId) {
  const out = await http("GET", `${APPIUM_URL}/session/${sessionId}/source`);
  return String(out?.value || "");
}

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const keyboardShot = path.join(OUT_DIR, `appium-ios-project-edit-keyboard-open-${ts}.png`);
  const dismissedShot = path.join(OUT_DIR, `appium-ios-project-edit-keyboard-dismissed-${ts}.png`);
  const failShot = path.join(OUT_DIR, `appium-ios-project-edit-keyboard-failure-${ts}.png`);
  const failSource = path.join(OUT_DIR, `appium-ios-project-edit-keyboard-failure-${ts}.xml`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, "utf8"));
  const created = await http("POST", `${APPIUM_URL}/session`, {
    capabilities: { alwaysMatch: caps, firstMatch: [{}] },
  });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  try {
    await wait(1200);
    let initialSource = await sourceText(sessionId);
    if (initialSource.includes("Private Access to Photos") || initialSource.includes("Collections")) {
      const closePicker =
        (await maybeFindElement(sessionId, "-ios predicate string", 'type == "XCUIElementTypeButton" AND (name == "Close" OR label == "Close")')) ||
        (await maybeFindElement(sessionId, "-ios predicate string", 'type == "XCUIElementTypeButton" AND (name == "x" OR label == "x")'));
      if (closePicker) {
        await click(sessionId, closePicker);
        await wait(700);
      } else {
        await tapAt(sessionId, 30, 95);
        await wait(700);
      }
      const afterClose = await sourceText(sessionId);
      if (afterClose.includes("Private Access to Photos") || afterClose.includes("Collections")) {
        await tapAt(sessionId, 30, 95);
        await wait(700);
      }
    }

    const meTab = await maybeFindElement(sessionId, "accessibility id", "person.fill");
    if (meTab) {
      await click(sessionId, meTab);
      await wait(900);
    }

    const projectTab = await maybeFindElement(sessionId, "accessibility id", "profile-tab-project");
    if (projectTab) {
      await click(sessionId, projectTab);
      await wait(500);
    }

    let src = await sourceText(sessionId);
    if (!src.includes("Edit Project")) {
      const editButton = await maybeFindElement(sessionId, "accessibility id", "profile-project-header-action");
      if (!editButton) {
        await screenshot(sessionId, failShot);
        await fs.writeFile(failSource, src, "utf8");
        throw new Error(`Project edit button not found. source=${failSource} screenshot=${failShot}`);
      }
      await click(sessionId, editButton);
      await wait(700);
      src = await sourceText(sessionId);
      if (!src.includes("Edit Project")) {
        await screenshot(sessionId, failShot);
        await fs.writeFile(failSource, src, "utf8");
        throw new Error(`Edit Project not opened. source=${failSource} screenshot=${failShot}`);
      }
    }

    const visibleTextFields = await maybeFindElements(
      sessionId,
      "-ios predicate string",
      'type == "XCUIElementTypeTextField" AND visible == 1',
    );
    const targetField = visibleTextFields[0] || null;
    if (!targetField) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, src, "utf8");
      throw new Error(`Editable text field not found. source=${failSource} screenshot=${failShot}`);
    }
    await click(sessionId, targetField);
    await wait(700);
    const srcWithKeyboard = await sourceText(sessionId);
    const keyboardOpen = srcWithKeyboard.includes("XCUIElementTypeKeyboard");
    if (!keyboardOpen) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, srcWithKeyboard, "utf8");
      throw new Error(`Keyboard did not open. source=${failSource} screenshot=${failShot}`);
    }
    await screenshot(sessionId, keyboardShot);

    const blankTapPoints = [
      [390, 520],
      [390, 460],
      [360, 420],
      [200, 260],
    ];
    let srcAfterTap = srcWithKeyboard;
    let keyboardDismissed = false;
    for (const [x, y] of blankTapPoints) {
      await tapAt(sessionId, x, y);
      await wait(220);
      srcAfterTap = await sourceText(sessionId);
      keyboardDismissed = !srcAfterTap.includes("XCUIElementTypeKeyboard");
      if (keyboardDismissed) break;
    }
    if (!keyboardDismissed) {
      await screenshot(sessionId, failShot);
      await fs.writeFile(failSource, srcAfterTap, "utf8");
      throw new Error(`Keyboard did not dismiss by blank tap. source=${failSource} screenshot=${failShot}`);
    }
    await screenshot(sessionId, dismissedShot);

    console.log(
      JSON.stringify(
        {
          session_id: sessionId,
          keyboard_opened: true,
          keyboard_dismissed_by_blank_tap: true,
          keyboard_open_screenshot: keyboardShot,
          keyboard_dismissed_screenshot: dismissedShot,
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
