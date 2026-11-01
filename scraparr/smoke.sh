set -eu

# scraparr exits without at least one connector, so point one at nothing
cat >> /etc/conf.d/scraparr <<'CONF'
export SONARR_URL=http://127.0.0.1:1
export SONARR_API_KEY=dummy
CONF

# A dead backend never reaches clear(), so starting the service can't catch a
# client that's too old. Check the copy the wrapper actually imports.
cd /usr/lib/scraparr
python3 -c "from prometheus_client import Gauge; Gauge.remove_by_labels"
