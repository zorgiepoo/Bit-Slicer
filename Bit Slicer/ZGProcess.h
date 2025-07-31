/*
 * Copyright (c) 2012 Mayur Pawashe
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * ZGProcess
 * ---------
 * This class represents a process in the system that can be debugged or manipulated.
 * It provides an abstraction over the underlying process details and offers methods
 * for accessing process memory, symbols, and binary information.
 *
 * Key responsibilities:
 * - Maintaining process identification (PID, name, type)
 * - Providing access to process memory
 * - Managing binary information and symbols
 * - Caching process-related data for performance
 *
 * Process Relationships:
 * +------------------------+     +------------------------+     +------------------------+
 * |      ZGProcess         |     |  Memory & Symbols      |     |  Binary Information   |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Represents a process | --> | - Provides memory      | --> | - Manages Mach binary |
 * |   in the system        |     |   access via processTask    |   information          |
 * | - Tracks process state |     | - Creates symbolicator |     | - Caches binary data  |
 * |   (valid, translated)  |     |   for symbol resolution|     |   for performance     |
 * +------------------------+     +------------------------+     +------------------------+
 */

#import <Foundation/Foundation.h>
#import "ZGSymbolicator.h"
#import "ZGMemoryTypes.h"
#import "ZGProcessTypes.h"
#import <sys/sysctl.h>

#define NON_EXISTENT_PID_NUMBER -1

NS_ASSUME_NONNULL_BEGIN

@class ZGMachBinary;

@interface ZGProcess : NSObject

/**
 * Initializes a process with complete information
 *
 * This is the designated initializer that creates a process object with all necessary information.
 *
 * @param processName The user-visible name of the process (can be nil)
 * @param internalName The internal name of the process (bundle identifier or executable name)
 * @param aProcessID The process identifier (PID)
 * @param processType The type of process (architecture)
 * @param translated Whether the process is running under translation (e.g., Rosetta)
 * @return An initialized process object
 */
- (instancetype)initWithName:(nullable NSString *)processName internalName:(NSString *)internalName processID:(pid_t)aProcessID type:(ZGProcessType)processType translated:(BOOL)translated;

/**
 * Initializes a process without a process ID
 *
 * Creates a process object that doesn't represent an actual running process.
 *
 * @param processName The user-visible name of the process (can be nil)
 * @param internalName The internal name of the process (bundle identifier or executable name)
 * @param processType The type of process (architecture)
 * @param translated Whether the process is running under translation (e.g., Rosetta)
 * @return An initialized process object with NON_EXISTENT_PID_NUMBER as the process ID
 */
- (instancetype)initWithName:(nullable NSString *)processName internalName:(NSString *)internalName type:(ZGProcessType)processType translated:(BOOL)translated;

/**
 * Initializes a process by copying another process's properties
 *
 * @param process The process to copy properties from
 * @return An initialized process object with the same properties as the given process
 */
- (instancetype)initWithProcess:(ZGProcess *)process;

/**
 * Initializes a process by copying another process's properties with a different name
 *
 * @param process The process to copy properties from
 * @param name The new name for the process
 * @return An initialized process object with properties from the given process but a different name
 */
- (instancetype)initWithProcess:(ZGProcess *)process name:(nullable NSString *)name;

/**
 * Initializes a process by copying another process's properties with a different process task
 *
 * @param process The process to copy properties from
 * @param processTask The new process task (memory map)
 * @return An initialized process object with properties from the given process but a different process task
 */
- (instancetype)initWithProcess:(ZGProcess *)process processTask:(ZGMemoryMap)processTask;

/** The process identifier (PID) of the process */
@property (nonatomic, readonly) pid_t processID;

/** The memory map used to access the process's memory */
@property (nonatomic, readonly) ZGMemoryMap processTask;

/** Whether the process is valid (has a real PID) */
@property (nonatomic, readonly) BOOL valid;

/** The user-visible name of the process */
@property (nonatomic, readonly) NSString *name;

/** The internal name of the process (bundle identifier or executable name) */
@property (nonatomic, readonly) NSString *internalName;

/** The type of process (architecture) */
@property (nonatomic, readonly) ZGProcessType type;

/** Whether the process is running under translation (e.g., Rosetta) */
@property (nonatomic, readonly) BOOL translated;

/** 
 * Indicates if this represents any sort of actual program
 * This is used to mark placeholder or special process objects
 */
@property (nonatomic) BOOL isDummy;

/** The main Mach binary of the process (lazily loaded) */
@property (nonatomic, readonly, nullable) ZGMachBinary *mainMachBinary;

/** The dynamic linker binary of the process (lazily loaded) */
@property (nonatomic, readonly, nullable) ZGMachBinary *dylinkerBinary;

/** Dictionary used for caching process-related data for performance */
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSMutableDictionary *> *cacheDictionary;

/** 
 * The symbolicator used for resolving symbols in the process
 * This is lazily created when first accessed
 */
@property (nonatomic, readonly, nullable) id <ZGSymbolicator> symbolicator;

/**
 * Compares two process objects for equality
 *
 * Two process objects are considered equal if they have the same process ID.
 *
 * @param process The process to compare with
 * @return YES if the processes have the same process ID, NO otherwise
 */
- (BOOL)isEqual:(id)process;

/**
 * Checks if the process has granted access to its memory
 *
 * @return YES if the process task is valid and accessible, NO otherwise
 */
- (BOOL)hasGrantedAccess;

/**
 * Gets the pointer size for the process based on its architecture
 *
 * @return The size of pointers in the process (4 for 32-bit, 8 for 64-bit)
 */
- (ZGMemorySize)pointerSize;

@end

NS_ASSUME_NONNULL_END
