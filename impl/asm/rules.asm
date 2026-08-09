; Pure rule-based solver (no guessing, no backtracking).
;
; x86-64 port of impl/c/rules.c: naked singles, hidden singles, naked
; pairs, hidden pairs, pointing pairs/triples, box-line reduction,
; X-Wing and Swordfish, applied to a fixpoint in that order (cheapest
; technique first). A puzzle that logic cannot finish prints UNSOLVED,
; and so does any contradiction found on the way.
; libc is used for I/O, parsing and timing only; every technique is
; hand-written assembly. Requires Haswell+ (BMI1: tzcnt/andn/blsr).

%define MAXP 100000                 ; max puzzles held in static storage
%define ALL  0x03FE                 ; bits 1..9 set

global main
extern fgets, strtol, clock_gettime, fwrite, fprintf
extern stdin, stdout, stderr

; Remove mask bits from cell %1; %3 is set to 1 on any change and the
; contradiction path branches to %4. Clobbers r11d.
%macro STRIP 4                      ; %1 cell(64), %2 mask(32), %3 prog(32), %4 bad label
    movzx   r11d, word [cand + %1*2]
    test    r11d, %2
    jz      %%skip
    andn    r11d, %2, r11d
    mov     [cand + %1*2], r11w
    mov     %3, 1
    jz      %4                      ; cell emptied: contradiction
%%skip:
%endmacro

section .bss
align 32
UNITS:  resb 27 * 9                 ; 9 rows, 9 cols, 9 boxes
PEERS:  resb 81 * 20
BOX_OF: resb 81
ROW_OF: resb 81
COL_OF: resb 81
cand:   resw 81
placed: resb 96
bad:    resd 1                      ; contradiction flag
grids:  resb MAXP * 81              ; parsed puzzles, one digit per byte
sols:   resb MAXP * 81              ; solutions as ASCII digits
okbuf:  resb MAXP

section .rodata
DIV3:    db 0,0,0,1,1,1,2,2,2
MOD3:    db 0,1,2,0,1,2,0,1,2
fmt_ns:  db "ns=%lu", 10, 0
uns_str: db "UNSOLVED", 10

section .text

; ---------------------------------------------------------------------
; init_tables: UNITS[27][9], BOX_OF/ROW_OF/COL_OF[81], PEERS[81][20].
; ---------------------------------------------------------------------
init_tables:
    xor     r8d, r8d                        ; r
.rloop:
    xor     r9d, r9d                        ; c
.cloop:
    lea     eax, [r8 + r8*8]
    add     eax, r9d                        ; i = r*9 + c
    lea     ecx, [r8 + r8*8]
    add     ecx, r9d
    mov     [UNITS + rcx], al               ; UNITS[r][c]
    lea     ecx, [r9 + r9*8]
    add     ecx, 81
    add     ecx, r8d
    mov     [UNITS + rcx], al               ; UNITS[9+c][r]
    mov     [ROW_OF + rax], r8b
    mov     [COL_OF + rax], r9b
    movzx   edx, byte [DIV3 + r8]
    lea     edx, [rdx + rdx*2]
    movzx   ecx, byte [DIV3 + r9]
    add     edx, ecx
    mov     [BOX_OF + rax], dl
    inc     r9d
    cmp     r9d, 9
    jb      .cloop
    inc     r8d
    cmp     r8d, 9
    jb      .rloop
    xor     r8d, r8d                        ; b
.bloop:
    xor     r9d, r9d                        ; k
.kloop:
    movzx   eax, byte [DIV3 + r8]
    lea     eax, [rax + rax*2]              ; b/3*3
    movzx   edx, byte [DIV3 + r9]
    add     eax, edx                        ; + k/3
    lea     eax, [rax + rax*8]              ; *9
    movzx   edx, byte [MOD3 + r8]
    lea     edx, [rdx + rdx*2]              ; b%3*3
    add     eax, edx
    movzx   edx, byte [MOD3 + r9]
    add     eax, edx                        ; cell
    lea     ecx, [r8 + r8*8]
    add     ecx, 162
    add     ecx, r9d
    mov     [UNITS + rcx], al               ; UNITS[18+b][k]
    inc     r9d
    cmp     r9d, 9
    jb      .kloop
    inc     r8d
    cmp     r8d, 9
    jb      .bloop
    xor     r8d, r8d                        ; i
.iloop:
    lea     rax, [r8 + r8*4]
    lea     r10, [PEERS + rax*4]            ; &PEERS[i][0]
    movzx   esi, byte [ROW_OF + r8]
    movzx   edi, byte [COL_OF + r8]
    movzx   ecx, byte [BOX_OF + r8]
    xor     r9d, r9d                        ; j
.jloop:
    cmp     r9d, r8d
    je      .jnext
    cmp     [ROW_OF + r9], sil
    je      .peer
    cmp     [COL_OF + r9], dil
    je      .peer
    cmp     [BOX_OF + r9], cl
    jne     .jnext
.peer:
    mov     [r10], r9b
    inc     r10
.jnext:
    inc     r9d
    cmp     r9d, 81
    jb      .jloop
    inc     r8d
    cmp     r8d, 81
    jb      .iloop
    ret

; ---------------------------------------------------------------------
; int naked_singles(void): place every cell with a single candidate and
; strip that digit from its 20 peers.
; ---------------------------------------------------------------------
naked_singles:
    push    rbx
    push    rbp
    push    r12
    push    r13
    xor     r12d, r12d                      ; prog
    xor     ebx, ebx                        ; i
.loop:
    cmp     byte [placed + rbx], 0
    jne     .next
    movzx   ebp, word [cand + rbx*2]        ; c
    popcnt  eax, ebp
    cmp     eax, 1
    jne     .next
    mov     byte [placed + rbx], 1
    mov     r12d, 1
    lea     rax, [rbx + rbx*4]
    lea     r13, [PEERS + rax*4]
    xor     ecx, ecx                        ; k
.peer:
    movzx   eax, byte [r13 + rcx]           ; p
    STRIP   rax, ebp, r12d, .set_bad
    inc     ecx
    cmp     ecx, 20
    jb      .peer
.next:
    inc     ebx
    cmp     ebx, 81
    jb      .loop
    mov     eax, r12d
    jmp     .ret
.set_bad:
    mov     dword [bad], 1
    mov     eax, r12d
.ret:
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int hidden_singles(void): a digit with exactly one place in a unit.
; ---------------------------------------------------------------------
hidden_singles:
    push    rbx
    push    rbp
    push    r12
    push    r13
    xor     r12d, r12d                      ; prog
    xor     ebx, ebx                        ; u
.uloop:
    lea     r13, [UNITS + rbx + rbx*8]
    mov     edx, 1                          ; d
.dloop:
    mov     ecx, edx
    mov     ebp, 1
    shl     ebp, cl                         ; bit
    xor     esi, esi                        ; cnt
    xor     edi, edi                        ; last
    xor     ecx, ecx                        ; k
.kloop:
    movzx   eax, byte [r13 + rcx]
    movzx   r8d, word [cand + rax*2]
    test    r8d, ebp
    jz      .knext
    inc     esi
    mov     edi, eax
.knext:
    inc     ecx
    cmp     ecx, 9
    jb      .kloop
    test    esi, esi
    jz      .set_bad                        ; digit has nowhere to go
    cmp     esi, 1
    jne     .dnext
    cmp     word [cand + rdi*2], bp
    je      .dnext
    mov     [cand + rdi*2], bp
    mov     r12d, 1
.dnext:
    inc     edx
    cmp     edx, 10
    jb      .dloop
    inc     ebx
    cmp     ebx, 27
    jb      .uloop
    mov     eax, r12d
    jmp     .ret
.set_bad:
    mov     dword [bad], 1
    mov     eax, r12d
.ret:
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int naked_pairs(void): two cells of a unit sharing the same two
; candidates lock those digits out of the rest of the unit.
; ---------------------------------------------------------------------
naked_pairs:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r12d, r12d                      ; prog
    xor     ebx, ebx                        ; u
.uloop:
    lea     r13, [UNITS + rbx + rbx*8]
    xor     r14d, r14d                      ; a
.aloop:
    lea     r15d, [r14 + 1]                 ; b
.bloop:
    cmp     r15d, 9
    jae     .anext
    movzx   eax, byte [r13 + r14]
    movzx   ebp, word [cand + rax*2]        ; m
    popcnt  ecx, ebp
    cmp     ecx, 2
    jne     .bnext
    movzx   eax, byte [r13 + r15]
    cmp     word [cand + rax*2], bp
    jne     .bnext
    xor     ecx, ecx                        ; k
.kloop:
    cmp     ecx, r14d
    je      .knext
    cmp     ecx, r15d
    je      .knext
    movzx   eax, byte [r13 + rcx]
    STRIP   rax, ebp, r12d, .set_bad
.knext:
    inc     ecx
    cmp     ecx, 9
    jb      .kloop
.bnext:
    inc     r15d
    jmp     .bloop
.anext:
    inc     r14d
    cmp     r14d, 9
    jb      .aloop
    inc     ebx
    cmp     ebx, 27
    jb      .uloop
    mov     eax, r12d
    jmp     .ret
.set_bad:
    mov     dword [bad], 1
    mov     eax, r12d
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int hidden_pairs(void): two digits confined to the same two cells of a
; unit own those cells.
; stack: pos[10] words at rsp, two[9] dwords at rsp+24
; ---------------------------------------------------------------------
hidden_pairs:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    xor     r12d, r12d                      ; prog
    xor     ebx, ebx                        ; u
.uloop:
    lea     r13, [UNITS + rbx + rbx*8]
    xor     r14d, r14d                      ; n
    mov     edx, 1                          ; d
.dloop:
    mov     ecx, edx
    mov     edi, 1
    shl     edi, cl                         ; bit
    xor     esi, esi                        ; p
    xor     ecx, ecx                        ; k
.kloop:
    movzx   eax, byte [r13 + rcx]
    movzx   eax, word [cand + rax*2]
    test    eax, edi
    jz      .knext
    bts     esi, ecx
.knext:
    inc     ecx
    cmp     ecx, 9
    jb      .kloop
    mov     [rsp + rdx*2], si               ; pos[d]
    popcnt  eax, esi
    cmp     eax, 2
    jne     .dnext
    mov     [rsp + 24 + r14*4], edx         ; two[n++] = d
    inc     r14d
.dnext:
    inc     edx
    cmp     edx, 10
    jb      .dloop
    xor     r15d, r15d                      ; x
.xloop:
    cmp     r15d, r14d
    jae     .unext
    mov     r8d, [rsp + 24 + r15*4]         ; dx
    movzx   r9d, word [rsp + r8*2]          ; px
    lea     ebp, [r15 + 1]                  ; y
.yloop:
    cmp     ebp, r14d
    jae     .xnext
    mov     r10d, [rsp + 24 + rbp*4]        ; dy
    movzx   eax, word [rsp + r10*2]
    cmp     eax, r9d
    jne     .ynext
    mov     ecx, r8d
    mov     edx, 1
    shl     edx, cl
    mov     ecx, r10d
    mov     eax, 1
    shl     eax, cl
    or      edx, eax                        ; mask
    xor     ecx, ecx                        ; k
.k2loop:
    bt      r9d, ecx
    jnc     .k2next
    movzx   eax, byte [r13 + rcx]
    movzx   esi, word [cand + rax*2]
    andn    edi, edx, esi
    jz      .k2next                         ; nothing outside the pair
    and     esi, edx
    mov     [cand + rax*2], si
    jz      .set_bad
    mov     r12d, 1
.k2next:
    inc     ecx
    cmp     ecx, 9
    jb      .k2loop
.ynext:
    inc     ebp
    jmp     .yloop
.xnext:
    inc     r15d
    jmp     .xloop
.unext:
    inc     ebx
    cmp     ebx, 27
    jb      .uloop
    mov     eax, r12d
    jmp     .ret
.set_bad:
    mov     dword [bad], 1
    mov     eax, r12d
.ret:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int pointing_and_boxline(void): pointing pairs/triples (box -> line)
; followed by box-line reduction (line -> box).
; stack: places[9] dwords at rsp
; ---------------------------------------------------------------------
pointing_and_boxline:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    xor     r12d, r12d                      ; prog
    ; ---- pointing pairs / triples ----
    xor     ebx, ebx                        ; b
.bloop:
    lea     eax, [rbx + 18]
    lea     r13, [UNITS + rax + rax*8]
    mov     r14d, 1                         ; d
.dloop:
    mov     ecx, r14d
    mov     ebp, 1
    shl     ebp, cl                         ; bit
    xor     r15d, r15d                      ; np
    xor     ecx, ecx                        ; k
.kloop:
    movzx   eax, byte [r13 + rcx]
    movzx   edx, word [cand + rax*2]
    test    edx, ebp
    jz      .knext
    mov     [rsp + r15*4], eax
    inc     r15d
.knext:
    inc     ecx
    cmp     ecx, 9
    jb      .kloop
    cmp     r15d, 2
    jb      .dnext
    cmp     r15d, 3
    ja      .dnext
    mov     r8d, [rsp]                      ; places[0]
    movzx   r9d, byte [ROW_OF + r8]
    movzx   r10d, byte [COL_OF + r8]
    mov     esi, 1                          ; samer
    mov     edi, 1                          ; samec
    mov     ecx, 1                          ; j
.jloop:
    cmp     ecx, r15d
    jae     .jdone
    mov     eax, [rsp + rcx*4]
    cmp     [ROW_OF + rax], r9b
    je      .same_r
    xor     esi, esi
.same_r:
    cmp     [COL_OF + rax], r10b
    je      .same_c
    xor     edi, edi
.same_c:
    inc     ecx
    jmp     .jloop
.jdone:
    test    esi, esi
    jnz     .box_row
    test    edi, edi
    jz      .dnext
    ; box -> column
    xor     ecx, ecx                        ; r
.colelim:
    lea     eax, [rcx + rcx*8]
    add     eax, r10d                       ; i = r*9 + col
    cmp     [BOX_OF + rax], bl
    je      .colnext
    STRIP   rax, ebp, r12d, .set_bad
.colnext:
    inc     ecx
    cmp     ecx, 9
    jb      .colelim
    jmp     .dnext
.box_row:
    ; box -> row
    lea     edx, [r9 + r9*8]                ; row*9
    xor     ecx, ecx                        ; c
.rowelim:
    lea     eax, [rdx + rcx]                ; i = row*9 + c
    cmp     [BOX_OF + rax], bl
    je      .rownext
    STRIP   rax, ebp, r12d, .set_bad
.rownext:
    inc     ecx
    cmp     ecx, 9
    jb      .rowelim
.dnext:
    inc     r14d
    cmp     r14d, 10
    jb      .dloop
    inc     ebx
    cmp     ebx, 9
    jb      .bloop
    ; ---- box-line reduction ----
    xor     r13d, r13d                      ; axis
.aloop:
    xor     ebx, ebx                        ; l
.lloop:
    mov     eax, r13d
    lea     eax, [rax + rax*8]
    add     eax, ebx                        ; unit = axis*9 + l
    lea     r10, [UNITS + rax + rax*8]
    mov     r14d, 1                         ; d
.d2loop:
    mov     ecx, r14d
    mov     ebp, 1
    shl     ebp, cl                         ; bit
    xor     r15d, r15d                      ; boxes
    xor     ecx, ecx                        ; k
.k2loop:
    movzx   eax, byte [r10 + rcx]
    movzx   edx, word [cand + rax*2]
    test    edx, ebp
    jz      .k2next
    movzx   edx, byte [BOX_OF + rax]
    bts     r15d, edx
.k2next:
    inc     ecx
    cmp     ecx, 9
    jb      .k2loop
    popcnt  eax, r15d
    cmp     eax, 1
    jne     .d2next
    tzcnt   r15d, r15d                      ; bx
    lea     eax, [r15 + 18]
    lea     r9, [UNITS + rax + rax*8]
    xor     ecx, ecx                        ; k
.k3loop:
    movzx   eax, byte [r9 + rcx]
    test    r13d, r13d
    jnz     .by_col
    cmp     [ROW_OF + rax], bl
    je      .k3next
    jmp     .k3strip
.by_col:
    cmp     [COL_OF + rax], bl
    je      .k3next
.k3strip:
    STRIP   rax, ebp, r12d, .set_bad
.k3next:
    inc     ecx
    cmp     ecx, 9
    jb      .k3loop
.d2next:
    inc     r14d
    cmp     r14d, 10
    jb      .d2loop
    inc     ebx
    cmp     ebx, 9
    jb      .lloop
    inc     r13d
    cmp     r13d, 2
    jb      .aloop
    mov     eax, r12d
    jmp     .ret
.set_bad:
    mov     dword [bad], 1
    mov     eax, r12d
.ret:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int fish_elim(int axis edi, int un esi, int keep edx, int bit ecx)
; Strip bit from the cross lines of a confirmed fish pattern.
; Clobbers rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11.
; ---------------------------------------------------------------------
fish_elim:
    xor     r10d, r10d                      ; prog
    xor     r8d, r8d                        ; cc
.ccloop:
    bt      esi, r8d
    jnc     .ccnext
    xor     r9d, r9d                        ; lc
.lcloop:
    bt      edx, r9d
    jc      .lcnext
    test    edi, edi
    jnz     .by_col
    lea     eax, [r9 + r9*8]
    add     eax, r8d                        ; i = lc*9 + cc
    jmp     .have
.by_col:
    lea     eax, [r8 + r8*8]
    add     eax, r9d                        ; i = cc*9 + lc
.have:
    movzx   r11d, word [cand + rax*2]
    test    r11d, ecx
    jz      .lcnext
    andn    r11d, ecx, r11d
    mov     [cand + rax*2], r11w
    mov     r10d, 1
    jz      .set_bad
.lcnext:
    inc     r9d
    cmp     r9d, 9
    jb      .lcloop
.ccnext:
    inc     r8d
    cmp     r8d, 9
    jb      .ccloop
    mov     eax, r10d
    ret
.set_bad:
    mov     dword [bad], 1
    mov     eax, r10d
    ret

; ---------------------------------------------------------------------
; int fish(int size edi): X-Wing (size 2) / Swordfish (size 3), rows and
; columns as base lines.
; stack: bl[9] dwords at rsp, bm[9] dwords at rsp+40, size at rsp+80,
;        axis at rsp+84, prog at rsp+88
; ---------------------------------------------------------------------
fish:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 104
    mov     [rsp + 80], edi                 ; size
    mov     dword [rsp + 88], 0             ; prog
    mov     dword [rsp + 84], 0             ; axis
.axis_loop:
    mov     r13d, 1                         ; d
.dloop:
    mov     ecx, r13d
    mov     r15d, 1
    shl     r15d, cl                        ; bit
    xor     r14d, r14d                      ; nb
    xor     ebx, ebx                        ; li
.li_loop:
    xor     ebp, ebp                        ; ps
    xor     ecx, ecx                        ; k
.kloop:
    cmp     dword [rsp + 84], 0
    jne     .k_col
    lea     eax, [rbx + rbx*8]
    add     eax, ecx                        ; i = li*9 + k
    jmp     .k_have
.k_col:
    lea     eax, [rcx + rcx*8]
    add     eax, ebx                        ; i = k*9 + li
.k_have:
    movzx   eax, word [cand + rax*2]
    test    eax, r15d
    jz      .knext
    bts     ebp, ecx
.knext:
    inc     ecx
    cmp     ecx, 9
    jb      .kloop
    popcnt  eax, ebp
    cmp     eax, 2
    jb      .li_next
    cmp     eax, [rsp + 80]
    ja      .li_next
    mov     [rsp + r14*4], ebx              ; bl[nb]
    mov     [rsp + 40 + r14*4], ebp         ; bm[nb]
    inc     r14d
.li_next:
    inc     ebx
    cmp     ebx, 9
    jb      .li_loop
    cmp     dword [rsp + 80], 2
    jne     .triples
    ; ---- X-Wing: pairs of base lines ----
    xor     ebx, ebx                        ; a
.p_a:
    cmp     ebx, r14d
    jae     .dnext
    lea     ebp, [rbx + 1]                  ; b
.p_b:
    cmp     ebp, r14d
    jae     .p_a_next
    mov     esi, [rsp + 40 + rbx*4]
    or      esi, [rsp + 40 + rbp*4]         ; un
    popcnt  eax, esi
    cmp     eax, 2
    jne     .p_b_next
    mov     ecx, [rsp + rbx*4]
    mov     edx, 1
    shl     edx, cl
    mov     ecx, [rsp + rbp*4]
    mov     eax, 1
    shl     eax, cl
    or      edx, eax                        ; keep
    mov     edi, [rsp + 84]
    mov     ecx, r15d
    call    fish_elim
    or      [rsp + 88], eax
    cmp     dword [bad], 0
    jne     .ret
.p_b_next:
    inc     ebp
    jmp     .p_b
.p_a_next:
    inc     ebx
    jmp     .p_a
    ; ---- Swordfish: triples of base lines ----
.triples:
    xor     ebx, ebx                        ; a
.t_a:
    cmp     ebx, r14d
    jae     .dnext
    lea     ebp, [rbx + 1]                  ; b
.t_b:
    cmp     ebp, r14d
    jae     .t_a_next
    lea     r12d, [rbp + 1]                 ; c
.t_c:
    cmp     r12d, r14d
    jae     .t_b_next
    mov     esi, [rsp + 40 + rbx*4]
    or      esi, [rsp + 40 + rbp*4]
    or      esi, [rsp + 40 + r12*4]         ; un
    popcnt  eax, esi
    cmp     eax, 3
    jne     .t_c_next
    mov     ecx, [rsp + rbx*4]
    mov     edx, 1
    shl     edx, cl
    mov     ecx, [rsp + rbp*4]
    mov     eax, 1
    shl     eax, cl
    or      edx, eax
    mov     ecx, [rsp + r12*4]
    mov     eax, 1
    shl     eax, cl
    or      edx, eax                        ; keep
    mov     edi, [rsp + 84]
    mov     ecx, r15d
    call    fish_elim
    or      [rsp + 88], eax
    cmp     dword [bad], 0
    jne     .ret
.t_c_next:
    inc     r12d
    jmp     .t_c
.t_b_next:
    inc     ebp
    jmp     .t_b
.t_a_next:
    inc     ebx
    jmp     .t_a
.dnext:
    inc     r13d
    cmp     r13d, 10
    jb      .dloop
    inc     dword [rsp + 84]
    cmp     dword [rsp + 84], 2
    jb      .axis_loop
.ret:
    mov     eax, [rsp + 88]
    add     rsp, 104
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int solve(const uint8_t *grid rdi, char *out rsi)
; Applies the techniques to a fixpoint, cheapest first, then validates
; the finished grid against all 27 units before writing it out.
; ---------------------------------------------------------------------
solve:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                        ; grid
    mov     r13, rsi                        ; out
    vpxor   xmm0, xmm0, xmm0
    vmovdqu [placed], ymm0
    vmovdqu [placed + 32], ymm0
    vmovdqu [placed + 64], ymm0
    vzeroupper
    mov     dword [bad], 0
    xor     ebx, ebx
.init:
    movzx   ecx, byte [r12 + rbx]
    mov     eax, ALL
    test    ecx, ecx
    jz      .init_store
    mov     eax, 1
    shl     eax, cl                         ; 1 << digit
.init_store:
    mov     [cand + rbx*2], ax
    inc     ebx
    cmp     ebx, 81
    jb      .init
.fixpoint:
    call    naked_singles
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    call    hidden_singles
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    call    naked_pairs
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    call    hidden_pairs
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    call    pointing_and_boxline
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    mov     edi, 2
    call    fish
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    mov     edi, 3
    call    fish
    cmp     dword [bad], 0
    jne     .fail
    test    eax, eax
    jnz     .fixpoint
    ; ---- every cell must hold exactly one candidate ----
    xor     ebx, ebx
.chk_cell:
    movzx   eax, word [cand + rbx*2]
    popcnt  ecx, eax
    cmp     ecx, 1
    jne     .fail
    inc     ebx
    cmp     ebx, 81
    jb      .chk_cell
    ; ---- and every unit must hold all nine digits ----
    xor     ebx, ebx                        ; u
.chk_unit:
    lea     r14, [UNITS + rbx + rbx*8]
    xor     ecx, ecx
    xor     edx, edx
.chk_k:
    movzx   eax, byte [r14 + rcx]
    movzx   eax, word [cand + rax*2]
    or      edx, eax
    inc     ecx
    cmp     ecx, 9
    jb      .chk_k
    cmp     edx, ALL
    jne     .fail
    inc     ebx
    cmp     ebx, 27
    jb      .chk_unit
    xor     ebx, ebx
.emit:
    movzx   eax, word [cand + rbx*2]
    tzcnt   eax, eax
    add     eax, '0'
    mov     [r13 + rbx], al
    inc     ebx
    cmp     ebx, 81
    jb      .emit
    mov     eax, 1
    jmp     .ret
.fail:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
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
    lea     rdi, [grids + r15]
    lea     rsi, [sols + r15]
    call    solve
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
    lea     rax, [rax + rax*8]
    lea     rsi, [sols + rax]
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rsi + 32]
    vmovdqu xmm2, [rsi + 64]
    vmovdqu [rsp], ymm0
    vmovdqu [rsp + 32], ymm1
    vmovdqu [rsp + 64], xmm2
    movzx   eax, byte [rsi + 80]
    mov     [rsp + 80], al
    mov     byte [rsp + 81], 10
    vzeroupper
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
