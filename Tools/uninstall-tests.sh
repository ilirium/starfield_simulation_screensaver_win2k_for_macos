#!/bin/bash
# Tests for ./uninstall.sh.
#
# Hermetic by construction: every test overrides the script's directories, which
# puts it in hermetic mode, where it touches files only and makes no defaults,
# cfprefsd or killall call. That matters more than it looks. cfprefsd ignores
# HOME, so the obvious design -- run the script under a throwaway HOME -- would
# delete the developer's real screen saver preferences while reporting success
# (AING-0005 §2.2).
#
# Two things cannot be covered this way, and are covered differently at the end:
# the real directory literals, which hermetic mode never executes, and the
# cfprefsd behaviour, which has its own opt-in script.
#
# Mutation-tested rather than assumed adequate. Nine mutations of uninstall.sh
# were run against this suite; seven were killed -- dropping the container
# ByHost sweep, dropping nullglob, loosening the cache-entry pattern, dropping
# the bundle identity check, dropping the render scratch-domain sweep, dropping
# the dry-run early exit, and dropping the root refusal.
#
# Two survive, and both are redundant guards rather than gaps:
#
#   - --keep-settings is honoured twice, at collection and again at removal.
#     Defeating either one alone changes nothing, because the other still
#     holds.
#   - valid_bundle_path cannot fire today: bundle paths are *constructed* from
#     the two known directories, never discovered, so they are correct by
#     construction. The check is there for a future where they are not.
#
# Neither is worth contorting a test to kill. If either guard ever becomes the
# only one, this note is wrong and the mutation should be re-run.

set -uo pipefail
cd "$(dirname "$0")/.."
SCRIPT="$PWD/uninstall.sh"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$*"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

exists()     { [ -e "$1" ] && echo yes || echo no; }
link_exists(){ [ -L "$1" ] && echo yes || echo no; }

# ---------------------------------------------------------------------------
# A fake installation, built fresh for each test.
#
# Decoys are the point: another saver, Apple's own screensaver preferences, and
# an unrelated com.ilirium domain all have to survive untouched.
# ---------------------------------------------------------------------------

UUID_A="A8C59E65-B37B-5D22-B9AA-899163695E85"
UUID_B="11111111-2222-3333-4444-555555555555"

setup() {
    ROOT="$(mktemp -d "${TMPDIR:-/tmp}/starfield-uninstall-tests.XXXXXX")"
    export STARFIELD_USER_SAVER_DIR="$ROOT/user-savers"
    export STARFIELD_SYSTEM_SAVER_DIR="$ROOT/system-savers"
    export STARFIELD_BYHOST_DIR="$ROOT/byhost"
    export STARFIELD_CONTAINER_BYHOST_DIR="$ROOT/container-byhost"
    export STARFIELD_PREFS_DIR="$ROOT/prefs"
    export STARFIELD_THUMBCACHE_DIR="$ROOT/thumbcache"
    mkdir -p "$STARFIELD_USER_SAVER_DIR" "$STARFIELD_SYSTEM_SAVER_DIR" \
             "$STARFIELD_BYHOST_DIR" "$STARFIELD_CONTAINER_BYHOST_DIR" \
             "$STARFIELD_PREFS_DIR" "$STARFIELD_THUMBCACHE_DIR"

    # The saver: a real directory with real contents, and an Info.plist whose
    # CFBundleIdentifier the script checks before removing anything.
    local b="$STARFIELD_USER_SAVER_DIR/Starfield.saver"
    mkdir -p "$b/Contents/MacOS"
    echo "binary" >"$b/Contents/MacOS/Starfield"
    cat >"$b/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.ilirium.Starfield</string>
</dict></plist>
PLIST

    # Two ByHost plists with different UUIDs, in both locations, to exercise the
    # glob and AING-0006 §7's two-places finding.
    echo x >"$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist"
    echo x >"$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_B.plist"
    echo x >"$STARFIELD_CONTAINER_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist"

    # Tools/Render's scratch domain: plain Preferences, no UUID.
    echo x >"$STARFIELD_PREFS_DIR/com.ilirium.Starfield.render.plist"

    # Decoys. None of these may be touched.
    mkdir -p "$STARFIELD_USER_SAVER_DIR/Nebula.saver/Contents"
    echo x >"$STARFIELD_USER_SAVER_DIR/Nebula.saver/Contents/Info.plist"
    echo x >"$STARFIELD_BYHOST_DIR/com.apple.screensaver.$UUID_A.plist"
    echo x >"$STARFIELD_BYHOST_DIR/com.ilirium.SomethingElse.$UUID_A.plist"
    echo x >"$STARFIELD_PREFS_DIR/com.ilirium.Unrelated.plist"
}

teardown() { rm -rf "$ROOT"; }

decoys_intact() {
    local all=yes
    [ -e "$STARFIELD_USER_SAVER_DIR/Nebula.saver/Contents/Info.plist" ] || all=no
    [ -e "$STARFIELD_BYHOST_DIR/com.apple.screensaver.$UUID_A.plist" ]  || all=no
    [ -e "$STARFIELD_BYHOST_DIR/com.ilirium.SomethingElse.$UUID_A.plist" ] || all=no
    [ -e "$STARFIELD_PREFS_DIR/com.ilirium.Unrelated.plist" ] || all=no
    echo "$all"
}

# ---------------------------------------------------------------------------

echo "uninstall.sh"

# --- a full removal -------------------------------------------------------
setup
out="$("$SCRIPT" -y 2>&1)"; rc=$?
check "full run exits 0"                "$rc" "0"
check "saver removed"                   "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "no"
check "byhost plist A removed"          "$(exists "$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist")" "no"
check "byhost plist B removed"          "$(exists "$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_B.plist")" "no"
check "container plist removed"         "$(exists "$STARFIELD_CONTAINER_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist")" "no"
check "render scratch domain removed"   "$(exists "$STARFIELD_PREFS_DIR/com.ilirium.Starfield.render.plist")" "no"
check "every decoy intact"              "$(decoys_intact)" "yes"
teardown

# --- dry run --------------------------------------------------------------
setup
out="$("$SCRIPT" --dry-run 2>&1)"; rc=$?
check "dry run exits 0"                 "$rc" "0"
check "dry run keeps the saver"         "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "yes"
check "dry run keeps the plists"        "$(exists "$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist")" "yes"
teardown

# --- keep settings --------------------------------------------------------
setup
out="$("$SCRIPT" -y --keep-settings 2>&1)"; rc=$?
check "keep-settings exits 0"           "$rc" "0"
check "keep-settings removes the saver" "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "no"
check "keep-settings keeps byhost"      "$(exists "$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist")" "yes"
check "keep-settings keeps container"   "$(exists "$STARFIELD_CONTAINER_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist")" "yes"
# The confirmation prompt must not offer to remove what it will then keep.
check "keep-settings lists no plists"   "$(grep -c 'Starfield\.[0-9A-Fa-f-]*\.plist' <<<"$out")" "0"
teardown

# --- nothing installed ----------------------------------------------------
setup
rm -rf "$STARFIELD_USER_SAVER_DIR/Starfield.saver" \
       "$STARFIELD_BYHOST_DIR"/com.ilirium.Starfield.* \
       "$STARFIELD_CONTAINER_BYHOST_DIR"/com.ilirium.Starfield.* \
       "$STARFIELD_PREFS_DIR"/com.ilirium.Starfield.*
out="$("$SCRIPT" -y 2>&1)"; rc=$?
check "nothing installed exits 0"       "$rc" "0"
check "nothing installed says so"       "$(grep -c 'does not appear to be installed' <<<"$out")" "1"
check "decoys still intact"             "$(decoys_intact)" "yes"
teardown

# --- unmatched glob never reaches rm --------------------------------------
# Without nullglob an unmatched glob expands to its own literal, which contains
# a "*" and would be handed straight to rm.
setup
rm -f "$STARFIELD_BYHOST_DIR"/com.ilirium.Starfield.*
out="$("$SCRIPT" -y 2>&1)"; rc=$?
check "unmatched glob exits 0"          "$rc" "0"
check "no path containing * was echoed" "$(grep -c 'Starfield[.]\*' <<<"$out")" "0"
teardown

# --- a symlinked install --------------------------------------------------
setup
target="$ROOT/real-build/Starfield.saver"
mkdir -p "$target/Contents"
cp "$STARFIELD_USER_SAVER_DIR/Starfield.saver/Contents/Info.plist" "$target/Contents/Info.plist"
rm -rf "$STARFIELD_USER_SAVER_DIR/Starfield.saver"
ln -s "$target" "$STARFIELD_USER_SAVER_DIR/Starfield.saver"
out="$("$SCRIPT" -y 2>&1)"; rc=$?
check "symlink run exits 0"             "$rc" "0"
check "symlink removed"                 "$(link_exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "no"
check "symlink target untouched"        "$(exists "$target/Contents/Info.plist")" "yes"
# rm -rf on a symlink removes the link either way, so the target surviving does
# not prove the -L branch ran. Check the script said what it meant to do.
check "symlink reported as a symlink"   "$(grep -c 'Removed symlink' <<<"$out")" "1"
teardown

# --- a foreign bundle wearing our name ------------------------------------
setup
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.example.Imposter' \
    "$STARFIELD_USER_SAVER_DIR/Starfield.saver/Contents/Info.plist" >/dev/null
out="$("$SCRIPT" -y 2>&1)"; rc=$?
check "foreign bundle is refused"       "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
check "foreign bundle survives"         "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "yes"
teardown

# --- --refresh-preview ----------------------------------------------------
setup
hash64="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
# Note there is no uppercase-hex decoy: APFS is case-insensitive by default, so
# an uppercase spelling of the same 64 characters is the *same file*, not a
# decoy. The pattern stays lowercase because that is what macOS writes.
short63="${hash64%?}"
nonhex64="g${hash64:1}"
echo png >"$STARFIELD_THUMBCACHE_DIR/$hash64.png"
echo png >"$STARFIELD_THUMBCACHE_DIR/${hash64/0123/beef}.png"
# Decoys inside the cache directory itself.
echo x >"$STARFIELD_THUMBCACHE_DIR/notahash.png"
echo x >"$STARFIELD_THUMBCACHE_DIR/$short63.png"         # 63 chars, not 64
echo x >"$STARFIELD_THUMBCACHE_DIR/$nonhex64.png"        # 64 chars, one not hex
echo x >"$STARFIELD_THUMBCACHE_DIR/$hash64.txt"
mkdir -p "$STARFIELD_THUMBCACHE_DIR/subdir"
out="$("$SCRIPT" --refresh-preview 2>&1)"; rc=$?
check "refresh-preview exits 0"         "$rc" "0"
check "hashed tile removed"             "$(exists "$STARFIELD_THUMBCACHE_DIR/$hash64.png")" "no"
check "non-hash png survives"           "$(exists "$STARFIELD_THUMBCACHE_DIR/notahash.png")" "yes"
check "63-char png survives"            "$(exists "$STARFIELD_THUMBCACHE_DIR/$short63.png")" "yes"
check "non-hex-char png survives"       "$(exists "$STARFIELD_THUMBCACHE_DIR/$nonhex64.png")" "yes"
check "non-png survives"                "$(exists "$STARFIELD_THUMBCACHE_DIR/$hash64.txt")" "yes"
check "subdirectory survives"           "$(exists "$STARFIELD_THUMBCACHE_DIR/subdir")" "yes"
check "refresh leaves the saver alone"  "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "yes"
check "refresh leaves settings alone"   "$(exists "$STARFIELD_BYHOST_DIR/com.ilirium.Starfield.$UUID_A.plist")" "yes"
teardown

# --- --refresh-preview on an absent cache ---------------------------------
setup
rm -rf "$STARFIELD_THUMBCACHE_DIR"
out="$("$SCRIPT" --refresh-preview 2>&1)"; rc=$?
check "absent cache exits 0"            "$rc" "0"
check "absent cache says so"            "$(grep -c 'nothing to refresh' <<<"$out")" "1"
teardown

# --- --refresh-preview --dry-run ------------------------------------------
setup
echo png >"$STARFIELD_THUMBCACHE_DIR/$hash64.png"
out="$("$SCRIPT" --refresh-preview --dry-run 2>&1)"; rc=$?
check "refresh dry run exits 0"         "$rc" "0"
check "refresh dry run removes nothing" "$(exists "$STARFIELD_THUMBCACHE_DIR/$hash64.png")" "yes"
teardown

# --- mutually exclusive options -------------------------------------------
setup
out="$("$SCRIPT" --refresh-preview --all-users -y 2>&1)"; rc=$?
check "refresh + all-users is refused"  "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
out="$("$SCRIPT" --nonsense 2>&1)"; rc=$?
check "unknown option is refused"       "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
teardown

# --- the copy that ships inside the bundle deletes itself -----------------
# build.sh puts a copy in Contents/Resources, so the script can be asked to
# remove the bundle it is executing from. It re-execs out of $TMPDIR first --
# and that re-exec has to carry the original arguments, or an unattended -y run
# stops at a prompt that nobody is there to answer.
setup
res="$STARFIELD_USER_SAVER_DIR/Starfield.saver/Contents/Resources"
mkdir -p "$res"
cp "$SCRIPT" "$res/uninstall.sh"
chmod +x "$res/uninstall.sh"
out="$(printf '' | "$res/uninstall.sh" -y 2>&1)"; rc=$?
check "bundled copy exits 0"            "$rc" "0"
check "bundled copy removed its bundle" "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "no"
check "bundled copy did not prompt"     "$(grep -c 'Continue?' <<<"$out")" "0"
teardown

# --- refuses to run under sudo --------------------------------------------
# Only half of this is executable. EUID is readonly in bash, so the uid guard
# cannot be exercised by faking it, and running the suite as root to reach it
# would be worse than the bug. That half is asserted textually below instead.
setup
out="$(SUDO_USER=someone bash "$SCRIPT" -y 2>&1)"; rc=$?
check "sudo invocation is refused"      "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
check "sudo run removes nothing"        "$(exists "$STARFIELD_USER_SAVER_DIR/Starfield.saver")" "yes"
teardown

# ---------------------------------------------------------------------------
# What hermetic mode cannot reach
#
# Every test above overrides the directories, so the real defaults are the one
# thing never executed -- and a typo in one of them is exactly the bug the seam
# hides. Assert them against the source text instead.
# ---------------------------------------------------------------------------

echo "source literals"

literal() {
    if grep -qF "$2" "$SCRIPT"; then ok "$1"; else bad "$1 (not found in uninstall.sh)"; fi
}

literal "user saver dir default"      ': "${STARFIELD_USER_SAVER_DIR:=$HOME/Library/Screen Savers}"'
literal "system saver dir default"    ': "${STARFIELD_SYSTEM_SAVER_DIR:=/Library/Screen Savers}"'
literal "byhost dir default"          ': "${STARFIELD_BYHOST_DIR:=$HOME/Library/Preferences/ByHost}"'
literal "container byhost default"    'Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost}"'
literal "prefs dir default"           ': "${STARFIELD_PREFS_DIR:=$HOME/Library/Preferences}"'
literal "thumbnail cache default"     'com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails}"'
literal "nullglob is set"             'shopt -s nullglob'
literal "killall is tolerant"         'killall legacyScreenSaver 2>/dev/null || true'
literal "cfprefsd is flushed"         'killall -u "$USER" cfprefsd 2>/dev/null || true'
literal "refuses to run as root"      'if [ "${EUID:-$(id -u)}" -eq 0 ]; then'
literal "elevates only the system rm" 'sudo rm -rf "$b"'

echo
if [ "$FAIL" -eq 0 ]; then
    echo "OK: $PASS checks passed"
else
    echo "FAILED: $FAIL of $((PASS + FAIL)) checks"
    exit 1
fi
