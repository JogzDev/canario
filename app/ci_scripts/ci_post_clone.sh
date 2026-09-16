#!/bin/sh
# Preparação reproduzível do Xcode Cloud. Este script instala somente a
# configuração pública de exemplo e valida a lógica Swift sem rede do app.
set -eu
umask 077

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH ausente}"
cp "$REPO_ROOT/Config.xcconfig.example" "$REPO_ROOT/Config.xcconfig"
swift test --package-path "$REPO_ROOT/app"
