#!/usr/bin/env bash
# Build OKMOD, run the guard, then restart the 1106 XenProxy.
# The service serves this tree directly: no /opt copy, no publish step.
set -euo pipefail
cd "$(dirname "$0")"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BIN="build/okmod-R8-AIM-ESP.bin"
UNIT="okmod-xenproxy"
mkdir -p backup/patches logs

echo "[1/7] backup current payload"
if [ -f "$BIN" ]; then
  cp -a "$BIN" "backup/patches/patch.pre-clean-${TS}.bin"
fi

echo "[2/7] build"
(cd build && python3 build.py)

echo "[3/7] core guard"
./buildkit/tools/core_guard.sh \
  --candidate "$BIN" \
  --report build/build-aim-report.json \
  --mode r8-aim

echo "[4/7] publish PAC"
cp -f proxy/pac-1297.js proxy/pac.resolved.js /var/www/okmod-1297/

echo "[5/7] telemetry guard test"
python3 proxy/xenproxy/test_guard.py

echo "[6/7] install/refresh XenProxy unit"
# XenProxy reads xenproxy-* names from the same confdir the mitmproxy CA lives
# in, so the CA already trusted by devices keeps working.
[ -e proxy/conf/xenproxy-ca.pem ] || ln -sf mitmproxy-ca.pem proxy/conf/xenproxy-ca.pem
[ -e proxy/conf/xenproxy-dhparam.pem ] || ln -sf mitmproxy-dhparam.pem proxy/conf/xenproxy-dhparam.pem
[ -e proxy/conf/xenproxy-ca-cert.pem ] || ln -sf mitmproxy-ca-cert.pem proxy/conf/xenproxy-ca-cert.pem
install -m 0644 proxy/okmod-xenproxy.service "/etc/systemd/system/${UNIT}.service"
systemctl daemon-reload
systemctl enable "$UNIT" >/dev/null 2>&1 || true
systemctl restart "$UNIT"
sleep 5

echo "[7/7] verify through the proxy"
python3 proxy/xenproxy/verify.py --proxy http://127.0.0.1:1106 --payload "$BIN"

sha256sum "$BIN"
systemctl is-active "$UNIT"
echo "backup payload: backup/patches/patch.pre-clean-${TS}.bin"
echo "rollback: cp backup/patches/patch.pre-clean-${TS}.bin $BIN && systemctl restart $UNIT"
