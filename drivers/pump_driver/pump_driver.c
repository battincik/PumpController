#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/irq.h>
#include <linux/interrupt.h>
#include <linux/gpio.h>
#include <linux/fs.h>
#include <linux/debugfs.h>
#include <linux/mm.h>  		// mmap related stuff */

#include <linux/slab.h>  	// kmalloc  kfree 

#include "pump_driver_util.h"
#include "pump_driver.h"  


static struct dentry  *vfs_fd;

struct mmap_info {
	irq_user_info *usrData;		//user space data
	int reference;       		// mmap refrence count
};

static irq_user_info *myUsrData;
static int latchPin_irq_number;

//static unsigned char opened = 0;

static int fops_mmap(struct file *filp, struct vm_area_struct *vma);
static int fops_open(struct inode *inode, struct file *filp);
static int fops_close(struct inode *inode, struct file *filp);

static void mmap_open(struct vm_area_struct *vma);
static void mmap_close(struct vm_area_struct *vma);
static int mmap_fault(struct vm_area_struct *vma, struct vm_fault *vmf);

static struct vm_operations_struct mmap_vm_ops = {
	.open =     mmap_open,
	.close =    mmap_close,
	.fault =   mmap_fault,
};

static const struct file_operations my_fops = {
	.open = fops_open,
	.mmap = fops_mmap,
	.release = fops_close,
};

#define CLK_CNT_INCR(x)	( x->clkCount = (x->clkCount + 1) & 0x0003ff )	// wraps at 1023

unsigned long flags;
volatile unsigned long cpuCount;
unsigned char restored = 1;

/*
static void test(void) {
	volatile uint32_t c1, c2, c3, c4;
	printk(KERN_ERR "TEST: 0\n");
	c1 = st_cnt_read(); c2 = c1;
//	printk(KERN_ERR "cnt: %u, cpu cnt: %u\n", c1, pmc_ccnt_read());
//	while ( (c2 - c1) < 10 ) {
		c3 = pmc_ccnt_read();
		delayCycles(46);
		//setPinPUD(LATCH_PIN, GPIO_PUD_PU);
		c4 = pmc_ccnt_read();
		c2 = st_cnt_read();
		printk(KERN_ERR "delay: %u, cpu: %u\n", (c2 - c1), (c4 - c3));
//	}
}
*/
/*
char debugStr[97] = {0};
*/
 
static irqreturn_t gpio_rising_interrupt(int irq, void* dev_id) {

	volatile uint32_t c1, c2;
	uint16_t clkCount;
	uint8_t oldClk, newClk, bail, i;
	bail = 0;
/*
	volatile uint32_t c3, c4;
*/
	if ( myUsrData ) {

		if ( irq == latchPin_irq_number ) {
			local_irq_save(flags);
			restored = 0;

			/* printk(KERN_ERR "ISR: 0\n"); */
			c1 = st_cnt_read(); c2 = c1;
			/* printk(KERN_ERR "cnt: %u\n", c1); */
			while ( (c2 - c1) < 300 ) {
				c2 = st_cnt_read();
				if ( ! __gpio_get_value(LATCH_PIN) ) {
					/* printk(KERN_ERR "Pump driver: width %u\n", c2 - c1); */
					bail = 1;
					break;
				}
			}

			//we got a clean load pulse, clock in data
			clkCount = myUsrData->clkCount;
			if ( !bail ) {
				/* printk(KERN_ERR "Wide load: width %u\n", c2 - c1); */
				newClk = 0;
				for (i = 0; i < 96; i++) {
					do {
						oldClk = newClk;
						newClk = __gpio_get_value(CLOCK_PIN);
					} while ( (!oldClk) || newClk );
					//on falling edge of clock
					myUsrData->dataBuffer[ myUsrData->clkCount ] = __gpio_get_value(DATA_PIN);
					/* debugStr[i] = (char) 48 + myUsrData->dataBuffer[ myUsrData->clkCount ]; */
					CLK_CNT_INCR(myUsrData);

				}
				myUsrData->begin = clkCount;
				myUsrData->latchCount++;
				myUsrData->end = myUsrData->clkCount;
			}
			/* printk(KERN_ERR "Finished clocking in %s.", debugStr); */

			//bail!
			local_irq_restore(flags);
			restored = 1;
		}
		else {
			printk(KERN_ERR "Pump driver: wierd irq arg to the ISR");
		}
	}

	return(IRQ_HANDLED);
}

static int __init mymodule_init(void) {

	//myUsrData = 0;
	int ret;
	cpuCount = 0;

	printk("Pump driver: enabling PMCR\n");
/*	asm volatile("mcr   p15, 0, %0, c15, c9, 0" : : "r"(1));*/
	armv6_pmcr_write(ARMV6_PMCR_ENABLE);

	// create the debugfs file used to communicate buffer address to user space
	vfs_fd = debugfs_create_file(MAPPED_BUFFER_FILENAME, 0644, NULL, NULL, &my_fops);
	if ( ! vfs_fd ) {
		printk(KERN_ERR "Pump driver: failed to create vfs file\n");
		goto err;
	}

	
	if ( ret = gpio_request(LATCH_PIN, "PUMP -- Latch"), ret ) {
		printk(KERN_ERR "Pump driver: LATCH pin request failed %d\n", ret);
		goto relFile;
	}
	
	if ( ret = gpio_request(CLOCK_PIN, "PUMP -- Clock"), ret ) {
		printk(KERN_ERR "Pump driver: CLOCK pin request failed %d\n", ret);
		goto relLatchPin;
	}
	
	if ( ret = gpio_request(DATA_PIN, "PUMP -- Data"), ret ) {
		printk(KERN_ERR "Pump driver: DATA pin request failed %d\n", ret);
		goto relClockPin;
	}

	if ( gpio_direction_input(LATCH_PIN) || gpio_direction_input(CLOCK_PIN) || 
			gpio_direction_input(DATA_PIN) ) {
		printk(KERN_ERR "Pump driver: direction failed\n");
		goto relAllPins;
	}

	setPinPUD(LATCH_PIN, GPIO_PUD_PD);
	printk("Pump driver: GPIO PD enabled\n");
/*
	if ( gpio_set_debounce(LATCH_PIN, 0) || gpio_set_debounce(CLOCK_PIN, 0) ) {
		gpio_free(LATCH_PIN); gpio_free(CLOCK_PIN); gpio_free(DATA_PIN);
		printk(KERN_ERR "Pump driver: debounce set failed\n");
		return -EIO;
	}
*/
	latchPin_irq_number = gpio_to_irq(LATCH_PIN);


	if ( request_irq(latchPin_irq_number, gpio_rising_interrupt, 
				IRQF_TRIGGER_RISING, "pump_driver_clk_rising", NULL) ) {
		printk(KERN_ERR "Pump driver: trouble requesting IRQ %d", latchPin_irq_number);
		goto relAllPins;
	}

	disable_irq(latchPin_irq_number);

	printk("Pump driver: init successful\n");
	return 0;

	//clean up
relAllPins:
	gpio_free(DATA_PIN);
relClockPin:
	gpio_free(CLOCK_PIN);
relLatchPin:
	gpio_free(LATCH_PIN);
relFile:
	debugfs_remove(vfs_fd);
err:
	return -EIO;	

}

static void __exit mymodule_exit(void) {

	//clean up
	debugfs_remove(vfs_fd);
	printk("Pump driver: removed SMF\n");

	setPinPUD(LATCH_PIN, GPIO_PUD_DISABLE);
	printk("Pump driver: GPIO PUD disabled\n");

	gpio_free(LATCH_PIN);
	gpio_free(CLOCK_PIN);
	gpio_free(DATA_PIN);
	printk("Pump driver: freed GPIOs\n");

	free_irq(latchPin_irq_number, NULL);
	printk("Pump driver: released IRQ\n");

	if ( ! restored ) {
		printk("Pump driver: had to restore flags\n");
		local_irq_restore(flags);
		printk("Pump driver: restored flags\n");
	}

	printk("Pump driver: disabling PMCR\n");
/*	asm volatile("mcr   p15, 0, %0, c15, c9, 0" : : "r"(0));*/
	armv6_pmcr_write(ARMV6_PMCR_DISABLE);

	printk ("Pump driver: module unloaded\n");
	return;
}

//-----------------------------------------



/* keep track of how many times it is mmapped */
static void mmap_open(struct vm_area_struct *vma)
{
	struct mmap_info *info = (struct mmap_info *)vma->vm_private_data;
	info->reference++;
}

static void mmap_close(struct vm_area_struct *vma)
{
	struct mmap_info *info = (struct mmap_info *)vma->vm_private_data;
	info->reference--;
}

/* fault is called the first time a memory area is accessed which is not in memory,
 * it does the actual mapping between kernel and user space memory
 */
static int mmap_fault(struct vm_area_struct *vma, struct vm_fault *vmf)
{
	struct page *page;
 	struct mmap_info *info = (struct mmap_info *)vma->vm_private_data;
	
	//printk("mmap_fault called info=0x%8X\n",(unsigned int)info);

	/* the data is in vma->vm_private_data */
	if (!info) {
		printk("Pump driver: mmap_fault return VM_FAULT_OOM\n");
		return VM_FAULT_OOM;	
	}
	if (!info->usrData) {
		printk("Pump driver: mmap_fault return VM_FAULT_OOM\n");
		return VM_FAULT_OOM;	
	}

	if (info->usrData != myUsrData) {
		printk(KERN_ERR "Pump driver: WEIRD STUFF HAPPENING, module var mismatch!!\n");
	}


	//get the page
	page = virt_to_page(info->usrData);

	printk("Pump driver: page added via fault handler 0x%8X\n", (unsigned int) page);

	if (!page) {
		printk(KERN_ERR "Pump driver: mmap_fault return VM_FAULT_SIGBUS\n");
		return VM_FAULT_SIGBUS;
	}

	//increment the reference count of this page
	get_page(page);
	vmf->page = page;

	//printk("Pump driver: mmap_fault return 0\n");
	return 0;
}

//-----------------------------------------


static int fops_mmap(struct file *filp, struct vm_area_struct *vma)
{
	//printk("Pump driver: fops_mmap called\n");

	vma->vm_ops = &mmap_vm_ops;
	vma->vm_flags |= VM_RESERVED;
	// assign the file private data to the vm private data
	vma->vm_private_data = filp->private_data;

	mmap_open(vma);

	return 0;
}

static int fops_close(struct inode *inode, struct file *filp)
{
	struct mmap_info *info = filp->private_data;

	if ( ! restored ) {
		local_irq_restore(flags);
	}
	disable_irq(latchPin_irq_number);

	//opened = 0;

	printk("Pump driver: page freed in fops_close 0x%8X!!\n", (unsigned int) virt_to_page(info->usrData));

	free_page((unsigned long)info->usrData);
	kfree((const void *)info);
	
	//printk("Pump driver: fops_close called\n");
	filp->private_data = NULL;

	return 0;
}

static int fops_open(struct inode *inode, struct file *filp)
{
	struct mmap_info *info = kmalloc(sizeof(struct mmap_info), GFP_KERNEL);

/*	if ( opened ) {
		printk(KERN_ERR "Pump driver: a second open attemp\n");
		return -1;
	}
*/
	if (info) {
		//data is lass than a page (2096 bytes)
		info->usrData = (irq_user_info *)get_zeroed_page(GFP_KERNEL);
		
		printk("Pump driver: page allocated in fops_open 0x%8X!!\n", (unsigned int) virt_to_page(info->usrData));

		if (info->usrData) {
			//printk("Pump driver: fops_open called buffer=0x%8X\n", (unsigned int)info->usrData);
			myUsrData = info->usrData;
		}
		else {
			printk(KERN_ERR "Pump driver: error allocating sample buffer\n");
			kfree((const void *)info);
			return -1;
		}
	}
	else {
		printk(KERN_ERR "Pump driver: error allocating mmap info\n");
		return -1;
	}

	enable_irq(latchPin_irq_number);

	myUsrData->clkCount = 0;
	myUsrData->begin = 0;
	myUsrData->end = 0;
	myUsrData->latchCount = 0;

//	opened = 1;

	/* assign this info struct to the file */
	filp->private_data = info;
	inode->i_private = info;

	return 0;
}

module_init(mymodule_init);
module_exit(mymodule_exit);

MODULE_LICENSE("GPL");

/*
### make sure the kernel gets recompiled with 'CONFIG_DEBUG_FS=y' to enable debugfs.
###
### Before having access to the debugfs it has to be mounted with the following command.
### 'mount -t debugfs none /sys/kernel/debug'
###
*/


