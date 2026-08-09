; Naive backtracking: first empty cell, digits 1-9 in order.
;
; x86-64 port of impl/c/naive.c. Validity is a plain row/col/box scan over
; the 81-byte grid; no candidate masks, no heuristics. libc is used for
; I/O, parsing and timing only; the solver itself is hand-written assembly.

%define MAXP 100000                 ; max puzzles held in static storage

global main
extern fgets, strtol, clock_gettime, fwrite, fprintf
extern stdin, stdout, stderr

; copy 81 bytes: three 32-byte VEX loads/stores (last one overlaps).
%macro COPY81 2                     ; %1 = dst reg, %2 = src reg
    vmovdqu ymm0, [%2]
    vmovdqu ymm1, [%2 + 32]
    vmovdqu ymm2, [%2 + 49]
    vmovdqu [%1], ymm0
    vmovdqu [%1 + 32], ymm1
    vmovdqu [%1 + 49], ymm2
%endmacro

; Row/col/box scan for one candidate digit -- the C valid() inlined.
; In:  r8  = &g[row start], r9 = &g[col], r10 = &g[box start],
;      xmm0 = digit broadcast to 16 bytes, r12b = digit.
; Out: falls through when the digit is placeable, jumps to %1 on conflict.
; Clobbers eax/xmm1. Row and box are one 16-byte compare each (the loads
; run up to 7 bytes past the grid, always into the next .bss object).
%macro CELL_VALID 1                 ; %1 = conflict label
    vpcmpeqb xmm1, xmm0, [r8]       ; row: cells +0..+8
    vpmovmskb eax, xmm1
    test    eax, 0x1FF
    jnz     %1
    vpcmpeqb xmm1, xmm0, [r10]      ; box: cells +0..+2 and +9..+11
    vpmovmskb eax, xmm1
    test    eax, 0x0E07
    jnz     %1
    cmp     [r10 + 18], r12b        ; box: cells +18..+20
    je      %1
    cmp     [r10 + 19], r12b
    je      %1
    cmp     [r10 + 20], r12b
    je      %1
%assign %%k 0
%rep 9
    cmp     [r9 + %%k], r12b        ; column, stride 9
    je      %1
%assign %%k %%k + 9
%endrep
%endmacro

section .bss
align 32
grids:   resb MAXP * 81             ; parsed puzzles, one digit per byte
sols:    resb MAXP * 81             ; solved (or partially solved) grids
okbuf:   resb MAXP
alignb 32
RS:      resb 81                    ; index of first cell in the row
CC:      resb 81                    ; column
BS:      resb 81                    ; index of top-left cell of the box

section .rodata
fmt_ns:  db "ns=%lu", 10, 0
uns_str: db "UNSOLVED", 10

section .text

; ---------------------------------------------------------------------
; init_tables: RS[i], CC[i], BS[i]. Startup only, plain div is fine.
; ---------------------------------------------------------------------
init_tables:
    xor     r8d, r8d                ; i
.i_loop:
    mov     eax, r8d
    xor     edx, edx
    mov     ecx, 9
    div     ecx                     ; eax = r, edx = c
    mov     r9d, eax                ; r
    mov     r10d, edx               ; c
    lea     eax, [r9 + r9*8]        ; r*9
    mov     [RS + r8], al
    mov     [CC + r8], r10b
    mov     eax, r9d
    xor     edx, edx
    mov     ecx, 3
    div     ecx                     ; eax = r/3
    lea     r11d, [rax + rax*2]     ; (r/3)*3
    lea     r11d, [r11 + r11*8]     ; (r/3)*27
    mov     eax, r10d
    xor     edx, edx
    div     ecx                     ; eax = c/3
    lea     eax, [rax + rax*2]      ; (c/3)*3
    add     eax, r11d
    mov     [BS + r8], al
    inc     r8d
    cmp     r8d, 81
    jb      .i_loop
    ret

; ---------------------------------------------------------------------
; bool bt(uint8_t *g rdi, uint32_t start esi)
; ---------------------------------------------------------------------
bt:
    push    rbx
    push    rbp
    push    r12
    mov     rbx, rdi                ; g
    mov     ebp, esi                ; pos
.scan:
    cmp     ebp, 81
    jae     .full
    cmp     byte [rbx + rbp], 0
    je      .found
    inc     ebp
    jmp     .scan
.full:
    mov     eax, 1
    jmp     .ret
.found:                             ; unit pointers are the same for all digits
    movzx   eax, byte [RS + rbp]
    lea     r8, [rbx + rax]
    movzx   eax, byte [CC + rbp]
    lea     r9, [rbx + rax]
    movzx   eax, byte [BS + rbp]
    lea     r10, [rbx + rax]
    mov     r12d, 1                 ; d
.d_loop:
    vmovd   xmm0, r12d
    vpbroadcastb xmm0, xmm0
    CELL_VALID .d_next
    mov     [rbx + rbp], r12b
    mov     rdi, rbx
    lea     esi, [rbp + 1]
    call    bt
    test    eax, eax
    jnz     .ret
    movzx   eax, byte [RS + rbp]    ; recompute: the callee clobbered r8-r10
    lea     r8, [rbx + rax]
    movzx   eax, byte [CC + rbp]
    lea     r9, [rbx + rax]
    movzx   eax, byte [BS + rbp]
    lea     r10, [rbx + rax]
.d_next:
    inc     r12d
    cmp     r12d, 9
    jbe     .d_loop
    mov     byte [rbx + rbp], 0
    xor     eax, eax
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; bool solve(uint8_t *g rdi) -- rejects inconsistent clues, then searches.
; ---------------------------------------------------------------------
solve:
    push    rbx
    push    rbp
    push    r12
    mov     rbx, rdi
    xor     ebp, ebp                ; i
.clue_loop:
    movzx   r12d, byte [rbx + rbp]  ; d
    test    r12d, r12d
    jz      .clue_next
    mov     byte [rbx + rbp], 0     ; hide the clue from its own scan
    movzx   eax, byte [RS + rbp]
    lea     r8, [rbx + rax]
    movzx   eax, byte [CC + rbp]
    lea     r9, [rbx + rax]
    movzx   eax, byte [BS + rbp]
    lea     r10, [rbx + rax]
    vmovd   xmm0, r12d
    vpbroadcastb xmm0, xmm0
    CELL_VALID .bad_clue
    mov     [rbx + rbp], r12b
.clue_next:
    inc     ebp
    cmp     ebp, 81
    jb      .clue_loop
    mov     rdi, rbx
    xor     esi, esi
    call    bt
    jmp     .ret
.bad_clue:
    mov     [rbx + rbp], r12b
    xor     eax, eax
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int main(int argc, char **argv)
; locals: [rsp..rsp+511] line buffer, [rsp+512] t0, [rsp+528] t1
; ---------------------------------------------------------------------
main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 552
    ; reps = argc > 1 ? max(1, strtol(argv[1])) : 1; threads ignored
    mov     rbp, 1
    cmp     edi, 2
    jl      .no_args
    mov     rdi, [rsi + 8]
    xor     esi, esi
    mov     edx, 10
    call    strtol wrt ..plt
    mov     rbp, rax
    cmp     rbp, 1
    jge     .no_args
    mov     rbp, 1
.no_args:
    call    init_tables
    ; ---- read all puzzles before starting the clock ----
    xor     r12d, r12d              ; n
.read_loop:
    mov     rdi, rsp
    mov     esi, 512
    mov     rdx, [stdin]
    call    fgets wrt ..plt
    test    rax, rax
    jz      .read_done
    xor     eax, eax                ; len = strlen(buf)
.len_scan:
    cmp     byte [rsp + rax], 0
    je      .strip
    inc     eax
    cmp     eax, 512
    jb      .len_scan
.strip:                             ; drop trailing \n / \r
    test    eax, eax
    jz      .check_line
    movzx   ecx, byte [rsp + rax - 1]
    cmp     cl, 10
    je      .strip_one
    cmp     cl, 13
    jne     .check_line
.strip_one:
    dec     eax
    mov     byte [rsp + rax], 0
    jmp     .strip
.check_line:
    test    eax, eax
    jz      .read_loop              ; empty line
    cmp     byte [rsp], '#'
    je      .read_loop              ; comment
    cmp     r12, MAXP
    jae     .read_loop
    lea     rdx, [r12 + r12*8]
    lea     rdx, [rdx + rdx*8]      ; n*81
    lea     rbx, [grids + rdx]
    cmp     eax, 81
    jne     .invalid
    xor     ecx, ecx
.val_loop:
    movzx   edx, byte [rsp + rcx]
    sub     edx, '0'
    cmp     edx, 9
    ja      .invalid
    mov     [rbx + rcx], dl
    inc     ecx
    cmp     ecx, 81
    jb      .val_loop
    jmp     .line_stored
.invalid:                           ; impossible clue -> UNSOLVED
    xor     ecx, ecx
.inv_loop:
    mov     byte [rbx + rcx], 10
    inc     ecx
    cmp     ecx, 81
    jb      .inv_loop
.line_stored:
    inc     r12
    jmp     .read_loop
.read_done:
    ; ---- timed solve loop ----
    mov     edi, 1                  ; CLOCK_MONOTONIC
    lea     rsi, [rsp + 512]
    call    clock_gettime wrt ..plt
    mov     r13, rbp                ; rep counter
.rep_loop:
    test    r12, r12
    jz      .rep_next
    xor     r14d, r14d              ; i
.solve_loop:
    lea     rax, [r14 + r14*8]
    lea     rax, [rax + rax*8]      ; i*81
    lea     rdi, [sols + rax]
    lea     rsi, [grids + rax]
    COPY81  rdi, rsi                ; fresh copy per repetition
    lea     rdi, [sols + rax]
    call    solve
    mov     [okbuf + r14], al
    inc     r14
    cmp     r14, r12
    jb      .solve_loop
.rep_next:
    dec     r13
    jnz     .rep_loop
    vzeroupper
    mov     edi, 1
    lea     rsi, [rsp + 528]
    call    clock_gettime wrt ..plt
    ; ---- output ----
    xor     r14d, r14d
.out_loop:
    cmp     r14, r12
    jae     .out_done
    cmp     byte [okbuf + r14], 0
    je      .unsolved
    lea     rax, [r14 + r14*8]
    lea     rax, [rax + rax*8]
    lea     rsi, [sols + rax]
    xor     ecx, ecx
.dig_loop:
    movzx   eax, byte [rsi + rcx]
    add     eax, '0'
    mov     [rsp + rcx], al
    inc     ecx
    cmp     ecx, 81
    jb      .dig_loop
    mov     byte [rsp + 81], 10
    mov     rdi, rsp
    mov     esi, 1
    mov     edx, 82
    mov     rcx, [stdout]
    call    fwrite wrt ..plt
    jmp     .out_next
.unsolved:
    mov     edi, uns_str
    mov     esi, 1
    mov     edx, 9
    mov     rcx, [stdout]
    call    fwrite wrt ..plt
.out_next:
    inc     r14
    jmp     .out_loop
.out_done:
    ; ns = (t1 - t0) in nanoseconds
    mov     rax, [rsp + 528]
    sub     rax, [rsp + 512]
    imul    rax, rax, 1000000000
    add     rax, [rsp + 536]
    sub     rax, [rsp + 520]
    mov     rdi, [stderr]
    mov     esi, fmt_ns
    mov     rdx, rax
    xor     eax, eax
    call    fprintf wrt ..plt
    xor     eax, eax
    add     rsp, 552
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
