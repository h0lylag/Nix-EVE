#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl
# shellcheck shell=bash
# Updates package.nix to the newest EVE Online launcher installer.
set -euo pipefail
# Let set -e also stop the script inside $(...).
shopt -s inherit_errexit

package_file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/package.nix"
installer_base_url='https://launcher.ccpgames.com/eve-online/release/win32/x64'
version_line='^  version = "([0-9]+\.[0-9]+\.[0-9]+)";$'
hash_line='^    hash = "sha256-[A-Za-z0-9+/=]+";$'
# The hash must correspond to the URL template that Nix will fetch.
url_line="    url = \"$installer_base_url/eve-online-\${version}+Setup.exe\";"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

check_package_file() {
  if [[ "$(grep -Ec "$version_line" "$package_file")" -ne 1 \
    || "$(grep -Ec "$hash_line" "$package_file")" -ne 1 ]]; then
    fail "Expected one version and one installer hash in $package_file"
  fi
  grep -Fxq "$url_line" "$package_file" \
    || fail "Installer URL in $package_file differs from this updater."
}

latest_version() {
  local manifest line version=''
  local release_pattern='^[[:xdigit:]]{40}[[:space:]]+eve-online-([0-9]+[.][0-9]+[.][0-9]+)-full[.]nupkg[[:space:]]+[0-9]+$'
  manifest="$(curl --fail --location --silent --show-error \
    --proto '=https' --proto-redir '=https' "$installer_base_url/RELEASES")"

  # Each RELEASES line lists a package hash, filename, and size. The last
  # full package filename supplies the version for the Setup.exe URL.
  while IFS= read -r line; do
    if [[ "$line" =~ $release_pattern ]]; then
      version="${BASH_REMATCH[1]}"
    fi
  done <<<"$manifest"
  [[ -n "$version" ]] || fail 'Could not find a full launcher package in RELEASES.'

  printf '%s\n' "$version"
}

# Downloads the installer into the Nix store and prints its hash. Using the
# name fetchurl uses gives the same store path, so the next build reuses it.
# The RELEASES hash covers the .nupkg, not Setup.exe, so Nix hashes it here.
prefetch_installer() {
  local name="$1" prefetch
  local hash_pattern='"hash":"(sha256-[A-Za-z0-9+/=]+)"'
  prefetch="$(nix store prefetch-file --json --name "$name" "$installer_base_url/$name")"
  [[ "$prefetch" =~ $hash_pattern ]] \
    || fail 'Could not read the installer hash from nix store prefetch-file.'
  printf '%s\n' "${BASH_REMATCH[1]}"
}

update_package() {
  local version="$1" hash="$2"
  sed -i -E \
    -e "s|$version_line|  version = \"$version\";|" \
    -e "s|$hash_line|    hash = \"$hash\";|" \
    "$package_file"
}

check_package_file
current="$(sed -nE "s/$version_line/\1/p" "$package_file")"
version="$(latest_version)"
if [[ "$version" == "$current" ]]; then
  printf 'Already at %s\n' "$version"
  exit 0
fi

hash="$(prefetch_installer "eve-online-$version+Setup.exe")"
update_package "$version" "$hash"
printf 'Updated %s from %s to %s\nHash: %s\n' "$package_file" "$current" "$version" "$hash"
