package CE::MonitorInterface;

use strict;
use warnings;

use Curses;
use Data::Dumper;

#attributes and their default values
my %reqAttrs = (
	'_scrX' => 16, '_scrY' => 2,
	'_cursorX' => 1, '_cursorY' => 1,
	'_scr' => undef
);

sub new {
	my $class = shift;
	my %args = @_;

	warn "the input args @_\n";

	my $self = {};

	for my $key (keys %reqAttrs) {
		$self->{$key} = $args{$key} || $reqAttrs{$key};
	}

	bless($self, $class);

	$self->_initCursesScr() unless $self->{_scr};

	return $self;
}

#accepts a string and a row number (starting from 1 not 0!)
#clears the line, puts the string (as much as fits)
sub putLine {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	my ($str, $y) = @_;

	return ERR if ( ($y > $self->{_scrY}) || ($y < 1) );

	my $win = $self->{_scr};

	$self->clearLine($y);
	#$win->move($y, 1);
	$win->addnstr($str, $self->{_scrX});
	$y++ if $y < $self->{_scrY};
	$win->move($y, 1);
	($self->{_cursorY}, $self->{_cursorX} ) = ($y, 1);

	$win->refresh();

	return $self;
}

#adds a character at the current cursor position and move the cursor
#forwards
sub addChar {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	my $ch = shift;
	if ( $self->inside() ) {
		#warn "addch $ch\n";
		$self->{_scr}->addch($ch);
		$self->{_cursorX}++;
		$self->{_scr}->refresh();
		#$self->{_scr}->move($self->{_cursorY}, $self->{_cursorX});
	}

	return $self;
}

#checks the validity of the current cursor
sub inside {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	if ( ($self->{_cursorX} < $self->{_scrX} + 1) &&
       		($self->{_cursorY} < $self->{_scrY} + 1) &&
		($self->{_cursorX} > 0) && 
		($self->{_cursorY} > 0) ) {
		return 1;
	}
	else {
		return 0;
	}
}

#deletes the previous character if possible and moves the cursor back by
#one
sub backspace {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	if ($self->{_cursorX} > 1) {
		my $win = $self->{_scr};

		$self->{_cursorX}--;
		$win->move($self->{_cursorY}, $self->{_cursorX});
		$win->addch(' ');
		$win->move($self->{_cursorY}, $self->{_cursorX});
		$win->refresh();
	}

	return $self;
}

#accepts a row number (starting from 1 not 0) and clears it on the screen
sub clearLine {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	my $y = shift;

	my $win = $self->{_scr};

	$win->move($y, 1);
	$win->addnstr(' ' x $self->{_scrX}, $self->{_scrX});
	$win->move($y, 1);
	($self->{_cursorY}, $self->{_cursorX} ) = ($y, 1);

	$win->refresh();
}

#clear the whole screen
sub clearScr {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	$self->{_scr}->clear();
	$self->{_scr}->box(0, 0);

	$self->{_scr}->move(1, 1);
	($self->{_cursorY}, $self->{_cursorX} ) = (1, 1);

	return $self;
}

#curses init for now
sub _initCursesScr {
	my $self = shift;

	warn "init monitor interface\n";

	initscr();
	cbreak();
	noecho();

	#add two extra rows and two extra columns for border
	$self->{_scr} =  new Curses($self->{_scrY} + 2, $self->{_scrX} + 2, 1, 0);

	$self->{_scr}->keypad(1);

	$self->{_scr}->box(0, 0);
	$self->{_scr}->refresh();
}

#curses cleen-up for now
sub destroyScr {
	my $self = shift;

	$self->{_scr}->delwin();
	endwin();

	warn "monitor interface, cleaning up\n";

	$self->{_scr} = undef;
	
	return $self;
}

#getter
sub get_scr {
	my $self = shift;

	return $self->{_scr};
}

sub get_scrX {
	my $self = shift;

	return $self->{_scrX};
}

1;
