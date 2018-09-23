# Bit Slicer
![Bit Slicer icon](https://zgcoder.net/software/bitslicer/images/web_icon.png)

[Download Bit Slicer](https://zgcoder.net/software/bitslicer/dist/stable/Bit%20Slicer.dmg)

## Introduction
Bit Slicer is a universal game trainer for macOS, written using Cocoa and Mach kernel APIs.

It allows you to cheat in video games by searching and modifying values such as your score, lives, ammunition, and much more.

## Features
* Memory Scanner
	* Search & narrow down values of several types: integers, floating-points, strings, byte arrays, and pointers
	* Add, delete, and modify variables with ease
	* Freeze variable's values
	* Store a process' entire virtual memory space and search for values based on incremental changes
	* Manipulate pointers by dereferencing variable addresses
* Memory Inspection
	* View and edit memory live in a hex editor style window
	* Dump memory to files on disk for manual inspection
	* Modify memory protection attributes
* Debugger
	* View live disassembly of instructions
	* Modify instruction's bytes directly, or by assembling instructions (including nopping)
	* Set breakpoints, resume from them when they're hit, view backtraces, manipulate thread registers, and step into/out/over instructions
	* Inject x86 code on the fly
	* Watch for what instructions access a variable in a document
* Save slice documents so that you can send cheats to your friends
* Write Scripts to automate tasks that involve using virtual memory and debugger methods
* Pause and un-pause current process
* Undo & Redo many kinds of changes, including searches
* Evaluate mathematical expressions automatically (eg: in a flash game, search for 58 * 8)
* Run as a normal user, not as the superuser (root)!
* Enjoy OS level features such as auto-saving, document versioning, window restoration, notification center, app nap, dark mode, etc.

## System Requirements
* **Current Release**: macOS 10.10 or newer
* [1.7.8](https://github.com/zorgiepoo/Bit-Slicer/releases/download/1.7.8/Bit.Slicer.dmg): macOS 10.8
* [1.6.2](https://github.com/zorgiepoo/Bit-Slicer/releases/download/1.6.2/Bit_Slicer_1.6.2.zip): macOS 10.6.8, a 64-bit intel Mac
* [1.5.2](https://github.com/zorgiepoo/Bit-Slicer/releases/download/1.5.2/Bit_Slicer_1.5.2.zip): macOS 10.6.8

## Support
* Check the [wiki](https://github.com/zorgiepoo/Bit-Slicer/wiki/) for how to use Bit Slicer
* Visit the [forums](http://portingteam.com/forum/157-bit-slicer/) for discussion and current development
* Visit the [chat room](http://webchat.freenode.net/?channels=bitslicer) for support or development (#bitslicer on irc.freenode.net). Note availability for support is not 24/7.

## Contributing
* Improve the current [wiki](https://github.com/zorgiepoo/Bit-Slicer/wiki/) by fixing errors or by adding content
* Report bugs or request features on the [issue tracker](https://github.com/zorgiepoo/Bit-Slicer/issues)
* Help [translate](https://github.com/zorgiepoo/Bit-Slicer/wiki/Localization) Bit Slicer into a different language
* Help [design improved artwork](https://github.com/zorgiepoo/Bit-Slicer/issues/18)
* Learn how to build and contribute to the [source code](https://github.com/zorgiepoo/Bit-Slicer/wiki/Source-Code)

Please read this project's [Code Of Conduct](https://github.com/zorgiepoo/Bit-Slicer/blob/master/CODE_OF_CONDUCT.md) residing in the root level of the project.

**Update**: This project may need some help! I cannot guarantee my activeness in reviewing / pulling in future changes, as well as pushing out new releases.
