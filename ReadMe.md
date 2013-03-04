# Bit Slicer
![Bit Slicer icon](https://dl.dropbox.com/u/10108199/bit_slicer/web_icon.png)

## Introduction
Bit Slicer is an open-source generic game trainer application for OS X, written using Cocoa and Mach kernel APIs.

It allows you to cheat in video games by modifying your score, lives, money, ammunition, and much more.

*Disclaimer: Use at your own risk. I'm not responsible for any damage that could occur.*

## Features
* Memory Scanner
	* Search & narrow down values by integers, floating-points, strings, byte arrays, and pointers
	* Add, delete, and modify variables with ease
	* Freeze variable's values
	* Store a process' entire virtual memory space and comparing how values have changed at a later time
	* Manipulate pointers by variable address dereferencing
* Memory Viewer
	* View live memory in a hex editor style window
	* Dump memory to fileson disk for inspection by hand
	* Modify memory protection attributes
* Debugger
	* View live disassembly of instructions
	* Modify instruction's bytes directly, or instructions themselves via an assembler (including nopping)
	* Set breakpoints, resume from them when they're hit, view backtrace, manipulate thread registers, and step into/out/over instructions
	* Find what instructions write to an address by watching for variable accesses in a document
* Save slice documents so that you can send cheats to your friends
* Pause and un-pause current process
* Undo & Redo many kinds of changes, including searches
* Run as a normal user, not as a superuser (root)!
* Enjoy OS level features such as auto-saving, document versioning, window restoration, notification center, etc.

*Note: Many of the features listed are only available in 1.6, which hasn't been publicly released yet, and is still in its alpha stages.*


## System Requirements
* **Bit Slicer 1.6 or later**: OS X 10.6.8 or newer on a 64-bit processor
* Bit Slicer 1.5.2 and older: Same as above, except also runs on 32-bit processors.

## Support & Feedback
* Visit the [forums](http://portingteam.com/forum/157-bit-slicer/)
* Check [how to use Bit Slicer](http://portingteam.com/topic/4454-faq-information/)
* Send an email to zorgiepoo (at) gmail (dot) com.

## Source Code
### Licensing
Bit Slicer is licensed under the 3-clause BSD license. However, versions prior to 1.6 are licensed under the GPL version 3 license.

### Code Signing
In order to build Bit Slicer, you will need to code-sign it. By code-signing, you can gain privileges to *task_for_pid()* without adding procmod group permissions or becoming a superuser.

Unfortunately, unless you have purchased a Developer ID from Apple, this could prove to be challenging. Theoretically, it should be possible to sign the code using a self-signed certificate. However, I have not been able to get this work, which is a shame because I would really like to set up using a self-signed certificate for debug builds.

If you are interested in setting up a self-signed certificate, you may want to check out this [llvm document on code-signing](https://llvm.org/svn/llvm-project/lldb/trunk/docs/code-signing.txt). If you are able to figure it out, I'd appreciate if you let me know how to do it.

Versions prior to 1.6 are not code-signed, and consequently, the user authorizes the application to run as a superuser.
