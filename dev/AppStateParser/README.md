# AppStateParser

AppStateParser package performs basic parsing of the output of `String(describing:)` for the purpose of pretty-printing.

If the input is copied from a feedback, it might have to be unquoted by passing `-u` or `--unquote` flag.

You can disable syntax highlighting by passing `-nohl` flag.

```
$ swift run parser --help
USAGE: cli [-nohl] [--unquote] [--print-parse-tree] [-file <file>] [<string>]

ARGUMENTS:
  <string>                AppState string to parse. 

OPTIONS:
  -nohl                   Disable syntax highlighting. 
  -u, --unquote           Unquotes the input. 
  --print-parse-tree      Prints parse tree. 
  -f, -file <file>        Input file path. 
  -h, --help              Show help information.
```


## Example usage

```
swift run parser -nohl "A(values: [\"a\", \"b\", \"c\"])"

swift run parser "A(pendingPsiCashRefresh: Pending<Result<Unit, Error>>.completed)"
```

# Some notes

- Check value of `String(describing:)` when changes are made to the values that are included in the feedbacks, like [AppState](https://github.com/Psiphon-Inc/psiphon-ios-vpn/blob/master/Psiphon/AppState.swift).

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
