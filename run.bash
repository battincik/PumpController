#!/bin/bash

#paths need to be set properly to run a perl app with sudo using a perlbrew perl
# PATH=/home/saamaan/perl5/perlbrew/bin:/home/saamaan/perl5/perlbrew/perls/perl-5.16.3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# which perl
# echo "$@"
# perl "$@"
OUT=""
for i in $@; do
	case $i in
		--output=*)
			OUT=" > ${i#*=} 2>&1"
			;;
		*)
			echo "Unrecognized option: $i"
			exit 2
			;;
	esac
done
echo "--output switch: $OUT"
sleep 10
eval "/home/saamaan/perl5/perlbrew/perls/perl-5.16.3/bin/perl /home/saamaan/CowichanEnergy/lib/kickStart.perl --terms='LCD&realKP' --coldstart $OUT"
# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
sudo rmmod pump_driver
sleep 2
sudo umount /sys/kernel/debug/ 
sleep 2
dmesg | tail -n 20
