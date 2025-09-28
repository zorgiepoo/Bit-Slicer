#import <Foundation/Foundation.h>

#define HFASSERT(a) if (0 && ! (a)) abort()

#define HFASSERT_MAIN_THREAD() HFASSERT(NSThread.currentThread.isMainThread)
