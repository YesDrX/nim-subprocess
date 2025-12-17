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
