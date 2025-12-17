## Windows implementation of subprocess management
##
## This module provides the Windows-specific implementation using CreateProcessA
## and Windows pipe APIs.

import std/[tables, times]
import std/winlean

type
    # Winlean defines Handle as int
    ProcessPID* = int
    IOHandle*   = Handle

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
    
    Subprocess* = ref SubprocessObj

proc closeHandleSafe(h: var winlean.Handle)

proc `=destroy`*(subprocess: var SubprocessObj) =
    ## Destructor to clean up resources
    if subprocess.process_handle != 0:
        if subprocess.process_handle != 0:
            var code: int32
            if getExitCodeProcess(subprocess.process_handle, code) != 0:
                if code == STILL_ACTIVE:
                    discard terminateProcess(subprocess.process_handle, 1)
        closeHandleSafe(subprocess.process_handle)
        subprocess.process_handle = 0
    
    var hIn = subprocess.stdin
    closeHandleSafe(hIn)
    var hOut = subprocess.stdout
    closeHandleSafe(hOut)
    var hErr = subprocess.stderr
    closeHandleSafe(hErr)

# Winlean defines STARTUPINFO with cstrings, so it is actually STARTUPINFOA.
# Winlean exposes CreateProcessW, which mismatches the struct. 
# We import CreateProcessA to match the struct and your working C code.
proc createProcessA(
    lpApplicationName: cstring,
    lpCommandLine: cstring,
    lpProcessAttributes: ptr SECURITY_ATTRIBUTES,
    lpThreadAttributes: ptr SECURITY_ATTRIBUTES,
    bInheritHandles: WINBOOL,
    dwCreationFlags: int32,
    lpEnvironment: cstring, 
    lpCurrentDirectory: cstring,
    lpStartupInfo: var STARTUPINFO,
    lpProcessInformation: var PROCESS_INFORMATION
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "CreateProcessA".}

proc peekNamedPipe(
    hNamedPipe: Handle,
    lpBuffer: pointer,
    nBufferSize: int32,
    lpBytesRead: ptr int32,
    lpTotalBytesAvail: ptr int32,
    lpBytesLeftThisMessage: ptr int32
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "PeekNamedPipe".}

const INVALID_HANDLE = cast[winlean.Handle](-1)

# --- Helpers ---

proc buildCmdLine(cmd: string, args: openArray[string]): string =
    # Proper Windows command line escaping
    var sb = newStringOfCap(cmd.len + 100)
    
    proc addArg(s: string) =
        # Windows command line escaping rules:
        # 1. Always quote if empty or contains space/tab
        # 2. Backslashes before quotes need to be escaped
        # 3. Trailing backslashes before closing quote need to be escaped
        
        let needsQuotes = s.len == 0 or ' ' in s or '\t' in s or '"' in s
        
        if needsQuotes:
            sb.add('"')
        
        var i = 0
        while i < s.len:
            var numBackslashes = 0
            while i < s.len and s[i] == '\\':
                inc numBackslashes
                inc i
            
            if i == s.len:
                # Backslashes at end of arg - escape them if quoting
                if needsQuotes:
                    for j in 0..<(numBackslashes * 2):
                        sb.add('\\')
                else:
                    for j in 0..<numBackslashes:
                        sb.add('\\')
            elif s[i] == '"':
                # Backslashes before quote - escape them and the quote
                for j in 0..<(numBackslashes * 2 + 1):
                    sb.add('\\')
                sb.add('"')
                inc i
            else:
                # Normal backslashes
                for j in 0..<numBackslashes:
                    sb.add('\\')
                sb.add(s[i])
                inc i
        
        if needsQuotes:
            sb.add('"')

    addArg(cmd)
    for a in args:
        sb.add(' ')
        addArg(a)
    return sb

proc buildEnvBlock(env: Table[string, string]): string =
    # ANSI Environment block: key=val\0key2=val2\0\0
    result = ""
    for k, v in env:
        if k.len == 0: continue
        result.add(k)
        result.add('=')
        result.add(v)
        result.add('\0')
    result.add('\0')

proc closeHandleSafe(h: var winlean.Handle) =
    if h != 0 and h != INVALID_HANDLE:
        discard closeHandle(h)
        h = INVALID_HANDLE

# --- Implementation ---

proc startSubprocess*(
    command: string,
    args: openArray[string],
    options: SubprocessOptions
): Subprocess =
    ## Start a new subprocess with the given command and arguments.
    ## 
    ## Args:
    ##   command: The program to execute (can be name or full path)
    ##   args: Command-line arguments
    ##   options: Configuration options (stdin/stdout/stderr, env, cwd)
    ## 
    ## Returns:
    ##   A Subprocess ref object for interacting with the process
    ## 
    ## Raises:
    ##   OSError if pipe creation or process creation fails
    ## 
    ## Example:
    ##   ```nim
    ##   var opts = SubprocessOptions(useStdout: true)
    ##   let p = startSubprocess("cmd", ["/c", "dir"], opts)
    ##   echo p.readAllStdout()
    ##   p.close()
    ##   ```
    result = Subprocess()
    result.pid = 0
    result.process_handle = 0
    result.exit_code = -1
    result.stdin = 0
    result.stdout = 0
    result.stderr = 0

    var
        sa: SECURITY_ATTRIBUTES
        hInRd, hInWr: winlean.Handle
        hOutRd, hOutWr: winlean.Handle
        hErrRd, hErrWr: winlean.Handle

    sa.nLength = sizeof(SECURITY_ATTRIBUTES).cint
    sa.lpSecurityDescriptor = nil
    sa.bInheritHandle = 1 # TRUE

    # 1. Create Pipes
    try:
        if options.useStdin:
            if createPipe(hInRd, hInWr, sa, 0) == 0: raise newException(OSError, "Failed stdin pipe")
            discard setHandleInformation(hInWr, HANDLE_FLAG_INHERIT, 0)

        if options.useStdout:
            if createPipe(hOutRd, hOutWr, sa, 0) == 0: raise newException(OSError, "Failed stdout pipe")
            discard setHandleInformation(hOutRd, HANDLE_FLAG_INHERIT, 0)

        if options.useStderr and not options.combineStdoutStderr:
            if createPipe(hErrRd, hErrWr, sa, 0) == 0: raise newException(OSError, "Failed stderr pipe")
            discard setHandleInformation(hErrRd, HANDLE_FLAG_INHERIT, 0)

    except OSError:
        closeHandleSafe(hInRd); closeHandleSafe(hInWr)
        closeHandleSafe(hOutRd); closeHandleSafe(hOutWr)
        closeHandleSafe(hErrRd); closeHandleSafe(hErrWr)
        raise

    # 2. Setup Startup Info
    var si: STARTUPINFO
    si.cb = sizeof(STARTUPINFO).int32
    si.dwFlags = STARTF_USESTDHANDLES
    
    si.hStdInput = if options.useStdin: hInRd else: getStdHandle(STD_INPUT_HANDLE)
    si.hStdOutput = if options.useStdout: hOutWr else: getStdHandle(STD_OUTPUT_HANDLE)
    
    if options.combineStdoutStderr:
        si.hStdError = si.hStdOutput
    else:
        si.hStdError = if options.useStderr: hErrWr else: getStdHandle(STD_ERROR_HANDLE)

    # 3. Create Process (ANSI)
    # We use 'var string' to ensure the buffer is alive and mutable-compatible
    var cmdLineStr = buildCmdLine(command, args)
    
    var cwdStr: string
    var cwdPtr: cstring = nil
    if options.cwd.len > 0:
        cwdStr = options.cwd
        cwdPtr = cwdStr.cstring
    
    var envStr: string
    var envPtr: cstring = nil
    if options.env.len > 0:
        envStr = buildEnvBlock(options.env)
        envPtr = envStr.cstring
    
    var pi: PROCESS_INFORMATION

    let success = createProcessA(
        nil,
        cmdLineStr.cstring, 
        nil, 
        nil,
        1, # bInheritHandles = TRUE
        0, # 0 for ANSI environment (CREATE_UNICODE_ENVIRONMENT is for W)
        envPtr, 
        cwdPtr,
        si,
        pi
    )

    # 4. Cleanup Handles in Parent
    closeHandleSafe(hInRd)
    closeHandleSafe(hOutWr)
    closeHandleSafe(hErrWr)

    if success == 0:
        closeHandleSafe(hInWr)
        closeHandleSafe(hOutRd)
        closeHandleSafe(hErrRd)
        let errCode = getLastError()
        raise newException(OSError, "Failed to create process: " & $errCode)

    # 5. Populate Result
    result.pid = pi.dwProcessId.int
    result.process_handle = pi.hProcess
    discard closeHandle(pi.hThread)

    if options.useStdin: result.stdin = hInWr
    if options.useStdout: result.stdout = hOutRd
    if options.useStderr and not options.combineStdoutStderr: result.stderr = hErrRd

proc isRunning*(subprocess: Subprocess): bool =
    ## Check if the subprocess is still running.
    ## 
    ## Uses GetExitCodeProcess to check process status.
    ## 
    ## Returns:
    ##   true if the process is still running, false otherwise
    if subprocess.process_handle == 0: return false
    var code: int32
    if getExitCodeProcess(subprocess.process_handle, code) != 0:
        if code == STILL_ACTIVE:
            return true
        else:
            subprocess.exit_code = code
            return false
    return false

proc wait*(subprocess: Subprocess): int =
    ## Wait for the subprocess to exit and return its exit code.
    ## 
    ## This is a blocking call using WaitForSingleObject.
    ## 
    ## Returns:
    ##   The exit code of the process
    if subprocess.process_handle == 0: return subprocess.exit_code
    discard waitForSingleObject(subprocess.process_handle, INFINITE)
    discard isRunning(subprocess)
    return subprocess.exit_code

proc write*(subprocess: Subprocess, data: string): int =
    ## Write data to subprocess stdin.
    ## 
    ## Handles partial writes automatically by retrying until all data is written.
    ## 
    ## Args:
    ##   data: The string data to write to stdin
    ## 
    ## Returns:
    ##   Number of bytes successfully written
    let h = subprocess.stdin
    if h == 0 or h == INVALID_HANDLE: return 0
    if data.len == 0: return 0
    
    var totalWritten: int32 = 0
    while totalWritten < data.len.int32:
        var written: int32 = 0
        let remaining = data.len.int32 - totalWritten
        if writeFile(h, unsafeAddr data[totalWritten], remaining, addr written, nil) == 0:
            return totalWritten.int  # Error, return what we wrote
        if written == 0:
            return totalWritten.int  # Pipe closed
        totalWritten += written
    return totalWritten.int

proc hasDataStdout*(subprocess: Subprocess): bool =
    ## Check if stdout has data available to read without blocking.
    ## 
    ## Uses PeekNamedPipe for non-blocking check.
    ## 
    ## Returns:
    ##   true if data is available, false otherwise
    let h = subprocess.stdout
    if h == 0 or h == INVALID_HANDLE: return false
    
    var bytesAvail: int32 = 0
    if peekNamedPipe(h, nil, 0, nil, addr bytesAvail, nil) != 0:
        return bytesAvail > 0
    return false

proc hasDataStderr*(subprocess: Subprocess): bool =
    ## Check if stderr has data available to read without blocking.
    ## 
    ## Uses PeekNamedPipe for non-blocking check.
    ## 
    ## Returns:
    ##   true if data is available, false otherwise
    let h = subprocess.stderr
    if h == 0 or h == INVALID_HANDLE: return false
    
    var bytesAvail: int32 = 0
    if peekNamedPipe(h, nil, 0, nil, addr bytesAvail, nil) != 0:
        return bytesAvail > 0
    return false

proc readStdout*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read from stdout with optional timeout.
    ## 
    ## Reads up to 4096 bytes. For reading all data, use readAllStdout().
    ## 
    ## Args:
    ##   timeoutMs: Timeout in milliseconds. -1 means blocking
    ## 
    ## Returns:
    ##   String with data read, or empty string if timeout/EOF/error
    ## 
    ## Note:
    ##   Uses polling with PeekNamedPipe since WaitForSingleObject
    ##   doesn't work for anonymous pipes on Windows.
    let h = subprocess.stdout
    if h == 0 or h == INVALID_HANDLE: return ""
    
    # If timeout is specified, wait for data availability using polling
    # Note: WaitForSingleObject doesn't work for anonymous pipes
    if timeoutMs >= 0:
        let startTime = epochTime()
        let timeoutSec = timeoutMs.float / 1000.0
        
        while true:
            var bytesAvail: int32 = 0
            if peekNamedPipe(h, nil, 0, nil, addr bytesAvail, nil) != 0:
                if bytesAvail > 0:
                    break  # Data is available, proceed to read
            
            let elapsed = epochTime() - startTime
            if elapsed >= timeoutSec:
                return ""  # Timeout expired
            
            sleep(10)  # Small sleep to avoid busy waiting
    
    var buffer = newString(4096)
    var readBytes: int32 = 0
    
    if readFile(h, addr buffer[0], 4096, addr readBytes, nil) != 0:
        if readBytes > 0:
            buffer.setLen(readBytes)
            return buffer
    # EOF or error
    return ""

proc readStderr*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read from stderr with optional timeout.
    ## 
    ## Reads up to 4096 bytes. For reading all data, use readAllStderr().
    ## 
    ## Args:
    ##   timeoutMs: Timeout in milliseconds. -1 means blocking
    ## 
    ## Returns:
    ##   String with data read, or empty string if timeout/EOF/error
    let h = subprocess.stderr
    if h == 0 or h == INVALID_HANDLE: return ""

    # If timeout is specified, wait for data availability using polling
    # Note: WaitForSingleObject doesn't work for anonymous pipes
    if timeoutMs >= 0:
        let startTime = epochTime()
        let timeoutSec = timeoutMs.float / 1000.0
        
        while true:
            var bytesAvail: int32 = 0
            if peekNamedPipe(h, nil, 0, nil, addr bytesAvail, nil) != 0:
                if bytesAvail > 0:
                    break  # Data is available, proceed to read
            
            let elapsed = epochTime() - startTime
            if elapsed >= timeoutSec:
                return ""  # Timeout expired
            
            sleep(10)  # Small sleep to avoid busy waiting
    
    var buffer = newString(4096)
    var readBytes: int32 = 0
    
    if readFile(h, addr buffer[0], 4096, addr readBytes, nil) != 0:
        if readBytes > 0:
            buffer.setLen(readBytes)
            return buffer
    # EOF or error
    return ""

proc readAllStdout*(subprocess: Subprocess, timeoutMs: int = -1): string =
    ## Read all available data from stdout.
    ## 
    ## Continues reading until no more data is available or timeout expires.
    ## 
    ## Args:
    ##   timeoutMs: Total timeout in milliseconds for the entire operation.
    ##     -1 means no timeout
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
    ##     -1 means no timeout
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

proc closeStdin*(subprocess: Subprocess) =
    ## Close the stdin pipe to the subprocess.
    ## 
    ## This signals EOF to the subprocess.
    var h = subprocess.stdin
    closeHandleSafe(h)
    subprocess.stdin = 0

proc terminate*(subprocess: Subprocess, graceful: bool = true) =
    ## Terminate the subprocess.
    ## 
    ## Note: Windows doesn't have graceful termination like POSIX SIGTERM.
    ## This always uses TerminateProcess regardless of the graceful parameter.
    ## 
    ## Args:
    ##   graceful: Ignored on Windows (kept for API compatibility)
    if subprocess.process_handle == 0: return
    if isRunning(subprocess):
        discard terminateProcess(subprocess.process_handle, 1)
    discard subprocess.wait()

proc close*(subprocess: Subprocess) =
    ## Close subprocess and clean up all resources.
    ## 
    ## Terminates the process if still running, then closes all handles.
    subprocess.terminate(graceful = false)
    
    var hIn = subprocess.stdin
    closeHandleSafe(hIn); subprocess.stdin = 0
    var hOut = subprocess.stdout
    closeHandleSafe(hOut); subprocess.stdout = 0
    var hErr = subprocess.stderr
    closeHandleSafe(hErr); subprocess.stderr = 0
    
    closeHandleSafe(subprocess.process_handle)
    subprocess.process_handle = 0
    subprocess.pid = 0
