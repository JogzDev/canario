#!/bin/sh
# Preparação reproduzível do Xcode Cloud. Este script instala somente a
# configuração pública de exemplo e valida a lógica Swift sem rede do app.
set -eu
umask 077

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    echo 'Preparação disponível somente no ambiente do Xcode Cloud.' >&2
    exit 1
fi

# A ação Test usa build-for-testing e test-without-building. Não se chama
# "test" nesta variável. O modelo ainda não serve para distribuir o app.
case "${CI_XCODEBUILD_ACTION:-}" in
    build|build-for-testing|test-without-building) ;;
    archive)
        echo 'Archive bloqueado: a configuração de exemplo contém placeholders.' >&2
        exit 1
        ;;
    *)
        echo 'Configuração de exemplo aceita somente ações Build/Test do Xcode Cloud.' >&2
        exit 1
        ;;
esac

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH ausente}"
cp "$REPO_ROOT/Config.xcconfig.example" "$REPO_ROOT/Config.xcconfig"
swift test --package-path "$REPO_ROOT/app"
