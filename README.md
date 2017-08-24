# zbs-autocomplete

I was having a hard time finding a lua autocompleter that could type inference and find methods in all of my files in a project.
Developed this zerobranestudio extension to allow more intelligent autocomplete.

## Install

Copy contents of repo into the packages folder of your ZBS install.

## Usage

 * Open a lua folder in ZBS
 * Ensure you have a program entry point defined
 * Every time you want to update your autocomplete, save a file or use the Autocomplete menu
 
## Known Issues

 * Needs some way of configuring package path on a per project basis. It just uses a hardcoded package path atm.
 * Some constructs can cause the parser to infinite loop. This will throw a stackoverflow error.
 * Still very beta, but works enough for me that I can't live without it :)
 
## Features

 * Parses includes
 * Tries its best to follow metatable prototype chain
 * Tries to detect common "class" patterns
 * Tracks return types and table mutations to provide a more accurate autocomplete
 * Combines with existing ZBS defined api's (it actually generates ZBS API definition)
 
 
