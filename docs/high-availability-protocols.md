# High Availability Protocols

## Restore Proceedure

This is performed once an edge or slave node has come back online

* Master stops modules
* Master sends module status dump to slave
* Master indicates to slave to start modules


## Reconnection Negotiation Protocol

1. Slave connects to master
1. Authenticates with master node including its startup time
  * If the masters recorded failover time > slave start time
    - Slave is in control, master stops modules if they are running
    - Slave sends status dump to control so it is in sync
    - NOTE:: The only time this is incorrect behaviour is if the slave was on with its network unplugged (don't do this)
  * else
    - Slave is not in control
    - Start restore proceedures (above) either straight away or in the restore window

