#!/bin/bash
# Double-clickable wrapper around uninstall.sh, for people who would rather not
# open a terminal. Finder runs a .command by opening Terminal in it, so the only
# things this has to do are find its own directory and keep the window open long
# enough to be read.
#
# It lives in packaging/ rather than Resources/, because Resources/ in this
# repository means bundle content. build.sh copies uninstall.sh into the bundle;
# this file only ever ships beside the saver in the release zip.

cd "$(dirname "$0")" || exit 1

if [ ! -x ./uninstall.sh ]; then
    echo "uninstall.sh is missing from this folder, or is not executable."
    echo "Keep both files together, or run the commands in the project README."
    echo
    printf 'Press Return to close this window. '
    read -r _
    exit 1
fi

./uninstall.sh
status=$?

echo
printf 'Press Return to close this window. '
read -r _
exit "$status"
