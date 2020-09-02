object frmMain: TfrmMain
  Left = 192
  Top = 115
  Width = 808
  Height = 627
  Caption = 'GravityWARZ'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyPress = FormKeyPress
  OnMouseDown = FormMouseDown
  OnMouseMove = FormMouseMove
  OnMouseUp = FormMouseUp
  PixelsPerInch = 96
  TextHeight = 13
  object Timer: TTimer
    Interval = 25
    OnTimer = TimerTimer
    Left = 8
    Top = 8
  end
  object BallTimer: TTimer
    Interval = 5000
    OnTimer = BallTimerTimer
    Left = 40
    Top = 8
  end
  object FPSTimer: TTimer
    Interval = 500
    OnTimer = FPSTimerTimer
    Left = 72
    Top = 8
  end
  object UDP: TIdUDPClient
    Active = True
    Host = 'gravitywarz.d2k5.com'
    Port = 40000
    Left = 104
    Top = 8
  end
end
