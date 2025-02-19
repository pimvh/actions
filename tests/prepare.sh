#!/usr/bin/env bash

if [[ -n $RUNNER_DEBUG ]]; then
    set -x
fi

set -euo pipefail

SKIPPED_PACKAGES=()

SKIP=2

function skip-package {
    if [[ $pkg =~ ^pkg: ]]; then
        while read -r pkg_file; do
            echo "Skipping package $pkg_file"
            SKIPPED_PACKAGES+=("$pkg_file")
        done < <(grep -Flr "$pkg" packages)
    else
        echo "Skipping package $1"
        SKIPPED_PACKAGES+=("$1")
    fi
}

function skip-packages {
    for pkg in "$@"; do
        skip-package "$pkg"
    done
}

function is-testing-package {
    local pkg=$1
    for PKG in ${PACKAGES[@]}; do
        if [[ $pkg =~ ^pkg: ]]; then
            if grep -Fq "id: $pkg" "$PKG"; then
                return 0
            fi
        else
            if [[ $PKG == "$pkg" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

function match {
    local fn=$1
    shift
    if [[ $TARGET != *"x64"* ]]; then
        # All runners run on the x64 architecture currently. Emulation currently takes place in the application layer
        # (mason.nvim itself), and only for GitHub release sources. It's pointless to install these when not targeting x64.
        echo "Not targeting x64, skipping all provided packages."
        skip-packages "$@"
        return 0
    fi

    for pkg in "$@"; do
        if is-testing-package "$pkg"; then
            EXIT_CODE=0
            echo "Running $fn"
            "$fn" || EXIT_CODE=$?
            case "$EXIT_CODE" in
                0)
                    return 0
                    ;;
                2)
                    skip-packages "$@"
                    return 0
                    ;;
                *)
                    echo >&2 "Failed to run ${fn}"
                    return 1
                    ;;
            esac
        fi
    done
    return 0
}

function install-erlang {
    if [[ $RUNNER_OS == macOS ]]; then
        brew install erlang rebar3
        return 0
    else
        echo "setup_beam=true" >> "$GITHUB_OUTPUT"
        return 0
    fi
}

function install-ruby {
    echo "setup_ruby=true" >> "$GITHUB_OUTPUT"
    return 0
}

function install-opam {
    if [[ $RUNNER_OS == macOS ]]; then
        brew install opam
        opam init
        return 0
    elif [[ $RUNNER_OS == Linux ]]; then
        sudo add-apt-repository -y ppa:avsm/ppa
        sudo apt install -y opam
        opam init
        return 0
    elif [[ $RUNNER_OS == Windows ]]; then
        # Opam support via Chocolatey planned for 2.2
        return "$SKIP"
    fi
    return 1
}

function install-nim {
    echo "setup_nim=true" >> "$GITHUB_OUTPUT"
    return 0
}

function install-nix {
    if [[ $RUNNER_OS == Windows ]]; then
        return "$SKIP"
    fi
    echo "setup_nix=true" >> "$GITHUB_OUTPUT"
    return 0
}

function install-luarocks {
    # Maybe use https://github.com/leafo/gh-actions-luarocks in the future.
    if [[ $RUNNER_OS == macOS ]]; then
        brew install luarocks
        return 0
    fi
    return "$SKIP"
}

function install-zstd {
    if [[ $RUNNER_OS == Windows ]]; then
        choco install 7zip-zstd
        return 0
    elif [[ $RUNNER_OS == macOS ]]; then
        brew install zstd
        return 0
    fi
    return "$SKIP"
}

function install-java {
    echo "setup_java=true" >> "$GITHUB_OUTPUT"
}

function install-golang {
    echo "setup_golang=true" >> "$GITHUB_OUTPUT"
}

function install-r {
    if [[ $RUNNER_OS == Linux ]]; then
        # The "remotes" package relies on libcurl to compile R curl bindings.
        sudo apt install libcurl4-openssl-dev
        echo "setup_R=true" >> "$GITHUB_OUTPUT"
    else
        echo "setup_R=true" >> "$GITHUB_OUTPUT"
    fi
}

function install-ghc {
    echo "setup_haskell=true" >> "$GITHUB_OUTPUT"
}

if [[ $RUNNER_OS == Linux ]]; then
    sudo apt update
fi

match install-erlang "packages/erlang-ls/package.yaml"
match install-ghc "packages/haskell-language-server/package.yaml" "packages/haskell-debug-adapter/package.yaml"
match install-golang "pkg:golang"
match install-java "packages/java-language-server/package.yaml"
match install-luarocks "pkg:luarocks"
match install-nim "packages/nimlsp/package.yaml" "packages/nimlangserver/package.yaml"
match install-nix "packages/nil/package.yaml"
match install-opam "pkg:opam"
match install-r "packages/r-languageserver/package.yaml"
match install-ruby "pkg:gem"
match install-zstd "packages/zls/package.yaml"

echo "SKIPPED_PACKAGES=${SKIPPED_PACKAGES[@]+"${SKIPPED_PACKAGES[@]}"}" >> "$GITHUB_ENV"

PACKAGES_TO_TEST=""

set +u

for pkg in $PACKAGES; do
    if [[ ! " ${SKIPPED_PACKAGES[*]} " =~ " ${pkg} " ]]; then
        PACKAGES_TO_TEST="$pkg $PACKAGES_TO_TEST"
    fi
done

echo "PACKAGES=$PACKAGES_TO_TEST" >> "$GITHUB_OUTPUT"

# vim:sw=4:et
