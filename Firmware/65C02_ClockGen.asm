;******************************************************************
;                                                                 *
;    Project: 65C02_ClockGen                                      *
;       File: 16F18313_Clock.asm                                  *
;     Author: Mike McLaren, K8LH                                  *
;    (C)2016: Micro Application Consultants                       *
;           : All Rights Reserved                                 *
;       Date: 04-Apr-2016                                         *
;                                                                 *
;    16F18313 Clock-Gen + Econo-Reset for 65C02 (8-MHz crystal)   *
;    produces a 1, 2, 4, or 8 MHz CPU clock and an ACIA clock.    *
;                                                                 *
;        IDE: MPLABX v3.05                                        *
;       Lang: MPASM v5.62 (absolute addressing mode)              *
;                                                                 *
;******************************************************************

        #include p16F18313.inc
        errorlevel -302,-311    ; suppress bank warnings
        list st=off             ; symbol table off
        radix dec

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;  config settings                                                ~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

__CONFIG _CONFIG1, _FEXTOSC_HS & _FCMEN_OFF
;
; CLKOUTEN_OFF default
; CSWEN_ON     default
;
__CONFIG _CONFIG2, _WDTE_OFF & _PPS1WAY_OFF
;
; MCLRE_ON     default
; PWRTE_OFF    default
; LPBOREN_OFF  default
; BOREN_ON     default
; BOREN_LOW    default
; STVREN_ON    default
; DEBUG_OFF    default
;
__CONFIG _CONFIG3, _LVP_OFF
;
; WRT_OFF      default
;
__CONFIG _CONFIG4, _CP_OFF & _CPD_OFF

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;  variables                                                      ~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        cblock  0x70            ; common RAM available any bank
delayhi                         ; DelayCy() subsystem variable
        endc

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;  constants                                                      ~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;
;  assign clock and reset pins (RA0..RA2 inclusive).
;
PHI0_clk equ    RA0             ; bit index for RA0 (0)
ACIA_clk equ    RA1             ; bit index for RA1 (1)
RESB_out equ    RA2             ; bit index for RA2 (2)
;
;  associate to "Peripheral Pin Select" output registers.
;
PHI0_PPS equ    RA0PPS+PHI0_clk ; equ RA0PPS
ACIA_PPS equ    RA0PPS+ACIA_clk ; equ RA1PPS
RESB_PPS equ    RA0PPS+RESB_out ; equ RA2PPS
;
;  set 'CLKR_div' constant for desired 65C02 clock frequency.
;
;               6 ->  0.5-MHz (Fosc / 64)
;               5 ->  1.0-MHz (Fosc / 32)
;               4 ->  2.0-MHz (Fosc / 16)
;               3 ->  4.0-MHz (Fosc / 8)
;               2 ->  8.0-MHz (Fosc / 4)
;
CLKR_div equ    4               ; 2.0-MHz PHI0 CPU clock
;
;  set 'NCO1_inc' constant for desired ACIA clock output.
;
;          2517 ->    38400-Hz (  2400 * 16) @ 0.01659%
;          5033 ->    76800-Hz (  4800 * 16) @ 0.00327%
;         10066 ->   153600-Hz (  9600 * 16) @ 0.00327%
;         20133 ->   307200-Hz ( 19200 * 16) @ 0.00169%
;         40265 ->   614400-Hz ( 38400 * 16) @ 0.00079%
;         60398 ->   921600-Hz ( 57600 * 16) @ 0.00004%
;        120796 ->  1843200-Hz (115200 * 16) @ 0.00004%
;        241592 ->  3686400-Hz (230400 * 16) @ 0.00004%
;
NCO1_inc equ    120796          ; 1.8432-MHz (115200 * 16)

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;  K8LH DelayCy() subsystem macro generates four instructions     ~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        radix dec
clock   equ     32              ; 4, 8, 12, 16, 20 (MHz), etc.
usecs   equ     clock/4         ; cycles/microsecond multiplier
msecs   equ     usecs*1000      ; cycles/millisecond multiplier
dloop   equ     5               ; loop size, 5 to ??? cycles
;
;  -- loop --  -- delay range --  -- memory overhead ----------
;  5-cyc loop, 11..327690 cycles,  9 words (+4 each macro call)
;  6-cyc loop, 11..393226 cycles, 10 words (+4 each macro call)
;  7-cyc loop, 11..458762 cycles, 11 words (+4 each macro call)
;  8-cyc loop, 11..524298 cycles, 12 words (+4 each macro call)
;  9-cyc loop, 11..589834 cycles, 13 words (+4 each macro call)
;
DelayCy macro   cycles          ; range, see above
    if (cycles<11)|(cycles>(dloop*65536+10))
        error " DelayCy range error "
    else
        movlw   high((cycles-11)/dloop)+1
        movwf   delayhi
        movlw   low ((cycles-11)/dloop)
        call    uLoop-((cycles-11)%dloop)
    endif
        endm

;******************************************************************
;  reset vector                                                   *
;******************************************************************
        org     0x0000
v_reset
        bra     setup           ;                                 |00

;******************************************************************
;  interrupt vector                                               *
;******************************************************************
        org     0x0004
v_int
        retfie                  ;                                 |??

;******************************************************************
;  main setup                                                     *
;******************************************************************

setup
;
;  turn off analog functions (all I/O will be digital).
;
        banksel ANSELA          ; bank 03                         |03
        clrf    ANSELA          ; analog off, digital I/O         |03
;
;  setup data direction for 'output' pins (default 'input').
;
        banksel TRISA           ; bank 01                         |01
        bcf     TRISA,PHI0_clk  ; set phi0 clock pin as output    |01
        bcf     TRISA,ACIA_clk  ; set acia clock pin as output    |01
        bcf     TRISA,RESB_out  ; set resb reset pin as output    |01
;
;  clear RESB pin output latch (hold the 65C02 in reset).
;
        banksel LATA            ; bank 02                         |02
        bcf     LATA,RESB_out   ; RESB_out = '0'                  |02
;
;  setup Fosc for 32-MHz (external 8-MHz crystal and 4xPLL).
;
        banksel OSCCON1         ; bank 18                         |18
        movlw   b'00010000'     ; -001---- NOSC[2:0], Ext 4xPLL   |18
                                ; ----0000 NDIV[3:0], Clk Div 1   |18
        movwf   OSCCON1         ; 8-MHz Xtal & 4xPLL -> 32-MHz    |18
stable
        btfss   OSCCON3,ORDY    ; OSC stable? yes, skip, else     |18
        bra     stable          ; loop (wait 'til OSC stable)     |18
;
;  assign PHI0_clk pin (RA0) and ACIA_clk pin (RA1) resources
;  via 'Peripheral Pin Select'.
;
        banksel PPSLOCK         ; bank 28                         |28
        movlw   0x55            ; PPS unlock sequence             |28
        movwf   PPSLOCK         ;  "                              |28
        movlw   0xAA            ;  "                              |28
        movwf   PPSLOCK         ;  "                              |28
        bcf   PPSLOCK,PPSLOCKED ;  "                              |28
        banksel RXPin		    ; bank 29                         |29
        movlw   b'00000011'     ; assign RA as PPS Input (RX)	  |29
        movwf   PHI0_PPS        ; to the PHI0 clock pin (RA0)     |29
        movlw   b'00011101'     ; assign NCO module output to     |29
        movwf   ACIA_PPS        ; the ACIA clock pin (RA1)        |29
        banksel PPSLOCK         ; bank 28                         |28
		movlw   0x55            ; PPS Lock sequence               |28
        movwf   PPSLOCK         ;  "                              |28
        movlw   0xAA            ;  "                              |28
        movwf   PPSLOCK         ;  "                              |28
        bsf   PPSLOCK,PPSLOCKED ; all done, lock it up            |28
;
;  setup CLKR (Reference Clock) module for PHI0 CPU Clock.
;
        banksel CLKRCON         ; bank 07                         |07
        movlw   0x10|CLKR_div   ; 50% duty cycle & divider bits   |07
        movwf   CLKRCON         ; prep 1, 2, 4, or 8-MHz output   |07
        bsf     CLKRCON,CLKREN  ; enable Reference Clock output   |07
;
;  setup NCO to generate the ACIA clock.
;
        banksel NCO1CON         ; bank 08                         |08
;       bcf     NCO1CON,N1PFM   ; fixed duty cycle mode (default) |08
        movlw   b'00000001'     ; N1CKS<1:0> = '01' = Fosc        |08
        movwf   NCO1CLK         ; set NCO clock source            |08
        clrf    NCO1ACCL        ; clear 20-bit phase accumulator  |08
        clrf    NCO1ACCH        ;  "                              |08
        clrf    NCO1ACCU        ;  "                              |08
        movlw   low(NCO1_inc)   ; setup 20-bit phase increment    |08
        movwf   NCO1INCL        ;  "                              |08
        movlw   high(NCO1_inc)  ;  "                              |08
        movwf   NCO1INCH        ;  "                              |08
        movlw   upper(NCO1_inc) ;  "                              |08
        movwf   NCO1INCU        ;  "                              |08
        bsf     NCO1CON,N1EN    ; enable NCO module output        |08
;
;  complete the 65C02 reset cycle.
;
        DelayCy(20*msecs)       ; wait ~20-msecs                  |08
        banksel LATA            ; bank 02                         |02
        bsf     LATA,RESB_out   ; release 65C02 from reset        |02

;******************************************************************
;  main loop                                                      *
;******************************************************************

loop
        bra     loop            ; loop forever (until reset)      |02

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;  K8LH DelayCy() subsystem 16-bit 'uLoop' timing subroutine      ~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
a = dloop-1
    while a > 0
        nop                     ; (cycles-11)%dloop entry points  |??
a -= 1
    endw
uLoop   addlw   -1              ; subtract 'dloop' loop time      |??
        skpc                    ; borrow? no, skip, else          |??
        decfsz  delayhi,F       ; done?  yes, skip, else          |??
        goto    uLoop-dloop+5   ; do another loop                 |??
        return                  ;                                 |??

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        end