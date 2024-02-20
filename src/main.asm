; Endereço em que esperamos que o código seja executado.
org 0x7c00

bits 16 ; Para retrocompatibilidade

%define ENDL 0x0D, 0x0A

start:
    jmp main


; Printa algo na tela.
print:
    push si
    push ax
    push bx

.loop:
    lodsb
    or al, al
    jz .done

    mov ah, 0x0e
    mov bh, 0
    int 0x10

    jmp .loop

.done:
    pop ax
    pop bx
    pop si
    ret

main:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov ss, ax
    mov sp, 0x7c00

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