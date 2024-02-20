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