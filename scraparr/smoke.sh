# scraparr exits without at least one connector, so point one at nothing
cat >> /etc/conf.d/scraparr <<'CONF'
export SONARR_URL=http://127.0.0.1:1
export SONARR_API_KEY=dummy
CONF
