; Endereço em que esperamos que o código seja executado.
org 0x7c00

bits 16 ; Para retrocompatibilidade

; Código para fim de linha. Melhor escrever ENDL do que o hex o tempo todo.
%define ENDL 0x0D, 0x0A

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