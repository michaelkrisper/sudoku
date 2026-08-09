; Norvig-style constraint propagation + search (bitmask candidates).
;
; x86-64 port of impl/c/norvig.c: eliminate + naked singles + hidden
; singles to a fixpoint, then depth-first search with MRV cell choice.
; libc is used for I/O, parsing and timing only; the solver itself
; (eliminate/assign/search/solve) is hand-written assembly.
; Requires Haswell+ (AVX2, BMI1: tzcnt/popcnt/andn/blsi).

%define MAXP 100000                 ; max puzzles held in static storage
%define ALLC 0x03FE                 ; bits 1..9 set

global main
extern fgets, strtol, clock_gettime, fwrite, fprintf
extern stdin, stdout, stderr

; copy a 162-byte candidate array: 5x32-byte AVX + trailing word.
; clobbers eax, ymm0-ymm4.
%macro COPY162 2                    ; %1 = dst reg, %2 = src reg
    vmovdqu ymm0, [%2]
    vmovdqu ymm1, [%2 + 32]
    vmovdqu ymm2, [%2 + 64]
    vmovdqu ymm3, [%2 + 96]
    vmovdqu ymm4, [%2 + 128]
    movzx   eax, word [%2 + 160]
    vmovdqu [%1], ymm0
    vmovdqu [%1 + 32], ymm1
    vmovdqu [%1 + 64], ymm2
    vmovdqu [%1 + 96], ymm3
    vmovdqu [%1 + 128], ymm4
    mov     [%1 + 160], ax
%endmacro

section .bss
align 32
grids:   resb MAXP * 81             ; parsed puzzles, one digit per byte
cands:   resb MAXP * 162            ; uint16 cand[81] per puzzle
okbuf:   resb MAXP
PEERS:   resb 81 * 20
UNITS:   resb 27 * 9
UNIT_OF: resb 81 * 3

section .rodata
fmt_ns:  db "ns=%lu", 10, 0
uns_str: db "UNSOLVED", 10

section .text

; ---------------------------------------------------------------------
; init_tables: build UNITS[27][9], UNIT_OF[81][3], PEERS[81][20].
; No calls inside; uses caller-saved regs + 96 stack bytes for seen[].
; ---------------------------------------------------------------------
init_tables:
    sub     rsp, 96
    ; rows and columns
    xor     ecx, ecx                ; r
.r_loop:
    xor     edx, edx                ; c
.c_loop:
    lea     eax, [rcx + rcx*8]      ; r*9
    add     eax, edx                ; cell = r*9 + c
    mov     [UNITS + rax], al       ; UNITS[r][c]: offset r*9+c == value
    lea     esi, [rdx + rdx*8]      ; c*9
    add     esi, ecx
    mov     [UNITS + 81 + rsi], al  ; UNITS[9+c][r]
    inc     edx
    cmp     edx, 9
    jb      .c_loop
    inc     ecx
    cmp     ecx, 9
    jb      .r_loop
    ; boxes: b = br*3+bc, k = kr*3+kc
    xor     r8d, r8d                ; br
.br_loop:
    xor     r9d, r9d                ; bc
.bc_loop:
    lea     eax, [r8 + r8*2]
    add     eax, r9d                ; b
    lea     eax, [rax + rax*8]      ; b*9
    lea     rdi, [UNITS + 162 + rax]
    xor     r10d, r10d              ; kr
.kr_loop:
    xor     r11d, r11d              ; kc
.kc_loop:
    lea     eax, [r8 + r8*2]        ; br*3
    add     eax, r10d
    lea     eax, [rax + rax*8]      ; (br*3+kr)*9
    lea     ecx, [r9 + r9*2]        ; bc*3
    add     eax, ecx
    add     eax, r11d
    mov     [rdi], al
    inc     rdi
    inc     r11d
    cmp     r11d, 3
    jb      .kc_loop
    inc     r10d
    cmp     r10d, 3
    jb      .kr_loop
    inc     r9d
    cmp     r9d, 3
    jb      .bc_loop
    inc     r8d
    cmp     r8d, 3
    jb      .br_loop
    ; UNIT_OF and PEERS
    xor     r8d, r8d                ; i
.i_loop:
    mov     eax, r8d
    xor     edx, edx
    mov     ecx, 9
    div     ecx                     ; eax = i/9, edx = i%9
    lea     r9, [UNIT_OF + r8 + r8*2]
    mov     [r9], al                ; unit 0: row
    lea     esi, [rdx + 9]
    mov     [r9 + 1], sil           ; unit 1: 9 + col
    mov     r10d, edx               ; save i%9
    xor     edx, edx
    mov     ecx, 3
    div     ecx                     ; eax = i/27
    lea     esi, [rax + rax*2]      ; (i/27)*3
    mov     eax, r10d
    xor     edx, edx
    div     ecx                     ; eax = (i%9)/3
    add     esi, eax
    add     esi, 18
    mov     [r9 + 2], sil           ; unit 2: box
    ; seen[] on stack, cleared
    vpxor   xmm0, xmm0, xmm0
    vmovdqu [rsp], ymm0
    vmovdqu [rsp + 32], ymm0
    vmovdqu [rsp + 64], ymm0
    mov     byte [rsp + r8], 1      ; seen[i] = true
    lea     rax, [r8 + r8*4]
    shl     rax, 2
    lea     r11, [PEERS + rax]      ; write ptr &PEERS[i][0]
    xor     ecx, ecx                ; t
.t_loop:
    movzx   eax, byte [r9 + rcx]    ; unit index
    lea     rdi, [UNITS + rax + rax*8]
    xor     edx, edx                ; k
.k_loop:
    movzx   eax, byte [rdi + rdx]   ; j
    cmp     byte [rsp + rax], 0
    jne     .k_next
    mov     byte [rsp + rax], 1
    mov     [r11], al
    inc     r11
.k_next:
    inc     edx
    cmp     edx, 9
    jb      .k_loop
    inc     ecx
    cmp     ecx, 3
    jb      .t_loop
    inc     r8d
    cmp     r8d, 81
    jb      .i_loop
    vzeroupper
    add     rsp, 96
    ret

; ---------------------------------------------------------------------
; bool eliminate(uint16_t *cand rdi, uint32_t i esi, uint32_t bit edx)
; ---------------------------------------------------------------------
eliminate:
    movzx   eax, word [rdi + rsi*2]
    test    eax, edx
    jz      .true_nf                ; bit already absent
    andn    eax, edx, eax           ; c &= ~bit
    jz      .false_nf               ; last candidate removed
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi                ; cand
    mov     r12d, esi               ; i
    mov     r13d, edx               ; bit
    mov     ebp, eax                ; c (new value)
    mov     [rbx + r12*2], ax
    lea     ecx, [rbp - 1]
    test    ebp, ecx
    jnz     .hidden                 ; more than one bit left
    ; naked single: strip c from all 20 peers
    lea     r14, [r12 + r12*4]
    shl     r14, 2
    lea     r14, [PEERS + r14]
    xor     r15d, r15d
.peer_loop:
    movzx   esi, byte [r14 + r15]   ; p
    movzx   eax, word [rbx + rsi*2]
    test    eax, ebp
    jz      .peer_next
    mov     rdi, rbx
    mov     edx, ebp
    call    eliminate
    test    eax, eax
    jz      .ret_false
.peer_next:
    inc     r15d
    cmp     r15d, 20
    jb      .peer_loop
.hidden:
    ; hidden single: does `bit` have exactly one place in each unit of i?
    lea     r14, [UNIT_OF + r12 + r12*2]
    xor     r15d, r15d              ; t
.unit_loop:
    movzx   eax, byte [r14 + r15]   ; unit index
    lea     rcx, [UNITS + rax + rax*8]
    mov     r9d, -1                 ; place
    xor     r8d, r8d                ; k
.scan:
    movzx   eax, byte [rcx + r8]    ; u[k]
    movzx   edx, word [rbx + rax*2]
    test    edx, r13d
    jz      .scan_next
    cmp     r9d, -1
    jne     .two_places
    mov     r9d, eax
    jmp     .scan_next
.two_places:
    mov     r9d, -2
    jmp     .scan_done
.scan_next:
    inc     r8d
    cmp     r8d, 9
    jb      .scan
.scan_done:
    cmp     r9d, -1
    je      .ret_false              ; bit has nowhere left in unit
    test    r9d, r9d
    js      .unit_next              ; two or more places
    movzx   eax, word [rbx + r9*2]
    lea     edx, [rax - 1]
    test    eax, edx
    jz      .unit_next              ; already a single there
    mov     rdi, rbx
    mov     esi, r9d
    mov     edx, r13d
    call    assign
    test    eax, eax
    jz      .ret_false
.unit_next:
    inc     r15d
    cmp     r15d, 3
    jb      .unit_loop
    mov     eax, 1
    jmp     .ret
.ret_false:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
.true_nf:
    mov     eax, 1
    ret
.false_nf:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------
; bool assign(uint16_t *cand rdi, uint32_t i esi, uint32_t bit edx)
; eliminate every other candidate of cell i.
; ---------------------------------------------------------------------
assign:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12d, esi
    movzx   eax, word [rdi + rsi*2]
    andn    r13d, edx, eax          ; other = cand[i] & ~bit
.loop:
    test    r13d, r13d
    jz      .true
    blsi    ecx, r13d               ; lowest set bit
    xor     r13d, ecx
    mov     rdi, rbx
    mov     esi, r12d
    mov     edx, ecx
    call    eliminate
    test    eax, eax
    jz      .false
    jmp     .loop
.true:
    mov     eax, 1
    jmp     .ret
.false:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------
; bool search(uint16_t *cand rdi)
; DFS with minimum-remaining-values cell choice. On success cand holds
; the solved grid (all cells single bits). Trial array lives on the
; machine stack (162 bytes/frame, depth <= 81).
; ---------------------------------------------------------------------
search:
    push    rbx
    push    rbp
    push    r12
    push    r13
    sub     rsp, 184                ; trial[81] at [rsp], keeps rsp 16-aligned
    mov     rbx, rdi
    mov     ebp, -1                 ; best
    mov     r12d, 10                ; best_n
    xor     ecx, ecx
.scan:
    movzx   eax, word [rbx + rcx*2]
    lea     edx, [rax - 1]
    test    eax, edx
    jz      .scan_next              ; single bit: cell done
    popcnt  edx, eax
    cmp     edx, r12d
    jge     .scan_next
    mov     r12d, edx
    mov     ebp, ecx
    cmp     edx, 2
    je      .scan_done              ; can't do better than 2
.scan_next:
    inc     ecx
    cmp     ecx, 81
    jb      .scan
.scan_done:
    cmp     ebp, -1
    je      .solved                 ; all cells singles
    movzx   r13d, word [rbx + rbp*2]
.branch:
    test    r13d, r13d
    jz      .false
    blsi    r12d, r13d              ; bit to try
    xor     r13d, r12d
    COPY162 rsp, rbx                ; trial = cand
    mov     rdi, rsp
    mov     esi, ebp
    mov     edx, r12d
    call    assign
    test    eax, eax
    jz      .branch
    mov     rdi, rsp
    call    search
    test    eax, eax
    jz      .branch
    COPY162 rbx, rsp                ; cand = trial
.solved:
    mov     eax, 1
    jmp     .ret
.false:
    xor     eax, eax
.ret:
    add     rsp, 184
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------
; bool solve(const uint8_t *grid rdi, uint16_t *cand rsi)
; ---------------------------------------------------------------------
solve:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi                ; grid
    mov     rbx, rsi                ; cand
    mov     eax, ALLC
    vmovd   xmm0, eax
    vpbroadcastw ymm0, xmm0
    vmovdqu [rbx], ymm0
    vmovdqu [rbx + 32], ymm0
    vmovdqu [rbx + 64], ymm0
    vmovdqu [rbx + 96], ymm0
    vmovdqu [rbx + 128], ymm0
    mov     word [rbx + 160], ALLC
    xor     r13d, r13d              ; i
.clue_loop:
    movzx   eax, byte [r12 + r13]
    test    eax, eax
    jz      .clue_next
    mov     ecx, eax
    mov     eax, 1
    shl     eax, cl                 ; bit = 1 << d (d = 10 for bad lines)
    cmp     word [rbx + r13*2], ax
    je      .clue_next
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, eax
    call    assign
    test    eax, eax
    jz      .ret
.clue_next:
    inc     r13d
    cmp     r13d, 81
    jb      .clue_loop
    mov     rdi, rbx
    call    search
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------
; int main(int argc char **argv)
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
    lea     rdi, [grids + rax]
    lea     rsi, [cands + rax*2]    ; i*162
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
    lea     rsi, [cands + rax*2]
    xor     ecx, ecx
.dig_loop:
    movzx   eax, word [rsi + rcx*2]
    tzcnt   eax, eax
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
