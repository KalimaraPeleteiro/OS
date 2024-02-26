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


    cli
    hlt ; Interompe a CPU.


; ===== ERROS =====
; Aqui lidamos com eles.

floppy_error:
    mov si, msg_error_read_from_disk ; Mensagem simples de erro.
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


; ===== CRIANDO SETOR DE INICIALIZAÇÃO DE BOOT =====
; Um setor válido possui 512 bytes.
times 510-($-$$) db 0 ; Vamos preencher 510 com zeros...
dw 0AA55h ; E o último byte com a assinatura de validação.