#!/usr/bin/env bash

set -Eeuo pipefail

# Installs the dependencies that were missing on this host. Git, Node, npm,
# Docker, Docker Compose, and unzip are validated because they were preinstalled.
# Docker Buildx is installed from the configured APT repositories when missing.
readonly PHP_VERSION="8.5"
readonly GRPCURL_VERSION="1.9.3"
readonly HERD_BIN="$HOME/.config/herd-lite/bin"
readonly LOCAL_BIN="$HOME/.local/bin"
readonly GATEWAY="academia-dev.eastus2.cloudapp.azure.com:50050"

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

for command_name in curl grep install mktemp sha256sum tar uname; do
    require_command "$command_name"
done

mkdir -p "$HERD_BIN" "$LOCAL_BIN"
export PATH="$HERD_BIN:$LOCAL_BIN:$PATH"
export PHP_INI_SCAN_DIR="$HERD_BIN${PHP_INI_SCAN_DIR:+:$PHP_INI_SCAN_DIR}"

php_toolchain_ready=true
for command_name in php composer laravel; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        php_toolchain_ready=false
    fi
done

if $php_toolchain_ready && ! php -r \
    'exit(version_compare(PHP_VERSION, "8.3.0", ">=") ? 0 : 1);'; then
    php_toolchain_ready=false
fi

if ! $php_toolchain_ready; then
    log "Installing PHP $PHP_VERSION, Composer, and Laravel CLI from php.new"
    temp_installer="$(mktemp)"
    trap 'rm -f "$temp_installer"' EXIT
    curl -fsSL "https://php.new/install/linux/$PHP_VERSION" -o "$temp_installer"
    TERM=xterm /bin/bash "$temp_installer"
    rm -f "$temp_installer"
    trap - EXIT
else
    log "PHP, Composer, and Laravel CLI are already installed"
fi

log "Updating Composer to the current stable release"
composer self-update --stable --no-interaction

case "$(uname -m)" in
    x86_64)
        grpcurl_arch="x86_64"
        ;;
    aarch64 | arm64)
        grpcurl_arch="arm64"
        ;;
    *)
        die "Unsupported grpcurl architecture: $(uname -m)"
        ;;
esac

if ! grpcurl --version 2>&1 | grep -qx "grpcurl v$GRPCURL_VERSION"; then
    log "Installing grpcurl $GRPCURL_VERSION"
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    archive="grpcurl_${GRPCURL_VERSION}_linux_${grpcurl_arch}.tar.gz"
    release_url="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}"

    curl -fsSL "$release_url/$archive" -o "$temp_dir/$archive"
    curl -fsSL \
        "$release_url/grpcurl_${GRPCURL_VERSION}_checksums.txt" \
        -o "$temp_dir/checksums.txt"

    checksum_line="$(grep "  ${archive}$" "$temp_dir/checksums.txt")" \
        || die "Checksum for $archive was not found"
    (
        cd "$temp_dir"
        printf '%s\n' "$checksum_line" | sha256sum --check --strict -
    )

    tar -xzf "$temp_dir/$archive" -C "$temp_dir" grpcurl
    install -m 0755 "$temp_dir/grpcurl" "$LOCAL_BIN/grpcurl"
    rm -rf "$temp_dir"
    trap - EXIT
else
    log "grpcurl $GRPCURL_VERSION is already installed"
fi

log "Validating preinstalled system requirements"
for command_name in git node npm docker unzip; do
    require_command "$command_name"
done

node -e '
const [major, minor] = process.versions.node.split(".").map(Number);
if (major < 20 || (major === 20 && minor < 19)) process.exit(1);
' || die "Node 20.19 or newer is required"

docker compose version >/dev/null
docker info >/dev/null || die "Docker is installed, but its daemon is not accessible"

if ! docker buildx version >/dev/null 2>&1; then
    log "Installing Docker Buildx"
    require_command apt-get
    require_command apt-cache

    apt_command=(apt-get)
    if (( EUID != 0 )); then
        require_command sudo
        apt_command=(sudo apt-get)
    fi

    "${apt_command[@]}" update

    buildx_package=""
    for package_name in docker-buildx-plugin docker-buildx; do
        if apt-cache show "$package_name" 2>/dev/null | grep '^Package:' >/dev/null; then
            buildx_package="$package_name"
            break
        fi
    done

    if [ -z "$buildx_package" ]; then
        die "Docker Buildx was not found in the configured APT repositories"
    fi

    "${apt_command[@]}" install -y "$buildx_package"
else
    log "Docker Buildx is already installed"
fi

docker buildx version >/dev/null 2>&1 \
    || die "Docker Buildx was installed, but the Docker CLI cannot load it"

php -r '
$required = [
    "curl", "dom", "fileinfo", "filter", "hash", "mbstring", "openssl",
    "pdo", "pdo_sqlite", "session", "tokenizer", "xml", "zip",
];
$missing = array_values(array_filter(
    $required,
    static fn (string $extension): bool => !extension_loaded($extension),
));
if ($missing !== []) {
    fwrite(STDERR, "Missing PHP extensions: " . implode(", ", $missing) . PHP_EOL);
    exit(1);
}
'

composer diagnose

log "Installed versions"
php --version | sed -n '1p'
composer --version
laravel --version
grpcurl --version
node --version
npm --version
docker --version
docker compose version
docker buildx version

if grpcurl -max-time 10 -plaintext "$GATEWAY" list >/dev/null; then
    log "Gateway reflection is reachable at $GATEWAY"
else
    printf 'WARNING: Dependencies are installed, but gateway reflection is unavailable at %s\n' \
        "$GATEWAY" >&2
fi

log "Configuring permanent PATH settings in shell profiles"
for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ]; then
        updated=false
        if ! grep -q '\.local/bin' "$profile"; then
            printf '\n# Added local bin to PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
            updated=true
        fi
        if ! grep -q 'herd-lite/bin' "$profile"; then
            printf '\n# Laravel / Herd-Lite PHP Toolchain\n' >> "$profile"
            printf 'export PATH="$HOME/.config/herd-lite/bin:$PATH"\n' >> "$profile"
            printf 'export PHP_INI_SCAN_DIR="$HOME/.config/herd-lite/bin${PHP_INI_SCAN_DIR:+:$PHP_INI_SCAN_DIR}"\n' >> "$profile"
            updated=true
        fi
        if [ "$updated" = true ]; then
            log "Updated $profile. Please run 'source $profile' or restart your terminal to apply changes."
        fi
    fi
done

log "Dependency setup complete"
