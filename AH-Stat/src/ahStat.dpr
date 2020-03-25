{$SETPEFLAGS $20} // Allow 4GB memory space for 32-bit process
program ahStat;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

uses
{$IFnDEF FPC}
{$ELSE}
  Interfaces,
{$ENDIF}
  Forms,
  NetCommon,
  UCalculating,
  Cnsts,
  mainWnd in 'mainWnd.pas' {MainForm},
  BackupDB in 'BackupDB.pas',
  Data in 'Data.pas',
  ReportWnd in 'ReportWnd.pas',
  customUI in 'customUI.pas',
  UICharts in 'UICharts.pas',
  Reports in 'Reports.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
