ASFLAGS = --32

all:	picohttpd

picohttpd:	picohttpd.o
	$(LD) -m elf_i386 -s $^ -o $@

clean:
	rm -f *.o picohttpd *~ core

.PHONY:	all clean
