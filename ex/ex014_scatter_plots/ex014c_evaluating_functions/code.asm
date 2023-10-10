;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;DEFINITIONS;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%define LOAD_ADDRESS 0x00020000 ; pretty much any number >0 works
%define CODE_SIZE END-(LOAD_ADDRESS+0x78) ; everything beyond HEADER is code
%define PRINT_BUFFER_SIZE 4096
%define HEAP_SIZE 2048

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;HEADER;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BITS 64
org LOAD_ADDRESS
ELF_HEADER:
	db 0x7F,"ELF" ; magic number to indicate ELF file
	db 0x02 ; 0x1 for 32-bit, 0x2 for 64-bit
	db 0x01 ; 0x1 for little endian, 0x2 for big endian
	db 0x01 ; 0x1 for current version of ELF
	db 0x09 ; 0x9 for FreeBSD, 0x3 for Linux (doesn't seem to matter)
	db 0x00 ; ABI version (ignored?)
	times 7 db 0x00 ; 7 padding bytes
	dw 0x0002 ; executable file
	dw 0x003E ; AMD x86-64 
	dd 0x00000001 ; version 1
	dq START ; entry point for our program
	dq 0x0000000000000040 ; 0x40 offset from ELF_HEADER to PROGRAM_HEADER
	dq 0x0000000000000000 ; section header offset (we don't have this)
	dd 0x00000000 ; unused flags
	dw 0x0040 ; 64-byte size of ELF_HEADER
	dw 0x0038 ; 56-byte size of each program header entry
	dw 0x0001 ; number of program header entries (we have one)
	dw 0x0000 ; size of each section header entry (none)
	dw 0x0000 ; number of section header entries (none)
	dw 0x0000 ; index in section header table for section names (waste)
PROGRAM_HEADER:
	dd 0x00000001 ; 0x1 for loadable program segment
	dd 0x00000007 ; read/write/execute flags
	dq 0x0000000000000078 ; offset of code start in file image (0x40+0x38)
	dq LOAD_ADDRESS+0x78 ; virtual address of segment in memory
	dq 0x0000000000000000 ; physical address of segment in memory (ignored?)
	dq CODE_SIZE ; size (bytes) of segment in file image
	dq CODE_SIZE+PRINT_BUFFER_SIZE+HEAP_SIZE ; size (bytes) of segment in memory
	dq 0x0000000000000000 ; alignment (doesn't matter, only 1 segment)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;INCLUDES;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%include "syscalls.asm"	; requires syscall listing for your OS in lib/sys/	

%include "lib/io/file_open.asm"
; int {rax} file_open(char* {rdi}, int {rsi}, int {rdx});

%include "lib/io/file_close.asm"
; int {rax} file_close(int {rdi});

%include "lib/io/svg/scatter_plot.asm"
; void scatter_plot(uint {rdi}, struct* {rsi});

%include "lib/math/parametric/evaluate_parameters.asm"
; bool {rax} evaluate_parameters(void* {rdi}, void* {rsi}, void* {rdx});

%include "lib/math/parametric/linear_space.asm"
; bool {rax} linear_space(double* {rdi}, long {rsi}, ulong {rdx}
;			double {xmm0}, double {xmm1});

%include "lib/mem/heap_init.asm"
; void heap_init(void);

%include "lib/mem/heap_alloc.asm"
; void* {rax} heap_alloc(long {rdi});

%include "lib/sys/exit.asm"	
; void exit(byte {dil});

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;INSTRUCTIONS;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

function: ; takes 1 double from [rsp+8] and computes polynomial thereof

	sub rsp,64
	movdqu [rsp+0],xmm0
	movdqu [rsp+16],xmm1
	movdqu [rsp+32],xmm2
	movdqu [rsp+48],xmm3

	movq xmm3,[rsp+72]	; sets value from stack
	
	movsd xmm0,[START.two]	; f(x)=2

	subsd xmm0,xmm3		; f(x)=-x+2

	movsd xmm1,xmm3
	mulsd xmm1,xmm3
	movsd xmm2,xmm1
	mulsd xmm2,[START.three]	
	subsd xmm0,xmm2		; f(x)=-3x^2-x+2

	mulsd xmm1,xmm3
	addsd xmm0,xmm1		; f(x)=x^3-3x^2-x+2

	movq [rsp+72],xmm0	; moves value to stack

	movdqu xmm0,[rsp+0]
	movdqu xmm1,[rsp+16]
	movdqu xmm2,[rsp+32]
	movdqu xmm3,[rsp+48]

	add rsp,64

	ret			; returns

START:

	; initialize heap for arrays
	call heap_init

	; allocate arrays on heap
	mov rdi,808	; 101x 8-byte doubles
	call heap_alloc
	mov r12,rax	; save pointer to x_array in {r12}
	mov rdi,808	; 101x 8-byte doubles
	call heap_alloc
	mov r13,rax	; save pointer to y_array in {r13}

	; store heap locations of arrays into structures
	mov [.x_param+8],r12
	mov [.data+16],r12
	mov [.y_param+8],r13
	mov [.data+26],r13

	; create linear spacing in x_param
	movsd xmm0,[.neg_two]
	movsd xmm1,[.four]
	mov rdi,r12	; location of x_array on heap
	xor rsi,rsi
	mov rdx,101
	call linear_space

	; evaluate function of x_param into y_param
	mov rdi,.y_param
	mov rsi,.x_param
	mov rdx,function
	call evaluate_parameters

	; open file
	mov rdi,.filename
	mov rsi,SYS_READ_WRITE+SYS_CREATE_FILE+SYS_TRUNCATE
	mov rdx,SYS_DEFAULT_PERMISSIONS
	call file_open	; file descriptor in {rax}

	; write scatter plot to SVG file
	mov rdi,rax			; output file descriptor
	mov rsi,.plot_structure		; structure start address
	call scatter_plot

	; close file
	call file_close

	; exit
	xor dil,dil
	call exit	

.x_param:
	dq 0 ; address of next parameter in list (0 on last element)
	dq 0 ; address of first parameter value
	dq 0 ; extra stride between parameter values
	dq 101 ; number of values (only matters for first input parameter in linked list)
	dq 0 ; work zone (track address of current element), initial value unused

.y_param:
	dq 0 ; address of next parameter in list (0 on last element)
	dq 0 ; address of first parameter value
	dq 0 ; extra stride between parameter values
	dq 101 ; number of values (only matters for first input parameter in linked list)
	dq 0 ; work zone (track address of current element), initial value unused

.two:
	dq 2.0

.three:
	dq 3.0

.neg_two:
	dq -2.0

.four:
	dq 4.0

.filename:
	db `func.svg\0`

.title:
	db `f(x)=x^3-3x^2-x+2\0`

.xlabel:
	db `x\0`

.ylabel:
	db `f(x)\0`

.plot_structure:
	dq .title; address of null-terminated title string {*+0}
	dq .xlabel; address of null-terminated x-label string {*+8}
	dq .ylabel; address of null-terminated y-label string {*+16}
	dq .data; address of linked list for datasets {*+24}
	dw 480; plot width (px) {*+32}
	dw 200; plot height (px) {*+34}
	dw 5; plot margins (px) {*+36}
	dq -2.0; x-min (double) {*+38}
	dq 4.0; x-max (double) {*+46}
	dq -18.0; y-min (double) {*+54}
	dq 18.0; y-max (double) {*+62}
	dw 0; legend left x-coordinate (px) {*+70}
	dw 0; legend top y-coordinate (px) {*+72}
	dw 0; legend width (px) {*+74}
	dd 0xFFFFFF; #XXXXXX RGB background color {*+76}
	dd 0x000000; #XXXXXX RGB axis color {*+80}
	dd 0x000000; #XXXXXX RGB font color {*+84}
	db 7; number of major x-ticks {*+88}
	db 7; number of major y-ticks {*+89}
	db 0; minor subdivisions per x-tick {*+90}
	db 0; minor subdivisions per y-tick {*+91}
	db 2; significant digits on x values {*+92}
	db 2; significant digits on y values {*+93}
	db 14; title font size (px) {*+94}
	db 5; vertical margin below title (px) {*+95}
	db 12; axis label font size (px) {*+96}
	db 8; tick & legend label font size (px) {*+97}
	db 5; horizontal margin right of y-tick labels (px) {*+98}
	db 5; vertical margin above x-tick labels (px) {*+99}
	db 1; grid major stroke thickness (px) {*+100}
	db 0; grid minor stroke thickness (px) {*+101}
	db 30; width for y-axis ticks (px) {*+102}
	db 30; height for x-axis ticks (px) {*+103}
	db 0x1F; flags: {*+104}
		; bit 0 (LSB)	= show title?
		; bit 1		= show x-label?
		; bit 2		= show y-label?
		; bit 3		= draw grid?
		; bit 4		= show tick labels?
		; bit 5		= draw legend?

.data:
	dq 0; address of next dataset in linked list {*+0}
	dq 0; address of null-terminated label string {*+8}
	dq 0; address of first x-coordinate {*+16}
	dw 0; extra stride between x-coord elements {*+24}
	dq 0; address of first y-coordinate {*+26}
	dw 0; extra stride between y-coord elements {*+34}
	dd 101; number of elements {*+36}
	dd 0x000000; #XXXXXX RGB marker color {*+40}
	dd 0xFF0000; #XXXXXX RGB line color {*+44}
	dd 0x000000; #XXXXXX RGB fill color {*+48}
	db 1; marker size (px) {*+52}
	db 2; line thickness (px) {*+53}
	db 0; fill opacity (%) {*+54}
	db 0x03; flags: {*+55}
		; bit 0 (LSB)	= point marker?
		; bit 1		= connecting lines?
		; bit 2		= dashed line? (bit 1 must be set)
		; bit 3		= fill?
		; bit 4		= include in legend?
		; bits 6-5	= 00 = no curves
		;		= 01 = quadratic bezier
		;		= 10 = cubic bezier
		;		= 11 = arc

END:

PRINT_BUFFER: 	; PRINT_BUFFER_SIZE bytes will be allocated here at runtime,
		; all initialized to zeros

HEAP_START_ADDRESS equ (PRINT_BUFFER+PRINT_BUFFER_SIZE)
