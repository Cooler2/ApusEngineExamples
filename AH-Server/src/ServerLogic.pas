// В этом модуле реализована обработка стандартных запросов сервера
// - сервисные запросы (статистика, управление сервером, подключение/отключение)
// - запросы сообщений юзеров
// Т.о. код этого модуля не содержит прикладной специфики
{$R+}
unit ServerLogic;
interface
 uses globals,MyServis,database,gameData;

 type
  TCustomMySQLDatabase=class(TMySQLDatabase)
   function Query(DBquery:RawByteString):AStringArr; override;
  end;

 // Server status
 function RequestAdmin(con:integer):UTF8String;

 // Management command
 function RequestAdminCmd(con:integer):UTF8String;

 // Server log
 function RequestLog(con:integer):UTF8String;

 // запрос сообщений, накопившихся для юзера, очищает буфер сообщений юзера
 // возвращает сообщения без заголовков
 // если их нет - пустую строку
 function GetUserMsgs(UserID:integer):UTF8String;

 // Отправка сообщения юзеру. Сообщения складываются в буфер юзера
 // delayed - отправить сразу же или можно когда-нибудь потом (не влияет на порядок доставки сообщений)
 // возвращает false в случае ошибки
 function PostUserMsg(userID:integer;msg:UTF8String;delayed:boolean=false):boolean;

 // Convert values to strings and join them
 function FormatMessage(data:array of const):UTF8String;

 procedure SendVerificationEmail(email,login,lang:UTF8String);

 // ------ вызывать только внутри критсекции gSect! -----------
 // Создает юзера, возвращает UserID
 function CreateUser(tempUser:boolean=false):integer;
 // Удаляет юзера по UserID
 procedure DeleteUser(userID:integer;reason:UTF8String='';extra:UTF8String='');
 // UserID by name (0 - not found)
 function FindUser(name:UTF8String;ignoreBots:boolean=true):integer;
 // Get UserID by session
// function GetUser(sess:UTF8String):integer;

 function GetPlayerID(userID:integer):integer; // 0 если такого юзера нет

 // Вызывать внутри gSect (очевидно)
 function IsValidUserID(userID:integer;authorizedOnly:boolean=false):boolean;

 function TempUserIndex(userID:integer):integer;

 function FormatHTML(body,title:UTF8String;head:UTF8String=''):UTF8String;

 function LoginAllowed:boolean;

 // Вызывается раз в секунду внутри gSect
 procedure onTimer;

 var
  // Список АВТОРИЗОВАННЫХ юзеров
  // занятые записи идут не по порядку! Индекс массива - userID
  users:array[0..MAX_USERS] of TUser;  // -1,0 - специальный слот для инвалидного юзера

implementation
 uses SysUtils,Logging,net,workers,CustomLogic,structs,WinSock2,classes,StrUtils;

 var
  // Неавторизованные (временные) юзеры имеют номера вида 1xxxx,
  // где xxxx - случайное число
  // Эти юзеры не создаются и не управляются кастомной логикой
  //   служат только для управления соединением
  tempUsers:array[1..20] of TUser;


 const
  HTML_TEMPLATE:UTF8String=
   '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">'#13#10+
   '<html>'#13#10+
   '<head>'#13#10+
   '__HEAD__'#13#10+
   '</head>'#13#10+
   '<body>'#13#10+
   '__BODY__'#13#10+
   '</body>'#13#10+
   '</html>'#13#10;

procedure SendVerificationEmail(email,login,lang:UTF8String);
 var
  msg:TStringList;
 begin
{  try
   msg:=TStringList.Create;
   msg.Add(Format('Hello, %s!',[login]));
   SendToEx('support@astralheroes.com',email,'Astral Heroes: please verify your email address',
     '127.0.0.1',msg,'','','Content-Type: text/html; charset=UTF-8');
  except
   on e:exception do LogMsg('Error sending email to '+email+': '+ExceptionMsg(e));
  end;}
 end;

function StringReplaceEx(OriginalString, Pattern, Replace: UTF8String): UTF8String;
var
  SearchStr, Patt, NewStr: UTF8String;
  Offset: Integer;
begin
  Result := '';
  SearchStr := OriginalString;
  Patt := Pattern;
  NewStr := OriginalString;

  while SearchStr <> '' do
  begin
    Offset := Pos(Patt, SearchStr); // Was AnsiPos
    if Offset = 0 then
    begin
      Result := Result + NewStr;
      Break;
    end;
    Result := Result + Copy(NewStr, 1, Offset - 1) + Replace;
    NewStr := Copy(NewStr, Offset + Length(Pattern), MaxInt);
    SearchStr := Copy(SearchStr, Offset + Length(Patt), MaxInt);
  end;
end;

function TCustomMySQLDatabase.Query(DBquery: RawByteString): AStringArr;
 begin
  if UpperCase(copy(DBquery,1,6))='SELECT' then begin
    if LOG_SQL then LogMsg(DBquery,logInfo,2)
  end else
   LogMsg(DBquery,logNormal,2);
  lastError:='';
  result:=inherited Query(DBquery);
  if lastError<>'' then LogMsg('SQL Error: '+lastError,logWarn,2);
 end;

 function FormatHTML(body,title:UTF8String;head:UTF8String=''):UTF8String;
  begin
   result:=HTML_TEMPLATE;
   if title<>'' then head:=' <title>'+title+'</title>'#13#10+head;
   result:=StringReplace(result,'__HEAD__',head,[]);
   result:=StringReplace(result,'__BODY__',body,[]);
  end;

 function GetPlayerID(userID:integer):integer;
  begin
   result:=0;
   EnterCriticalSection(gSect);
   try
    if IsValiduserID(userID,true) then
     result:=users[userID].playerID;
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 function CreateUser(tempUser:boolean=false):integer;
  var
   userID,i:integer;
  begin
   EnterCriticalSection(gSect);
   try
   if tempUser then begin
    result:=0;
    for i:=1 to High(tempUsers) do
     if tempUsers[i]=nil then begin
      userID:=10001+random(10000);
      tempUsers[i]:=TUser.Create(userID);
      result:=userID;
      break;
     end;
    exit;
   end;
   // Нормальный юзер
   if uCnt>=MAX_USERS then
    raise EError.Create('TOO MANY USERS');

   // Find empty slot 
   for i:=1 to high(users) do
    if users[i]=nil then begin
     userID:=i; result:=i; break;
    end;
   users[userID]:=TUser.Create(userID);
   users[userID].timeOut:=MyTickCount+USER_TIMEOUT; // 30 sec (override default 10 sec value)
   finally
    LeaveCriticalSection(gSect);
   end;
   LogMsg('User created: '+inttostr(userID),logInfo);
  end;

 procedure DeleteUser(userID:integer;reason:UTF8String='';extra:UTF8String='');
  var
   i:integer;
  begin
   try
   LogMsg('Deleting user %d (%s) (%s)',[userID,reason,extra],logInfo);
   if userID<=0 then begin
    LogMsg('Invalid userID to delete!',logError);
    exit;
   end;
   EnterCriticalSection(gSect);
   try
   userID:=userID and $FFFF;
   if userID>10000 then begin
    for i:=1 to High(tempUsers) do
     if (tempusers[i]<>nil) and (tempusers[i].userID=userID) then begin
      FreeAndNil(tempUsers[i]);
      exit;
     end;
    LogMsg('User '+inttostr(userID)+' not found!',logWarn);
   end else
    if users[userID]<>nil then begin
     Logout(userID,reason,extra);
     FreeAndNil(users[userID]);
     CloseUserConnections(userID);
    end else
     LogMsg('User '+inttostr(userID)+' not found!',logWarn);
   finally
    LeaveCriticalSection(gSect);
   end;
   except
    on e:exception do LogMsg('Error in DeleteUser: '+ExceptionMsg(e),logWarn);
   end;
  end;

 function FindUser(name:UTF8String;ignoreBots:boolean=true):integer;
  var
   i:integer;
  begin
   result:=0;
   name:=UpperCase(name);
   for i:=1 to High(users) do
    if users[i]<>nil then begin
     if ignoreBots and (users[i].botLevel>0) then continue;
     if UpperCase(users[i].name)=name then begin
      result:=i; exit;
     end;
    end;
  end;  

{ function GetUser(sess:UTF8String):integer;
  begin
   result:=0;
   if length(sess)<10 then exit;
   result:=HexToInt(copy(sess,1,4));
   if (result>0) and (result<=MAX_USERS) and
      (users[result]<>nil) and (users[result].session=sess) then exit;
   result:=0;
  end;}

 function IsValidUserID(userID:integer;authorizedOnly:boolean=false):boolean;
  var
   i:integer;
  begin
   result:=false;
   if (userID>=0) and (userID<=High(users)) then
    if users[userID]<>nil then result:=true;
   if authorizedOnly then exit;
   if (userID>=10000) and (userID<20000) then
    for i:=1 to High(tempUsers) do
     if (tempUsers[i]<>nil) and (tempUsers[i].userID=userID) then begin
      result:=true; exit;
     end;
  end;

 function TempUserIndex(userID:integer):integer;
  var
   i:integer;
  begin
   result:=0;
   for i:=1 to high(tempUsers) do
    if (tempUsers[i]<>nil) and (tempusers[i].userID=userID) then begin
     result:=i; exit;
    end;
  end;   

 function PostUserMsg(userID:integer;msg:UTF8String;delayed:boolean=false):boolean;
  begin
   result:=false;
   if userID=0 then exit; // special fake user
   EnterCriticalSection(gSect);
   try
    if not IsValidUserID(userID) then begin
      LogMsg('PostUserMsg: invalid UserID: '+inttostr(userID),logNormal);
      exit;
    end;
    with users[userid] do begin
     if (botLevel>0) then exit; // don't send anything to bot
     if not delayed then
      LogMsg('PostMsg to '+name+': '+copy(msg,1,100)+IfThen(length(msg)>100,'..',''),logInfo);
     msg:=StringReplaceEx(msg,'\','\\');
     msg:=StringReplaceEx(msg,#13#10,'\n');
     if messages<>'' then messages:=messages+#13#10+msg
      else messages:=messages+msg;
     if not delayed then sendASAP:=true;
     inc(msgCount);
     if msgCount>=10 then sendASAP:=true; // накопилось слишком много сообщений - надо отправить   
    end;
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 function GetUserMsgs(UserID:integer):UTF8String;
  begin
   result:='';
   EnterCriticalSection(gSect);
   try
    if not IsValidUserID(userID,true) then
      raise EError.Create('GetUserMsg: Invalid UserID: '+inttostr(userID));
    result:=users[userID].messages;
    users[userID].messages:='';
    users[userID].msgCount:=0;
    users[userID].sendASAP:=false;
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 function FormatMessage(data:array of const):UTF8String;
  var
   sa:StringArr;
   i:integer;
  begin
   SetLength(sa,length(data));
   for i:=0 to length(data)-1 do
    sa[i]:=VarToStr(data[i]);
   result:=combine(sa,'~','_');
  end;

 function BuildStatusBlock:UTF8String;
  begin
   result:=
     '<p>Version: '+GetAllowedVersions+
     '<p>Date: '+FormatDateTime('ddddd hh:nn:ss.zzz',Now())+'<p>'+
     '<p>Autosearch state: <span title="'+HTMLString(autosearchState[dtCustom])+
        '">custom</span> <span title="'+HTMLString(autosearchState[dtClassic])+
        '">classic</span> <span title="'+HTMLString(autosearchState[dtDraft])+
        '">draft</span>';
  end;

 function BuildConnectionsList:UTF8String;
  var
   cList:TConInfoArray;
   i:integer;
   key,items:UTF8String;
   hash:THash;
   v:integer;
  const
   sNames:array[1..4] of UTF8String=('Reading','Waiting','Sending','Closing');
  begin
   cList:=GetConnectionsList;
   // Sort by IP
   hash.Init(true);
   for i:=0 to high(cList) do
    hash.Put(IntToHex(ntohl(cList[i].remIP),8),i);
   hash.SortKeys;
   result:='connections=new Array(""';
   for key in hash.AllKeys do begin
    items:='';
    for v in hash.GetAll(key) do begin
     result:=result+Format(',"%d|%s|%d|%s|%d|%s|%s|%d|%d|%d"',
       [cList[v].ID,IpToStr(cList[v].remIP),cList[v].remPort,cList[v].country,ord(cList[v].status),
        HowLong(cList[v].opened),HowLong(cList[v].lastRequestTime),cList[v].cometUserID,
        cList[v].clientType,cList[v].timeout]);
    end;
   end;
   result:=result+');'#13#10;
  end;

 // POST admincmd action=xxx
 function RequestAdminCmd(con:integer):UTF8String;
  var
   action,value,target,lang:UTF8String;
   userID,i:integer;
   sa:StringArr;
   fl:boolean;
  begin
   EnterCriticalSection(gSect);
   try
   result:='FAILURE!';
   action:=LowerCase(Param(con,'action'));
   LogMsg('AdminCmd: action='+action,logNormal);

   if action='reloadguilds' then begin
    FreeOfflineGuilds;
    for i:=1 to high(guilds) do
     if guilds[i].name<>'' then
      AddTask(0,0,['RELOADGUILD',i]);
    result:='OK';
   end;

   if action='dailymaintenance' then begin
    AddTask(0,0,['DAILY_MAINTENANCE']);
    result:='OK';
   end;

   if action='msgtoall' then begin
     LogMsg('Message to All');
     value:=Param(con,'msg');
     if value<>'' then begin
       result:='OK';
       PostServerMsg(-1,value);
     end else
       result:='Invalid message!';
   end;

   if action='msgto' then begin
     value:=Param(con,'msg');
     target:=Param(con,'target');
     fl:=Param(con,'nosender')<>'';
     LogMsg('Message to '+target);
     sa:=split(',',target);
     for i:=0 to high(sa) do begin
      target:=sa[i];
      userID:=FindUser(target);
      if (userID>0) and (value<>'') then begin
        result:='OK';
        PostServerMsg(userID,value,fl);
      end else begin
        if userID=0 then result:='User '+target+' not found!'
         else  result:='Invalid message!'
      end;
     end;
   end;

   if action='requestgamelog' then begin
     target:=Param(con,'plrname');
     LogMsg('Request game log from player '+target);
     userID:=FindUser(target);
     if (userID>0) then begin
       result:='OK';
       PostUserMsg(userID,'3');
     end else begin
      result:='User '+target+' not found!';
     end;
   end;


   if action='dumpdata' then begin
    LogMsg('DumpServerData');
    DumpServerData;
    result:='OK';
   end;

   if action='restart30' then begin
    LogMsg('Planned restart in 30 min',logImportant);
    restartNotices:=0;
    restartTime:=Now+30*Minute;
    serverState:=ssRestarting;
    result:='OK';
   end;

   if action='restart20' then begin
    LogMsg('Planned restart in 20 min',logImportant);
    restartNotices:=0;
    restartTime:=Now+20*Minute;
    serverState:=ssRestarting;
    result:='OK';
   end;

   if action='kickplayer' then begin
     target:=Param(con,'plrname');
     value:=Param(con,'reason');
     LogMsg('Kick player: '+target);
     userID:=FindUser(target);
     if (userID>0) then begin
       result:='OK';
       PostServerMsg(userID,'You''re kicked from the server, reason: '+value);
       DeleteUser(userID,value);
     end else
      result:='User not found!'
   end;

   // Только юзера на сервере, наказание в базу не вносит
   if action='makesilent' then begin
     target:=Param(con,'plrname');
     value:=Param(con,'reason');
     LogMsg('Make player silent: '+target);
     userID:=FindUser(target);
     if (userID>0) then begin
       result:='OK';
       PostServerMsg(userID,'Your account switched to silent mode, reason: '+value);
       users[userID].flags:=users[userID].flags or ufSilent;
     end else
      result:='User not found!'
   end;

   if action='welcome' then begin
     target:=Param(con,'target');
     value:=Param(con,'msg');
     if target='welcomeEn' then welcomeEn:=value;
     if target='welcomeRu' then welcomeRu:=value;
     if target='altWelcomeEn' then altWelcomeEn:=value;
     if target='altWelcomeRu' then altWelcomeRu:=value;
     if target='altDate' then altWelcomeForDate:=GetDateFromStr(value);
     LogMsg('Welcome messages: ');
     LogMsg(' EN='+welcomeEn);
     LogMsg(' RU='+welcomeRu);
     LogMsg(' AltEN='+AltWelcomeEn);
     LogMsg(' AltRU='+AltWelcomeRu);
     LogMsg(' AltDate='+FormatDateTime('ddddd t',altWelcomeForDate));
   end;

   result:=FormatResponse(result,false,'text/html');
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 function RequestAdmin(con:integer):UTF8String;
  begin
   AdminPage:=LoadFileAsString('HTML\admin.htm');
   result:=AdminPage;
   EnterCriticalSection(gSect);
   try
    result:=StringReplace(result,'#SERVER_NAME#',SERVER_NAME,[]);
    FillAdminPage(result);
    result:=StringReplace(result,'#STATUS_BLOCK#',BuildStatusBlock,[]);
    result:=StringReplace(result,'#CONNECTIONS_BLOCK#',BuildConnectionsList,[]);
   finally
    LeaveCriticalSection(gSect);
   end;
   result:=FormatResponse(result,false,'text/html');
  end;

 function RequestLog(con:integer):UTF8String;
  const
   checked:array[boolean] of UTF8String=('','checked');
  var
   dateFrom,dateTo:TDateTime;
   sa:StringArr;
   minLevel,msgCount,msgCount1,memUse:integer;
   st:UTF8String;
  begin
   st:=param(con,'token');
   if st<>'' then begin
    if st<>controlToken then begin
      result:=FormatError('403 Forbidden','Log');
      exit;
    end;
    minLogMemLevel:=StrToIntDef(Param(con,'memlog'),minLogMemLevel);
    minLogFileLevel:=StrToIntDef(Param(con,'filelog'),minLogFileLevel);
    st:=Param(con,'groups');
    while length(st)<10 do st:=st+'0';
    LOG_HTTP:=st[1]<>'0';
    LOG_SQL:=st[2]<>'0';
    LOG_TASKS:=st[3]<>'0';
    st:=Format('Log levels set to %d/%d %d%d%d',[minLogMemLevel,minLogFileLevel,byte(LOG_HTTP),byte(LOG_SQL),byte(LOG_TASKS)]);
    LogMsg(st,logImportant);
    result:=FormatResponse('Success!'#13#10+st,false,'text/html');
    exit;
   end;
   minLevel:=StrToIntDef(Param(con,'minLevel'),-1);
   if minLevel=-1 then begin
    st:=LoadFileAsString('HTML\log.htm');
    st:=StringReplace(st,'#MANAGEMEMLOG#',IntToStr(minLogMemLevel),[]);
    st:=StringReplace(st,'#MANAGEFILELOG#',IntToStr(minLogFileLevel),[]);
    memuse:=LogMemUsage(msgCount,msgCount1);
    st:=StringReplace(st,'#LOG_INFO#',Format('Messages: %d<br> non-debug: %d<br>Used memory: %s',
      [msgCount,msgCount1,SizeToStr(MemUse)]),[]);
    st:=StringReplace(st,'#DATE_FROM#',FormatDateTime('dd.mm.yy hh:nn',NowGMT-10/1440),[]); // last 10 min
    st:=StringReplace(st,'#DATE_TO#',FormatDateTime('dd.mm.yy hh:nn',NowGMT+8/24),[]);

    st:=StringReplace(st,'#LOG1#',checked[LOG_HTTP],[]);
    st:=StringReplace(st,'#LOG2#',checked[LOG_SQL],[]);
    st:=StringReplace(st,'#LOG3#',checked[LOG_TASKS],[]);

    result:=FormatResponse(st,false,'text/html');
    exit;
   end;

   DateTo:=GetDateFromStr(Param(con,'dateTo'),nowGMT+1);
   DateFrom:=GetDateFromStr(Param(con,'dateFrom'),DateTo-10*MINUTE);
   sa:=FetchLog(dateFrom,dateTo,minLevel);
   if length(sa)=0 then
    result:=FormatResponse('Log empty...',false,'text/plain')
   else
    result:=FormatResponse(join(sa,#0),false,'text/plain');
  end;

 function LoginAllowed:boolean;
  begin
   result:=true;
   if uCnt>round(high(users)*0.75) then result:=false; // Запрещен логин, если в резерве осталось менее 25%
  end;   

 // 10 раз в секунду
 procedure onTimer;
  var
   i:integer;
   t:int64;
  begin
   try
   // Удаление юзеров по таймауту
   t:=myTickCount;
   for i:=1 to MAX_USERS do
    if (users[i]<>nil) and (t>users[i].timeOut) then begin
     if users[i].connected>0 then continue; // Never delete playing user!
     LogMsg('WARN: user timeout %d (%s)',[i,users[i].name],logWarn);
     DeleteUser(i,'Timeout');
    end;
   // Удаление временных юзеров
   for i:=1 to High(tempUsers) do
    if (tempUsers[i]<>nil) and (t>tempUsers[i].timeOut) then begin
     LogMsg('Temp user timeout '+inttostr(10000+i),logInfo);
     DeleteUser(tempUsers[i].userID);
    end;
   except
    on e:exception do LogMsg('Error in onTimer: '+ExceptionMsg(e),logError);
   end;
  end;  

end.

