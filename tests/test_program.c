#include <stdio.h>

int add(int a, int b) {
    return a + b;
}

int main() {
    int x = 5;
    int y = 10;
    int result = add(x, y);
    
    printf("x = %d\n", x);
    printf("y = %d\n", y);
    printf("result = %d\n", result);
    
    // Create a simple array for debugging
    int numbers[5] = {1, 2, 3, 4, 5};
    int sum = 0;
    for (int i = 0; i < 5; i++) {
        sum += numbers[i];
    }
    printf("sum = %d\n", sum);
    
    return 0;
}
