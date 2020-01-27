;*******************************************************************************
;
;	Filename:		NCO-3.asm
;	Date:			15 Nov 2019
;	File Version:	1.0
;	Author:			Vanderson Carvalho
;	Description:
;		This program uses a PIC 16F18313 and its Numerically Controlled Oscillator
;		It allows for variable frequency operation via a potentiometer
;		connected to RA2
;
;		PIC16F18313 I/O:
;			pin 1: VDD
;			pin 2: RA5					Output
;			pin 3: RA4/AN3				/Halt control: LOW = ON, HIGH = OFF
;			pin 4: RA3/~MCLR			Select Operation Mode (LOW = Freerun, HIGH = Manual)
;			pin 5: RA2/ANA2				Manual Fire Switch HIGH = PULSE
;			pin 6: RA1/ANA1/ICSPCLK		A/D input for frequency control (0-5V)
;			pin 7: RA0/ANA0/ISCPDAT		Mode LED Indicator (ON - Manual, OFF - Freerun)
;			pin 8: VSS
;
; The frequency values are based on the CPU clock = 32MHz divided by 4.
; The min frequency is also the frequency step size.
; The max frequency is 1023 times the min frequency.
;
; Definitions used by the program which are associated with specific I/O pins:
;	O_PULSE				- output pulse pin
;	AV_FREQUENCY	- pin for analog voltage for frequency
;	AV_RANGE			- pin for analog voltage for range
;
;*******************************************************************************
;*******************************************************************************

#include p16F18313.inc

; CONFIG1
; __config 0xDF8F
 __CONFIG _CONFIG1, _FEXTOSC_OFF & _RSTOSC_HFINT32 & _CLKOUTEN_OFF & _CSWEN_ON & _FCMEN_OFF
; CONFIG2
; __config 0xF732
 __CONFIG _CONFIG2, _MCLRE_OFF & _PWRTE_OFF & _WDTE_OFF & _LPBOREN_OFF & _BOREN_OFF & _BORV_LOW & _PPS1WAY_OFF & _STVREN_ON & _DEBUG_OFF
; CONFIG3
; __config 0x3
 __CONFIG _CONFIG3, _WRT_OFF & _LVP_OFF
; CONFIG4
; __config 0x3
 __CONFIG _CONFIG4, _CP_OFF & _CPD_OFF


O_PULSE			equ	RA5
O_PPS			equ	RA5PPS
I_ON_OFF		equ	RA4
AV_FREQUENCY	equ	RA1
MODE			equ	RA3
MODE_LED		equ	RA0
MAN_SWITCH		equ	RA2

TRISA_VAL		equ	(1<<AV_FREQUENCY) | (1<<MODE) | (1<<I_ON_OFF) | (1<<MAN_SWITCH)
ADCH_FREQ		equ	( AV_FREQUENCY<<CHS0 ) | (1<< ADON )

RIGHT_JUSTIFY	equ	0x80 | (b'010'<<ADCS0)
LEFT_JUSTIFY	equ	0 | (b'010'<<ADCS0)		; not used by this program


;*******************************************************************************
; RAM
;*******************************************************************************

Access_RAM		udata_shr	0x70		; 16 bytes starting at address 0x70
NCO_Accum		res	3
Range			res	1
Dbg_Range		res	1
Dcnt1			res	1
Dcnt2			res	1
Dcnt3			res	1
;*******************************************************************************
; Vectors
;*******************************************************************************

	org	0
	goto	Main

	org	0x04											; interrupt vector
ISR.Exit
	retfie


;*******************************************************************************
; MAIN PROGRAM
;*******************************************************************************

MAIN_PROG CODE                  				; let linker place main program

Main
	call		init							; initialize the system hardware

	BANKSEL	ADCON0
	movlw		ADCH_FREQ						; set the A/D channel and keep A/D on
	movwf		ADCON0
	bsf			ADCON0, ADGO					; start first conversion

;*******************************************************************************
; Main Program Loop
;*******************************************************************************
Main.10
	call		Check_On_Off
	call		Check_Mode					
	call		Get.Frequency
	goto		Main.10

;**
;** Check operation mode ** 
;**

Check_Mode
	BANKSEL	PORTA
	bcf			LATA, MODE_LED
	btfss		PORTA, I_ON_OFF					; skip next if HALT
	btfss		PORTA, MODE						; skip next if MODE=HIGH=MANUAL
	return
	bsf			LATA, MODE_LED
	btfss    	PORTA, MAN_SWITCH
	return
SW_LOOP
	btfsc		PORTA, MAN_SWITCH
	goto 		SW_LOOP
	goto 		Set_Out
Set_Out
	bsf			PORTA, O_PULSE
	call		Delay_100ms
	BANKSEL	LATA
	clrf		LATA
	return
;Check_Mode

;**
;** 10ms Delay **
;**

Delay_100ms:
	movlw		0xB9
	movwf		Dcnt1
	movlw		0x20
	movwf		Dcnt2
	movlw		0x02
	movwf		Dcnt3
Loop
	decfsz		Dcnt1, f
	goto 		Loop
	decfsz		Dcnt2, f
	goto 		Loop
;	decfsz		Dcnt3, 
;	goto 		Loop
	return
;Delay_100ms

;**
;** Halt Oscillator & Manual **
;**

Check_On_Off
	BANKSEL	PORTA
	btfss		PORTA, MODE						; If MODE=HIGH=Manual turn Off NCO
	btfsc		PORTA, I_ON_OFF					; skip next if on
	goto		Turn_Off
; here if switch is on
	BANKSEL	O_PPS
	movlw		b'11101'						; NCO output
	movwf		O_PPS
	return
Turn_Off
	BANKSEL	O_PPS
	clrf		O_PPS
	BANKSEL	LATA
	clrf		LATA							; make output low
	return
; Check_On_Off

;**
;** Get Frenquecy from ADC **
;**

Get.Frequency
	movlw		ADCH_FREQ
	call		AD.Read

; test for 0
	movfw		ADRESL
	iorwf		ADRESH, w
	btfsc		STATUS, Z
	incf		ADRESL, f
;

	movfw		ADRESL

	movwf		NCO_Accum						; store Low byte for processing
	movfw		ADRESH

	movwf		NCO_Accum+1						; store High byte for processing
	clrf		NCO_Accum+2						; ensure U byte is clear

Get.Frequency.10
	btfsc		STATUS, Z						; skip next if not done
	goto		Get.Frequency.20
	lslf		NCO_Accum, f					; L
	rlf			NCO_Accum+1, f					; H
	rlf			NCO_Accum+2, f					; U
	decf		WREG, f							; update shift counter
	goto		Get.Frequency.10
; put the results into the increment registers
Get.Frequency.20
	BANKSEL	NCO1INCU
	movfw		NCO_Accum+2						; get U byte
	movlw 		0
	movwf		NCO1INCU
	movfw		NCO_Accum+1						; get H byte
	movlw		0
	movwf		NCO1INCH

	movfw		NCO_Accum+0
	movwf		NCO1INCL						; this writes all 3 bytes to the register
	return
; Get.Frequency

;**
;** Read the 10bits ADC **
;**

AD.Read
; read the 10 bit A/D
; enter with w = A/D channel in appropriate bits and ADON bit set
; exit with 10 bit value in AD registers
;		w = low byte value
;		BANKSEL = ADCON0

	BANKSEL	ADCON0
	movwf		ADCON0							; set the channel and keep A/D on
; delay for acquisition time - 20 instruction sycles
	movlw		.7
AD.Read.05
	decfsz		WREG, f							; 1 update count, skip next if done
	goto		AD.Read.05						; 2
	bsf			ADCON0, ADGO					; start the conversion
AD.Read.10
	btfsc		ADCON0, ADGO					; skip next if done conversion
	goto		AD.Read.10						; wait for done
	return
; AD.Read

;*******************************************************************************
;Initialize Hardware
;*******************************************************************************

init	; initialize the system hardware

; Oscillator - set to 32MHz using 8MHz clock and PLL
	BANKSEL	OSCCON1
	movlw		(b'110'<<NOSC0) | (b'0010'<<NDIV0)
	movwf		OSCCON1							; HFINTOSC with 2x PLL (32 MHz), DIV = 4
												; OSCCON2 is read-only
	clrf		OSCCON3
	movlw		1<<HFOEN						; enable the HF internal oscillator
	movwf		OSCEN
	movlw		3								; select 32MHz
	movwf		OSCFRQ
init.10
	btfss		OSCCON3, NOSCR					; wait for oscillator ready
	goto		init.10

; Port A
	BANKSEL	PORTA
	clrf		PORTA
	BANKSEL	TRISA
	movlw		TRISA_VAL
	movwf		TRISA							; set analog and digital input pins
	BANKSEL	ANSELA
	movlw		b'00000010'						; set analog input pins RA1
	movwf		ANSELA
	BANKSEL	INLVLA
	movlw		0xFF							; set up to
	movwf		INLVLA							; make all inputs Schmitt Trigger CMOS

; Peripheral Pin Select
	BANKSEL	RA5PPS
	movlw		b'11101'						; NCO output
	movwf		RA5PPS

; A/D convertor
	BANKSEL	ADCON0
	movlw		(1<<ADON)						; A/D on, used later to select A/D channel
	movwf		ADCON0
	movlw		RIGHT_JUSTIFY					; clk=Fosc/32, VRPOS=VDD, right justify data
	movwf		ADCON1
	clrf		ADACT							; no auto conversion trigger

; Interrupts
	clrf		INTCON							; clear global interrupt enable
	BANKSEL	PIE0
	clrf		PIE0							; clear peripheral interrupt enables
	clrf		PIE1							; clear peripheral interrupt enables

; NCO
	BANKSEL	NCO1ACCL
	movlw		b'01'							; use Fosc for clock
	movwf		NCO1CLK
	movlw		(1<<N1EN) | (0<<N1PFM)			; enable NCO1, set to Fixed Duty Cycle (50%)
	movwf		NCO1CON
	return
; init

	END
