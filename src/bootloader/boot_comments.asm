; BOOTLOADER
; - Primeiro software a ser chamado.
; - Responsável por carregar o resto do sistema operacional (kernel) na RAM.



; Endereço em que esperamos que o código seja executado.
org 0x7c00

bits 16 ; Para retrocompatibilidade

; Código para fim de linha. Melhor escrever ENDL do que o hex o tempo todo.
%define ENDL 0x0D, 0x0A


; ===== SISTEMA DE ARQUIVOS =====
; Configurando o sistema de arquivos FAT12 (São necessários alguns headers)
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 
bdb_media_descriptor_type:  db 0F0h                 
bdb_sectors_per_fat:        dw 9                    
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                    
                            db 0                    
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   
ebr_volume_label:           db 'NANOBYTE OS'        
ebr_system_id:              db 'FAT12   '           


start:
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Iniciando a Stack de Comandos depois do nosso SO, para não ter conflito.
    mov ss, ax
    mov sp, 0x7c00

    ; Algumas bios podem inicializar em 07C0:0000 ao invés de 0000:7C00. Vamos nos garantir que isso não aconteça.

    ; O registrador extra segment (es) pode armazenar uma área específica na memória.
    push es
    push word .after ; Vamos salvar o endereço dos próximos comandos, para evitar conflitos.
    retf ; retf faz o salto necessário.

.after:

    ; Lendo algo do disco.
    mov [ebr_drive_number], dl

    ;mov ax, 1       ; LBA = 1, vamos ler o segundo setor.
    ;mov cl, 1       ; 1 setor para ler
    ;mov bx, 0x7E00  ; Leitura será feita no endereço logo após do bootloader
    ;call disk_read

    ; Passando a mensage e chamando a função.
    mov si, msg_initializing
    call print


    ; Vamos ler esses valores da BIOS ao invés do disco, para caso de problemas de corrupção de disco
    push es
    mov ah, 08h     ; Obtendo informações 
    int 13h         ; da BIOS sobre o disco
    jc floppy_error ; Caso de erro.
    pop es

    and cl, 0x3F
    xor ch, ch
    mov [bdb_sectors_per_track], cx     ; contagem de setores

    inc dh
    mov [bdb_heads], dh     ; contagem de heads


    ; -- Sistema FAT --

    ; Os registradores bh (Base High) e dx (Data Register) são usados para armazenar dados temporários,
    ; principalmente em operações de multiplicação e divisão. Nós zeramos esses valores antes das operações
    ; para garantir que não teremos resultados de operações anteriores atrapalhando os cálculos.

    ; Calculando endereço da Root. Fórmula: espaço reservado + (N° de File Allocation Tables * Setores por FAT)
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh                          ; bh = 0
    mul bx                              ; ax = (N° de File Allocation Tables * Setores por FAT)
    add ax, [bdb_reserved_sectors]      ; Somando com o espaço reservado, temos o LBA da Root.

    ; Agora, calculando o tamanho do diretório Root. Fórmula: (32 * número de entradas)/bytes por setor.
    mov ax, [bdb_dir_entries_count]     ; Passando número de entradas.
    shl ax, 5                           ; Número de entradas * 32
    xor dx, dx                          ; dx = 0
    div word [bdb_bytes_per_sector]     ; Número de setores.

    test dx, dx                         ; Se o resultado não for inteiro (como 14.2 setores)
    jz .root_dir_after
    inc ax                              ; Vamos acresecentar 1 setor a mais.

.root_dir_after:

    ; Lendo a Root (Setando os parâmetros para chamar disk_read)
    mov cl, al                  ; Número de setores
    pop ax                      ; ax = LBA da Root
    mov dl, [ebr_drive_number]  ; dl = Número de Drive
    mov bx, buffer              ; es:bx = buffer
    call disk_read

    ; -- Buscando pelo Kernel --

    ; Agora que a root está carregada, devemos buscar pelo Kernel.bin no sistema de arquivos para carregar o resto do
    ; sistema operacional.
    xor bx, bx      ; Vamos usar bx de contador, então vamos zerá-lo.
    mov di, buffer  ; E di para apontar para o primeito elemento do diretório (nome)

.search_kernel:
    mov si, file_kernel_bin ; Nosso Alvo
    mov cx, 11              ; Só precisamos comparar os primeiros 11 caracteres (porque é o máximo em FAT12)
    push di                 ; Salvando valor do nome atual

    ; O loop irá continuar enquanto os bytes forem iguais e irá se repetir até cx (11) vezes.
    repe cmpsb              ; repe = repeat while equal | cmpsb = compare string bytes

    pop di                  ; Restaurando valor.

    je .found_kernel        ; Caso encontrado, vamos para o próximo passo.

    ; Senão...
    add di, 32                      ; Passe para o próximo diretório (32 Bytes cada um)
    inc bx                          ; Aumente nosso contador
    cmp bx, [bdb_dir_entries_count] ; E veja se não já buscamos todos os diretórios.
    jl .search_kernel               ; Se não tivermos buscado todos, repita o processo.

    jmp kernel_not_found_error      ; Caso contrário, mensagem de erro.
    
.found_kernel:
    
    ; Com di tendo o endereço que desejamos, podemos extraí-lo.
    mov ax, [di + 26]           ; Queremos apenas o primeiro cluster (primeiros 26 bytes)
    mov [kernel_cluster], ax    ; Armazenamos em kernel_cluster

    ; Com o Kernel encontrado, vamos carregar as File Allocation Tables. Mesmo processo,
    ; basta definir os parâmetros e chamar disk_read.
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; Com a File Allocation Table, podemos ler o Kernel
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:

    ; Lendo os clusters do kernel.

    ; Passand para o próximo cluster.
    mov ax, [kernel_cluster]
    add ax, 31                  ; Somar 31 funciona, por enquanto.

    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read              ; Lendo cluster.

    add bx, [bdb_bytes_per_sector]


    ; Calculando o endereço do próximo cluster. Esse processo já foi feito em readFile em C

    ; fatIndex = (clusterAtual * 3) / 2
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, buffer
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even 

.odd:   ; Cluster ìmpar
    shr ax, 4
    jmp .next_cluster_after

.even:  ; Cluster par
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8              ; Se o valor final foir maior que FF8, chegamos ao fim
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop       ; Caso contrário, continue lendo.

.read_finish:

    ; Finalizamos pulando para o Kernel
    mov dl, [ebr_drive_number]

    mov ax, KERNEL_LOAD_SEGMENT
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot

    cli
    hlt ; Interompe a CPU.


; ===== ERROS =====
; Aqui lidamos com eles.

floppy_error:
    mov si, msg_error_read_from_disk ; Mensagem simples de erro.
    call print
    jmp wait_key_and_reboot ; Em caso de erro, tentamos o reboot.

kernel_not_found_error:
    mov si, msg_error_kernel_not_found ; Mensagem simples de erro.
    call print
    jmp wait_key_and_reboot ; Em caso de erro, tentamos o reboot.

wait_key_and_reboot:
    mov ah, 0
    int 16h             ; Esperando o usuário clicar em qualquer tecla.
    jmp 0FFFFh:0        ; Pulando para o início da BIOS para reboot.
    hlt

.halt:
    cli
    hlt


; ===== CÓDIGO DE MENSAGEM INICIAL =====
; Printa algo na tela.
print:
    ; Salvando o conteúdo dos registradores na pilha para manter os estados depois.
    push si ; Usando como índice em loadsb.
    push ax ; Usando para configurar a interupção com ah
    push bx ; Usando para configurar a interrupção com bh

.loop:
    lodsb ;Loop lê os bytes da memória e exibe na tela.
    or al, al   ; Quando o próximo caractere for nulo, pare o loop.
    jz .done

    ; Definindo o serviço de interrupção.
    mov ah, 0x0e
    mov bh, 0
    int 0x10 ;Use a interrupção para imprimir o conteúdo na tela.

    jmp .loop

.done:
    ; Restaurando os valores originais dos registradores.
    pop ax
    pop bx
    pop si
    ret


; ===== IMPLEMENTANDO ROTINAS DE DISCO =====
; Funções necessárias para a leitura de dados do disco.

; --- Convertendo LBA para CHS ---
; LBA é um método moderno para acessar dados em disco.
; O disco é tratado como uma sequência linear de setores.
; CHS é o método utilizado em discos antigos.
; Discos antigos possuíam cilindros, setores e cabeças.

; Essa função converte endereços LBA para CHS para garantir retrocompatibilidade com sistemas legado.

; As fórmulas para conversão são:
; Cilindro = LBA/Cabeças por Cilindro * Setores por Trilha
; Cabeça = LBA % (Cabeças por Cilindro * Setores por Trilha) / Setores por Trilha
; Setor = LBA % (Cabeças por Cilindro * Setores por Trilha) % Setores por Trilha + 1

; Parâmetros
; - ax: Endereço LBA

; Retornos
; - cx [bits 0-5]: Número de Setor
; - cx [bits 6-15]: Cilindro utilizado
; - dh: Cabeça do disco

lba_to_chs:

    ; Salvando o valor dos registradores antes de começar as operações.
    push ax
    push dx


    xor dx, dx  ; dx = 0

    ; Divisões armazenam o quociente em parte alta (ax) e o resto e parte baixa (dx)
    ; Usamos word para sinalizar a divisão de 16 bits.
    div word [bdb_sectors_per_track]    ; ax = LBA/SetoresPorTrilha
                                        ; dx = LBA % Setores por Trilha

    inc dx  ; Somando 1 a dx para conseguir o setor.
    mov cx, dx ; cx agora tem o setor.

    xor dx, dx ; Resetando dx = 0
    div word [bdb_heads] ; ax = LBA/Setores por Trilha / Cabeças = cilindro
                         ; dx = LBA/Setores por Trilha % Cabeças = cabeça

    mov dh, dl  ; dh recebe o valor de cabeça.
    mov ch, al  ; ch recebe o cilindro (somente os últimos 8 bits)
    shl ah, 6   ; Deslocando 6 bits (já que roubamos 2) para fica tudo em cx.
    or cl, ah   ; passando 2 bits de cilindro para cl (precisamos de 10)


    ; Restaurando o valor dos registradores e retornando os valores da função.
    pop ax
    mov dl, al
    pop ax
    
    ret


; --- Lendo Setores de um Disco ---
; Parâmetros
; - ax: Endereço LBA
; - cl: Número de Setores
; - dl: Número de driver
; - es:bx: Endereço de memória no qual iremos armazenar os dados.

disk_read:

    ; Salvando Registradores
    push ax                             
    push bx
    push cx
    push dx
    push di
    
    ; Salvando cx (número de setores) antes da função
    push cx

    call lba_to_chs ; Convertendo
    pop ax

    mov ah, 02h
    mov di, 3 ;Contagem de tentativas.

; Discos Floppy não são muito confiáveis e podem gerar na leitura. Assim, tentamos a leitura 
; 03 vezes antes de declarar um erro.
.retry:
    pusha           ; Salvando Registradores, porque a BIOS pode modificar
    stc             ; Flag de Carry, que algumas BIOS não setam.
    int 13h         ; Leitura
    jnc .done       ; Caso sem erros, vai para o fim (.done)

    popa            ; Retorna os registradores
    call disk_reset ; Restaura o estado do controlador de disco com disk_reset

    dec di          ; Diminui o loop em 1.
    test di, di
    jnz .retry

.fail:
    jmp floppy_error ; Caso de falha, vá para a seção de erros.

.done:
    popa

    ; Restaurando Registradores
    pop di
    pop dx
    pop cx
    pop bx
    pop ax

    ret


; --- Resetando o Controlador de Disco ---

; Após inicializar os dispositivos de disco, é necessário uma função que redefina os estados
; dos controladores para o seu modo básico, para operações futuras.
; Basicamente, estamos devolvendo tudo ao seu lugar após usar os itens desejados.

; Parâmetros
; - dl: Número de Driver
disk_reset:
    pusha ; Salvando Registradores
    mov ah, 0 ; Preparando solicitação
    stc ; Flag de Carry (algumas bios não fazem)
    int 13h ; Solicitando redefinição do disco.
    jc floppy_error ; Em caso de erro...
    popa ; Retornando registradores
    ret



msg_initializing: db "Inicializando Sistema Operacional...", ENDL, 0
msg_error_read_from_disk: db "Falha na Leitura de Disco!", ENDL, 0
msg_error_kernel_not_found: db "Não foi possível encontrar KERNEL.BIN.", ENDL, 0
file_kernel_bin: db 'KERNEL  BIN'
kernel_cluster: dw 0

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0


; ===== CRIANDO SETOR DE INICIALIZAÇÃO DE BOOT =====
; Um setor válido possui 512 bytes.
times 510-($-$$) db 0 ; Vamos preencher 510 com zeros...
dw 0AA55h ; E o último byte com a assinatura de validação.

buffer: