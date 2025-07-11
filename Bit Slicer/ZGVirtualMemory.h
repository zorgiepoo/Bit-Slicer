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
 */

/**
 * @file ZGVirtualMemory.h
 * @brief Virtual Memory Interface for Bit Slicer
 *
 * This header provides a C interface for virtual memory operations in macOS,
 * wrapping Mach kernel functions for memory manipulation. It allows for reading,
 * writing, allocating, and deallocating memory in other processes, as well as
 * querying and modifying memory protection.
 *
 * Memory Model Overview:
 * ----------------------
 * 
 * Virtual memory in macOS is organized as follows:
 * 
 * +----------------+----------------+----------------+----------------+
 * |    Process A   |    Process B   |    Process C   |      ...      |
 * | Virtual Memory | Virtual Memory | Virtual Memory |               |
 * +----------------+----------------+----------------+----------------+
 *         |                |                |
 *         v                v                v
 * +----------------------------------------------------------+
 * |                   Physical Memory                        |
 * +----------------------------------------------------------+
 *
 * Each process has its own virtual memory space, which is mapped to physical
 * memory by the kernel. The functions in this file allow for cross-process
 * memory operations.
 *
 * Memory Debugging Example:
 * -----------------------
 * The following diagram shows how to use these functions for memory debugging:
 *
 * 1. Attach to a process:
 * ```
 * ZGMemoryMap task;
 * if (ZGTaskForPID(1234, &task)) {
 *     // Process attached successfully
 * }
 * ```
 *
 * 2. Read memory from the process:
 * ```
 * ZGMemoryAddress address = 0x10000;
 * ZGMemorySize size = 100;
 * void *data;
 * if (ZGReadBytes(task, address, &data, &size)) {
 *     // Use data...
 *     ZGFreeBytes(data, size);
 * }
 * ```
 *
 * 3. Write memory to the process:
 * ```
 * int value = 42;
 * if (ZGWriteBytesIgnoringProtection(task, address, &value, sizeof(value))) {
 *     // Memory written successfully
 * }
 * ```
 *
 * 4. Memory debugging process diagram:
 * ```
 * +----------------+        +----------------+        +----------------+
 * |  Your Process  |        |  Target Process|        |  Your Process  |
 * |                |        |                |        |                |
 * | 1. ZGTaskForPID| -----> | Process        | -----> | 2. ZGReadBytes |
 * |                |        | Memory         |        |                |
 * +----------------+        +----------------+        +----------------+
 *         |                                                   |
 *         v                                                   v
 * +----------------+                                  +----------------+
 * |  Your Process  |                                  |  Your Process  |
 * |                |                                  |                |
 * | 3. Process Data| <--------------------------------| 4. Display Data|
 * |                |                                  |                |
 * +----------------+                                  +----------------+
 *         |
 *         v
 * +----------------+        +----------------+
 * |  Your Process  |        |  Target Process|
 * |                |        |                |
 * | 5. ZGWriteBytes| -----> | 6. Modified    |
 * |                |        |    Memory      |
 * +----------------+        +----------------+
 * ```
 *
 * Code Injection Example:
 * ---------------------
 * The following diagram shows how to use these functions for code injection:
 *
 * 1. Allocate memory in the target process:
 * ```
 * ZGMemoryAddress address = 0;
 * ZGMemorySize size = 1024;
 * if (ZGAllocateMemory(task, &address, size)) {
 *     // Memory allocated successfully
 * }
 * ```
 *
 * 2. Write code to the allocated memory:
 * ```
 * // Suspend the process while modifying its memory
 * ZGSuspendTask(task);
 *
 * // Write the code to the allocated memory
 * if (ZGWriteBytesIgnoringProtection(task, address, codeBytes, codeSize)) {
 *     // Code written successfully
 * }
 *
 * // Make the memory executable
 * ZGProtect(task, address, codeSize, VM_PROT_READ | VM_PROT_EXECUTE);
 *
 * // Resume the process
 * ZGResumeTask(task);
 * ```
 *
 * 3. Code injection process diagram:
 * ```
 * Original Program Flow:
 * +----------------+        +----------------+        +----------------+
 * | Instruction 1  | -----> | Instruction 2  | -----> | Instruction 3  |
 * +----------------+        +----------------+        +----------------+
 *
 * After Code Injection:
 * +----------------+        +----------------+        +----------------+
 * | Instruction 1  | -----> |    Jump to     |        | Instruction 3  |
 * +----------------+        | Injected Code  |        +----------------+
 *                           +----------------+               ^
 *                                   |                        |
 *                                   v                        |
 * +----------------+        +----------------+        +----------------+
 * | Injected Code  | -----> | Your Custom    | -----> |    Jump to     |
 * | Entry Point    |        | Instructions   |        | Instruction 3  |
 * +----------------+        +----------------+        +----------------+
 * ```
 */

#ifndef ZG_VIRTUAL_MEMORY_H
#define ZG_VIRTUAL_MEMORY_H

#ifdef __cplusplus
extern "C" {
#endif

#include "ZGMemoryTypes.h"
#include <mach/vm_region.h>
#include <stdbool.h>

/**
 * @brief Get a task port for a process ID
 *
 * @param processID The process ID to get a task port for
 * @param processTask Pointer to store the resulting task port
 * @return true if successful, false otherwise
 *
 * @note The caller is responsible for deallocating the port using ZGDeallocatePort()
 *
 * Example:
 * ```
 * ZGMemoryMap task;
 * if (ZGTaskForPID(1234, &task)) {
 *     // Use task...
 *     ZGDeallocatePort(task);
 * }
 * ```
 */
bool ZGTaskForPID(int processID, ZGMemoryMap *processTask);

/**
 * @brief Deallocate a task port
 *
 * @param processTask The task port to deallocate
 * @return true if successful, false otherwise
 *
 * @note This should be called when finished with a task port obtained from ZGTaskForPID()
 */
bool ZGDeallocatePort(ZGMemoryMap processTask);

/**
 * @brief Modify the reference count of a port's send right
 *
 * @param processTask The task port to modify
 * @param delta The change to apply to the reference count
 * @return true if successful, false otherwise
 *
 * @note This is used for managing port references in complex scenarios
 */
bool ZGSetPortSendRightReferenceCountByDelta(ZGMemoryMap processTask, mach_port_delta_t delta);

/**
 * @brief Get the process ID for a task port
 *
 * @param processTask The task port to query
 * @param processID Pointer to store the resulting process ID
 * @return true if successful, false otherwise
 *
 * Example:
 * ```
 * int pid;
 * if (ZGPIDForTask(task, &pid)) {
 *     printf("Process ID: %d\n", pid);
 * }
 * ```
 */
bool ZGPIDForTask(ZGMemoryMap processTask, int *processID);

/**
 * @brief Get the page size for a task
 *
 * @param processTask The task port to query
 * @param pageSize Pointer to store the resulting page size
 * @return true if successful, false otherwise
 *
 * @note Page size is the minimum unit of memory allocation in virtual memory
 *
 * Example:
 * ```
 * ZGMemorySize pageSize;
 * if (ZGPageSize(task, &pageSize)) {
 *     printf("Page size: %llu bytes\n", pageSize);
 * }
 * ```
 */
bool ZGPageSize(ZGMemoryMap processTask, ZGMemorySize *pageSize);

/**
 * @brief Allocate memory in a process
 *
 * @param processTask The task port of the process
 * @param address Pointer to store the resulting address (input value is ignored)
 * @param size The size of memory to allocate in bytes
 * @return true if successful, false otherwise
 *
 * Example:
 * ```
 * ZGMemoryAddress address = 0;
 * ZGMemorySize size = 4096;
 * if (ZGAllocateMemory(task, &address, size)) {
 *     printf("Allocated %llu bytes at address 0x%llx\n", size, address);
 * }
 * ```
 *
 * Memory Allocation Diagram:
 * --------------------------
 * Before:
 * +---------------------+
 * | Process Memory Map  |
 * +---------------------+
 *
 * After ZGAllocateMemory(task, &address, size):
 * +---------------------+
 * | Process Memory Map  |
 * +---------------------+
 * |       address       | <- Newly allocated region
 * |         ...         |
 * | address + size - 1  |
 * +---------------------+
 */
bool ZGAllocateMemory(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize size);

/**
 * @brief Deallocate memory in a process
 *
 * @param processTask The task port of the process
 * @param address The starting address of the memory to deallocate
 * @param size The size of memory to deallocate in bytes
 * @return true if successful, false otherwise
 *
 * @note This should be called to free memory allocated with ZGAllocateMemory()
 */
bool ZGDeallocateMemory(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size);

/**
 * @brief Read bytes from a process's memory
 *
 * @param processTask The task port of the process
 * @param address The address to read from
 * @param bytes Pointer to store the resulting bytes
 * @param size On input, the number of bytes to read; on output, the number of bytes actually read
 * @return true if successful, false otherwise
 *
 * @note This function allocates memory that must be freed with ZGFreeBytes()
 *
 * Example:
 * ```
 * void *data;
 * ZGMemorySize size = 100;
 * if (ZGReadBytes(task, 0x10000, &data, &size)) {
 *     // Use data...
 *     ZGFreeBytes(data, size);
 * }
 * ```
 *
 * Memory Reading Diagram:
 * ----------------------
 * Process Memory:
 * +---------------------+
 * |       0x10000       | <- Starting address
 * |         ...         |
 * |     0x10000+size    |
 * +---------------------+
 *         |
 *         v
 * +---------------------+
 * |        data         | <- Allocated buffer in our process
 * +---------------------+
 */
bool ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size);

/**
 * @brief Free memory allocated by ZGReadBytes()
 *
 * @param bytes The memory to free
 * @param size The size of the memory
 * @return true if successful, false otherwise
 *
 * @note This should be called to free memory returned by ZGReadBytes()
 */
bool ZGFreeBytes(void *bytes, ZGMemorySize size);

/**
 * @brief Write bytes to a process's memory
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @return true if successful, false otherwise
 *
 * @note This requires the memory to be writable
 *
 * Example:
 * ```
 * int value = 42;
 * if (ZGWriteBytes(task, 0x10000, &value, sizeof(value))) {
 *     printf("Successfully wrote value\n");
 * }
 * ```
 */
bool ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);

/**
 * @brief Write bytes to a process's memory, temporarily changing protection if needed
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @return true if successful, false otherwise
 *
 * @note This will temporarily make the memory writable if it isn't already
 *
 * Protection Overwriting Diagram:
 * ------------------------------
 * Before:
 * +---------------------+
 * | Address: 0x10000    |
 * | Protection: r-x     | <- Read-only, executable
 * +---------------------+
 *
 * During ZGWriteBytesOverwritingProtection:
 * +---------------------+
 * | Address: 0x10000    |
 * | Protection: rw-     | <- Temporarily made writable
 * +---------------------+
 *
 * After:
 * +---------------------+
 * | Address: 0x10000    |
 * | Protection: r-x     | <- Original protection restored
 * +---------------------+
 */
bool ZGWriteBytesOverwritingProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);

/**
 * @brief Write bytes to a process's memory, ignoring protection
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @return true if successful, false otherwise
 *
 * @note This will temporarily change protection and restore it afterward
 */
bool ZGWriteBytesIgnoringProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);

/**
 * @brief Get basic information about a memory region
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param regionInfo Pointer to store the resulting region information
 * @return true if successful, false otherwise
 *
 * Example:
 * ```
 * ZGMemoryAddress address = 0x10000;
 * ZGMemorySize size;
 * ZGMemoryBasicInfo info;
 * if (ZGRegionInfo(task, &address, &size, &info)) {
 *     printf("Region: 0x%llx - 0x%llx, protection: %d\n", 
 *            address, address + size, info.protection);
 * }
 * ```
 *
 * Memory Region Diagram:
 * ---------------------
 * +---------------------+
 * |      Region 1       | <- address points here
 * |        ...          |
 * +---------------------+
 * |      Region 2       |
 * |        ...          |
 * +---------------------+
 * |        ...          |
 */
bool ZGRegionInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryBasicInfo *regionInfo);

/**
 * @brief Get extended information about a memory region
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param regionInfo Pointer to store the resulting extended region information
 * @return true if successful, false otherwise
 */
bool ZGRegionExtendedInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryExtendedInfo *regionInfo);

/**
 * @brief Get submap information about a memory region
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param regionInfo Pointer to store the resulting submap region information
 * @return true if successful, false otherwise
 *
 * @note This recursively traverses submaps until it finds a non-submap region
 */
bool ZGRegionSubmapInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemorySubmapInfo *regionInfo);

/**
 * @brief Get the memory protection of a region
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param memoryProtection Pointer to store the resulting memory protection
 * @return true if successful, false otherwise
 *
 * Protection Flags:
 * ----------------
 * VM_PROT_NONE    = 0x00 (---)
 * VM_PROT_READ    = 0x01 (r--)
 * VM_PROT_WRITE   = 0x02 (-w-)
 * VM_PROT_EXECUTE = 0x04 (--x)
 *
 * Common combinations:
 * VM_PROT_READ | VM_PROT_WRITE            = 0x03 (rw-)
 * VM_PROT_READ | VM_PROT_EXECUTE          = 0x05 (r-x)
 * VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE = 0x07 (rwx)
 */
bool ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection);

/**
 * @brief Change the memory protection of a region
 *
 * @param processTask The task port of the process
 * @param address The starting address of the region
 * @param size The size of the region
 * @param protection The new protection to apply
 * @return true if successful, false otherwise
 *
 * Example:
 * ```
 * // Make memory readable and writable
 * if (ZGProtect(task, 0x10000, 4096, VM_PROT_READ | VM_PROT_WRITE)) {
 *     printf("Changed protection successfully\n");
 * }
 * ```
 */
bool ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection);

/**
 * @brief Get the suspend count of a task
 *
 * @param processTask The task port of the process
 * @param suspendCount Pointer to store the resulting suspend count
 * @return true if successful, false otherwise
 *
 * @note A suspend count > 0 means the task is suspended
 */
bool ZGSuspendCount(ZGMemoryMap processTask, integer_t *suspendCount);

/**
 * @brief Suspend a task
 *
 * @param processTask The task port of the process to suspend
 * @return true if successful, false otherwise
 *
 * @note This increments the task's suspend count
 */
bool ZGSuspendTask(ZGMemoryMap processTask);

/**
 * @brief Resume a task
 *
 * @param processTask The task port of the process to resume
 * @return true if successful, false otherwise
 *
 * @note This decrements the task's suspend count
 */
bool ZGResumeTask(ZGMemoryMap processTask);

#ifdef __cplusplus
}
#endif

#endif
