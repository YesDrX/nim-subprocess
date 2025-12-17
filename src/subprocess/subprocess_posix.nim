## POSIX implementation of subprocess management
##
## This module provides the POSIX-specific implementation (Linux, macOS, BSD, etc.)
## using fork/exec and standard POSIX APIs.

import std/[tables, posix, os, times]

type
    Handle*     = cint
    ProcessPID* = cint
    IOHandle*   = cint

type
    SubprocessOptions* = object
        env*                 : Table[string, string]
        cwd*                 : string
        useStdin*            : bool
        useStdout*           : bool
        useStderr*           : bool
        combineStdoutStderr* : bool

    SubprocessObj* = object
        pid*            : ProcessPID
        process_handle* : Handle
        stdin*          : IOHandle
        stdout*         : IOHandle
        stderr*         : IOHandle
        exit_code*      : int
        stdoutEof*      : bool  ## True when stdout has reached EOF
        stderrEof*      : bool  ## True when stderr has reached EOF
    
    Subprocess* = ref SubprocessObj

proc closePipe(fd: var cint)

proc `=destroy`*(subprocess: var SubprocessObj) =
    ## Destructor to prevent zombie processes
    if subprocess.pid > 0:
        discard kill(subprocess.pid, SIGKILL)
        # Try to reap the zombie
        var status: cint
        discard waitpid(subprocess.pid, status, WNOHANG)
    closePipe(subprocess.stdin)
    closePipe(subprocess.stdout)
    closePipe(subprocess.stderr)

proc closePipe(fd: var cint) =
  if fd >= 0:
    discard close(fd)
    fd = -1

proc startSubprocess*(
    command: string,
    args: openArray[string],
    options: SubprocessOptions
): Subprocess =
    ## Start a new subprocess with the given command and arguments.
    ## 
    ## Args:
    ##   command: The program to execute (can be name or full path)
    ##   args: Command-line arguments (argv[1], argv[2], ...)
    ##   options: Configuration options (stdin/stdout/stderr, env, cwd)
    ## 
    ## Returns:
    ##   A Subprocess ref object for interacting with the process
    ## 
    ## Raises:
    ##   OSError if pipe creation or fork fails
    ## 
    ## Example:
    ##   ```nim
    ##   var opts = SubprocessOptions(useStdout: true)
    ##   let p = startSubprocess("ls", ["-la"], opts)
    ##   echo p.readAllStdout()
    ##   p.close()
    ##   ```
    result = Subprocess()
    result.pid = -1
    result.exit_code = -1
    result.process_handle = 1 # Mark as active
    result.stdin = -1
    result.stdout = -1
    result.stderr = -1
    result.stdoutEof = false
    result.stderrEof = false

    var
        pStdin: array[2, cint]  = [-1.cint, -1.cint]
        pStdout: array[2, cint] = [-1.cint, -1.cint]
        pStderr: array[2, cint] = [-1.cint, -1.cint]

    try:
        if options.useStdin:
            if pipe(pStdin) != 0: raise newException(OSError, "Failed stdin pipe")
        if options.useStdout:
            if pipe(pStdout) != 0: raise newException(OSError, "Failed stdout pipe")
        if options.useStderr and not options.combineStdoutStderr:
            if pipe(pStderr) != 0: raise newException(OSError, "Failed stderr pipe")
    except OSError:
        closePipe(pStdin[0]); closePipe(pStdin[1])
        closePipe(pStdout[0]); closePipe(pStdout[1])
        closePipe(pStderr[0]); closePipe(pStderr[1])
        raise

    # Resolve the executable path eagerly. 
    # execve (used when env is custom) requires an absolute path.
    # findExe searches the current system PATH.
    var cmdPath = command
    if options.env.len > 0:
        let resolved = findExe(command)
        if resolved.len > 0:
            cmdPath = resolved

    let pid = fork()
    if pid < 0:
        # Clean up pipes on fork failure
        closePipe(pStdin[0]); closePipe(pStdin[1])
        closePipe(pStdout[0]); closePipe(pStdout[1])
        closePipe(pStderr[0]); closePipe(pStderr[1])
        raise newException(OSError, "Failed to fork")

    if pid == 0:
        # --- CHILD ---
        if options.useStdin:
            discard dup2(pStdin[0], STDIN_FILENO)
            closePipe(pStdin[0]); closePipe(pStdin[1])
        
        if options.useStdout:
            discard dup2(pStdout[1], STDOUT_FILENO)
            closePipe(pStdout[0]); closePipe(pStdout[1])

        if options.combineStdoutStderr:
            if options.useStdout:
                discard dup2(STDOUT_FILENO, STDERR_FILENO)
        elif options.useStderr:
            discard dup2(pStderr[1], STDERR_FILENO)
            closePipe(pStderr[0]); closePipe(pStderr[1])

        if options.cwd != "":
            if chdir(options.cwd.cstring) != 0:
                discard write(STDERR_FILENO, "Error: Could not change directory\n".cstring, 32)
                exitnow(1)

        # Corrected Argument Construction
        # We pass the original 'command' string as argv[0] (convention),
        # but we execute the resolved 'cmdPath'.
        var c_args_seq = @[command]
        for a in args: c_args_seq.add(a)
        let c_args = allocCStringArray(c_args_seq)

        if options.env.len > 0:
            var env_seq: seq[string] = @[]
            for k, v in options.env: env_seq.add(k & "=" & v)
            let c_env = allocCStringArray(env_seq)
            
            # execve requires full path (cmdPath), it does not search PATH.
            discard execve(cmdPath.cstring, c_args, c_env)
        else:
            # execvp searches PATH automatically.
            discard execvp(command.cstring, c_args)

        # Error handling if exec fails
        let err = strerror(errno)
        discard write(STDERR_FILENO, "Exec failed: ".cstring, 13)
        discard write(STDERR_FILENO, err, err.len.int)
        discard write(STDERR_FILENO, "\n".cstring, 1)
        
        # Deallocate (good practice, though OS cleans up on exit)
        deallocCStringArray(c_args)
        exitnow(127)

    # --- PARENT ---
    result.pid = pid
    
    if options.useStdin:
        closePipe(pStdin[0]) # Close read end
        result.stdin = pStdin[1]
    
    if options.useStdout:
        closePipe(pStdout[1]) # Close write end
        result.stdout = pStdout[0]
    
    if options.useStderr and not options.combineStdoutStderr:
        closePipe(pStderr[1]) # Close write end
        result.stderr = pStderr[0]

proc isRunning*(subprocess: Subprocess): bool =
    ## Check if the subprocess is still running.
    ## 
    ## This is a non-blocking check using waitpid with WNOHANG.
    ## If the process has exited, updates exit_code automatically.
    ## 
    ## Returns:
    ##   true if the process is still running, false otherwise
    ## 
    ## Example:
    ##   ```nim
    ##   while p.isRunning():
    ##     let output = p.readStdout(timeoutMs = 100)
    ##     if output.len > 0: echo output
    ##   ```
    if subprocess.pid <= 0: return false
    var status: cint
    let res = waitpid(subprocess.pid, status, WNOHANG)
    if res == 0: return true
    if res == subprocess.pid:
        subprocess.exit_code = if WIFEXITED(status): WEXITSTATUS(status) else: -1
        subprocess.pid = -1
        return false
    return false

proc wait*(subprocess: Subprocess): int =
    ## Wait for the subprocess to exit and return its exit code.
    ## 
    ## This is a blocking call that waits until the process terminates.
    ## 
    ## Returns:
    ##   The exit code of the process (0 typically means success)
    ## 
    ## Example:
    ##   ```nim
    ##   let exitCode = p.wait()
    ##   if exitCode == 0:
    ##     echo "Process succeeded"
    ##   ```
    if subprocess.pid <= 0: return subprocess.exit_code
    var status: cint
    let res = waitpid(subprocess.pid, status, 0)
    if res == subprocess.pid:
        subprocess.exit_code = if WIFEXITED(status): WEXITSTATUS(status) else: -1
        subprocess.pid = -1
    return subprocess.exit_code

proc write*(subprocess: Subprocess, data: string): int =
    ## Write data to subprocess stdin.
    ## 
    ## Handles partial writes automatically by retrying until all data is written.
    ## Handles EINTR, EAGAIN, and EWOULDBLOCK conditions.
    ## 
    ## Args:
    ##   data: The string data to write to stdin
    ## 
    ## Returns:
    ##   Number of bytes successfully written (should equal data.len on success)
    ## 
    ## Example:
    ##   ```nim
    ##   let written = p.write("hello\n")
    ##   if written != 6:
    ##     echo "Partial write or error"
    ##   ```
    ## Write data to subprocess stdin. Returns number of bytes written.
    ## Handles partial writes automatically.
    if subprocess.stdin < 0: return 0
    if data.len == 0: return 0
    
    var totalWritten = 0
    while totalWritten < data.len:
        let n = write(subprocess.stdin, unsafeAddr data[totalWritten], data.len - totalWritten)
        if n < 0:
            if errno == EINTR: continue  # Interrupted, retry
            if errno == EAGAIN or errno == EWOULDBLOCK:
                sleep(1)  # Would block, wait a bit
                continue
            return totalWritten  # Error, return what we wrote
        if n == 0: return totalWritten  # Pipe closed
        totalWritten += n
    return totalWritten

proc closeStdin*(subprocess: Subprocess) =
    ## Close the stdin pipe to the subprocess.
    ## 
    ## This signals EOF to the subprocess. Useful after writing all input.
    ## Many programs (like `cat`, `wc`, etc.) wait for EOF before processing.
    closePipe(subprocess.stdin)

proc hasDataStdout*(subprocess: Subprocess): bool =
    ## Check if stdout has data available to read without blocking.
    ## 
    ## Uses select() with zero timeout for immediate, non-blocking check.
    ## 
    ## Returns:
    ##   true if data is available, false otherwise
    ## 
    ## Example:
    ##   ```nim
    ##   if p.hasDataStdout():
    ##     let data = p.readStdout()
    ##     echo "Got: ", data
    ##   ```
    if subprocess.stdout < 0: return false
    var readfds: TFdSet
    FD_ZERO(readfds)
    FD_SET(subprocess.stdout, readfds)
    var timeout = Timeval(tv_sec: posix.Time(0), tv_usec: Suseconds(0))
    let selectResult = select(subprocess.stdout + 1, addr readfds, nil, nil, addr timeout)
    return selectResult > 0 and FD_ISSET(subprocess.stdout, readfds) != 0.cint

proc hasDataStderr*(subprocess: Subprocess): bool =
    ## Check if stderr has data available to read without blocking.
    ## 
    ## Uses select() with zero timeout for immediate, non-blocking check.
    ## 
    ## Returns:
    ##   true if data is available, false otherwise
    if subprocess.stderr < 0: return false
    var readfds: TFdSet
    FD_ZERO(readfds)
    FD_SET(subprocess.stderr, readfds)
    var timeout = Timeval(tv_sec: posix.Time(0), tv_usec: Suseconds(0))
    let selectResult = select(subprocess.stderr + 1, addr readfds, nil, nil, addr timeout)
    return selectResult > 0 and FD_ISSET(subprocess.stderr, readfds) != 0.cint

proc isStdoutEof*(subprocess: Subprocess): bool =
    ## Check if stdout has reached end-of-file (EOF).
    ## 
    ## Returns true if a previous read operation encountered EOF,
    ## indicating the subprocess has closed its stdout.
    ## 
    ## Returns:
    ##   true if stdout has reached EOF, false otherwise
    ## 
    ## Example:
    ##   ```nim
    ##   while not p.isStdoutEof():
    ##     let data = p.readStdout(timeoutMs = 100)
    ##     if data.len > 0:
    ##       echo data
    ##   ```
    return subprocess.stdoutEof

proc isStderrEof*(subprocess: Subprocess): bool =
    ## Check if stderr has reached end-of-file (EOF).
    ## 
    ## Returns true if a previous read operation encountered EOF,
    ## indicating the subprocess has closed its stderr.
    ## 
    ## Returns:
    ##   true if stderr has reached EOF, false otherwise
    return subprocess.stderrEof

proc readStdout*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read from stdout with optional timeout.
    ## 
    ## Reads up to 4096 bytes. For reading all data, use readAllStdout().
    ## 
    ## Args:
    ##   timeoutMs: Timeout in milliseconds. -1 means blocking (wait forever)
    ## 
    ## Returns:
    ##   String with data read, or empty string if timeout/EOF/error
    ## 
    ## Example:
    ##   ```nim
    ##   # Read with 1 second timeout
    ##   let data = p.readStdout(timeoutMs = 1000)
    ##   if data.len > 0:
    ##     echo "Read: ", data
    ##   ```
    if subprocess.stdout < 0: return ""
    
    # If timeout is specified, use select to wait for data
    if timeoutMs >= 0:
        var readfds: TFdSet
        FD_ZERO(readfds)
        FD_SET(subprocess.stdout, readfds)
        var timeout = Timeval(
            tv_sec: posix.Time(timeoutMs div 1000),
            tv_usec: Suseconds((timeoutMs mod 1000) * 1000)
        )
        let selectResult = select(subprocess.stdout + 1, addr readfds, nil, nil, addr timeout)
        if selectResult <= 0:
            return ""  # Timeout or error
    
    var buffer = newString(4096)
    let n = read(subprocess.stdout, addr buffer[0], 4096)
    if n > 0:
        buffer.setLen(n)
        return buffer
    # n == 0 means EOF, n < 0 means error
    if n == 0:
        subprocess.stdoutEof = true
    return ""

proc readStderr*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read from stderr with optional timeout.
    ## 
    ## Reads up to 4096 bytes. For reading all data, use readAllStderr().
    ## 
    ## Args:
    ##   timeoutMs: Timeout in milliseconds. -1 means blocking (wait forever)
    ## 
    ## Returns:
    ##   String with data read, or empty string if timeout/EOF/error
    if subprocess.stderr < 0: return ""
    
    # If timeout is specified, use select to wait for data
    if timeoutMs >= 0:
        var readfds: TFdSet
        FD_ZERO(readfds)
        FD_SET(subprocess.stderr, readfds)
        var timeout = Timeval(
            tv_sec: posix.Time(timeoutMs div 1000),
            tv_usec: Suseconds((timeoutMs mod 1000) * 1000)
        )
        let selectResult = select(subprocess.stderr + 1, addr readfds, nil, nil, addr timeout)
        if selectResult <= 0:
            return ""  # Timeout or error
    
    var buffer = newString(4096)
    let n = read(subprocess.stderr, addr buffer[0], 4096)
    if n > 0:
        buffer.setLen(n)
        return buffer
    # n == 0 means EOF, n < 0 means error
    if n == 0:
        subprocess.stderrEof = true
    return ""

proc readAllStdout*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read all available data from stdout.
    ## 
    ## Continues reading until no more data is available or timeout expires.
    ## 
    ## Args:
    ##   timeoutMs: Total timeout in milliseconds for the entire operation.
    ##     -1 means no timeout (reads until EOF or no data available)
    ## 
    ## Returns:
    ##   Concatenated string of all data read
    ## 
    ## Example:
    ##   ```nim
    ##   let allData = p.readAllStdout()
    ##   echo "Complete output: ", allData
    ##   ```
    result = ""
    let startTime = if timeoutMs >= 0: epochTime() else: 0.0
    
    while true:
        let remainingTimeout = 
            if timeoutMs >= 0:
                let elapsed = (epochTime() - startTime) * 1000.0
                let remaining = timeoutMs.float - elapsed
                if remaining <= 0: break
                remaining.int
            else:
                -1
        
        let chunk = subprocess.readStdout(remainingTimeout)
        if chunk.len == 0: break
        result.add(chunk)

proc readAllStderr*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read all available data from stderr.
    ## 
    ## Continues reading until no more data is available or timeout expires.
    ## 
    ## Args:
    ##   timeoutMs: Total timeout in milliseconds for the entire operation.
    ##     -1 means no timeout (reads until EOF or no data available)
    ## 
    ## Returns:
    ##   Concatenated string of all data read
    result = ""
    let startTime = if timeoutMs >= 0: epochTime() else: 0.0
    
    while true:
        let remainingTimeout = 
            if timeoutMs >= 0:
                let elapsed = (epochTime() - startTime) * 1000.0
                let remaining = timeoutMs.float - elapsed
                if remaining <= 0: break
                remaining.int
            else:
                -1
        
        let chunk = subprocess.readStderr(remainingTimeout)
        if chunk.len == 0: break
        result.add(chunk)

proc terminate*(subprocess: Subprocess, graceful: bool = true) =
    ## Terminate the subprocess.
    ## 
    ## Args:
    ##   graceful: If true, sends SIGTERM first and waits up to 3 seconds
    ##     before escalating to SIGKILL. If false, sends SIGKILL immediately.
    ## 
    ## Example:
    ##   ```nim
    ##   # Try graceful shutdown first
    ##   p.terminate(graceful = true)
    ##   
    ##   # Force kill immediately
    ##   p.terminate(graceful = false)
    ##   ```
    if subprocess.pid <= 0: return
    
    if graceful:
        # Try SIGTERM first
        discard kill(subprocess.pid, SIGTERM)
        
        # Wait up to 3 seconds for graceful shutdown
        let startTime = epochTime()
        while epochTime() - startTime < 3.0:
            if not subprocess.isRunning():
                return
            sleep(50)
        
        # Still running, use SIGKILL
        discard kill(subprocess.pid, SIGKILL)
    else:
        # Immediate kill
        discard kill(subprocess.pid, SIGKILL)
    
    discard subprocess.wait()

proc close*(subprocess: Subprocess) =
    ## Close subprocess and clean up all resources.
    ## 
    ## Terminates the process (using SIGKILL) if still running, then closes
    ## all pipes (stdin, stdout, stderr).
    ## 
    ## Example:
    ##   ```nim
    ##   let p = startSubprocess(...)
    ##   p.close()
    ##   ```
    subprocess.terminate(graceful = false)
    closePipe(subprocess.stdin)
    closePipe(subprocess.stdout)
    closePipe(subprocess.stderr)
