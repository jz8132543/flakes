import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";
import {
  createWorker,
  ENGINE_URL,
  ENGINE_INTEGRITY,
} from "../terraform/modules/speedtest-worker/worker.mjs";

const BASE = "https://speedtest.dora.im";
const request = (path, options = {}) => new Request(`${BASE}${path}`, options);

function assertHeaders(result) {
  assert.match(result.headers.get("cache-control"), /no-store/);
  assert.match(result.headers.get("cache-control"), /no-transform/);
  assert.equal(result.headers.get("cdn-cache-control"), "no-store");
  assert.equal(result.headers.get("cloudflare-cdn-cache-control"), "no-store");
  assert.equal(result.headers.get("x-content-type-options"), "nosniff");
  assert.equal(result.headers.get("access-control-allow-origin"), null);
  const csp = result.headers.get("content-security-policy");
  assert.match(csp, /script-src 'self' https:\/\/cdn\.jsdelivr\.net;/);
  assert.match(csp, /connect-src 'self' https:\/\/speed\.cloudflare\.com;/);
  assert.doesNotMatch(csp, /unsafe-eval|connect-src \*/);
}

test("Terraform uses the locked provider and only a script plus Custom Domain", async () => {
  const module = await readFile(
    new URL("../terraform/modules/speedtest-worker/main.tf", import.meta.url),
    "utf8",
  );
  const root = await readFile(
    new URL("../terraform/cloudflare.tf", import.meta.url),
    "utf8",
  );
  const lock = await readFile(
    new URL("../terraform/.terraform.lock.hcl", import.meta.url),
    "utf8",
  );
  assert.match(
    lock,
    /provider "registry\.terraform\.io\/cloudflare\/cloudflare"\s*\{\s*version = "5\.16\.0"/,
  );
  assert.match(module, /version\s*= "~> 5\.16\.0"/);
  assert.equal([...module.matchAll(/resource "/g)].length, 2);
  assert.match(module, /resource "cloudflare_workers_script" "this"/);
  assert.match(module, /resource "cloudflare_workers_custom_domain" "this"/);
  assert.match(module, /content_sha256\s*= filesha256\(/);
  assert.match(module, /main_module\s*= "worker\.mjs"/);
  assert.match(module, /cpu_ms = 10/);
  assert.match(module, /observability = \{\s*enabled = false/);
  assert.doesNotMatch(
    module,
    /cloudflare_dns_record|api_token|secret_text|\.tfstate/,
  );
  assert.match(
    root,
    /module "speedtest_worker"\s*\{[\s\S]*?account_id = local\.cloudflare_main_account_id[\s\S]*?zone_id\s*= cloudflare_zone\.im_dora\.id[\s\S]*?hostname\s*= "speedtest\.\$\{cloudflare_zone\.im_dora\.name\}"/,
  );
});

test("official engine version and integrity are pinned in the homepage", async () => {
  assert.equal(
    ENGINE_URL,
    "https://cdn.jsdelivr.net/npm/@cloudflare/speedtest@1.17.0/dist/speedtest.js",
  );
  assert.match(ENGINE_INTEGRITY, /^sha384-[A-Za-z0-9+/]{64}$/);
  const worker = createWorker();
  const home = await worker.fetch(request("/"));
  assert.equal(home.status, 200);
  assertHeaders(home);
  const page = await home.text();
  assert.match(page, /name="viewport"/);
  assert.ok(
    page.includes(
      `src="${ENGINE_URL}" integrity="${ENGINE_INTEGRITY}" crossorigin="anonymous"`,
    ),
  );
  assert.match(page, /<script type="module" src="\/app\.js">/);
  assert.match(page, /speed\.cloudflare\.com/);
  assert.match(page, /Separate results logging is disabled/);
  assert.equal(await (await worker.fetch(request("/speedtest"))).text(), page);
});

test("official API configuration has no custom measurement backend or telemetry", async () => {
  const result = await createWorker().fetch(request("/app.js"));
  assert.equal(result.status, 200);
  assertHeaders(result);
  const script = await result.text();
  assert.ok(script.startsWith(`import SpeedTest from "${ENGINE_URL}";`));
  assert.match(script, /autoStart: false/);
  assert.match(
    script,
    /downloadApiUrl: "https:\/\/speed\.cloudflare\.com\/__down"/,
  );
  assert.match(
    script,
    /uploadApiUrl: "https:\/\/speed\.cloudflare\.com\/__up"/,
  );
  assert.match(script, /logAimApiUrl: null/);
  assert.match(script, /logMeasurementApiUrl: null/);
  assert.doesNotMatch(
    script,
    /\/download\?|\/upload"|crypto\.getRandomValues|measurements:|setInterval/,
  );
});

test("GET and HEAD health checks remain bodyless and independent", async () => {
  const worker = createWorker();
  for (const method of ["GET", "HEAD"]) {
    const result = await worker.fetch(request("/generate_204", { method }));
    assert.equal(result.status, 204);
    assert.equal(result.body, null);
    assertHeaders(result);
  }
  for (const path of ["/", "/speedtest", "/app.js", "/missing"]) {
    const result = await worker.fetch(request(path, { method: "HEAD" }));
    assert.equal(result.body, null);
    assertHeaders(result);
  }
});

test("unsupported methods cancel unconsumed bodies", async () => {
  const worker = createWorker();
  for (const path of ["/", "/speedtest", "/app.js", "/generate_204"]) {
    let cancelled = false;
    const body = new ReadableStream({
      cancel() {
        cancelled = true;
      },
    });
    const result = await worker.fetch(
      request(path, { method: "POST", body, duplex: "half" }),
    );
    assert.equal(result.status, 405);
    assert.equal(result.headers.get("allow"), "GET, HEAD");
    assert.equal(cancelled, true);
    assertHeaders(result);
  }
});

test("removed backends and arbitrary URLs cannot trigger Worker subrequests", async (t) => {
  t.mock.method(globalThis, "fetch", () => {
    assert.fail("Worker attempted an outbound request");
  });
  const worker = createWorker();
  for (const path of [
    "/download?bytes=0",
    "/upload",
    "/__down",
    "/__up",
    "/proxy?url=https://example.com",
  ]) {
    const result = await worker.fetch(request(path));
    assert.equal(result.status, 404);
    assertHeaders(result);
  }
  assert.equal(
    (await worker.fetch(request("/?url=https://example.com"))).status,
    200,
  );
  assert.equal((await worker.fetch(request("/generate_204"))).status, 204);
});

test("browser controls start only on click and use official results", async () => {
  const script = await (await createWorker().fetch(request("/app.js"))).text();
  const elements = Object.fromEntries(
    ["start", "status", "latency", "download", "upload"].map((id) => [
      id,
      { textContent: "", disabled: true },
    ]),
  );
  let click;
  elements.start.addEventListener = (name, callback) => {
    assert.equal(name, "click");
    click = callback;
  };
  let engine;
  const results = {
    getUnloadedLatency: () => 12,
    getDownloadBandwidth: () => 100_000_000,
    getUploadBandwidth: () => 20_000_000,
  };
  class MockSpeedTest {
    constructor(options) {
      engine = this;
      this.options = options;
      this.results = results;
      this.isRunning = false;
      this.isFinished = false;
      this.starts = 0;
    }
    play() {
      this.starts++;
      this.isRunning = true;
      this.onRunningChange(true);
    }
    pause() {
      this.isRunning = false;
      this.onRunningChange(false);
    }
    restart() {
      this.isFinished = false;
    }
  }
  const context = vm.createContext({
    SpeedTest: MockSpeedTest,
    document: { getElementById: (id) => elements[id] },
  });
  // Mock only the import in our UI wrapper; the pinned upstream engine is unchanged.
  new vm.Script(script.slice(script.indexOf("\n") + 1)).runInContext(context);
  assert.equal(engine.starts, 0);
  assert.equal(engine.options.autoStart, false);
  assert.equal(engine.options.logAimApiUrl, null);
  assert.equal(engine.options.logMeasurementApiUrl, null);
  assert.equal(elements.start.disabled, false);
  click();
  assert.equal(engine.starts, 1);
  assert.equal(elements.start.textContent, "Pause test");
  engine.onResultsChange();
  assert.equal(elements.latency.textContent, "12 ms");
  assert.equal(elements.download.textContent, "100.0 Mbps");
  assert.equal(elements.upload.textContent, "20.0 Mbps");
  click();
  assert.equal(engine.isRunning, false);
  assert.equal(elements.start.textContent, "Resume test");
  engine.isFinished = true;
  engine.onFinish(results);
  assert.equal(elements.start.textContent, "Start again");
  click();
  assert.equal(engine.starts, 2);
  engine.onError("unavailable", 503);
  assert.match(elements.status.textContent, /unavailable \(HTTP 503\)/);
});
