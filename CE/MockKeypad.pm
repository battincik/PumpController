package CE::MockKeypad;

use strict;
use warnings;

use Curses;

my %reqAttrs = (
	'promptTO' => 3000, '_kp' => undef
);

sub new {
	my $class = shift;
	my %args = @_;

	my $self = {};

	for my $key (keys %reqAttrs) {
		$self->{$key} = $args{$key} || $reqAttrs{$key};
	}

	bless($self, $class);

	$self->_initCursesKeypad();

	return $self;
}

#blocking read char, accepts optional timeout argument, if not provided
#defaults to the promptTO set at construction.
#TO = -1 for infinite timeout
sub getChar {
	my $self = shift;

	my $TO = $_[0] if @_;
	$self->{_kp}->timeout($TO) if defined $TO;
	my $ch = $self->{_kp}->getch();
	$self->{_kp}->timeout($self->{prompTO}) if defined $TO;

	return $ch; 
}

#sub emptyBuffer {
#	my $self = shift;
#
#	$self->{_kp}->timeout(1000);
#	while ($self->{_kp}->getch() != getERR() ) {
#	}
#	$self->{_kp}->timeout($self->{prompTO});
#}

sub _initCursesKeypad {
	my $self = shift;

	warn "init mock keypad\n";

	if ( not defined $self->{_kp} ) {
		initscr();
		cbreak();
		noecho();

		$self->{_kp} = Curses->new();
		$self->{_kp}->keypad(1);

		$self->{mustDestroy} = 1;
	}
	else {
		$self->{mustDestroy} = 0;
	}
	$self->{_kp}->timeout($self->{promptTO});
}

sub destroyKP {
	my $self = shift;

	if ( $self->{mustDestroy} ) {
			endwin();
			warn "MockedKeypad, cleaning up\n";
	}
	$self->{_kp} = undef;
}

#replace these with class static variables (kep in a hash perhaps) that are exportable
sub getKEY_BACKSPACE {
	return KEY_BACKSPACE;
}

sub getERR {
	return ERR;
}

sub getESC {
	return 'q';
}

1;
