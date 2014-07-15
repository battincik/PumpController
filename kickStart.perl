#!/usr/bin/perl

use strict;
use warnings;

my ($opts, $term, $coldstartFlag);

BEGIN {
	require Getopt::Long;

	print @ARGV;

	Getopt::Long::GetOptions ("terms=s" => \$term, 
			"coldstart" => \$coldstartFlag) 
			|| die ("Bad command line arguments\n");

	die("command line args missing\n") unless defined $term;

	if ( defined $coldstartFlag ) {
		print STDERR "Cold start flag used. Setting up some stuff\n";

		my $resp = `sudo service couchdb status 2>&1`;
		if ( $resp !~ /is not running/ ) {
			warn "stopping couch";
			`sudo service couchdb stop`;
		}
		warn "couch is not running";

		$resp = `ps aux | grep ssh`;
		my $loc = "ssh -f -L5984:127.0.0.1:5984 -i ./bio.pem ubuntu\@ec2-54-213-146-19.us-west-2.compute.amazonaws.com -N";
		#my $loc = "ssh -f -L5984:127.0.0.1:5984 saamaan\@cowichanenergy -N";
	
		if ( $resp !~ /ssh -f -L5984:127.0.0.1:5984/ ) {
			warn "tunnelling to cowichanenergy server";
			system($loc);
		}

		$resp = `mount`;
		if ( $resp !~ /debugfs/ ) {
			warn "mounting VFS";
			`sudo mount -t debugfs none /sys/kernel/debug/`
		}

		$resp = `lsmod`;
		if ( $resp !~ /pump_driver/ ) {
			warn "inserting pump_driver";
			`sudo insmod drivers/pump_driver/pump_driver.ko`;
		}
	}
	else {
		print STDERR "Cold start setup was skipped. BE WARNED: Things will crash and burn if this is in fact a cold start..";
	}
	print STDERR "End of BEGIN\n";
}



use CE::PumpHandler;

sub cleanup {
	print STDERR "Attempting to teminate gracefully\n";
	print STDERR "Unloading pump_controller driver..\n";
	`sudo rmmod pump_controller`;
	print STDERR "Unmounting debugfs..\n";
	`sudo umount /sys/kernel/debug/`;
}


$SIG{INT} = \&_sigHandler;

warn "terms: $term\n";

my $PH = CE::PumpHandler->new('http://127.0.0.1:5984/testdb', 'Duncan', $term);
$PH->run;
cleanup();


sub _sigHandler {
	my $signame = shift;
	warn "caught $signame";
	die "No pump handler to destroy" unless defined $PH;
	
	#TODO make sure this was successful
	#TODO put some message on the LCD and keep it on..
	$PH->destroy();
	die "pump handler destroyed";
	cleanup();
}

