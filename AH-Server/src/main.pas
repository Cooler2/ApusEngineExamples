{R+}
unit main;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, SvcMgr, Dialogs;

type
  TServiceObj = class(TService)
    procedure ServiceExecute(Sender: TService);
    procedure ServiceBeforeInstall(Sender: TService);
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
    procedure ServiceShutdown(Sender: TService);
  private
    { Private declarations }
  public
    function GetServiceController: TServiceController; override;
    { Public declarations }
  end;

var
  ServiceObj: TServiceObj;

  procedure ServerInit;
  procedure ServerDone(fatal:boolean=false);
  procedure ServerRun;

implementation
 uses MyServis,globals,ControlFiles2,net,workers,Logging,database,cnsts;

 {$R *.DFM}
 var
  counter:integer;
  configAge,chatFilterAge:integer;

procedure LoadChatFilter;
 var
  fname,st:UTF8String;
  i:integer;
 begin
  fname:=WorkingDir+'\chatFilter.txt';
  if not FileExists(fname) then exit;
  chatFilterAge:=FileAge(fname);
  st:=LoadFileAsString(fname);
  EnterCriticalSection(gSect);
  try
   chatFilter:=splitW(#13#10,DecodeUTF8(st));
  finally
   LeaveCriticalSection(gSect);
  end;
 end;

procedure LoadConfig;
 var
  i,j,n:integer;
  keys,types:StringArr;
  st,fname:string;
  a:integer;
 begin
  fname:=WorkingDir+'\server.ctl';
  ForceLogMessage('Loading config '+fname+'...');
  configAge:=FileAge(fname);
  ctl:=TControlFile.Create(fname,'');
  EnterCriticalSection(gSect);
  try
  try
  // Version
  a:=ctl.getInt('UpdateVersion',cnsts.version);
  if a>cnsts.version then begin
   cnsts.version:=a;
   cnsts.sVersion:=Format('v %d.%.2d',[a div 1000,a mod 1000]);
  end;
  // Log
  a:=ctl.GetInt('Log\LogSize',16);
  LOG_VERBOSITY:=ctl.GetInt('LOG\Verbosity',LOG_VERBOSITY);
  LOG_FLUSH_INTERVAL:=ctl.GetInt('LOG\FlushInterval',LOG_FLUSH_INTERVAL);

  InitLogging(a,WorkingDir+'\logs\',LOG_VERBOSITY);
  LogMsg('Log initialized',logImportant);

  // Extra features to log
  LOG_HTTP:=ctl.GetBool('LOG\LogHTTP',LOG_HTTP);
  LOG_SQL:=ctl.GetBool('LOG\LogSQL',LOG_SQL);
  LOG_TASKS:=ctl.GetBool('LOG\LogTasks',LOG_TASKS);
  LogMsg('Logging: HTTP=%d, SQL=%d',[byte(LOG_HTTP),byte(LOG_SQL)],logImportant);

  MAX_CONNECTIONS:=ctl.GetInt('Net\MaxConnections',MAX_CONNECTIONS);
  if MAX_CONNECTIONS>MAX_CONNECTIONS_LIMIT then MAX_CONNECTIONS:=MAX_CONNECTIONS_LIMIT;
  INBUF_SIZE:=ctl.GetInt('Net\InBufSize',INBUF_SIZE);
  REQUEST_TIMEOUT:=ctl.GetInt('Net\RequestTimeout',REQUEST_TIMEOUT div 1000)*1000;
  KEEP_ALIVE_TIMEOUT:=ctl.GetInt('Net\KeepAliveTimeout',KEEP_ALIVE_TIMEOUT div 1000)*1000;
  DATA_TIMEOUT:=ctl.GetInt('Net\DataTimeout',DATA_TIMEOUT div 1000)*1000;
  USER_TIMEOUT:=ctl.GetInt('Net\UserTimeout',USER_TIMEOUT div 1000)*1000;
  MAX_LOCAL_FILESIZE:=ctl.GetInt('Net\MaxLocalFileSize',MAX_LOCAL_FILESIZE div 1024)*1024;

  NET_LOOP_INTERVAL:=ctl.GetInt('Net\NetLoopInterval',NET_LOOP_INTERVAL);
  HTTP_PORT:=ctl.GetInt('Net\Port',HTTP_PORT);
  SEND_ACAO:=ctl.GetBool('Net\SendACAO',SEND_ACAO);

  NUM_WORKERS:=ctl.GetInt('NumWorkers',NUM_WORKERS);
  MAX_URGENCY:=ctl.GetInt('MaxUrgency',MAX_URGENCY);

  SPARE_SERVER:=ctl.GetBool('SpareServer',SPARE_SERVER);
  if SPARE_SERVER then ForceLogMessage('Running in SPARE mode');

  SERVER_NAME:=ctl.GetStr('DisplayName',SERVER_NAME);
  STEAM_API_KEY:=ctl.GetStr('SteamAPIKey',STEAM_API_KEY);

  AccessToken:=ctl.GetStr('AccessToken','');
  ControlToken:=ctl.GetStr('ControlToken','');

  // Welcome messages
  welcomeEn:=ctl.GetStr('Welcome\En','');
  welcomeRu:=Win1251toUTF8(ctl.GetStr('Welcome\Ru',''));
  altWelcomeEn:=ctl.GetStr('Welcome\AltEn','');
  altWelcomeRu:=Win1251toUTF8(ctl.GetStr('Welcome\AltRu',''));
  altWelcomeForDate:=GetDateFromStr(ctl.GetStr('Welcome\AltForDate',''));

  // Database
  MySQL_HOST:=ctl.GetStr('MySQL\Host',MySQL_HOST);
  MySQL_DATABASE:=ctl.GetStr('MySQL\Database',MySQL_DATABASE);
  MySQL_LOGIN:=ctl.GetStr('MySQL\Login',MySQL_LOGIN);
  MySQL_PASSWORD:=ctl.GetStr('MySQL\Password',MySQL_PASSWORD);

  homeDir:=ctl.GetStr('HomeDir','');
  if LastChar(homeDir)<>'\' then homeDir:=homeDir+'\';
  // MIME types for static files
  keys:=split(' ',ctl.GetKeys('MIME'));
  setLength(mimeTypes,length(keys));
  n:=0;
  for i:=0 to length(keys)-1 do begin
   types:=Split(' ',ctl.GetStr('MIME\'+keys[i]+'\extensions'));
   st:=ctl.GetStr('MIME\'+keys[i]+'\Type');
   for j:=0 to length(types)-1 do begin
    if n>=length(MimeTypes) then begin
     SetLength(MimeTypes,n+1);
    end;
    MimeTypes[n].extension:=UpperCase(types[j]);
    MimeTypes[n].mimetype:=st;
    inc(n);
   end;
  end;

  // Cache control rules
  keys:=split(' ',ctl.GetKeys('CacheControl'));
  setLength(cacheRules,length(keys));
  for i:=0 to length(cacheRules)-1 do begin
   cacheRules[i].pattern:=UpperCase(ctl.GetStr('CacheControl\'+keys[i]+'\Pattern'));
   cacheRules[i].value:=ctl.GetStr('CacheControl\'+keys[i]+'\Value');
  end;

  BOT_DELAY_CUSTOM:=ctl.GetInt('BotDelayCustom',BOT_DELAY_CUSTOM);
  BOT_DELAY_CLASSIC:=ctl.GetInt('BotDelayClassic',BOT_DELAY_DRAFT);
  BOT_DELAY_DRAFT:=ctl.GetInt('BotDelayDraft',BOT_DELAY_DRAFT);
  BOT_TURN_DELAY:=ctl.GetInt('BotTurnDelay',BOT_TURN_DELAY);
  BOT_ACTION_DELAY:=ctl.GetInt('BotActionDelay',BOT_ACTION_DELAY);

  ForceLogMessage('Config loaded');
  except
   on e:exception do ForceLogMessage('LoadConfig error: '+ExceptionMsg(e));
  end;
  finally
   LeaveCriticalSection(gSect);
  end;
  ctl.Free;
 end;

procedure ServerInit;
 var
  path:string;
 begin
  randomize;
  path:=ExtractFileDir(ParamStr(0));
  WorkingDir:=path;
  SetCurrentDir(workingDir);
  try
   // copy old log
   if FileExists(path+'\logs\server.log') then begin
    DeleteFile(path+'\logs\server_.log');
    RenameFile(path+'\logs\server.log',path+'\logs\server_.log');
   end;
   if FileExists(path+'\logs\status.log') then begin
    DeleteFile(path+'\logs\status_.log');
    RenameFile(path+'\logs\status.log',path+'\logs\status_.log');
   end;
   // initialize new log
   UseLogFile(path+'\logs\server.log');
   SetLogMode(lmVerbose);
 // SetLogMode(lmVerbose,'6');
   ForceLogMessage('Starting server at '+FormatDateTime('ddddd tt',Now));

   RegisterThread('Main');
   LoadConfig;
   // DB init
   DB_HOST:=MYSQL_HOST;
   DB_DATABASE:=MYSQL_DATABASE;
   DB_LOGIN:=MYSQL_LOGIN;
   DB_PASSWORD:=MYSQL_PASSWORD;

   InitWorkers;

   // Load templates
   ForceLogMessage('Loading templates');
   loginPage:=LoadFileAsString('HTML\login.htm');
   adminPage:=LoadFileAsString('HTML\admin.htm');

   sleep(50);
   SetThreadPriority(GetCurrentThread,THREAD_PRIORITY_ABOVE_NORMAL);

//   watchThread:=TWatchThread.Create;

   StartNetwork;
   serverState:=ssRunning;
  except
   on e:Exception do begin
    ForceLogMessage('Can''t initialize: '+ExceptionMsg(e));
    serverState:=ssFailure;
   end;
  end;
 end;

procedure ServerDone(fatal:boolean=false);
 var
  i:integer;
 begin
  ForceLogMessage('ServerDone called');
  try
   LogMsg('ServerDone!',logImportant);
   // Порядок имеет значение! Если А использует Б, то сначала остановить А, а потом Б
   acceptIncomingMessages:=false;
   // ожидание завершения выполнения тасков
   for i:=1 to 10 do begin
    sleep(40);
    if TaskQueueSize=0 then break;
   end;
   DoneNetwork;
   LogMsg('Unfinished tasks: '+IntToStr(TaskQueueSize),logImportant);
   if not fatal then DoneWorkers;
   SaveLogMessages;
   sleep(100);
//   DoneDB;
  except
   on e:exception do ForceLogMessage('Error in SD: '+ExceptionMsg(e));
  end;
  ForceLogMessage('ServerDone finished');
 end;

procedure FatalExit;
 var
  i:integer;
 begin
   ForceLogMessage('Enforcing restart...');
   ForceLogMessage('User request: '+inttostr(curUser)+' '+curUserCmd);
   ForceLogMessage('Async tasks:'#13#10+GetCurrentTasks);
   DumpCritSects;
   ServerDone(true);
   ForceLogMessage('Exiting...');
   halt(65500);
 end;

procedure ServerRun;
 var
  f:text;
  st:string;
  wait:integer;
 begin
  inc(counter);
  try
   wait:=500;

//   gSect.Enter;
//   try
    if (netThreadTimeStamp>0) and (Now>netThreadTimeStamp+15*SECOND) then begin
     LogMsg('NET thread stall since '+FormatDateTime('hh:nn:ss.zzz',netThreadTimeStamp),logError);
     if Now>netThreadTimeStamp+MINUTE then FatalExit;
     inc(wait,500);
    end;

    if (workersTimestamp>0) and (Now>workersTimestamp+20*SECOND) then begin
     LogMsg('WORKER threads stall since '+FormatDateTime('hh:nn:ss.zzz',workersTimestamp),logError);
     if Now>workersTimestamp+MINUTE then FatalExit;
     inc(wait,500);
    end;

    if counter mod 60=0 then
     ForceLogMessage(Format('Status: net=%s work=%s curuser=%d curUserCmd="%s"'#13#10' workers="%s"',
       [FormatDateTime('hh:nn:ss.zzz',netThreadTimeStamp),FormatDateTime('hh:nn:ss.zzz',workersTimeStamp),
        curUser,curUserCmd,GetCurrentTasks]));
{   finally
    gSect.Leave;
   end;}

   try
   if FileAge(WorkingDir+'\server.ctl')<>configAge then LoadConfig;
   if FileAge(WorkingDir+'\chatFilter.txt')<>chatFilterAge then LoadChatFilter;
   except
    on e:Exception do LogMsg('Error XX: '+e.message);
   end;

   if FileExists('command.txt') then begin
     assign(f,'command.txt');
     reset(f);
     readln(f,st);
     close(f);
     DeleteFile('command.txt');
     ForceLogMessage('Command: '+st);
     st:=UpperCase(st);
     if st='STOP' then needExit:=true;
   end;
  except
   on e:exception do ForceLogMessage('ServerRun error: '+ExceptionMsg(e));
  end;
  sleep(wait);
 end;


procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  ServiceObj.Controller(CtrlCode);
end;

function TServiceObj.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TServiceObj.ServiceBeforeInstall(Sender: TService);
var
 ctl:TControlFile;
begin
  WorkingDir:=ExtractFileDir(ParamStr(0));
  ctl:=TControlFile.Create(WorkingDir+'\server.ctl','');
  serviceObj.name:=ctl.GetStr('ServiceName',serviceObj.name);
  serviceObj.DisplayName:=ctl.GetStr('DisplayName',serviceObj.DisplayName);
  ctl.Free;
end;

procedure TServiceObj.ServiceExecute(Sender: TService);
begin
// Main loop here
 try
 ForceLogMessage('Main loop...');
 repeat
   ServerRun;
   sleep(0); // задержка есть в самом ServerRun
   ServiceThread.ProcessRequests(false); // Ключевая штука - без неё сервис не будет реагировать на команды
   if needExit then ServiceThread.Terminate;
 until terminated;
 except
  on e:Exception do begin
   ForceLogMessage('Error in service thread: '+ExceptionMsg(e));
  end;
 end;
 ServerDone;
end;

procedure TServiceObj.ServiceShutdown(Sender: TService);
begin
 needExit:=true;
end;

procedure TServiceObj.ServiceStart(Sender: TService; var Started: Boolean);
begin
 ServerInit;
 started:=true;
end;

procedure TServiceObj.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
 needExit:=true;
 stopped:=true;
end;
{
procedure TWatchThread.Execute;
var
 c:integer;
 f,f2:text;
 flag:boolean;
 prev:integer;
 fname:string;
begin
 try
  SetThreadPriority(GetCurrentThread,THREAD_PRIORITY_HIGHEST);
  c:=0;
  assign(f,WorkingDir+'\logs\status.log');
  rewrite(f);
  close(f);
  restartTimer:=RestartDelay;
  flag:=true;
  repeat
   inc(c);
   sleep(100);
   dec(restartTimer);
   if userCnt<>saveuserCnt then begin
    if userCnt>saveUserCnt then
     restartTimer:=RestartDelay;
    saveUserCnt:=userCnt;
   end;
   if RestartTimer<0 then begin
    ForceLogMessage('No activity - restart!');
    LogMsg('No activity - restart!');
    SMServ.needrestart:=true;
    exit;
   end;
   // Раз в минуту
   if c mod 600=0 then try
    fname:=WorkingDir+'\logs\netstat'+FormatDateTime('mmdd',Now)+'.log';
    assign(f2,fname);
    if fileExists(fname) then append(f2)
     else rewrite(f2);
    writeln(f2,FormatDateTime('dd.mm.yyyy hh:nn:ss',Now),' ',c,' NET:',
     GetNetStat(1),':',GetNetStat(2),' pkt ',GetNetStat(3),':',GetNetStat(4),
     ' bytes. Users: ',maxUsers,' Games: ',gamesCounter);
    gamesCounter:=0;
    close(f2);
    maxusers:=0;
   except
    on e:exception do ForceLogMessage('Error WT1: '+e.message);
   end;
   if c mod 75=0 then try // 7.5 секунд
    append(f);
    writeln(f,FormatDateTime('hh:nn:ss.zzz',Now),' Main: ',counter,
    ', state: ',logic.serverState,'/',serverState,' MEM: ',GetMemoryState);
    close(f);
    if flag and (counter=prev) then begin
     ForceLogMessage('Main thread stall! State: '+inttostr(logic.serverState)+
       ' req: '+inttostr(currequest));
     DumpCritSects;
     flag:=false;
     SMServ.CloseServer(true);
    end;
    prev:=counter;
   except
    on e:exception do ForceLogMessage('Error WT2: '+e.message);
   end;
  until terminated;
 except
  on e:Exception do ForceLogMessage('Watcher: '+e.message);
 end;
end;
}

end.
