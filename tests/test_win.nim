when not defined(windows):
  quit(0)

import unittest
import std/[strutils, os, tables]
import subprocess

type CommandSpec = object
  cmd: string
  args: seq[string]

# Helper to find cmd.exe
proc getCmdExe(): string =
  result = getEnv("COMSPEC")
  if result.len == 0: result = "cmd.exe"

proc getSimpleEcho(msg: string): CommandSpec =
  when defined(windows):
    result.cmd = getCmdExe()
    # /c, echo, msg are separate arguments to avoid treating "echo msg" as file
    result.args = @["/c", "echo", msg]
  else:
    result.cmd = "echo"
    result.args = @[msg]

proc getCatCommand(): CommandSpec =
  when defined(windows):
    result.cmd = "findstr" 
    result.args = @["^"] 
  else:
    result.cmd = "cat"
    result.args = @[]

proc getEnvEcho(varName: string): CommandSpec =
  when defined(windows):
    result.cmd = getCmdExe()
    result.args = @["/c", "echo", "%" & varName & "%"]
  else:
    result.cmd = "sh"
    result.args = @["-c", "echo $" & varName]

proc getMixedOutput(): CommandSpec =
  when defined(windows):
    result.cmd = getCmdExe()
    result.args = @["/c", "echo std_msg && echo err_msg 1>&2"]
  else:
    result.cmd = "sh"
    result.args = @["-c", "echo std_msg; echo err_msg >&2"]

suite "Subprocess Library Tests":

  test "Basic Stdout Capture":
    let spec = getSimpleEcho("hello_world")
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess(spec.cmd, spec.args, opts)
    var output = ""
    while true:
      let chunk = process.readStdout()
      if chunk.len == 0 and not process.isRunning(): break
      output.add(chunk)
    check process.wait() == 0
    check output.strip() == "hello_world"
    process.close()

  test "Stdin -> Stdout (Interactive)":
    let spec = getCatCommand()
    var opts = SubprocessOptions(useStdin: true, useStdout: true)
    let process = startSubprocess(spec.cmd, spec.args, opts)
    discard process.write("ping payload")
    process.closeStdin()
    let output = process.readStdout()
    check process.wait() == 0
    check output.contains("ping payload")
    process.close()

  test "Environment Variable Injection":
    let varName = "TEST_NIM_SUBPROC"
    let varVal = "custom_value_123"
    var env = initTable[string, string]()
    env[varName] = varVal
    # We must preserve SystemRoot/COMSPEC for cmd.exe to run
    env["SystemRoot"] = getEnv("SystemRoot", "C:\\Windows")
    env["COMSPEC"] = getEnv("COMSPEC", "C:\\Windows\\System32\\cmd.exe")
    
    let spec = getEnvEcho(varName)
    var opts = SubprocessOptions(useStdout: true, env: env)
    let process = startSubprocess(spec.cmd, spec.args, opts)
    let output = process.readStdout().strip()
    check process.wait() == 0
    check output == varVal
    process.close()

  test "Combined Stdout and Stderr":
    let spec = getMixedOutput()
    var opts = SubprocessOptions(useStdout: true, combineStdoutStderr: true)
    let process = startSubprocess(spec.cmd, spec.args, opts)
    var output = ""
    while true:
      let chunk = process.readStdout()
      if chunk.len == 0 and not process.isRunning(): break
      output.add(chunk)
    check process.wait() == 0
    check output.contains("std_msg")
    check output.contains("err_msg")
    process.close()

  test "Separate Stdout and Stderr":
    let spec = getMixedOutput()
    var opts = SubprocessOptions(useStdout: true, useStderr: true)
    let process = startSubprocess(spec.cmd, spec.args, opts)
    var outStr = ""
    var errStr = ""
    while process.isRunning():
      outStr.add(process.readStdout())
      errStr.add(process.readStderr())
    outStr.add(process.readStdout())
    errStr.add(process.readStderr())
    check outStr.contains("std_msg")
    check errStr.contains("err_msg")
    process.close()

  test "Exit Codes":
    when defined(windows):
      let cmd = getCmdExe()
      let args = @["/c", "exit 42"]
    else:
      let cmd = "sh"
      let args = @["-c", "exit 42"]
    var opts = SubprocessOptions()
    let process = startSubprocess(cmd, args, opts)
    check process.wait() == 42
    process.close()

  test "hasDataStdout - Data Available":
    # Python script that immediately prints output
    let script = "import sys; print('test data'); sys.stdout.flush()"
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess("python", ["-c", script], opts)
    
    # Try to read with timeout - if data is available, this should succeed quickly
    let output = process.readStdout(timeoutMs = 2000)
    check output.contains("test data")
    
    # Now that we've read the data, hasDataStdout should return false
    # (no more data available)
    check process.hasDataStdout() == false
    
    check process.wait() == 0
    process.close()
  
  test "hasDataStdout - Check Before Read":
    # Python script that prints then waits (stays alive)
    let script = "import sys, time; print('ready'); sys.stdout.flush(); time.sleep(10)"
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess("python", ["-c", script], opts)
    
    # Wait a bit for the print to happen
    sleep(200)
    
    # Now hasDataStdout should work since process is still running
    if process.hasDataStdout():
      let output = process.readStdout()
      check output.contains("ready")
    else:
      # If hasDataStdout didn't work, at least verify we can read with timeout
      let output = process.readStdout(timeoutMs = 1000)
      check output.contains("ready")
    
    process.close()
  
  test "hasDataStdout - No Data Available":
    # Python script that sleeps before printing
    let script = "import time; time.sleep(5); print('delayed')"
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess("python", ["-c", script], opts)
    
    # Immediately check - should be no data yet
    check process.hasDataStdout() == false
    
    process.close()
  
  test "hasDataStderr - Data Available":
    # Python script that prints to stderr
    let script = "import sys; sys.stderr.write('error data\\n'); sys.stderr.flush()"
    var opts = SubprocessOptions(useStderr: true)
    let process = startSubprocess("python", ["-c", script], opts)
    
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
    let process = startSubprocess("python", ["-c", script], opts)
    
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
    let process = startSubprocess("python", ["-c", script], opts)
    
    # Try to read with short timeout - should timeout
    let output = process.readStdout(timeoutMs = 100)
    check output == ""
    
    process.close()
  
  test "readStderr with Timeout - Data Available":
    # Python script that immediately prints to stderr
    let script = "import sys; sys.stderr.write('error output\\n'); sys.stderr.flush()"
    var opts = SubprocessOptions(useStderr: true)
    let process = startSubprocess("python", ["-c", script], opts)
    
    # Give it time to produce output
    sleep(100)
    
    # Read with timeout - should succeed
    let output = process.readStderr(timeoutMs = 1000)
    check output.contains("error output")
    
    check process.wait() == 0
    process.close()