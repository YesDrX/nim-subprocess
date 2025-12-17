# subprocess

A cross-platform subprocess management library for Nim that makes redirecting stdin/stdout/stderr easy.

## Features

- 🚀 **Simple API** - Clean, intuitive interface for spawning and managing subprocesses
- 🔄 **Easy I/O Redirection** - Straightforward stdin/stdout/stderr redirection and capture
- 🌍 **Cross-Platform** - Works seamlessly on Windows, Linux, and macOS
- ⚡ **Non-Blocking I/O** - Check for data availability before reading
- ⏱️ **Timeout Support** - Read with configurable timeouts
- 📡 **EOF Detection** - Detect when stdout/stderr reach end-of-file
- 🎯 **Interactive Process Support** - Handle interactive CLI tools like debuggers and REPLs
- 🔧 **Custom Environments** - Set custom environment variables for subprocesses
- 📦 **Byte Frame Protocol Support** - [Read exact byte counts](#byte-frame-protocol-support) for binary protocols

## Installation

```bash
nimble install subprocess
```

Or add to your `.nimble` file:
```nim
requires "subprocess"
```

## Quick Example

```nim
import subprocess
import std/strutils

# Capture standard output
var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("echo", ["Hello from subprocess!"], opts)
let output = process.readAllStdout().strip()
echo output  # "Hello from subprocess!"
process.close()

# Interactive process - write to stdin, read from stdout
var opts2 = SubprocessOptions(useStdin: true, useStdout: true)
let cat = startSubprocess("cat", [], opts2)
discard cat.write("Hello\n")
cat.closeStdin()
let result = cat.readAllStdout().strip()
echo result  # "Hello"
check cat.wait() == 0
cat.close()

# Byte frame protocol - read exact byte counts
# For protocols with format: [4-byte length][payload]
proc readFrame(process: Subprocess): string =
  # Read exactly 4 bytes for the message length
  let lengthBytes = process.readStdout(numBytesToRead = 4)
  if lengthBytes.len != 4:
    return "" # Not enough data
  
  # Convert the 4 bytes to an integer (little-endian)
  var msgLength: int
  copyMem(addr msgLength, lengthBytes[0].unsafeAddr, 4)
  
  # Read exactly msgLength bytes for the payload
  let payload = process.readStdout(numBytesToRead = msgLength)
  if payload.len != msgLength:
    return "" # Incomplete payload
  
  return payload

# Usage with a subprocess that outputs framed data
# var opts3 = SubprocessOptions(useStdout: true)
# let process = startSubprocess("frame_protocol_app", [], opts3)
# 
# while process.isRunning() or not process.isStdoutEof():
#   let frame = readFrame(process)
#   if frame.len > 0:
#     echo "Received frame: ", frame
#   else:
#     # Small delay to prevent busy looping
#     sleep(10)
# 
# process.close()
```

## API Overview

### Types

#### `SubprocessOptions`
Configuration object for spawning subprocesses.

```nim
type SubprocessOptions* = object
    useStdin*: bool              ## Enable writing to subprocess stdin
    useStdout*: bool             ## Enable reading from subprocess stdout
    useStderr*: bool             ## Enable reading from subprocess stderr
    combineStdoutStderr*: bool   ## Combine stderr into stdout
    env*: Table[string, string]  ## Custom environment variables (empty = inherit)
```

#### `Subprocess`
Represents a running subprocess.

### Core Functions

#### `startSubprocess`
Start a new subprocess.

```nim
proc startSubprocess*(
    command: string,
    args: openArray[string],
    options: SubprocessOptions = SubprocessOptions()
): Subprocess
```

**Parameters:**
- `command` - The executable to run
- `args` - Command-line arguments
- `options` - Configuration options

**Returns:** A `Subprocess` object

**Example:**
```nim
var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("ls", ["-la"], opts)
```

### Process Control

#### `wait`
Wait for the process to exit and return its exit code.

```nim
proc wait*(subprocess: Subprocess): int
```

#### `isRunning`
Check if the process is still running.

```nim
proc isRunning*(subprocess: Subprocess): bool
```

#### `terminate`
Terminate the process.

```nim
proc terminate*(subprocess: Subprocess, graceful: bool = false)
```

**Parameters:**
- `graceful` (POSIX only) - If true, sends SIGTERM first, then SIGKILL after a delay

#### `close`
Release resources.

```nim
proc close*(subprocess: Subprocess)
```

### Input/Output

#### `write`
Write data to subprocess stdin.

```nim
proc write*(subprocess: Subprocess, data: string): int
```

**Returns:** Number of bytes written

**Example:**
```nim
discard process.write("input data\n")
```

#### `readStdout`
Read available data from stdout (non-blocking or with timeout).

```nim
proc readStdout*(subprocess: Subprocess, numBytesToRead: int = -1, timeoutMs: int = -1): string
```

**Parameters:**
- `numBytesToRead` - Number of bytes to read. `-1` = read up to 4096 bytes (default behavior)
- `timeoutMs` - Timeout in milliseconds. `-1` = blocking (wait forever), `0` = non-blocking, `>0` = wait up to this many milliseconds

**Returns:** Available data as a string (may be empty)

**Example:**
```nim
# Non-blocking read (default behavior)
let data = process.readStdout()

# Read with 1 second timeout
let data = process.readStdout(timeoutMs = 1000)

# Read exactly 10 bytes
let frame = process.readStdout(numBytesToRead = 10)

# Read exactly 5 bytes with 500ms timeout
let frame = process.readStdout(numBytesToRead = 5, timeoutMs = 500)
```

#### `readStderr`
Read available data from stderr (non-blocking or with timeout).

```nim
proc readStderr*(subprocess: Subprocess, numBytesToRead: int = -1, timeoutMs: int = -1): string
```

**Parameters:**
- `numBytesToRead` - Number of bytes to read. `-1` = read up to 4096 bytes (default behavior)
- `timeoutMs` - Timeout in milliseconds. `-1` = blocking (wait forever), `0` = non-blocking, `>0` = wait up to this many milliseconds

**Returns:** Available data as a string (may be empty)

**Example:**
```nim
# Non-blocking read (default behavior)
let data = process.readStderr()

# Read exactly 10 bytes
let frame = process.readStderr(numBytesToRead = 10)
```

#### `readAllStdout`
Read all remaining stdout data (blocks until process exits).

```nim
proc readAllStdout*(subprocess: Subprocess): string
```

**Example:**
```nim
let process = startSubprocess("echo", ["test"], opts)
let output = process.readAllStdout()
process.close()
```

#### `readAllStderr`
Read all remaining stderr data (blocks until process exits).

```nim
proc readAllStderr*(subprocess: Subprocess): string
```

#### `hasDataStdout`
Check if stdout has data available to read.

```nim
proc hasDataStdout*(subprocess: Subprocess): bool
```

**Example:**
```nim
if process.hasDataStdout():
    let data = process.readStdout()
```

#### `hasDataStderr`
Check if stderr has data available to read.

```nim
proc hasDataStderr*(subprocess: Subprocess): bool
```

#### `closeStdin`
Close the stdin pipe to signal EOF to the subprocess.

```nim
proc closeStdin*(subprocess: Subprocess)
```

**Example:**
```nim
# Useful for programs that read until EOF
let cat = startSubprocess("cat", [], opts)
discard cat.write("data\n")
cat.closeStdin()  # Signal EOF
let result = cat.readAllStdout()
```

#### `isStdoutEof`
Check if stdout has reached end-of-file (EOF).

```nim
proc isStdoutEof*(subprocess: Subprocess): bool
```

**Returns:** `true` if stdout has reached EOF, `false` otherwise

**Example:**
```nim
while not process.isStdoutEof():
    let data = process.readStdout(timeoutMs = 100)
    if data.len > 0:
        echo data
```

#### `isStderrEof`
Check if stderr has reached end-of-file (EOF).

```nim
proc isStderrEof*(subprocess: Subprocess): bool
```

**Returns:** `true` if stderr has reached EOF, `false` otherwise

## Usage Examples

### Capture Output

```nim
import subprocess

var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("echo", ["hello world"], opts)
let output = process.readAllStdout()
echo output  # "hello world\n"
check process.wait() == 0
process.close()
```

### Capture Both Stdout and Stderr

``nim

import subprocess

# Separate streams
var opts = SubprocessOptions(useStdout: true, useStderr: true)
let process = startSubprocess("python3", ["-c", "import sys; print('out'); sys.stderr.write('err')"], opts)

check process.wait() == 0
let stdout = process.readStdout()
let stderr = process.readStderr()
process.close()

# Combined streams
var opts2 = SubprocessOptions(useStdout: true, combineStdoutStderr: true)
let process2 = startSubprocess("python3", ["-c", "import sys; print('out'); sys.stderr.write('err')"], opts2)
let combined = process2.readAllStdout()
process2.close()

```

### Interactive Process

```nim

import subprocess

var opts = SubprocessOptions(useStdin: true, useStdout: true)
let process = startSubprocess("cat", [], opts)

discard process.write("line 1\n")
discard process.write("line 2\n")
process.closeStdin()

let output = process.readAllStdout()
echo output  # "line 1\nline 2\n"
check process.wait() == 0
process.close()

```

### Custom Environment Variables

```nim
import subprocess
import std/tables

var env = initTable[string, string]()
env["MY_VAR"] = "custom_value"

var opts = SubprocessOptions(useStdout: true, env: env)
let process = startSubprocess("sh", ["-c", "echo $MY_VAR"], opts)
let output = process.readAllStdout()
echo output.strip()  # "custom_value"
process.close()
```

### Non-Blocking I/O

```nim
import subprocess

var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("some_command", [], opts)

while process.isRunning():
    if process.hasDataStdout():
        let data = process.readStdout()
        echo "Got data: ", data
    sleep(100)

# Capture any remaining output
let remaining = process.readStdout()
check process.wait() == 0
process.close()
```

### Read with Timeout

```nim
import subprocess

var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("slow_command", [], opts)

# Wait up to 5 seconds for output
let output = process.readStdout(timeoutMs = 5000)
if output == "":
    echo "No output received within timeout"

process.close()
```

### EOF Detection

```nim
import subprocess

var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("cat", ["file.txt"], opts)

# Read until EOF is reached
var allOutput = ""
while not process.isStdoutEof():
    let chunk = process.readStdout(timeoutMs = 100)
    if chunk.len > 0:
        allOutput.add(chunk)

echo "Process finished writing. Total output: ", allOutput.len, " bytes"
check process.wait() == 0
process.close()
```

### Interactive Debugger (GDB)

See [tests/example_gdb_interactive.nim](tests/example_gdb_interactive.nim) for a complete example of running GDB interactively.

### Byte Frame Protocol Support

The library now supports reading exact byte counts, making it easier to implement byte frame protocols. This is useful when dealing with binary protocols that encode message length information.

```nim
import subprocess

# Example for a protocol with format: [4-byte length][payload]
proc readFrame(process: Subprocess): string =
  # Read exactly 4 bytes for the message length
  let lengthBytes = process.readStdout(numBytesToRead = 4)
  if lengthBytes.len != 4:
    return "" # Not enough data
  
  # Convert the 4 bytes to an integer (little-endian)
  var msgLength: int
  copyMem(addr msgLength, lengthBytes[0].unsafeAddr, 4)
  
  # Read exactly msgLength bytes for the payload
  let payload = process.readStdout(numBytesToRead = msgLength)
  if payload.len != msgLength:
    return "" # Incomplete payload
  
  return payload

# Usage
var opts = SubprocessOptions(useStdout: true)
let process = startSubprocess("frame_protocol_app", [], opts)

while process.isRunning() or not process.isStdoutEof():
  let frame = readFrame(process)
  if frame.len > 0:
    echo "Received frame: ", frame
  else:
    # Small delay to prevent busy looping
    sleep(10)

process.close()
```

## Platform-Specific Notes

### Windows
- Uses Windows API for process creation and pipe management
- `terminate(graceful = true)` behaves the same as `terminate(graceful = false)`

### POSIX (Linux, macOS)
- Uses `fork()` and `execve()` for process creation
- `terminate(graceful = true)` sends SIGTERM first, then SIGKILL after a delay
- `terminate(graceful = false)` sends SIGKILL immediately

## Testing

Run the test suite:

```
# POSIX systems
nim c -r tests/test_posix.nim

# Windows
nim c -r tests/test_win.nim
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

YesDrX

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
