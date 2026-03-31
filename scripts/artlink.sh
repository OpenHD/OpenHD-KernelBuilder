#!/bin/bash

ARTLINK_REPO=${ARTLINK_REPO:-https://github.com/OpenHD-Technologies/OpenHD-ArtLink.git}
ARTLINK_BRANCH=${ARTLINK_BRANCH:-main}
ARTLINK_REPO_DIR=${ARTLINK_REPO_DIR:-OpenHD-ArtLink}

# Reuse the OpenHD secret contract when present.
ARTLINK_DOWNLOAD_URL=${ARTLINK_DOWNLOAD_URL:-${DOWNLOAD_URL:-}}
ARTLINK_DOWNLOAD_KEY=${ARTLINK_DOWNLOAD_KEY:-${DOWNLOAD_KEY:-}}
ARTLINK_GIT_AUTH_USERNAME=${ARTLINK_GIT_AUTH_USERNAME:-raphael@openhdfpv.org}
ARTLINK_GIT_TOKEN=${ARTLINK_GIT_TOKEN:-${OPENHD_SUBMODULE_TOKEN:-}}
ARTLINK_GIT_AUTH=${ARTLINK_GIT_AUTH:-${ARTLINK_DOWNLOAD_KEY:-}}

if [[ -z "${ARTLINK_GIT_AUTH}" && -n "${ARTLINK_GIT_TOKEN}" ]]; then
    ARTLINK_GIT_AUTH="${ARTLINK_GIT_AUTH_USERNAME}:${ARTLINK_GIT_TOKEN}"
fi

function _artlink_git_auth_basic() {
    if [[ -z "${ARTLINK_GIT_AUTH}" ]]; then
        return 1
    fi

    local raw_auth
    if [[ "${ARTLINK_GIT_AUTH}" == *:* ]]; then
        raw_auth="${ARTLINK_GIT_AUTH}"
    else
        raw_auth="x-access-token:${ARTLINK_GIT_AUTH}"
    fi

    # shellcheck disable=SC2005
    echo "$(printf '%s' "${raw_auth}" | base64 | tr -d '\n')"
}

function _artlink_git() {
    local auth_b64
    auth_b64=$(_artlink_git_auth_basic) || true

    if [[ -n "${auth_b64}" && "${ARTLINK_REPO}" == https://github.com/* ]]; then
        GIT_TERMINAL_PROMPT=0 git -c http.https://github.com/.extraheader="AUTHORIZATION: basic ${auth_b64}" "$@"
    else
        GIT_TERMINAL_PROMPT=0 git "$@"
    fi
}

function _artlink_repo_path() {
    echo "${SRC_DIR}/workdir/mods/${ARTLINK_REPO_DIR}"
}

function _extract_artlink_archive() {
    local archive="$1"
    local extract_dir="$2"

    rm -rf "${extract_dir}" || exit 1
    mkdir -p "${extract_dir}" || exit 1

    if tar -xf "${archive}" -C "${extract_dir}" >/dev/null 2>&1; then
        return 0
    fi

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "${archive}" -d "${extract_dir}" || exit 1
        return 0
    fi

    echo "Unable to extract ArtLink archive (${archive}). Provide a tar.* archive or install unzip." >&2
    exit 1
}

function fetch_artlink_driver() {
    local repo_dir
    repo_dir="$(_artlink_repo_path)"

    mkdir -p "${SRC_DIR}/workdir/mods" || exit 1

    if [[ -d "${repo_dir}/host_drv/driver/linux" ]]; then
        echo "ArtLink driver source already present"
        return
    fi

    rm -rf "${repo_dir}" || exit 1

    if [[ -n "${ARTLINK_DOWNLOAD_URL}" ]]; then
        local archive_path="${SRC_DIR}/workdir/mods/artlink-source.archive"
        local extract_dir="${SRC_DIR}/workdir/mods/artlink-source-extract"

        echo "Download the ArtLink driver source via secured URL"
        if [[ -n "${ARTLINK_DOWNLOAD_KEY}" ]]; then
            curl --fail --location --retry 3 -u "${ARTLINK_DOWNLOAD_KEY}" --output "${archive_path}" "${ARTLINK_DOWNLOAD_URL}" || exit 1
        else
            curl --fail --location --retry 3 --output "${archive_path}" "${ARTLINK_DOWNLOAD_URL}" || exit 1
        fi

        _extract_artlink_archive "${archive_path}" "${extract_dir}"

        local source_root
        source_root=$(find "${extract_dir}" -type d -path "*/host_drv/driver/linux" | head -n 1)
        if [[ -z "${source_root}" ]]; then
            echo "Downloaded ArtLink archive does not contain host_drv/driver/linux" >&2
            exit 1
        fi

        source_root=$(dirname "$(dirname "$(dirname "${source_root}")")")
        mv "${source_root}" "${repo_dir}" || exit 1
        rm -rf "${extract_dir}" "${archive_path}" || exit 1
    else
        echo "Download the ArtLink driver source from git"
        _artlink_git clone "${ARTLINK_REPO}" "${repo_dir}" || exit 1
    fi

    if [[ -d "${repo_dir}/.git" ]]; then
        pushd "${repo_dir}"
            _artlink_git fetch --all --tags --prune || exit 1

            if [[ -n "${ARTLINK_BRANCH}" && "${ARTLINK_BRANCH}" != "latest" ]]; then
                if _artlink_git show-ref --verify --quiet "refs/remotes/origin/${ARTLINK_BRANCH}"; then
                    _artlink_git checkout -f -B "${ARTLINK_BRANCH}" "origin/${ARTLINK_BRANCH}" || exit 1
                else
                    _artlink_git checkout -f "${ARTLINK_BRANCH}" || exit 1
                fi
            fi
        popd
    fi

    if [[ ! -d "${repo_dir}/host_drv/driver/linux" ]]; then
        echo "ArtLink driver source missing expected host_drv/driver/linux path" >&2
        exit 1
    fi
}

function build_artlink_driver() {
    local repo_dir driver_dir kernel_build_dir target_kernel_version module_dst firmware_dst

    repo_dir="$(_artlink_repo_path)"
    driver_dir="${repo_dir}/host_drv/driver/linux"
    kernel_build_dir="${LINUX_DIR}"
    target_kernel_version="${KERNEL_VERSION}"

    if [[ ! -d "${driver_dir}" ]]; then
        echo "ArtLink driver source not found at ${driver_dir}" >&2
        exit 1
    fi

    if [[ "${PLATFORM}" == "jetson" ]]; then
        target_kernel_version="4.9.253OpenHD-2.1-tegra"
        if [[ -d "${LINUX_DIR}/build" ]]; then
            kernel_build_dir="${LINUX_DIR}/build"
        fi
    fi

    echo "Build ArtLink driver"
    pushd "${driver_dir}"
        make -C "${kernel_build_dir}" M="$(pwd)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" clean || exit 1
        make -C "${kernel_build_dir}" M="$(pwd)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" modules || exit 1

        module_dst="${PACKAGE_DIR}/lib/modules/${target_kernel_version}/kernel/drivers/net/artlink"
        mkdir -p "${module_dst}" || exit 1
        install -p -m 644 artosyn_drv.ko "${module_dst}/artosyn_drv.ko" || exit 1
    popd

    firmware_dst="${PACKAGE_DIR}/lib/firmware/artlink"
    mkdir -p "${firmware_dst}" || exit 1
    if [[ -d "${repo_dir}/file/firmware_14G" ]]; then
        cp -af "${repo_dir}/file/firmware_14G" "${firmware_dst}/" || exit 1
    fi
    if [[ -d "${repo_dir}/file/firmware_24G" ]]; then
        cp -af "${repo_dir}/file/firmware_24G" "${firmware_dst}/" || exit 1
    fi
}
