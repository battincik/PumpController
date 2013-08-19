package CE::Keypad;

use warnings;
use strict;

my %reqAttr = (
	'dev' => '/dev/input/by-id/usb-Hagstrom_Electronics__Inc._Hagstrom_Electronics__Inc._KEUSB2-event-kbd',
	'promptTO' => 3000
);

sub new {
	my $class = shift;

	my %args = @_;
	my $dev = $args{dev} || $reqAttr{dev};
	my $TO = $args{promptTO} || $reqAttr{promptTO};

	my $self = {};

	my $k = init($dev, $TO);
	if ( $k == -1 ) {
		die "Provide SU" if myGetUID();
		die "failed to open the device";
	}

	if ( myGrab() == 0 ) {
		warn "grabbed\n";
	}
	else {
		_myCloseAndDie("Failed to grab.");
	}

	$self->{destroyed} = 0;
	$self->{dev} = $dev;

	return bless($self, $class);
}

sub getChar {
	my $self = shift;
	if ($self->getTO == -1) {
		return myReadChar(1);
	}
	else {
		return myReadChar(0);
	}
}

sub getERR {
	return -1;
}

sub getESC {
	return 'X';
}

sub getKEY_BACKSPACE {
	return _getKEY_BACKSPACE();
}

sub getTO {
	return _getTO();
}

sub setTO {
	return _setTO();
}

sub getUID {
	return myGetUID();
}

sub destroyKP {
	my $self = shift;

	warn "Keypad, cleaning up\n";

	myClose();
	$self->{destroyed} = 1;
	undef $self->{dev};
}


sub _myCloseAndDie {
	my $msg = shift;

	myClose();
	die "$msg\n";
}

#__END__
#__C__

use Inline C => q{

#include <linux/input.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/select.h>

static struct timeval _timeout = {0};
static int _fd = {0};

#define KEY_PRESS 1
#define KEY_RELEASE 0
#define KEY_HELD 2

int init(char *dev, int TO_msecs) {

	_fd = open(dev, O_RDONLY);
	if ( _fd != -1 ) {

		_timeout.tv_sec = TO_msecs / 1000;
		_timeout.tv_usec = (TO_msecs % 1000) * 1000;

	}

	return _fd;
}

int _setTO(int TO_msecs) {
	_timeout.tv_sec = TO_msecs / 1000;
	_timeout.tv_usec = (TO_msecs % 1000) * 1000;
	return 0;
}

int _getTO() {
	return ( _timeout.tv_sec * 1000 + (_timeout.tv_usec / 1000) );
}

int myGetUID() {
	return getuid();
}

int myClose() {
	close(_fd);
	return 0;
}

int myGrab() {
	return ioctl(_fd, EVIOCGRAB, 1);
}

inline int readKeyPressed_blocking() {
	struct input_event ev = {0};

	while ( (ev.type != EV_KEY) || (ev.value == KEY_RELEASE) ) {
		int rd = read(_fd, &ev, sizeof(struct input_event));
		if ( rd < sizeof(struct input_event) ) {
			return -1;
		}
	}
	return ev.code;
}

inline int readKeyPressed_timeout() {
	struct input_event ev = {0};

	while ( (ev.type != EV_KEY) || (ev.value == KEY_RELEASE) ) {

		struct timeval to = _timeout;
		fd_set read_fds, write_fds, except_fds;
		FD_ZERO(&read_fds);
		FD_ZERO(&write_fds);
		FD_ZERO(&except_fds);
		FD_SET(_fd, &read_fds);

		if (select(_fd+1, &read_fds, &write_fds, &except_fds, &to) == 1 ) {
			int rd = read(_fd, &ev, sizeof(struct input_event));
			if ( rd < sizeof(struct input_event) ) {
				return -1;
			}
		}
		else {
			//maybe this should be different. Curses uses the same error code
			//for the timeout as other errors..don't like this tho..!
			//fprintf(stderr, "readKeyPressed timedout\n");
			return -1; 
		}
	}
	return ev.code;
}


SV *myReadChar(int block) {
	
	int keyPressed2, keyPressed;
       	keyPressed = block ? readKeyPressed_blocking() : readKeyPressed_timeout();

	switch (keyPressed) {
		case KEY_KP0:
			return newSVpv("0", 1);
		case KEY_KP1:
			return newSVpv("1", 1);
		case KEY_KP2:
			return newSVpv("2", 1);
		case KEY_KP3:
			return newSVpv("3", 1);
		case KEY_KP4:
			return newSVpv("4", 1);
		case KEY_KP5:
			return newSVpv("5", 1);
		case KEY_KP6:
			return newSVpv("6", 1);
		case KEY_KP7:
			return newSVpv("7", 1);
		case KEY_KP8:
			return newSVpv("8", 1);
		case KEY_KP9:
			return newSVpv("9", 1);
		case KEY_BACKSPACE:
			return newSVpv("\b", 1);
		case KEY_KPENTER:
			return newSVpv("\n", 1);
		case KEY_KPASTERISK:
			return newSVpv("*", 1);
		case KEY_LEFTSHIFT: 
		       	keyPressed2 = block ? readKeyPressed_blocking() : readKeyPressed_timeout();

			switch (keyPressed2) {
				case KEY_SLASH:
					return newSVpv("?", 1);
				case KEY_X:
					return newSVpv("X", 1);
				case KEY_3:
					return newSVpv("#", 1);
				default:
					return newSViv(-1);
			}
		default:
			return newSViv(-1);
	}
}

SV *_getKEY_BACKSPACE() {
	return newSVpv("\b", 1);
}

};

1;
