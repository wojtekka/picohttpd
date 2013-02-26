all:	picohttpd

picohttpd:	picohttpd.o
	$(LD) -s $^ -o $@

clean:
	rm -f *.o picohttpd *~ core

.PHONY:	all clean
