program updater;

uses
  Forms,SysUtils,httpRequests,MyServis,
  updaterWnd in 'updaterWnd.pas' {MainForm};

{$R *.res}

var
 serverAddr:AnsiString;
 f:text;
 request:cardinal;
 i,n,code:integer;
 sa:AStringArr;
 response:AnsiString;
begin
 {$IFDEF INSTALLER}
  if ParamCount>0 then begin
   if UpperCase(ParamStr(1))='-INSTALL' then begin
    UpdateFiles(paramStr(2));
    exit;
   end;
  end else
   UpdateFiles(GetEnvironmentVariable('TEMP')+'\AstralHeroesUpdate');
 {$ELSE}
  dontInstall:=true;
  if ParamCount>0 then begin
   if UpperCase(ParamStr(1))='-INSTALL' then begin
    UpdateFiles(paramStr(2));
    exit;
   end;
   for i:=1 to paramCount do begin
    if UpperCase(ParamStr(i))='-DONTINSTALL' then dontInstall:=true;
    if length(paramStr(i))<5 then ver:=StrToIntDef(paramStr(i),0);
   end;
  end else begin
   // no parameters
   if pos('INSTALLUPDATE.EXE',UpperCase(ParamStr(0)))>0 then begin
    UpdateFiles(GetEnvironmentVariable('TEMP')+'\AstralHeroesUpdate');
    exit;
   end;
   if DirectoryExists('Logs') then
    UseLogFile('Logs\GameUpdate.log')
   else
    UseLogFile('GameUpdate.log');
   ForceLogMessage('Updater started...');
   try
    assign(f,'server.txt');
    reset(f);
    readln(f,serverAddr);
    close(f);
    chop(serverAddr);
    request:=HTTPrequest(serverAddr+'/getversion','','');
    n:=300; // Wait up to 3s
    while n>0 do begin
     code:=GetRequestResult(request,response);
     if code=httpStatusFailed then break;
     if code=httpStatusCompleted then begin
      LogMessage('Response: '+response);
      sa:=splitA(';',response);
      ver:=StrToIntDef(sa[0],0);
      ForceLogMessage('Server version: '+inttostr(ver));
      break;
     end;
     sleep(10);
    end;
   except
    on e:exception do begin
     ForceLogMessage('Update failure: '+e.message);
     ErrorMessage('Update failure: '+e.message);
     exit;
    end;
   end;
  end;
  Application.Initialize;
  Application.Title := 'Astral Heroes Updater';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
 {$ENDIF} 
end.
