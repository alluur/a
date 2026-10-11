" Vim syntax file
" Language: A (https://aytict.fi)
if exists("b:current_syntax") | finish | endif


syn keyword aConditional if else switch case default
syn keyword aRepeat      while do for
syn keyword aStatement   break continue return
syn keyword aStructure   struct class enum
syn keyword aStorage     const
syn keyword aAccess      public private
syn keyword aModule      module import
syn keyword aType        int long char byte bool void func
syn keyword aOperatorKw  new sizeof
syn keyword aSelf        this
syn keyword aBoolean     true false
syn keyword aNull        null

" declared type names: class Foo / struct Foo / enum Foo
syn match aTypeName "\<\(class\|struct\|enum\)\s\+\zs\h\w*"
" module qualified names: geometry.area
syn match aModuleName "\<\h\w*\ze\.\h\w*\s*("
" function definitions and calls
syn match aFunction "\<\h\w*\ze\s*("
" built-in runtime functions
syn match aBuiltin "\<__\(write\|read\|exit\|open\|close\|syscall\|cmdline\|winapi\|winapix\)\>"
syn keyword aBuiltin setjmp longjmp
" standard library
syn keyword aStdlib print println printInt printlnInt printChar printBool printHex eprint eprintln
syn keyword aStdlib readChar readLine atoi strlen streq strcmp strcpy strcat strdup memcpy memset
syn keyword aStdlib indexOf startsWith intToStr isDigit isAlpha isUpper isLower isSpace toUpper toLower
syn keyword aStdlib abs min max srand rand exit alloc fileOpen fileRead fileWrite fileClose readFile writeFile
syn keyword aStdlib input askInt confirm readAll parseInt format printf printRepeat printColor clearScreen cursorTo isTerminal ansiInit
syn keyword aStdlib argIndex hasArg argValue millis sleepMs getEnv fileExists fileDelete makeDir endsWith find contains substr trim strUpper strLower streqi hexToStr
syn keyword aStdConst ANSI_RESET ANSI_BOLD ANSI_RED ANSI_GREEN ANSI_YELLOW ANSI_BLUE ANSI_MAGENTA ANSI_CYAN ANSI_GRAY
syn keyword aStdConst FILE_READ FILE_WRITE FILE_APPEND
" the C library (import clib;)
syn keyword aStdlib malloc calloc realloc free qsort bsearch atexit strtol strtoul strtod atof getenv setenv system fopen fclose fgets fputs fread fwrite fseek ftell fprintf sprintf snprintf sscanf fscanf scanf fflush popen pclose
syn keyword aStdlib strchr strrchr strstr strncpy strncmp strtok memmove memcmp memchr isalpha isdigit isalnum isspace toupper tolower time localtime gmtime mktime strftime stat opendir readdir signal
syn keyword aStdlib sqrt sin cos tan atan2 exp log log10 pow floor ceil round fabs fmod dadd dsub dmul ddiv itod dtoi dlit dtostr printfd sprintfd
syn keyword aStdConst stdin stdout stderr EOF NULL errno EXIT_SUCCESS EXIT_FAILURE INT_MAX M_PI M_E INFINITY NAN

" literals
syn match  aNumber  "\<\d[0-9_]*\>"
syn match  aNumber  "\<0[xX][0-9a-fA-F_]\+\>"
syn match  aNumber  "\<0[bB][01_]\+\>"
syn match  aEscape  contained "\\\([ntre0\\\"']\|x\x\x\)"
syn match  aBadEsc  contained "\\[^ntre0\\\"'x]"
syn region aString  start=+"+ skip=+\\\\\|\\"+ end=+"+ oneline contains=aEscape,aBadEsc,@Spell
syn match  aChar    "'\([^\\']\|\\.\|\\x\x\x\)'" contains=aEscape

" operators
syn match aOperator "[-+*/%&|^~!<>=?:]\|<<\|>>\|->\|++\|--"
syn match aDelim    "[(){}\[\];,.]"

" comments last: they must win over operators and strings
syn keyword aTodo        contained TODO FIXME XXX NOTE
syn match   aLineComment "//.*" contains=aTodo,@Spell
syn region  aBlockComment start="/\*" end="\*/" contains=aTodo,@Spell

syn sync fromstart

hi def link aTodo         Todo
hi def link aLineComment  Comment
hi def link aBlockComment Comment
hi def link aConditional  Conditional
hi def link aRepeat       Repeat
hi def link aStatement    Statement
hi def link aStructure    Structure
hi def link aStorage      StorageClass
hi def link aAccess       aAccessGroup
hi def link aModule       Include
hi def link aType         Type
hi def link aTypeName     Typedef
hi def link aOperatorKw   Operator
hi def link aSelf         Special
hi def link aBoolean      Boolean
hi def link aNull         Constant
hi def link aFunction     Function
hi def link aModuleName   Namespace
hi def link aBuiltin      PreProc
hi def link aStdlib       Identifier
hi def link aStdConst     Constant
hi def link aNumber       Number
hi def link aString       String
hi def link aChar         Character
hi def link aEscape       SpecialChar
hi def link aBadEsc       Error
hi def link aOperator     Operator
hi def link aDelim        Delimiter
hi def link aAccessGroup  Keyword

let b:current_syntax = "a"
