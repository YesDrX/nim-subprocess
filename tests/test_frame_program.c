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
    