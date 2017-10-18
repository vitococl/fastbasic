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
; In addition to the permissions in the GNU General Public License, the
; authors give you unlimited permission to link the compiled version of
; this file into combinations with other programs, and to distribute those
; combinations without any restriction coming from the use of this file.
; (The General Public License restrictions do apply in other respects; for
; example, they cover modification of the file, and distribution when not
; linked into a combine executable.)


; Common runtime between interpreter and parser
; ---------------------------------------------

        ; 16bit math
        .export         umul16, divmod_sign_adjust, neg_AX
        ; simple I/O
        .export         getkey, putc, print_word, getline, putc_nosave
        .export         line_buf, cio_close, close_all, sound_off
        .exportzp       IOCHN, COLOR, IOERROR, tabpos, divmod_sign
        ; String functions
        .export         read_word
        ; memory move
        .export         move_up_src, move_up_dst, move_up
        .export         move_dwn_src, move_dwn_dst, move_dwn
        ; Common ZP variables (2 bytes each)
        .exportzp       tmp1, tmp2, tmp3

.ifdef FASTBASIC_FP
        ; Exported only in Floating Point version
        .export         print_fp, int_to_fp, read_fp
        ; Convert string to floating point
read_fp = AFP
.else
        ; In integer version, the conversion and printing is the same
print_word = int_to_fp
.endif ; FASTBASIC_FP

        .include        "atari.inc"

        .zeropage

tmp1:   .res    2
tmp2:   .res    2
tmp3:   .res    2
divmod_sign:
        .res    1
IOCHN:  .res    1
IOERROR:.res    2
COLOR:  .res    1
tabpos: .res    1

        .segment        "RUNTIME"

; Negate AX value : SHOULD PRESERVE Y
.proc   neg_AX
        clc
        eor     #$FF
        adc     #1
        pha
        txa
        eor     #$FF
        adc     #0
        tax
        pla
        rts
.endproc

;
; 16x16 -> 16 multiplication
.proc umul16
        ; Mult
        sta     tmp3
        stx     tmp3+1

        lda     #0
        sta     tmp2+1
        ldy     #16             ; Number of bits

        lsr     tmp1+1
        ror     tmp1            ; Get first bit into carry
@L0:    bcc     @L1

        clc
        adc     tmp3
        tax
        lda     tmp3+1
        adc     tmp2+1
        sta     tmp2+1
        txa

@L1:    ror     tmp2+1
        ror
        ror     tmp1+1
        ror     tmp1
        dey
        bne     @L0

;       sta     tmp2            ; Save byte 3
        rts                     ; Done
.endproc

; Adjust sign for SIGNED div/mod operations
; INPUT: OP1:    stack, y
;        OP2:    A / X
;
; The signs are stored in divmod_sign:
;        OP1    OP2     divmod_sign     DIV (bit 7)     MOD (bit 8)
;        +      +       00              +       0       +       0
;        +      -       80              -       1       +       0
;        -      +       FF              -       1       .       1
;        -      -       7F              +       0       .       1
.proc   divmod_sign_adjust
        ; Reads stack from the interpreter
        .import stack_l, stack_h
        .importzp sptr
        ldy     #0
        cpx     #$80
        bcc     y_pos
        ldy     #$80
        jsr     neg_AX
y_pos:  sta     tmp1
        stx     tmp1+1
        sty     divmod_sign

        ldy     sptr
        inc     sptr
        lda     stack_l, y
        ldx     stack_h, y
        bpl     x_pos
        jsr     neg_AX
        dec     divmod_sign
x_pos:  sta     tmp3
        stx     tmp3+1
.endproc        ; Fall through

; Divide TMP3 / TMP2, result in AX and remainder in TMP2
.proc   udiv16
        ldy     #16
        lda     #0
        sta     tmp2+1
        ldx     tmp1+1
        beq     udiv16x8

L0:     asl     tmp3
        rol     tmp3+1
        rol
        rol     tmp2+1

        tax
        cmp     tmp1
        lda     tmp2+1
        sbc     tmp1+1
        bcc     L1

        sta     tmp2+1
        txa
        sbc     tmp1
        tax
        inc     tmp3

L1:     txa
        dey
        bne     L0
        sta     tmp2
        lda     tmp3
        ldx     tmp3+1
        rts

udiv16x8:
        ldx     tmp1
        beq     L0
L2:     asl     tmp3
        rol     tmp3+1
        rol
        bcs     L3

        cmp     tmp1
        bcc     L4
L3:     sbc     tmp1
        inc     tmp3

L4:     dey
        bne     L2
        sta     tmp2
        lda     tmp3
        ldx     tmp3+1
xit:    rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; I/O routines
;
.proc   getkey
        lda     KEYBDV+5
        pha
        lda     KEYBDV+4
        pha
        lda     #12
        sta     ICAX1Z          ; fix problems with direct call to KEYBDV
lrts:   rts
.endproc

.proc   putc_nosave
        lda     ICAX1,X
        sta     ICAX1Z
        lda     ICPTH, x
        pha
        lda     ICPTL, x
        pha
        tya
        rts
.endproc

.proc   putc
        pha
        sty     save_y+1
        ldx     IOCHN
        tay
        jsr     putc_nosave
save_y: ldy     #0
        dec     tabpos
        bpl     :+
        lda     #9
        sta     tabpos
:       pla
        rts
.endproc

line_buf        = LBUFF
.proc   getline
        lda     #>line_buf
        sta     ICBAH, x
.assert (>line_buf) = GETREC, error, "invalid optimization"
        ;lda     #GETREC
        sta     ICCOM, x
        lda     #<line_buf
        sta     ICBAL, x
.assert (<line_buf) = $80, error, "invalid optimization"
        ;lda     #$80
        sta     ICBLL, x
        lda     #0
        sta     ICBLH, x
        jsr     CIOV
        lda     ICBLL, x
xit:    rts
.endproc

.proc   int_to_fp
FR0     = $D4
IFP     = $D9AA
        stx     tmp1
        cpx     #$80
        bcc     positive
        jsr     neg_AX
positive:
        sta     FR0
        stx     FR0+1
        jsr     IFP
        lda     tmp1
        and     #$80
        eor     FR0
        sta     FR0

        ; Minor optimization: in integer version, we don't use
        ; int_to_fp from outside, so fall through to print_fp
.ifdef FASTBASIC_FP
        rts
.endproc

.proc   print_word
FR0     = $D4
        jsr     int_to_fp

.endif ; FASTBASIC_FP

        ; Fall through
.endproc
.proc   print_fp
FASC    = $D8E6
INBUFF  = $F3
        jsr     FASC
        ldy     #$FF
ploop:  iny
        lda     (INBUFF), y
        pha
        and     #$7F
        jsr     putc
        pla
        bpl     ploop
        rts
.endproc

.proc   cio_close
        lda     #CLOSE
        sta     ICCOM, x
        jmp     CIOV
.endproc

.proc   close_all
        lda     #$70
:       tax
        jsr     cio_close
        txa
        sec
        sbc     #$10
        bne     :-
        rts
.endproc

.proc   sound_off
        ldy     #7
        lda     #0
:       sta     AUDF1, y
        dey
        bpl     :-
        rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Convert string to integer (word)
.proc   read_word
SKBLANK = $DBA1
        ; Skips white space at start
        jsr     SKBLANK

        ; Clears result
        ldx     #0
        stx     tmp1
        stx     tmp1+1

        ; Reads a '+' or '-'
        cmp     #'+'
        beq     skip
        cmp     #'-'
        bne     nosign
        dex
skip:   iny

nosign: stx     divmod_sign
        sty     tmp2+1  ; Store starting Y position - used to check if read any digits
loop:
        ; Reads one character
        lda     (INBUFF), y
        sec
        sbc     #'0'
        cmp     #10
        bcs     xit_n ; Not a number

        iny             ; Accept

        sta     tmp2    ; and save digit

        ; Multiply "tmp1" by 10 - uses A,X, keeps Y
        lda     tmp1
        ldx     tmp1+1

        asl
        rol     tmp1+1
        bcs     ebig
        asl
        rol     tmp1+1
        bcs     ebig

        adc     tmp1
        sta     tmp1
        txa
        adc     tmp1+1
        bcs     ebig

        asl     tmp1
        rol     a
        sta     tmp1+1
        bcs     ebig

        ; Add new digit
        lda     tmp2
        adc     tmp1
        sta     tmp1
        bcc     loop
        inc     tmp1+1
        bne     loop

ebig:
        sec
xit:    rts

xit_n:  cpy     tmp2+1
        beq     ebig    ; No digits read

        ; Restore sign - conditional!
        lda     tmp1
        ldx     tmp1+1
        bit     divmod_sign
        bpl     :+
        jsr     neg_AX
:       clc
        rts
.endproc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Memory move routines
.proc   move_up
        ; copy first bytes by adjusting the pointer *down* just the correct
        ; amount: from  "(ptr-(256-len)) + (256-len)" to "(ptr+len-256) + 256"
        ;
        inx
        tay
        beq     cpage
        dey
        clc
        adc     src+1
        sta     src+1
        bcs     :+
        dec     src+2
:       tya
        sec
        adc     dst+1
        sta     dst+1
        bcs     :+
        dec     dst+2
:
        tya
        eor     #$ff
        tay
cloop:
src:    lda     $FF00,y
dst:    sta     $FF00,y
        iny
        bne     cloop
        ; From now-on we copy full pages!
        inc     src+2
        inc     dst+2
cpage:  dex
        bne     cloop

xit:    rts
.endproc
move_up_src     = move_up::src+1
move_up_dst     = move_up::dst+1

.proc   move_dwn
        ; Store len_l
        sta     len_l+1

        ; Here, we will copy (X-1) * 255 + Y bytes, up to src+Y / dst+Y
        ; X*255 - 255 + Y = A*256+B
        ; Calculate our new X/Y values
        txa
        clc
len_l:  adc     #$FF
        tay
        bcc     :+
        inx
        iny
:
chk_len:
        ; Adds 255*X to SRC/DST
        txa
        clc
        eor     #$FF
        adc     src+1
        sta     src+1
        txa
        adc     #$FF
        clc
        adc     src+2
        sta     src+2

        txa
        clc
        eor     #$FF
        adc     dst+1
        sta     dst+1
        txa
        adc     #$FF
        clc
        adc     dst+2
        sta     dst+2

        inx

        ; Copy 255 bytes down - last byte can't be copied without two comparisons!
        tya
        beq     xit
ploop:
cloop:
src:    lda     $FF00,y
dst:    sta     $FF00,y
        dey
        bne     cloop

        ; We need to decrease the pointers by 255
next_page:
        inc     src+1
        beq     :+
        dec     src+2
:       inc     dst+1
        beq     :+
        dec     dst+2
:
        ; And copy 255 bytes more!
        dey
        dex
        bne     cloop

xit:    rts
.endproc
move_dwn_src     = move_dwn::src+1
move_dwn_dst     = move_dwn::dst+1

; vi:syntax=asm_ca65
