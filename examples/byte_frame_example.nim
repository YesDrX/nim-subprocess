import subprocess
import std/[strutils, os]

# Example showing how to use the byte frame protocol functionality
# This example assumes a subprocess that outputs data in a frame format:
# [4-byte message length][newline][message payload]

proc readFrameProtocol(process: Subprocess): string =
  # Read exactly 4 bytes for the message length
  let lengthBytes = process.readStdout(numBytesToRead = 4)
  if lengthBytes.len != 4:
    return "" # Not enough data
  
  # Convert the 4 bytes to an integer (little-endian)
  var msgLength: int
  copyMem(addr msgLength, lengthBytes[0].unsafeAddr, 4)
  
  # Read the newline separator
  let newline = process.readStdout(numBytesToRead = 1)
  if newline != "\n":
    return "" # Invalid format
  
  # Read exactly msgLength bytes for the payload
  let payload = process.readStdout(numBytesToRead = msgLength)
  if payload.len != msgLength:
    return "" # Incomplete payload
  
  return payload

# Example usage
when isMainModule:
  echo "Byte Frame Protocol Example"
  echo "==========================="
  
  # This would work with a real subprocess that outputs framed data
  # For demonstration, we'll show the API usage:
  
  # var opts = SubprocessOptions(useStdout: true)
  # let process = startSubprocess("your_frame_protocol_app", [], opts)
  #
  # while process.isRunning() or not process.isStdoutEof():
  #   let frame = readFrameProtocol(process)
  #   if frame.len > 0:
  #     echo "Received frame: ", frame
  #   else:
  #     # Small delay to prevent busy looping
  #     sleep(10)
  #
  # process.close()
  
  echo "API Usage Examples:"
  echo "1. Read exactly N bytes: process.readStdout(numBytesToRead = 10)"
  echo "2. Read with timeout: process.readStdout(numBytesToRead = 10, timeoutMs = 1000)"
  echo "3. Backward compatible: process.readStdout() # Same as before"
  echo "4. With timeout only: process.readStdout(timeoutMs = 500)"