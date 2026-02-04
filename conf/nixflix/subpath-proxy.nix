{
  path,
  port ? null,
}:
''
  # ============================================================
  # ULTIMATE SUBPATH PROXY CONFIG - Maximum Compatibility Mode
  # ============================================================

  # --- CRITICAL: Disable compression to allow sub_filter to work ---
  proxy_set_header Accept-Encoding "";

  # --- Cookie handling - CRITICAL for login/sessions ---
  proxy_cookie_path / /${path}/;
  proxy_cookie_path ~^/(.+)$ /${path}/$1;
  proxy_cookie_flags ~ nosecure samesite=lax;
  # proxy_cookie_domain ~\.?(.+)$ $host;

  # --- Essential headers for subpath awareness ---
  proxy_set_header X-Forwarded-Prefix /${path};
  proxy_set_header X-Base-URL /${path};
  proxy_set_header X-Script-Name /${path};
  proxy_set_header X-Ingress-Path /${path};

  # --- Redirect rewriting ---
  proxy_redirect default;
  proxy_redirect ~^/(.*)$ /${path}/$1;
  ${
    if port != null then
      ''
        proxy_redirect http://127.0.0.1:${toString port}/ /${path}/;
        proxy_redirect http://localhost:${toString port}/ /${path}/;
        proxy_redirect http://127.0.0.1:${toString port} /${path};
        proxy_redirect / /${path}/;
      ''
    else
      ''
        proxy_redirect off;
      ''
  }


  # --- WebSocket settings removed (handled by proxyWebsockets = true in location) ---
   # proxy_http_version 1.1;
   # proxy_read_timeout 86400s;
   # proxy_send_timeout 86400s;

  # --- Buffering settings for sub_filter ---
  proxy_buffering on;
  proxy_buffer_size 128k;
  proxy_buffers 4 256k;
  proxy_busy_buffers_size 256k;

  # ============================================================
  # CONTENT REWRITING - User requested broad but safe rules
  # ============================================================
  sub_filter_once off;
  # text/html is default, adding others as requested
  sub_filter_types
    text/css
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    image/svg+xml;

  # --- Surgical Contextual Rewriting (HTML/CSS/JS safe) ---
  sub_filter ' href="/' ' href="/${path}/';
  sub_filter ' src="/' ' src="/${path}/';
  sub_filter ' action="/' ' action="/${path}/';
  sub_filter ' url("/' ' url("/${path}/';
  sub_filter " url('/" " url('/${path}/";
  sub_filter ' fetch("/' ' fetch("/${path}/';
  sub_filter ' axios.get("/' ' axios.get("/${path}/';
  sub_filter ' serviceWorker.register("/' ' serviceWorker.register("/${path}/';
  sub_filter ' registerServiceWorker("/' ' registerServiceWorker("/${path}/';
  sub_filter ' window.location="/' ' window.location="/${path}/';
  sub_filter ' location.href="/' ' location.href="/${path}/';

  # --- JSON/JS string paths (targeting common patterns) ---
  sub_filter '": "/' '": "/${path}/';
  sub_filter "': '/" "': '/${path}/";
  sub_filter 'path: "/' 'path: "/${path}/';
  sub_filter "path: '/" "path: '/${path}/";

  # --- Absolute root paths with single quotes ---
  # sub_filter "='/" "='/${path}/";
  # sub_filter "= '/" "= '/${path}/";

  # --- JSON/JS string paths ---
  sub_filter '": /' '": /${path}/';
  sub_filter '": "/' '": "/${path}/';
  sub_filter "': /" "': /${path}/";
  sub_filter "': '/" "': '/${path}/";

  # --- Common HTML attributes with absolute paths ---
  sub_filter ' href="/' ' href="/${path}/';
  sub_filter " href='/" " href='/${path}/";
  sub_filter ' src="/' ' src="/${path}/';
  sub_filter " src='/" " src='/${path}/";
  sub_filter ' action="/' ' action="/${path}/';
  sub_filter " action='/" " action='/${path}/";
  sub_filter ' data-url="/' ' data-url="/${path}/';
  sub_filter " data-url='/" " data-url='/${path}/";
  sub_filter ' data-src="/' ' data-src="/${path}/';
  sub_filter " data-src='/" " data-src='/${path}/";
  sub_filter ' data-href="/' ' data-href="/${path}/';
  sub_filter " data-href='/" " data-href='/${path}/";
  sub_filter ' poster="/' ' poster="/${path}/';
  sub_filter " poster='/" " poster='/${path}/";
  sub_filter ' content="/' ' content="/${path}/';
  sub_filter " content='/" " content='/${path}/";

  # --- CSS url() patterns ---
  sub_filter 'url(/' 'url(/${path}/';
  sub_filter 'url("/' 'url("/${path}/';
  sub_filter "url('/" "url('/${path}/";
  sub_filter 'url( /' 'url( /${path}/';
  sub_filter 'url( "/' 'url( "/${path}/';
  sub_filter "url( '/" "url( '/${path}/";

  # --- @import CSS patterns ---
  sub_filter '@import "/' '@import "/${path}/';
  sub_filter "@import '/" "@import '/${path}/";
  sub_filter '@import url("/' '@import url("/${path}/';
  sub_filter "@import url('/" "@import url('/${path}/";

  # --- JavaScript fetch/XHR patterns ---
  sub_filter 'fetch("/' 'fetch("/${path}/';
  sub_filter "fetch('/" "fetch('/${path}/";
  sub_filter 'fetch(`/' 'fetch(`/${path}/';
  sub_filter 'axios.get("/' 'axios.get("/${path}/';
  sub_filter "axios.get('/" "axios.get('/${path}/";
  sub_filter 'axios.post("/' 'axios.post("/${path}/';
  sub_filter "axios.post('/" "axios.post('/${path}/";
  sub_filter 'axios.put("/' 'axios.put("/${path}/';
  sub_filter "axios.put('/" "axios.put('/${path}/";
  sub_filter 'axios.delete("/' 'axios.delete("/${path}/';
  sub_filter "axios.delete('/" "axios.delete('/${path}/";
  # jQuery patterns removed due to nginx variable conflict with $
  sub_filter 'XMLHttpRequest.open("GET","/' 'XMLHttpRequest.open("GET","/${path}/';
  sub_filter 'XMLHttpRequest.open("POST","/' 'XMLHttpRequest.open("POST","/${path}/';

  # --- Vue/React/Angular router patterns ---
  sub_filter 'to="/' 'to="/${path}/';
  sub_filter "to='/" "to='/${path}/";
  sub_filter ':to="/' ':to="/${path}/';
  sub_filter ":to='/" ":to='/${path}/";
  sub_filter 'router.push("/' 'router.push("/${path}/';
  sub_filter "router.push('/" "router.push('/${path}/";
  sub_filter 'router.replace("/' 'router.replace("/${path}/';
  sub_filter "router.replace('/" "router.replace('/${path}/";
  sub_filter 'navigate("/' 'navigate("/${path}/';
  sub_filter "navigate('/" "navigate('/${path}/";
  sub_filter 'redirect:"/' 'redirect:"/${path}/';
  sub_filter "redirect:'/" "redirect:'/${path}/";
  sub_filter 'path:"/' 'path:"/${path}/';
  sub_filter "path:'/" "path:'/${path}/";
  sub_filter 'location.href="/' 'location.href="/${path}/';
  sub_filter "location.href='/" "location.href='/${path}/";
  sub_filter 'location.pathname="/' 'location.pathname="/${path}/';
  sub_filter "location.pathname='/" "location.pathname='/${path}/";
  sub_filter 'window.location="/' 'window.location="/${path}/';
  sub_filter "window.location='/" "window.location='/${path}/";
  sub_filter 'history.pushState' 'history.pushState';
  sub_filter 'history.replaceState' 'history.replaceState';

  # --- Service Worker and PWA ---
  sub_filter 'serviceWorker.register("/' 'serviceWorker.register("/${path}/';
  sub_filter "serviceWorker.register('/" "serviceWorker.register('/${path}/";
  sub_filter 'navigator.serviceWorker.register("/' 'navigator.serviceWorker.register("/${path}/';
  sub_filter "navigator.serviceWorker.register('/" "navigator.serviceWorker.register('/${path}/";
  sub_filter 'scope:"/' 'scope:"/${path}/';
  sub_filter "scope:'/" "scope:'/${path}/";
  sub_filter 'scope: "/' 'scope: "/${path}/';
  sub_filter "scope: '/" "scope: '/${path}/";
  sub_filter '"start_url":"/' '"start_url":"/${path}/';
  sub_filter '"scope":"/' '"scope":"/${path}/';
  sub_filter '"start_url": "/' '"start_url": "/${path}/';
  sub_filter '"scope": "/' '"scope": "/${path}/';

  # --- WebSocket paths ---
  sub_filter 'new WebSocket("ws://' 'new WebSocket("ws://';
  sub_filter 'new WebSocket("wss://' 'new WebSocket("wss://';
  sub_filter "'ws://' + location.host + \"/\"" "'ws://' + location.host + \"/${path}/\"";
  sub_filter "'wss://' + location.host + \"/\"" "'wss://' + location.host + \"/${path}/\"";

  # --- SignalR (ASP.NET real-time) ---
  sub_filter '"/signalr' '"/${path}/signalr';
  sub_filter "'/signalr" "'/${path}/signalr";
  sub_filter '"/hubs' '"/${path}/hubs';
  sub_filter "'/hubs" "'/${path}/hubs";

  # --- Common static asset directories ---
  sub_filter '"/assets' '"/${path}/assets';
  sub_filter "'/assets" "'/${path}/assets";
  sub_filter '"/static' '"/${path}/static';
  sub_filter "'/static" "'/${path}/static";
  sub_filter '"/js' '"/${path}/js';
  sub_filter "'/js" "'/${path}/js";
  sub_filter '"/css' '"/${path}/css';
  sub_filter "'/css" "'/${path}/css";
  sub_filter '"/img' '"/${path}/img';
  sub_filter "'/img" "'/${path}/img";
  sub_filter '"/images' '"/${path}/images';
  sub_filter "'/images" "'/${path}/images";
  sub_filter '"/fonts' '"/${path}/fonts';
  sub_filter "'/fonts" "'/${path}/fonts";
  sub_filter '"/media' '"/${path}/media';
  sub_filter "'/media" "'/${path}/media";
  sub_filter '"/dist' '"/${path}/dist';
  sub_filter "'/dist" "'/${path}/dist";
  sub_filter '"/build' '"/${path}/build';
  sub_filter "'/build" "'/${path}/build";
  sub_filter '"/public' '"/${path}/public';
  sub_filter "'/public" "'/${path}/public";
  sub_filter '"/vendor' '"/${path}/vendor';
  sub_filter "'/vendor" "'/${path}/vendor";
  sub_filter '"/lib' '"/${path}/lib';
  sub_filter "'/lib" "'/${path}/lib";
  sub_filter '"/node_modules' '"/${path}/node_modules';
  sub_filter "'/node_modules" "'/${path}/node_modules";
  sub_filter '"/Content' '"/${path}/Content';
  sub_filter "'/Content" "'/${path}/Content";
  sub_filter '"/Scripts' '"/${path}/Scripts';
  sub_filter "'/Scripts" "'/${path}/Scripts";
  sub_filter '"/bundles' '"/${path}/bundles';
  sub_filter "'/bundles" "'/${path}/bundles";

  # --- Common app routes ---
  sub_filter '"/api' '"/${path}/api';
  sub_filter "'/api" "'/${path}/api";
  sub_filter '"/v1' '"/${path}/v1';
  sub_filter "'/v1" "'/${path}/v1";
  sub_filter '"/v2' '"/${path}/v2';
  sub_filter "'/v2" "'/${path}/v2";
  sub_filter '"/auth' '"/${path}/auth';
  sub_filter "'/auth" "'/${path}/auth";
  sub_filter '"/login' '"/${path}/login';
  sub_filter "'/login" "'/${path}/login";
  sub_filter '"/logout' '"/${path}/logout';
  sub_filter "'/logout" "'/${path}/logout";
  sub_filter '"/user' '"/${path}/user';
  sub_filter "'/user" "'/${path}/user";
  sub_filter '"/users' '"/${path}/users';
  sub_filter "'/users" "'/${path}/users";
  sub_filter '"/account' '"/${path}/account';
  sub_filter "'/account" "'/${path}/account";
  sub_filter '"/profile' '"/${path}/profile';
  sub_filter "'/profile" "'/${path}/profile";
  sub_filter '"/settings' '"/${path}/settings';
  sub_filter "'/settings" "'/${path}/settings";
  sub_filter '"/admin' '"/${path}/admin';
  sub_filter "'/admin" "'/${path}/admin";
  sub_filter '"/dashboard' '"/${path}/dashboard';
  sub_filter "'/dashboard" "'/${path}/dashboard";
  sub_filter '"/app' '"/${path}/app';
  sub_filter "'/app" "'/${path}/app";
  sub_filter '"/home' '"/${path}/home';
  sub_filter "'/home" "'/${path}/home";
  sub_filter '"/web' '"/${path}/web';
  sub_filter "'/web" "'/${path}/web";
  sub_filter '"/views' '"/${path}/views';
  sub_filter "'/views" "'/${path}/views";
  sub_filter '"/socket' '"/${path}/socket';
  sub_filter "'/socket" "'/${path}/socket";
  sub_filter '"/ws' '"/${path}/ws';
  sub_filter "'/ws" "'/${path}/ws";
  sub_filter '"/stream' '"/${path}/stream';
  sub_filter "'/stream" "'/${path}/stream";
  sub_filter '"/config' '"/${path}/config';
  sub_filter "'/config" "'/${path}/config";
  sub_filter '"/health' '"/${path}/health';
  sub_filter "'/health" "'/${path}/health";
  sub_filter '"/status' '"/${path}/status';
  sub_filter "'/status" "'/${path}/status";

  # --- Meta tags and common files ---
  sub_filter '"/manifest.json' '"/${path}/manifest.json';
  sub_filter "'/manifest.json" "'/${path}/manifest.json";
  sub_filter '"/favicon.ico' '"/${path}/favicon.ico';
  sub_filter "'/favicon.ico" "'/${path}/favicon.ico";
  sub_filter '"/favicon.png' '"/${path}/favicon.png';
  sub_filter '"/apple-touch-icon' '"/${path}/apple-touch-icon';
  sub_filter '"/robots.txt' '"/${path}/robots.txt';
  sub_filter '"/sitemap.xml' '"/${path}/sitemap.xml';
  sub_filter '"/sw.js' '"/${path}/sw.js';
  sub_filter '"/service-worker.js' '"/${path}/service-worker.js';
  sub_filter '"/workbox' '"/${path}/workbox';

  # --- Media stack specific paths (Sonarr/Radarr/Jellyfin/etc) ---
  sub_filter '"/system' '"/${path}/system';
  sub_filter "'/system" "'/${path}/system";
  sub_filter '"/library' '"/${path}/library';
  sub_filter "'/library" "'/${path}/library";
  sub_filter '"/queue' '"/${path}/queue';
  sub_filter "'/queue" "'/${path}/queue";
  sub_filter '"/calendar' '"/${path}/calendar';
  sub_filter "'/calendar" "'/${path}/calendar";
  sub_filter '"/wanted' '"/${path}/wanted';
  sub_filter "'/wanted" "'/${path}/wanted";
  sub_filter '"/activity' '"/${path}/activity';
  sub_filter "'/activity" "'/${path}/activity";
  sub_filter '"/series' '"/${path}/series';
  sub_filter "'/series" "'/${path}/series";
  sub_filter '"/movie' '"/${path}/movie';
  sub_filter "'/movie" "'/${path}/movie";
  sub_filter '"/artist' '"/${path}/artist';
  sub_filter "'/artist" "'/${path}/artist";
  sub_filter '"/album' '"/${path}/album';
  sub_filter "'/album" "'/${path}/album";
  sub_filter '"/indexer' '"/${path}/indexer';
  sub_filter "'/indexer" "'/${path}/indexer";
  sub_filter '"/download' '"/${path}/download';
  sub_filter "'/download" "'/${path}/download";
  sub_filter '"/Items' '"/${path}/Items';
  sub_filter "'/Items" "'/${path}/Items";

  # --- Template literal backticks (ES6) ---
  sub_filter '`/' '`/${path}/';

  # --- Prevent double-prefixing (safety net) ---
  sub_filter '/${path}/${path}/' '/${path}/';
  sub_filter '"/${path}/${path}/' '"/${path}/';
  sub_filter "'/${path}/${path}/" "'/${path}/";

  # --- Fix double-rewriting in API paths (VueTorrent/qBittorrent) ---
  sub_filter '/api/v2/${path}/' '/api/v2/';
  sub_filter '/api/v1/${path}/' '/api/v1/';
''
