' ------------- Carrera 3D ---------------
' ----------- by DMSC - 2015 -------------
'
' Modified to run under FastBasic - 2017
'

 ' Reserve 112 pages of memory for graphics and set 160x96 mode
 ' dlist = display lists pointer.
 '         150 bytes per display list, total of 11*6 = 66 display lists,
 '         but can't cross 1k boundary => 11KBytes, 44 pages
 ' gbase = graphic data pointer
 '         40 bytes per line, total of 48*4*2 = 384 lines => 15KBytes, 60 pages
 ' pmadr = Player 0 graphics pointer (plus 8 to pack over last graphics data).
 '         There are 256 bytes for each player, total 1k, 4 pages.
  mem = peek(106)-112
  poke 106,mem
  dlist = mem * 256
  gbase = dlist + $2C00
  pmadr = gbase + $4008

  ' Sets graphics mode, 160x96, 4 colors.
  graphics 7

  ' Sets the start of the image to 255, (full color 3),
  ' we then use a "move" to copy to all the line.
  img = dpeek(88)
  poke img, 255

  ' Make display-lists and graphics data
  ' Size of display list
  dlsize = 156
  ' Loop over all Y values
  for y=1 to 48
    r = y+14
    zpos = 19200/r - 300
    p = r/8
    n = (r+p+3)/2
    z = 2*r+p
    ' Loop over the 4 possible X values
    for x=0 to 3
      ' Clean the screen
      move img, img+1, 80
      ' Draws the road with color 1 borders
      color 1
      plot x,1
      drawto p+x,1
      color 0
      drawto z+x-1,1
      color 1
      drawto z+p+x,1
      move img+n, gbase + x * 80, 80
      ' Draw the road with color 2 borders
      color 2
      plot x,1
      drawto p+x,1
      plot z+x,1
      drawto z+p+x,1
      move img+n, gbase + 40 + x * 80, 80
    next x
    ' Now, calculate the shifted track position for each curve value and set
    ' the value in each of the display lists.
    d = dlist + 3 * y
    for curvature=-5 to 5
      ' Calculate the X position
      x = 81 - y * 189/100
      x = ( x*x*curvature/729 + 80 -r -p )
      ' Get the graphics address to print this position
      tmp = gbase + 40 - n + x&3 * 80
      tmp = tmp - x/4
      ' Calculate each of the 6 frames (with shifted Z value)
      for z=zpos to zpos+100 step 17
        dpoke d,77
        dpoke d+1, tmp + (z/50)&1 * 40
        d = d + dlsize
      next z
      d = d+88
    next curvature
    ' Advance the pointer to the graphics data
    gbase=gbase+320
    ' Fixes crossing over 4KB - this depends on the initial address!!
    if gbase&960 = 960
      gbase = gbase+256
    endif
   next y
  ' Moved here to optimize space, corresponds to the clearing of PM data
  dpoke pmadr,0

  ' Adds display list first and last bytes to all DLs
  d = dlist
  for curvature=0 to 10
    for z=0 to 5
      dpoke d, $7070
      dpoke d+1, $70
      d = d + dlsize
      dpoke d-9, $4270
      dpoke d-7, dpeek(660)
      dpoke d-5, $41
      dpoke d-4, d - dlsize
    next z
    d = d + 88
  next curvature

  ' Sets PM data (continued from above)
  move pmadr, pmadr+1, 999
  ' TODO: convert this back to hex:
  'move adr("\18\18\18\3C\3C\24\24\3C\00\18\18\3C\7E\7E\00\FF\00\7E\7E"), pmadr+345, 19
  'move adr("\24\24\24\3C\3C\00\7E\18\DB\C3\C3\C3\FF\FF\FF\C3\C3\C3\C3"), pmadr+91, 19
  move adr("<<$$< <~~ � ~~")+1, pmadr+345, 19
  move adr("$$$<< ~�����������")+1, pmadr+91, 19


  ' P/M over playfield and P0+P1 / P2+P3 blends
  dpoke 623,33

  ' Set color registers
  dpoke 712, 8
  dpoke 704, $4482

  dpoke 710, $D2
  dpoke 708, $EE52
  dpoke 706, $8640

  ' Set P/M data address
  poke $D407, mem+104

  ' "e" is the GTIA address, space optimization
  gtia = $d000

  ' Enable P/M
  dpoke gtia + $1d, 2
  ' P0 quad width, P1 double width
  dpoke gtia + $08, 259

  ' P2 shows distance traveled, set a basic shape
  dpoke pmadr+631, 511

  ' Enable ANTIC P/M DMA
  dpoke 559, 58

  ' Start of game loop
  pmadr = 3000
  do

    '# Current "drag"
    drag = 0

    '# Position in track
    trackPos = 0
    '# Current speed
    speed = 0
    '# Track "low" position
    trackLow = 0
    '# Location of "curve" DL ( 1024 * (c+5) )
    curvature = 5
    '# End of current track segment
    segend = 99
    '# Position of car
    x = 1920

    ' Main game loop, starts from "pmadr", on first run has a value bigger
    ' than the end, so the race goes straight to the end screen.
    ' This is a tricky optimization!!
    for z=pmadr to 3000
      ' Waits for VBLANK, read collision register
      pause 0
      tmp = peek(gtia + $04)

      ' Clear collision register and sets player position
      poke gtia + $1e, 0
      ' Set PM0 and PM1 x coordinates
      dpoke gtia, (x/16) * 257 - 8

      ' Sets DL (for next frame)
      dpoke 560, dlist + curvature * 1024 + dlsize * (trackPos mod 6)

      ' Advance track position
      trackLow = trackLow + speed
      trackPos = trackPos + trackLow / 112
      trackLow = trackLow mod 112

      ' "motor" sound. Note the values of frequency=k*31-1 produce pure tones,
      ' but we don't have enough space to filter out.
      sound 0, 255 - speed, 6, 8
      ' Process collisions with the outside of the track
      if tmp
        ' Decreases the speed by 5%
        speed = speed * 19 / 20
      else
        ' Increases the speed, max speed is 2 if button is not pressed, 1 if pressed.
        ' Scaled by 112
        speed = ( 211 + 112 * STRIG(0) + speed * 99 ) / 100
      endif
      ' Read joystick
      tmp = STICK(0)
      ' Updates X position, adds joystick and "drag" times "speed"
      ' As drag is scaled by 50/9, speed by 112, and c by 16, we need to
      ' divide by (50*112)/(9*16) = 38.88 ~ 39
      x = x + (tmp&4) * 4 - (tmp&8) * 2 - drag*speed/39
      ' Test if current track segment is over
      if trackPos > segend
        ' Yes, generate a new segment
        ' (first, set text position to 0)
        dpoke 657, 0

        ' New random direction
        curvature = rand(11)
        ' Drag is from -0.9 to 0.9 (scaled by 50/9)
        drag = curvature - 5
        ' New random length, from 10 to 110.
        segend=segend+rand(100)+10
        ' Shows the current time and position
        print "T:"; z, "D:"; trackPos,
      endif

      ' Sets the Player 2 position to current track position
      dpoke gtia + $02, 48 + trackPos / 32
    next z

    ' End of game, shows score, turns of sound and waits for keystroke
    print "LAST:"; trackPos,
    sound
    get tmp

    ' Next race starts at time 0 (a full race)
    pmadr=0
  loop
