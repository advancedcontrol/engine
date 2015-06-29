# Cent OS - Configuring Limits

Copied from: http://developer.couchbase.com/mobile/develop/guides/sync-gateway/os-level-tuning/max-file-descriptors/index.html
and: http://developer.couchbase.com/mobile/develop/guides/sync-gateway/os-level-tuning/tcp-keep-alive/index.html

Raising the maximum number of file descriptors available to Sync Gateway is important because it directly affects the maximum number of sockets the Sync Gateway can have open, and therefore the maximum number of clients that the Sync Gateway can support.

Linux Instructions (CentOS)
The following instructions are geared towards CentOS.

Increase the max number of file descriptors available to all processes. To specify the number of system wide file descriptors allowed, open up the /etc/sysctl.conf file and add the following line:

fs.file-max = 500000
         
Apply the changes and persist them (this will last across reboots) by running the following command:

$ sysctl -p
         
Increase the ulimit setting for max number of file descriptors available to a single process. For example, setting it to 250K will allow the Sync Gateway to have 250K connections open at any given time, and leave 250K remaining file descriptors available for the rest of the processes on the machine. These settings are just an example, you will probably want to tune them for your own particular use case.

$ ulimit -n 250000
           
In order to persist the ulimit change across reboots, add the following lines to /etc/security/limits.conf

* soft nofile 250000
* hard nofile 250000
           
Verify your changes by running the following commands:

$ cat /proc/sys/fs/file-max
$ ulimit -n 
           
The value of both commands above should be 250000.







Tuning the TCP Keepalive settings is not without its downsides -- it will increase the amount of overall network traffic on your system, because the tcp/ip stack will be sending more frequent Keepalive packets in order to detect dead peers faster.

The following settings will reduce the amount of time that dead peer connections hang around from approximately 2 hours down to approximately 30 minutes. Add the following lines to your /etc/sysctl.conf file:

net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 9
           
           
To activate the changes and persist them across reboots, run:

$ sysctl -p







Other Tweaks

# Check using
cat /proc/sys/vm/swappiness

# Set swap memory to 0
sudo echo 0 > /proc/sys/vm/swappiness

# Edit /etc/sysctl.conf
vm.swappiness = 0


# Disable THP on a running system
sudo echo never > /sys/kernel/mm/transparent_hugepage/enabled
sudo echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Add these commands to /etc/rc.local
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi

