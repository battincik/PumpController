package CE::PumpHandler;

use strict;
use warnings;

use CE::UI;
use CE::PumpInterface;

use AnyEvent::CouchDB;
use Try::Tiny;
use DateTime;
use Data::Dumper;

#The it's probably best to encapsulate the couch/Biopay interface code
#into its own thing.
#Though within Biopay project itself, pushing txns is done in the code 
#in a similar way. A modular txn class or something is not used.

sub new {
	my $class = shift;

	my $self = {};
	$self->{db_uri} = shift;
#	$self->{couch} = couchdb('http://cowichanenergy/couchdb/testdb');
	$self->{couch} = couchdb( $self->{db_uri} );
	$self->{loc} = shift || 'RA';

	$self->{terms} = shift;
	$self->{UI} = CE::UI->new( $self->{terms} );
	$self->{PI} = CE::PumpInterface->new();

	return bless($self, $class);
}

sub run {
	my $self = shift;

	#my $PI = CE::PumpInterface->new();

	my $UI = $self->{UI};
	my $PI = $self->{PI};
	my $couch = $self->{couch};

	my @resp;
	my $checkedOut = 0;
	my ($id, $p, $num, $vol, $bail); $bail = 0;

	while ( ( $bail == 0 ) && ( $self->_idle() ) ) {

		$num = $UI->promptFeedback("User ID + Enter", \@resp, 7, 'fb');
		if ($num == $UI->timeoutError) {
			$UI->message("Timeout");
			sleep(3);
			next;
		}
		$id = join('', @resp[0..($num - 1)]);
		my $docID = "member:$id";

		my $doc;
		try {
			$doc = $couch->open_doc($docID)->recv();
		}
		catch {		
			#check the error message here. This could also happen due to DB connection failure..
			warn "catch error message: $_\n";

			if ( /404 - / ) {
				$UI->message("ID invalid");
			}
			else {
				$UI->message("No DB connection");
			}
			sleep(3);
			next;
		};

		if ( $doc->{member_id} == $id ) {
			if ( (defined $doc->{frozen}) and ($doc->{frozen} == 1) ) {
				$UI->message("Account frozen");
				sleep(3);
				next;
			}

			$num = $UI->promptFeedback("PIN + Enter", \@resp, 4, 'scramble');
			if ($num == $UI->timeoutError) {
				$UI->message("Timeout");
				sleep(3);
				next;
			}
			$p = join('', @resp[0..($num - 1)]);
			unless ( $p == $doc->{PIN} ) {
				$UI->message("Invalid PIN");
				sleep(3);
				next;
			}
			
			$UI->message("Checked out");
			sleep(1);

			$UI->message("Select type");
			my $type = $PI->waitForType();
			if ($type eq $PI->timeoutError) {
				$UI->message("Timeout");
				sleep(3);
				next;
			}
			$UI->message("$type selected");
			sleep(3);
			$UI->message("remove nozzle");

			my $nozzle = ($type eq "Diesel") ? "Diesel" : "BioDiesel";
			my $ret;
			$ret = $PI->waitForNozzleRemoval($nozzle);
			if ($ret eq $PI->timeoutError) {
				$UI->message("Timeout");
				sleep(3);
				next;
			}

			$UI->message("begin fueling");
			sleep(1);

			$PI->enablePumps();
			my $pumpData = $PI->intercept($nozzle);
			$PI->disablePumps();
			#gotta take out the taxes and stuff

			if ( not defined $pumpData->{vol} ) {
				warn "Pump data was invalid.";
				next;
			}
			if ($pumpData->{vol} == 0) {
				warn "Session ended without any fuel being dispensed.";
				next;
			}

			my $pricePerLiter = sprintf("%.4f", $pumpData->{cost} / $pumpData->{vol});
			$ret = $self->_pushTXN({
					member_id => $id,
					vol => $pumpData->{vol},
					priceFromDispsr => $pricePerLiter,
					total_price => $pumpData->{cost},
					#product_type => $type
					});
			#TODO: this probably means something serious is wrong, not "next" probably!
			next if $ret;

			#$num = $UI->promptFeedback("Volume (e.g. 13)", \@resp, 3, 'fb');
			#if ($num == $UI->timeoutError) {
			#	$UI->message("Timeout");
			#	sleep(3);
			#	next;
			#}
			#$vol = join('', @resp[0..($num - 1)]);


			$UI->message("$pumpData->{vol}".'L$'."$pumpData->{cost}");
			sleep(3);
			$pumpData = undef;
		
		}
		else {
			#this shouldn't happen unless the DB records are messed up.
			#probably log some thing or send a message to admin or something..
		}
		

		#$num = $UI->promptFeedback("PIN + Enter", \@resp, 4, 'scramble');
		#$p = join('', @resp[0..($num - 1)]);
		#$checkedOut = authenticate($p);
	}

	$PI->destroy();
	$UI->destroyUI();

	print "UI destroyed normally\n";

	#for (my $i = 0; $i < 10; $i++) {
	#	$PI->enablePump();
	#	$PI->delayMS(500);
	#	$PI->disablePump();
	#	$PI->delayMS(500);
	#}
	#
	#my $fm = $PI->pollFMPin();
	#my $nr = $PI->pollNozzleRemoved();

	#print "flow meter: $fm, nozzle removed: $nr\n";
}

#user authentication
#this should talk to the DB...
sub authenticate {
	my $PIN = shift;

	return $PIN == 1234 ? 1 : 0;
}

sub destroy {
	my $self = shift;

	$self->{PI}->destroy();
	$self->{UI}->destroyUI();
}

#put try catch blocks here
sub _pushTXN {
	my $self = shift;

	my $args = shift;

	my $dt = DateTime->now();
	my $txn_id = $args->{member_id} . "." . $dt->epoch;

	my $txn_hash = {
		Type => 'txn',
		_id => "txn:" . $txn_id,
		txn_id => $txn_id,
		member_id => $args->{member_id},
		epoch_time => $dt->epoch,
		litres => $args->{vol},
		date => "$dt",
		price_per_litre => $args->{priceFromDispsr},
		price => $args->{total_price},
		paid => 0,
		pump => $self->{loc}
	};

	#my $str = Dumper($txn_hash);
	#warn "txn hash: $str";

	try {
		$self->{couch}->save_doc($txn_hash)->recv();
		return 0;
	}
	catch {
		#TODO this should obviously do something else!
		#check the error message here. This could also happen due to DB connection failure..
		warn "catch error message: $_\n";

		if ( /404 - / ) {
			$self->{UI}->message("ID invalid");
		}
		else {
			$self->{UI}->message("No DB connection");
		}
		return -1;
	};
}

#TODO verify the connection to the server periodically?
sub _idle {
	my $self = shift;

#	$self->{UI}->emptyBuffer();

	$self->{UI}->message("Press Enter");
	return $self->{UI}->waitForStart();
}

1;
