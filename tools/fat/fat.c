#include <stdio.h>

int main(int argc, char** argv)
{
    if (argc < 3) {
        printf("Você inicou o programa incorretamente.\n");
        printf("Sintaxe correta: %s <imagem de disco> <arquivo>\n", argv[0]);
        return -1;
    }

    return 0;
}
