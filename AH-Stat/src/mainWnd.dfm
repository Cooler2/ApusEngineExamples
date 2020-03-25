object MainForm: TMainForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'Astral Heroes Analytics'
  ClientHeight = 336
  ClientWidth = 478
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnActivate = FormActivate
  OnClose = FormClose
  DesignSize = (
    478
    336)
  PixelsPerInch = 96
  TextHeight = 13
  object memo: TMemo
    Left = 0
    Top = 0
    Width = 478
    Height = 289
    Align = alTop
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlack
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object btnSync: TButton
    Left = 16
    Top = 295
    Width = 145
    Height = 33
    Anchors = [akLeft, akBottom]
    Caption = 'DB Sync'
    Enabled = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
    OnClick = btnSyncClick
  end
  object btnReports: TButton
    Left = 318
    Top = 295
    Width = 145
    Height = 33
    Anchors = [akLeft, akBottom]
    Caption = 'Reports'
    Enabled = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 2
    OnClick = btnReportsClick
  end
  object btnVerify: TButton
    Left = 167
    Top = 295
    Width = 145
    Height = 33
    Anchors = [akLeft, akBottom]
    Caption = 'Verify'
    Enabled = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 3
    OnClick = btnSyncClick
  end
  object XPManifest1: TXPManifest
    Left = 360
    Top = 16
  end
  object Timer: TTimer
    Interval = 50
    OnTimer = TimerTimer
    Left = 392
    Top = 16
  end
end
