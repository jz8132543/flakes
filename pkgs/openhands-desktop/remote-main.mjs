import { readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

const configuredUrl = process.env.OPENHANDS_SERVER_URL;

if (configuredUrl === undefined) {
  await import("./main.mjs");
} else {
  const server = new URL(configuredUrl);
  if (
    server.origin !== "https://openhands.dora.im" ||
    server.username ||
    server.password ||
    server.search ||
    server.hash ||
    !["/", "/canvas", "/canvas/"].includes(server.pathname)
  ) {
    throw new Error("Remote mode only accepts https://openhands.dora.im");
  }

  const { app, BrowserWindow, dialog, shell } = await import("electron");
  if (
    ["no-sandbox", "disable-web-security", "ignore-certificate-errors"].some(
      (flag) => app.commandLine.hasSwitch(flag),
    )
  ) {
    throw new Error(
      "Remote mode requires sandboxing, web security, and TLS verification",
    );
  }

  const attempts = new Map();
  let window;

  app.on("login", (event, contents, details, auth, callback) => {
    event.preventDefault();
    let requestUrl;
    try {
      requestUrl = new URL(details.url);
    } catch {
      callback();
      return;
    }
    if (
      contents !== window?.webContents ||
      requestUrl.origin !== server.origin ||
      auth.isProxy ||
      auth.host !== server.hostname ||
      auth.port !== 443 ||
      auth.scheme?.toLowerCase() !== "basic"
    ) {
      callback();
      return;
    }

    const count = (attempts.get(requestUrl.href) ?? 0) + 1;
    attempts.set(requestUrl.href, count);
    if (count > 3) {
      callback();
      return;
    }

    try {
      const path = process.env.OPENHANDS_PASSWORD_FILE;
      const stat = statSync(path);
      if (
        !stat.isFile() ||
        stat.uid !== process.getuid() ||
        (stat.mode & 0o077) !== 0
      ) {
        throw new Error("Credential file is not private");
      }
      const password = readFileSync(path, "utf8").replace(/\r?\n$/, "");
      if (!password || /[\r\n]/.test(password)) {
        throw new Error("Invalid credential file");
      }
      callback("i", password);
    } catch {
      callback();
      dialog.showErrorBox(
        "OpenHands login",
        "Cannot read the private SOPS password file.",
      );
    }
  });

  function external(url) {
    try {
      const target = new URL(url);
      if (
        ["https:", "http:"].includes(target.protocol) &&
        !target.username &&
        !target.password
      ) {
        void shell.openExternal(target.href);
      }
    } catch {
      // Unsupported URLs stay outside the desktop client's trust boundary.
    }
  }

  await app.whenReady();
  window = new BrowserWindow({
    width: 1440,
    height: 960,
    title: "OpenHands Agent Canvas",
    icon: fileURLToPath(new URL("./build-resources/icon.png", import.meta.url)),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
    },
  });
  window.webContents.session.setPermissionRequestHandler(
    (contents, permission, callback) => {
      callback(
        contents === window.webContents &&
          permission === "clipboard-sanitized-write" &&
          window.isFocused(),
      );
    },
  );
  window.webContents.session.setPermissionCheckHandler(
    (contents, permission, origin) => {
      return (
        contents === window.webContents &&
        permission === "clipboard-sanitized-write" &&
        origin === server.origin &&
        window.isFocused()
      );
    },
  );
  window.webContents.setWindowOpenHandler(({ url }) => {
    external(url);
    return { action: "deny" };
  });
  for (const eventName of ["will-navigate", "will-redirect"]) {
    window.webContents.on(eventName, (event, url) => {
      try {
        if (new URL(url).origin === server.origin) return;
      } catch {
        // Reject malformed navigation instead of changing the trusted origin.
      }
      event.preventDefault();
      external(url);
    });
  }
  app.on("window-all-closed", () => app.quit());
  await window.loadURL(new URL("/canvas/", server).href);
}
