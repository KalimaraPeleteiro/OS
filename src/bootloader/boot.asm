; Endereço em que esperamos que o código seja executado.
org 0x7c00

bits 16 ; Para retrocompatibilidade

; Código para fim de linha. Melhor escrever ENDL do que o hex o tempo todo.
%define ENDL 0x0D, 0x0A



; Configurando o sistema de arquivos FAT12 (São necessário alguns headers)
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
    jmp main ; Pulando para main.


; ===== Funções =====
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


main:
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Iniciando a Stack de Comandos depois do nosso SO, para não ter conflito.
    mov ss, ax
    mov sp, 0x7c00

    ; Passando a mensage e chamando a função.
    mov si, msg
    call print

    hlt ; Interompe a CPU.


.halt:
    jmp .halt


msg: db "Inicializando Sistema Operacional...", ENDL, 0

; ===== Criando um Setor de Inicialização de Boot =====
; Um setor válido possui 512 bytes.
times 510-($-$$) db 0 ; Vamos preencher 510 com zeros...
dw 0AA55h ; E o último byte com a assinatura de validação.