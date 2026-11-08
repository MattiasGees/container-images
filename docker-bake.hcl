# Builds every image together, so spire-tools and spire-server always use the
# ubuntu-tools built from this checkout rather than the published one.
#
# Images are tagged for local testing by default. CI overrides these variables
# when it publishes.
variable "REPOSITORY" {
  default = "container-images-test"
}

variable "TAG" {
  default = "test"
}

variable "SPIRE_SERVER_TAG" {
  default = "test"
}

group "default" {
  targets = ["ubuntu-tools", "spire-tools", "spire-server"]
}

target "_common" {
  platforms = ["linux/amd64", "linux/arm64"]
}

target "ubuntu-tools" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile"
  tags       = ["${REPOSITORY}/ubuntu-tools:${TAG}"]
}

target "spire-tools" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile.spire-tools"
  contexts = {
    "ghcr.io/mattiasgees/container-images/ubuntu-tools:latest" = "target:ubuntu-tools"
  }
  tags = ["${REPOSITORY}/spire-tools:${TAG}"]
}

target "spire-server" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile.spire-server"
  contexts = {
    "ghcr.io/mattiasgees/container-images/ubuntu-tools:latest" = "target:ubuntu-tools"
  }
  tags = ["${REPOSITORY}/spire-server:${SPIRE_SERVER_TAG}"]
}
