// В этом модуле реализованы запросы пользовательской логики
// (запросы вида GET /userID?xxx)
// Именно здесь находится весь код, определяющий специфику конкретного сервера
// Copyright (C) Ivan Polyacov, ivan@apus-software.com, cooler@tut.by
{$R+}
unit CustomLogic;
interface
 const
  // number of simultaneous records
  MAX_GAMES = 2000;
  MAX_DRAFTS = 200;

 // Процедуры выполняют запрос клиента - т.е. обрабатывает сообщение от клиента
 // Если необходимо - отправляет дополнительные сообщения клиенту или другим юзерам
 // ВСЕ клиентские запросы (сообщения) передаются в ExecUserRequest, а если запрос
 // нельзя обработать без задержки (требуется запрос к БД или обращение к файлам),
 // то используется AddTask для асинхронного выполнения

 // Возможно 2 варианта обработки запросов:
 // 1. Немедленный - все действия проводятся сразу же, результат (если он не пустой)
 //    посылается немедленно в ответ на текущий запрос
 // Всегда вызывается внутри gSect! userID - валидный
 procedure ExecUserRequest(userID:integer;userMsg:UTF8String);

 // 2. Асинхронный - запрос помещается в очередь и будет обработан в working thread
 //    ответ (если не пустой) отправляется в ответ на запрос, который обрабатывался
 // Эта процедура вызывается из рабочего потока; параметр - текстовый, то, что было занесено в очередь
 // осторожно: вызывается ВНЕ gSect!
 function ExecAsyncTask(CRID:integer;userID:integer;request:UTF8String):UTF8String;

 procedure InitThreadDatabase(wID:integer);
 procedure DoneThreadDatabase(wID:integer);

 // Завершает указанную игру (winner - userID победителя)
 // Если winner=0 - значит оба игрока проиграли
 // Eсли winner<0 - значит победитель - тот, с кем играл -winner
 procedure GameOver(gameID:integer;winner:integer;comments:UTF8String='');

 function FindGame(userID:integer):integer;

 // Наполняет страницу админки специфичными данными
 procedure FillAdminPage(var page:UTF8String);

 // Вызывается 1 раз в секунду внутри gSect (поэтому должна работать быстро!)
 procedure onCustomTimer;

 // Послать юзеру сообщение от имени сервера (toUser=-1 - послать ВСЕМ)
 // если emptySender - то будет послано как вспомогательное
 procedure PostServerMsg(toUser:integer;text:UTF8String;emptySender:boolean=false);

 // Посылает сообщение всем членам гильдии с заданным индексом
 procedure PostGuildMsg(gIdx:integer;msg:UTF8String;reason:UTF8String='');

 // Добавляет сообщение в гильдейский лог
 procedure GuildLogMessage(gIdx:integer;msg:UTF8String;silentMode:boolean=false);

 // Показать юзеру сообщение в окне
 procedure ShowMessageToUser(toUser:integer;text:UTF8String);

 // Производит все действия, необходимые ПЕРЕД удалением юзера (вызывается внутри gSect!)
 procedure Logout(userID:integer;reason,clientinfo:UTF8String);

 function GetAllowedVersions:UTF8String;

 procedure EditFriendlist(userID:integer;pname:UTF8String;add:boolean);
 procedure EditBlacklist(userID:integer;pname:UTF8String;add:boolean);

implementation
 uses math,windows,SysUtils,MyServis,logging,net,workers,database,DCPmd5a,ZLibEx,
    ULogic,ULogicWrapper,NetCommon,UCalculating,ServerLogic,UCompAI,CrossPlatform,
    cnsts,gameData,globals,UDict,UDraftLogic,UDeck,UCampaignLogic,UMissionsLogic,
    structs,TextUtils;

 var
  games:array[1..MAX_GAMES] of TGame;
  drafts:array[1..MAX_DRAFTS] of TDraft;
  lastDraftAutosearch:TDateTime; // время, когда последний раз какой-либо игрок заходил в автопоиск драфта

  cardInfoHash:UTF8String;
  botDuelCnt:integer; // серийный номер ботовой дуэли

  initialized:boolean=false;

 threadvar
  DB:TCustomMySQLDatabase; // Per-thread DB instance
  currentCon:integer;  // индекс текущего соединения, используется для доступа к соединению через ф-ции net

 procedure DatabaseMaintenance; forward;
 procedure SendGuildInfo(userID:integer;sendGuildLog:boolean=false); forward;
 procedure TrainingWithBot(userID,enemy,mode:integer;deckName:UTF8String); forward;
 procedure SearchReplays(userID:integer;name,startDate,endDate:UTF8String); forward;


 function GetAllowedVersions:UTF8String;
  begin
   result:=IntToStr(cnsts.version)+';'+CardInfoHash+';'+cnsts.sVersion+';'+IntToStr(cnsts.minversion);
  end;

 function IsValidDraftID(draftID:integer):boolean;
  begin
   result:=false;
   if (draftID<1) or (draftID>high(drafts)) then exit;
   if drafts[draftID].players[1]<=0 then exit;
   result:=true;
  end;

 function FindGame(userID:integer):integer;
  var
   i:integer;
  begin
   result:=0;
   if userID<=0 then exit;
   for i:=1 to High(games) do
    if (games[i].user1=userID) or
       (games[i].user2=userID) then begin
    result:=i; exit;
   end;
  end;

 // Постит одинаковое сообщение всем членам указанной гильдии, которые онлайн
 // Потенциально медленно
 procedure PostGuildMsg(gIdx:integer;msg:UTF8String;reason:UTF8String='');
  var
   i,u:integer;
  begin
   if gIdx<=0 then exit;
   if reason<>'' then LogMsg('GuildMsg - reason: '+reason,logDebug);
   with guilds[gIdx] do
    for i:=0 to high(members) do begin
     u:=FindUser(members[i].name);
     if u=0 then continue;
     if users[u].guild<>name then begin
      LogMsg('Warn! user %s guild="%s" <> "%s"',[members[i].name,users[u].guild,name],logInfo);
      continue;
     end;
     if u>0 then PostUserMsg(u,msg);
    end;
  end;

 // Послать юзеру приватное сообщение от имени сервера
 // если сообщение начинается с [xy], то xy - язык клиентов получателей сообщения (только если сообщение всем)
 // если сообщение начинается с [X], то X - тип сообщения, порядок комбинирования: [en][I]text
 procedure PostServerMsg(toUser:integer;text:UTF8String;emptySender:boolean=false);
  var
   i:integer;
   msg,sender,lang:UTF8String;
   mType:AnsiChar;
  begin
   if emptySender then sender:='' else sender:='Server message';
   lang:='';
   if (length(text)>4) and (text[1]='[') and (text[4]=']') then begin
    lang:=copy(text,2,2); delete(text,1,4);
   end;
   gSect.Enter;
   try
    if toUser=-1 then begin
     LogMsg('[Chat] Server to ALL: '+text,logImportant,lgChat);
     msg:=FormatMessage([22,'S',sender,text,0]);
     for i:=1 to high(users) do
      if users[i]<>nil then
       if (users[i].botlevel=0) and
          ((lang='') or (users[i].lang=lang) or
           (users[i].flags and (ufAdmin+ufModerator)>0)) then
        PostUserMsg(i,msg);
     exit;
    end;
    if IsValidUserID(toUser) then begin
     if not emptysender then begin
      LogMsg('[Chat] Server to '+users[toUser].name+': '+text,logInfo,lgChat);
      mType:='S';
     end else
      mType:='I';
     if (length(text)>3) and (text[1]='[') and (text[3]=']') then begin
      mType:=text[2]; delete(text,1,3);
     end;  
     PostUserMsg(toUser,FormatMessage([22,mType,sender,text,0]));
    end else
     LogMsg('PSM error: invalid userID '+inttostr(toUser),logNormal);
   finally
    gSect.Leave;
   end;
  end;

 procedure ShowMessageToUser(toUser:integer;text:UTF8String);
  begin
   PostUserMsg(toUser,FormatMessage([2,31,text]));
  end;

 // Вызывается в виде таска 1 раз сразу после старта сервера 
 procedure InitServerData;
  var
   sa:AStringArr;
   i,k,id,cs:integer;
  begin
   LogMsg('Initializing server data',logImportant);
   try
   DatabaseMaintenance; // Перекинуть данные из временных таблиц в основные
   LogMsg('Init: Loading last duels',logNormal);

   // Загрузка информации о последних боях
   sa:=db.Query('SELECT date,dueltype,winner,loser,scenario,turns,firstPlr FROM duels WHERE date>DATE_SUB(Now(),INTERVAL 3 DAY)');
   if db.lastError='' then begin
    k:=0;
    EnterCriticalSection(gSect);
    try
    for i:=1 to db.rowCount do begin
     AddLocalDuelRec(GetDateFromStr(sa[k]),
       StrToIntDef(sa[k+2],0),
       StrToIntDef(sa[k+3],0),
       StrToIntDef(sa[k+1],0),
       StrToIntDef(sa[k+4],0),
       StrToIntDef(sa[k+5],0),
       StrToIntDef(sa[k+6],0));
     inc(k,7);
    end;
    finally
     LeaveCriticalSection(gSect);
    end;
   end;
   // Загрузка информации обо всех игроках
   LogMsg('Init: Loading all players',logNormal);
   sa:=db.Query('SELECT max(id) FROM players');
   if db.rowCount=1 then begin
    SetLength(allPlayers,StrToInt(sa[0])+1);
    sa:=db.Query('SELECT id,name,guild,email,customFame,customLevel,classicFame,classicLevel,draftFame,draftLevel,level,'+
       'customWins,customLoses,classicWins,classicLoses,draftWins,draftLoses,campaignWins,lastVisit FROM players');
    if db.rowCount>0 then begin
     for i:=0 to db.rowCount-1 do begin
      cs:=db.colCount;
      id:=StrToInt(sa[i*cs]);
      if (id>0) and (id<length(allPlayers)) then begin
        allPlayers[id].name:=sa[i*cs+1];
        allPlayers[id].guild:=sa[i*cs+2];
        allPlayers[id].email:=sa[i*cs+3];
        allPlayers[id].customFame:=StrToInt(sa[i*cs+4]);
        allPlayers[id].customLevel:=StrToInt(sa[i*cs+5]);
        allPlayers[id].classicFame:=StrToInt(sa[i*cs+6]);
        allPlayers[id].classicLevel:=StrToInt(sa[i*cs+7]);
        allPlayers[id].draftFame:=StrToInt(sa[i*cs+8]);
        allPlayers[id].draftLevel:=StrToInt(sa[i*cs+9]);
        allPlayers[id].totalFame:=CalcPlayerFame(allPlayers[id].customFame,allPlayers[id].classicFame,allPlayers[id].draftFame);
        allPlayers[id].totalLevel:=CalcLevel(allPlayers[id].totalFame); //StrToInt(sa[i*cs+10]);
        allPlayers[id].customWins:=StrToInt(sa[i*cs+11]);
        allPlayers[id].customloses:=StrToInt(sa[i*cs+12]);
        allPlayers[id].classicWins:=StrToInt(sa[i*cs+13]);
        allPlayers[id].classicLoses:=StrToInt(sa[i*cs+14]);
        allPlayers[id].draftWins:=StrToInt(sa[i*cs+15]);
        allPlayers[id].draftLoses:=StrToInt(sa[i*cs+16]);
        allPlayers[id].campaignWins:=StrToInt(sa[i*cs+17]);
        allPlayers[id].lastVisit:=GetDateFromStr(sa[i*cs+18]);
        allPlayers[id].status:=psOffline;
        allPlayersHash.Put(lowercase(allPlayers[id].name),id);
      end;
     end;
     LogMsg('Players loaded: '+inttostr(db.rowCount),logNormal);
     BuildRanking(dtCustom);
     BuildRanking(dtClassic);
     BuildRanking(dtDraft);
     BuildRanking(dtNone);
     LogMsg('Rankings built',logNormal);
    end;
   end;
   except
    on e:exception do LogMsg('Error in ISD: '+ExceptionMsg(e),logWarn);
   end;
  end;

  // Возвращает false если указанной декой играть нельзя или нельзя выбрать рандомную
 function SetCurDeck(userID:integer;deckName:UTF8String;silentMode:boolean=false):boolean;
  var
   i,plrID,cnt,idx:integer;
   list:array[1..100] of integer;
   res:UTF8String;
  begin
   result:=false;
   if not IsValidUserID(userID,true) then exit;
   with users[userID] do begin
    idx:=FindDeckByName(deckName);
    plrID:=playerID;
    if idx>0 then begin
     // Deck found
     res:=decks[idx].IsValidForUser(users[userid]);
     if res<>'' then begin
      if not silentmode then
       ShowMessageToUser(userID,'Sorry, you can''t play with this deck:^~^'+res);
//      PostUserMsg(userID,FormatMessage([2,3101,'Sorry, you can''t play with this deck']));
      LogMsg('Deck %s is not allowed for %s - %s ',[deckName,name,res],logInfo);
      exit;
     end;
    end else begin
     // choose a random deck
     cnt:=0;
     for i:=1 to high(decks) do
      if decks[i].IsValidForUser(users[userID])='' then begin
       inc(cnt);
       list[cnt]:=i;
      end;
     if cnt=0 then begin
      ShowMessageToUser(userID,'Sorry, you have no valid decks to play.');
//      PostUserMsg(userID,FormatMessage([2,3102,'Sorry, you have no valid decks to play']));
      LogMsg('No valid decks for %s',[name],logInfo);
      exit;
     end;
     idx:=list[1+random(cnt)];
    end;
    curDeckID:=decks[idx].deckID;
    AddTask(userID,0,['SETCURDECK',decks[idx].deckID,plrID]);
   end;
   result:=true;
  end;

 // Определяет противников кампании/квесты для игрока на базе текущих значений
 // Если квесты заменяются - заносит в базу квесты и текущую дату
 procedure DefineUserQuests(userID:integer;replaceQuests:boolean=false);
  var
   i,j,k:integer;
   mask:array[0..100] of boolean;
  begin
   EnterCriticalSection(gSect);
   try
    if not IsValidUserID(userID) then exit;
    with users[userid] do begin
     case campaignWins of
      -1,0:begin
         // Самый первый бой - туториальный
         quests[1]:=1;
         quests[2]:=0;
         quests[3]:=0;
        end;
      1,2:begin
         // Начало кампании
         quests[1]:=campaignWins+1;
         quests[2]:=0;
         quests[3]:=0;
        end;
      3..13:begin
          // какие квесты уже имеются у игрока
          fillchar(mask,sizeof(mask),0);
          for i:=1 to 3 do mask[quests[i]]:=true;
          // теперь добавим, если надо
          for i:=1 to 3 do
           if quests[i]=0 then begin
            // нужно по возможности заполнить эту дырку, для этого поищем подходящего противника
            k:=campaignWins; // столько нужно пропустить
            for j:=1 to 14 do
             if not (mask[j] or
                     ((j=13) and mask[11])) then begin // не добавлять 13-го врага если имеется непройденный 11-й
              if k=0 then begin
               quests[i]:=j;
               mask[j]:=true;
               break;
              end else
               dec(k);
             end;
           end;
          // Заменить Гработа на Миктианта если жизни уже 30
          if (quests[1]=14) and (initialHP=30) then quests[1]:=13;
         end;
      14:begin
          // Последний соперник 1-й фазы
          quests[1]:=15;
          quests[2]:=0;
          quests[3]:=0;
         end;
      15:begin
          // Если нет 10-го уровня, то тут должны быть квесты
          quests[1]:=16;
          quests[2]:=0;
          quests[3]:=0;
         end;
      16:begin
          quests[1]:=17;
          quests[2]:=18;
          quests[3]:=19;
         end;
      19:begin
          quests[1]:=20;
          quests[2]:=0;
          quests[3]:=0;
         end;
      20:begin
          // Тут только квесты
          quests[1]:=0;
          quests[2]:=0;
          quests[3]:=0;
         end;
     end;
     if replaceQuests then begin
      quests[4]:=41+random(3);
      quests[5]:=44+random(3);
      quests[6]:=47+random(3);
     end;
     i:=campaignWins;
     if flags and ufNotPlayed>0 then i:=-1;
     if campaignWins<15 then begin
      PostUserMsg(userID,FormatMessage([25,i,quests[1],quests[2],quests[3],0,0,0]))
     end else
      PostUserMsg(userID,FormatMessage([25,i,quests[1],quests[2],
        quests[3],quests[4],quests[5],quests[6]]));

     AddTask(0,0,['UPDATEPLAYER',playerID,'dailyUpd=Date(Now())']);
    end;
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 // Добавляет (отнимает) кристаллы без записи в eventlog
 procedure AddGems(userID:integer;amount:integer);
  var
   oldval:integer;
  begin
   with users[userID] do begin
    if botLevel>0 then exit;
    oldval:=users[userID].gems;
    users[userID].gems:=max2(0,oldval+amount);
    LogMsg('%d gems for %s: %d -> %d',[amount,name,oldval,gems],logNormal);
    AddTask(0,0,['UPDATEPLAYER',playerID,'gems='+inttostr(gems)]);   
   end;
  end;

 procedure CancelAllProposals(userID:Integer);
  var
   i,j,u:integer;
   st:UTF8String;
  begin
   try
   // Отменим все исходящие предложения
   with users[userID] do begin
    for i:=0 to high(proposals) do begin
     u:=proposals[i].userID;
     if IsValidUserID(u,true) then
      st:=users[u].name;
      PostUserMsg(u,FormatMessage([66,ord(proposals[i].gametype),name]));
    end;
   end;
   // Отклоним все входящие предложения
   for i:=1 to high(users) do
    if (users[i]<>nil) then begin
     // type 1
     j:=users[i].FindProposal(userID,dtCustom);
     if j>=0 then begin
      PostUserMsg(i,FormatMessage([65,1,users[userid].name]));
      users[i].DeleteProposal(j);
     end;
     // type 2
     j:=users[i].FindProposal(userID,dtClassic);
     if j>=0 then begin
      PostUserMsg(i,FormatMessage([65,2,users[userid].name]));
      users[i].DeleteProposal(j);
     end;
    end;
   except
    on e:Exception do LogMsg('Error in CAP for '+users[userid].name+': '+ExceptionMsg(e),logWarn);
   end;
  end;

 // Добавляет юзера-бота для режима игры forMode (выполнять в gSect!)
 // lvl = 1..6 (новичок..архмаг)
 function AddBot(lvl:integer;forMode:TDuelType;deckIdx:integer=0;customBotLevel:integer=0):integer;
  var
   userID:integer;
  const
   names:array[0..9] of UTF8String=
     ('Jack','John','Jenny','Justin','Jerry','Jaques','Jennifer','Julliette','Jasmin','Jeremy');
//   aiFame:array[1..4] of integer=(300,300,3200,6200);
   aiLevel:array[1..6] of byte=(2,4,8,12,20,30);
  begin
   ASSERT(gSect.lockCount>0,'AddBot: not in gSect!');
   userID:=CreateUser(false);
   lvl:=Sat(lvl,1,6);
   LogMsg('Adding bot '+inttostr(userID)+' level '+inttostr(lvl),logNormal,lgAI);
   with users[userID] do begin
{    case lvl of
     1:name:='Novice';
     2:name:='Mage';
     3:name:='Master';
     4:name:='Archmage';
    end;
    name:=name+' '+names[random(high(names))];}
    name:=aiNames[lvl];
    if forMode=dtCampaign then name:=campaignMages[deckIdx].name;
    PwdHash:='';
    email:='support@astralheroes.com';
    avatar:=1;
    lang:='X';
    ip:='0.0.0.0';
    country:='NA';
    flags:=ufBot+ufHasRitualOfPower+ufCanReplaceCards+ufHasManaStorm;
    gold:=0;
    heroicPoints:=0;
    needHeroicPoints:=100;
    initialHP:=30;
    if (lvl>=4) and (forMode=dtCustom) then inc(initialHP,2); // бонус ботам за титул 
    premium:=0;
    curDeckID:=0;
    customFame:=CalcFame(customBotLevel);
    customLevel:=customBotLevel;
    classicLevel:=aiLevel[lvl];
    classicFame:=CalcFame(classicLevel);
    draftLevel:=aiLevel[lvl];
    draftFame:=CalcFame(draftLevel);
    level:=round(1.2*(customLevel+classicLevel+draftLevel)/3);
    astralPower:=500;
    timeout:=MyTickCount+1000*60*120; // 120 минут
    if forMode in [dtClassic,dtCustom] then autoSearchStarted[forMode]:=Now;
    botLevel:=lvl;
    if forMode=dtCustom then begin
     SetLength(decks,2);
     decks[1].deckID:=99999999;
     decks[1].name:='Bot Deck '+inttostr(deckIdx);
     CopyDeck(CustomBotDecksList.BotDecks[deckIdx].cards,decks[1].cards);
     decks[1].cost:=CalculateDeckCost(decks[1].cards);
     curDeckID:=99999999;
     customLevel:=CustomBotDecksList.BotDecks[deckIdx].startinglevel;
     customFame:=CalcFame(customLevel);
    end;
    playerID:=-botLevel; // regular bot
   end;
   result:=userID;
  end;

 function GetBotLevelForUser(userID:integer;gamemode:TDuelType):integer;
  var
   virtlevel:integer;
   v:single;
  begin
   result:=1;
   if not IsValidUserID(userID) then raise EWarning.Create('GBLFU: invalid userID '+inttostr(userID));
   case gamemode of
    dtClassic:begin
     // Classic
     virtlevel:=Sat(CalcLevel(users[userID].classicFame)+users[userid].boostLevel[dtClassic],1,100);
     v:=0;
     case virtlevel of
      1..2:v:=1;
      3:v:=1.5;
      4:v:=2;
      5:v:=2.25;
      6:v:=2.5;
      7:v:=2.75;
      8:v:=2.75+random/2;
      9:v:=3.25;
      10:v:=3.5;
      11:v:=3.75;
      12:v:=3.75+random/2;
      13..19:v:=4+(virtlevel-12)/8;
      20:v:=4.75+random/2;
      21..29:v:=5+(virtlevel-20)/10;
      30..99:v:=6;
     end;
     result:=RandomInt(v);
     if (minLogMemLevel=0) then
      LogMsg('Bot level for %s: lvl %d, %f -> %d',[users[userID].name,virtlevel,v,result],logDebug);
    end;
   end;
  end;

 // Рассылает 33-й пакет всем тем, кто в этом нуждается, вызывается внутри gSect
 procedure NotifyAboutLookingForDraft(userID:integer=0);
  var
   i,cnt:integer;
   msg:UTF8String;
  begin
   // Подсчитам кол-во игроков в автопоиске драфта
   cnt:=0;
   for i:=1 to high(users) do
    if users[i]<>nil then
     if users[i].autoSearchStarted[dtDraft]>0 then inc(cnt);
   // Формируем сообщение для рассылки
   msg:=FormatMessage([33,cnt]);
   // рассылаем
   if userID>0 then
    PostUserMsg(userID,msg)
   else
    for i:=1 to high(users) do
     if users[i]<>nil then begin
      if (users[i].connected>0) or (users[i].draftID>0) then continue;
      PostUserMsg(i,msg);
     end;
  end;

 // Запускать внутри gSect!
 // Создаёт драфтовый турнир с указанными игроками
 // Если среди u1..u4 есть нули - будут заменены ботами
 function StartDraft(u1,u2,u3,u4:integer):integer;
  var
   i,draftID,userID,cnt:integer;
   avgHumanLvl:single;
   u:array[1..4] of integer;
  procedure CheckUsers;
   var
    i,bot:integer;
    lev:array[1..3] of integer; // Есть 3 бота, здесь будут их уровни (в случайном порядке)
    v:single;
   begin
     // Составляем список допустимых уровней ботов в случайном порядке
     lev[1]:=1; lev[2]:=2; lev[3]:=3;

     if avgHumanLvl>4 then 
      v:=(avgHumanLvl-4)/4 // порог вероятности
     else
      v:=0; 
     if random<v then begin
      inc(lev[3]);
      if random<v then begin
       inc(lev[2]);
       if random<v then inc(lev[1]);
      end;
     end;

     // Еще разок
     v:=0;
     if avgHumanLvl>9 then v:=(avgHumanLvl-9)/5;
     if random<v then begin
      inc(lev[3]);
      if random<v then begin
       inc(lev[2]);
       if random<v then inc(lev[1]);
      end;
     end;

     // Еще разок...
     v:=0;
     if avgHumanLvl>15 then v:=(avgHumanLvl-15)/6;
     if random<v then begin
      inc(lev[3]);
      if random<v then begin
       inc(lev[2]);
       if random<v then inc(lev[1]);
      end;
     end;

     // Перемешаем ботов
     for i:=1 to 10 do begin
      if random(2)>0 then swap(lev[1],lev[3]);
      if random(2)>0 then swap(lev[1],lev[2]);
      if random(2)>0 then swap(lev[2],lev[3]);
     end;
     for bot:=1 to 3 do begin
       // Пытаемся добавить очередного бота вместо пустого слота игрока
       for i:=1 to 4 do
        if u[i]=0 then begin
         u[i]:=AddBot(lev[bot],dtDraft);
         break;
        end;
     end;
   end;
  begin
   result:=0;
   try
   ASSERT(gSect.lockCount>0,'StartDraft error: not in gSect!');
   LogMsg('StartDraft(%s,%s,%s,%s)',[users[u1].name,users[u2].name,users[u3].name,users[u4].name],logNormal);
   u[1]:=u1; u[2]:=u2;
   u[3]:=u3; u[4]:=u4;
   // Определить максимальный уровень живых участников
   avgHumanLvl:=0; cnt:=0;
   for i:=1 to 4 do
    if u[i]>0 then begin
     inc(cnt);
     avgHumanLvl:=avgHumanLvl+users[u[i]].draftLevel;
    end;
   if cnt>0 then avgHumanLvl:=avgHumanLvl/cnt;
   for i:=1 to 4 do
    if u[i]>0 then begin
     if not IsValidUserID(u[i],true) then raise EWarning.Create('Sdr: invalid userID - '+inttostr(u[i]));
     if users[u[i]].connected>0 then raise EWarning.Create('Sdr: user '+users[u[i]].name+' is playing');
    end;
   // Заменить всех нулевых юзеров на ботов
   CheckUsers;

   if (u[1]=u[2]) or (u[1]=u[3]) or (u[1]=u[4]) or
      (u[2]=u[3]) or (u[2]=u[4]) or (u[3]=u[4]) then
    raise EWarning.Create('SDr: invalid users!');
   LogMsg('Starting Draft for %s, %s, %s, %s',
     [users[u[1]].name,users[u[2]].name,users[u[3]].name,users[u[4]].name]);

   for draftID:=1 to high(drafts) do
    if drafts[draftID].players[1]=0 then
     with drafts[draftID] do begin
      result:=draftID;
      created:=Now;
      stage:=0; // ready to draft
      round:=0; // how many cards are taken already
      started:=0;
      timeout:=Now+120*SECOND;
      for i:=1 to 4 do begin
       userID:=u[i];
       players[i]:=userID;
       AddGems(userID,-users[userID].GetCostForMode(dtDraft));
       users[userID].autoSearchStarted[dtDraft]:=0;
       users[userID].draftID:=draftID;
       PostUserMsg(userID,FormatMessage(['31',users[userID].gems]));
       users[userID].UpdateUserStatus;
      end;
      NotifyAboutLookingForDraft;
      // Initialize draft object
      draftInfo.Init;
      for i:=1 to 4 do begin
       draftInfo.Players[i].Name:=users[players[i]].name;
       draftInfo.players[i].control:=users[players[i]].botLevel;
       draftInfo.players[i].cardTaken:=false;
       draftInfo.players[i].deckBuilt:=false;
       draftInfo.players[i].played:=0;       
       draftInfo.players[i].time:=0;
      end;
      exit;
     end;

    raise EWarning.Create('SDr: no draft slots available!');
   except
    on e:EWarning do LogMsg('ERROR in StartDraft: '+ExceptionMsg(e),logWarn);
    on e:exception do LogMsg('ERROR in StartDraft: '+ExceptionMsg(e),logError);
   end;
  end;

 function GetDuelHash(gameID:integer):int64;
  begin
   result:=CheckSum64(@games[gameid].duelSave,sizeof(games[gameid].duelSave));
  end;

 // Запускать внутри gSect!
 function StartDuel(user1,user2:integer;gametype:TDuelType;
     gameclass:TDuelClass;scenario:integer=0):integer;
  var
   i,j,gameID,draftID,firstPlr,c,level1,level2,cost,player1HP,player2HP:integer;
   msg,name,cmpst:UTF8String;
   log:UTF8String;
  function GetBotFace(botLevel:integer):integer;
   begin
    result:=1;
    case botLevel of
     3:result:=11;
     4:result:=9;
     5:result:=14;
    end;
   end;
  function GetPlayerDeck(userID:integer):tshortcardlist;
   var
    deckIdx:integer;
   begin
    with users[userid] do begin
     // если у игрока вообще нет колод - использовать базовую для его специальности
     if length(decks)=1 then begin
      StrToDeck(startDecks[speciality],result);
      exit;
     end;
     deckIdx:=FindDeckByID(curDeckID);
     if deckIdx=0 then deckIdx:=1+random(length(decks));
     ASSERT((deckIdx>0) and (deckIdx<=high(decks)),'Invalid deck index '+inttostr(deckIdx));
     CopyDeck(decks[deckIdx].cards,result);
    end;
   end;
  begin
   try
   result:=0;
   ASSERT((user1>0) and (user2>0),'SD Error: Invalid userID');
   ASSERT(IsValidUserID(user1) and IsValidUserID(user2),'SD Error: Invalid userID');
   ASSERT(gSect.lockCount>0,'SD Error: not in gSect!');
   if user1=user2 then
    raise EWarning.Create('SD ERROR! user1=user2 = '+users[user1].name);
   if users[user1].connected>0 then begin
    i:=users[user1].connected;
    raise EWarning.Create('SD ERROR! '+users[user1].name+' is already in duel with '+users[i].name);
   end;
   if users[user2].connected>0 then begin
    i:=users[user2].connected;
    raise EWarning.Create('SD ERROR! '+users[user2].name+' is already in duel with '+users[i].name);
   end;
   if (serverState=ssRestarting) then begin
    i:=round((restartTime-Now)*1440);
    i:=Sat(i,0,15);
    if i<=5 then begin
     msg:='Sorry, the server is closing in %1 min, please try again later.%%'+inttostr(i);
     PostServerMsg(user1,msg);
     PostServerMsg(user2,msg);
     exit;
    end;
   end;
   result:=0;
   for gameID:=1 to high(games) do
     if games[gameID].user1=0 then begin
      result:=gameID; break;
     end;
   gameID:=result;
   if gameid=0 then raise EWarning.Create('StartDuel: no game slots available!');

   CancelAllProposals(user1);
   CancelAllProposals(user2);

   firstPlr:=1+random(2);
   if gametype=dtCampaign then begin
    if campaignMages[scenario].actfirst then firstPlr:=2;
    if campaignMages[scenario].actsecond then firstPlr:=1;
   end;
   if firstPlr=1 then name:=users[user1].name
    else name:=users[user2].name;
   if scenario>0 then cmpst:=Format(' Scenario: %d. ',[scenario])
    else cmpst:='';
   LogMsg('Starting duel (%d) type %d between "%s" (%d) and "%s" (%d).%s First player: %s class: %d',
     [gameID,ord(gametype),users[user1].name,users[user1].userID,
      users[user2].name,users[user2].userID,cmpst,name,ord(gameclass)]);
   users[user1].playingDeck:='';
   users[user2].playingDeck:='';
   level1:=0; level2:=0;
   player1HP:=users[user1].initialHP;
   player2HP:=users[user2].initialHP;
   if gametype=dtCustom then begin
    inc(player1HP,users[user1].StartLifeBoost);
    inc(player2HP,users[user2].StartLifeBoost);       
   end;
   // Initialize game
   with gamelogic[0] do begin
     fillchar(playersinfo,sizeof(playersinfo),0);
     playersinfo[1].Name:=users[user1].name;
     playersinfo[1].control:=users[user1].botLevel;
     playersinfo[1].FaceNum:=users[user1].avatar;
     playersinfo[1].forcedlife:=player1HP;
     playersinfo[1].skipritual:=not(users[user1].flags and ufHasRitualOfPower>0);
     playersinfo[2].Name:=users[user2].name;
     playersinfo[2].control:=users[user2].botLevel;
     playersinfo[2].FaceNum:=users[user2].avatar;
     if (users[user2].botLevel>0) and (gametype<dtCampaign) then
      playersinfo[2].FaceNum:=GetBotFace(users[user2].botLevel);
     playersinfo[2].forcedlife:=player2HP;
     playersinfo[2].skipritual:=not(users[user2].flags and ufHasRitualOfPower>0);
     case gametype of
      dtCustom:begin
       playersinfo[1].Deck.cards:=GetPlayerDeck(user1);
       if users[user1].botLevel in [1..2] then playersinfo[1].Deck.MutateDeck;
       playersinfo[1].Deck.Prepare; // shuffle
       users[user1].playingDeck:=DeckToStr(playersinfo[1].Deck.cards);
       playersinfo[2].Deck.cards:=GetPlayerDeck(user2);
       if users[user2].botLevel in [1..2] then playersinfo[2].Deck.MutateDeck;
       playersinfo[2].Deck.Prepare; // shuffle
       users[user2].playingDeck:=DeckToStr(playersinfo[2].Deck.cards);
       level1:=users[user1].GetActualLevel(dtCustom);
       level2:=users[user2].GetActualLevel(dtCustom);
      end;
      dtClassic:begin // classic decks
       playersinfo[1].Deck.GenerateRandom(2-byte(firstPlr=1));
       playersinfo[2].Deck.GenerateRandom(2-byte(firstPlr=2));
       level1:=users[user1].GetActualLevel(dtClassic);
       level2:=users[user2].GetActualLevel(dtClassic);
      end;
      dtDraft:begin
       draftID:=users[user1].draftID;
       level1:=users[user1].GetActualLevel(dtdraft);
       level2:=users[user2].GetActualLevel(dtdraft);
       for j:=1 to 4 do begin
        if drafts[draftID].players[j]=user1 then
          playersinfo[1].Deck:=drafts[draftID].draftInfo.players[j].deck;
        if drafts[draftID].players[j]=user2 then
          playersinfo[2].Deck:=drafts[draftID].draftInfo.players[j].deck;
       end;
       playersinfo[1].Deck.Prepare; // shuffle
       playersinfo[2].Deck.Prepare; // shuffle
      end;
      dtCampaign:begin
       level1:=users[user1].GetActualLevel(dtCampaign);
       level2:=users[user2].GetActualLevel(dtCampaign);
       if scenario>=4 then begin
        if scenario<>49 then begin
         // Обычный квест
         playersinfo[1].Deck.cards:=GetPlayerDeck(user1);
         playersinfo[1].Deck.Prepare; // shuffle
        end else begin
         // Специальный квест - всё как в классике
         playersinfo[1].Deck.GenerateRandom(2-byte(firstPlr=1));
         playersinfo[2].Deck.GenerateRandom(2-byte(firstPlr=2));
        end;
       end else begin
        i:=20+scenario;
        if users[user1].speciality=2 then inc(i,3);
        PreparePlayer(playersinfo[1],i,0);
       end;

       if scenario<=20 then i:=users[user1].campaignLoses[scenario]
        else i:=0;
       PreparePlayer(playersInfo[2],scenario,i); // Здесь выставляется уровень бота!
       if (scenario in [41..48]) then begin
        if (users[user1].customLevel<3) then playersInfo[2].control:=2;
        if (users[user1].customLevel>9) then playersInfo[2].control:=4;
       end;
       if scenario=49 then begin
        if (users[user1].customLevel<=2) and
           (users[user1].classicLevel<=2) and
           (users[user1].draftLevel<=2) then playersInfo[2].control:=1
        else
        if (users[user1].classicLevel<5) then playersInfo[2].control:=2
        else
        if (users[user1].classicLevel>9) then playersInfo[2].control:=4;
       end;
       users[user2].botLevel:=playersInfo[2].control;
       users[user2].playerID:=-users[user2].botLevel;
       users[user2].initialHP:=playersInfo[2].forcedlife;
       player2HP:=playersInfo[2].forcedlife;
       users[user2].avatar:=playersInfo[2].FaceNum;
      end;
      else ASSERT(false,'Not yet implemented!');
     end;

     // Dump cards and determine powers
     games[gameid].powers1:=0;
     games[gameid].powers2:=0;
     log:='Cards1:';
     for i:=48 downto 1 do begin
      c:=playersinfo[1].Deck.cards[i];
      if c<>0 then begin
       log:=log+' '+inttostr(c);
       games[gameID].powers1:=games[gameID].powers1 or (1 shl (cardInfo[c].element));
      end;
     end;
     log:=log+'; Pwr='+IntToHex(games[gameID].powers1,1);
     LogMsg(log,logInfo);
     log:='Cards2:';
     for i:=48 downto 1 do begin
      c:=playersinfo[2].Deck.cards[i];
      if c<>0 then begin
       log:=log+' '+inttostr(c);
       games[gameID].powers2:=games[gameID].powers2 or (1 shl (cardInfo[c].element));
      end;
     end;
     log:=log+'; Pwr='+IntToHex(games[gameID].powers2,1);
     LogMsg(log,logInfo);
     // Build duel
     duel.PrepareDuel(ord(gametype),'',0,firstPlr);
     games[gameID].firstPlayer:=duel.curplayer;
     duel.StartTurn;
   end;
   // Create game record
   games[gameID].user1:=user1;
   games[gameID].user2:=user2;
   games[gameID].gametype:=gameType;
   games[gameID].withBot:=(users[user1].botlevel>0) or (users[user2].botlevel>0);
   games[gameID].gameClass:=gameclass;
   games[gameID].turn:=0;
   games[gameID].turns:=0;
   games[gameID].turnStarted:=0;
   games[gameID].turnTimeout:=games[gameID].CalcTurnTimeout;  // ????
   games[gameID].gameStarted:=Now;
   games[gameID].finished:=false;
   games[gameID].numActions:=-1;
   games[gameID].reward:=0;
   games[gameID].time1:=0;
   games[gameID].time2:=0;
   games[gameID].gamelog:='';
   games[gameID].savelog:=false;
   games[gameID].scenario:=scenario;
   games[gameid].duelSave.ImportData(0); // gamelogic ->duelsave
   with games[gameid].duelSave do
    LogMsg('Duel hash: '+inttostr(SaveDuel.getPlayerHash(saveduel.curplayer)),logInfo);
   games[gameID].SaveInitialState;
    
   // Users
   users[user1].connected:=user2;
   users[user2].connected:=user1;
   fillchar(users[user1].autoSearchStarted,sizeof(users[user1].autoSearchStarted),0);
   fillchar(users[user2].autoSearchStarted,sizeof(users[user2].autoSearchStarted),0);
   users[user1].timeoutWarning:=false;
   users[user2].timeoutWarning:=false;
   users[user1].inCombat:=true;
   users[user2].inCombat:=true;
   users[user1].trackPlayersStatus:=false;
   users[user2].trackPlayersStatus:=false;

   // Cost
   if (gametype=dtClassic) and (gameclass=dcRated) then begin
    AddGems(user1,-users[user1].GetCostForMode(gametype));
    AddGems(user2,-users[user2].GetCostForMode(gametype));
   end;
   // Cost for Arena
   if (gameType=dtClassic) and
      (gameclass=dcTraining) and
      (users[user2].botLevel>0) and
      (users[user1].premium<Now) then AddGems(user1,-2);
   
   // Notify player1
   if users[user1].botLevel>0 then level1:=-level1;
   if users[user2].botLevel>0 then level2:=-level2;
   msg:=FormatMessage([30,byte(gametype),byte(gameclass),users[user2].name,users[user2].avatar,
     firstPlr,player1HP,player2HP,users[user2].HasManaStorm,level2,users[user1].gems,users[user2].lang]);
   with games[gameid].duelsave.SavePlayersInfo[1].deck do
     for i:=1 to high(cards) do
       if cards[i]<>0 then
         msg:=msg+'~'+IntToStr(cards[i] xor EncryptSequence(i,users[user2].name));
   PostUserMsg(user1,msg);
   // player2
   msg:=FormatMessage([30,byte(gametype),byte(gameclass),users[user1].name,users[user1].avatar,
     3-firstPlr,player2HP,player1HP,users[user1].HasManaStorm,level1,users[user2].gems,users[user1].lang]);
   with games[gameid].duelsave.SavePlayersInfo[2].deck do
     for i:=1 to high(cards) do
       if cards[i]<>0 then
         msg:=msg+'~'+IntToStr(cards[i] xor EncryptSequence(i,users[user1].name));
   PostUserMsg(user2,msg);

   users[user1].thinkTime:=0;
   users[user2].thinkTime:=0;
   if firstPlr=1 then
    games[gameID].SetTurnTo(user1)
   else
    games[gameID].SetTurnTo(user2);

   games[gameid].duelSaveHash:=GetDuelHash(gameid);

   users[user1].UpdateUserStatus;
   users[user2].UpdateUserStatus;

   except
    on e:EWarning do begin LogMsg('ERROR in StartDuel: '+ExceptionMsg(e),logWarn); result:=0; end;
    on e:exception do begin LogMsg('ERROR in StartDuel: '+ExceptionMsg(e),logError); result:=0; end;
   end;
  end;

 // Стартует бой в кампании (либо квест) с определённым ботом
 procedure StartCampaignDuel(userID,scenario:integer;deckName:UTF8String);
  var
   bot,gameID,reward,g,c,i,level:integer;
  function ChooseRandomCard:integer;
   var
    i,n:integer;
    basicList,advList:IntArray;
   begin
    for i:=1 to high(cardInfo) do
     with cardinfo[i] do
      if not guild and not special then begin
       if abs(users[userID].ownCards[i])>=3 then continue;
       if basic then AddInteger(basicList,i)
        else AddInteger(advList,i);
      end;
    n:=length(basicList);
    if n>0 then begin
     result:=basicList[random(n)];
     exit;
    end;
    n:=length(advList);
    if n>0 then begin
     result:=advList[random(n)];
     exit;
    end;
    result:=-10-10; // 10 gold
   end;

  begin
   if (serverState=ssRestarting) and (Now>restartTime-9*MINUTE) then begin
     LogMsg('StartCampaign rejected for '+users[userid].name+' - server restarting',logInfo);
     ShowMessageToUser(userID,'Sorry, the server restarts in^ '+HowLong(restartTime));
     exit;
    end;

   // нельзя стартовать бой тому, кому выслано приглашение на грабёж каравана
   for g:=1 to high(guilds) do
    if guilds[g].name<>'' then
     for c:=1 to 2 do
      if guilds[g].caravans[c].running then
       for i:=1 to 8 do
        if (guilds[g].caravans[c].battles[i]=1) and
           (guilds[g].caravans[c].attackers[i]=users[userID].name) then begin
         LogMsg('StartCampaignDuel refused because of caravan proposal %s type %d slot %d',
          [guilds[g].name,c,i],logDebug);
         exit;
        end;

   if users[userID].connected>0 then
    raise EWarning.Create('Player '+users[userid].name+' is already in duel with '+users[users[userID].connected].name);
   if not users[userID].HasQuest(scenario) then
    raise EWarning.Create('Player '+users[userid].name+' doesn''t have quest #'+inttostr(scenario));
   users[userID].room:=1;
   if scenario>=4 then begin  // Check deck
    if not SetCurDeck(userID,deckName) then begin
     LogMsg('Invalid deck for '+users[userid].name+' for campaign duel: '+deckName,logWarn);
     exit;
    end;
   end;

   if scenario=38 then begin
    // Тренировка с ботом своими колодами - противник выбирается случайно, но исходя из скрытой славы игрока
    TrainingWithBot(userID,0,1,deckName);
    exit;
   end;

   bot:=AddBot(1,dtCampaign,scenario); // actually, level doesn't matter here -> will be overriden
   gameID:=StartDuel(userID,bot,dtCampaign,dcRated,scenario);
   if gameID=0 then exit;
   // Предстоящая награда
   reward:=0;
   case scenario of
     1:reward:=-users[userID].speciality;
     2:case users[userID].speciality of
         1:reward:=5;
         2:reward:=58;
       end;
     3:reward:=10001;  // deck editing + mage title
     4:reward:=-10-25; // +25 gold
     5:reward:=10002;  // card replacing
     6,10,11:reward:=ChooseRandomCard;
     7:reward:=-10-30; // +30 gold
     8:reward:=30002; // +2 HP
     9:reward:=40025; // +25 AP
    12:reward:=10003; // Ritual of power
    13:reward:=-10-40; // +40 gold
    14:reward:=30003; // +3 HP
    15:reward:=50100; // +100 gems
    16:reward:=-10-25; // +25 Gold
    17:reward:=40010; // +10 AP
    18:reward:=20001; // +1d of premium
    19:reward:=50025; // +25 MissionPoints
    20:reward:=10004; // Wtf? IDK

    41..43:reward:=50005; // +5 gems
    44..46:if users[userid].GetUserTitle>=titleAdvancedMage then reward:=60020 else reward:=60005; // +5 heroic
{    44..46:if GuildHasPerk(users[userid].guild,10) then reward:=60015 // +15 heroic
     else reward:=60005; // +5 heroic}
    47..49:reward:=-10-5; // +5 gold
   end;
   if (reward<1000) then PostUserMsg(userID,FormatMessage([24,reward]));
   if scenario=2 then reward:=0; // отмена награды, т.к. эта карта уже присутствует в начальном наборе и стартовой колоде
   games[gameid].reward:=reward;
  end;

 procedure NotifyUserAboutGoldOrGems(userid:integer);
  begin
   if IsValidUserID(userID) then
    PostUserMsg(userID,FormatMessage([28,users[userID].gold,users[userID].gems]));
  end;

 // Возвращает кол-во фактически начисленной экспы
 function GrantGuildExp(playerID:integer;gName:UTF8String;amount:single;reason:UTF8String):integer;
  var
   g,was,m:integer;
   bonus:single;
  begin
   result:=0;
   if gName='' then exit;
   try
   gSect.Enter;
   try
   g:=FindGuild(gName);
   if g<=0 then begin
    LogMsg('Guild '+gName+' not found!',logWarn);
    exit;
   end;
   with guilds[g] do begin
    bonus:=ExpBonus;
    was:=exp;
    result:=round(amount*bonus+0.001);
    inc(exp,result);
    while exp>=GuildExpRequied[level+1] do begin
     inc(level);
     dec(exp,GuildExpRequied[level]);
     GuildLogMessage(g,'The guild reached level %1!%%'+inttostr(level));
    end;
    PostGuildMsg(g,FormatMessage([122,1,exp,level]));
    AddTask(0,0,['UPDATEGUILD',id,'exp='+inttostr(exp)+', level='+inttostr(level)]);
    AddTask(0,0,['EVENTLOG',GUILDBASE+id,'GUILDEXP',
     Format('%d+%f*%f=%d; %d; %s',[was,amount,bonus,exp,playerID,reason])]);
    m:=FindMemberById(playerID);
    if m>=0 then begin
     inc(members[m].exp,result);
     AddTask(0,0,['UPDATEGUILDMEMBER',playerID,'exp='+inttostr(members[m].exp)]);
     PostGuildMsg(g,'122~7~'+FormatMemberInfo(m),'Exp');
    end;
   end;
   finally
    gSect.Leave;
   end;
   except
    on e:Exception do LogMsg('GrantGuildExp error: '+ExceptionMsg(e));
   end;
  end;

 procedure GrantGuildGold(playerID:integer;gName:UTF8String;amount:integer;reason:UTF8String);
  var
   g,was,m:integer;
  begin
   if gName='' then exit;
   try
   gSect.Enter;
   try
   g:=FindGuild(gName);
   if g<=0 then begin
    LogMsg('Guild '+gName+' not found!',logInfo);
    exit;
   end;
//   bonus:=1.0;
   was:=guilds[g].treasures;
   inc(guilds[g].treasures,amount);
   PostGuildMsg(g,FormatMessage([122,2,guilds[g].treasures]));
   AddTask(0,0,['UPDATEGUILD',guilds[g].id,'treasures='+inttostr(guilds[g].treasures)]);
   AddTask(0,0,['EVENTLOG',GUILDBASE+guilds[g].id,'GUILDGOLD',
    Format('%d+%d=%d; %d; %s',[was,amount,guilds[g].treasures,playerID,reason])]);

   m:=guilds[g].FindMemberById(playerID);
   if m>=0 then with guilds[g] do begin
    inc(members[m].treasures,amount);
    AddTask(0,0,['UPDATEGUILDMEMBER',playerID,'treasures='+inttostr(members[m].treasures)]);
    PostGuildMsg(g,'122~7~'+FormatMemberInfo(m),'Gold');
   end;

   finally
    gSect.Leave;
   end;
   except
    on e:Exception do LogMsg('GrantGuildGold error: '+ExceptionMsg(e));
   end;
  end;

 procedure CheckGuildForDailyQuest(g:integer);
  begin
   with guilds[g] do begin
    if daily=100 then exit;
    if daily>=DailyGuildQuestWins(level,bonuses[5]='1') then begin
     LogMsg('Daily mission achieved for guild '+name,logNormal);
     GrantGuildExp(0,name,100,'Daily mission');
     daily:=100; // reached
    end;
    PostGuildMsg(g,FormatMessage([122,4,daily]));
    AddTask(0,0,['UPDATEGUILD',id,'daily='+inttostr(daily)]);
   end;
  end;

 procedure AddGuildWin(playerID:integer;gName:UTF8String);
  var
   g:integer;
  begin
   if gName='' then exit;
   g:=FindGuild(gName);
   if g<=0 then begin
    LogMsg('Guild '+gName+' not found!',logWarn);
    exit;
   end;
   with guilds[g] do
    if daily<100 then begin
     inc(daily);
     CheckGuildForDailyQuest(g);
    end;
  end;

 // Даёт указанное кол-во чего-то игроку (не для регулярных трат!)
 procedure Grant(userID:integer;what:TPlayerParam;amount:integer;reason:UTF8String);
  var
   was,new:integer;
   pName,fName:UTF8String;
  begin
   ASSERT(users[userID]<>nil);
   ASSERT((amount>=0) and (amount<=100000),'Grant: invalid amount '+inttostr(amount));
   if amount=0 then exit;
   with users[userid] do begin
    if botLevel>0 then exit; // grant nothing to bots
    case what of
     ppGold:begin
       pName:='GOLD';
       fName:='gold';
       was:=gold;
       inc(gold,amount);
       new:=gold;
     end;
     ppHP:begin
       pName:='HP';
       fName:='HP';
       was:=initialHP;
       inc(initialHP,amount);
       if initialHP>30 then begin
        LogMsg('Warning! Too high HP - '+IntToStr(initialHP),logWarn);
        initialHP:=30;
       end;
       new:=initialHP;
     end;
     ppAP:begin
       pName:='AP';
       fName:='astralPower';
       was:=astralPower;
       inc(astralPower,amount);
       new:=astralPower;
     end;
     ppGems:begin
       pName:='GEMS';
       fName:='gems';
       was:=gems;
       inc(gems,amount);
       new:=gems;
     end;
     else begin was:=0; new:=0; end;
    end;
    AddTask(0,0,['UPDATEPLAYER',playerID,fName+'='+inttostr(new)]);
    AddTask(0,0,['EVENTLOG',playerID,pName,Format('%d+%d=%d; %s',[was,amount,new,reason])]);
   end;
  end;

 // Отнимает указанное кол-во чего-то (золота или кристаллов) у игрока
 function Spend(userID:integer;what:TPlayerParam;amount:integer;reason:UTF8String):boolean;
  var
   was,new:integer;
   pName,fName:UTF8String;
  begin
   ASSERT((amount>=0) and (amount<=100000),'Grant: invalid amount '+inttostr(amount));
   ASSERT(users[userID]<>nil);
   result:=true;
   if amount=0 then exit;
   result:=false;
   gSect.Enter;
   try
   with users[userid] do begin
    if botLevel>0 then exit;
    case what of
     ppGold:begin
       pName:='GOLD';
       fName:='gold';
       was:=gold;
       dec(gold,amount);
       new:=gold;
     end;
     ppGems:begin
       pName:='GEMS';
       fName:='gems';
       was:=gems;
       dec(gems,amount);
       new:=gems;
     end;
     else begin
      result:=false;
      was:=0; new:=0;
     end;
    end;
    if new<0 then begin
     LogMsg('Can''t spend %d of %s: only %d available!',[amount,fname,was],logWarn);
     exit;
    end;
    AddTask(0,0,['UPDATEPLAYER',playerID,fName+'='+inttostr(new)]);
    AddTask(0,0,['EVENTLOG',playerID,pName,Format('%d-%d=%d; %s',[was,amount,new,reason])]);
   end;
   result:=true;
   finally
    gSect.Leave;
   end;
  end;

 // Потратить гильдейское богатство
 function SpendGuild(playerID:integer;gIdx:integer;amount:integer;reason:UTF8String):boolean;
  var
   was,new:integer;
  begin
   result:=false;
   gSect.Enter;
   try
    ASSERT((gIdx>0) and (gIdx<high(guilds)));
    ASSERT(guilds[gIdx].id>0);
    ASSERT((amount>=0) and (amount<=100000),'Grant: invalid amount '+inttostr(amount));
    was:=guilds[gIdx].treasures;
    if amount>was then result:=false;
    dec(guilds[gIdx].treasures,amount);
    new:=guilds[gIdx].treasures;

    AddTask(0,0,['UPDATEGUILD',guilds[gIdx].id,'treasures='+inttostr(new)]);
    AddTask(0,0,['EVENTLOG',GUILDBASE+guilds[gIdx].id,'GUILDGOLD',
      Format('%d-%d=%d;%d;%s',[was,amount,new,playerid,reason])]);
    PostGuildMsg(gIdx,FormatMessage([122,2,new]));
    result:=true;
   finally
    gSect.leave;
   end;
  end;

 // Изменяет какой-либо флаг игроку
 procedure GrantFlag(userID:integer;flag:integer;state:boolean;reason:UTF8String);
  var
   was,new:UTF8String;
  begin
   ASSERT(users[userID]<>nil);
   ASSERT(flag>=$100,'GrantFlag: invalid flag '+inttostr(flag));
   with users[userid] do begin
    was:=MakeUserFlags(flags);
    if state then flags:=flags or flag
     else flags:=flags and (not flag);
    new:=MakeUserFlags(flags);
    AddTask(0,0,['UPDATEPLAYER',playerID,'flags="'+new+'"']);
    AddTask(0,0,['EVENTLOG',playerID,'FLAGS',
      Format('%s+%s=%s; %s',[was,MakeUserFlags(flag),new,reason])]);
   end;
  end;

 // Даёт указанное кол-во премиума игроку (в сутках)
 procedure GrantPremium(userID:integer;amount:single;reason:UTF8String);
  var
   p:TDateTime;
  begin
   ASSERT(users[userID]<>nil);
   ASSERT((amount>=0) and (amount<=10000),'GrantPremium: invalid amount '+Floattostr(amount));
   with users[userID] do begin
    p:=premium;
    if p<Now then p:=Now;
    premium:=p+amount;
    AddTask(0,0,['UPDATEPLAYER',playerID,'premium="'+FormatDateTime('yyyy.mm.dd hh:nn:ss',premium)+'"']);
    AddTask(0,0,['EVENTLOG',playerID,'PREMIUM',Format('%s+%f->%s; %s',
      [FormatDateTime('dd.mm.yy hh:nn',p),amount,FormatDateTime('dd.mm.yy hh:nn',premium),reason])]);
    PostUserMsg(userID,FormatMessage([29,round((premium-Now)*86400)]));
   end;
  end;

 // Даёт указанное кол-во премиума игроку (в сутках)
 // Запускать асихронно!
 procedure GrantPremiumToOfflinePlayer(plrName:UTF8String;amount:single;reason:UTF8String);
  var
   p,pNew:TDateTime;
   sa:AStringArr;
   playerID:integer;
  begin
   ASSERT(plrName<>'');
   ASSERT((amount>0) and (amount<=1000),'GrantPremium: invalid amount '+Floattostr(amount));
   sa:=db.Query('SELECT id,premium FROM players WHERE name="'+SQLSafe(plrName)+'"');
   if db.rowCount=0 then raise EError.Create('Player '+plrName+' not found!');
   playerID:=StrtoIntDef(sa[0],0);
   p:=GetDateFromStr(sa[1]);
   LogMsg('GrantPremium to %s: was %s (%s)',[plrName,FormatDateTime('yyyy-mm-dd hh:nn:ss',p),sa[1]]);
   if p<Now then p:=Now;
   pNew:=p+amount;
   LogMsg('GrantPremium to %s: %s -> %s',
     [plrName,FormatDateTime('yyyy-mm-dd hh:nn:ss',p),FormatDateTime('yyyy-mm-dd hh:nn:ss',pNew)]);
   AddTask(0,0,['UPDATEPLAYER',playerID,'premium="'+FormatDateTime('yyyy.mm.dd hh:nn:ss',pNew)+'"']);
   AddTask(0,0,['EVENTLOG',playerID,'PREMIUM',Format('%s+%f->%s; %s',
     [FormatDateTime('dd.mm.yy hh:nn',p),amount,FormatDateTime('dd.mm.yy hh:nn',pNew),reason])]);
  end;

 // Даёт указанное кол-во голды игроку
 // Запускать асихронно!
 procedure GrantGoldToOfflinePlayer(plrName:UTF8String;amount:integer;reason:UTF8String);
  var
   gold:integer;
   sa:AStringArr;
   playerID:integer;
  begin
   ASSERT(plrName<>'');
   ASSERT((amount>0) and (amount<=10000),'GrantGold: invalid amount '+inttostr(amount));
   sa:=db.Query('SELECT id,gold FROM players WHERE name="'+SQLSafe(plrName)+'"');
   if db.rowCount=0 then raise EError.Create('Player '+plrName+' not found!');
   playerID:=StrtoIntDef(sa[0],0);
   gold:=StrToInt(sa[1]);
   LogMsg('GrantGold to %s: %d + %d = %d',[plrName,gold,amount,gold+amount]);
   inc(gold,amount);
   AddTask(0,0,['UPDATEPLAYER',playerID,'gold='+IntToStr(gold)]);
   AddTask(0,0,['EVENTLOG',playerID,'GOLD',Format('%d+%d->%d; %s',
     [gold-amount,amount,gold,reason])]);
  end;

 // Даёт указанное кол-во кристаллолв игроку
 // Запускать асихронно!
 procedure GrantGemsToOfflinePlayer(plrName:UTF8String;amount:integer;reason:UTF8String);
  var
   gems:integer;
   sa:AStringArr;
   playerID:integer;
  begin
   ASSERT(plrName<>'');
   ASSERT((amount>0) and (amount<=10000),'GrantGems: invalid amount '+inttostr(amount));
   sa:=db.Query('SELECT id,gems FROM players WHERE name="'+SQLSafe(plrName)+'"');
   if db.rowCount=0 then raise EError.Create('Player '+plrName+' not found!');
   playerID:=StrtoIntDef(sa[0],0);
   gems:=StrToInt(sa[1]);
   LogMsg('GrantGems to %s: %d + %d = %d',[plrName,gems,amount,gems+amount]);
   inc(gems,amount);
   AddTask(0,0,['UPDATEPLAYER',playerID,'gold='+IntToStr(gems)]);
   AddTask(0,0,['EVENTLOG',playerID,'GEMS',Format('%d+%d->%d; %s',
     [gems-amount,amount,gems,reason])]);
  end;

 // Сообщает игроку о том, что он получил новую карту
 // (cardSource=1 - за хероик поинты, 2 - покупка за голду в маркете, 3 - случайная карта за 50g, 4 - крафт, 5 - за первую победу в классике)
 // Проверяет кол-во карт у игрока, и если надо - даёт бонус за миссию
 procedure NotifyUserAboutNewCard(userID,card,cardSource:integer);
  var
   cnt,mission,cost:integer;
  begin
   try
    with users[userID] do begin
     if cardSource in [1,5] then
      PostUserMsg(userID,FormatMessage([23,cardSource,card,abs(ownCards[card]),heroicPoints,needHeroicPoints]));
     if cardSource in [2,3] then begin
      if cardSource=2 then cost:=20
       else cost:=50;
      PostUserMsg(userID,FormatMessage([19,card,cost,gold]));
     end; 
    end;

    // Миссия про карты
    cnt:=users[userID].OwnedCardsCount;
    if (cnt mod 10=0) and (cnt<=400) then begin
      if (cnt=100) or (cnt=200) or (cnt=300) or (cnt=400) then begin
       mission:=45;
       if cnt=200 then mission:=46;
       if cnt=300 then mission:=47;
       if cnt=400 then mission:=48;
       PostUserMsg(userID,FormatMessage([71,mission]));
       if users[userID].steamID<>0 then
        AddTask(userID,0,['SETSTEAMACHIEVEMENTS']);
      end else begin
       PostUserMsg(userID,FormatMessage([71,44]));
       //Grant(userID,ppGems,20,'Cards='+inttostr(cnt));
      end;
      Grant(userID,ppAP,5,'Cards='+inttostr(cnt));
    end;
   except
    on e:exception do LogMsg('Error in CFCM: '+ExceptionMsg(e),logWarn);
   end;
  end;

 function GetRandomAvailableCard(userID:integer):integer;
  var
   list:array[1..500] of integer;
   i,cnt,maxCount:integer;
   basicOnly:boolean;
  begin
   result:=0;
   basicOnly:=users[userID].OwnedCardsCount<90;
   maxCount:=3;
   if users[userID].getUserTitle>=titleArchmage then maxCount:=6;
   cnt:=0;
   for i:=1 to high(cardInfo) do begin
    if cardInfo[i].guild or cardInfo[i].special then continue;
    if basicOnly and not cardInfo[i].basic then continue;
    if (users[userid].ownCards[i]=maxCount) or
       (users[userid].ownCards[i]<0) {upgraded cards} then continue;
    inc(cnt);
    list[cnt]:=i;
   end;
   if cnt=0 then exit;
   result:=list[1+random(cnt)];
  end;

 // Открывает доступ игроку к очередному случайному экземпляру карты,
 // возвращает false если все карты уже доступны, поэтому ничего игроку не дали
 // Эта функция никак не уведомляет игрока - это забота внешнего кода
 // Если card<>0, то даёт именно указанную карту
 function GrantNewCard(userID:integer;card:integer=0):integer;
  begin
   result:=0;
   try
   if card=0 then card:=GetRandomAvailableCard(userID);
   if card=0 then exit;
   if (card<0) or (card>high(cardInfo)) then raise EWarning.Create('WARN! Invalid card index: '+inttostr(card));
   LogMsg('Grant card %s (%d) to %s',[cardinfo[card].name,card,users[userID].name],logNormal);
   if users[userID].ownCards[card]>=0 then
    inc(users[userID].ownCards[card]);
   //ASSERT(users[userID].ownCards[card]<=3);
   AddTask(userID,0,['GRANTCARD',users[userid].playerID,CardSetToStr(users[userID].ownCards)]);
   result:=card;
   except
    on e:exception do LogMsg('Error in GrantNewCard: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure GrantNewCardsIfNeeded(winner:integer);
  var
   card:integer;
  begin
   with users[winner] do
    while heroicPoints>=needHeroicPoints do begin
     LogMsg('%d HP > %d (needHP) for %s ',[heroicPoints,needHeroicPoints,name],logInfo);
     // Give a card to winner
     card:=GrantNewCard(winner);
     if card>0 then begin
      dec(heroicPoints,needHeroicPoints);
      if needHeroicPoints<100 then inc(needHeroicPoints,3)
       else inc(needHeroicPoints,2);
      NotifyUserAboutNewCard(winner,card,1);
      AddTask(0,0,['EVENTLOG',users[userid].playerID,'NEWCARD',
         Format('%d;nhp=%d',[card,users[userid].needheroicPoints])]);
     end else begin
      // All cards already available
      heroicPoints:=needHeroicPoints-1;
      if (minLogMemLevel=0) then
       LogMsg(users[winner].name+' already has all cards',logDebug);
     end;
    end;
  end;

 procedure GrantNewCardForClassic(winner:integer);
  var
   card:integer;
  begin
   with users[winner] do begin
    card:=GrantNewCard(winner);
    if card>0 then begin
      NotifyUserAboutNewCard(winner,card,5);
      AddTask(0,0,['EVENTLOG',users[userid].playerID,'NEWCARD',inttostr(card)+';ClsDailyWin']);
    end else begin
     // Все карты уже есть - дать 5 кристаллов
     Grant(winner,ppGems,5,'ClsDailyWin');
    end;
   end;
  end;

 // Игрок выиграл бой в кампании - дать плюшки, обновить инфу
 procedure GrantCampaignReward(gameID,userID:integer;winner:boolean);
  var
   scenario,reward,rType,g,m,res:integer;
   i:integer;
   reason:UTF8String;
//   heroic,needHeroic:integer;
  begin
   ASSERT(IsValidUserID(userID,true),'GCR: Invalid winner '+inttostr(userID));
   if users[userID].botLevel>0 then exit;
   if games[gameid].gameclass<>dcRated then exit; // тренировка с ботом - нет наград
   scenario:=games[gameID].scenario;
   reward:=games[gameID].reward;
   ASSERT(scenario>0,'GCR: Invalid scenario '+inttostr(scenario));
   if winner then begin
    // Battle won
    LogMsg('Reward=%d for scenario %d for player %s',[reward,scenario,users[userid].name],logInfo);
    with users[userID] do begin
     for i:=1 to 6 do
      if quests[i]=scenario then begin
       quests[i]:=0;
       if scenario<=20 then inc(campaignWins); // Campaign or quest?
      end;
     DefineUserQuests(userID,users[userid].updateQuests);
     if users[userid].updateQuests then users[userid].updateQuests:=false;
     if scenario>=40 then begin
      i:=1;
      if GuildHasPerk(guild,19) then i:=i*3;
      inc(caravanPriority,i);
     end;
     AddTask(0,0,['UPDATEPLAYER',playerID,Format('campaignwins=%d, quests="%s", carPrior=%d',
       [campaignWins,GetQuests,caravanPriority])]);
     UpdatePlayerData;
     if (scenario=20) and (guild<>'') then begin
      g:=FindGuild(guild);
      if g>0 then begin
       m:=guilds[g].FindMember(name);
       PostGuildMsg(g,'122~7~'+guilds[g].FormatMemberInfo(m),'Camp-20');
      end;
     end;
     if scenario=15 then begin
      inc(caravanPriority,100);
      if GuildHasPerk(guild,19) then inc(caravanPriority,200);
      AddTask(0,0,['UPDATEPLAYER',playerID,'carPrior='+IntToStr(caravanPriority)]);
     end;
    end;
    rType:=reward div 10000;
    if rType>0 then reward:=reward mod 10000;
    reason:='Reward for #'+inttostr(scenario);
    case rType of
     0:begin // card or gold
        if reward>0 then GrantNewCard(userID,reward);
        if reward<-10 then Grant(userID,ppGold,-reward-10,reason);
       end;
     1:begin // something special
        case reward of
         1:GrantFlag(userID,ufCanMakeDecks,true,reason); // Deck editing
         2:GrantFlag(userID,ufCanReplaceCards,true,reason); // Card replacing
         3:GrantFlag(userID,ufHasRitualOfPower,true,reason); // Ritual of Power
        end;
       end;
     2:GrantPremium(userID,reward,reason);
     3:Grant(userID,ppHP,reward,reason);
     4:Grant(userID,ppAP,reward,reason);
     5:Grant(userID,ppGems,reward,reason);
     6:begin
        inc(users[userID].heroicPoints,reward);
        GrantNewCardsIfNeeded(userID);
        // Уведомлять клиент не нужно - он и так в курсе
        with users[userID] do
         AddTask(0,0,['UPDATEPLAYER',playerID,Format('insight=%d,needInsight=%d',[heroicPoints,needHeroicPoints])]);
     end;
    end;
    if scenario>=40 then begin
     if GuildHasPerk(users[userid].guild,2) then begin
      GrantGuildGold(users[userid].playerID,users[userid].guild,1,'Perk-2');
     end;
     if GuildHasPerk(users[userid].guild,20) then begin
      res:=GrantGuildExp(users[userid].playerID,users[userid].guild,5,'Perk-20');
     end;
    end;
   end else begin
    // Battle lost
    if scenario<=20 then with users[userID] do begin
     inc(campaignLoses[scenario]);
     AddTask(0,0,['UPDATEPLAYER',playerID,Format('campaignLoses="%s"',[GetCampaignLoses])]);
    end;
   end;
  end;

 // Вычисляет плюшки для участников игры (вызывается внутри gSect в сетевом потоке,
 // все фактические изменения выносятся в асинхронные таски)
 procedure AddGameRewards(gameID,winner,loser:integer);
  var
   winnerFameBonus,loserFamePenalty,heroic,heroicBonus,guildExpBonus,needHeroic,loserLevel,winnerLevel,
     card,winnerFame,loserFame,newFame,newLevel,newTotalLevel,gems,i,CtP,winnerPowers,CPbonus:integer;
   gametype:TDuelType;
   arenaMode:boolean;
   g,m:integer;
  begin
   ASSERT(IsValidUserID(winner,true),'AGR: Invalid winner'+inttostr(winner));
   ASSERT(IsValidUserID(loser,true),'AGR: Invalid loser'+inttostr(loser));
   try
   gems:=0;
   gametype:=games[gameid].gametype;
   arenaMode:=false;
   case gametype of
    dtCustom:begin
     loserLevel:=users[loser].customLevel;
     winnerLevel:=users[winner].customLevel;
     loserFame:=users[loser].customFame;
     winnerFame:=users[winner].customFame;
     winnerFameBonus:=FameForCustomized(winnerFame,loserFame);
     gems:=Sat(round(3*winnerFameBonus/50),1,6);
     CPbonus:=1;
    end;
    dtClassic:begin
     loserLevel:=users[loser].classicLevel;
     winnerLevel:=users[winner].classicLevel;
     loserFame:=users[loser].classicFame;
     winnerFame:=users[winner].classicFame;
     winnerFameBonus:=FameForClassic(winnerFame,loserFame);
     gems:=0; //Sat(round(10*sqrt(winnerFameBonus/50)),4,20);
     CPbonus:=2;
    end;
    dtDraft:begin
     loserLevel:=users[loser].draftLevel;
     winnerLevel:=users[winner].draftLevel;
     loserFame:=users[loser].draftFame;
     winnerFame:=users[winner].draftFame;
     winnerFameBonus:=FameForDraft(winnerFame,loserFame);
     gems:=0; //Sat(round(8*Power(winnerFameBonus/50,1/3)),2,15);
     CPbonus:=2;     
    end;
   end;
   loserFamePenalty:=-(winnerFameBonus-1);
   if loserFamePenalty>0 then loserFamePenalty:=0;
   case loserLevel of
    1:loserFamePenalty:=round(0.25*loserFamePenalty+0.001);
    2:loserFamePenalty:=round(0.5*loserFamePenalty+0.001);
    3:loserFamePenalty:=round(0.75*loserFamePenalty+0.001);
   end;
   guildExpBonus:=0;

   // Insight points and new cards
   heroicBonus:=loserLevel;

   // Training?
   if games[gameID].gameclass=dcTraining then begin
     if (minLogMemLevel=0) then
      LogMsg('Training => no rewards',logDebug);
     winnerFameBonus:=0;
     loserFamePenalty:=0;
     heroicBonus:=0;
     gems:=0;
     if users[loser].botLevel>0 then begin // Тренировка с ботом
       // арена
       arenaMode:=true;
       if games[gameid].gametype=dtClassic then begin
         heroicBonus:=users[loser].classicLevel; // Бонус за платную тренировку случайными колодами
         LogMsg('Arena: +%d hp',[heroicBonus],logInfo);
         if users[winner].maxBotLevel=users[loser].botLevel then begin
          inc(users[winner].maxBotLevel);
          with users[winner] do
           AddTask(0,0,['UPDATEPLAYER',playerID,'botLevels='+inttostr(maxBotLevel*10+curBotLevel)]);
         end;
       end;
     end;
     if (games[gameid].gametype=dtCustom) and
        (users[loser].botLevel>0) or
        (users[winner].botLevel>0) then begin
         if users[loser].botLevel>0 then gems:=1;
         winnerFameBonus:=FameForCustomized(users[winner].trainFame,loserFame);
         LogMsg('DoS: +'+inttostr(gems)+' crystal, fameBonus='+inttostr(winnerFameBonus),logInfo);
         if users[loser].botLevel>0 then begin
          with users[winner] do begin
           trainFame:=max2(customFame,trainFame+winnerFameBonus);
           AddTask(0,0,['UPDATEPLAYER',playerID,'trainFame='+inttostr(trainFame)]);
          end;
         end else begin
          with users[loser] do begin
           trainFame:=max2(customFame,trainFame-winnerFameBonus+1);
           AddTask(0,0,['UPDATEPLAYER',playerID,'trainFame='+inttostr(trainFame)]);
          end;
         end;
         winnerFameBonus:=0;
       end;
   end;

   if games[gameID].gameclass=dcCaravan then begin
     if (minLogMemLevel=0) then
      LogMsg('Caravan => no rewards',logDebug);
     heroicBonus:=0;
     gems:=0;
   end;

   if games[gameid].gameclass=dcRated then begin // Лига - рейтинг
    // В кастоме если премиум - полуторная награда
    if (gametype=dtCustom) and (users[winner].premium>Now) then heroicBonus:=round(heroicBonus*2);
    // В классике и драфте - учетверённая награда
    if gametype in [dtClassic,dtDraft] then heroicBonus:=heroicBonus*4;
    // Guild perk 15
    if (heroicBonus>0) and GuildHasPerk(users[winner].guild,15) then inc(heroicBonus,2);
   end;

   // Guild perk 17 - конвертация HP в гильдейский опыт (втч и Арена)
   if (heroicBonus>0) and GuildHasPerk(users[winner].guild,17) and
      (GetRandomAvailableCard(winner)=0) then begin
    LogMsg('Perk-17: heroicBonus -> guild XP');  
    guildExpBonus:=GrantGuildExp(users[winner].playerID,users[winner].guild,0.6+heroicBonus/15,'Perk-17');
    heroicBonus:=0;
   end;

   heroic:=users[winner].heroicPoints+heroicBonus;
   needHeroic:=users[winner].needHeroicPoints;

   // Call to Powers
   CtP:=0;
   if (users[winner].guild<>'') and
      (gametype=dtCustom) and
      (games[gameID].gameclass=dcRated) then begin
    if winner=games[gameid].user1 then
     winnerPowers:=games[gameid].powers1
    else
     winnerPowers:=games[gameid].powers2;
    CtP:=GetGuildCtP(users[winner].guild,users[winner].name,winnerPowers);
   end;

   // Уведомим игроков о наградах
   users[winner].PreviewStats(gametype,winnerFameBonus,newFame,newLevel,newTotalLevel);
   PostUserMsg(winner,FormatMessage([38,ord(gametype),winnerFameBonus,newFame,newLevel,newTotalLevel,
     gems,heroicBonus,guildExpBonus,loserFamePenalty,CtP]));

   users[loser].PreviewStats(gametype,loserFamePenalty,newFame,newLevel,newTotalLevel);
   PostUserMsg(loser,FormatMessage([38,ord(gametype),loserFamePenalty,newFame,newLevel,newTotalLevel,
     0,heroicBonus,0,winnerFameBonus,0]));

   AddGems(winner,gems); 
   LogMsg('Victory reward for %s: fame=%d gems=%d heroic=%d',[users[winner].name,winnerFameBonus,gems,heroicBonus],logNormal);

   // Корректировка виртуального уровня
   users[winner].boostLevel[gametype]:=1;
   users[loser].boostLevel[gametype]:=-1;

   if GuildHasPerk(users[winner].guild,19) then CPBonus:=CPbonus*3;
   inc(users[winner].caravanPriority,CPbonus);

   // Grant new cards?
   users[winner].heroicPoints:=heroic;
   users[winner].needHeroicPoints:=needHeroic;
   GrantNewCardsIfNeeded(winner);

   if (gametype=dtClassic) and (games[gameID].gameclass=dcRated) and (users[winner].CanGetRewardForClassic) then
    GrantNewCardForClassic(winner);

   if CtP>0 then begin
    LogMsg('CallToPowers %d for %s',[CtP,users[winner].name],logDebug);
    case CtP of
     1:GrantGuildExp(users[winner].playerID,users[winner].guild,10,'CtP');
     2:GrantGuildGold(users[winner].playerID,users[winner].guild,3,'CtP');
     3:inc(winnerFameBonus,20);
    end;
    g:=FindGuild(users[winner].guild);
    if g>0 then begin
     m:=guilds[g].FindMember(users[winner].name);
     if m>=0 then begin
      inc(guilds[g].members[m].rewards);
      inc(guilds[g].members[m].rew[CtP]);
      AddTask(0,0,['UPDATEGUILDMEMBER',users[winner].playerID,
        Format('rewards=%d, r%d=r%d+1',[guilds[g].members[m].rewards,CtP,CtP])]);
      PostUserMsg(winner,'122~8~'+guilds[g].members[m].FormatCallToPowers);
     end;
    end;
   end;

   // Update fame and Insight in the DB
   if games[gameID].gameclass<>dcTraining then begin
    if users[winner].playerID>0 then AddTask(winner,0,
      ['UpdatePlayerStats',users[winner].playerID,byte(games[gameid].gametype),winnerFameBonus,
        users[winner].heroicPoints,users[winner].needHeroicPoints,1]);
    if users[loser].playerID>0 then AddTask(loser,0,
      ['UpdatePlayerStats',users[loser].playerID,byte(games[gameid].gametype),loserFamePenalty,-1,-1,-1]);
   end else
   if arenaMode and (users[winner].playerID>0) then
    AddTask(winner,0,['UPDATEPLAYER',users[winner].playerID,
     Format('insight=%d, needInsight=%d',[users[winner].heroicPoints,users[winner].needHeroicPoints])]);

   if not arenaMode and
      (gametype in [dtClassic,dtDraft]) and
      (GuildHasPerk(users[winner].guild,9)) then
     GrantGuildGold(users[winner].playerID,users[winner].guild,1,'Wealth');

   if not arenaMode and
      (gametype in [dtClassic,dtDraft]) and
      (GuildHasPerk(users[winner].guild,14)) then
     GrantGuildExp(users[winner].playerID,users[winner].guild,3,'Battle Spirit');

   if (users[winner].guild<>'') and (games[gameID].gameclass=dcRated) then
    AddGuildWin(users[winner].playerID,users[winner].guild);

   except
    on e:exception do LogMsg('Error in AddGameRewards: '+ExceptionMsg(e),logWarn);
   end;
  end;

// procedure SetSteamMission(steamID:int64;

 // Вызывать только из gSect!
 // Уведомляет игрока о том, что миссия выполнена, сохраняет новое состояние миссий
 procedure MissionDone(userID:integer;mission:integer);
  begin
   with users[userid] do try
    if botlevel>0 then exit;
    ASSERT((mission>0) and (mission<=high(missions)),'Invalid mission number');
    if missions[mission]<0 then begin
     LogMsg('Player %s already completed mission %d',[name,mission]);
     exit;
    end;
    LogMsg('Player %s completed mission %d',[name,mission],logNormal);
    missions[mission]:=-1;
    AddTask(0,0,['UPDATEPLAYER',playerID,'missions="'+MissionsToStr+'"']);
    PostUserMsg(userID,FormatMessage([71,mission]));
    case mission of
     1:Grant(userID,ppGems,25,'Mission-1');
     2:GrantPremium(userID,2,'Mission-2');
     3:Grant(userID,ppGems,30,'Mission-3');
     4:Grant(userID,ppGems,40,'Mission-4');
     5:Grant(userID,ppGold,25,'Mission-5');
     6:Grant(userID,ppGold,50,'Mission-6');
     7:Grant(userID,ppGems,25,'Mission-7');
     8:Grant(userID,ppGems,30,'Mission-8');
     9:Grant(userID,ppGems,20,'Mission-9');
     21:Grant(userID,ppGold,10,'Mission-21');
     22:Grant(userID,ppGems,10,'Mission-22');
     23:Grant(userID,ppGems,25,'Mission-23');
     24:Grant(userID,ppGems,75,'Mission-24');
     25:Grant(userID,ppGems,30,'Mission-25');
     26:Grant(userID,ppGems,20,'Mission-26');
     27:Grant(userID,ppGems,20,'Mission-27');
    end;
   except
    on e:exception do
      LogMsg('Error in CompleteMission for '+name+' '+IntToStr(mission)+':'+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure UpdateMissionProgress(userID,mission,amount:integer);
  begin
   with users[userid] do try
    if botlevel>0 then exit;
    ASSERT((mission>0) and (mission<=high(missions)),'Invalid mission number'); 
    LogMsg('Player %s has progress in mission %d: %d+=%d',
      [name,mission,missions[mission],amount],logInfo);
    inc(missions[mission],amount);
    if missions[mission]>=MissionsInfo[mission].MaxProgress then
     MissionDone(userID,mission)
    else
     AddTask(0,0,['UPDATEPLAYER',playerID,'missions="'+MissionsToStr+'"']);

    if steamID<>0 then
     AddTask(userID,0,['SETSTEAMACHIEVEMENTS']);
   except
    on e:exception do
      LogMsg('Error in MissionProgress for '+name+' '+IntToStr(mission)+':'+ExceptionMsg(e),logWarn);
   end;
  end;

 // Вызывать только из gSect!
 // Проверяет не выполнил ли игрок какие-либо миссии, если выполнил - сообщает ему об этом
 procedure CheckForDuelMissions(userID:integer;isWinner,isQuest:boolean;var duelSave:TDuelSave);
  var
   winnerDeck:TDeck;
   i:integer;
   hasCreatures,hasSpells:boolean;
  begin
   with users[userID] do try
    ASSERT(gSect.lockCount>0,'not in gSect!');
    with duelsave.saveDuel do begin
      // Get winner deck properties
      hasCreatures:=false; hasSpells:=false;
      if winner>0 then begin
       winnerDeck:=duelSave.SavePlayersInfo[winner].Deck;
       for i:=1 to high(winnerDeck.cards) do
        if winnerDeck.cards[i]<>0 then
         if cardInfo[winnerDeck.cards[i]].life=0 then hasSpells:=true
          else hasCreatures:=true;
      end;

      // 1. Победить, нанеся врагу более 20 урона последним ударом. 25 кристаллов.
      if IsWinner and (winner>0) then
       if Players[winner].lastDamageAmount>20 then MissionDone(userID,1);

      // 7. Добить врага атакой овцы. 25 кристаллов
      if IsWinner and (winner>0) then
       if Players[winner].lastDamageSource=-2 then MissionDone(userID,7);

      // 22  Толстяк. Победить, имея 50 жизни либо больше.
      if IsWinner and isQuest and (winner>0) then
       if Players[winner].life>=50 then MissionDone(userID,22);

      // 25 Dragon Master. Повелитель драконов. Позвать за бой трех драконов и победить
      if IsWinner and isQuest and (winner>0) then
       if Players[winner].dragonssummoned>=3 then MissionDone(userID,25);

      // 26 Вождь орды. Победить, имея на поле 6 существ
      if IsWinner and isQuest and (winner>0) then
       if Players[winner].hasCreatures>=6 then MissionDone(userID,26);

      // 27 Победить, не имея существ на поле боя
      if IsWinner and isQuest and (winner>0) then
       if Players[winner].hasCreatures=0 then MissionDone(userID,27);

      // 8. Охотник на вампиров. Уничтожить 100 вражеских вампиров.
      if (missions[8]>=0) and isWinner and (winner>0) and
         (Players[winner].vampireskilled>0) then
           UpdateMissionProgress(userID,8,Players[winner].vampireskilled);

      // 9. Союзник эльфов. Призвать 100 эльфов.
      if (missions[9]>=0) and isWinner and (winner>0) and
         (Players[winner].elvessummoned>0) then
           UpdateMissionProgress(userID,9,Players[winner].elvessummoned);
    end;
    // Миссии, не связанные с дуэлью
    // -----------------------------
    // 21. Наёмник. Выполнить 5 квестов.
    if isWinner and isQuest and (missions[21]>=0) then UpdateMissionProgress(userID,21,1);

    // 23. Призыватель. Победить колодой без заклинаний. 25 кристаллов
    if isWinner and isQuest and
      (missions[23]=0) and (hasSpells=false) then MissionDone(userID,23);

    // 24. Заклинатель. Победить колодой без существ. 75 кристаллов.
    if isWinner and isQuest and
      (missions[24]=0) and (hasCreatures=false) then MissionDone(userID,24);

   except
    on e:exception do LogMsg('Error in CheckForMissions: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure PostMissionsProgress(userID:integer;sendCompletedMissions:boolean);
  var
   i:integer;
   missionSet:UTF8String;
  begin
   with users[userID] do begin
    // Выполненные миссии
    if sendCompletedMissions then begin
     missionSet:='70';
     for i:=1 to high(missions) do
      if missions[i]<0 then missionSet:=missionSet+'~'+IntToStr(i);
     PostUserMsg(userID,missionSet);
    end;
    // Миссии с прогрессом
    missionSet:='72';
    for i:=1 to high(missions) do
     if MissionsInfo[i].MaxProgress>0 then
      missionSet:=missionSet+'~'+IntToStr(i)+'~'+IntToStr(missions[i]);
    PostUserMsg(userID,missionSet);
   end;
  end;

 // Вызывать только из gSect!
 // Составляет текущую турнирную таблицу и высылает её участникам драфта
 procedure PostDraftInfo(draftID:integer);
  var
   i,j:integer;
   msg:UTF8String;
   pos:array[1..4,1..2] of integer;
   plr:array[1..4] of PDraftPlayer;
  begin
   ASSERT(gSect.lockCount>0,'PostDraftInfo error: not in gSect!');
   if IsValidDraftID(draftID) then
    with drafts[draftID] do begin
      for i:=1 to 4 do begin
       pos[i,1]:=i;
       pos[i,2]:=draftInfo.players[i].wins*1000000-draftInfo.players[i].time;
      end;
      for i:=1 to 3 do
       for j:=i+1 to 4 do
        if pos[j,2]>pos[i,2] then
         Swap(pos[i],pos[j],sizeof(pos[i]));

      for i:=1 to 4 do begin
       draftInfo.Players[pos[i,1]].place:=i;
       plr[i]:=@draftInfo.players[pos[i,1]];
      end;
      msg:=FormatMessage([52,
        plr[1].name,plr[1].wins,plr[1].time,
        plr[2].name,plr[2].wins,plr[2].time,
        plr[3].name,plr[3].wins,plr[3].time,
        plr[4].name,plr[4].wins,plr[4].time]);
      for i:=1 to 4 do
       PostUserMsg(players[i],msg);
    end;
  end;

 procedure CaravanBattleFinished(winner,loser,cType:integer);
  var
   g,i,j,res,amount,exp:integer;
  begin
     for g:=1 to high(guilds) do
      if guilds[g].caravans[cType].running then begin
       LogMsg('Caravan battle finished!',logDebug);
       for i:=1 to 8 do
        with guilds[g].caravans[cType] do begin
         if battles[i]<>1 then continue;
         res:=0;
         if (attackers[i]=users[winner].name) and (defenders[i]=users[loser].name) then res:=3;
         if (attackers[i]=users[loser].name) and (defenders[i]=users[winner].name) then res:=2;
         if res=0 then continue;
         battles[i]:=res;
         needBattleIn[i]:=Now;
         PostGuildMsg(g,FormatBattleUpdate(i),'BattleFinished');
         // Занять очередной слот
         RequestActiveSlotIn(15);
         // Награда за успешный грабёж
         if res=3 then begin
          if cType=1 then amount:=8
           else amount:=6;
          if users[winner].guild='' then begin
           Grant(winner,ppGold,amount,'RobCaravan;'+guilds[g].name);
           PostServerMsg(winner,'You have robbed the caravan and got %1 gold from it!%%'+inttostr(amount),true);
           NotifyUserAboutGoldOrGems(winner);
          end else begin
           // всё добро - в гильдию!
           exp:=GrantGuildExp(users[winner].playerID,users[winner].guild,amount,'RobCaravan;'+guilds[g].name);
           if GuildHasPerk(users[winner].guild,7) then amount:=round(amount*1.5); // Perk-7: ferocity
           GrantGuildGold(users[winner].playerID,users[winner].guild,amount,'RobCaravan;'+guilds[g].name);
           PostServerMsg(winner,'You have robbed the caravan! Your guild received %1 gold and %2 experience.%%'+
             inttostr(amount)+'%%'+inttostr(exp),true);
          end;
          if (users[winner].missions[5]>=0) then
             UpdateMissionProgress(winner,5,1);
         end;
         // Миссия защитник каравана
         if (res=2) and (users[winner].missions[4]=0) then MissionDone(winner,4);
        end;
       LogMsg('Caravan updated, res='+inttostr(res)+': '+guilds[g].caravans[cType].FormatLog,logInfo); 
      end;
  end;


 // Завершает указанную игру (winner - userID победителя)
 // Если winner=0 - значит игра отменена: никто ничего не получает
 // Eсли winner<0 - значит победитель - тот, с кем играл -winner
 procedure GameOver(gameID:integer;winner:integer;comments:UTF8String='');
  var
   u1,u2,duration,i,winnerLevel,loserLevel,dt,winnerStarts,replayID,replayAccess:integer;
  procedure DraftDuelFinished(userID:integer;win:boolean);
   var
    i,draftID,time:integer;
   begin
    draftID:=users[userID].draftID;
    if IsValidDraftID(draftID) then
     with drafts[draftID] do begin
       if users[userid].botLevel<>0 then GetDraftPlayer(userid).played:=Now
         else GetDraftPlayer(userid).played:=Now+120*SECOND;
       //
       for i:=1 to 4 do
         if players[i]=userID then begin
           time:=users[userID].thinkTime;
           if users[userid].botLevel<>0 then time:=system.round(time*2.25);
           inc(draftInfo.Players[i].time,time);
         end;
     end;
   end;
  procedure ReportDraftDuelResults(winner,loser:integer);
   var
    i,draftID,uid:integer;
    msg:UTF8String;
    plr1,plr2:PDraftPlayer;
   begin
    draftID:=users[winner].draftID;
    if IsValidDraftID(draftID) then
     with drafts[draftID] do begin
       plr1:=GetDraftPlayer(winner);
       plr2:=GetDraftPlayer(loser);
       msg:='';
       if plr2.control>0 then // проигравший - бот
         msg:='%1 defeats %2`bot%%'+plr1.name+'`13%%'+plr2.name
       else
         msg:='%1 defeats %2`player%%'+plr1.name+'`13%%'+plr2.name;

       // Уведомить игроков драфта о результатах боя
       msg:=FormatMessage([53,msg]);
       for i:=1 to 4 do begin
        uid:=players[i];
        if IsValidUserID(uid) then PostUserMsg(uid,msg);
       end;

       draftInfo.ReportWinner(users[winner].name);
       PostDraftInfo(draftID);
     end;
   end;
  procedure UpdateQuestsIfNeeded(userID:integer);
   begin
    with users[userid] do
     if updateQuests then begin
       updateQuests:=false;
       DefineUserQuests(userID,true);
       if users[userid].updateQuests then users[userid].updateQuests:=false;
        AddTask(0,0,['UPDATEPLAYER',playerID,Format('campaignwins=%d, quests="%s", dailyUpd=Date(Now())',
         [campaignWins,GetQuests])]);
     end;
   end;
  begin
   try
   ASSERT(gSect.lockCount>0,'GameOver error: not in gSect!');

   games[gameid].finished:=true;
   replayID:=games[gameid].SaveReplay;
   u1:=games[gameID].user1;
   u2:=games[gameID].user2;

   if winner<0 then begin
    winner:=-winner;
    if u1=winner then winner:=u2
     else winner:=u1;
   end;
   // Сделать так, что всегда u1 побеждает u2, если вообще побеждает (winner>0)
   if u2=winner then begin
    u2:=u1; u1:=winner;
   end;

   // Кому можно смотреть реплеи
   replayAccess:=3; // по умолчанию - всем
   if (games[gameid].gametype in [dtCustom,dtCampaign]) then begin
    if (users[u1].playerID>0) and (users[u1].optionsflags and 32768>0) then dec(replayAccess,1); // winner
    if (users[u2].playerID>0) and (users[u2].optionsflags and 32768>0) then dec(replayAccess,2); // loser
   end; 

   // Важно убрать эти флаги ДО определения наград и следующих противников
   i:=0;
   if users[u1].flags and ufNotPlayed>0 then i:=u1;
   if i>0 then begin // remove "Not Played" flag
    users[i].flags:=users[i].flags xor ufNotPlayed;
    AddTask(0,0,['UPDATEPLAYER',users[i].playerID,'flags="'+MakeUserFlags(users[i].flags)+'"']);
   end;
   i:=0;
   if users[u2].flags and ufNotPlayed>0 then i:=u2;
   if i>0 then begin // remove "Not Played" flag
    users[i].flags:=users[i].flags xor ufNotPlayed;
    AddTask(0,0,['UPDATEPLAYER',users[i].playerID,'flags="'+MakeUserFlags(users[i].flags)+'"']);
   end;
   users[u1].lastDuelFinished:=Now;
   users[u2].lastDuelFinished:=Now;

   if winner>0 then begin
     // Normal duel
     LogMsg('GameOver (id='+inttostr(gameID)+', type='+inttostr(byte(games[gameid].gametype))+'): '+
       users[u1].name+' won '+users[u2].name+' ('+comments+')');
     with games[gameID] do begin
       if gameStarted>0 then duration:=round((Now-gameStarted)*86400)
        else duration:=0;
       winnerLevel:=users[u1].GetActualLevel(gametype);
       loserLevel:=users[u2].GetActualLevel(gametype);
       if users[u2].botLevel<>0 then LogMsg('Loser bot type %d, fame %d, level %d',
         [users[u2].botLevel,users[u2].GetFame(gametype),CalcLevel(users[u2].GetFame(gametype))],logDebug);
       dt:=byte(gametype)+10*byte(gameclass);
       if winner=u1 then winnerStarts:=firstPlayer else winnerStarts:=3-firstPlayer;
       AddTask(0,0,['DUELREC',users[u1].playerID,users[u2].playerID,
         dt,turns,duration,scenario,winnerStarts,winnerlevel,loserLevel,
         users[u1].playingDeck,users[u2].playingDeck,
         users[u1].GetFame(gametype),users[u2].GetFame(gametype),replayID,replayAccess]);
     end;
     // Награды
     if games[gameID].gametype in [dtClassic,dtCustom,dtDraft] then begin
       // Бой в лиге
       AddGameRewards(gameID,u1,u2); // Запускать даже для тренировок!!!
       UpdateQuestsIfNeeded(u1);
       UpdateQuestsIfNeeded(u2);
       // 2. Боевое неистовство. Выиграть 10 боёв в онлайн лиге. 2 дня премиума.
       if (games[gameID].gameclass=dcRated) and (users[u1].missions[2]>=0) then UpdateMissionProgress(u1,2,1);
       // корректировка виртуального уровня
     end else begin
       // бой в кампании
       GrantCampaignReward(gameID,u1,true);
       GrantCampaignReward(gameID,u2,false); // обновляет инфу о поражениях
     end;

     if games[gameID].gameclass=dcRated then begin
      // Миссии
      with games[gameid] do begin
       CheckForDuelMissions(u1,true,scenario>=40,DuelSave);
       CheckForDuelMissions(u2,false,scenario>=40,duelsave);
      end;
     end;

     if games[gameID].gameclass=dcCaravan then CaravanBattleFinished(u1,u2,byte(games[gameID].gametype));

     if games[gameID].gameclass<>dcTraining then begin
      PostMissionsProgress(u1,false);
      PostMissionsProgress(u2,false);
     end;

     // local record - добавлять строго ПОСЛЕ определения наград!
     with games[gameID] do
      AddLocalDuelRec(Now,users[u1].playerID,users[u2].playerID,dt,scenario,turns,firstPlayer);

   end else begin
    // Aborted game
    LogMsg('GameOver: both '+users[u1].name+' and '+users[u2].name+' lost. '+comments);
    with games[gameID] do
     AddTask(0,0,['EVENTLOG',0,'DUELABORT',Format('%d;%d',[users[u1].playerID,users[u2].playerID])]);
   end;

   if users[u1].draftID>0 then DraftDuelFinished(u1,true);
   if users[u2].draftID>0 then DraftDuelFinished(u2,false);
   if (users[u1].draftID or users[u2].draftID)>0 then ReportDraftDuelResults(u1,u2);

   // Disconnect
   users[u1].connected:=0;
   users[u2].connected:=0;
   users[u1].UpdateUserStatus;
   users[u2].UpdateUserStatus;
   NotifyAboutLookingForDraft(u1);
   NotifyAboutLookingForDraft(u2);

   // Delete bots (if any)
   if games[gameID].gametype in [dtCustom,dtClassic,dtCampaign] then begin
    if users[u1].botLevel>0 then DeleteUser(u1,'Bot');
    if users[u2].botLevel>0 then DeleteUser(u2,'Bot');
   end;

   // Delete game data
   // fillchar(games[gameID],sizeof(TGame),0); // bug!
   games[gameID].Clear;
   except
    on e:exception do LogMsg('Error in GameOver: '+ExceptionMsg(e),logError);
   end;
  end;

 // Может вызываться ТОЛЬКО из рабочих потоков!
 // В сетевом потоке, если нужно добавить что-то в лог - использовать AddTask
 procedure AddEventLog(playerID:integer;event,info:UTF8String);
  begin
   if DB=nil then begin
    raise EError.Create('Wrong thread!?');
   end;
   SQLstring(RawByteString(event));
   SQLstring(RawByteString(info));
   DB.Query('INSERT INTO eventlog_new (created,playerid,event,info) values(Now(),%d,"%s","%s")',
     [playerID,event,info]);
  end;

 procedure AddDuelRec(winnerID,loserID,dueltype,turns,duration,scenario,firstPlr,
   winnerLevel,loserLevel,winnerDeck,loserDeck,winnerFame,loserFame,replayID,replayAccess:UTF8String);
  begin
   DB.Query('INSERT INTO duels_new (date,winner,loser,dueltype,turns,duration,scenario,firstPlr,winnerLevel,loserLevel,winnerDeck,loserDeck,winnerFame,loserFame,replayID,replayAccess) '+
    'values(Now(),%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s","%s",%s,%s,%s,%s)',
    [winnerID,loserID,dueltype,turns,duration,scenario,firstPlr,
     winnerLevel,loserLevel,winnerDeck,loserDeck,winnerFame,loserFame,replayID,replayAccess]);
  end;

 // Вызывать внутри gSect!
 procedure ReplaceDraftPlayerWithBot(userID:integer);
  var
   i,draftID,botID:integer;
   msg:UTF8String;
  begin
   ASSERT(gSect.lockCount>0,'ReplaceDraftPlayerWithBot error: not in gSect!');
   ASSERT(users[userID].botlevel=0,'Trying to replace bot with bot');

   draftID:=users[userID].draftID;
   users[userID].draftID:=0; // ушедший игрок больше не в драфте 
   if IsValidDraftID(draftID) then
    with drafts[draftID] do begin
     if (stage=3) and (round=4) then exit; // Драфт закончен - уже не надо...
     LogMsg('Replacing '+users[userid].name+' with bot',logNormal);
     botID:=AddBot(3,dtDraft);
     users[botID].draftID:=draftID;
     for i:=1 to 4 do
      if players[i]=userID then begin
        LogMsg('Replacing draft %d player %d (%d -> %d)',[draftID,i,userID,botID],logInfo);
        msg:='Player %1 is replaced with bot%%'+users[userid].name+'`13';
        players[i]:=botID;
        draftInfo.Players[i].control:=3;
        draftInfo.Players[i].name:=draftInfo.Players[i].name+' (Bot)';
        draftInfo.Players[i].played:=Now;
        users[botID].name:=draftInfo.Players[i].name;
      end;
     for i:=1 to 4 do
      PostUserMsg(players[i],FormatMessage([53,msg])); 
    end;
  end;

 // Вызывается внутри gSect! userID должен быть валидным!
 procedure Logout(userID:integer;reason,clientinfo:UTF8String);
  var
   gameID:integer;
  begin
   try
   ASSERT(gSect.lockCount>0,'Logout error: not in gSect!');
   LogMsg('Logout for '+users[userid].name+' reason: '+reason,logNormal);
   with users[userid] do begin
    if connected>0 then begin
     gameID:=FindGame(userID);
     if gameID>0 then begin
      PostUserMsg(connected,FormatMessage([0,5]));
      games[gameID].SaveTurnData([0,5]);
      GameOver(gameID,connected,'User deleted');
     end;
    end;
    if (draftID>0) and (botlevel=0) then // Юзер (не бот) был в драфте - заменить его на бота!
      ReplaceDraftPlayerWithBot(userID);

    users[userid].UpdateUserStatus(psOffline);

    // Отменить все предложения тренировок: как сделанные этим игроком, так и сделанные ЭТОМУ игроку
    CancelAllProposals(userID);

    if (botLevel=0) and (playerID>0) then begin
     AddTask(0,0,['PLAYEROFFLINE',playerID,reason,room]);
     if clientinfo<>'' then
      AddTask(0,0,['CLIENTINFO',playerID,clientinfo]);
    end;
   end;
   except
    on e:Exception do LogMsg('Logout error: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure SendFriendlist(userID:integer);
  var
   msg:UTF8String;
   friends:AStringArr;
   online:array[0..100] of boolean;
   status:array[0..100] of TPlayerStatus;
   levels:array[0..100,0..3] of integer;
   i,n,u,plr:integer;
  begin
   friends:=users[userid].friendlist;
   n:=0;
   for i:=0 to high(friends) do begin
    if i>100 then break;
    online[i]:=false;
    status[i]:=psOffline;
    u:=FindUser(friends[i]);
    if u>0 then begin
     online[i]:=true;
     status[i]:=users[u].status;
     levels[i,0]:=users[u].GetActualLevel(dtNone);
     levels[i,1]:=users[u].GetActualLevel(dtcustom);
     levels[i,2]:=users[u].GetActualLevel(dtclassic);
     levels[i,3]:=users[u].GetActualLevel(dtdraft);
     inc(n);
    end else begin
     plr:=FindPlayerID(friends[i]);
     if plr>0 then begin
      levels[i,0]:=CalcLevel(allPlayers[plr].totalFame);
      levels[i,1]:=CalcLevel(allPlayers[plr].customFame);
      levels[i,2]:=CalcLevel(allPlayers[plr].classicFame);
      levels[i,3]:=CalcLevel(allPlayers[plr].draftFame);
     end else begin
      levels[i,0]:=1;
      levels[i,1]:=1;
      levels[i,2]:=1;
      levels[i,3]:=1;
     end;
    end;
   end;
   msg:='60~'+IntToStr(n);
   // Online friends
   for i:=0 to high(friends) do
    if online[i] then msg:=msg+'~'+
      FormatMessage([friends[i],'',integer(status[i]),levels[i,0],levels[i,1],levels[i,2],levels[i,3]]);
   // Offline friends
   for i:=0 to high(friends) do
    if not online[i] then msg:=msg+'~'+
      FormatMessage([friends[i],'',integer(status[i]),levels[i,0],levels[i,1],levels[i,2],levels[i,3]]);
   // Send friendlist
   PostUserMsg(userID,msg);
  end;

 procedure SendBlacklist(userID:integer);
  var
   msg:UTF8String;
   i:integer;
  begin
   with users[userid] do begin
    msg:='63';
    for i:=0 to high(blacklist) do
     msg:=msg+'~'+FormatMessage([blacklist[i]]);
   end;
   PostUserMsg(userID,msg);
  end;

 // Устанавливает игроку набор карт для покупки
 procedure DefineUserMarket(userID:integer);
  var
   i,j,k,cnt:integer;
   list:array[1..500] of integer;
  begin
   try
   with users[userid] do begin
    fillchar(marketCards,sizeof(marketCards),0);
    // Список доступных карт
    cnt:=0;
    for i:=1 to high(cardInfo) do begin
     if cardInfo[i].guild or cardInfo[i].special then continue;
     if (ownCards[i]>=MaxCardInstances) or (ownCards[i]<0) then continue;
     inc(cnt);
     list[cnt]:=i;
    end;
    // Перемешать его
    for i:=1 to cnt*5 do begin
     j:=1+random(cnt);
     k:=1+random(cnt);
     if j<>k then swap(list[j],list[k]);
    end;
    if cnt>5 then cnt:=5;
    for i:=1 to cnt do marketCards[i]:=list[i];
   end;
   except
    on e:exception do LogMsg('Error in DefineUserMarket: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure SendMarketCards(userID:integer);
  var
   i,cnt,card,cardStatus:integer;
   msg:UTF8String;
  begin
   try
   with users[userID] do begin
    cnt:=0;
    for i:=1 to 6 do
     if marketCards[i]<>0 then inc(cnt);
    msg:='18~'+IntToStr(cnt);
    for i:=1 to 6 do
     if marketCards[i]<>0 then begin
      cardStatus:=0;
      card:=marketCards[i];
      if card=0 then continue;
      if card<0 then begin
       cardStatus:=1; card:=abs(card);
      end;
      if (cardStatus=0) and (ownCards[card]>=MaxCardInstances) then cardStatus:=2; // ???
      msg:=msg+'~'+IntToStr(card)+'~'+IntToStr(cardStatus);
     end;
    // Еще нужно определить, может ли игрок получить награду за 1-ю победу в классике
    msg:=msg+'~'+IntToStr(byte(not CanGetRewardForClassic));
    PostUserMsg(userID,msg);
   end;
   except
    on e:exception do LogMsg('Error in SendMarketCards: '+ExceptionMsg(e),logWarn); 
   end;
  end;

 procedure SendServerTime(userid:integer);
  begin
   PostUserMsg(userid,FormatMessage([4,FloatToStrF(Now,ffFixed,13,8)]));
  end;

 function Login(tempUser:integer;login,clientInfo,sign:UTF8String):UTF8String;
  var
   userID,premiumSeconds,i,j,n,plrID,version,fl,gIdx:integer;
   sa,sa2,sa3,sa1:AStringArr;
   userInfo,clientlang,msg,enterMsg,st,url,data:UTF8String;
   sendConsts:boolean;
   firstDailyLogin:boolean;
   created,lastModified:TDateTime;
   dailyUpdate:integer; // номер дня, когда были обновлены квесты
   silentMode,paidMoney:boolean;
   silentUntil:TDateTime;
   clientSteamID:int64;
  begin
   result:=''; clientSteamID:=0; 
   silentMode:=false;
   LogMsg('Logging user: '+login+', '+clientInfo+', '+sign,logInfo);
   sa:=splitA(';',clientInfo);
   // Проверка версии и т.п.
   if length(sa)<8 then begin
    result:='ERROR: Invalid request';
    LogMsg('Wrong ClientInfo!',logImportant);
    UseIP(currentCon,30);
    exit;
   end;
   version:=StrToIntDef(sa[0],0);
   if version<cnsts.minVersion then begin
    result:='ERROR: Game version mismatch. Please update game.';
    LogMsg('Wrong version! '+inttostr(version),logImportant);
    UseIP(currentCon,20);
    exit;
   end;
   clientlang:=lowercase(sa[7]);

   if (sa[1]<>cardInfoHash) then begin
    // Здесь можно будет добавить автоапдейт на уровне констант
    LogMsg('Wrong cardInfohash, should be '+cardInfoHash,logImportant);
    sendConsts:=true;
   end else
    sendConsts:=false;

   for i:=0 to high(sa) do begin
    j:=pos(':ST=',sa[i]);
    if j>0 then begin
     st:=copy(sa[i],j+4,30);
     while (length(st)>0) and (not (st[length(st)] in ['0'..'9'])) do SetLength(st,length(st)-1);
     clientSteamID:=StrToInt64Def(st,0); 
    end;
   end; 

   // Check login
   sa:=DB.Query('SELECT id,name,pwd,email,avatar,gold,insight,needinsight,premium, '+
     'curDeck,customFame,customLevel, classicFame,classicLevel, draftFame,draftLevel, level,'+
     'astralPower,flags,cards, customWins,customLoses, classicWins,classicLoses, '+
     'draftWins,draftLoses,draftTourWins, HP,'+
     'speciality,quests,campaignWins, room,campaignLoses,gems,'+
     'optionsflags,friendlist,blacklist,lastvisit,missions,market,'+
     'modified,dailyUpd,created,onEnterMsg,guild,carPrior,tips,trainFame,botLevels'+
     ' FROM players WHERE email="'+SQLsafe(login)+'"');

   if db.rowCount=0 then begin
    result:='ERROR: Wrong login';
    LogMsg('Wrong login (email not found)! '+login,logImportant);
    UseIP(currentCon,30);
    exit;
   end;

   fl:=ParseUserFlags(sa[18]);
   if fl and ufBanned>0 then begin
     result:='ERROR: Account banned';
     LogMsg('Account banned! '+login,logImportant);
     UseIP(currentCon,30);
     exit;
   end;

   sa1:=db.Query('SELECT date,reason,action FROM users_ban WHERE Now()<date AND playerID='+sa[0]);
   for i:=0 to db.rowCount-1 do begin
     if sa1[i*3+2]='B' then begin
      LogMsg('Account %s banned until %s, reason: %s',[login,sa1[i*3+0],sa1[i*3+1]],logImportant);
      result:='{ACCESS DENIED!}^Account is banned until^ '+sa1[i*3+0]+'.~ ^Reason:^ '+sa1[i*3+1];
      UseIP(currentCon,30);
      exit;
     end;
     if sa1[i*3+2]='S' then begin
      silentMode:=true;
      silentUntil:=GetDateFromStr(sa1[i*3+0]);
     end;
   end;

   db.Query('SELECT id FROM payments WHERE userID='+sa[0]+' AND completed>=2');
   paidMoney:=db.rowCount>0;

   EnterCriticalSection(gSect);
   try
    // Check password
    if sign<>ShortMD5(inttostr(tempUser)+login+clientInfo+sa[2]) then begin
     result:='ERROR: Wrong password';
     LogMsg('Wrong password!',logImportant);
     UseIP(currentCon,30);
     exit;
    end;

    DeleteUser(tempUser);

    try
     userID:=FindUser(sa[1]);
     if userID>0 then DeleteUser(userID,'relogin','');
    except
     on e:exception do LogMsg('Failed to logout user '+sa[1],logWarn);
    end;

    userID:=CreateUser(false);
    with users[userID] do begin
     name:=sa[1];
     PwdHash:=sa[2];
     email:=sa[3];
     avatar:=StrToIntDef(sa[4],1);
     lang:=clientLang;
     playerID:=StrToIntDef(sa[0],0);
     gold:=StrToIntDef(sa[5],0);
     heroicPoints:=StrToIntDef(sa[6],0);
     needHeroicPoints:=StrToIntDef(sa[7],0);
     premium:=GetDateFromStr(sa[8],0);
//     if premium>0 then premium:=Now+1; // PREMIUM FOR ALL BETA TESTERS!
     curDeckID:=StrToIntDef(sa[9],0);
     customFame:=StrToIntDef(sa[10],0);
     customLevel:=StrToIntDef(sa[11],0);
     classicFame:=StrToIntDef(sa[12],0);
     classicLevel:=StrToIntDef(sa[13],0);
     draftFame:=StrToIntDef(sa[14],0);
     draftLevel:=StrToIntDef(sa[15],0);
     level:=StrToIntDef(sa[16],0);
     astralPower:=StrToIntDef(sa[17],0);
     flags:=ParseUserFlags(sa[18]);
     if silentmode then flags:=flags or ufSilent;
     ip:=GetConnAttr(currentCon,caIP);
     country:=GetConnAttr(currentCon,caCountry);
     StrToCardSet(sa[19],ownCards);
     customWins:=StrToIntDef(sa[20],0);
     customLoses:=StrToIntDef(sa[21],0);
     classicWins:=StrToIntDef(sa[22],0);
     classicLoses:=StrToIntDef(sa[23],0);
     draftWins:=StrToIntDef(sa[24],0);
     draftLoses:=StrToIntDef(sa[25],0);
     draftTourWins:=StrToIntDef(sa[26],0);
     initialHP:=StrToIntDef(sa[27],25);
     speciality:=StrToIntDef(sa[28],0);
     SetQuests(sa[29]);
     campaignWins:=StrToIntDef(sa[30],0);
     room:=StrToIntDef(sa[31],1);
     SetCampaignLoses(sa[32]);
     gems:=StrToIntDef(sa[33],0);
     optionsflags:=StrToIntDef(sa[34],0);
     if paidMoney then optionsflags:=optionsflags or $10000;
     friendlist:=SplitA(',',sa[35]);
     blacklist:=SplitA(',',sa[36]);
     lastLogin:=GetDateFromStr(sa[37],0);
     MissionsFromStr(sa[38]);
     ImportMarket(sa[39]);
     lastModified:=GetDateFromStr(sa[40],0);
     dailyUpdate:=Trunc(GetDateFromStr(sa[41],0));
     created:=GetDateFromStr(sa[42],0);
     enterMsg:=sa[43];
     guild:=sa[44];
     caravanPriority:=StrToIntDef(sa[45],0);
     LoadTips(sa[46]);
     trainFame:=StrToIntDef(sa[47],0);
     maxBotLevel:=StrToIntDef(sa[48],0);
     curBotLevel:=max2(1,maxBotLevel mod 10);
     maxBotLevel:=max2(1,maxBotLevel div 10);
     steamID:=clientSteamID;
     gIdx:=-1;
     if guild<>'' then
      gIdx:=FindGuild(guild,false);

     result:=inttostr(userID);
     LogMsg('User logged: '+users[userid].GetUserInfo);
     PostUserMsg(UserID,FormatMessage([10,cnsts.version,cnsts.sVersion,cardInfoHash]));

     if sendConsts then try
      PostUserMsg(userID,FormatMessage([9,gd_spe]));
     except
      on e:exception do LogMsg('Failed to send gd.spe');
     end;

     // Первый логин в сутках
     firstDailyLogin:=trunc(now)>trunc(lastLogin);

     // Сформировать инфу об игроке
     if premium=0 then premiumSeconds:=-1
      else
       if premium>Now then premiumSeconds:=round((premium-Now)*86400);

     userInfo:=FormatMessage([20,name,gold,premiumSeconds,heroicPoints,needHeroicPoints,astralPower,avatar,
       customFame,classicFame,draftFame,customLevel,classicLevel,draftLevel,level,getUserTitle,
       customWins,customLoses,classicWins,classicLoses,draftWins,draftLoses,room,gems,
       byte(flags and ufCanMakeDecks>0),byte(flags and ufCanReplaceCards>0),initialHP,
       byte(flags and ufHasRitualOfPower>0),byte(flags and ufHasManaStorm>0),
       inttostr(optionsFlags)+','+inttostr(maxBotLevel)+','+inttostr(curBotLevel),
       Format('%d,%d,%d,%d',[GetCostForMode(dtClassic,-1),GetCostForMode(dtClassic,1),
         GetCostForMode(dtDraft,-1),GetCostForMode(dtDraft,1)]),sa[19]]);

     plrID:=playerID;
    end;
   finally
    LeaveCriticalSection(gSect);
   end;
   // Гильдия есть, но она не в кэше
   if (gIdx=0) then begin
    gIdx:=AllocGuildIndex;
    guilds[gIdx].LoadFromDB(db,'name="'+SqlSafe(users[userID].guild)+'"');
   end;

   // Get decks
   sa2:=DB.Query('SELECT id,name,data FROM decks WHERE owner='+inttostr(plrID)+' ORDER BY id');
{   // Get duels
   sa3:=DB.Query('SELECT dueltype,scenario,date,winner,loser FROM duels '+
     'WHERE date>SubDate(Now(),3) AND (winner='+inttostr(plrID)+' OR loser='+inttostr(plrID)+')');}

   EnterCriticalSection(gSect);
   try
    with users[userID] do begin
     // Guild
     if gIdx>0 then begin
      // Если у гильдии сейчас есть запущенный караван, то запросить активацию слота в этом караване
      n:=0;
      if guilds[gIdx].caravans[1].running then n:=1;
      if guilds[gIdx].caravans[2].running then n:=2;
      if n>0 then guilds[gIdx].caravans[n].RequestActiveSlotIn(0);
      SendGuildInfo(userID,true);
     end;

     // Store decks
     SetLength(decks,1+length(sa2) div 3);
     if length(sa2)>2 then
      for i:=1 to high(decks) do begin
       decks[i].deckID:=StrToIntDef(sa2[(i-1)*3],0);
       decks[i].name:=sa2[(i-1)*3+1];
       st:=sa2[(i-1)*3+2];
       StrToDeck(st,decks[i].cards);
       decks[i].cost:=CalculateDeckCost(decks[i].cards);
      end;

     if FindDeckByID(curDeckID)=0 then curDeckID:=0;
     userInfo:=userInfo+Format('~%d~%d',[high(decks),FindDeckByID(curDeckID)]);

     for i:=1 to high(decks) do begin
      st:=DeckToStr(decks[i].cards);
      userInfo:=userInfo+'~'+
        QuoteStr(decks[i].name,true,'_')+'~'+QuoteStr(st,true,'_');
     end;

     PostUserMsg(UserID,userInfo);

     if length(friendlist)>0 then SendFriendlist(userID);
     if length(blacklist)>0 then SendBlacklist(userID);

     UpdatePlayerData;      // User login - Update players[] with actual info
     UpdateUserStatus;      // Set status "online"
    end;
    // Выполненные миссии
    PostMissionsProgress(userID,true);
    if users[userID].steamID<>0 then
     AddTask(userID,0,['SETSTEAMACHIEVEMENTS']);

    // Отправить список противников в кампании/квестах
    DefineUserQuests(userID,trunc(now)>DailyUpdate);
    with users[userID] do
      AddTask(0,0,['UPDATEPLAYER',playerID,Format('quests="%s"',[GetQuests])]);

    // Если игрок был онлайн в полночь, то не давать новых карт
    // Маркет нужно обновить если:
    //  a) последняя модификация аккаунта была не сегодня - значит в полночь игрока не было и логина с тех пор тоже не было
    //  б) это вообще первый логин с момента создания аккаунта - можно проверить
    firstDailyLogin:=(trunc(now)>lastModified) or (users[userid].lastLogin=0);
    if firstDailyLogin then
     with users[userID] do begin
      LogMsg('First daily login for '+name,logInfo);
      DefineUserMarket(userID);
      i:=10;
      if GuildHasPerk(guild,19) then i:=i*3;
      inc(caravanPriority,i);
      AddTask(0,0,['UPDATEPLAYER',playerID,Format('market="%s", carPrior=%d',[ArrayToStr(marketCards),caravanPriority])]);
     end;
    SendMarketCards(userID);

    msg:='';
    if clientlang='en' then begin
     if (users[userID].lastLogin<altWelcomeForDate) and (altWelcomeEn<>'') then msg:=altWelcomeEn
      else msg:=welcomeEn;
    end;
    if clientlang='ru' then begin
     if (users[userID].lastLogin<altWelcomeForDate) and (altWelcomeRu<>'')then msg:=altWelcomeRu
      else msg:=welcomeRu;
    end;

    users[userID].SelectAndSendTip;

   finally
    LeaveCriticalSection(gSect);
   end;
   if enterMsg<>'' then begin
    // Сообщение, начинающееся с символа +, показывается дополнительно к основному, иначе - заменяет основное
    if enterMsg[1]='+' then delete(enterMsg,1,1)
     else msg:='';
   end; 

   if msg<>'' then PostServerMsg(userID,msg,true);
   if enterMsg<>'' then PostServerMsg(userID,enterMsg,true);

   if silentMode then PostServerMsg(userID,'Your account is in silent mode: you can''t use chat for '+
    IntToStr(round(0.5+silentUntil-Now()))+' days',true);

   if (serverState=ssRestarting) then
    PostServerMsg(userID,'^Planned restart in^ '+HowLong(restartTime));

   SendServerTime(userID); 

   with users[userID] do begin
    AddEventLog(playerID,'LOGIN',Format('%s;%s;%s',[IP,country,clientinfo]));
    DB.Query('UPDATE players SET online="Y",lastvisit=Now() WHERE id='+inttostr(playerID));
    data:='user='+UrlEncode(GetUserFullDump);
   end;

   url:='http://astralheroes.com/userlogged.cgi';
   LogMsg('CURL: '+copy(data,1,70),logDebug);
   LaunchProcess('curl.exe','-s -g --data "'+data+'" '+url);
  end;

 function CreateAccount(tempUser:integer;data:UTF8String):UTF8String;
  var
   i,avatar,speciality,playerID:integer;
   b:byte;
   sa:AStringArr;
   name,email,pwdhash:UTF8String;
   request:UTF8String;
   res,lang:UTF8String;
  begin
   result:='ERROR:';
   UseIP(currentCon,30); // создавать не слишком часто
   request:='';
   b:=47;
   for i:=0 to (length(data) div 2)-1 do begin
    request:=request+chr(HexToInt(data[i*2+1]+data[i*2+2]) xor b);
    inc(b,39);
   end;
{   for i:=1 to length(data) do begin
    data[i]:=AnsiChar(byte(data[i]) xor b);
//    inc(b);
   end;}
   sa:=SplitA(#9,request); // TAB
   if length(sa)<5 then raise EWarning.Create('CA: too few fields!');
   if length(sa)>=6 then begin
    lang:=lowercase(sa[5]);
    if (lang<>'en') and (lang<>'ru') and (lang<>'it') and
       (lang<>'by') and (lang<>'kr') and (lang<>'cn') then lang:='en';
   end else
    lang:='en';
   // 1. Check name
   name:=sa[0];
   email:=sa[1];
   pwdhash:=sa[2];
   avatar:=StrToIntDef(sa[3],0);
   speciality:=StrToIntDef(sa[4],1);
   if (speciality<low(startCardSets)) or (speciality>high(startCardSets)) then speciality:=1;
   res:=IsValidName(EncodeUTF8(name));
   if res<>'' then begin
    LogMsg('Invalid name: '+name+' - '+res,logWarn);
    result:=result+' invalid name: '+res;
    UseIP(currentCon,10);
    exit;
   end;
   sa:=DB.Query('SELECT id,flags FROM players WHERE name="%s"',[name]);
   if length(sa)=2 then begin
    result:=result+' ^Character name is in use^';
    UseIP(currentCon,10);
    exit;
   end;
   // 2. Check email
   res:=IsValidLogin(EncodeUTF8(email));
   if res<>'' then begin
    LogMsg('Invalid email: '+email+' - '+res,logWarn);
    result:=result+' Invalid email: '+res;
    UseIP(currentCon,10);
    exit;
   end;
   sa:=DB.Query('SELECT id,flags FROM players WHERE email="%s"',[email]);
   if length(sa)=2 then begin
    result:=result+' Email is in use';
    UseIP(currentCon,10);
    exit;
   end;
   // 3. Check PWDHASH
   for i:=1 to length(pwdhash) do
    if not (pwdhash[i] in ['0'..'9','A'..'F']) then begin
     LogMsg('Invalid PWDHASH: '+pwdhash,logWarn);
     exit;
    end;

   // Create!
   sa:=DB.Query('INSERT INTO players (name,email,pwd,avatar,created,cards,speciality,friendlist,blacklist,modified,curDeck)'+
      ' values("%s","%s","%s",%d,Now(),"%s",%d,"","",Now(),1)',
      [name,email,pwdhash,avatar,CardSetToStr(startCardSets[speciality]),speciality]);
   if length(sa)>0 then begin
    LogMsg('NewAcc error: '+sa[0],logWarn);
    exit;
   end else begin
    sa:=DB.Query('SELECT id FROM players WHERE email="%s"',[email]);
    if pos('ERROR',sa[0])>0 then begin
     LogMsg('CreateAccount DB Error: '+sa[0],logError);
     result:=result+' DB error';
    end else begin
     LogMsg('Account created: '+name+' / '+email,logImportant);
     playerID:=StrToIntDef(sa[0],0);
     AddEventLog(playerID,'NEWACC',Format('%s;%s;%s;%s',
       [name,email,GetConnAttr(currentCon,caIP),GetConnAttr(currentCon,caCountry)]));
     result:='OK';
     // Create default deck
     DB.Query('INSERT INTO decks (owner,name,data,cost) values(%d,"%s","%s",%d)',
       [playerID,'My Deck',startDecks[speciality],startDecksCost[speciality]]);
     //DB.Query('UPDATE players SET curDeck=1 WHERE id='+IntToStr(playerID));
    end;
    // Send account verification email
    LaunchProcess('curl','-s http://astralheroes.com/verifyemail.cgi?playerid='+inttostr(playerid)+'&lang='+lang);
   end;
  end;

 function CheckEmail(con:integer;email:UTF8String):UTF8String;
  var
   res:UTF8String;
   sa:AStringArr;
  begin
   res:=IsValidLogin(EncodeUTF8(email));
   if res<>'' then begin
    result:='ERROR: '+res; exit;
   end;
   sa:=DB.Query('SELECT id FROM players WHERE email="%s"',[email]);
   if length(sa)=0 then result:='OK'
    else result:='ERROR: email in use';
  end;

 function CheckName(con:integer;name:UTF8String):UTF8String;
  var
   res:UTF8String;
   sa:AStringArr;
  begin
   res:=IsValidName(EncodeUTF8(name));
   if res<>'' then begin
    result:='ERROR: '+res; exit;
   end;
   sa:=DB.Query('SELECT id FROM players WHERE name="%s"',[name]);
   if length(sa)=0 then result:='OK'
    else result:='ERROR: name in use';
  end;

 procedure SaveDeck(userID:integer;deckName,deck:UTF8String);
  var
   sa:AStringArr;
   cost,plrID:integer;
   cards:array[1..100] of smallint;
  procedure DeleteUserDeck;
   var
    idx,i:integer;
   begin
    EnterCriticalSection(gSect);
    try
     if IsValidUserID(userID) then
      with users[userid] do begin
       idx:=FindDeckByName(deckName);
       for i:=idx to high(decks)-1 do
        decks[i]:=decks[i+1];
      end;
    finally
     LeaveCriticalSection(gSect);
    end;
   end;
  procedure SaveUserDeck(deckID:integer=0);
   var
    idx:integer;
   begin
    EnterCriticalSection(gSect);
    try
     if IsValidUserID(userID) then
      with users[userid] do begin
       idx:=FindDeckByName(deckName);
       if idx=0 then begin
        idx:=length(decks);
        SetLength(decks,idx+1);
       end;
       decks[idx].name:=deckName;
       StrToDeck(deck,decks[idx].cards);
       decks[idx].cost:=CalculateDeckCost(decks[idx].cards);
       if deckID>0 then begin
        decks[idx].deckID:=deckID;
        curDeckID:=deckID;
       end;
      end;
    finally
     LeaveCriticalSection(gSect);
    end;
   end;
  begin
   DB.lastError:='';
   plrId:=GetPlayerID(userID);
   sa:=DB.Query('SELECT id,owner FROM decks WHERE name="%s" AND owner=%d',
     [deckName,plrID]);
   if DB.lastError<>'' then begin
    PostUserMsg(userID,FormatMessage([40,'DB error']));
    exit;
   end;
   StrToDeck(deck,cards);
   cost:=CalculateDeckCost(cards);
   if length(sa)=2 then begin // колода уже существует
    if deck<>'' then begin
     DB.Query('UPDATE decks SET data="'+SQLSafe(deck)+'",cost='+inttostr(cost)+' WHERE id='+sa[0]);
     SaveUserDeck;
    end else begin
     // Удалить колоду
     DB.Query('DELETE FROM decks WHERE id='+sa[0]);
     DeleteUserDeck;
    end;
   end else begin
    // Колоды нет - создать (проверить лимит)
    sa:=DB.Query('SELECT count(*) FROM decks WHERE owner='+inttostr(plrID));
    if StrToIntDef(sa[0],0)>=60 then begin
      PostUserMsg(userID,FormatMessage([40,'Too many decks!']));
      exit;
    end;
    if deck<>'' then begin
     DB.Query('INSERT INTO decks (owner,name,data,cost) values(%d,"%s","%s",%d)',
       [plrID,deckName,deck,cost]);
     SaveUserDeck(DB.InsertID);
    end;
   end;
   if DB.lastError<>'' then
    PostUserMsg(userID,FormatMessage([40,'DB error']))
   else
    PostUserMsg(userID,FormatMessage([40,'OK']));
  end;

 procedure GetDeck(userID:integer;deckName:UTF8String);
  var
   sa:AStringArr;
   plrID:integer;
  begin
   DB.lastError:='';
   plrId:=GetPlayerID(userID);
   sa:=DB.Query('SELECT id,owner,data FROM decks WHERE name="%s" AND owner=%d',
     [deckName,plrID]);
   if DB.lastError<>'' then begin
    PostUserMsg(userID,FormatMessage([41,'DB error']));
    exit;
   end;
   if length(sa)<>3 then begin
    PostUserMsg(userID,FormatMessage([41,'ERROR','Deck not found']));
    exit;
   end;
   PostUserMsg(userID,FormatMessage([41,deckName,sa[2]]));
  end;

 function HandleUserAsyncMsg(userID:integer;cmd:integer;v:AStringArr):UTF8String;
  begin
   result:='';
   case cmd of
    40:SaveDeck(userID,v[1],v[2]);
    41:GetDeck(userID,v[1]);
    81:SearchReplays(userID,v[1],v[2],v[3]);
   end;
  end;

 procedure ProcessDuelMsg(userID:integer;data:AStringArr);
  var
   target,gameID:integer;
   i,res,hash:integer;
   buf:array of integer;
  begin
   try
   ASSERT(gSect.lockCount>0,'ProcessDuelMsg error: not in gSect!');

   target:=users[userID].connected;
   if target=0 then begin
    if (length(data)>2) and (data[0]='0') and (data[1]='5') then exit;
    raise EWarning.Create('Duel packet from non-playing user: '+users[userid].name);
   end;
   gameID:=FindGame(userID);
   if gameID=0 then raise EWarning.Create('PDM: GameID not found for: '+users[userid].name);
   // Проверить пакет и переслать его сопернику по дуэли
   SetLength(buf,length(data));
   for i:=0 to length(buf)-1 do
     buf[i]:=StrToIntDef(data[i],0);
   // Ctrl+W ?
   if (buf[0]=0) and (buf[1]=666) and
      ((users[userID].flags and ufAdmin>0) or
       (pos('@astralheroes.com',lowercase(users[userID].email))>0)) and
      (users[target].botLevel>0) then begin
    LogMsg('AutoWin for '+users[userID].name,logNormal);
    GameOver(gameID,userID,'AutoWin');
    PostUserMsg(userID,FormatMessage([39,1]));
    exit;
   end;
   // Проверка хэша
   if high(buf)>=5 then begin
    with games[gameID].duelsave do
     hash:=SaveDuel.getPlayerHash(saveduel.curplayer);
    if (hash<>buf[5]) and (buf[1]>0) then
     LogMsg('WARN wrong duelhash for player %s: %d <> %d',[users[userid].name,hash,buf[5]],logImportant);
   end;
   games[gameid].SaveTurnData(buf);

   res:=CheckDuelMsg(userID,games[gameID].duelsave,games[gameid].turn,buf);
   games[gameID].duelsaveHash:=GetDuelHash(gameID);
   if (res<0) or (res=1) then begin
     PostServerMsg(userID,'^Cheating detected^');
     PostUserMsg(userID,FormatMessage([39,0]));
     PostUserMsg(userID,FormatMessage([3])); // Запрос лога
     PostUserMsg(target,FormatMessage([0,5]));
   end;
   case res of
     0:LogMsg('Turn data: '+logStr,logInfo,lgTurnData); // OK
     1:begin
       LogMsg('Cheating detected for '+users[userID].name+' info: '+logStr,logImportant,lgTurnData);
       GameOver(gameID,target,'Cheating!'); // cheating
     end;
     2:GameOver(gameID,userID,'code 2');
     3:GameOver(gameID,target,'code 3');
     4:begin
        LogMsg('Unallowed turn data from '+users[userID].name+': '+logStr,logWarn,lgTurnData); // Ignoring
        if users[userID].botLevel>0 then GameOver(gameID,target,'code 4')
       end;
    -1,-2:begin
       LogMsg('CheckDuelMsg returned '+inttostr(res)+' info: '+logStr,logWarn,lgTurnData);
       GameOver(gameID,target,'Cheating '+inttostr(res));
    end
   end;
   // Forward or not?
   if (res<0) or (res in [1,4]) then exit;

   // Переслать данные хода сопернику
   if IsValidUserID(target,true) then // user may be already deleted
     PostUserMsg(target,join(data,'~'));

   if res<>0 then exit; // игра уже удалена
   
   if turnChanged then begin
     games[gameID].SetTurnTo(target);
     games[gameID].turnTimeout:=Now+75*SECOND+15*SECOND*games[gameID].numActions; // 5+15*кол-во действий противника
     games[gameID].numActions:=-1; // ждём подтверждения начала хода от оппонента
   end else
    if games[gameID].numActions>=0 then
     inc(games[gameID].numActions)
    else
     games[gameID].numActions:=1;
   except
    on e:Exception do LogMsg('Error in ProcessDuelMsg: '+ExceptionMsg(e));
   end;
  end;

 procedure LaunchAI(userID,gameID:integer);
  var
   values:AStringArr;
   time:int64;
   lm:integer;
   ds:TDuelSave;
  begin
   try
    serverThreadNum:=workerID;
    with games[gameid] do
     if finished or (user1<=0) or (user2<=0) then exit;
    if (minLogMemLevel=0) then
     LogMsg('AI (WT='+inttostr(workerID)+') for '+users[userid].name,logDebug,lgAI);
    if IsValidUserID(userID,true) then
     users[userID].timeOut:=MyTickCount+1000*60*100; // + 100 min
    time:=myTickCount;
    games[gameID].duelSaveHash:=0;
    ds:=games[gameID].duelsave;
    values:=MakeAiDecisions(games[gameID].duelsave);
    games[gameID].duelSaveHash:=GetDuelHash(gameid);
    time:=MyTickCount-time;
    if time<200 then lm:=logDebug else lm:=logNormal;
    if time>1000 then lm:=logWarn;
    LogMsg('AI (WT='+inttostr(workerID)+') returned '+join(values,';')+' AItime: '+inttostr(time),lm,lgAI);
    if time>6000 then try
     SaveFile('Logs\DuelSave'+IntToStr(100+random(900)),@ds,sizeof(ds));
    except
    end;
   except
    on e:exception do begin
     LogMsg('Error in AI code: '+ExceptionMsg(e),logError,lgAI);
     values:=SplitA(';','0;5'); // surrender
    end;
   end;
   EnterCriticalSection(gSect);
   try
    if IsValidUserID(userID,true) then begin
     ProcessDuelMsg(userID,values);
     if users[userID]<>nil then
       users[userID].botThinking:=false;
    end;
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 procedure TestAI(filename:UTF8String);
  var
   values:AStringArr;
   time:int64;
   lm:integer;
   ds:TDuelSave;
  begin
   try
    serverThreadNum:=workerID;
    time:=myTickCount;
    ReadFile(filename,@ds,0,sizeof(ds));
    values:=MakeAiDecisions(ds);
    time:=MyTickCount-time;
    if time<200 then lm:=logDebug else lm:=logNormal;
    if time>1000 then lm:=logWarn;
    LogMsg('TestAI (WT='+inttostr(workerID)+') returned '+join(values,';')+' AItime: '+inttostr(time),lm,lgAI);
   except
    on e:exception do
     LogMsg('Error in TestAI code: '+ExceptionMsg(e),logError,lgAI);
   end;
  end;

 // Обновление числовых параметров игрока (в базе и в users), heroic в users НЕ МЕНЯЕТСЯ (только пишется в базу)
 procedure UpdatePlayerStats(userID,playerID:integer;gametype,deltaFame,heroic,needHeroic:integer;winner:integer);
  var
   i,g,m:integer;
   sa:AStringArr;
   plrName,gMode,gModeText,gName:UTF8String;
   oldVal,newVal,level,totalLevel,totalFame,CP:integer;
   query,msg,cmsg:UTF8String;
   fame:array[1..4] of integer;
   levelChanged:boolean;
  begin
   if playerID<=0 then exit; // Bot or fake player?
   case gametype of
    1:gMode:='custom';
    2:gMode:='classic';
    3:gMode:='draft';
    4:exit; // пока тут не поддерживается изменение чего-либо в кампании!
   end;
   sa:=db.Query('SELECT name,customFame,classicFame,draftFame,'+gMode+'Level,level,guild FROM players WHERE id='+IntToStr(playerID));
   ASSERT(db.lastError='');
   plrName:=sa[0];
   fame[1]:=StrToInt(sa[1]);
   fame[2]:=StrToInt(sa[2]);
   fame[3]:=StrToInt(sa[3]);
   gName:=sa[6];

   // Здесь дублирование кода -> править также в TUser.GetNewUserInfo
   CP:=-1;
   EnterCriticalSection(gSect);
   try
    if IsValidUserID(userID,true) then begin
     users[userID].customFame:=fame[1];
     users[userID].classicFame:=fame[2];
     users[userID].draftFame:=fame[3];
     CP:=users[userID].caravanPriority;
    end;
   finally
    LeaveCriticalSection(gSect);
   end;
   levelChanged:=false;
   level:=StrToInt(sa[4]);
   totalLevel:=StrToInt(sa[5]);
   oldVal:=fame[gametype];
   newVal:=Sat(oldVal+deltaFame,0,999999);
   query:=gMode+'Fame='+IntToStr(newVal);
   msg:=Format('Updating %s, mode %s: fame+=%d (%d->%d)',[plrName,gMode,deltaFame,oldVal,newVal]);
   case gametype of
    1:gModeText:='custom decks mode.';
    2:gModeText:='random decks mode.';
    3:gModeText:='draft tournaments.';
    else gModeText:='';
   end;
   // New level?
   if CalcLevel(newVal)>level then begin
    levelChanged:=true;
    level:=CalcLevel(newVal);
    query:=query+','+gMode+'Level='+IntToStr(level);
    msg:=msg+' Level='+inttostr(level);
    AddEventLog(playerID,'NEWLEVEL',gmode+'='+inttostr(level));
    case random(4) of
     0:cmsg:='^Well done!^';
     1:cmsg:='^Good job!^';
     2:cmsg:='^Excellent!^';
     3:cmsg:='^Splendid!^';
     else cmsg:='';
    end;
    PostServerMsg(userID,'[#]'+cmsg+' You''ve reached level %1 in '+gModeText+'%%'+inttostr(level),true);
    // Здесь же проверить миссию про уровень
    // Миссии про левел
    gSect.Enter;
    try
     try
      for i:=1 to high(MissionLevels) do
       if level=missionLevels[i] then begin
        LogMsg('New mission level reached for %s in type %d: %d ',
         [users[userID].name,byte(gametype),level]);
        PostUserMsg(userID,FormatMessage([71,40+byte(gametype)]));
        //Grant(winner,ppGems,20,'Level-'+inttostr(newLevel));
        Grant(userID,ppAP,5,'Level-'+inttostr(level)+' in '+inttostr(byte(gametype)));
       end;
     except
      on e:Exception do LogMsg('Error in level mission: '+ExceptionMsg(e));
     end;
    finally
     gSect.Leave;
    end;
   end;
   // New total level?
   fame[gametype]:=newVal;
   totalFame:=CalcPlayerFame(fame[2],fame[1],fame[3]);
   if CalcLevel(totalFame)>totalLevel then begin
    levelChanged:=true;
    totalLevel:=CalcLevel(totalFame);
    query:=query+',level='+inttostr(totalLevel);
    msg:=msg+' TotalLevel='+inttostr(totalLevel);
    AddEventLog(playerID,'NEWLEVEL','total='+inttostr(totalLevel));
   end;

   if heroic>=0 then begin
    query:=query+',insight='+inttostr(heroic);
    msg:=msg+' IP='+inttostr(heroic);
   end;
   if needHeroic>=0 then begin
    query:=query+',needInsight='+inttostr(needHeroic);
    msg:=msg+' needIP='+inttostr(needHeroic);
   end;

   if winner>0 then query:=query+','+gMode+'Wins='+gMode+'Wins+1';
   if winner<0 then query:=query+','+gMode+'Loses='+gMode+'Loses+1';

   if (winner>0) and (CP>0) then query:=query+', carPrior='+inttostr(CP);

   // Update user record
   EnterCriticalSection(gSect);
   try
    if IsValidUserID(userID,true) then
     if users[userID].playerID=playerID then begin
      case gametype of
       1:begin
          users[userID].customFame:=newVal;
          users[userID].customLevel:=level;
          if winner>0 then inc(users[userID].customWins);
          if winner<0 then inc(users[userID].customLoses);
         end;
       2:begin
          users[userID].classicFame:=newVal;
          users[userID].classicLevel:=level;
          if winner>0 then inc(users[userID].classicWins);
          if winner<0 then inc(users[userID].classicLoses);
         end;
       3:begin
          users[userID].draftFame:=newVal;
          users[userID].draftLevel:=level;
          if winner>0 then inc(users[userID].draftWins);
          if winner<0 then inc(users[userID].draftLoses);
         end;
      end;
      users[userID].level:=totalLevel;
      users[userID].UpdatePlayerData; // parameters changed - update allPlayers[]

      // Уведомить игрока об изменениях
      PostUserMsg(userID,FormatMessage([21,gametype,newVal,totalFame,level,totalLevel]));
     end;

    if levelChanged and (gName<>'') then try
     g:=FindGuild(gName);
     m:=-1;
     if g>0 then m:=guilds[g].FindMember(plrName);
     if m>=0 then
      PostGuildMsg(g,'122~7~'+guilds[g].FormatMemberInfo(m),'newlevel');
    except
     on e:exception do LogMsg('Error in gNewLevel: '+ExceptionMsg(e),logWarn);
    end;
   finally
    LeaveCriticalSection(gSect);
   end;

   // Post changes to DB
   LogMsg(msg,logNormal);
   db.Query('UPDATE players SET '+query+' WHERE id='+IntToStr(playerID));
   if db.lastError<>'' then
    LogMsg('Failed to update player '+plrName+': '+query,logWarn);
  end;

 procedure SetPlayerOffline(playerID:integer;reason:UTF8String;room:UTF8String);
  begin
   if playerID<=0 then exit; // Fake user
   DB.Query('UPDATE players SET online="N", lastvisit=Now(), room='+room+' WHERE id='+IntToStr(playerID));
   AddEventLog(playerID,'LOGOUT',reason);
  end;

 procedure ShutdownServer;
  begin
   LogMsg('Server shutdown',logImportant);
   if not SPARE_SERVER then
    DB.Query('UPDATE players SET online="N" WHERE online="Y"');
   AddEventLog(0,'SHUTDOWN','');
  end;

 procedure SaveClientInfo(playerID:integer;info:UTF8String);
  var
   instanceID,i:integer;
   sa:AStringArr;
  begin
   if playerID<=0 then exit; // Fake user
   instanceID:=0;
   i:=pos(';',info);
   if i>0 then begin
    instanceID:=StrToIntDef(copy(info,1,i-1),0);
    delete(info,1,i);
   end;
   sa:=DB.Query('SELECT id FROM clientinfo WHERE instanceID=%d AND playerID=%d AND date="%s"',
     [instanceID,playerID,FormatDateTime('yyyy-mm-dd',Now)]);
   if db.lastError<>'' then exit;
   if length(sa)=1 then begin
    DB.Query('UPDATE clientinfo SET info="%s" WHERE id=%s',[info,sa[0]]);
   end else
    DB.Query('INSERT INTO clientinfo (playerID,instanceID,date,info) values(%d,%d,Now(),"%s")',
     [playerID,instanceID,info]);
  end;

 // Производит дуэль между ботами, заносит результат в соответствующий драфт
 procedure ExecBotDuel(user1,user2:integer);
  var
   time:int64;
   i,draftID,duelN,winner:integer;
   plr:array[1..2] of TPlayerInfo;
   msg:UTF8String;
  begin
   duelN:=0;
   try
    EnterCriticalSection(gSect);
    try
     ASSERT(IsValidUserID(user1),'EBD: Invalid userID '+inttostr(user1));
     ASSERT(IsValidUserID(user2),'EBD: Invalid userID '+inttostr(user2));
     draftID:=users[user1].draftID;
     ASSERT(IsValidDraftID(draftID),'EBD invalid draftID for '+users[user1].name);
     ASSERT(draftID=users[user2].draftID,'EBD: '+users[user1].name+' not in the same draft');
     inc(botDuelCnt);
     duelN:=botDuelCnt;
     // Setup duel
     with users[user1] do begin
      plr[1].Name:=name;
      plr[1].control:=botLevel;
      plr[1].Deck:=drafts[draftID].GetDraftPlayer(user1).deck;
     end;
     with users[user2] do begin
      plr[2].Name:=name;
      plr[2].control:=botLevel;
      plr[2].Deck:=drafts[draftID].GetDraftPlayer(user2).deck;
     end;
    finally
     LeaveCriticalSection(gSect);
    end;
    LogMsg('Starting Bot duel %d between %s and %s in draft %d',
      [duelN,users[user1].name,users[user2].name,draftID]);

    time:=MyTickCount;
    serverThreadNum:=workerID;

    winner:=MakeAIDuel(3,plr[1],plr[2]);
    
    time:=MyTickCount-time;
    LogMsg('Bot duel %d: time - %d, winner - %s',[duelN,time,plr[winner].name],
     logInfo+2*byte(time>200));

    EnterCriticalSection(gSect);
    try
    if IsValidDraftID(draftID) then
     with drafts[draftID] do begin
      msg:='%1 defeats %2`bot%%'+plr[winner].name+'`13%%'+plr[3-winner].name;

      msg:=FormatMessage([53,msg]);
      for i:=1 to 4 do
       PostUserMsg(players[i],msg);

      draftInfo.ReportWinner(plr[winner].name);
      GetDraftPlayer(user1).played:=Now;
      inc(GetDraftPlayer(user1).time,plr[1].time);
      GetDraftPlayer(user2).played:=Now;
      inc(GetDraftPlayer(user2).time,plr[2].time);
      PostDraftInfo(draftID);
     end else
       LogMsg('Draft does not exists',logInfo);
    finally
     LeaveCriticalSection(gSect);
    end
   except
    on e:exception do LogMsg('Error in BotDuel '+inttostr(duelN)+': '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure SetAutoSearch(userID:integer;mode:TDuelType;enable:boolean);
  var
   cost,g,f,i,c:integer;
  begin
   if not (mode in [dtCustom..dtDraft]) then raise EWarning.Create('Incorrect mode');
   with users[userID] do begin
     // Если игрок в гильдии...
     if guild<>'' then begin
      g:=FindGuild(guild);
      // ...которая запустила караван...
      for c:=1 to 2 do
       if guilds[g].caravans[c].running then begin
        f:=0;
        // ...и в нём еще не все бои стартанули
        for i:=1 to 8 do
         if (guilds[g].caravans[c].defenders[i]<>'') then inc(f);
        if f<8 then begin
         PostUserMsg(userID,FormatMessage([32,ord(mode)]));
         ShowMessageToUser(userID,'Don''t waste your time on regular battles:~the guild''s caravan needs your protection!');
         exit;
        end;
       end;
     end;

     if enable then begin
       // нельзя стартовать автопоиск тому, кому выслано приглашение на грабёж каравана
       for g:=1 to high(guilds) do
        if guilds[g].name<>'' then
         for c:=1 to 2 do
          if guilds[g].caravans[c].running then
           for i:=1 to 8 do
            if (guilds[g].caravans[c].battles[i]=1) and
               (guilds[g].caravans[c].attackers[i]=users[userID].name) then begin
             PostUserMsg(userID,FormatMessage([32,ord(mode)]));
             LogMsg('Autosearch refused because of caravan proposal %s type %d slot %d',
              [guilds[g].name,c,i],logDebug);
             exit;
            end;

       cost:=users[userID].GetCostForMode(mode);
       if cost>gems then begin
        PostUserMsg(userID,FormatMessage([32,ord(mode)]));
        LogMsg('Not enough crystals to start autosearch for %s: %d<%d',[name,gems,cost],logNormal);
        ShowMessageToUser(userID,'^Not enough crystals:^ '+inttostr(gems)+' < '+inttostr(cost));
        exit;
       end;
       if (serverState=ssRestarting) and ((mode=dtDraft) or (Now>restartTime-10*MINUTE)) then begin
        LogMsg('Autosearch rejected for '+users[userid].name+' - server restarting',logInfo);
        PostUserMsg(userID,FormatMessage([32,ord(mode)]));
        ShowMessageToUser(userID,'^Sorry, the server restarts in^ '+HowLong(restartTime));
        exit;
       end;

       autoSearchStarted[mode]:=Now;
       if mode=dtDraft then begin
        NotifyAboutLookingForDraft;
        lastDraftAutosearch:=Now;
       end;
       // Подсказка
       users[userID].UseTipAndSelectAnother;
     end else begin
       // отмена автопоиска
       autoSearchStarted[mode]:=0;
       PostUserMsg(UserID,'32~'+inttostr(byte(mode))); // Confirmation
       if mode=dtDraft then NotifyAboutLookingForDraft;
     end;
    room:=2; // multiplayer room
   end;
  end;

 procedure SetClientLang(userID:integer;lang:UTF8String);
  begin
   if (lang='en') or (lang='ru') then begin
    users[userID].lang:=lang;
    AddTask(0,0,['UPDATEPLAYER',users[userid].playerid,'lang="'+lang+'"']);
   end;
  end;

 // Это лучше бы делать в асинхронном таске, но пока делаем тут в рассчёте, что логи всё-таки присылаются редко
 // если их присылать часто - то можно заDOS-ить сервер
 procedure SaveClientLog(userID:integer;packedLog:UTF8String);
  var
   logData:UTF8String;
   fname:UTF8String;
  begin
   try
    logData:=ZDecompressStr(packedLog);
    with users[userid] do begin
     fname:='Logs\User-'+SafeFileName(name)+'-'+IntToStr(lastlognum mod 10)+'.log';
     inc(lastlognum);
     LogMsg('Saving client log from '+name+' to '+fname);
    end;
    SaveFile(fname,@logData[1],length(logdata));
   except
    on e:exception do LogMsg('Failed to save client log: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure ExecChatCommand(userID:integer;cmd:UTF8String);
  var
   answer:UTF8String;
   i:integer;
   arg:AStringArr;
  begin
   answer:='';
   delete(cmd,1,1);
   if cmd='' then exit;
   arg:=SplitA(' ',cmd);
   cmd:=lowercase(arg[0]);
   if (cmd='h') or (cmd='help') then begin
    if length(arg)=1 then begin
     answer:=#13#10+
             '/list - list online players '#13#10+
//             '/play [name] - propose training to player'#13#10+
             '/blacklist - edit blacklist, type "/h blacklist" for details'#13#10+
             '/friendlist - edit friendlist, type "/h friendlist" for details'#13#10+
             '/read - set public chat mode, type "/h read" for details';
    end else begin
     if lowercase(arg[1])='read' then
      answer:=#13#10+
              '/read 0 - do not receive any public chat messages'#13#10+
              '/read 1 - see public messages from players of the same language (default)'#13#10+
              '/read 2 - see all public messages';
     if lowercase(arg[1])='blacklist' then
      answer:=#13#10+
              '/blacklist - display your blacklist'#13#10+
              '/blacklist [name] - blacklist the player'#13#10+
              '/blacklist delete [name] - remove the player from your blacklist';
     if lowercase(arg[1])='friendlist' then
      answer:=#13#10+
              '/friendlist - display your friendlist'#13#10+
              '/friendlist [name] - add player to your friendlist'#13#10+
              '/friendlist delete [name] - remove player from your friendlist';
    end;
   end;
   if cmd='read' then begin
    if (length(arg)<>2) or ((length(arg)=2) and not (StrToIntDef(arg[1],9) in [0..2])) then begin
     answer:='Invalid argument, type "/h read" for instructions';
    end;
    if arg[1]='0' then begin
     users[userid].chatmode:=0;
     answer:='Public chat disabled';
    end;
    if arg[1]='1' then begin
     users[userid].chatmode:=1;
     answer:='Public chat: read my language channel only';
    end;
    if arg[1]='2' then begin
     users[userid].chatmode:=2;
     answer:='Public chat: read all language channels';
    end;
   end;
   if cmd='blacklist' then begin
    if length(arg)=1 then begin
     answer:=join(users[userid].blacklist,', ');
     if answer='' then answer:='<empty>';
     answer:='Your blacklist: '+answer;
    end;
    if length(arg)=2 then begin // blacklist name
     EditBlacklist(userID,arg[1],true); exit;
    end;
    if (length(arg)=3) and
       ((lowercase(arg[1])='delete') or (lowercase(arg[1])='remove') or (arg[1]='-')) then begin // blacklist delete name
     EditBlacklist(userID,arg[2],false); exit;
    end;
   end;
   if cmd='friendlist' then begin
    if length(arg)=1 then begin
     answer:=join(users[userid].friendlist,', ');
     if answer='' then answer:='<empty>';
     answer:='Your friendlist: '+answer;
    end;
    if length(arg)=2 then begin // friendlist name
     EditFriendlist(userID,arg[1],true); exit;
    end;
    if (length(arg)=3) and
       ((lowercase(arg[1])='delete') or (lowercase(arg[1])='remove') or (arg[1]='-')) then begin // friendlist delete name
     EditFriendlist(userID,arg[2],false); exit;
    end;
   end;
   if (cmd='list') or (cmd='l') then begin
    for i:=1 to high(users) do
     if (users[i]<>nil) and (i<>userID) and
        (users[i].botLevel=0) and (users[i].connected=0) then begin
      if answer<>'' then answer:=answer+', ';
      answer:=answer+users[i].name;
      if length(answer)>150 then begin
       answer:=answer+'...'; break;
      end;
     end;
    if answer='' then answer:='No other players in chat...'
     else answer:='Players in chat: '+answer; 
   end;
   if answer='' then answer:='Unknown command! Type /h for help';
   PostUserMsg(userID,FormatMessage([22,'','Server',answer,0]));
  end;

 procedure PostChatMsg(fromUser:integer;receiver,text:UTF8String);
  var
   senderID,target,i,j,k,n,flags,opp,guild:integer;
   name,msg,mylang,myGuild:UTF8String;
   t:int64;
   toAll:boolean;
   wst,lst:WideString;
  begin
   if not IsValidUserID(fromUser,true) then raise EWarning.Create('PCM: Invalid sender user '+inttostr(fromUser));
   if users[fromUser].flags and ufSilent>0 then begin
    PostServerMsg(fromUser,'^You can''t use chat - your account is in silent mode.^',true);
    exit;
   end;
   // Chat filter
   wst:=DecodeUTF8(text);
   lst:=WideLowerCase(wst);
   for i:=0 to high(chatFilter) do begin
    n:=0; j:=0;
    repeat
     inc(n);
     j:=Pos(string(chatFilter[i]),string(lst));
     if (j>0) and ((j=1) or (lst[j-1] in [' ',#9..#13])) then
      for k:=1 to length(chatFilter[i])-1 do begin
       wst[j+k]:='*';
       lst[j+k]:='*';
      end;
    until (j<=0) or (n>5);
   end;
   text:=EncodeUTF8(wst);

   // Something special?
   if (length(text)>1) and (text[1] in ['/','\']) then begin
    ExecChatCommand(fromUser,text); exit;
   end;

   flags:=0;
   guild:=0;
   if users[fromUser].guild<>'' then guild:=1;
   senderID:=users[fromUser].playerID;
   name:=users[fromUser].name;
   // If player is in duel - assume this as a private message to the opponent, if receiver isn't specified
   if receiver='' then begin
    opp:=users[fromUser].connected;
    if opp>0 then receiver:=users[opp].name;
   end;
   with users[fromUser] do begin
    t:=MyTickCount;
    if t-lastChatMsgTime<1800 then begin
     inc(chatFlood);
     if chatFlood>2 then begin
      PostServerMsg(fromUser,'^Flood protection blocked your message^',true);
      exit;
     end;
    end else
     chatFlood:=0;
    lastChatMsgTime:=t;
   end;

   if receiver<>'' then begin
    myGuild:=users[fromUser].guild;
    if (receiver='#GUILD') and (myGuild<>'') then begin
     // Сообщение в гильдию
     LogMsg('[Chat] '+name+' to guild '+myGuild+': '+text,logNormal,lgChat);
     flags:=flags or 2;
     msg:=FormatMessage([22,'G',name,text,1]);
     for i:=1 to high(users) do
      if (i<>fromUser) and (users[i]<>nil) and (users[i].guild=myGuild) and
         (users[i].FindInBlacklist(name)<0) then PostUserMsg(i,msg);
    end else begin
     // Private message
     target:=FindUser(receiver);
     flags:=flags or 1;
     LogMsg('[Chat] '+name+' to '+receiver+': '+text,logNormal,lgChat);
     if target>0 then begin
       if users[target].FindInBlacklist(name)<0 then
         PostUserMsg(target,FormatMessage([22,'P',users[fromUser].name,text,guild]))
       else
         PostServerMsg(fromUser,'^You can''t send messages to^ '+receiver,true);
       if users[target].flags and ufSilent>0 then
         PostServerMsg(fromUser,receiver+' ^is in silent mode and can''t answer you.^',true);
     end else // Auto response
       PostServerMsg(fromUser,'User %1 isn''t online%%'+receiver+'`13',true);
    end;
   end else begin
    // Public chat
    LogMsg('[Chat] '+name+': '+text,logNormal,lgChat);
    toAll:=false;
    if lowercase(copy(text,1,3))='/a ' then begin
     toAll:=true; delete(text,1,3);
    end;
    if lowercase(copy(text,1,5))='/all ' then begin
     toAll:=true; delete(text,1,5);
    end;
    msg:=FormatMessage([22,'',name,text,guild]);
    mylang:=users[fromUser].lang;
    for i:=1 to high(users) do begin
      if (users[i]<>nil) and (users[i].chatMode=0) then continue;
      if (users[i]<>nil) and (toAll or (users[i].lang=mylang) or (users[i].chatMode=2)) and
         (users[i].FindInBlacklist(name)<0) then PostUserMsg(i,msg,users[i].connected>0);
    end;
   end;

   AddTask(0,0,['SAVECHATMSG','senderID,senderName,targetName,created,message,flags',
     Format('%d,"%s","%s",Now(),"%s",%d',[senderID,name,receiver,text,flags])]);
  end;

 // Драфт завершен - вычислить и раздать всем плюшки, очистить структуры
 // Вызывать внутри gSect!
 procedure DraftFinished(draftID:integer);
  var
   i,fame,uid:integer;
   res:UTF8String;
   plr:array[1..4] of integer;
  begin
   try
   if IsValidDraftID(draftID) then
    with drafts[draftID] do begin
     if (stage=3) and (round=4) then begin
      // Драфт закончился полностью!
      PostDraftInfo(draftID);
      // Format results
      for i:=1 to 4 do
       plr[draftInfo.Players[i].place]:=i;
      res:='';
      for i:=1 to 4 do
       res:=res+#13#10+Format('%d) %20s %d %d',
         [i,draftInfo.Players[plr[i]].Name,draftInfo.Players[plr[i]].wins,draftInfo.Players[plr[i]].time]);
      LogMsg('Draft '+inttostr(draftID)+' finished! '+res);
      // Людям - дать славу, ботов - удалить!
      for i:=1 to 4 do
       if (draftInfo.players[i].control=0) then begin
        case draftInfo.Players[i].place of
         1:fame:=15;
         2:fame:=6;
         3:fame:=3;
         4:fame:=0;
        end;
        if fame>0 then begin
         uid:=players[i];
         if draftInfo.Players[i].place=1 then begin
           // Draft winner
           PostServerMsg(uid,'Congratulations! You won this draft tournament and got %1 fame for that!%%'+inttostr(fame),true);
           AddTask(uid,0,['UpdatePlayerStats',users[uid].playerID,3,fame,-1,-1,0]);
           AddTask(uid,0,['IncrementPlayerTourWins',users[uid].playerID]);
           with users[uid] do begin
            inc(draftTourWins);
            if missions[6]=0 then MissionDone(uid,6);
           end;
         end;
        end;
       end else
        DeleteUser(players[i],'DraftBot');
     end else begin
      // Драфт закончился досрочно
      for i:=1 to 4 do begin
       uid:=players[i];
       if IsValidUserID(uid) then
        if users[uid].botLevel>0 then
         DeleteUser(uid,'DraftBot2');
      end;
     end;
     // Удалить всех игроков из драфта
     for i:=1 to 4 do begin
      uid:=players[i];
      if IsValidUserID(uid) then begin
       users[uid].draftID:=0;
       users[uid].UpdateUserStatus;
      end;
     end;
     fillchar(players,sizeof(players),0); // Delete
    end;
   except
    on e:exception do LogMsg('Error in DraftFinished: '+ExceptionMsg(e),logWarn);
   end;
  end;

 // В драфте случился таймаут - надо что-то сделать
 procedure DraftTimeout(draftID:integer);
  var
   i,j:integer;
  begin
   try
   if (minLogMemLevel=0) then
    LogMsg('Timeout in draft %d: %s',
     [draftID,FormatDateTime('hh:nn:ss.zzz',drafts[draftID].timeout)],logDebug);
   with drafts[draftID] do
    case stage of
     1:begin // Стадия раздачи карт (кто-то не выбрал...)
        for i:=1 to 4 do begin
         if (draftInfo.Players[i].control=0) and
             not draftInfo.Players[i].cardTaken then begin
          try
           draftInfo.Players[i].TakeCard(0); // взять случайную карту
          except
           on e:exception do
            LogMsg('ERROR in TakeCard(0): %s'#13#10' Cards: %s'#13#10'AvailCards: %s',
              [ExceptionMsg(e),DeckToText(draftInfo.Players[i].cards),DeckToText(draftInfo.Players[i].availablecards)],logWarn);
          end;
          LogMsg('Timeout: %s takes random card',[users[players[i]].name],logInfo);
          inc(draftInfo.Players[i].time,integer(system.round(86400*(Now-timeX))));
         end;
        end;
       end;

     2:begin // Составление колоды (кто-то не успел...)
        for i:=1 to 4 do
         with draftInfo.Players[i] do
         if (control=0) and not deckBuilt then begin
          if IsValidUserID(players[i],true) then
           LogMsg('Timeout: %s has no deck -> build default',[users[players[i]].name])
          else
           raise EWarning.Create('Invalid userID: '+IntToStr(players[i]));
          // Игрок не успел составить колоду - поможем ему в этом, возьмем просто первые 15 карт
          for j:=1 to 15 do deck.cards[j]:=cards[j];
          deckBuilt:=true;
          played:=Now+3*SECOND;
          inc(draftInfo.Players[i].time,integer(system.round(86400*(Now-timeX))));
         end;
       end;

     3:begin // Фаза боя (такого вообще-то быть не должно)
      timeout:=timeout+5*MINUTE;
     end;
    end;
   except
    on e:exception do LogMsg('DraftTimeout: '+ExceptionMsg(e),logWarn);
   end;
  end;

 const
// Время на выбор очередной карты
// draftTimes:array[1..20] of integer=(60,55,50,45,42,38,34,30,26,22,18,15,12,10, 8, 7,6,5,0,0);
//   draftTimes:array[1..22] of integer=(75,70,65,60,55,50,45,40,36,32,28,24,20,18,16,14,10,5,0,0,0,0);
   draftTimes:array[1..22] of integer=(75,72,68,64,60,55,50,45,40,36,32,28,24,20,18,16,14,12,10,5,0,0);

 // Если в драфте необходимо действие - сделать его
 // Вызывать только внутри gSect!
 procedure HandleDraft(draftID:integer);
  var
   j,k,time:integer;
   cards,availCards,msg:UTF8String;
  begin
   try
    with drafts[draftID] do
     if players[1]>0 then begin
       // Сперва обработаем ситуацию таймаута
       if (timeout>0.1) and
          (Now>timeout+0.5*SECOND) then DraftTimeout(draftID);

       if NoPlayersAlive then begin
        LogMsg('No more players in draft -> deleting',logNormal);
        DraftFinished(draftID);
        exit;
       end;

       if ReadyForNextCard then begin
         LogMsg('ReadyForNextCard '+inttostr(draftID),logDebug); 
         if stage=0 then begin
           stage:=1; // стадия выбора карт
           round:=0;
         end else begin
           try
             draftInfo.MakeAIChoices(system.round((Now-timeX)*86400));
           except
             on e:exception do LogMsg('Error in MakeAIChoices: '+ExceptionMsg(e),logWarn);
           end;
           inc(round);
         end;
         // Все карты уже разобраны?
         if round=20 then begin
           stage:=2; round:=0; // Стадия составления колоды
           time:=180;
           timeout:=Now+time*SECOND; // 3 минуты на составление колоды
           timeX:=now;
           for j:=1 to 4 do begin
             cards:=DeckToStr(draftInfo.Players[j].cards);
             PostUserMsg(players[j],FormatMessage([51,time,cards]));
             draftInfo.Players[j].deckBuilt:=false;
             if draftInfo.players[j].control<>0 then // bot?
              users[players[j]].timeOut:=MyTickCount+100*60*1000; // +100 min
           end;
           // Начальный состав участников
           PostDraftInfo(draftID);
           exit;
         end;
         // Послать всем юзерам карты для выбора
         time:=draftTimes[round+1];
         timeout:=Now+time*SECOND;
         timeX:=now;
         for j:=1 to 4 do begin
           cards:=DeckToStr(draftInfo.Players[j].cards);
           availCards:=DeckToStr(draftInfo.Players[j].availablecards);
           PostUserMsg(players[j],FormatMessage([50,time,availCards,cards]));
           draftInfo.Players[j].cardTaken:=false;
         end;

{         st:='';
         for j:=1 to 4 do
          st:=st+Format(#13#10' %s %d',[draftInfo.Players[j].Name,draftInfo.Players[j].time]);
         LogMsg('Draft player times: '+st,logDebug);}
         exit;
       end;
       
       if ReadyForNextRound then begin
         LogMsg('ReadyForNextRound '+inttostr(draftID),logDebug); 
         if stage=2 then begin
           for j:=1 to 4 do
             if draftInfo.Players[j].control>0 then begin
               if draftInfo.Players[j].control>5 then begin
                LogMsg('WARN! Draft bot: control='+inttostr(draftInfo.Players[j].control),logWarn);
                draftInfo.Players[j].control:=4;
               end;
               try
                draftInfo.Players[j].CreateAIDeck;
               except
                on e:Exception do LogMsg('Error in CreateAIDeck: '+e.message+
                  #13#10' Cards: '+DeckToText(draftInfo.Players[j].cards),logWarn);
               end;
               inc(draftInfo.Players[j].time,10+random(40));
             end;
           stage:=3; // Фаза боя
           round:=1; // 1-й раунд
           with draftInfo do
            for j:=1 to 4 do
             LogMsg('Draft cards for %s: %s',[Players[j].Name,DeckToText(players[j].deck.cards)],logInfo);
         end else // Main stage
           inc(round);
         // Запустить бои  
         if round<4 then begin
           LogMsg('Draft %d: next round - %d',[draftID,round],logNormal);
           msg:=FormatMessage([53,'-- Round %1 started --%%'+inttostr(round)]);
           for j:=1 to 4 do
             PostUserMsg(players[j],msg);
           timeout:=Now+30*MINUTE; // +30 min for a round
           draftInfo.PrepareNextRound;
           LogMsg('Draft %d opponents %d,%d,%d,%d',[draftID,
             draftInfo.opponents[round,1],
             draftInfo.opponents[round,2],
             draftInfo.opponents[round,3],
             draftInfo.opponents[round,4]],logInfo);
           for j:=1 to 4 do begin
             if draftInfo.players[j].control<>0 then
              inc(users[players[j]].timeOut,30*60*1000); // +30 min

             k:=draftInfo.opponents[round,j]; // С кем играет j-й игрок
             if k>j then begin
                if (users[players[j]].botLevel=0) or
                   (users[players[k]].botLevel=0) then StartDuel(players[j],players[k],dtDraft,dcRated)
                else AddTask(0,0,['BOTDUEL',players[j],players[k]]);
             end;
           end;
         end else
           DraftFinished(draftID);
       end;
     end;
   except
    on e:EWarning do LogMsg('ERROR in HandleDraft '+inttostr(draftID)+': '+ExceptionMsg(e),logWarn);
    on e:exception do LogMsg('ERROR in HandleDraft '+inttostr(draftID)+': '+ExceptionMsg(e),logError);
   end;
  end;

 // Юзер потянул карту
 procedure DraftCard(userID:integer;card:integer);
  var
   draftID:integer;
  begin
   draftID:=users[userID].draftID;
   ASSERT(IsValidDraftID(draftID),'Invalid draftID '+inttostr(draftID)+' for user '+users[userid].name);
   drafts[draftID].PlayerTookCard(userID,card);
   HandleDraft(draftID);
  end;

 procedure DraftDeckCreated(userID:integer;cards:UTF8String);
  var
   draftID,i:integer;
  begin
   draftID:=users[userID].draftID;
   ASSERT(IsValidDraftID(draftID),'Invalid draftID '+inttostr(draftID)+' for user '+users[userid].name);
   i:=drafts[draftID].PlayerMadeDeck(userID,cards);
   if i<>0 then begin
    LogMsg('DRAFT %d: %s has invalid card - %d',[draftID,users[userID].name,i],logWarn);
    ReplaceDraftPlayerWithBot(userID);
    PostUserMsg(userID,FormatMessage([54,'^Cheating: wrong card in deck^ - '+Simply(cardinfo[i].name)]));
   end;
   HandleDraft(draftID);
   PostDraftInfo(draftID);
  end;

 procedure LeaveDraft(userID:integer);
  var
   draftID:integer;
  begin
   draftID:=users[userID].draftID;
   ASSERT(IsValidDraftID(draftID),'Invalid draftID '+inttostr(draftID)+' for user '+users[userid].name);
   ReplaceDraftPlayerWithBot(userID);
  end;

 procedure UpdateTurnTimeout(userID:integer);
  var
   gameID:integer;
  begin
   gameID:=FindGame(userID);
   if gameID=0 then begin
    LogMsg('Error: Req#1 from %s while not in duel!',[users[userid].name],logInfo);
    exit;
   end;
   if games[gameID].numActions=-1 then begin
    games[gameID].numActions:=0;
    games[gameID].turnTimeout:=games[gameID].CalcTurnTimeout;
    PostUserMsg(userID,FormatMessage([1,FloatToStrF(games[gameID].turnTimeout,ffFixed,13,8)]));
   end else
    LogMsg('Incorrect Req#1 from '+users[userID].name,logNormal);
  end;

 procedure SetReadyForNextRound(userID:integer);
  var
   draftID:integer;
  begin
   draftID:=users[userID].draftID;
   if not IsValidDraftID(draftID) then exit;
   drafts[draftID].GetDraftPlayer(userID).played:=Now+5*SECOND;
  end;


 procedure EditFriendlist(userID:integer;pname:UTF8String;add:boolean);
  var
   n,l,u,i:integer;
   found:boolean;
   lname:UTF8String;
   plrInfo:TPlayerRec;
  begin
   pname:=SQLSafe(pname);
   with users[userID] do begin
    n:=FindFriend(pname);
    if add then begin
     if n>=0 then begin
      PostServerMsg(userID,'Player %1 is in your friendlist%%'+pname+'`13',true);
      exit;
     end;
     // А есть ли вообще такой игрок?
     found:=false;
     lname:=lowercase(pname);
     for i:=1 to high(allPlayers) do
      if lowercase(allPlayers[i].name)=lname then begin
       plrInfo:=allPlayers[i];
       found:=true; break;
      end;
     if not found then begin
      PostServerMsg(userID,'Player %1 not found%%'+pname+'`13',true);
      exit;
     end;
     LogMsg('Player %s adds %s to his friendlist',[name,pname]);
     l:=length(friendList);
     if l>=100 then begin
      PostServerMsg(userID,'Your Friends list is full',true); exit;
     end;
     SetLength(friendlist,l+1);
     friendlist[l]:=pname;
     // Уведомим игрока об этом
     u:=FindUser(pname);
     if u>0 then PostServerMsg(u,'%1 added you to their Friends list%%'+name+'`13',true);
     // Итог операции
     PostServerMsg(userID,'%1 was added to your Friends list%%'+pname+'`13',true);
     PostUserMsg(userID,FormatMessage([61,plrInfo.name,integer(plrInfo.status),plrInfo.totalLevel,
       plrInfo.customLevel,plrInfo.classicLevel,plrInfo.draftLevel]));
    end else begin
     // Delete from friendlist
     if n<0 then begin
      PostServerMsg(userID,'%1 is not in your Friends list%%'+pname+'`13',true);
      exit;
     end;
     LogMsg('Player %s removes %s from his friendlist',[name,pname]);
     l:=length(friendlist)-1;
     friendlist[n]:=friendlist[l];
     SetLength(friendlist,l);
     PostServerMsg(userID,'%1 was removed from your Friends list%%'+pname+'`13',true);
    end;
    AddTask(0,0,['UPDATEPLAYER',playerID,'friendlist="'+join(friendlist,',')+'"']);
   end;
  end;

 procedure EditBlacklist(userID:integer;pname:UTF8String;add:boolean);
  var
   n,l:integer;
  begin
   pname:=SQLSafe(pname);
   with users[userID] do begin
    n:=FindInBlacklist(pname);
    if add then begin
     if n>=0 then begin
      PostServerMsg(userID,'Player %1 is in your blacklist%%'+pname+'`13',true);
      exit;
     end;
     LogMsg('Player %s`13 adds %s to his blacklist',[name,pname]);
     l:=length(blacklist);
     if l>=100 then begin
      PostServerMsg(userID,'Your blacklist is full',true); exit;
     end;
     SetLength(blacklist,l+1);
     blacklist[l]:=pname;
     PostServerMsg(userID,'^You have blacklisted^ '+pname,true);
    end else begin
     // Delete from blacklist
     if n<0 then begin
      PostServerMsg(userID,'Player %1 is not in your blacklist%%'+pname+'`13',true);
      exit;
     end;
     LogMsg('Player %s removes %s from his blacklist',[name+'`13',pname]);
     l:=length(blacklist)-1;
     blacklist[n]:=blacklist[l];
     SetLength(blacklist,l);
     PostServerMsg(userID,'Player %1 was removed from your blacklist%%'+pname+'`13',true);
    end;
    AddTask(0,0,['UPDATEPLAYER',playerID,'blacklist="'+join(blacklist,',')+'"']);
   end;
  end;

 // mode - duelType (1..4)
 // enemy - индекс колоды (в кастоме), либо уровень (в рандоме), либо сценарий (в кампании)
 procedure TrainingWithBot(userID,enemy,mode:integer;deckName:UTF8String);
  var
   bot,scenario,duel,virtLevel,idx,botLev:integer;
   dt:TDuelType;
  begin
   try
    if (mode=2) and not users[userid].CanPlayTrainingWithBot then begin
     ShowMessageToUser(userID,'Sorry, you don''t have enough crystals to play this!');
     exit;
    end;

    LogMsg('Training with bot: %s %d %d %s',[users[userid].name,enemy,mode,deckname],logInfo);
    dt:=TDuelType(mode);
    with users[userID] do begin

     if mode in [1,4] then curDeckID:=FindDeckIDByName(deckName);
     bot:=0; scenario:=0;
     case mode of
      1:begin
         if enemy=0 then begin
          scenario:=38;
          // Выбор случайного бота подходящего уровня
          virtlevel:=Sat(CalcLevel(users[userid].trainFame),1,100);
          idx:=CustomBotDecksList.FindRandomCustomBot(virtlevel);
          ASSERT((idx>=low(CustomBotDecksList.BotDecks)) AND (idx<=high(CustomBotDecksList.BotDecks)),
            'Wrong bot deck index for fame '+inttostr(users[userid].customFame));
          botLev:=CustomBotDecksList.BotDecks[idx].control;
          LogMsg('Selected bot: %d, control=%d, level=%d player level %d',
            [idx,botlev,CustomBotDecksList.BotDecks[idx].startinglevel,virtlevel],logInfo);
          bot:=AddBot(botLev,dtCustom,idx,CustomBotDecksList.BotDecks[idx].startinglevel);
//          users[bot].name:='Shadow of '+users[bot].name;
         end else
          bot:=AddBot(CustomBotDecksList.BotDecks[enemy].control,dt,
            enemy,CustomBotDecksList.BotDecks[enemy].startinglevel);
        end;
      2:begin
         bot:=AddBot(enemy,dt);
         if enemy<>curBotLevel then begin
          curBotLevel:=enemy;
          AddTask(0,0,['UPDATEPLAYER',users[userID].playerID,'botLevels='+inttostr(maxBotLevel*10+curBotLevel)]);
         end;
         scenario:=39;
        end;
      4:begin
         scenario:=enemy;
         bot:=AddBot(1,dt,scenario);
        end;
     end;
     duel:=StartDuel(userID,bot,dt,dcTraining,scenario);
    end;
   except
    on e:Exception do LogMsg('Error in training with bot: '+ExceptionMsg(e));
   end;
  end;

 procedure ProposeTraining(userID:integer;mode:integer;plrname,deckName:UTF8String);
  var
   u:integer;
  begin
   if copy(plrName,1,1)='#' then begin
    delete(plrName,1,1);
    TrainingWithBot(userID,StrToIntDef(plrName,0),mode,deckName);
    exit;
   end;
   u:=FindUser(plrname);
   if (u<=0) or (u=userID) then begin // нет такого юзера?
    PostServerMsg(userID,'Player %1 isn''t online%%'+plrName+'`13',true);
    PostUserMsg(userID,FormatMessage([66,mode,plrname])); // canceled
    exit;
   end;
   with users[userID] do begin
    LogMsg('%s propose training to %s type %d',[name,plrname,mode],logInfo);
    // Предложение уже было сделано?
    if FindProposal(u,TDuelType(mode))>=0 then exit;
    // Игрок уже играет?
    if users[u].connected>0 then begin
     PostServerMsg(userID,'Player %1 is already playing%%'+plrname+'`13',true);
     exit;
    end;
    if users[u].FindInBlacklist(name)>=0 then begin
     PostServerMsg(userID,'You can''t play with %1 - you''re blacklisted%%'+plrname+'`13',true);
     exit;
    end;
    // Добавим предложение
    AddProposal(u,TDuelType(mode));
    PostuserMsg(u,FormatMessage([64,mode,name,getActualLevel(TDuelType(mode))]));
    if mode=1 then curDeckID:=FindDeckIDByName(deckName);
   end;
  end;

 // action: 0 - reject, 1 - accept, 2 - cancel
 procedure HandleProposal(userID:integer;mode:integer;plrname:UTF8String;action:integer;deckname:UTF8String);
  var
   i,u:integer;
  begin
   u:=0;
   if action<>3 then begin
    u:=FindUser(plrname);
    if u<=0 then begin
     PostServerMsg(userID,'Player %1 isn''t online%%'+plrName+'`13',true);
     exit;
    end;
   end;
   with users[userID] do begin
    case action of
     3:begin
      // Отмена ВСЕХ собственных предложений
      if (minLogMemLevel=0) then
        LogMsg(name+' cancel ALL proposals',logDebug);
      for i:=0 to high(proposals) do
       PostUserMsg(proposals[i].userID,FormatMessage([66,ord(proposals[i].gametype),name]));
      SetLength(proposals,0);
     end;
     2:begin
      // Отмена собственного предложения
      if (minLogMemLevel=0) then
        LogMsg('%s cancel proposal to %s type %d',[name,plrname,mode],logDebug);
      i:=FindProposal(u,TDuelType(mode));
      if i>=0 then begin
       PostUserMsg(u,FormatMessage([66,mode,name]));
       DeleteProposal(i);
      end;
     end;
     1:begin
      // Accept
      if (minLogMemLevel=0) then
       LogMsg('%s accept proposal from %s type %d',[name,plrname,mode],logDebug);
      i:=users[u].FindProposal(userID,TDuelType(mode));
      if i>=0 then begin
       users[u].DeleteProposal(i);
       PostServerMsg(userID,'Starting training with^ '+plrName+'...',true);
       PostServerMsg(u,'Starting training with^ '+name+'...',true);
       PostUserMsg(u,FormatMessage([67,mode,name]));
       if mode=1 then curDeckID:=FindDeckIDByName(deckName);
       StartDuel(userID,u,TDuelType(mode),dcTraining);
      end else
       PostServerMsg(userID,'Proposal from %1 isn''t available anymore%%'+plrname+'`13',true);
     end;
     0:begin
      // Reject
      if (minLogMemLevel=0) then
        LogMsg(Format('%s reject proposal from %s type %d',[name,plrname,mode]),logDebug);
      i:=users[u].FindProposal(userID,TDuelType(mode));
      if i>=0 then begin
       PostUserMsg(u,FormatMessage([65,mode,name]));
       users[u].DeleteProposal(i);
      end;
     end;
    end;
   end;
  end;

 procedure SearchPlayers(userID:integer;query:UTF8String;levelType,minLevel,maxLevel,showOffline:integer);
  var
   item:TPlayerRec;
   rate:single;
   items:array[0..127] of TPlayerRec;
   rates:array[0..127] of single;
   i,j,count:integer;
   list:UTF8String;

  function GetHeapItem:TPlayerRec;
   var
    p,p1,p2:integer;
   begin
    result:=items[1];
    p:=1;
    if count=0 then exit;
    dec(count);
    repeat
     p1:=p*2;
     if p1>count then break;
     p2:=p1+1;
     if (p2<=count) and (rates[p2]<rates[p1]) then p1:=p2;
     if rates[count+1]>rates[p1] then begin
      items[p]:=items[p1];
      rates[p]:=rates[p1];
      p:=p1;
     end else
      break;
    until false;
    items[p]:=items[count+1];
    rates[p]:=rates[count+1];
   end;

  procedure AddHeapItem(plr:TPlayerRec;rate:single);
   var
    i:integer;
   begin
    if count>=101 then GetHeapItem;
    inc(count);
    i:=count;
    while i>0 do
     if rates[i div 2]>rate then begin
      rates[i]:=rates[i div 2];
      items[i]:=items[i div 2];
      i:=i div 2;
     end else
      break;
    rates[i]:=rate;
    plr.customLevel:=CalcLevel(plr.customFame);
    plr.classicLevel:=CalcLevel(plr.classicFame);
    plr.draftLevel:=CalcLevel(plr.draftFame);
    plr.TotalLevel:=CalcLevel(plr.totalFame);
    items[i]:=plr;
   end;

  // Проверяет, соответствует ли запись фильтру, возвращает степень соответствия (0..1)
  function CheckFilter(var player:TPlayerRec):single;
   var
    p:integer;
   begin
    if query<>'' then begin
     result:=0;
     p:=pos(query,lowercase(player.name));
     if p>0 then result:=1/p+length(query)/length(player.name);
     p:=pos(query,lowercase(player.guild));
     if p>0 then result:=max2d(result,1/p+length(query)/length(player.guild));
    end else
     result:=player.totalLevel;
    case levelType of
     0:if (player.totalLevel<minLevel) or (player.totalLevel>maxLevel) then result:=0;
     1:if (player.customLevel<minLevel) or (player.customLevel>maxLevel) then result:=0;
     2:if (player.classicLevel<minLevel) or (player.classicLevel>maxLevel) then result:=0;
     3:if (player.draftLevel<minLevel) or (player.draftLevel>maxLevel) then result:=0;
    end;
   end;
  begin
   if maxLevel=0 then maxLevel:=100;
   query:=lowercase(query);
   rates[0]:=-10000;
   count:=0;

   // Fill players list
   if true then begin
    // Искать среди тех, кто в онлайне
    for i:=1 to high(users) do
     if (users[i]<>nil) and (users[i].botLevel=0) then begin
      item:=users[i].GetPlayerRec;
      rate:=CheckFilter(item);
      if rate>0 then
       AddHeapItem(item,rate);
     end;
   end;
   if (showOffline>0) and (count<100) then begin
    // Искать среди оффлайн
    if (minLogMemLevel=0) then
      LogMsg('Search from '+inttostr(high(allPlayers))+' query: '+query,logDebug);
    for i:=1 to high(allPlayers) do
     if (allPlayers[i].name<>'') and (allPlayers[i].status=psOffline) then begin
      rate:=CheckFilter(allPlayers[i]);
      if rate>0 then
       AddHeapItem(allPlayers[i],rate);
     end;
   end;
   if (minLogMemLevel=0) then
    LogMsg('Found players: '+inttostr(count),logDebug);

   // Send response
   if count>100 then GetHeapItem;
   list:='75~'+IntToStr(count);
   for i:=1 to count do begin
    item:=GetHeapItem;
    with item do
     list:=list+'~'+FormatMessage([name,guild,totalLevel,customLevel,classicLevel,draftLevel,integer(status)]);
   end;
   PostUserMsg(userID,list);
   users[userID].trackPlayersStatus:=true;
  end;

 procedure SearchReplays(userID:integer;name,startDate,endDate:UTF8String);
  var
   date,date1,date2:TDateTime;
   msg,bestName,addFilter,winnerName,loserName:UTF8String;
   i,plrID,j,id1,id2,cnt,g,dt,scenario:integer;
   rate,bestRate:single;
   w1,w:WideString;
   allowed:boolean;
   sa:AStringArr;
   q1,q2:UTF8String;
  begin
   try
    if (startDate<>'') and (startDate<>'0') then
     date1:=ParseFloat(startDate)
    else
     date1:=Now-10000;
    if (endDate<>'') and (endDate<>'0') then
     date2:=ParseFloat(endDate)
    else
     date2:=Now+1;
    // Search for player ID
    plrID:=0;
    addFilter:='';
    if name<>'' then begin
     bestRate:=0;
     w:=UpperCase(name);
     gSect.Enter;
     try
      for i:=1 to High(allPlayers) do
       if allPlayers[i].name<>'' then begin
        w1:=UpperCase(allPlayers[i].name);
        rate:=1/(1+GetWordsDistance(w1,w));
        if rate>bestRate then begin
         bestRate:=rate;
         bestName:=allPlayers[i].name;
         plrID:=i;
        end;
       end;
     finally
      gSect.Leave;
     end;
     LogMsg('Search replays: name='+name+' acc='+bestName,logInfo);
     // Нужно проверить есть ли право смотреть приватные реплеи этого игрока
     // если нет - искать только те, где доступ открыт
     allowed:=plrID=users[userID].playerID;
     if not allowed and (users[userid].guild<>'') then begin
      gSect.Enter;
      try
       // Доступ к приватным реплеям разрешен если
       //    - текущий игрок состоит в той же гильдии, что и name,
       //  И - текущий игрок имеет ранг выше рекрута
       g:=FindGuild(users[userid].guild);
       j:=0;
       if g>0 then with guilds[g] do
        for i:=0 to high(members) do begin
         if members[i].name=bestname then j:=j or 1; // Игрок name состоит в той же гильдии
         if (members[i].playerID=users[userid].playerID) and
            (members[i].rank>1) then j:=j or 2;
        end;
       if j=3 then begin
        allowed:=true;
        LogMsg('Private access allowed for '+users[userid].name,logDebug);
       end;
      finally
       gSect.Leave;
      end;
     end;
     if allowed then
      addFilter:=Format('AND ((winner=%d) or (loser=%d))',[plrID,plrID])
     else
      addFilter:=Format('AND (((winner=%d) AND (replayAccess & 1>0)) or ((loser=%d) AND (replayAccess & 2>0)))',[plrID,plrID]);
    end;
    msg:=FormatMessage([81,bestName]);

    q1:=Format('SELECT replayID,dueltype,winner,loser,date,turns,scenario FROM duels_new '+
      'WHERE date>"%s" AND date<"%s" AND replayID>0 %s',
      [FormatDateTime('YYYY-MM-DD HH:NN:SS',date1),
       FormatDateTime('YYYY-MM-DD HH:NN:SS',date2),addFilter]);

    q2:=Format('SELECT replayID,dueltype,winner,loser,date,turns,scenario FROM duels '+
      'WHERE date>"%s" AND date<"%s" AND replayID>0 %s LIMIT 150',
      [FormatDateTime('YYYY-MM-DD HH:NN:SS',date1),
       FormatDateTime('YYYY-MM-DD HH:NN:SS',date2),addFilter]);

    sa:=db.Query(Format('(%s) UNION (%s) ORDER BY replayID DESC',[q1,q2]));
    j:=0;
    gSect.Enter;
    try
    for i:=1 to min2(db.rowCount,100) do begin
     id1:=StrToInt(sa[j+2]);
     if id1>0 then winnerName:=allPlayers[id1].name
      else winnerName:=aiNames[-id1];
     id2:=StrToInt(sa[j+3]);
     if id2>0 then loserName:=allPlayers[id2].name
      else loserName:=aiNames[-id2];
     date:=GetDateFromStr(sa[j+4]);
     dt:=StrToInt(sa[j+1]);
     // Только что прошедшие драфты показывать не будем
     if (dt=3) and (date>Now-15*MINUTE) then continue;
     scenario:=StrToInt(sa[j+6]);
     if scenario>0 then begin
      if scenario in [38,39] then dt:=scenario
      else begin
       if id1<0 then winnerName:=CampaignMages[scenario].name;
       if id2<0 then loserName:=CampaignMages[scenario].name;
      end;
      if scenario>=40 then dt:=40;
     end;
     msg:=msg+'~'+FormatMessage([sa[j],winnerName,loserName,date,dt,sa[j+5]]);
     inc(j,db.colCount);
    end;
    finally
     gSect.Leave;
    end;
   except
    on e:Exception do LogMsg('Error in SearchReplays: '+ExceptionMsg(e));
   end;
   PostUserMsg(userID,msg);
  end;

 // Несмотря на наличие обращения к файлу, этот запрос выполняется в gSect, потому что файл все-равно нужно блокировать
 procedure SendReplayData(userID,replayID:integer);
  var
   bundle,slot:integer;
   fname:UTF8String;
   hdr:array[0..1] of integer;
   data:UTF8String;
  begin
   ASSERT(replayID>0);
   bundle:=replayID div 1000;
   slot:=replayID mod 1000;
   fname:='Replays\b'+inttostr(bundle);
   try
    ReadFile(fname,@hdr,slot*8,8);
    ASSERT(hdr[0]>0);
    ASSERT((hdr[1]>200) and (hdr[1]<8000));
    SetLength(data,hdr[1]);
    ReadFile(fname,@data[1],hdr[0],hdr[1]);
    users[userid].inCombat:=true;
    users[userid].UpdateUserStatus(psWatching);
   except
    on e:exception do LogMsg('Error loading replay data id='+inttostr(replayID)+': '+ExceptionMsg(e));
   end;
   PostUserMsg(userID,FormatMessage([82,data]));
  end;

 procedure CraftCard(userID,card,paymentType:integer);
  var
   cost:integer;
  begin
   ASSERT(paymentType in [1..2]);
   ASSERT(card>0);
   with users[userID] do begin
    LogMsg('Player %s crafts card %d using %d',[name,card,paymentType],logImportant);
    cost:=200;
    if (paymentType=1) and (gold<200) then begin
     PostUserMsg(userID,FormatMessage([2,1701,
       Format('^Not enough gold to craft a card:^ %d ^needed^, %d ^available^',[cost,gold])]));
     exit;
    end;
    if (paymentType=2) and (gems<200) then begin
     PostUserMsg(userID,FormatMessage([2,1702,
       Format('^Not enough crystals to craft a card:^ %d ^needed^, %d ^available^',[cost,gems])]));
     exit;
    end;
    if GrantNewCard(userID,card)=0 then begin
     PostUserMsg(userID,FormatMessage([2,1703,'You can''t craft this card']));
     raise EError.Create('Failed to grant a card '+inttostr(card));
    end;
    if paymentType=1 then Spend(userID,ppGold,cost,'Craft card '+inttostr(card));
    if paymentType=2 then Spend(userID,ppGems,cost,'Craft card '+inttostr(card));
    NotifyUserAboutNewCard(userID,card,4);
    PostUserMsg(userID,FormatMessage([17,card,gold,gems]));

    if GuildHasPerk(guild,4) then
     GrantGuildExp(playerID,guild,20,'Skilled Crafters');
   end;
  end;

 procedure BuyCard(userID:integer;slot,cardNum:integer);
  var
   card,cost,c:integer;
   i:integer;
  begin
   ASSERT((slot>=0) and (slot<6));
   with users[userID] do begin
    LogMsg('Player %s buys card (%d) in slot %d',[name,cardNum,slot],logNormal);
    if slot=0 then begin
     // Случайная карта
     card:=GetRandomAvailableCard(userID);
     cost:=50;
    end else begin
     card:=marketCards[slot];
     cost:=20;
    end;
    if card<=0 then begin
     PostUserMsg(userID,FormatMessage([2,1901,'No card available to buy']));
     exit;
    end;
    if gold<cost then begin
     PostUserMsg(userID,FormatMessage([2,1902,
       Format('^Not enough gold to buy a card:^ %d ^needed^, %d ^available^',[cost,gold])]));
     exit;
    end;
    c:=GrantNewCard(userID,card);
    if c=0 then begin
     LogMsg('Failed to grant a card to '+users[userid].name,logWarn);
     PostUserMsg(userID,FormatMessage([2,1903,'You can''t buy this card']));
     exit;
    end;
    Spend(userID,ppGold,cost,'Buy card '+inttostr(card));
    if cost=20 then i:=2 else i:=3;
    NotifyUserAboutNewCard(userID,card,i);
    if slot>0 then begin
     marketCards[slot]:=-marketCards[slot];
     AddTask(0,0,['UPDATEPLAYER',playerID,'market="'+ArrayToStr(marketCards)+'"']);
    end;
   end;
  end;

 procedure BuyPremiumForGold(userID,days:integer);
  var
   cost:integer;
  begin
   with users[userID] do begin
    LogMsg('Player %s buys %d days of premium',[name,days],logImportant);
    cost:=0;
    case days of
     //1:cost:=75;
     1:cost:=45; // экспериментальное снижение
     5:cost:=200;
     30:cost:=750;
    end;
    if cost<=0 then begin
     ShowMessageToUser(userID,'Incorrect number of days');
     exit;
    end;
    if cost>gold then begin
     ShowMessageToUser(userID,'^Not enough gold, need^ '+inttostr(cost));
     exit;
    end;
    GrantPremium(userID,days,'purchase for gold');
    Spend(userID,ppGold,cost,'premium purchase');
    NotifyUserAboutGoldOrGems(userid);
   end;
  end;

 procedure GuildLogMessage(gIdx:integer;msg:UTF8String;silentMode:boolean=false);
  var
   q:UTF8String;
  begin
   gSect.Enter;
   try
   with guilds[gIdx] do begin
    LogMsg('GuildLog('+name+'): '+msg,logNormal);
    guilds[gIdx].AddLogMessage(msg);
    q:=Format('INSERT INTO guildlog (guild,date,msg) values(%d,"%s","%s")',
     [guilds[gIdx].id,FormatDateTime('YYYY-MM-DD hh:nn:ss',Now),msg]);
    AddTask(0,0,['DBQUERY',q]);
    // Уведомить всех
    if not silentMode then
     PostGuildMsg(gIdx,FormatMessage([121,1,Now,msg]));
   end;
   finally
    gSect.Leave;
   end;
  end;

 procedure ReallyDepositTreasures(userid,g,amount:integer);
  var
   idx:integer;
  begin
   inc(guilds[g].treasures,amount);
   AddTask(0,0,['UPDATEGUILD',guilds[g].id,'treasures='+inttostr(guilds[g].treasures)]);
   AddTask(0,0,['UPDATEGUILDMEMBER',users[userid].playerID,
    'treasures=treasures+'+inttostr(amount)+', deposit=deposit+'+inttostr(amount)]);
   PostGuildMsg(g,FormatMessage([122,2,guilds[g].treasures]));
   NotifyUserAboutGoldOrGems(userID);
   idx:=guilds[g].FindMember(users[userid].name);
   if idx>=0 then begin
    inc(guilds[g].members[idx].treasures,amount);
    PostGuildMsg(g,'122~7~'+guilds[g].FormatMemberInfo(idx),'Treasures');
   end;
   GuildLogMessage(g,'%1 added %2 gold to the Guild Treasury%%'+
     users[userid].name+'`13%%'+inttostr(amount));
  end;

 // Высылает информацию о гильдии игроку
 procedure SendGuildInfo(userID:integer;sendGuildLog:boolean=false);
  var
   g,m,i,skip,cnt:integer;
   plrInfo,slog:UTF8String;
  begin
   gSect.Enter;
   try
   try
    g:=FindGuild(users[userid].guild);
    if g<=0 then exit;
    with guilds[g] do begin
     m:=FindMember(users[userid].name,true);
     plrInfo:=members[m].FormatCallToPowers+'~'+inttostr(length(members));
     LogMsg('CtP for '+users[userID].name+': '+members[m].FormatCallToPowers,logDebug);
     for m:=0 to high(members) do
      plrInfo:=plrInfo+'~'+FormatMemberInfo(m);
     PostUserMsg(userID,FormatMessage([120,name,level,exp,treasures,size,daily,
       bonuses,cards,motto,NextLaunchTime(1),NextLaunchTime(2)])+
       '~'+plrInfo);
     // Гильдейский лог
     if sendGuildLog then begin
      sLog:='';
      skip:=0; cnt:=0;
      if high(log)>150 then skip:=high(log)-120;
      for i:=0 to high(log) do begin
       if (i>0) and (i<skip) then begin
        if i=1 then slog:=slog+'~'+FormatMessage([log[0].date,'...']);
        continue; // слишком много сообщений - посылать только 1-е и 120 последних
       end;
       slog:=slog+'~'+FormatMessage([log[i].date,log[i].text]);
       inc(cnt);
      end;
      slog:='121~'+inttostr(cnt)+sLog;
      PostUserMsg(userID,slog);
     end;
     // Караваны
     for i:=1 to 2 do
      if caravans[i].running then
       PostUserMsg(userID,'124~'+inttostr(i)+caravans[i].FormatInfo);
    end;
   except
    on e:exception do LogMsg('Failed to send guild info for '+users[userid].name+': '+ExceptionMsg(e),logWarn);
   end;
   finally
    gSect.Leave;
   end;
  end;

 procedure CreateGuild(userID:integer;guildname:UTF8String;paymentType:integer);
  var
   st:UTF8String;
  begin
   st:=IsValidName(EncodeUTF8(guildname),true);
   if st<>'' then begin
    ShowMessageToUser(userID,st);
    exit;
   end;
   AddTask(UserID,0,['NEWGUILD',guildname,users[userid].playerID,paymentType]);
  end;

 procedure CreateGuildData(userID:integer;guildname:UTF8String;playerID,paymentType:integer);
  var
   id,n,cost,v,deposit:integer;
   powers:String[2];
   res:boolean;
   sa:AStringArr;
  begin
   // Validate guild name
   db.Query('SELECT id FROM guilds WHERE name="'+SqlSafe(guildname)+'"');
   if db.rowCount=1 then begin
    ShowMessageToUser(userID,'Sorry, this guild name is in use!');
    exit;
   end;
   gSect.Enter;
   try
    if not IsValidUserID(userID,true) then exit;

    if paymentType=1 then begin
     // Pay by Gold
     cost:=100;
     if users[userID].gold<cost then begin
      ShowMessageToUser(userID,Format('Not enough gold: %d required, %d available',[cost,users[userID].gold]));
      exit;
     end;
    end else begin
     // Pay by Crystals
     cost:=200;
     if users[userID].gems<cost then begin
      ShowMessageToUser(userID,Format('Not enough crystals: %d required, %d available',[cost,users[userID].gems]));
      exit;
     end;
    end;
   finally
    gSect.leave;
   end;

   db.Query('SELECT id FROM guilds WHERE name="%s"',[guildname]);
   if db.rowCount>0 then begin
    ShowMessageToUser(userID,'Sorry, this guild name is in use.');
    exit;
   end;
   db.Query('INSERT INTO guilds (name) values("%s")',[guildname]);
   if db.lastError<>'' then exit;
   id:=db.insertID;
   v:=1+random(6);
   powers:=CallToPowers[v];
   db.Query('INSERT INTO guildmembers (playerid,guild,rank,powers,treasures) values(%d,%d,3,%d,100) '+
    'ON DUPLICATE KEY UPDATE guild=%d, rank=3, powers=%d, treasures=100, exp=0',
     [playerid,id,v,id,v]);
   n:=AllocGuildIndex;
   guilds[n].LoadFromDB(db,Format('name="%s"',[SqlSafe(guildname)]));
   GuildLogMessage(n,'Guild "%1" created by %2%%'+guildname+'%%'+guilds[n].members[0].name+'`13',true);
   db.Query('UPDATE players SET guild="'+SqlSafe(guildname)+'" WHERE id='+inttostr(playerID));
   if db.lastError<>'' then exit;

   sa:=db.Query('SELECT deposit FROM guildmembers WHERE playerid='+inttostr(playerid));
   if db.rowCount=1 then begin
    deposit:=StrToInt(sa[0]);
    if deposit>0 then
     db.Query('UPDATE guildmembers SET deposit=0 WHERE playerid='+inttostr(playerid));
   end;

   gSect.Enter;
   try
    if paymentType=1 then
     res:=Spend(userID,ppGold,cost,'NewGuild:'+guildname)
    else
     res:=Spend(userID,ppGems,cost,'NewGuild:'+guildname);
    if not res then exit; // Failed to pay
    users[userid].guild:=guildName;
    PostUserMsg(userID,FormatMessage([101,guildname,users[userid].gold,users[userid].gems]));
    if deposit>0 then ReallyDepositTreasures(userid,n,deposit);

    SendGuildInfo(userID,true);
    MissionDone(userID,3);
   finally
    gSect.leave;
   end;
  end;

 procedure ReloadGuild(gIdx:integer);
  begin
   if guilds[gIdx].name<>'' then
    guilds[gIdx].LoadFromDB(db,'name="'+SqlSafe(guilds[gIdx].name)+'"');
  end;

 procedure ProposeJoinGuild(userID:integer;plrName:UTF8String);
  var
   g,user:integer;
  begin
   try
    user:=FindUser(plrName);
    if user<=0 then begin
     ShowMessageToUser(userID,'Sorry, player %1 is not available%%'+plrName+'`13');
     exit;
    end;
    if users[user].guild<>'' then begin
     ShowMessageToUser(userID,'Sorry, player %1 is already in a guild%%'+plrName+'`13');
     exit;
    end;
    g:=FindGuild(users[userid].guild,true);
    with guilds[g] do begin
     if length(members)>=size then raise EWarning.Create('Guild size limit exceed');
     if FindInteger(proposals,users[user].playerID)<0 then
      AddInteger(proposals,users[user].playerID);
     PostUserMsg(user,FormatMessage([102,users[userid].name,name]));
    end;
   except
    on e:Exception do begin
     LogMsg('ProposeJoinGuild error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,10201,'Operation failed!']));
    end;
   end;
  end;

 procedure HandleGuildProposal(userID:integer;accepted:boolean;guildname,fromPlayer:UTF8String);
  var
   g,idx,user:integer;
  begin
   try
    user:=FindUser(fromPlayer);
    g:=FindGuild(guildname,true);
    with guilds[g] do begin
     idx:=FindInteger(proposals,users[userID].playerID);
     if idx>=0 then begin
      RemoveInteger(proposals,idx);
      if user>0 then
       PostUserMsg(user,FormatMessage([103,2-byte(accepted),guildname,users[userid].name]));
      if accepted then begin
       if users[userID].guild<>'' then begin
        ShowMessageToUser(userID,'You should leave the guild %1 before you can join another guild%%'+users[userID].guild);
        exit;
       end;
       if FindMember(users[userID].name)>=0 then raise EWarning.Create('Duplicated guild member');
       // Игрок вступил в гильдию
       if length(members)>=size then raise EWarning.Create('Guild size limit exceed');
       AddTask(userID,0,['JOINGUILD',users[userID].name,guildname,fromplayer]);
      end;
     end else
      raise EWarning.Create('Proposal not found');
    end;
   except
    on e:Exception do begin
     LogMsg('ProposeJoinGuild error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,10301,'Operation failed!']));
    end;
   end;
  end;

 procedure JoinGuild(userID:integer;plrName,guildname,fromplayer:UTF8String);
  var
   p,g,m,guildID,plrID,i,deposit:integer;
   mem:TGuildMember;
   sa:AStringArr;
  begin
   gSect.Enter;
   try
    if not IsValidUserID(userID) or (users[userID].name<>plrName) then begin
     LogMsg('JoinGuild: invalid UserID',logWarn); exit;
    end;
    g:=FindGuild(guildName,true);
    guildID:=guilds[g].id;
    plrID:=users[userID].playerID;
   finally
    gSect.Leave;
   end;

   p:=1+random(6);
   db.Query('INSERT INTO guildmembers (playerid,guild,rank,powers) values(%d,%d,1,%d) '+
          'ON DUPLICATE KEY UPDATE guild=%d, treasures=0, exp=0, rank=1',
           [users[userID].playerID,guildID,p,guildID]);

   db.Query('UPDATE players SET guild="'+SqlSafe(guildName)+'" WHERE id='+inttostr(plrID));
   guilds[g].LoadFromDB(db,'id='+inttostr(guildID));

   sa:=db.Query('SELECT deposit FROM guildmembers WHERE playerid='+IntToStr(users[userID].playerID));
   if db.rowCount=1 then begin
    deposit:=StrToIntDef(sa[0],0);
    if deposit>0 then
     db.Query('UPDATE guildmembers SET deposit=0 WHERE playerid='+IntToStr(users[userID].playerID));
   end;

   gSect.Enter;
   try
    users[userID].guild:=guildName;
    SendGuildInfo(userID,true);
    m:=guilds[g].FindMember(plrName,true);
    // передвинуть в конец
    with guilds[g] do begin
     mem:=guilds[g].members[m];
     for i:=m to high(members)-1 do
      members[i]:=members[i+1];
     m:=high(members);
     members[m]:=mem;
    end;
    PostGuildMsg(g,'122~7~'+guilds[g].FormatMemberInfo(m),'Joined');
    GuildLogMessage(g,'%1 joined guild (invited by %2)%%'+plrName+'`13%%'+fromPlayer+'`13');
    if deposit>0 then ReallyDepositTreasures(userID,g,deposit);
    MissionDone(userID,3);
   finally
    gSect.Leave;
   end;
  end;

 procedure RemovePlayerFromGuild(userID:integer;plrName:UTF8String);
  var
   g,m1,m2,u,plrID:integer;
   allowed:boolean;
  begin
   g:=FindGuild(users[userid].guild);
   if g=0 then raise EWarning.Create('No guild found for user '+users[userid].name+':'+users[userid].guild);
   with guilds[g] do begin
    m1:=FindMember(users[userid].name,true);
    m2:=FindMember(plrName,true);
    allowed:=false;
    if m1=m2 then begin
     if (members[m1].rank<3) or
        (length(members)=1) then allowed:=true;
    end else
     allowed:=(members[m1].rank=3);
    if not allowed then begin
     ShowMessageToUser(userID,'You are not allowed to~remove player from guild');
     exit;
    end;
    // Рассылка уведомления всем
    PostGuildMsg(g,FormatMessage([104,plrName,users[userid].name]));
    // Добавление сообщения в гильдейский лог
    if plrname<>users[userid].name then
     GuildLogMessage(g,'Player %1 is kicked from guild by %2%%'+plrName+'`13%%'+users[userid].name+'`13')
    else
     GuildLogMessage(g,'%1 left the guild%%'+plrName+'`13');
    // Удаление из гильдии
    plrID:=members[m2].playerID; // ID удаляемого игрока
    members[m2]:=members[high(members)];
    SetLength(members,length(members)-1);
    u:=FindUser(plrName);
    if u>0 then begin
     users[u].guild:='';
    end else
     LogMsg('Player '+plrName+' not online',logInfo);
    AddTask(0,0,['UPDATEGUILDMEMBER',plrID,'guild=0']);
    AddTask(0,0,['UPDATEPLAYER',plrID,'guild=NULL']);
    AddTask(0,0,['CARRYGOLDOUT',plrName,guilds[g].id,plrID]);
   end;
  end;

 // Игрок забирает золото из гильдии
 procedure CarryGoldOut(plrname:UTF8String;gID,plrID:integer);
  var
   sa,sb:AStringArr;
   i,deposit,v,g,u:integer;
   st:UTF8String;
  begin
   deposit:=0;
   sa:=db.Query('SELECT deposit FROM guildmembers WHERE playerID='+inttostr(plrID));
   if db.rowCount>0 then deposit:=StrToInt(sa[0]);
   gSect.Enter;
   try
    g:=FindGuildByID(gID);
    if (g>0) and (deposit>guilds[g].treasures) then begin
     deposit:=guilds[g].treasures;
     LogMsg('Gold amount limited to guild treasures: '+inttostr(deposit),logNormal);
    end;
    if deposit>0 then begin
     GuildLogMessage(g,'%1 withdrawn %2 gold from the Guild Treasury%%'+
      plrname+'`13%%'+inttostr(deposit));
     u:=FindUser(plrname);
     if u>0 then PostServerMsg(u,'You have withdrawn %1 gold from the Guild Treasury. '+
      'If you join a guild again, this amount will be deposited '+
      'to the Guild Treasury automatically.%%'+inttostr(deposit),true);
    end;
    dec(guilds[g].treasures,deposit);
    v:=guilds[g].treasures;
    PostGuildMsg(g,FormatMessage([122,2,v]));
   finally
    gSect.Leave;
   end;
   db.Query('UPDATE guildmembers SET deposit=%d WHERE playerID=%d',[deposit,plrID]);
   db.Query('UPDATE guilds SET treasures=%d WHERE id=%d',[v,gID]);
  end;

 procedure ResetGuild(userID:integer;what:UTF8String);
  var
   g,m,code:integer;
   empty:UTF8String;
  begin
   ASSERT((what='cards') or (what='bonuses'),'Whaaat??? '+what);
   g:=FindGuild(users[userid].guild);
   if g=0 then raise EWarning.Create('No guild found for user '+users[userid].name+':'+users[userid].guild);
   with guilds[g] do begin
    m:=FindMember(users[userid].name,true);
    if members[m].rank<2 then begin
     ShowMessageToUser(userID,'You are not allowed to do this');
     exit;
    end;
    empty:='00000000000000000000';
    if what='bonuses' then begin
     bonuses:=empty;
     code:=5;
    end;
    if what='cards' then begin
     cards:=empty;
     code:=6;
    end;
   end;
   if not SpendGuild(users[userid].playerID,g,20,'Reset '+what) then begin
    ShowMessageToUser(userID,'Failed to pay for this operation');
    exit;
   end;
   GuildLogMessage(g,'%1 has reset guild '+what+'%%'+users[userid].name+'`13');
   AddTask(0,0,['UPDATEGUILD',guilds[g].id,Format('%s="%s"',[what,empty])]);
   PostGuildMsg(g,FormatMessage([122,code,empty]));
  end;

 procedure TakeGuildItem(userID:integer;what:UTF8String;index:integer);
  var
   g,spent,m:integer;
  begin
   try
    ASSERT(index in [1..20]);
    ASSERT((what='cards') or (what='bonuses'),'Whaaat??? '+what);
    g:=FindGuild(users[userid].guild,true);
    with guilds[g] do begin
     m:=FindMember(users[userid].name,true);
     if members[m].rank<2 then raise EWarning.Create('Rank is too low');
     if what='cards' then
      spent:=guilds[g].numCards
     else
      spent:=guilds[g].numBonuses;
     if spent>=level then raise EWarning.Create('Not enough points to take item');

     if what='cards' then begin
      if cards[index]='1' then raise EWarning.Create('Card already taken');
      cards[index]:='1';
      AddTask(0,0,['UPDATEGUILD',guilds[g].id,'cards="'+cards+'"']);
      GuildLogMessage(g,'%1 took guild card "%2"%%'+users[userid].name+'`13%%'+cardinfo[guildcards[index]].name);
      PostGuildMsg(g,FormatMessage([122,6,cards]));
     end else begin
      if bonuses[index]='1' then raise EWarning.Create('Bonus already taken');
      bonuses[index]:='1';
      AddTask(0,0,['UPDATEGUILD',guilds[g].id,'bonuses="'+bonuses+'"']);
      GuildLogMessage(g,'%1 took guild bonus "%2"%%'+users[userid].name+'`13%%'+bonusInfo[index].name);
      PostGuildMsg(g,FormatMessage([122,5,bonuses]));
      if index=5 then
       CheckGuildForDailyQuest(g);
     end;
    end;
   except
    on e:Exception do begin
     LogMsg('TakeGuildItem(%d,%s,%d) error: %s',[userID,what,index,ExceptionMsg(e)]);
     PostUserMsg(userID,FormatMessage([2,10601,'Operation failed!']));
    end;
   end;
  end;

 procedure ChangePlayerRank(userID:integer;plrName:UTF8String;newRank:integer);
  var
   g,m1,m2:integer;
  procedure SetMemberRank(m,rank:integer);
   begin
    with guilds[g] do begin
     members[m].rank:=rank;
     AddTask(0,0,['UPDATEGUILDMEMBER',members[m].playerID,'rank='+inttostr(rank)]);
     PostGuildMsg(g,'122~7~'+FormatMemberInfo(m),'Rank');
    end;
   end;
  begin
   try
    ASSERT(newRank in [1..3]);
    g:=FindGuild(users[userid].guild,true);
    with guilds[g] do begin
     m1:=FindMember(users[userid].name,true);
     m2:=FindMember(plrname,true);
     if members[m1].rank<3 then raise EWarning.Create('Rank too low');
     SetMemberRank(m2,newRank);
     if newRank=3 then SetMemberRank(m1,2);
     GuildLogMessage(g,'%1 changed rank for %2 to %3%%'+users[userid].name+'`13%%'+plrname+'`13%%'+GuildRankNames[newRank]);
    end;
   except
    on e:Exception do begin
     LogMsg('ChangePlayerRank error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,10901,'Operation failed!']));
    end;
   end;
  end;

 procedure AddGuildTreasures(userID:integer;srcType,amount:integer);
  var
   g,rate:integer;
   pp:TPlayerParam;
  begin
   try
    g:=FindGuild(users[userid].guild,true);
    ASSERT(srcType in [1,2]);
    if srcType=1 then begin
     pp:=ppGold; rate:=1;
    end else begin
     pp:=ppGems; rate:=2;
    end;
    if not Spend(userID,pp,amount*rate,'GuildDeposit->'+users[userid].guild) then
      raise EWarning.Create('Failed to pay for the guild gold');
    ReallyDepositTreasures(userID,g,amount);
   except
    on e:Exception do begin
     LogMsg('AddGuildTreasures error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,11001,'Operation failed!']));
    end;
   end;
  end;

 procedure IncreaseGuildSize(userID:integer);
  var
   g,cost:integer;
  begin
   try
    g:=FindGuild(users[userid].guild,true);
    ASSERT(guilds[g].size in [8..11]);
    cost:=GuildUpgradeCosts[guilds[g].size-7];
    if not SpendGuild(users[userID].playerID,g,cost,'Size+1='+inttostr(guilds[g].size+1)) then
     raise EWarning.Create('Failed to pay for increasing guild size');
    inc(guilds[g].size);
    AddTask(0,0,['UPDATEGUILD',guilds[g].id,'size='+inttostr(guilds[g].size)]);
    PostGuildMsg(g,FormatMessage([122,3,guilds[g].size]));
    GuildLogMessage(g,'%1 increased guild size to %2%%'+users[userid].name+'`13%%'+inttostr(guilds[g].size));
   except
    on e:Exception do begin
     LogMsg('IncreaseGuildSize error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,11101,'Operation failed!']));
    end;
   end;
  end;

 procedure ChangeGuildMotto(userID:integer;motto:UTF8String);
  var
   g,m:integer;
  begin
   try
    g:=FindGuild(users[userid].guild,true);
    m:=guilds[g].FindMember(users[userid].name,true);
    ASSERT(guilds[g].members[m].rank>1);
    ASSERT(length(DecodeUTF8(motto))<150);
    guilds[g].motto:=motto;
    AddTask(0,0,['UPDATEGUILD',guilds[g].id,'motto="'+SQLSafe(motto)+'"']);
    PostGuildMsg(g,FormatMessage([122,9,guilds[g].motto]));
    GuildLogMessage(g,'%1 changed guild message%%'+users[userid].name+'`13');
   except
    on e:Exception do begin
     LogMsg('ChangeGuildMotto error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,11201,'Operation failed!']));
    end;
   end;
  end;

 // Выбирает защитника и стартует бой (атакующий уже должен быть назначен!)
 procedure StartCaravanBattle(gIdx,cType,slot,userID:integer);
  var
   i,j,c,u,defender,l1,l2,n,defCount,goodDefCount,d:integer;
   bestRate,rate,numBattles:integer;
   st,defList:UTF8String;
  begin
   with guilds[gIdx] do begin
    if users[userID].connected>0 then begin
     LogMsg('Caravan attacker is already in duel! '+users[userID].name,logWarn);
     caravans[cType].attackers[slot]:='';
     caravans[cType].needBattleIn[slot]:=0;
     exit;
    end;
    LogMsg('Caravan state: '+guilds[gIdx].caravans[cType].FormatLog,logDebug);
    LogMsg('Staring caravan battle [%s], type=%d slot=%d - %s',[name,cType,slot,users[userID].name],logInfo);
    // Список защитников
    bestrate:=1000000; defender:=0; defCount:=0; goodDefCount:=0;
    l1:=CalcLevel(users[userID].GetFame(TDuelType(cType))); // уровень игрока
    st:=''; defList:='';
    for i:=0 to high(members) do begin
     u:=FindUser(members[i].name);
     if u<=0 then continue;
     if (users[u].connected>0) or (users[u].draftID>0) or (users[u].inCombat) then continue;
     if (Now<users[u].lastDuelFinished+10*SECOND) then continue;
     inc(defCount);
     l2:=CalcLevel(users[u].GetFame(TDuelType(cType))); // уровень игрока
     rate:=abs(l1-l2);
     for j:=1 to 8 do
      if (caravans[cType].battles[j] in [2,3]) and
         (caravans[cType].defenders[j]=users[u].name) then inc(rate,100);
     c:=0;
     for j:=1 to 8 do
      if (caravans[cType].battles[j]=3) and
         (caravans[cType].defenders[j]=users[u].name) then inc(c);
     case ctype of
      1:if (c>=3) then inc(rate,1000);
      2:if (c>=4) then inc(rate,1000);
     end;
     if users[u].status=psAFK then inc(rate,5000);
     if rate<5000 then inc(goodDefCount);
     st:=st+Format(' %s: lvl=%d rate=%d;',[members[i].name,l2,rate]);
     if rate<bestRate then begin
      bestRate:=rate; defender:=u;
     end;
    end;
     LogMsg('Defenders for %s lvl=%d: %s',[users[userID].name,l1,st],logDebug);

    if defender>0 then begin
     // Стартануть бой
     d:=StartDuel(userID,defender,TDuelType(cType),dcCaravan);
     if d=0 then raise EError.Create('Failed to start caravan battle!');
     caravans[cType].defenders[slot]:=users[defender].name;
     // Может нужно активировать еще слоты?
     n:=0;
     case cType of
      1:numBattles:=3;
      2:numBattles:=2;
     end;
     with caravans[cType] do begin
      for i:=1 to 8 do begin
       if (battles[i]>=1) and (attackers[i]<>'') and (defenders[i]<>'') then inc(n);
       if (battles[i]=1) and (defenders[i]='') then dec(goodDefCount);
      end;
      if n=numBattles then begin// 2-й этап запуска каравана - активируем столько слотов, сколько доступных защитников сейчас есть
       LogMsg('Caravan launch 2-nd stage! GoodDefs='+inttostr(goodDefCount),logInfo);
       for i:=1 to 8 do
        if (goodDefCount>1) and (battles[i]=0) then begin
         dec(goodDefCount);
         RequestActiveSlotIn(0);
        end;
       LogMsg('Caravan state: '+FormatLog,logDebug);
      end;
     end;
    end else begin
     // Защиты нет - автоматическая победа!
     LogMsg('No defender! Autowin for '+users[userID].name+' slot='+inttostr(slot),logNormal);
     caravans[cType].defenders[slot]:=users[0].name;
     caravans[cType].attackers[slot]:=users[userID].name;
     CaravanBattleFinished(userID,0,cType);
     exit;
    end;
    PostGuildMsg(gIdx,caravans[cType].FormatBattleUpdate(slot),'startBattle');
   end;
  end;

 // Создаёт бота и назначает его атакующим, а затем вызывает поиск защитника и старт боя
 procedure StartCaravanBattleWithBot(gIdx,cType,slot,avgLevel:integer);
  var
   bot,idx,botLev:integer;
  begin
   LogMsg('Caravan state: '+guilds[gIdx].caravans[cType].FormatLog,logDebug);
   LogMsg('Caravan battle with bot: %s, type=%d, slot=%d, avgLevel=%d',
     [guilds[gIdx].name,cType,slot,avgLevel],logInfo);
   // 1. Создать бота
   if cType=1 then begin
    users[0].boostLevel[dtCustom]:=0;
    users[0].customFame:=CalcFame(avgLevel);
    idx:=CustomBotDecksList.FindRandomCustomBot(avgLevel);
    botLev:=CustomBotDecksList.BotDecks[idx].control;
    LogMsg('Selected bot for Caravan: %d, control=%d, level=%d player level %d',
      [idx,botlev,CustomBotDecksList.BotDecks[idx].startinglevel,avgLevel],logInfo);
    bot:=AddBot(botLev,dtCustom,idx,CustomBotDecksList.BotDecks[idx].startinglevel);
   end else begin
    users[0].boostLevel[dtClassic]:=0;
    users[0].classicFame:=CalcFame(avgLevel);
    bot:=AddBot(GetBotLevelForUser(0,dtClassic),dtClassic);
   end;
   guilds[gIdx].caravans[cType].attackers[slot]:=users[bot].name;
   StartCaravanBattle(gIdx,cType,slot,bot);
  end;

 // Если в караване есть свободные слоты - пытается их занять
 // Возвращает true если слот активирован (статус>0), false - статус не изменился
 function ProposeCaravanBattle(gidx,cType,slot:integer):boolean;
  var
   i,j,n,k,n2,u,l1,l2,aLev,reason,bRunning,t,threshold,g:integer;
   best,attacker:integer;
   defenders:array[1..20] of integer;
   fl:boolean;
   st:UTF8String;
  begin
   result:=false;
   ASSERT(slot in [1..8]);
   with guilds[gIdx] do begin
    if not caravans[cType].running then exit;
    ASSERT(caravans[cType].battles[slot]=1);
    ASSERT(caravans[cType].attackers[slot]='');

    // 2. Список потенциальных защитников
    n:=0; aLev:=0;
    n2:=0; // кол-во защитников, которые не слили 2 боя
    for i:=0 to high(members) do begin
     u:=FindUser(members[i].name);
     if (u>0) and (users[u].connected=0) and (users[u].draftID=0) and (Now>users[u].lastDuelFinished+10*SECOND) then begin
      inc(n);
      defenders[n]:=u;
      inc(aLev,users[u].GetActualLevel(TDuelType(cType)));
      // Посчитаем сколько боёв уже слил этот игрок
      k:=0;
      for j:=1 to 8 do
       if (caravans[cType].battles[j]=3) and
          (caravans[cType].defenders[j]=users[u].name) then inc(k);
      if cType=2 then threshold:=3
       else threshold:=2;
      if k<threshold then inc(n2);
     end;
    end;

    // Защитников нет - вычислим средний уровень членов гильдии
    if n=0 then begin
     aLev:=0;
     for j:=1 to high(members) do begin
      if cType=1 then inc(aLev,allPlayers[members[j].playerID].customLevel);
      if cType=2 then inc(aLev,allPlayers[members[j].playerID].classicLevel);
     end;
     aLev:=round(aLev/high(members));
    end else
     aLev:=round(aLev/n);

    // Сколько боёв уже идёт?
    bRunning:=0;
    for i:=1 to 8 do
     if (caravans[cType].battles[i]=1) and (caravans[cType].needBattleIn[i]<>0) then inc(bRunning);

    if caravans[cType].needBattleIn[slot]=0 then begin
     // Первый раз: проверим, допустимо ли было вообще активировать этот слот?
     if (n2>0) or (bRunning<2) then begin
      LogMsg('Slot activated properly '+inttostr(slot),logDebug);
      t:=20;
      case slot of
       1:t:=15;
       3:t:=25;
       4:if cType=1 then t:=30;
      end;
      caravans[cType].needBattleIn[slot]:=Now+t*SECOND; // запустить бота через 20 сек
     end else begin
      LogMsg('Slot reset: %d good_def=%d running=%d',[slot,n2,bRunning],logDebug);
      caravans[cType].ResetSlot(slot);
      exit;
     end;
    end;

    // Очень временный дебаг!
    if random(10)=1 then
     LogMsg('PropState slot %d: running=%d defcnt=%d def=%d prop=%d t=%s aLev=%d',
       [slot,bRunning,n2,n,caravans[cType].propCount[slot],HowLong(caravans[cType].NeedBattleIn[slot]),aLev],logDebug);

    // 3. Выбор атакующего среди игроков
    attacker:=0; best:=-1;
    for i:=1 to High(users) do
     if users[i]<>nil then begin
      reason:=0;
      // уже играет либо в драфте либо AFK либо из своей же гильдии
      if (users[i].botLevel>0) then reason:=8 else
      if (users[i].connected>0) then reason:=1 else
      if (users[i].lastDuelFinished>Now-5*SECOND) then reason:=5 else
      if (users[i].draftID>0) then reason:=2 else
      if (users[i].status=psAFK) then reason:=3 else
      if (users[i].guild=name) then reason:=4 else
      // уже звали менее часа назад?
      if (caravanChallenged.Get(users[i].name)>Now-60*MINUTE) then reason:=5 else
      // не имеет 5 побед в Лиге
      if (users[i].classicWins+users[i].customWins+users[i].draftWins<5) then reason:=6;
      // cам защищает другой караван?
      if users[i].guild<>'' then begin
       g:=FindGuild(users[i].guild,false);
       if g>0 then
        if guilds[g].caravans[1].running or
           guilds[g].caravans[2].running then reason:=7;
      end;
      if reason>0 then begin
       if Now>users[i].dontLogUntil then begin
        if not (reason in [1,9]) then
         LogMsg('User %s can''t attack: %d',[users[i].name,reason],logDebug);
        users[i].dontLogUntil:=Now+3*SECOND;
       end;
       continue;
      end;
      // может играть с кем-либо из защитников?
      l1:=CalcLevel(users[i].GetFame(TDuelType(cType)));
      fl:=false;
      if n>0 then begin
       // Есть живые защитники - сравниваем с ними
       for j:=1 to n do begin
        l2:=CalcLevel(users[defenders[j]].GetFame(TDuelType(cType)));
        if CanDuel(l1,l2) then begin
         fl:=true; break;
        end;
       end;
      end else begin
       // Нет защитников - берём средний уровень
       fl:=CanDuel(l1,aLev-2) or CanDuel(l1,aLev+2);
      end;
      if not fl then continue;
      // приоритет
      if users[i].caravanPriority>best then begin
       attacker:=i; best:=users[i].caravanPriority;
      end;
     end;

    // Не прошло ли 20 секунд?
    if Now>caravans[cType].needBattleIn[slot] then begin
     LogMsg('Timer reached, slot %d, att=%d, running=%d def=%d',[slot,attacker,bRunning,n],logdebug);
     if n>0 then begin
      // Есть защитники
      // нет атакера - старт боя с ботом (если есть - будет дальше сделано предложение
      if (attacker=0) then StartCaravanBattleWithBot(gIdx,cType,slot,aLev);
     end else begin
      // Нет защитников
      // поражение без боя
      if (attacker>0) or
         ((attacker=0) and (bRunning<3)) then begin
       LogMsg('Autowin! Caravan: no attackers, no defenders, slot='+inttostr(slot)+'! '+caravans[cType].FormatLog,logInfo);
       caravans[cType].battles[slot]:=3;
       caravans[cType].attackers[slot]:='^Expert Mage^';
       PostGuildMsg(gIdx,caravans[cType].FormatBattleUpdate(slot),'autowin');
       st:='Defenders: ';
       for i:=0 to high(members) do begin
        st:=st+#13#10+members[i].name+': ';
        u:=FindUser(members[i].name);
        if u<=0 then st:=st+'offline' else
        if (users[u].connected=0) then st:=st+'in duel' else
        if (users[u].draftID=0) then st:=st+'in draft' else
        if (Now<users[u].lastDuelFinished+10*SECOND) then st:=st+'last duel finished '+FormatDateTime('hh:nn:ss',users[u].lastDuelFinished);
       end;
       LogMsg(st,logInfo);
       // активируем еще слот, раз бой виртуально завершен
       caravans[cType].RequestActiveSlotIn(10);
       LogMsg('Caravan state after: '+caravans[cType].FormatLog,logInfo);
      end;

      // Ресет слота
      if (attacker=0) and (bRunning>=3) then begin
       caravans[cType].ResetSlot(slot);
       LogMsg('Slot reset '+inttostr(slot)+': '+caravans[cType].FormatLog,logInfo);
      end;
     end;
    end;

    if attacker=0 then exit;

    LogMsg('Attacker selected: '+users[attacker].name,logDebug);
    // Отмена автопоиска тому, кому делается предложение
    for i:=1 to 3 do
     if users[attacker].autoSearchStarted[TDuelType(i)]>0 then begin
      users[attacker].autoSearchStarted[TDuelType(i)]:=0;
      PostUserMsg(attacker,FormatMessage([32,i]));
     end;
    PostUserMsg(attacker,FormatMessage([114,cType,name,Now+40*SECOND]));
    caravanChallenged.Put(users[attacker].name,Now,true);
    
    caravans[cType].battles[slot]:=1;
    inc(caravans[cType].propCount[slot]);
    caravans[cType].attackers[slot]:=users[attacker].name;
    result:=true;
    LogMsg('Caravan state: '+caravans[cType].FormatLog,logDebug);
   end;
  end;

 procedure LaunchCaravan(userID:integer;carType:integer);
  var
   g,m,cost,i,j,numPlr,minplrnum:integer;
   plrList:UTF8String;
  begin
   try
    if (serverState=ssRestarting) then begin
     i:=round((restartTime-Now)*1440);
     i:=sat(i,0,1000);
     if i<=20 then begin
      PostServerMsg(userID,'Sorry, the server is closing in %1 min, please try again later.%%'+inttostr(i));
      exit;
     end;
    end;

    g:=FindGuild(users[userid].guild,true);
    m:=guilds[g].FindMember(users[userid].name,true);
    ASSERT(guilds[g].members[m].rank>1);
    ASSERT(carType in [1..2]);
    if carType=1 then cost:=60 else cost:=40;
    if carType=1 then minplrnum:=3 else minplrnum:=2;
    if GuildHasPerk(guilds[g].name,3) then cost:=round(cost*0.8); // Perk-3: Resourceful Heroes
    ASSERT(guilds[g].treasures>=cost,'Not enough treasures');
    // Никакой караван не может сейчас быть в пути
    ASSERT(guilds[g].caravans[1].running=false);
    ASSERT(guilds[g].caravans[2].running=false);
    ASSERT(Now>=guilds[g].NextLaunchTime(carType));
    numPlr:=0; plrList:='';
    for i:=1 to high(users) do
     if users[i]<>nil then
      if (users[i].guild=guilds[g].name) and (users[i].connected=0) and
         (users[i].draftID=0) then begin
           inc(numPlr); plrList:=plrList+users[i].name+' ';
         end;
    if numPlr<minplrnum then begin
     PostUserMsg(userID,FormatMessage([2,11302,'Need at least %1 guild members~ready to defend (not in combat)!%%'+inttostr(minplrnum)]));
     exit;
    end;
    // All right - launch!
    ASSERT(SpendGuild(userID,g,cost,'Caravan launch'));
    with guilds[g] do begin
     LogMsg('Caravan launched type %d by "%s" Active players: %s',[carType,name,plrList]);
     caravans[carType].running:=true;
     caravans[carType].launched:=Now;
     with caravans[carType] do begin
      for i:=1 to 8 do ResetSlot(i);
      // начальный этап запуска
      for i:=1 to minplrnum do RequestActiveSlotIn(0);
      LogMsg('Caravan info: '+FormatLog,logDebug);
     end;
     AddTask(0,0,['UPDATEGUILD',id,'carLaunch'+inttostr(carType)+'=Now()']);
    end;

    // Всех гильдейцев из автопоиска выкинуть
    for i:=1 to high(users) do
     if users[i]<>nil then
      if (users[i].guild=guilds[g].name) then begin
       for j:=1 to 3 do
        if users[i].autoSearchStarted[TDuelType(j)]>0 then begin
          users[i].autoSearchStarted[TDuelType(j)]:=0;
          PostUserMsg(i,FormatMessage([32,j]));
        end;
       if users[i].connected>0 then PostServerMsg(i,'Your guild has launched a caravan!');
      end;

    PostGuildMsg(g,'124~'+inttostr(carType)+guilds[g].caravans[carType].FormatInfo);

   except
    on e:Exception do begin
     LogMsg('LaunchCaravan error: '+ExceptionMsg(e));
     PostUserMsg(userID,FormatMessage([2,11301,'Operation failed!']));
    end;
   end;
  end;

 // Предложение пограбить было принято (1) или отклонено (0)
 procedure CaravanAction(userID:integer;action:integer);
  var
   g,cType,slot:integer;
  begin
   for g:=1 to high(guilds) do
    for cType:=1 to 2 do
     if (guilds[g].caravans[cType].running) then
      for slot:=1 to 8 do
       with guilds[g].caravans[cType] do
        if (battles[slot]=1) and (attackers[slot]=users[userID].name) and
           (defenders[slot]='') then begin
         LogMsg('Caravan action %d, state=%s',[action,guilds[g].caravans[cType].FormatLog],logInfo);
         if action=1 then begin
          // Предложение принято!
          users[userID].caravanPriority:=0;
          AddTask(0,0,['UPDATEPLAYER',users[userid].playerID,'carPrior=0']);
          StartCaravanBattle(g,cType,slot,userID);
         end else begin
          // Предложение отклонено
          attackers[slot]:='';
          if propCount[slot]<2 then needBattleIn[slot]:=Now+20*SECOND;
          
          LogMsg('Caravan proposal rejected, attacker cleared for slot'+inttostr(slot),logDebug);
          with users[userid] do begin
           caravanPriority:=round(caravanPriority*2/3);
           AddTask(0,0,['UPDATEPLAYER',playerID,'carPrior='+IntToStr(caravanPriority)]);
          end;
         end;
         exit;
        end;
  end;

 procedure HandleCaravan(gIdx,cType:integer);
  const
   ct:array[1..2] of UTF8String=('Large','Small');
  var
   i,slot,u,wins,amount,exp,gold:integer;
  begin
   try
   with guilds[gIdx].caravans[cType] do begin
    if not running then exit;

    // 0. Нужно ли предложить грабёж по уже занятому слоту?
    for i:=1 to 8 do
     if (battles[i]=1) and (attackers[i]='') then
       ProposeCaravanBattle(gIdx,cType,i);

    // 1. Не пора ли активировать новый слот?
    for slot:=1 to 8 do
     if (battles[slot]=0) and (needBattleIn[slot]>0) and (Now>needBattleIn[slot]) then begin
        LogMsg('Activating caravan slot %d [%s, type %d] %s',[slot,guilds[gIdx].name,cType,
          guilds[gIdx].caravans[cType].FormatLog],logDebug);
        battles[slot]:=1;
        needBattleIn[slot]:=0; // Now+20*SECOND; // запуск бота через 20 секунд
        break;
     end;

    // 2. Не истёк ли таймаут предложений?
    for i:=1 to 8 do
     if (battles[i]=1) and (defenders[i]='') and (attackers[i]<>'') then begin
      u:=FindUser(attackers[i]);
      if u<=0 then AddTask(0,0,['DBQUERY','UPDATE players SET carPrior=Round(carPrior*2/3) WHERE name="'+SQLSafe(attackers[i])+'"']);
      if (u>0) and (caravanChallenged.Get(users[u].name)<Now-42*SECOND) then begin
       LogMsg('Caravan proposal timeout for slot '+IntToStr(i)+':'+FormatLog,logDebug);
       with users[u] do begin
        caravanPriority:=round(caravanPriority*2/3);
        AddTask(0,0,['UPDATEPLAYER',playerID,'carPrior='+IntToStr(caravanPriority)]);
       end;
       u:=0;
      end;
      if u<=0 then begin
       LogMsg('Slot cleared '+IntToStr(i)+':'+FormatLog,logDebug);
       attackers[i]:='';
      end;
     end; 

    // Караван завершён?
    for i:=1 to 8 do
     if battles[i]<2 then exit;

    // Finished!
    LogMsg('Caravan finished! [%s] type %d',[guilds[gidx].name,cType]);
    wins:=0; // кол-во успешных грабежей
    for i:=1 to 8 do
     if battles[i]=3 then inc(wins);
    PostGuildMsg(gIdx,FormatMessage([125,cType,guilds[gIdx].NextLaunchTime(cType)]));

    if cType=1 then amount:=120 else amount:=80;
    amount:=amount*(10-wins) div 10;
    GrantGuildGold(0,guilds[gIdx].name,amount,'Caravan');
    exp:=amount;
    if GuildHasPerk(guilds[gIdx].name,18) then exp:=exp*2; // Perk-18: Guild of Merchants
    exp:=GrantGuildExp(0,guilds[gIdx].name,exp,'Caravan');
    with guilds[gIdx].caravans[cType] do begin
     running:=false;
    end;
    GuildLogMessage(gIdx,ct[cType]+' caravan has been escorted! Guild received %1 gold and %2 experience.%%'+
     inttostr(amount)+'%%'+inttostr(exp));
   end;
   except
    on e:exception do LogMsg('HandleCaravan Error: '+ExceptionMsg(e));
   end;
  end;

 procedure ResetCaravan(userID,carType,payType:integer);
  var
   g,m,cost:integer;
   lt,ttl:double;
   st:UTF8String;
  begin
   try
    ASSERT(carType in [1..2]);
    ASSERT(payType in [1..2]);
    g:=FindGuild(users[userid].guild,true);
    with guilds[g] do begin
     if caravans[carType].running then begin
      PostUserMsg(userID,FormatMessage([2,11501,'Caravan is already running']));
      exit;
     end;
     lt:=NextLaunchTime(carType);
     ttl:=lt-Now;
     if ttl<30*SECOND then begin
      PostUserMsg(userID,FormatMessage([2,11502,'Caravan is almost ready to launch']));
      exit;
     end;
     cost:=CaravanResetGoldCost(carType,ttl);
     if payType=2 then cost:=cost*2;
     LogMsg('Caravan reset, type %d, next launch %s, remaining time %s, cost %d (%d)',[carType,
       FormatDateTime('mm.dd hh:nn:ss',lt),HowLong(lt),cost,payType],logDebug);

     if (payType=1) and (cost>users[userID].gold) then begin
      PostUserMsg(userID,FormatMessage([2,11503,'Not enough gold!']));
      exit;
     end;
     if (payType=2) and (cost>users[userID].gems) then begin
      PostUserMsg(userID,FormatMessage([2,11503,'Not enough crystals!']));
      exit;
     end;

     st:=Format('Caravan reset for %s type %d',[name,carType]);
     case payType of
      1:Spend(userID,ppGold,cost,st);
      2:Spend(userID,ppGems,cost,st);
     end;
     NotifyUserAboutGoldOrGems(userid);
     caravans[carType].launched:=0;
     AddTask(0,0,['UPDATEGUILD',id,'carLaunch'+inttostr(carType)+'=NULL']);
     PostGuildMsg(g,FormatMessage([122,11,NextLaunchTime(1),NextLaunchTime(2)]));
    end;
   except
    on e:exception do LogMsg('ResetCaravan Error: '+ExceptionMsg(e));
   end;
  end;

 procedure UpgradeCard(userID:integer;card:integer);
  var
   i,count,cost:integer;
   c:shortint;
  begin
   if users[userID].GetUserTitle<titleArchmage then begin
     PostUserMsg(userID,FormatMessage([2,4201,'Archmage title required to upgrade cards']));
     exit;
   end;
   ASSERT((card>0) AND (card<=numcards),'Bad card ID');
   if users[userid].ownCards[card]<6 then begin
     PostUserMsg(userID,FormatMessage([2,4202,'You should have 6 instances of the card to upgrade']));
     exit;
   end;
   
   count:=0;
   for c in users[userid].ownCards do
    if c<0 then inc(count);

   cost:=10+(count div 10)*5;
   if users[userID].gems<cost then begin
     PostUserMsg(userID,FormatMessage([2,4203,'Not enough crystals to uprage the card: '+inttostr(cost)+' required']));
     exit;
   end;
   if users[userID].gold<cost then begin
     PostUserMsg(userID,FormatMessage([2,4204,'Not enough gold to uprage the card: '+inttostr(cost)+' required']));
     exit;
   end;
   Spend(userId, ppGold, cost, 'Card upgrade: '+inttostr(card));
   Spend(userId, ppGems, cost, 'Card upgrade: '+inttostr(card));
   LogMsg('Player %s upgrades card %d (%s)',[users[userID].name,card,cardinfo[card].name]);
   users[userid].ownCards[card]:=-3;
   PostUserMsg(userID,FormatMessage([42,card,users[userid].gold,users[userid].gems]));
   AddTask(userID,0,['GRANTCARD',users[userid].playerID,CardSetToStr(users[userID].ownCards)]);
  end;

 procedure PostAdMgsIfNeeded(userID:integer);
  var
   fname:UTF8String;
   msg:UTF8String;
  begin
   if users[userid].flags and ufGoodnight=0 then exit;
   if users[userID].lastAdMsg>Now-120*MINUTE then exit;
   if (users[userid].room<>2) and (random(100)>30) then exit;
   if users[userID].gold>15 then exit;
   if users[userID].premium>Now then exit;
   try
    users[userID].lastAdMsg:=Now;
    fname:='adMsg.txt';
    if FileExists(fname) then msg:=LoadFileAsString(fname);
    PostServerMsg(userID,msg);
   except
    on e:Exception do LogMsg('Error in PostAdMsg: '+ExceptionMsg(e),logWarn);
   end;
  end;

 // всегда вызывается внутри gSect, userID - заведомо валидный
 procedure ExecUserRequest(userID:integer;userMsg:UTF8String);
  var
   j,code:integer;
   values:AStringArr;
   autopacket:boolean;
  begin
   try
    autopacket:=false;
    curUser:=userID;
    curUserCmd:=userMsg;
    values:=SplitA('~',userMsg);
    code:=StrToIntDef(values[0],-1);
    LogMsg('Msg from '+users[userID].name+': '+copy(userMsg,1,60),logInfo);
    serverThreadNum:=0; // main thread
    // Некоторые запросы шлются клиентом без участия игрока - они не должны выводить из AFK
    if (code=31) and (values[1]='0') then autoPacket:=true;

    if not autoPacket then begin
     users[userid].lastCommand:=now;
     users[userID].UpdateUserStatus;
    end;
    case code of
      0:ProcessDuelMsg(userID,values);
      1:UpdateTurnTimeout(userID);
      3:SaveClientLog(UserID,values[1]);
      4:SendServerTime(UserID);
     11:SetClientLang(userID,values[1]);
     12:users[userid].room:=StrToIntDef(values[1],users[userid].room);
     13:with users[userid] do begin
         optionsflags:=StrToIntDef(values[1],optionsFlags);
         AddTask(0,0,['UPDATEPLAYER',users[userid].playerID,'optionsflags='+IntToStr(optionsflags)]);
        end;
     15:AddTask(userID,0,['GETPLAYERPROFILE',values[1]]);
     16:begin
         users[userID].avatar:=StrToIntDef(values[1],users[userID].avatar);
         AddTask(0,0,['UPDATEPLAYER',users[userid].playerID,'avatar='+IntToStr(users[userID].avatar)]);
        end;
     17:CraftCard(userID,StrToIntDef(values[1],-1),StrToIntDef(values[2],-1));
     19:BuyCard(userID,StrToIntDef(SafeStrItem(values,1),-1),StrToIntDef(SafeStrItem(values,2),0));
     22:if high(values)>=2 then PostChatMsg(userID,values[1],values[2]);
     29:BuyPremiumForGold(userID,StrToIntDef(values[1],0));
     30:StartCampaignDuel(userID,StrToIntDef(values[1],0),values[2]);
     31:if users[userID].connected=0 then begin
         j:=StrToInt(values[1]);
         if j>0 then
          SetAutoSearch(userID,TDuelType(j),true);
         if j in [0,1] then // Check deck
           if not SetCurDeck(userID,values[2],j=0) then begin
             LogMsg('Invalid deck for user '+users[userid].name+': '+values[2],logWarn);
             if j=1 then SetAutoSearch(userID,TDuelType(StrToInt(values[1])),false);
           end;
        end else begin
         LogMsg('AS failed: user in duel '+users[userid].name);
         PostUserMsg(userID,'32~'+values[1]);
        end;
     32:SetAutoSearch(userID,TDuelType(StrToInt(values[1])),false);
     37:begin
         users[userID].inCombat:=false;
         PostAdMgsIfNeeded(userID);
        end;
     40:AddTask(userID,0,[40,values[1],values[2]]);  // Save/delete deck
     41:AddTask(userID,0,[41,values[1]]);
     42:UpgradeCard(userID,StrToInt(values[1]));
     50:DraftCard(userID,StrToIntDef(values[1],0));
     51:DraftDeckCreated(userID,values[1]);
     52:SetReadyForNextRound(userID);
     54:LeaveDraft(userID);
     61:EditFriendlist(userID,values[1],values[2]='1');
     63:EditBlacklist(userID,values[1],values[2]='1');
     64:ProposeTraining(userID,StrToIntDef(values[1],0),values[2],SafeStrItem(values,3));
     65:HandleProposal(userID,StrToIntDef(values[1],0),values[2],StrToIntDef(values[3],0),SafeStrItem(values,4));
     75:SearchPlayers(userID,values[1],StrToIntDef(values[2],0),StrToIntDef(values[3],0),
          StrToIntDef(values[4],0),StrToIntDef(values[5],0));
     81:AddTask(userID,0,[81,values[1],values[2],values[3]]);
     82:SendReplayData(userID,StrToIntDef(values[1],0));

     101:CreateGuild(userID,values[1],StrToIntDef(values[2],0));
     102:ProposeJoinGuild(userID,values[1]);
     103:HandleGuildProposal(userID,values[1]='1',values[2],values[3]);
     104:RemovePlayerFromGuild(userID,values[1]);
     105:ResetGuild(userID,'bonuses');
     106:TakeGuildItem(userID,'bonuses',StrToInt(values[1]));
     107:ResetGuild(userID,'cards');
     108:TakeGuildItem(userID,'cards',StrToInt(values[1]));
     109:ChangePlayerRank(userID,values[1],StrToInt(values[2]));
     110:AddGuildTreasures(userID,StrToInt(values[1]),StrToInt(values[2]));
     111:IncreaseGuildSize(userID);
     112:ChangeGuildMotto(userID,values[1]);
     113:LaunchCaravan(userID,StrToInt(values[1]));
     114:CaravanAction(userID,StrToInt(values[1]));
     115:ResetCaravan(userID,StrToInt(values[1]),StrToInt(values[2]));
    end;
   except
    on e:exception do LogMsg('Error in user '+users[userID].name+
      ' request: '+userMsg+' - '+ExceptionMsg(e),logWarn);
   end;
   curUser:=0;
  end;

 procedure HandleAutoSearch(allowBots:boolean);
  var
   mode:TDuelType;
   i,idx,n,best,cnt,total,botLevel,userID,maxDelay,minDelay,bot,virtlevel:integer;
   t,max,waitSec:double; // время нахождения юзера в автопоиске (в секундах)
   list:array[1..100] of integer;
   time:TDateTime;

  // Оценить пару (чем выше оценка - тем лучше пара, <0 - играть не может)
  function RatePair(user1,user2:integer;mode:TDuelType):double;
    var
     level1,level2:integer; // Уровни, соответствующие славе игроков после корректировки
     rLevel1,rLevel2:integer; // уровни без корректировки
    begin
     result:=-1;
     // на всякий случай: боты друг с другом играть не могут
     if (users[user1].botLevel>0) and (users[user2].botLevel>0) then exit;
     if waitSec<4 then exit; // минимальное время ожидания 
     // Используем эффективный уровень вместо видимого
     case mode of
      dtCustom:begin
       rLevel1:=CalcLevel(users[user1].customFame);
       rLevel2:=CalcLevel(users[user2].customFame);
      end;
      dtClassic:begin
       rLevel1:=CalcLevel(users[user1].classicFame);
       rLevel2:=CalcLevel(users[user2].classicFame);
      end;
      else exit;
     end;
     level1:=Sat(rLevel1+users[user1].boostLevel[mode],1,100);
     level2:=Sat(rLevel2+users[user2].boostLevel[mode],1,100);

     if not CanDuel(level1,level2) then exit;
     if not CanDuel(rLevel1,rLevel2) then exit;

     result:=max2(1,20-abs(level1-level2));
     if not users[user1].CanPlayWithPlayer(users[user2].playerID,mode) then begin
      result:=-1;
     end;
    end;

  begin
   time:=Now;

   for mode:=dtCustom to dtDraft do try
    // Составить список живых юзеров в автопоиске
    cnt:=0;
    fillchar(list,sizeof(list),0);
    for i:=1 to high(users) do
      if (users[i]<>nil) and
         (users[i].autoSearchStarted[mode]>0) and
         (users[i].connected=0) and
         (users[i].botLevel=0) and
         (users[i].draftID=0) then begin
        inc(cnt);
        list[cnt]:=i;
      end;
    total:=cnt;  
    autoSearchState[mode]:='Players in search:'#13#10;
    for i:=1 to cnt do autoSearchState[mode]:=autoSearchState[mode]+IntToStr(i)+' '+users[list[i]].name+#13#10;

    if mode in [dtCustom,dtClassic] then
     while cnt>0 do begin
      // Выберем из списка игрока, который ждёт дольше всех
      userID:=0; max:=0; n:=0;
      for i:=1 to cnt do begin
       t:=time-users[list[i]].autoSearchStarted[mode];
       if (t>max) and (users[list[i]].playerID>0) then begin // только для живых
         max:=t; n:=i; userID:=list[i];
       end;
      end;
      if userID=0 then break;
      autoSearchState[mode]:=autoSearchState[mode]+' '+users[userID].name+':';
      // Удалим игрока из списка
      list[n]:=list[cnt];  // list[n] отныне использовать нельзя!!!
      dec(cnt);
      // Может ли этот игрок стартовать?
      waitSec:=max*86400; // сколько уже ждёт живой юзер (в секундах)
      minDelay:=3;
      case mode of
       dtCustom:minDelay:=round(3*sqrt(users[userid].customLevel));
       dtClassic:minDelay:=round(3*sqrt(users[userid].classicLevel));
      end;
      if total>3 then minDelay:=minDelay div 2;
      if waitSec<minDelay then continue; // слишком мало ждёт

      // Не пора ли стартовать бой с ботом?
      case mode of
       dtCustom:maxDelay:=BOT_DELAY_CUSTOM+users[userID].customLevel;
       dtClassic:maxDelay:=BOT_DELAY_CLASSIC+users[userID].classicLevel;
       dtDraft:maxDelay:=BOT_DELAY_DRAFT+users[userID].draftLevel;
       else maxDelay:=15;
      end;
      if users[userID].optionsflags and 4>0 then inc(maxDelay,360000); // не играть с ботами (100 часов)
      autoSearchState[mode]:=autoSearchState[mode]+Format('waiting %f, maxdelay %d'#13#10,[waitSec,maxdelay]);
      if (waitSec>maxDelay) and (total<10) then begin
       // надо добавить бота и стартануть бой
       if mode=dtCustom then begin
{        if abs(users[userID].boostLevel[dtCustom])>1 then begin
         users[userID].boostLevel[dtCustom]:=Sat(users[userID].boostLevel[dtCustom],-1,1);
         LogMsg(Format('Bad BoostLevel for %s = %d',[users[userID].name,users[userID].boostLevel[dtCustom]]));
        end;}
        with users[userID] do
         virtlevel:=Sat(CalcLevel(customFame)+boostLevel[dtCustom],1,100);
        idx:=CustomBotDecksList.FindRandomCustomBot(virtlevel);
        ASSERT((idx>=low(CustomBotDecksList.BotDecks)) AND (idx<=high(CustomBotDecksList.BotDecks)),
          'Wrong bot deck index for fame '+inttostr(users[userid].customFame));
        botLevel:=CustomBotDecksList.BotDecks[idx].control;
        LogMsg('Selected bot: %d, control=%d, level=%d player level %d',
          [idx,botlevel,CustomBotDecksList.BotDecks[idx].startinglevel,virtlevel],logInfo);
        bot:=AddBot(botLevel,dtCustom,idx,CustomBotDecksList.BotDecks[idx].startinglevel);
       end else
        bot:=AddBot(GetBotLevelForUser(userID,mode),mode); // Добавить бота
       StartDuel(userID,bot,mode,dcRated);
       break;
      end;
      // Поищем пару для этого игрока
      max:=0; best:=0;
      for i:=1 to cnt do begin
       if time<users[list[i]].autoSearchStarted[mode]+SECOND then continue; // Нужно пробыть в автопоиске хотя бы полсекунды!
       t:=RatePair(userID,list[i],mode);
       autoSearchState[mode]:=autoSearchState[mode]+Format(' %s rate %f'#13#10,[users[list[i]].name,t]);
       if t>max then begin
         max:=t; best:=i;
       end;
      end;
      autoSearchState[mode]:=autoSearchState[mode]+Format('Best rate = %f',[max]);
      if best>0 then begin
        if (minLogMemLevel=0) then LogMsg(autoSearchState[mode],logDebug);
        StartDuel(userID,list[best],mode,dcRated);
        break;
      end;
     end;

    if mode=dtDraft then begin // В драфте совсем другой алгоритм
     autoSearchState[mode]:=autoSearchState[mode]+Format('cnt=%d; lastAS=%s',[cnt,HowLong(lastDraftAutosearch)]);
     // 1) если в автопоиске кто-то ровно один, он готов воевать с ботами и ждёт уже 30 секунд - стартовать с тремя ботами.
     if (cnt=1) and (users[list[1]].optionsflags and 4=0) and
        (time>users[list[1]].autoSearchStarted[dtDraft]+30*SECOND) then begin
      LogMsg('Draft autosearch: case 1',logInfo);
      StartDraft(list[1],0,0,0); // Один игрок с ботами
      continue;
     end;
     // 2) если в автопоиск набились 4 игрока - стартовать драфт.
     if (cnt>=4) then begin
      LogMsg('Draft autosearch: case 2',logInfo);
      StartDraft(list[1],list[2],list[3],list[4]);
      continue;
     end;
     // 3) если в автопоиске минимум двое и в автопоиск никто уже 20 секунд не заходил - стартовать бой дополнив ботами. (независимо от галочек про ботов).
     if (cnt>=2) and (Now>lastDraftAutosearch+20*SECOND) then begin
      LogMsg('Draft autosearch: case 3',logInfo);
      StartDraft(list[1],list[2],list[3],list[4]);
      continue;
     end;
    end;
   except
    on e:exception do LogMsg('Error in AutoSearch, mode '+inttostr(ord(mode))+': '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure HandleTimeouts;
  var
   i:integer;
   user:integer;
  begin
   try
    // Таймауты дуэлей
    for i:=1 to High(games) do
      with games[i] do
        if (user1>0) and
           (user2>0) and
//           (scenario=0) and
           (turnStarted>0) then begin
          if turn=1 then user:=user1
            else user:=user2;
          if (not timeout_flag) and (Now>turnTimeout-15*SECOND) then begin
            timeout_flag:=true;
            users[user].timeoutWarning:=true;
            PostUserMsg(user,FormatMessage([39,15,FloatToStrF(turnTimeout,ffFixed,13,8)]));
          end;
          if Now>turnTimeout+4*SECOND then begin
            LogMsg('Timeout for '+users[user].name+': '+FormatDateTime('hh:mm:ss.zzz',turnTimeout));
            PostUserMsg(user,FormatMessage([39,0]));
            PostUserMsg(users[user].connected,FormatMessage([39,1]));
            SaveTurnData([0,5]);
            GameOver(i,-user,'TurnTimeout');
          end;
        end;
   except
    on e:exception do LogMsg('Error in HandleTimeouts: '+ExceptionMsg(e),logWarn);
   end;
  end;

 // Пройти по всем боям и если где-то ожидается действие от AI-бота - запустить AI
 procedure HandleAI;
  var
   i,user:integer;
  begin
   for i:=1 to high(games) do try
    with games[i] do
     if (user1>0) and (user2>0) and not finished and
        (Now>turnStarted+(BOT_TURN_DELAY+BOT_ACTION_DELAY*numActions)*SECOND) then begin
       if not (turn in [1,2]) then continue;
       if turn=1 then user:=user1 else user:=user2;
       if (users[user].botLevel>0) and (not users[user].botThinking) then begin
         users[user].botThinking:=true;
         AddTask(user,0,['AI',i]);
       end;
     end;
   except
    on e:exception do LogMsg('Error in HandleAI, game '+inttostr(i)+': '+ExceptionMsg(e),logWarn);
   end;
  end;

 // Load everything (once the server is started)
 procedure Initialize;
  begin
   try
    ForceLogMessage('CL Initialization');
    gameData.InitConsts;
    PairPowerLoad;
    CustomBotDecksList.init;
    AddTask(0,0,['INITSERVERDATA']);
   except
    on e:Exception do LogMsg('CL Initialization error: '+ExceptionMsg(e),logCritical);
   end;
   initialized:=true;
  end;

 function GetSystemTimes(var time1,time2,time3:TFileTime):boolean; stdcall; external 'kernel32.dll'; 
 var
  lastMinute:integer=-1;
  saveKernelTime:int64=-1;
  saveUserTime:int64=-1;
  saveIdleTotal:int64=-1;
  saveKernelTotal:int64=-1;
  saveUserTotal:int64=-1;

 // Вызывается из таймера внутри gSect
 procedure HandleStat;
  var
   time:TDateTime;
   i,min:integer;
   time1,time2,time3,time4,v1,v2:int64;
  begin
   try
   time:=Now;
   min:=trunc(frac(time)*1440);
   // Наступила новая минута?
   if min<>lastMinute then begin
    if lastMinute=-1 then begin
     lastMinute:=min;
     exit;
    end;
    lastMinute:=min;
    // Получаем статистическую инфу сервера
    // Есть 2 типа параметров:
    // 1) счётчики событий, идут нарастающим итогом,
    // 2) моментальные значения какого-либо показателя

    // ServerStat

    serverStat.connections:=GetConCount;
    serverStat.users:=0;
    serverStat.usersAlive:=0;
    for i:=1 to high(users) do
     if users[i]<>nil then begin
      inc(serverStat.users);
      if users[i].botLevel=0 then
       inc(serverStat.usersAlive);
     end;

    serverStat.duels:=0;
    for i:=1 to high(games) do
     if (games[i].user1>0) and (games[i].user2>0) then
      inc(serverStat.duels);

    serverStat.drafts:=0;
    for i:=1 to high(drafts) do
     if drafts[i].players[1]>0 then
      inc(serverStat.drafts);

    serverStat.maxQueue:=MaxQueueSize;
    MaxQueueSize:=0;

    GetProcessTimes(GetCurrentProcess,TFileTime(time1),TFileTime(time2),
      TFileTime(time3), // kernel time in 0.1us
      TFileTime(time4)); // user time
    if saveKernelTime>=0 then
     serverStat.cpuUsageKernel:=(time3-saveKernelTime) div 10000
    else
     serverStat.cpuUsageKernel:=0;
    saveKernelTime:=time3;

    if saveUserTime>=0 then
     serverStat.cpuUsageUser:=(time4-saveUserTime) div 10000
    else
     serverStat.cpuUsageUser:=0;
    SaveUserTime:=time4;

    GetSystemTimes(TFileTime(time1),TFileTime(time2),TFileTime(time3));
    if saveIdleTotal>=0 then begin
     time4:=time1-saveIdleTotal;
     v1:=time2-saveKernelTotal;
     v2:=time3-saveUserTotal;
     serverStat.cpuTotal:=round(100*((v1+v2-time4)/(v1+v2))); // в процентах
    end else begin
     serverStat.cpuTotal:=0;
    end;
    saveIdleTotal:=time1;
    saveKernelTotal:=time2;
    saveUserTotal:=time3;

    serverStat.memoryUsed:=integer(GetMemoryAllocated);

    AddTask(0,0,['SAVESERVERSTAT']);
   end;
   except
    on e:exception do LogMsg('Error in HandleStat: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure HandlePlayerStatuses;
  var
   i:integer;
  begin
   try
    if statusChanges='' then exit;
    statusChanges:='76'+statusChanges;
    for i:=0 to high(users) do
     if users[i]<>nil then
      if users[i].trackPlayersStatus then
       PostUserMsg(i,statusChanges);

    statusChanges:='';      
   except
    on e:exception do LogMsg('Error in HandleStatuses: '+ExceptionMsg(e),logWarn);
   end;
  end;

 // Всегда вызывается внутри gSect (10 раз в секунду)
 procedure onCustomTimer;
  var
   i,j:integer;
  begin
   try
    if not initialized then Initialize;
    // Check hashes
    for i:=1 to high(games) do
     if (games[i].user1>0) and (games[i].duelSaveHash<>0) then
      if games[i].duelSaveHash<>GetDuelHash(i) then begin
       LogMsg('ERROR DuelSave broken in duel #'+IntToStr(i),logWarn);
       games[i].duelSaveHash:=0;
      end;

    HandleAutoSearch(true);
//    HandleAutoSearch(false);
    HandleTimeouts;
    HandleAI;
    HandleStat;
    for i:=1 to High(drafts) do
     with drafts[i] do
      if players[1]>0 then HandleDraft(i);

    for i:=1 to high(guilds) do
     for j:=1 to 2 do
      if guilds[i].caravans[j].running then HandleCaravan(i,j);

    HandlePlayerStatuses;
   except
    on e:EWarning do LogMsg('Error in CustomTimer: '+ExceptionMsg(e),logWarn);
    on e:exception do LogMsg('Error in CustomTimer: '+ExceptionMsg(e),logError);
   end;
  end;

 procedure InitThreadDatabase(wID:integer);
  var
   i:integer;
  begin
   EnterCriticalSection(gSect);
   try
    LogMsg('Initializing DB: '+inttostr(wID));
    DB:=TCustomMySqlDatabase.Create;
    DB.Connect;
    if not DB.connected then raise EError.Create('DB connection failed!');
    LogMsg('DB Initialized: '+inttostr(wID),logImportant);
   finally
    LeaveCriticalSection(gSect);
   end;
  end;

 procedure DoneThreadDatabase(wID:integer);
  begin
   LogMsg('DB Done: '+inttostr(wID),logImportant);
   FreeAndNil(DB);
  end;

 procedure UpdateQuestsForOnlineUsers;
  var
   i:integer;
  begin
   try
   EnterCriticalSection(gSect);
   try
    for i:=1 to High(users) do
     if (users[i]<>nil) and (users[i].botLevel=0) then
      users[i].updateQuests:=true;
   finally
    LeaveCriticalSection(gSect);
   end;
   except
    on e:Exception do LogMsg('Error in UQFOU: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure UpdateMarketForOnlineUsers;
  var
   i:integer;
   uList:array[1..3000] of integer;
   uMarket:array[1..3000] of UTF8String;
   cnt:integer;
  begin
   try
   EnterCriticalSection(gSect);
   try
    cnt:=0;
    for i:=1 to High(users) do
     if (users[i]<>nil) and (users[i].botLevel=0) then begin
      DefineUserMarket(i);
      SendMarketCards(i);
      inc(cnt);
      uList[cnt]:=users[i].playerID;
      uMarket[cnt]:=ArrayToStr(users[i].marketCards);
     end;
   finally
    LeaveCriticalSection(gSect);
   end;
   for i:=1 to cnt do
    db.Query('UPDATE players SET market="'+uMarket[i]+'" WHERE id='+IntToStr(uList[i]));
   except
    on e:Exception do LogMsg('Error in UMFOU: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure UpdateGuilds;
  var
   sa:AStringArr;
   ctp:array of integer; // userID*100+powers
   i,j,id,v,delta,g:integer;
   list,values:IntArray;
   hash:TSimpleHashS;
   gName:UTF8String;
  begin
   try
   if SPARE_SERVER then begin
    LogMsg('Spare server - no guild update!');
    exit;
   end;

   try
    // Update guild exp (Perk 10)
    // Выберем игроков, которые претендуют на звание архмага (400+ карт)
    sa:=db.Query('SELECT id,guild,cards FROM players WHERE campaignWins>=15');
    // здесь будет список гильдий, в которых есть Архмаги
    hash.Init(200);
    // Составляем список гильдий
    for i:=0 to db.rowCount-1 do
     if CardsCount(sa[i*3+2])>=400 then
      hash.Add(sa[i*3+1],1);

    for i:=0 to hash.count-1 do
     if hash.keys[i]>'' then begin
      v:=hash.values[i];
      gName:=hash.keys[i];
      // Есть ли эта гильдия в кэше? Если нет - загрузим её
      gSect.Enter;
      try
       g:=FindGuild(gName);
      finally
       gSect.Leave;
      end;
      if g<=0 then begin
       g:=AllocGuildIndex;
       guilds[g].LoadFromDB(db,'name="'+SqlSafe(gName)+'"');
      end;
      GrantGuildExp(0,gName,25*v,'Perk-10');
     end;

   except
    on e:exception do LogMsg('ERROR in Perk-10: '+ExceptionMsg(e));
   end;

   // Update treasures (Perk 6)
   db.Query('UPDATE guilds SET treasures=treasures+10+treasures div 1000 WHERE SUBSTR(bonuses,6,1)="1"');
   sa:=db.Query('SELECT id,treasures FROM guilds WHERE SUBSTR(bonuses,6,1)="1"');
   SetLength(list,0);
   SetLength(values,0);
   gSect.Enter;
   try
   for i:=0 to db.rowCount-1 do begin
    id:=StrToIntDef(sa[i*2],0);
    v:=StrToInt(sa[i*2+1]);
    AddInteger(list,id);
    AddInteger(values,v);
    for j:=1 to high(guilds) do
     if guilds[j].id=id then begin
      guilds[j].treasures:=v;
      PostGuildMsg(j,FormatMessage([122,2,v])); // потенциально тормознутое место!!!
     end;
   end;
   finally
    gSect.Leave;
   end;
   try
    for i:=0 to high(list) do begin
     delta:=10+(values[i]-10-values[i] div 1000) div 1000;
     AddEventLog(GUILDBASE+list[i],'GUILDGOLD',Format('%d+%d=%d;0;Perk-6',[values[i]-delta,delta,values[i]]));
    end;
   except
    on e:Exception do LogMsg('Error! '+ExceptionMsg(e),logWarn);
   end;

   // Update daily quests
   db.Query('UPDATE guilds SET daily=0 WHERE daily=100');
   gSect.Enter;
   try
   for i:=1 to high(guilds) do begin
    if guilds[i].daily=100 then begin
     guilds[i].daily:=0;
     PostGuildMsg(i,FormatMessage([122,4,0]));
    end;
   end;
   finally
    gSect.Leave;
   end;
   // Update CtP
   db.Query('UPDATE guildmembers SET powers=Ceil(5.5*Rand()),rewards=0');
   sa:=db.Query('SELECT playerID,powers FROM guildmembers');
   SetLength(ctp,100000);
   for i:=0 to db.rowCount-1 do begin
    id:=StrToInt(sa[i*2]);
    v:=StrToInt(sa[i*2+1]);
    if id>high(ctp) then SetLength(ctp,id+5000);
    if id<0 then continue;
    ctp[id]:=v; // паверы
   end;
   // Update guilds cache
   gSect.Enter;
   try
   // mark online players
   for i:=1 to high(users) do
    if users[i]<>nil then begin
     id:=users[i].playerID;
     if (id>0) and (id<length(ctp)) then
      ctp[id]:=ctp[id] mod 100+i*100;
    end;

   for i:=1 to high(guilds) do
    for j:=0 to high(guilds[i].members) do
     with guilds[i].members[j] do
      if playerID<=high(ctp) then begin
       v:=ctp[playerID] mod 100;
       rewards:=0;
       powers:=CallToPowers[v];
       // Player online?
       if ctp[playerID]>100 then
         PostUserMsg(ctp[playerID] div 100,'122~8~'+FormatCallToPowers);
      end;
   finally
    gSect.Leave;
   end;
   // Save guilds into history
   db.Query('SET @place=0');
   db.Query('INSERT INTO guildplaces (place,guild,level,date,exp) SELECT @place:=@place+1,id,level,Date(Now()),exp FROM guilds WHERE flags=0 ORDER BY level DESC,exp DESC LIMIT 100');
   except
    on e:exception do LogMsg('Error in UpdateGuilds: '+ExceptionMsg(e));
   end;
  end;

 procedure WeeklyDecreaseFame;
  var
   sa:AStringArr;
   active:array of boolean;
   i,id:integer;
   q:UTF8String;
  begin
   try
    LogMsg('Weekly Decrease Fame!');
    SetLength(active,length(allPlayers)+1);
    for i:=0 to high(active) do active[i]:=false;

    sa:=db.Query('SELECT winner,MAX(date) FROM duels WHERE date>SubDate(Now(),30) AND winner>0 GROUP BY winner');
    for i:=0 to length(sa) div 2-1 do begin
     id:=StrToInt(sa[i*2]);
     if (id>0) and (id<length(active)) then active[id]:=true;
    end;
    sa:=db.Query('SELECT loser,MAX(date) FROM duels WHERE date>SubDate(Now(),30) AND loser>0 GROUP BY loser');
    for i:=0 to length(sa) div 2-1 do begin
     id:=StrToInt(sa[i*2]);
     if (id>0) and (id<length(active)) then active[id]:=true;
    end;

    q:='';
    for i:=1 to high(active) do begin
     if active[i] then begin
      if q<>'' then q:=q+',';
      q:=q+inttostr(i);
     end else with allPlayers[i] do begin
      customFame:=round(customFame*0.99);
      customLevel:=CalcLevel(customLevel);
      classicFame:=round(classicFame*0.99);
      classicLevel:=CalcLevel(classicLevel);
      draftFame:=round(draftFame*0.99);
      draftLevel:=CalcLevel(draftLevel);
     end;
     if (length(q)>250) or (i=high(active)) then begin
      db.Query('UPDATE players SET flags=concat(flags,"A") WHERE id in ('+q+')');
      q:='';
     end;
    end;

    db.Query('UPDATE players SET customFame=round(customFame*0.99), classicFame=round(classicFame*0.99),'+
     ' draftFame=round(draftFame*0.99) WHERE locate("A",flags)=0');
    db.Query('UPDATE players SET flags=replace(flags,"A","")');
   except
    on e:Exception do LogMsg('Error in MDF: '+ExceptionMsg(e),logError);
   end;
  end;

 procedure DatabaseMaintenance;
  var
   sa:AStringArr;
   maxID:integer;
  begin
   if SPARE_SERVER then exit;
   LogMsg('DB maintenance',logNormal);
   // Перенести все строки из duels_new в duels
   sa:=db.Query('SELECT max(id) FROM duels_new');
   if db.rowCount>0 then begin
    maxID:=StrToIntDef(sa[0],0);
    if maxID>0 then begin
     db.Query('INSERT INTO duels (dueltype,scenario,winner,loser,date,turns,duration,firstPlr,winnerLevel,loserLevel,winnerDeck,loserDeck,winnerFame,loserFame,replayID,replayAccess) '+
      ' SELECT dueltype,scenario,winner,loser,date,turns,duration,firstPlr,winnerLevel,loserLevel,winnerDeck,loserDeck,winnerFame,loserFame,replayID,replayAccess '+
      ' FROM duels_new WHERE id<='+inttostr(maxID)+' ORDER BY id');
     if db.lastError='' then
      db.Query('DELETE FROM duels_new WHERE id<='+inttostr(maxID));
    end;
   end;
   LogMsg('DB: duels moved',logNormal);
   // Перенести все строки из eventlog_new в eventlog
   sa:=db.Query('SELECT max(id) FROM eventlog_new');
   if db.rowCount>0 then begin
    maxID:=StrToIntDef(sa[0],0);
    if maxID>0 then begin
     db.Query('INSERT INTO eventlog (created,playerid,event,info) '+
      ' SELECT created,playerid,event,info '+
      ' FROM eventlog_new WHERE id<='+inttostr(maxID)+' ORDER BY id');
     if db.lastError='' then
      db.Query('DELETE FROM eventlog_new WHERE id<='+inttostr(maxID));
    end;
   end;
   LogMsg('DB: events moved',logNormal);
  end;

 procedure HourlyMaintenance;
  begin
   if SPARE_SERVER then exit;
   LogMsg('Hourly maintenance',logImportant);
   db.Query('DELETE FROM chatmsg WHERE created<DATE_SUB(NOW(),INTERVAL 30 DAY)');
  end;

 procedure DailyMaintenance;
  begin
   LogMsg('Daily maintenance',logImportant);
   UpdateQuestsForOnlineUsers;
   UpdateMarketForOnlineUsers;
   UpdateGuilds;
   if SPARE_SERVER then exit;
   db.Query('DELETE FROM users_ban WHERE date<Now()');
   db.Query('DELETE FROM serverstat WHERE time<DATE_SUB(NOW(),INTERVAL 10 DAY) '+
     'AND time>DATE_SUB(NOW(),INTERVAL 20 DAY) '+
     'AND (MINUTE(time) MOD 5>0)');
   if DayOfWeek(Now)=2 then WeeklyDecreaseFame;
  end;

 procedure GetPlayerProfile(userID:integer;name:UTF8String);
  var
   sa:AStringArr;
   title,level,fame,greatHero:integer;
   plr:TPlayerRec;
  begin
   if not IsValidUserID(userID,true) then exit;
   LogMsg('Player profile request: '+name+' for '+users[userid].name,logInfo);
   sa:=db.Query('SELECT name,guild,avatar,customFame,customLevel,customWins,customLoses,'+
     'classicFame,classicLevel,classicWins,classicLoses,'+
     'draftFame,draftLevel,draftWins,draftLoses,level,campaignWins,CardsCount(cards) FROM players WHERE name="'+SqlSafe(name)+'"');
   if db.rowCount=1 then begin
    plr.customFame:=StrToIntDef(sa[3],0);
    plr.customLevel:=StrToIntDef(sa[4],1);
    plr.customWins:=StrToIntDef(sa[5],0);
    plr.customLoses:=StrToIntDef(sa[6],0);
    plr.classicFame:=StrToIntDef(sa[7],0);
    plr.classicLevel:=StrToIntDef(sa[8],1);
    plr.classicWins:=StrToIntDef(sa[9],0);
    plr.classicLoses:=StrToIntDef(sa[10],0);
    plr.draftFame:=StrToIntDef(sa[11],0);
    plr.draftLevel:=StrToIntDef(sa[12],1);
    plr.draftWins:=StrToIntDef(sa[13],0);
    plr.draftLoses:=StrToIntDef(sa[14],0);
    fame:=CalcPlayerFame(plr.customFame,plr.classicFame,plr.draftFame);
    level:=CalcLevel(fame); //StrToIntDef(sa[15],1);
    greatHero:=0;
    if sa[16]='20' then greatHero:=1;
    title:=CalcPlayerTitle(StrToIntDef(sa[16],0),StrToIntDef(sa[17],0));
    PostUserMsg(userID,FormatMessage([15,sa[0],sa[1],title,greatHero,sa[2],
      plr.customWins+plr.classicWins+plr.draftWins,plr.customWins,plr.classicWins,plr.draftWins,
      plr.customLoses+plr.classicLoses+plr.draftLoses,plr.customLoses,plr.classicLoses,plr.draftLoses,
      fame,plr.customFame,plr.classicFame,plr.draftFame,
      level,plr.customLevel,plr.classicLevel,plr.draftLevel]));
   end;
  end;

 procedure SaveServerStat;
  var
   stat:TServerStat;
  begin
   if SPARE_SERVER then exit;
   EnterCriticalSection(gSect);
   try
    stat:=serverStat;
   finally
    LeaveCriticalSection(gSect);
   end;
   with stat do
    db.Query('INSERT INTO serverstat (conCnt,uCnt,human,duels,drafts,cpuLoad,cpuKernel,cpuUser,maxQueue,memUsed)'+
      ' values(%d,%d,%d,%d,%d,%d,%d,%d,%d,%d)',
      [connections,users,usersAlive,duels,drafts,cpuTotal,cpuUsageKernel,cpuUsageUser,maxQueue,memoryUsed div 1024]);
  end;

 // HTTP GET cmd?action=grantpremium&player=PlrName&p1=amount&p2=paymentID&sign=EA62A85345BE
 // p3=reason
 // action=finishcaravan&p1=gID - прибить караван указанной гильдии
 function ExecCommand(action,sign,player,p1,p2,p3:UTF8String):UTF8String;
  var
   userID,amount,id,v,i,g,m:integer;
   sa,sb,sc:AStringArr;
   reason:UTF8String;
  begin
   result:='FAILURE';
   LogMsg('ExecCommand(%s,%s,%s,%s,%s,%s)',[action,sign,player,p1,p2,p3],logImportant);
   try
   action:=lowercase(action);
   if sign='EA62A85345BE' then begin
    // Premium
    if action='grantpremium' then begin
     amount:=StrToIntDef(p1,0);
     id:=StrToIntDef(p2,0);
     reason:='Purchase '+IntToStr(id);
     if p3<>'' then reason:=p3;
     gSect.Enter;
     try
      userID:=FindUser(player);
      if userID>0 then GrantPremium(userID,amount,reason);
     finally
      gSect.Leave;
     end;
     if userID<=0 then  GrantPremiumToOfflinePlayer(player,amount,reason);
     db.Query('UPDATE payments SET completed=2 WHERE id='+IntToStr(id));
     result:='OK';
    end;
    // Gems
    if action='grantgems' then begin
     amount:=StrToIntDef(p1,0);
     id:=StrToIntDef(p2,0);
     reason:='Purchase '+IntToStr(id);
     if p3<>'' then reason:=p3;
     gSect.Enter;
     try
      userID:=FindUser(player);
      if userID>0 then begin
       Grant(userID,ppGems,amount,reason);
       NotifyUserAboutGoldOrGems(userID);
      end;
     finally
      gSect.Leave;
     end;
     if userID<=0 then GrantGemsToOfflinePlayer(player,amount,reason);
     db.Query('UPDATE payments SET completed=2 WHERE id='+IntToStr(id));
     result:='OK';
    end;
    // Gold
    if action='grantgold' then begin
     amount:=StrToIntDef(p1,0);
     id:=StrToIntDef(p2,0);
     reason:='Purchase '+IntToStr(id);
     if p3<>'' then reason:=p3;
     gSect.Enter;
     try
      userID:=FindUser(player);
      if userID>0 then begin
       Grant(userID,ppGold,amount,reason);
       NotifyUserAboutGoldOrGems(userID);
      end;
     finally
      gSect.Leave;
     end;
     if userID<=0 then GrantGoldToOfflinePlayer(player,amount,reason);
     db.Query('UPDATE payments SET completed=2 WHERE id='+IntToStr(id));
     result:='OK';

     // Patronage perk - +10% золота в гильдию
     sa:=db.Query('SELECT guilds.id,guilds.bonuses FROM guilds,players '+
      ' WHERE guilds.name=players.guild AND players.name="'+SqlSafe(player)+'"');
     if db.rowCount=1 then
      if sa[1][11]='1' then begin
       id:=StrToInt(sa[0]);
       v:=round(amount*0.1);
       db.Query('UPDATE guilds SET treasures=treasures+'+inttostr(v)+' WHERE id='+sa[0]);
       sb:=db.Query('SELECT treasures FROM guilds WHERE id='+sa[0]);
       db.Query('UPDATE guildmembers SET treasures=treasures+'+inttostr(v)+' WHERE playerID='+inttostr(FindPlayerID(player)));
       sc:=db.Query('SELECT guild,treasures FROM guildmembers WHERE playerID='+inttostr(FindPlayerID(player)));
       gSect.Enter;
       try
        for i:=1 to high(guilds) do
         if guilds[i].id=id then begin
          guilds[i].treasures:=StrToInt(sb[0]);
          PostGuildMsg(i,FormatMessage([122,2,guilds[i].treasures]));
         end;
        if length(sc)=2 then begin
         g:=FindGuildByID(StrToInt(sc[0]));
         if g>0 then begin
          m:=guilds[g].FindMember(player);
          if m>=0 then begin
           guilds[g].members[m].treasures:=StrToInt(sc[1]);
           PostGuildMsg(g,'122~7~'+guilds[g].FormatMemberInfo(m),'Patronage');
          end;
         end;
        end;
       finally
        gSect.Leave;
       end;
      end;
    end; // grantgold

    // Debug commands
    if action='testai' then begin
     p1:='Logs\DuelSave'+p1;
     if not FileExists(p1) then exit;
     TestAI(p1);
     result:='OK';
    end; // test ai
    // For testing
    if action='decreasefame' then begin
     WeeklyDecreaseFame;
     result:='OK';
    end;

    if action='finishcaravan' then begin
     g:=StrToInt(p1);
     gSect.Enter;
     try
      for i:=1 to 2 do
       if guilds[g].caravans[i].running then
        for m:=1 to 8 do
         if guilds[g].caravans[i].battles[m]<2 then guilds[g].caravans[i].battles[m]:=3;
     finally
      gSect.Leave;
     end;
    end;

   end;
   except
    on e:exception do LogMsg('Error in ExecCommand: '+ExceptionMsg(e),logWarn);
   end;
  end;

 procedure UpdateSteamAchievements(userID:integer);
  var
   i,n,level,wins,loses,owncards:integer;
   steamID:int64;
   missions:array[1..200] of integer;
   data,url:UTF8String;
   params:AStringArr;
   name:array[1..100] of UTF8String;
   value:array[1..100] of integer;
  procedure Add(newname:UTF8String;newvalue:integer);
   begin
    if newvalue=0 then exit;
    inc(n);
    name[n]:=newname;
    value[n]:=newvalue;
   end;
  begin
   gSect.Enter;
   try
    if not IsValidUserID(userID) then exit;
    steamID:=users[userID].steamID;
    owncards:=users[userID].OwnedCardsCount;
    fillchar(missions,sizeof(missions),0);
    for i:=low(users[userid].missions) to high(users[userid].missions) do begin
     missions[i]:=users[userID].missions[i];
     if missions[i]<0 then begin
      if MissionsInfo[i].MaxProgress>0 then
       missions[i]:=MissionsInfo[i].MaxProgress
      else
       missions[i]:=1;
     end;
    end;
    level:=users[userid].level;
    wins:=users[userid].customWins+users[userid].classicWins+users[userid].draftWins;
   finally
    gSect.Leave;
   end;
   LogMsg('Posting Steam achievements for %s SteamID=%s',[users[userid].name,IntToStr(steamID)],logInfo);
   // Сформировать список значений всех ачивок
   n:=0;
   // Stats
   Add('level',level);
   Add('wins',wins);
   if wins>=10 then Add('2',1);
   Add('caravans',missions[5]);
   if missions[5]>=3 then Add('5',1);
   Add('vampires',missions[8]);
   if missions[8]>=100 then Add('8',1);
   Add('elves',missions[9]);
   if missions[9]>=100 then Add('9',1);
   Add('quests',missions[21]);
   if missions[21]>=5 then Add('21',1);
   // Achievements
   Add('1',missions[1]);  // Defeat an opponent by dealing more than 20 damage with your final hit.
   Add('3',missions[3]);  // Join an existing guild, or create a new guild
   Add('4',missions[4]);  // Successfully defend your guild caravan from the attack of another player
   Add('6',missions[6]);  // Win a Draft Tournament in the Online League
   Add('7',missions[7]);  // Defeat an opponent using the attack of a Sheep as your final hit
   Add('22',missions[22]); // Defeat a Quest opponent with 50 or more life remaining
   Add('23',missions[23]); // Complete a Quest using a deck that contains no Spells
   Add('24',missions[24]); // Complete a Quest using a deck that contains no Creatures
   Add('25',missions[25]); // Defeat a Quest opponent after summoning 3 Dragons during the battle
   Add('26',missions[26]); // Defeat a Quest opponent with 6 ally creatures on the board at the end of the battle
   Add('27',missions[27]); // Defeat a Quest opponent with no ally creatures on the board at the end of the battle

   // Коллекционер
   Add('cards',owncards);
   if owncards>=100 then Add('45',1);
   if owncards>=200 then Add('46',1);
   if owncards>=300 then Add('47',1);
   if owncards>=400 then Add('48',1);
   // Сформировать запрос
   SetLength(params,0);
   AddString(params,'key='+STEAM_API_KEY);
   AddString(params,'steamid='+IntToStr(steamID));
   AddString(params,'appid=488910');
   AddString(params,'count='+inttostr(n));
   for i:=1 to n do begin
    AddString(params,'name['+inttostr(i-1)+']='+name[i]);
    AddString(params,'value['+inttostr(i-1)+']='+IntToStr(value[i]));
   end;
   data:=join(params,'&');
   url:='https://partner.steam-api.com/ISteamUserStats/SetUserStatsForGame/v0001/';
   LogMsg('CURL: '+data,logDebug);
   LaunchProcess('curl.exe','-s -g --data "'+data+'" '+url);
  end;

 // Вызывается ВНЕ gSect
 function ExecAsyncTask(CRID:integer;userID:integer;request:UTF8String):UTF8String;
  var
   sa:AStringArr;
   r:integer;
  begin
   result:='';
   try
    if CRID<>0 then CheckConIndex(CRID);
    currentCon:=CRID;
    sa:=SplitA('~',request,'_');
    if (length(sa[0])=2) then begin
     r:=StrToIntDef(sa[0],0);
     if r>0 then begin
      result:=HandleUserAsyncMsg(userID,r,sa);
      exit;
     end;
    end;
    sa[0]:=UpperCase(sa[0]);
    if sa[0]='AI' then LaunchAI(userID,StrToInt(sa[1])) else
    if sa[0]='CHECKEMAIL' then result:=CheckEmail(CRID,sa[1]) else
    if sa[0]='CHECKNAME' then result:=CheckName(CRID,sa[1]) else
    if sa[0]='SETCURDECK' then DB.Query('UPDATE players SET curDeck='+sa[1]+' WHERE id='+sa[2]) else
    if sa[0]='SAVECHATMSG' then DB.Query('INSERT INTO chatmsg (%s) values(%s)',[sa[1],sa[2]]) else
    if sa[0]='UPDATEPLAYERSTATS' then UpdatePlayerStats(userID,StrToIntDef(sa[1],0),
      StrToInt(sa[2]),StrToInt(sa[3]),StrToInt(sa[4]),StrToInt(sa[5]),StrToInt(sa[6])) else
    if sa[0]='DUELREC' then AddDuelRec(sa[1],sa[2],sa[3],sa[4],sa[5],sa[6],sa[7],sa[8],sa[9],sa[10],sa[11],sa[12],sa[13],sa[14],sa[15]) else
    if sa[0]='EVENTLOG' then AddEventLog(StrToIntDef(sa[1],0),sa[2],sa[3]) else
//    if sa[0]='SETROOM' then SetPlayerRoom(StrToInt(sa[1]),StrToInt(sa[2])) else
    if sa[0]='UPDATEPLAYER' then DB.Query('UPDATE players SET '+sa[2]+' WHERE id='+sa[1]) else
    if sa[0]='UPDATEGUILD' then DB.Query('UPDATE guilds SET '+sa[2]+' WHERE id='+sa[1]) else
    if sa[0]='UPDATEGUILDMEMBER' then DB.Query('UPDATE guildmembers SET '+sa[2]+' WHERE playerID='+sa[1]) else
    if sa[0]='GRANTCARD' then DB.Query('UPDATE players SET cards="'+sa[2]+'" WHERE id='+sa[1]) else
    if sa[0]='GETPLAYERPROFILE' then GetPlayerProfile(userID,sa[1]) else
    if sa[0]='LOGIN' then result:=Login(userID,sa[1],sa[2],sa[3]) else
    if sa[0]='SETSTEAMACHIEVEMENTS' then UpdateSteamAchievements(userID) else
    if sa[0]='PLAYEROFFLINE' then SetPlayerOffline(StrToInt(sa[1]),sa[2],sa[3]) else
    if sa[0]='CLIENTINFO' then SaveClientInfo(StrToInt(sa[1]),sa[2]) else
    if sa[0]='DBQUERY' then DB.Query(sa[1]) else
    if sa[0]='JOINGUILD' then JoinGuild(userID,sa[1],sa[2],sa[3]);
    if sa[0]='CMD' then result:=ExecCommand(sa[1],sa[2],sa[3],sa[4],sa[5],sa[6]) else
    if sa[0]='NEWACC' then result:=CreateAccount(userID,sa[1]) else
    if sa[0]='BOTDUEL' then ExecBotDuel(StrToInt(sa[1]),StrToInt(sa[2])) else
//    if sa[0]='SENDEMAIL' then SendVerificationEmail(sa[1],sa[2],sa[3]) else
    if sa[0]='SAVESERVERSTAT' then SaveServerStat else
    if sa[0]='NEWGUILD' then CreateGuildData(userID,sa[1],StrToInt(sa[2]),StrToInt(sa[3])) else
    if sa[0]='RELOADGUILD' then ReloadGuild(StrToInt(sa[1])) else
    if sa[0]='SERVERSHUTDOWN' then ShutdownServer else
    if sa[0]='DB_MAINTENANCE' then DatabaseMaintenance else
    if sa[0]='INITSERVERDATA' then InitServerData else
    if sa[0]='HOURLY_MAINTENANCE' then HourlyMaintenance else
    if sa[0]='CARRYGOLDOUT' then CarryGoldOut(sa[1],StrToInt(sa[2]),StrToInt(sa[3])) else
    if sa[0]='DAILY_MAINTENANCE' then DailyMaintenance else
    if sa[0]='INCREMENTPLAYERTOURWINS' then
      DB.Query('UPDATE players SET draftTourWins=draftTourWins+1 WHERE id='+sa[1]);

   except
    on e:exception do begin
     LogMsg('Error in request "'+sa[0]+'" from user: '+inttostr(userID)+': '+ExceptionMsg(e),logError);
     result:='ERROR: internal request error';
    end;
   end;
  end;
  

function BuildUsersList:UTF8String;
 var
  i:integer;
  prem:UTF8String;
 begin
  // Main users
  result:='users=new Array(""';
  for i:=1 to high(users) do
   if users[i]<>nil then
    with users[i] do begin
     if premium>now then prem:=HowLong(premium)
      else prem:='-';
     result:=result+Format(',"%d|%d|%s|%s|%s|%d|%s|%s|%s|%d|%s|%s|%s|%d|%d/%d|%d|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%s"',
       [userID,playerID,name,email,MakeUserFlags(flags),avatar,IP,country,HowLong(IdleSince),connected,
        HowLong(autoSearchStarted[dtCustom]),HowLong(autoSearchStarted[dtClassic]),HowLong(autoSearchStarted[dtDraft]),
        gold,heroicPoints,needHeroicPoints,astralPower,prem,
        customFame,customLevel,classicFame,classicLevel,draftFame,draftLevel,level,
        botLevel,gems,draftID,room,guild]);
    end;
  result:=result+');'+#13#10;
 end;

function BuildGamesList:UTF8String;
 var
  i:integer;
 begin
  result:='games=new Array(""';
  for i:=1 to high(games) do
   with games[i] do
    if (games[i].user1>0) and (games[i].user2>0) then begin
     result:=result+Format(',"%d|%d|%d|%d|%d|%d|%d|%s|%s|%d|%s|%d"',
       [i,user1,user2,byte(gametype),byte(gameclass),turn,turns,
        HowLong(turnStarted),HowLong(gameStarted),byte(finished),HowLong(turnTimeout),scenario]);
   end;
  result:=result+');'#13#10;
 end;

function BuildDraftsList:UTF8String;
 var
  i:integer;
 begin
  result:='drafts=new Array(""';
  for i:=1 to high(drafts) do
   with drafts[i] do
    if (drafts[i].players[1]>0) then begin
     result:=result+Format(',"%d|%d|%d|%d|%d|%d|%d|%s|%s|%s"',
       [i,players[1],players[2],players[3],players[4],stage,round,
        HowLong(created),HowLong(started),HowLong(timeout)]);
   end;
  result:=result+');'#13#10;
 end;

function BuildCaravansList:UTF8String;
 var
  i,j,k:integer;
 begin
  result:='caravans=new Array(""';
  for i:=1 to high(guilds) do
   for j:=1 to 2 do
    with guilds[i] do
     if (caravans[j].running) then begin
      result:=result+Format(',"%s|%d|%s',[name,j,HowLong(caravans[j].launched)]);
      with caravans[j] do
       for k:=1 to 8 do
        result:=result+Format('|%d %6s A=[%s] D=[%s]',[battles[k],HowLong(needBattleIn[k]),attackers[k],defenders[k]]);
      result:=result+'"';
     end;
  result:=result+');'#13#10;
 end;

procedure FillAdminPage(var page:UTF8String);
 var
  data:UTF8String;
 begin
  data:=BuildUsersList+#13#10+BuildGamesList+#13#10+BuildDraftsList+#13#10+BuildCaravansList;
  page:=StringReplace(page,'#DATA_BLOCK#',data,[]);
 end;

var
 digest:UTF8String;
 cards:array[1..100] of smallint;
 st:UTF8String='35307E36387EC295C2ABC280C2846F66C29C2E6E366D7453C2B7C2894E77C2B17E5C5C6E';
 sa:AStringArr;
 i:integer;
initialization
 // Init cardinfo
 cardInfo:=DefCardInfo;
 digest:=CardInfoDigest;
 cardInfoHash:=MD5(digest[1],length(digest));
 SetLength(cardInfoHash,10);
 digest:='';

 // Fake user
 users[0]:=TUser.Create(0);
 with users[0] do begin
  playerID:=0;
  name:='Nobody';
 end;

end.

