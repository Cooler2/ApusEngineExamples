{$SETPEFLAGS $20} // Allow 4GB memory space for 32-bit process
program AHserver;

uses
  SvcMgr,
  SysUtils,
  MyServis,
  ControlFiles2,
  Cnsts,
  UCompAI,
  NetCommon,
  UDeck,
  UMissionsLogic,
  UCalculating,
  main in 'main.pas' {ServiceObj: TService},
  net in 'net.pas',
  globals in 'globals.pas',
  workers in 'workers.pas',
  ServerLogic in 'ServerLogic.pas',
  CustomLogic in 'CustomLogic.pas',
  ULogicWrapper in 'ULogicWrapper.pas',
  gameData in 'gameData.pas';
{$R *.RES}

begin
 if UpperCase(paramStr(1))='-TABLES' then begin
  CreateTables;
  exit;
 end; 
 if UpperCase(paramStr(1))='-RUN' then begin // run as standalone program
  serviceMode:=false;
  ServerInit;
  try
   repeat
    ServerRun;
    sleep(0);
   until needExit;
  except
   on e:Exception do ForceLogMessage('Error in main loop: '+ExceptionMsg(e));   
  end;
  ServerDone;
  halt;
 end;
  // Windows 2003 Server requires StartServiceCtrlDispatcher to be
  // called before CoRegisterClassObject, which can be called indirectly
  // by Application.Initialize. TServiceApplication.DelayInitialize allows
  // Application.Initialize to be called from TService.Main (after
  // StartServiceCtrlDispatcher has been called).
  //
  // Delayed initialization of the Application object may affect
  // events which then occur prior to initialization, such as
  // TService.OnCreate. It is only recommended if the ServiceApplication
  // registers a class object with OLE and is intended for use with
  // Windows 2003 Server.
  //
  // Application.DelayInitialize := True;
  //
  try
   if not Application.DelayInitialize or Application.Installing then
     Application.Initialize;
   Application.CreateForm(TServiceObj, ServiceObj);
  serviceObj.LogMessage('Starting AH Server');
   WorkingDir:=ExtractFileDir(ParamStr(0));
   ctl:=TControlFile.Create(WorkingDir+'\server.ctl','');
   serviceObj.name:=ctl.GetStr('ServiceName',ServiceObj.name);
   serviceObj.DisplayName:=ctl.GetStr('DisplayName',serviceObj.DisplayName);
   ctl.Free;
   Application.Run;
  except
   on e:exception do
    if serviceObj<>nil then begin
     serviceObj.LogMessage('Exception: '+ExceptionMsg(e));
     WriteFile('error.txt',@ExceptionMsg(e)[1],0,length(ExceptionMsg(e)));
    end;
  end;
end.
