{
  lib,
  stdenv,
  linuxKernel,
  kernel,
  bbrSourceKernel ? linuxKernel.kernels.linux_6_1,
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

    # Use the 6.1 LTS tcp_bbr.c by default because it is still BBRv1. Newer
    # kernels may ship BBRv3 in net/ipv4/tcp_bbr.c.
    extract_bbr_source "${bbrSourceKernel.src}" source/tcp_bbrv1.c

    # Keep BBRv1 behavior but expose a distinct congestion-control name: bbrv1.
    sed -i \
      -e 's/\.name[[:space:]]*=[[:space:]]*"bbr"/.name = "bbrv1"/' \
      -e 's/MODULE_ALIAS_TCP_CONG("bbr")/MODULE_ALIAS_TCP_CONG("bbrv1")/' \
      -e 's/prandom_u32_max/get_random_u32_below/g' \
      source/tcp_bbrv1.c

    TCP_H="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/source/include/net/tcp.h"
    if [ ! -f "$TCP_H" ]; then
      TCP_H="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/include/net/tcp.h"
    fi

    # Kernel API compatibility:
    # Some patched kernels expose tso_segs() (2 args) instead of min_tso_segs().
    if grep -q 'u32 (\*tso_segs)(struct sock \*sk, unsigned int mss_now);' \
      "$TCP_H"; then
      sed -i \
        -e 's/\.min_tso_segs[[:space:]]*=[[:space:]]*bbr_min_tso_segs/.tso_segs = (u32 (*)(struct sock *, unsigned int))bbr_min_tso_segs/' \
        source/tcp_bbrv1.c
    fi

    # Newer tcp_bbr.c versions may have a dedicated tx-start hook. Remove it
    # when the target kernel's tcp_congestion_ops does not provide the member.
    if ! grep -q 'cwnd_event_tx_start' "$TCP_H"; then
      sed -i '/\.cwnd_event_tx_start[[:space:]]*=/d' source/tcp_bbrv1.c
    fi

    # Linux 6.10+ passes ack/flag into cong_control(). BBRv1 only needs the
    # rate sample, so keep the original body and add a small signature shim.
    if grep -q 'void (\*cong_control)(struct sock \*sk, u32 ack, int flag, const struct rate_sample \*rs);' "$TCP_H"; then
      sed -i 's/static void bbr_main(struct sock \*sk, const struct rate_sample \*rs)/static void bbr_main_v1(struct sock *sk, const struct rate_sample *rs)/' source/tcp_bbrv1.c
      printf '%s\n' \
        'static void bbr_main(struct sock *sk, u32 ack, int flag, const struct rate_sample *rs)' \
        '{' \
        '	bbr_main_v1(sk, rs);' \
        '}' \
        > bbr-main-wrapper.c
      perl -0pi -e 's/static void bbr_init\(struct sock \*sk\)/do { local $\/; open my $fh, "<", "bbr-main-wrapper.c"; <$fh> } . "\nstatic void bbr_init(struct sock *sk)"/e' source/tcp_bbrv1.c
    fi

    printf '%s\n' 'obj-m += tcp_bbrv1.o' > source/Makefile
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
