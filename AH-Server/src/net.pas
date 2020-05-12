// Универсальная сетевая часть сервера: реализация HTTP на overlapped-сокетов TCP/IP
// Copyright (C) Ivan Polyacov, ivan@apus-software.com, cooler@tut.by
{$R+}
unit net;
interface
 type
  // аттрибуты соединения
  TConAttr=(caIP,           // IP-адрес
            caCountry);     // Страна, соответствующая IP

  // состояние соединения
  TConStatus=(csNone=0,
              csReading=1,   // идет чтение из сети (ожидание) входящего запроса
              csWaiting=2,   // ждем когда будет готов ответ на запрос
              csWriting=3,   // идет запись (отправка в сеть) ответа
              csClosing=4);  // соединение нуждается в закрытии

  TConInfo=record
   ID:integer;
   cometUserID:cardinal; // если соединение ожидает данных для юзера - здесь userID
   remIP:cardinal;
   remPort:word;
   clientType:byte; // 0 - browser
   country:string[3];
   status:TConStatus;
   keepAlive:boolean;
   opened,lastRequestTime:TDateTime;
   timeout:integer;
  end;
 TConInfoArray=array of TConInfo; 

 var
  loopCounter:int64;
  netThreadTimestamp:TDateTime;
  acceptIncomingMessages:boolean=true; // разрешить входящие запросы

 procedure StartNetwork;
 procedure DoneNetwork;

 function FormatResponse(body:UTF8String;dontCompress:boolean=false;mime:UTF8String='';cacheControl:UTF8String=''):UTF8String;
 function FormatError(status,query:UTF8String):UTF8String;

 // записать данные сообщения в исходящий буфер соединения (либо отправить)
 // msg - без заголовков! (может добавляться к уже накопленным сообщениям)
 procedure SendMsg(con:integer;msg:UTF8String;urgency:byte=0);

 // Получить параметр запроса, который обрабатывается в соединении con по его имени
 // idx желательно получать через TConnection.GetTarget
 function Param(CRID:integer;name:UTF8String):UTF8String;

 // Получить cookie запроса, который обрабатывается в соединении con по его имени
 // idx желательно получать через TConnection.GetTarget
 function Cookie(CRID:integer;name:UTF8String):UTF8String;

 // Возвращает запрашиваемый аттрибут соединения по его индексу
 function GetConnAttr(con:integer;attr:TConAttr):UTF8String;

 function GetConnInfo(con:integer):TConInfo;

 // Увеличивает счетчик бана по IP
 procedure UseIP(con:integer;value:integer);

 function GetConnectionsList:TConInfoArray;
 function GetConCount:integer;
 procedure CheckConIndex(var con:integer);

 procedure CloseUserConnections(userID:integer);

implementation
 uses windows,SysUtils,classes,logging,WinSock2,MyServis,structs,globals,
   GeoIP,serverLogic,customLogic,workers, gameData,ZLibEx;
 const
  ERR400 = '400 Bad request ';
  ERR403 = '403 Forbidden ';
  ERR404 = '404 Not Found ';  
  ERR500 = '500 Internal Server Error ';
  ERR503 = '503 Service Unavailable ';

 type
  TNetworkThread=class(TThread)
    procedure Execute; override;
  end;

  TConnection=record
   selfID:integer;    // ID данного соединения
   socket:TSocket;
   cometUserID:integer; // если соединение ожидает данных для юзера - здесь userID
   remIP:cardinal;
   remPort:word;
   country:string[3];
   status:TConStatus;
   keepAlive:boolean;
   inBuf:UTF8String; // буфер для входящих данных
   inPos:integer; // текущая позиция - номер первого незанятого байта
   headersParsed:boolean; // заголовки были получены и обработаны?
   bodySize,bodyPos:integer; // размер и расположение тела (для запроса POST)
   requestRnd:byte; // случайное число, обновляющееся с каждым новым запросом
   rTypeGet:boolean; // тип запроса
   rURI:UTF8String; // что запрашивается
   query:UTF8String; // часть запроса после '?'
   contentType:UTF8String; // тип тела запроса POST
   body:UTF8String; // тело запроса (POST)
   userAgent:UTF8String;
   cookies:UTF8String; // куки из заголовка
   dontCompress:boolean;
   outBuf:UTF8String;  // исходящие данные
   overlapped:TOverlapped;
   opened,lastRequestTime:TDateTime;
   timeOut:int64; // момент после которого нужно закрыть соединение по таймауту (MyTickCount)
   closeReason:byte; // 1 - not keep-alive, 2 - receive error, 3 - error,  5 - graceful termination, 7 - закрыто сервером за ненадобностью
   parNames,parValues:AStringArr;
   function RequestReceived(bytesReceived:integer):boolean;
   function ParseHeaders(size:integer):boolean; // возвращает false если запрос некорректный
   procedure HandleRequest;
   procedure SendResponse(context:integer=0);
   procedure ExtractParameters; // заполняет массивы имен и значений параметров
   procedure HandleLogin;
   procedure HandleLogout;
   procedure HandleCheckValue;
   procedure HandleNewAcc;
   procedure HandleUserMsgs(userID,serial:integer;sign:UTF8String);
   procedure HandleCometRequest(userID:integer;serial:cardinal;sign:UTF8String);
   function Param(name:UTF8String):UTF8String;
   function GetCRID:cardinal; // Target текущего запроса
   procedure PrepareForNextRequest;
   function FormatError(status:UTF8String):UTF8String;
   function GetInfo:TConInfo;
  end;

  TStatistics=record
   sentBytes,receivedBytes:int64;
   requests,connections:int64;
  end;

{  TBanItem=record
   ip:cardinal;
   value:integer;
  end;}

  TBadIP=record
   ip:cardinal;
   errors:integer;
  end;
 const
  logError=logging.logError;

 var
  netThread:TNetworkThread;
  //crSect:TMyCriticalSection;
  sock:TSocket;
  local_IP:cardinal=INADDR_ANY; // localhost

  // Сокеты подключений клиентов
  connections:array[1..MAX_CONNECTIONS_LIMIT] of TConnection;
  // list of free connection indices
//  freeCon:array[1..MAX_CONNECTIONS_LIMIT] of integer;
//  conCount:integer=0; // кол-во занятых соединений

{  // список соединений, в которых есть данные для отправки
  notifications:array[1..MAX_CONNECTIONS_LIMIT] of integer;
  nCount:integer;}

//  totalUrgency:integer;
  event:THandle; // событие, связанное с выполнением какой-либо сетевой задачи 

  lastSecond,lastMinute,lastHour,lastDay:integer; // для таймера
  firstTimer:boolean=true;
  
  // Statistics
//  stat:TStatistics;

  // время до сброса лога
  timeToFlush:integer;

  // Temporary ban list
  // Принцип работы: IP -> значение
  // С каждым запросом значение растёт, с каждым ошибочным запросом значение растет сильно
  // При достижении критического уровня (100) соединение закрывается, новые соединения с этого IP не принимаются
  // Раз в секунду значение уменьшается на 10
  banlist:array[0..$3FFFFF] of byte; // 4Mb table

  badIP:array[0..7] of TBadIP; // проблемные IP - на такие сообщения отправляются чаще

 function IPHash(ip:cardinal):cardinal; inline;
  begin
   result:=((ip shr 12) xor ip) and $3FFFFF;
  end;

 procedure UseIP(con:integer;value:integer);
  var
   ip:cardinal;
  begin
   ip:=connections[con and $FFFF].remIP;
   ip:=IPhash(ip);
   value:=banlist[ip]+value;
   if value<0 then value:=0;
   if value>250 then value:=250;
   banlist[ip]:=value;
  end;

 procedure MarkIPAsBad(ip:cardinal);
  var
   i:integer;
  begin
   for i:=0 to high(badIP) do
    if badIP[i].ip=ip then begin
     inc(badIP[i].errors);
     if badIP[i].errors=4 then LogMsg('IP '+IpToStr(ip)+' reached 4 errors',logDebug);
     exit;
    end;
   for i:=high(badIP) downto 1 do
    badIP[i]:=badIP[i-1];
   badIP[0].ip:=ip;
   badIP[0].errors:=1; 
  end;

 function GetIPErrors(ip:cardinal):integer;
  var
   i:integer;
  begin
   result:=0;
   for i:=0 to high(badIP) do
    if badIP[i].ip=ip then result:=badIP[i].errors;
  end;

 function connectionstr(idx:integer):UTF8String;
  begin
   with connections[idx] do
    result:=inttostr(idx)+' '+IpToStr(remIP)+':'+inttostr(remPort);
  end;

 // Format UTF8String with HTTP body (skip headers) in printable form
 function DumpData(buf:PByte;size:integer):UTF8String;
  var
   c:integer;
   hdr:string[120];
  begin
   c:=min2(size,120);
   SetLength(hdr,c);
   move(buf^,hdr[1],c);
   if pos('deflate'#13#10,hdr)>0 then begin
    result:='<compressed_data>'; exit;
   end;
   c:=0;
   while size>0 do begin
    if buf^ in [10,13] then inc(c)
     else c:=0;
    inc(buf); dec(size);
    if c=4 then break;
   end;
   size:=min2(size,100);
   if size=0 then begin
    result:='<empty>'; exit;
   end;
   SetLength(result,size);
   move(buf^,result[1],size);
   result:=PrintableStr(result);
  end;

 function GetConnectionsList:TConInfoArray;
  var
   i,cnt:integer;
  begin
   cnt:=0;
   EnterCriticalSection(gSect);
   try
    SetLength(result,high(connections));
    for i:=1 to high(connections) do
     if connections[i].status<>csNone then begin
      result[cnt]:=connections[i].GetInfo;
      inc(cnt);
     end;
   finally
    LeaveCriticalSection(gSect);
   end;
   SetLength(result,cnt);
  end;

 function GetConCount:integer;
  var
   i:integer;
  begin
   result:=0;
   for i:=1 to MAX_CONNECTIONS do
    if connections[i].status<>csNone then inc(result);
//    result:=conCount;
  end;  

 procedure CheckConIndex(var con:integer);
  var
   rbyte:byte;
  begin
   rByte:=con shr 16;
   con:=con and $FFFF;
   if rByte=0 then rByte:=connections[con].requestRnd;
   if (con<1) or (con>High(connections)) then exit;
   if (connections[con].status<>csWaiting) or
    (connections[con].requestRnd<>rByte) then
    raise EWarning.Create('Connection is in wrong state (wrong ID?)');
  end;

 function Param(CRID:integer;name:UTF8String):UTF8String;
  begin
   result:='';
   CheckConIndex(CRID);
   result:=connections[CRID].Param(name);
  end;

 function Cookie(CRID:integer;name:UTF8String):UTF8String;
  var
   i,p:integer;
   cookies:AStringArr;
   cname:UTF8String;
  begin
   result:='';
   CheckConIndex(CRID);
   cookies:=splitA(';',connections[CRID].cookies);
   name:=UpperCase(name);
   for i:=0 to length(cookies)-1 do begin
    p:=pos('=',cookies[i]);
    if p>0 then begin
     cname:=UpperCase(copy(cookies[i],1,p-1));
     if name=chop(cname) then begin
      result:=copy(cookies[i],p+1,length(cookies[i]));
      exit;
     end;
    end;
   end;
  end;

 function GetConnAttr(con:integer;attr:TConAttr):UTF8String;
  begin
   result:='!ERROR!';
   CheckConIndex(con);
   case attr of
    caIP:result:=IpToStr(connections[con].remIP);
    caCountry:result:=connections[con].country;
   end;
  end;

 function GetConnInfo(con:integer):TConInfo;
  begin
   CheckConIndex(con);
   result:=connections[con].GetInfo;
  end;

 function WSAError(dwError:cardinal):UTF8String;
  begin
   case (dwError mod 1000) of
    4:result:='WSAEINTR';
    9:result:='WSAEBADF';
    13:result:='WSAEACCES';
    14:result:='WSAEFAULT';
    22:result:='WSAEINVAL';
    24:result:='WSAEMFILE';
    35:result:='WSAEWOULDBLOCK';
    36:result:='WSAEINPROGRESS';
    37:result:='WSAEALREADY';
    38:result:='WSAENOTSOCK';
    39:result:='WSAEDESTADDRREQ';
    40:result:='WSAEMSGSIZE';
    41:result:='WSAEPROTOTYPE';
    42:result:='WSAENOPROTOOPT';
    43:result:='WSAEPROTONOSUPPORT';
    44:result:='WSAESOCKTNOSUPPORT';
    45:result:='WSAEOPNOTSUPP';
    46:result:='WSAEPFNOSUPPORT';
    47:result:='WSAEAFNOSUPPORT';
    48:result:='WSAEADDRINUSE';
    49:result:='WSAEADDRNOTAVAIL';
    50:result:='WSAENETDOWN';
    51:result:='WSAENETUNREACH';
    52:result:='WSAENETRESET';
    53:result:='WSAECONNABORTED';
    54:result:='WSAECONNRESET';
    55:result:='WSAENOBUFS';
    56:result:='WSAEISCONN';
    57:result:='WSAENOTCONN';
    58:result:='WSAESHUTDOWN';
    59:result:='WSAETOOMANYREFS';
    60:result:='WSAETIMEDOUT';
    61:result:='WSAECONNREFUSED';
    62:result:='WSAELOOP';
    63:result:='WSAENAMETOOLONG';
    64:result:='WSAEHOSTDOWN';
    65:result:='WSAEHOSTUNREACH';
    66:result:='WSAENOTEMPTY';
    67:result:='WSAEPROCLIM';
    68:result:='WSAEUSERS';
    69:result:='WSAEDQUOT';
    70:result:='WSAESTALE';
    71:result:='WSAEREMOTE';

    91:result:='WSASYSNOTREADY';
    92:result:='WSAVERNOTSUPPORTED';
    93:result:='WSANOTINITIALISED';
    101:result:='WSAEDISCON';
    102:result:='WSAENOMORE';
    103:result:='WSAECANCELLED';
    104:result:='WSAEINVALIDPROCTABLE';
    105:result:='WSAEINVALIDPROVIDER';
    106:result:='WSAEPROVIDERFAILEDINIT';
    107:result:='WSASYSCALLFAILURE';
    108:result:='WSASERVICE_NOT_FOUND';
    109:result:='WSATYPE_NOT_FOUND';
    110:result:='WSA_E_NO_MORE';
    111:result:='WSA_E_CANCELLED';
    112:result:='WSAEREFUSED';
  else result:='UNKNOWN';
   end;
   result:=result+'('+inttostr(dwError)+')';
  end;

 procedure CloseUserConnections(userID:integer);
  var
   i:integer;
  begin
   for i:=1 to high(connections) do
    if (connections[i].socket<>0) and (connections[i].cometUserID=userID) then
     connections[i].status:=csClosing;
  end;


 procedure StartNetwork;
  var
   i:integer;
  begin
   ForceLogMessage('Init GeoIP');
   InitGeoIP;
   ForceLogMessage('Starting network thread');
   for i:=1 to High(connections) do connections[i].selfID:=i;
   event:=CreateEvent(nil,false,false,nil);
   netThread:=TNetworkThread.Create(false);
  end;

 procedure DoneNetwork;
  begin
   netThread.Terminate;
   CloseHandle(event);
  end;

 function FormatError(status,query:UTF8String):UTF8String;
  var
   html,q:UTF8String;
  begin
   q:=query;
   inc(serverStat.httpErrors);
   LogMsg('ERR: '+status+'; Query: '+q,logWarn,lgHTTP);
   html:='<h2>'+status+'</h2>';
   result:='HTTP/1.1 '+status+#13#10+
    'Access-Control-Allow-Origin: *'#13#10+
    'Connection: Close'#13#10+
    'Content-type: text/html'#13#10+
    'Content-Length: '+IntToStr(length(html))+#13#10#13#10+html;
  end;

 function TConnection.FormatError(status:UTF8String):UTF8String;
  var
   q:UTF8String;
  begin
   q:=rURI;
   if query<>'' then q:=q+'?'+copy(query,1,100);
   result:=net.FormatError(status,q);
  end;

 function FormatResponse(body:UTF8String;dontCompress:boolean=false;mime:UTF8String='';cacheControl:UTF8String=''):UTF8String;
  var
   st:UTF8String;
   compress:boolean;
  begin
   if mime='' then mime:='text/plain';
   compress:=(length(body)>2048) and (pos('text/',mime)>0);
   if (mime='dontcompress') or (dontCompress) then begin
    compress:=false;
    mime:='text/plain';
   end;  
   st:='';
   compress:=false;
   if compress then begin
    st:=st+'Content-Encoding: deflate'#13#10;
    ZSendToBrowser(RawByteString(body));
   end;
   if SEND_ACAO then st:=st+'Access-Control-Allow-Origin: *'#13#10;
   if cacheControl='' then st:=st+'Cache-Control: no-cache'#13#10
    else st:=st+'Cache-Control: '+cacheControl+#13#10;

{   if length(body)=0 then
    result:='HTTP/1.1 204 NO CONTENT'#13#10+st+'Connection: Keep-Alive'#13#10#13#10
   else}
   if length(body)=0 then body:='empty';
    result:='HTTP/1.1 200 OK'#13#10+
       'Content-Type: '+mime+'; charset=utf-8'#13#10+
       st+
       'Connection: Keep-Alive'#13#10+
       'Content-Length: '+inttostr(length(body))+#13#10#13#10+
       body;
  end;

  procedure DeleteConnection(i:integer);
   begin
    try
    with connections[i] do begin
     if LOG_HTTP and (minLogMemLevel=0) then
      LogMsg('Conn closed: #'+inttostr(i)+' '+
        ipToStr(remIP)+':'+inttostr(remPort)+' rsn:'+inttostr(closeReason),logDebug,lgHTTP);
     if socket<>0 then
       CloseSocket(socket)
     else
      LogMsg('Socket=0 for closing connection '+inttostr(i),logWarn);
     SetLength(inBuf,0);
     SetLength(outBuf,0);
     socket:=0;
     cometUserID:=0;
     status:=csNone;
    end;
   except
    on e:exception do begin
     ForceLogMessage('Error in DeleteConnection '+inttostr(i)+': '+ExceptionMsg(e));
     sleep(20);
    end;
   end;
   end;

 // Проверяет на допустимость запрос файла.
 // Запрос должен быть безопасным, а файл - существовать.
 // Возвращает путь к файлу либо пустую строку
 function ValidFileRequest(req:UTF8String):UTF8String;
  var
   i,c:integer;
  begin
   result:='';
   if length(req)>60 then exit;
   c:=0;
   for i:=1 to length(req) do begin
    if not (req[i] in ['A'..'Z','a'..'z','0'..'9','/','.','_','-']) then exit;
    if req[i]='.' then inc(c);
    if (req[i]='/') and (c>0) then exit; // точки допустимы только в имени файла 
   end;
   if c>1 then exit; // более 1 точки нельзя
   req:=StringReplace(req,'/','\',[rfReplaceAll]);
   if not FileExists(HomeDir+req) then exit;
   result:=HomeDir+req;
  end;

 // Формирует HTTP-ответ с телом указанного файла
 // Файл должен существовать
 function GetStaticFile(fname:UTF8String):UTF8String;
  var
   f:file;
   st,mimetype,cache:UTF8String;
   i:integer;
  begin
   result:='';
   try
    fname:=UpperCase(fname);
    // Determine MIME type
    mimetype:='';
    for i:=0 to length(mimeTypes)-1 do
     if pos(mimetypes[i].extension,fname)=length(fname)-length(mimetypes[i].extension)+1 then begin
       mimetype:=mimetypes[i].mimeType;
       break;
     end;
    if mimetype='' then begin
     LogMsg('ERR: no MIME type for '+fname,logWarn,lgHTTP);
     exit;
    end;
    // Cache options
    cache:='';
    for i:=0 to length(cacheRules)-1 do
     if pos(cacheRules[i].pattern,fname)>0 then begin
      cache:=cacheRules[i].value; break;
     end;

    assign(f,fname);
    filemode:=fmOpenRead;
    reset(f,1);
    if filesize(f)<=MAX_LOCAL_FILESIZE then begin
     setLength(st,filesize(f));
     blockRead(f,st[1],filesize(f));
    end else
     st:=''; // too large
    close(f);
    result:=FormatResponse(st,false,mimetype,cache);
   except
    on e:exception do LogMsg('ERR: GetStaticFile('+fname+'): '+ExceptionMsg(e),logWarn,lgHTTP);
   end;
   filemode:=fmOpenReadWrite;
  end;

 function TConnection.GetCRID: cardinal;
  begin
   result:=SelfID+requestRnd shl 16;
  end;

 function TConnection.GetInfo: TConInfo;
  begin
   result.ID:=selfID;
   result.cometUserID:=cometUserID;
   result.remIP:=remIP;
   result.remPort:=remPort;
   result.country:=country;
   result.status:=status;
   result.keepAlive:=keepAlive;
   result.opened:=opened;
   result.lastRequestTime:=lastRequestTime;
   result.clientType:=0;
   result.timeout:=round((MyTickCount-timeOut)/1000);
   if pos('ENGINE3_CLIENT',userAgent)>0 then result.clientType:=1;
  end;

procedure TConnection.HandleNewAcc;
  var
   A:UTF8String;
  begin
   A:=param('A');
   AddTask(0,GetCRID,['NEWACC',A]);
  end;

 procedure TConnection.HandleLogin;
  var
   rnd,userID:integer;
   A,B,C,D:UTF8String;
  begin
   rnd:=StrToIntDef(query,0);
   if rnd<>0 then begin
    // Подключение без авторизации
    userID:=CreateUser(true);
    outBuf:=FormatResponse(IntToStr(userID),false,'text/plain');
    exit;
   end else
   if length(parNames)=4 then begin
    A:=param('A');
    UserID:=StrToIntDef(A,0);
    if IsValidUserID(userID) then begin
     if LoginAllowed then begin
      // попытка авторизации
      B:=param('B'); C:=param('C'); D:=param('D');
      AddTask(userID,GetCRID,['LOGIN',B,C,D]);
     end else
      outBuf:=FormatResponse('ERROR: Server does not allow login at this moment, please try again later',false);
    end else
     outBuf:=FormatError(ERR500+'(invalid UID)');
   end else
    if outbuf='' then outBuf:=FormatError(ERR500);
  end;

 procedure TConnection.HandleLogout;
  var
   userID:integer;
   sign,extra:UTF8String;
   i:integer;
  begin
   userID:=StrToIntDef(param('A'),0);
   sign:=UpperCase(param('B'));
   extra:=param('C');
   if extra<>'' then extra:=DecodeHex(extra);
   if IsValidUserID(userID,true) then begin
    if sign<>ShortMD5(inttostr(userID)+users[userid].PwdHash) then begin
     LogMsg('Bad signature ('+sign+') for: '+users[userid].name,logWarn);
     outBuf:=FormatError(ERR403+' (#4 wrong signature)');
     exit;
    end;
    LogMsg('Logout: '+users[userid].name,logNormal);
    DeleteUser(userID,'Logout',extra);
    for i:=1 to high(connections) do
     if connections[i].cometUserID=userID then begin
      connections[i].status:=csClosing;
      connections[i].cometUserID:=0;
      connections[i].closeReason:=6;
      connections[i].keepAlive:=false;
      connections[i].outBuf:='CLOSE';
     end;
   end;
   outBuf:=FormatResponse('',false);
  end;

 procedure TConnection.HandleCheckValue;
  var
   st:UTF8String;
  begin
   st:=param('email');
   if st<>'' then begin
    AddTask(0,GetCRID,['CHECKEMAIL',st]);
    exit;
   end;
   st:=param('name');
   if st<>'' then begin
    AddTask(0,GetCRID,['CHECKNAME',st]);
    exit;
   end;
   outbuf:='';
  end;

 procedure TConnection.HandleUserMsgs(userID,serial:integer;sign:UTF8String);
  var
   i,n,l:integer;
   whole,sign2:UTF8String;
   sa:AStringArr;
  begin
   if not acceptIncomingMessages then begin
    outBuf:=FormatError(ERR503+' (the server is going to be restarted, please retry in a few seconds)');
    exit;
   end;
   with users[userID] do begin
    if sign<>ShortMD5(IntToStr(UserID)+IntToStr(serial)+users[userID].PwdHash) then begin
     outBuf:=FormatError(ERR500+' (#1.1)');
    end else
    if serial<lastPostSerial then begin
     outBuf:=FormatError(ERR500+' (#1.2)');
     LogMsg('Out of order POST request ignored '+IntToStr(serial),logInfo,lgHTTP);
    end
    else
    if serial=lastPostSerial then begin  // Нужно пересмотреть этот код, т.к. смысл POST и GET не соответствует POLL и PUSH
     outBuf:=FormatResponse('IGNORED');
     LogMsg('Duplicated request '+IntToStr(serial),logInfo,lgHTTP);
    end else
    if serial>lastPostSerial then begin
     // Extract incoming messages
     if pos('text/plain',contentType)>0 then begin
      // text mode
      sa:=splitA(#13#10,body);
      for i:=1 to high(sa) do begin
       sa[i]:=Unescape(sa[i]);
{       sa[i]:=StringReplace(sa[i],'\n',#13#10,[rfReplaceAll]);
       sa[i]:=StringReplace(sa[i],'\\','\',[rfReplaceAll]);}
      end;
     end;
     if pos('application/octet-stream',contentType)>0 then begin
      // binary mode
      SetLength(sa,15); // Up to 15 messages per request
      for i:=0 to high(sa) do sa[i]:='';
      n:=0;
      i:=1; // текущая позиция в body
      while i<length(body) do begin
       if n>high(sa) then break;
       l:=byte(body[i]); inc(i);
       if l=255 then begin
        l:=byte(body[i])+byte(body[i+1])*256+byte(body[i+2])*65536;
        inc(i,3);
       end;
       SetLength(sa[n],l);
       if i+l-1<=length(body) then begin
        move(body[i],sa[n][1],l);
        inc(n);
       end;
       inc(i,l);
      end;
      SetLength(sa,n);
     end;
     // Check signature
     whole:='';
     for i:=1 to high(sa) do
      whole:=whole+sa[i];
     sign2:=ShortMD5(whole+PwdHash);
     if sign2<>sa[0] then begin
      LogMsg('Invalid request sign from '+name+' ('+sign2+'): '+whole,logWarn);
      outbuf:=FormatError(ERR500+' (#1.4)');
      exit;
     end;

     // Response
     lastPostSerial:=serial;
     outbuf:=FormatResponse('OK');
     users[userID].timeOut:=MyTickCount+USER_TIMEOUT;

     // Execute
     for i:=1 to high(sa) do
      ExecUserRequest(userID,sa[i]);
    end;
   end;
  end;

 procedure TConnection.HandleCometRequest(UserID:integer;serial:cardinal;sign:UTF8String);
  var
   i,err:integer;
   checkSign:UTF8String;
  begin
   with users[userID] do begin
    checkSign:=ShortMD5(IntToStr(UserID)+IntToStr(serial)+users[userID].PwdHash);
    if sign<>checkSign then begin
     LogMsg('Bad sign from '+users[userid].name+' should be: '+checkSign,logWarn);
     outBuf:=FormatError(ERR403+' (#2 wrong signature)');
    end else
    if serial=lastPollSerial then begin
     LogMsg('Duplicated poll request '+IntToStr(serial),logInfo,lgHTTP);
     if lastPollResponse=UNSENT_RESPONSE then begin
      // ответ еще не был отправлен - поискать другое соединение для юзера
      for i:=1 to high(connections) do
       if connections[i].status<>csNone then
        if (connections[i].cometUserID=userID) and (connections[i].status<>csClosing) then begin
          LogMsg('Closing another poll connection #%d from user %s (%d)',[i,name,userID],logInfo,lgHTTP);
          connections[i].status:=csClosing;
          connections[i].closeReason:=7;
          self.timeout:=connections[i].timeOut;
        end;
       cometUserID:=userID;
     end else
      outBuf:=FormatResponse(lastPollResponse,dontCompress); // already processed
    end
    else
    if serial<lastPollSerial then begin
     outBuf:=FormatResponse('WTF!? '+inttostr(lastPolLSerial)); // already processed
     LogMsg('Invalid serial %d < %d',[serial,lastPollSerial],logNormal,lgHTTP);
    end
    else
    if serial>lastPollSerial then begin
     // отправим исходящие сообщения (если есть) и запомним ответ, либо поставим в ожидание
     users[userid].timeout:=MyTickCount+USER_TIMEOUT;
     lastPollSerial:=serial;
     lastPollResponse:=GetUserMsgs(userID);
     if lastPollResponse<>'' then
      outBuf:=FormatResponse(lastPollResponse,dontCompress)
     else begin
      lastPollResponse:=UNSENT_RESPONSE;
      cometUserID:=userID;
      err:=1+GetIPErrors(remIP);
      if err>4 then err:=4;
      self.timeOut:=MyTickCount+DATA_TIMEOUT div err; // в это время будет отправлен пустой ответ, если только сообщения не поступят раньше
     end;
    end;
   end;
  end;

 function TConnection.Param(name: UTF8String): UTF8String;
  var
   i:integer;
  begin
   result:='';
   name:=lowercase(name);
   for i:=0 to length(parNames)-1 do
    if lowercase(parNames[i])=name then result:=parValues[i];
  end;

 procedure TConnection.ExtractParameters;
  var
   i,c,p:integer;
   pairs:AStringArr;
   ct,boundary,partHdr,partData,st:UTF8String;
   parts:AStringArr;
  begin
   SetLength(parNames,0);
   SetLength(parValues,0);
   if not headersParsed then exit;
   // POST?
   if not rTypeGet then begin
    ct:=LowerCase(contentType);
    if pos('application/x-www-form-urlencoded',ct)>0 then
     query:=body
    else if pos('multipart/form-data;',ct)>0 then begin
     // Parse multipart body
     p:=pos('boundary=',ct);
     boundary:=copy(contentType,p+9,200);
     parts:=SplitA(boundary,body);
     SetLength(parNames,100);
     SetLength(parvalues,100);
     c:=0;
     for i:=0 to length(parts)-1 do begin
      if c>=100 then break;
      p:=pos(#13#10#13#10,parts[i]);
      if p=0 then continue;
      partHdr:=copy(parts[i],1,p-1);
      partData:=copy(parts[i],p+4,length(parts[i])-p-4-3);
      st:=lowercase(partHdr);
      p:=pos('name="',st);
      if p=0 then continue;
      st:=copy(partHdr,p+6,250); // max parameter name
      p:=pos('"',st);
      if p=0 then continue;
      SetLength(st,p-1);
      parNames[c]:=st; // What if " occurs in par name? Maybe URLDecode is needed here...
      parValues[c]:=partData;
      inc(c);
     end;
     SetLength(parNames,c);
     SetLength(parvalues,c);
     exit;
    end;
   end; // POST

   if query<>'' then begin
    // Extract parameters from query UTF8String (GET)
    pairs:=splitA('&',query);
    c:=length(pairs);
    SetLength(parNames,c);
    SetLength(parvalues,c);
    for i:=0 to c-1 do begin
     p:=pos('=',pairs[i]);
     if p>0 then begin
      parNames[i]:=UrlDecode(copy(pairs[i],1,p-1));
      parValues[i]:=UrlDecode(copy(pairs[i],p+1,length(pairs[i])));
     end else begin
      parNames[i]:=UrlDecode(pairs[i]);
      parValues[i]:='TRUE';
     end;
    end;
   end;
  end;

 // Во входящем буфере соединения полностью содержится запрос
 // Нужно его обработать и сформировать ответ в исходящем буфере
 procedure TConnection.HandleRequest;
  var
   i,level:integer;
   req:AStringArr;
   fname:UTF8String;
   uID:integer;
   serial:cardinal;
   params:UTF8String;
  begin
   try
    UseIP(selfID,2);
    inc(serverStat.httpRequests);
    
    if keepAlive then
     timeOut:=MyTickCount+KEEP_ALIVE_TIMEOUT;

    // Разделение запроса на части
    i:=pos('?',rURI);
    if i>0 then begin
     query:=copy(rURI,i+1,length(rURI));
     SetLength(rURI,i-1);
    end else
     query:='';

    if bodySize>0 then body:=copy(inBuf,bodyPos,bodySize);

    ExtractParameters;

    rURI:=UpperCase(rURI);

    // Логирование запросов
    if LOG_HTTP then begin
     params:='';
     for i:=0 to length(parNames)-1 do
      params:=params+parNames[i]+'='+parValues[i]+';';
     if length(params)>100 then SetLength(params,100);
     level:=logInfo;
     if rTypeGet then begin
      if pos('-',rURI) in [2..5] then level:=logDebug;
      LogMsg('Con#'+inttoStr(selfID)+' GET '+rURI+' '+params,level,lgHTTP);
     end else begin
      if pos('text/plain',contentType)>0 then params:=copy(body,1,100);
      if pos('application/octet-stream',contentType)>0 then params:='[Binary data '+inttostr(bodySize)+'b]';
      if pos('-',rURI) in [2..5] then level:=logDebug;
      LogMsg('Con#'+inttoStr(selfID)+' POST '+rURI+' '+params,level,lgHTTP);
     end;
    end;

    // Сперва стандартные запросы
    if rTypeGet then begin
     // GET
     if rURI='CMD' then begin
      AddTask(0,GetCRID,['CMD',param('action'),param('sign'),param('player'),param('p1'),param('p2'),param('p3')]);
      exit;
     end;
     if rURI='LOGIN' then begin
      HandleLogin;
      exit;
     end;
     if rURI='LOGOUT' then begin
      HandleLogout;
      exit;
     end;
     if rURI='CHECKVALUE' then begin // проверка допустимости значений аккаунта
      HandleCheckValue;
      exit;
     end;
     if rURI='GETVERSION' then begin // текущая версия игры
      outBuf:=FormatResponse(GetAllowedVersions,false,'text/plain');
      exit;
     end;
     // Запросы, требующие авторизации
     if (rURI='ADMIN') or (rURI='LOG') then begin
      if (length(accessToken)>3) and (Cookie(selfID,'AHSERVER_TOKEN')=AccessToken) then begin
       if rURI='ADMIN' then begin
        outBuf:=RequestAdmin(GetCRID);
        exit;
       end;
       if rURI='LOG' then begin
        outBuf:=RequestLog(GetCRID);
        exit;
       end;
      end else begin
       UseIP(selfID,30);
       outBuf:=FormatResponse(StringReplace(loginPage,'#SERVER_NAME#',SERVER_NAME,[rfReplaceAll]),false,'text/html');
       exit;
      end;
     end;
    end else begin
     // POST
     if rURI='NEWACC' then begin
      HandleNewAcc;
      exit;
     end;
     if (length(accessToken)>3) and
        ((Cookie(selfID,'AHSERVER_TOKEN')=AccessToken) or (param('AHSERVER_TOKEN')=AccessToken)) then begin
      // Требуется авторизация через cookie
      if rURI='ADMINCMD' then begin
       outBuf:=RequestAdminCmd(GetCRID);
       exit;
      end;
      if rURI='CONTROL' then begin
       outBuf:=FormatResponse(LoadFileAsString('HTML\control.htm'),false,'text/html');
       exit;
      end;
     end;
    end;

    // Отправка/получение сообщений залогинившегося юзера?
    i:=pos('-',rURI);
    if i>0 then begin
     req:=splitA('-',rURI);
     uID:=StrToIntDef(req[0],0);
     serial:=StrToIntDef(req[1],0);
     if IsValidUserID(uID,true) and (length(req)=3) then begin
      if bodySize>0 then
       HandleUserMsgs(uID,serial,req[2]) // приём входящих сообщений юзера
      else
       HandleCometRequest(uID,serial,req[2]); // запрос исходящих сообщений

      exit;
     end;
    end;

    // если ни один вариант не подошел - попробуем запрос статического файла
    if HomeDir<>'' then begin
     fname:=ValidFileRequest(rURI);
     if fname<>'' then outBuf:=GetStaticFile(fname)
      else outBuf:=FormatError('404 Not Found');
     if outBuf='' then outBuf:=FormatError('500 Internal Server Error');
     exit;
    end;

    // если ничего не подошло - 404
    outBuf:=FormatError('404 Not Found');
    LogMsg('WARN! Request not handled',logNormal,lgHTTP);
   except
    on e:exception do begin
     outBuf:=FormatError(ERR500+'(HandleRequest)');
     LogMsg('Error: HandleRequest '+rURI+':'+ExceptionMsg(e),logError,lgHTTP);
    end;
   end;
  end;

procedure StartRecv(idx:integer); forward;

procedure onSent(const dwError,cbTransferred:DWORD;
        const lpOverlapped:LPWSAOVERLAPPED; const dwFlags:DWORD); stdcall;
 var
  idx:integer;
 begin
  idx:=-1;
  if dwError<>0 then LogMsg('onSent error: '+WSAError(dwError),logNormal,lgHTTP);
  EnterCriticalSection(gSect);
  try
   try
   idx:=lpOverlapped.hEvent;
   if (idx<1) or (idx>MAX_CONNECTIONS) then begin
    LogMsg('ERROR2: invalid idx=#'+inttostr(idx),logNormal,lgHTTP);
    exit;
   end;
   inc(serverStat.sentBytes,cbTransferred);
   if connections[idx].status in [csNone,csClosing] then exit;
   with connections[idx] do
    if keepAlive and (banList[IPhash(connections[idx].remIP)]<=80) then begin
     connections[idx].PrepareForNextRequest;
     StartRecv(idx); // прием очередного запроса
    end else begin
     if banList[IPhash(connections[idx].remIP)]>80 then inc(serverStat.ipBanned);
     if LOG_HTTP then begin
      if keepAlive then
       LogMsg('Closing connection '+inttostr(idx)+' rsn 8'+
         inttostr(banList[IPhash(connections[idx].remIP)]),logInfo,lgHTTP)
      else
       if (minLogMemLevel=0) then
        LogMsg('Closing connection '+inttostr(idx)+' rsn 1',logDebug,lgHTTP);
     end;
     status:=csClosing;
     closeReason:=1; // not keep-alive
    end;
   except
    on e:exception do LogMsg('onSent error (idx=#'+inttostr(idx)+'): '+ExceptionMsg(e),logWarn,lgHTTP);
   end;
  finally
   LeaveCriticalSection(gSect);
  end;
 end;

procedure TConnection.SendResponse(context:integer=0);
 var
  buf:WSAbuf;
  size:cardinal;
  res:integer;
 begin
  inPos:=1; // сперва очистим входящий буфер
  if length(outBuf)=0 then begin
   LogMsg('Trying to send 0 bytes',logWarn,lgHTTP);
   exit;
  end;
  headersParsed:=false;
  buf.len:=length(outBuf);
  buf.buf:=@outBuf[1];
  overlapped.hEvent:=selfID;
  status:=csWriting;
  res:=WSASend(socket,@buf,1,size,0,@overlapped,onSent);
  if res<>0 then begin
   res:=WSAGetLastError;
   if res<>WSA_IO_PENDING then begin
    LogMsg('WSAsend code='+WSAError(res)+' on con#'+inttostr(selfID),logNormal,lgHTTP);
    status:=csClosing;
    exit;
   end;
  end;
  if LOG_HTTP and (minLogMemLevel=0) then begin
   LogMsg('SR'+inttostr(context)+' Sent to con#'+inttostr(selfID)+
     ': '+inttostr(size)+' bytes: '+DumpData(PByte(buf.buf),size),logDebug,lgHTTP);
  end;
 end;

// Парсит заголовки запроса
// - если это корректный запрос POST - определяет размер тела для чтения
// - если корректный запрос GET - устанавливает размер тела в 0
// - если запрос некорректный - формирует ошибку, устанавливает keepAlive=false, возвращает false
function TConnection.ParseHeaders(size:integer):boolean;
 var
  i,p:integer;
  req:AStringArr;
  par,value:UTF8String;
  headers:UTF8String;
 begin
  result:=false;
  headers:=copy(inBuf,1,size);
  i:=pos(#13#10,headers);
  req:=splitA(' ',copy(inBuf,1,i-1));
  keepAlive:=false;
  bodySize:=0;
  // запрос должен содержать 3 поля
  if (length(req)<>3) then begin
   outBuf:=FormatError(ERR400);
   result:=true;   exit;
  end;
  // первое поле должно быть GET либо POST
  req[0]:=UpperCase(req[0]);
  if (req[0]<>'GET') and (req[0]<>'POST') then begin
   outBuf:=FormatError('405 Method Not Allowed'#13#10'Allow: GET,POST');
   result:=true;   exit;
  end;
  rTypeGet:=req[0]='GET';
  // проверка версии HTTP пока опущена...
  // запрос должен начинаться с / и содержать хотя бы 1 символ после слэша
  rURI:=req[1];
  if (length(rURI)<2) or (rURI[1]<>'/') then begin
   outBuf:=FormatError(ERR404);
   result:=true; exit;
  end;
  delete(rURI,1,1); // Remove '/'
  bodyPos:=size+5;

//  if not rTypeGet then begin  // POST?
   req:=splitA(#13#10,headers);
   for i:=1 to length(req)-1 do begin
    p:=pos(':',req[i]);
    if p=0 then continue;
    par:=UpperCase(copy(req[i],1,p));
    value:=copy(req[i],p+1,length(req[i]));
    // размер тела запроса
    if par='CONTENT-LENGTH:' then begin
     bodySize:=StrToIntDef(value,0);
     if bodyPos+bodySize>=Length(inBuf) then begin
      outBuf:=FormatError('413 Request Entity Too Large');
      result:=true; exit;
     end;
    end;
    // тип содержимого тела
    if par='CONTENT-TYPE:' then contentType:=lowercase(value);
    if par='USER-AGENT:' then userAgent:=value;
    if par='COOKIE:' then cookies:=value;
    if par='X-DONT-COMPRESS:' then dontCompress:=true;
   end;
//  end;
  headersParsed:=true;
  keepAlive:=true;
  result:=true;
 end;

procedure TConnection.PrepareForNextRequest;
 begin
  status:=csReading;
  outBuf:='';
  body:='';
  cookies:='';
  dontCompress:=false;
  userAgent:='';
  query:='';
  cometUserID:=0;
  requestRnd:=1+random(255);
  if keepAlive then
   timeOut:=MyTickCount+KEEP_ALIVE_TIMEOUT
  else
   timeOut:=MyTickCount+REQUEST_TIMEOUT;
  inPos:=1;
  headersParsed:=false;
  SetLength(parNames,0);
  SetLength(parValues,0);
 end;

// Проверяет наличие полностью принятого запроса во входящем буфере
// Возможные варианты:
// - запрос еще не получен, необходим дальнейший прием данных - выставляем csReading
// - получено нечто, что не может быть корректным запросом - дальнейший прием не имеет смысла - csClosing
// - запрос получен полностью и может быть обработан
function TConnection.RequestReceived(bytesReceived:integer):boolean;
 var
  i,crlf:integer;
 begin
  result:=false;
  status:=csReading;
  if inPos<12 then exit; // слишком мало данных принято
  if not headersParsed then begin
   // поиск \n\n
   i:=inPos-bytesReceived-4;
   if i<1 then i:=1;
   crlf:=0;
   while i<=inPos-4 do begin
    if inBuf[i]=#13 then
     if inBuf[i+1]=#10 then
      if inBuf[i+2]=#13 then
       if inBuf[i+3]=#10 then begin
        crlf:=i; break;
       end;
    inc(i);
    end;
   if (crlf=0) or (crlf>3000) then begin
    if (inPos>3000) or (crlf>3000) then status:=csClosing; // получена какая-то хрень!
    exit;
   end;
   // Парсинг заголовков
   if ParseHeaders(crlf-1) then begin
    if rTypeGet then result:=true;
    if inPos>=bodySize+bodyPos then result:=true;
   end;
  end else begin
   // Заголовки уже обработаны - нужно лишь дождаться загрузки всего запроса
   if inPos>=bodySize+bodyPos then result:=true;
  end;
  if result then inc(requestRnd);
 end;

procedure onReceive(const dwError,cbTransferred:DWORD;
        const lpOverlapped:LPWSAOVERLAPPED; const dwFlags:DWORD); stdcall;
 var
  idx:integer;
 begin
  //LogMsg('onRecv: '+inttostr(dwError)+' '+inttostr(cbTransferred));
  idx:=-1;
  EnterCriticalSection(gSect);
  try
   try
   idx:=lpOverlapped.hEvent;
   if (idx<1) or (idx>MAX_CONNECTIONS) then begin
    LogMsg('ERROR: invalid idx=#'+inttostr(idx),logNormal,lgHTTP);
    exit;
   end;
//  LogMsg(inttostr(idx)+' Received: '+inttostr(cbTransferred)+#13#10+connections[idx].inBuf);
   with connections[idx] do begin
    if status=csNone then exit; // соединение уже удалено
    if status=csClosing then exit; // соединение уже закрывается - нечего тут делать
    if dwerror<>0 then LogMsg('onRecv error '+WSAError(dwError)+' in con #'+inttostr(idx),logNormal,lgHTTP);
    if (dwError=WSAENOTCONN) or
       (dwError=WSAEDISCON) or
       (dwError=WSAECONNABORTED) or
       (dwError=WSAECONNRESET) or
       ((dwError=0) and (cbTransferred=0)) then begin // gracefull closed connection?
     if LOG_HTTP and (minLogMemLevel=0) then
      LogMsg('Closing connection '+inttostr(idx)+' rsn 2 '+WSAError(dwError),logDebug,lgHTTP);
     status:=csClosing;
     closeReason:=2; // receive error
     if dwError=WSAECONNRESET then MarkIPAsBad(remIP);
     exit;
    end;
    inc(inPos,cbTransferred);
    inc(serverStat.recvBytes,cbTransferred);
    // проверим, поступил ли запрос полностью
    if RequestReceived(cbTransferred) then begin
      lastRequestTime:=now;
      status:=csWaiting;
      if outBuf='' then HandleRequest;
      // если сформирован ответ - отправить его
      if outBuf<>'' then SendResponse(1);
    end else begin
     if status=csReading then StartRecv(idx); // слишком мало данных, продолжаем прием
    // if outBuf<>'' then SendResponse; - что это за хрень!??
    end;
   end;
   except
    on e:exception do LogMsg('onReceive error (con#'+inttostr(idx)+'): '+ExceptionMsg(e),logWarn,lgHTTP);
   end;
  finally
   LeaveCriticalSection(gSect);
  end;
 end;

// Инициируем прием/чтение данных из сокета соединения
procedure StartRecv(idx:integer);
 var
  buf:WSAbuf;
  size:cardinal;
  res:integer;
  flags:cardinal;
 begin
  with connections[idx] do begin
   if status in [csClosing,csNone] then begin
    LogMsg('Can''t read from closed con#'+inttostr(idx),logInfo);
    exit;
   end;
   buf.len:=length(inBuf)-inPos+1; // столько байтов еще можно прочитать в буфер
   buf.buf:=@inBuf[inPos]; // тут range check error!
   fillchar(overlapped,sizeof(overlapped),0);
   overlapped.hEvent:=idx;
   flags:=0;
   res:=WSArecv(socket,@buf,1,size,flags,@overlapped,@onReceive);
   if (res=0) and (size=0) then begin
    status:=csClosing;
    closeReason:=5; // graceful termination initiated by remote side
    LogMsg('Closing connection '+inttostr(idx)+' rsn=5',logInfo,lgHTTP);
    exit;
   end;
   if res=SOCKET_ERROR then begin
    res:=WSAGetLastError;
    if (res=WSAENOTCONN) or
       (res=WSAEDISCON) or
       (res=WSAECONNABORTED) or
       (res=WSAECONNRESET) then begin
         LogMsg('Closing connection '+inttostr(idx)+' rsn=3',logInfo,lgHTTP);
         status:=csClosing;
         closeReason:=3; // error
       end;
   end;
  end;
 end;

{ procedure PostNotification(idx:integer;urgency:byte);
  begin
   if nCount>=MAX_CONNECTIONS_LIMIT then
    raise EError.Create('Notification buffer overflow!');
   inc(nCount);
   notifications[nCount]:=idx;
   inc(totalUrgency,urgency);
   if totalUrgency>MAX_URGENCY then
    SetEvent(event);
  end;}

 procedure SendMsg(con:integer;msg:UTF8String;urgency:byte=0);
  var
   rnd:byte;
  begin
   ASSERT(msg<>'','Empty msg in SendMsg');
   EnterCriticalSection(gSect);
   try
    rnd:=(con shr 16) and $FF;
    con:=con and $FFFF;
    if (con<1) or (con>High(connections)) then
     raise EError.Create('SendMsg: wrong idx');
    with connections[con] do begin
     if status<>csWaiting then begin
      LogMsg('SendMsg: status<>waiting',logWarn);
      exit;
     end;
     if (rnd>0) and (rnd<>requestRnd) then begin
      LogMsg('SendMsg: wrong request rnd',logWarn);
      exit;
     end;
     if outBuf<>'' then outBuf:=outBuf+#13#10+msg
      else outBuf:=msg;

//     PostNotification(con,urgency);
    end;
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 // Callback
 function AllowConnection(lpCallerId,lpCallerData:LPWSABUF;
                          lpSQOS,lpGQOS:LPQOS;
                          lpCalleeId,lpCalleeData:LPWSABUF;
                          g:GROUP; dwCallbackData:DWORD):integer; stdcall;
  var
   addr:sockaddr_in;
   ip:cardinal;
  begin
   result:=CF_ACCEPT;
   if (lpCallerID<>nil) and (lpCallerID.len=16) then begin
    move(lpCallerID.buf^,addr,sizeof(addr));
    ip:=addr.sin_addr.S_addr;
    if banlist[IPhash(ip)]>40 then begin
     result:=CF_REJECT; // 5 секунд после принудительного разрыва новое соединение установить нельзя
     inc(serverStat.connDenied);
     LogMsg('Connection not allowed from '+IpToStr(ip),logInfo,lgHTTP);
     exit;
    end;
   end;
  end;

{ TNetworkThread }

procedure TNetworkThread.Execute;
var
 WSAdata:TWSAData;
 i,j,res,addrLen:integer;
 addr:sockaddr_in;
 newSock:TSocket;
 arg:cardinal;
 time:TSystemTime;
 t:int64;
begin
 RegisterThread('Net');
 ForceLogMessage('Hello from NET thread');
 // Initialization
// conCount:=0;
// for i:=1 to high(freeCon) do freeCon[i]:=i;

 res:=WSAStartup($0202, WSAData);
 if res<>0 then raise EFatalError.Create('WSA Init failure: '+inttostr(res));
 try
  // create main socket
  Sock:=socket(PF_INET,SOCK_STREAM,IPPROTO_IP);
  if Sock=INVALID_SOCKET then
   raise EFatalError.Create('Socket creation failure: '+inttostr(WSAGetLastError));
  // bind
  addr.sin_family:=PF_INET;
  addr.sin_port:=htons(HTTP_PORT);
  addr.sin_addr.S_addr:=htonl(local_IP);
  ForceLogMessage(Format('Binding to %s:%d',[IpToStr(local_IP),HTTP_PORT]));

  res:=bind(sock,@addr,sizeof(addr));
  if res<>0 then raise EFatalError.Create('Bind failed: '+inttostr(WSAGetLastError));

  arg:=1;
  if ioctlsocket(sock,FIONBIO,arg)<>0 then
   raise EFatalError.Create('Cannot make non-blocking socket');

  res:=listen(sock,SOMAXCONN);
  if res<>0 then raise EError.Create('Listen returned error '+inttostr(WSAGetLastError));
 except
  on e:exception do begin
   ForceLogMessage('Error in NetThread init: '+ExceptionMsg(e));
   exit;
  end;
 end;
 ForceLogMessage('Starting NET loop...');
 // Main loop
 repeat
  try
   EnterCriticalSection(gSect);
   try
   inc(loopCounter);

   try
    // Send out data
    j:=0;
    for i:=1 to MAX_CONNECTIONS do
     with connections[i] do
      if (status=csWaiting) then begin
       if (cometUserID>0) and (IsValidUserID(cometUserID,true)) and (outBuf='') then begin
        if users[cometUserID].sendASAP then
         outbuf:=GetUserMsgs(cometUserID);
       end;
       if outBuf<>'' then begin
        users[cometUserID].lastPollResponse:=outBuf;
        outBuf:=FormatResponse(outBuf,dontCompress);
        inc(j,200+length(outBuf));
        SendResponse(3);
        if j>10000 then break; // слишком много сразу отправлять не будем
       end;
      end;
   except
    on e:exception do begin
     ForceLogMessage('NET Error 1: '+ExceptionMsg(e));
     sleep(100);
    end;
   end;

   try
    // Check for incoming connections
    if {conCount<MAX_CONNECTIONS}true then begin
     addrLen:=sizeof(addr);
     newSock:=WSAAccept(sock,@addr,@addrlen,AllowConnection,0);
 //    newSock:=accept(sock,@addr,@addrLen);
     if newSock=INVALID_SOCKET then begin
      res:=WSAGetLastError;
      if (res<>WSAEWOULDBLOCK) and (res<>WSAECONNREFUSED) then
        ForceLogmessage('ACCEPT failed with '+inttostr(res));
     end else begin
      // new connection established
//      inc(conCount);
//      i:=freeCon[conCount];
      i:=0;
      for j:=1 to MAX_CONNECTIONS do
       if connections[j].status=csNone then begin
        i:=j; break;
       end;
      if i>0 then
       with connections[i] do begin
        ASSERT((status=csNone) and (socket=0),'New connection isn''t free! '+inttostr(ord(status))+' '+inttostr(socket));
        socket:=newSock;
        remIP:=cardinal(addr.sin_addr.S_addr);
        remPort:=addr.sin_port;
        country:=GetCountryByIP(remIP);
        opened:=Now; lastRequestTime:=0;
        closeReason:=0;
        setLength(inBuf,INBUF_SIZE);
        PrepareForNextRequest;
        keepAlive:=true; // устанавливается ПОСЛЕ PrepareForNext... для правильного выбора таймаута
        StartRecv(i);
        if LOG_HTTP and (minLogMemLevel=0) then
          LogMsg('Conn accepted: #'+connectionstr(i),logDebug,lgHTTP);
        inc(serverStat.httpConnections);
       end
      else
       CloseSocket(newSock);
     end;
    end;
   except
    on e:exception do begin
     ForceLogMessage('NET Error 2: '+ExceptionMsg(e));
     sleep(100);
    end;
   end;

   try
    // Timer (10 times per second)
    GetSystemTime(time);
    if firstTimer then begin
     lastDay:=time.wDay;
     lastHour:=time.wHour;
     firstTimer:=false;
    end;

    // Если что-то надо делать ежеминутно
    i:=time.wMinute;
    if i<>lastMinute then begin
     lastMinute:=i;
     if lastMinute mod 10=1 then AddTask(0,0,['DB_MAINTENANCE']); // Раз в 10 минут обслуживать базу данных
     MarkIPAsBad(i); // вытеснение проблемных IP со временем
    end;

    // Если что-то надо делать раз в час
    i:=time.wHour;
    if i<>lastHour then begin
     lastHour:=i;
     AddTask(0,0,['HOURLY_MAINTENANCE']); // Раз в час
    end;

    i:=time.wDay;
    if i<>lastDay then begin
     lastDay:=i;
     AddTask(0,0,['DAILY_MAINTENANCE']); // Раз в сутки
    end;
   except
    on e:exception do begin
     ForceLogMessage('NET Error 3: '+ExceptionMsg(e));
     sleep(100);
    end;
   end;

   i:=time.wMilliseconds div 100;
   if i<>LastSecond then begin
    lastSecond:=i;
    // обработка таймаутов
    try
     t:=MyTickCount;
     for i:=1 to MAX_CONNECTIONS do
      with connections[i] do
       if (socket<>0) and (not (status in [csClosing,csWriting])) then begin
        if t>timeOut then begin
         // если ждем запроса а его все нет - закрыть соединение
         if status in [csReading,csWriting] then begin
          if LOG_HTTP and (minLogMemLevel=0) then
            LogMsg('Timeout for con#'+inttostr(i)+': '+inttostr(t-timeOut),logDebug,lgHTTP);
          status:=csClosing;
          closeReason:=4; // request read timeout
         end;
         // если запрос был, а ответа все нет - отправить пустой ответ
         if status=csWaiting then begin
          if LOG_HTTP and (minLogMemLevel=0) then
            LogMsg('Con#'+inttostr(i)+' timeout',logDebug,lgHTTP);
          if outBuf='' then begin
           if (cometUserID>0) and (IsValidUserID(cometUserID)) then begin
            outbuf:=GetUserMsgs(cometUserID);
            users[cometUserID].lastPollResponse:=outbuf; // возможно пустой ответ - признак того, что он был отправлен
            if outbuf<>'' then outBuf:=FormatResponse(outbuf,dontCompress);
           end;
          end else
           LogMsg('WARN: outbuf(%d) not sent until timeout',[length(outbuf)],logNormal,lgHTTP);
          if outbuf='' then outBuf:=FormatResponse('');
          SendResponse(5);
         end;
        end;
       end;

     // ban list (1 раз в секунду)          
     if lastSecond=0 then
      for i:=0 to high(banlist) do
       if banlist[i]>10 then dec(banlist[i],10)
        else banlist[i]:=0;
    except
     on e:exception do LogMsg('Error in NET timer: '+ExceptionMsg(e),logError);
    end;

    if timeToFlush<=0 then begin
     FlushLogs;
     timeToFlush:=LOG_FLUSH_INTERVAL;
    end else dec(timeToFlush);

    // Таймеры сервера и логики
    onTimer;
    onCustomTimer;
   end;

   // Delete connections
   for i:=1 to MAX_CONNECTIONS do
    if //(connections[i].socket<>0) and 
       (connections[i].status=csClosing) then DeleteConnection(i);

   finally
    LeaveCriticalSection(gSect);
   end;
  except
   on e:exception do begin
    ForceLogMessage('Error in net loop: '+ExceptionMsg(e));
    sleep(1000);
   end;
  end;

  // Non-alterable delay
  WaitForSingleObject(event,NET_LOOP_INTERVAL);
  SleepEx(1,true); // позволяет выполняться APC
  netThreadTimestamp:=Now;
  
 until terminated;

 ForceLogMessage('NET loop stopped.');
 // Finalization
 try

 except
  on e:exception do ForceLogMessage('Error in NetThread done: '+ExceptionMsg(e));
 end;
 ForceLogMessage('NET thread done.');
end;

end.
