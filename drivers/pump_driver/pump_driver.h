
#define	CLOCK_PIN	17		// P1.11 <-> gpio 17
#define	DATA_PIN	22		// P1.15 <-> gpio 22
#define	LATCH_PIN	23		// P1.16 <-> gpio 23

#define E_B_L		96		//expected bits per latch
#define FIX_A_SEG_IF_POSSIBLE 1		//Sometimes control is passed to the ISR a bit late
					//later than 3us past the first rising edge of the clock 
					//which causes the sampled to actually be the same as the
					//second bit. If it there some redundancy in the 7-seg
					//encoding which can be used to fix erros in the first bit.. 

#define MAPPED_BUFFER_FILENAME "pump_driver_buffer"
#define VFS_PATH "/sys/kernel/debug/pump_driver_buffer"

// size of my buffer in 8 bit words
// sizeof(irq_user_info) must be smaller than a page which on the Pi is 4069 bytes..
#define	kIRQbuffSize	1024

typedef struct irq_user_info {
	unsigned char dataBuffer[kIRQbuffSize]; /* the data */
	unsigned short clkCount;
	unsigned short end;
	unsigned short begin;
	unsigned short latchCount;
} irq_user_info;

