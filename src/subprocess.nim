## Cross-platform subprocess management library
##
## This module provides a simple interface for spawning and managing subprocesses
## across Windows and POSIX platforms (Linux, macOS, etc.).
##
## Basic usage:
## 
## .. code-block:: nim
##   import subprocess
##   
##   # Capture standard output
##   var opts = SubprocessOptions(useStdout: true)
##   let process = startSubprocess("echo", ["hello world"], opts)
##   let output = process.readAllStdout()
##   echo output  # "hello world"
##   process.close()
##
## .. code-block:: nim
##   import std/strutils
##   import subprocess
##
##   ## Example 1: Capture output
##   block:
##     var opts = SubprocessOptions(useStdout: true)
##     let process = startSubprocess("echo", ["test output"], opts)
##     let output = process.readAllStdout().strip()
##     doAssert output == "test output"
##     doAssert process.wait() == 0
##     process.close()
##   
##   ## Example 2: Write to stdin and read stdout
##   block:
##     var opts = SubprocessOptions(useStdin: true, useStdout: true)
##     let process = startSubprocess("cat", [], opts)
##     discard process.write("hello from stdin\n")
##     process.closeStdin()
##     let output = process.readAllStdout().strip()
##     doAssert output == "hello from stdin"
##     process.close()
##   
##   ## Example 3: Check for data before reading
##   block:
##     var opts = SubprocessOptions(useStdout: true)
##     let process = startSubprocess("echo", ["quick"], opts)
##     sleep(50)  ## Give it time to produce output
##     if process.hasDataStdout():
##       let output = process.readStdout()
##       doAssert output.len > 0
##     process.close()
##   
##   ## Example 4: Read with timeout
##   block:
##     var opts = SubprocessOptions(useStdout: true)
##     let process = startSubprocess("echo", ["timeout test"], opts)
##     sleep(50)
##     ## Read with 1 second timeout
##     let output = process.readStdout(timeoutMs = 1000).strip()
##     doAssert output == "timeout test"
##     process.close()
##   
##   ## Example 5: Graceful termination (POSIX only)
##   when not defined(windows):
##     block:
##       var opts = SubprocessOptions()
##       let process = startSubprocess("sleep", ["10"], opts)
##       doAssert process.isRunning()
##       process.terminate(graceful = true)  ## Sends SIGTERM first
##       doAssert not process.isRunning()
##   
##   ## Example 6: Byte frame protocol - read exact byte counts
##   block:
##     # For protocols with format: [4-byte length][payload]
##     proc readFrame(process: Subprocess): string =
##       # Read exactly 4 bytes for the message length
##       let lengthBytes = process.readStdout(numBytesToRead = 4)
##       if lengthBytes.len != 4:
##         return "" # Not enough data
##       
##       # Convert the 4 bytes to an integer (little-endian)
##       var msgLength: int
##       copyMem(addr msgLength, lengthBytes[0].unsafeAddr, 4)
##       
##       # Read exactly msgLength bytes for the payload
##       let payload = process.readStdout(numBytesToRead = msgLength)
##       if payload.len != msgLength:
##         return "" # Incomplete payload
##       
##       return payload
##     
##     # Usage with a subprocess that outputs framed data
##     # var opts = SubprocessOptions(useStdout: true)
##     # let process = startSubprocess("frame_protocol_app", [], opts)
##     # 
##     # while process.isRunning() or not process.isStdoutEof():
##     #   let frame = readFrame(process)
##     #   if frame.len > 0:
##     #     echo "Received frame: ", frame
##     #   else:
##     #     # Small delay to prevent busy looping
##     #     sleep(10)
##     # 
##     # process.close()

when defined(windows):
    import ./subprocess/subprocess_win
    export subprocess_win
else:
    import ./subprocess/subprocess_posix
    export subprocess_posix