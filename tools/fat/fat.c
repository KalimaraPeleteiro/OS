// Sistema FAT12 em C.
// Não está incluso no sistema ainda, criado apenas para entender como o processo funciona.
// Base para a implementação em Assembly.

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>  

// Definindo boolean.
typedef uint8_t bool;
#define true 1
#define false 0

// ===== STRUCTS =====

// Setor de Boot (com os Headers necessários).
typedef struct {
    uint8_t BootJumpInstruction[3];
    uint8_t OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    uint8_t DriveNumber;
    uint8_t _Reserved;
    uint8_t Signature;
    uint32_t VolumeId;
    uint8_t VolumeLabel[11];
    uint8_t SystemId[8];

} __attribute__((packed)) BootSector; // Necessário usar "packed" para o GCC não modificar nossa estrutura para otimização.

// Estrutura de Diretório. Todos os campos obrigatórios em um Sistema FAT12.
typedef struct {
    uint8_t Name[11];    // Apenas arquivos de, no máximo 11 letras de nome. Restrições do FAT12.
    uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AcessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;
} __attribute__((packed)) DirectoryEntry;


// ===== VARIÁVEIS GLOBAIS =====
BootSector globalBootSector;
uint8_t* globalFat = NULL;
DirectoryEntry* globalRootDirectory = NULL;
uint32_t globalRootDirectoryEnd;


// ===== FUNÇÕES =====

// Leitura do Primeiro Setor (Boot) do disco.
// fread necessita de:
// - O ponteiro indicando o primeiro bloco de memória a ser lido (&globalBootSector)
// - O tamanho a ser lido (sizeof)
// - A quantidade de itens a serem lidos
// - A localização de onde iremos ler os arquivos (disk);
// fread retorna o número de bytes lidos. Logo, retornamos true para valores maiores que 0 e false, caso contrário.
bool readBootSector(FILE* disk) {
    return fread(&globalBootSector, sizeof(globalBootSector), 1, disk) > 0;
}


// Lendo Setores em memória.
// fseek é utilizada para nos movermos em direção ao próximo setor (já que eles não são alinhados, necessariamente)
// e fread, já explorada, faz a leitura.
// Se algo de errado, a variável de retorno é alterada.
bool readSectors(FILE* disk, uint32_t lbaAdress, uint32_t numberOfSectors, void* bufferOut) {
    bool ok = true;
    ok = ok && (fseek(disk, lbaAdress * globalBootSector.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, globalBootSector.BytesPerSector, numberOfSectors, disk) == numberOfSectors);
    return ok;
}


// Lendo a FAT (File Allocation Table)
// A FAT mapeia os clusters aos setores, para localizarmos os arquivos.
bool readFat(FILE* disk) {
    // É necessário calcular a quantidade de de bytes a serem reservados.
    globalFat = (uint8_t*) malloc(globalBootSector.SectorsPerFat * globalBootSector.BytesPerSector);
    return readSectors(disk, globalBootSector.ReservedSectors, globalBootSector.SectorsPerFat, globalFat);
}


// Com a FAT mapeada, vamos para a Root.
// Calculamos o endereço da Root usando as informações de boot, bem como o seu tamanho e número de setores.
// A memória é alocada e os setores são lidos.
bool readRootDirectory(FILE * disk) {
    uint32_t lbaAdress = globalBootSector.ReservedSectors + globalBootSector.SectorsPerFat * globalBootSector.FatCount;
    uint32_t size = sizeof(DirectoryEntry) * globalBootSector.DirEntryCount;
    uint32_t sectors = (size / globalBootSector.BytesPerSector);

    // Caso o tamanho não seja perfeito. Por exemplo, se tivermos um tamanho de 14.2 setores.
    // Nesse caso, alocamos 15.
    if (size % globalBootSector.BytesPerSector > 0) { 
        sectors ++;
    }

    globalRootDirectoryEnd = lbaAdress + sectors; 
    globalRootDirectory = (DirectoryEntry *) malloc(sectors * globalBootSector.BytesPerSector);
    return readSectors(disk, lbaAdress, sectors, globalRootDirectory);
}


// Função de busca de arquivo.
// A função nativa memcmp (memory comparison) compara os bytes de arquivos.
// Comparamos apenas o nome e os primeiros 11 caracteres, já que arquivos só possuem, no máximo,
// este tamanho em FAT12.
// Caso encontrado, o endereço do arquivo é retornado.
DirectoryEntry* findFile(const char* name) {
    for (uint32_t i = 0; i < globalBootSector.DirEntryCount; i ++) {
        if (memcmp(name, globalRootDirectory[i].Name, 11) == 0) {
            return &globalRootDirectory[i];
        }
    }

    return NULL;
}


// Leitura de Arquivo
// Um arquivo pode estar disposto em vários clusters, então temos que buscar em vários desde a sua entrada.
// Começamos calculando o endereço (lbaAdress) do primeiro cluster.
// A partir daí, lemos os setores deste cluster com a File Allocation Table e a readSectors.

// Depois, criamos o fatIndex para descobrir se o próximo cluster é ímpar ou par.
// Caso seja par, queremos os primeiros 12 bits.
// Caso seja ímpar, os últimos 12 bits.

// Caso o cluster seja de endereço 0x0FF8 é sinal que chegamos ao fim do arquivo e paramos.
// Endereços FF8 para cima (FF9, FFA, FFD...) são bits de fim de arquivo em FAT12.
bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer) {
    bool ok = true;
    uint16_t currentCluster = fileEntry -> FirstClusterLow;

    do {
        uint32_t lbaAdress = globalRootDirectoryEnd + (currentCluster - 2) * globalBootSector.SectorsPerCluster;
        ok = ok && readSectors(disk, lbaAdress, globalBootSector.SectorsPerCluster, outputBuffer);
        outputBuffer += globalBootSector.SectorsPerCluster * globalBootSector.BytesPerSector;

        uint32_t fatIndex = currentCluster * 3 / 2;
        if (currentCluster % 2 == 0) {
            currentCluster = (*(uint16_t*)(globalFat + fatIndex)) & 0x0FFF;
        } else {
            currentCluster = (*(uint16_t*)(globalFat + fatIndex)) >> 4;
        }
    } while (ok && currentCluster < 0x0FF8);

    return ok;
}


// ===== FLUXO PRINCIPAL =====
int main(int argc, char** argv)
{
    if (argc < 3) {  // Verificando sintaxe.
        printf("Você inicou o programa incorretamente.\n");
        printf("Sintaxe correta: %s <imagem de disco> <arquivo>\n", argv[0]);
        return -1;
    }

    // Começamos abrindo a imagem e lendo o disco.
    FILE* disk = fopen(argv[1], "rb");
    if (!disk) {
        fprintf(stderr, "Não é possível ler imagem de disco %s!\n", argv[1]);
        return -1;
    } 

    // O próximo passo é ler o primeiro setor (com as configurações necessárias para o FAT12)
    if (!readBootSector(disk)) {
        fprintf(stderr, "Não é possível ler setor de boot!\n");
        return -2;
    }

    // Em seguida, usamos o BootSector para ler a File Allocation Table.
    if (!readFat(disk)) {
        fprintf(stderr, "Não é possível ler FAT!\n");
        free(globalFat);
        return -3;
    } 

    // Com a FAT pronta, podemos ler a ROOT.
    if (!readRootDirectory(disk)) {
        fprintf(stderr, "Não é possível ler a Root!\n");
        free(globalFat);
        free(globalRootDirectory);
        return -4;
    }

    // Finalizando a inicialização do sistem FAT12, podemos começar a buscar pelo arquivo.
    DirectoryEntry* fileEntry = findFile(argv[2]);
    if (!fileEntry) {
        fprintf(stderr, "Não é possível encontrar o arquivo %s!\n", argv[2]);
        free(globalFat);
        free(globalRootDirectory);
        return -5;
    }

    // Com o arquivo em mãos, basta alocar a memória e ler o conteúdo.
    uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + globalBootSector.BytesPerSector);
    if (!readFile(fileEntry, disk, buffer)) {
        fprintf(stderr, "Não é possível ler  o arquivo %s!\n", argv[2]);
        free(globalFat);
        free(globalRootDirectory);
        free(buffer);
        return -5;
    }

    // E no caso de TXT (nosso alvo de teste), basta printar o conteúdo.
    for (size_t i = 0; i < fileEntry->Size; i++) {
        if (isprint(buffer[i])) {
            fputc(buffer[i], stdout);
        } else {
            printf("<%02x>", buffer[i]);
        }
    }
    printf("\n");

    free(buffer);
    free(globalFat);
    free(globalRootDirectory);
    return 0;
}
