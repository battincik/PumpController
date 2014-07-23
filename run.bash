#!/bin/bash

#paths need to be set properly to run a perl app with sudo using a perlbrew perl
PATH=/home/saamaan/perl5/perlbrew/bin:/home/saamaan/perl5/perlbrew/perls/perl-5.16.3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
which perl
echo "$@"
perl "$@"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
sudo rmmod pump_driver
sudo umount /sys/kernel/debug/ 
dmesg | tail -n 20
