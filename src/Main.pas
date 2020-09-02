{
  Copyright 2007 Black Phoenix <phoenix@uol.ua>

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
}

unit Main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, Hyper64, Math, ExtCtrls, FModDyn, FModTypes, modEqualizer, modKeyTable,
  modCRC, IdBaseComponent, IdComponent, IdUDPBase, IdUDPClient, modFVersion,
  IdUDPServer;

type TBall = record
  X,Y,DX,DY,M,R : Single;
  IsBlackHole : Boolean;
  TTD : Single;

  Evility : Integer;

  NextBall, PrevBall : Pointer;
end;
type PBall = ^TBall;

type
  TfrmMain = class(TForm)
    Timer: TTimer;
    BallTimer: TTimer;
    FPSTimer: TTimer;
    UDP: TIdUDPClient;
    procedure FormCreate(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure BallTimerTimer(Sender: TObject);
    procedure FPSTimerTimer(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    { Private declarations }
  public
    { Public declarations }
    procedure Simulate;
    procedure AddBlackHole;
    procedure AddNormalBall;
    procedure NewGame;
    procedure Death;
    procedure SetupTitle;

    procedure CheatTest;

    procedure EventException(Sender: TObject; E: Exception);

    function FMod(X,Y : Single) : Single;

    procedure KillBall(var Ball : PBall);
    procedure KillAllBalls;
    function AddBall : PBall;

    procedure LoadBGSong(Name : String);
    procedure LoadSongs;

    procedure HiScore_Submit;

    function XORFunc(I : Cardinal) : Cardinal;

    function CheckCode(Name : String; Score : Integer) : Integer;
  end;

type THiscore = record
  Name : String;
  Score,CheckCode : Integer;
end;

var
  frmMain: TfrmMain;
  Scr : THyper64;
  FullScr : TFullHyper64;
  Buf, Buf2, LastBuf : TBuffer64;
  Time : TTimer64;
  Input : TInput64;
  HPK : THPK;

  FontName : String;
  FontCharset : Integer;
  FontSize : Single;
//  Snd : TSound64;

  Settings, HiScoreStore : TKeyTable;
  LoadedSong : String;
  VistaIssue : Boolean;

  MasterMass, SkillMod,NextPowerUpTime : Single;
  CalcMasterMass,DeathTime,LastBlackHoleTime,BlackHoleMode : Single;
  PushedLeft, PushedRight : Boolean;

  Frames,Score,MX,MY : Integer;
  XorOfScore : Cardinal;

  Died, GameStarted, Paused : Boolean;

  FirstBall, LastBall, BlackHole : PBall;
  BallCount, UniverseMass, BallID,Ball_AddEffect : Integer;

  PowerupMsg : String;
  PowerupMsgTime : Single;

  DSP : PFSoundDSPUnit;

  DSP_Distortion : Single;
  DSP_DEQ, DSP_DeathEQ, DSP_MasterEQ,DSP_BassEQ : EQState;
  Volume,VULeft,VURight,VULeftPeak,VURightPeak : Single;
  DSP_SomethingDied, DSP_MenuClick : Single;

  GraphicLevel : Integer;
  DisplayCoolStuff, PrevBlurred, AcceptButton_TempFix : Boolean;

  Songs : array[1..5] of PFMusicModule;

  MenuID : Integer;

  HiScores : array[1..10] of THiScore;

  Oscililoscope : array[0..127] of Single;

  HiScore_EnteringName, TakeScreenShot : Boolean;
  HiScoreNewName, PanicMessage : String;

  AntiCheatCounters : array[1..1000] of Integer;

//  hSem: THandle = 0;

type TFPoint = record
  X,Y : Single;
end;

const W = 39; //800 -> 40
      H = 29; //600 -> 30
var Gird : array[0..W,0..H] of TFPoint;

implementation

uses modDebug;

{$R *.dfm}

function Clip(Sample : Double) : Integer;
begin
  Result := Round(Max(Min(Sample,32767),-32767));
end;

type
  PSmallintArray = ^TSmallintArray;
  TSmallintArray = array [0..0] of Smallint;

const DSP_DEATH_GAIN = 1;
      DSP_DEATH_LOW = 100;
      DSP_DEATH_HIGH = 300;

function DSPProc(OriginalBuffer: Pointer; NewBuffer: Pointer; Length, Param: Integer): Pointer; stdcall;
var
  AData: PSmallintArray;
  DistortionData, VUData : array[0..8191] of Smallint;
  I,J : Integer;
  TMP : Single;
begin
 // try

  AData := PSmallintArray(OriginalBuffer);
  {SetLength(DistortionData,Length*4);
  SetLength(VUData,Length*4);}

  //MONO
  {for I := 0 to Length-1 do begin
    AData[I*2] := Clip((AData[I*2+1] + AData[I*2]) / 2);
    AData[I*2+1] := Clip((AData[I*2+1] + AData[I*2]) / 2);
  end;}

  //EQ
  for I := 0 to Length*2-1 do begin
    AData[I] := Clip(EQ_Sample(DSP_MasterEQ,AData[I]));
  end;  
  for I := 0 to Length*2-1 do begin
    AData[I] := Clip(EQ_Sample(DSP_DeathEQ,AData[I]));
  end;
  for I := 0 to Length*2-1 do begin
    DistortionData[I] := Clip(EQ_Sample(DSP_DEQ,AData[I]));
  end;

  for I := 0 to Length*2-1 do begin
    VUData[I] := Clip(EQ_Sample(DSP_BassEQ,AData[I]));
  end;

  //DSP
  TMP := 0;
  for I := 0 to Length*2-1 do begin
    if I mod 128 = 0 then TMP := 8000*Random*DSP_Distortion;
    AData[I] := Clip(AData[I]*(1-DSP_Distortion*0.1) + 0.03*Clip(DistortionData[I]*256*DSP_Distortion) + TMP);
  end;

  for I := 0 to Length*2-1 do begin
    if I mod 1024 < 512 then
      AData[I] := Clip(AData[I] + 32000*DSP_SomethingDied)
    else
      AData[I] := Clip(AData[I] + 8000*Random*DSP_SomethingDied);
  end;

  for I := 0 to Length*2-1 do begin
    if I mod 64 < 32 then
      AData[I] := Clip(AData[I] + 10000*DSP_MenuClick)
    else
      AData[I] := Clip(AData[I] + 10000*Random*DSP_MenuClick);
  end;

  if GameStarted and (BlackHole <> nil) then
    if BlackHole.TTD < 200 then begin
      for I := 0 to Length*2-1 do begin
        if I mod 512 < 256 then
          AData[I] := Clip(AData[I] + 6000)
        else
          AData[I] := Clip(AData[I] + 6000*Random);
      end;
    end else begin
      for I := 0 to Length*2-1 do begin
        if I mod 2048 < 1024 then
          AData[I] := Clip(AData[I] + 6000)
        else
          AData[I] := Clip(AData[I] + 6000*Random);
      end;
    end;

  if PushedLeft and not Died and GameStarted then begin
    J := Round(512{ - UniverseMass/10{64*Sin(Time.Time)});
    for I := 0 to Length*2-1 do begin
      if I mod J < J div 2 then
        AData[I] := Clip(AData[I] + 4000)
      else
        AData[I] := Clip(AData[I] + 4000*Random);
    end;
  end;
  {if PushedRight and not Died and GameStarted then begin
    J := Round(16);
    for I := 0 to Length*2-1 do begin
      if I mod J < J div 2 then
        AData[I] := Clip(AData[I] + 4000)
      else
        AData[I] := Clip(AData[I] + 4000*Random);
    end;

    J := Round(640);
    for I := 0 to Length*2-1 do begin
      if I mod J < J div 2 then
        AData[I] := Clip(AData[I] + 4000)
      else
        AData[I] := Clip(AData[I] + 4000*Random);
    end;
  end;}  

  DSP_SomethingDied := DSP_SomethingDied - 0.15;
  if DSP_SomethingDied < 0 then DSP_SomethingDied := 0;

  DSP_MenuClick := DSP_MenuClick - 0.1;
  if DSP_MenuClick < 0 then DSP_MenuClick := 0;

  //Calculate VU
  for i := 0 to Length-1 do begin
    VULeft := VULeft + Abs(VUData[I*2] / 32768);
    VURight := VURight + Abs(VUData[I*2+1] / 32768);
  end;
  VULeft := Min(VULeft / (Length / 2),1);
  VURight := Min(VURight / (Length / 2),1);
  if VULeft > VULeftPeak then VULeftPeak := VULeft;
  if VURight > VURightPeak then VURightPeak := VURight;

  for I := 0 to 127 do begin
    Oscililoscope[I] := ((AData[I*2+1]+AData[I*2]) / 2) / 32768;
  end;

  //Volume
  for I := 0 to Length*2-1 do begin
    AData[I] := Clip(Volume*AData[I]);
  end;

  {FreeMem(DistortionData);
  FreeMem(VUData);}
  //SetLength(DistortionData,0);
  //SetLength(VUData,0);
  Result := Pointer(AData);

  //except Result := Pointer(OriginalBuffer) end;
//  hSem := CreateSemaphore(nil, 1, 1, nil);
end;

procedure TfrmMain.FormCreate(Sender: TObject);

function SCompare(L,R : Integer) : Integer;
begin
  Result := HiScores[R].Score-HiScores[L].Score;
end;
procedure ExchangeItems(L,R : Integer);
var Temp : THiscore;
begin
  Temp := HiScores[L];
  HiScores[L] := HiScores[R];
  HiScores[R] := Temp;
end;
procedure QuickSort(L, R: Integer);
var
  I, J, P: Integer;
begin
  repeat
    I := L;
    J := R;
    P := (L + R) shr 1;
    repeat
      while SCompare(I, P) < 0 do Inc(I);
      while SCompare(J, P) > 0 do Dec(J);
      if I <= J then
      begin
        ExchangeItems(I, J);
        if P = I then
          P := J
        else if P = J then
          P := I;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then QuickSort(L, J);
    L := I;
  until I >= R;
end;

var X,Y: Integer;
begin
  Application.OnException := EventException;
  _DebugMode := False;
  _init;
  _call('FormCreate','',[]);

  if not FileExists('music.dat') then begin
    ShowMessage('Cant load - music.dat is missing!');
    Application.Terminate;    
    _leave;
    Exit;
  end;

  HPK := THPK.Create('music.dat');
  if not FileExists('fmod.dll') then
    HPK.UnPackToFile('fmod.dll','fmod.dll');

  FMOD_Load('fmod.dll');
  Settings := TKeyTable.Create;
  Settings.OpenTable(ExtractFilePath(Application.ExeName) + 'gravitywarz.settings');

  _DebugMode := Settings.GetBool('settings','debugmode',True);

  Randomize;
  if Settings.GetBool('settings','fullscreen',True) then begin
    FullScr := TFullHyper64.Create(Handle,800,600,32);
    Buf := TBuffer64.Create(FullScr,FullScr.XSize,FullScr.YSize,False);
    Buf2 := TBuffer64.Create(FullScr,FullScr.XSize,FullScr.YSize,False);
    LastBuf := TBuffer64.Create(FullScr,FullScr.XSize,FullScr.YSize,False);
  end else begin
    Scr := THyper64.Create(Handle,800,600);
    Buf := TBuffer64.Create(Scr,Scr.XSize,Scr.YSize,False);
    Buf2 := TBuffer64.Create(Scr,Scr.XSize,Scr.YSize,False);
    LastBuf := TBuffer64.Create(Scr,Scr.XSize,Scr.YSize,False);
  end;
  
  Input := TInput64.Create(Handle);
  Time := TTimer64.Create(tfSec);
  Time.Start;

  Input.SetWinCursor(false);
//  Input.m_setPosition(10,10);

  GameStarted := False;
  TakeScreenShot := False;
  KillAllBalls;

  AddNormalBall;
  AddNormalBall;
  AddNormalBall;
  AddNormalBall;

  FirstBall.X := -1e6;
  FirstBall.Y := -1e6;

  BallTimer.Interval := 1000;
  Frames := 0;
  LastBlackHoleTime := -1e10;
  NextPowerUpTime := -1e10;
  SkillMod := 1;

   HiScores[1].Name := 'JACK';
   HiScores[2].Name := 'JOHN';
   HiScores[3].Name := 'TOM';
   HiScores[4].Name := 'TRACY';
   HiScores[5].Name := 'MARTIN';
   HiScores[6].Name := 'PHAZE';
   HiScores[7].Name := 'DAVID';
   HiScores[8].Name := 'TOBY';
   HiScores[9].Name := 'PETER';
  HiScores[10].Name := 'OZZY';

  for X := 1 to 10 do begin
    HiScores[X].Score := (11-X)*25000;
    HiScores[X].CheckCode := CheckCode(HiScores[X].Name,HiScores[X].Score);
  end;

  HiScoreStore := TKeyTable.Create;
  HiScoreStore.OpenTable('gravitywarz.hiscore');
  HiScoreStore.SetStr('game','name','Gravity Warz');

  for X := 1 to 10 do begin
    HiScores[X].Name := HiScoreStore.GetStr('hiscore',IntToStr(X) + '_name',HiScores[X].Name);
    HiScores[X].Score := HiScoreStore.GetInt('hiscore',IntToStr(X) + '_score',HiScores[X].Score);
    HiScores[X].CheckCode := StrToInt('$' + HiScoreStore.GetStr('hiscore',IntToStr(X) + '_CheckCode',IntToHex(HiScores[X].CheckCode,8)));
  end;

  QuickSort(1,10);

  HiScoreStore.Save;

  GraphicLevel := Settings.GetInt('settings','graphiclevel',1); //Highest

  //Make megagird
  for X := 0 to W do begin
    for Y := 0 to H do begin
      Gird[X,Y].X := ClientWidth*(X / W);
      Gird[X,Y].Y := ClientHeight*(Y / H);
    end;
  end;

  //Init FMOD
  if not FSOUND_SetOutput(FSOUND_OUTPUT_DSOUND) or
     not FSOUND_SetDriver(0) or
     not FSOUND_SetMixer(FSOUND_MIXER_QUALITY_AUTODETECT) or
     not FSOUND_SetHWND(Handle) then begin
    ShowMessage('Soundsystem can''t init');
    Application.Terminate;
    _leave;
    Exit;
  end;

  FSOUND_SetBufferSize(128);
  FSOUND_Stream_SetBufferSize(2048);

  if not FSOUND_Init(22050, 128, FSOUND_INIT_GLOBALFOCUS{ or
                                 FSOUND_INIT_STREAM_FROM_MAIN_THREAD}) then begin
    ShowMessage('Soundsystem can''t init');
    Application.Terminate;
    _leave;
    Exit;
  end;

  DSP := FSOUND_DSP_Create(DSPProc, FSOUND_DSP_GetPriority(FSOUND_DSP_GetFFTUnit)-1, 0);
  FSOUND_DSP_SetActive(DSP, true);

  //LoadBGSong('FIRSTSTR.MOD');

  DSP_Distortion := 0;
  DSP_SomethingDied := 0;
  EQ_InitState(DSP_DEQ,880,3500,22050);
  EQ_InitState(DSP_DeathEQ,DSP_DEATH_LOW,DSP_DEATH_HIGH,22050);
  EQ_InitState(DSP_MasterEQ,880,3500,22050);
  EQ_InitState(DSP_BassEQ,280,1500,22050);

  DSP_DEQ.lg := 0;
  DSP_MasterEQ.lg := Settings.GetFloat('settings','master_bass',2);

  DSP_BassEQ.lg := 1;
  DSP_BassEQ.mg := 0;
  DSP_BassEQ.hg := 0;

  Volume := Settings.GetFloat('settings','volume',1);
  DisplayCoolStuff := Settings.GetBool('settings','displaycoolstuff',false);

  MenuID := 0;
  Paused := False;

  LoadSongs;

  LoadBGSong('THECONF.XM');
  SetupTitle;

  if Screen.Fonts.IndexOf('WST_Engl') <> -1 then begin
    FontName := 'WST_Engl';
    FontCharset := SYMBOL_CHARSET;
    FontSize := 1;
    VistaIssue := False;
  end else begin
    FontName := 'Lucida Console';
    FontCharset := ANSI_CHARSET;
    FontSize := 0.75;
    VistaIssue := True;    
  end;
//  Screen.Fonts

  FPSTimerTimer(nil);
  _leave;
end;

procedure TfrmMain.Simulate;
var NX,NY,D,TX,TY,F : Single;
    Ball, BallJ : PBall;
begin
  _call('Simulate','',[]);

  //if GameStarted then Ball := FirstBall.NextBall else Ball := FirstBall;
  Ball := FirstBall.NextBall;
  while (Ball <> nil) do begin
    //Step 1: check ball collisions
    {for J := 0 to High(Balls) do
      if (I <> J) and (Sqr(Balls[I].X-Balls[J].X)+Sqr(Balls[I].Y-Balls[J].Y) <= Sqr(Balls[I].M + Balls[J].M)) then begin
        //1. Calculate collision vector
        NX := Balls[I].X-Balls[J].X;
        NY := Balls[I].Y-Balls[J].Y;

        //2. Normalize
        D := Sqrt(NX*NX+NY*NY)+1e-6;
        NX := NX / D;
        NY := NY / D;

        F := (Balls[J].M/Balls[I].M)+1e-6;
        //F := Min(Max(F,0),1.1);

        //3. Modify direction vector of each ball
        Balls[I].DX := Balls[I].DX*NX*F;
        Balls[I].DY := Balls[I].DY*NY*F;
        Balls[J].DX := -Balls[J].DX*NX*(1/F);
        Balls[J].DY := -Balls[J].DY*NY*(1/F);

        //4. Apply antistick
        //Balls[I].X := Balls[J].X + NX*(Balls[J].M+Balls[J].M);
        //Balls[I].Y := Balls[J].Y + NY*(Balls[J].M+Balls[J].M);
      end;}

    //Step 1a: Collide against walls
    if (Ball.X < Ball.R) then begin
      Ball.X := Ball.R;
      Ball.DX := -Ball.DX;
    end;
    if (Ball.X > Buf.XSize*2-Ball.R) then begin
      Ball.X := Buf.XSize*2-Ball.R;
      Ball.DX := -Ball.DX;
    end;
    if (Ball.Y < Ball.R) then begin
      Ball.Y := Ball.R;
      Ball.DY := -Ball.DY;
    end;
    if (Ball.Y > Buf.YSize*2-Ball.R) then begin
      Ball.Y := Buf.YSize*2-Ball.R;
      Ball.DY := -Ball.DY;
    end;
    //Step 2: Accumulate gravity force
    NX := 0;
    NY := 0;
    BallJ := FirstBall;
    while BallJ <> nil do begin
      if (Ball <> BallJ) and not(Sqr(Ball.X-BallJ.X)+Sqr(Ball.Y-BallJ.Y) <= Sqr(Ball.R + BallJ.R)) then begin
        //1. Calculate distance
        TX := BallJ.X-Ball.X;
        TY := BallJ.Y-Ball.Y;
        D := Sqrt(TX*TX+TY*TY)+1e-6;

        //2. Calculate normalized direction vector
        TX := TX / D;
        TY := TY / D;

        //3. Calculate force
        F := (Abs(BallJ.M/Ball.M)*(Ball.M*BallJ.M)) / (D*D+1e-6);

        //4. Accumulate force
        NX := NX + TX*F;
        NY := NY + TY*F;
      end;
      BallJ := BallJ.NextBall;
    end;

    Ball.DX := Min(Max(Ball.DX + NX,-16),16);
    Ball.DY := Min(Max(Ball.DY + NY,-16),16);

    if not Ball.IsBlackHole then begin
      Ball.X := Ball.X + Ball.DX;
      Ball.Y := Ball.Y + Ball.DY;
    end;

    Ball := Ball.NextBall;
  end;
  _leave;
end;

function Darken(C : Integer; F : Single) : Integer;
var r,g,b : Byte;
begin
  if Assigned(Scr) then Scr.UnRGB(c,r,g,b)
  else FullScr.UnRGB(c,r,g,b);
  r := Round(Max(Min(r * F,255),0));
  g := Round(Max(Min(g * F,255),0));
  b := Round(Max(Min(b * F,255),0));
  if Assigned(Scr) then Result := Scr.RGB(r,g,b)
  else Result := FullScr.RGB(r,g,b);
end;

procedure TfrmMain.TimerTimer(Sender: TObject);

procedure DrawUI;
var C,X,Y : Integer;
begin
  _call('TimerTimer.DrawUI','',[]);

  if GameStarted then begin
    Buf.FillRect(14,14,18+200,34,0);
    Buf.FillRect(16,16,16+200,32,$3F);
    Buf.FillRect(16,16,16+Round(MasterMass),32,$FF);

    C := Darken($00FF00,0.5+(VULeftPeak+VURightPeak)/2.5);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(32*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(250+X*2,16+Y*2,'SCORE: ' + IntToStr(Score),0);
        if VistaIssue then
          Buf.WriteStr(450+X*2,16+Y*2,'UNIVERSE ENERGY: ' + IntToStr(UniverseMass),0)
        else
          Buf.WriteStr(400+X*2,16+Y*2,'UNIVERSE ENERGY: ' + IntToStr(UniverseMass),0);
        //Buf.WriteStr(700+X*2,16+Y*2,'A: ' + FloatToStrF(Time.Time,ffFixed,2,1),0);
      end;
                                             
    Buf.WriteStr(250,16,'SCORE: ' + IntToStr(XORFunc(XorOfScore)),C);
    if VistaIssue then
      Buf.WriteStr(450,16,'UNIVERSE ENERGY: ' + IntToStr(UniverseMass),C)
    else
      Buf.WriteStr(400,16,'UNIVERSE ENERGY: ' + IntToStr(UniverseMass),C);
    //Buf.WriteStr(700,16,'A: ' + FloatToStrF(Time.Time,ffFixed,2,1),C);
  end;
  _leave;
end;

var I,X,Y,T,K : Integer;
    NX,NY,D,TX,TY,F,NewDistortion : Single;
    Ball, KBall : PBall;
    WaitReturn : DWord;

    TMP : array[0..9] of String;
begin
  _call('TimerTimer','',[]);

  for I := 1 to 1000 do
    AntiCheatCounters[I] := Random($FFFFFF);

  CheatTest;

  if PanicMessage <> '' then begin
    Buf.Fill($7F);
    Buf.ChangeFont('Terminal',FW_NORMAL,OEM_CHARSET,12);
    Buf.WriteStr(16,16,PanicMessage,$FFFFFF);
    Buf.WriteStr(16,32,'Please send the file to bugs@forest-tm.com, so I could fix the bug, if its present (probably)',$FFFFFF);
    Buf.WriteStr(16,48,'Press space to restore game state (exception may occur again), any other key to quit (recomended to restart)',$FFFFFF);
    Buf.Flip(false);
    _leave;
    Exit;
  end;

//  WaitReturn := WaitForSingleObject(hSem, INFINITE);
//  if WaitReturn <> WAIT_OBJECT_0 then Exit;
  try
  Inc(Frames);

  VULeftPeak := VULeftPeak - 0.04;
  if VULeftPeak < 0 then VULeftPeak := 0;
  VURightPeak := VURightPeak - 0.04;
  if VURightPeak < 0 then VURightPeak := 0;  

  Buf.Fill(0);

  UniverseMass := 0;
  Ball := FirstBall.NextBall;
  while Ball <> nil do begin
    UniverseMass := UniverseMass + Round(Abs(Ball.DX) + Abs(Ball.DY));
    Ball := Ball.NextBall;
  end;
//  Caption := IntToStr(UniverseMass);
  if BlackHole <> nil then begin
    if BlackHole.TTD < 200 then BlackHole.M := 300*SkillMod+0.1*(200-BlackHole.TTD) else BlackHole.M := 10;
  end;

  if not Paused then Simulate;

  //Make megagird
  if not Paused then
    for X := 0 to W do begin
      for Y := 0 to H do begin
        Gird[X,Y].X := (Gird[X,Y].X*1.5 + ClientWidth*(X / W)*0.5) / 2;
        Gird[X,Y].Y := (Gird[X,Y].Y*1.5 + ClientHeight*(Y / H)*0.5) / 2;
      end;
    end;

  //Apply gird physics
  if not Paused then
    for X := 0 to W do begin
      for Y := 0 to H do begin
        NX := 0;
        NY := 0;
        Ball := FirstBall;
        while Ball <> nil do begin
          //1. Calculate distance
          TX := 2*Gird[X,Y].X-Ball.X;
          TY := 2*Gird[X,Y].Y-Ball.Y;
          D := Sqrt(TX*TX+TY*TY)+1e-6;
          //2. Calculate normalized direction vector
          TX := TX / D;
          TY := TY / D;

          //3. Calculate force
          {if I = 0 then
            F := -8*(Ball.M /(0.5*D))
          else }
          F := -10*(Ball.M /(0.5*D));

          //4. Accumulate force
          NX := Max(Min(NX + TX*F,D),-D);
          NY := Max(Min(NY + TY*F,D),-D);

          Ball := Ball.NextBall;
        end;
        Gird[X,Y].X := ((Gird[X,Y].X + {Max(Min(}NX{,10),-10)}) + Gird[X,Y].X) / 2;
        Gird[X,Y].Y := ((Gird[X,Y].Y + {Max(Min(}NY{,10),-10)}) + Gird[X,Y].Y) / 2;
      end;
    end;

  BlackHoleMode := BlackHoleMode - 1;
  if (BlackHoleMode > 0) and (BlackHole = nil) then
    BlackHole := FirstBall;
  if (BlackHoleMode < 0) and (BlackHole = FirstBall) then
    BlackHole := nil;    

  //Render black hole
  if BlackHole <> nil then begin
    if BlackHole.TTD < 200 then begin
      for X := 48 downto 1 do begin
        Buf.FillCircle(Round(BlackHole.X/2),Round(BlackHole.Y/2),
                   Round(X*2),Round(Min(255,Max(0,$FF*(Max(0,Abs(Sin(Time.Time*4+X*2/10))) - (X*2/100))))));
      end;

      if (GraphicLevel <= 1) and (BlackHole <> FirstBall) then begin
        {I := 10;}
        for X := 1 to 36 do begin
          {Buf.Line(Round(BlackHole.X/2+(256-FMod(Time.Time*200+X*10,256))*Cos(DegToRad(X*8)+Time.Time/I)),
                   Round(BlackHole.Y/2+(256-FMod(Time.Time*200+X*10,256))*Sin(DegToRad(X*8)+Time.Time/I)),
                   Round(BlackHole.X/2+(256-FMod(Time.Time*200+X*10,256)+32)*Cos(DegToRad(X*8)+Time.Time/I)),
                   Round(BlackHole.Y/2+(256-FMod(Time.Time*200+X*10,256)+32)*Sin(DegToRad(X*8)+Time.Time/I)),
                   $FF);}
          Buf.SLine(Round(BlackHole.X/2),
                    Round(BlackHole.Y/2),
                    Round(BlackHole.X/2+256*Cos(DegToRad(X*10)+Time.Time)),
                    Round(BlackHole.Y/2+256*Sin(DegToRad(X*10)+Time.Time)),
                    64,Abs(Round(Time.Time*64+X*100)),$FFFFFF);
        end;
      end;
    end else begin
      for X := 48 downto 1 do begin
        Buf.FillCircle(Round(BlackHole.X/2),Round(BlackHole.Y/2),
                   Round(X*2),Round(Min(255,Max(0,$FF*(Max(0,Abs(Cos(Time.Time*4))*(Abs(Sin(Time.Time*32+X*2/10))) - (X*2/100)))))));
      end;
    end;

    if BlackHole <> FirstBall then begin
      if (not Paused) and (BlackHole.TTD < 200) then begin
        TX := -FirstBall.X+BlackHole.X;
        TY := -FirstBall.Y+BlackHole.Y;
        D := Sqrt(TX*TX+TY*TY)+1e-6;
        MasterMass := MasterMass - (Min(SkillMod,3)*200)/(D);
      end;

      if not Paused then
        BlackHole.TTD := BlackHole.TTD - 1;
      if BlackHole.TTD < 0 then begin
        Buf.Negative;
        DSP_SomethingDied := 1;
        KillBall(BlackHole);
        BlackHole := nil;
        LastBlackHoleTime := Time.Time;
      end;
    end;
  end;

  if Ball_AddEffect > 0 then begin
    Ball := LastBall;
    for I := Round(Ball.R) downto 1 do
      Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(I),
                     Darken($0000FF,0.1+0.1*Sin(Time.Time*8+Ball_AddEffect+I/2)+Ball.M/400{-0.1*Sqr(1-Ball_AddEffect/30)}));
    Ball_AddEffect := Ball_AddEffect - 1;
  end;  

  CheatTest;

  NewDistortion := 0;
  if GameStarted then begin
    if not Paused then begin
      if PushedLeft and not Died then begin
        CalcMasterMass := CalcMasterMass + 0.1*(MasterMass*8 - CalcMasterMass)
      {end else if PushedRight and not Died then begin
        CalcMasterMass := CalcMasterMass + 0.8*(-MasterMass*4 - CalcMasterMass);}
      end else begin
        if BlackHoleMode > 0 then
          CalcMasterMass := CalcMasterMass + 0.2*(MasterMass*8 - CalcMasterMass)
        else
          CalcMasterMass := CalcMasterMass + 0.2*(MasterMass - CalcMasterMass);
      end;

      FirstBall.M := CalcMasterMass;
      FirstBall.R := 25*(MasterMass/50);
      if FirstBall.R > 25 then FirstBall.R := 25;
    end;

    if not Died then begin
      Ball := FirstBall.NextBall;
      while Ball <> nil do begin
        KBall := Ball.NextBall;
        //1. Calculate distance
        TX := -FirstBall.X+Ball.X;
        TY := -FirstBall.Y+Ball.Y;
        D := Sqrt(TX*TX+TY*TY)+1e-6;
        {//2. Calculate normalized direction vector
        TX := TX / D;
        TY := TY / D; }

        //3. Calculate force
        {F := -4*(Ball.M /(0.5*D));}
        if PushedLeft then
          F := D/(128 + 128*Abs(CalcMasterMass)/MasterMass)
        else
          F := D/(256 + 256*Abs(CalcMasterMass)/MasterMass);

        if D < 512 then begin
          NewDistortion := NewDistortion + (1-F)*0.5;
        end;

        if Ball.Evility < 2 then
          if PushedLeft{ or PushedRight} then begin
            if D < 512 then
              for X := 0 to 31 do
                Buf.CubicBezierLine(Round(FirstBall.X/2),Round(FirstBall.Y/2),Round(Ball.X/2),Round(Ball.Y/2),
                                    Round(FirstBall.X/2+TX*0.1+Random*80),Round(FirstBall.Y/2+TX*0.1+Random*80),
                                    Round(FirstBall.X/2+TX*0.4+Random*80),Round(FirstBall.Y/2+TX*0.4+Random*80),
                                    32 div GraphicLevel,Darken($FF0000 * (Ball.Evility) + $FFFF * (1-Ball.Evility),1-F));
          end else begin
            if D < 512 then
              for X := 0 to 7 do
                Buf.CubicBezierLine(Round(FirstBall.X/2),Round(FirstBall.Y/2),Round(Ball.X/2),Round(Ball.Y/2),
                                    Round(FirstBall.X/2+TX*0.1+Random*80),Round(FirstBall.Y/2+TX*0.1+Random*80),
                                    Round(FirstBall.X/2+TX*0.4+Random*80),Round(FirstBall.Y/2+TX*0.4+Random*80),
                                    32 div GraphicLevel,Darken($FF0000 * (Ball.Evility) + $FFFF * (1-Ball.Evility),1-F));
          end;

        if not Paused then begin
          if (Ball.Evility = 1) and (D < 512) then begin
            MasterMass := MasterMass - SkillMod*0.8*(1-F);
          end;
          if (Ball.Evility = 0) and (D < 512) then begin
            MasterMass := MasterMass + Abs(0.5*(1-F));
            Score := Score + Abs(Round(SkillMod*5*(1-F))*10);
            XorOfScore := XORFunc(XORFunc(XorOfScore) + Abs(Round(SkillMod*5*(1-F))*10));

            Ball.M := Ball.M - Abs(0.1*(1-F));
            if Ball.M < 0 then begin
              DSP_SomethingDied := 1;
              Buf.Negative;
              KillBall(Ball);
            end;
          end;
        end;

        Ball := KBall;
      end;
    end;

    if (not Died) and (MasterMass < 0) then begin
      Death;
    end;
    if MasterMass > 200 then MasterMass := 200;
    if MasterMass < 0 then MasterMass := 0;
  end;

  CheatTest;

  //DSP ========================================================================
  NewDistortion := Min(Max(NewDistortion,0),1);
  DSP_Distortion := (DSP_Distortion + NewDistortion) / 2;
  if Died then begin
    DSP_DeathEQ.hg := DSP_DeathEQ.hg + 0.1*(0 - DSP_DeathEQ.hg);
    DSP_DeathEQ.lg := DSP_DeathEQ.mg*4;
  end else begin
    if (BlackHole <> nil) or Paused then begin
      if BlackHole <> nil then
        DSP_Distortion := DSP_Distortion + 0.1*(2 - DSP_Distortion);
      DSP_DeathEQ.hg := DSP_DeathEQ.hg + 0.1*(0.3 - DSP_DeathEQ.hg)
    end else
      DSP_DeathEQ.hg := DSP_DeathEQ.hg + 0.1*(1 - DSP_DeathEQ.hg);
    DSP_DeathEQ.lg := DSP_DeathEQ.hg;
  end;
  //DSP ========================================================================

  if (Died) and (Time.Time-DeathTime < 3) then begin
    for X := 511 downto 0 do begin
      {TX := FirstBall.X/2;
      TY := FirstBall.Y/2;
      for I := 0 to 3 do begin
        NX := TX + 32*(Random-0.5);
        NY := TY + 32*(Random-0.5);

        Buf.Line(Round(TX),Round(TY),Round(NX),Round(NY),Darken($FF,1-(Time.Time-DeathTime)));
        TX := NX;
        TY := NY;
      end;}
      I := Round(X*(Time.Time-DeathTime)*1);
      if I < Buf.XMid*2 then
        Buf.Circle(Round(FirstBall.X/2),Round(FirstBall.Y/2),I,Darken($FF,Max(Sin(X/10) - (Time.Time-DeathTime)/3,0)));
    end;
  end;  

  //Render mega gird
  for X := 0 to W do begin
    for Y := 0 to H do begin
      if Y - 1 >= 0 then
        Buf.Line(Round(Gird[X,Y-1].X),Round(Gird[X,Y-1].Y),Round(Gird[X,Y].X),Round(Gird[X,Y].Y),$FF);
      if X - 1 >= 0 then
        Buf.Line(Round(Gird[X-1,Y].X),Round(Gird[X-1,Y].Y),Round(Gird[X,Y].X),Round(Gird[X,Y].Y),$FF);
    end;
  end;

  //Render dumb particles
  (*for I := 0 to High(DumbParticles) do begin
    {Buf.FillCircle(Round(DumbParticle.X/2),
                   Round(DumbParticle.Y/2),
                   2,$FF);}
    for X := 0 to 15 do
      Buf.Line(Round(DumbParticle.X/2),
               Round(DumbParticle.Y/2),
               Round(DumbParticle.X/2+32*2*(Random-0.5)),
               Round(DumbParticle.Y/2+32*2*(Random-0.5)),$FF);
  end;*)

  //GUI BEFORE GLOW ============================================================
  DrawUI;
  //GUI BEFORE GLOW ============================================================

  if GraphicLevel <= 2 then
    Buf.Blur2x_Speed;

  {//Render mega gird
  for X := 1 to W do begin
    for Y := 1 to H do begin
      Buf.Line(Round(Gird[X,Y-1].X),Round(Gird[X,Y-1].Y),Round(Gird[X,Y].X),Round(Gird[X,Y].Y),$FF);
      Buf.Line(Round(Gird[X-1,Y].X),Round(Gird[X-1,Y].Y),Round(Gird[X,Y].X),Round(Gird[X,Y].Y),$FF);
    end;
  end;}

  //Render balls
  Ball := FirstBall.NextBall;
  while Ball <> nil do begin
    KBall := Ball.NextBall;
    if not Ball.IsBlackHole then begin
      if Ball.Evility = 0 then begin
        if Ball.M > 0 then begin
          if GraphicLevel > 2 then
            Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(Ball.R/2),
                           Darken($FFFFFF,Ball.M/25))
          else
            for I := Round(Ball.R/2) downto 1 do
              Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(I),
                             Darken($FFFFFF,0.1+0.1*Sin(Time.Time*16+I/2)+Ball.M/25));
        end;
      //Buf.Circle(Round(Ball.X/2),Round(Ball.Y/2),Round(Ball.R/2),$FFFFFF);
      end else begin
        if GraphicLevel > 2 then
          Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(Ball.R/2),
                         Darken($FF0000,Ball.M/25))
        else
          for I := Round(Ball.R/2) downto 1 do
            Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(I),
                           Darken($FF0000,0.2*Sin(Time.Time*16+I/2)+Ball.M/25{-I*I/500}));
      end;
    end;

    if (BlackHole <> nil) and (Ball <> BlackHole) then begin
      //1. Calculate distance
      TX := BlackHole.X-Ball.X;
      TY := BlackHole.Y-Ball.Y;
      D := Sqrt(TX*TX+TY*TY)+1e-6;

      if D < 64 then
        KillBall(Ball);
    end;

    Ball := KBall;
  end;

  CheatTest;

  Ball := FirstBall;
  if Ball.R > 1 then begin
    if GraphicLevel > 2 then
      Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(Ball.R/2),
      Darken($FFFFFF,Ball.M/400))
    else
      for I := Round(Ball.R/2) downto 1 do
        Buf.FillCircle(Round(Ball.X/2),Round(Ball.Y/2),Round(I),
                       Darken($FFFFFF,0.1+0.1*Sin(Time.Time*8*(1+MasterMass/200)+I/2)+Ball.M/400));
  end;

  if GameStarted then begin
    if (MasterMass < 25) then begin
      Buf.Copy(Buf2,0,0);
      Buf2.Grayscale;
      Buf2.CopyAlpha(Buf,0,0,Round(200-200*(MasterMass/25)));
    end;
  end else begin
    if Sin(Time.Time*4) > 0.9 then begin
      {Buf.Copy(Buf2,0,0);
//      Buf2.Grayscale;
      if Random(2) = 0 then
        Buf2.HMirror;
      if Random(2) = 0 then
        Buf2.VMirror;
      Buf2.CopyAlpha(Buf,0,0,Round(255*Sin(Time.Time*64)));}
    end;
  end;

  //GUI AFTER GLOW =============================================================
  DrawUI;
  //GUI AFTER GLOW =============================================================

  if (BlackHole <> nil) and (GraphicLevel <= 1) and not PrevBlurred then
    Buf.Copy(LastBuf,0,0);
  PrevBlurred := False;
  if (BlackHole <> nil) and (GraphicLevel <= 1) then begin
    Buf.CopyAlpha(LastBuf,0,0,60);
    LastBuf.Copy(Buf,0,0);
    PrevBlurred := True;
  end;

  if (UniverseMass > Max(200/(SkillMod{*SkillMod}),50)) and (Random(10) = 0) and (BlackHole = nil) and
     (Time.Time - LastBlackHoleTime > 10) then begin
    AddBlackHole;
  end;

  if (not Died) and (GameStarted) and (Time.Time > NextPowerUpTime) then begin
    //PowerupMsg := '012345678901234';
    PowerupMsgTime := Time.Time;
    I := Random(100);
    if (I >= 0) and (I < 30) then begin
                   //---------------//
      PowerupMsg := '   Mass Bonus  ';
      MasterMass := MasterMass + 25;
    {end else if (I >= 30) and (I < 40) then begin
      PowerupMsg := 'Black hole mode';
      BlackHoleMode := 300;}
    end else begin
      PowerupMsg := '  Score bonus  ';
      Score := Score + UniverseMass*100;
      XorOfScore := XORFunc(XORFunc(XorOfScore) + UniverseMass*100);
    end;
    //Add powerup
    NextPowerUpTime := Time.Time + 30 + 30*Random;
  end;

  CheatTest;

  if (not Paused) and (not Died) and (GameStarted) and (Time.Time - PowerupMsgTime < 3) then begin
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(64*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do
        if (X <> Y) and (X <> 0) then
          Buf2.WriteStr(25+X*4,50+Y*4,PowerupMsg,1);

    T := Darken($FFFFFF,Max(0,4*Sin(((Time.Time - PowerupMsgTime) / 3)*Pi)));
    Buf2.WriteStr(25,50,PowerupMsg,T);
    Buf2.CopyRotateSprite(Buf,Buf.XMid,Buf.YMid,((VULeftPeak+VURightPeak)/2)*0.2+1,((VULeftPeak+VURightPeak)/2)*(Random-0.5),0);
  end;

  if Paused then begin
    Buf.Grayscale;

    if GraphicLevel <= 2 then begin
      Buf.Copy(Buf2,0,0);
      if Random(2) = 0 then
        Buf2.HMirror;
      if Random(2) = 0 then
        Buf2.VMirror;

      I := Random(Buf.YSize);
      Buf2.FillRect(0,I,Buf.XSize,I + Random(128),0);
      Buf2.CopyAlpha(Buf,0,0,40);
    end;

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(128*FontSize));
    Buf.WriteStr(130,200,'GAME PAUSED',$00FF00);    
    for Y := 0 to Buf.YMax do
      if Y mod 2 = 0 then
        Buf.HLine(0,Buf.XMax,Y,0);
  end;

  if (not GameStarted) and (MenuID <> 3) then begin
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(128*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do
        if (X <> Y) and (X <> 0) then
          if VistaIssue then
            Buf2.WriteStr(80+X*4,50+Y*4,'GRAVITYWARZ',1)
          else
            Buf2.WriteStr(130+X*4,50+Y*4,'GRAVITYWARZ',1);

    T := $FFFFFF;
    if VistaIssue then
      Buf2.WriteStr(80,50,'GRAVITYWARZ',T)
    else
      Buf2.WriteStr(130,50,'GRAVITYWARZ',T);    
    Buf2.CopyRotateSprite(Buf,Buf.XMid,Buf.YMid,((VULeftPeak+VURightPeak)/2)*0.2+1,((VULeftPeak+VURightPeak)/2)*(Random-0.5),0);
  end;

  if (not GameStarted) and (MenuID = 0) then begin //Main Menu
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        if VistaIssue then
          Buf2.WriteStr(100+X*3,150+Y*3,'GRAVITY WARZ BY BLACK PHOENIX',1)
        else
          Buf2.WriteStr(120+X*3,150+Y*3,'GRAVITY WARZ BY BLACK PHOENIX',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4+Pi)*0.1+0.9);
    if VistaIssue then
      Buf2.WriteStr(100,150,'GRAVITY WARZ BY BLACK PHOENIX',T)
    else
      Buf2.WriteStr(120,150,'GRAVITY WARZ BY BLACK PHOENIX',T);
    Buf2.CopySprite(Buf,0,0,0);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(250+X*2,240+Y*2,'Start new game',0);
        Buf.WriteStr(310+X*2,300+Y*2,'Options',0);
        Buf.WriteStr(300+X*2,360+Y*2,'Hiscores',0);
        Buf.WriteStr(334+X*2,420+Y*2,'Exit',0);
      end;
    T := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(250,240,'Start new game',T);
    Buf.WriteStr(310,300,'Options',T);
    Buf.WriteStr(300,360,'Hiscores',T);
    Buf.WriteStr(334,420,'Exit',T);

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 240) and (Input.m_y < 280) then begin
      DSP_MenuClick := 1;
      MenuID := 1;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 300) and (Input.m_y < 340) then begin
      DSP_MenuClick := 1;
      MenuID := 2;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 360) and (Input.m_y < 400) then begin
      DSP_MenuClick := 1;
      MenuID := 3;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      //DSP_MenuClick := 1;
      Close;
    end;
    if PushedLeft then PushedLeft := False;    
  end;

  CheatTest;

  if (not GameStarted) and (MenuID = 1) then begin //New Game
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf2.WriteStr(260+X*3,150+Y*3,'START NEW GAME',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4)*0.1+0.9);
    Buf2.WriteStr(260,150,'START NEW GAME',T);
    Buf2.CopySprite(Buf,0,0,0);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(350+X*2,240+Y*2,'Easy',0);
        Buf.WriteStr(335+X*2,300+Y*2,'Normal',0);
        Buf.WriteStr(350+X*2,360+Y*2,'Hard',0);
        Buf.WriteStr(300+X*2,420+Y*2,'Very Hard!',0);
      end;

    T := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(350,240,'Easy',T);
    Buf.WriteStr(335,300,'Normal',T);
    Buf.WriteStr(350,360,'Hard',T);
    Buf.WriteStr(300,420,'Very Hard!',T);

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 240) and (Input.m_y < 280) then begin
      DSP_MenuClick := 1;
      SkillMod := 0.5;
      NewGame;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 300) and (Input.m_y < 340) then begin
      DSP_MenuClick := 1;
      SkillMod := 1;
      NewGame;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 360) and (Input.m_y < 400) then begin
      DSP_MenuClick := 1;
      SkillMod := 3;
      NewGame;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      SkillMod := 5;
      NewGame;
    end;
    if PushedLeft then PushedLeft := False; 
  end;

  if (not GameStarted) and (MenuID = 2) then begin //Options
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf2.WriteStr(320+X*3,150+Y*3,'OPTIONS',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4)*0.1+0.9);
    Buf2.WriteStr(320,150,'OPTIONS',T);
    Buf2.CopySprite(Buf,0,0,0);

    TMP[0] := 'Game volume: ' + IntToStr(Round(Volume*100)) + '%';
    if GraphicLevel = 1 then TMP[1] := 'GFX quality: high';
    if GraphicLevel = 2 then TMP[1] := 'GFX quality: medium';
    if GraphicLevel = 3 then TMP[1] := 'GFX quality: low';
    {if CanUseInternet then
      TMP[2] := 'Internet connectivity: on'
    else}
    if Settings.GetBool('settings','fullscreen',False) then
      TMP[2] := 'Fullscreen: yes'
    else
      TMP[2] := 'Fullscreen: no';
    TMP[3] := 'Extra settings';
    TMP[4] := 'Return to menu';

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(220+X*2,240+Y*2,TMP[0],0);
        Buf.WriteStr(220+X*2,300+Y*2,TMP[1],0);
        Buf.WriteStr(240+X*2,360+Y*2,TMP[2],0);
        Buf.WriteStr(240+X*2,420+Y*2,TMP[3],0);
        Buf.WriteStr(240+X*2,480+Y*2,TMP[4],0);
      end;

    T := Darken($00FF3F,Sin(Time.Time*4)*0.1+0.9);
    K := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(220,240,TMP[0],T);
    Buf.WriteStr(220,300,TMP[1],T);
    Buf.WriteStr(240,360,TMP[2],T);
    Buf.WriteStr(240,420,TMP[3],T);
    Buf.WriteStr(240,480,TMP[4],K);

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 240) and (Input.m_y < 280) then begin
      DSP_MenuClick := 1;
      Volume := Volume + 0.1;
      if Volume > 1.01 then Volume := 0;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 300) and (Input.m_y < 340) then begin
      DSP_MenuClick := 1;
      GraphicLevel := GraphicLevel + 1;
      if GraphicLevel > 3 then GraphicLevel := 1;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 360) and (Input.m_y < 400) then begin
      DSP_MenuClick := 1;
      //CanUseInternet := not CanUseInternet;
      Settings.SetBool('settings','fullscreen',not Settings.GetBool('settings','fullscreen',False))
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      MenuID := 4;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 480) and (Input.m_y < 520) then begin
      DSP_MenuClick := 1;
      MenuID := 0;
    end;
    if PushedLeft then PushedLeft := False; 
  end;

  CheatTest;
{
  if (not GameStarted) and (MenuID = 1) then begin //New Game
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf2.WriteStr(230+X*3,150+Y*3,'START NEW GAME',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4)*0.1+0.9);
    Buf2.WriteStr(230,150,'START NEW GAME',T);
    Buf2.CopySprite(Buf,0,0,0);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(260+X*2,240+Y*2,'Easy',0);
        Buf.WriteStr(260+X*2,300+Y*2,'Normal',0);
        Buf.WriteStr(260+X*2,360+Y*2,'Hard',0);
        Buf.WriteStr(260+X*2,420+Y*2,'Very Hard!',0);
      end;

    T := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(260,240,'Easy',T);
    Buf.WriteStr(260,300,'Normal',T);
    Buf.WriteStr(260,360,'Hard',T);
    Buf.WriteStr(260,420,'Very Hard!',T);

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 240) and (Input.m_y < 280) then begin
      DSP_MenuClick := 1;
      SkillMod := 0.5;
      NewGame;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 300) and (Input.m_y < 340) then begin
      DSP_MenuClick := 1;
      SkillMod := 1;
      NewGame;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 360) and (Input.m_y < 400) then begin
      DSP_MenuClick := 1;
      SkillMod := 3;
      NewGame;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      SkillMod := 5;
      NewGame;
    end;
    if PushedLeft then PushedLeft := False; 
  end; }

  if (not GameStarted) and (MenuID = 4) then begin //Extra Options
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf2.WriteStr(250+X*3,150+Y*3,'EXTRA OPTIONS',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4)*0.1+0.9);
    Buf2.WriteStr(250,150,'EXTRA OPTIONS',T);
    Buf2.CopySprite(Buf,0,0,0);


    TMP[0] := 'Master bass: ' + IntToStr(Round(DSP_MasterEQ.lg*100)) + '%';
    TMP[1] := 'Change background music';
    TMP[2] := 'Sumbit hiscores...';
    TMP[3] := 'Back';

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(220+X*2,240+Y*2,TMP[0],0);
        Buf.WriteStr(170+X*2,300+Y*2,TMP[1],0);
        Buf.WriteStr(220+X*2,360+Y*2,TMP[2],0);
        Buf.WriteStr(340+X*2,420+Y*2,TMP[3],0);
      end;

    T := Darken($00FF3F,Sin(Time.Time*4)*0.1+0.9);
    K := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(220,240,TMP[0],T);
    Buf.WriteStr(170,300,TMP[1],T);
    Buf.WriteStr(220,360,TMP[2],T);
    Buf.WriteStr(340,420,TMP[3],K);

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 240) and (Input.m_y < 280) then begin
      DSP_MenuClick := 1;
      DSP_MasterEQ.lg := DSP_MasterEQ.lg + 0.2;
      if DSP_MasterEQ.lg > 4.010 then DSP_MasterEQ.lg := 0;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 300) and (Input.m_y < 340) then begin
      DSP_MenuClick := 1;
      if LoadedSong = 'PLASTICS.MOD' then
        LoadBGSong('FIRSTSTR.MOD')
      else if LoadedSong = 'TECHNOLO.MOD' then
        LoadBGSong('PLASTICS.MOD')
      else if LoadedSong = 'THECONF.XM' then
        LoadBGSong('TECHNOLO.MOD')
      else LoadBGSong('THECONF.XM');
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 360) and (Input.m_y < 400) then begin
      DSP_MenuClick := 1;
      //SUMBIT
      //Begin submit
      HiScore_Submit;
    end;
    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      MenuID := 2;
    end;
    if PushedLeft then PushedLeft := False; 
  end;

  if (not GameStarted) and (MenuID = 3) then begin //Hiscores
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf2.WriteStr(320+X*3,20+Y*3,'HISCORES',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4)*0.1+0.9);
    Buf2.WriteStr(320,20,'HISCORES',T);
    Buf2.CopySprite(Buf,0,0,0);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(100+X*2,420+Y*2,'Return to menu',0);
        Buf.WriteStr(420+X*2,420+Y*2,'Submit hiscores',0);
      end;

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(40*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        for I := 1 to 10 do begin
          Buf.WriteStr(80+X*3,60+Y*3+I*30,HiScores[I].Name,0);
          Buf.WriteStr(490+X*3,60+Y*3+I*30,Format('%8d',[HiScores[I].Score]),0);
        end;
      end;

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    T := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(100,420,'Return to menu',T);
    T := Darken($00FF3F,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(420,420,'Submit hiscores',T);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(40*FontSize));
    for I := 1 to 10 do begin
      if CheckCode(HiScores[I].Name,HiScores[I].Score) = HiScores[I].CheckCode then begin
        T := Darken($00FF00,Sin(Time.Time*4+I/2)*0.1+0.9)
      end else begin
        if LoadedSong <> 'SCOTTY.MOD' then LoadBGSong('SCOTTY.MOD');
        T := Darken($FF0000,Sin(Time.Time*4+I/2)*0.1+0.9);
      end;

      Buf.WriteStr(80,60+I*30,HiScores[I].Name,T);
      Buf.WriteStr(490,60+I*30,Format('%8d',[HiScores[I].Score]),T);

      if DisplayCoolStuff then begin
        Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(16*FontSize));
        Buf.WriteStr(700,60+I*30+10,IntToHex(HiScores[I].CheckCode,8),T);
        Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(40*FontSize));
      end;
    end;

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 380) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      MenuID := 0;
    end;
    if (PushedLeft) and (Input.m_x > 380) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      HiScore_Submit;
    end;
    if PushedLeft then PushedLeft := False; 
  end;

  if (GameStarted) and (MenuID = 5) then begin //Beat Hiscores
    Buf2.Fill(0);
    Buf2.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));

    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf2.WriteStr(280+X*3,20+Y*3,'NEW HISCORE',1);
      end;

    T := Darken($3FFF00,Sin(Time.Time*4)*0.1+0.9);
    Buf2.WriteStr(280,20,'NEW HISCORE',T);
    Buf2.CopySprite(Buf,0,0,0);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(320+X*2,420+Y*2,'Accept',0);
      end;

    K := -1;
    for I := 1 to 10 do
      if (K = -1) and (XORFunc(XorOfScore) = HiScores[I].Score) then begin
        HiScores[I].Name := HiScoreNewName;
        //HiScores[I].Score := Score;
        HiScores[I].CheckCode := CheckCode(HiScoreNewName,HiScores[I].Score);
        K := I;
      end;

    if K = -1 then begin
      Buf.Flip(False);
      _leave;
      Exit;
    end;
    //T := 10;


    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(40*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        for I := 1 to 10 do begin
          if I = K then
            Buf.WriteStr(120+X*3,60+Y*3+I*30,HiScores[I].Name + #$7F,0)
          else
            Buf.WriteStr(120+X*3,60+Y*3+I*30,HiScores[I].Name,0);
          Buf.WriteStr(490+X*3,60+Y*3+I*30,Format('%8d',[HiScores[I].Score]),0);
        end;
      end;

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    T := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(320,420,'Accept',T);

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(40*FontSize));
    for I := 1 to 10 do begin
      if CheckCode(HiScores[I].Name,HiScores[I].Score) = HiScores[I].CheckCode then
        T := Darken($00FF00,Sin(Time.Time*4+I/2)*0.1+0.9)
      else
        T := Darken($FF0000,Sin(Time.Time*4+I/2)*0.1+0.9);

      if I = K then
        Buf.WriteStr(120,60+I*30,HiScores[I].Name + #$7F,T)
      else
        Buf.WriteStr(120,60+I*30,HiScores[I].Name,T);
      Buf.WriteStr(490,60+I*30,Format('%8d',[HiScores[I].Score]),T);
    end;

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      for I := 1 to 10 do
        if HiScores[I].Name = '' then begin
          HiScores[I].Name := 'ANONYMOUS';
          HiScores[I].CheckCode := CheckCode(HiScores[I].Name,HiScores[I].Score);
        end;

      HiScoreStore.SetStr('game','name','Gravity Warz');
      for X := 1 to 10 do begin
        HiScoreStore.SetStr('hiscore',IntToStr(X) + '_name',HiScores[X].Name);
        HiScoreStore.SetInt('hiscore',IntToStr(X) + '_score',HiScores[X].Score);
        HiScoreStore.SetStr('hiscore',IntToStr(X) + '_CheckCode',IntToHex(HiScores[X].CheckCode,8));
      end;
      HiScoreStore.Save;        

      HiScore_EnteringName := False;
      SetupTitle;
      MenuID := 0;
      GameStarted := False;
      Died := False;
      LoadBGSong('TECHNOLO.MOD');
      AcceptButton_TempFix := true;
    end;
    if PushedLeft then PushedLeft := False; 
  end;

  if (GameStarted) and (MenuID = 6) then begin //Not beat hiscore
    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    for X := -1 to 1 do
      for Y := -1 to 1 do begin
        Buf.WriteStr(280+X*2,420+Y*2,'Back to menu',0);
      end;

    Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(48*FontSize));
    T := Darken($003FFF,Sin(Time.Time*4)*0.1+0.9);
    Buf.WriteStr(280,420,'Back to menu',T);

    Buf.Rect(Input.m_x-4,Input.m_y-4,Input.m_x+4,Input.m_y+4,0);
    Buf.Rect(Input.m_x-3,Input.m_y-3,Input.m_x+3,Input.m_y+3,$FFFFFF);
    Buf.Rect(Input.m_x-2,Input.m_y-2,Input.m_x+2,Input.m_y+2,0);

    if (PushedLeft) and (Input.m_x > 100) and (Input.m_x < 700) and
                    (Input.m_y > 420) and (Input.m_y < 460) then begin
      DSP_MenuClick := 1;
      SetupTitle;
      MenuID := 0;
      GameStarted := False;
      Died := False;
      LoadBGSong('THECONF.XM');
    end;
    if PushedLeft then PushedLeft := False; 
  end;

  if DisplayCoolStuff then begin
    X := 700-70;
    Y := 500-100;

    Buf.FillRect(X+16,Y+16,X+32+128,Y+32+64,0);

    Buf.FillRect(X+24,Y+24,X+24+128,Y+24+16,$001F00);
    Buf.FillRect(X+24,Y+48,X+24+128,Y+48+40,$001F00);

    Buf.FillRect(X+24,Y+24,X+24+Round(128*((VULeftPeak+VURightPeak)/2)),Y+24+16,$00FF00);
    for I := 0 to 126 do
      Buf.Line(X+24+I,Y+48+20+Round(Oscililoscope[I]*20),
               X+24+I+1,Y+48+20+Round(Oscililoscope[I+1]*20),
               $00FF00);
  end;

  CheatTest;


  if TakeScreenShot then begin
    I := 0;
    while FileExists('picture' + IntToStr(I) + '.jpg') do Inc(I);
    Buf.SaveQuality(95);
    Buf.SaveImage('picture' + IntToStr(I) + '.jpg');
    TakeScreenShot := False;
  end;
  
  Buf.Flip(False);
  except end;
  _leave;
//  ReleaseSemaphore(hSem, 1, nil);
end;

procedure TfrmMain.FormKeyPress(Sender: TObject; var Key: Char);
var I,X : Integer;
begin
  _call('FormKeyPress','%s',[Key]);

  if PanicMessage <> '' then begin
    PanicMessage := '';
    if Key <> #32 then Close;
    _leave;
    Exit;
  end;

  if HiScore_EnteringName then begin
    if (Key <> #13) and (Key <> #27) then begin
      if (Key >= #40) and (Key <= #255) then
        HiScoreNewName := Copy(HiScoreNewName + UpCase(Key),1,12);
      if (Key = #8) then
        Delete(HiScoreNewName,Length(HiScoreNewName),1);
    end else begin
      for I := 1 to 10 do
        if HiScores[I].Name = '' then begin
          HiScores[I].Name := 'ANONYMOUS';
          HiScores[I].CheckCode := CheckCode(HiScores[I].Name,HiScores[I].Score);
        end;

      HiScoreStore.SetStr('game','name','Gravity Warz');
      for X := 1 to 10 do begin
        HiScoreStore.SetStr('hiscore',IntToStr(X) + '_name',HiScores[X].Name);
        HiScoreStore.SetInt('hiscore',IntToStr(X) + '_score',HiScores[X].Score);
        HiScoreStore.SetStr('hiscore',IntToStr(X) + '_CheckCode',IntToHex(HiScores[X].CheckCode,8));
      end;
      HiScoreStore.Save;

      DSP_MenuClick := 1;
      HiScore_EnteringName := False;

      SetupTitle;
      MenuID := 0;
      GameStarted := False;
      Died := False;
      LoadBGSong('TECHNOLO.MOD');
    end;
    _leave;
    Exit;
  end;

  {if Key = #13 then AddBlackHole;}
  if (not Died) and (GameStarted) and (Key = ' ') then begin
    Paused := not Paused;
    Time.running := not Paused;
    BallTimer.Enabled := not Paused;
  end;

  if Key = 's' then TakeScreenShot := True;
//  if Key = 'a' then MenuID := 5;//NewGame;

  if Key = #27 then begin
    if not GameStarted then begin
      if MenuID = 0 then Close else begin
        if MenuID = 4 then MenuID := 2 else if MenuID < 4 then MenuID := 0;
      end;
      if Died then
        Close;
    end else begin
      if Paused then begin
        Death;
      end else begin
        if not Died then begin
          Paused := not Paused;
          Time.running := not Paused;
          BallTimer.Enabled := not Paused;
        end else Close;
      end;
    end;
    DSP_MenuClick := 1;
  end;
  _leave;
end;

procedure TfrmMain.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  _call('FormMouseDown','%d %d',[X,Y]);

{  if Button = mbRight then
    AddAlmostRandomBall(X*2,Y*2,3)
  else
    AddAlmostRandomBall(X*2,Y*2,0);}
  if Button = mbLeft then
    PushedLeft := True;
  if Button = mbRight then
    PushedRight := True;

  //AddBlackHole;
  _leave;
end;

procedure TfrmMain.FormMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
begin
  _call('FormMouseMove','%d %d',[X,Y]);

  if (not Paused) and (not Died) and GameStarted then begin
    FirstBall.X := X*2;
    FirstBall.Y := Y*2;
  end;
  MX := X;
  MY := Y;
  _leave;
end;

procedure TfrmMain.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  _call('FormMouseUp','%d %d',[X,Y]);
  if Button = mbLeft then
    PushedLeft := False;
  if Button = mbRight then
    PushedRight := False;
  _leave;
end;


procedure TfrmMain.BallTimerTimer(Sender: TObject);
begin
  _call('BallTimerTimer','',[]);
  if not(Died) and (BallCount < 50) then begin
    AddNormalBall;
    Ball_AddEffect := 10;
  end;

  BallTimer.Interval := Max(Round(BallTimer.Interval*0.97),1000);
  _leave;
end;

procedure TfrmMain.Death;
var I,J : Integer;
begin
  _call('Death','',[]);
  Paused := False;  
  DSP_SomethingDied := 1;
  Buf.Negative;

  DeathTime := Time.Time;
  MasterMass := 0;
  Died := True;

  //Check if beat hiscore
  for I := 1 to 10 do
    if XORFunc(XorOfScore) >= HiScores[I].Score then begin
      //Scroll everybody down
      for J := 10 downto I+1 do
        HiScores[J] := HiScores[J-1];

      HiScores[I].Name := '';
      HiScores[I].Score := XORFunc(XorOfScore);
      HiScores[I].CheckCode := CheckCode('',XORFunc(XorOfScore));

      HiScore_EnteringName := True;
      HiScoreNewName := '';
      MenuID := 5;
      _leave;
      Exit;
    end;

  MenuID := 6;
  _leave;
end;

procedure TfrmMain.NewGame;
var X,Y: Integer;
begin
  _call('NewGame','',[]);
  Time.Start;
  BallTimer.Enabled := True;
  NextPowerUpTime := 5;
  PowerupMsgTime := 0;
  PowerupMsg := '';
  
  MasterMass := 25;
  CalcMasterMass := MasterMass;

  KillAllBalls;
  FirstBall := AddBall;
  FirstBall.X := MX*2;
  FirstBall.Y := MY*2;
  FirstBall.DX := 0;//10*(Random-0.5);
  FirstBall.DY := 0;//10*(Random-0.5);
  FirstBall.M := CalcMasterMass;
  FirstBall.R := 10;

  AddNormalBall;
  AddNormalBall;

  BallTimer.Interval := 5000;

  GameStarted := True;
  Died := False;
  Score := 0;
  XorOfScore := XORFunc(0);

  //Make megagird
  for X := 0 to W do begin
    for Y := 0 to H do begin
      Gird[X,Y].X := ClientWidth*(X / W);
      Gird[X,Y].Y := ClientHeight*(Y / H);
    end;
  end;

  LoadBGSong('FIRSTSTR.MOD');
  _leave;
end;

procedure TfrmMain.FPSTimerTimer(Sender: TObject);
begin
  Caption := 'GravityWARZ (build ' + Copy(GetFileVersionString2(Application.ExeName),7,$FFFF) +
             ') - FPS: ' + FloatToStr(Frames*2) + ' (Orbs: ' + IntToStr(BallCount) + ')';
  Frames := 0;
end;

procedure TfrmMain.AddBlackHole;
var Ball : PBall;
begin
  _call('AddBlackHole','',[]);
  Ball := AddBall;
  BlackHole := Ball;

  Ball.X := Random(ClientWidth*2-64)+32;
  Ball.Y := Random(ClientHeight*2-64)+32;
  Ball.DX := 0;
  Ball.DY := 0;
  Ball.M := 10;
  Ball.R := 0;
  Ball.TTD := 200 + 50 / SkillMod;
  Ball.IsBlackHole := True;

  Ball.Evility := 2;
  _leave;
end;

procedure TfrmMain.AddNormalBall;
var Ball : PBall;
begin
  _call('AddNormalBall','',[]);
  Ball := AddBall;

  Ball.X := Random(ClientWidth*2-64)+32;
  Ball.Y := Random(ClientHeight*2-64)+32;
  Ball.DX := 10*(Random-0.5);
  Ball.DY := 10*(Random-0.5);
  Ball.M := Random*14+4;
  Ball.R := Ball.M*2;
  Ball.TTD := 1e10;
  Ball.IsBlackHole := False;

  Ball.Evility := BallID mod 2;
  _leave;
end;

procedure TfrmMain.KillBall(var Ball: PBall);
begin
  _call('KillBall','%d',[Integer(Ball)]);

  if Ball = nil then begin
    _leave;
    Exit;
  end;

  if Ball = FirstBall then begin
    FirstBall := FirstBall.NextBall;
    if FirstBall <> nil then
      FirstBall.PrevBall := nil;
  end;

  if Ball = LastBall then begin
    LastBall := LastBall.PrevBall;
    if LastBall <> nil then
      LastBall.NextBall := nil;
  end;

  if (Ball <> nil) and (PBall(Ball.NextBall) <> nil) then
    PBall(Ball.NextBall).PrevBall := Ball.PrevBall;

  if (Ball <> nil) and (PBall(Ball.PrevBall) <> nil) then
    PBall(Ball.PrevBall).NextBall := Ball.NextBall;

  Dispose(Ball);
  Dec(BallCount);
  //Ball := nil;
  _leave;
end;

procedure TfrmMain.KillAllBalls;
var NBall,Ball : PBall;
begin
  _call('KillAllBalls','',[]);

  Ball := FirstBall;
  while Ball <> nil do begin
    NBall := Ball.NextBall;
    Dispose(Ball);
    Ball := NBall;
  end;

  FirstBall := nil;
  LastBall := nil;
  BlackHole := nil;
  BallCount := 0;
  BallID := 0;
  _leave;
end;

function TfrmMain.AddBall: PBall;
var Ball : PBall;
begin
  _call('AddBall','',[]);

  New(Ball);
  //GetMem(Ball,SizeOf(TBall));
  Ball.PrevBall := LastBall;
  Ball.NextBall := nil;
  Inc(BallCount);
  Inc(BallID);

  if LastBall <> nil then begin
    LastBall.NextBall := Ball;
    LastBall := Ball;
  end else begin
    LastBall := Ball;
    FirstBall := Ball;
  end;

  Result := Ball;
  _leave;
end;

function TfrmMain.FMod(X, Y: Single): Single;
begin
  _call('FMod','%f %f',[x,y]);
  Result := X - Floor(X / Y)*Y;
  _leave;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  _call('FormDestroy','',[]);
  HPK.Free;

  FSOUND_DSP_SetActive(DSP, false);
  FMUSIC_StopAllSongs();
  FSOUND_Close;
  FMOD_Unload;

  Buf.Free;
  Buf2.Free;
  LastBuf.Free;
  Input.Free;
  Time.Free;
  if Assigned(Scr) then Scr.Free else FullScr.Free;
  _leave;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
var X : Integer;
begin
  _call('FormClose','',[]);
  HiScoreStore.SetStr('game','name','Gravity Warz');
  for X := 1 to 10 do begin
    HiScoreStore.SetStr('hiscore',IntToStr(X) + '_name',HiScores[X].Name);
    HiScoreStore.SetInt('hiscore',IntToStr(X) + '_score',HiScores[X].Score);
    HiScoreStore.SetStr('hiscore',IntToStr(X) + '_CheckCode',IntToHex(HiScores[X].CheckCode,8));
  end;
  HiScoreStore.Save;
  HiScoreStore.Free;

  Settings.SetInt('settings','graphiclevel',GraphicLevel);
  Settings.SetFloat('settings','master_bass',DSP_MasterEQ.lg);
  Settings.SetFloat('settings','volume',Volume);

  Settings.Save;
  Settings.Free;

  for X := 0 to 63 do begin
    Volume := Volume - 0.05;
    if Volume < 0 then Volume := 0;
    Buf2.Fill(0);
    Buf2.CopyAlpha(Buf,0,0,X);
    Buf.Flip(false);
  end;
  _leave;
end;

function TfrmMain.CheckCode(Name: String; Score: Integer): Integer;
begin
  _call('CheckCode','%s %d',[Name,Score]);
asm
  jmp @test;
  db 'Hi there! I see you like browsing the exe...';
  @test:
end;
  Result := Random($FFFFFF);
asm
  jmp @test;
  db 'Um uh, this game was pure accident';
  @test:
end;
  Result := CRC_Compute(Copy(Name,1,Length(Name) div 2));
asm
  jmp @test;
  db 'Yeah, it was';
  @test:
end;
  Result := Result + CRC_Compute(Copy(Name,Length(Name) div 2,Length(Name)))*$10000;
asm
  jmp @test;
  db 'Its like.... I dunno, I had the idea from one guys gravity simulation';
  @test:
end;  
  Result := Result + CRC_Compute(IntToStr(Score));
  _leave;
end;

procedure TfrmMain.SetupTitle;
begin
  _call('SetupTitle','',[]);
  SkillMod := 0.5;
  BallTimer.Interval := 1000;
  LastBlackHoleTime := -1e9;
  GameStarted := false;
  Died := false;

  FirstBall.X := -1e6;
  FirstBall.Y := -1e6;

  Time.running := true;
  BallTimer.Enabled := true;
  Paused := false;
  _leave;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  _call('FormCloseQuery','',[]);
//  CanClose := not AcceptButton_TempFix;
//  if AcceptButton_TempFix then begin
//    PushedLeft := False;
//    PushedRight := False;
//    AcceptButton_TempFix := False;
//  end;
  _leave;
end;

procedure TfrmMain.LoadSongs;
var Stream : TMemoryStream;
    T: Integer;
begin
  _call('LoadSongs','',[]);
  Stream := TMemoryStream.Create;

  //FMUSIC_StopAllSongs;

  Stream.Seek(0,0); Stream.Clear;
  HPK.UnPackToStream('FIRSTSTR.MOD',Stream);
  Songs[1] := FMUSIC_LoadSongEx(Stream.Memory,0,Stream.Size,FSOUND_LOADMEMORY,T,T);

  Stream.Seek(0,0); Stream.Clear;
  HPK.UnPackToStream('PLASTICS.MOD',Stream);
  Songs[2] := FMUSIC_LoadSongEx(Stream.Memory,0,Stream.Size,FSOUND_LOADMEMORY,T,T);

  Stream.Seek(0,0); Stream.Clear;
  HPK.UnPackToStream('SCOTTY.MOD',Stream);
  Songs[3] := FMUSIC_LoadSongEx(Stream.Memory,0,Stream.Size,FSOUND_LOADMEMORY,T,T);

  Stream.Seek(0,0); Stream.Clear;
  HPK.UnPackToStream('TECHNOLO.MOD',Stream);
  Songs[4] := FMUSIC_LoadSongEx(Stream.Memory,0,Stream.Size,FSOUND_LOADMEMORY,T,T);

  Stream.Seek(0,0); Stream.Clear;
  HPK.UnPackToStream('THECONF.XM',Stream);
  Songs[5] := FMUSIC_LoadSongEx(Stream.Memory,0,Stream.Size,FSOUND_LOADMEMORY,T,T);

  for T := 1 to 5 do FMUSIC_SetPanSeperation(Songs[T],0.35);

  Stream.Free;
  _leave;
end;

procedure TfrmMain.LoadBGSong(Name: String);
begin
  _call('LoadBGSong','%s',[Name]);
  FMUSIC_StopAllSongs;
  if Name = 'FIRSTSTR.MOD' then FMUSIC_PlaySong(Songs[1]) else
  if Name = 'PLASTICS.MOD' then FMUSIC_PlaySong(Songs[2]) else
  if Name = 'SCOTTY.MOD' then   FMUSIC_PlaySong(Songs[3]) else
  if Name = 'TECHNOLO.MOD' then FMUSIC_PlaySong(Songs[4]) else
  if Name = 'THECONF.XM' then  FMUSIC_PlaySong(Songs[5]);
  LoadedSong := Name;
  _leave;
end;

procedure TfrmMain.EventException(Sender: TObject; E: Exception);
var F : TextFile;
    PanicName : String;
begin
  DateTimeToString(PanicName,'yymmdd_hhnnss',Now);
  AssignFile(F,'panic' + PanicName + '.txt');
  Rewrite(F);
  WriteLn(F,'Exception: ' + E.Message);
  WriteLn(F);
  WriteLn(F,'Time: ' + DateTimeToStr(Now));
  Write(F,_getlog);
  CloseFile(F);

  PanicMessage := 'Application error: ' + E.Message + ' (' +
                  'Error information file was saved as panic' + PanicName + '.txt)';
end;

procedure TfrmMain.HiScore_Submit;
var TMP : array[0..1] of String;
    X : Integer;
begin
  _call('HiScore_Submit','',[]);

  Timer.Enabled := False;
  BallTimer.Enabled := False;

  Buf.FillRect(64,128,Buf2.XSize-64,Buf2.YSize-128,$7F);
  Buf.Rect(64,128,Buf2.XSize-64,Buf2.YSize-128,$FFFFFF);
  Buf.ChangeFont(FontName,FW_NORMAL,FontCharset,Round(32*FontSize));
  Buf.WriteStr(64+16,128+16,'Initiating transfer...',$FFFFFF);
  Buf.Flip(False);
  Application.ProcessMessages;
  Sleep(500);

  try
    UDP.Send('OMGPING');
    TMP[0] := UDP.ReceiveString(10000);
  except TMP[0] := ''; end;
  if (TMP[0] <> '') then begin
    Buf.WriteStr(64+16,128+16+32,'Connected... Sending data...',$FFFFFF);
    Buf.Flip(False);
    Application.ProcessMessages;
    Sleep(1000);

    for X := 1 to 10 do begin
      Buf.WriteStr(64+16+X*16-16,128+16+64,#$7F,$FFFFFF);
      Buf.Flip(False);
      Application.ProcessMessages;
      Sleep(100);

      TMP[1] := 'OMGKAY';
      try
        UDP.Send('OMGHISCORE "' + HiScores[X].Name + '" "' + IntToStr(HiScores[X].Score)
         + '" "' + IntToHex(HiScores[X].CheckCode,8) + '" "build_stephany"');
         TMP[1] := UDP.ReceiveString(10000);
      except TMP[1] := ''; end;
      if TMP[1] = '' then begin
        Buf.WriteStr(64+16,128+16+128,'Transfer error! Please try again later',$FFFFFF);
        Buf.Flip(False);
        Application.ProcessMessages;
        Sleep(1000);
        Exit;
      end;
    end;

    Buf.WriteStr(64+16,128+16+96,'Done....',$FFFFFF);
    Buf.Flip(False);
    Application.ProcessMessages;
    Sleep(1000);
  end else begin
    Buf.WriteStr(64+16,128+16+32,'Transfer error! Please try again later',$FFFFFF);
    Buf.Flip(False);
    Application.ProcessMessages;
    Sleep(1000);
  end; 
  //Buf2.WriteStr(64+16,128+16,'Initiating transfer...',$FFFFFF);

  //while true do Application.ProcessMessages;

  Timer.Enabled := True;
  BallTimer.Enabled := True;
  _leave;
  //End submit
end;

function TfrmMain.XORFunc(I: Cardinal): Cardinal;
begin
  Result := (((I xor $AEFEB452) and $FFFF) shl 16 + ((I xor $AEFEB452) and $FFFF0000) shr 16) xor $AEFEB452;
end;

procedure TfrmMain.CheatTest;
begin
  MasterMass := MasterMass - 1000000;
  if MasterMass >= 0 then begin
    ShowMessage('Memory violation');
    Application.Terminate;
    Exit;
    //XorOfScore := XORFunc(0);
  end;
  MasterMass := MasterMass + 1000000;
end;

end.
