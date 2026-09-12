#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IOS_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
WEB_ROOT=${HOSTWATCH_WEB_ROOT:-"$IOS_ROOT/../hostwatch"}

npm --prefix "$WEB_ROOT/apps/web" run build:ios-topology
rm -rf "$IOS_ROOT/Hostwatch/TopologyRenderer"
mkdir -p "$IOS_ROOT/Hostwatch/TopologyRenderer"
cp -R "$WEB_ROOT/apps/web/dist-ios-topology/." "$IOS_ROOT/Hostwatch/TopologyRenderer/"
