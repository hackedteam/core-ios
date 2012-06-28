/*
 * RCSiOS - ARMHooker
 *  ARM/THUMB Inline hooking
 *
 * 
 * Created on 27/04/2010
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
 
#import <Foundation/Foundation.h>

#ifndef _ARM_Hooker_
#define _ARM_Hooker_

#include <sys/types.h>
#include <mach/error.h>


enum {
  kAHSuccess            = 0,
  kErrorGeneric         = -1,
  kErrorSymbolNotFound  = -2,
  kErrorAssert          = -3,
  kErrorProt            = -4,
};

int AHOverrideFunction(char         *originalSymbolName,
                       const char   *originalLibraryNameHint,
                       const void   *newFunctionAddress,
                       void         **reentryIsland);

int AHOverrideFunctionPtr(void        *originalFunctionAddress,
                          const void  *newFunctionAddress,
                          void        **reentryIsland);

#endif