# picohttpd v2 for i386 Linux
# (C) Copyright 2001-2003 by Wojtek Kaniewski <wojtekka@toxygen.net>
# Released under terms of GNU GPL version 2
#
# This httpd is pretty useless. It doesn't support vhosts, userdirs,
# listing directory contents, CGI, PHP. It doesn't support full HTTP/1.0.
# It's insecure. It isn't portable. It's stupid. It's just a toy.

	.data

	port = 8000

document_root:
	.asciz "/home/httpd/html/"

error_header:
	.byte 9
	.ascii "HTTP/1.0 "
error_middle:
	.byte 8
	.ascii "\r\n\r\n<H1>"
error_footer:
	.byte 7
	.ascii "</H1>\r\n"

error404_text:
	.byte 13
	.ascii "404 Not Found"
error403_text:
	.byte 13
	.ascii "403 Forbidden"
error500_text:
	.byte 16
	.ascii "500 Server Error"

page_header:
	.byte 44
	.ascii "HTTP/1.0 200 OK\r\nServer: picohttpd2\r\nContent-type: "

text_html:
	.byte 9
	.ascii "text/html"
	
text_plain:
	.byte 10
	.ascii "text/plain"

image_gif:
	.byte 9
	.ascii "image/gif"

image_jpeg:
	.byte 10
	.ascii "image/jpeg"

image_png:
	.byte 9
	.ascii "image/png"

octet_stream:
	.byte 24
	.ascii "application/octet-stream"

rnrn:	.byte 4
	.ascii "\r\n\r\n"

ext_table:
	.long ('.'|'h'<<8|'t'<<16|'m'<<24), text_html
	.long ('h'|'t'<<8|'m'<<16|'l'<<24), text_html
	.long ('.'|'t'<<8|'x'<<16|'t'<<24), text_plain
	.long ('.'|'g'<<8|'i'<<16|'f'<<24), image_gif
	.long ('.'|'p'<<8|'n'<<16|'g'<<24), image_png
	.long ('.'|'j'<<8|'p'<<16|'g'<<24), image_jpeg
	.long 0, octet_stream

server_sa:
	.word 2							# AF_INET
	.word ((port & 0xff00) >> 8 | (port & 0xff) << 8)	# htons(port)
	.long 0							# INADDR_ANY

	.bss

buf:	.space 1024, 0			# char buf[1024];
	buf.l = .-buf
len:	.long 0				# int len;
buf2:	.space buf.l+256, 0		# char buf2[sizeof(buf)+256];

s_args:					# int s_args[5];
s_arg0:	.long 0
s_arg1:	.long 0
s_arg2:	.long 0
s_arg3:	.long 0
s_arg4:	.long 0

s_fd:	.long 0				# int s_fd;
c_fd:	.long 0				# int c_fd;

sa:	.space 128, 0			# struct sockaddr_in sa;
	sizeof_sa = . - sa
salen:	.long 0				# int salen;

stat:	.space 64, 0			# struct stat stat;
fd:	.long 0				# int fd;
off:	.long 0				# int off;

	O_RDONLY = 0
	AF_INET = 2
	SOCK_STREAM = 1
	IPPROTO_TCP = 6
	SOL_SOCKET = 1
	SO_REUSEADDR = 2
	SYS_SOCKET = 1
	SYS_BIND = 2
	SYS_CONNECT = 3
	SYS_LISTEN = 4
	SYS_ACCEPT = 5
	SYS_SETSOCKOPT = 14
	INADDR_ANY = 0
	EINTR = 4
	ECHILD = 10
	SIGCHLD = 17
	WNOHANG = 1
	NR_exit = 1
	NR_fork = 2
	NR_read = 3
	NR_write = 4
	NR_open = 5
	NR_close = 6
	NR_waitpid = 7
	NR_signal = 48
	NR_fstat = 108
	NR_sendfile = 187
	st_size = 20
	sin_family = 0
	sin_port = 2
	sin_addr = 4

.macro	socketcall call			# all socket calls are done
	movl $102, %eax			# by the same syscall.
	movl \call, %ebx
	movl $s_args, %ecx
	int $0x80
.endm

	.text
	
	.global _start
_start:
	call setup_sigchld

	movl $AF_INET, s_arg0		# s_fd = socket(AF_INET, ...);
	movl $SOCK_STREAM, s_arg1
	movl $0, s_arg2
	socketcall $SYS_SOCKET
	movl %eax, s_fd

	movl $1, off			# off = 1;
	movl %eax, s_arg0		# setsockopt(s_fd, SOL_SOCKET,
	movl $SOL_SOCKET, s_arg1	#   SO_REUSEADDR, &off, sizeo(off));
	movl $SO_REUSEADDR, s_arg2
	movl $off, s_arg3
	movl $4, s_arg4
	socketcall $SYS_SETSOCKOPT

	movl s_fd, %eax			# bind(s_fd, &sa, sizeof(sa));
	movl %eax, s_arg0		
	movl $server_sa, s_arg1
	movl $128, s_arg2
	socketcall $SYS_BIND

	cmpl $-1, %eax
	je exit

	movl s_fd, %eax			# listen(s_fd, 64);
	movl %eax, s_arg0
	movl $64, s_arg1
	socketcall $SYS_LISTEN

main_loop:
	movl s_fd, %eax			# c_fd = accept(s_fd, ...);
	movl %eax, s_arg0
	movl $sa, s_arg1
	movl $sizeof_sa, salen
	movl $salen, s_arg2
	socketcall $SYS_ACCEPT
	mov %eax, c_fd

	cmpl $0, %eax			# if (c_fd > 0) goto accept_ok;
	jg accept_ok

	cmpl $-EINTR, %eax		# if (c_fd != -EINTR) exit(0);
	jne exit

	jmp main_loop

accept_ok:
	movl $NR_fork, %eax		# tmp = fork();
	int $0x80

	orl %eax, %eax			# if (!tmp) goto handle_client;
	jz handle_client

	movl $NR_close, %eax		# close(c_fd);
	movl c_fd, %ebx
	int $0x80

	jmp main_loop
	
handle_client:
	movl c_fd, %ebx			# len = read(c_fd, buf, ...);
	movl $NR_read, %eax
	movl $buf, %ecx
	movl $buf.l, %edx
	int $0x80
	movl %eax, len

	cmpl $5, %eax			# if (len < 6) goto error500;
	jng error500

	cmpl $('G'|'E'<<8|'T'<<16|' '<<24), buf
	jnz error500			# if (buf[:3] != "GET ") goto error500;

	movl len, %ecx			# for (i = 0; i < len; i++) {
	movl $buf+4, %esi		#   p = buf + 4;
url:	lodsb				#   q = *p++;
	cmpb $' ', %al			#   if (q == ' ') break;
	jz last
	cmpb $'\r', %al			#   if (q == '\r') break;
	jz last
	cmpb $'\n', %al			#   if (q == '\n') break;
	jz last
	loop url			# }
last:	decl %esi			# p--;
	movl %esi, %edi
	xor %eax, %eax
	stosb				# *p = 0;

fetch:	movl $buf+4, %esi		# p = buf + 4;
	xorl %eax, %eax			# for (r = 0;;) {
trav:	lodsb				#   q = *p++;
	cmpb $0, %al			#   if (!p) goto done;
	jz done	
	cmpb $'.', %al			#   if (q == '.' && r == '.')
	jnz next2			#     goto error403;
	cmpb $'.', %ah
	jnz next2
	jmp error403
next2:	movb %al, %ah			#   r = q;
	jmp trav			# }

done:
	cld				# strcpy(buf2, document_root);
	movl $buf2, %edi
	movl $document_root, %esi
	xorl %eax, %eax
cpy1:	lodsb
	stosb
	orl %eax, %eax
	jnz cpy1

	decl %edi

	movl $buf+4, %esi		# strcat(buf2, buf + 4);
	xorl %eax, %eax
cpy2:	lodsb
	stosb
	orl %eax, %eax
	jnz cpy2

	subl $2, %esi			# if (buf2[strlen(buf2)-1] != '/')
	lodsb				#   goto notind;
	cmp $'/', %al
	jnz notind

	movl $('i'|'n'<<8|'d'<<16|'e'<<24), -1(%edi)
	movl $('x'|'.'<<8|'h'<<16|'t'<<24), 3(%edi)
	movl $('m'|'l'<<8), 7(%edi)
	addl $10, %edi			# strcat(buf2, "index.html");

notind:	push %edi

	movl $NR_open, %eax		# fd = open(buf2, O_RDONLY);
	movl $buf2, %ebx
	movl $O_RDONLY, %ecx
	int $0x80
	movl %eax, fd

	pop %edi

	andl $0x8000000, %eax		# if (fd < 0) goto error404;
	jnz error404

	push %edi
	movl $page_header, %esi		# write(c_fd, page_header, ...);
	call client_write
	pop %edi

	mov %edi, %esi
	subl $5, %esi
	lodsl
	mov %eax, %ebx

	mov $ext_table, %esi
ext_next:
	lodsl
	jz ext_match
	cmp %eax, %ebx
	je ext_match
	lodsl
	jmp ext_next

ext_match:
	lodsl
	mov %eax, %esi
	call client_write		# write(c_fd, ext[x], ...);

	movl $rnrn, %esi
	call client_write
	
	movl $NR_fstat, %eax		# fstat(fd, &stat);
	movl fd, %ebx
	movl $stat, %ecx
	int $0x80

	movl $0, off			# sendfile(..., &off, stat.st_size);
	movl $NR_sendfile, %eax
	movl c_fd, %ebx
	movl fd, %ecx
	movl $off, %edx
	movl stat+st_size, %esi
	int $0x80

exit:
	movl $NR_exit, %eax
	xorl %ebx, %ebx
	int $0x80

error403:
	movl $error403_text, %esi
	jmp send_error

error404:
	movl $error404_text, %esi
	jmp send_error

error500:
	movl $error500_text, %esi
	jmp send_error

send_error:
	push %esi
	mov $error_header, %esi
	call client_write
	pop %esi
	push %esi
	call client_write
	mov $error_middle, %esi
	call client_write
	pop %esi
	call client_write
	mov $error_footer, %esi
	call client_write
	jmp exit

client_write:
	cld
	xor %eax, %eax
	lodsb
	movl %eax, %edx
	movl c_fd, %ebx
	movl $NR_write, %eax
	movl %esi, %ecx
	int $0x80
	ret

setup_sigchld:
	movl $NR_signal, %eax		# signal(SIGCHLD, waitpid);
	movl $SIGCHLD, %ebx
	movl $waitpid, %ecx
	int $0x80
	
	ret

waitpid:
	call setup_sigchld

	movl $NR_waitpid, %eax		# if (waitpid(0, 0, WNOHANG) > 0)
	xorl %ebx, %ebx			#   goto waitpid;
	xorl %ecx, %ecx
	movl $WNOHANG, %edx
	int $0x80

	cmpl $0, %eax
	jg waitpid

	ret

