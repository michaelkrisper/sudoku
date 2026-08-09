; mrv parallelized over puzzles: worker threads pull (rep, puzzle) tasks
; off a shared atomic counter (dynamic scheduling; puzzle cost varies).
;
; x86-64 port of impl/c/mrv_mt.c. The solver core is identical to
; impl/asm/mrv.asm -- all mutable solver state lives in the calling
; thread's own stack frame, so the same code is reentrant across threads.
; The task counter is a single `lock xadd` on its own cache line.
; libc/pthreads are used for I/O, parsing, timing and thread plumbing
; only; the solver itself is hand-written assembly.
; Requires Haswell+ (BMI1/BMI2: tzcnt/blsi/blsr/rorx).

%define MAXP 100000                 ; max puzzles held in static storage
%define MAXT 4096                   ; max worker threads
%define ALLC 0x03FE                 ; bits 1..9 set
%define EOFF 64                     ; offset of E[] inside the solver frame

global main
extern fgets, strtol, clock_gettime, fwrite, fprintf
extern pthread_create, pthread_join
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

section .bss
align 32
grids:   resb MAXP * 81             ; parsed puzzles, one digit per byte
sols:    resb MAXP * 81             ; solved grids
okbuf:   resb MAXP
alignb 64
EPACK:   resd 81                    ; per-cell packed offsets, see mrv.asm
alignb 64
g_next:  resq 1                     ; shared task counter, own cache line
alignb 64
g_total: resq 1                     ; reps * npuz
g_npuz:  resq 1
g_lastrep: resq 1                   ; first task index of the final repetition
nthread: resq 1
tids:    resq MAXT

section .rodata
fmt_ns:  db "ns=%lu", 10, 0
uns_str: db "UNSOLVED", 10

section .text

; ---------------------------------------------------------------------
; init_tables: EPACK[i]. Startup only, plain div is fine.
; ---------------------------------------------------------------------
init_tables:
    xor     r8d, r8d                ; i
.i_loop:
    mov     eax, r8d
    xor     edx, edx
    mov     ecx, 9
    div     ecx                     ; eax = row, edx = col
    lea     r9d, [rax + rax]        ; rowoff = row*2
    lea     r10d, [rdx + rdx + 18]  ; coloff = 18 + col*2
    mov     r11d, edx               ; col
    xor     edx, edx
    mov     ecx, 3
    div     ecx                     ; eax = row/3
    lea     esi, [rax + rax*2]      ; (row/3)*3
    mov     eax, r11d
    xor     edx, edx
    div     ecx                     ; eax = col/3
    add     esi, eax                ; box
    lea     esi, [rsi + rsi + 36]   ; boxoff = 36 + box*2
    shl     r10d, 8
    or      r9d, r10d
    shl     esi, 16
    or      r9d, esi
    mov     eax, r8d
    shl     eax, 24
    or      r9d, eax
    mov     [EPACK + r8*4], r9d
    inc     r8d
    cmp     r8d, 81
    jb      .i_loop
    ret

; ---------------------------------------------------------------------
; bool bt(uint32_t k edi)
; Fixed across the whole recursion: r15 = solver frame, r14 = grid,
; r13d = number of empty cells. Preserves r13/r14/r15.
; ---------------------------------------------------------------------
bt:
    cmp     edi, r13d
    je      .all_placed
    push    rbx
    push    rbp
    push    r12
    sub     rsp, 32                 ; [rsp] k, +8/+16/+24 mask pointers
    mov     [rsp], edi
    mov     esi, edi                ; j = k
    lea     rdi, [r15 + EOFF]       ; E
    mov     r9d, esi                ; best_j
    mov     r10d, 10                ; best_n
    xor     r11d, r11d              ; best_cand
.scan:
    mov     eax, [rdi + rsi*4]
    movzx   ecx, al                 ; rowoff
    movzx   ecx, word [r15 + rcx]
    rorx    edx, eax, 8
    movzx   edx, dl                 ; coloff
    and     cx, [r15 + rdx]
    rorx    r8d, eax, 16
    movzx   r8d, r8b                ; boxoff
    and     cx, [r15 + r8]
    popcnt  edx, ecx
    cmp     edx, r10d
    jae     .scan_next
    test    edx, edx
    jz      .dead_end               ; cell with no candidate left
    mov     r9d, esi
    mov     r10d, edx
    mov     r11d, ecx
    cmp     edx, 1
    je      .scan_done              ; forced cell, can't do better
.scan_next:
    inc     esi
    cmp     esi, r13d
    jb      .scan
.scan_done:
    ; swap the chosen entry to slot k so the tail stays a clean partition
    mov     ecx, [rsp]
    mov     eax, [rdi + r9*4]
    mov     edx, [rdi + rcx*4]
    mov     [rdi + r9*4], edx
    mov     [rdi + rcx*4], eax
    movzx   ecx, al
    lea     rcx, [r15 + rcx]
    mov     [rsp + 8], rcx          ; &rows[r]
    rorx    edx, eax, 8
    movzx   edx, dl
    lea     rdx, [r15 + rdx]
    mov     [rsp + 16], rdx         ; &cols[c]
    rorx    edx, eax, 16
    movzx   edx, dl
    lea     rdx, [r15 + rdx]
    mov     [rsp + 24], rdx         ; &boxes[b]
    shr     eax, 24
    mov     ebx, eax                ; cell index
    mov     ebp, r11d               ; candidate set
.branch:
    test    ebp, ebp
    jz      .exhausted
    blsi    r12d, ebp               ; lowest candidate bit
    blsr    ebp, ebp
    tzcnt   ecx, r12d
    mov     [r14 + rbx], cl         ; g[i] = digit
    mov     rax, [rsp + 8]
    xor     [rax], r12w
    mov     rax, [rsp + 16]
    xor     [rax], r12w
    mov     rax, [rsp + 24]
    xor     [rax], r12w
    mov     edi, [rsp]
    inc     edi
    call    bt
    test    eax, eax
    jnz     .solved
    mov     rax, [rsp + 8]
    xor     [rax], r12w
    mov     rax, [rsp + 16]
    xor     [rax], r12w
    mov     rax, [rsp + 24]
    xor     [rax], r12w
    jmp     .branch
.exhausted:
    mov     byte [r14 + rbx], 0
.dead_end:
    xor     eax, eax
    jmp     .ret
.solved:
    mov     eax, 1
.ret:
    add     rsp, 32
    pop     r12
    pop     rbp
    pop     rbx
    ret
.all_placed:
    mov     eax, 1
    ret

; ---------------------------------------------------------------------
; bool solve(uint8_t *g rdi) -- solves in place, all state on our stack.
; ---------------------------------------------------------------------
solve:
    push    rbp
    mov     rbp, rsp
    push    r13
    push    r14
    push    r15
    and     rsp, -64
    sub     rsp, 448                ; EOFF + 81*4 rounded up to a multiple of 64
    mov     r15, rsp
    mov     r14, rdi
    mov     eax, ALLC
    vmovd   xmm0, eax
    vpbroadcastw ymm0, xmm0
    vmovdqa [r15], ymm0             ; units[0..15]
    vmovdqu [r15 + 22], ymm0        ; units[11..26]
    xor     esi, esi                ; i
    xor     r13d, r13d              ; number of empty cells
.clue_loop:
    movzx   eax, byte [r14 + rsi]   ; digit
    mov     edx, [EPACK + rsi*4]
    test    eax, eax
    jz      .empty
    mov     ecx, eax
    mov     eax, 1
    shl     eax, cl                 ; bit = 1 << d (d = 10 for bad lines)
    movzx   ecx, dl
    rorx    r9d, edx, 8
    movzx   r9d, r9b
    rorx    r10d, edx, 16
    movzx   r10d, r10b
    movzx   r8d, word [r15 + rcx]
    and     r8w, [r15 + r9]
    and     r8w, [r15 + r10]
    test    r8d, eax
    jz      .fail                   ; duplicate or impossible clue
    xor     [r15 + rcx], ax
    xor     [r15 + r9], ax
    xor     [r15 + r10], ax
    jmp     .clue_next
.empty:
    mov     [r15 + EOFF + r13*4], edx
    inc     r13d
.clue_next:
    inc     esi
    cmp     esi, 81
    jb      .clue_loop
    xor     edi, edi
    call    bt
    jmp     .ret
.fail:
    xor     eax, eax
.ret:
    lea     rsp, [rbp - 24]
    pop     r15
    pop     r14
    pop     r13
    pop     rbp
    ret

; ---------------------------------------------------------------------
; void *worker(void *) -- drain the shared task queue.
; Task t solves puzzle t % npuz; only the final repetition writes results,
; so every output slot is written exactly once.
; ---------------------------------------------------------------------
worker:
    push    rbx
    push    rbp
    push    r12
    sub     rsp, 96                 ; [rsp] = working copy of the grid
.loop:
    mov     eax, 1
    lock xadd [g_next], rax         ; t = g_next++
    cmp     rax, [g_total]
    jae     .done
    mov     rbx, rax                ; t
    xor     edx, edx
    div     qword [g_npuz]
    mov     r12, rdx                ; p = t % npuz
    lea     rax, [r12 + r12*8]
    lea     rax, [rax + rax*8]      ; p*81
    lea     rsi, [grids + rax]
    mov     rdi, rsp
    COPY81  rdi, rsi
    mov     rdi, rsp
    call    solve
    cmp     rbx, [g_lastrep]
    jb      .loop
    mov     [okbuf + r12], al
    lea     rcx, [r12 + r12*8]
    lea     rcx, [rcx + rcx*8]
    lea     rdi, [sols + rcx]
    mov     rsi, rsp
    COPY81  rdi, rsi
    jmp     .loop
.done:
    vzeroupper
    xor     eax, eax
    add     rsp, 96
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
    ; reps = argv[1], threads = argv[2], both default and clamped to >= 1
    mov     rbp, 1
    mov     qword [nthread], 1
    cmp     edi, 2
    jl      .no_args
    mov     r15d, edi               ; argc
    mov     rbx, rsi                ; argv
    mov     rdi, [rbx + 8]
    xor     esi, esi
    mov     edx, 10
    call    strtol wrt ..plt
    cmp     rax, 1
    jl      .reps_done
    mov     rbp, rax
.reps_done:
    cmp     r15d, 3
    jl      .no_args
    mov     rdi, [rbx + 16]
    xor     esi, esi
    mov     edx, 10
    call    strtol wrt ..plt
    cmp     rax, 1
    jl      .no_args
    cmp     rax, MAXT
    jbe     .thr_ok
    mov     eax, MAXT
.thr_ok:
    mov     [nthread], rax
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
    mov     [g_npuz], r12
    mov     rax, rbp
    imul    rax, r12                ; total = reps * n
    mov     [g_total], rax
    sub     rax, r12
    mov     [g_lastrep], rax        ; first task of the last repetition
    mov     qword [g_next], 0
    ; ---- timed region: spawn, work, join ----
    mov     edi, 1                  ; CLOCK_MONOTONIC
    lea     rsi, [rsp + 512]
    call    clock_gettime wrt ..plt
    mov     r14, [nthread]
    dec     r14                     ; main thread is a worker too
    xor     r13d, r13d              ; spawned
.spawn_loop:
    cmp     r13, r14
    jae     .spawn_done
    lea     rdi, [tids + r13*8]
    xor     esi, esi
    mov     edx, worker
    xor     ecx, ecx
    call    pthread_create wrt ..plt
    test    eax, eax
    jnz     .spawn_done             ; main thread still drains the queue
    inc     r13
    jmp     .spawn_loop
.spawn_done:
    xor     edi, edi
    call    worker
    xor     r14d, r14d
.join_loop:
    cmp     r14, r13
    jae     .join_done
    mov     rdi, [tids + r14*8]
    xor     esi, esi
    call    pthread_join wrt ..plt
    inc     r14
    jmp     .join_loop
.join_done:
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
