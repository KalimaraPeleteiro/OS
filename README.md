<h1>Sistema Operacional</h1>

Tendo como base a [série e projeto passo-a-passo](https://github.com/nanobyte-dev/nanobyte_os) de [Nanobyte](https://github.com/nanobyte-dev), esse projeto detalha a criação gradual de um sistema operacional simples, de sua estrutura mais básica até elementos mais complexos.

No momento, a imagem do Sistema Operacional é formada em apenas **1.44MB**. Esse era um tamanho popular em sistemas do passado, por ser a capacidade máxima da maioria dos disquetes. Esse é um dos fatores que mostra como o nosso sistema é simples, ao menos comparado com os modernos, como Linux e Windows.

<h3> Como o Sistema Funciona? </h3>

Para entender isso, é necessário saber *como um computador liga?*. O passo-a-passo é o abaixo.

1. A BIOS é copiada do HD (ou SSD) para a RAM.
2. A BIOS é executada (Inicializa o Hardware e faz alguns testes)
3. BIOS procura pelo Sistema Operacional
4. BIOS executa o Sistema
5. Sistema operacional inicia.

Tudo que devemos nos preocupar, aqui neste processo, são com os passos 3, 4 e 5. *Como a BIOS acha o Sistema Operacional*? Existem dois métodos tradicionais, e o que utilizamos aqui é o chamado **LegacyBoot**.
- A BIOS carrega o primeiro setor de dispositivos bootáveis em memória (0X7C00)
- Ela procura pela assinatura 0xAA55
- Se encontrado, executa o código.

É por isso que a **primeira imagem** de nosso Sistema foi simplesmente uma imagem válida de inicialização.
```
; Endereço em que esperamos que o código seja executado.
org 0x7c00

bits 16 ; Para retrocompatibilidade


main:
    hlt ; Interompe a CPU.


.halt:
    jmp .halt

; ===== Criando um Setor de Inicialização de Boot =====
; Um setor válido possui 512 bytes.
times 510-($-$$) db 0 ; Vamos preencher 510 com zeros...
dw 0AA55h ; E o último byte com a assinatura de validação.
```

Mas, como demonstrado nos comentários, um Setor Válido de Inicialização de Boot deve possuir 512 Bytes. Isso não chega nem próximo dos 1.44MB do nosso sistema, então o Sistema Operacional não deve ser concentrado em um arquivo. Por isso, ele é dividido em dois elementos:
- O Bootloader (a seção de 512 Bytes que inicia e chama a próxima seção)
- Kernel (O resto do sistema)

Mas, para que o Bootloader possa encontrar o nosso kernel (``kernel.bin``) e executar o resto do sistema, é necessário um **sistema de arquivos**. É por isso que no bootloader você encontrará as rotinas de leitura de disco, para nosso sistemas de arquivos e as configurações do sistema FAT12 (hoje usado apenas em torradeiras e embutidos bem simples), um sistema extremamente simples de arquivos, para que possamos localizar e executar o Kernel.

Apenas esse processo já é suficiente para preencher todos os 512 Bytes do bootloader quase que por completo, o que mostra quão pouco 512 Bytes são.

Agora com o Kernel sendo executado em outra seção, podemos expandir nosso Sistema Operacional com novas features...