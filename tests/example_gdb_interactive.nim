## Example: Running gdb interactively
## 
## This demonstrates how to use the subprocess library to run gdb
## in an interactive mode, sending commands and reading responses.

import subprocess
import std/[os, strutils]

proc main() =
    # Path to the test program we'll debug
    let testProgramPath = currentSourcePath.parentDir / "test_program"
    
    if not fileExists(testProgramPath):
        echo "Error: test_program not found. Please compile it first:"
        echo "  gcc -g -o test_program test_program.c"
        quit(1)
    
    echo "Starting gdb session with test_program..."
    echo "=" .repeat(50)
    
    # Configure subprocess to use stdin/stdout
    var opts = SubprocessOptions(
        useStdin: true, 
        useStdout: true,
        combineStdoutStderr: true
    )
    
    # Start gdb with the test program (-q for quiet mode)
    let process = startSubprocess("gdb", ["-q", testProgramPath], opts)
    
    # Helper proc to send command and read response
    proc gdbCommand(cmd: string): string =
        echo "\n[GDB Command] ", cmd
        discard process.write(cmd & "\n")
        sleep(200)  # Give gdb time to process and respond
        return process.readStdout()
    
    # Wait for initial gdb prompt and read welcome message
    sleep(300)
    let welcome = process.readStdout()
    echo welcome
    
    # Set a breakpoint at main
    var output = gdbCommand("break main")
    echo output
    
    # Run the program
    output = gdbCommand("run")
    echo output
    
    # Print variable x (should be 5)
    output = gdbCommand("print x")
    echo output
    
    # Print variable y (should be 10)
    output = gdbCommand("print y")
    echo output
    
    # Set another breakpoint at the add function
    output = gdbCommand("break add")
    echo output
    
    # Continue execution to hit the add function
    output = gdbCommand("continue")
    echo output
    
    # Print function parameters
    output = gdbCommand("print a")
    echo output
    
    output = gdbCommand("print b")
    echo output
    
    # Step through and see the return value
    output = gdbCommand("next")
    echo output
    
    # Print the result
    output = gdbCommand("print a + b")
    echo output
    
    # Continue to finish execution
    output = gdbCommand("continue")
    echo output
    
    # Quit gdb
    echo "\n[GDB Command] quit"
    discard process.write("quit\n")
    
    # Wait for gdb to exit
    let exitCode = process.wait()
    echo "\n" & "=" .repeat(50)
    echo "GDB session ended with exit code: ", exitCode
    
    process.close()

when isMainModule:
    main()
