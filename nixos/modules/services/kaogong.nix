{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.kaogong;
in
{
  imports = [
    inputs.kaogong.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    services.kaogong = {
      port = config.ports.kaogong or 3000;
      frontendDomain = "kaogong.${config.networking.domain or "localhost"}";
      adminPasswordFile = config.sops.secrets."password".path;
    };

    services.traefik.proxies.kaogong = lib.mkIf (config.services.traefik.enable or false) {
      rule = "Host(`kaogong.${config.networking.domain or "localhost"}`)";
      target = "http://127.0.0.1:${toString config.ports.nginx}";
    };

    systemd.services.kaogong-build = {
      path = with pkgs; [
        nodejs_22
        pnpm
        git
        bash
        coreutils
        rsync
        gnused
      ];
      script = lib.mkForce ''
                set -e
                # Copy source to /opt/kaogong if not exists
                if [ ! -d /opt/kaogong/backend ]; then
                  cp -rT ${inputs.kaogong.outPath} /opt/kaogong
                  chmod -R +w /opt/kaogong
                else
                  # RSYNC to keep it updated if the flake changes
                  ${pkgs.rsync}/bin/rsync -a --delete --exclude 'node_modules' --exclude 'dist' --exclude '.pnpm-store' ${inputs.kaogong.outPath}/ /opt/kaogong/
                  chmod -R +w /opt/kaogong
                fi

                # Ensure JSX escaping in frontend source
                sed -i "s|<Text>去刷题 ></Text>|<Text>{'去刷题 >'}</Text>|g" /opt/kaogong/frontend/src/pages/category/index.tsx 2>/dev/null || true
                sed -i "s|<Text className='arrow'>></Text>|<Text className='arrow'>{'>'}</Text>|g" /opt/kaogong/frontend/src/pages/profile/index.tsx 2>/dev/null || true
                sed -i "s|<Text className='history'>账单明细 ></Text>|<Text className='history'>{'账单明细 >'}</Text>|g" /opt/kaogong/frontend/src/pages/wallet/index.tsx 2>/dev/null || true

                cd /opt/kaogong

                # Build backend
                if [ ! -f backend/dist/main.js ]; then
                  cd backend
                  rm -rf node_modules
                  pnpm install --frozen-lockfile --ignore-scripts
                  npm run build
                  cd /opt/kaogong
                fi

                # Build admin
                if [ ! -f admin/dist/index.html ]; then
                  cd admin
                  rm -rf node_modules
                  pnpm install --frozen-lockfile --ignore-scripts
                  npm run build
                  cd /opt/kaogong
                fi

                # Build frontend (Taro H5)
                if [ ! -f frontend/dist/index.html ]; then
                  cd frontend
                  rm -rf node_modules
                  pnpm install --frozen-lockfile --ignore-scripts

                  # Ensure @tarojs/shared is accessible for webpack5-runner
                  if [ ! -e node_modules/@tarojs/shared ]; then
                    shared_path=$(find node_modules/.pnpm -maxdepth 4 -path '*/@tarojs+shared*/node_modules/@tarojs/shared' | head -n 1)
                    if [ -n "$shared_path" ]; then
                      ln -s "../../$shared_path" node_modules/@tarojs/shared
                    fi
                  fi

                  # Ensure app.css and index.html template exist
                  touch src/app.css
                  if [ ! -f src/index.html ]; then
                    html_tpl=$(find node_modules/.pnpm -path '*/@tarojs+cli*/node_modules/@tarojs/cli/templates/default/src/index.html' | head -n 1)
                    if [ -n "$html_tpl" ]; then
                      cp "$html_tpl" src/index.html
                      sed -i 's|{{ projectName }}|考公平台|g' src/index.html
                    fi
                  fi

                  # Fix unescaped > characters in JSX
                  sed -i "s|<Text>去刷题 ></Text>|<Text>{'去刷题 >'}</Text>|g" src/pages/category/index.tsx 2>/dev/null || true
                  sed -i "s|<Text className='arrow'>></Text>|<Text className='arrow'>{'>'}</Text>|g" src/pages/profile/index.tsx 2>/dev/null || true
                  sed -i "s|<Text className='history'>账单明细 ></Text>|<Text className='history'>{'账单明细 >'}</Text>|g" src/pages/wallet/index.tsx 2>/dev/null || true

                  # Configure esbuild-loader in config/index.js if needed
                  node -e '
                    const fs = require("fs");
                    let c = fs.readFileSync("config/index.js", "utf8");
                    const esbuildSetup = `
            webpackChain(chain) {
              const esbuildLoader = require.resolve("esbuild-loader", {
                paths: [
                  require("path").resolve(__dirname, "../node_modules/.pnpm/node_modules"),
                  require("path").resolve(__dirname, "../node_modules")
                ]
              });
              chain.module
                .rule("script")
                .use("esbuildLoader")
                .loader(esbuildLoader)
                .options({
                  loader: "tsx",
                  target: "es2015",
                  jsx: "transform"
                })
                .after("babelLoader");
            },
        `;
                    if (!c.includes("esbuildLoader")) {
                      c = c.replace("h5: {", "h5: {" + esbuildSetup);
                      fs.writeFileSync("config/index.js", c);
                    }
                  '
                  npm run build:h5
                  cd /opt/kaogong
                fi
      '';
    };
  };
}
