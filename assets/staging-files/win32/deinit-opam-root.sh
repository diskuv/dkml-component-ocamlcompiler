#!/bin/bash
# -------------------------------------------------------
# deinit-opam-root.sh PLATFORM
#
# Purpose:
# 1. Unregister former Opam roots and switches from previous installs
#
# -------------------------------------------------------
set -euf

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    deinit-opam-root.sh -h                   Display this help message" >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -d DKMLDIR: Location of directory with .dkmlroot" >&2
    printf "%s\n" "    -o OPAMEXE: The opam to use. If there is an opam shim the opam-real can be used" >&2
}

# shellcheck disable=SC2034
USERMODE=ON
# shellcheck disable=SC2034
STATEDIR=
OPAMEXE=
DKMLDIR=
while getopts ":ho:d:" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        o )
            # shellcheck disable=SC2034
            OPAMEXE=$OPTARG
            ;;
        d )
            DKMLDIR=$OPTARG
            ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

# END Command line processing
# ------------------

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/_common_tool.sh

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the TOPDIR (just like the container
# sets the directory to be /work mounted to TOPDIR)
cd "$TOPDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# ---------------------
# BEGIN Version Cleanup

uninstall_opam_root() {
    uninstall_opam_root_OLDOPAMROOT="$1"
    "$OPAMEXE" switch list --root "$uninstall_opam_root_OLDOPAMROOT" --short > "$WORK"/list
    while IFS= read -r sw
    do
        trimmed_switch=$(printf "%s" "$sw" | awk 'NF>0{print $1}')
        if [ -z "$trimmed_switch" ] || [ "$trimmed_switch" = "/" ]; then
            echo "Unsafe switch deletion: $trimmed_switch" >&2
            exit 2
        fi
        clear
        echo "The OPAM root has changed to $LOCALAPPDATA/opam in 0.2.x." >&2
        echo "    >>> All Diskuv OCaml switches must be deleted and recreated. <<<" >&2
        echo "    >>> Even critical switches like 'diskuv-boot-DO-NOT-DELETE' must be deleted. <<<" >&2
        echo "After the upgrade use './makeit prepare-dev' to recreate each of your Local Projects (if any)." >&2
        echo "Full instructions are at https://gitlab.com/diskuv/diskuv-ocaml/-/blob/main/contributors/changes/v0.2.0.md#upgrading-from-v010-or-v011-to-v020" >&2
        echo "" >&2
        echo "If you say anything other than 'yes' the installation will abort." >&2
        echo "" >&2
        read -r -p "Candidate for deletion: $trimmed_switch. Are you sure (yes/no)? Type 'yes' to proceed. " yesno
        case "$yesno" in
        yes ) echo "Deleting ...";;
        * )
            echo "Did not type 'yes'. Exiting." >&2
            exit 1
            ;;
        esac
        "$OPAMEXE" switch remove --root "$uninstall_opam_root_OLDOPAMROOT" --yes "$trimmed_switch"
    done < "$WORK"/list
    rm -rf "$uninstall_opam_root_OLDOPAMROOT"
}

# shellcheck disable=SC2154
case "$dkml_root_version" in
    0.2.0*)
        # $env:USERPROFILE/.opam is no longer used
        if [ -n "${USERPROFILE:-}" ] && [ -e "${USERPROFILE:-}/.opam/diskuv-boot-DO-NOT-DELETE" ]; then
            uninstall_opam_root "${USERPROFILE:-}"/.opam
            clear
        fi
        # $env:LOCALAPPDATA/.opam is no longer used
        if [ -n "${LOCALAPPDATA:-}" ] && [ -e "${LOCALAPPDATA:-}/.opam/diskuv-boot-DO-NOT-DELETE" ]; then
            uninstall_opam_root "${LOCALAPPDATA:-}"/.opam
            clear
        fi
        ;;
    0.4.0*)
        # $env:USERPROFILE/.opam/diskuv-boot-DO-NOT-DELETE switch is no longer used
        if [ -n "${USERPROFILE:-}" ] && [ -e "${USERPROFILE:-}/.opam/diskuv-boot-DO-NOT-DELETE" ]; then
            "$OPAMEXE" switch remove --root "${USERPROFILE:-}"/.opam --yes diskuv-boot-DO-NOT-DELETE
        fi
        # $env:LOCALAPPDATA/.opam/diskuv-boot-DO-NOT-DELETE switch is no longer used
        if [ -n "${LOCALAPPDATA:-}" ] && [ -e "${LOCALAPPDATA:-}/.opam/diskuv-boot-DO-NOT-DELETE" ]; then
            "$OPAMEXE" switch remove --root "${LOCALAPPDATA:-}"/.opam --yes diskuv-boot-DO-NOT-DELETE
        fi
        # $env:LOCALAPPDATA/opam/diskuv-boot-DO-NOT-DELETE switch is no longer used
        if [ -n "${LOCALAPPDATA:-}" ] && [ -e "${LOCALAPPDATA:-}/opam/diskuv-boot-DO-NOT-DELETE" ]; then
            "$OPAMEXE" switch remove --root "${LOCALAPPDATA:-}"/opam --yes diskuv-boot-DO-NOT-DELETE
        fi
        ;;
esac

# END Version Cleanup
# ---------------------
