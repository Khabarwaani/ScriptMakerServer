#!/bin/sh
set -eu

package_path=${1:?Usage: embed-agentatom.sh PACKAGE_PATH [debug|release]}
configuration=${2:-debug}
case "$configuration" in debug|release) ;; *) echo 'Expected debug or release' >&2; exit 2 ;; esac
bin_path=$(swift build --package-path "$package_path" -c "$configuration" --show-bin-path)
artifact="$package_path/.build/artifacts/agentatom/AgentAtom/AgentAtom.xcframework"
framework="$artifact/macos-arm64_x86_64/AgentAtom.framework"
[ -d "$framework" ] || { echo 'Resolve AgentAtom before embedding' >&2; exit 1; }
[ -d "$bin_path" ] || { echo 'Build the package before embedding' >&2; exit 1; }
ditto "$framework" "$bin_path/AgentAtom.framework"
mkdir -p "$bin_path/AgentAtomNotices/ThirdPartyNotices"
for notice in LICENSE COPYRIGHT THIRD_PARTY_NOTICES.md ThirdPartyNotices/TypeDecoder-LICENSE.txt; do
    cp "$artifact/$notice" "$bin_path/AgentAtomNotices/$notice"
done
