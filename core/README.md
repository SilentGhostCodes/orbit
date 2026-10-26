# Orbit's build of the Hiddify core

Upstream hiddify-core registers an `xray` outbound but only as a stub ("Xray is not implemented yet").
Orbit replaces it with `xray/outbound.go`, which runs each server's full Xray JSON config in the
xray-core that the core already links in. That is what makes Xray JSON subscriptions (XHTTP over a
CDN, `extra`, `xmux`, `downloadSettings`, fragment chains) work.

CI (`.github/workflows/android.yml`) checks out hiddify-core at `HIDDIFY_CORE_COMMIT`, copies
`xray/*` over `hiddify-sing-box/protocol/hiddify/xray/`, builds `hiddify-core.aar` with gomobile and
caches it until anything in this folder changes.

To move to a newer core, change `HIDDIFY_CORE_COMMIT`.
