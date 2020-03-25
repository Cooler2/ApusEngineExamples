unit mainWnd;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
{$IFnDEF FPC}
  XPMan, Windows,
{$ELSE}
  LCLIntf, LCLType, LMessages,
{$ENDIF}
  Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, StdCtrls, ExtCtrls, ControlFiles2;

type
  TMainForm = class(TForm)
    memo: TMemo;
    btnSync: TButton;
    btnReports: TButton;
    XPManifest1: TXPManifest;
    Timer: TTimer;
    btnVerify: TButton;
    procedure FormActivate(Sender: TObject);
    procedure btnSyncClick(Sender: TObject);
    procedure btnReportsClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure TimerTimer(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    btnMode:boolean; // функция первой кнопки: запуск синхронизации или же её отмена
    addLogStr:string;
    procedure UpdateLog;
    procedure SyncDone;
    procedure LoadingDone;
  end;

var
  MainForm: TMainForm;

  DBPath:AnsiString; // путь к файлам с данными
  ctl:TControlFile;


implementation
 uses
{$IFnDEF FPC}
  database,
{$ELSE}
{$ENDIF}
  MyServis,BackupDB,ReportWnd,eventman;


{$IFnDEF FPC}
  {$R *.dfm}
{$ELSE}
  {$R *.lfm}
{$ENDIF}

procedure TMainForm.btnReportsClick(Sender: TObject);
begin
 btnSync.Enabled:=false;
 btnReports.enabled:=false;
 ShowReportsWnd;
 Hide;
end;

procedure TMainForm.btnSyncClick(Sender: TObject);
begin
 if btnMode then begin
  btnSync.Enabled:=false;
  btnVerify.Enabled:=false;
  btnReports.Enabled:=false;
  if sender=btnSync then begin
   memo.Lines.Add('Запуск синхронизации БД...');
   btnSync.Caption:='Abort Sync';
   BackupGameDB;
   btnMode:=false;
   btnSync.Enabled:=true;
  end;
  if sender=btnVerify then begin
   memo.Lines.Add('Проверка целостности данных...');
   VerifyGameDB;
  end;
 end else begin
  btnSync.Enabled:=false;
  btnSync.Caption:='Aborting...';
  AbortBackup;  
  btnMode:=true;
  btnSync.Enabled:=true;
 end;
end;

function EventHandler(event:EventStr;tag:TTag):boolean;
begin
 event:=UpperCase(copy(event,8,100));
 if event='CLOSEWND' then begin
{  mainForm.btnSync.Enabled:=true;
  mainForm.btnReports.Enabled:=true;}
  MainForm.Close;
  application.Terminate;
 end;
end;

procedure TMainForm.FormActivate(Sender: TObject);
begin
 // Current dir
 SetCurrentDir(ExtractFilePath(ParamStr(0)));
 FormatSettings.DecimalSeparator:='.';
 // Logging
 if FileExists('AhStat.log') then RenameFile('AhStat.log','AhStat.old');
 UseLogFile('AhStat.log');
 SetLogMode(lmVerbose);
 LogCacheMode(true,false,true);
 // Load config
 ctl:=TControlFile.Create('ahStat.ctl','');
 DBPath:=ctl.GetStr('DBPath',GetCurrentDir);
 if LastChar(DBpath)<>'\' then DBPath:=DBPath+'\';
 DB_HOST:=ctl.GetStr('server','');
 DB_DATABASE:=ctl.GetStr('dbname','');
 DB_LOGIN:=ctl.GetStr('dbuser','');
 DB_PASSWORD:=ctl.GetStr('dbpassword','');
 lastSyncDate:=GetDateFromStr(ctl.GetStr('LastSyncTime','2016-01-01'));
 btnMode:=true;
 // Асинхронная загрузка всех данных из локальных файлов
 LoadAllData;

 SetEventHandler('AHStat',EventHandler,emQueued);
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 CloseReportsWnd; 
end;

procedure TMainForm.SyncDone;
begin
  lastSyncDate:=Now;
  ctl.SetStr('LastSyncTime',FormatDateTime('yyyy-mm-dd hh:nn',lastSyncDate));
  ctl.Save;
  btnSync.Caption:='DB Sync';
  btnSync.enabled:=true;
  btnMode:=true;
  btnReports.Enabled:=true;
  btnVerify.enabled:=true;
end;

procedure TMainForm.TimerTimer(Sender: TObject);
begin
 HandleSignals;
end;

procedure TMainForm.LoadingDone;
begin
  btnSync.Enabled:=true;
  btnVerify.Enabled:=true;
  btnReports.Enabled:=true;
  btnMode:=true;
  if Now>lastSyncDate+0.5 then
   btnSyncClick(btnSync)
  else
   memo.Lines.Add(WideString('Синхронизация БД выполнялась недавно: ')+FormatDateTime('dd.mm.yyyy hh:nn',lastSyncDate));
end;

procedure TMainForm.UpdateLog;
begin
 if addLogStr<>'' then begin
  if addLogStr[1]='+' then
   Memo.Lines[memo.lines.Count-1]:=Memo.Lines[memo.lines.Count-1]+copy(addLogStr,2,500)
  else
  if addLogStr[1]='-' then
   Memo.Lines[memo.lines.Count-1]:=copy(addLogStr,2,500)
  else
   Memo.Lines.Append(addLogStr);
 end;
 addLogStr:='';
end;

end.
