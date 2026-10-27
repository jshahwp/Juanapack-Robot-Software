'Station dimensions / clearances
Global Real ToolLengthDown, ToolLengthRight, ToolRadiusOffset, ValveClearance, TrayEdgeZClearance

'Pick jump motion configuration
Global Real PickJumpRiseDistance, PickJumpFallDistance, PickJumpZLimit, Plane1Z, PickTransferZ

Global Real ToolSwitchPlaneZ

'Drop jump motion configuration
Global Real DropJumpRiseDistance, DropJumpFallDistance, DropJumpZLimit

'Tool / bracket angle
Global Double BracketToolAngle

'Active tool sensor input number
Global Integer ToolSensorInput

'Drop target offset for vision trigger
Global Integer VisionTriggerPlaneX, VisionTriggerToleranceU

Global Boolean AtStandByPos

Function Main1

'---Initialize robot, points, tools, motion settings, and collision zones
	Print "Initializing"
	Call Initialize_Auto
	
'---Main automatic cycle
	Do
	'---Request first pick position calculation
		On PickPosRequest
		Xqt GetPickPosition
		
	'---Wait until tray is ready to start / continue cycle
		Print "Waiting for Tray"
		Wait Sw(TrayReady)
		Print "Tray ready"
			
	'---Execute pick and place cycle
		Call PickAndPlace
		
	'---Return robot to home when tray is no longer ready
		Tool 1
		OutW ToolDefined, 1
		'Till GetRobotInsideBox(1) = 0
		Go Here :Z(0) @0 /L 'Till
		
		On SwitchTool1
		Wait Sw(Tool2Sensor) = False And Sw(Tool3Sensor) = False
		Off SwitchTool1
		
		AtStandByPos = True
		
		TaskWait GetPickPosition
		
	Loop

Fend
  	
  	
Function Initialize_Auto
	
	
'---Lock all axes
	If ((RobotInfo(3) And &H1) <> &H1) Or ((RobotInfo(3) And &H2) <> &H2) Or ((RobotInfo(3) And &H4) <> &H4) Or ((RobotInfo(3) And &H8) <> &H8) Then
		SLock 1, 2, 3, 4
	EndIf
	
	If Not Motor Then Motor On
	
	Home
	
	Tool 1
	OutW ToolDefined, 1
	On SwitchTool1
	Wait Sw(Tool2Sensor) = False And Sw(Tool3Sensor) = False
	
	Reset
	
	If Not Motor Then Motor On
	
'---Load robot points and set power mode
	LoadPoints "benchtest.pts"
	
'---Weight [tool weight in kg], [Distance to Center Of Gravity in mm]
	Weight 0.8, 20

	If In(SpeedSet) > 5 Then
		Power High
		
	'---Point-to-point motion settings
		Speed In(SpeedSet), In(SpeedSet), In(SpeedSet)
		Accel In(AccelSet), In(DecelSet), In(AccelSet), In(DecelSet), In(AccelSet), In(DecelSet)
		
	'---Linear motion settings
		SpeedS 2000, 1000, 2000
		AccelS 5000, 5000
		AccelR 5000, 5000
	Else
		Power Low
	EndIf

'---Motion quality / precision settings
	Fine 200, 200, 200, 200

'---Station dimensions / clearances
	ValveClearance = 40
	TrayEdgeZClearance = 35			'**IMPORTANT**
	ToolLengthDown = 103			'Should match PLC values and actual distances
	ToolLengthRight = 48.5

'---Calculate tool/bracket mounting angle
	Double ToolDeltaX, ToolDeltaY

	ToolDeltaX = CX(TLSet(2)) - CX(TLSet(3))
	ToolDeltaY = CY(TLSet(2)) - CY(TLSet(3))
	BracketToolAngle = Atan2(ToolDeltaX, ToolDeltaY)

	'Offset between ToolLengthDown and tool radius when rotating
	ToolRadiusOffset = Sqr((ToolLengthDown * ToolLengthDown) + (ToolLengthRight * ToolLengthRight)) - ToolLengthDown

'---Create Local 3 from Local 2 and CatchBox height
	Real CatchBoxLiftHeight

	CatchBoxLiftHeight = InReal(CBLiftHeight)
	Local 3, XY(CX(Local(2)), CY(Local(2)), CZ(Local(2)) + CatchBoxLiftHeight, CU(Local(2)))

'---Collision boxes
	Box 1, -1000, 200, 150, 1000, -1000, CZ(Local(3)) - 5
	Box 2, -1000, 200, 150, 1000, -1000, CZ(Local(3)) - 5 + ToolLengthDown - ValveClearance
	

	
'---Initialization complete
	On Initialized
	Print "Initialized"

Fend


Function PickAndPlace

'---Repeat pick and place while tray is ready
	Do
		
	'---Wait until the next pick position is calculated
		TaskWait GetPickPosition
		
		'---Set pick jump height
		If AtHome Or AtStandByPos Then
		    PickJumpZLimit = 0
		Else
		    PickJumpZLimit = PickTransferZ
		EndIf
		
		Print "PickJumpZLimit used: ", PickJumpZLimit

		AtStandByPos = False
		On PickPosJump

	'---Prepare robot for pick movement
		CP On
		Tool 1
		OutW ToolDefined, 1

	'---Request drop position calculation in background
		On DropPosRequest
		Xqt GetDropPosition, NoPause
		
	'---Move to pick approach position		
		Print "Current J3 before Pick Jump: ", Agl(3)
		Print "PickJumpZLimit used: ", PickJumpZLimit
		
	'	Jump PickApproach C0 LimZ PickJumpZLimit CP ! D0; Wait GetRobotInsidePlane(1) = 1; On SwitchTool1 !
		Print "Starting next PickApproach"
		Jump PickApproach C0 LimZ PickJumpZLimit CP

	'---Wait until both tool sensors are clear before picking
		Wait Sw(Tool2Sensor) = False And Sw(Tool3Sensor) = False
		Print "Tool centered - Pick permitted"

	'---Move to pick position and activate vacuum
		Go PickPosition CP ! D0; On VacuumValve !

	'---Pick movement completed
		Off SwitchTool1
		Off PickPosJump

	'---Wait until drop position calculation is completed
		TaskWait GetDropPosition
		On DropPosJump

	'---Prepare robot for drop movement
		CP On
		Tool 4
		OutW ToolDefined, OutW(ToolSelection)

	'---Start monitoring and request next pick position in background
		Xqt MonitorDropPosJump, NoPause
		Xqt MonitorVacuum, NoPause
		Xqt GetPickPosition, NoPause
		
	'---Move to drop approach position
		Print "TEST 1 - Before DropApproach"
		Jump DropApproach C1 LimZ DropJumpZLimit CP
		Print "TEST 2 - After DropApproach"
		
	'---Wait until selected tool reaches its sensor position
		Print "TEST 3 - Waiting for Tool Sensor"
		Wait Sw(ToolSensorInput) = True
		Print "TEST 4 - Tool Sensor Active"
		Signal 1
		
	'---Enable sense stop if catchbox is not ready
		Sense Sw(CatchBoxReady) = False

	'---Move to drop position and release object when inside drop plane
		Print "TEST 5 - Before DropPosition"
		Jump DropPosition C2 LimZ DropJumpZLimit CP Sense
		Print "TEST 6 - After DropPosition"
		
	'---If sense stop occurred, wait for catchbox and finish drop movement
		If JS = True Then
			Print "TEST 7 - Waiting CatchBoxReady"
			Print "Waiting for catchbox ready"
			Wait Sw(CatchBoxReady) = True
			Print "TEST 8 - CatchBox Ready"
			Print "Catchbox ready"
			Go DropPosition CP
		EndIf
		
	'---Move away from drop position
		Print "TEST 9 - Before Retreat"
		Move RetreatPosition CP
		Print "TEST 10 - After Retreat"

	'---Wait for drop monitoring task to finish
		Print "TEST 11 - Waiting MonitorDropPosJump"
		TaskWait MonitorDropPosJump
		Print "TEST 12 - MonitorDropPosJump Complete"
		Print "TEST 13 - Waiting MonitorVacuum"
		TaskWait MonitorVacuum
		Print "TEST 14 - MonitorVacuum Complete"

	'---Reset drop movement flags
		Off SwitchTool
		Off DropPosJump
		

		'---Capture clearance height for tool switching
		ToolSwitchPlaneZ = Plane1Z
		
		Print "ToolSwitchPlaneZ: ", ToolSwitchPlaneZ
		Print "WaitPosition Z Local0: ", CZ(WaitPosition @0)
		
		'---Start parallel tool-switch monitoring
		Xqt MonitorSwitchTool1
		
		'---Move to waiting position
		Print "Before WaitPosition"
		
		CP Off
		
		Go WaitPosition
		Print "Active Tool: ", Tool
		Print "WaitPosition Target: ", WaitPosition @0
		Print "CurPos: ", CurPos @0
		Print "RealPos: ", RealPos @0
		Print "Plane1Z: ", Plane1Z
		Print "Plane 1 Status: ", GetRobotInsidePlane(1)
		Print "Joint 3: ", Agl(3)
		
		Print "After WaitPosition"
		
		'---Check whether additional Z clearance is required
		If CZ(RealPos @0) < ToolSwitchPlaneZ Then
		
		    Print "Additional Z clearance required"
		
		   ' Go Here :Z(ToolSwitchPlaneZ + 5) @0 /L
		
		EndIf
		
		'---Wait for tool-switch monitor
		TaskWait MonitorSwitchTool1
		
'		'---Confirm physical tool is centered
'		Wait Sw(Tool2Sensor) = False And Sw(Tool3Sensor) = False
'		
'		Print "Tool 1 centered"

		
		Print "Tool change TCP Z: ", CZ(CurPos @0)
		Print "Tool change J3: ", Agl(3)
		
	'---Store actual safe transfer height for next pick	
		PickTransferZ = Agl(3)
		Print "PickTransferZ: ", PickTransferZ
		

		Print "Waiting for next pick request"
		Print "GoToPickPos: ", Sw(GoToPickPos)
		Print "TrayReady: ", Sw(TrayReady)
		
		Wait Sw(GoToPickPos) Or Not Sw(TrayReady)
		
		If Sw(TrayReady) = False Then
		    Print "Tray not ready - exiting PickAndPlace"
		Else
		    Print "Next pick request received"
		EndIf

	Loop Until Sw(TrayReady) = False

Fend


Function GetPickPosition

'---Pick target coordinates from PLC
	Real PickTargetX, PickTargetY, PickTargetZ, PickTargetU

'---Calculated pick position coordinates
	Real PickPositionX, PickPositionY, PickPositionZ, PickPositionU

'---Calculated pick approach coordinates
	Real PickApproachX, PickApproachY, PickApproachZ, PickApproachU

'---Current robot position
	Real CurrentZ, CurrentU

'---Object coordinates in Local 0
	Integer ObjectXLocal0, ObjectYLocal0

'---Left / right U rotation offsets
	Integer PickLeft, PickRight
	PickLeft = 90
	PickRight = -90

'---Tray zone limits for tool orientation
	Integer LimitTop, LimitBottom, LimitLeft, LimitRight, LimitTopLeftX, LimitTopLeftY, LimitBottomRightY

	LimitTop = 440
	LimitBottom = 275
	LimitLeft = 275
	LimitRight = -10

	LimitTopLeftX = 390
	LimitTopLeftY = 250
	
	LimitBottomRightY = 145

'---Selected tool orientation
	Boolean UseTool2ForPick, TestTool2Forced
	
	TestTool2Forced = True

'---Wait for pick request from PLC
	Wait Sw(GoToPickPos)
	Off PickPosRequest

'---Read object coordinates from PLC
	PickTargetX = InReal(ObjectX)
	PickTargetY = InReal(ObjectY)
	PickTargetZ = InReal(ObjectZ)
	PickTargetU = InReal(ObjectU)

'---Convert object coordinates to Local 0
	ObjectXLocal0 = PickTargetX + CX(Local(1))
	ObjectYLocal0 = PickTargetY + CY(Local(1))

'---Get current robot position
	If AtHome() Then
		CurrentU = CU(CurPos @1)
	Else
		CurrentU = CU(DropPosition @1)
	EndIf

'---PickPosition coordinates----------------------------------------------------------------

	PickPositionX = PickTargetX
	PickPositionY = PickTargetY
	PickPositionZ = PickTargetZ

'---Choose pick side / tool orientation

	If Sw(InvertDrop) = False And TestTool2Forced Then
		UseTool2ForPick = True
		Print "Tool2Forced"
	'Top Left
	ElseIf ObjectYLocal0 > LimitTopLeftY And ObjectXLocal0 > LimitTopLeftX Then
	Print "1"
		UseTool2ForPick = PickTargetU < -20 Or PickTargetU > 160

	'Top Right
	ElseIf ObjectYLocal0 < LimitRight And ObjectXLocal0 > LimitTop Then
	Print "2"
		UseTool2ForPick = PickTargetU < -135 Or PickTargetU > 45

	'Bottom Right
	ElseIf ObjectYLocal0 < LimitBottomRightY And ObjectXLocal0 < LimitBottom Then
	Print "3"
		UseTool2ForPick = Not (PickTargetU < -45 Or PickTargetU > 135)

	'Bottom Left
	ElseIf ObjectYLocal0 > LimitLeft And ObjectXLocal0 < LimitBottom Then
	Print "4"
		UseTool2ForPick = Not (PickTargetU < -135 Or PickTargetU > 45)

	'Top
	ElseIf ObjectXLocal0 > LimitTop Then
	Print "5"
		UseTool2ForPick = PickTargetU < -30 Or PickTargetU > 150

	'Bottom
	ElseIf ObjectXLocal0 < LimitBottom Then
	Print "6"
		UseTool2ForPick = Not (PickTargetU < -90 Or PickTargetU > 90)

	'Left
	ElseIf ObjectYLocal0 > LimitLeft Then
	Print "7"
		UseTool2ForPick = PickTargetU < 0

	'Right
	ElseIf ObjectYLocal0 < LimitRight Then
	Print "8"
		UseTool2ForPick = PickTargetU > 0

	'Center
	Else
		Print "9"
		If Sw(InvertDrop) = False Then
			UseTool2ForPick = True
		Else
			UseTool2ForPick = False
		EndIf
	EndIf

'---Apply U rotation offset
	If UseTool2ForPick Then
		PickPositionU = PickTargetU + PickRight
	Else
		PickPositionU = PickTargetU + PickLeft
	EndIf

'---Inverse rotation if rotation is greater than 180 degree
	If PickPositionU - CurrentU > 180 Then
		PickPositionU = PickPositionU - 360

	ElseIf PickPositionU - CurrentU < -180 Then
		PickPositionU = PickPositionU + 360
	EndIf

'---Change orientation if joint limit is reached
	If PickPositionU > 270 - CU(Local(1)) Then
		PickPositionU = PickPositionU - 360

	ElseIf PickPositionU < -270 - CU(Local(3)) Then
		PickPositionU = PickPositionU + 360
	EndIf

'---Create PickPosition point
	PickPosition = XY(PickPositionX, PickPositionY, PickPositionZ, PickPositionU) /1 /L

'---PickApproach coordinates-----------------------------------------------------------------

	PickApproachX = PickPositionX
	PickApproachY = PickPositionY

'---Increase approach height if tool rotation clearance is required
	If OutW(ToolSelection) = 2 Then
		PickApproachZ = TrayEdgeZClearance + ToolRadiusOffset
	Else
		PickApproachZ = TrayEdgeZClearance
	EndIf

	PickApproachU = PickPositionU

'---Create PickApproach point
	PickApproach = XY(PickApproachX, PickApproachY, PickApproachZ, PickApproachU) /1 /L

'---PickApproach jump configuration----------------------------------------------------------

	If AtHome() Then
		PickJumpRiseDistance = 0
	Else
		If OutW(ToolSelection) = 2 Then
			PickJumpRiseDistance = 0 '5

		ElseIf OutW(ToolSelection) = 3 Then
			PickJumpRiseDistance = 0 'CZ(TLSet(4)) - CZ(DropPosition) - ToolLengthDown + ValveClearance
		EndIf
	EndIf
	
	If CZ(Local(3)) < CZ(Local(1)) + TrayEdgeZClearance Then
		PickJumpRiseDistance = CZ(Local(1)) - CZ(Local(3)) + TrayEdgeZClearance + PickJumpRiseDistance
	EndIf
	
	PickJumpFallDistance = 0
	'PickJumpZLimit = 0
	
	If AtHome Or AtStandByPos Then
		PickJumpZLimit = 0
		
	Else
		PickJumpZLimit = 0 '-33
		
	EndIf

	Arch 0, PickJumpRiseDistance, PickJumpFallDistance
	


'---Plane configuration----------------------------------------------------------------------
		If OutW(ToolSelection) = 2 And Not AtHome() Then
		
		    If CZ(Local(1)) + TrayEdgeZClearance > CZ(Local(3)) Then
		        Plane1Z = CZ(Local(1)) + TrayEdgeZClearance + ToolRadiusOffset
		    Else
		        Plane1Z = CZ(Local(3)) + ToolRadiusOffset
		    EndIf
		
		Else
		
		    If CZ(Local(1)) + TrayEdgeZClearance > CZ(Local(3)) Then
		        Plane1Z = CZ(Local(1)) + TrayEdgeZClearance
		    Else
		        Plane1Z = CZ(Local(3))
		    EndIf
		
		EndIf
		
		Plane 1, XY(0, 0, Plane1Z, 0)
		
		Print "Actual Plane1 Z: ", Plane1Z
'		If OutW(ToolSelection) = 2 And Not AtHome() Then
'			If CZ(Local(1)) + TrayEdgeZClearance > CZ(Local(3)) Then
'				Plane 1, XY(0, 0, CZ(Local(1)) + TrayEdgeZClearance + ToolRadiusOffset, 0)
'			Else
'				Plane 1, XY(0, 0, CZ(Local(3)) + ToolRadiusOffset, 0)
'			EndIf
'			
'		Else
'			If CZ(Local(1)) + TrayEdgeZClearance > CZ(Local(3)) Then
'				Plane 1, XY(0, 0, CZ(Local(1)) + TrayEdgeZClearance, 0)
'			Else
'				Plane 1, XY(0, 0, CZ(Local(3)), 0)
'			EndIf
'		EndIf

'---Tool orientation for next drop-----------------------------------------------------------
	Wait Oport(DropPosJump) = False
	
	If (UseTool2ForPick And Sw(InvertDrop) = False) Or (UseTool2ForPick = False And Sw(InvertDrop)) Then
		OutW ToolSelection, 2
		ToolSensorInput = 19

	ElseIf (UseTool2ForPick And Sw(InvertDrop)) Or (UseTool2ForPick = False And Sw(InvertDrop) = False) Then
		OutW ToolSelection, 3
		ToolSensorInput = 20
	EndIf

'---Print pick movement configuration--------------------------------------------------------

	Print "PickApproach", PickApproach
	Print "PickJumpZLimit", PickJumpZLimit
	'Print "PickJumpFallDistance", PickJumpFallDistance
	Print "PickJumpRiseDistance", PickJumpRiseDistance
	Print "PickPosition", PickPosition
	'Print "ToolRadiusOffset", ToolRadiusOffset
'	Print "Current Drop U: ", CU(DropPosition @0)
'	Print "PickApproach U: ", CU(PickApproach @0)
'	Print "PickJumpRiseDistance: ", PickJumpRiseDistance
'	Print "PickJumpZLimit: ", PickJumpZLimit
'	Print "Plane1 Tray Z: ", CZ(Local(1)) + TrayEdgeZClearance
'	Print "Local3 Z: ", CZ(Local(3))
'	Print "ToolRadiusOffset: ", ToolRadiusOffset
'	Print "WaitPosition", WaitPosition
'	Print "WaitPosition Local0", WaitPosition @0
'	Print "WaitPosition Z Local0: ", CZ(WaitPosition @0)

Fend
		

Function GetDropPosition
	
'---Tool 4 offset coordinates
	Real Tool4OffsetX, Tool4OffsetY, Tool4OffsetZ

'---Drop target coordinates from PLC
	Real DropTargetX, DropTargetY, DropTargetZ, DropTargetU

'---Calculated drop position coordinates
	Real DropPositionX, DropPositionY, DropPositionZ, DropPositionU

'---Calculated drop approach coordinates
	Real DropApproachX, DropApproachY, DropApproachZ, DropApproachU

'---Calculated retreat position coordinates
	Real RetreatPositionX, RetreatPositionY, RetreatPositionZ, RetreatPositionU

'---Calculated wait position coordinates
	Real WaitPositionX, WaitPositionY, WaitPositionZ, WaitPositionU

'---Drop approach U angle wrapped between -180 and 180
	Real WrappedDropApproachU

'---Object and tool clearance calculations
	Real ObjectRadiusSquared, InvertedObjectRadiusSquared, Tool4OffsetZInCatchBoxFrame
	Real Tool3ClearanceOffset, Tool2ClearanceOffset, ToolZDeltaSquared
	Real ObjectRadius, InvertedObjectRadius, ObjectLength, ObjectRadiusClearance

'---Path projection calculations
	Real ApproachPathProjectionRatio, PickToApproachDeltaX, PickToApproachDeltaY
	Real PickToDropDeltaX, PickToDropDeltaY

'---Retreat distance from PLC
	Real RetreatDistance
	RetreatDistance = InW(RetreatDist) * 0.1

'---Drop Z offset; change if drop height to low
	Real DropZOffset
	DropZOffset = 0

'---Base X position for drop approach
	Integer DropApproachXBase
	
	Real SpeedRatio
	SpeedRatio = Speed(1) / 100.0

'---Wait for drop request from PLC
	Wait Sw(GoToDropPos) = True
	Off DropPosRequest

'---Read object dimensions from PLC
	ObjectRadius = InW(ObjRadius) * 0.1
	InvertedObjectRadius = InW(ObjRadiusInv) * 0.1
	ObjectLength = InW(ObjLength) * 0.1

'---Calculate object and tool clearance values
	ObjectRadiusClearance = ObjectRadius - ToolLengthDown
	ObjectRadiusSquared = ObjectRadius * ObjectRadius
	InvertedObjectRadiusSquared = InvertedObjectRadius * InvertedObjectRadius
	Tool2ClearanceOffset = ToolLengthDown + ToolLengthRight + ObjectLength
	Tool3ClearanceOffset = ToolLengthDown - ToolLengthRight + ObjectLength

'---Calculate Tool 4 offset from selected tool and object offset
	Tool4OffsetX = CX(TLSet(OutW(ToolSelection))) + Cos(BracketToolAngle) * InReal(ObjOffset)
	Tool4OffsetY = CY(TLSet(OutW(ToolSelection))) + Sin(BracketToolAngle) * InReal(ObjOffset)
	Tool4OffsetZ = InReal(ToolZ)

'---Apply Tool 4 offset
	TLSet 4, XY(Tool4OffsetX, Tool4OffsetY, Tool4OffsetZ, 0)

'---Calculate Tool 4 Z in CatchBox frame
	Tool4OffsetZInCatchBoxFrame = CZ(Local(3)) + Tool4OffsetZ

'---Read drop target coordinates from PLC
	DropTargetX = InReal(CatchBoxX)
	DropTargetY = InReal(CatchBoxY)
	DropTargetZ = InReal(CatchBoxZ)
	DropTargetU = InReal(CatchBoxU)

'---DropPosition coordinates----------------------------------------------------------------------

	DropPositionX = DropTargetX
	DropPositionY = DropTargetY
	DropPositionZ = DropTargetZ - DropZOffset
	
	If DropPositionZ < Tool4OffsetZ - 200 Then
		DropPositionZ = Tool4OffsetZ - 200
	EndIf

'---Choose DropPositionU
	If OutW(ToolSelection) = 2 Then
	
'		Maintain pick orientation when using tool 2
		DropPositionU = CU(PickPosition @3)

'		If DropPositionY < 31.5 Then
'			DropPositionU = 0
'		Else
'			DropPositionU = 180
'		EndIf
	Else
		DropPositionU = DropTargetU
	EndIf

'---Inverse rotation if rotation is greater than 180 degree
	If DropPositionU - CU(PickPosition @3) > 180 Then
		DropPositionU = DropPositionU - 360

	ElseIf DropPositionU - CU(PickPosition @3) < -180 Then
		DropPositionU = DropPositionU + 360
	EndIf

'---Change orientation if joint limit is reached
	If DropPositionU > 270 - CU(Local(3)) Then
		DropPositionU = DropPositionU - 360

	ElseIf DropPositionU < -270 - CU(Local(3)) Then
		DropPositionU = DropPositionU + 360
	EndIf

'---Create DropPosition point
	DropPosition = XY(DropPositionX, DropPositionY, DropPositionZ, DropPositionU) /3 /L

'---DropApproach coordinates----------------------------------------------------------------------

	DropApproachXBase = 105
	DropApproachY = CY(DropPosition @0)
	
'---Set DropApproachZ according to tool clearance
	DropApproachZ = CZ(PickPosition @0) + TrayEdgeZClearance + ObjectRadiusClearance + Tool4OffsetZ
		
	If DropApproachZ - Tool4OffsetZ < CZ(Local(3)) Then
		DropApproachZ = Tool4OffsetZ + CZ(Local(3))
		
		If DropApproachZ > Tool4OffsetZ Then
			Quit All
		EndIf
		
	ElseIf DropApproachZ > Tool4OffsetZ Then
		DropApproachZ = Tool4OffsetZ
	EndIf

'---Calculate Z distance used for X clearance compensation
	ToolZDeltaSquared = (DropApproachZ - Tool4OffsetZInCatchBoxFrame) * (DropApproachZ - Tool4OffsetZInCatchBoxFrame)

'---Calculate projection ratio of approach point on pick-to-drop path
	PickToApproachDeltaX = DropApproachXBase - CX(PickPosition @0)
	PickToApproachDeltaY = DropApproachY - CY(PickPosition @0)
	PickToDropDeltaX = CX(DropPosition @0) - CX(PickPosition @0)
	PickToDropDeltaY = CY(DropPosition @0) - CY(PickPosition @0)

	ApproachPathProjectionRatio = (PickToApproachDeltaX * PickToDropDeltaX + PickToApproachDeltaY * PickToDropDeltaY) / (PickToDropDeltaX * PickToDropDeltaX + PickToDropDeltaY * PickToDropDeltaY)

''---Calculate DropApproachU along the pick-to-drop path
'	DropApproachU = CU(PickPosition @0) + (CU(DropPosition @0) - CU(PickPosition @0)) * ApproachPathProjectionRatio
'
''---Clamp DropApproachU if path crosses +90 degree
'	If (CU(PickPosition @0) <= 90 And DropApproachU >= 90) Or (CU(PickPosition @0) >= 90 And DropApproachU <= 90) Then
'		DropApproachU = 90
'	EndIf
'
''---Clamp DropApproachU if path crosses -90 degree
'	If (CU(PickPosition @0) <= -90 And DropApproachU >= -90) Or (CU(PickPosition @0) >= -90 And DropApproachU <= -90) Then
'		DropApproachU = -90
'	EndIf



'---Calculate DropApproachU
	If OutW(ToolSelection) = 2 Then
	
	    'Maintain drop orientation throughout transfer
	    DropApproachU = CU(PickPosition @0)
	
	Else
	
	    'Original interpolation
	    DropApproachU = CU(PickPosition @0) + (CU(DropPosition @0) - CU(PickPosition @0)) * ApproachPathProjectionRatio
	
	    'Clamp +90 degrees
	    If (CU(PickPosition @0) <= 90 And DropApproachU >= 90) Or (CU(PickPosition @0) >= 90 And DropApproachU <= 90) Then
	        DropApproachU = 90
	    EndIf
	
	    'Clamp -90 degrees
	    If (CU(PickPosition @0) <= -90 And DropApproachU >= -90) Or (CU(PickPosition @0) >= -90 And DropApproachU <= -90) Then
	        DropApproachU = -90
	    EndIf
	
	EndIf

'---Wrap DropApproachU between -180 and 180
	If DropApproachU < -180 Then
		WrappedDropApproachU = DropApproachU + 360

	ElseIf DropApproachU > 180 Then
		WrappedDropApproachU = DropApproachU - 360

	Else
		WrappedDropApproachU = DropApproachU
	EndIf

'---Calculate DropApproachX clearance compensation
	If WrappedDropApproachU > 0 And WrappedDropApproachU < 180 Then

		If OutW(ToolSelection) = 2 Then
			DropApproachX = DropApproachXBase + (ObjectRadius - Sqr(ObjectRadiusSquared - ToolZDeltaSquared)) * Abs(Sin(DegToRad(DropApproachU)))

		ElseIf OutW(ToolSelection) = 3 Then
			DropApproachX = DropApproachXBase + Abs(Sin(DegToRad(DropApproachU))) * Tool3ClearanceOffset
		EndIf

	Else

		If OutW(ToolSelection) = 2 Then
			DropApproachX = DropApproachXBase + Abs(Sin(DegToRad(DropApproachU))) * Tool2ClearanceOffset

		ElseIf OutW(ToolSelection) = 3 Then
			DropApproachX = DropApproachXBase + (InvertedObjectRadius - ToolLengthDown) * Abs(Sin(DegToRad(DropApproachU)))
		EndIf

	EndIf

'---Create DropApproach point
	DropApproach = XY(DropApproachX, DropApproachY, DropApproachZ, DropApproachU) /0 /L

'---RetreatPosition coordinates-----------------------------------------------------------------------------

	'---Calculate retreat position based on active tool orientation
	If OutW(ToolSelection) = 2 Then
		RetreatPositionX = RetreatDistance * Cos(DegToRad(DropPositionU - 90)) + DropPositionX
		RetreatPositionY = RetreatDistance * Sin(DegToRad(DropPositionU - 90)) + DropPositionY

	ElseIf OutW(ToolSelection) = 3 Then
		RetreatPositionX = -RetreatDistance * Cos(DegToRad(DropPositionU - 90)) + DropPositionX
		RetreatPositionY = -RetreatDistance * Sin(DegToRad(DropPositionU - 90)) + DropPositionY
	EndIf

	RetreatPositionZ = DropPositionZ
	RetreatPositionU = DropPositionU

'---Create RetreatPosition point
	RetreatPosition = XY(RetreatPositionX, RetreatPositionY, RetreatPositionZ, RetreatPositionU) /3 /L

'---WaitPosition coordinates-------------------------------------------------------------------------------

	WaitPositionX = RetreatPositionX
	WaitPositionY = RetreatPositionY

'---Set wait height according to tool clearance
'	If OutW(ToolSelection) = 2 Then
'		WaitPositionZ = DropPositionZ + 5
'
'	ElseIf OutW(ToolSelection) = 3 Then
'		WaitPositionZ = Tool4OffsetZ - ToolLengthDown + ValveClearance
'	EndIf
	
	WaitPositionZ = CZ(DropApproach @3) + 15
	WaitPositionU = RetreatPositionU

'---Create WaitPosition point
	WaitPosition = XY(WaitPositionX, WaitPositionY, WaitPositionZ, WaitPositionU) /3 /L

'---DropApproach jump configuration-------------------------------------------------------------------------

'---Set rise distance for minimum travel while avoiding tray collision
	If CZ(PickPosition @0) + TrayEdgeZClearance + ObjectRadiusClearance > 0 Then
		DropJumpRiseDistance = -CZ(PickPosition @0)
	Else
		DropJumpRiseDistance = TrayEdgeZClearance + ObjectRadiusClearance
	EndIf

'---Set fall distance for minimum travel while avoiding CatchBox collision
	If Tool4OffsetZ - ToolLengthDown + ValveClearance > 0 Then
		DropJumpFallDistance = Tool4OffsetZ - ToolLengthDown + ValveClearance - DropPositionZ
	Else
		DropJumpFallDistance = -DropPositionZ
	EndIf

'---Use DropApproachZ as drop jump Z limit
	DropJumpZLimit = DropApproachZ - Tool4OffsetZ

'---Apply jump configuration
	Arch 1, DropJumpRiseDistance, 0
	Arch 2, 0, DropJumpFallDistance

'---Trigger plane configuration------------------------------------------------------------------------------------
		
	Plane 2, XY(CX(Local(1)), CY(Local(1)), CZ(Local(1)) + Tool4OffsetZ + DropJumpRiseDistance * (1 - SpeedRatio), 0)
	Plane 3, XY(CX(Local(3)), CY(Local(3)), CZ(Local(3)) + DropPositionZ + 4 * SpeedRatio, 0)
	Plane 4, XY(115 + 50 * SpeedRatio, 0, 0, 0, -90, 0)
	VisionTriggerToleranceU = 5 + 10 * SpeedRatio


'---Print drop movement configuration----------------------------------------------------------------------

	Print "DropApproach", DropApproach
	'Print "DropJumpZLimit", DropJumpZLimit
	'Print "DropJumpFallDistance", DropJumpFallDistance
	'Print "DropJumpRiseDistance", DropJumpRiseDistance
	Print "DropPosition", DropPosition
	Print "RetreatPosition", RetreatPosition
	'Print "WaitPosition", WaitPosition
	'Print "SpeedRatio", SpeedRatio
	'Print "Speed", Speed(1)
	Print "Pick U Local0: ", CU(PickPosition @0)
	Print "DropApproach U Local0: ", CU(DropApproach @0)
	Print "Drop U Local0: ", CU(DropPosition @0)
	Print "Retreat U Local0: ", CU(RetreatPosition @0)
		
Fend


Function MonitorDropPosJump
	
	Off JointDropped
	Off JointMissing
	
'---Wait until robot crosses tool switch trigger plane
	Wait GetRobotInsidePlane(2) = 1
	On SwitchTool

'---Wait until robot crosses vision trigger plane
	Wait GetRobotInsidePlane(4) = 1

'---Wait until robot orientation is close enough to DropPosition
	Do
		If Abs(CU(RealPos @0) - CU(DropPosition @0)) <= VisionTriggerToleranceU Then
			On PickPosRequest
		EndIf
		Wait 0.004
	Loop Until Oport(PickPosRequest)
		
Fend

Function MonitorVacuum

	WaitSig 1
	
	Do
		Wait 0.01
	Loop Until Abs(CU(CurPos @0) - CU(DropPosition @0)) < 0.01
	
	Wait GetRobotInsidePlane(3) = 0
	If Sw(VacuumConfirm) = True Then
		On JointDropped
	Else
		On JointMissing
	EndIf
	Off VacuumValve
Fend
Function MonitorSwitchTool1

    Do

        If CZ(RealPos @0) >= ToolSwitchPlaneZ Then
            Exit Do
        EndIf

        Wait 0.004

    Loop

    '---Return physical tool to center
    On SwitchTool1

    Print "SwitchTool1 activated at Z: ", CZ(RealPos @0)

Fend

