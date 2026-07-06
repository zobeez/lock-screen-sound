#ifndef MyApp_Bridging_Header_h
#define MyApp_Bridging_Header_h

// Exposes the Darwin notification C API (notify_register_dispatch, etc.) to
// Swift. These live in <notify.h>, which is not part of the Swift Darwin
// overlay, so a bridging header is required to reach them.
#import <notify.h>

#endif /* MyApp_Bridging_Header_h */
