// Common routines (must be thread-safe)
unit site;
interface
 uses windows,MyServis,SCGI,Database,structs;
 type
  // Профиль пользователя
  TUserProfile=record
    id:integer;  // 0 - неавторизованный юзер
    email,name,guild:AnsiString;
    VID:int64;
    playerID:integer;
    network,networkID:AnsiString;
    avatar:integer;
    flags,realname,location:AnsiString;
    created:TDateTime;
    premium:boolean;
    session:integer; // текущий номер сессии, в которой авторизован юзер
    notificationMode:char;
  end;

  // Кэшированная информация о сессиях (из БД)
  TSessionCache=record
   profileID:integer;
   sessions:array[0..4] of integer;
   expires:TDateTime;
  end;

 var
  // Любые глобальные переменные (кроме thread-safe) можно использовать ТОЛЬКО под защитой глобальной критсекции
  gSect:TMyCriticalSection;
  //sessions:TSimpleHash;

  // Кэшированная информация о сессиях (из БД). 
  sessionCache:array[0..255] of TSessionCache;

  vid:int64; // Visitor ID
  pageAB:char; // A или B

 function InitSite:AnsiString; stdcall;

 // Самая главная страница, включающая в общем-то всё
 function IndexPage:AnsiString; stdcall;

 // /ranking, параметры: mode - тип боёв (0..3), start - начальная позиция рейтинга,
 // count - кол-во мест, plrname - выделить строку с именем данного игрока
 // Результат: 1-я строка - список страниц, остальные строки - '<tr><td>...'
 function RankingRequest:AnsiString; stdcall;
 // параметры: name=xxx, либо id=xxx
 function ProfileRequest:AnsiString; stdcall;
 // Аккаунт текущего игрока
 function AccountRequest:AnsiString; stdcall;
 // id = topic.id, [msgid=id сообщения, которое не надо сворачивать]
 function ThreadRequest:AnsiString; stdcall;

 function ChapterRequest:AnsiString; stdcall;
 // p=TEMPLATE - запрос страницы по шаблону
 function PageRequest:AnsiString; stdcall;
 // File={uploaded file}
 function AttachFileRequest:AnsiString; stdcall;
 function GetFileRequest:AnsiString; stdcall;
 function UploadImageRequest:AnsiString; stdcall;

 function GetDeckList:AnsiString; stdcall;

 // q=query
 function SearchRequest:AnsiString; stdcall;

 function PostMsgRequest:AnsiString; stdcall;
 // Запрос на авторизацию: параметры: login и password, возвращает куку TOKEN (http-only)
 function LoginRequest:AnsiString; stdcall;
 // Параметр backurl - адрес редиректа на который будет перенаправление. Удаляет куку TOKEN
 function LogoutRequest:AnsiString; stdcall;
 function DuelStat:AnsiString; stdcall;
 function ListHeaders:AnsiString; stdcall;
 function DumpData:AnsiString; stdcall;
 function DefaultPage:AnsiString; stdcall;

 // Служебный запрос
 function IndexForumRequest:AnsiString; stdcall;

 // Проверяет наличие куки VID и в случае отсутствия - выставляет куку и заносит данные в таблицу visits 
 procedure CheckSource;
 // Проверяет залогинен ли юзер и заполняет UserID. Также определяет язык в clientLang
 procedure CheckLogin;
 // Заполняет профиль юзера (если он авторизован)
 function GetUserProfile:TUserProfile;

 // Форматирует дату с учётом языка текущего юзера (clientLang)
 function FormatDate(d:TDateTime;short:boolean=false):AnsiString;

 function IsAdmin(const p:TUserProfile):boolean;
 function IsModerator(const p:TUserProfile):boolean;

implementation
 uses CrossPlatform,SysUtils,logging,dcpMD5a,ranking,UCalculating,forum,NetCommon,udict,Search;

 const
  loginSalt='AstraL';

 type
  TRequestRec=record
   ip:AnsiString;
   date:TDateTime;
  end;

 var
  lastRequests:array[0..255] of TRequestRec;
  nextRequest:byte;

 function ShortMD5(st:AnsiString):AnsiString;
  begin
   result:=MD5(st);
   setLength(result,10);
  end;

 function FormatDate(d:TDateTime;short:boolean=false):AnsiString;
  const
   mNames:array[1..12] of AnsiString=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
  var
   st:TSystemTIME;
  begin
   if d=0 then begin
    result:='-'; exit;
   end;
   DateTimeToSystemTime(d,st);
   if clientLang='RU' then begin
    if short then
     result:=FormatDateTime('dd.mm.yyyy',d)
    else
     result:=FormatDateTime('dd.mm.yyyy hh:nn',d);
   end else begin
    if short then
     result:=mNames[st.wMonth]+Format('-%d-%d',[st.wDay,st.wYear])
    else
     result:=mNames[st.wMonth]+Format('-%d-%d %.2d:%.2d',[st.wDay,st.wYear,st.wHour,st.wMinute]);
   end;
  end;

 function IndexPage:AnsiString; stdcall;
  var
   profile:TUserProfile;
   initialPage,st,initialScript,key:AnsiString;
   list:TPlayerArr;
   gList:TGuildArr;
   i:integer;
   lastRead:THash;
   replaceStartURI:boolean;
   pages:AnsiString;
  begin
   initialScript:='';
   CheckSource;
   CheckLogin;
   temp.Put('USERAVATAR',0);

   // A/B testing
//   modeA:=vid and 128=0;
   if param('pageMode')='A' then pageAB:='A';
   if param('pageMode')='B' then pageAB:='B';
   temp.Put('MODE',pageAB);
   if pageAB='A' then
    temp.Put('MODEA',true)
   else
    temp.Put('MODEB',true);

   if uri='/' then begin
    uri:='/'+lowercase(clientLang);
    if userID>0 then uri:=uri+'/home'
     else uri:=uri+'/welcome';
    initialScript:=initialScript+#13#10+'SetCurrentURL("'+uri+'");';
   end;
   profile:=GetUserProfile;
   uri:=lowercase(uri);
   initialPage:='welcome';
   if userID>0 then initialPage:='home';
   if pos('/home',uri)=4 then initialPage:='home';
   if pos('/leaderboard',uri)=4 then initialPage:='leaderboard';
   if pos('/forum',uri)=4 then initialPage:='forum';
   temp.Put('INITIALPAGE',initialPage);
   if (initialPage<>'welcome') then temp.Put('MAINMODE','ON');

   // Home
   st:=FormatNews(profile);
   temp.Put('NEWSFEED',st);

   // Ranking
   for i:=0 to 3 do begin
    list:=GetRanking(TDuelType(i),1,100,pages);
    st:=FormatRankingTable(TDuelType(i),list,profile.name);
    temp.Put('RANKING_TYPE'+inttostr(i),st);
    temp.Put('RANKING_PAGES'+inttostr(i),pages);
   end;
   gList:=GetGuildRanking(1,100,pages);
   st:=FormatGuildsRankingTable(gList,profile.guild);
   temp.Put('RANKING_GUILDS',st);
   temp.Put('RANKING_PAGES_GUILDS',pages);

   // Forum
   st:=FormatSuggestedThreads(profile);
   temp.Put('SUGGESTED_THREADS',st);
   if userID>0 then begin
     db.QueryHash(lastRead,'lastread','topic','msg','user='+IntToStr(userID));
     st:='';
     for key in lastRead.keys do
      st:=st+','+key+','+lastRead.Get(key);
     initialScript:=initialScript+#13#10+'lastReadInitialInfo=[0'+st+'];';
   end;

   // Final page
   temp.Put('INITIAL_SCRIPT',initialScript);
   result:=FormatHeaders('text/html','','')+BuildTemplate('#INDEX.HTM');
  end;

 function RankingRequest:AnsiString; stdcall;
  var
   i,start,count:integer;
   list:TPlayerArr;
   listG:TGuildArr;
   mode:integer;
   plrName,pages:AnsiString;
   profile:TUserProfile;
  begin
   CheckLogin;
   profile:=GetUserProfile;
   mode:=IntParam('mode',0);
   start:=IntParam('start',1);
   count:=IntParam('count',100);
   plrName:=Param('plrname');
   if mode<4 then begin
    list:=GetRanking(TDuelType(mode),start,count,pages);
    result:=FormatHeaders('text/html','','')+FormatRankingTable(TDuelType(mode),list,profile.name)+'<!--PAGES-->'+pages;
   end else begin
    listG:=GetGuildRanking(start,count,pages);
    result:=FormatHeaders('text/html','','')+FormatGuildsRankingTable(listG,profile.guild)+'<!--PAGES-->'+pages;
   end;
  end;

 function ProfileRequest:AnsiString; stdcall;
  var
   i,id,title:integer;
   name,email,emailVerify:AnsiString;
   plr:TPlayerRec;
   edit:boolean;
   profile:TUserProfile;
  begin
   id:=IntParam('id',0);
   edit:=IntParam('edit',0)>0;
   email:='';
   emailVerify:='';
   // Запрашивается собственный профайл?
   if edit then begin
    CheckLogin;
    profile:=GetUserProfile;
    email:=profile.email+BuildTemplate('<div class=IconEdit title="$MSG_EDIT_ICON" onClick="EditProfile(''Email'')">&#xf040;</div>');
    if pos('U',profile.flags)>0 then emailVerify:=BuildTemplate('$EMAIL_NOT_VERIFIED');
   end;

   if id=0 then id:=FindPlayer(Param('name'));
   LogMsg('Profile ID='+inttostr(id));
   plr:=GetPlayerInfo(id);
   title:=CalcPlayerTitle(plr.campaignWins,plr.ownedCards);
   result:=Join([plr.id,plr.name,plr.avatar,email,emailVerify,title,plr.guild,0,plr.realname,plr.location,
     plr.customFame,CalcLevel(plr.customFame),plr.customWins,plr.customLoses,plr.customPlace,
     plr.classicFame,CalcLevel(plr.classicFame),plr.classicWins,plr.classicLoses,plr.classicPlace,
     plr.draftFame,CalcLevel(plr.draftFame),plr.draftWins,plr.draftLoses,plr.draftPlace,
     plr.totalFame,CalcLevel(plr.totalFame),plr.place],#13#10);
   result:=FormatHeaders('text/html','','')+'OK'#13#10+HTMLString(result);
  end;

 function AccountRequest:AnsiString; stdcall;
  var
   profile:TUserProfile;
   plr:TPlayerRec;

  function UpdateAccount:AnsiString;
   var
    fName,fValue,fOut,fSmall,fSign:AnsiString;
    res:AnsiString;
    i:integer;
   begin
    if httpMethod<>'POST' then raise E405.Create('Wrong method: '+httpMethod);
    fSign:=param('s');
    if fSign<>temp.Get('USERSIGN') then raise E403.Create('Bad signature '+fSign);
    result:='';
    try
     if profile.playerID<=0 then raise Exception.Create('External profile can''t be modified!');
     fName:=Lowercase(param('f'));
     fValue:=param('v');
     if fvalue='' then raise Exception.Create('No value');

     if fname='notify' then begin
      profile.notificationMode:=CharAt(fValue,1);
      db.Query('UPDATE profiles SET notify="%s" WHERE id=%d',[profile.notificationMode,profile.id]);
      if db.lastError='' then result:='OK'
       else result:='Internal error';
      exit;
     end;

     if fname='email' then begin
      res:=IsValidLogin(fValue);
      if res<>'' then raise Exception.Create(Translate(res));
      if fValue<>profile.email then begin
       LogMsg('Player '+profile.email+' is trying to update their email to '+fValue);
       db.Query('SELECT id FROM players WHERE email="'+SqlSafe(fValue)+'"');
       if db.rowCount>0 then raise Exception.Create('This email is in use!');
       db.Query('UPDATE players SET email="%s", flags=concat(replace(replace(flags,"I",""),"U",""),"U") WHERE id=%d',
         [SQLSafe(fValue),profile.playerID]);
       db.Query('UPDATE profiles SET email="%s" WHERE id=%d',[SQLSafe(fValue),profile.id]);
      end;
      result:='OK'#13#10+fvalue+#13#10+BuildTemplate('#EMAIL_NOT_VERIFIED');
      exit;
     end;

     if (fName='realname') or (fName='location') then begin
      if length(DecodeUTF8(fValue))>45 then raise Exception.Create('Too long!');
      db.Query('UPDATE players SET %s="%s" WHERE id=%d',[fName,SQLSafe(fValue),profile.playerID]);
      if db.lastError='' then result:='OK'#13#10+fvalue
       else raise Exception.Create('DB Error');
      exit;
     end;

     // Avatar index (can be negative)
     if fname='avatar' then begin
      i:=StrToIntDef(fValue,0);
      if i<0 then begin
       i:=abs(i);
       fname:=rootDir+'faces\temp\face'+inttostr(i)+'.jpg';
       if FileExists(fname) then begin
         fOut:=rootDir+'faces\face'+inttostr(i)+'.jpg';
         RenameFile(fname,fOut);
         fSmall:=rootDir+'faces\s-'+inttostr(i)+'.jpg';
         LaunchProcess('magick.exe',fOut+' -resize 60x70 '+fSmall);
         WaitForFile(fSmall,500);
       end else
        raise Exception.Create('File not found!');
       db.Query('INSERT INTO eventlog (created,playerid,event,info) values(Now(),%d,"AVATAR","%d")',
         [profile.playerID,i]);
      end;
      db.Query('UPDATE players SET avatar=%d WHERE id=%d',[i,profile.playerID]);
      if db.lastError='' then result:='OK'#13#10+IntToStr(i);
      // Delete previous custom avatar
      if profile.avatar>1000 then try
       LogMsg('Deleting unused avatar '+inttostr(profile.avatar),logInfo);
       DeleteFile(rootDir+'faces\face'+inttostr(profile.avatar)+'.jpg');
       DeleteFile(rootDir+'faces\s-'+inttostr(profile.avatar)+'.jpg');
      except
       on e:exception do LogMsg('DelAvatar: '+e.message,logWarn);
      end;
      exit;
     end;

     // Custom avatar file
     if fName='customavatar' then begin
      // Сохранить картинку в /faces/temp
      repeat
       i:=100000+(MyTickCount+random(1000)) mod 900000;
      until (not FileExists(rootDir+'faces\temp\face'+inttostr(i)+'.jpg')) and
            (not FileExists(rootDir+'faces\face'+inttostr(i)+'.jpg'));
      fname:=rootDir+'faces\temp\'+inttostr(i);
      fOut:=rootDir+'faces\temp\face'+inttostr(i)+'.jpg';
      fValue:=DecodeHex(fValue);
      LogMsg('Saving avatar to: '+fname,logInfo);
      SaveFile(fname,@fValue[1],length(fValue));
      LogMsg('Convert to: '+fOut,logInfo);
      // [0] means frame number if it is animated GIF
      LaunchProcess('magick.exe',fname+'[0] -resize 120x140^ -gravity center -extent 120x140 -type TrueColor -strip '+fOut);
      if WaitForFile(fOut,2000) then begin
        result:='OK'#13#10+inttostr(i);
        DeleteFile(fname);
      end else begin
        LogMsg('File not converted: '+fname,logWarn);
        raise Exception.Create('Image conversion failed!');
      end;
      exit;
     end;

     raise Exception.Create('Unknown error');
    except
     on e:exception do begin
      LogMsg('UpdateAccount error: '+e.Message,logWarn);
      result:='FAILURE'#13#10+e.Message;
     end;
    end;
   end;

  function BuildAccountBlock(name:AnsiString):AnsiString;
   var
    title,content:AnsiString;
   begin
    if name='ABOUT' then begin
     temp.Put('REGDATE',FormatDateTime('dd.mm.yyyy',profile.created));
     temp.Put('REALNAME',HTMLString(profile.realname));
     temp.Put('LOCATION',HTMLString(profile.location));
    end;
    if name='STATS' then begin
     // Level
     temp.Put('LEVEL_CUSTOM',plr.customLevel);
     temp.Put('LEVEL_RANDOM',plr.classicLevel);
     temp.Put('LEVEL_DRAFT',plr.draftLevel);
     temp.Put('LEVEL_TOTAL',plr.totalLevel);
     // Fame
     temp.Put('FAME_CUSTOM',plr.customFame);
     temp.Put('FAME_RANDOM',plr.classicFame);
     temp.Put('FAME_DRAFT',plr.draftFame);
     temp.Put('FAME_TOTAL',plr.totalFame);
     // Place
     temp.Put('PLACE_CUSTOM',plr.customPlace);
     temp.Put('PLACE_RANDOM',plr.classicPlace);
     temp.Put('PLACE_DRAFT',plr.draftPlace);
     temp.Put('PLACE_TOTAL',plr.Place);
     // Wins
     temp.Put('WINS_CUSTOM',plr.customWins);
     temp.Put('WINS_RANDOM',plr.classicWins);
     temp.Put('WINS_DRAFT',plr.draftWins);
     temp.Put('WINS_TOTAL',plr.customWins+plr.classicWins+plr.draftWins);
     // Loses
     temp.Put('LOSES_CUSTOM',plr.customLoses);
     temp.Put('LOSES_RANDOM',plr.classicLoses);
     temp.Put('LOSES_DRAFT',plr.draftLoses);
     temp.Put('LOSES_TOTAL',plr.customLoses+plr.classicLoses+plr.draftLoses);
    end;
    if name='GOLD' then begin
     temp.Put('GOLD',plr.gold);
     temp.Put('CRYSTALS',plr.crystals);
    end;
    if name='NOTIFICATIONS' then begin
     temp.Put('ACCOUNT_NMODE',profile.notificationMode);
    end;
    title:=BuildTemplate('$ACCOUNT_BLOCK_'+name+'_TITLE');
    content:=BuildTemplate('$ACCOUNT_BLOCK_'+name+'_HTML');
    temp.Put('BLOCK_TITLE',title);
    temp.Put('BLOCK_CONTENT',content);
    result:=BuildTemplate('#ACCOUNT_BLOCK');
   end;
  begin
   CheckLogin;
   profile:=GetUserProfile;
   if userid=0 then begin
    result:=FormatHeaders('text/html','','')+'Please login!';
    exit;
   end;
   if Param('f')<>'' then begin
    // Изменение какого-либо параметра аккаунта
    result:=UpdateAccount;
    result:=FormatHeaders('text/html','','')+result;
    exit;
   end;
   plr:=GetPlayerInfo(profile.playerID);

   temp.Put('ACCOUNT_BLOCK_STATS',BuildAccountBlock('STATS'));
   temp.Put('ACCOUNT_BLOCK_ABOUT',BuildAccountBlock('ABOUT'));
   temp.Put('ACCOUNT_BLOCK_AVATAR',BuildAccountBlock('AVATAR'));
   temp.Put('ACCOUNT_BLOCK_GOLD',BuildAccountBlock('GOLD'));
//   temp.Put('ACCOUNT_BLOCK_PREMIUM',BuildAccountBlock('PREMIUM'));
//   temp.Put('ACCOUNT_BLOCK_CRAFTED',BuildAccountBlock('CRAFTED'));
   temp.Put('ACCOUNT_BLOCK_NOTIFICATIONS',BuildAccountBlock('NOTIFICATIONS'));
   result:=BuildTemplate('#ACCOUNT_PAGE');
   result:=FormatHeaders('text/html','','')+result;
  end;

 function AttachFileRequest:AnsiString; stdcall;
  var
   fName,st,fileData,fType,thumb,cmd,outp,visibleName:AnsiString;
   id,fSize,tw,th:integer;
   isImage:boolean;
   sa:StringArr;
  begin
   result:='FAILURE';
   CheckLogin();
   if userID=0 then raise E403.Create('You must be logged in to upload files');
   fileData:=Param('File');
   if fileData='' then raise E500.Create('File upload error: no data');
   // Предварительная запись в базе
   fType:=Lowercase(ExtractFileExt(uploadedFileName));
   if copy(fType,1,1)='.' then delete(fType,1,1);
   if not ((fType='jpg') or
           (fType='jpeg') or
           (fType='png') or
           (fType='tga') or
           (fType='bmp') or
           (fType='gif') or
           (fType='rar') or
           (fType='zip') or
           (fType='pdf') or
           (fType='7z') or
           (fType='txt') or
           (fType='log')) then begin
    result:=FormatHeaders('text/plain','','')+'ERROR: Unsupported file type: '+fType;
    exit;
   end;

   visibleName:=SQLSafe(uploadedFileName);
   db.Query('INSERT INTO attachments (filename) values("%s")',[visibleName]);
   if db.lastError<>'' then raise E500.Create('Database error');
   id:=db.insertID;
   fName:=rootDir+'attach\'+inttostr(id)+'.'+fType;
   SaveFile(fName,@filedata[1],length(filedata));
   fSize:=GetFileSize(fName);
   // Pack text files larger than 10K?
   if ((fType='txt') or (ftype='log')) and (length(filedata)>10000) then begin
    LogMsg('Packing file: '+fname);
    st:=rootDir+'attach\'+inttostr(id)+'.zip';
    if ExecAndCapture('7z a '+st+' '+fname,outp)>=0 then begin
     sleep(20);
     DeleteFile(fname);
     fName:=st;
     fType:='zip';
     visibleName:=visibleName+'.zip';
     db.Query(Format('UPDATE attachments SET filename="%s" WHERE id=%d',[visibleName,id]));
    end;
   end;

   isImage:=(fType='jpg') or (fType='jpeg') or (fType='gif') or (fType='png') or (fType='bmp') or (fType='tga');

   // Repack if image is larger than 1 Mb or non-web type
   if (isImage) and ((fSize>1024*1024) or (fType='bmp') or (fType='tga')) then begin
    st:=rootDir+'attach\'+inttostr(id)+'tmp.jpg';
    if ExecAndCapture('magick.exe '+fname+'[0] -resize 1920x1080> -type TrueColor '+st,outp)>=0 then begin
     sleep(20);
     DeleteFile(fname);
     fType:='jpg';
     fName:=rootDir+'attach\'+inttostr(id)+'.jpg';
     RenameFile(st,fName);
    end;
   end;

   // Generate thumbnail
   thumb:=''; tw:=0; th:=0;
   if isImage then begin
    thumb:=rootDir+'attach\T'+inttostr(id)+'.jpg';
    if ExecAndCapture('magick.exe '+fname+'[0] -resize 120x60 -type TrueColor '+thumb,outp)>=0 then begin
     sleep(20);
     // Get image size
     st:=rootDir+'attach\out';
     DeleteFile(st);
     cmd:='magick.exe '+thumb+' -ping -print "%w %h" nul';
     ExecAndCapture(cmd,st);
     sa:=SplitA(' ',st);
     if length(sa)=2 then begin
      tw:=ParseInt(sa[0]);
      th:=ParseInt(sa[1]);
     end;
    end;
   end;

   fSize:=GetFileSize(fName);
   thumb:=ExtractFileName(thumb);
   if fType='7z' then thumb:='file_7z.png';
   if fType='zip' then thumb:='file_zip.png';
   if fType='rar' then thumb:='file_rar.png';
   if fType='pdf' then thumb:='file_pdf.png';
   if fType='txt' then thumb:='file_txt.png';
   if fType='log' then thumb:='file_log.png';
   if copy(thumb,1,5)='file_' then begin
    tw:=60; th:=60;
   end;

   db.Query(Format('UPDATE attachments SET filesize=%d, fileType="%s",'+
    ' thumbnail="%s", th_width=%d, th_height=%d WHERE id=%d',[fSize,fType,thumb,tw,th,id]));

   result:=FormatHeaders('text/plain','','')+join(['OK',id,fType,uploadedFileName,fSize,thumb,tW,tH],#9);
  end;

 function UploadImageRequest:AnsiString; stdcall;
  var
   fName,st,fileData,fType,cmd,outp:AnsiString;
   id,fSize,tw,th:integer;
   sa:StringArr;
  begin
   result:='FAILURE';
   CheckLogin();
   if userID=0 then raise E403.Create('You must be logged in to upload files');
   fileData:=Param('File');
   if fileData='' then raise E500.Create('File upload error: no data');
   // Предварительная запись в базе
   fType:=Lowercase(ExtractFileExt(uploadedFileName));
   if copy(fType,1,1)='.' then delete(fType,1,1);
   if not ((fType='jpg') or
           (fType='jpeg') or
           (fType='png') or
           (fType='gif')) then begin
    result:=FormatHeaders('text/plain','','')+'ERROR: Unsupported file type: '+fType;
    exit;
   end;
   fName:=rootDir+'attach\i'+inttostr(userid)+'_'+IntToHex(random($FFFFFF),6)+'.'+fType;
   SaveFile(fName,@filedata[1],length(filedata));
   fSize:=GetFileSize(fName);

   tw:=9999; th:=9999;
   cmd:='magick.exe '+fName+' -ping -print "%w %h" nul';
   ExecAndCapture(cmd,st);
   sa:=SplitA(' ',st);
   if length(sa)=2 then begin
    tw:=ParseInt(sa[0]);
    th:=ParseInt(sa[1]);
   end;


   // Repack if image is larger than 1 Mb or too big
   if (fSize>65536) or (tw>400) or (th>250) then begin
    st:=fName+'.jpg';
    if ExecAndCapture('magick.exe '+fname+'[0] -resize 400x250> -type TrueColor '+st,outp)>=0 then begin
     sleep(20);
     DeleteFile(fname);
     fname:=st;
    end else
     raise E500.Create('Failed to repack image');

    cmd:='magick.exe '+fName+' -ping -print "%w %h" nul';
    ExecAndCapture(cmd,st);
    sa:=SplitA(' ',st);
    if length(sa)=2 then begin
     tw:=ParseInt(sa[0]);
     th:=ParseInt(sa[1]);
    end;
    if (tw>480) or (th>270) then raise E500.Create('Bad size after repack');
   end;

   result:=FormatHeaders('text/plain','','')+join(['OK',ExtractFileName(fName),tW,tH],#9);
  end;  


 function ThreadRequest:AnsiString; stdcall;
  var
   id,start,count,msgToShow:integer;
   profile:TUserProfile;
  begin
   CheckLogin;
   profile:=GetUserProfile;
   id:=IntParam('id',0); // ID темы
   msgToSHow:=IntParam('msgid',0); // ID сообщения, которое должно быть видно
   start:=IntParam('start',0); // порядковый номер сообщения в теме, с которого начать (0 - первое)
   count:=IntParam('count',0); // кол-во сообщений (0 - сформировать всю тему в урезанном виде)
   temp.Put('THREAD_ID',id);
   result:=FormatThread(id,profile,start,count,msgToShow);
   if count=0 then // добавим редактор в конец темы
    result:=result+#13#10+BuildTemplate('#THREAD_FOOTER');
   result:=FormatHeaders('text/html','','')+result;
  end;

 function GetFileRequest:AnsiString; stdcall;
  var
   aid:integer;
   mime,fname:AnsiString;
   sa:StringArr;
  begin
   aid:=IntParam('id',0);
   sa:=db.Query('SELECT filename,filetype FROM attachments WHERE id='+inttostr(aid));
   if db.lastError<>'' then raise E404.Create('Invalid file ID');
   fname:=rootDir+'attach\'+inttostr(aid)+'.'+sa[1];
   if not FileExists(fname) then raise E404.Create('File not found');
   mime:='application/octet-stream';
   if (sa[1]='jpg') or (sa[1]='jpeg') then mime:='image/jpeg';
   if (sa[1]='png') then mime:='image/png';
   if (sa[1]='gif') then mime:='image/gif';
   if (sa[1]='txt') or (sa[1]='log') then mime:='text/plain';
   if (sa[1]='zip') then mime:='application/zip';
   if (sa[1]='7z') then mime:='application/x-7z-compressed';
   if (sa[1]='rar') then mime:='application/x-rar-compressed';
   result:=FormatHeaders(mime,'','Content-Disposition: inline; filename="'+sa[0]+'"')+LoadFileAsString(fname);
  end;

 // id = chapter, start=x, count=y
 function ChapterRequest:AnsiString; stdcall;
  var
   chapter,start,count:integer;
   profile:TUserProfile;
   content:AnsiString;
  begin
   CheckLogin;
   profile:=GetUserProfile;
   chapter:=IntParam('id',0);
   start:=IntParam('start',0);
   count:=IntParam('count',150);
   temp.Put('CHAPTER_ID',chapter);
   temp.Put('CAN_POST',not (chapter in PrivChapters) or IsModerator(profile),true);
   content:=FormatChapter(chapter,start,count,profile);
   if content='' then content:=BuildTemplate('#EMPTY_CHAPTER');
   temp.Put('CHAPTER_THREADS',content);
   temp.Put('FORUM_PAGE_TITLE',BuildTemplate('<h2>$FORUM_HOME_LINK $FORUM_TITLE_ARROW $FORUM_CHAPTER_LINK'+IntToStr(chapter)+'</h2>'));
   result:=BuildTemplate('#FORUM_CHAPTER');
   result:=FormatHeaders('text/html','','')+result;
  end;

 function PageRequest:AnsiString; stdcall;
  var
   profile:TUserProfile;
   page,lang:AnsiString;
  begin
   CheckLogin;
   profile:=GetUserProfile;
   page:=Uppercase(param('p'));
{   lang:=Uppercase(cookie('lang'));
   if lang<>'EN' then lang:='_'+lang else lang:='';
   result:=BuildTemplate('#PAGE_'+page+lang);}
   result:=BuildTemplate('$PAGE_'+page);   
   if result<>'' then
    result:=FormatHeaders('text/html','','')+result
   else
    result:=FormatError(404,'Bad template: '+page);
  end;

 // Добавление сообщения форума
 // Параметры: topic, msg (текст сообщения), att - список id аттачей,
 //  title (если новая тема - имя темы), ch (chapter), lang (язык), msgid (если сообщение редактируется)
 // Ответ:
 // 1 строка: OK, либо текст ошибки,
 // 2 строка: параметры (зависят от запроса)
 // остальные строки: html-код сообщения (целиком)
 function PostMsgRequest:AnsiString; stdcall;
  var
   id,thread,msgid,guild,flags:integer;
   profile:TUserProfile;
   error,msgtext,status:AnsiString;
  begin
   CheckLogin;
   if userid<=0 then begin
    result:=FormatHeaders('text/html','','')+'You must be logged in to post to the forum!';
    exit;
   end;
   profile:=GetUserProfile;
   id:=IntParam('id',0);
   thread:=IntParam('topic',0);
   msgtext:=Param('msg');
   temp.Put('THREAD_ID',thread);
   error:=''; status:='';
   if thread=0 then begin
    // новая тема
    try
     ValidateForumMessage(msgtext);
    except
     on e:Exception do error:=e.Message;
    end;
    guild:=0;
    if IntParam('guildPrivate')=1 then guild:=FindGuild(profile.guild);
    if error='' then
     error:=CreateForumThread(IntParam('ch',0),guild,Param('title'),Param('lang'),profile,thread);
   end;
   if error='' then begin
    msgid:=IntParam('msgid',0);
    flags:=IntParam('sub',0);
    error:=AddForumMessage(thread,msgtext,Param('att'),flags,profile,msgid);
   end;
   result:=FormatForumMessages('id='+inttostr(msgid),profile);

   status:=inttostr(thread)+';'+inttostr(msgid);
   if error<>'' then result:=error
    else result:='OK'#13#10+status+#13#10+result;
   result:=FormatHeaders('text/html','','')+result;
  end;

 function DefaultPage:AnsiString; stdcall;
  begin
   result:=FormatHeaders('text/html','','')+'<h2 align=center>Default page</h2>';
  end;

 procedure CheckSource;
  var
   ref:AnsiString;
   newUser:boolean;
   i:integer;
   dd:TDateTime;
  begin
   newUser:=cookie('VID')='';

   if newUser then begin
    // Были ли запросы с этого же IP за последний час? Если были - юзер не новый
    dd:=Now-1/24;
    for i:=0 to high(lastRequests) do
     if (lastRequests[i].ip=clientIP) and
        (lastRequests[i].date>dd) then begin
      newUser:=false;
      break;
     end;
   end;

   if newuser then begin
    // New visitor
    vid:=(MyTickCount and $FFFFFFFF)+int64(random(100000))*10000000+round(Now*1000)+random(1000);
    if vid and 128=0 then pageAB:='A'
     else pageAB:='B';
    LogMsg('New visitor! VID -> '+inttostr(vid),logInfo);
    SetCookie('VID',IntToStr(vid),true,false);
    ref:=GetHeader(headers,'HTTP_REFERER');
    if length(ref)>250 then ref:=copy(ref,1,250)+'...';
    db.Query(Format('INSERT INTO visits (vid,date,ip,country,page,referer,tags) values(%s,Now(),"%s","%s","%s","%s","%s")',
     [IntToStr(vid),clientIP,clientCountry,GetHeader(headers,'REQUEST_URI'),ref,pageAB]));
    temp.Put('NEWUSER',1,true); 
   end else begin
    vid:=StrToInt64Def(cookie('VID'),random(10000));
    if vid and 128=0 then pageAB:='A'
     else pageAB:='B';
   end;
   lastRequests[nextRequest].ip:=clientIP;
   lastRequests[nextRequest].date:=Now;
  end;

 // Загружает сессии из БД в кэш (предыдущее содержимое кэша для данного профиля удаляется)
 // Возвращает индекс обновлённого слота кэша (либо -1, если профиль не найден)
 function CacheProfileSessions(pid:integer):integer;
  var
   i,n:integer;
   sa:StringArr;
  begin
   result:=-1;
   gSect.Enter;
   try
   // удаление старых записей
   for i:=0 to high(sessionCache) do
    if sessionCache[i].profileID=pid then sessionCache[i].profileID:=0;

   // Поиск свободного/случайного слота
   n:=random(high(sessionCache));
   for i:=0 to high(sessionCache) do
    if sessionCache[i].profileID=0 then begin
     n:=i; break;
    end;
   finally
    gSect.Leave;
   end;

   sa:=db.Query('SELECT sessions FROM profiles WHERE id='+inttostr(pid));
   if db.rowCount=1 then begin
    gSect.Enter;
    try
    sessionCache[n].profileID:=pid;
    sessionCache[n].expires:=Now+1;
    sa:=SplitA(',',sa[0]);
    for i:=0 to high(sessionCache[n].sessions) do
     if i<length(sa) then
      sessionCache[n].sessions[i]:=StrToIntDef(sa[i],0)
     else
      sessionCache[n].sessions[i]:=0;
    result:=n;
    finally
     gSect.Leave;
    end;
   end;
  end;

 // Проверяет существование указанной сессии у профиля (сперва в кэше, а если в кэше нет - грузит из БД)
 function ProfileHasSession(pid,session:integer):boolean;
  var
   i,j,n:integer;
   cached:boolean;
   sa:StringArr;
   dt:TDateTime;
  begin
   result:=false;
   // сперва проверим в кэше
   cached:=false;
   dt:=Now;
   gSect.Enter;
   try
   for i:=0 to high(sessionCache) do begin
    if Now>sessionCache[i].expires then sessionCache[i].profileID:=0;
    if (sessionCache[i].profileID=pid) then begin
     for j:=0 to high(sessionCache[i].sessions) do
      if (sessionCache[i].sessions[j]=session) then begin
       result:=true; exit;
      end;
     cached:=true;
    end;
   end;
   finally
    gSect.Leave;
   end;

   // Если в кэше нет записей для данного профиля - загрузим их (даже если там 0)
   if not cached then begin
    n:=CacheProfileSessions(pid);
    if n>=0 then begin
     gSect.Enter;
     try
     for j:=0 to high(sessionCache[n].sessions) do
      if (sessionCache[n].sessions[j]=session) then begin
       result:=true; exit;
      end;
     finally
      gSect.Leave;
     end;
    end;
   end;
  end;

 // Добавление новой сессии к профилю
 procedure AddSessionToProfile(pid,session:integer);
  var
   i,n:integer;
   list:AnsiString;
  begin
   n:=CacheProfileSessions(pid);
   if n<0 then raise EError.Create('Bad PID = '+inttostr(pid));
   gSect.Enter;
   try
    for i:=high(sessionCache[n].sessions) downto 1 do
     sessionCache[n].sessions[i]:=sessionCache[n].sessions[i-1];
    sessionCache[n].sessions[0]:=session;
    list:=ListIntegers(sessionCache[n].sessions);
   finally
    gSect.Leave;
   end;
   db.Query(Format('UPDATE profiles SET sessions="%s" WHERE id=%d',[list,pid]));
  end;

 procedure RemoveSessionFromProfile(pid,session:integer);
  var
   i,n:integer;
   list:AnsiString;
  begin
   n:=CacheProfileSessions(pid);
   if n>=0 then begin
    gSect.Enter;
    try
     for i:=0 to high(sessionCache[n].sessions) do begin
      if sessionCache[n].sessions[i]=session then sessionCache[n].sessions[i]:=0;
      if (i>0) and (sessionCache[n].sessions[i-1]=0) and (sessionCache[n].sessions[i]>0) then
       Swap(sessionCache[n].sessions[i-1],sessionCache[n].sessions[i]);
     end;
     list:=ListIntegers(sessionCache[n].sessions);
    finally
     gSect.Leave;
    end;
    LogMsg(Format('Removing session %d for profile %d, result: %s',[session,pid,list]));
    db.Query('UPDATE profiles SET sessions="'+list+'" WHERE id='+inttostr(pid));
   end;
  end;

 procedure CheckLogin;
  var
   token,al,authtoken:AnsiString;
   sa,sb:StringArr;
   id,session,realSession,p:integer;
  begin
   userid:=0;
   if authtoken='' then authtoken:=Param('auth');
   clientLang:=Uppercase(Cookie('LANG'));
   if pos('/en/',uri)=1 then clientLang:='EN';
   if pos('/ru/',uri)=1 then clientLang:='RU';
   if (clientLang='') or
      (length(clientLang)<>2) or
      (pos(clientLang,templates.Get('SUPPORTED_LANGUAGES'))=0) then begin
    // Выберем подходящий язык по заголовкам
    clientLang:='EN';
    al:=GetHeader(headers,'HTTP_Accept_Language');
    if pos('ru',al)>0 then clientLang:='RU';
   end;
   temp.Put('LANG',clientLang);
   temp.Put('LANG_LC',lowercase(clientLang));
   token:=Cookie('TOKEN');
   if authToken<>'' then begin
    // Авторизация по authtoken
    authToken:=DecodeHex(authToken);
    sa:=SplitA(#9,authtoken);
    sb:=db.Query('SELECT pwd,id FROM players WHERE email="'+SQLSafe(sa[0])+'"');
    if (db.rowCount=1) and (uppercase(sb[0])=uppercase(sa[1])) then begin
     // Проверка IP
     sb:=db.Query('SELECT info FROM eventlog WHERE playerid='+sb[1]+' AND event="LOGIN" ORDER BY id DESC LIMIT 1');
     if (db.rowCount=1) then
      if (pos(clientIP,sb[0])>0) then begin
       temp.Put('AUTHLOGIN',sa[0]);
       temp.Put('AUTHPWD',ShortMD5(sa[0]+clientIP+loginSalt));
      end else
       LogMsg(Format('Autologin failed! Client IP mismatch: %s not in %s',[clientIP,sb[0]]),logWarn);
    end;
    exit;
   end;
   if token='' then exit;
   sa:=SplitA(',',token); // части token-а
   if length(sa)<3 then exit;
   // Проверка подписи токена
   p:=LastDelimiter(',',token);
   if ShortMD5(copy(token,1,p-1)+loginSalt)<>sa[high(sa)] then begin
    LogMsg('WARN: Invalid token hash! ',logWarn);
    exit;
   end;
   // Проверка сессии
   id:=StrToIntDef(sa[0],0);
   session:=StrToIntDef(sa[1],-1); // сессия из токена
   if not ProfileHasSession(id,session) then begin
    LogMsg(Format('Wrong session: %d for profile %d',[session,id]),logNormal);
    exit;
   end;

   // All OK -> user authorized
   userID:=id;
   temp.Put('USERID',IntToStr(userID));
   if userID>0 then begin
    temp.Put('LOGGED','ON');
    temp.Put('DISPLAY_UNREG','none');
    temp.Put('DISPLAY_REG','block');
    temp.Put('USERSIGN',ShortMD5('510960946089734683476'+IntToStr(userID)));
   end else begin
    temp.Put('DISPLAY_UNREG','block');
    temp.Put('DISPLAY_REG','none');
   end;
  end;

 function GetUserProfile:TUserProfile;
  var
   sa,sb:StringArr;
  begin
   fillchar(result,sizeof(result),0);
   if userid<=0 then exit;
   sa:=db.Query('SELECT email,name,vid,playerID,network,networkid,avatar,flags,session,notify FROM profiles WHERE id='+inttostr(userID));
   if db.rowCount=1 then begin
    result.id:=userID;
    result.email:=sa[0];
    result.name:=sa[1];
    result.VID:=StrToInt64Def(sa[2],0);
    result.playerID:=StrToIntDef(sa[3],0);
    result.network:=sa[4];
    result.networkid:=sa[5];
    result.avatar:=StrToIntDef(sa[6],0);
    result.flags:=sa[7];
    result.session:=StrToIntDef(sa[8],0);
    result.notificationMode:=CharAt(sa[9],1);
    result.guild:='';
    if (result.playerID>0) and (result.network='') then begin
     // Юзер имеет только игровой аккаунт -
     sb:=db.Query('SELECT name,email,flags,avatar,created,realname,location,premium>Now(),guild FROM players WHERE id='+inttostr(result.playerID));
     if db.rowCount=1 then begin
      result.name:=sb[0];
      result.email:=sb[1];
      result.flags:=sb[2];
      result.avatar:=StrToIntDef(sb[3],0);
      result.created:=GetDateFromStr(sb[4]);
      result.realname:=sb[5];
      result.location:=sb[6];
      result.premium:=sb[7]='1';
      result.guild:=sb[8];
     end;
    end;
    temp.Put('USEREMAIL',result.email);
    temp.Put('USERNAME',result.name);
    temp.Put('USERGUILD',result.guild);
    temp.Put('USERAVATAR',result.avatar,true);
    temp.Put('PREMIUM',result.premium);
    if IsAdmin(result) then temp.Put('ADMIN',true);
    if IsModerator(result) then temp.Put('MODERATOR',true);
    if pos('U',result.flags)=0 then
     temp.Put('EMAIL_VERIFIED',true)
    else
     temp.Put('EMAIL_UNVERIFIED',true);
    if pos('I',result.flags)=0 then temp.Put('INVALID_EMAIL',true);
   end;
  end;

 // Создаёт профиль c указанными данными, возвращает его ID
 procedure CreateUserProfile(var profile:TUserProfile);
  var
   sa:StringArr;
  begin
   LogMsg('Creating new user profile');
   with profile do
    db.Query(Format('INSERT INTO profiles (email,name,playerID,VID,network,networkID,avatar,flags,session)'+
     ' values("%s","%s",%d,%d,"%s","%s",%d,"%s",%d)',
     [SQLSafe(email),SQLSafe(name),playerID,VID,SQLSafe(network),SQLSafe(networkid),avatar,SQLSafe(flags),session]));
   if db.lastErrorCode<>0 then raise EWarning.Create('Internal DB error');
   profile.id:=db.insertID;
   ASSERT(db.insertID>0,'InsertID=0!');
  end;

 // Возвращает профиль игрока (если его не было - создаёт новый)
 function GetUserProfileForPlayer(playerID:integer):TUserProfile;
  var
   sa:StringArr;
  begin
   sa:=db.Query('SELECT id,email,name,VID,network,networkID,avatar,flags,session FROM profiles WHERE playerID='+inttostr(playerID));
   if (db.rowCount=0) and (db.lastErrorCode=0) then begin
    // Not found? Create new!
    sa:=db.Query('SELECT email,name,avatar FROM players WHERE id='+inttostr(playerID));
    if db.rowCount=0 then raise EWarning.Create('Player #'+inttostr(playerid)+' not found!');
    result.email:=sa[0];
    result.name:=sa[1];
    result.VID:=StrToInt64Def(Cookie('VID'),0);
    result.playerID:=playerID;
    result.network:='';
    result.networkID:='';
    result.avatar:=StrToIntDef(sa[2],0);
    result.flags:='';                                                                   
    result.session:=random(10000);
    CreateUserProfile(result);
    exit;
   end;
   // fill result
   result.id:=StrToIntDef(sa[0],0);
   result.email:=sa[1];
   result.name:=sa[2];
   result.VID:=StrToInt64Def(sa[3],0);
   result.playerID:=playerID;
   result.network:=sa[4];
   result.networkID:=sa[5];
   result.avatar:=StrToIntDef(sa[6],0);
   result.flags:=sa[7];
   result.session:=StrToIntDef(sa[8],0);
  end;

 function LoginRequest:AnsiString; stdcall;
  var
   login,pwd,pwdhash,token:AnsiString;
   playerID,pID:integer;
   sa,sb:StringArr;
   userProfile:TUserProfile;
   autologin,proceed,temp:boolean;
  begin
   token:=param('t');
   temp:=param('temp')<>'';
   // Передан токен - нужно проверить его и если всё в порядке - установить его в качестве куки
   if token<>'' then begin
    result:='OK'#13#10+token;
    SetCookie('TOKEN',token,not temp);
    sb:=SplitA(',',token);
    pID:=StrToIntDef(sb[0],0);
    sa:=db.Query('SELECT VID,sessions FROM profiles WHERE id='+IntToStr(pid));
    if db.rowCount<>1 then
     result:='Bad session token!'
    else begin
     if not ProfileHasSession(pid,StrToIntDef(sb[1],-1)) then result:='Wrong session!';
    end;
    if sa[0]='0' then
     db.Query(Format('UPDATE profiles SET vid=%d WHERE id=%d',[StrToInt64Def(Cookie('VID'),0),pid]));
    result:=FormatHeaders('text/plain','','Access-Control-Allow-Origin: *')+result;
    exit;
   end;

   if httpMethod<>'POST' then raise E405.Create('Wrong login method: '+httpMethod);
   result:='';
   token:='';
   login:=param('login');
   pwd:=param('password');
   autologin:=false;
   if pos('AUTO:',login)=1 then begin
    // Automatic login
    delete(login,1,5);
    autologin:=true;
   end;
   proceed:=false;
   sa:=db.Query(Format('SELECT id,flags,pwd FROM players WHERE email="%s"',[SQLSafe(login)]));
   if db.rowCount=1 then begin
    playerID:=StrToInt(sa[0]);
    if autologin then begin
     LogMsg('Autologin for '+login+':'+pwd,logInfo);
     if pwd=ShortMD5(login+clientIP+loginSalt) then proceed:=true;
    end;
    if sa[2]=ShortMD5('AH'+pwd) then proceed:=true;
    if proceed then begin
     // Пароль подходит
     userProfile:=GetUserProfileForPlayer(playerID);
     userProfile.session:=1000+random(990000);
     // Create new session
     LogMsg(Format('New session %d for profile %d',[userProfile.session,userProfile.id]),logInfo);
     AddSessionToProfile(userProfile.id,userProfile.session);
     token:=IntToStr(userprofile.id)+','+IntToStr(userProfile.session);
     token:=token+','+ShortMD5(token+loginSalt); // sign token
    end else
     result:='2'#13#10'Sorry, the password is incorrect';
   end else
    result:='1'#13#10'There is no game account with this email';

   if result='' then begin
    result:='OK'#13#10+token;
    SetCookie('TOKEN',token,not temp);
    LogMsg(Format('User logged: %s (%s) Session: %d ',[userProfile.name,userProfile.email,userProfile.session]));
   end else
    result:='ERROR'#13#10+result;

   result:=FormatHeaders('text/plain','','Access-Control-Allow-Origin: *')+result;
  end;

 function LogoutRequest:AnsiString; stdcall;
  var
   url:AnsiString;
   token:AnsiString;
   sa:StringArr;
   sessID:integer;
  begin
   CheckLogin;
   token:=Cookie('TOKEN');
   sa:=SplitA(',',token);
   if length(sa)>2 then sessID:=StrToIntDef(sa[1],0)
    else sessID:=0;
   DeleteCookie('TOKEN');
//   SetCookie('TOKEN','',true);
   url:=param('backurl');
   result:=FormatHeaders('','303 See Other','Location: '+url);
   if (userID>0) and (sessID>0) then
    RemoveSessionFromProfile(userID,sessID);
  end;

 function GetDeckList:AnsiString; stdcall;
  var
   sa:StringArr;
   profile:TUserProfile;
   i:integer;
   deck:array[1..50] of smallint;
  begin
   try
    result:='';
    CheckLogin;
    if userID<=0 then begin
     result:='ERROR'#9'You''re not logged in';
     exit;
    end;
    profile:=GetUserProfile;
    sa:=db.Query('SELECT name,data,cost FROM decks WHERE owner='+inttostr(profile.playerID)+' ORDER BY cost DESC');
    result:='OK';
    if db.rowCount=0 then begin
     result:=result+#9'You have no decks...';
     exit;
    end;
    for i:=0 to db.rowCount-1 do begin
     StrToDeck(sa[i*3+1],deck);
     result:=result+#9+HTMLString(sa[i*3])+#9+DescribeDeck(deck,true)+#9+sa[i*3+2];
    end;
   finally
    result:=FormatHeaders('text/html','')+result;
   end;
  end;

 function ListHeaders:AnsiString; stdcall;
  var
   i:integer;
   sa:stringArr;
   st:AnsiString;
  begin
   sa:=SplitA(#0,headers);
   st:='';
   for i:=0 to length(sa)-2 do begin
    if i and 3=2 then st:=st+'<tr>';
    if i and 3=0 then st:=st+'<tr style="background-color:#D8F0F0">';
    st:=st+'<td>'+sa[i];
   end;
   temp.Put('HEADERS_LIST',st);
   result:=FormatHeaders('text/html','','')+BuildTemplate('#MAINPAGE');
  end;

 function DumpData:AnsiString; stdcall;
  var
   st:AnsiString;
   i:integer;
  begin
   st:='All Players:'#13#10;
   for i:=1 to high(allPlayers) do
    if allPlayers[i].name<>'' then
     with AllPlayers[i] do
      st:=st+Format('%d %s %s [%s]'#13#10,[i,name,email,guild]);

   st:=st+#13#10+'All Guilds:'#13#10;
   for i:=1 to high(allGuilds) do
    if allGuilds[i].name<>'' then
     with allGuilds[i] do
      st:=st+Format('%d %d [%s] %d %d mCnt=%d leader=%d'#13#10,[i,place,name,level,exp,mcount,leader]);
      
   WriteFile('allPlayers.txt',@st[1],0,length(st));
   result:=FormatHeaders('text/html','','')+'OK!';
  end;

 function DuelStat:AnsiString; stdcall;
  var
   sa:AStringArr;
   info:AnsiString;
   UserID:AnsiString;
  begin
//   sa:=SplitA(#0,headers,#1);
   userID:=MakeNumber(Cookie('UserID'));
   sa:=db.Query('SELECT * FROM users WHERE id='+userid);
   info:=Join(sa,',');
   temp.Put('MAINTEXT','UserID: '+userID+'<br>'+info);
   result:=FormatHeaders('text/html','','')+BuildTemplate('#DUELSTAT');
  end;

 function IsAdmin(const p:TUserProfile):boolean;
  begin
   result:=pos('A',p.flags)>0;
  end;

 function IsModerator(const p:TUserProfile):boolean;
  begin
   result:=IsAdmin(p) or (pos('M',p.flags)>0);
  end;

 function InitSite:AnsiString; stdcall;
  begin
   result:='';
   LoadAllPlayersAndGuilds(true);
   //IndexAllForum;
   ForumChanged(100);
   DictInit('language.rus');
   InitForum;
  end;

 function SearchRequest:AnsiString;
  var
   cnt:integer;
   query:AnsiString;
  begin
   cnt:=StrToIntDef(param('cnt'),6);
   query:=param('q');
   clientlang:=Cookie('LANG');
   if clientlang='' then clientlang:='En';
   temp.Put('LANG',UpperCase(clientlang));
   temp.Put('LANG_LC',LowerCase(clientLang));
   result:=RunSearch(query,cnt);
   result:=FormatHeaders('text/html','','')+result;
  end;

 function IndexForumRequest:AnsiString;
  begin
   IndexAllForum;
   result:='OK';
  end;

var
 st:AnsiString;
initialization
 randomize;
 InitCritSect(gSect,'gSect');
end.
