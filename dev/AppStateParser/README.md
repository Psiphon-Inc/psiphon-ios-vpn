# AppStateParser

AppStateParser package performs basic parsing of the output of AppState value dump in the feedbacks for the purpose of pretty-printing.

You can disable syntax highlighting by passing `-nohl` flag.

```
$ swift run parser --help
USAGE: cli [-nohl] [--print-parse-tree] [-timezone <timezone>] [-file <file>] [<string>]

ARGUMENTS:
  <string>                AppState string to parse. 

OPTIONS:
  -nohl                   Disable syntax highlighting. 
  --print-parse-tree      Prints parse tree. 
  -t, -timezone <timezone>
                          Formats dates in the given time zone (e.g. "America/Toronto") 
  -f, -file <file>        Input file path. 
  -h, --help              Show help information.
```


## Example usage

```
$ swift run parser -nohl "A(values: [\"a\", \"b\", \"c\"])"

$ swift run parser "{\"AppState\": \"AppState(num: 2, string: \\\"stringValue\\\")\"}"

```

# Some notes

- Check value of AppState that is logged into feedback when changes are made to the struct.

- Prefer to wrap description of Objective-C types in double quotes. Trying to parse description of many Objective-C types adds complexity to the parser.

# Installation

You can also build and install the tool with the following commands (or simply run `install.sh` from this directory):
```
# Build the project under .build/release/
swift build -c release

# Copies it to /usr/local/bin/ under name appStateParser
cp -f .build/release/parser /usr/local/bin/appStateParser

# Test
appStateParser "A((((()), (()),())))"
```
