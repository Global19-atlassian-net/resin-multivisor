#!/bin/sh

set -e

[ -d /dev/net ] ||
    mkdir -p /dev/net
[ -c /dev/net/tun ] ||
    mknod /dev/net/tun c 10 200

cd /app
./wrapdocker

DATA_DIRECTORY=/data
if [ -d "$DATA_DIRECTORY" ]; then
	cp bin/enter.sh $DATA_DIRECTORY/enter.sh
	chmod +x $DATA_DIRECTORY/enter.sh
fi

mkdir -p /var/log/supervisor && touch /var/log/supervisor/supervisord.log
mkdir -p /var/run/resin
mount -t tmpfs -o size=1m tmpfs /var/run/resin

/usr/bin/supervisord -c /etc/supervisor/supervisord.conf

supervisorctl start resin-supervisor

tail -f /var/log/supervisor/supervisord.log &
tail -f /var/log/resin_supervisor_stderr.log &
tail -f /var/log/resin_supervisor_stdout.log
