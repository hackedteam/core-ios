//	cygwin1_supp.h : supplement header file for cygwin1.dll
//	Author: DLL to Lib version 3.00
//	Date: Monday, March 11, 2013
//	Description: The declaration of the cygwin1.dll's entry-point function.
//	Prototype: BOOL WINAPI xxx_DllMain(HINSTANCE hinstance, DWORD fdwReason, LPVOID lpvReserved);
//	Parameters: 
//		hinstance
//		  Handle to current instance of the application. Use AfxGetInstanceHandle()
//		  to get the instance handle if your project has MFC support.
//		fdwReason
//		  Specifies a flag indicating why the entry-point function is being called.
//		lpvReserved 
//		  Specifies further aspects of DLL initialization and cleanup. Should always
//		  be set to NULL;
//	Comment: Please see the help document for detail information about the entry-point 
//		 function
//	Homepage: http://www.binary-soft.com
//	Technical Support: support@binary-soft.com
/////////////////////////////////////////////////////////////////////

#if !defined(D2L_CYGWIN1_SUPP_H__001D05BD_4200_46FC_00AB_799C6AE200F0__INCLUDED_)
#define D2L_CYGWIN1_SUPP_H__001D05BD_4200_46FC_00AB_799C6AE200F0__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#ifdef __cplusplus
extern "C" {
#endif


#include <windows.h>

/* This is cygwin1.dll's entry-point function. You should call it to do necessary
 initialization and finalization. */

BOOL WINAPI CYGWIN1_DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved);


#ifdef __cplusplus
}
#endif

#endif // !defined(D2L_CYGWIN1_SUPP_H__001D05BD_4200_46FC_00AB_799C6AE200F0__INCLUDED_)