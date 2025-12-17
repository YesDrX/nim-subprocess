import unittest
import subprocess
import std/os

# Test program that generates byte frame protocol messages
# Message format: [4-byte length][newline][payload]
const testProgramSource =
  when defined(windows):
    """
    #include <stdio.h>
    #include <string.h>
    #include <windows.h>
    #include <io.h>
    #include <fcntl.h>
    
    int main() {
        // Set stdout to binary mode to prevent text translation
        setmode(fileno(stdout), O_BINARY);
        
        // Message 1: Length 5 + payload "Hello"
        char msg1[] = "Hello";
        int len1 = strlen(msg1);
        
        // Write the length as 4 bytes (little-endian)
        unsigned char len_bytes[4];
        len_bytes[0] = len1 & 0xFF;
        len_bytes[1] = (len1 >> 8) & 0xFF;
        len_bytes[2] = (len1 >> 16) & 0xFF;
        len_bytes[3] = (len1 >> 24) & 0xFF;
        
        fwrite(len_bytes, 1, 4, stdout);
        fputc('\n', stdout);
        fwrite(msg1, 1, len1, stdout);
        fflush(stdout);
        
        // Small delay to simulate real-world timing
        Sleep(100); // 100ms
        
        // Message 2: Length 7 + payload "World!"
        char msg2[] = "World!";
        int len2 = strlen(msg2);
        
        // Write the length as 4 bytes (little-endian)
        len_bytes[0] = len2 & 0xFF;
        len_bytes[1] = (len2 >> 8) & 0xFF;
        len_bytes[2] = (len2 >> 16) & 0xFF;
        len_bytes[3] = (len2 >> 24) & 0xFF;
        
        fwrite(len_bytes, 1, 4, stdout);
        fputc('\n', stdout);
        fwrite(msg2, 1, len2, stdout);
        fflush(stdout);
        
        return 0;
    }
    """
  else:
    """
    #include <stdio.h>
    #include <string.h>
    #include <unistd.h>
    
    int main() {
        // Message 1: Length 5 + payload "Hello"
        char msg1[] = "Hello";
        int len1 = strlen(msg1);
        fwrite(&len1, sizeof(int), 1, stdout);
        fputc('\n', stdout);
        fwrite(msg1, 1, len1, stdout);
        fflush(stdout);
        
        // Small delay to simulate real-world timing
        usleep(100000); // 100ms
        
        // Message 2: Length 7 + payload "World!"
        char msg2[] = "World!";
        int len2 = strlen(msg2);
        fwrite(&len2, sizeof(int), 1, stdout);
        fputc('\n', stdout);
        fwrite(msg2, 1, len2, stdout);
        fflush(stdout);
        
        return 0;
    }
    """

suite "Byte Frame Protocol Tests":
  
  setup:
    # Compile the test program
    const testProgramBaseName = "test_frame_program"
    const testSourcePath = currentSourcePath().parentDir() / "test_frame_program.c"
    
    # Write the test program source
    writeFile(testSourcePath, testProgramSource)
    
    # Compile it
    when defined(windows):
      const exeExt = ".exe"
    else:
      const exeExt = ""
    
    try:
      discard execShellCmd("gcc " & testSourcePath & " -o " & testProgramBaseName & exeExt)
    except:
      skip()
  
  teardown:
    # Clean up test files
    const testProgramBaseName = "test_frame_program"
    const testSourcePath = currentSourcePath().parentDir() / "test_frame_program.c"
    
    when defined(windows):
      const exeExt = ".exe"
    else:
      const exeExt = ""
    
    const finalProgramPath = testProgramBaseName & exeExt
    
    # if fileExists(testSourcePath):
    #   removeFile(testSourcePath)
    if fileExists(finalProgramPath):
      removeFile(finalProgramPath)
  
  test "Read exact byte counts for frame protocol":
    when defined(windows):
      const executablePath = "test_frame_program.exe"
    else:
      const executablePath = "./test_frame_program"
    
    # Skip if test program doesn't exist
    if not fileExists(executablePath):
      skip()
    
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess(executablePath, [], opts)
    
    # Read the 4-byte length field
    let lengthBytes = process.readStdout(numBytesToRead = 4)
    check lengthBytes.len == 4
    
    # Convert bytes to integer (assuming little-endian)
    var msgLength: int
    copyMem(addr msgLength, lengthBytes[0].unsafeAddr, 4)
    
    # Read the newline
    let newline = process.readStdout(numBytesToRead = 1)
    check newline == "\n"
    
    # Read the exact message payload
    let payload = process.readStdout(numBytesToRead = msgLength)
    check payload.len == msgLength
    check payload == "Hello"
    
    # Read the second message
    let lengthBytes2 = process.readStdout(numBytesToRead = 4)
    check lengthBytes2.len == 4
    
    var msgLength2: int
    copyMem(addr msgLength2, lengthBytes2[0].unsafeAddr, 4)
    
    let newline2 = process.readStdout(numBytesToRead = 1)
    check newline2 == "\n"
    
    let payload2 = process.readStdout(numBytesToRead = msgLength2)
    check payload2.len == msgLength2
    check payload2 == "World!"
    
    check process.wait() == 0
    process.close()
  
  test "Backward compatibility - default parameters":
    # Ensure the new implementation is backward compatible
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess("echo", ["test"], opts)
    
    # Call with default parameters (should work exactly like before)
    let output = process.readStdout()
    check output.len > 0
    
    check process.wait() == 0
    process.close()
  
  test "Read specific byte counts":
    var opts = SubprocessOptions(useStdout: true)
    let process = startSubprocess("echo", ["Hello World"], opts)
    
    # Give it time to produce output
    sleep(100)
    
    # Read exactly 5 bytes
    let firstChunk = process.readStdout(numBytesToRead = 5)
    check firstChunk.len == 5
    # Note: echo adds a newline, so first 5 bytes would be "Hello"
    
    process.close()