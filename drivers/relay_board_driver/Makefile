CC=gcc
CFLAGS=-Wall
AR=ar
ARFLAGS=rcs

all: pfio

pfio: pfio.o
	$(AR) $(ARFLAGS) libpfio.a pfio.o 

pfio.o: pfio.c
	$(CC) $(CFLAGS) -c -o pfio.o pfio.c

clean:
	rm *.[ao]
