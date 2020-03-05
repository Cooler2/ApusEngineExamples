unit forum;
interface
 uses MyServis,site;

 const
  // Thread flags
  threadClosed = 1;
  threadHidden = 2;
  threadSticked = 4;
  threadDeleted = 8;
  threadNews = 32;

  // Set of chapters where only admins/mds can post
  PrivChapters=[4];

  chapterURL:array[1..7] of AnsiString=('general','problems','offtopic','news','suggestions','guilds','tournaments');

 // Форматирует список рекомендуемых тем (html)
 function FormatSuggestedThreads(const profile:TUserProfile):AnsiString;
 // Форматирует сообщения темы (html)
 function FormatThread(id:integer;const profile:TUserProfile;start,count,msgToShow:integer):AnsiString;
  // Форматирует список тем
 function FormatChapter(id,skip,count:integer;const profile:TUserProfile):AnsiString;

 function FormatNews(const profile:TUserProfile):AnsiString;

 // Форматирует сообщения по заданному SQL-условию (html)
 // если cutNearMsgID>0 - сокращает (вырезает) сообщения вокруг указанного (или ближайшего к указанному)
 function FormatForumMessages(condition:AnsiString;const profile:TUserProfile;cutNearMsgID:integer=-1):AnsiString;

 // Возвращает текст ошибки либо пустую строку
 function CreateForumThread(chapter,guild:integer;title,lang:AnsiString;const profile:TUserProfile;out threadID:integer):AnsiString;
// function UpdateForumMessage(msgid:integer;msgtext,attachments:AnsiString;const profile:TUserProfile):AnsiString;
 function AddForumMessage(threadid:integer;msgtext,attachments:AnsiString;flags:integer;const profile:TUserProfile;var msgid:integer):AnsiString;

 // закрывает незакрытые теги, закрытие которых обязательно
 function CompleteHTML(st:AnsiString):AnsiString;

 procedure ValidateForumMessage(msg:AnsiString);

 procedure InitForum;

implementation
 uses SysUtils,TextUtils,SCGI,UCalculating,Logging,structs,Variants,RegExpr,database,Search,ranking,cnsts,UDict;

 const
  // список слов, которых внутри названий карт быть не может
  noCardWords:array[1..15] of WideString=('другой','другие','лично','светлый','светлые','светлая','светлое',
   'лицо','банки','монет','личка','фамилия','curve','close','молчит');
 var
  // названия карт на различных языках - в нижнем регистре
  cardNames:array[1..numcards,1..2] of WideString;

  // исходная и переведённая строка
  hintedStrings:array[0..255,0..1] of AnsiString;
  hintedIdx:integer;

 procedure InitForum;
  var
   i:integer;
   st1,st2,desc,name:AnsiString;
  begin
   st1:=''; st2:='';
   // English
   DictInit('');
   gSect.Enter;
   try
    ModifyCnsts;
    for i:=1 to numcards do begin
     if cardinfo[i].special then continue;
     name:=Simplify(cardinfo[i].name);
     cardNames[i,1]:=Lowercase(name);
     desc:=Simplify(cardInfo[i].desc);
     desc:=StringReplace(desc,'"','',[rfReplaceAll]);
     st1:=st1+Format('%d:{name:"%s", cost:%d, attack:%d, life:%d, price:%d, desc:"%s", file:"%s"},'#13#10,
       [i,name,cardinfo[i].cost,cardinfo[i].damage,cardinfo[i].life,cardinfo[i].mentalcost,desc,Simply(cardinfo[i].name)]);
    end;
    st1:='var cardList={'#13#10+st1+'0:{}};';
   finally
    gSect.Leave;
   end;
   // Russian
   DictInit('language.rus');
   gSect.Enter;
   try
    ModifyCnsts;
    for i:=1 to numcards do begin
     if cardinfo[i].special then continue;
     name:=Translate(cardinfo[i].name);
     cardNames[i,2]:=WideLowerCase(DecodeUTF8(name));
     desc:=Translate(cardInfo[i].desc);
     desc:=StringReplace(desc,'"','',[rfReplaceAll]);
     st2:=st2+Format('%d:{name:"%s", cost:%d, attack:%d, life:%d, price:%d,  desc:"%s", file:"%s"},'#13#10,
       [i,name,cardinfo[i].cost,cardinfo[i].damage,cardinfo[i].life,cardinfo[i].mentalcost,desc,Simply(cardinfo[i].name)]);
    end;
    st2:='var cardList={'#13#10+st2+'0:{}};';
   finally
    gSect.Leave;
   end;

   SaveFile('cardlist_en.js',@st1[1],length(st1));
   SaveFile('cardlist_ru.js',@st2[1],length(st2));
  end;

 function AllowedLangs:AnsiString;
  begin
   result:='"En"';
   if clientLang='RU' then result:=result+',"Ru"';
   result:=result+',"Cn","De","Es","It"';
  end;

 function CompleteHTML(st:AnsiString):AnsiString;
  var
   stack:array[1..50] of AnsiString;
   i,depth,mode:integer;
   tagname:AnsiString;
  begin
   result:=st;
   depth:=0; mode:=1;
   for i:=1 to length(st) do begin
    case mode of
     1:begin
        if (st[i]='<') then begin
         mode:=2;
         if (i<length(st)) and (st[i+1] in ['A'..'Z','a'..'z']) then begin
          tagname:=''; mode:=3;
         end;
         if (i<length(st)-1) and (st[i+1]='/') then begin
          tagname:=''; mode:=4;
         end;
        end;
       end;
     2:begin
        if st[i]='>' then mode:=1;
       end;
     3:begin
        if st[i]='>' then begin
         if tagname<>'' then begin
          inc(depth);
          stack[depth]:=lowercase(tagname);
         end;
         mode:=1;
        end;
        if (st[i] in ['A'..'Z','a'..'z','0'..'9']) then tagname:=tagName+st[i]
         else mode:=2;
       end;
     4:begin
        if st[i]='/' then continue;
        if (st[i] in ['A'..'Z','a'..'z','0'..'9']) then tagname:=tagName+st[i]
         else begin
          while depth>0 do begin
           dec(depth);
           if stack[depth+1]=lowercase(tagname) then break;
          end;
          mode:=2;
         end;
       end;
    end;
   end;
  end;

 // Заменяет названия карт в тексте на <dfn ...>...</dfn>
 function InsertCardHints(const msgText:AnsiString):AnsiString;
  var
   i,j,k,l,m,p,f,d1,d2,w,words:integer;
   text,s1,s2,cardname:WideString;
   ia:IntArray;
   skip,inTag:boolean;
  begin
   gSect.Enter;
   try
    // Поиск в кэше
    for i:=0 to high(hintedStrings) do
     if hintedStrings[i,0]=msgText then begin
      result:=hintedStrings[i,1];
      exit;
     end;
   finally
    gSect.Leave;
   end;

   // Трансляция 
   text:=DecodeUTF8(msgText);
   i:=0; inTag:=false;
   while i<length(text)-4 do begin
    inc(i);
    if text[i]='<' then inTag:=true;
    if text[i]='>' then inTag:=false;
    if inTag then continue;
    // может ли с i-й позиции начинаться название карты?
    if text[i]<'A' then continue;
    if (i>1) and ((text[i-1]>='A') or (text[i-1] in ['0'..'9'])) then continue;
    // если может - попробуем все варианты названий карт на всех языках
    s1:=WideLowercase(copy(text,i,3));
    for j:=1 to high(noCardWords) do
     if pos(noCardWords[j],s1)>0 then continue;

    words:=1;
    for w:=2 to length(s1) do
     if IsWordChar(s1[w]) and not IsWordChar(s1[w-1]) then inc(words);

    for j:=1 to high(cardNames) do
     for k:=1 to 2 do begin
      // Проверим, совпадают ли первые 3 буквы (с точностью до регистра)
      if s1<>copy(cardNames[j,k],1,3) then continue; // не совпадают - значит нет смысла проверять дальше
      cardname:=cardNames[j,k];
      // для некоторых карт требуется совпадение более чем 3-х начальных символов
      if (cardname='друид') or (cardname='монах') then begin
       if WideLowercase(copy(text,i,4))<>copy(cardNames[j,k],1,4) then continue;
      end;
      m:=i+length(cardname);
      while (m>i+1) and (text[m]<'A') do dec(m);
      while (m<length(text)) and (m<i+30) do
       if not (text[m]<'A') then inc(m)
        else break;
      s2:=WideLowercase(copy(text,i,m-i));

      d1:=GetWordsDistance(s2,cardname);
      // для английского допустима разница в 1 символ, для русского - кол-во слов+1
      if (d1>words+1) or ((d1>1) and (k=1)) then continue;

      // Слово больше похоже на нормальное, чем на карту?
      skip:=false;
      for l:=1 to high(noCardWords) do
       if GetWordsDistance(s2,noCardWords[l])<d1 then begin
        skip:=true;
        break;
       end;
      if skip then continue; 

      // Теперь сделаем замену
      Insert('</dfn>',text,m);
      s2:='<dfn onMouseOver="ShowCardHint(this,'+inttostr(j)+')" onMouseOut="HideCardHint()">';
      Insert(s2,text,i);
      i:=m+length(s2)+6;
     end;
   end;

   result:=EncodeUTF8(text);

   gSect.Enter;
   try
    // Сохранение в кэше
    hintedStrings[hintedIdx,0]:=msgText;
    hintedStrings[hintedIdx,1]:=result;
    inc(hintedIdx);
    if hintedIdx>high(hintedStrings) then hintedIdx:=0;
   finally
    gSect.Leave;
   end;
  end;

 function FormatForumMessages(condition:AnsiString;const profile:TUserProfile;cutNearMsgID:integer=-1):AnsiString;
  var
   key,key2,list,msgtext,author,pFlags:AnsiString;
   messages:THash;
   profiles:THash;
   players:THash;
   attachments:THash;
   lastread:THash;
   plrID,profileID,face,topicID:variant;
   i,n,cnt:integer;
   attList,lrd,levelLabel:AnsiString;
   arr:IntArray;
   attType,attThumb:AnsiString;
   moderator:boolean;
   r1,r2:TRegExpr;
   date:TDateTime;
   skipFrom,skipTo,SkipAfter:integer;
  begin
   try
   moderator:=IsModerator(profile);
   // Получим все сообщения по переданному условию
   db.QueryHash(messages,'messages','id','msg,created,author,authorname,flags,score,topic',condition);
   // требуется урезание?
   skipFrom:=0; skipTo:=0; skipAfter:=99999;
   if (messages.count>40) and (cutNearMsgID>=0) then begin
    // 1. Найти индекс сообщения в списке
    key:=IntToStr(cutNearMsgID);
    n:=0;
    while n<messages.count-1 do
     if messages.keys[n]=key then break
      else inc(n);
    // 2. Удалить сообщения ПЕРЕД указанным сообщением, если это необходимо
    if n>24 then begin
     skipFrom:=1;
     skipTo:=n-1;
     if skipTo>messages.count-9 then skipTo:=messages.count-9; 
    end;
    // 3. Удалить сообщения ПОСЛЕ указанного, если это необходимо
    if messages.count>n+30 then
     skipAfter:=n+20;
   end;

   // Прикреплённые файлы (если есть)
   attachments.Init(true);
   lastread.Init(true);
   n:=-1;
   for key in messages.keys do begin
    inc(n);
    if (n>=skipFrom) and (n<skipTo) or (n>skipAfter) then continue;
    topicID:=messages.Get(key,6);
    lastRead.Put(topicID,0,true);
    msgtext:=messages.Get(key,0);
    i:=pos('<!-- ATTACHED:',msgtext);
    if i>0 then begin
      attList:=copy(msgtext,i+14,50);
      i:=pos('-->',attList);
      SetLength(attList,i-1);
      arr:=StrToArray(attList);
      for i:=0 to high(arr) do
        attachments.Put(IntToStr(arr[i]),0,true);
    end;
   end;
   db.QueryValues(attachments,'attachments','id','msg,filename,filesize,thumbnail,th_width,th_height,filetype');
   db.QueryValues(lastRead,'lastread','topic','msg',false,'user='+IntToStr(userID));

   // перечислим всех авторов, имеющихся в теме
   profiles.Init(true);
   n:=-1;
   for key in messages.keys do begin
    inc(n);
    if (n>=skipFrom) and (n<skipTo) or (n>skipAfter) then continue;
    profiles.Put(messages.Get(key,2),0,true);
   end;
   // запросим инфу об этих авторах
   db.QueryValues(profiles,'profiles','id','name,playerID,network,networkid,avatar,flags');

   // Кто из авторов имеет игровой аккаунт?
   players.Init(true);
   for key in profiles.keys do begin
    plrID:=profiles.Get(key,1);
    if plrID>0 then players.Put(plrID,0,true);
   end;
   db.QueryValues(players,'players','id','level,name,CardsCount(cards),avatar');

   // Регэкспы
   r1:=TRegExpr.Create;
   r1.Expression:='<blockquote title="(.*?),(.*?)">(.*?)<\/blockquote>';
   r1.ModifierI:=true;
   r1.ModifierG:=true;

   r2:=TRegExpr.Create;
   r2.Expression:='<!-- UPDATED:(.+):(.+) -->';
   r2.ModifierI:=true;

   // Сформировать список сообщений, вставив в шаблон необходимые значения
   levelLabel:=BuildTemplate('$LABEL_LEVEL');
   n:=-1;
   for key in messages.keys do begin
     inc(n);
     if (n>=skipFrom) and (n<skipTo) then begin
      // Нужно вставить разрывы
      if n=skipFrom then begin
       cnt:=skipTo-skipFrom;
       i:=skipFrom;
       while cnt>30 do begin
        temp.Put('SKIPPED_RANGE',inttostr(i)+'..'+inttostr(i+19));
        result:=result+BuildTemplate('$FORUM_SKIPPED_MSGS');
        inc(i,20); dec(cnt,20);
       end;
       temp.Put('SKIPPED_RANGE',inttostr(i)+'..'+inttostr(i+cnt-1));
       result:=result+BuildTemplate('$FORUM_SKIPPED_MSGS');
      end;
      continue;
     end;
     if n>skipAfter then begin
      cnt:=messages.count-skipAfter;
      i:=skipAfter;
      while cnt>30 do begin
       temp.Put('SKIPPED_RANGE',inttostr(i)+'..'+inttostr(i+19));
       result:=result+BuildTemplate('$FORUM_SKIPPED_MSGS');
       inc(i,20); dec(cnt,20);
      end;
       temp.Put('SKIPPED_RANGE',inttostr(i)+'..'+inttostr(i+cnt-1));
      result:=result+BuildTemplate('$FORUM_SKIPPED_MSGS');
      break;
     end;

     temp.Put('MSG_ID',key);
     face:=0;
     profileID:=messages.Get(key,2);
     topicID:=messages.Get(key,6);
     face:=profiles.Get(profileID,4);
     if face='' then face:=0;
     author:=messages.Get(key,3);
     plrID:=profiles.Get(profileID,1);
     pFlags:=profiles.Get(profileID,5);
     if plrID>0 then begin
      // Профиль соответствует аккаунту игрока
      face:=players.Get(plrID,3);
      author:=author+', '+levelLabel+' '+VarToStr(players.Get(plrID,0));
      author:='<a href=''javascript:ShowPlayerProfile("'+players.Get(plrID,1)+'")''>'+author+'</a>';
     end;
     if pos('A',pFlags)>0 then begin
      author:=author+templates.Get('AUTHOR_ADMIN_MARK');
     end else
     if pos('M',pFlags)>0 then begin
      author:=author+templates.Get('AUTHOR_MODERATOR_MARK');
     end;
     temp.Put('FACE_ID',face);
     temp.Put('AUTHOR',author);
     temp.Put('CREATED',messages.Get(key,1));
     temp.Put('MSGRATE',messages.Get(key,5));
     temp.Put('IS_NEWMSG','');
     temp.Put('CAN_EDIT',moderator OR ((userID>0) and (profileID=userID)),true);
     if userid>0 then begin
      lrd:=lastRead.Get(topicID);
      if lrd<>'' then
       if (StrToInt(key)>StrToInt(lrd)) then temp.Put('IS_NEWMSG',true);
     end;
     msgtext:=messages.Get(key,0);
     msgText:=InsertCardHints(msgText);
     // Цитаты
     msgText:=r1.Replace(msgText,'<div class=QuoteAuthor> <span>$1 wrote:</span></div><blockquote>$3</blockquote>',true);
     // Обновления
     if r2.Exec(msgText) then begin
       date:=ParseTimeStamp(r2.Substitute('$2'));
       msgText:=r2.Replace(msgText,'<div class="small gray">Updated by $1 on '+FormatDate(date)+'UTC </div>',true);
     end;

     // Аттачи
     attList:='';
     for key2 in attachments.keys do
      if attachments.Get(key2,0)=key then begin
       attType:=attachments.Get(key2,6);
       attThumb:=attachments.Get(key2,3);
       if attThumb='' then attThumb:='picture.gif';
       attList:=attList+'<td><a target="_blank" href="/getfile?id='+key2+
         '"><img id=AThumb'+key2+' class=attached src="/attach/'+attThumb+
         '" width='+attachments.Get(key2,4)+' height='+attachments.Get(key2,5)+
         ' alt="'+attachments.Get(key2,1)+'" title="'+attachments.Get(key2,1)+'"></a>';
      end;
     if attList<>'' then msgText:=msgText+templates.Get('ATTACHMENTS')+attList+'</table>'; 

     temp.Put('MSGTEXT',msgtext);
     result:=result+BuildTemplate('#FORUM_MESSAGE');
   end;
   r1.Free;
   r2.Free;
   except
    on e:Exception do begin
     LogMsg('Error in FormatForumMessages '+condition,logError);
     raise E500.Create('');
    end;
   end;
  end;

 function FormatThread(id:integer;const profile:TUserProfile;start,count,msgToShow:integer):AnsiString;
  var
   sa,sb:StringArr;
   lastread,msgcount,flags,guild:integer;
   i,cols:integer;
   title:AnsiString;
  begin
   lastRead:=0;
   guild:=0;
   if id>0 then begin
    // Реальная тема
    if userID>0 then begin
      sa:=db.Query('SELECT msg FROM lastread WHERE topic=%d AND user=%d',[id,userID]);
      if db.rowCount>0 then lastRead:=StrToIntDef(sa[0],0);
    end;
    sa:=db.Query('SELECT title,lang,chapter,flags,lastmsg,msgcount,guild FROM topics WHERE id='+inttostr(id));
    if db.rowCount<>1 then begin
      result:='<h2>Thread not found!</h2>';
      exit;
    end;
    flags:=StrToIntDef(sa[3],0);
    if flags and 1>0 then temp.Put('THREAD_CLOSED',true);
    guild:=StrToIntDef(sa[6],0);
    if guild>0 then
     if not (IsAdmin(profile) or (profile.guild<>'') and (allGuilds[guild].name=profile.guild)) then begin
      result:='<h3>Oops! Access denied!</h3><div align=center style="padding:10px;">This thread is private. </div>';
      exit;
     end;
   end else begin
    // Виртуальная тема: создание новой темы
    SetLength(sa,3);
    sa[0]:=BuildTemplate('$TITLE_NEW_THREAD');
    sa[1]:=''; sa[2]:=IntToStr(IntParam('chapter'));
   end;
   if count=0 then begin
    // Вся тема (возможно сокращенная)
    // Thread title
    title:=HTMLString(sa[0]);
    if guild>0 then title:=BuildTemplate('$FORUM_GUILD_MARK_BIG')+title;
    result:=Format('<!-- LASTREAD=%d --><input type=hidden id=THREADLANG%d value=%s>'#13#10,[lastRead,id,UpperCase(sa[1])])+
      BuildTemplate(Format('<h2>$FORUM_HOME_LINK $FORUM_TITLE_ARROW '+
      '$FORUM_CHAPTER_LINK%s $FORUM_TITLE_ARROW %s</h2>',[sa[2],title]));
    if msgToShow>0 then lastRead:=msgToShow;
    result:=result+FormatForumMessages('topic='+inttostr(id)+' ORDER BY id',profile,lastRead);
   end else begin
    // Отдельный диапазон сообщений
    result:=FormatForumMessages('topic='+inttostr(id)+' ORDER BY id LIMIT '+inttostr(start)+','+inttostr(count),profile);
   end;
  end;

 function FormatChapter(id,skip,count:integer;const profile:TUserProfile):AnsiString;
  var
   sa:StringArr;
   i,c,flags,msgcount,guild:integer;
   date:TDateTime;
   tName,mark,unread,threadID,cls:AnsiString;
   lastRead:THash;
   threadRead:boolean;
   moderator:boolean;
  begin
   result:='';
   moderator:=IsModerator(profile);
   // LastRead
   lastRead.Init(true);
   if userID>0 then
    db.QueryHash(lastRead,'messages,lastread,topics','topics.id','count(*)','lastread.user='+IntToStr(userID)+
     ' AND topics.id=lastread.topic AND messages.topic=topics.id AND messages.id>=lastread.msg GROUP BY topics.id');

   sa:=db.Query('SELECT id,title,lang,flags,lastmsg,msgcount,updated,guild '+
    ' FROM topics WHERE chapter=%d AND lang IN ('+AllowedLangs+')'+
    ' ORDER BY (flags & 4) DESC,guild DESC,updated DESC'+
    ' LIMIT %d,%d',[id,skip,count]);
   c:=db.colCount;

   for i:=0 to db.rowCount-1 do begin
    threadRead:=false;
    threadID:=sa[i*c];
    tName:='<a href="/'+lowercase(clientLang)+'/forum/thread/'+threadID+'">'+HTMLString(sa[i*c+1])+'</a>';
    flags:=StrToIntDef(sa[i*c+3],0);
    mark:='';
    // Guild private
    guild:=StrToIntDef(sa[i*c+7],0);
    if guild>0 then
     if not (moderator or (profile.guild=allGuilds[guild].name)) then continue;


    // Flags
    if flags and 8>0 then // deleted
     if moderator then tName:='<del>'+tname+'</del>'
      else continue;

    if (flags and 2>0) then // hidden
     if moderator then tName:='<i>'+tName+'</i>'+templates.Get('FORUM_HIDDEN_MARK_BIG')
      else continue;

    if guild>0 then mark:=templates.Get('FORUM_GUILD_MARK');

    if flags and 1>0 then tName:=tName+templates.Get('FORUM_CLOSED_MARK_BIG');
    if flags and 4>0 then mark:=mark+templates.Get('FORUM_PINNED_MARK_BIG');
    date:=GetDateFromStr(sa[i*c+6]);
    msgcount:=StrToIntDef(sa[i*c+5],0);
    unread:=lastRead.Get(threadID);
    if unread<>'' then begin
     if unread='1' then begin
      threadRead:=true;
      unread:=IntToStr(msgcount-1);
     end else
      unread:=Format('<span class=UnreadCnt>%d</span> / %d',[StrToIntDef(unread,1)-1,msgcount-1]);
    end else
     unread:=IntToStr(msgcount-1);

    // Moderation
    if IsModerator(profile) then tName:=tName+'<span class=ModThread thread='+threadID+'>&#xf044;</span>';

    if threadRead then cls:='"ThreadRow ThreadRead"' else cls:='ThreadRow';
    result:=result+Format('<tr id=THREADROW%s class=%s><td>%s<td>%s<td>%s<td>%s',
      [threadID,cls,mark,tname,unread,FormatDate(date)]);
   end;
  end;


 function FormatSuggestedThreads(const profile:TUserProfile):AnsiString;
  var
   i,j,id,flags,guild:integer;
   sa,sb:StringArr;
   cnt,cols,newCount:integer;
   tList,newMsgs,tName,langs:AnsiString;
   newCnt,lastRead:TSimpleHash;
   updated:TDateTime;
  begin
   result:='';
   try
    // 1. Составить список новых тем (скрытые темы будут выкинуты позднее)
    sa:=db.Query('SELECT id,title,flags,msgcount,updated,chapter,lang,lastmsg,guild '+
      'FROM topics WHERE lang in ('+AllowedLangs+') AND (flags & 10=0) ORDER BY (flags & 4) DESC,updated DESC LIMIT 30');
    cnt:=db.rowCount;
    cols:=db.colCount;

    // 2. Юзер авторизован? Узнать какие темы и насколько он прочитал
    newCnt.Init(40); // threadID -> number of new messages
    lastRead.Init(40); 
    if userID>0 then begin
     tList:='';
     for i:=0 to cnt-1 do tList:=tList+sa[i*cols]+',';
     SetLength(tList,length(tList)-1);

     sb:=db.Query('SELECT topics.id,count(*) FROM messages,lastread,topics '+
       'WHERE topics.id IN (%s) AND lastread.user=%d AND topics.id=lastread.topic AND '+
       'messages.topic=topics.id AND messages.id>lastread.msg GROUP BY topics.id',
       [tList,profile.id]);
     for i:=0 to db.rowCount-1 do
      newCnt.Put(StrToIntDef(sb[i*2],0),StrToIntDef(sb[i*2+1],0));

     sb:=db.Query('SELECT topic,msg FROM lastread WHERE user=%d AND topic in (%s)',[profile.id,tList]);
     for i:=0 to db.rowCount-1 do
      lastRead.Put(StrToIntDef(sb[i*2],0),StrToIntDef(sb[i*2+1],0));
    end;

    // 3. Отформатировать список тем
    for i:=0 to cnt-1 do begin
     id:=StrToIntDef(sa[i*cols],0);
     flags:=StrToIntDef(sa[i*cols+2],0);
     guild:=StrToIntDef(sa[i*cols+8],0);
     if guild>0 then // видно если ЛИБО админ ЛИБО название гильдии совпадает с гильдией визитора 
      if not (IsAdmin(profile) or (profile.guild<>'') and (allGuilds[guild].name=profile.guild)) then continue; // not allowed to see this guild
     temp.Put('THREAD_ID',sa[i*cols],true);
     tname:=HtmlString(sa[i*cols+1]);
     if flags and 4>0 then tname:=templates.Get('FORUM_PINNED_MARK')+tname;
     if guild>0 then tname:=templates.Get('FORUM_GUILD_MARK')+tname;
     temp.Put('THREAD_NAME',tName,true);
     temp.Put('MSGCOUNT',sa[i*cols+3],true);
     updated:=GetDateFromStr(sa[i*cols+4]);
     temp.Put('LAST_UPDATE',FormatDate(updated),true);
     j:=StrToIntDef(sa[i*cols+7],0); // lastMsg
     newMsgs:=''; newCount:=-1;
     if newCnt.HasValue(id) then begin
       newCount:=newCnt.Get(id);
       newMsgs:=Format(' (<span class=newmsg>%d new</span>)',[newCount]);
     end;
     temp.Put('NEWMSG',newMsgs,true);
     if (newCount>0) or (not lastRead.HasValue(id)) then
      result:=result+BuildTemplate('#FORUM_THREAD_ITEM')
     else
      result:=result+BuildTemplate('#FORUM_THREAD_ITEM_READ'); // в теме всё прочитано
    end;

   except
    on e:Exception do LogMsg('Error in FormatSuggestedThreads: '+ExceptionMsg(e));
   end;
  end;

 // Обработка сообщения, если что не так - кинет исключение с текстом
 procedure ValidateForumMessage(msg:AnsiString);
  const
   alpha=['A'..'Z','a'..'z'];
   alphaNum=['A'..'Z','a'..'z','0'..'9'];
  var
   i,state:integer;
   tag,attribute,value:AnsiString;
   countA,countBQ:integer;
  procedure CheckTagName;
   begin
    tag:=lowercase(tag);
    if (tag='div') or (tag='span') or (tag='p') or (tag='br') or (tag='blockquote') or
       (tag='strong') or (tag='em') or (tag='ul') or (tag='ol') or (tag='li') or
       (tag='tt') or (tag='a') or (tag='h2') or (tag='h3') or (tag='h4') or (tag='h5') or
       (tag='b') or (tag='i') or (tag='u') or (tag='img') or (tag='dfn') or (tag='s') or
       (tag='time') or (tag='pre') then exit;
    LogMsg('Unallowed tag: '+tag+' in '+msg,logInfo);
    raise Exception.Create('Unallowed HTML code (tag "'+tag+'" not allowed)');
   end;
  procedure CheckAttribute;
   begin
    attribute:=lowercase(attribute);
    if (attribute='class') or (attribute='style') or (attribute='title') or
       (attribute='href') or (attribute='src') or (attribute='target') or (attribute='alt') or
       (attribute='align') or (attribute='valign') or  (attribute='id')  then exit;
    LogMsg('Unallowed attribute: '+attribute+' in '+msg,logInfo);
    raise Exception.Create('Unallowed HTML code (attribute "'+attribute+'" not allowed)');
   end;
  procedure CheckValue;
   begin
    // Допустимы только локальные адреса
    if attribute='src' then begin
     if (length(value)<3) or (value[1]<>'/') or not (value[2] in alphanum) then begin
       LogMsg('Unallowed src value: '+value,logInfo);
       raise Exception.Create('Unallowed HTML code (src="'+value+'" not allowed)');
     end;
    end;
    // Недопустим никакой код
    if attribute='href' then begin
     value:=lowercase(value);
     if pos('http://',value)=1 then exit;
     if pos('https://',value)=1 then exit;
     LogMsg('Unallowed href value: '+value,logInfo);
     raise Exception.Create('Unallowed HTML code (link "'+value+'" not allowed)');
    end;
   end;
  begin
   state:=0; // текст
   countA:=0; countBQ:=0;
   for i:=1 to length(msg) do begin
    case state of
     // plain text
     0:begin
        if (msg[i]='<') and (i<length(msg)) and (msg[i+1] in alpha) then begin
         tag:=''; attribute:=''; value:='';
         state:=1; // tag (opening)
        end;
        if (msg[i]='<') and (i<length(msg)) and (msg[i+1]='/') then begin
         tag:=''; attribute:=''; value:='';
         state:=10; // tag (closing)
        end;
       end;
     // tag begin
     1:if msg[i] in alphaNum then tag:=tag+msg[i]
        else begin
         CheckTagName;
         if (tag='a') then inc(countA);
         if (tag='blockquote') then inc(countBQ);
         if msg[i]='>' then state:=0
          else state:=2; // before attributes
         attribute:='';
        end;
     2:if msg[i]>' ' then begin
         if (msg[i]='>') then state:=0;
         if (msg[i]='=') then begin
          CheckAttribute;
          value:='';
          state:=3; // value
         end else
          attribute:=attribute+msg[i];
       end;
     3:begin
         if msg[i]='"' then state:=4 else
         if msg[i]='''' then state:=5 else
         if (msg[i]>' ') and (msg[i]<>'>') then value:=value+msg[i]
          else begin
           CheckValue;
           state:=2;
           value:='';
           attribute:='';
          end;
       end;
     4:begin
         if msg[i]<>'"' then value:=value+msg[i]
           else begin
             CheckValue;
             state:=2;
             attribute:=''; value:='';
           end;
       end;
     5:begin
         if msg[i]<>'''' then value:=value+msg[i]
           else begin
             CheckValue;
             state:=2;
             attribute:=''; value:='';
           end;
       end;
     10:begin
          if msg[i]='/' then continue;
          if msg[i] in alphaNum then
            tag:=tag+msg[i]
          else begin
            CheckTagName;
            if (tag='a') then dec(countA);
            if (tag='blockquote') then dec(countBQ);
            if msg[i]='>' then state:=0
             else state:=11;
          end;
        end;
     11:if msg[i]='>' then state:=0;
    end;
   end;
   if (countA<>0) or (countBQ<>0) then begin
    LogMsg('Unclosed tags',logInfo);
    raise Exception.Create('Unallowed HTML code (9)');
   end;
  end;

 // Процессинг текста сообщения перед отправкой
 procedure PreprocessMessage(var msg:AnsiString);
  var
   r:TRegExpr;
   msgid,info,href,suffix:AnsiString;
   sa:StringArr;
   links:StringArr;
   i,ps:integer;
  begin
   // Quotes
   r:=TRegExpr.Create;
   r.ModifierI:=true;
   r.expression:='<blockquote title="*(\d+)"*>';
   while r.Exec(msg) do begin
    msgid:=r.Substitute('$1');
    sa:=db.Query('SELECT authorname,created FROM messages WHERE id='+SqlSafe(msgid));
    info:='';
    if db.rowCount=1 then info:=sa[0]+', '+sa[1];
    msg:=r.Replace(msg,'<blockquote title="'+info+'">',false,false);
   end;
   r.Free;

   // всякая ненужная фигня (удалить)
   msg:=ReplaceRegExpr('<div>(\s|&nbsp;)*<\/div>',msg,'<br>',false);
   msg:=ReplaceRegExpr('<div>(\s|&nbsp;)*<\/div>\s*$',msg,'',false);

   // Links
(*   SetLength(links,0);
   r:=TRegExpr.Create;
   r.ModifierI:=true;
   r.expression:='(\w+:\/\/|www\.)([\@\w\d\/\.,\-=_?&#\%+]+)';
   r.InputString:=msg;
   ps:=1;
   while r.ExecPos(ps) do begin
    i:=r.MatchPos[2]+r.matchLen[2];
    LogMsg('Link replacement: '+r.Match[1]+r.Match[2]);
    ps:=i; suffix:='';
    // ссылка в кавычках либо в тэге <a> - не обрабатывать
    if (i<length(msg)) and
     ((msg[i]='"') or (copy(msg,i,4)='</a>')) then continue;
    href:=r.Substitute('$1')+r.Substitute('$2');
    if href[length(href)] in ['.','?','!'] then begin
     suffix:=href[length(href)];
     SetLength(href,length(href)-1);
    end;
    info:=href;
    if length(info)>70 then begin
     SetLength(info,60);
     info:=info+'...';
    end;
    if pos('://',href)=0 then href:='http://'+href;
    AddString(links,'<a href="'+href+'" target=_blank>'+info+'</a>');
    msg:=r.Replace(msg,'~({LiNK})~'+suffix,false,false);
   end;
   r.Free;
   for i:=0 to high(links) do
    msg:=StringReplace(msg,'~({LiNK})~',links[i],[]);     *)
  end;

 function CreateForumThread(chapter,guild:integer;title,lang:AnsiString;const profile:TUserProfile;out threadID:integer):AnsiString;
  begin
   result:='Unknown failure';
   if (chapter in PrivChapters) and not IsModerator(profile) then begin
    result:='You have no right to create thread in this chapter'; exit;
   end;
   try
    db.Query('INSERT INTO topics (title,chapter,lang,guild) values("%s",%d,"%s",%d)',
      [SQLSafe(title),chapter,SqlSafe(lang),guild]);
    if db.lastError='' then threadID:=db.insertID;
    result:='';
    ForumChanged(10);

   except
    on e:Exception do begin
     LogMsg('Error in CreateForumThread: '+ExceptionMsg(e));
     result:=ExceptionMsg(e);
    end;
   end;
  end;

 function AddForumMessage(threadId:integer;msgtext,attachments:AnsiString;flags:integer;const profile:TUserProfile;var msgid:integer):AnsiString;
  var
   thr:StringArr;
   threadFlags:integer;
   attList:IntArray;
   edited:boolean;
   wst:WideString;
   notify1,notify2:TSimpleHashS;
   sa:StringArr;
   i,f:integer;
  begin
   result:='Unknown failure';
   wst:=DecodeUTF8(msgtext);
   if length(wst)>12000 then begin
    result:='Your message is too large! If you really want to post so much text, consider splitting it into few separate messages.';
    exit;
   end;
   edited:=msgid>0;
   try
    thr:=db.Query('SELECT flags,chapter,lang FROM topics WHERE id='+inttostr(threadID));
    if db.rowCount<>1 then raise Exception.Create('Invalid thread ID');
    threadFlags:=StrToIntDef(thr[0],0);
    if threadFlags and 1>0 then raise Exception.Create('Thread closed!');

    ValidateForumMessage(msgText);
    PreprocessMessage(msgText);
    msgText:=StringReplace(msgText,'-=cut=-','<!-- CUT -->',[]);
    if attachments<>'' then begin
     attList:=StrToArray(attachments,';');
     if attList[high(attList)]=0 then SetLength(attList,length(attList)-1);
     msgText:=msgText+'<!-- ATTACHED:'+ArrayToStr(attList)+'-->';
    end;

    if not edited then begin
     db.Query('INSERT INTO messages (topic,msg,author,authorname,ip,flags,created) '+
       'values(%d,"%s",%d,"%s","%s",%d,UTC_TIMESTAMP())',
       [threadId,SqlSafe(msgText),userID,profile.name,clientIP,flags]);
     if db.lastErrorCode<>0 then raise Exception.Create('Database error');
     msgid:=db.insertID;
     db.Query('INSERT INTO fchanges (item,userid,operation) values(%d,%d,1)',[msgid,userid]);
     db.Query('UPDATE topics SET msgcount=msgcount+1,lastmsg=%d WHERE id=%d',[msgid,threadid]);
    end else begin
     msgText:=msgText+Format('<!-- UPDATED:%s:%s -->',[profile.name,CurrentTimeStamp]);
     db.Query('UPDATE messages SET msg="%s",flags=%d WHERE id=%d ',
       [SqlSafe(msgText),flags,msgID]);
     if db.lastErrorCode<>0 then raise Exception.Create('Database error');
     db.Query('INSERT INTO fchanges (item,userid,operation) values(%d,%d,3)',[msgid,userid]);
    end;
    ForumChanged(20);

    // Аттачи
    attList:=StrToArray(attachments,';');
    if length(attList)>0 then begin
      db.Query('DELETE FROM attachments WHERE msg=%d AND id NOT IN (%s)',[msgid,ArrayToStr(attList)]);
      db.Query('UPDATE attachments SET topic=%d, msg=%d WHERE id IN (%s) AND topic=0',
       [threadID,msgid,ArrayToStr(attList)]);
    end;
    result:='';

    if not edited then begin
     // Уведомления
     // 1. Всем, кто подписался на тему
     notify2.Init(50);
     sa:=db.Query('SELECT author,flags FROM messages WHERE topic=%d AND flags&3>0');
     for i:=0 to db.rowCount-1 do begin
      f:=StrToIntDef(sa[i*2+1],0);
      if f and 2>0 then notify2.Put(sa[i*2],2);
      if f and 1>0 then notify1.Put(sa[i*2],1);
     end;
     // 2. Всем, кто указан в цитатах
    end;

   except
    on e:Exception do begin
     LogMsg('Error in AddForumMessage: '+ExceptionMsg(e));
     result:=ExceptionMsg(e);
    end;
   end;
  end;

 function FormatNews(const profile:TUserProfile):AnsiString;
  var
   i,n,c,id,cnt,j,flags:integer;
   sa,sb:StringArr;
   title,text,comLink:AnsiString;
   date:TDateTime;
   plain:WideString;
  begin
   result:='Unknown failure';
   try
    sa:=db.Query('SELECT id,title,msgcount,flags FROM topics '+
      'WHERE chapter=4 AND lang="'+clientLang+'" AND (flags & 10=0) ORDER BY (flags & 4) DESC, id DESC LIMIT 5');
    if db.lastErrorCode<>0 then raise Exception.Create('DB error: '+db.lastError);
    n:=db.rowCount;
    c:=db.colCount;
    result:='';
    for i:=0 to n-1 do begin
     id:=StrToIntDef(sa[i*c],0);
     title:=sa[i*c+1];
     cnt:=StrToIntDef(sa[i*c+2],1)-1;
     flags:=StrToIntDef(sa[i*c+3],0);
     sb:=db.Query('SELECT msg,created FROM messages WHERE topic='+inttostr(id)+' ORDER BY id LIMIT 1');
     if (db.lastErrorCode<>0) or (length(sb)<2) then continue;
     temp.Put('NEWS_ID',id,true);
     date:=GetDateFromStr(sb[1]);
     temp.Put('NEWS_DATE',FormatDate(date,true),true);
     temp.Put('NEWS_TITLE',title,true);
     temp.Put('NEWS_PINNED',flags and 4>0,true);
     text:=sb[0];
     text:=ReplaceRegExpr('<\/div>\s*<div.*?>',text,'<br>',false);
     text:=ReplaceRegExpr('<\/div>',text,'',false);
     text:=ReplaceRegExpr('<div.*?>',text,'',false);
     plain:=DecodeUTF8(ExtractPlainText(text));
     comLink:='';
     if (length(plain)>800) or ((length(plain)>500) and (i>0)) then begin
      j:=pos('<!-- CUT -->',text);
      if j>0 then SetLength(text,j-1);
      text:=CompleteHTML(text);
      text:=text+'...';
      comLink:='$LNK_READ_MORE | ';
     end;
     if cnt>0 then
      comLink:=comLink+inttostr(cnt)+' $LNK_COMMENTS'
     else
      comLink:=comLink+'$LNK_LEAVE_COMMENT';
 
     temp.Put('NEWS_TEXT',text,true);
     temp.Put('COMMENTS',comLink,true);
     result:=result+BuildTemplate('#NEWSFEED_ITEM');
    end;

   except
    on e:Exception do begin
     LogMsg('Error in FormatNews: '+ExceptionMsg(e));
     result:='Internal error';
    end;
   end;
  end;

initialization

end.
