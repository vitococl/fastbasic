;
; FastBasic - Fast basic interpreter for the Atari 8-bit computers
; Copyright (C) 2017 Daniel Serpell
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program.  If not, see <http://www.gnu.org/licenses/>
;

; State machine actions (external subs)
; -------------------------------------

        .export         E_REM, E_EOL, E_NUMBER, E_HEXNUMBER
        .export         E_PUSH_LOOP, E_POP_LOOP, E_PUSH_REPEAT, E_POP_REPEAT
        .export         E_PUSH_IF, E_POP_IF, E_ELSE, E_EXIT_LOOP
        .export         E_PUSH_WHILE, E_PUSH_WHILE2, E_POP_WHILE
        .export         E_PUSH_PROC, E_POP_PROC
        .export         E_PUSH_FOR, E_PUSH_FOR2, E_POP_FOR
        .export         E_CONST_STRING
        .export         E_VAR_CREATE, E_VAR_WORD, E_VAR_ARRAY_BYTE, E_VAR_ARRAY_WORD
        .export         E_VAR_SET_TYPE, E_VAR_STRING
        .export         E_LABEL, E_LABEL_DEF
        .export         check_labels
        .exportzp       VT_WORD, VT_ARRAY_WORD, VT_ARRAY_BYTE, VT_STRING
        .exportzp       loop_sp
        .importzp       bpos, blen, bmax, bptr, tmp1, tmp2, tmp3, opos
        ; From runtime.asm
        .import         umul16, sdiv16, read_word
        ; From vars.asm
        .import         var_search, var_new, var_getlen, var_set_type
        .import         label_search, label_new
        .importzp       var_namelen
        ; From alloc.asm
        .import         alloc_laddr
        .importzp       prog_ptr, laddr_ptr, laddr_buf
        ; From parser.asm
        .import         parser_error, parser_skipws
        .importzp       TOK_CSTRING
        ; From error.asm
        .importzp       ERR_LOOP, ERR_VAR

;----------------------------------------------------------
        ; Types of variables
        .enum
                VT_UNDEF
                VT_WORD
                VT_ARRAY_WORD
                VT_ARRAY_BYTE
                VT_STRING
        .endenum
        ; Types of labels
        .enum
                LBL_UNDEF       = 0
                LBL_PROC
        .endenum
;----------------------------------------------------------
        .zeropage
loop_sp:        .res    1

        ; TODO: this space should be reclaimed by the interpreter!
        .bss
loop_stk:       .res    128

;----------------------------------------------------------
; Parser initialization here:
        .segment "PINIT"
        lda     #0
        sta     loop_sp

;----------------------------------------------------------
        .code

; Emits 16bit AX into codep
.proc   emit_AX
        ldy     opos
new_y:  sta     (prog_ptr),y
        txa
        iny
        sta     (prog_ptr),y
        iny
        sty     opos
        clc
        rts
.endproc

; Parser external subs
.proc   E_REM
        ; Accept all the line
        ldy     blen
        sty     bpos
        sty     bmax
ok:     clc
        rts
.endproc

.proc   E_EOL
        ldy     bpos
        cpy     blen
        beq     E_REM::ok
        lda     (bptr),y
        cmp     #$9b ; Atari EOL
        beq     E_REM::ok
        cmp     #$0A ; ASCII EOL
        beq     E_REM::ok
        sec
        rts
.endproc

.proc   E_HEXNUMBER
        ldx     #0
        stx     tmp1+1

        ldy     bpos

nloop:
        ; Check length
        cpy     blen
        beq     xit
        ; Read a number
        lda     (bptr),y
        sec
        sbc     #'0'
        cmp     #10
        bcc     digit
        cmp     #'A'-'0'
        bcc     xit
        sbc     #'A'-'0'-10
        cmp     #16
        bcs     xit ; Not an hex number

digit:
        iny             ; Accept
        cpy     bmax
        bcc     :+
        sty     bmax
:
        sta     tmp1    ; and save digit

        ; Check OF
        cpx     #<$FFF
        lda     tmp1+1
        sbc     #>$FFF
        bcs     ebig

        ; Multiply tmp by 16
        txa
        asl
        rol     tmp1+1
        asl
        rol     tmp1+1
        asl
        rol     tmp1+1
        asl
        rol     tmp1+1

        ; Add new digit
        ora     tmp1
        tax
        bcc     nloop

ebig:
        sec
        rts

xit:
        cpy     bpos
        beq     ebig

        sty     bpos

        txa
        ldx     tmp1+1
        jmp     emit_AX
.endproc

.proc   E_NUMBER
        ldx     #0
        stx     tmp1+1

        ldy     bpos
        jsr     read_word
        bcs     xit
        cpy     bmax
        bcc     :+
        sty     bmax
:       sty     bpos
        jmp     emit_AX
xit:    rts
.endproc

.proc   E_CONST_STRING
        ; Get characters until a '"' - emit all characters read!
        ldx     #0
        ; Store original output position
        lda     opos
        sta     tmp1
        ; Increase by two (token and length)
        inc     opos
        inc     opos
nloop:
        ; Check length
        ldy     bpos
        cpy     blen
        beq     err
        lda     (bptr), y
        iny
        cpy     bmax
        bcc     :+
        sty     bmax
:       sty     bpos
        cmp     #'"'
        beq     eos
        ; Store
store:  inx
        ldy     opos
        sta     (prog_ptr),y
        inc     opos
        bne     nloop
err:    ; Restore opos and exit
        lda     tmp1
        sta     opos
        sec
        rts
eos:    lda     (bptr), y
        iny
        cmp     #'"'    ; Check for "" to encode one ".
        beq     store
        ; Store token and length
        ldy     tmp1
        lda     #TOK_CSTRING
        sta     (prog_ptr), y
        iny
        txa
        sta     (prog_ptr), y
        ; And adds an extra character to properly terminate string on IO operations
        ldy     opos
        sta     (prog_ptr),y
        inc     opos
        clc
        rts
.endproc


; Variable marching.
; The parser calls the routine to check if there is a variable
; with the correct type
.proc   E_VAR_STRING
        lda     #VT_STRING
        .byte   $2C   ; Skip 2 bytes over next "LDA"
.endproc        ; Fall through
.proc   E_VAR_ARRAY_BYTE
        lda     #VT_ARRAY_BYTE
        .byte   $2C   ; Skip 2 bytes over next "LDA"
.endproc        ; Fall through
.proc   E_VAR_ARRAY_WORD
        lda     #VT_ARRAY_WORD
        .byte   $2C   ; Skip 2 bytes over next "LDA"
.endproc        ; Fall through
.proc   E_VAR_WORD
        lda     #VT_WORD
        sta     tmp3    ; Store variable type
        jsr     parser_skipws
        ; Check if we have a valid name - this exits on error!
        jsr     var_getlen
        ; Search existing var
        jsr     var_search
        bcs     exit
        cmp     tmp3
        bne     not_found
        jmp     emit_varn
not_found:
        sec
exit:
        rts
.endproc

; Creates a new variable, with no type (the type will be set by parser next)
.proc   E_VAR_CREATE
        jsr     parser_skipws
        ; Check if we have a valid name - this exits on error!
        jsr     var_getlen
        ; Search existing var
        jsr     var_search
        bcc     E_VAR_WORD::not_found ; Exit with error if already exists
        ; Create new variable - exits on error
        jsr     var_new
        stx     last_var_num
        ; Fall through
.endproc
        ; Emits the variable, advancing pointers.
.proc   emit_varn
        ; Store VARN
        txa
        ldy     opos
        sta     (prog_ptr),y
        inc     opos
        ; Fall through
.endproc
        ; Advances variable name in source pointer
.proc   advance_varn
        lda     bpos
        clc
        adc     var_namelen
        tay
        cpy     bmax
        bcc     :+
        sty     bmax
:       sty     bpos
        jsr     parser_skipws
        clc
        rts
.endproc

; Sets the type of a variable - variable number and new type must be in the stack:
.proc   E_VAR_SET_TYPE
        dec     opos            ; Remove variable TYPE from stack
        ldy     opos
        lda     (prog_ptr),y    ; The variable TYPE
        ldx     #$00            ; The variable NUMBER
::last_var_num= * - 1
        jmp     var_set_type
.endproc

        ; Adds a label address pointer to the list
.proc   add_laddr_list
        stx     var_n+1
        sty     var_t+1

        lda     laddr_ptr
        sta     tmp2
        lda     laddr_ptr+1
        sta     tmp2+1

        lda     #4
        jsr     alloc_laddr
        bcs     xit

        ldy     #0
var_t:  lda     #0
        sta     (tmp2), y
        iny
var_n:  lda     #0
        sta     (tmp2), y
        ldy     #3
        lda     prog_ptr
        clc
        adc     opos
        sta     (tmp2), y
        dey
        lda     prog_ptr+1
        adc     #0
        sta     (tmp2), y
        clc
xit:    rts
.endproc

.proc   inc_laddr
        lda     tmp1
        clc
        adc     #4
        sta     tmp1
        bcc     comp
        inc     tmp1+1
comp:
        lda     tmp1
        cmp     laddr_ptr
        lda     tmp1+1
        sbc     laddr_ptr+1
        rts
.endproc

.proc   label_create
        jsr     parser_skipws
        ; Check if we have a valid name - this exits on error!
        jsr     var_getlen
        jsr     label_search
        bcc     xit
        ; Create a new label
        jsr     label_new
xit:    rts
.endproc

; Label search / create (on use)
.proc   E_LABEL
        jsr     label_create
        ; Emits a label, searching the label address in the label list
        stx     l_num + 1
        lda     laddr_buf
        ldy     laddr_buf+1
        sta     tmp1
        sty     tmp1+1

        jsr     inc_laddr::comp
        bcs     nfound

        ; Check label number
cloop:  ldy     #0
        lda     (tmp1), y
        bpl     next    ; 0 == label not defined, 1 == label defined, 128 == label address
        iny
        lda     (tmp1), y
l_num:  cmp     #$00
        bne     next
        ; Found, get address from label and emit
        iny
        lda     (tmp1), y
        tax
        iny
        lda     (tmp1), y
emit_end:
        jsr     emit_AX
        jmp     advance_varn
next:
        jsr     inc_laddr
        bcc     cloop
        ; Not found, add to the label address list
nfound: ldy     #0
        jsr     add_laddr_list
        bcs     ret
        lda     #0
        tax
        beq     emit_end
ret:    rts
.endproc

; Label definition search/create
.proc   E_LABEL_DEF
        jsr     label_create
        stx     l_num + 1

        ; Fills all undefined labels with current position - saved for the label
        lda     laddr_buf
        ldy     laddr_buf+1
        sta     tmp1
        sty     tmp1+1

        jsr     inc_laddr::comp
        bcs     nfound

        ; Check label number
cloop:  ldy     #1
        lda     (tmp1), y
l_num:  cmp     #$00
        bne     next    ; not our label
        dey
        lda     (tmp1), y
        bmi     error   ; label already defined
        ; Copy address
        ldy     #2
        lda     (tmp1), y
        sta     tmp2+1
        iny
        lda     (tmp1), y
        sta     tmp2
        ; Set label as "defined"
        tya
        ldy     #0
        sta     (tmp1), y
        ; And fill with current ptr
        ldy     #0
        lda     prog_ptr
        clc
        adc     opos
        sta     (tmp2), y
        iny
        lda     prog_ptr+1
        adc     #0
        sta     (tmp2), y
        ; Continue
next:   jsr     inc_laddr
        bcc     cloop
nfound:
        ldx     l_num + 1
        ldy     #128
        jsr     add_laddr_list
        bcs     error
        jmp     advance_varn
error:  sec
        rts
.endproc

; Check if all labels are defined
.proc   check_labels
        lda     laddr_buf
        ldy     laddr_buf+1
        sta     tmp1
        sty     tmp1+1

        jsr     inc_laddr::comp
        bcs     ok

        ; Check list
cloop:  ldy     #0
        lda     (tmp1), y
        beq     error
        jsr     inc_laddr
        bcc     cloop
ok:     clc
        rts
error:  sec
        rts
.endproc

; Actions for LOOPS
.proc   patch_codep
        ; Patches saved position with current position
        sta     tmp1
        stx     tmp1+1
        ldy     #0
        lda     opos
        clc
        adc     prog_ptr
        sta     (tmp1),y
        iny
        lda     prog_ptr+1
        adc     #0
        sta     (tmp1),y
        rts     ; C is cleared on exit!
.endproc

.proc   push_codep
        ; Saves current code position in loop stack
        ldy     loop_sp
        sta     loop_stk, y
        iny
        lda     prog_ptr
        clc
        adc     opos
        sta     loop_stk, y
        iny
        lda     prog_ptr+1
        adc     #0
        sta     loop_stk, y
        iny
        bmi     loop_error
        sty     loop_sp
        rts     ; C is cleared on exit!
.endproc

.proc   loop_error
        lda     #ERR_LOOP
        jmp     parser_error
.endproc

.proc   pop_codep
        ; Saves current code position in loop stack
        ldy     loop_sp
        dey
        dey
        dey
        sty     loop_sp
        bmi     loop_error
        ; Check if loop type is correct
retry:  cmp     loop_stk, y
        beq     ok
        ; If loop type is "ELSE", accept also "IF"
        cmp     #'E'
        bne     loop_error
        lda     #'I'
        bne     retry
ok:     ; Get saved position
        iny
        iny
        lda     loop_stk, y
        tax
        dey
        lda     loop_stk, y
rtsclc: clc
        rts     ; C is cleared on exit!
.endproc

.proc   check_loop_exit
        ; Checks if there is an "EXIT" in the stack, and adjust target pointer
        ldy     loop_sp
        dey
        dey
        dey
        bmi     pop_codep::rtsclc
        lda     loop_stk, y
        cmp     #'X'
        bne     pop_codep::rtsclc
        ; Yes, pop and patch
        sty     loop_sp
        iny
        iny
        lda     loop_stk, y
        tax
        dey
        lda     loop_stk, y
        jsr     patch_codep
        ; And check for more possible EXIT's
        jmp     check_loop_exit
.endproc

.proc   E_POP_PROC
        ; Pop saved "jump to end" position
        lda     #'P'
        jsr     pop_codep
        jsr     patch_codep
        ; Checks for an "EXIT"
        jmp     check_loop_exit
.endproc

.proc   E_PUSH_LOOP
        ; Push current position, don't emit
        lda     #'D'
        jmp     push_codep
.endproc

.proc   E_POP_LOOP
        ; Pop saved position, store
        lda     #'D'
        jsr     pop_codep
        jsr     emit_AX
        ; Checks for an "EXIT"
        jmp     check_loop_exit
.endproc

.proc   E_PUSH_WHILE
        ; Push current position (loop reentry)
        lda     #'W'
        jmp     push_codep
.endproc

.proc   E_PUSH_WHILE2
        ; Push current position (jump to exit), emit spare bytes (to be filled)
        lda     #'W'
        jsr     push_codep
        jmp     emit_AX
.endproc

.proc   E_POP_WHILE
        ; Pop saved "jump to end" position
        lda     #'W'
        jsr     pop_codep
        ; Save current position + 2 (skip over jump)
        inc     opos
        inc     opos
        jsr     patch_codep
        ; Pop saved "loop reentry" position
        lda     #'W'
        jsr     pop_codep
        ; And store
        dec     opos
        dec     opos
        jsr     emit_AX
        ; Checks for an "EXIT"
        jmp     check_loop_exit
.endproc

.proc   E_PUSH_REPEAT
        ; Push current position
        lda     #'R'
        jmp     push_codep
.endproc

.proc   E_POP_REPEAT
        ; Pop saved position, store
        lda     #'R'
        jsr     pop_codep
        jsr     emit_AX
        ; Checks for an "EXIT"
        jmp     check_loop_exit
.endproc

.proc   E_PUSH_FOR
        ; Push current position (loop reentry)
        lda     #'F'
        jmp     push_codep
.endproc

.proc   E_PUSH_FOR2
        ; Push current position (jump to exit), emit spare bytes (to be filled)
        lda     #'F'
        jsr     push_codep
        jmp     emit_AX
.endproc

.proc   E_POP_FOR
        ; Pop saved "jump to end" position
        lda     #'F'
        jsr     pop_codep
        ; Save current position + 1 (skip over jump)
        inc     opos
        jsr     patch_codep
        ; Pop saved "loop reentry" position
        lda     #'F'
        jsr     pop_codep
        ; And store
        dec     opos
        dec     opos
        jsr     emit_AX
        ; Checks for an "EXIT"
        jmp     check_loop_exit
.endproc

.proc   E_PUSH_PROC
        ; Jumps over the procedure!
        lda     #'P'
        .byte   $2C   ; Skip 2 bytes over next "LDA"
.endproc        ; Fall through
.proc   E_PUSH_IF
        ; Push current position, emit spare bytes (to be filled)
        lda     #'I'
        jsr     push_codep
        jmp     emit_AX
.endproc

.proc   E_POP_IF
        ; Patch IF/ELSE with current position
        lda     #'E'
        jsr     pop_codep
        jmp     patch_codep
.endproc

.proc   E_ELSE
        ; Pop the old position to patch (from IF)
        lda     #'I'
        jsr     pop_codep
        sta     tmp1
        stx     tmp1+1
        ; Emit a jump to a new position
        lda     #'E'
        jsr     push_codep
        ; Emit two dummy bytes
        inc     opos
        inc     opos
        ; Parch current position + 2 (over jump)
        lda     tmp1
        ldx     tmp1+1
        jmp     patch_codep
.endproc

.proc   E_EXIT_LOOP
        ; Search the loop stack for a loop (not "I"f nor "E"lse) and inserts a
        ; patching code before
        ldy     loop_sp
retry:  dey
        dey
        dey
        bmi     loop_error
        lda     loop_stk, y
        cmp     #'I'
        beq     retry
        cmp     #'E'
        beq     retry
        cmp     #'F'
        beq     dec3
        cmp     #'W'
        bne     ok
dec3:   dey     ; While and FOR loops use two slots!
        dey
        dey
ok:
        ; Store slot
        sty     comp_y+1
        ; Check if enough stack
        ldy     loop_sp
        iny
        iny
        iny
        bmi     loop_error

        ; Move all stack 3 positions up
        ldx     #2
move_1:
        ldy     loop_sp
move:
        dey
        lda     loop_stk, y
        iny
        sta     loop_stk, y
        dey
comp_y: cpy     #$FF
        bne     move

        inc     loop_sp
        dex
        bpl     move_1

        ; Store our new stack entry
        ldx     loop_sp
        ldy     comp_y+1
        sty     loop_sp
        lda     #'X'
        jsr     push_codep
        stx     loop_sp
        jmp     emit_AX
loop_error:
        jmp     ::loop_error
.endproc

; vi:syntax=asm_ca65
