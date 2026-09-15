#!/bin/bash
# Removes Starfield.saver and the settings it stored.
#
# This is the only script in the repository that deletes, so it is deliberately
# paranoid: it works out everything it would remove, checks it can remove all of
# it, and only then removes anything. Two path shapes are ever removable -- a
# bundle named exactly Starfield.saver inside a known screen saver directory,
# and a preferences file whose name matches this saver's domain. Anything else
# is refused out loud.
#
# See aingineering/AING-0005-uninstaller-revised.md §3 for why the order of
# operations below is what it is, and AING-0006 §7 for why preferences are
# removed from two places rather than one.

set -euo pipefail

# Without this an unmatched glob expands to its own literal, which then matches
# the validation patterns below and hands rm a path containing "*".
shopt -s nullglob

# Captured before the parsing loop below consumes them, because the re-exec in
# the self-deletion section has to pass the user's original arguments on.
ORIG_ARGS=("$@")

DOMAIN="com.ilirium.Starfield"
BUNDLE_NAME="Starfield.saver"
BUNDLE_ID="com.ilirium.Starfield"

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [options]

  --dry-run           print what would be removed, change nothing
  --keep-settings     remove the saver, keep Density and WarpSpeed
  --all-users         also remove /Library/Screen Savers/Starfield.saver
  --refresh-preview   only clear the System Settings preview cache, remove
                      nothing else -- use after upgrading, when the Screen
                      Saver pane still shows the old thumbnail
  -y                  do not ask for confirmation
  -h, --help          this message

Removing nothing that is not installed is not an error; the script exits 0.
EOF
}

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'uninstall.sh: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Hermetic mode
#
# The test suite cannot isolate this script with a throwaway HOME: cfprefsd
# ignores HOME, so a script that calls `defaults` under a fake home edits the
# real user's preferences while claiming to be sandboxed (AING-0005 §2.2).
#
# So the directories are overridable instead, and overriding any of them puts
# the script in hermetic mode: it touches files only, and skips every defaults,
# cfprefsd and killall call.
# ---------------------------------------------------------------------------

HERMETIC=0
for var in STARFIELD_USER_SAVER_DIR STARFIELD_SYSTEM_SAVER_DIR \
           STARFIELD_BYHOST_DIR STARFIELD_CONTAINER_BYHOST_DIR \
           STARFIELD_PREFS_DIR STARFIELD_THUMBCACHE_DIR; do
    if [ -n "${!var:-}" ]; then HERMETIC=1; fi
done

: "${STARFIELD_USER_SAVER_DIR:=$HOME/Library/Screen Savers}"
: "${STARFIELD_SYSTEM_SAVER_DIR:=/Library/Screen Savers}"
: "${STARFIELD_BYHOST_DIR:=$HOME/Library/Preferences/ByHost}"
# Savers have been sandboxed since macOS 10.15 and their preferences moved with
# them. This is where the installed saver actually reads and writes; the plain
# ByHost directory above holds only what unsandboxed tools wrote. Removing one
# and not the other leaves the user's real settings behind (AING-0006 §7).
: "${STARFIELD_CONTAINER_BYHOST_DIR:=$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost}"
# Tools/Render's scratch domain lands here, in plain Preferences rather than
# ByHost, so a ByHost-only sweep would miss it.
: "${STARFIELD_PREFS_DIR:=$HOME/Library/Preferences}"
: "${STARFIELD_THUMBCACHE_DIR:=$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails}"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

DRY_RUN=0
KEEP_SETTINGS=0
ALL_USERS=0
REFRESH_ONLY=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)         DRY_RUN=1 ;;
        --keep-settings)   KEEP_SETTINGS=1 ;;
        --all-users)       ALL_USERS=1 ;;
        --refresh-preview) REFRESH_ONLY=1 ;;
        -y|--yes)          ASSUME_YES=1 ;;
        -h|--help)         usage; exit 0 ;;
        *)                 usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

if [ "$REFRESH_ONLY" = 1 ] && { [ "$KEEP_SETTINGS" = 1 ] || [ "$ALL_USERS" = 1 ]; }; then
    die "--refresh-preview removes nothing else, so it cannot be combined with --keep-settings or --all-users"
fi

# ---------------------------------------------------------------------------
# Never run the whole script as root
#
# `sudo ./uninstall.sh --all-users` is the obvious invocation and it is wrong:
# as root, `defaults` targets root's domain rather than the user's, and any
# user-path file touched ends up root-owned. Only the single rm of the system
# path is elevated, further down.
# ---------------------------------------------------------------------------

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    die "do not run this as root. Run it as your own user; --all-users elevates only the one command that needs it."
fi
if [ -n "${SUDO_USER:-}" ]; then
    die "this looks like a sudo invocation (SUDO_USER=$SUDO_USER). Run it as your own user instead."
fi

# ---------------------------------------------------------------------------
# Self-deletion
#
# This script also ships inside the saver bundle, so it can be asked to delete
# the file it is currently executing. bash may re-read a script mid-run, so
# re-exec from a copy outside the bundle before anything is removed.
# ---------------------------------------------------------------------------

SELF="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
if [ -z "${STARFIELD_REEXEC:-}" ] && [[ "$SELF" == */"$BUNDLE_NAME"/* ]]; then
    copy="$(mktemp "${TMPDIR:-/tmp}/starfield-uninstall.XXXXXX")"
    cat "$SELF" >"$copy"
    chmod +x "$copy"
    STARFIELD_REEXEC=1 exec "$copy" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
fi

# ---------------------------------------------------------------------------
# Validation
#
# Nothing reaches rm without passing one of these.
# ---------------------------------------------------------------------------

# A bundle is removable only at exactly <known saver dir>/Starfield.saver.
valid_bundle_path() {
    local path="$1" dir
    for dir in "$STARFIELD_USER_SAVER_DIR" "$STARFIELD_SYSTEM_SAVER_DIR"; do
        [ "$path" = "$dir/$BUNDLE_NAME" ] && return 0
    done
    return 1
}

# ByHost preferences are named <domain>.<UUID>.plist. Matching the UUID with a
# real pattern rather than * means a future sub-domain can only ever be removed
# deliberately.
valid_byhost_plist() {
    [[ "$(basename "$1")" =~ ^com\.ilirium\.Starfield\.[0-9A-Fa-f-]{36}\.plist$ ]]
}

# Plain Preferences holds Tools/Render's scratch domain, which has no UUID.
valid_prefs_plist() {
    [[ "$(basename "$1")" =~ ^com\.ilirium\.Starfield(\.[A-Za-z0-9_-]+)?\.plist$ ]]
}

# Tile cache entries are content-addressed: 64 lowercase hex digits.
valid_cache_entry() {
    [[ "$(basename "$1")" =~ ^[0-9a-f]{64}\.png$ ]]
}

# A bundle at the right path could still be somebody else's saver that happens
# to share the name, so confirm the identity before removing it.
bundle_is_ours() {
    local plist="$1/Contents/Info.plist" id
    [ -f "$plist" ] || return 0   # no plist to disagree with; the path is ours
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
    [ -z "$id" ] || [ "$id" = "$BUNDLE_ID" ]
}

# ---------------------------------------------------------------------------
# The tile cache, and --refresh-preview
#
# System Settings caches the Screen Saver pane's tiles per module, and nothing
# about the bundle invalidates an entry -- not changed content, not replacing
# the bundle, not a version bump (AING-0006 §2). There is no supported
# invalidation call, so removing the files is the only lever.
#
# A plain uninstall deliberately does NOT do this: clearing every other saver's
# tile is not what someone removing one saver asked for (AING-0006 §5).
# ---------------------------------------------------------------------------

collect_cache_entries() {
    local f
    for f in "$STARFIELD_THUMBCACHE_DIR"/*.png; do
        valid_cache_entry "$f" && printf '%s\n' "$f"
    done
}

refresh_preview() {
    local entries=() f
    while IFS= read -r f; do entries+=("$f"); done < <(collect_cache_entries)

    if [ ! -d "$STARFIELD_THUMBCACHE_DIR" ]; then
        say "No preview cache at $STARFIELD_THUMBCACHE_DIR -- nothing to refresh."
        return 0
    fi
    if [ ${#entries[@]} -eq 0 ]; then
        say "Preview cache is already empty."
        return 0
    fi

    say "Preview cache: ${#entries[@]} tile(s) in $STARFIELD_THUMBCACHE_DIR"
    if [ "$DRY_RUN" = 1 ]; then
        say "(dry run -- nothing removed)"
        return 0
    fi

    rm -f "${entries[@]}"
    say "Cleared ${#entries[@]} cached tile(s)."

    if [ "$HERMETIC" = 0 ]; then
        killall WallpaperLegacyExtension 2>/dev/null || true
        say "Quit System Settings if it is open -- it caches the module list separately."
    fi
}

if [ "$REFRESH_ONLY" = 1 ]; then
    refresh_preview
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Collect
# ---------------------------------------------------------------------------

# Arrays are expanded as ${ARR[@]+"${ARR[@]}"} throughout: macOS ships bash 3.2,
# where "${ARR[@]}" on an empty array trips `set -u` as an unbound variable.
BUNDLES=()
[ -e "$STARFIELD_USER_SAVER_DIR/$BUNDLE_NAME" ] && BUNDLES+=("$STARFIELD_USER_SAVER_DIR/$BUNDLE_NAME")
if [ "$ALL_USERS" = 1 ] && [ -e "$STARFIELD_SYSTEM_SAVER_DIR/$BUNDLE_NAME" ]; then
    BUNDLES+=("$STARFIELD_SYSTEM_SAVER_DIR/$BUNDLE_NAME")
fi

PLISTS=()
if [ "$KEEP_SETTINGS" = 0 ]; then
    for f in "$STARFIELD_CONTAINER_BYHOST_DIR/$DOMAIN".*.plist; do
        valid_byhost_plist "$f" && PLISTS+=("$f")
    done
    for f in "$STARFIELD_BYHOST_DIR/$DOMAIN".*.plist; do
        valid_byhost_plist "$f" && PLISTS+=("$f")
    done
    for f in "$STARFIELD_PREFS_DIR/$DOMAIN"*.plist; do
        valid_prefs_plist "$f" && PLISTS+=("$f")
    done
fi

if [ ${#BUNDLES[@]} -eq 0 ] && [ ${#PLISTS[@]} -eq 0 ]; then
    say "Starfield does not appear to be installed. Nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Check everything is removable before removing anything
#
# A partial uninstall that fails halfway is worse than one that refuses up
# front.
# ---------------------------------------------------------------------------

NEED_SUDO=0
for b in ${BUNDLES[@]+"${BUNDLES[@]}"}; do
    valid_bundle_path "$b" || die "refusing to remove an unexpected path: $b"
    bundle_is_ours "$b"    || die "$b is not this saver (its CFBundleIdentifier is not $BUNDLE_ID). Refusing."
    parent="$(dirname "$b")"
    if [ ! -w "$parent" ]; then
        if [ "$parent" = "$STARFIELD_SYSTEM_SAVER_DIR" ]; then
            NEED_SUDO=1
        else
            die "cannot remove $b -- $parent is not writable."
        fi
    fi
done
for p in ${PLISTS[@]+"${PLISTS[@]}"}; do
    valid_byhost_plist "$p" || valid_prefs_plist "$p" || die "refusing to remove an unexpected path: $p"
    [ -w "$(dirname "$p")" ] || die "cannot remove $p -- its directory is not writable."
done

if [ "$NEED_SUDO" = 1 ] && ! command -v sudo >/dev/null 2>&1; then
    die "$STARFIELD_SYSTEM_SAVER_DIR needs elevation and sudo is not available."
fi

# ---------------------------------------------------------------------------
# 3. Warn if this is the selected saver. Never write to Apple's plists.
# ---------------------------------------------------------------------------

if [ "$HERMETIC" = 0 ] && [ ${#BUNDLES[@]} -gt 0 ]; then
    selected="$(defaults -currentHost read com.apple.screensaver moduleDict 2>/dev/null || true)"
    name="$(defaults -currentHost read com.apple.screensaver moduleName 2>/dev/null || true)"
    if [[ "$selected" == *"$BUNDLE_NAME"* ]] || [[ "$name" == *"Starfield"* ]]; then
        warn "Note: Starfield appears to be the selected screen saver."
        warn "      macOS will fall back to another one; this script does not change your choice."
    fi
fi

# ---------------------------------------------------------------------------
# 4. Confirm
# ---------------------------------------------------------------------------

say "Will remove:"
for b in ${BUNDLES[@]+"${BUNDLES[@]}"}; do say "  $b"; done
for p in ${PLISTS[@]+"${PLISTS[@]}"}; do say "  $p"; done
[ "$KEEP_SETTINGS" = 1 ] && say "  (keeping Density and WarpSpeed)"
[ "$NEED_SUDO" = 1 ] && say "  (one of these needs sudo)"

if [ "$DRY_RUN" = 1 ]; then
    say
    say "Dry run -- nothing was removed."
    exit 0
fi

if [ "$ASSUME_YES" = 0 ]; then
    printf 'Continue? [y/N] '
    read -r reply
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) say "Cancelled."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------------------
# 5. Stop the clients, before removing anything
#
# Order is load-bearing. A live client holding the preferences domain open
# keeps its values in cfprefsd, and its next write recreates the plist with the
# old values in it -- so deleting the file first does not remove the setting
# (AING-0005 §2.1). legacyScreenSaver is exactly such a client, and it stays
# running on macOS 14+ even while the screen is unblanked.
# ---------------------------------------------------------------------------

if [ "$HERMETIC" = 0 ]; then
    killall legacyScreenSaver 2>/dev/null || true
    say "Quit System Settings if it is open -- it holds saver bundles open separately."
fi

# ---------------------------------------------------------------------------
# 6. Remove the bundles
# ---------------------------------------------------------------------------

for b in ${BUNDLES[@]+"${BUNDLES[@]}"}; do
    # -h, not -e: a developer may have symlinked build/Starfield.saver here, and
    # the link should go rather than whatever it points at.
    if [ -L "$b" ]; then
        rm "$b"
        say "Removed symlink $b"
    elif [ "$NEED_SUDO" = 1 ] && [ ! -w "$(dirname "$b")" ]; then
        sudo rm -rf "$b"
        say "Removed $b"
    else
        rm -rf "$b"
        say "Removed $b"
    fi
done

# ---------------------------------------------------------------------------
# 7. Remove the settings
# ---------------------------------------------------------------------------

if [ "$KEEP_SETTINGS" = 0 ]; then
    if [ "$HERMETIC" = 0 ]; then
        # Reports the domain gone but leaves the plist on disk, so the file
        # removal below is not redundant. Neither operation alone suffices.
        defaults -currentHost delete "$DOMAIN" 2>/dev/null || true
    fi

    for p in ${PLISTS[@]+"${PLISTS[@]}"}; do
        rm -f "$p"
        say "Removed $p"
    done

    if [ "$HERMETIC" = 0 ]; then
        killall -u "$USER" cfprefsd 2>/dev/null || true
    fi
fi

say
say "Done."
if [ "$HERMETIC" = 0 ]; then
    say "If the Screen Saver pane still shows a Starfield thumbnail, run:"
    say "  ./uninstall.sh --refresh-preview"
fi
