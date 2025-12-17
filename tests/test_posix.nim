when defined(windows):
    quit(0)

import unittest
import subprocess
import std/[os, strutils, tables]

suite "Subprocess Tests":

    test "Standard Output Capture":
        var opts = SubprocessOptions(useStdout: true)
        let process = startSubprocess("echo", ["hello world"], opts)
        
        var output = ""
        while process.isRunning():
            output.add(process.readStdout())
        
        # Capture remaining buffer after exit
        output.add(process.readStdout()) 
        process.close()

        check output.strip() == "hello world"

    test "Stdin to Stdout (Interactive)":
        # 'cat' echoes what we write to it
        var opts = SubprocessOptions(useStdin: true, useStdout: true)
        let process = startSubprocess("cat", [], opts)
        
        discard process.write("ping\n")
        
        # Give it a tiny bit of time to flush (OS dependent, usually instant for cat)
        sleep(50)
        
        let out1 = process.readStdout()
        check out1.contains("ping")

        # Close stdin to tell cat to finish
        process.closeStdin()
        check process.wait() == 0
        process.close()

    test "Combined Output (Stdout + Stderr)":
        # Python script to print to both
        let script = "import sys; print('out'); sys.stderr.write('err\\n')"
        var opts = SubprocessOptions(useStdout: true, combineStdoutStderr: true)
        
        # Note: 'python3' must be in PATH. 
        # If using execve (custom env), full path needed.
        let process = startSubprocess("python3", ["-c", script], opts)
        
        var output = ""
        while true:
            let chunk = process.readStdout()
            if chunk == "" and not process.isRunning(): break
            output.add(chunk)
            
        check output.contains("out")
        check output.contains("err")
        process.close()

    test "Environment Variables":
        var env = initTable[string, string]()
        env["MY_VAR"] = "nim_subprocess_test"
        
        var opts = SubprocessOptions(useStdout: true, env: env)
        # Using 'sh' to check env var
        let process = startSubprocess("sh", ["-c", "echo $MY_VAR"], opts)
        
        check process.wait() == 0
        let output = process.readStdout().strip()
        
        check output == "nim_subprocess_test"
        process.close()
        
    test "Exit Codes":
        var opts = SubprocessOptions()
        let process = startSubprocess("sh", ["-c", "exit 42"], opts)
        check process.wait() == 42
        process.close()
    
    test "hasDataStdout - Data Available":
        # Python script that immediately prints output
        let script = "import sys; print('test data'); sys.stdout.flush()"
        var opts = SubprocessOptions(useStdout: true)
        let process = startSubprocess("python3", ["-c", script], opts)
        
        # Give process time to write
        sleep(100)
        
        # Check if data is available
        check process.hasDataStdout() == true
        
        # Read the data
        let output = process.readStdout()
        check output.contains("test data")
        
        check process.wait() == 0
        process.close()
    
    test "hasDataStdout - No Data Available":
        # Python script that sleeps before printing
        let script = "import time; time.sleep(5); print('delayed')"
        var opts = SubprocessOptions(useStdout: true)
        let process = startSubprocess("python3", ["-c", script], opts)
        
        # Immediately check - should be no data yet
        check process.hasDataStdout() == false
        
        process.close()
    
    test "hasDataStderr - Data Available":
        # Python script that prints to stderr
        let script = "import sys; sys.stderr.write('error data\\n'); sys.stderr.flush()"
        var opts = SubprocessOptions(useStderr: true)
        let process = startSubprocess("python3", ["-c", script], opts)
        
        # Give process time to write
        sleep(100)
        
        # Check if data is available
        check process.hasDataStderr() == true
        
        # Read the data
        let output = process.readStderr()
        check output.contains("error data")
        
        check process.wait() == 0
        process.close()
    
    test "readStdout with Timeout - Data Available":
        # Python script that immediately prints
        let script = "import sys; print('quick output'); sys.stdout.flush()"
        var opts = SubprocessOptions(useStdout: true)
        let process = startSubprocess("python3", ["-c", script], opts)
        
        # Give it time to produce output
        sleep(100)
        
        # Read with timeout - should succeed
        let output = process.readStdout(timeoutMs = 1000)
        check output.contains("quick output")
        
        check process.wait() == 0
        process.close()
    
    test "readStdout with Timeout - Timeout Expires":
        # Python script that sleeps before printing
        let script = "import time; time.sleep(5); print('delayed output')"
        var opts = SubprocessOptions(useStdout: true)
        let process = startSubprocess("python3", ["-c", script], opts)
        
        # Try to read with short timeout - should timeout
        let output = process.readStdout(timeoutMs = 100)
        check output == ""
        
        process.close()
    
    test "readStderr with Timeout - Data Available":
        # Python script that immediately prints to stderr
        let script = "import sys; sys.stderr.write('error output\\n'); sys.stderr.flush()"
        var opts = SubprocessOptions(useStderr: true)
        let process = startSubprocess("python3", ["-c", script], opts)
        
        # Give it time to produce output
        sleep(100)
        
        # Read with timeout - should succeed
        let output = process.readStderr(timeoutMs = 1000)
        check output.contains("error output")
        
        check process.wait() == 0
        process.close()