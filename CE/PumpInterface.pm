package CE::PumpInterface;

use strict;
use warnings;

use Carp qw( croak  );

use Path::Class;
use constant THIS_FILE => "".file( __FILE__ )->absolute;
use constant CE_DIR => "".file( THIS_FILE )->dir;
my $RELAY_BOARD_DRIVER_PATH;
BEGIN { 
	$RELAY_BOARD_DRIVER_PATH = CE_DIR . "/../drivers/relay_board_driver/"; 
	warn "relay_board_driver absolute path for PumpInterface Inline link: $RELAY_BOARD_DRIVER_PATH";
}

#use Device::BCM2835 qw( HIGH LOW );

my %reqAttr = (
	TO => 10,	#timeout in seconds
);	

#see P[1234]_PIN
#                 P1        P2     P3      P4
#                PIN0      PIN1   PIN2    PIN3
my @products = qw(Diesel B20 B50 B100);

#see NOZZLE[12]_PIN
#              Nozzle1       Nozzle2
#		PIN4         PIN5
my @nozzles = qw(Diesel BioDiesel);

sub timeoutError { return '-1'; }

sub new {
	my $class = shift;
	my %args = @_;

#	Device::BCM2835::init() || die "Unable to initialize PumpInterface" ;

	my $self = {};

	myInit();

#	my $base = "&Device::BCM2835::";

	for my $key (keys %reqAttr) {
		$self->{$key} = defined $args{$key} ? $args{$key} : $reqAttr{$key};
	}

#	Device::BCM2835::gpio_fsel($self->{'PEPin'},
#				&Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);

	return bless($self, $class);
}

sub enablePumps {
	my $self = shift;

#	Device::BCM2835::gpio_write($self->{PEPin}, HIGH);
	myEnablePumps();

	return $self;
}

sub disablePumps {
	my $self = shift;

#	Device::BCM2835::gpio_write($self->{PEPin}, LOW);
	myDisablePumps();

	return $self;
}

##This is can be a static function
#sub delayMS {
#	my $selfOrClass = shift;
#
#	my ($delayMilliSeconds) = @_;
#	$delayMilliSeconds || croak "PumpInterface::delay(int milliseconds) missing argument";
#
#	Device::BCM2835::delay($delayMilliSeconds);
#
#	return $selfOrClass;
#}

sub intercept {
	my $self = shift;
	my $correctNozzle = shift;
	#return {cost => 123.34, vol => 14.908};

	my ($ind) = grep { $nozzles[$_] eq $correctNozzle } 0..$#nozzles;
	die "undefined nozzle" unless defined $ind;
	warn "intercept, correctNozzle: $correctNozzle, ind: $ind";

	my $ret = {};
	myIntercept($ind, $ret);
	if ( defined $ret->{vol} ) {
		$ret->{cost} /= 100;
		$ret->{vol} /= 1000;
		warn 'PumpInterface intercept returning $'."$ret->{cost} and $ret->{vol} Liters";
	}
	else {
		warn "myIntercept() returned with errors";
	}

	return $ret;
}

sub monitorRelBrdInputs {
	my $self = shift;
	printf STDERR "Reading relay board input pins:\n";
	return myMonitorRelBrdInputs();
}

sub waitForType {
	my $self = shift;

	my $t1 = time();		#epoch in secs
	my $t2 = $t1;

	my $type;
	while ( ($t2 - $t1) < $self->{TO} ) {
		$type = myTypeSelected();
		return $products[$type] if $type >= 0;
		$t2 = time();
	}

	warn "waitForType() timed out";
	return timeoutError();
}

sub waitForNozzleRemoval {
	warn "waiting for nozzle to be removed";

	my $self = shift;
	my $correctNozzle = shift;

	my $t1 = time();		#epoch in secs
	my $t2 = $t1;

	my $noz;
	while ( ($t2 - $t1) < $self->{TO} ) {
		$noz = myNozzleRemoved();
		return "yes" if ( ($noz >= 0) && ($nozzles[$noz] eq $correctNozzle) );
		#warn "noz: $noz, correct: $correctNozzle, returned: $nozzles[$noz]";
		$t2 = time();
	}

	warn "waitForNozzleRemoval() timed out";
	return timeoutError();
}

sub nozzleReplaced {
	my $self = shift;
	my $correctNozzle = shift;

	my ($ind) = grep { $nozzles[$_] eq $correctNozzle } 0..$#nozzles;
	die "undefined nozzle" unless defined $ind;

	return myNozzleReplaced($ind) ? "yes" : "no";
}

sub bothNozzlesReplaced {
	my $self = shift;

	return myBothNozzlesReplaced() ? "yes" : "no";
}

sub destroy {
	my $self = shift;

	myDestroy();
}

#__END__
#__C__

#use Inline C => Config => LIBS => '-Ldrivers/relay_board_driver/ -lpfio';
use Inline C => Config => LIBS => "-L$RELAY_BOARD_DRIVER_PATH -lpfio";
use Inline C => q{

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>

#include "drivers/pump_driver/pump_driver.h"
#include "drivers/relay_board_driver/pfio.h"

#define RELAY1_PIN 0
#define RELAY2_PIN 1

//See @products
#define P1_PIN 0
#define P2_PIN 1
#define P3_PIN 2
#define P4_PIN 3
//See @nozzles
#define NOZZLE1_PIN 4
#define NOZZLE2_PIN 5

#define DP_SET(x) ( (x & 0x80) == 0 ? : 0 : 1 )
#define CHAR_FROM_SS(x) ( SS_to_Char[ ( x & 0x7F ) ] )
#define DIG_FROM_SS(x) ( ( CHAR_FROM_SS(x) ) - '0' )

static char SS_to_Char[128];// = {45}; //ascii for '-'

static int fd = 0;
static long pagesize;
static char bits[97] = {0};
static uint8_t digs[13] = {0};
static char chrs[13] = {0};

static uint8_t _productsMask, _nozzlesMask, _p1Mask, _p2Mask, _p3Mask, _p4Mask, _nozzle1Mask, _nozzle2Mask;

int myInit() {

	//Init pump_driver
	int i;
	for (i = 0; i < 128; i++) {
		SS_to_Char[i] = '-';
	}
	pagesize = sysconf(_SC_PAGESIZE);
	fd = 0;
	SS_to_Char[0b0000000] = '0';    //blank is treated as zero in calculations
	SS_to_Char[0b0111111] = '0';
	SS_to_Char[0b0000110] = '1';
	SS_to_Char[0b1011011] = '2';
	SS_to_Char[0b1001111] = '3';
	SS_to_Char[0b1100110] = '4';
	SS_to_Char[0b1101101] = '5';
	SS_to_Char[0b1111101] = '6';
	SS_to_Char[0b0000111] = '7';
	SS_to_Char[0b1111111] = '8';
	SS_to_Char[0b1101111] = '9';

#ifdef FIX_A_SEG_IF_POSSIBLE
	//SS_to_Char[0b0111111] = '0'; //not needed, decoded correctly
	//SS_to_Char[0b0000111] = '1'; //can't fix this one, turns into '7' :|
	//SS_to_Char[0b1011011] = '2'; //not needed, decoded correctly
	//SS_to_Char[0b1001111] = '3'; //not needed, decoded correctly
	SS_to_Char[0b1100111] = '4';
	SS_to_Char[0b1101100] = '5';
	SS_to_Char[0b1111100] = '6';
	//SS_to_Char[0b0000111] = '7'; //not needed, decoded correctly
	SS_to_Char[0b1111111] = '8'; //not needed, decoded correctly
	SS_to_Char[0b1101111] = '9'; //not needed, decoded correctly

#endif

	//init relay board driver
	int ret = pfio_init();
       	if ( ret ) {
		fprintf(stderr, "PumpInterface, error initializeing relay board driver\n");
		return -1;
	}

	_p1Mask = pfio_get_pin_bit_mask(P1_PIN);
       	_p2Mask = pfio_get_pin_bit_mask(P2_PIN);
       	_p3Mask = pfio_get_pin_bit_mask(P3_PIN);
       	_p4Mask = pfio_get_pin_bit_mask(P4_PIN);
	_productsMask = _p1Mask | _p2Mask | _p3Mask | _p4Mask;

	_nozzle1Mask = pfio_get_pin_bit_mask(NOZZLE1_PIN);
       	_nozzle2Mask = pfio_get_pin_bit_mask(NOZZLE2_PIN);
	_nozzlesMask = _nozzle1Mask | _nozzle2Mask;
	fprintf(stderr, "nozzlesMask: 0x%X\n", _nozzlesMask);


	fprintf(stderr, "PumpInterface, relay board driver initialized successfully\n");

	return 0;
}

int myEnablePumps() {
	uint8_t new_output_reg, old_output_reg, output_bit_mask;
	
	old_output_reg = pfio_read_output();

	output_bit_mask = pfio_get_pin_bit_mask(RELAY1_PIN);
	output_bit_mask |= pfio_get_pin_bit_mask(RELAY2_PIN);

	new_output_reg = old_output_reg | output_bit_mask;

	pfio_write_output(new_output_reg);
}

int myDisablePumps() {
	uint8_t new_output_reg, old_output_reg, output_bit_mask;
	
	old_output_reg = pfio_read_output();

	output_bit_mask = pfio_get_pin_bit_mask(RELAY1_PIN);
	output_bit_mask |= pfio_get_pin_bit_mask(RELAY2_PIN);

	new_output_reg = old_output_reg & ~output_bit_mask;

	pfio_write_output(new_output_reg);
}

int myNozzleReplaced(int ind) {
	uint8_t input_reg = pfio_read_input();
	uint8_t mask = ind ? _nozzle2Mask : _nozzle1Mask;	//ind == 1 means nozzle2, ind == 0 means nozzle1
	//fprintf(stderr, "mask: 0x%X, reg: 0x%X\n", mask, input_reg);

	return (input_reg & mask) ? 0 : 1;
}

//returns true if both nozzles are replaced, which means both inputs
//are high, which means corresponding bits of the reg are zero
int myBothNozzlesReplaced() {
	uint8_t input_reg = pfio_read_input();

	return (input_reg & _nozzlesMask) ? 0 : 1;
}

int myNozzleRemoved() {
	uint8_t input_reg = pfio_read_input();

	input_reg &= _nozzlesMask;	//Grrr switch is not allowed without compile time constant case lables..
	if (input_reg == _nozzle1Mask) {
		return 0;
	}
	else if (input_reg == _nozzle2Mask) {
		return 1;
	}
	else {
		return -1;
	}
}

int myTypeSelected() {
	uint8_t input_reg = pfio_read_input();
	//piface board inputs are active low, the corresponding bit in the input
	//reg will be one when the input pin is pulled ot ground
	//According to Doug, the type buttons on the fuel dispensers are active low
	//(level will be low when the button is depressed)

	input_reg &= _productsMask;	//Grrr switch is not allowed without compile time constant case lables..
	if (input_reg == _p1Mask) {		
		return P1_PIN;
	}
	else if (input_reg == _p2Mask ) {
		return P2_PIN;
	}
	else if (input_reg == _p3Mask) {
		return P3_PIN;
	}
	else if (input_reg == _p4Mask) {
		return P4_PIN;
	}
	else {
		return -1;
	}
}

int myMonitorRelBrdInputs() {
	/*
	clock_t t1, t2;
	int i, totalReads = 1000;
	t1 = clock();
	for (i = 0; i < totalReads; i++) {
	       	pfio_read_input();
	}
	t2 = clock();
	fprintf(stderr, "%d relay board reads took %f seconds\n", totalReads, (t2 - t1) / (double)CLOCKS_PER_SEC);
	*/

	uint8_t input_reg = pfio_read_input();
	fprintf(stderr, "0x%02X\n", input_reg);

	return 0;
}

irq_user_info *getDriverBuffer() {
	irq_user_info *buffer;
	fd = open(VFS_PATH, O_RDWR);

	fprintf(stderr, "getDriverBuffer() called, fd = %d.\n", fd);

	if (fd < 0) {
		fprintf(stderr, "PumpHandler, failed to open %s\n", VFS_PATH);
		return 0;
	}

	buffer = (irq_user_info *)mmap(NULL, pagesize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	if (buffer == MAP_FAILED) {
		releaseDriverBuffer();
		fprintf(stderr, "PumpHandler, mmap failed\n");
		return 0;
	}

	return buffer;
}

int releaseDriverBuffer() {
	fprintf(stderr, "releaseDriverBuffer() called, fd = %d.\n", fd);

	if ( fd > 0 ) {
		fprintf(stderr, "attempt to close %s\n", VFS_PATH);
		int ret = close(fd);
		fprintf(stderr, "close returned %d.\n", ret);
	}
	else {
		fprintf(stderr, "PumpHandler, releaseDriverBuffer() was called while fd was unacceptable\nWill continue..\n");
	}

	return 0;
}

int myIntercept(int nozInd, HV *retHash) {

	int i, j, k, clockedIn, b, oldLatch, errCode = 0;
	unsigned long volCoeff, costCoeff, cost, vol;	//need to fit up to 1000000 in these
	uint8_t tmpSS, nozzleReplacedFlag = 0;
	volatile irq_user_info *buf = getDriverBuffer();

	fprintf(stderr, "nozInd: %d\n", nozInd);

	//pointer will be NULL if the allocation was unseccessful
	if ( buf ) {
		fprintf(stderr, "init\n");
	
		oldLatch = buf->latchCount;
		//for (i = 0; i < 10; i++)
		while ( ! nozzleReplacedFlag ) {
			nozzleReplacedFlag = myNozzleReplaced(nozInd);

			fprintf(stderr, "%d, lacthcnt: %d\n", i, oldLatch);

			while (oldLatch == buf->latchCount) {
				//sleep(1);
			}

			//figure out how many bits were clocked in, indeces might have been wrapped
			//at 1024 or 0x0003ff
			b = buf->begin;	
			clockedIn = ( b < buf->end ) ? 
				(buf->end - b) : (1024 - b + buf->end);
			if ( clockedIn < E_B_L ) {		//probably missed some pulses
				errCode = -1;
				fprintf(stderr, "Only got %d clock edge(s), skipping\n", clockedIn);
			}
			else {
				//only last 96 bits are of interest
				b += ( (clockedIn > E_B_L) ? ( (clockedIn - E_B_L) & 0x0003ff ) : 0 );
				//decode to 12 bytes (12 x 8 bits)
				for (j = 0; j < 12; j++ ) {
					tmpSS = 0;
					for (k = 0; k < 8; k++) {
						//bits are clocked in LSB first, hence shift by k
						tmpSS += ( ( buf->dataBuffer[ (b + ( (j * 8) + k ) ) & 0x0003ff ] ) << k );
					}
					//bytes are clocked in last first, hence "11 - j"
					digs[11 - j] = DIG_FROM_SS(tmpSS); //tmpSS;
					//Doesn't matter when printing..
					//chrs[j] = CHAR_FROM_SS(tmpSS);
					//fprintf(stderr, "%u|%u||", digs[11-j], chrs[j]);
				}
				//fprintf(stderr, "\n");
				//fprintf(stderr, "digs: %s\n", chrs);
				cost = 0; costCoeff = 1;
				vol = 0; volCoeff = 1;
				for (j = 0; j < 6; j++) {	//digits 0-5 constitute the cost
					cost += digs[j] * costCoeff;
					costCoeff *= 10;
				}
				for ( ; j < 12; j++) {		//digits 6-11 constitute the vol
					vol += digs[j] * volCoeff;
					volCoeff *= 10;
				}
				fprintf(stderr, "$%4.2f\n%3.3fL\n", (float)cost / 100, (float)vol / 1000);
				errCode = 0;
			}
			oldLatch = buf->latchCount;
//		}

		//hmm...this does the right thing with regard to reference counts and stuff doesn't it??
		hv_stores(retHash, "cost", newSVuv(cost));
		hv_stores(retHash, "vol", newSVuv(vol));
		if ( errCode == -1 ) {
			hv_stores(retHash, "err", newSVpv("missedClock", 11));
		}
	}
	else {
		fprintf(stderr, "Error reading the data\n");
		releaseDriverBuffer();
		return -1;
	}

	releaseDriverBuffer();
	releaseDriverBuffer();
	return 0;
}


int myDestroy() {
	//clean up after pump_driver
	//releaseDriverBuffer();

	//clean up after relay_boad driver
	pfio_deinit();

	return 0;
}

};

1;
