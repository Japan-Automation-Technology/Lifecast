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

async function click(sessionId, elementId) {
  await http("POST", `${APPIUM_URL}/session/${sessionId}/element/${elementId}/click`, {});
}

async function screenshot(sessionId, filePath) {
  const shot = await http("GET", `${APPIUM_URL}/session/${sessionId}/screenshot`);
  const b64 = shot?.value;
  if (!b64) throw new Error("Screenshot payload missing");
  await fs.writeFile(filePath, Buffer.from(b64, "base64"));
}

async function source(sessionId, filePath) {
  const out = await http("GET", `${APPIUM_URL}/session/${sessionId}/source`);
  await fs.writeFile(filePath, String(out?.value || ""), "utf8");
}

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function findByContains(sessionId, text) {
  return maybeFindElement(
    sessionId,
    "-ios predicate string",
    `name CONTAINS[c] "${text}" OR label CONTAINS[c] "${text}" OR value CONTAINS[c] "${text}"`,
  );
}

async function sourceText(sessionId) {
  const out = await http("GET", `${APPIUM_URL}/session/${sessionId}/source`);
  return String(out?.value || "");
}

async function tapMeTab(sessionId) {
  const candidates = [
    ["accessibility id", "person.fill"],
    ['accessibility id', 'Me'],
    ['accessibility id', 'person'],
    ['-ios predicate string', 'type == "XCUIElementTypeButton" AND (name == "person.fill" OR label == "person.fill")'],
    ['-ios predicate string', 'type == "XCUIElementTypeButton" AND (name CONTAINS[c] "Me" OR label CONTAINS[c] "Me")'],
  ];
  for (const [using, value] of candidates) {
    const el = await maybeFindElement(sessionId, using, value);
    if (el) {
      await click(sessionId, el);
      return true;
    }
  }
  return false;
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const ts = Date.now();
  const beforeShot = path.join(OUT_DIR, `appium-ios-plan-image-before-${ts}.png`);
  const afterTapShot = path.join(OUT_DIR, `appium-ios-plan-image-after-tap-${ts}.png`);
  const pickerShot = path.join(OUT_DIR, `appium-ios-plan-image-picker-open-${ts}.png`);
  const failShot = path.join(OUT_DIR, `appium-ios-plan-image-failure-${ts}.png`);
  const failSource = path.join(OUT_DIR, `appium-ios-plan-image-failure-${ts}.xml`);

  const caps = JSON.parse(await fs.readFile(CAPS_PATH, "utf8"));
  caps["appium:noReset"] = true;
  const created = await http("POST", `${APPIUM_URL}/session`, {
    capabilities: { alwaysMatch: caps, firstMatch: [{}] },
  });
  const sessionId = created?.value?.sessionId || created?.sessionId;
  if (!sessionId) throw new Error(`Failed to create session: ${JSON.stringify(created)}`);

  try {
    await wait(1200);
    const startupSource = await sourceText(sessionId);
    if (
      startupSource.includes("Private Access to Photos") ||
      startupSource.includes("Collections") ||
      startupSource.includes("XCUIElementTypeCollectionView")
    ) {
      await screenshot(sessionId, pickerShot);
      console.log(
        JSON.stringify(
          {
            session_id: sessionId,
            picker_opened: true,
            before_screenshot: beforeShot,
            after_tap_screenshot: afterTapShot,
            picker_screenshot: pickerShot,
          },
          null,
          2,
        ),
      );
      return;
    }

    const editProfileNav = await maybeFindElement(
      sessionId,
      "-ios predicate string",
      'type == "XCUIElementTypeNavigationBar" AND (name CONTAINS[c] "Edit Profile" OR label CONTAINS[c] "Edit Profile")',
    );
    if (editProfileNav) {
      const cancelEditProfile =
        (await maybeFindElement(sessionId, "accessibility id", "Cancel")) ||
        (await findByContains(sessionId, "Cancel"));
      if (cancelEditProfile) {
        await click(sessionId, cancelEditProfile);
        await wait(700);
      }
    }

    const movedToMe = await tapMeTab(sessionId);
    if (!movedToMe) {
      await source(sessionId, failSource);
      await screenshot(sessionId, failShot);
      throw new Error(`Me tab not found. source=${failSource} screenshot=${failShot}`);
    }
    await wait(1000);

    const usernameOnMe = await maybeFindElement(
      sessionId,
      "-ios predicate string",
      `type == "XCUIElementTypeStaticText" AND (name BEGINSWITH "@" OR label BEGINSWITH "@")`,
    );
    if (!usernameOnMe) {
      await source(sessionId, failSource);
      await screenshot(sessionId, failShot);
      throw new Error(`Not on Me screen after tap. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, beforeShot);

    let selectPlanImageButton =
      (await maybeFindElement(sessionId, "accessibility id", "project-inline-plan-image-picker")) ||
      (await findByContains(sessionId, "Select Plan Image")) ||
      (await findByContains(sessionId, "Change Plan Image"));

    if (!selectPlanImageButton) {
      const projectTab = await maybeFindElement(sessionId, "accessibility id", "profile-tab-project");
      if (!projectTab) {
        await source(sessionId, failSource);
        await screenshot(sessionId, failShot);
        throw new Error(`Project tab not found. source=${failSource} screenshot=${failShot}`);
      }
      await click(sessionId, projectTab);
      await wait(500);

      const editButton = await maybeFindElement(sessionId, "accessibility id", "profile-project-header-action");
      if (!editButton) {
        await source(sessionId, failSource);
        await screenshot(sessionId, failShot);
        throw new Error(`Project edit button not found. source=${failSource} screenshot=${failShot}`);
      }
      await click(sessionId, editButton);
      await wait(700);

      const editSource = await sourceText(sessionId);
      if (!editSource.includes("Edit Project")) {
        await source(sessionId, failSource);
        await screenshot(sessionId, failShot);
        throw new Error(`Project inline editor did not open. source=${failSource} screenshot=${failShot}`);
      }

      selectPlanImageButton =
        (await maybeFindElement(sessionId, "accessibility id", "project-inline-plan-image-picker")) ||
        (await findByContains(sessionId, "Select Plan Image")) ||
        (await findByContains(sessionId, "Change Plan Image"));
    }
    if (!selectPlanImageButton) {
      await source(sessionId, failSource);
      await screenshot(sessionId, failShot);
      throw new Error(`Select Plan Image button not found. source=${failSource} screenshot=${failShot}`);
    }
    await screenshot(sessionId, afterTapShot);
    await click(sessionId, selectPlanImageButton);
    await wait(1000);

    const pickerSource = await sourceText(sessionId);
    const pickerVisible =
      pickerSource.includes("Photo Library") ||
      pickerSource.includes("Photos") ||
      pickerSource.includes("Collections") ||
      pickerSource.includes("Private Access to Photos") ||
      pickerSource.includes("Recents") ||
      pickerSource.includes("Choose") ||
      pickerSource.includes("XCUIElementTypeCollectionView") ||
      pickerSource.includes("XCUIElementTypeCell");

    if (!pickerVisible) {
      await source(sessionId, failSource);
      await screenshot(sessionId, failShot);
      throw new Error(`Photo picker did not open. source=${failSource} screenshot=${failShot}`);
    }

    await screenshot(sessionId, pickerShot);

    console.log(
      JSON.stringify(
        {
          session_id: sessionId,
          picker_opened: true,
          before_screenshot: beforeShot,
          after_tap_screenshot: afterTapShot,
          picker_screenshot: pickerShot,
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
