set -x

/dlv --log --listen=:4567 --continue --headless=true --accept-multiclient --api-version=2 exec /entry -- $@

