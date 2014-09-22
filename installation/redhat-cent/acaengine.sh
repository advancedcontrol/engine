#!/bin/bash
#
# Startup script for ACA Engine.
#
# chkconfig: 345 85 15
# description: ACA Engine is an automation engine
# processname: ruby
#
# Reference: http://wiki.nginx.org/RedHatPHPFCGIInitScript
# Ensure script executable
# chmod +x /etc/init.d/acaengine
# service acaengine start
# service acaengine stop
# chkconfig acaengine on

 
# Source function library.
. /etc/rc.d/init.d/functions


ENGINE_PID=/home/aca_apps/sydney-control/tmp/pids/sg.pid
ENGINE_HOME="/home/aca_apps/sydney-control"
ENGINE_PORT="3000"
ENGINE_ADDR="127.0.0.1"
ENGINE_USER=acaengine

 
case "$1" in
  start)
        ENGINE_START=$"Starting ${NAME} service: "
        echo -n $ENGINE_START

        # Load RVM into a shell session *as a function*
        if [[ -s "$HOME/.rvm/scripts/rvm" ]] ; then

          # First try to load from a user install
          source "$HOME/.rvm/scripts/rvm"

        elif [[ -s "/usr/local/rvm/scripts/rvm" ]] ; then

          # Then try to load from a root install
          source "/usr/local/rvm/scripts/rvm"

        else

          echo "ERROR: An RVM installation was not found.\n"

        fi

        cd $ENGINE_HOME
        PATH=$PATH:/usr/local/rvm/gems/ruby-2.1.2/bin:/usr/local/rvm/gems/ruby-2.1.2@global/bin:/usr/local/rvm/rubies/ruby-2.1.2/bin:/usr/local/rvm/bin
        export PATH
        export RAILS_ENV=production
        export COUCHBASE_HOST=couch-db-uat-1.ucc.usyd.edu.au
        export COUCHBASE_BUCKET=control
        export COUCHBASE_PASSWORD=ea1pcqx49Xzq8qCSFlYG
        /etc/profile.d/rvm.sh
        rvm reload
        rvm repair all
        rvm use ruby
        bundle check || bundle install

        daemon "bundle exec sg -p $ENGINE_PORT -e production &> /dev/null &"
 
        pid=`pidof ruby`
        if [ -n "$pid" ]; then
            success $ENGINE_START
        else
            failure $ENGINE_START
        fi
        echo
        ;;
  stop)
        echo -n "Stopping ACA Engine"
        if [ -f "$ENGINE_PID" ]; then
            pid=`cat $ENGINE_PID`
            kill -9 $pid
        fi
        echo
        ;;
  status)
        if [ -f "$ENGINE_PID" ]; then
            pid=`cat $ENGINE_PID`
            if  ps -p $pid >&- ; then
              echo -n "ACA Engine running"
            else
              echo -n "ACA Engine not running"
            fi
        else
            echo -n "ACA Engine not running"
        fi
        echo
        ;;
  restart)
        $0 stop
        $0 start
        ;;
  *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
esac
 
exit 0
