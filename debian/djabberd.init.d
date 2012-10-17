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
USER=djabberd
GROUP=djabberd
CONFIG_DIR=/etc/djabberd
HOME_DIR=/var/lib/djabberd
DAEMON=/usr/bin/djabberd
PIDDIR=/run/djabberd
PIDFILE="$PIDDIR/djabberd.pid"
SCRIPTNAME=/etc/init.d/djabberd
OPTS="--daemon"

test -x $DAEMON || exit 0
test -d $CONFIG_DIR || exit 0

. /lib/lsb/init-functions

d_start() {
  mkdir -p $PIDDIR
  chown $USER:$GROUP $PIDDIR
  start-stop-daemon --start --quiet --pidfile $PIDFILE \
    --chuid $USER \
    --exec $DAEMON -- $OPTS
}

d_stop() {
  start-stop-daemon --stop --quiet --pidfile $PIDFILE \
    --name $NAME -- $OPTS || true
}

d_reload() {
  start-stop-daemon --stop --quiet --pidfile $PIDFILE \
    --name $NAME --signal 1
}

case "$1" in
  start)
    log_begin_msg "Starting $DESC: $NAME"
    d_start
    log_end_msg $? 
    ;;
  stop)
    log_begin_msg "Stopping $DESC: $NAME"
    d_stop
    log_end_msg $?
    ;;
  reload)
    log_begin_msg "Reloading $DESC: $NAME"
    d_reload
    log_end_msg $?
    ;;
  restart|force-reload)
    log_begin_msg "Restarting $DESC: $NAME"
    d_stop
    sleep 1
    d_start
    log_end_msg $?
    ;;
  *)
    echo "Usage: $SCRIPTNAME {start|stop|reload|restart|force-reload}" >&2
    exit 1
    ;;
esac

exit 0

# vim: set ai sts=2 sw=2 tw=0:
