#!/bin/bash

#paths need to be set properly to run a perl app with sudo using a perlbrew perl
# PATH=/home/saamaan/perl5/perlbrew/bin:/home/saamaan/perl5/perlbrew/perls/perl-5.16.3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# which perl
# echo "$@"
# perl "$@"
sleep 10
/home/saamaan/perl5/perlbrew/perls/perl-5.16.3/bin/perl /home/saamaan/CowichanEnergy/lib/kickStart.perl --terms='LCD&realKP' --coldstart
# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
sudo rmmod pump_driver
sleep 2
sudo umount /sys/kernel/debug/ 
sleep 2
dmesg | tail -n 20
