package CE::LCD;

use strict;
use warnings;

#use Inline Python;

my %reqAttrs = (
	'_scrX' => 16, '_scrY' => 2,
	'_cursorX' => 1, '_cursorY' => 1,
	'useCurses' => 1, '_scr' => undef
);

sub ERR { return -1; };

sub new {
	my $class = shift;
	my %args = @_;

	print "the input args @_\n";

	my $self = {};

	for my $key (keys %reqAttrs) {
		$self->{$key} = $args{$key} || $reqAttrs{$key};
	}

	bless($self, $class);

	my $scr = Inline::Python::Object->new('__main__', 'Adafruit_CharLCDPlate');
	$self->{_scr} = $scr;

	$scr->begin($self->{_scrX}, $self->{_scrY});
	$scr->display();
	$scr->clear();
	#$scr->cursor();
	#$scr->blink();

	return $self;
}

sub putLine {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	my ($str, $y) = @_;

	return ERR if ( ($y > $self->{_scrY}) || ($y < 1) );

	my $scr = $self->{_scr};
	$self->clearLine($y);
	sleep(3);
	$scr->message($str);
	$y++ if $y < $self->{_scrY};
	$scr->setCursor(0, $y - 1);

	($self->{_cursorY}, $self->{_cursorX}) = ($y, 1);

	return $self;
}

sub addChar {
	my $self = shift;

	die "_scr doesn't exist\n" unless $self->{_scr};

	my $ch = shift;
	if ( $self->inside() ) {
		#warn "addch $ch\n";
		$self->{_scr}->message("$ch");
		$self->{_cursorX}++;
	}

	return $self;

}

sub backspace {
	 my $self = shift;

	 die "_scr doesn't exist\n" unless $self->{_scr};

	 if ($self->{_cursorX} > 1) {
		 my $scr = $self->{_scr};

		 $self->{_cursorX}--;
		 $scr->setCursor($self->{_cursorX} - 1, $self->{_cursorY} - 1);
		 $scr->message(' ');
		 $scr->setCursor($self->{_cursorX} - 1, $self->{_cursorY} - 1);
	 }		 
}

sub inside {
	my $self = shift;

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

sub clearLine {
	my $self = shift;

	my $y = shift;

	my $scr = $self->{_scr};
	$scr->setCursor(0, $y - 1);
	$scr->message(' ' x $self->{_scrX});
	$scr->setCursor(0, $y - 1);
}

sub clearScr {
	my $self = shift;

	$self->{_scr}->clear();
}

sub destroyScr {
	my $self = shift;

	$self->{_scr}->noDisplay();
	$self->{_scr} = undef;

	return $self;
}

sub get_scrX {
	my $self = shift;

	return $self->{_scrX};
}

#__END__
#__Python__
use Inline Python => q{

from drivers.LCD_driver.Adafruit_CharLCDPlate import Adafruit_CharLCDPlate as Adafruit_CharLCDPlate

print 'Python LCD driver...initialized\n'
};

1;


