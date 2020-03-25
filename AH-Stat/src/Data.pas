unit Data;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
 uses MyServis,Structs;

var
 isBusy:integer=0; // busy state semaphor

type
 // Колода (массив номеров карт)
 TDeck=array[1..25] of smallint;

 // Запись об одном бое
 TDuelRec=record
  id:integer;
  date:TDateTime;
  winner,loser:integer;
  dueltype,scenario,winnerLevel,loserLevel,firstPlr,turns:shortint;
  duration,winnerFame,loserFame:smallint;
  decks:array of TDeck; // если игра с колодами - массив [0..1], где 1 - winner, 0 - loser
 end;

 // запись из EventLog
 TEventRec=record
  id,playerID:integer;
  created:TDateTime;
  event:string[15];
  info:String8;
 end;

 // Завершённый платёж
 TPaymentRec=record
  id,playerID:integer;
  created:TDateTime;
  username:String[19];
  itemCode:String[7];
  amount:single;
  currency,country:String[3];
  method:String[19];
  transaction:int64;
  // Derived data
  amountUSD:single;
  payMethod:String8; // всё что известно про метод платежа (например "Steam->Webmoney")
 end;

 // Игровой аккаунт
 TPlayerRec=record
  id:integer;
  name,email,guild:String8;
  pwd,flags:String[15];
  lang:String[3];
  created,lastvisit,premium:TDateTime;
  avatar,gold:integer;
  gems,AP,hero,needHero:smallint;
  fame:array[0..3] of smallint;     // 0 - total
  level:array[0..3] of shortint;
  realname,location,about:String8;
  wins,loses:array[0..3] of word;
  dtWins,cardsCount:smallint;
  tags,cards:String8;
  referer,paramX,optFlags:integer;
  HP,speciality,campaignWins,room:shortint;
  quests,campaignLoses,friendlist,blacklist,missions,market:String8;

  // Derived data - эти поля не хранятся в базе, а вычисляются дополнительно
  clientLang:String[3]; // язык выбранный в клиенте,
  regCountry,lastCountry:String[3]; // страна на момент регистрации, страна последней сессии
  isSteam:byte; // 1:0
  paidAmount:single; // сколько всего игрок задонатил $
  osVersion,videocard,openGL:String8; // информация по последней сессии игрока
 end;

 TVisitRec=record
  id:integer;
  vid:int64;
  date:TDateTime;
  ip:String[15];
  country:String[3];
  playerID:integer;
  page,referer,tags:String8;
 end;

 TGuildRec=record
  id:integer;
  name:String8;
  size,level,daily:shortint;
  exp,treasures,flags:integer;
  bonuses,cards:String[20];
 end;

 TGuildMember=record
  plrID,guildID:integer;
  treasures,exp:integer;
  rank:shortint;
 end;

 TGuildLog=record
  guildID:integer;
  date:TDateTime;
  msg:String8;
 end;

 var
  duels:array of TDuelRec;
  events:array of TEventRec;
  payments:array of TPaymentRec;
  players:array of TPlayerRec;
  visits:array of TVisitRec;
  guilds:array of TGuildRec;
  guildMembers:array of TGuildMember;
  guildlog:array of TGuildLog;

  // Индексы
  //playerID -> player index
  playerIDhash:TSimpleHash;
  maxPlayerID:integer;

  dataAddLogMsg:procedure(st: String8);

 procedure LoadAllDuels(fname:String8);
 function SaveAllDuels(fname:String8):integer;

 procedure LoadAllEvents(fname:String8);
 function SaveAllEvents(fname:String8):integer;

 procedure LoadAllPayments(fname:String8);
 function SaveAllPayments(fname:String8):integer;

 procedure LoadAllPlayers(fname:String8);
 function SaveAllPlayers(fname:String8):integer;

 procedure LoadAllVisits(fname:String8);
 function SaveAllVisits(fname:String8):integer;

 procedure LoadAllGuilds(fname:String8);
 function SaveAllGuilds(fname:String8):integer;

 procedure LoadAllGuildMembers(fname:String8);
 function SaveAllGuildMembers(fname:String8):integer;

 procedure LoadAllGuildLog(fname:String8);
 function SaveAllGuildLog(fname:String8):integer;

 procedure BuildPlayersIndex;
 // Заполняет производные данные (например страну регистрации игрока и т.п)
 procedure BuildDerivedData;

 procedure DumpEvents(fname:String8);

implementation
 uses CrossPlatform,SysUtils;

 type
  // Процедура загружает одну запись из потока, выставляя указатель на следующий после записи байт
  // Возвращает true в случае успешной загрузки, иначе false (некорректная запись)
  TDataLoader=function(version:integer;idx:integer;var pb:PByte):boolean;
  // Записывает запись с указанным индексом в поток
  TDataWriter=procedure(idx:integer;var pb:PByte);

 // Универсальная загрузка/созранение массивов данных
 // -------------------------------------------------------------

 procedure LoadDataFromFile(fname:String8;loader:TDataLoader);
  var
   f:file;
   buf:array of byte;
   fSize,loaded,handled:int64;
   size,curpos:integer;
   pb:PByte;
   count,idx,version:integer;
   head:cardinal;
   w:word;
   last:boolean;
  begin
   try
   if not FileExists(fname) then begin
    count:=0;
    Loader(-1,count,pb);
    exit;
   end;
   SetLength(buf,1000000);
   assign(f,fname);
   reset(f,1);
   BlockRead(f,head,4);
   if head<>$DEADBEAF then raise EError.Create('File '+fname+' corrupted: bad signature');
   BlockRead(f,count,4);
   Loader(-1,count,pb);
   BlockRead(f,version,4);
   loaded:=0; handled:=0;
   curPos:=0; idx:=0;
   repeat
    if loaded=0 then // первая порция
     BlockRead(f,buf[0],1000000,size)
    else begin
     move(pb^,buf[0],1000000-curPos); // перемещаем необработанную часть буфера в его начало
     BlockRead(f,buf[1000000-curPos],curPos,size) // Дозагружаем остаток буфера
    end;
    inc(loaded,size);
    last:=eof(f);

    pb:=@buf[0];
    repeat
     move(pb^,w,2); inc(pb,2);
     if w<>$BEDA then
      raise EWarning.Create('Error loading file '+fname+' Bad record signature'); 
     if Loader(version,idx,pb) then
       inc(idx);
    until (idx>=count) or (PtrUInt(pb)>PtrUInt(@buf[900000])) and not last;

    curPos:=PtrUInt(pb)-PtrUInt(@buf[0]); // сколько байт было обработано
    handled:=handled+curPos;
   until eof(f);
   close(f);
   except
    on e:Exception do dataAddLogMsg('Failed to load file: '+fname+' - '+e.message);
   end;
  end;

 procedure SaveDataToFile(fname:String8;writer:TDataWriter);
  var
   f:file;
   buf:array of byte;
   handled:integer;
   pb:PByte;
   version,count,i:integer;
   head:cardinal;
   w:word;
  begin
   try
   SetLength(buf,1000000);
   assign(f,fname);
   rewrite(f,1);
   head:=$DEADBEAF;
   BlockWrite(f,head,4);
   pb:=@count;
   Writer(-1,pb);
   BlockWrite(f,count,4);
   pb:=@version;
   Writer(-2,pb);
   BlockWrite(f,version,4);
   handled:=0; 
   pb:=@buf[0];
   w:=$BEDA;
   for i:=0 to count-1 do begin
    move(w,pb^,2); inc(pb,2);
    Writer(i,pb);
    handled:=PtrUInt(pb)-PtrUInt(@buf[0]);
    if handled>900000 then begin
     BlockWrite(f,buf[0],handled);
     pb:=@buf[0]; handled:=0;
    end;
   end;
   BlockWrite(f,buf[0],handled);
   close(f);
   except
    on e:Exception do dataAddLogMsg('Failed to save file: '+fname+' - '+e.message);
   end;
  end;

// Сериализаторы дуэлей
// -------------------------------------------------------------

 function DuelsLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count:integer;
  begin
   result:=true;  
   if version=-1 then begin
    count:=idx;
    SetLength(duels,count);
    exit;
   end;
   if version=1 then
    with duels[idx] do begin
     move(pb^,id,4); inc(pb,4);
     move(pb^,date,8); inc(pb,8);
     move(pb^,winner,4); inc(pb,4);
     move(pb^,loser,4); inc(pb,4);
     move(pb^,duration,2); inc(pb,2);
     move(pb^,winnerFame,2); inc(pb,2);
     move(pb^,loserFame,2); inc(pb,2);
     dueltype:=pb^; inc(pb);
     scenario:=pb^; inc(pb);
     winnerLevel:=pb^; inc(pb);
     loserLevel:=pb^; inc(pb);
     firstPlr:=pb^; inc(pb);
     turns:=pb^; inc(pb);
     if pb^=1 then begin
      inc(pb);
      SetLength(decks,2);
      move(pb^,decks[0],50); inc(pb,50);
      move(pb^,decks[1],50); inc(pb,50);
     end else inc(pb);
    end;
  end;

 procedure DuelsWriter(idx:integer;var pb:PByte);
  var
   count,version:integer;
  begin
   if idx>=0 then
    with duels[idx] do begin
     move(id,pb^,4); inc(pb,4);
     move(date,pb^,8); inc(pb,8);
     move(winner,pb^,4); inc(pb,4);
     move(loser,pb^,4); inc(pb,4);
     move(duration,pb^,2); inc(pb,2);
     move(winnerFame,pb^,2); inc(pb,2);
     move(loserFame,pb^,2); inc(pb,2);
     pb^:=dueltype; inc(pb);
     pb^:=scenario; inc(pb);
     pb^:=winnerLevel; inc(pb);
     pb^:=loserLevel; inc(pb);
     pb^:=firstPlr; inc(pb);
     pb^:=turns; inc(pb);
     if length(decks)=2 then begin
      pb^:=1; inc(pb);
      move(decks[0],pb^,50); inc(pb,50);
      move(decks[1],pb^,50); inc(pb,50);
     end else begin
      pb^:=0; inc(pb);
     end;
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(duels);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=1;
    move(version,pb^,4);
   end;
  end;

 // Сериализация строк
 procedure SaveString(st:String8;var pb:PByte);
  var
   l:integer;
  begin
   l:=length(st);
   if l<255 then begin
    pb^:=l; inc(pb);
   end else begin
    pb^:=255; inc(pb);
    move(l,pb^,2); inc(pb,2);
   end;
   if l>0 then begin
    move(st[1],pb^,l); inc(pb,l);
   end;
  end;

 function LoadString(var pb:PByte):String8;
  var
   l:word;
  begin
   if pb^=255 then begin
    inc(pb);
    move(pb^,l,2); inc(pb,2);
    SetLength(result,l);
   end else begin
    SetLength(result,pb^); inc(pb);
   end;
   if length(result)>0 then begin
    move(pb^,result[1],length(result));
    inc(pb,length(result));
   end;
  end;

 procedure Save1(val:shortint;var pb:PByte); inline;
  begin
   pb^:=val; inc(pb);
  end;
 procedure Save2(val:smallint;var pb:PByte); inline;
  begin
   move(val,pb^,2); inc(pb,2);
  end;
 procedure Save2u(val:word;var pb:PByte); inline;
  begin
   move(val,pb^,2); inc(pb,2);
  end;

 procedure Save4(val:integer;var pb:PByte); inline;
  begin
   move(val,pb^,4); inc(pb,4);
  end;
 procedure Save8(val:double;var pb:PByte); inline; overload;
  begin
   move(val,pb^,8); inc(pb,8);
  end;
 procedure Save8(val:int64;var pb:PByte); inline; overload;
  begin
   move(val,pb^,8); inc(pb,8);
  end;

 procedure Load1(out val:shortint;var pb:PByte); inline;
  begin
   val:=pb^; inc(pb);
  end;
 procedure Load2(out val:smallint;var pb:PByte); inline; overload;
  begin
   move(pb^,val,2); inc(pb,2);
  end;
 procedure Load2u(out val:word;var pb:PByte); inline;
  begin
   move(pb^,val,2); inc(pb,2);
  end;
 procedure Load2w(out val:word;var pb:PByte); inline;
  begin
   move(pb^,val,2); inc(pb,2);
  end;
 procedure Load4(out val:integer;var pb:PByte); inline;
  begin
   move(pb^,val,4); inc(pb,4);
  end;
 procedure Load8(out val:TDateTime;var pb:PByte); inline; overload;
  begin
   move(pb^,val,8); inc(pb,8);
  end;
 procedure Load8(out val:int64;var pb:PByte); inline; overload;
  begin
   move(pb^,val,8); inc(pb,8);
  end;


// Сериализаторы событий
// -------------------------------------------------------------
 function EventLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count:integer;
  begin
   result:=true;
   if version=-1 then begin
    count:=idx;
    SetLength(events,count);
    exit;
   end;
   if version=1 then
    with events[idx] do begin
     move(pb^,id,4); inc(pb,4);
     move(pb^,playerID,4); inc(pb,4);
     move(pb^,created,8); inc(pb,8);
     event:=LoadString(pb);
     info:=LoadString(pb);
     if (id<=0) or (created=0) or (event='') then
       result:=false;
    end;
  end;

 procedure EventWriter(idx:integer;var pb:PByte);
  var
   count,version:integer;
  begin
   if idx>=0 then
    with events[idx] do begin
     move(id,pb^,4); inc(pb,4);
     move(playerID,pb^,4); inc(pb,4);
     move(created,pb^,8); inc(pb,8);
     SaveString(event,pb);
     SaveString(info,pb);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(events);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=1;
    move(version,pb^,4);
   end;
  end;

// Сериализаторы платежей
// -------------------------------------------------------------
 function PaymentLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count,v:integer;
  begin
   result:=true;
   if version=-1 then begin
    count:=idx;
    SetLength(payments,count);
    exit;
   end;
   if version=1 then
    with payments[idx] do begin
     move(pb^,id,4); inc(pb,4);
     move(pb^,playerID,4); inc(pb,4);
     move(pb^,created,8); inc(pb,8);
     username:=LoadString(pb);
     itemcode:=LoadString(pb);
     move(pb^,amount,4); inc(pb,4);
     currency:=LoadString(pb);
     Load4(v,pb); transaction:=v;
    end;
   if version in [2,3] then
    with payments[idx] do begin
     move(pb^,id,4); inc(pb,4);
     move(pb^,playerID,4); inc(pb,4);
     move(pb^,created,8); inc(pb,8);
     username:=LoadString(pb);
     itemcode:=LoadString(pb);
     move(pb^,amount,4); inc(pb,4);
     currency:=LoadString(pb);
     if version=3 then begin
      country:=LoadString(pb);
      method:=LoadString(pb);
     end;
     Load8(transaction,pb);
    end;
  end;

 procedure PaymentWriter(idx:integer;var pb:PByte);
  var
   count,version:integer;
  begin
   if idx>=0 then
    with payments[idx] do begin
     move(id,pb^,4); inc(pb,4);
     move(playerID,pb^,4); inc(pb,4);
     move(created,pb^,8); inc(pb,8);
     SaveString(username,pb);
     SaveString(itemcode,pb);
     move(amount,pb^,4); inc(pb,4);
     SaveString(currency,pb);
     SaveString(country,pb);
     SaveString(method,pb);
     Save8(transaction,pb);
//     move(transaction,pb^,4); inc(pb,4);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(payments);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=3;
    move(version,pb^,4);
   end;
  end;

// Сериализаторы игроков
// -------------------------------------------------------------
 function PlayerLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count,i:integer;
  begin
   result:=true;
   if version=-1 then begin
    count:=idx;
    SetLength(players,count);
    exit;
   end;
   if version in [1,2,3,4] then
    with players[idx] do begin
     Load4(id,pb);
     name:=LoadString(pb);
     email:=LoadString(pb);
     if version>=3 then guild:=LoadString(pb);
     pwd:=LoadString(pb);
     flags:=LoadString(pb);
     if version>=2 then lang:=LoadString(pb)
      else lang:='??';

     Load8(created,pb);
     Load8(lastVisit,pb);
     Load8(premium,pb);
     Load4(avatar,pb);
     Load4(gold,pb);

     Load2(gems,pb);
     Load2(AP,pb);
     Load2(hero,pb);
     Load2(needHero,pb);
     Load2(dtWins,pb);

     for i:=0 to 3 do begin
      Load2(fame[i],pb);
      Load2u(wins[i],pb);
      Load2u(loses[i],pb);
      Load1(level[i],pb);
     end;
     realname:=LoadString(pb);
     location:=LoadString(pb);
     about:=LoadString(pb);
     tags:=LoadString(pb);
     cards:=LoadString(pb);
     // cardsCount:= здесь нужно вычислить кол-во карт у игрока - это число в базе не хранится
     Load4(referer,pb);
     Load4(paramX,pb);
     Load4(optFlags,pb);

     Load1(HP,pb);
     Load1(speciality,pb);
     Load1(campaignWins,pb);
     Load1(room,pb);

     quests:=LoadString(pb);
     campaignLoses:=LoadString(pb);
     friendlist:=LoadString(pb);
     blacklist:=LoadString(pb);
     missions:=LoadString(pb);
     market:=LoadString(pb);
    end;
  end;

 procedure PlayerWriter(idx:integer;var pb:PByte);
  var
   count,version,i:integer;
  begin
   if idx>=0 then
    with players[idx] do begin
     Save4(id,pb);
     SaveString(name,pb);
     SaveString(email,pb);
     // Ver?>=3
     SaveString(guild,pb);

     SaveString(pwd,pb);
     SaveString(flags,pb);
     SaveString(lang,pb);
     Save8(created,pb);
     Save8(lastVisit,pb);
     Save8(premium,pb);
     Save4(avatar,pb);
     Save4(gold,pb);

     Save2(gems,pb);
     Save2(AP,pb);
     Save2(hero,pb);
     Save2(needHero,pb);
     Save2(dtWins,pb);

     for i:=0 to 3 do begin
      Save2(fame[i],pb);
      Save2u(wins[i],pb);
      Save2u(loses[i],pb);
      Save1(level[i],pb);
     end;
     SaveString(realname,pb);
     SaveString(location,pb);
     SaveString(about,pb);
     SaveString(tags,pb);
     SaveString(cards,pb);
     // cardsCount:= здесь нужно вычислить кол-во карт у игрока - это число в базе не хранится
     Save4(referer,pb);
     Save4(paramX,pb);
     Save4(optFlags,pb);

     Save1(HP,pb);
     Save1(speciality,pb);
     Save1(campaignWins,pb);
     Save1(room,pb);

     SaveString(quests,pb);
     SaveString(campaignLoses,pb);
     SaveString(friendlist,pb);
     SaveString(blacklist,pb);
     SaveString(missions,pb);
     SaveString(market,pb);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(players);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=3;
    move(version,pb^,4);
   end;
  end;

// Сериализаторы визитов
// -------------------------------------------------------------
 function VisitLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count,i:integer;
  begin
   result:=true;  
   if version=-1 then begin
    count:=idx;
    SetLength(visits,count);
    exit;
   end;
   if version=1 then
    with visits[idx] do begin
     Load4(id,pb);
     Load4(playerid,pb);
     Load8(vid,pb);
     Load8(date,pb);
     ip:=LoadString(pb);
     country:=LoadString(pb);
     page:=LoadString(pb);
     referer:=LoadString(pb);
     tags:=LoadString(pb);
    end;
  end;

 procedure VisitWriter(idx:integer;var pb:PByte);
  var
   count,version,i:integer;
  begin
   if idx>=0 then
    with visits[idx] do begin
     Save4(id,pb);
     Save4(playerid,pb);
     Save8(vid,pb);
     Save8(date,pb);
     SaveString(ip,pb);
     SaveString(country,pb);
     SaveString(page,pb);
     SaveString(referer,pb);
     SaveString(tags,pb);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(visits);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=1;
    move(version,pb^,4);
   end;
  end;

// Сериализаторы гильдий
// -------------------------------------------------------------
 function GuildLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count,i:integer;
  begin
   result:=true;
   if version=-1 then begin
    count:=idx;
    SetLength(guilds,count);
    exit;
   end;
   if version=1 then
    with guilds[idx] do begin
     Load4(id,pb);
     name:=LoadString(pb);
     Load1(size,pb);
     Load1(level,pb);
     Load1(daily,pb);
     Load4(exp,pb);
     Load4(treasures,pb);
     Load4(flags,pb);
     bonuses:=LoadString(pb);
     cards:=LoadString(pb);
    end;
  end;

 procedure GuildWriter(idx:integer;var pb:PByte);
  var
   count,version,i:integer;
  begin
   if idx>=0 then
    with guilds[idx] do begin
     Save4(id,pb);
     SaveString(name,pb);
     Save1(size,pb);
     Save1(level,pb);
     Save1(daily,pb);
     Save4(exp,pb);
     Save4(treasures,pb);
     Save4(flags,pb);
     SaveString(bonuses,pb);
     SaveString(cards,pb);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(guilds);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=1;
    move(version,pb^,4);
   end;
  end;

// Сериализаторы гильдмемберов
// -------------------------------------------------------------
 function GuildMemberLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count,i:integer;
  begin
   result:=true;
   if version=-1 then begin
    count:=idx;
    SetLength(guildmembers,count);
    exit;
   end;
   if version=1 then
    with guildmembers[idx] do begin
     Load4(plrid,pb);
     Load4(guildid,pb);
     Load4(treasures,pb);
     Load4(exp,pb);
     Load1(rank,pb);
    end;
  end;

 procedure GuildMemberWriter(idx:integer;var pb:PByte);
  var
   count,version,i:integer;
  begin
   if idx>=0 then
    with guildmembers[idx] do begin
     Save4(plrid,pb);
     Save4(guildid,pb);
     Save4(treasures,pb);
     Save4(exp,pb);
     Save1(rank,pb);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(guildmembers);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=1;
    move(version,pb^,4);
   end;
  end;

// Сериализаторы гильдлога
// -------------------------------------------------------------
 function GuildMemberLogLoader(version:integer;idx:integer;var pb:PByte):boolean;
  var
   count,i:integer;
  begin
   result:=true;
   if version=-1 then begin
    count:=idx;
    SetLength(guildlog,count);
    exit;
   end;
   if version=1 then
    with guildlog[idx] do begin
     Load4(guildid,pb);
     Load8(date,pb);
     msg:=LoadString(pb);
    end;
  end;

 procedure GuildMemberLogWriter(idx:integer;var pb:PByte);
  var
   count,version,i:integer;
  begin
   if idx>=0 then
    with guildlog[idx] do begin
     Save4(guildid,pb);
     Save8(date,pb);
     SaveString(msg,pb);
     exit;
    end;
   // кол-во записей
   if idx=-1 then begin
    count:=length(guildlog);
    move(count,pb^,4);
   end;
   // версия
   if idx=-2 then begin
    version:=1;
    move(version,pb^,4);
   end;
  end;


 procedure LoadAllDuels(fname:String8);
  begin
   LoadDataFromFile(fname,DuelsLoader);
  end;
 function SaveAllDuels(fname:String8):integer;
  begin
   SaveDataToFile(fname,DuelsWriter);
   result:=length(duels);
  end;

 procedure LoadAllEvents(fname:String8);
  begin
   LoadDataFromFile(fname,EventLoader);
  end;
 function SaveAllEvents(fname:String8):integer;
  begin
   SaveDataToFile(fname,EventWriter);
   result:=length(events);
  end;

 procedure LoadAllPayments(fname:String8);
  begin
   LoadDataFromFile(fname,PaymentLoader);
  end;
 function SaveAllPayments(fname:String8):integer;
  begin
   SaveDataToFile(fname,PaymentWriter);
   result:=length(payments);
  end;

 procedure LoadAllPlayers(fname:String8);
  begin
   LoadDataFromFile(fname,PlayerLoader);
   BuildPlayersIndex;
  end;
 function SaveAllPlayers(fname:String8):integer;
  begin
   SaveDataToFile(fname,PlayerWriter);
   result:=length(players);
  end;

 procedure LoadAllVisits(fname:String8);
  begin
   LoadDataFromFile(fname,VisitLoader);
  end;
 function SaveAllVisits(fname:String8):integer;
  begin
   SaveDataToFile(fname,VisitWriter);
   result:=length(visits);
  end;

 procedure LoadAllGuilds(fname:String8);
  begin
   LoadDataFromFile(fname,GuildLoader);
  end;
 function SaveAllGuilds(fname:String8):integer;
  begin
   SaveDataToFile(fname,GuildWriter);
   result:=length(guilds);
  end;

 procedure LoadAllGuildmembers(fname:String8);
  begin
   LoadDataFromFile(fname,GuildMemberLoader);
  end;
 function SaveAllGuildmembers(fname:String8):integer;
  begin
   SaveDataToFile(fname,GuildMemberWriter);
   result:=length(guildmembers);
  end;

 procedure LoadAllGuildLog(fname:String8);
  begin
   LoadDataFromFile(fname,GuildMemberLogLoader);
  end;
 function SaveAllGuildLog(fname:String8):integer;
  begin
   SaveDataToFile(fname,GuildMemberLogWriter);
   result:=length(guildLog);
  end;

 procedure BuildPlayersIndex;
  var
   i:integer;
  begin
   maxPlayerID:=0;
   playerIDHash.Init(Length(players));
   for i:=0 to high(players) do begin
    playerIDHash.Put(players[i].id,i);
    maxPlayerID:=max2(maxPlayerID,players[i].id);
   end;
  end;

 procedure DumpEvents(fname:String8);
  var
   f:text;
   i:integer;
  begin
   assign(f,fname);
   rewrite(f);
   for i:=0 to high(events) do
    with events[i] do
     writeln(f,Format('%8d | %8d | %8d | %17s | %-12s | %s ',[i,id,playerID,FormatDateTime('dd.mm.yy hh:nn:ss',created),event,info]));
   close(f);
  end;

 function IsValidPlayerIDX(id:integer):boolean; inline;
  begin
   if (id>0) and (id<=high(players)) then result:=true
    else result:=false;
  end; 

 const
  // среднемесячные курсы валют с начала 2016 года
  RUBrate:array[1..36] of single=
    (75,78,70,68,66,65,64,65,64,63,64,64,
     59,58,57,57,58,59,59,58,57,57,59,59,
     56,56,57,61,63,62,63,66,67,65,65,65);
  BYNrate:array[1..36] of single=
    (2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0,
     2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0,
     2.0, 2.0, 2.0, 2.0, 2.1, 2.1, 2.1, 2.1, 2.1, 2.13, 2.11, 2.0);

 procedure BuildDerivedData;
  var
   i,id,cnt:integer;
   month,year,day:word;
   rate:single;
   sa:AStringArr;
  function GetOSVersion(s:String8):String8;
   begin
    result:='';
    if copy(s,1,1)='w' then begin
     result:='Windows';
     delete(s,1,1);
     if s='0106' then result:=result+' 7' else
     if s='0306' then result:=result+' 8.1' else
     if s='0206' then result:=result+' 8' else
     if s='000A' then result:=result+' 10' else
     if s='0105' then result:=result+' XP' else
     if s='0205' then result:=result+' XP64' else
     if s='0005' then result:=result+' 2000' else
     if s='0006' then result:=result+' Vista' else
      result:=result+' '+s;
     exit;
    end;
    result:=s;
   end;
  function GetGLVersion(s:String8):String8;
   var
    i,c:integer;
   begin
    result:=''; c:=0;
    for i:=1 to length(s) do begin
     if s[i]='.' then inc(c);
     if c>1 then break;
     if s[i] in ['0'..'9','.'] then result:=result+s[i];
    end;
   end;
  begin
   LogMessage('Building derived data: payments');
   inc(isBusy);
   try
   // Платежи - перевод рублей в доллары
   for i:=0 to high(payments) do
    with payments[i] do begin
     if currency='USD' then
      amountUSD:=amount
     else begin
      DecodeDate(created,year,month,day);
      inc(month,12*(year-2016));
      if currency='RUB' then begin
       if month>high(RUBrate) then month:=high(RUBrate);
       rate:=RUBrate[month];
       amountUSD:=amount/rate;
      end;
      if currency='EUR' then begin
       rate:=0.88;
       amountUSD:=amount/rate;
      end;
      if currency='BYN' then begin
       if month>high(BYNrate) then month:=high(BYNrate);
       rate:=BYNrate[month];
       amountUSD:=amount/rate;
      end;
      if currency='UAH' then begin
       rate:=28;
       amountUSD:=amount/rate;
      end;
      if currency='KZT' then begin
       rate:=370;
       amountUSD:=amount/rate;
      end;
     end;
    end;

   LogMessage('Building derived data: paid amount');
   // Донат
   for i:=0 to high(payments) do begin
    id:=payments[i].playerID;
    id:=playerIDhash.Get(id);
    if not IsValidPlayerIDX(id) then continue;
    players[id].paidAmount:=players[id].paidAmount+payments[i].amountUSD;
   end;

   LogMessage('Building derived data: from events');
   // Язык, страна, Steam
   for i:=0 to high(players) do players[i].isSteam:=99;
   cnt:=0;
   for i:=0 to high(events) do begin
    if events[i].event='LOGIN' then begin
     id:=events[i].playerID;
     id:=playerIDhash.Get(id);
     if not IsValidPlayerIDX(id) then continue;
     inc(cnt);
     sa:=splitA(';',events[i].info); // 62.249.146.16; RU; 1010; 867F36AB0D; 04806AB2; W; 4FA; 300; w0306; ru; 37; 4.5.0 NVI; GeForce GTX 760/PCIe/SSE2; WIN; ST=xxx
     if high(sa)<9 then continue;
     players[id].lastCountry:=sa[1];
     players[id].clientLang:=sa[9];
     if players[id].isSteam=99 then // учитывать только первый логин
      if (high(sa)>=13) and (copy(sa[13],1,7)='WIN:ST=') then
       players[id].isSteam:=1
      else
       players[id].isSteam:=0;
     if high(sa)>=12 then begin
      players[id].osVersion:=GetOSVersion(sa[8]);
      players[id].videocard:=sa[12];
      players[id].openGL:=GetGLVersion(sa[11]);
     end;
     continue;
    end else
    if events[i].event='NEWACC' then begin
     id:=events[i].playerID;
     id:=playerIDhash.Get(id);
     if not IsValidPlayerIDX(id) then continue;
     sa:=splitA(';',events[i].info); // AngelofAvarice; trevorkmee@gmail.com; 153.90.88.244; US
     if high(sa)<3 then continue;
     players[id].regCountry:=sa[3];
    end;
   end;
   LogMessage('Login events: %d',[cnt]);

   for i:=0 to high(players) do
    if players[i].isSteam=99 then players[i].isSteam:=0;

   LogMessage('Derived data: done');
   except
    on e:Exception do ForceLogMessage('Error building derived data: '+ExceptionMsg(e));
   end;
   dec(isBusy);
  end;

end.
