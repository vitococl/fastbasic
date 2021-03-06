
' Record start time
ETIME%=0
EXEC GetTime
STIME%=ETIME%

DIM RR(320)
FOR I=0 TO 320:RR(I)=193:NEXT I

GRAPHICS 8+16
SETCOLOR 2,0,0
COLOR 1

XP=144:XR%=4.71238905:XF%=XR%/XP

FOR ZI=64 TO -64 STEP -1
 ZT%=ZI*2.25:ZS%=ZT%*ZT%
 XL=INT(SQR(20736-ZS%))
 FOR XI=0 TO XL
  SXT% = SIN(SQR(XI*XI+ZS%)*XF%)
  YY = INT(SXT%*(123.2-89.6*SXT%*SXT%))
  X1=XI+ZI+160:Y1=90-YY+ZI
  IF RR(X1)>Y1
   RR(X1)=Y1
   PLOT X1,Y1
  ENDIF
  X1=-XI+ZI+160
  IF RR(X1)>Y1
   RR(X1)=Y1
   PLOT X1,Y1
  ENDIF
 NEXT XI
NEXT ZI

' Read End time
EXEC GetTime
ETIME%=ETIME%-STIME%

' Enable text window
GRAPHICS 8+32 : SE.2,0,0

' Convert to seconds (NTSC, use 49.86074 for PAL)
ESEC = INT(ETIME%/59.92271 + 0.5)
EHOUR = ESEC / 3600
EMIN  = (ESEC MOD 3600) / 60
ESEC  = ESEC MOD 60

? "ELLAPSED:";EHOUR;":";EMIN;":";ESEC
GET KEY

PROC GetTime
  REPEAT
    QT = PEEK(18)
    ETIME% = TIME
  UNTIL QT = PEEK(18)
  IF ETIME%<0
    QT = QT + 1
  ENDIF
  ETIME% = 65536.0 * QT + ETIME%
ENDPROC
