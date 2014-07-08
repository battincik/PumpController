obj-m=pump_driver.o
PWD=$(shell pwd)
KDIR=$(KERNEL_SRC)

all: pump_driver

pump_driver: pump_driver.c pump_driver.h
	make -C $(KDIR) ARCH=arm CROSS_COMPILE=$(CCPREFIX) M=$(PWD) modules

clean:
	make -C $(KDIR) ARCH=arm M=$(PWD) clean


### 	$(MAKE) -C /lib/modules/$(KVERSION)/build M=$(PWD) modules
