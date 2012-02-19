#!/bin/sh

### BEGIN INIT INFO
# Provides:          djabberd
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Should-Start:      $all
# Should-Stop:       $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start/stop djabberd 
# Description:       Start/stop djabberd 
### END INIT INFO

# Original Version from http://graveyard.martinjansen.com/2006/08/06/djabberd.html
# Modified by Dominik Schulz <dominik.schulz@gauner.org>

set -e

test $DEBIAN_SCRIPT_DEBUG && set -v -x

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DESC="DJabberd"
NAME="djabberd"
CONFIG_DIR=/etc/djabberd
HOME_DIR=/var/lib/djabberd
DAEMON=/usr/bin/djabberd
PIDFILE=/var/run/djabberd/djabberd.pid
SCRIPTNAME=/etc/init.d/djabberd
OPTS="--conf=$CONFIG_DIR/djabberd.conf"

test -x $DAEMON || exit 0
test -d $CONFIG_DIR || exit 0

d_start() {
        start-stop-daemon --start --quiet --pidfile $PIDFILE -m \
                -d $HOME_DIR \
                --chuid djabberd \
                --background \
                --exec $DAEMON -- $OPTS
}

d_stop() {
        start-stop-daemon --stop --quiet --pidfile $PIDFILE \
                -d $HOME_DIR \
                --name $NAME -- $OPTS
}

d_reload() {
        start-stop-daemon --stop --quiet --pidfile $PIDFILE \
                --name $NAME --signal 1
}

case "$1" in
  start)
        echo -n "Starting $DESC: $NAME"
        d_start
        echo "."
        ;;
  stop)
        echo -n "Stopping $DESC: $NAME"
        d_stop
        echo "."
        ;;
  reload)
        echo -n "Reloading $DESC: $NAME"
        d_reload
        echo "."
        ;;
  restart|force-reload)
        echo -n "Restarting $DESC: $NAME"
        d_stop
        sleep 1
        d_start
        echo "."
        ;;
  *)
        echo "Usage: $SCRIPTNAME {start|stop|reload|restart|force-reload}" >&2
        exit 1
        ;;
esac

exit 0

# vim: set ai sts=2 sw=2 tw=0:
