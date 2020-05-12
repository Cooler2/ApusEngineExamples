// Ключевые типы и массивы данных, хранящие игро-специфические вещи
{$R+}
unit gameData;
interface
 uses globals,MyServis,cnsts,ULogic,UDraftLogic,Classes,structs,database;
 const
  // User flags
  ufAdmin = 1;  // A
  ufModerator = 2; // M
  ufUnverified = 4; // U (email not verified)
  ufSilent  = 8;  // S  (can't chat)
  ufBanned  = 16;  // B (can't play)
  ufBot     = 32;  // #
  ufBonus50 = 64;         // % - единовременный бонус 50% при покупке золота или премиума
  ufInvalidEmail =128; // I (invalid email)
  ufHardMode         = $0100; // h - hard mode
  ufCanMakeDecks     = $0400; // d
  ufCanReplaceCards  = $0800; // r
  ufHasRitualOfPower = $1000; // p
  ufHasManaStorm     = $2000; // m
  ufAdvGuildExp      = $4000; // g
  ufNotPlayed        = $8000; // n (never started campaign)
  ufGoodnight        = $10000; // G - разрешена отправка рекламных сообщений Goodnight

  UNSENT_RESPONSE = '#UNSENT#';

  GUILDBASE = 10000000;

  CallToPowers:array[1..6] of AnsiString=('12','34','14','23','24','13');

  titleMage         = 2;
  titleAdvancedMage = 3;
  titleExpertMage   = 4;
  titleMagister     = 5;
  titleArchmage     = 6;

 type
  // Game types
  TDuelType=(
    dtNone     = 0, // also used for "Total" level/fame/rank etc...
    dtCustom   = 1,
    dtClassic  = 2,
    dtDraft    = 3,
    dtCampaign = 4);

  TDuelClass=(
   dcRated     = 0,  // обычный рейтинговый бой
   dcTraining  = 1,  // тренировка
   dcCaravan   = 2); // грабёж каравана

  TFriendStatus=(
    fsOffline = 0,
    fsOnline  = 1,
    fsInDuel  = 2);

  TPlayerStatus=(
   psDefault    = 0,
   psInCampaign = 1,
   psInDraft    = 2,
   psInCombat   = 3,
   psAFK        = 4,
   psOnline     = 5,
   psWatching   = 6,
   psOffline    = 9);

  TPlayerParam=(ppGold,ppHP,ppAP,ppGems);    
    
  THashStr=string[11];

  // кол-во карт в наличии (отрицательное число - улучшенные карты)
  TCardSet=array[1..numCards] of shortint;

  TUser=class;

  // Колода, хранимая на сервере в БД
  TGameDeck=record
   deckID:integer; // ключ в БД
   name:AnsiString;
   cost:integer;
   cards:array[1..50] of smallint;
   function IsValidForUser(const user:TUser):AnsiString; // проверяет допустимость колоды для юзера, возвращает описание причины недоступности
  end;

  TProposal=record
   userID:integer; // кому предложение
   gametype:TDuelType; // какого типа предложение
  end;

  // Кэшированная информация об игроке
  TPlayerRec=record
   name:string[23];
   guild,email:AnsiString;
   customFame,customLevel,customWins,customLoses,customPlace:integer;
   classicFame,classicLevel,classicWins,classicLoses,classicPlace:integer;
   draftFame,draftLevel,draftWins,draftLoses,draftPlace:integer;
   totalFame,totalLevel,place,campaignWins:integer;
   status:TPlayerStatus;
   lastVisit:TDateTime; // когда последний раз был онлайн
  end;

{  // Информация о сыгранном бое (эквивалент записи в таблице duels)
  TDuelRec=record
   dueltype,scenario:byte;
   winner,loser:integer;
   date:TDateTime;
  end;}

  TUser=class
   userID,playerID:integer;  // playerID>0 - живой игрок, иначе - бот
   steamID:int64; // ID игрока в Стиме
   logged:TDateTime; // когда создан объект
   // кэширование ответов
   lastPostSerial,lastPollSerial:cardinal;
   lastPollResponse:AnsiString; // До отправки содержит строку "#UNSENT#"
   lastCommand:TDateTime; // время поступления последней команды от юзера (используется для определения AFK)

   name,email:AnsiString;
   guild:AnsiString;
   avatar:integer;
   flags:cardinal;
   PwdHash:THashStr; // начало хэша двойного пароля (если авторизован)
   messages:AnsiString; // буфер исходящих сообщений для юзера
   msgCount:integer; // кол-во сообщений в messages
   sendASAP:boolean; // следует ли отправить исходящие сообщения сразу же, или можно подождать? (до 30 секунд)
   timeOut:int64; // момент, после которого юзера нужно удалить по таймауту
   autoSearchStarted:array[TDuelType] of TDateTime;
   boostLevel:array[tDuelType] of integer; // +/- к уровню по итогам предыдущих боёв для автопоиска
   connected:integer; // с кем соединён (в дуэли)
   draftID:integer; // турнир (0 - не в турнире) 
   IP:AnsiString; // IP, с которого поступил последний запрос
   country:String[3]; // страна (определяется по IP при логине)
   idleSince:TDateTime; // время поступления последнего запроса от юзера
   lang:String[3];  // язык клиента
   botLevel:shortint;  // 0 - not a bot, 1..5 - от новичка до архмага
   botThinking:boolean; // код AI запущен
   thinktime:integer; // время, затраченное на размышления в бою (в секундах)
   inCombat:boolean; // в отличие от connected этот флаг сохраняется до получения 37-го запроса от игрока

   gold,heroicPoints,needHeroicPoints,astralPower,gems,optionsflags:integer;
   friendlist,blacklist:AStringArr;
   premium:TDateTime; // Время завершения премиума (либо 0 - если его нет)
   customFame,customLevel,classicFame,classicLevel,draftFame,draftLevel,trainFame,level:integer;
   customWins,customLoses,classicWins,classicLoses,draftWins,draftLoses,draftTourWins:integer;
   initialHP,speciality:integer; // стартовая жизнь и выбранный игроком класс
   curDeckID:integer; // DeckID текущей деки юзера в decks (0 - random)
   decks:array of TGameDeck; // 1..N, ([0] - не используется)
   ownCards:TCardSet; // кол-во карт каждого типа, имеющихся у игрока (без учёта гильдейских), отрицательное число - заапгрейдженые карты
   campaignWins:integer;
   room:integer; // 1 - campaign, 2 - multiplayer
   quests:array[1..6] of integer; // соперники в кампании либо квесты
   updateQuests:boolean; // необходимо обновить квесты после ближайшего боя (любого типа)
   campaignLoses:array[1..20] of integer;
   playingDeck:AnsiString; // если игрок в кастом дуэли - здесь его колода
   lastLogin:TDateTime;
   proposals:array of TProposal;
   missions:array[1..40] of integer; // Отрицательное число - миссия выполнена (в БД обозначается плюсиком)
   lastlognum:integer; // цифра для имени файла для сохранения game.log клиента
   status:TPlayerStatus;
   marketCards:array[1..6] of integer; // Карты в маркете (отрицательное число - карта куплена)
   lastChatMsgTime:int64; // момент последней отправки чат-сообщения (MyTickCount)
   chatFlood:integer; // вес флудинга
   chatMode:byte; // 0..2 - фильтр чата (default = 1)
   caravanPriority:integer;
   lastDuelFinished:TDateTime; // время авершения последнего боя этим игроком
   dontLogUntil:TDateTime; // время, раньше которого юзер не рассматривается в качестве атакующего (вернее, причина не пишется в лог)

   tipsShown:array[1..20] of byte;
   currentTip:integer; // индекс подсказки, которая выбрана и отправлена клиенту для показа при следующем автопоиске
   lastTip:integer; // предыдущая подсказка (для избежания повторов)
   maxBotLevel,curBotLevel:byte; // уровни ботов в тренировках
   timeoutWarning:boolean; // устанавливается, если игрок получил предупреждение о 15 сек до таймаута
   trackPlayersStatus:boolean; // получать ли 76-й пакет об изменениях статуса
   lastAdMsg:TDateTime; // когда последний раз получал сообщение с рекламой

   function FindDeckByName(name:AnsiString):integer; // возвращает индекс в массиве
   function FindDeckIDByName(name:AnsiString):integer;
   function FindDeckByID(deckID:integer):integer; // возвращает индекс в массиве
   constructor Create(ID:integer);
   destructor Destroy; override;
   function GetUserInfo:AnsiString; // текстовое описание юзера
   function GetUserDump:AnsiString;  // подробное описание юзера
   function GetUserFullDump:AnsiString;  // полное описание юзера
   function OwnedCardTypes:integer; // сколько различных карт имеет игрок
   function OwnedCardsCount:integer; // сколько всего карт имеет игрок (включая повторы)
   function GetUserTitle:integer;
   procedure SetQuests(st:AnsiString);
   function GetQuests:AnsiString;
   function QuestsCount:integer;
   function HasQuest(n:integer):boolean;
   function HasManaStorm:byte; // 0 or 1
   procedure SetCampaignLoses(st:AnsiString);
   function GetCampaignLoses:AnsiString;
   function SaveAsString:AnsiString;
   // Применяет бонус к fame указанного типа и возвращает что в итоге получится
   procedure PreviewStats(dueltype:TDuelType;fameBonus:integer;out newFame,newLevel,newTotalLevel:integer);
   // Возвращает стоимость боя указанного типа в кристаллах
   function GetCostForMode(mode:TDuelType;forcePremium:integer=0):integer;
   function GetActualLevel(gametype:TDuelType):integer; // Актуальный (соответствующий славе) уровень
   function GetFame(gametype:TDuelType):integer;
   function FindFriend(name:AnsiString):integer; // -1 - not found
   function FindInBlacklist(name:AnsiString):integer; // -1 - not found
   function FindProposal(uid:integer;mode:TDuelType):integer;
   procedure DeleteProposal(idx:integer);
   procedure AddProposal(uid:integer;mode:TDuelType);
   // Импорт/экспорт миссий
   procedure MissionsFromStr(st:AnsiString);
   function MissionsToStr:AnsiString;
   function GetPlayerRec:TPlayerRec;
   // Определяет статус юзера, записывает его в поле status, а также возвращает
   function UpdateUserStatus(forceStatus:TPlayerStatus=psDefault):TPlayerStatus;
   procedure UpdatePlayerData; // Обновляет информацию в allPlayers
   // Market cards
   procedure ImportMarket(st:AnsiString);
   // Может ли игрок в настоящий момент получить награду за 1-ю победу в классике?
   function CanGetRewardForClassic:boolean;
   function CanPlayTrainingWithBot:boolean;
   // Может ли играть с указанным игроков (не может, если последние два рейтинговых боя такого же типа были с этим же игроком)
   function CanPlayWithPlayer(plrID:integer;dt:TDuelType):boolean;

   function APlimit:integer; // максимальный AP с учётом перков
   procedure LoadTips(st:AnsiString);
   function TipsToStr:AnsiString;
   procedure SelectAndSendTip;
   procedure UseTipAndSelectAnother;

   function MaxCardInstances:integer; // сколько экземпляров одной карты может иметь (3/6)
   function StartLifeBoost:integer; // Кол-во дополнительной жизни в кастоме
  end;

  TGame=record
   user1,user2:integer;  // если нули - игры нет, если user2=0 - игра с ботом
   gametype:TDuelType;  // 1,2,3,4
   scenario:integer; // если gametype=dtCampaign, то тут номер противника/квеста
   withBot:boolean; // хотя бы один из игроков - бот
   reward:integer; // Награда за победу (в кампании/квесте)
   gameclass:TDuelClass;
   firstPlayer:byte; // 1 или 2 (user1 или user2 ходит первым)
   turn:byte; // чей сейчас ход: 1 или 2 (0 - бой не стартовал)
   turns:integer; // сколько ходов уже сделано
   turnStarted,gameStarted,turnTimeout:TDateTime; // время начала хода / создания игры / когда завершить по таймауту
   numActions:shortint; // кол-во действий сделанных игроком за ход
   timeout_flag:boolean; // посылалось ли предупреждение о таймауте
   finished:boolean; // игра потенциально закончена, но результат еще неизвестен
   time1,time2:integer; // время (в секундах) потраченное игроками
   powers1,powers2:byte; // Какие стихии использует 1 и 2 игроки
   // объект данных игры
   duelsave:tDuelSave;
   duelSaveHash:int64;
   //usedcards:array[1..numcards] of byte; // 0-й бит - игрок user1, 1-й - игрок user2
   gamelog:AnsiString;
   savelog:boolean; // флаг необходимости сохранения лога
   replayData:ByteArray;
   procedure SetTurnTo(userID:integer);
   function CalcTurnTimeout:double;
   procedure Clear; // очищает запись
   procedure SaveInitialState; // Сохранить начальное состояние дуэли в replayData
   procedure SaveTurnData(buf:array of integer);
   function SaveReplay:integer;
  private
   procedure AppendBytes(var bytes;count:byte);
  end;

  // Драфтовый турнир
  TDraft=record
   players:array[1..4] of integer; // userID участников драфта
   stage,round:integer; // stage=1 - вытягивание карт, 2 - создание колод, 3 - игра
   created,started,timeout,
    timeX:TDateTime; // момент начала выбора очередной карты или момент начала составления колоды
   draftInfo:TDraftGeneralInfo;

   function ReadyForNextCard:boolean; // Можно посылать наборы карт для выбора
   function ReadyForNextRound:boolean; // true - можно стартовать бои очередного раунда
   function NoPlayersAlive:boolean; // true - если остались только боты

   procedure PlayerTookCard(userID,card:integer);
   function PlayerMadeDeck(userID:integer;cards:AnsiString):integer; // 0 - OK, else - wrong card
   function GetDraftPlayer(userID:integer):PDraftPlayer;
  end;

  // запись из таблицы duels (20 байт)
  TDuelRec=record
   winner,loser:integer;
   date:TDateTime;
   dueltype,scenario,turns,firstplr:byte;
  end;

  TGuildMember=record
   playerID:integer;
   name:AnsiString;
   rank,rewards:shortint; // ранг и кол-во полученных за сутки наград
   powers:String[2]; // Call to Powers
   treasures,exp:integer; // Сколько принёс гильдии
   rew:array[1..3] of integer; // сколько наград каждого типа за Зов получил
   function FormatCallToPowers:AnsiString;
  end;

  TGuildLogRecord=record
   date:TDateTime;
   text:AnsiString;
  end;

  TCaravan=record
   running:boolean;
   launched:TDateTime;
   battles:array[1..8] of shortint; // статус боя: 0 - свободен, 1 - в процессе (*), 2 атака отбита, 3 - атака успешна
   // * это не значит, что сам бой уже идёт - фазы есть разные, нужно смотреть поля ниже
   needBattleIn:array[1..8] of TDateTime; // таймеры слотов (статус 0 - время до перехода к статусу 1, статус 1 - время до старта с ботом)
   propCount:array[1..8] of byte; // сколько раз уже делалось предложение этому слоту
   attackers,defenders:array[1..8] of AnsiString;
   procedure Clear;
   function FormatInfo:AnsiString;
   function FormatBattleUpdate(i:integer):AnsiString;
   function FormatLog:AnsiString;
   procedure RequestActiveSlotIn(time:integer); // запрос на активацию слота через time секунд
   procedure ResetSlot(slot:integer);
  end;

  TGuild=record
   id:integer;
   name,motto:AnsiString;
   size,level,exp,treasures,daily:integer; // daily - сколько побед сегодня еще предстоит сделать, чтобы взять дейлик
   bonuses,cards:String[20]; // '1' - элемент активен
   members:array of TGuildMember;
   log:array of TGuildLogRecord;
   proposals:IntArray; // список playerID, которым предложено вступить в эту гильдию
   caravans:array[1..2] of TCaravan;

   procedure LoadFromDB(db:TMySQLdatabase;condition:AnsiString);
   procedure AddLogMessage(msg:AnsiString);
   function FindMember(plrname:AnsiString;raiseIfNotFound:boolean=false):integer;
   function FindMemberById(plrID:integer;raiseIfNotFound:boolean=false):integer;
   function FormatMemberInfo(m:integer):AnsiString;
   function NumCards:integer;
   function NumBonuses:integer;
   function ExpBonus:single; // мультипликатор получения экспы
   function GetFullDump:AnsiString;
   function NextLaunchTime(kind:integer):TDateTime; // Когда можно будет запустить караван в следующий раз
  end;

 var
//  onEnterMsg:array[0..10] of AnsiString;

  autosearchState:array[TDuelType] of AnsiString; // строка с описанием последнего автопоиска по каждому типу
  uCnt:integer; // кол-во занятых (авторизованных) юзеров
  lockReplays:TMyCriticalSection;
  
  startDecks:array[1..2] of AnsiString;
  startDecksCost:array[1..2] of integer;
  startCardSets:array[1..2] of TCardSet;

  lastDuels:array[0..$FFFF] of TDuelRec; // последние бои (кольцевой список)
  lastDuelsFirst,lastDuelsLast:integer; // номера первого занятого и первого свободного элемента (если совпадают - список пуст)

  allPlayers:array of TPlayerRec;
  allPlayersHash:THash; // (lowercase) playername -> playerID

  guilds:array[0..500] of TGuild; // кэш гильдий ([0] - служебный индекс, валидные >0)

  caravanChallenged:THash; // TDateTime; // когда игроку последний раз предлагали пограбить караван

  statusChanges:AnsiString; // содержимое 76-го ответа об изменениях статуса игроков

  // Индексы в массиве allPlayers (хранятся только игроки с ненулевой славой)
  customRanking,classicRanking,draftRanking,totalRanking:IntArray;

  gd_spe:AnsiString; // content of gd.spe file
 const
  // Начальные колоды
  InitialDecks:array[1..2] of AnsiString=(
   '35,35,31,31,5,75, 75, 70,70,70,38, 38, 38, 65, 65, 65,41, 41, 41,42, 42, 12, 12,43,43',
   '58,72,72,143,143,143,48,48,48,132,132,109,109,127,127,127,87,87,87,128,134,19,19,23,23');

  // Изначально доступные карты (кроме тех, которые уже есть в начальной колоде)
  InitialCards:array[1..2] of AnsiString=(
   '11x2,141x2,35,143x3,134x2,20x2,24x2,28,47x3,128x2,127x2,54,115x2,139,82,107,37,124x2,9x2,84,39,44,12',
   '47x3,51,73,24x2,128,115x2,54,139x2,82x2,70x3,11,12x2,65x3,37,45x2,18x2,41x2,28,20x2,103,134,142');

 procedure InitConsts;
 function GetUserByName(name:AnsiString):integer;
 function FindPlayerID(name:AnsiString):integer; // 0 - если не найден
 function MakeUserFlags(flags:cardinal):AnsiString;
 function ParseUserFlags(st:AnsiString):cardinal;
 function CardSetToStr(cardSet:TCardSet):AnsiString;
 procedure StrToCardSet(st:AnsiString;var cardSet:TCardSet);
 procedure AddLocalDuelRec(date:TDateTime;winner,loser,dueltype,scenario,turns,firstPlr:integer);
 procedure DumpServerData;
 // Строит рейтинг всех игроков заданного типа
 procedure BuildRanking(mode:TDuelType);
 // Обновляет позицию игрока в рейтинге указанного типа
 procedure UpdatePlayerRanking(mode:TDuelType;playerID:integer);

 // Поиск гильдии в кэше по имени
 function FindGuild(name:AnsiString;raiseIfNotFound:boolean=false):integer;
 function FindGuildByID(guildID:integer;raiseIfNotFound:boolean=false):integer;
 function GuildHasPerk(name:AnsiString;idx:integer):boolean;
 // Определяет награду за Call to Powers исходя из имени гильдии и использованных стихий
 // 1 - опыт, 2 - золото, 3 - личная слава
 function GetGuildCtP(name,plrName:AnsiString;powers:byte):integer;
 
 // Находит индекс свободного элемента в кэше гильдий, если свободных нет - освобождает гильдию, игроки которой оффлайн 
 function AllocGuildIndex:integer;

 // Чистит записи кэша гильдий, все игроки которых оффлайн
 procedure FreeOfflineGuilds;

implementation
 uses SysUtils,Logging,ServerLogic,UDeck,NetCommon,UCalculating,workers,CustomLogic;


{ TAstralUser }

constructor TUser.Create(ID: integer);
begin
 messages:='';
 sendASAP:=false;
 msgCount:=0;
 TimeOut:=MyTickCount+10000; // 10 sec initial timeout
 userID:=ID;
 playerID:=0;
 name:=''; email:='';
 avatar:=0;
 lang:='en';
 connected:=0;
 draftID:=0;
 steamID:=0;
 updateQuests:=false;
 autoSearchStarted[dtCustom]:=0;
 autoSearchStarted[dtClassic]:=0;
 autoSearchStarted[dtDraft]:=0;
 boostLevel[dtCustom]:=0;
 boostLevel[dtClassic]:=0;
 boostLevel[dtDraft]:=0;
 country:=''; ip:='';
 botLevel:=0;
 botThinking:=false;
 inc(uCnt);
 logged:=Now;
 lastPostSerial:=0;
 lastPollSerial:=0;
 lastPollResponse:='';
 lastlognum:=random(10);
 lastCommand:=Now;
 lastChatMsgTime:=0;
 chatFlood:=0;
 chatMode:=1;
 status:=psOffline; // будет изменён на online позже, когда все поля будут заполнены
 lastDuelFinished:=0;
 inCombat:=false;
end;

function FindGuild(name:AnsiString;raiseIfNotFound:boolean=false):integer;
var
 i:integer;
begin
 result:=0;
 for i:=1 to high(guilds) do
  if guilds[i].name=name then begin
   result:=i;
   exit;
  end;
 if raiseIfNotFound then
  raise EWarning.Create('Guild "'+name+'" not found!');
end;

function FindGuildByID(guildID:integer;raiseIfNotFound:boolean=false):integer;
var
 i:integer;
begin
 result:=0;
 for i:=1 to high(guilds) do
  if guilds[i].id=guildID then begin
   result:=i;
   exit;
  end;
 if raiseIfNotFound then
  raise EWarning.Create('Guild ID='+IntToStr(guildID)+' not found!');
end;

function GuildHasPerk(name:AnsiString;idx:integer):boolean;
var
 g:integer;
begin
 gSect.Enter;
 try
 result:=false;
 if name='' then exit;
 if (idx<1) or (idx>20) then exit;
 g:=FindGuild(name);
 if g<=0 then exit;
 if guilds[g].bonuses[idx]='1' then result:=true;
 finally
  gSect.Leave;
 end;
end;

function GetGuildCtP(name,plrName:AnsiString;powers:byte):integer;
var
 g,m,p1,p2,cnt,mask:integer;
 fl:boolean;
begin
 result:=0;
 if name='' then exit;
 g:=FindGuild(name);
 if g<=0 then exit;
 with guilds[g] do begin
  m:=FindMember(plrName);
  if m<0 then begin
   LogMsg('Guild member not found! '+plrName+' : '+name,logWarn);
   exit;
  end;
  // Лимит уже достигнут?
  if members[m].rewards>=5 then exit;
  // Проверка использованных стихий
  p1:=StrToInt(members[m].powers[1]);
  p2:=StrToInt(members[m].powers[2]);
  if powers and (1 shl p1)=0 then exit;
  if powers and (1 shl p2)=0 then exit;

  with members[m] do begin
   mask:=0;
   cnt:=rew[1]+rew[2]+rew[3];
   if rew[1]<=cnt*0.4+0.4 then mask:=mask+1;
   if rew[2]<=cnt*0.4+0.4 then mask:=mask+2;
   if rew[3]<=cnt*0.2+0.4 then mask:=mask+4;
   fl:=false;
   if rew[1]>cnt*0.4+2 then fl:=true;
   if rew[2]>cnt*0.4+2 then fl:=true;
   if rew[3]>cnt*0.2+2 then fl:=true;

   if (mask>0) and (fl or (random(10)>1)) then begin
    repeat
     result:=1+random(3);
    until mask and (1 shl (result-1))>0;
    LogMsg('%s CtP mode 1: %d (%d %d %d)',[plrName,result,rew[1],rew[2],rew[3]],logDebug);
   end else begin
    // Выбор награды
    case random(10) of
     0..3:result:=1;
     4..7:result:=2;
     8..9:result:=3;
    end;
    LogMsg('%s CtP mode 2: %d mask=%d %d/%d/%d',
     [plrName,result,mask,rew[1],rew[2],rew[3]],logDebug);
   end;
  end;
 end;
end;

procedure FreeOfflineGuilds;
var
 i,j:integer;
 gCount:integer;
 gList:array[1..MAX_USERS] of AnsiString;
 online:boolean;
 rList:StringArr;
begin
 gSect.Enter;
 try
 // 1. Список гильдий всех онлайн-игроков
 gCount:=0;
 for i:=1 to high(users) do
  if users[i]<>nil then
   if (users[i].playerID>0) and (users[i].guild<>'') then begin
    inc(gCount);
    gList[gCount]:=users[i].guild;
   end;

 // 2. Выбор гильдии, которой нет в списке
 for i:=1 to high(guilds) do begin
  if guilds[i].name='' then continue;
  online:=false;
  for j:=1 to gCount do
   if gList[j]=guilds[i].name then begin
    online:=true; break;
   end;
  if not online then begin
   AddString(rList,guilds[i].name);
   guilds[i].name:='';
   guilds[i].caravans[1].Clear;
   guilds[i].caravans[2].Clear;
   SetLength(guilds[i].log,0);
   SetLength(guilds[i].members,0);
  end;
 end;
 finally
  gSect.leave;
 end;
 LogMsg('Offline guilds removed from cache: '+join(rList,','),logInfo);
end;

function AllocGuildIndex:integer;
var
 i,j,n:integer;
 online:boolean;
begin
 gSect.Enter;
 try
  FreeOfflineGuilds;
  for i:=1 to high(guilds) do
   if guilds[i].name='' then begin
    guilds[i].name:='-%%-';
    result:=i; exit;
   end;
 finally
  gSect.Leave;
 end;
end;

function TUser.FindDeckByName(name: AnsiString): integer;
var
 i:integer;
begin
 result:=0;
 for i:=1 to high(decks) do
  if decks[i].name=name then begin
   result:=i; exit;
  end;
end;

function TUser.FindDeckIDByName(name: AnsiString): integer;
var
 i:integer;
begin
 result:=0;
 for i:=1 to high(decks) do
  if decks[i].name=name then begin
   result:=decks[i].deckID; exit;
  end;
end;

function TUser.FindDeckByID(deckID:integer):integer; // возвращает индекс в массиве
var
 i:integer;
begin
 result:=0;
 for i:=1 to high(decks) do
  if decks[i].deckID=deckID then begin
   result:=i; exit;
  end;
end;

destructor TUser.Destroy;
begin
 messages:='';
 dec(uCnt);
end;

function TUser.GetUserDump: AnsiString;
begin
  result:=Format('%-4d %-5d "%s" %s AS1=%s AS2=%s AS3=%s',[userID,playerID,name,email,
    HowLong(autoSearchStarted[dtCustom]),
    HowLong(autoSearchStarted[dtClassic]),
    HowLong(autoSearchStarted[dtDraft])]);
end;

function TUser.GetUserFullDump: AnsiString;
begin
 try
 result:=Format(' %d;%d;"%s";%d;%d;%d;"%s";"%s";"%s";%d;%d; Car:%d/%s'#13#10,
   [userID,playerID,FormatDateTime('ddddd tt',logged),ord(status),lastPostSerial,lastPollSerial,name,email,guild,avatar,flags,
     caravanPriority,HowLong(caravanChallenged.Get(name))]);


 result:=result+Format('   "%s";"%s";"%s";"%s";%d;%d;"%s";"%s";"%s"',
   [FormatDateTime('ddddd tt',timeout),FormatDateTime('ddddd tt',autosearchStarted[dtCustom]),
    FormatDateTime('ddddd tt',autosearchStarted[dtClassic]),FormatDateTime('ddddd tt',autosearchStarted[dtDraft]),
    connected,draftID,IP,country,FormatDateTime('ddddd tt',IdleSince)]);

 result:=result+Format('   "%s";%d;%d;%d;%d;%d;%d;%d;%d;%x;"%s","%s"'#13#10,
   [lang,botLevel,byte(botThinking),thinkTime,gold,heroicPoints,needHeroicPoints,astralPower,gems,optionsFlags,
    Join(friendlist,','),Join(blacklist,',')]);

 result:=result+Format('   ST:%s;"%s";%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d;%d'#13#10,
   [IntToStr(steamID),FormatDateTime('ddddd tt',premium),customFame,customLevel,classicFame,classicLevel,
    draftFame,draftLevel,level,customWins,customLoses,classicWins,classicLoses,draftWins,draftLoses,
    draftTourWins]);
 except
  on e:exception do result:='UserDump error: '+ExceptionMsg(e);
 end;
end;

function TUser.GetUserInfo: AnsiString;
begin
  result:=Format('%-4d -%5d "%s" %s',[userID,playerID,name,email]);
end;

function TUser.OwnedCardsCount: integer;
var
 i:integer;
begin
 result:=0;
 for i:=low(ownCards) to high(ownCards) do
   inc(result,abs(ownCards[i]));
end;

function TUser.OwnedCardTypes: integer;
var
 i:integer;
begin
 result:=0;
 for i in ownCards do
  if i>0 then inc(result);
end;

function TUser.GetUserTitle:integer;
var
 count:integer;
begin
 count:=OwnedCardsCount;
 result:=CalcPlayerTitle(campaignWins,count);
end;

procedure TUser.SetQuests(st:AnsiString);
var
 sa:StringArr;
 i:integer;
begin
 sa:=split(',',st);
 for i:=1 to high(quests) do quests[i]:=0;
 for i:=1 to min2(length(sa),high(quests)) do
  quests[i]:=StrToIntDef(sa[i-1],0);
end;

function TUser.GetQuests:AnsiString;
var
 i:integer;
begin
 result:=IntToStr(quests[1]);
 for i:=2 to high(quests) do
  result:=result+','+IntToStr(quests[i]);
end;

function TUser.QuestsCount:integer;
var
 i:integer;
begin
 result:=0;
 for i:=1 to high(quests) do
  if quests[i]>40 then inc(result);
end;

function TUser.HasQuest(n:integer):boolean;
begin
 result:=false;
 if n<=0 then exit;
 result:=(n=quests[1]) or (n=quests[2]) or (n=quests[3]) or
   (n=quests[4]) or (n=quests[5]) or (n=quests[6]) or (n=38) or (n=39);
end;

function TUser.HasManaStorm;
begin
 if flags and ufHasManaStorm>0 then result:=1
  else result:=0;
end;

function TUser.SaveAsString: AnsiString;
begin
 result:=#13#10' userid='+inttostr(userid)+
    #13#10' playerid='+inttostr(playerid);

 result:=#13#10'{'+result+#13#10'}'#13#10;
end;

procedure TUser.SetCampaignLoses(st:AnsiString);
var
 i:integer;
 sa:StringArr;
begin
 sa:=split(',',st);
 for i:=1 to high(campaignLoses) do begin
  if i-1<length(sa) then campaignLoses[i]:=StrToIntDef(sa[i-1],0)
   else campaignLoses[i]:=0;
 end;
end;

function TUser.GetCampaignLoses:AnsiString;
var
 i:integer;
begin
 result:=IntToStr(campaignLoses[1]);
 for i:=2 to high(campaignLoses) do
  result:=result+','+IntToStr(campaignLoses[i]);
end;

function TUser.GetCostForMode(mode: TDuelType;forcePremium:integer=0): integer;
begin
 result:=0;
 if mode=dtClassic then result:=4;
 if mode=dtDraft then result:=10;
 if ForcePremium=-1 then exit;
 if (ForcePremium=1) or (premium>Now) then result:=0;
end;

function TUser.GetActualLevel(gametype: TDuelType): integer;
begin
 case gametype of
  dtCustom:result:=CalcLevel(customFame);
  dtClassic:result:=CalcLevel(classicFame);
  dtDraft:result:=CalcLevel(draftFame);
  else result:=CalcLevel(GetFame(dtNone));
 end;
end;

function TUser.GetFame(gametype:TDuelType):integer;
begin
 case gametype of
  dtCustom:result:=customFame;
  dtClassic:result:=classicFame;
  dtDraft:result:=draftFame;
  else result:=CalcPlayerFame(classicFame,customFame,draftFame);
 end;
end;

function TUser.FindFriend(name:AnsiString):integer; // -1 - not found
 var
  i:integer;
 begin
  result:=-1;
  name:=lowercase(name); // такой вариант в 6 раз быстрее, чем AnsiSameText 
  for i:=0 to high(friendlist) do
   if name=lowercase(friendlist[i]) then begin
     result:=i; exit;
   end;
 end;

function TUser.FindInBlacklist(name:AnsiString):integer; // -1 - not found
 var
  i:integer;
 begin
  result:=-1;
  name:=lowercase(name);
  for i:=0 to high(blacklist) do
   if name=lowercase(blacklist[i]) then begin
     result:=i; exit;
   end;
 end;

function TUser.FindProposal(uid:integer;mode:TDuelType):integer;
 var
  i:integer;
 begin
  result:=-1;
  for i:=0 to high(proposals) do
   if (proposals[i].userID=uid) and (proposals[i].gametype=mode) then begin
     result:=i; exit;
   end;
 end;

procedure TUser.DeleteProposal(idx:integer);
 var
  l:integer;
 begin
  l:=length(proposals)-1;
  ASSERT((idx>=0) and (idx<=l));
  proposals[idx]:=proposals[l];
  SetLength(proposals,l);
 end;

procedure TUser.AddProposal(uid:integer;mode:TDuelType);
 var
  l:integer;
 begin
  l:=length(proposals);
  SetLength(proposals,l+1);
  proposals[l].userID:=uid;
  proposals[l].gametype:=mode;
 end;

procedure TUser.PreviewStats(dueltype:TDuelType;fameBonus:integer;out newFame,newLevel,newTotalLevel:integer);
 var
  fame:array[1..5] of integer;
  curLevel,totalFame:integer;
 begin
  fame[1]:=customFame;
  fame[2]:=classicFame;
  fame[3]:=draftFame;
  case dueltype of
   dtCustom:curLevel:=customLevel;
   dtClassic:curLevel:=classicLevel;
   dtDraft:curLevel:=draftLevel;
   else curLevel:=1;
  end;
  newFame:=Sat(fame[ord(duelType)]+fameBonus,0,999999);
  fame[ord(duelType)]:=newFame;
  newLevel:=Max2(curLevel,CalcLevel(newFame));
  totalFame:=CalcPlayerFame(fame[2],fame[1],fame[3]);
  newTotalLevel:=CalcLevel(totalFame);
 end;

procedure TUser.MissionsFromStr(st:AnsiString);
 var
  sa:StringArr;
  i:integer;
 begin
  sa:=split(',',st);
  fillchar(missions,sizeof(missions),0);
  for i:=0 to high(sa) do
   if sa[i]='+' then missions[i+1]:=-99
    else missions[i+1]:=StrToIntDef(sa[i],0);
 end;

function TUser.MissionsToStr:AnsiString;
 var
  i,max:integer;
  st:AnsiString;
 begin
  max:=1;
  for i:=2 to high(missions) do
   if missions[i]<>0 then max:=i;
  result:='';
  for i:=1 to max do begin
   if missions[i]<0 then st:='+'
    else st:=IntToStr(missions[i]);
   if i>1 then result:=result+',';
   result:=result+st;
  end;
 end;

function TUser.GetPlayerRec:TPlayerRec;
 begin
  result.name:=name;
  result.email:=email;
  result.guild:=guild;
  result.customFame:=customFame;
  result.customLevel:=customLevel;
  result.classicFame:=classicFame;
  result.classicLevel:=classicLevel;
  result.draftFame:=draftFame;
  result.draftLevel:=draftLevel;
  result.totalFame:=CalcPlayerFame(customFame,classicFame,draftFame);
  result.totalLevel:=level;
  result.status:=UpdateUserStatus;
 end;

function TUser.UpdateUserStatus(forceStatus:TPlayerStatus):TPlayerStatus;
 var
  i,g,m:integer;
  wasStatus:TPlayerStatus;
 begin
  EnterCriticalSection(gSect);
  try
  wasStatus:=status;
  if forceStatus=psDefault then begin
   forceStatus:=psOnline;
   if Now>lastCommand+5*MINUTE then forceStatus:=psAFK;
   if connected>0 then forceStatus:=psInCombat;
   if draftID>0 then forceStatus:=psInDraft;
   if campaignWins<15 then forceStatus:=psInCampaign;
  end;
  if status<>forceStatus then begin
   status:=forceStatus;
   if (playerID>0) and (playerID<=high(allPlayers)) then begin
    allPlayers[playerID].status:=status;
    allPlayers[playerID].lastVisit:=Now;
   end;
   if wasStatus=psAFK then LogMsg('User not AFK: '+name,logDebug);
   if status=psAFK then LogMsg('User AFK: '+name,logDebug);
   // Уведомить друзей и членов гильдии об изменении статуса (если только не бот)
   if botLevel=0 then begin
    for i:=1 to high(users) do
     if users[i]<>nil then
      if users[i].FindFriend(name)>=0 then
       PostUserMsg(i,FormatMessage([61,name,integer(status),GetActualLevel(dtNone),
         GetActualLevel(dtcustom),GetActualLevel(dtclassic),GetActualLevel(dtdraft)]));

    if (guild<>'') and ((wasstatus=psOffline) or (status=psOffline)) then begin
     g:=FindGuild(guild);
     if g>0 then begin
      m:=guilds[g].FindMember(name);
      if m>=0 then
       PostGuildMsg(g,'122~7~'+guilds[g].FormatMemberInfo(m),'Status');
     end;
    end;
   end;
  end;
  result:=status;

  if status<>wasStatus then begin
   statusChanges:=statusChanges+'~'+name+'~'+IntToStr(integer(status));
  end;
  finally
   LeaveCriticalSection(gSect);
  end;
 end;

procedure TUser.UpdatePlayerData;
 begin
  if PlayerID>high(allPlayers) then begin
   LogMsg('Resizing allPlayers to '+inttostr(playerID),logInfo);
   SetLength(allPlayers,playerID+1);
   allPlayers[playerID].name:=name;
   allPlayers[playerID].guild:='';
   allPlayers[playerID].email:=email;
  end;
  LogMsg('Updating allPlayers['+inttostr(playerID)+']',logDebug);
  if (playerID>0) and (playerID<=high(allPlayers)) then begin
   allPlayers[playerID].name:=name;
   allPlayers[playerID].guild:=guild;
   allPlayers[playerID].email:=email;
   allPlayers[playerID].customFame:=customFame;
   allPlayers[playerID].customLevel:=customLevel;
   allPlayers[playerID].classicFame:=classicFame;
   allPlayers[playerID].classicLevel:=classicLevel;
   allPlayers[playerID].draftFame:=draftFame;
   allPlayers[playerID].draftLevel:=draftLevel;
   allPlayers[playerID].totalFame:=CalcPlayerFame(customFame,classicFame,draftFame);
   allPlayers[playerID].totalLevel:=level;
   allPlayers[playerID].campaignWins:=campaignWins;
   allPlayers[playerID].lastVisit:=Now;   
   allPlayers[playerID].status:=status;
  end;
 end;

procedure TUser.ImportMarket(st:AnsiString);
 var
  i:integer;
  sa:StringArr;
 begin
  fillchar(marketCards,sizeof(marketCards),0);
  sa:=split(',',st);
  for i:=0 to high(sa) do begin
   marketCards[i+1]:=StrToIntDef(sa[i],0);
   if i=5 then break;
  end;
 end;

function TUser.CanGetRewardForClassic;
 var
  i,day:integer;
 begin
  result:=true;
  day:=trunc(now);
  i:=lastDuelsFirst;
  while i<>lastDuelsLast do begin
   if (lastDuels[i].winner=playerID) and
      (lastDuels[i].dueltype=2) and
      (trunc(lastDuels[i].date)=day) then begin
    result:=false;
    break;
   end;
   i:=(i+1) and $FFFF;
  end;
 end;

function TUser.CanPlayTrainingWithBot;
 var
  i,day,cnt:integer;
 begin
  result:=true;
//  if premium>Now then exit;
  if gems>=2 then exit;
  result:=false;
 end;

function TUser.CanPlayWithPlayer(plrID:integer;dt:TDuelType):boolean;
 var
  i,cnt,cnt2:integer;
 begin
  result:=true;
  cnt:=0; cnt2:=0;
  i:=lastDuelsLast;
  while i<>lastDuelsFirst do begin
   dec(i);
   if i<0 then i:=high(lastDuels);
   inc(cnt2);
   if cnt2>2000 then exit; // давно было дело, неактуально
   if (lastDuels[i].dueltype=byte(dt)) and
      ((lastDuels[i].winner=playerID) or (lastDuels[i].loser=playerID)) then begin
    if (lastDuels[i].winner=plrID) or (lastDuels[i].loser=plrID) then begin
     inc(cnt);
     if cnt=2 then begin
      result:=false;
      exit;
     end;
    end else
     exit;
   end;
  end;
 end;


function TUser.APlimit:integer; // максимальный AP с учётом перков
 var
  g:integer;
 begin
  result:=astralPower;
  if guild<>'' then begin
   g:=FindGuild(guild);
   if g<1 then exit;
   if guilds[g].bonuses[1]='1' then inc(result,10);
   if guilds[g].bonuses[13]='1' then inc(result,15);
   if guilds[g].bonuses[16]='1' then inc(result,25);
  end;
 end;

procedure TUser.LoadTips(st:AnsiString);
 var
  i:integer;
 begin
  for i:=1 to high(tipsShown) do begin
   tipsShown[i]:=0;
   if i<=length(st) then
    if st[i] in ['A'..'Z'] then
     tipsShown[i]:=byte(st[i])-64;
  end;
 end;

function TUser.TipsToStr:AnsiString;
 var
  i:integer;
 begin
  result:='';
  for i:=1 to high(tipsShown) do
   if tipsShown[i]>0 then
    result:=result+chr(64+min2(tipsShown[i],26))
   else
    result:=result+'-';
 end;

procedure TUser.SelectAndSendTip;
 var
  p,r:array[1..20] of single;
  i:integer;
  s,v:single;
 begin
  // 1. Отберём те подсказки, показ которых вообще возможен
  for i:=low(p) to high(p) do p[i]:=0;
  p[1]:=1;
  p[2]:=1;
  if level>1 then p[3]:=1;
  if level>1 then p[4]:=1;
  p[5]:=1;
  if level>3 then p[6]:=1;
  if level>1 then p[7]:=1;
  if level>2 then p[8]:=1;
  if level>6 then p[9]:=1;
  if (OwnedCardsCount>320) and (ownedCardsCount<400) then p[10]:=1;
  if guild<>'' then begin
   p[11]:=1;
   p[12]:=1;
   p[13]:=1;
   p[14]:=1;
  end;
  // Предыдущую подсказку желательно не показывать
  if lastTip>0 then p[lastTip]:=p[lastTip]/5;
  // Уменьшить шансы показа того, что уже много раз показывалось
  for i:=1 to high(tipsShown) do
   if (p[i]>0) and (tipsShown[i]>3) then
    p[i]:=p[i]*(2/(tipsShown[i]-1));

  // Нормализация шансов (чтобы их сумма была равна 1)
  s:=0;
  for i:=1 to high(p) do s:=s+p[i];
  for i:=1 to high(p) do begin
    p[i]:=p[i]/s;
    if i>1 then r[i]:=r[i-1]+p[i]
     else r[i]:=p[i];
  end;
  v:=random;
  s:=0;
  for i:=1 to high(p) do begin
   if r[i]>v then begin
    lastTip:=currentTip;
    currentTip:=i;
    break;
   end;
  end;
  PostUserMsg(userID,'34~'+inttostr(currentTip));
 end;

procedure TUser.UseTipAndSelectAnother;
 begin
  if currentTip in [1..20] then
   tipsShown[currentTip]:=min2(tipsShown[currentTip]+1,25);

  AddTask(0,0,['UPDATEPLAYER',playerID,'tips="'+TipsToStr+'"']);
  SelectAndSendTip;
 end;

function TUser.MaxCardInstances:integer;
 begin
  result:=3;
  if getUserTitle>=titleArchmage then result:=6;
 end;

function TUser.StartLifeBoost:integer;
 var
  g:integer;
 begin
  result:=0;
  if getUserTitle>=titleMagister then result:=2;
 end;

{ TGame }

procedure TGame.Clear;
begin
 user1:=0; user2:=0;
 gameStarted:=0;
 turnStarted:=0;
 fillchar(duelsave,sizeof(duelsave),0);
 gamelog:='';
end;

procedure TGame.SetTurnTo(userID: integer);
 var
  newturn,time:integer;
 begin
  if userID=user1 then newturn:=1;
  if userID=user2 then newturn:=2;
  if newturn<>turn then begin
   if turn>0 then begin
    time:=round((Now-turnStarted)*86400);
    if turn=1 then begin
     inc(time1,time);
     inc(users[user1].thinktime,time);
    end;
    if turn=2 then begin
     inc(time2,time);
     inc(users[user2].thinktime,time);
    end;
   end;
   inc(turns);
   turn:=newTurn;
   turnStarted:=Now;
   timeout_flag:=false;
  end;
 end;

function TGame.CalcTurnTimeout;
var
 u,dur:integer;
begin
  if withBot and (gametype<>dtDraft) and (gameClass<>dcCaravan) then result:=Now+30*MINUTE
   else begin
    dur:=60;
    if turns in [0..1] then dur:=40; // Первый ход - на 20 сек короче
    if turns in [2..3] then dur:=50; // Второй ход - на 10 сек короче
    u:=0;
    if (turn=1) and (user1>0) then u:=user1;
    if (turn=2) and (user2>0) then u:=user2;
    if (u>0) and (users[u].timeoutWarning) then begin
     dur:=30;
     users[u].timeoutWarning:=false;
     LogMsg('Short turn timeout for slow user '+users[u].name,logDebug);
    end;
    result:=Now+(dur+15)*SECOND;
   end;
end;

procedure TGame.SaveInitialState; // Сохранить начальное состояние дуэли в replayData
var
 i,v:integer;
 plr:TReplayPlayerInfo;
 cards:tshortcardlist;
 procedure InitPlrData(p:integer);
  begin
   with duelsave.SaveDuel.players[p] do begin
    plr.life:=life;
    plr.spellpower:=spellpower;
    plr.mana:=mana;
    plr.numdeckcards:=numdeckcards;
    plr.numhandcards:=numHandCards;
    move(handCards,plr.handcards,sizeof(plr.handcards));
   end;
   with duelSave.SavePlayersInfo[p] do begin
    plr.name:=Name;
    plr.level:=level;
    plr.faceNum:=FaceNum;
   end;
  end;
begin
 try
 SetLength(replayData,0);
 AppendBytes(cnsts.version,4);
 AppendBytes(duelSave.SaveDuel.curplayer,1);
 for i:=1 to 2 do begin
  v:=sizeof(plr);
  InitPlrData(i);
  AppendBytes(v,1);
  AppendBytes(plr,v);
  with duelSave.SavePlayersInfo[i].Deck do begin
   v:=sizeof(cards);
   AppendBytes(v,1);
   AppendBytes(cards,sizeOf(cards));
  end;
 end;
 except
  on e:Exception do LogMsg('Error in SaveInitialState: '+ExceptionMsg(e),logError);
 end;
end;

procedure TGame.SaveTurnData(buf:array of integer);
var
 v:byte;
 i:integer;
begin
 try
 v:=length(buf);
 AppendBytes(v,1);
 v:=$FF;
 for i:=1 to high(buf) do begin
  if buf[i] and $FFFFFF80=0 then
   AppendBytes(buf[i],1)
  else begin
   AppendBytes(v,1);
   AppendBytes(buf[i],4);
  end;
 end;
 except
  on e:Exception do LogMsg('Error in SaveTurnData: '+ExceptionMsg(e),logError);
 end;
end;

procedure TGame.AppendBytes(var bytes;count:byte);
var
 i,n:integer;
 pb:PByte;
begin
 n:=length(replayData);
 SetLength(replayData,n+count);
 pb:=@bytes;
 for i:=n to n+count-1 do begin
  replayData[i]:=pb^;
  inc(pb);
 end;
end;

// Вообще это дело вызывается из gSect, так что может вызывать некоторые задержки
// Ктобы это было не смертельно, функция не должна выполняться дольше 0.1 сек
function TGame.SaveReplay:integer;
var
 f:file;
 id,bundle,entry:integer;
 fname:AnsiString;
 fpos:integer;
 rec:array[0..1] of integer;
begin
 try
  lockReplays.Enter;
  try
   if FileExists('Replays\lastid') then
    ReadFile('Replays\lastid',@id,0,4)
   else
    id:=0;
   inc(id);
   result:=id;
   bundle:=id div 1000;
   entry:=id mod 1000;
   fname:='Replays\b'+inttostr(bundle);
   if FileExists(fname) then
    fPos:=GetFileSize(fname)
   else
    fPos:=8000;
   rec[0]:=fPos;
   rec[1]:=length(replayData);
   WriteFile(fname,@rec,entry*8,8);
   WriteFile(fname,@replayData[0],fPos,length(replayData));
   // Save new ID
   WriteFile('Replays\lastid',@id,0,4);
  finally
   lockReplays.Leave;
  end;
 except
  on e:exception do LogMsg('Error saving replay: '+ExceptionMsg(e),logError);
 end;
end;

{ TDraft }

function TDraft.NoPlayersAlive: boolean;
var
 user:integer;
begin
 result:=true;
 for user in players do
  if IsValidUserID(user) then
   if users[user].botLevel=0 then result:=false;
end;

function TDraft.PlayerMadeDeck(userID: integer; cards: AnsiString):integer;
var
 plr,time:integer;
 deck:tshortcardlist;
begin
  result:=0;
  for plr:=1 to 4 do
   if players[plr]=userID then begin
     StrToDeck(cards,deck);
     //LogMsg('Player deck: '+cards+' -> '+DeckToText(deck),logInfo);
     result:=draftInfo.players[plr].DeckMade(deck);
     if result=0 then begin
      time:=system.round(86400*(Now-timeX));
      LogMsg('Deck for '+users[userid].name+' accepted (time '+inttostr(time)+'): '+DeckToText(deck),logInfo);
      if DeckToText(deck)='' then LogMsg('WARN! EMPTY DECK!',logWarn);
      inc(draftInfo.Players[plr].time,time);
      draftInfo.Players[plr].played:=Now+3*SECOND;
     end;
     exit;
   end;
  LogMsg('Player not in draft: '+users[userid].name,logWarn);
end;

procedure TDraft.PlayerTookCard(userID, card: integer);
var
 plr:integer;
begin
  for plr:=1 to 4 do
   if players[plr]=userID then begin
     inc(draftInfo.Players[plr].time,random(2)+system.round(86400*(Now-timeX)));
     if not draftInfo.Players[plr].TakeCard(card) then begin
      LogMsg('Player '+users[userid].name+' took unavailable card: '+inttostr(card),logWarn);
      card:=draftInfo.players[plr].availableCards[1];
      draftInfo.Players[plr].TakeCard(card);
     end;
     exit;
   end;
  LogMsg('Player not in draft: '+users[userid].name,logWarn);
end;

function TDraft.ReadyForNextCard: boolean;
var
 i:integer;
begin
 result:=false;
 if stage>1 then exit;
 result:=true;
 if stage=0 then exit;
 for i:=1 to 4 do
  if (draftInfo.Players[i].control=0) and
     (not draftInfo.Players[i].cardTaken) then result:=false;
end;

function TDraft.ReadyForNextRound:boolean;
var
 i,j:integer;
begin
 try
 result:=false;
 for i:=1 to 4 do begin
  if not IsValidUserID(players[i],true) then begin
   j:=players[i];
   players[i]:=0;
   ASSERT(false,'Invalid userID - '+inttostr(players[j]));
  end;
  if users[players[i]].connected>0 then exit; // Игрок в бою
 end;

 if stage=2 then begin // Идёт составление колод
  result:=true;
  for i:=1 to 4 do
   if (draftInfo.Players[i].control=0) and
     ((not draftInfo.Players[i].deckBuilt) or
      (Now<draftInfo.Players[i].played)) then result:=false;
 end;
 if stage=3 then begin // Турнир уже идёт
  result:=true;
  for i:=1 to 4 do
   if (draftInfo.Players[i].played=0) or
      (draftInfo.Players[i].played>Now) then begin
    if random(100)=55 then
     LogMsg('Draft: player %s not ready %s',[draftInfo.Players[i].Name,HowLong(draftInfo.Players[i].played)],logDebug);
    result:=false;
   end;
 end;
 except
  on e:Exception do LogMsg('Error in ReadyForNextRound: '+ExceptionMsg(e),logWarn);
 end;
end;

function TDraft.GetDraftPlayer(userID:integer):PDraftPlayer;
var
 i:integer;
begin
 result:=nil;
 for i:=1 to 4 do
  if players[i]=userID then begin
   result:=@draftInfo.players[i];
   exit;
  end;
 raise EWarning.Create('User '+inttostr(userID)+' not found in draft');
end;

function TGameDeck.IsValidForUser(const user:TUser):AnsiString; // проверяет допустимость колоды для юзера
var
 i,g,card,count:integer;
 owned:TCardSet;
begin
 // Проверить кол-во карт
 count:=0;
 for i:=1 to high(cards) do
  if cards[i]<>0 then inc(count);
 if count<25 then begin
  result:='too few cards (25 required)';
  exit;
 end;
 // Проверить стоимость колоды
 result:='deck cost is too high';
 cost:=CalculateDeckCost(cards,CardSetToStr(user.ownCards));
 if cost>user.APlimit then exit;
 result:='some cards are not available';
 // Проверить доступность карт
 for i:=1 to high(owned) do
  owned[i]:=abs(user.ownCards[i]);
 // Добавим гильдейские карты
 if user.guild<>'' then begin
  g:=FindGuild(user.guild);
  if g>0 then
   with guilds[g] do
    for i:=1 to 20 do
     if cards[i]='1' then
      owned[guildcards[i]]:=3;
 end;
 // Проверим доступность карт колоды
 for i:=1 to high(cards) do begin
  card:=cards[i];
  if card>0 then begin
   if owned[card]<=0 then begin
    result:='"%1" is not available.%%'+cardinfo[card].name;
    exit;
   end;
   dec(owned[card]); 
  end;
 end;
 result:='';
end;

 function CardSetToStr(cardSet:TCardSet):AnsiString;
  var
   i,max:integer;
  begin
   SetLength(result,numCards);
   max:=1;
   for i:=1 to numCards do begin
    if cardSet[i]>=0 then
     result[i]:=AnsiChar($30+min2(cardSet[i],6))
    else
     result[i]:='*';
    if cardSet[i]<>0 then max:=i;
   end;
   SetLength(result,max);
  end;

 procedure StrToCardSet(st:AnsiString;var cardSet:TCardSet);
  var
   i:integer;
  begin
   fillchar(cardSet,sizeof(cardSet),0);
   if length(st)>high(cardSet) then SetLength(st,high(cardSet));
   for i:=1 to length(st) do begin
    if st[i] in ['0'..'9'] then cardSet[i]:=min2(StrToInt(st[i]),6);
    if st[i]='*' then cardSet[i]:=-3;
   end;
  end;

 procedure AddLocalDuelRec(date:TDateTime;winner,loser,dueltype,scenario,turns,firstPlr:integer);
  begin
   if (scenario<0) or (scenario>100) then scenario:=0;
   lastDuels[lastDuelsLast].winner:=winner;
   lastDuels[lastDuelsLast].loser:=loser;
   lastDuels[lastDuelsLast].dueltype:=dueltype;
   lastDuels[lastDuelsLast].scenario:=scenario;
   lastDuels[lastDuelsLast].turns:=turns;
   lastDuels[lastDuelsLast].firstplr:=firstplr;
   lastDuels[lastDuelsLast].date:=date;
   lastDuelsLast:=(lastDuelsLast+1) and $FFFF;
   if lastDuelsFirst=lastDuelsLast then
    lastDuelsFirst:=(lastDuelsFirst+1) and $FFFF;
  end;

 function ParseUserFlags(st:AnsiString):cardinal;
  var
   ch:AnsiChar;
  begin
   result:=0;
   for ch in st do
    case ch of
     'A':result:=result or ufAdmin;
     'U':result:=result or ufUnverified;
     'S':result:=result or ufSilent;
     'M':result:=result or ufModerator;
     'B':result:=result or ufBanned;
     'b':result:=result or ufBot;
     'd':result:=result or ufCanMakeDecks;
     'r':result:=result or ufCanReplaceCards;
     'p':result:=result or ufHasRitualOfPower;
     'm':result:=result or ufHasManaStorm;
     'g':result:=result or ufAdvGuildExp;
     'n':result:=result or ufNotPlayed;
     'h':result:=result or ufHardMode;
     '%':result:=result or ufBonus50;
     'I':result:=result or ufInvalidEmail;
     'G':result:=result or ufGoodnight;
    end;
  end;

 function MakeUserFlags(flags:cardinal):AnsiString;
  begin
   result:='';
   if flags and ufAdmin>0 then result:=result+'A';
   if flags and ufUnverified>0 then result:=result+'U';
   if flags and ufSilent>0 then result:=result+'S';
   if flags and ufModerator>0 then result:=result+'M';
   if flags and ufBanned>0 then result:=result+'B';
   if flags and ufBot>0 then result:=result+'#';
   if flags and ufCanMakeDecks>0 then result:=result+'d';
   if flags and ufCanReplaceCards>0 then result:=result+'r';
   if flags and ufHasRitualOfPower>0 then result:=result+'p';
   if flags and ufHasManaStorm>0 then result:=result+'m';
   if flags and ufAdvGuildExp>0 then result:=result+'g';
   if flags and ufNotPlayed>0 then result:=result+'n';
   if flags and ufHardMode>0 then result:=result+'h';
   if flags and ufBonus50>0 then result:=result+'%';
   if flags and ufInvalidEmail>0 then result:=result+'I';
   if flags and ufGoodnight>0 then result:=result+'G';
  end;

 function GetUserByName(name:AnsiString):integer;
  var
   i:integer;
  begin
   result:=0;
   for i:=1 to High(users) do
    if (users[i]<>nil) and (users[i].name=name) then begin
     result:=i;
     exit;
    end;
  end;

 function FindPlayerID(name:AnsiString):integer;
  var
   i:integer;
  begin
   // В будущем переделать на хэш!!!
   result:=0;
   name:=lowercase(name);
   gSect.Enter;
   try
   for i:=1 to high(allPlayers) do
    if lowercase(allPlayers[i].name)=name then result:=i;
   finally
    gSect.Leave;
   end;
  end;

 type
  TRankingFunc=function(playerID:integer):int64; 

 function CustomRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=int64(customFame) shl 40+int64(customWins) shl 24+(65000-customLoses) shl 8+playerID and 255;
  end;
 function ClassicRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=int64(classicFame) shl 40+int64(classicWins) shl 24+(65000-classicLoses) shl 8+playerID and 255;
  end;
 function DraftRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=int64(draftFame) shl 40+int64(draftWins) shl 24+(65000-draftLoses) shl 8+playerID and 255;
  end;
 function TotalRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=int64(totalFame) shl 40+
      int64(classicWins+customWins+DraftWins) shl 24+
      (65000-classicLoses-customLoses-draftLoses) shl 8+playerID and 255;
  end;

 procedure BuildRanking(mode:TDuelType);
  var
   i,n,count:integer;
   ranking:IntArray;
   fl:boolean;
  procedure QuickSort(a,b:integer;func:TRankingFunc);
   var
    lo,hi,v,mid:integer;
    o:integer;
    midVal:int64;
   begin
    lo:=a; hi:=b;
    mid:=(a+b) div 2;
    midVal:=func(ranking[mid]);
    repeat
     while midVal<func(ranking[lo]) do inc(lo);
     while midVal>func(ranking[hi]) do dec(hi);
     if lo<=hi then begin
      Swap(ranking[lo],ranking[hi]);
      inc(lo);
      dec(hi);
     end;
    until lo>hi;
    if hi>a then QuickSort(a,hi,func);
    if lo<b then QuickSort(lo,b,func);
   end;
  begin
   try
   count:=0;
   for i:=1 to high(allPlayers) do
    case mode of
     dtNone:if allPlayers[i].totalFame>0 then inc(count);
     dtCustom:if allPlayers[i].customFame>0 then inc(count);
     dtClassic:if allPlayers[i].classicFame>0 then inc(count);
     dtDraft:if allPlayers[i].draftFame>0 then inc(count);
    end;
   SetLength(ranking,count+1);
   n:=0;
   for i:=1 to high(allPlayers) do begin
    fl:=false;
    case mode of
     dtNone:if allPlayers[i].totalFame>0 then fl:=true;
     dtCustom:if allPlayers[i].customFame>0 then fl:=true;
     dtClassic:if allPlayers[i].classicFame>0 then fl:=true;
     dtDraft:if allPlayers[i].draftFame>0 then fl:=true;
    end;
    if fl then begin
     inc(n); ranking[n]:=i;
    end;
   end;
   case mode of
    dtCustom:begin
     QuickSort(1,count,CustomRate);
     customRanking:=ranking;
     for i:=1 to high(allPlayers) do
      allPlayers[i].customPlace:=0;
     for i:=1 to high(ranking) do
      allPlayers[ranking[i]].customPlace:=i; 
    end;
    dtClassic:begin
     QuickSort(1,count,ClassicRate);
     classicRanking:=ranking;
     for i:=1 to high(allPlayers) do
      allPlayers[i].classicPlace:=0;
     for i:=1 to high(ranking) do
      allPlayers[ranking[i]].classicPlace:=i;
    end;
    dtDraft:begin
     QuickSort(1,count,DraftRate);
     draftRanking:=ranking;
     for i:=1 to high(allPlayers) do
      allPlayers[i].draftPlace:=0;
     for i:=1 to high(ranking) do
      allPlayers[ranking[i]].draftPlace:=i; 
    end;
    dtNone:begin
     QuickSort(1,count,TotalRate);
     totalRanking:=ranking;
     for i:=1 to high(allPlayers) do
      allPlayers[i].place:=0;
     for i:=1 to high(ranking) do
      allPlayers[ranking[i]].place:=i;
    end;
   end;
   except
    on e:exception do LogMsg('Error in BuildRanking, mode '+inttostr(integer(mode)),logWarn);
   end;
  end;

 // Обновляет позицию игрока в рейтинге указанного типа
 procedure UpdatePlayerRanking(mode:TDuelType;playerID:integer);
  type
   PIntArray=^IntArray;
  var
   i,place:integer;
   rate:int64;
   ranking:PIntArray;
   func:TRankingFunc;
  procedure UpdatePlayerPlace(place:integer);
   begin
    case mode of
     dtNone:allPlayers[ranking^[place]].place:=place;
     dtCustom:allPlayers[ranking^[place]].customplace:=place;
     dtClassic:allPlayers[ranking^[place]].classicplace:=place;
     dtDraft:allPlayers[ranking^[place]].draftplace:=place;
    end;
   end;
  begin
   try
   if (playerID<=0) or (playerID>high(allPlayers)) then exit;
   place:=0;
   case mode of
    dtCustom:begin
     ranking:=@customRanking;
     func:=CustomRate;
     place:=allPlayers[playerID].customPlace;
    end;
    dtClassic:begin
     ranking:=@classicRanking;
     func:=ClassicRate;
     place:=allPlayers[playerID].classicPlace;
    end;
    dtDraft:begin
     ranking:=@draftRanking;
     func:=DraftRate;
     place:=allPlayers[playerID].draftPlace;
    end;
    dtNone:begin
     ranking:=@totalRanking;
     func:=TotalRate;
     place:=allPlayers[playerID].place;
    end;
   end;

   if ranking^[place]<>playerID then begin
    place:=0;
    // Find player in ranking (1 pass)
    for i:=1 to high(ranking^) do
     if ranking^[i]=playerID then begin
      place:=i; break;
     end;
   end;

   rate:=func(playerID);
   if (place=0) and (rate>=$10000000000) then begin // not in ranking? Add!
    place:=length(ranking^);
    SetLength(ranking^,place+1);
    ranking^[place]:=playerID;
   end;
   // go up?
   while (place>1) and (rate>func(ranking^[place-1])) do begin
    Swap(ranking^[place],ranking^[place-1]);
    UpdatePlayerPlace(place); dec(place);
   end;
   // go down?
   while (place<high(ranking^)) and (rate>func(ranking^[place+1])) do begin
    Swap(ranking^[place],ranking^[place+1]);
    UpdatePlayerPlace(place); inc(place);
   end;
   UpdatePlayerPlace(place); 
   // Remove from ranking?
   if (place=high(ranking^)) and (rate<$10000000000) then SetLength(ranking^,place);
   except
    on e:exception do LogMsg('Error in UpdatePlayerRank: '+inttostr(playerID),logWarn);
   end;
  end;

procedure AddCardsFromList(cardList:AnsiString;var cards:TCardSet);
 var
  sa:StringArr;
  i,j,k,c:integer;
begin
  sa:=Split(',',cardList);
  for i:=0 to high(sa) do begin
   k:=pos('x',sa[i]);
   c:=1;
   if k>0 then begin
    c:=StrToIntDef(copy(sa[i],k+1,1),1);
    SetLength(sa[i],k-1);
   end;
   j:=StrToIntDef(sa[i],0);
   if j>0 then inc(cards[j],c);
  end;
end;

function BuildCardSetForSpeciality(speciality:integer):TCardSet;
 begin
  fillchar(result,sizeof(result),0);
  AddCardsFromList(InitialDecks[speciality],result);
  AddCardsFromList(InitialCards[speciality],result);
 end;

procedure BuildDeckForSpeciality(speciality:integer);
 var
  sa:StringArr;
  i,j,n,k,c:integer;
  deck:array[1..50] of smallint;
 begin
  sa:=Split(',',InitialDecks[speciality]);
  n:=0;
  fillchar(deck,sizeof(deck),0);
  for i:=0 to high(sa) do begin
   c:=1;
   k:=pos('x',sa[i]);
   if k>0 then begin
    c:=StrToIntDef(copy(sa[i],k+1,1),1);
    SetLength(sa[i],k-1);
   end;
   j:=StrToIntDef(sa[i],0);
   if j<>0 then
    while c>0 do begin
     inc(n);
     deck[n]:=j;
     dec(c);
    end;
  end;
  startDecksCost[speciality]:=CalculateDeckCost(deck);
  startDecks[speciality]:=DeckToStr(deck);
 end;

procedure InitConsts;
 var
  i,j,n:integer;
  deck:AnsiString;
 begin
  try
  cnsts.SaveConsts('Inf\gd.spe'); // save gd.spe
  gd_spe:=LoadFileAsString('Inf\gd.spe');
  for i:=1 to 2 do begin
   startCardSets[i]:=BuildCardSetForSpeciality(i);
   BuildDeckForSpeciality(i);

   deck:='';
   for n:=3 downto 1 do
    for j:=low(startCardSets[i]) to high(startCardSets[i]) do
     if startCardSets[i][j]=n then begin
      if deck<>'' then deck:=deck+#13#10;
      deck:=deck+inttostr(n)+' x '+cardInfo[j].name;
     end;
   LogMessage('Starting cards for speciality '+inttostr(1)+#13#10+deck);
  end;
  except
   on e:Exception do LogMsg('Error in InitConsts: '+ExceptionMsg(e));
  end;
 end;

procedure DumpServerData;
 var
  st:AnsiString;
  i:integer;
 begin
  try
   st:='USERS:'#13#10;
   for i:=1 to high(users) do
    if users[i]<>nil then st:=st+users[i].GetUserFullDump;
   st:=st+#13#10'GUILDS:'#13#10;
   for i:=1 to high(guilds) do
    if guilds[i].name<>'' then st:=st+guilds[i].GetFullDump;
   SaveFile('datadump.txt',@st[1],length(st));
  except
   on e:Exception do LogMsg('Error in dumping server data: '+ExceptionMsg(e));
  end;
 end;

 procedure TGuild.LoadFromDB(db:TMySQLdatabase;condition:AnsiString);
  var
   sa,sb,sc:AStringArr;
   i,j,k,guildID,count,col,loglines:integer;
   st:AnsiString;
   mem:TGuildMember;
  begin
   LogMsg('Loading guild from DB: '+condition,logDebug);
   sa:=db.Query('SELECT id,name,size,exp,level,treasures,bonuses,cards,daily,motto,carLaunch1,carLaunch2 FROM guilds WHERE '+condition);
   if db.rowCount<>1 then raise EWarning.Create('No guild found in DB');
   guildID:=StrToInt(sa[0]);
   sb:=db.Query('SELECT playerid,rank,powers,rewards,treasures,exp,r1,r2,r3 FROM guildmembers WHERE guild='+inttostr(guildID));
   count:=db.rowCount;
   col:=db.colCount;
   sc:=db.Query('SELECT date,msg FROM guildlog WHERE guild='+inttostr(guildID)+' ORDER BY id');
   logLines:=db.rowCount;
   gSect.Enter;
   try
    id:=guildID;
    name:=sa[1];
    size:=StrToInt(sa[2]);
    exp:=StrToInt(sa[3]);
    level:=StrToInt(sa[4]);
    treasures:=StrToInt(sa[5]);
    bonuses:=sa[6];
    cards:=sa[7];
    daily:=StrToInt(sa[8]);
    motto:=sa[9];
    caravans[1].launched:=GetDateFromStr(sa[10]);
    caravans[2].launched:=GetDateFromStr(sa[11]);
    SetLength(members,count);
    for i:=0 to count-1 do begin
     members[i].playerID:=StrToIntDef(sb[i*col],0);
     if members[i].playerID<=high(allPlayers) then
      members[i].name:=AllPlayers[members[i].playerID].name;
     members[i].rank:=StrToIntDef(sb[i*col+1],0);
     members[i].powers:=CallToPowers[StrToInt(sb[i*col+2])];
     members[i].rewards:=StrToIntDef(sb[i*col+3],0);
     members[i].treasures:=StrToIntDef(sb[i*col+4],0);
     members[i].exp:=StrToIntDef(sb[i*col+5],0);
     members[i].rew[1]:=StrToIntDef(sb[i*col+6],0);
     members[i].rew[2]:=StrToIntDef(sb[i*col+7],0);
     members[i].rew[3]:=StrToIntDef(sb[i*col+8],0);
    end;
    // Здесь же сортировка членов гильдии по порядку вступления
    SetLength(log,logLines);
    for i:=0 to logLines-1 do begin
     log[i].date:=GetDateFromStr(sc[i*2]);
     st:=sc[i*2+1];
     log[i].text:=st;
     if pos('%1 joined guild',st)=1 then begin
      j:=pos('%%',st);
      delete(st,1,j+1);
      j:=pos('`',st);
      if j=0 then j:=pos('%%',st);
      SetLength(st,j-1);
      if st='' then continue;
      for j:=0 to count-2 do
       if members[j].name=st then begin
        mem:=members[j];
        for k:=j to count-2 do
         members[k]:=members[k+1];
        members[count-1]:=mem;
        break;
       end;
     end;
    end;
   finally
    gSect.Leave;
   end;
  end;

 procedure TGuild.AddLogMessage(msg:AnsiString);
  var
   n:integer;
   q:AnsiString;
  begin
   gSect.Enter;
   try
    n:=length(log);
    SetLength(log,n+1);
    log[n].date:=Now;
    log[n].text:=msg;
   finally
    gSect.Leave;
   end;
  end;

 function TGuild.FindMember(plrname:AnsiString;raiseIfNotFound:boolean=false):integer;
  var
   i:integer;
  begin
   result:=-1;
   for i:=0 to high(members) do
    if members[i].name=plrname then begin
     result:=i; exit;
    end;
   if raiseIfNotFound then
    raise EWarning.Create('Guild member '+plrname+' not found in guild "'+name+'"');
  end;

 function TGuild.FindMemberByID(plrID:integer;raiseIfNotFound:boolean=false):integer;
  var
   i:integer;
  begin
    result:=-1;
   for i:=0 to high(members) do
    if members[i].playerID=plrID then begin
     result:=i; exit;
    end;
   if raiseIfNotFound then
    raise EWarning.Create('Guild member '+IntToStr(plrID)+' not found in guild "'+name+'"');
  end;


 function TGuild.FormatMemberInfo(m:integer):AnsiString;
  var
   lvl:array[0..3] of byte;
   hero:byte;
   status:TDateTime;
  begin
   hero:=0;
   status:=0;
   with members[m] do begin
    if (playerID>0) and
       (playerID<=High(allPlayers)) and
       (allPlayers[playerID].name=name) then begin
     lvl[0]:=CalcLevel(allPlayers[playerID].totalFame);
     lvl[1]:=CalcLevel(allPlayers[playerID].customFame);
     lvl[2]:=CalcLevel(allPlayers[playerID].classicFame);
     lvl[3]:=CalcLevel(allPlayers[playerID].draftFame);
     if allPlayers[playerID].campaignWins>=20 then hero:=1;
     if allPlayers[playerID].status=psOffline then
      status:=allPlayers[playerID].lastVisit;
    end else
     fillchar(lvl,sizeof(lvl),0);
   end;
   result:=FormatMessage([members[m].name,lvl[0],lvl[1],lvl[2],lvl[3],
     members[m].treasures,members[m].exp,members[m].rank,hero,status]);
  end;

 function TCaravan.FormatInfo:AnsiString;
  var
   i,v:integer;
  begin
   result:='';
   for i:=1 to 8 do begin
    v:=battles[i];
    if (v=1) and (defenders[i]='') and (attackers[i]='') then v:=0;
    result:=result+Format('~%d~%s~%s',[v,defenders[i],attackers[i]]);
   end;
  end;

 function TCaravan.FormatLog:AnsiString;
  var
   i:integer;
  begin
   result:='';
   for i:=1 to 8 do begin
    result:=result+Format('%d:[%d %d %s %s/%s];',[i,battles[i],propCount[i],HowLong(needBattleIn[i]),defenders[i],attackers[i]]);
   end;
  end;

 procedure TCaravan.RequestActiveSlotIn(time:integer); // запрос на активацию слота через time секунд
  var
   i:integer;
  begin
   for i:=1 to 8 do
    if (battles[i]=0) and (needBattleIn[i]=0) then begin
     LogMsg('Request slot activation %d in %d',[i,time],logDebug);
     needBattleIn[i]:=Now+time*SECOND;
     exit;
    end;
  end;

 procedure TCaravan.ResetSlot(slot:integer);
  begin
   battles[slot]:=0;
   needBattleIn[slot]:=0;
   attackers[slot]:='';
   defenders[slot]:='';
   propCount[slot]:=0;
  end;

 function TCaravan.FormatBattleUpdate(i:integer):AnsiString;
  begin
   result:=FormatMessage([122,10,i,battles[i],defenders[i],attackers[i]]);
  end;  

 function TGuild.NumCards:integer;
  var
   i:integer;
  begin
   result:=0;
   for i:=1 to high(cards) do
    if cards[i]='1' then inc(result);
  end;

 function TGuild.NumBonuses:integer;
  var
   i:integer;
  begin
   result:=0;
   for i:=1 to high(bonuses) do
    if bonuses[i]='1' then inc(result);
  end;

 function TGuild.ExpBonus:single;
  var
   i,l,plr,lvl:integer;
  begin
   result:=1;
   // по 5% за каждого героя в составе
   for i:=0 to high(members) do begin
    plr:=members[i].playerID;
    if plr<=high(allPlayers) then
     if allPlayers[plr].campaignWins>=20 then
      result:=result+0.05;
   end;

   // по 1% за каждые 100 богатства
   if bonuses[8]='1' then
    result:=result+0.01*(treasures div 100);

   // по 1% за каждый уровень сильнейшего игрока
   if bonuses[12]='1' then begin
    l:=1;
    for i:=0 to high(members) do begin
     plr:=members[i].playerID;
     lvl:=1;
     if plr<=high(allPlayers) then
      lvl:=allPlayers[plr].totalLevel
     else
      LogMsg('Player ID='+inttostr(plr)+' not found in AllPlayers!',logImportant);
     l:=max2(l,lvl);
    end;
    result:=result+0.01*l;
   end;   
  end;

 function TGuildMember.FormatCallToPowers:AnsiString;
  begin
   ASSERT(powers[1] in ['1'..'4']);
   ASSERT(powers[2] in ['1'..'4']);
   result:=FormatMessage([powers[1],powers[2],rewards]);
  end;

 function TGuild.GetFullDump:AnsiString;
  var
   i,j:integer;
  begin
   result:=Format('id=%d, name="%s", size=%d, level=%d, exp=%d, tr=%d, daily=%d',[id,name,size,level,exp,treasures,daily]);
   result:=result+Format(#13#10' bonuses=%s, cards=%s',[bonuses,cards]);
   for i:=0 to high(members) do
    result:=result+Format(#13#10' - %s (%d) %d [%s] %d %d %d %d/%d/%d',[members[i].name,members[i].playerID,members[i].rank,
     members[i].powers,members[i].rewards,members[i].treasures,members[i].exp,
     members[i].rew[1],members[i].rew[2],members[i].rew[3]]);
   for i:=1 to 2 do
    if caravans[i].running then begin
     result:=result+Format(#13#10'Caravan type %d launched at %s',[i,FormatDateTime('hh:nn:ss',caravans[i].launched)]);
     with caravans[i] do begin
      for j:=1 to 8 do
       result:=result+Format(#13#10'  %d) %d %d %s att=%s def=%s',
         [j,battles[j],propCount[j],FormatDateTime('hh:nn:ss',needBattleIn[j]),attackers[j],defenders[j]]);
     end;
    end;
   result:=result+#13#10;
  end;

 function TGuild.NextLaunchTime(kind:integer):TDateTime; // Когда можно будет запустить караван в следующий раз
  begin
   result:=caravans[kind].launched;
   case kind of
    1:result:=result+70/24;
    2:result:=result+46/24;
   end;
   if result<Now then result:=Now;
  end;

 procedure TCaravan.Clear;
  var
   i:integer;
  begin
   running:=false;
   launched:=0;
   for i:=1 to 8 do begin
    battles[i]:=0;
    needBattleIn[i]:=0;
    propCount[i]:=0;
    attackers[i]:='';
    defenders[i]:='';
   end;
  end;


{var
 deck:tshortcardlist;
 cards:AnsiString;
 r:integer;
 plr:TDraftPlayer;}
initialization
 uCnt:=0;
 allPlayersHash.Init;
 caravanChallenged.Init;
 InitCritSect(lockReplays,'Replays');
end.
