;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;DEFINITIONS;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%define LOAD_ADDRESS 0x00020000 ; pretty much any number >0 works
%define CODE_SIZE END-(LOAD_ADDRESS+0x78) ; everything beyond HEADER is code
%define PRINT_BUFFER_SIZE 4096
;%define HEAP_SIZE 0x2000000 ; ~32 MB

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
	dq CODE_SIZE+PRINT_BUFFER_SIZE;+HEAP_SIZE ; size (bytes) of segment in memory
	dq 0x0000000000000000 ; alignment (doesn't matter, only 1 segment)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;INCLUDES;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%include "syscalls.asm"	; requires syscall listing for your OS in lib/sys/	

%include "lib/math/rand/rand_float_array.asm" 
%include "lib/math/rand/rand_float.asm" 

%include "lib/time/tick_time.asm" 
%include "lib/time/tock_time.asm" 

%include "lib/math/expressions/trig/sine.asm"
%include "lib/math/expressions/trig/cosine.asm"

%include "lib/io/print_string.asm"
%include "lib/io/print_float.asm"
%include "lib/io/print_int_d.asm"

%include "lib/sys/exit.asm"

%include "lib/debug/debug.asm"


%include "sine_lookup.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;INSTRUCTIONS;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

START:

	; populate our random numbers
	mov rdi,.rands
	xor rsi,rsi
	mov rdx,5
	movsd xmm0,[.bounds]
	movsd xmm1,[.bounds+8]
	call rand_float_array

	mov r14,.rands

.input_loop:

	movsd xmm0,[r14]

	mov rdi,SYS_STDOUT
	mov rsi,6
	call print_float

	mov rsi,.grammar
	mov rdx,3
	call print_chars

	add r14,8
	cmp r14,.rands_end
	jl .input_loop

	mov rsi,.grammar+5
	mov rdx,1
	call print_chars

	mov r15,.func_table

.func_loop:

	mov rdi,SYS_STDOUT
	mov rsi,r15
	call print_string

	mov rsi,.grammar
	mov rdx,3
	call print_chars

	mov r14,.rands
	add r15,8

.value_loop:


	movsd xmm0,[r14]
	call [r15]

	mov rdi,SYS_STDOUT
	mov rsi,6
	call print_float

	mov rsi,.grammar
	mov rdx,3
	call print_chars

	add r14,8
	cmp r14,.rands_end
	jl .value_loop

	call tick_time
	mov rcx,[.n_calls]

.time_loop:

;	movsd xmm0,[.bounds]
;	movsd xmm1,[.bounds+8]
;	call rand_float
	call [r15]
	dec rcx
	jnz .time_loop

	call tock_time
	mov rdi,SYS_STDOUT
	mov rsi,rax
	call print_int_d

	mov rsi,.grammar+2
	mov rdx,4
	call print_chars

	call print_buffer_flush

	add r15,8	
	cmp r15,.func_table_end
	jl .func_loop


	xor dil,dil
	call exit


align 8
.rands:
	times 5 dq 0.0
.rands_end:

.bounds:
	dq -10.00,10.00

.n_funcs:
	db 3
.n_calls:
	dq 10000

align 8
.func_table:
	db `ret0   `,0
	dq SINE_FUNC_1
	db `Tseries`,0
	dq SINE_FUNC_2
	db `lookupC`,0
	dq SINE_FUNC_3
.func_table_end:

.grammar:
	db ` | us\n`

align 64
SINE_FUNC_1:

	pxor xmm0,xmm0
	ret

align 64
SINE_FUNC_2:

	movsd xmm1,[.tol]
	call sine

	ret

.tol:
	dq 0.000001

align 64
SINE_FUNC_3:

	call sine_lookup
	ret

END:

PRINT_BUFFER: 	; PRINT_BUFFER_SIZE bytes will be allocated here at runtime,
		; all initialized to zeros

;HEAP_START_ADDRESS equ (PRINT_BUFFER+PRINT_BUFFER_SIZE)

