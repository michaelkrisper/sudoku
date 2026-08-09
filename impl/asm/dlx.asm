; Knuth's Algorithm X with dancing links, flat 16-bit index arrays.
;
; x86-64 port of impl/c/dlx.c: 324 columns (81 cell + 81 row-digit +
; 81 col-digit + 81 box-digit), 729 candidate rows of 4 nodes each.
; The matrix is built once before the clock starts; per puzzle only the
; mutable link arrays (L/R/U/D/size) are copied and the clue rows covered.
; libc is used for I/O, parsing and timing only; build/cover/uncover/
; search/solve are hand-written assembly.

%define MAXP  100000               ; max puzzles held in static storage
%define NCOLS 324
%define NNODE 3241                 ; 1 root + 324 headers + 729*4 nodes
%define FIRST 325                  ; index of the first row node
%define NST   3248                 ; padded array stride, in 16-bit words

; the five mutable arrays live in one block so a puzzle reset is one copy
%define OFF_L  0
%define OFF_R  (NST*2)
%define OFF_U  (NST*4)
%define OFF_D  (NST*6)
%define OFF_SZ (NST*8)
%define BLK    (NST*8 + 656)       ; 26640 bytes = 3330 qwords

global main
extern fgets, strtol, clock_gettime, fwrite, fprintf
extern stdin, stdout, stderr

section .bss
align 32
IMM0:   resb BLK                   ; immutable master copy: L0/R0/U0/D0/SZ0
WORK:   resb BLK                   ; per-puzzle working copy: L/R/U/D/SZ
COL:    resw NST                   ; column header of each node
RID:    resw NST                   ; (cell << 4) | digit of each node
sol:    resw 81
nsol:   resd 1
grids:  resb MAXP * 81             ; parsed puzzles, one digit per byte
sols:   resb MAXP * 81
okbuf:  resb MAXP

section .rodata
DIV3:    db 0,0,0,1,1,1,2,2,2
fmt_ns:  db "ns=%lu", 10, 0
uns_str: db "UNSOLVED", 10

section .text

; ---------------------------------------------------------------------
; addnode: append node r10d in column edi, row id esi. Bumps r10d.
; ---------------------------------------------------------------------
addnode:
    mov     [COL + r10*2], di
    mov     [RID + r10*2], si
    mov     [IMM0 + OFF_D + r10*2], di      ; D0[n] = col
    movzx   eax, word [IMM0 + OFF_U + rdi*2]
    mov     [IMM0 + OFF_U + r10*2], ax      ; U0[n] = U0[col]
    mov     [IMM0 + OFF_D + rax*2], r10w    ; D0[U0[col]] = n
    mov     [IMM0 + OFF_U + rdi*2], r10w    ; U0[col] = n
    inc     word [IMM0 + OFF_SZ + rdi*2]
    inc     r10d
    ret

; ---------------------------------------------------------------------
; build: fill the immutable matrix. Runs once, before the clock starts.
; ---------------------------------------------------------------------
build:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    ; root + column headers, doubly linked in a ring, empty columns
    xor     ecx, ecx
.hloop:
    lea     eax, [rcx - 1]
    test    ecx, ecx
    jnz     .l_ok
    mov     eax, NCOLS
.l_ok:
    mov     [IMM0 + OFF_L + rcx*2], ax
    lea     eax, [rcx + 1]
    cmp     ecx, NCOLS
    jb      .r_ok
    xor     eax, eax
.r_ok:
    mov     [IMM0 + OFF_R + rcx*2], ax
    mov     [IMM0 + OFF_U + rcx*2], cx
    mov     [IMM0 + OFF_D + rcx*2], cx
    inc     ecx
    cmp     ecx, NCOLS
    jbe     .hloop
    ; 729 candidate rows
    mov     r10d, FIRST                     ; n
    xor     r8d, r8d                        ; r
.rloop:
    xor     r9d, r9d                        ; c
.cloop:
    lea     r11d, [r8 + r8*8]
    add     r11d, r9d                       ; cell = r*9 + c
    movzx   eax, byte [DIV3 + r8]
    lea     eax, [rax + rax*2]              ; r/3*3
    movzx   ecx, byte [DIV3 + r9]
    add     eax, ecx                        ; b
    lea     r13d, [rax + rax*8]
    add     r13d, 244                       ; 244 + b*9
    lea     r14d, [r8 + r8*8]
    add     r14d, 82                        ; 82 + r*9
    lea     r15d, [r9 + r9*8]
    add     r15d, 163                       ; 163 + c*9
    lea     r12d, [r11 + 1]                 ; 1 + cell
    xor     ebx, ebx                        ; d = digit - 1
.dloop:
    mov     esi, r11d
    shl     esi, 4
    lea     esi, [rsi + rbx + 1]            ; rid = (cell << 4) | (d+1)
    mov     edi, r12d
    call    addnode
    lea     edi, [r14 + rbx]
    call    addnode
    lea     edi, [r15 + rbx]
    call    addnode
    lea     edi, [r13 + rbx]
    call    addnode
    ; link the 4 fresh nodes circularly: f = n - 4
    lea     eax, [r10 - 4]
    lea     ecx, [rax + 3]
    mov     [IMM0 + OFF_L + rax*2], cx
    lea     ecx, [rax + 1]
    mov     [IMM0 + OFF_R + rax*2], cx
    mov     [IMM0 + OFF_L + rcx*2], ax
    lea     edx, [rax + 2]
    mov     [IMM0 + OFF_R + rcx*2], dx
    mov     [IMM0 + OFF_L + rdx*2], cx
    lea     ecx, [rax + 3]
    mov     [IMM0 + OFF_R + rdx*2], cx
    mov     [IMM0 + OFF_L + rcx*2], dx
    mov     [IMM0 + OFF_R + rcx*2], ax
    inc     ebx
    cmp     ebx, 9
    jb      .dloop
    inc     r9d
    cmp     r9d, 9
    jb      .cloop
    inc     r8d
    cmp     r8d, 9
    jb      .rloop
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------
; cover(rdi = column index). Clobbers rax, rcx, rdx, r8, r9.
; ---------------------------------------------------------------------
cover:
    movzx   eax, word [WORK + OFF_L + rdi*2]
    movzx   edx, word [WORK + OFF_R + rdi*2]
    mov     [WORK + OFF_R + rax*2], dx      ; R[L[c]] = R[c]
    mov     [WORK + OFF_L + rdx*2], ax      ; L[R[c]] = L[c]
    movzx   r8d, word [WORK + OFF_D + rdi*2]
.iloop:
    cmp     r8d, edi
    je      .done
    movzx   r9d, word [WORK + OFF_R + r8*2]
.jloop:
    cmp     r9d, r8d
    je      .jdone
    movzx   eax, word [WORK + OFF_U + r9*2]
    movzx   edx, word [WORK + OFF_D + r9*2]
    mov     [WORK + OFF_D + rax*2], dx      ; D[U[j]] = D[j]
    mov     [WORK + OFF_U + rdx*2], ax      ; U[D[j]] = U[j]
    movzx   ecx, word [COL + r9*2]
    dec     word [WORK + OFF_SZ + rcx*2]
    movzx   r9d, word [WORK + OFF_R + r9*2]
    jmp     .jloop
.jdone:
    movzx   r8d, word [WORK + OFF_D + r8*2]
    jmp     .iloop
.done:
    ret

; ---------------------------------------------------------------------
; uncover(rdi = column index). Exact inverse of cover.
; ---------------------------------------------------------------------
uncover:
    movzx   r8d, word [WORK + OFF_U + rdi*2]
.iloop:
    cmp     r8d, edi
    je      .done
    movzx   r9d, word [WORK + OFF_L + r8*2]
.jloop:
    cmp     r9d, r8d
    je      .jdone
    movzx   ecx, word [COL + r9*2]
    inc     word [WORK + OFF_SZ + rcx*2]
    movzx   eax, word [WORK + OFF_U + r9*2]
    movzx   edx, word [WORK + OFF_D + r9*2]
    mov     [WORK + OFF_D + rax*2], r9w     ; D[U[j]] = j
    mov     [WORK + OFF_U + rdx*2], r9w     ; U[D[j]] = j
    movzx   r9d, word [WORK + OFF_L + r9*2]
    jmp     .jloop
.jdone:
    movzx   r8d, word [WORK + OFF_U + r8*2]
    jmp     .iloop
.done:
    movzx   eax, word [WORK + OFF_L + rdi*2]
    movzx   edx, word [WORK + OFF_R + rdi*2]
    mov     [WORK + OFF_R + rax*2], di      ; R[L[c]] = c
    mov     [WORK + OFF_L + rdx*2], di      ; L[R[c]] = c
    ret

; ---------------------------------------------------------------------
; int search(void): Algorithm X, minimum-size column choice.
; ---------------------------------------------------------------------
search:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    movzx   ebx, word [WORK + OFF_R]        ; best = R[0]
    test    ebx, ebx
    jz      .true                           ; no columns left: solved
    movzx   ebp, word [WORK + OFF_SZ + rbx*2]
    cmp     ebp, 1
    jbe     .chosen                         ; Knuth's S heuristic, early out
    movzx   r12d, word [WORK + OFF_R + rbx*2]
.scan:
    test    r12d, r12d
    jz      .chosen
    movzx   eax, word [WORK + OFF_SZ + r12*2]
    cmp     eax, ebp
    jae     .scan_next
    mov     ebp, eax
    mov     ebx, r12d
    cmp     eax, 2
    jb      .chosen
.scan_next:
    movzx   r12d, word [WORK + OFF_R + r12*2]
    jmp     .scan
.chosen:
    mov     edi, ebx
    call    cover
    movzx   r13d, word [WORK + OFF_D + rbx*2]
.iloop:
    cmp     r13d, ebx
    je      .fail
    mov     eax, [nsol]                     ; sol[nsol++] = RID[i]
    movzx   ecx, word [RID + r13*2]
    mov     [sol + rax*2], cx
    inc     eax
    mov     [nsol], eax
    movzx   r14d, word [WORK + OFF_R + r13*2]
.cov:
    cmp     r14d, r13d
    je      .cov_done
    movzx   edi, word [COL + r14*2]
    call    cover
    movzx   r14d, word [WORK + OFF_R + r14*2]
    jmp     .cov
.cov_done:
    call    search
    test    eax, eax
    jnz     .true
    movzx   r14d, word [WORK + OFF_L + r13*2]
.unc:
    cmp     r14d, r13d
    je      .unc_done
    movzx   edi, word [COL + r14*2]
    call    uncover
    movzx   r14d, word [WORK + OFF_L + r14*2]
    jmp     .unc
.unc_done:
    dec     dword [nsol]
    movzx   r13d, word [WORK + OFF_D + r13*2]
    jmp     .iloop
.fail:
    mov     edi, ebx
    call    uncover
    xor     eax, eax
    jmp     .ret
.true:
    mov     eax, 1
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int solve(const uint8_t *grid rdi, uint8_t *out rsi)
; stack: rm[9] at rsp, cm[9] at rsp+24, bm[9] at rsp+48
; ---------------------------------------------------------------------
solve:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 88
    mov     r12, rdi                        ; grid
    mov     r13, rsi                        ; out
    vpxor   xmm0, xmm0, xmm0
    vmovdqu [rsp], ymm0
    vmovdqu [rsp + 32], ymm0
    mov     qword [rsp + 64], 0
    ; ---- cheap consistency gate: no digit twice in a row/col/box ----
    xor     r8d, r8d                        ; r
.grow:
    xor     r9d, r9d                        ; c
.gcol:
    lea     eax, [r8 + r8*8]
    add     eax, r9d                        ; i
    movzx   edx, byte [r12 + rax]           ; d
    test    edx, edx
    jz      .gnext
    mov     ecx, edx
    mov     edx, 1
    shl     edx, cl                         ; bit = 1 << d
    movzx   eax, byte [DIV3 + r8]
    lea     eax, [rax + rax*2]
    movzx   ecx, byte [DIV3 + r9]
    add     eax, ecx                        ; b
    movzx   ecx, word [rsp + r8*2]
    movzx   r11d, word [rsp + 24 + r9*2]
    or      ecx, r11d
    movzx   r11d, word [rsp + 48 + rax*2]
    or      ecx, r11d
    test    ecx, edx
    jnz     .fail
    or      [rsp + r8*2], dx
    or      [rsp + 24 + r9*2], dx
    or      [rsp + 48 + rax*2], dx
.gnext:
    inc     r9d
    cmp     r9d, 9
    jb      .gcol
    inc     r8d
    cmp     r8d, 9
    jb      .grow
    ; ---- fresh copies of the mutable arrays ----
    mov     esi, IMM0
    mov     edi, WORK
    mov     ecx, BLK / 8
    rep movsq
    mov     dword [nsol], 0
    ; ---- pre-select the clue rows (the gate makes this safe) ----
    xor     ebx, ebx                        ; i
.clue:
    movzx   eax, byte [r12 + rbx]           ; d
    test    eax, eax
    jz      .clue_next
    lea     edx, [rbx + rbx*8]
    add     edx, eax
    dec     edx                             ; i*9 + d - 1
    shl     edx, 2
    lea     ebp, [rdx + FIRST]              ; node
    movzx   edi, word [COL + rbp*2]
    call    cover
    movzx   r14d, word [WORK + OFF_R + rbp*2]
.clue_cov:
    cmp     r14d, ebp
    je      .clue_next
    movzx   edi, word [COL + r14*2]
    call    cover
    movzx   r14d, word [WORK + OFF_R + r14*2]
    jmp     .clue_cov
.clue_next:
    inc     ebx
    cmp     ebx, 81
    jb      .clue
    call    search
    test    eax, eax
    jz      .fail
    ; ---- write the solution: clues from the grid, rest from sol[] ----
    vmovdqu ymm0, [r12]
    vmovdqu ymm1, [r12 + 32]
    vmovdqu xmm2, [r12 + 64]
    vmovdqu [r13], ymm0
    vmovdqu [r13 + 32], ymm1
    vmovdqu [r13 + 64], xmm2
    movzx   eax, byte [r12 + 80]
    mov     [r13 + 80], al
    mov     ecx, [nsol]
    xor     eax, eax
.emit:
    cmp     eax, ecx
    jae     .done
    movzx   edx, word [sol + rax*2]
    mov     esi, edx
    shr     esi, 4                          ; cell
    and     edx, 15                         ; digit
    mov     [r13 + rsi], dl
    inc     eax
    jmp     .emit
.done:
    mov     eax, 1
    jmp     .ret
.fail:
    xor     eax, eax
.ret:
    vzeroupper
    add     rsp, 88
    pop     r15
    pop     r14
    pop     r13
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
    call    build
    ; ---- read all puzzles before starting the clock ----
    xor     r12d, r12d                      ; n
.read_loop:
    mov     rdi, rsp
    mov     esi, 512
    mov     rdx, [stdin]
    call    fgets wrt ..plt
    test    rax, rax
    jz      .read_done
    xor     eax, eax                        ; len = strlen(buf)
.len_scan:
    cmp     byte [rsp + rax], 0
    je      .strip
    inc     eax
    cmp     eax, 512
    jb      .len_scan
.strip:                                     ; drop trailing \n / \r
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
    jz      .read_loop                      ; empty line
    cmp     byte [rsp], '#'
    je      .read_loop                      ; comment
    cmp     r12, MAXP
    jae     .read_loop
    lea     rdx, [r12 + r12*8]
    lea     rdx, [rdx + rdx*8]              ; n*81
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
.invalid:                                   ; malformed line -> UNSOLVED
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
    mov     edi, 1                          ; CLOCK_MONOTONIC
    lea     rsi, [rsp + 512]
    call    clock_gettime wrt ..plt
    mov     r13, rbp                        ; rep counter
.rep_loop:
    test    r12, r12
    jz      .rep_next
    xor     r14d, r14d                      ; i
.solve_loop:
    lea     rax, [r14 + r14*8]
    lea     r15, [rax + rax*8]              ; i*81
    xor     eax, eax
    cmp     byte [grids + r15], 9
    ja      .store_ok                       ; malformed line
    lea     rdi, [grids + r15]
    lea     rsi, [sols + r15]
    call    solve
.store_ok:
    mov     [okbuf + r14], al
    inc     r14
    cmp     r14, r12
    jb      .solve_loop
.rep_next:
    dec     r13
    jnz     .rep_loop
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
    lea     rsi, [rax + rax*8]
    xor     ecx, ecx
.dig_loop:
    movzx   eax, byte [sols + rsi + rcx]
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
