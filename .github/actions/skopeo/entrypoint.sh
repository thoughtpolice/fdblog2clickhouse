#! /usr/bin/env bash

# Entrypoint that runs Skopeo Copy

[ "$DEBUG" = "1" ] && set -x
set -e

# sanitize env
[ "$GITHUB_SHA" = "" ] && \
  echo "GITHUB_SHA must be configured!" && exit 1

registry="docker://thoughtpolice/fdblog2clickhouse"

# get required tags
nixtag=$(nix eval --raw -f default.nix "docker.imageTag")
alltags=("$nixtag")

if [ ! "$GITHUB_REF" = "" ]; then
  reftag="${GITHUB_REF##*/}"
  alltags+=("$reftag")

  echo using GITHUB_REF tag "$reftag"
  if [[ "$reftag" == "master" ]]; then
    alltags+=("latest")
    echo "master branch: tagging image with 'latest'"
  fi
fi

# do the business
echo using "$(skopeo --version)"
echo using tags: "$(for x in "${alltags[@]}"; do echo -n "$x "; done)"

for t in "${alltags[@]}"; do
  skopeo copy "docker-archive:fdblog2clickhouse-$nixtag.tar.gz" "${registry}:${t}"
done
