# Bit Slicer
![Bit Slicer icon](https://dl.dropbox.com/u/10108199/bit_slicer/web_icon.png)

## Introduction
Bit Slicer is an open-source universal game trainer for OS X, written using Cocoa and Mach kernel APIs.

It allows you to cheat in video games by searching and modifying values such as your score, lives, ammunition, and much more.

*Disclaimer: Use this software at your own risk. I'm not responsible for any damage that could occur.*

## Features
* Memory Scanner
	* Search & narrow down values of several types: integers, floating-points, strings, byte arrays, and pointers
	* Add, delete, and modify variables with ease
	* Freeze variable's values
	* Store a process' entire virtual memory space and search for values based on incremental changes
	* Manipulate pointers by dereferencing variable addresses
* Memory Viewer
	* View memory live in a hex editor style window
	* Dump memory to files on disk for manual inspection
	* Modify memory protection attributes
* Debugger
	* View live disassembly of instructions
	* Modify instruction's bytes directly, or by assembling instructions (including nopping)
	* Set breakpoints, resume from them when they're hit, view backtraces, manipulate thread registers, and step into/out/over instructions
	* Watch for what instructions access a variable in a document
* Save slice documents so that you can send cheats to your friends
* Pause and un-pause current process
* Undo & Redo many kinds of changes, including searches
* Evaluate mathematical expressions automatically (eg: in a flash game, search for 58 * 8)
* Run as a normal user, not as the superuser (root)!
* Enjoy OS level features such as auto-saving, document versioning, window restoration, notification center, etc.

*Note: Many of the features listed are only available in 1.6, which hasn't been publicly released yet, and is still in its alpha stages.*


## System Requirements
* [Bit Slicer 1.6 Alphas](https://bitbucket.org/zorgiepoo/bit-slicer/downloads/) or later: OS X 10.6.8 or newer on a 64-bit Mac
* [Bit Slicer 1.5.2](https://bitbucket.org/zorgiepoo/bit-slicer/downloads/Bit%20Slicer%201.5.2.zip) and older: Same as above, except also runs on 32-bit Macs.

## Support & Feedback
* Check the [wiki](https://bitbucket.org/zorgiepoo/bit-slicer/wiki/)
* Visit the [forums](http://portingteam.com/forum/157-bit-slicer/)
* Send an email to zorgiepoo (at) gmail (dot) com

## Source Code
### Licensing
Bit Slicer is licensed under the 3-clause BSD license. Versions prior to 1.6, however, are licensed under the GPL version 3 license.

### Code Signing
In order to build Bit Slicer, you will need to code-sign it. By code-signing, you can gain privileges to *task_for_pid()* without adding procmod group permissions or becoming the superuser.

Unfortunately, unless you have purchased a Developer ID from Apple, this could prove to be challenging. Theoretically, it should be possible to sign the code using a self-signed certificate. However, I have not been able to get this to work, which is a shame because I really want to set one up for debug builds.

If you are interested in setting up a self-signed certificate, you may want to check out this [lldb document on code-signing](https://llvm.org/svn/llvm-project/lldb/trunk/docs/code-signing.txt). If you are able to figure it out, I'd appreciate if you let me know how to do it.

Versions prior to 1.6 are not code-signed, and consequently, the user is required to authorize the application to run as the superuser.
