import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, SourceTextModule, SyntheticModule } from "node:vm";

const source = readFileSync(
  new URL("./remote-main.mjs", import.meta.url),
  "utf8",
);
const origin = "https://openhands.dora.im";

async function launch(env = {}, overrides = {}) {
  const state = {
    events: {},
    navigations: {},
    errors: [],
    external: [],
    passwordReads: 0,
  };
  const context = createContext({ process: { env, getuid: () => 1000 }, URL });
  const app = {
    commandLine: {
      hasSwitch: (name) =>
        overrides.switches?.includes(name) ||
        (name === "no-sandbox" && overrides.noSandbox === true),
    },
    on: (name, handler) => {
      state.events[name] = handler;
    },
    whenReady: async () => {},
    quit: () => {
      state.quit = true;
    },
  };
  class BrowserWindow {
    constructor(options) {
      state.options = options;
      state.window = this;
      this.webContents = {
        on: (name, handler) => {
          state.navigations[name] = handler;
        },
        setWindowOpenHandler: (handler) => {
          state.popup = handler;
        },
        session: {
          setPermissionRequestHandler: (handler) => {
            state.permission = handler;
          },
          setPermissionCheckHandler: (handler) => {
            state.checkPermission = handler;
          },
        },
      };
    }
    isFocused() {
      return overrides.focused ?? true;
    }
    async loadURL(url) {
      state.loadedUrl = url;
    }
  }
  const objects = {
    "node:fs": {
      statSync: (path) => {
        if (!path) throw new Error("Missing credential file");
        return {
          uid: overrides.uid ?? 1000,
          mode: overrides.mode ?? 0o100600,
          isFile: () => true,
        };
      },
      readFileSync: () => {
        state.passwordReads++;
        return "fake-test-password\n";
      },
    },
    "node:url": { fileURLToPath },
    electron: {
      app,
      BrowserWindow,
      dialog: { showErrorBox: (...args) => state.errors.push(args) },
      shell: {
        openExternal: async (url) => {
          state.external.push(url);
        },
      },
    },
    "./main.mjs": {},
  };
  const modules = new Map();
  async function module(name) {
    if (modules.has(name)) return modules.get(name);
    if (name === "./main.mjs") state.local = true;
    const object = objects[name];
    const result = new SyntheticModule(
      Object.keys(object),
      function () {
        for (const [key, value] of Object.entries(object))
          this.setExport(key, value);
      },
      { context },
    );
    modules.set(name, result);
    await result.link(() => {});
    await result.evaluate();
    return result;
  }
  const main = new SourceTextModule(source, {
    context,
    initializeImportMeta: (meta) => {
      meta.url = new URL("./remote-main.mjs", import.meta.url).href;
    },
    importModuleDynamically: module,
  });
  await main.link(module);
  await main.evaluate();
  return state;
}

function login(state, overrides = {}) {
  let credentials;
  const auth = {
    isProxy: false,
    host: "openhands.dora.im",
    port: 443,
    scheme: "basic",
    ...overrides.auth,
  };
  state.events.login(
    { preventDefault() {} },
    overrides.contents ?? state.window.webContents,
    { url: overrides.url ?? `${origin}/canvas/` },
    auth,
    (...args) => {
      credentials = args;
    },
  );
  return credentials;
}

test("the unconfigured client retains the official local entry point", async () => {
  const state = await launch();
  assert.equal(state.local, true);
  assert.equal(state.window, undefined);
});

test("remote mode rejects invalid origins and disabled sandboxing", async () => {
  for (const url of [
    "",
    "http://openhands.dora.im",
    "https://evil.example",
    `${origin}:8443`,
    `${origin}/?password=x`,
    "https://i:secret@openhands.dora.im",
  ]) {
    await assert.rejects(launch({ OPENHANDS_SERVER_URL: url }));
  }
  await assert.rejects(
    launch({ OPENHANDS_SERVER_URL: origin }, { noSandbox: true }),
  );
  for (const flag of ["disable-web-security", "ignore-certificate-errors"]) {
    await assert.rejects(
      launch({ OPENHANDS_SERVER_URL: origin }, { switches: [flag] }),
    );
  }
});

test("remote mode opens the server without Node access or an upstream preload", async () => {
  const state = await launch({ OPENHANDS_SERVER_URL: origin });
  assert.equal(state.local, undefined);
  assert.equal(state.loadedUrl, `${origin}/canvas/`);
  assert.equal(state.options.webPreferences.sandbox, true);
  assert.equal(state.options.webPreferences.contextIsolation, true);
  assert.equal(state.options.webPreferences.nodeIntegration, false);
  assert.equal(state.options.webPreferences.webSecurity, true);
  assert.equal(state.options.webPreferences.preload, undefined);
  state.events["window-all-closed"]();
  assert.equal(state.quit, true);
});

test("SOPS credentials are provided only to the matching HTTPS challenge", async () => {
  const state = await launch({
    OPENHANDS_SERVER_URL: origin,
    OPENHANDS_PASSWORD_FILE: "/private/password",
  });
  for (const overrides of [
    { url: "http://openhands.dora.im/canvas/" },
    { url: "https://evil.example/" },
    { url: "not-a-url" },
    { auth: { isProxy: true } },
    { auth: { host: "evil.example" } },
    { auth: { port: 8443 } },
    { auth: { scheme: "digest" } },
    { contents: {} },
  ])
    assert.deepEqual(login(state, overrides), []);
  assert.equal(state.passwordReads, 0);
  assert.deepEqual(login(state), ["i", "fake-test-password"]);
  assert.equal(state.passwordReads, 1);
});

test("credential files must be private and owned by the desktop user", async () => {
  for (const overrides of [{ uid: 0 }, { mode: 0o100644 }]) {
    const state = await launch(
      {
        OPENHANDS_SERVER_URL: origin,
        OPENHANDS_PASSWORD_FILE: "/private/password",
      },
      overrides,
    );
    assert.deepEqual(login(state), []);
    assert.equal(state.passwordReads, 0);
    assert.equal(state.errors.length, 1);
  }
});

test("repeated authentication failure is bounded", async () => {
  const state = await launch({
    OPENHANDS_SERVER_URL: origin,
    OPENHANDS_PASSWORD_FILE: "/private/password",
  });
  for (let count = 0; count < 3; count++) assert.equal(login(state).length, 2);
  assert.deepEqual(login(state), []);
  assert.equal(state.passwordReads, 3);
});

test("navigation stays on the server and hardware permissions are denied", async () => {
  const state = await launch({ OPENHANDS_SERVER_URL: origin });
  let blocked = false;
  const event = {
    preventDefault: () => {
      blocked = true;
    },
  };
  state.navigations["will-navigate"](event, `${origin}/canvas/settings`);
  assert.equal(blocked, false);
  state.navigations["will-redirect"](event, "https://example.org/");
  assert.equal(blocked, true);
  assert.deepEqual(state.external, ["https://example.org/"]);
  assert.equal(state.popup({ url: "file:///etc/passwd" }).action, "deny");
  assert.equal(state.external.length, 1);
  let allowed;
  state.permission(state.window.webContents, "media", (value) => {
    allowed = value;
  });
  assert.equal(allowed, false);
  assert.equal(
    state.checkPermission(state.window.webContents, "clipboard-read", origin),
    false,
  );
  assert.equal(
    state.checkPermission({}, "clipboard-sanitized-write", origin),
    false,
  );
});
