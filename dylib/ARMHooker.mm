/*
 * RCSIpony - ARMHooker
 *  ARM/THUMB Inline hooking
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 27/04/2010
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <stdio.h>
#import <dlfcn.h>
#import <unistd.h>
#import <stdlib.h>

#import <mach/port.h>
#import <mach/vm_map.h>
#import <mach/mach_init.h>

#import "ARMHooker.h"

//#define DEBUG


//
// stolen from MobileSubstrate
//

enum A$r {
  A$r0, A$r1, A$r2, A$r3,
  A$r4, A$r5, A$r6, A$r7,
  A$r8, A$r9, A$r10, A$r11,
  A$r12, A$r13, A$r14, A$r15,
  A$sp = A$r13,
  A$lr = A$r14,
  A$pc = A$r15
};

#define A$ldr_rd_$rn_im$(rd, rn, im) /* ldr rd, [rn, #im] */ \
    (0xe5100000 | ((im) < 0 ? 0 : 1 << 23) | ((rn) << 16) | ((rd) << 12) | abs(im))
#define A$stmia_sp$_$r0$  0xe8ad0001 /* stmia sp!, {r0}   */
#define A$bx_r0           0xe12fff10 /* bx r0             */
  
#define T$pop_$r0$ 0xbc01 // pop {r0}
#define T$blx(rm) /* blx rm */ \
    (0x4780 | (rm << 3))
#define T$bx(rm) /* bx rm */ \
    (0x4700 | (rm << 3))
#define T$nop      0x46c0 // nop
  
#define T$add_rd_rm(rd, rm) /* add rd, rm */ \
    (0x4400 | (((rd) & 0x8) >> 3 << 7) | (((rm) & 0x8) >> 3 << 6) | (((rm) & 0x7) << 3) | ((rd) & 0x7))
#define T$push_r(r) /* push r... */ \
    (0xb400 | (((r) & (1 << A$lr)) >> A$lr << 8) | (r) & 0xff)
#define T$pop_r(r) /* pop r... */ \
    (0xbc00 | (((r) & (1 << A$pc)) >> A$pc << 8) | (r) & 0xff)
#define T$mov_rd_rm(rd, rm) /* mov rd, rm */ \
    (0x4600 | (((rd) & 0x8) >> 3 << 7) | (((rm) & 0x8) >> 3 << 6) | (((rm) & 0x7) << 3) | ((rd) & 0x7))
#define T$ldr_rd_$rn_im_4$(rd, rn, im) /* ldr rd, [rn, #im * 4] */ \
    (0x6800 | (abs(im) << 6) | ((rn) << 3) | (rd))
#define T$ldr_rd_$pc_im_4$(rd, im) /* ldr rd, [PC, #im * 4] */ \
    (0x4800 | ((rd) << 8) | abs(im))

// This should be invoked manually
extern "C" void __clear_cache (char *beg, char *end);
  
static inline bool A$pcrel$r(uint32_t ic) {
  return (ic & 0x0c000000) == 0x04000000 && (ic & 0xf0000000) != 0xf0000000 && (ic & 0x000f0000) == 0x000f0000;
}

static inline bool T$32bit$i(uint16_t ic) {
  return ((ic & 0xe000) == 0xe000 && (ic & 0x1800) != 0x0000);
}

static inline bool T$pcrel$bl(uint16_t *ic) {
  return (ic[0] & 0xf800) == 0xf000 && (ic[1] & 0xf800) == 0xe800;
}

static inline bool T$pcrel$ldr(uint16_t ic) {
  return (ic & 0xf800) == 0x4800;
}

static inline bool T$pcrel$add(uint16_t ic) {
  return (ic & 0xff78) == 0x4478;
}

static inline bool T$pcrel$ldrw(uint16_t ic) {
  return (ic & 0xff7f) == 0xf85f;
}

//
// EoMobileSubstrate
//

/*
typedef struct {
  u_int   length;     // max 15
  u_char  mask[15];   // sequence of bytes in memory order
  u_char  opcode[15]; // sequence of bytes in memory order
}	AsmInstruction;

static AsmInstruction THUMB_prologues[] = {
  { 0x2, {0xFF, 0xFF}, {0xC0, 0x46} },    // nop
  { 0x2, {0xFF, 0xFF}, {0x0F, 0xB4} },    // push	{r0 - r3}
  { 0x2, {0xFF, 0xFF}, {0x90, 0xB5} },    // push {r4, r7, lr}
  { 0x2, {0xFF, 0xFF}, {0xF0, 0xB5} },    // push {r4 - r7, lr}
  { 0x2, {0xFF, 0xFF}, {0x03, 0xAF} },    // add r6, sp, #12
  // Deep prologue
  { 0x2, {0xFF, 0xFF}, {0x81, 0xB0} },    // sub sp, #4
  { 0x2, {0xFF, 0xFF}, {0x05, 0x1C} },    // adds r5, r0, #0
  { 0x2, {0xFF, 0xFF}, {0x08, 0x1C} },    // adds r0, r1, #0
  { 0x2, {0xFF, 0xFF}, {0x69, 0x46} },    // mov r1, sp
  { 0x0 }
};

static AsmInstruction ARM_prologues[] = {
  { 0x4, {0x00, 0x00, 0xFF, 0xFF}, {0x00, 0x00, 0x2D, 0xE9} },  // stmfd SP!, {??}
  { 0x4, {0x00, 0x00, 0xFF, 0xFF}, {0x00, 0x00, 0xA0, 0xE1} },  // mov ??, R12
  { 0x0 }
};
*/
#pragma mark	-
#pragma mark	Private Functions

int _AHOverride_ARM(char        *originalFunctionPtr,
                    const void  *newFunctionAddress,
                    void        **reentryIsland)
{
  kern_return_t error;
  
  if (originalFunctionPtr == NULL)
    return kErrorAssert;
  
  int page          = getpagesize();
  uint32_t address  = (uint32_t)originalFunctionPtr;
  uint32_t base     = address / page * page;
  
  if (page - ((uint32_t)originalFunctionPtr - base) < 8)
    page *= 2;
  
  mach_port_t self = mach_task_self();
  
  error = vm_protect(self, base, page, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
  
  if (error)
    {
#ifdef DEBUG
      NSLog(@"[ARMHooker][err] vm_protect rwc returned %d\n", error);
#endif
      return kErrorProt;
    }
  
  uint32_t *code = (uint32_t *)originalFunctionPtr;
  const size_t used(2);
  
  uint32_t backup[used] = {code[0], code[1]};
  
  code[0] = A$ldr_rd_$rn_im$(A$pc, A$pc, 4 - 8);
  code[1] = (uint32_t)newFunctionAddress;
  
  __clear_cache((char *)code, (char *)(code + used));
  
  error = vm_protect(self, base, page, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
  
  if (error)
    {
#ifdef DEBUG
      NSLog(@"[ARMHooker][err] vm_protect x returned %d\n", error);
#endif
    }
  
#ifdef DEBUG
  NSLog(@"[ARMHooker] Function hooked!");
#endif
  
  return kAHSuccess;
}

int _AHOverride_THUMB(char        *originalFunctionPtr,
                      const void  *newFunctionAddress,
                      void        **reentryIsland)
{
  kern_return_t error;
  
  if (originalFunctionPtr == NULL)
    return kErrorAssert;
  
  int page = getpagesize();
  uint32_t address  = (uint32_t)originalFunctionPtr;
  uint32_t base     = address / page * page;
  
  // XXX: this 12 needs to account for a trailing 32-bit instruction
  if ((page - (uint32_t)originalFunctionPtr - base) < 12)
    page *= 2;
  
  mach_port_t self = mach_task_self();
  
  error = vm_protect(self, base, page, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);

  if (error)
    {
#ifdef DEBUG
      NSLog(@"[ARMHooker][err] vm_protect rwc returned %d\n", error);
#endif

      return kErrorProt;
    }
  
  //
  // XXX: First thing, we need to know if we are able to hook the specific
  // function prologue
  //
  
  unsigned used(6);
  
  unsigned align((address & 0x2) == 0 ? 0 : 1);
  used += align;
  
  uint16_t *_thumbCodePtr = (uint16_t *)originalFunctionPtr;
  //uint16_t backup[used];
  
  // XXX: antani
  uint32_t *arm = (uint32_t *)(_thumbCodePtr + 2 + align);
  
  if (align != 0)
    _thumbCodePtr[0] = T$nop;
  
  _thumbCodePtr[align + 0] = T$bx(A$pc);
  _thumbCodePtr[align + 1] = T$nop;
  
  arm[0] = A$ldr_rd_$rn_im$(A$pc, A$pc, 4 - 8);
  arm[1] = (uint32_t)newFunctionAddress;
  
  __clear_cache((char *)_thumbCodePtr, (char *)(_thumbCodePtr + used));
  
  error = vm_protect(self, base, page, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);

  if (error)
    {
#ifdef DEBUG
      NSLog(@"[ARMHooker][err] vm_protect x returned %d\n", error);
#endif
    }
    
#ifdef DEBUG
  NSLog(@"[ARMHooker] Function hooked!");
#endif

  return kAHSuccess;
}

#pragma mark	-
#pragma mark	Public Functions

int AHOverrideFunction(char         *originalSymbolName,
                       const char   *originalLibraryNameHint,
                       const void   *newFunctionAddress,
                       void         **reentryIsland)
{
  char *originalFunctionPtr = NULL;
  
#ifdef DEBUG
  NSLog(@"[ARMHooker] Hooking %s", originalSymbolName);
#endif
  
  if (originalLibraryNameHint)
    {
#ifdef DEBUG
      NSLog(@"[ARMHooker] TODO: LibraryNameHint");
#endif
    }
  else
    {
      originalFunctionPtr = (char *)dlsym(RTLD_DEFAULT, originalSymbolName);
    }
  
  if (originalFunctionPtr != NULL)
    {
      if (((uint32_t)originalFunctionPtr & 0x1) == 0)
        {
#ifdef DEBUG
          NSLog(@"[ARMHooker] ARM Function found: 0x%08x", originalFunctionPtr);
#endif

          return _AHOverride_ARM(originalFunctionPtr,
                                 newFunctionAddress,
                                 reentryIsland);
        }
      else
        {
#ifdef DEBUG
          NSLog(@"[ARMHooker] THUMB Function found: 0x%08x", originalFunctionPtr);
#endif
          
          // 1's complement on functionPtr
          return _AHOverride_THUMB((char *)((uint32_t)originalFunctionPtr & ~0x1),
                                   newFunctionAddress,
                                   reentryIsland);
        }
    }
  else
    {
#ifdef DEBUG
      NSLog(@"[ARMHooker][err] Function %s not found", originalSymbolName);
#endif
    
      return kErrorSymbolNotFound;
    }
}

int AHOverrideFunctionPtr(void        *originalFunctionAddress,
                          const void  *newFunctionAddress,
                          void        **reentryIsland)
{
#ifdef DEBUG
  NSLog(@"[ARMHooker] TODO: AHOverrideFunctionPtr");
#endif

  return kErrorGeneric;
}