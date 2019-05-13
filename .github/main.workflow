workflow "Build and Publish" {
  on = "push"
  resolves = [ "Push to Docker Hub" ]
}

action "Shell Lint" {
  uses = "actions/bin/shellcheck@master"
  args = ".github/actions/nix-build/entrypoint.sh .github/actions/skopeo/entrypoint.sh"
}

action "Docker Lint" {
  uses = "docker://replicated/dockerfilelint"
  args = [ ".github/actions/nix-build/Dockerfile", ".github/actions/skopeo/Dockerfile" ]
}

action "Build Docker Image" {
  uses = "./.github/actions/nix-build"
  needs = [ "Shell Lint", "Docker Lint" ]
}

action "Docker Login" {
  uses = "actions/docker/login@master"
  secrets = [ "DOCKER_USERNAME", "DOCKER_PASSWORD" ]
  needs = [ "Build Docker Image" ]
}

action "Push to Docker Hub" {
  uses = "./.github/actions/skopeo"
  needs = [ "Docker Login" ]
}
