TODO
====

## Important
* Current ZFs implementation could mess with existing zfs pools if they have the same name.  This should be remedied by enumerating existing pools on the local machine running the script before generating a name that will not collide with them.

## Nice
* Allow for package installation
* Stop syslog from listening: echo 'syslogd_flags="-ss"' >> ${TMPMNTPNT}/etc/rc.conf
