export const ENGINE_URL =
  "https://cdn.jsdelivr.net/npm/@cloudflare/speedtest@1.17.0/dist/speedtest.js";
export const ENGINE_INTEGRITY =
  "sha384-QSxbDLkpzCkYnmlY7lYkK29jrk+LCj770oX3W3u23BwLq2/VFU8qj07kh51aOpDT";

const HEADERS = {
  "cache-control": "no-store, no-cache, max-age=0, no-transform",
  "cdn-cache-control": "no-store",
  "cloudflare-cdn-cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "content-security-policy":
    "default-src 'none'; script-src 'self' https://cdn.jsdelivr.net; style-src 'unsafe-inline'; connect-src 'self' https://speed.cloudflare.com; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
};

const PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dora Speed Test</title><style>
:root{color-scheme:light;font-family:system-ui,sans-serif;color:#143b3b;background:#f3f5ef}
*{box-sizing:border-box}body{margin:0;padding:clamp(24px,6vw,80px)}main{max-width:800px;margin:auto}
header{border-top:3px solid #187b70;padding-top:20px;letter-spacing:.12em;font-size:12px;text-transform:uppercase}
h1{font-size:clamp(36px,7vw,64px);font-weight:550;line-height:1.05;margin:48px 0 24px;letter-spacing:-.04em}
p{max-width:600px;line-height:1.6;color:#526665}.metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:32px 0}
.metric{border:1px solid #c9d6ce;border-radius:8px;padding:20px;background:#fff}.label{font-size:13px;color:#526665}
output{display:block;font-size:clamp(24px,4vw,36px);margin-top:12px;font-variant-numeric:tabular-nums}
button{font:inherit;background:#176b62;color:white;border:0;border-radius:6px;padding:14px 22px;cursor:pointer}
button:disabled{opacity:.5;cursor:wait}#status{min-height:26px}footer{font-size:13px;border-top:1px solid #c9d6ce;padding-top:20px;margin-top:40px}
@media(max-width:520px){.metrics{grid-template-columns:1fr}.metric{display:flex;align-items:center;justify-content:space-between}output{margin:0}}
</style></head><body><main><header>Dora / Speed Test</header>
<h1>A small check.<br>A clearer connection.</h1>
<p>Powered by Cloudflare's official speedtest engine. Measurements use Cloudflare's official endpoints and start only when you press the button.</p>
<section class="metrics" aria-label="Test results">
<div class="metric"><span class="label">Latency</span><output id="latency">Not tested</output></div>
<div class="metric"><span class="label">Download</span><output id="download">Not tested</output></div>
<div class="metric"><span class="label">Upload</span><output id="upload">Not tested</output></div></section>
<button id="start" type="button" disabled>Start speed test</button><p id="status" role="status" aria-live="polite">Loading the official engine...</p>
<footer>Website hosted on Cloudflare Workers. Engine version 1.17.0 is loaded from jsDelivr; measurements go to speed.cloudflare.com. Separate results logging is disabled. Tests can transfer substantial data and do not guarantee an exemption from traffic shaping.</footer>
</main><script type="module" src="${ENGINE_URL}" integrity="${ENGINE_INTEGRITY}" crossorigin="anonymous"></script><script type="module" src="/app.js"></script></body></html>`;

const APP = `import SpeedTest from "${ENGINE_URL}";
const button = document.getElementById("start");
const status = document.getElementById("status");
const engine = new SpeedTest({
  autoStart: false,
  downloadApiUrl: "https://speed.cloudflare.com/__down",
  uploadApiUrl: "https://speed.cloudflare.com/__up",
  logAimApiUrl: null,
  logMeasurementApiUrl: null,
  abortRequestDuration: 15000,
  abortTestDuration: 60000,
});
function display(id, value, scale, unit, decimals = 1) {
  document.getElementById(id).textContent = Number.isFinite(value) ? (value * scale).toFixed(decimals) + unit : "Not measured";
}
function render(results) {
  display("latency", results.getUnloadedLatency(), 1, " ms", 0);
  display("download", results.getDownloadBandwidth(), 0.000001, " Mbps");
  display("upload", results.getUploadBandwidth(), 0.000001, " Mbps");
}
engine.onResultsChange = () => render(engine.results);
engine.onRunningChange = running => {
  button.textContent = running ? "Pause test" : engine.isFinished ? "Start again" : "Resume test";
  status.textContent = running ? "Measuring against Cloudflare's edge..." : engine.isFinished ? "Test finished." : "Paused. No further measurements until resumed.";
};
engine.onFinish = results => {
  render(results);
  button.textContent = "Start again";
  status.textContent = "Test finished. Results describe this route to Cloudflare, not guaranteed line speed.";
};
engine.onError = (error, code) => {
  status.textContent = "Measurement warning: " + error + (code ? " (HTTP " + code + ")" : "");
};
button.addEventListener("click", () => {
  if (engine.isRunning) return engine.pause();
  if (engine.isFinished) engine.restart();
  engine.play();
});
button.disabled = false;
status.textContent = "Ready when you are.";
`;

function response(body, status = 200, headers = {}) {
  return new Response(body, { status, headers: { ...HEADERS, ...headers } });
}

export function createWorker() {
  return {
    async fetch(request) {
      const path = new URL(request.url).pathname;
      const head = request.method === "HEAD";
      if (request.body && !request.body.locked)
        void request.body.cancel().catch(() => {});
      if (!["/", "/speedtest", "/app.js", "/generate_204"].includes(path)) {
        return response(head ? null : "Not found\n", 404, {
          "content-type": "text/plain; charset=utf-8",
        });
      }
      if (!["GET", "HEAD"].includes(request.method)) {
        return response("Method not allowed\n", 405, {
          allow: "GET, HEAD",
          "content-type": "text/plain; charset=utf-8",
        });
      }
      if (path === "/generate_204") return response(null, 204);
      if (path === "/app.js")
        return response(head ? null : APP, 200, {
          "content-type": "text/javascript; charset=utf-8",
        });
      return response(head ? null : PAGE, 200, {
        "content-type": "text/html; charset=utf-8",
      });
    },
  };
}

export default createWorker();
