# ubuntu-tools
An Ubuntu container with some tools installed like OpenSSL and Curl

## Testing
`make test` builds `ubuntu-tools`, `spire-tools` and `spire-server` from this checkout and runs `tests/smoke.sh` against them, once for each platform. It checks that:

- each tool runs and reports the version its Dockerfile pins
- each downloaded binary is built for the image's architecture
- `spire-server` starts with the TPM plugin loaded

To test a single platform, for example when your Docker host can't emulate the other one:

```sh
make test PLATFORMS=linux/arm64
```

CI runs `make test` on every pull request and on `main`. Images are only published from `main`, after the tests pass.
