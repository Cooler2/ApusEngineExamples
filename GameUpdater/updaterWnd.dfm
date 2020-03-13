object MainForm: TMainForm
  Left = 0
  Top = 0
  AlphaBlendValue = 50
  BorderStyle = bsDialog
  Caption = 'Updating Astral Heroes'
  ClientHeight = 66
  ClientWidth = 600
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  Scaled = False
  OnActivate = FormActivate
  OnClose = FormClose
  DesignSize = (
    600
    66)
  PixelsPerInch = 96
  TextHeight = 13
  object lab: TLabel
    Left = 8
    Top = 5
    Width = 584
    Height = 22
    Alignment = taCenter
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Color = clBtnFace
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentColor = False
    ParentFont = False
    Transparent = True
    WordWrap = True
  end
  object progress: TProgressBar
    AlignWithMargins = True
    Left = 8
    Top = 34
    Width = 495
    Height = 25
    Hint = '123'
    Anchors = [akLeft, akTop, akRight]
    ParentShowHint = False
    Smooth = True
    ShowHint = False
    TabOrder = 0
  end
  object btn: TButton
    Left = 509
    Top = 34
    Width = 83
    Height = 25
    Anchors = [akLeft, akTop, akRight]
    Cancel = True
    Caption = 'Cancel'
    Default = True
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
    OnClick = btnClick
  end
  object panel: TPanel
    Left = 8
    Top = 72
    Width = 584
    Height = 267
    BevelOuter = bvLowered
    TabOrder = 2
    object browser: TWebBrowser
      Left = 1
      Top = 1
      Width = 582
      Height = 265
      Align = alClient
      TabOrder = 0
      ExplicitWidth = 584
      ExplicitHeight = 267
      ControlData = {
        4C000000273C0000631B00000000000000000000000000000000000000000000
        000000004C000000000000000000000001000000E0D057007335CF11AE690800
        2B2E12620A000000000000004C0000000114020000000000C000000000000046
        8000000000000000000000000000000000000000000000000000000000000000
        00000000000000000100000000000000000000000000000000000000}
    end
  end
  object XPManifest1: TXPManifest
    Left = 16
    Top = 48
  end
  object Timer: TTimer
    Interval = 10
    OnTimer = TimerTimer
    Left = 48
    Top = 48
  end
end
