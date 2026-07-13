#!/usr/bin/env bash

set -Eeuo pipefail

# Installs the dependencies that were missing on this host. Git, Node, npm,
# Docker, Docker Compose, and unzip are validated because they were preinstalled.
# Docker Buildx and fuser (from psmisc) are installed when missing.
# Linux and Windows Git Bash use different PHP and grpcurl distributions.
readonly PHP_VERSION="8.5"
readonly GRPCURL_VERSION="1.9.3"
readonly HERD_BIN="$HOME/.config/herd-lite/bin"
readonly LOCAL_BIN="$HOME/.local/bin"
readonly GATEWAY="academia-dev.eastus2.cloudapp.azure.com:50050"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Linux*)
        readonly HOST_PLATFORM="linux"
        readonly EXECUTABLE_SUFFIX=""
        ;;
    MINGW* | MSYS*)
        readonly HOST_PLATFORM="windows"
        readonly EXECUTABLE_SUFFIX=".exe"
        ;;
    *)
        printf 'ERROR: Unsupported operating system: %s\n' "$(uname -s)" >&2
        exit 1
        ;;
esac

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

enable_required_windows_php_extensions() {
    php_ini_file="$(php -r 'echo php_ini_loaded_file() ?: "";')"
    if [ -z "$php_ini_file" ]; then
        php_command="$(command -v php)"
        php_directory="${php_command%/*}"
        php_ini_template="$php_directory/php.ini-production"
        php_ini_file="$php_directory/php.ini"

        [ -f "$php_ini_template" ] \
            || die "Bundled PHP configuration template was not found: $php_ini_template"
        install -m 0644 "$php_ini_template" "$php_ini_file"
        log "Activated the bundled production PHP configuration"
    fi

    log "Enabling required bundled PHP extensions when necessary"
    php -r '
$required = [
    "curl", "dom", "fileinfo", "filter", "hash", "mbstring", "openssl",
    "pdo", "pdo_sqlite", "session", "tokenizer", "xml", "zip",
];
$missing = array_values(array_filter(
    $required,
    static fn (string $extension): bool => !extension_loaded($extension),
));
if ($missing === []) {
    exit(0);
}

$ini = php_ini_loaded_file();
if ($ini === false || !is_writable($ini)) {
    fwrite(STDERR, "PHP configuration is not writable: " . ($ini ?: "none") . PHP_EOL);
    exit(1);
}

$configuration = file_get_contents($ini);
if ($configuration === false) {
    fwrite(STDERR, "Unable to read PHP configuration: $ini" . PHP_EOL);
    exit(1);
}

$extensionDirectory = ini_get("extension_dir");
if (!is_dir($extensionDirectory)) {
    $extensionDirectory = dirname(PHP_BINARY) . DIRECTORY_SEPARATOR . "ext";
    if (!is_dir($extensionDirectory)) {
        fwrite(STDERR, "Bundled PHP extension directory was not found: $extensionDirectory" . PHP_EOL);
        exit(1);
    }

    $extensionDirectory = str_replace("\\", "/", $extensionDirectory);
    $configuration .= PHP_EOL . "extension_dir=\"$extensionDirectory\"" . PHP_EOL;
}

$notConfigurable = [];
foreach ($missing as $extension) {
    $name = preg_quote($extension, "/");
    $activePattern = "/^[\\t ]*extension[\\t ]*=[\\t ]*(?:php_)?{$name}(?:\\.dll)?[\\t ]*(?:\\r)?$/mi";
    if (preg_match($activePattern, $configuration) === 1) {
        continue;
    }

    $pattern = "/^[\\t ]*;[\\t ]*extension[\\t ]*=[\\t ]*(?:php_)?{$name}(?:\\.dll)?[\\t ]*(\\r?)$/mi";
    $replacementCount = 0;
    $configuration = preg_replace_callback(
        $pattern,
        static fn (array $matches): string => "extension=$extension" . $matches[1],
        $configuration,
        1,
        $replacementCount,
    );
    if ($replacementCount !== 1) {
        $notConfigurable[] = $extension;
    }
}

if ($notConfigurable !== []) {
    fwrite(
        STDERR,
        "Missing PHP extensions cannot be enabled from $ini: "
            . implode(", ", $notConfigurable) . PHP_EOL,
    );
    exit(1);
}

if (file_put_contents($ini, $configuration, LOCK_EX) === false) {
    fwrite(STDERR, "Unable to update PHP configuration: $ini" . PHP_EOL);
    exit(1);
}

fwrite(STDOUT, "Enabled PHP extensions: " . implode(", ", $missing) . PHP_EOL);
'

    php -r '
$required = ["curl", "mbstring", "openssl", "pdo_sqlite", "zip"];
$missing = array_values(array_filter(
    $required,
    static fn (string $extension): bool => !extension_loaded($extension),
));
if ($missing !== []) {
    fwrite(STDERR, "PHP extensions failed to load: " . implode(", ", $missing) . PHP_EOL);
    exit(1);
}
'
}

for command_name in chmod curl grep install mktemp sha256sum tar tr uname; do
    require_command "$command_name"
done

if [ "$HOST_PLATFORM" = "windows" ]; then
    require_command unzip
fi

mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

if [ "$HOST_PLATFORM" = "linux" ]; then
    mkdir -p "$HERD_BIN"
    export PATH="$HERD_BIN:$PATH"
    export PHP_INI_SCAN_DIR="$HERD_BIN${PHP_INI_SCAN_DIR:+:$PHP_INI_SCAN_DIR}"
fi

php_toolchain_ready=false
if command -v php >/dev/null 2>&1 \
    && command -v composer >/dev/null 2>&1 \
    && php -r 'exit(version_compare(PHP_VERSION, "8.3.0", ">=") ? 0 : 1);' \
        >/dev/null 2>&1; then
    php_toolchain_ready=true
fi

if ! $php_toolchain_ready; then
    if [ "$HOST_PLATFORM" = "windows" ]; then
        die "PHP 8.3 or newer and Composer must be installed before running this script in Git Bash"
    fi

    log "Installing PHP $PHP_VERSION, Composer, and Laravel CLI from php.new"
    temp_installer="$(mktemp)"
    trap 'rm -f "$temp_installer"' EXIT
    curl -fsSL "https://php.new/install/linux/$PHP_VERSION" -o "$temp_installer"
    TERM=xterm /bin/bash "$temp_installer"
    rm -f "$temp_installer"
    trap - EXIT
    hash -r
else
    log "PHP and Composer are already installed"
fi

if [ "$HOST_PLATFORM" = "windows" ]; then
    enable_required_windows_php_extensions
fi

log "Updating Composer to the current stable release"
composer_command="$(command -v composer)"
composer_directory="${composer_command%/*}"
if composer_write_probe="$(mktemp "$composer_directory/.composer-write-test.XXXXXX" 2>/dev/null)"; then
    rm -f "$composer_write_probe"
    if ! composer self-update --stable --no-interaction; then
        printf 'WARNING: Composer could not update itself; continuing with the installed version.\n' >&2
    fi
else
    log "Installing the current Composer release in $LOCAL_BIN"
    composer_installer="$(mktemp)"
    trap 'rm -f "$composer_installer"' EXIT
    composer_installer_signature="$(curl -fsSL https://composer.github.io/installer.sig)"
    curl -fsSL https://getcomposer.org/installer -o "$composer_installer"
    composer_installer_checksum="$(
        php -r 'echo hash_file("sha384", $argv[1]);' "$composer_installer"
    )"
    [ "$composer_installer_checksum" = "$composer_installer_signature" ] \
        || die "Composer installer signature verification failed"
    php "$composer_installer" \
        --install-dir="$LOCAL_BIN" \
        --filename=composer \
        --quiet
    chmod 0755 "$LOCAL_BIN/composer"
    rm -f "$composer_installer"
    trap - EXIT
    hash -r
fi

composer_global_bin="$(composer global config bin-dir --absolute --no-interaction 2>/dev/null)" \
    || die "Unable to determine Composer's global bin directory"
if [ "$HOST_PLATFORM" = "windows" ]; then
    composer_global_bin="$(printf '%s' "$composer_global_bin" | tr '\\' '/')"
    if [[ "$composer_global_bin" =~ ^([[:alpha:]]):/(.*)$ ]]; then
        composer_drive="${BASH_REMATCH[1],,}"
        composer_global_bin="/$composer_drive/${BASH_REMATCH[2]}"
    else
        die "Unable to convert Composer's global bin directory for Git Bash: $composer_global_bin"
    fi
fi
export PATH="$composer_global_bin:$PATH"

readonly LARAVEL_INSTALLER_VERSION="5.28.1"
log "Ensuring Laravel CLI $LARAVEL_INSTALLER_VERSION is installed"
composer global require \
    "laravel/installer:$LARAVEL_INSTALLER_VERSION" \
    --no-interaction \
    --no-progress
hash -r

laravel --version >/dev/null 2>&1 \
    || die "Laravel CLI was installed, but it cannot be executed"

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

grpcurl_version_prefix="grpcurl"
if [ "$HOST_PLATFORM" = "windows" ]; then
    grpcurl_version_prefix="grpcurl.exe"
fi

if ! grpcurl --version 2>&1 \
    | grep -qx "$grpcurl_version_prefix v$GRPCURL_VERSION"; then
    log "Installing grpcurl $GRPCURL_VERSION"
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    if [ "$HOST_PLATFORM" = "windows" ]; then
        archive="grpcurl_${GRPCURL_VERSION}_windows_${grpcurl_arch}.zip"
    else
        archive="grpcurl_${GRPCURL_VERSION}_linux_${grpcurl_arch}.tar.gz"
    fi
    release_url="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}"

    curl -fsSL "$release_url/$archive" -o "$temp_dir/$archive"
    curl -fsSL \
        "$release_url/grpcurl_${GRPCURL_VERSION}_checksums.txt" \
        -o "$temp_dir/checksums.txt"

    checksum_line="$(tr -d '\r' < "$temp_dir/checksums.txt" | grep "  ${archive}$")" \
        || die "Checksum for $archive was not found"
    (
        cd "$temp_dir"
        printf '%s\n' "$checksum_line" | sha256sum --check --strict -
    )

    grpcurl_binary="grpcurl${EXECUTABLE_SUFFIX}"
    if [ "$HOST_PLATFORM" = "windows" ]; then
        unzip -q "$temp_dir/$archive" "$grpcurl_binary" -d "$temp_dir"
    else
        tar -xzf "$temp_dir/$archive" -C "$temp_dir" "$grpcurl_binary"
    fi
    install -m 0755 "$temp_dir/$grpcurl_binary" "$LOCAL_BIN/$grpcurl_binary"
    hash -r
    rm -rf "$temp_dir"
    trap - EXIT
else
    log "grpcurl $GRPCURL_VERSION is already installed"
fi

fuser_command="$(command -v fuser 2>/dev/null || true)"
if [ -z "$fuser_command" ]; then
    log "Installing fuser"
    if [ "$HOST_PLATFORM" = "windows" ]; then
        install -m 0755 "$SCRIPT_DIR/fuser-windows-wrapper.sh" "$LOCAL_BIN/fuser"
    else
        require_command apt-get

        fuser_apt_command=(apt-get)
        if (( EUID != 0 )); then
            require_command sudo
            fuser_apt_command=(sudo apt-get)
        fi

        "${fuser_apt_command[@]}" update
        "${fuser_apt_command[@]}" install -y --no-install-recommends psmisc
    fi
    hash -r
elif [ "$HOST_PLATFORM" = "windows" ] \
    && [ "$fuser_command" = "$LOCAL_BIN/fuser" ] \
    && grep -q 'FUSER_PORT' "$fuser_command"; then
    install -m 0755 "$SCRIPT_DIR/fuser-windows-wrapper.sh" "$LOCAL_BIN/fuser"
    hash -r
    log "fuser is already installed"
else
    log "fuser is already installed"
fi

fuser --version >/dev/null 2>&1 \
    || die "fuser was installed, but it cannot be executed"

log "Validating preinstalled system requirements"
if [ "$HOST_PLATFORM" = "windows" ]; then
    docker_command="$(command -v docker 2>/dev/null || true)"
    if [ -z "$docker_command" ]; then
        require_command wsl.exe
        log "Configuring the Docker CLI bridge to the default WSL distribution"
        install -m 0755 "$SCRIPT_DIR/docker-wsl-wrapper.sh" "$LOCAL_BIN/docker"
        hash -r
    elif [ "$docker_command" = "$LOCAL_BIN/docker" ] \
        && grep -q 'DOCKER_WSL_DISTRO' "$docker_command"; then
        install -m 0755 "$SCRIPT_DIR/docker-wsl-wrapper.sh" "$LOCAL_BIN/docker"
        hash -r
    fi
fi

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
    if [ "$HOST_PLATFORM" = "windows" ]; then
        die "Docker Buildx is missing from the Docker installation exposed to Git Bash"
    fi

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
fuser --version
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
if [ "$HOST_PLATFORM" = "windows" ]; then
    php_command="$(command -v php)"
    windows_php_bin="${php_command%/*}"
    touch "$HOME/.bashrc"
    if [ ! -e "$HOME/.bash_profile" ] \
        && [ ! -e "$HOME/.bash_login" ] \
        && [ ! -e "$HOME/.profile" ]; then
        printf '# Load interactive Git Bash settings.\n[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' \
            > "$HOME/.bash_profile"
    fi
fi
for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ]; then
        updated=false
        if ! grep -q '\.local/bin' "$profile"; then
            printf '\n# Added local bin to PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
            updated=true
        fi
        if ! grep -Fq "$composer_global_bin" "$profile"; then
            printf '\n# Composer global executables\nexport PATH="%s:$PATH"\n' \
                "$composer_global_bin" >> "$profile"
            updated=true
        fi
        if [ "$HOST_PLATFORM" = "windows" ] \
            && ! grep -Fq "$windows_php_bin" "$profile"; then
            printf '\n# Project-compatible PHP runtime\nexport PATH="%s:$PATH"\n' \
                "$windows_php_bin" >> "$profile"
            updated=true
        fi
        if [ "$HOST_PLATFORM" = "linux" ] && ! grep -q 'herd-lite/bin' "$profile"; then
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
