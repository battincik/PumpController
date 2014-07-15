#ifndef __PUMP_DRIVER_UTIL__
#define __PUMP_DRIVER_UTIL__

/*
 * loop delay_cycles
 * Tested this against PMC cycle counter ran at 3x + 20-30
 *  **This is the first attempt** Tested this against PMC cycle counter ran at 2x + 20 fairly consistently.
 */
//#define NOP() asm("MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;MOV r0, r0;") 
inline static void delayCycles(uint32_t count) {
//	NOP();
/*	asm volatile(
			"delayLoop_%=: subs %[cnt], %[cnt], #1\n\t"
			"bne delayLoop_%=" 
			:: [cnt]"r"(count) : "cc");
*/			
			
	for ( ; count != 0; count--) {
		__asm volatile("MOV r0, r0");
	}
	
}

#define ARMV6_PMCR_DISABLE	(0)
#define ARMV6_PMCR_ENABLE	(1 << 0)
#define ARMV6_PMCR_CCOUNT_RESET	(1 << 2)
/*
 * Write to Performance Monitor Control Register
 * dmb() is not required after each read or write 
 * unless "a peripheral read or write may be followed
 * by a read or write of a different peripheral" 
 * This is not for sync purposes.
 * See BCM2835 ARM Peripherals, sec 1.3
 *dmb: asm ("mov r12, #0; mcr p15, 0, r12, c7, c10, 5; mov pc, lr;")
 */
static inline void armv6_pmcr_write(uint32_t val)
{
	asm volatile("mcr p15, 0, %0, c15, c12, 0" :: "r"(val));
	//dmb()
}

/* Read the PMC cycle couner
 * PMC has three counters: 
 * ARMV6_CYCLE_COUNTER 1
 * ARMV6_COUNTER0 2
 * ARMV6_COUNTER1 3
 */
static inline uint32_t pmc_ccnt_read (void) {
	uint32_t cycleCount;
	//dmb()
	asm volatile ("mrc p15, 0, %0, c15, c12, 1" : "=r"(cycleCount));
	return cycleCount;
}

/*
 * Definitions and addresses for the ARM CONTROL logic
 * This file is manually generated.
*/
//#define BCM2708_PERI_BASE        0x20000000
//#define ST_BASE                  (BCM2708_PERI_BASE + 0x3000)   /* System Timer */

/** Layout of the BCM2835 System Timer's registers. */
//
//struct bcm2835_timer_regs {
//	unsigned int CS; /** System Timer Control/Status */
//	unsigned int CLO; /** System Timer Counter Lower 32 bits */
//	unsigned int CHI; /** System Timer Counter Higher 32 bits */
//	unsigned int C0; /** System Timer Compare 0. DO NOT USE; is used by GPU. */
//	unsigned int C1; /** System Timer Compare 1 */
//	unsigned int C2; /** System Timer Compare 2. DO NOT USE; is used by GPU. */
//	unsigned int C3; /** System Timer Compare 3 */
//};
//static volatile struct bcm2835_timer_regs * const regs =
//        (volatile struct bcm2835_timer_regs*)ST_BASE;
//

#define VIRT_BASE (0xf2000000)
#define VIRT_ST_BASE (VIRT_BASE + 0x3000)
#define VIRT_ST_CLO (VIRT_ST_BASE + 0x04)	//CLO counter lower 32b

/*
 * read the lower 32 bits of the 'system timer' counter
 */
inline static uint32_t st_cnt_read (void) {
	volatile uint32_t cc;
	cc = *(volatile unsigned int *) VIRT_ST_CLO; 
	return cc;
}

#define VIRT_GPIO_BASE (VIRT_BASE + 0x200000)
#define VIRT_GPPUD (VIRT_GPIO_BASE + 0x0094)
#define VIRT_GPPUDCLK0 (VIRT_GPIO_BASE + 0x0098)
#define VIRT_GPPUDCLK1 (VIRT_GPIO_BASE + 0x009c)

#define GPIO_PUD_DISABLE	(0)
#define GPIO_PUD_PD		(0x01)
#define GPIO_PUD_PU		(0x02)

/*
 * Just following BCM2835 ARM Peripherals, section 6.1
 * Have to write to PUD reg and 'apply' it by enabling the clock.
 * Cuz the PUD setting is kept even when the chip is not powered..
 * Required delay is actually 150 cycles. See the comments on delayCycles()
 *
 * We are using pins 17, 22, 23 all ( < 32 ) set via PUDCLK0 
 * There is no check on the arguments. Intended for users who know what they are doing ...
 */
inline static void setPinPUD(uint8_t pin, uint32_t pud) {
	*(volatile uint32_t *) VIRT_GPPUD = pud;
	delayCycles(75);
	*(volatile uint32_t *) VIRT_GPPUDCLK0 = (0x00000001 << pin);
	delayCycles(75);
	*(volatile uint32_t *) VIRT_GPPUD = GPIO_PUD_DISABLE;
	*(volatile uint32_t *) VIRT_GPPUDCLK0 = 0x00000000;
	//dmb()
}

#endif
