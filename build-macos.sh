#!/usr/bin/env bash
#
# build-macos.sh – build tilde on macOS from a single tilde checkout.
#
# Usage:
#   cd /path/to/tilde
#   bash build-macos.sh
#
# What this script does:
#   1. Installs Homebrew build dependencies
#   2. Builds and installs LLnextgen (parser generator, not on Homebrew)
#   3. Clones the companion repositories alongside this checkout
#   4. Builds all packages
#
# The resulting binary is at:  src/.objects/edit
#
set -euo pipefail

LLNEXTGEN_VERSION=0.5.5

TILDE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$TILDE_DIR")"

info() { printf '\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Temporary directories – cleaned up automatically when the script exits
TMP_DIRS=()
new_tmp() { local d; d=$(mktemp -d); TMP_DIRS+=("$d"); echo "$d"; }
cleanup() { [ ${#TMP_DIRS[@]} -gt 0 ] && rm -rf "${TMP_DIRS[@]}"; }
trap cleanup EXIT

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
command -v brew >/dev/null 2>&1 \
  || die "Homebrew not found. Install it from https://brew.sh first."

info "Installing Homebrew build dependencies..."
brew install flex gettext gnu-sed ncurses pcre2 libunistring libtool pkg-config
ok "Homebrew dependencies ready"

BREW=$(brew --prefix)

# Expose keg-only binaries and GNU sed (replaces BSD sed for rules.mk compat)
export PATH="$(brew --prefix flex)/bin:$PATH"
export PATH="$(brew --prefix gettext)/bin:$PATH"
export PATH="$(brew --prefix gnu-sed)/libexec/gnubin:$PATH"
export PATH="$(brew --prefix libtool)/bin:$PATH"

# libtool shims: macOS ships Apple libtool; configure scripts expect GNU names
LIBTOOL_SHIMS="$(new_tmp)"
ln -sf "$(brew --prefix libtool)/bin/glibtool"    "$LIBTOOL_SHIMS/libtool"
ln -sf "$(brew --prefix libtool)/bin/glibtoolize" "$LIBTOOL_SHIMS/libtoolize"
export PATH="$LIBTOOL_SHIMS:$PATH"

export PKG_CONFIG_PATH="${BREW}/lib/pkgconfig:${BREW}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:$(brew --prefix ncurses)/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:$(brew --prefix pcre2)/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:$(brew --prefix libunistring)/lib/pkgconfig"
export CPPFLAGS="-I${BREW}/include"
export LDFLAGS="-L${BREW}/lib"

# ── 2. LLnextgen ─────────────────────────────────────────────────────────────
# Install into a project-local directory so it doesn't interfere with system
# packages. Override with LLNEXTGEN_PREFIX to use a custom location.
LLNEXTGEN_INSTALL="${LLNEXTGEN_PREFIX:-${PARENT_DIR}/.build-deps/llnextgen-${LLNEXTGEN_VERSION}}"
if [ ! -x "${LLNEXTGEN_INSTALL}/bin/LLnextgen" ]; then
  info "Building LLnextgen ${LLNEXTGEN_VERSION}..."
  TMP=$(new_tmp)
  curl -fsSL \
    "https://os.ghalkes.nl/LLnextgen/releases/LLnextgen-${LLNEXTGEN_VERSION}.tgz" \
    -o "${TMP}/llnextgen.tgz"
  tar xzf "${TMP}/llnextgen.tgz" -C "${TMP}"
  (
    cd "${TMP}/LLnextgen-${LLNEXTGEN_VERSION}"
    ./configure --prefix="${LLNEXTGEN_INSTALL}"
    make
    make install
  )
  ok "LLnextgen installed"
else
  ok "LLnextgen already installed"
fi
export PATH="${LLNEXTGEN_INSTALL}/bin:$PATH"

# ── 3. Compiler wrappers ──────────────────────────────────────────────────────
# makesys/rules.mk uses GNU ld flags (-Wl,--no-undefined, -Wl,-rpath=<p>) that
# the Apple linker rejects on macOS ≤ 13 (Xcode ≤ 14).  Wrap clang/clang++ to
# translate them transparently.
CC_WRAPPERS="$(new_tmp)"
for CMD in clang clang++; do
  REAL=$(xcrun -f "$CMD" 2>/dev/null || echo "$CMD")
  cat > "${CC_WRAPPERS}/${CMD}" <<END_WRAPPER
#!/usr/bin/env bash
NEWARGS=()
for arg in "\$@"; do
  case "\$arg" in
    -Wl,--no-undefined) NEWARGS+=("-Wl,-undefined,error") ;;
    -Wl,-rpath=*)       NEWARGS+=("-Wl,-rpath,\${arg#-Wl,-rpath=}") ;;
    *)                  NEWARGS+=("\$arg") ;;
  esac
done
exec "$REAL" "\${NEWARGS[@]}"
END_WRAPPER
  chmod +x "${CC_WRAPPERS}/${CMD}"
done
export PATH="${CC_WRAPPERS}:$PATH"

# ── 4. Clone companion repositories ──────────────────────────────────────────
info "Cloning companion repositories into $(dirname "$TILDE_DIR")..."
for repo in makesys transcript t3shared t3window t3widget t3key t3config t3highlight; do
  if [ ! -d "${PARENT_DIR}/${repo}" ]; then
    git clone --depth=1 "https://github.com/gphalkes/${repo}.git" "${PARENT_DIR}/${repo}"
    ok "Cloned ${repo}"
  else
    ok "${repo} already present"
  fi
done

# ── 5. Build ──────────────────────────────────────────────────────────────────
info "Building tilde and all dependencies..."
(cd "${PARENT_DIR}" && ./t3shared/doall --skip-non-source --stop-on-error make -C src)

BINARY="${TILDE_DIR}/src/.objects/edit"
[ -x "${BINARY}" ] || die "Build completed but binary not found at ${BINARY}"

printf '\n\033[1;32m════════════════════════════════════════\033[0m\n'
printf '\033[1;32m  Build complete!\033[0m\n'
printf '\033[1;32m════════════════════════════════════════\033[0m\n\n'
printf '  Binary:  %s\n\n' "${BINARY}"
printf '  Run:     %s [file ...]\n' "${BINARY}"
printf '  Symlink: sudo ln -sf %s /usr/local/bin/tilde\n\n' "${BINARY}"
