#!/usr/bin/perl

use strict;
use warnings;

use YAML::XS;

my ($opts, $term, $coldstartFlag, $config);

BEGIN {
	require Getopt::Long;

	print "$^X\n";
	print "INC: @INC\n";
	print "@ARGV\n";

	Getopt::Long::GetOptions ("terms=s" => \$term, 
			"coldstart" => \$coldstartFlag) 
			|| die ("Bad command line arguments\n");

	die("Command line args missing\n") unless defined $term;

	$config = YAML::XS::LoadFile('config.yaml');
	die("Config file missing.") unless defined $config;

	if ( defined $coldstartFlag ) {
		print STDERR "Cold start flag used. Setting up some stuff\n";

		my $resp = `sudo service couchdb status 2>&1`;
		if ( $resp !~ /is not running/ ) {
			warn "stopping couch";
			`sudo service couchdb stop`;
		}
		warn "couch is not running";

		$resp = `ps aux | grep ssh`;
		my $loc = "ssh -f -L ".
			"5984:127.0.0.1:5984 -i $config->{tunnel}->{private_key} ".
			"$config->{tunnel}->{user}\@$config->{tunnel}->{host} -N";
		#my $loc = "ssh -f -L5984:127.0.0.1:5984 saamaan\@cowichanenergy -N";
	
		if ( $resp !~ /ssh -f -L 5984:127.0.0.1:5984/ ) {
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


$SIG{INT} = \&_sigHandler;

warn "terms: $term\n";

# die 'about to initialize pump handler';

my $PH = CE::PumpHandler->new($config->{db_uri}, $config->{location}, $term);
$PH->run;


sub _sigHandler {
	my $signame = shift;
	warn "caught $signame";
	die "No pump handler to destroy" unless defined $PH;
	
	#TODO make sure this was successful
	#TODO put some message on the LCD and keep it on..
	$PH->destroy();
	die "pump handler destroyed";
}

