#! /usr/bin/env bash

# Entrypoint that runs nix-build and, optionally, copies Docker image tarballs
# to real files. The reason this is necessary is because once a Nix container
# exits, you must copy out the artifacts to the working directory before exit.

[ "$DEBUG" = "1" ] && set -x
[ "$QUIET" = "1" ] && QUIET_ARG="-Q"

set -e

echo "Building everything..."
nix-build --no-link default.nix

echo "Building docker image..."
docker=$(nix-build --no-link ${QUIET_ARG} default.nix -A "docker")
version=$(nix eval --raw -f default.nix "docker.imageTag")

echo "Copying Docker Tarball"
echo "  to:      fdblog2clickhouse-$version.tar.gz"
echo "  from:    $docker"
echo "  version: $version"
cp -fL "$docker" "fdblog2clickhouse-$version.tar.gz"
