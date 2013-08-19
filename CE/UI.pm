package CE::UI;

use strict;
use warnings;

use CE::MonitorInterface;
use CE::Keypad;
use CE::MockKeypad;
use CE::LCD;

use Switch;


sub new {
	my $class = shift;
	my $self = {};
	$self->{terms} = shift;

	switch ( $self->{terms} ) {
		case 'monitor&mockKP' {
			$self->{scr} = CE::MonitorInterface->new();
			$self->{kp} = CE::MockKeypad->new( ('_kp' => $self->{scr}->get_scr()) );
		}
		case 'monitor&realKP' {
			die "provide SU" if ( CE::Keypad->getUID() );
			$self->{scr} = CE::MonitorInterface->new();
			$self->{kp} = CE::Keypad->new( ('dev' => '/dev/input/by-id/usb-Hagstrom_Electronics__Inc._Hagstrom_Electronics__Inc._KEUSB2-event-kbd', 'promptTO' => 5000) );
		}
		case 'LCD&mockKP' {
			die "provide SU" if ( CE::Keypad->getUID() );
			$self->{scr} = CE::LCD->new();
			$self->{kp} = CE::MockKeypad->new();
		}
		case 'LCD&realKP' {
			die "provide SU" if ( CE::Keypad->getUID() );
			$self->{scr} = CE::LCD->new();
			$self->{kp} = CE::Keypad->new( ('dev' => '/dev/input/by-id/usb-Hagstrom_Electronics__Inc._Hagstrom_Electronics__Inc._KEUSB2-event-kbd', 'promptTO' => 5000) );
		}
		else {
			die "Wrong terminal options";
		}
	}

	return bless($self, $class);

}

sub timeoutError {
	my $self = shift;
	return $self->{kp}->getERR;
}

#wipes the screen, prompts the user, and accepts the expected number of 
#characters.
#feedbacks will be provided on the screen based on the last argument
#	-fb: everything get echoed
#	-scramble: everything gets echoed as *
#	--hide: nothing gets echoed
#return the number of characters entered.
#returns zero in case of timeout
sub promptFeedback {
	my $self = shift;

	my $promptStr = shift;
	my $respStr = shift;
	my $charLimit = shift;
	$charLimit = $self->{scr}->get_scrX() if $charLimit > $self->{scr}->get_scrX();

	my $left = $charLimit;

	my $fbType = $_[0] || 'fb';

	$self->{scr}->clearScr();
	$self->{scr}->putLine($promptStr, 1);

	my $k = 0;

	while ($k = $self->{kp}->getChar(), ord($k) != 10) {
		#warn "char ", ord($k), " |", $self->{kp}->getKEY_BACKSPACE, "|\n";
		if ("$k" eq $self->{kp}->getKEY_BACKSPACE) {
			#warn "UI, backspace\n";
			$self->{scr}->backspace();
			$left++ if ($left < $charLimit);
		}
		elsif ($k eq $self->{kp}->getERR) {
			return $self->{kp}->getERR;
		}
		elsif ($left > 0) {
			$respStr->[$charLimit - $left] = $k;

			switch ( $fbType ) {
				case 'fb' { $self->{scr}->addChar($k); }
				case 'scramble' { $self->{scr}->addChar('*'); }
				case 'hide' {}
				else {}
			}

			$left--;
		}
		else {}
	}

	return ($charLimit - $left);
}

#wipes the screen then shows a message to the user
sub message {
	my $self = shift;

	my $str = shift;

	$self->{scr}->clearScr();
	$self->{scr}->putLine($str, 2);

	return 1;
}

#waits quitely for the strat signal from the user
sub waitForStart {
	my $self = shift;

	my $k = 0;
#	$k = $self->{kp}->getChar() until ( ord($k) == 10 || $k eq $self->{kp}->getESC );
	until ( ord($k) == 10 || $k eq $self->{kp}->getESC ) {
		$k = $self->{kp}->getChar();
		#warn "char |$k|\n";
	}


	return ($k eq $self->{kp}->getESC) ? 0 : 1;
}

#sub emptyBuffer {
#	my $self = shift;
#
#	$self->{kp}->emptyBuffer();
#}

sub destroyUI {
	my $self = shift;

	$self->{scr}->destroyScr();
	$self->{kp}->destroyKP();
}

1;
