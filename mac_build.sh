#!/usr/bin/env bash
# macOS Tilde Build Automation Script
# This script configures the local environment, clones Tilde's upstream dependencies,
# applies macOS-specific compatibility patches, and builds the editor.

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$DIR")"

echo "==== Tilde macOS Build Configuration ===="
echo "Working in parent directory: $PARENT_DIR"

if ! command -v brew >/dev/null 2>&1; then
    echo "Error: Homebrew must be installed to build Tilde on macOS."
    exit 1
fi

echo "Checking Homebrew dependencies..."
brew install pkg-config gettext libtool ncurses pcre2 libunistring gnu-sed findutils > /dev/null 2>&1 || true

# Setup strict GNU tool shims because Apple BSD variations break 'makesys'
SHIM_DIR="/tmp/libtool-shims"
mkdir -p "$SHIM_DIR"
ln -sf "$(brew --prefix libtool)/bin/glibtool" "$SHIM_DIR/libtool"
ln -sf "$(brew --prefix gnu-sed)/bin/gsed" "$SHIM_DIR/sed"
ln -sf "$(brew --prefix findutils)/bin/gfind" "$SHIM_DIR/find"

BREW=$(brew --prefix)
export PATH="$SHIM_DIR:$(brew --prefix flex)/bin:$(brew --prefix gettext)/bin:$(brew --prefix libtool)/bin:/usr/local/bin:$PATH:-$PATH"
export PKG_CONFIG_PATH="${BREW}/lib/pkgconfig:${BREW}/share/pkgconfig:$(brew --prefix ncurses)/lib/pkgconfig:$(brew --prefix pcre2)/lib/pkgconfig:$(brew --prefix libunistring)/lib/pkgconfig"
export EXTRACFLAGS="-I${BREW}/include -I$(brew --prefix gettext)/include -DUSE_XLOCALE_H"
export EXTRACXXFLAGS="${EXTRACFLAGS}"

# macOS linker blocks dynamic undefined lookup, and rpath needs mapping
export LDFLAGS="-L${BREW}/lib -L$(brew --prefix gettext)/lib -Wl,-not_for_dyld_shared_cache"

echo "==== Cloning / Updating Dependencies ===="
cd "$PARENT_DIR"
REPOS="makesys transcript t3shared t3window t3widget t3key t3config t3highlight"
for repo in $REPOS; do
    if [ ! -d "$repo" ]; then
        echo "--> Cloning $repo"
        git clone "https://github.com/gphalkes/${repo}.git" > /dev/null 2>&1
    else
        echo "--> Found $repo"
    fi
done

echo "==== Applying macOS Compatibility Patches ===="
export PATCHES_DIR="$DIR/macos-patches"
for repo in makesys transcript t3window t3widget t3key t3config; do
    echo "--> Patching $repo..."
    cd "$PARENT_DIR/$repo"
    # Reset local modifications if any before applying
    git checkout -- .
    if [ -f "$PATCHES_DIR/${repo}.patch" ]; then
        git apply "$PATCHES_DIR/${repo}.patch"
    else
        echo "Warning: No patch file found for $repo"
    fi
done

echo "==== Building Tilde ===="
cd "$DIR"

# During build, intermediate tools need DYLD_LIBRARY_PATH mapped to temporary .libs locations
export DYLD_LIBRARY_PATH="$PARENT_DIR/transcript/src/.libs:$PARENT_DIR/t3config/src/.libs:$PARENT_DIR/t3key/src/.libs:$PARENT_DIR/t3window/src/.libs:$PARENT_DIR/t3widget/src/.libs:$PARENT_DIR/t3highlight/src/.libs:$DYLD_LIBRARY_PATH"

../t3shared/doall make -C src

echo "==== Build Complete! ===="
echo "You can test the binary at:"
echo "  cd src && .objects/edit"
