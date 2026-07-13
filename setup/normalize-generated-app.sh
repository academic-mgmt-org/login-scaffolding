#!/usr/bin/env bash

set -Eeuo pipefail

readonly APP_DIR="${1:-.}"

if [ ! -f "$APP_DIR/artisan" ] || [ ! -f "$APP_DIR/composer.json" ]; then
    printf 'ERROR: Laravel application not found at %s\n' "$APP_DIR" >&2
    exit 1
fi

cd "$APP_DIR"

# git apply honors core.autocrlf on Windows. Normalize every reproducible text
# artifact so a Git Bash build and a Linux build produce identical bytes.
while IFS= read -r -d '' file; do
    sed -i 's/\r$//' "$file"
done < <(
    find app bootstrap config database proto public resources routes tests \
        -type f \
        \( \
            -name '*.blade.php' -o \
            -name '*.css' -o \
            -name '*.html' -o \
            -name '*.js' -o \
            -name '*.json' -o \
            -name '*.md' -o \
            -name '*.neon' -o \
            -name '*.php' -o \
            -name '*.proto' -o \
            -name '*.svg' -o \
            -name '*.xml' -o \
            -name '*.yaml' -o \
            -name '*.yml' \
        \) \
        -print0
)

for file in \
    .editorconfig \
    .env.example \
    .gitattributes \
    .gitignore \
    .npmrc \
    artisan \
    chisel-paths.php \
    chisel.php \
    composer.json \
    composer.lock \
    package.json \
    package-lock.json \
    phpstan-bootstrap.php \
    phpstan.neon \
    phpunit.xml \
    pint.json \
    vite.config.js; do
    if [ -f "$file" ]; then
        sed -i 's/\r$//' "$file"
    fi
done

vendor/bin/pint
