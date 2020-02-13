#!/bin/bash

build_failure() {
    local component=$1
    local package_set=$2
    local dist=$3
    local build_log_url=$4

    local RELEASE
    # don't let the API key be logged...
    local GITHUB_API_KEY
    local GITHUB_BUILD_ISSUES_REPO
    RELEASE=$(make -s get-var GET_VAR=RELEASE)
    GITHUB_API_KEY=$(make -s get-var GET_VAR=GITHUB_API_KEY)
    GITHUB_BUILD_ISSUES_REPO=$(make -s get-var GET_VAR=GITHUB_BUILD_ISSUES_REPO)
    echo "Build failed: $component for $package_set (r$RELEASE $dist)" >&2
    if [ -z "$GITHUB_API_KEY" ] || [ -z "$GITHUB_BUILD_ISSUES_REPO" ]; then
        echo "No alternative way of build failure reporting (GITHUB_API_KEY, GITHUB_BUILD_ISSUES_REPO), exiting" >&2
        exit 1
    fi
    curl -H "Authorization: token $GITHUB_API_KEY" \
		-d "{ \"title\": \"Build failed: $component for $package_set ($RELEASE $dist)\",
              \"body\": \"See $build_log_url for details\" }" \
        "https://api.github.com/repos/$GITHUB_BUILD_ISSUES_REPO/issues"
}

get_build_log_url() {
    local log_name
    log_name=$(cat "$log_service_output_file" 2>/dev/null || :)
    GITHUB_LOGS_REPO=$(make -s get-var GET_VAR=GITHUB_LOGS_REPO)
    if [ -z "$log_name" ]; then
        echo "https://github.com/${GITHUB_LOGS_REPO:-QubesOS/logs}/tree/master/$(hostname)"
    else
        echo "https://github.com/${GITHUB_LOGS_REPO:-QubesOS/logs}/tree/master/$log_name"
    fi
}

cleanup() {
    if [ -d "$tmpdir" ]; then
        rm -rf "$tmpdir"
    fi
}

tmpdir=$(mktemp -d)

trap "cleanup" EXIT

log_service_output_file="$tmpdir/build-log-filename"

# enable logging (use qrexec policy to redirect to the right VM)
export QUBES_BUILD_LOG_CMD="qrexec-client-vm 'dom0' qubesbuilder.BuildLog >$log_service_output_file"

