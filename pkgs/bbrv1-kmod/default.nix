{
  lib,
  stdenv,
  linuxPackages_latest,
  kernel,
}:
stdenv.mkDerivation {
  pname = "bbrv1-kmod";
  version = "${kernel.modDirVersion}";

  src = null;
  dontUnpack = true;
  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  postPatch = ''
    set -euo pipefail

    mkdir -p source

    # Extract upstream tcp_bbr.c in a source-shape agnostic way:
    # - unpacked source tree
    # - compressed tarball source
    extract_bbr_source() {
      local src="$1"
      local out="$2"

      if [ -d "$src" ]; then
        cp "$src/net/ipv4/tcp_bbr.c" "$out"
        return 0
      fi

      if [ -f "$src" ]; then
        tar -xOf "$src" --wildcards '*/net/ipv4/tcp_bbr.c' > "$out"
        return 0
      fi

      return 1
    }

    # Prefer upstream source first (mainline-style BBRv1), and only fallback
    # to kernel.src if upstream extraction is unavailable.
    if ! extract_bbr_source "${linuxPackages_latest.kernel.src}" source/tcp_bbrv1.c; then
      extract_bbr_source "${kernel.src}" source/tcp_bbrv1.c
    fi

    # Keep BBRv1 behavior but expose a distinct congestion-control name: bbrv1.
    sed -i \
      -e 's/\.name[[:space:]]*=[[:space:]]*"bbr"/.name = "bbrv1"/' \
      -e 's/MODULE_ALIAS_TCP_CONG("bbr")/MODULE_ALIAS_TCP_CONG("bbrv1")/' \
      source/tcp_bbrv1.c

    # Kernel API compatibility:
    # Some patched kernels expose tso_segs() (2 args) instead of min_tso_segs().
    if grep -q 'u32 (\*tso_segs)(struct sock \*sk, unsigned int mss_now);' \
      "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/source/include/net/tcp.h"; then
      sed -i \
        -e 's/\.min_tso_segs[[:space:]]*=[[:space:]]*bbr_min_tso_segs/.tso_segs = (u32 (*)(struct sock *, unsigned int))bbr_min_tso_segs/' \
        source/tcp_bbrv1.c
    fi

    cat > source/Makefile <<'EOF'
    obj-m += tcp_bbrv1.o
    EOF
  '';

  buildPhase = ''
    runHook preBuild
    make -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" M="$PWD/source" modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D -m 0644 source/tcp_bbrv1.ko "$out/lib/modules/${kernel.modDirVersion}/extra/tcp_bbrv1.ko"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Out-of-tree TCP BBRv1 congestion control module (named bbrv1)";
    platforms = platforms.linux;
    license = licenses.gpl2Only;
  };
}
